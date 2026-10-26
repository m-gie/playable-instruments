-- One Controller per local player, wired to the game; starts the play action alongside the music.

require "PlayIt/Controller"
require "PlayIt/Config"
require "PlayIt/Net"
require "TimedActions/ISPlayItAction"

PlayIt = PlayIt or {}
PlayIt.Controls = PlayIt.Controls or {}
local Controls = PlayIt.Controls

local controllers = {}

local function musicLevel(player)
    return Perks.PlayItMusic and player:getPerkLevel(Perks.PlayItMusic) or 0
end

function Controls.get(player)
    local key = player:getPlayerNum()
    local c = controllers[key]
    if c == nil or c.player ~= player then
        c = PlayIt.Controller.new(player, {
            net = PlayIt.Net,
            newSeed = function() return ZombRand(1, 2000000000) end,
            position = function() return PlayIt.Playback.position(PlayIt.Net.idOf(player), getTimestampMs()) end,
            currentChord = function() return PlayIt.Playback.currentChord(PlayIt.Net.idOf(player)) end,
            level = function() return musicLevel(player) end,
            config = PlayIt.Config.get,
            mood = function()
                local stats = player:getStats()
                return stats:get(CharacterStat.INTOXICATION), stats:get(CharacterStat.PANIC)
            end,
        })
        controllers[key] = c
    end
    return c
end

-- queue the play action; it starts (or resumes) the song once the instrument is in hand
function Controls.play(player, text, bpm, volume, fullType)
    if ISTimedActionQueue.hasActionType(player, "ISPlayItAction") then return end
    local song = { text = text, bpm = bpm, volume = volume, fullType = fullType }
    ISTimedActionQueue.add(ISPlayItAction:new(player, Controls.get(player), song))
end

function Controls.pause(player)
    Controls.get(player):pause()
end

function Controls.stop(player)
    Controls.get(player):stop()
end

Events.OnPlayerDeath.Add(function(player)
    if player:isLocalPlayer() then Controls.stop(player) end
end)
