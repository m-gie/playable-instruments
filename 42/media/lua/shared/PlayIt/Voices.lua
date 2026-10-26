-- The sounding notes of one musician. Every note gets its own pooled world emitter: the game's
-- FMODSoundEmitter.setPitch(ref, p) re-pitches every sound on an emitter, so notes can't share one.

require "PlayIt/Trace"

PlayIt = PlayIt or {}
PlayIt.Voices = PlayIt.Voices or {}
local Voices = PlayIt.Voices
Voices.__index = Voices

Voices.MAX_VOICES = 12
Voices.RELEASE_MS = 300

local function worldEmitter(x, y, z)
    return getWorld():getFreeEmitter(x, y, z)
end

-- getPos() -> x, y, z of the musician; newEmitter(x, y, z) defaults to a pooled world emitter;
-- releaseMs: fade-out after each note (instrument's release), default RELEASE_MS
function Voices.new(getPos, maxVoices, newEmitter, releaseMs)
    return setmetatable({ getPos = getPos, max = maxVoices or Voices.MAX_VOICES, newEmitter = newEmitter or worldEmitter,
                          release = releaseMs or Voices.RELEASE_MS, list = {} }, Voices)
end

local function stop(voice)
    voice.emitter:stopSound(voice.ref)
end

function Voices:noteOn(sound, ratio, durMs, nowMs, gain)
    local emitter = self.newEmitter(self.getPos())
    -- playSoundImpl, not playSound: on an MP client playSound also sends an unpitched copy to other players,
    -- who already play the song themselves
    local ref = emitter:playSoundImpl(sound, false, nil)
    if ref == nil or ref == 0 then
        PlayIt.trace("note %s failed to start (ref %s)", sound, tostring(ref))
        return
    end
    emitter:setPitch(ref, ratio)
    emitter:setVolume(ref, gain)
    if #self.list >= self.max then stop(table.remove(self.list, 1)) end
    table.insert(self.list, { emitter = emitter, ref = ref, start = nowMs, dur = durMs, gain = gain })
end

-- follow the musician; full gain for the note's length, then a linear fade over the release
function Voices:update(nowMs)
    local x, y, z = self.getPos()
    for i = #self.list, 1, -1 do
        local v = self.list[i]
        local past = nowMs - v.start - v.dur
        if not v.emitter:isPlaying(v.ref) then
            -- the sample ended: the game pools the emitter again, so stop touching it
            table.remove(self.list, i)
        elseif past >= self.release then
            stop(v)
            table.remove(self.list, i)
        else
            v.emitter:setPos(x, y, z)
            v.emitter:setVolume(v.ref, past <= 0 and v.gain or v.gain * (1 - past / self.release))
        end
    end
end

function Voices:stopAll()
    for _, v in ipairs(self.list) do stop(v) end
    self.list = {}
end
