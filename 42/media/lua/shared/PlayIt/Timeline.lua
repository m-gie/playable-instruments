-- Turns a parsed song into timed note events with blunders. Everything is derived from (song, seed, segments),
-- so every client builds the same timeline, blunders and hesitations included.

PlayIt = PlayIt or {}
PlayIt.Timeline = PlayIt.Timeline or {}
local Timeline = PlayIt.Timeline

Timeline.MAX_CHANCE = 0.6
Timeline.DRUNK_WEIGHT = 0.30
Timeline.PANIC_WEIGHT = 0.20
Timeline.PAUSE_MAX_MS = 400

local MODULUS = 2147483647

-- p0/p10 are fractions (0.5 = 50%); intox and panic are 0-100. Between the two ends the chance falls slowly
-- at first and fast at the end (exponent (level/10)^2): about 6% at level 5 with the default ends.
function Timeline.chance(level, p0, p10, intox, panic, skillOn)
    local base = 0
    if skillOn and p0 > 0 then
        base = p0 * (p10 / p0) ^ ((level / 10) ^ 2)
    end
    local total = base + Timeline.DRUNK_WEIGHT * intox / 100 + Timeline.PANIC_WEIGHT * panic / 100
    return math.min(total, Timeline.MAX_CHANCE)
end

-- Park-Miller LCG; integer arithmetic stays exact in doubles, so Kahlua and other Luas agree
function Timeline.rng(seed, index)
    local state = (seed + index * 7919) % (MODULUS - 1) + 1
    return function()
        state = (state * 16807) % MODULUS
        return state / MODULUS
    end
end

local function chanceFor(segments, chord)
    local chance = 0
    for _, seg in ipairs(segments) do
        if seg.fromChord <= chord then chance = seg.chance else break end
    end
    return chance
end

local function sign(r) return r < 0.5 and -1 or 1 end

-- returns notes ({midi, cents, dur}), blunder kind or nil, extra delay in ms before the chord
local function rollChord(chord, chordMs, rand, chance)
    local notes = {}
    for i, m in ipairs(chord.notes) do
        notes[i] = { midi = m, cents = 0, dur = 60000 / chord.qpm * (chord.lens and chord.lens[i] or chord.beats) }
    end
    if #notes == 0 or rand() >= chance then return notes, nil, 0 end
    local kind = rand()
    if kind < 0.5 then
        local victim = notes[math.floor(rand() * #notes) + 1]
        victim.midi = victim.midi + (1 + math.floor(rand() * 3)) * sign(rand())
        return notes, "wrong", 0
    elseif kind < 0.8 then
        for _, n in ipairs(notes) do n.cents = (30 + 20 * rand()) * sign(rand()) end
        return notes, "sour", 0
    end
    return notes, "pause", math.min(0.5 * chordMs, Timeline.PAUSE_MAX_MS)
end

-- segments: { {fromChord = 1, chance = p}, ... } ascending, first fromChord = 1.
-- Timeline 0 is the first note: the silence before it (leadMs) is skipped in solo play and kept on a shared
-- performance's clock. bars: bar start times, negative before the first note. A hesitation delays its own chord
-- only, so a band member never falls behind for good. Chord numbers stay as written.
function Timeline.build(song, seed, segments)
    local starts, base, leadMs = {}, 0, nil
    for i, chord in ipairs(song.chords) do
        starts[i] = base
        if leadMs == nil and #chord.notes > 0 then leadMs = base end
        base = base + 60000 / chord.qpm * chord.beats
    end
    leadMs = leadMs or base
    local events, bars = {}, {}
    for i, chord in ipairs(song.chords) do
        local t = starts[i] - leadMs
        if chord.bar then bars[#bars + 1] = t end
        if t >= 0 then
            local chordMs = 60000 / chord.qpm * chord.beats
            local notes, blunder, delay = rollChord(chord, chordMs, Timeline.rng(seed, i), chanceFor(segments, i))
            events[#events + 1] = { t = t + delay, chord = i, notes = notes, dur = chordMs, blunder = blunder }
        end
    end
    return { events = events, length = base - leadMs, leadMs = leadMs, bars = bars }
end

-- the first bar start at or after posMs; nil when no bar is left
function Timeline.nextBar(timeline, posMs)
    for _, t in ipairs(timeline.bars) do
        if t >= posMs then return t end
    end
    return nil
end

-- index of the first event starting at or after posMs; nil past the end
function Timeline.firstEventAt(timeline, posMs)
    for i, e in ipairs(timeline.events) do
        if e.t >= posMs then return i end
    end
    return nil
end
