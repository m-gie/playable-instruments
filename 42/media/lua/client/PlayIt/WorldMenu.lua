-- World context menu: "Play <instrument>" on a piano, organ or drum piece (walks over first when out of reach)
-- and "Stop playing" while this player plays it.

require "PlayIt/Instruments"
require "PlayIt/Furniture"
require "PlayIt/Playback"
require "PlayIt/Controls"
require "PlayIt/Net"
require "PlayIt/Session"
require "TimedActions/ISPlayItOpenAction"

-- the first instrument tile among the clicked objects: fullType, piece, square
local function instrumentIn(worldobjects)
    for _, obj in ipairs(worldobjects) do
        local square = obj:getSquare()
        if square then
            for _, f in ipairs(PlayIt.Furniture.look(square:getX(), square:getY(), square:getZ())) do
                return f.fullType, f.piece, square
            end
        end
    end
    return nil
end

local function play(player, fullType, square)
    local place = { x = square:getX(), y = square:getY(), z = square:getZ() }
    if PlayIt.Furniture.inReach(player:getX(), player:getY(), player:getZ(), place.x, place.y, place.z) then
        PlayIt.MusicWindow.open(player, fullType, place)
    elseif luautils.walkAdj(player, square) then
        ISTimedActionQueue.add(ISPlayItOpenAction:new(player, fullType, place))
    end
end

local function tooltip(text)
    local t = ISWorldObjectContextMenu.addToolTip()
    t.description = text
    return t
end

Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldobjects, test)
    if test then return end
    local player = getSpecificPlayer(playerNum)
    local fullType, piece, square = instrumentIn(worldobjects)
    if fullType == nil then return end
    local here = { x = square:getX(), y = square:getY(), z = square:getZ() }
    if piece then here.kit = { { piece = piece, x = here.x, y = here.y, z = here.z } } end

    local option = context:addOption(getText("ContextMenu_PlayIt_PlayWorld", PlayIt.Instruments.displayName(fullType)),
        player, play, fullType, square)
    if piece and not player:getInventory():contains(PlayIt.Furniture.STICK) then
        option.notAvailable = true
        option.toolTip = tooltip(getText("Tooltip_PlayIt_NeedSticks"))
    elseif PlayIt.Playback.busyAt(fullType, here, PlayIt.Net.idOf(player)) then
        option.notAvailable = true
        option.toolTip = tooltip(getText("Tooltip_PlayIt_Busy"))
    end

    local c = PlayIt.Controls.get(player)
    local playingHere = PlayIt.Session.overlaps(fullType, here, c:instrument(), c:place())
    if (c:isPlaying() or c:isPaused()) and playingHere then
        context:addOption(getText("ContextMenu_PlayIt_Stop"), player, PlayIt.Controls.stop)
    end
end)
