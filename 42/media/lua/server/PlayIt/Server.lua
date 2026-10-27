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

local RELAY_RANGE = 80
local CATCH_UP_MS = 2000

local sessions = PlayIt.Session.new()
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

local function sendPlay(id, musician, perf, fullType, posMs)
    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p ~= musician and not sessions:hasListener(id, p:getOnlineID()) and inRange(p, musician) then
            sessions:addListener(id, p:getOnlineID())
            sendServerCommand(p, "PlayIt", "play", { id = id, fullType = fullType, perf = perf, posMs = posMs })
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

function handlers.start(player, args)
    if not sessions:allow(player:getOnlineID(), getTimestampMs()) then return end -- flooding: drop quietly
    local ok, why = PlayIt.Session.validate(args.perf)
    if ok and type(args.posMs) ~= "number" then ok, why = false, "posMs" end
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
    if not ok then
        print("[PlayIt] rejected start from " .. player:getUsername() .. ": " .. tostring(why))
        return
    end
    local id = player:getOnlineID()
    sessions:start(id, args.perf, args.posMs, getTimestampMs())
    local s = sessions:get(id)
    s.fullType = args.fullType
    s.username = player:getUsername()
    s.timeline = PlayIt.Timeline.build(PlayIt.Song.parse(args.perf.text, args.perf.bpm), args.perf.seed, args.perf.segments)
    s.moodFrom = args.posMs
    sendPlay(id, player, args.perf, args.fullType, args.posMs)
end

function handlers.pause(player, args)
    local id = player:getOnlineID()
    local s = sessions:get(id)
    if s then s.moodFrom = nil end
    sendToListeners(id, "stop", { id = id })
    sessions:pause(id, args.posMs)
end

function handlers.stop(player)
    local id = player:getOnlineID()
    sendToListeners(id, "stop", { id = id })
    sessions:stop(id)
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
    s.timeline = PlayIt.Timeline.build(PlayIt.Song.parse(s.perf.text, s.perf.bpm), s.perf.seed, args.segments)
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
        else
            local pos = sessions:positionAt(id, now)
            if pos then
                sendPlay(id, musician, s.perf, s.fullType, pos)
                playingTick(musician, s, now, pos)
            elseif not sessions:pausedAt(id) then
                sessions:stop(id) -- song over
            end
        end
    end
end)
