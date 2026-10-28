require "PlayIt/Effects"
require "PlayIt/Instruments"
local E, I = PlayIt.Effects, PlayIt.Instruments
local function near(a, b) return math.abs(a - b) < 1e-9 end
local trumpet, violin, guitar = I.defs["Base.Trumpet"], I.defs["Base.Violin"], I.defs["Base.GuitarAcoustic"]

check(E.noiseRadius(trumpet, 1, 1) == 45, "trumpet full volume: 45 tiles")
check(E.noiseRadius(violin, 0.5, 1) == 13, "violin half volume: 12.5 rounds to 13")
check(E.noiseRadius(guitar, 1, 0) == 0, "noise multiplier 0: no noise")
check(E.noiseRadius(trumpet, 1, 2) == 90, "noise multiplier scales")
check(E.earshot(guitar, 0.5) == 15, "earshot = max radius x volume")
check(near(E.boredomPerSecond(10), 3 * E.boredomPerSecond(0)), "level 10 cheers up 3x faster than level 0")
check(E.XP_PER_SECOND == 0.2, "0.2 XP per second of playing (user, 2026-10-26: double the original rate)")

-- what one played chord does to a listener
local chord = { dur = 2000 }
local calm = { unhappy = 0, stress = 0 }
local fx = E.forListener(chord, 5, 15, 0, true, false, calm)
check(near(fx.boredom, -E.boredomPerSecond(0) * 2) and fx.stress == 0 and fx.unhappy == 0, "in earshot: boredom down for the chord's length")
check(E.forListener(chord, 16, 15, 0, true, false, calm) == nil, "out of earshot: nothing")
local blunder = { dur = 500, blunder = "wrong" }
fx = E.forListener(blunder, 1, 15, 0, true, false, calm)
check(near(fx.stress, E.ANNOY_STRESS_PER_SEC * 0.5) and near(fx.unhappy, E.ANNOY_UNHAPPY_PER_SEC * 0.5), "a blunder annoys for its length")
fx = E.forListener(blunder, 1, 15, 0, false, false, calm)
check(fx.stress == 0 and fx.unhappy == 0, "annoyance off: blunders don't annoy")

-- Final review #2: what a 2 s server window of a song does
require "PlayIt/Timeline"; require "PlayIt/Song"
local tl = PlayIt.Timeline.build(PlayIt.Song.parse("X:1\nL:1/4\nK:C\nC D E F", 120), 1, { { fromChord = 1, chance = 0 } })
local dur, blunders = E.window(tl, 0, 1000)
check(dur == 1000 and blunders == 0, "chords starting in [0, 1000) counted")
dur = E.window(tl, 1000, 2000); check(dur == 1000, "next window")
local bad = PlayIt.Timeline.build(PlayIt.Song.parse("X:1\nL:1/4\nK:C\nC D", 120), 1, { { fromChord = 1, chance = 1 } })
local _, nb = E.window(bad, 0, 2000); check(nb == 1000, "blunders counted by their length")
local fx2 = E.forWindow(2000, 1000, 4, 10, 0, true, false, calm)
check(near(fx2.boredom, -E.boredomPerSecond(0) * 2) and near(fx2.stress, E.ANNOY_STRESS_PER_SEC) and near(fx2.unhappy, E.ANNOY_UNHAPPY_PER_SEC), "a window of 2 s with 1 s of blunders")
check(E.forWindow(2000, 1000, 11, 10, 0, true, false, calm) == nil, "window: out of earshot")

-- bad music is only slightly bad (user, 2026-10-27): a whole botched song at Music 0 (half the notes wrong)
-- ends just past the first Unhappy and Anxious moodles, and never pushes anyone further
local mood, t = { unhappy = 0, stress = 0 }, 0
while t < 180 do
    fx = E.forWindow(2000, 1000, 1, 10, 0, true, false, mood)
    mood.unhappy, mood.stress, t = mood.unhappy + fx.unhappy, mood.stress + fx.stress, t + 2
end
check(near(mood.unhappy, E.ANNOY_UNHAPPY_MAX) and near(mood.stress, E.ANNOY_STRESS_MAX), "3 min at Music 0 reaches the ceiling")
check(E.ANNOY_UNHAPPY_MAX == 25 and E.ANNOY_STRESS_MAX == 0.25, "ceiling: unhappiness 25, stress 25%")
fx = E.forWindow(2000, 1000, 1, 10, 0, true, false, { unhappy = 24.9, stress = 0.249 })
check(near(fx.unhappy, 0.1) and near(fx.stress, 0.001), "capped at the ceiling")
fx = E.forWindow(2000, 1000, 1, 10, 0, true, false, { unhappy = 60, stress = 0.8 })
check(fx.unhappy == 0 and fx.stress == 0, "already sadder than the ceiling: no worse")

-- the musician isn't annoyed by their own wrong notes, but still enjoys playing (user, 2026-10-26)
fx = E.forListener(blunder, 0, 15, 0, true, true, calm)
check(fx.stress == 0 and fx.unhappy == 0 and fx.boredom < 0, "musician: no annoyance from own blunders, boredom still drops")
fx2 = E.forWindow(2000, 1000, 0, 10, 0, true, true, calm)
check(fx2.stress == 0 and fx2.unhappy == 0 and fx2.boredom < 0, "musician over a window: same")
