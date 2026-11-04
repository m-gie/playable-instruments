-- The sounding notes of one musician. Every note gets its own pooled world emitter: the game's
-- FMODSoundEmitter.setPitch(ref, p) re-pitches every sound on an emitter, so notes can't share one.

require "PlayIt/Trace"

PlayIt = PlayIt or {}
PlayIt.Voices = PlayIt.Voices or {}
local Voices = PlayIt.Voices
Voices.__index = Voices

Voices.MAX_VOICES = 20 -- echo tails double the count
Voices.RELEASE_MS = 300
Voices.CUT_MS = 120 -- a ringing tail or finished note fades this long when the next note starts (echo on)

-- the player's Sound volume option (0-1). The options set FMOD faders that only reach the game's sound banks;
-- our notes are plain files, so the voices apply it themselves.
function Voices.userVolume()
    return getSoundManager():getSoundVolume()
end

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

function Voices:start(sound, ratio, durMs, nowMs, gain, isTail)
    local emitter = self.newEmitter(self.getPos())
    -- playSoundImpl, not playSound: on an MP client playSound also sends an unpitched copy to other players,
    -- who already play the song themselves
    local ref = emitter:playSoundImpl(sound, false, nil)
    if ref == nil or ref == 0 then
        PlayIt.trace("note %s failed to start (ref %s)", sound, tostring(ref))
        return
    end
    emitter:setPitch(ref, ratio)
    emitter:setVolume(ref, gain * Voices.userVolume())
    if #self.list >= self.max then stop(table.remove(self.list, 1)) end
    table.insert(self.list, { emitter = emitter, ref = ref, start = nowMs, dur = durMs, gain = gain, tail = isTail })
end

-- the gain a voice sounds at now (before any cut)
local function level(self, v, nowMs)
    if v.tail then return v.gain end
    local past = nowMs - v.start - v.dur
    return past <= 0 and v.gain or v.gain * math.max(0, 1 - past / self.release)
end

-- tail: the sample's echo tail, started beside it at tailGain (echo on). With a tail, every earlier tail and note
-- past its written length fades out over CUT_MS; notes still within their length (held chords) keep sounding.
function Voices:noteOn(sound, ratio, durMs, nowMs, gain, tail, tailGain)
    if tail then
        for _, v in ipairs(self.list) do
            if v.cutAt == nil and v.start < nowMs and (v.tail or nowMs - v.start >= v.dur) then
                v.cutFrom, v.cutAt = level(self, v, nowMs), nowMs
            end
        end
    end
    self:start(sound, ratio, durMs, nowMs, gain, false)
    if tail then self:start(tail, ratio, durMs, nowMs, tailGain, true) end
end

-- live volume and echo: ringing notes take noteGain, tails tailGain (0: they fade out over CUT_MS from nowMs)
function Voices:setGains(noteGain, tailGain, nowMs)
    for _, v in ipairs(self.list) do
        if v.cutAt == nil then
            if not v.tail then
                v.gain = noteGain
            elseif tailGain > 0 then
                v.gain = tailGain
            else
                v.cutFrom, v.cutAt = v.gain, nowMs
            end
        end
    end
end

-- a new tone: its release, for the notes still to come
function Voices:setRelease(releaseMs)
    self.release = releaseMs or Voices.RELEASE_MS
end

-- follow the musician; full gain for the note's length, then a linear fade over the release (tails ring to their
-- end); a cut voice fades from where it was over CUT_MS
function Voices:update(nowMs)
    local x, y, z = self.getPos()
    local user = Voices.userVolume()
    for i = #self.list, 1, -1 do
        local v = self.list[i]
        local past = nowMs - v.start - v.dur
        local cut = v.cutAt and (nowMs - v.cutAt) / Voices.CUT_MS
        if not v.emitter:isPlaying(v.ref) then
            -- the sample ended: the game pools the emitter again, so stop touching it
            table.remove(self.list, i)
        elseif (cut and cut >= 1) or (not v.tail and past >= self.release) then
            stop(v)
            table.remove(self.list, i)
        else
            v.emitter:setPos(x, y, z)
            v.emitter:setVolume(v.ref, (cut and v.cutFrom * (1 - cut) or level(self, v, nowMs)) * user)
        end
    end
end

function Voices:stopAll()
    for _, v in ipairs(self.list) do stop(v) end
    self.list = {}
end
