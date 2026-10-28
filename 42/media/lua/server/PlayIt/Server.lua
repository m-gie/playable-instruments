-- Multiplayer relay: checks a musician's song once, sends it to everyone within RELAY_RANGE, catches up
-- players who walk in mid-song, and ends sessions whose musician is gone. No per-note traffic.

if not isServer() then return end -- clients run lua/server too in B42

require "PlayIt/Session"
require "PlayIt/Instruments"
require "PlayIt/Effects"
require "PlayIt/Herd"
require "PlayIt/Config"
require "PlayIt/Song"
require "PlayIt/Timeline"
require "PlayIt/Furniture"
require "PlayIt/Band"

local RELAY_RANGE = 80
local CATCH_UP_MS = 2000
local ORIGIN_SLACK_MS = 5000

local sessions = PlayIt.Session.new()
local bands = PlayIt.Band.new()
local ready = {} -- players waiting to play along who already pressed Play: { [id] = { perf, fullType } }
local nextCatchUp = 0

local function inRange(a, b)
    return math.abs(a:getZ() - b:getZ()) <= 1 and IsoUtils.DistanceTo(a:getX(), a:getY(), b:getX(), b:getY()) <= RELAY_RANGE
end

local function musicianOf(id)
    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p:getOnlineID() == id then return p end
    end
    return nil
end

-- origin: server ms of the part's timeline 0; each listener places it with its own clock offset
local function sendPlay(id, musician, perf, fullType, origin)
    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p ~= musician and not sessions:hasListener(id, p:getOnlineID()) and inRange(p, musician) then
            sessions:addListener(id, p:getOnlineID())
            sendServerCommand(p, "PlayIt", "play", { id = id, fullType = fullType, perf = perf, origin = origin })
        end
    end
end

local function sendToListeners(id, command, args)
    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if sessions:hasListener(id, p:getOnlineID()) then sendServerCommand(p, "PlayIt", command, args) end
    end
end

local function holds(player, fullType)
    local item = player:getPrimaryHandItem()
    return item ~= nil and item:getFullType() == fullType and PlayIt.Instruments.defs[fullType] ~= nil
end

-- furniture: the instrument is there, the musician is next to it (with a drumstick for drums) and nobody else
-- plays it. true, or false and the reason the client shows ("Gone", "TooFar", "NoSticks", "Busy")
local function mayPlayFurniture(player, fullType, place)
    if place == nil then return false, "Gone" end
    local ok, why = PlayIt.Furniture.check(fullType, place, PlayIt.Furniture.ctxFor(player))
    if not ok then return false, why end
    if sessions:busyAt(fullType, place, player:getOnlineID()) then return false, "Busy" end
    return true
end

local handlers = {}

local function send(player, command, args)
    if player then sendServerCommand(player, "PlayIt", command, args) end
end

