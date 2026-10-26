-- Playing an instrument. Client-only (vanilla WalkToTimedAction style): nothing here needs the server.
-- Walking is fine; running, aiming, being hit or grabbed, dropping the instrument or entering a vehicle
-- interrupt it, and an interruption pauses the song so Play resumes it.

require "TimedActions/ISBaseTimedAction"

ISPlayItAction = ISBaseTimedAction:derive("ISPlayItAction")

local CHANCE_EVERY_MS = 2000

function ISPlayItAction:holdsInstrument()
    local item = self.character:getPrimaryHandItem()
    return item ~= nil and item:getFullType() == self.controller:instrument()
end

function ISPlayItAction:interrupted()
    local c = self.character
    local hit = c:getHitReaction() ~= nil and c:getHitReaction() ~= ""
    return hit or c:isKnockedDown() or c:isZombieAttacking() or c:isBumped() or c:getVehicle() ~= nil
        or not self:holdsInstrument()
end

function ISPlayItAction:isValid()
    return self.controller:isPlaying() and self:holdsInstrument() and self.character:getVehicle() == nil
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

function ISPlayItAction:start()
    self.nextChance = getTimestampMs() + CHANCE_EVERY_MS
end

function ISPlayItAction:stop()
    self.controller:pause()
    ISBaseTimedAction.stop(self)
end

function ISPlayItAction:perform()
    ISBaseTimedAction.perform(self)
end

function ISPlayItAction:new(character, controller)
    local o = ISBaseTimedAction.new(self, character)
    o.controller = controller
    o.maxTime = -1
    o.stopOnWalk = false
    o.stopOnRun = true
    o.stopOnAim = true
    return o
end
