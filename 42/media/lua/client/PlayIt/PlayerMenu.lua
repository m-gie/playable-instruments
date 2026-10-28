-- World context menu on other players: "Play along with <name>", in multiplayer, while the clicking player has
-- the music window or the widget open, on someone who plays or holds an instrument.

require "PlayIt/Instruments"
require "PlayIt/Playback"
require "PlayIt/Controls"
require "PlayIt/Net"

-- players on and around the clicked squares (characters stand between tiles), other than the clicking one
local function playersNear(worldobjects, self)
    local found, seen = {}, {}
    for _, obj in ipairs(worldobjects) do
        local sq = obj:getSquare()
        if sq then
            for dx = -1, 1 do
                for dy = -1, 1 do
                    local s = getCell():getGridSquare(sq:getX() + dx, sq:getY() + dy, sq:getZ())
                    local movers = s and s:getMovingObjects()
                    for i = 0, (movers and movers:size() or 0) - 1 do
                        local o = movers:get(i)
                        if instanceof(o, "IsoPlayer") and o ~= self and not seen[o] then
                            seen[o] = true
                            found[#found + 1] = o
                        end
                    end
                end
            end
        end
    end
    return found
end

-- playing (we hear them) or holding an instrument
local function isMusician(p)
    if PlayIt.Playback.position(PlayIt.Net.idOf(p), getTimestampMs()) then return true end
    local item = p:getPrimaryHandItem()
    return item ~= nil and PlayIt.Instruments.defs[item:getFullType()] ~= nil
end

local function windowOpen(player)
    local w = PlayIt.MusicWindow and PlayIt.MusicWindow.get(player)
    return (w ~= nil and w:isVisible()) or (PlayIt.MiniWidget ~= nil and PlayIt.MiniWidget.isOpen(player))
end

local function playAlong(player, target)
    PlayIt.Controls.get(player):playAlong(target:getOnlineID(), target:getDisplayName())
end

Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldobjects, test)
    if test or not isClient() then return end
    local player = getSpecificPlayer(playerNum)
    if player == nil or not windowOpen(player) then return end
    for _, p in ipairs(playersNear(worldobjects, player)) do
        if isMusician(p) then
            context:addOption(getText("ContextMenu_PlayIt_PlayAlong", p:getDisplayName()), player, playAlong, p)
        end
    end
end)
