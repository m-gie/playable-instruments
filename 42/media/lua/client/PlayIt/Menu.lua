-- Inventory context menu: "Play" on an instrument (equips it, opens the music window) and
-- "Stop playing" while it plays.

require "PlayIt/Instruments"
require "PlayIt/Controls"

local function instrumentIn(items)
    for _, entry in ipairs(items) do
        local item = entry
        if type(entry) == "table" then item = entry.items and entry.items[1] end
        if item and PlayIt.Instruments.defs[item:getFullType()] then return item end
    end
    return nil
end

local function play(player, item)
    if player:getPrimaryHandItem() ~= item then
        ISInventoryPaneContextMenu.equipWeapon(item, true, item:isTwoHandWeapon(), player:getPlayerNum())
    end
    PlayIt.MusicWindow.open(player, item:getFullType())
end

Events.OnFillInventoryObjectContextMenu.Add(function(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    local item = instrumentIn(items)
    if item == nil then return end
    context:addOption(getText("ContextMenu_PlayIt_Play"), player, play, item)
    local c = PlayIt.Controls.get(player)
    if (c:isPlaying() or c:isPaused()) and c:instrument() == item:getFullType() then
        context:addOption(getText("ContextMenu_PlayIt_Stop"), player, PlayIt.Controls.stop)
    end
end)
