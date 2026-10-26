-- Debug-only listening check: a two-octave major scale and a chord on each instrument, through Voices.

require "PlayIt/Instruments"
require "PlayIt/Voices"

local jobs = {}
local active = {}

local function at(ms, fn) table.insert(jobs, { t = getTimestampMs() + ms, fn = fn }) end

Events.OnTick.Add(function()
    local now = getTimestampMs()
    for i = #jobs, 1, -1 do
        if now >= jobs[i].t then table.remove(jobs, i).fn(now) end
    end
    for _, v in ipairs(active) do v:update(now) end
end)

local MAJOR = { 0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19, 21, 23, 24 }

local function playScale(player, fullType)
    local def = PlayIt.Instruments.defs[fullType]
    local voices = PlayIt.Voices.new(function() return player:getX(), player:getY(), player:getZ() end, nil, nil, def.release)
    table.insert(active, voices)
    local root = def.low + (12 - def.low % 12) % 12 -- first C in range
    for i, step in ipairs(MAJOR) do
        at((i - 1) * 300, function(now)
            local sound, ratio = PlayIt.Instruments.resolve(def, root + step, 0)
            voices:noteOn(sound, ratio, 300, now, 1)
            print(string.format("[PlayIt] %s midi=%d %s x%.3f", def.key, root + step, sound, ratio))
        end)
    end
    at(#MAJOR * 300 + 300, function(now)
        for _, step in ipairs({ 12, 16, 19 }) do
            local sound, ratio = PlayIt.Instruments.resolve(def, root + step, 0)
            voices:noteOn(sound, ratio, 1500, now, 1)
        end
    end)
end

Events.OnFillInventoryObjectContextMenu.Add(function(playerNum, context, items)
    if not isDebugEnabled() then return end
    local player = getSpecificPlayer(playerNum)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(context:addOption("PlayIt scales"), sub)
    for fullType, def in pairs(PlayIt.Instruments.defs) do
        sub:addOption(def.key, player, playScale, fullType)
    end
end)
