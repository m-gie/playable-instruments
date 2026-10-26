-- The sounding notes of one musician. Every note gets its own pooled world emitter: the game's
-- FMODSoundEmitter.setPitch(ref, p) re-pitches every sound on an emitter, so notes can't share one.

PlayIt = PlayIt or {}
PlayIt.Voices = PlayIt.Voices or {}
local Voices = PlayIt.Voices
Voices.__index = Voices

Voices.MAX_VOICES = 12
Voices.RELEASE_MS = 300

local function worldEmitter(x, y, z)
    return getWorld():getFreeEmitter(x, y, z)
end

-- getPos() -> x, y, z of the musician; newEmitter(x, y, z) defaults to a pooled world emitter
function Voices.new(getPos, maxVoices, newEmitter)
    return setmetatable({ getPos = getPos, max = maxVoices or Voices.MAX_VOICES,
                          newEmitter = newEmitter or worldEmitter, list = {} }, Voices)
end

local function stop(voice)
    voice.emitter:stopSound(voice.ref)
end

function Voices:noteOn(sound, ratio, durMs, nowMs, gain)
    local emitter = self.newEmitter(self.getPos())
    local ref = emitter:playSound(sound)
    if ref == nil or ref == 0 then return end
    emitter:setPitch(ref, ratio)
    emitter:setVolume(ref, gain)
    if #self.list >= self.max then stop(table.remove(self.list, 1)) end
    table.insert(self.list, { emitter = emitter, ref = ref, start = nowMs, dur = durMs, gain = gain })
end

-- follow the musician; full gain for the note's length, then a linear fade over RELEASE_MS
function Voices:update(nowMs)
    local x, y, z = self.getPos()
    for i = #self.list, 1, -1 do
        local v = self.list[i]
        local past = nowMs - v.start - v.dur
        if past >= Voices.RELEASE_MS then
            stop(v)
            table.remove(self.list, i)
        else
            v.emitter:setPos(x, y, z)
            v.emitter:setVolume(v.ref, past <= 0 and v.gain or v.gain * (1 - past / Voices.RELEASE_MS))
        end
    end
end

function Voices:stopAll()
    for _, v in ipairs(self.list) do stop(v) end
    self.list = {}
end
