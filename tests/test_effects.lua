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
local fx = E.forListener(chord, 5, 15, 0, true)
check(near(fx.boredom, -E.boredomPerSecond(0) * 2) and fx.stress == 0 and fx.unhappy == 0, "in earshot: boredom down for the chord's length")
check(E.forListener(chord, 16, 15, 0, true) == nil, "out of earshot: nothing")
local blunder = { dur = 500, blunder = "wrong" }
fx = E.forListener(blunder, 1, 15, 0, true)
check(fx.stress == E.ANNOY_STRESS and fx.unhappy == E.ANNOY_UNHAPPY, "a blunder annoys")
fx = E.forListener(blunder, 1, 15, 0, false)
check(fx.stress == 0 and fx.unhappy == 0, "annoyance off: blunders don't annoy")

-- Final review #2: what a 2 s server window of a song does
require "PlayIt/Timeline"; require "PlayIt/Song"
local tl = PlayIt.Timeline.build(PlayIt.Song.parse("c,d,e,f", 120), 1, { { fromChord = 1, chance = 0 } })
local dur, blunders = E.window(tl, 0, 1000)
check(dur == 1000 and blunders == 0, "chords starting in [0, 1000) counted")
dur = E.window(tl, 1000, 2000); check(dur == 1000, "next window")
local bad = PlayIt.Timeline.build(PlayIt.Song.parse("c,d", 120), 1, { { fromChord = 1, chance = 1 } })
local _, nb = E.window(bad, 0, 2000); check(nb == 2, "blunders counted")
local fx2 = E.forWindow(2000, 3, 4, 10, 0, true)
check(math.abs(fx2.boredom + E.boredomPerSecond(0) * 2) < 1e-9 and math.abs(fx2.stress - 3 * E.ANNOY_STRESS) < 1e-9 and fx2.unhappy == 3 * E.ANNOY_UNHAPPY, "a window of 2 s with 3 blunders")
check(E.forWindow(2000, 3, 11, 10, 0, true) == nil, "window: out of earshot")

-- the musician isn't annoyed by their own wrong notes, but still enjoys playing (user, 2026-10-26)
fx = E.forListener(blunder, 0, 15, 0, true, true)
check(fx.stress == 0 and fx.unhappy == 0 and fx.boredom < 0, "musician: no annoyance from own blunders, boredom still drops")
fx2 = E.forWindow(2000, 3, 0, 10, 0, true, true)
check(fx2.stress == 0 and fx2.unhappy == 0 and fx2.boredom < 0, "musician over a window: same")
