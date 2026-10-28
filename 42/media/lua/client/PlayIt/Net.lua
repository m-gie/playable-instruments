-- Client side of the relay. The musician's own playback starts at once; the server forwards the song to
-- players nearby. In single player there is no server: everything stays local.

require "PlayIt/Playback"
require "PlayIt/Session"
require "PlayIt/Clock"

PlayIt = PlayIt or {}
PlayIt.Net = PlayIt.Net or {}
local Net = PlayIt.Net

local function multiplayer() return isClient() end

Net.clock = PlayIt.Clock.new() -- the server's clock; songs travel with server-time origins
Net.PING_EVERY_MS = 30000
local nextPing = 0

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
    local now = getTimestampMs()
    PlayIt.Playback.start(Net.idOf(player), Net.sourceOf(player), fullType, perf, posMs, now)
    if multiplayer() then
        local origin = Net.clock:toServer(now) - posMs
        sendClientCommand(player, "PlayIt", "start", { fullType = fullType, perf = perf, origin = origin })
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

-- where a relayed part is now on this client, from its server-time origin; nil once over
local function relayedPos(args, now)
    return PlayIt.Session.posAt(args.origin, Net.clock:toServer(now), args.perf.length)
end

function handlers.play(args)
    local musician = getPlayerByOnlineID(args.id)
    if musician == nil then
        waiting[args.id] = args
        return
    end
    if musician:isLocalPlayer() then return end -- split screen: the musician's own playback is already running
    waiting[args.id] = nil
    local now = getTimestampMs()
    local pos = relayedPos(args, now)
    if pos then PlayIt.Playback.start(args.id, Net.sourceOf(musician), args.fullType, args.perf, pos, now) end
end

function handlers.pong(args)
    Net.clock:sample(args.t0, args.s, getTimestampMs())
end

function handlers.stop(args)
    waiting[args.id] = nil
    PlayIt.Playback.stop(args.id)
end

function handlers.segments(args)
    PlayIt.Playback.setSegments(args.id, args.segments)
end

-- the server turned down our song on a piano, organ or drums: stop it here too and say why
function handlers.refused(args)
    local player = getPlayer()
    if player == nil or PlayIt.Controls == nil then return end
    PlayIt.Controls.stop(player)
    local w = PlayIt.MusicWindow and PlayIt.MusicWindow.get(player)
    if w then w:setStatus(getText("IGUI_PlayIt_" .. tostring(args.reason))) end
end

-- the relay reaches further than a client loads players: start waiting songs once their musician appears.
-- Also pings the server now and then to keep the clock offset fresh.
Events.OnTick.Add(function()
    local now = getTimestampMs()
    if multiplayer() and now >= nextPing and getPlayer() then
        nextPing = now + Net.PING_EVERY_MS
        sendClientCommand(getPlayer(), "PlayIt", "ping", { t0 = now })
    end
    for id, args in pairs(waiting) do
        local pos = relayedPos(args, now)
        local musician = getPlayerByOnlineID(id)
        if pos == nil then
            waiting[id] = nil
        elseif musician then
            waiting[id] = nil
            PlayIt.Playback.start(id, Net.sourceOf(musician), args.fullType, args.perf, pos, now)
        end
    end
end)

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "PlayIt" or handlers[command] == nil then return end
    handlers[command](args)
end)
