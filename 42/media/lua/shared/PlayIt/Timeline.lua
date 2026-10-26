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

-- p0/p10 are fractions (0.5 = 50%); intox and panic are 0-100
function Timeline.chance(level, p0, p10, intox, panic, skillOn)
    local base = 0
    if skillOn and p0 > 0 then
        base = p0 * (p10 / p0) ^ (level / 10)
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

-- returns notes ({midi, cents}), blunder kind or nil, extra delay in ms before the chord
local function rollChord(midis, chordMs, rand, chance)
    local notes = {}
    for i, m in ipairs(midis) do notes[i] = { midi = m, cents = 0 } end
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

-- segments: { {fromChord = 1, chance = p}, ... } ascending, first fromChord = 1
function Timeline.build(song, seed, segments)
    local events, t = {}, 0
    for i, chord in ipairs(song.chords) do
        local chordMs = 60000 / song.bpm * chord.beats
        local notes, blunder, delay = rollChord(chord.notes, chordMs, Timeline.rng(seed, i), chanceFor(segments, i))
        t = t + delay
        events[i] = { t = t, chord = i, notes = notes, dur = chordMs, blunder = blunder }
        t = t + chordMs
    end
    return { events = events, length = t }
end

-- index of the first event starting at or after posMs; nil past the end
function Timeline.firstEventAt(timeline, posMs)
    for i, e in ipairs(timeline.events) do
        if e.t >= posMs then return i end
    end
    return nil
end
