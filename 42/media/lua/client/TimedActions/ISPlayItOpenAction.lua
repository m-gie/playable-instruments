-- Opens the music window once the character has walked up to a piano, organ or drums (queued after walkAdj).

require "TimedActions/ISBaseTimedAction"

ISPlayItOpenAction = ISBaseTimedAction:derive("ISPlayItOpenAction")

function ISPlayItOpenAction:isValid()
    return true
end

function ISPlayItOpenAction:perform()
    PlayIt.MusicWindow.open(self.character, self.fullType, self.place)
    ISBaseTimedAction.perform(self)
end

-- place: { x, y, z } of the clicked instrument tile
function ISPlayItOpenAction:new(character, fullType, place)
    local o = ISBaseTimedAction.new(self, character)
    o.fullType = fullType
    o.place = place
    o.maxTime = 1
    o.stopOnWalk = false
    o.stopOnRun = false
    return o
end
