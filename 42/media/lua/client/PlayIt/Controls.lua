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

-- one controller per player slot; after a respawn it moves to the new character (never back to a dead one),
-- and its hooks always use its current character
function Controls.get(player)
    local key = player:getPlayerNum()
    local c = controllers[key]
    if c == nil then
        c = PlayIt.Controller.new(player, {
            net = PlayIt.Net,
            newSeed = function() return ZombRand(1, 2000000000) end,
            position = function() return PlayIt.Playback.position(PlayIt.Net.idOf(c.player), getTimestampMs()) end,
            currentChord = function() return PlayIt.Playback.currentChord(PlayIt.Net.idOf(c.player)) end,
            level = function() return musicLevel(c.player) end,
            config = PlayIt.Config.get,
            serverNow = function() return PlayIt.Net.clock:toServer(getTimestampMs()) end,
            mood = function()
                local stats = c.player:getStats()
                return stats:get(CharacterStat.INTOXICATION), stats:get(CharacterStat.PANIC)
            end,
        })
        controllers[key] = c
    elseif c.player ~= player and not player:isDead() then
        c.player = player
    end
    return c
end

-- queue the play action; it starts (or resumes) the song once the instrument is in hand.
-- place: where a piano, organ or drum kit stands (nil for hand-held instruments)
function Controls.play(player, text, bpm, volume, fullType, place)
    if ISTimedActionQueue.hasActionType(player, "ISPlayItAction") then return end
    local song = { text = text, bpm = bpm, volume = volume, fullType = fullType, place = place }
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
