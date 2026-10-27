-- Playing an instrument. Client-only (vanilla WalkToTimedAction style): nothing here needs the server.
-- Walking is fine; running, aiming, being hit or grabbed, dropping the instrument or entering a vehicle
-- interrupt it, and an interruption pauses the song so Play resumes it. At a piano, organ or drums, walking out of
-- reach, the instrument going away or losing the last drumstick interrupt it too.

require "TimedActions/ISBaseTimedAction"
require "PlayIt/Trace"
require "PlayIt/Instruments"
require "PlayIt/Furniture"

ISPlayItAction = ISBaseTimedAction:derive("ISPlayItAction")

local CHANCE_EVERY_MS = 2000

function ISPlayItAction:holdsInstrument()
    local item = self.character:getPrimaryHandItem()
    return item ~= nil and item:getFullType() == self.song.fullType
end

-- holding the instrument, or for furniture still at it (and with a drumstick for drums)
function ISPlayItAction:hasInstrument()
    local s = self.song
    if PlayIt.Instruments.isWorld(s.fullType) then
        return s.place ~= nil and PlayIt.Furniture.check(s.fullType, s.place, PlayIt.Furniture.ctxFor(self.character))
    end
    return self:holdsInstrument()
end

function ISPlayItAction:interrupted()
    local c = self.character
    local hit = c:getHitReaction() ~= nil and c:getHitReaction() ~= ""
    return hit or c:isKnockedDown() or c:isZombieAttacking() or c:isBumped() or c:getVehicle() ~= nil
        or not self:hasInstrument()
end

-- checked when the action begins (after any equip action queued before it) and every tick
function ISPlayItAction:isValid()
    return self:hasInstrument() and self.character:getVehicle() == nil
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
    PlayIt.trace("action start: %s, holding %s, invisible %s", s.fullType,
        tostring(self.character:getPrimaryHandItem() and self.character:getPrimaryHandItem():getFullType()),
        tostring(self.character:isInvisible()))
    if not self.controller:play(s.text, s.bpm, s.volume, s.fullType, s.place) then
        self:forceStop() -- too long to send; the window already said so
        return
    end
    self.nextChance = getTimestampMs() + CHANCE_EVERY_MS
end

function ISPlayItAction:stop()
    PlayIt.trace("action stop (interrupted or cancelled)")
    self.controller:pause()
    ISBaseTimedAction.stop(self)
end

function ISPlayItAction:perform()
    ISBaseTimedAction.perform(self)
end

-- song: { text, bpm, volume, fullType, place (furniture) }
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
