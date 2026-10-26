-- Playing an instrument. Client-only (vanilla WalkToTimedAction style): nothing here needs the server.
-- Walking is fine; running, aiming, being hit or grabbed, dropping the instrument or entering a vehicle
-- interrupt it, and an interruption pauses the song so Play resumes it.

require "TimedActions/ISBaseTimedAction"

ISPlayItAction = ISBaseTimedAction:derive("ISPlayItAction")

local CHANCE_EVERY_MS = 2000

function ISPlayItAction:holdsInstrument()
    local item = self.character:getPrimaryHandItem()
    return item ~= nil and item:getFullType() == self.song.fullType
end

function ISPlayItAction:interrupted()
    local c = self.character
    local hit = c:getHitReaction() ~= nil and c:getHitReaction() ~= ""
    return hit or c:isKnockedDown() or c:isZombieAttacking() or c:isBumped() or c:getVehicle() ~= nil
        or not self:holdsInstrument()
end

-- checked when the action begins (after any equip action queued before it) and every tick
function ISPlayItAction:isValid()
    return self:holdsInstrument() and self.character:getVehicle() == nil
end

function ISPlayItAction:update()
    if self:interrupted() then
        self:forceStop()
        return
    end
    self.controller:tick()
    if not self.controller:isPlaying() then
        self:forceComplete()
        return
    end
    local now = getTimestampMs()
    if now >= self.nextChance then
        self.nextChance = now + CHANCE_EVERY_MS
        self.controller:updateChance()
    end
end

-- the song starts only now, with the instrument in hand
function ISPlayItAction:start()
    local s = self.song
    if not self.controller:play(s.text, s.bpm, s.volume, s.fullType) then
        self:forceStop() -- too long to send; the window already said so
        return
    end
    self.nextChance = getTimestampMs() + CHANCE_EVERY_MS
end

function ISPlayItAction:stop()
    self.controller:pause()
    ISBaseTimedAction.stop(self)
end

function ISPlayItAction:perform()
    ISBaseTimedAction.perform(self)
end

-- song: { text, bpm, volume, fullType }
function ISPlayItAction:new(character, controller, song)
    local o = ISBaseTimedAction.new(self, character)
    o.controller = controller
    o.song = song
    o.maxTime = -1
    o.stopOnWalk = false
    o.stopOnRun = true
    o.stopOnAim = true
    return o
end
