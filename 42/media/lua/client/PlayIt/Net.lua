-- Client side of the relay. The musician's own playback starts at once; the server forwards the song to
-- players nearby. In single player there is no server: everything stays local.

require "PlayIt/Playback"
require "PlayIt/Session"

PlayIt = PlayIt or {}
PlayIt.Net = PlayIt.Net or {}
local Net = PlayIt.Net

local function multiplayer() return isClient() end

function Net.idOf(player)
    if multiplayer() then return player:getOnlineID() end
    return "sp" .. player:getPlayerNum()
end

function Net.sourceOf(player)
    return {
        getPos = function() return player:getX(), player:getY(), player:getZ() end,
        isSilent = function() return player:isInvisible() end,
    }
end

function Net.start(player, fullType, perf, posMs)
    PlayIt.Playback.start(Net.idOf(player), Net.sourceOf(player), fullType, perf, posMs, getTimestampMs())
    if multiplayer() then
        sendClientCommand(player, "PlayIt", "start", { fullType = fullType, perf = perf, posMs = posMs })
    end
end

-- returns where the song was paused (nil if it had ended)
function Net.pause(player)
    local pos = PlayIt.Playback.pause(Net.idOf(player), getTimestampMs())
    if multiplayer() then sendClientCommand(player, "PlayIt", "pause", { posMs = pos or 0 }) end
    return pos
end

function Net.stop(player)
    PlayIt.Playback.stop(Net.idOf(player))
    if multiplayer() then sendClientCommand(player, "PlayIt", "stop", {}) end
end

function Net.segments(player, segments)
    PlayIt.Playback.setSegments(Net.idOf(player), segments)
    if multiplayer() then sendClientCommand(player, "PlayIt", "segments", { segments = segments }) end
end

local handlers = {}
local waiting = {} -- songs whose musician isn't loaded on this client yet, by musician id

function handlers.play(args)
    local musician = getPlayerByOnlineID(args.id)
    if musician == nil then
        waiting[args.id] = { args = args, received = getTimestampMs() }
        return
    end
    if musician:isLocalPlayer() then return end -- split screen: the musician's own playback is already running
    waiting[args.id] = nil
    PlayIt.Playback.start(args.id, Net.sourceOf(musician), args.fullType, args.perf, args.posMs, getTimestampMs())
end

function handlers.stop(args)
    waiting[args.id] = nil
    PlayIt.Playback.stop(args.id)
end

function handlers.segments(args)
    PlayIt.Playback.setSegments(args.id, args.segments)
end

-- the relay reaches further than a client loads players: start waiting songs once their musician appears
Events.OnTick.Add(function()
    if next(waiting) == nil then return end
    local now = getTimestampMs()
    for id, w in pairs(waiting) do
        local pos = PlayIt.Session.lateStart(w.args.posMs, w.received, now, w.args.perf.length)
        local musician = getPlayerByOnlineID(id)
        if pos == nil then
            waiting[id] = nil
        elseif musician then
            waiting[id] = nil
            PlayIt.Playback.start(id, Net.sourceOf(musician), w.args.fullType, w.args.perf, pos, now)
        end
    end
end)

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "PlayIt" or handlers[command] == nil then return end
    handlers[command](args)
end)
