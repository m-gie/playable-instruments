-- Client side of the relay. The musician's own playback starts at once; the server forwards the song to
-- players nearby. In single player there is no server: everything stays local.

require "PlayIt/Playback"

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

function handlers.play(args)
    local musician = getPlayerByOnlineID(args.id)
    if musician == nil then return end -- not loaded on this client
    PlayIt.Playback.start(args.id, Net.sourceOf(musician), args.fullType, args.perf, args.posMs, getTimestampMs())
end

function handlers.stop(args)
    PlayIt.Playback.stop(args.id)
end

function handlers.segments(args)
    PlayIt.Playback.setSegments(args.id, args.segments)
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "PlayIt" or handlers[command] == nil then return end
    handlers[command](args)
end)
