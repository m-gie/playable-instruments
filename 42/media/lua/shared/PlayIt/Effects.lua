-- How far music carries and what it does to the people listening.

PlayIt = PlayIt or {}
PlayIt.Effects = PlayIt.Effects or {}
local Effects = PlayIt.Effects

Effects.NOISE_INTERVAL_MS = 2000
-- the engine x1.5s perks.txt and gives skills without a profession/trait boost (Music always) only x0.25 XP:
-- 0.8 -> 0.2 XP/s in practice, level 1 after ~6 min of playing, level 5 after ~3.9 h, level 10 after ~45.5 h
Effects.XP_PER_SECOND = 0.8
Effects.BOREDOM_BASE = 0.1 -- boredom (0-100) per real second at Music 0; a TV has no fixed rate to copy
-- Bad music is only slightly bad: it can push a listener just past the first Unhappy and Anxious moodles and
-- no further, and a whole botched song at Music 0 (half the notes wrong, 90 s of blunders in 3 min) gets there.
Effects.ANNOY_UNHAPPY_MAX = 25 -- unhappiness is 0-100
Effects.ANNOY_STRESS_MAX = 0.25 -- stress is 0-1
Effects.ANNOY_UNHAPPY_PER_SEC = Effects.ANNOY_UNHAPPY_MAX / 90 -- per second of wrong notes heard
Effects.ANNOY_STRESS_PER_SEC = Effects.ANNOY_STRESS_MAX / 90

-- tiles zombies and animals notice the music from
function Effects.noiseRadius(def, volume, mult)
    return math.floor(def.maxRadius * volume * mult + 0.5)
end

-- tiles within which listeners are affected
function Effects.earshot(def, volume)
    return def.maxRadius * volume
end

function Effects.boredomPerSecond(level)
    return Effects.BOREDOM_BASE * (1 + 0.2 * level)
end

-- total length (ms) of the chords starting in [fromMs, toMs) and of the botched ones: what a listener heard
function Effects.window(timeline, fromMs, toMs)
    local dur, blunderMs = 0, 0
    for _, e in ipairs(timeline.events) do
        if e.t >= fromMs and e.t < toMs and #e.notes > 0 then
            dur = dur + e.dur
            if e.blunder then blunderMs = blunderMs + e.dur end
        end
    end
    return dur, blunderMs
end

-- what `add` raises a stat by when it can't go past `max` (and never lowers it)
local function capped(now, add, max)
    return math.max(0, math.min(add, max - now))
end

-- a character's current { unhappy, stress }, as forWindow wants them
function Effects.moodOf(stats)
    return { unhappy = stats:get(CharacterStat.UNHAPPINESS), stress = stats:get(CharacterStat.STRESS) }
end

-- stat changes for a stretch of music (durMs of chords, blunderMs of them wrong) on a listener in `mood`
-- ({ unhappy, stress }, their current stats); nil when out of earshot.
-- The musician enjoys their own playing but isn't annoyed by their own wrong notes.
function Effects.forWindow(durMs, blunderMs, distance, earshot, musicianLevel, annoy, isMusician, mood)
    if distance > earshot then return nil end
    local secs = (annoy and not isMusician) and blunderMs / 1000 or 0
    return {
        boredom = -Effects.boredomPerSecond(musicianLevel) * durMs / 1000,
        stress = capped(mood.stress, secs * Effects.ANNOY_STRESS_PER_SEC, Effects.ANNOY_STRESS_MAX),
        unhappy = capped(mood.unhappy, secs * Effects.ANNOY_UNHAPPY_PER_SEC, Effects.ANNOY_UNHAPPY_MAX),
    }
end

-- stat changes for one played chord on a listener at `distance`; nil when out of earshot
function Effects.forListener(event, distance, earshot, musicianLevel, annoy, isMusician, mood)
    return Effects.forWindow(event.dur, event.blunder and event.dur or 0, distance, earshot, musicianLevel, annoy,
        isMusician, mood)
end
