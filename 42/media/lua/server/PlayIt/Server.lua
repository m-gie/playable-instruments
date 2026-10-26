-- Multiplayer relay: checks a musician's song once, sends it to everyone within RELAY_RANGE, catches up
-- players who walk in mid-song, and ends sessions whose musician is gone. No per-note traffic.

if not isServer() then return end -- clients run lua/server too in B42

require "PlayIt/Session"
require "PlayIt/Instruments"
require "PlayIt/Effects"
require "PlayIt/Herd"
require "PlayIt/Config"

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

local handlers = {}

function handlers.start(player, args)
    local ok, why = PlayIt.Session.validate(args.perf)
    if not ok or type(args.posMs) ~= "number" or not holds(player, args.fullType) then
        print("[PlayIt] rejected start from " .. player:getUsername() .. ": " .. tostring(why or "instrument"))
        return
    end
    local id = player:getOnlineID()
    sessions:start(id, args.perf, args.posMs, getTimestampMs())
    sessions:get(id).fullType = args.fullType
    sendPlay(id, player, args.perf, args.fullType, args.posMs)
end

function handlers.pause(player, args)
    local id = player:getOnlineID()
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
    local perf = {}
    for k, v in pairs(s.perf) do perf[k] = v end
    perf.segments = args.segments
    if not PlayIt.Session.validate(perf) then return end
    sessions:setSegments(id, args.segments)
    sendToListeners(id, "segments", { id = id, segments = args.segments })
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "PlayIt" or handlers[command] == nil then return end
    handlers[command](player, args or {})
end)

-- while a musician plays: Music XP, and tame animals that trust them come over (server-simulated in MP)
local function playingTick(musician, s, now)
    local cfg = PlayIt.Config.get()
    if cfg.skillOn and Perks.PlayItMusic then
        addXp(musician, Perks.PlayItMusic, PlayIt.Effects.XP_PER_SECOND * CATCH_UP_MS / 1000)
    end
    local def = PlayIt.Instruments.defs[s.fullType]
    if def and not musician:isInvisible() then
        local r = PlayIt.Effects.noiseRadius(def, s.perf.volume, cfg.noiseMult)
        if r > 0 then PlayIt.Herd.call(musician, r, now) end
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
        if musician == nil or musician:isDead() then
            sendToListeners(id, "stop", { id = id })
            sessions:removePlayer(id)
        else
            local pos = sessions:positionAt(id, now)
            if pos then
                sendPlay(id, musician, s.perf, s.fullType, pos)
                playingTick(musician, s, now)
            elseif not sessions:pausedAt(id) then
                sessions:stop(id) -- song over
            end
        end
    end
end)