-- a copy of a part played at bpm, with its song and timeline (members play at the performance's tempo)
local function atBpm(perf, bpm)
    local copy = {}
    for k, v in pairs(perf) do copy[k] = v end
    copy.bpm = bpm
    local song = PlayIt.Song.parse(copy.text, bpm)
    local timeline = PlayIt.Timeline.build(song, copy.seed, copy.segments)
    copy.length = timeline.length
    return copy, song, timeline
end

-- a session for the part with its timeline 0 at origin (server ms), relayed to the players in range
local function startPart(player, perf, fullType, song, timeline, origin)
    local id = player:getOnlineID()
    sessions:start(id, perf, origin)
    local s = sessions:get(id)
    s.fullType = fullType
    s.username = player:getUsername()
    s.song = song
    s.timeline = timeline
    s.moodFrom = math.max(perf.fromMs or 0, getTimestampMs() - origin)
    sendPlay(id, player, perf, fullType, origin)
end

local joinWaiter, sendWaiters -- defined below; go and joinWaiter call each other for waits on waiters

-- players who wait for a musician who just started come in at the next bar; the musician's list empties
local function releaseWaiters(id, now)
    local band = bands:of(id)
    if band then
        for _, waiterId in ipairs(bands:waitersOf(id)) do joinWaiter(waiterId, band, now) end
    end
    sendWaiters(id)
end

-- the part starts for its musician, who waited for the server: at origin, from fromMs, at the band's bpm
local function go(player, perf, fullType, song, timeline, origin, startAt)
    startPart(player, perf, fullType, song, timeline, origin)
    send(player, "go", { origin = origin, fromMs = perf.fromMs, bpm = perf.bpm, startAt = startAt })
    releaseWaiters(player:getOnlineID(), getTimestampMs())
end

-- nothing to join or start with: alone, a moment from now, from posMs in the part
local function goSolo(player, perf, fullType, posMs, now)
    local copy, song, timeline = atBpm(perf, perf.bpm)
    copy.fromMs = posMs > 0 and posMs or nil
    local origin = now + PlayIt.Band.JOIN_MARGIN_MS - posMs
    bands:startSolo(player:getOnlineID(), timeline, copy.bpm, origin)
    go(player, copy, fullType, song, timeline, origin)
end

local function nameOf(player) return player:getDisplayName() end

-- every member learns who plays in their performance
local function sendRoster(band)
    if band == nil then return end
    local names, players = {}, {}
    for _, id in ipairs(bands:members(band)) do
        local p = musicianOf(id)
        if p then
            names[#names + 1] = nameOf(p)
            players[#players + 1] = p
        end
    end
    for _, p in ipairs(players) do send(p, "band", { members = names, bpm = band.bpm }) end
end

-- the musician learns who waits for them to start (their client then waits for the count-in)
sendWaiters = function(targetId)
    local names = {}
    for _, id in ipairs(bands:waitersOf(targetId)) do
        local p = musicianOf(id)
        if p then names[#names + 1] = nameOf(p) end
    end
    send(musicianOf(targetId), "waiters", { names = names })
end

local function endWait(id, reason)
    local target = bands.waits[id]
    bands:unwait(id)
    ready[id] = nil
    if reason then send(musicianOf(id), "alongEnded", { reason = reason }) end
    if target then sendWaiters(target) end
end

-- a waiter whose musician started without them comes in at the next bar; alone if their part is over there
joinWaiter = function(waiterId, band, now)
    local w, player = ready[waiterId], musicianOf(waiterId)
    if w == nil or player == nil then return end
    endWait(waiterId)
    local perf, song, timeline = atBpm(w.perf, band.bpm)
    local origin, fromMs = bands:join(waiterId, band, timeline, now)
    if origin == nil then
        goSolo(player, w.perf, w.fullType, 0, now)
        return
    end
    perf.fromMs = fromMs
    go(player, perf, w.fullType, song, timeline, origin)
end

local function leaveBand(id, now)
    local band = bands:of(id)
    bands:leave(id, now)
    sendRoster(band)
end

function handlers.start(player, args)
    if not sessions:allow(player:getOnlineID(), getTimestampMs()) then -- flooding: drop
        if args.wait then send(player, "alongEnded", { reason = "Refused" }) end
        return
    end
    local ok, why = PlayIt.Session.validate(args.perf)
    if ok and type(args.origin) ~= "number" then ok, why = false, "origin" end
    if ok and not PlayIt.Session.validStart(args) then ok, why = false, "start" end
    if ok and PlayIt.Instruments.isWorld(args.fullType) then
        local refused
        ok, refused = mayPlayFurniture(player, args.fullType, args.perf.place)
        if not ok then
            why = refused
            sendServerCommand(player, "PlayIt", "refused", { reason = refused })
        end
    elseif ok and not holds(player, args.fullType) then
        ok, why = false, "instrument"
    end
    local song = ok and PlayIt.Song.parse(args.perf.text, args.perf.bpm)
    if ok and song.events >= PlayIt.Song.MAX_EVENTS then ok, why = false, "too many notes" end
    if not ok then
        print("[PlayIt] rejected start from " .. player:getUsername() .. ": " .. tostring(why))
        if args.wait then send(player, "alongEnded", { reason = "Refused" }) end -- its client waits for an answer
        return
    end
    local id = player:getOnlineID()
    local now = getTimestampMs()
    endWait(id)

    if not args.wait then
        -- playing alone, already sounding on the musician's client: their clock estimate, implausible ones now
        local origin = args.origin
        if math.abs(origin - now) > args.perf.length + ORIGIN_SLACK_MS then origin = now end
        local timeline = PlayIt.Timeline.build(song, args.perf.seed, args.perf.segments)
        bands:startSolo(id, timeline, args.perf.bpm, origin)
        startPart(player, args.perf, args.fullType, song, timeline, origin)
        releaseWaiters(id, now)
        sendRoster(bands:of(id))
        return
    end

    -- back into the performance they left, or into the one of the player they play along with
    local band = (args.resume and bands:lastBand(id)) or (args.along and bands:of(args.along))
    if band then
        local perf, partSong, timeline = atBpm(args.perf, band.bpm)
        local origin, fromMs = bands:join(id, band, timeline, now)
        if origin then
            perf.fromMs = fromMs
            go(player, perf, args.fullType, partSong, timeline, origin)
            sendRoster(band)
            return
        end
    elseif args.along and not args.resume then
        local target = musicianOf(args.along)
        if target == nil or target == player or not inRange(player, target) then
            send(player, "alongEnded", { reason = "TooFar" })
            return
        end
        bands:wait(id, args.along)
        ready[id] = { perf = args.perf, fullType = args.fullType }
        send(player, "waiting", { name = nameOf(target) })
        sendWaiters(args.along)
        return
    end

    -- the musician others wait for: everyone ready and in range starts together after the count-in
    local perf, partSong, timeline = atBpm(args.perf, args.perf.bpm)
    local joining, parts, any = {}, {}, false
    for _, waiterId in ipairs(bands:waitersOf(id)) do
        local w, wp = ready[waiterId], musicianOf(waiterId)
        if w and wp and inRange(wp, player) then
            local wPerf, wSong, wTimeline = atBpm(w.perf, perf.bpm)
            joining[waiterId] = { player = wp, perf = wPerf, song = wSong, timeline = wTimeline, fullType = w.fullType }
            parts[waiterId] = wTimeline
            any = true
        end
    end
    if any then
        local starts = bands:startWithWaiters(id, timeline, perf.bpm, now, parts)
        local startAt = now + PlayIt.Band.COUNT_IN_MS
        go(player, perf, args.fullType, partSong, timeline, starts[id], startAt)
        for waiterId, j in pairs(joining) do
            ready[waiterId] = nil
            go(j.player, j.perf, j.fullType, j.song, j.timeline, starts[waiterId], startAt)
        end
        sendWaiters(id)
        sendRoster(bands:of(id))
        return
    end

    goSolo(player, args.perf, args.fullType, args.posMs, now)
    sendRoster(bands:of(id))
end

-- the client's clock: answer with ours (PlayIt.Clock on the client)
function handlers.ping(player, args)
    if type(args.t0) ~= "number" then return end
    sendServerCommand(player, "PlayIt", "pong", { t0 = args.t0, s = getTimestampMs() })
end

function handlers.pause(player, args)
    local id = player:getOnlineID()
    local s = sessions:get(id)
    if s then s.moodFrom = nil end
    sendToListeners(id, "stop", { id = id })
    sessions:pause(id, args.posMs)
    leaveBand(id, getTimestampMs())
end

function handlers.stop(player)
    local id = player:getOnlineID()
    sendToListeners(id, "stop", { id = id })
    sessions:stop(id)
    leaveBand(id, getTimestampMs())
    endWait(id)
end

-- a waiting player gave up; if the go crossed on the way, its session ends too
function handlers.unalong(player)
    handlers.stop(player)
end

function handlers.segments(player, args)
    local id = player:getOnlineID()
    local s = sessions:get(id)
    if s == nil or type(args.segments) ~= "table" then return end
    if not sessions:allow(id, getTimestampMs()) then return end
    local perf = {}
    for k, v in pairs(s.perf) do perf[k] = v end
    perf.segments = args.segments
    if not PlayIt.Session.validate(perf) then return end
    sessions:setSegments(id, args.segments)
    s.timeline = PlayIt.Timeline.build(s.song, s.perf.seed, args.segments)
    sendToListeners(id, "segments", { id = id, segments = args.segments })
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "PlayIt" or handlers[command] == nil then return end
    handlers[command](player, args or {})
end)

-- listeners' stats are server-owned in MP: apply the mood of the music heard since the last tick, then sync
local function moodTick(musician, s, pos, cfg, def)
    local dur, blunderMs = PlayIt.Effects.window(s.timeline, s.moodFrom or pos, pos)
    s.moodFrom = pos
    if dur == 0 then return end
    local earshot = PlayIt.Effects.earshot(def, s.perf.volume)
    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if not p:isDead() then
            local stats = p:getStats()
            local fx = PlayIt.Effects.forWindow(dur, blunderMs, p:DistTo(musician), earshot, s.perf.level, cfg.annoy,
                p == musician, PlayIt.Effects.moodOf(stats))
            if fx then
                stats:remove(CharacterStat.BOREDOM, -fx.boredom)
                if fx.stress > 0 then stats:add(CharacterStat.STRESS, fx.stress) end
                if fx.unhappy > 0 then stats:add(CharacterStat.UNHAPPINESS, fx.unhappy) end
                syncPlayerStats(p, -1) -- all stats; the bit order of CharacterStat.ORDERED_STATS isn't ours to hard-code
            end
        end
    end
end

-- while a musician plays: Music XP, mood, and tame animals that trust them come over (server-simulated in MP)
local function playingTick(musician, s, now, pos)
    local cfg = PlayIt.Config.get()
    if cfg.skillOn and Perks.PlayItMusic then
        addXp(musician, Perks.PlayItMusic, PlayIt.Effects.XP_PER_SECOND * CATCH_UP_MS / 1000)
    end
    local def = PlayIt.Instruments.defs[s.fullType]
    if def and not musician:isInvisible() then
        local r = PlayIt.Effects.noiseRadius(def, s.perf.volume, cfg.noiseMult)
        if r > 0 then PlayIt.Herd.call(musician, r, now) end
        moodTick(musician, s, pos, cfg, def)
    end
end

-- waits end when either player is gone or out of reach; a member out of reach of every other member stops
-- ("too far from the band"); performances nobody played in for a while end
local function bandTick(now)
    for waiterId, targetId in pairs(bands.waits) do
        local waiter, target = musicianOf(waiterId), musicianOf(targetId)
        if waiter == nil then
            endWait(waiterId)
        elseif target == nil then
            endWait(waiterId, "TargetLeft")
        elseif not inRange(waiter, target) then
            endWait(waiterId, "TooFar")
        end
    end
    for _, band in pairs(bands.list) do
        local ids = bands:members(band)
        if #ids > 1 then
            for _, id in ipairs(ids) do
                local p, near = musicianOf(id), false
                for _, other in ipairs(ids) do
                    local o = musicianOf(other)
                    if other ~= id and o and p and inRange(p, o) then near = true end
                end
                if p and not near then
                    sendToListeners(id, "stop", { id = id })
                    sessions:stop(id)
                    leaveBand(id, now)
                    send(p, "alongEnded", { reason = "TooFarFromBand" })
                end
            end
        end
    end
    bands:tick(now)
end

-- late joiners get the song at its current place; sessions of departed or dead musicians end
Events.OnTick.Add(function()
    local now = getTimestampMs()
    PlayIt.Herd.update(now)
    if now < nextCatchUp then return end
    nextCatchUp = now + CATCH_UP_MS
    for id, s in pairs(sessions.list) do
        local musician = musicianOf(id)
        if musician == nil or musician:isDead() or musician:getUsername() ~= s.username then
            sendToListeners(id, "stop", { id = id })
            sessions:removePlayer(id)
            leaveBand(id, now)
        else
            local pos = sessions:positionAt(id, now)
            if pos then
                sendPlay(id, musician, s.perf, s.fullType, s.origin)
                if pos >= 0 then playingTick(musician, s, now, pos) end
            elseif not sessions:pausedAt(id) then
                sessions:stop(id) -- song over
                leaveBand(id, now)
            end
        end
    end
    bandTick(now)
end)
