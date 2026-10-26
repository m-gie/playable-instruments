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
