require "PlayIt/Instruments"
local I = PlayIt.Instruments
local function near(a, b) return math.abs(a - b) < 1e-9 end

local guitar = { low = 40, high = 76, samples = {
    { midi = 40, tune = 0, sound = "G_E2" }, { midi = 50, tune = 0, sound = "G_D3" }, { midi = 64, tune = -20, sound = "G_E4" } } }
local s, r = I.resolve(guitar, 40, 0); check(s == "G_E2" and near(r, 1), "exact sample, ratio 1")
s, r = I.resolve(guitar, 28, 0); check(s == "G_E2" and near(r, 1), "below range folds up an octave")
s, r = I.resolve(guitar, 100, 0); check(s == "G_E4" and near(r, 2 ^ ((76 - 64) / 12 + 20 / 1200)), "above range folds down into range (100 -> 76)")
s, r = I.resolve(guitar, 40, 50); check(near(r, 2 ^ (50 / 1200)), "cents bend the ratio")
s, r = I.resolve(guitar, 47, 0); check(s == "G_D3" and near(r, 2 ^ (-3 / 12)), "nearest sample chosen")
s, r = I.resolve(guitar, 64, 0); check(near(r, 2 ^ (20 / 1200)), "sample tuning offset corrected")

local keys = { ["Base.GuitarAcoustic"] = "Guitar", ["Base.Violin"] = "Violin", ["Base.Trumpet"] = "Trumpet", ["Base.Harmonica"] = "Harmonica",
    ["Base.Flute"] = "Flute", ["Base.Saxophone"] = "Saxophone", ["Base.Keytar"] = "Keytar" }
for fullType, key in pairs(keys) do
    local def = I.defs[fullType]
    check(def ~= nil and def.key == key, fullType .. " defined")
    local inside = def and #def.samples >= 2
    for _, smp in ipairs(def and def.samples or {}) do
        inside = inside and smp.midi >= def.low - 6 and smp.midi <= def.high + 6
    end
    check(inside, fullType .. " has samples around its range")
end
check(I.defs["Base.Trumpet"].maxRadius == 45 and I.defs["Base.Harmonica"].maxRadius == 20, "radii")
check(I.defs["Base.GuitarAcoustic"].release == 400, "guitar strings ring on")
check(I.defs["Base.Flute"].maxRadius == 25 and I.defs["Base.Saxophone"].maxRadius == 40 and I.defs["Base.Keytar"].maxRadius == 35, "radii of the later three")
check(I.defs["Base.Keytar"].release == 80, "keytar: very short release (VCSL's advice for this patch)")
for _, ft in ipairs({ "Base.Violin", "Base.Trumpet", "Base.Harmonica", "Base.Flute", "Base.Saxophone" }) do
    check(I.defs[ft].release == 100, ft .. " stops quickly")
end

-- world instruments: pianos, organ and drums (2026-10-27)
require "PlayIt/Song"
local D = I.defs["PlayIt.Drums"]
check(I.isWorld("PlayIt.GrandPiano") and not I.isWorld("Base.Violin"), "world instruments are flagged")
check(I.defs["PlayIt.WesternPiano"].samples ~= I.defs["PlayIt.GrandPiano"].samples, "the two pianos sound different")
check(I.defs["PlayIt.ChurchOrgan"].maxRadius == 60 and D.maxRadius == 50, "organ and drums carry far")
-- song range in quarters (user, 2026-10-27): 48..60 -> kick <= 51, toms 51..54, snare 54..57, hi-hat 57..60,
-- crash on the very top note
check(I.drumPiece(48, 48, 60) == "kick" and I.drumPiece(51, 48, 60) == "kick", "lowest quarter: kick")
check(I.drumPiece(52, 48, 60) == "tom" and I.drumPiece(53, 48, 60) == "tom", "second quarter: toms")
check(I.drumPiece(54, 48, 60) == "snare" and I.drumPiece(56, 48, 60) == "snare", "third quarter: snare")
check(I.drumPiece(57, 48, 60) == "hihat" and I.drumPiece(59, 48, 60) == "hihat", "top quarter: hi-hat")
check(I.drumPiece(60, 48, 60) == "crash", "the song's highest note: crash")
check(I.drumPiece(55, 55, 55) == "snare", "drums: one pitch")
check(I.drumPiece(40, 48, 60) == "kick" and I.drumPiece(70, 48, 60) == "crash", "drums: outside range")
local full = { kick = true, snare = true, tom = true }
check(I.resolve(D, 48, 0, { low = 48, high = 60, kit = full }) == "PlayIt_Drums_Kick", "kick sound")
check(I.resolve(D, 48, 0, { low = 48, high = 60, kit = { snare = true } }) == nil, "missing piece is silent")
check(I.resolve(D, 58, 0, { low = 48, high = 60, kit = { snare = true } }) == "PlayIt_Drums_Hihat", "the snare brings the hi-hat")
check(I.resolve(D, 60, 0, { low = 48, high = 60, kit = { tom = true } }) == "PlayIt_Drums_Crash", "the tom brings the crash")
check(I.resolve(D, 58, 0, { low = 48, high = 60, kit = { kick = true, tom = true } }) == nil, "no snare, no hi-hat")
check(I.resolve(D, 60, 0, { low = 48, high = 60, kit = { kick = true, snare = true } }) == nil, "no tom, no crash")
-- toms: band 51..54, low tom below 52.5, high tom above
local sLow, rLow = I.resolve(D, 52, 0, { low = 48, high = 60, kit = full })
local sHigh, rHigh = I.resolve(D, 53, 0, { low = 48, high = 60, kit = full })
check(sLow == "PlayIt_Drums_TomLow" and sHigh == "PlayIt_Drums_TomHigh", "lower toms on the low tom, higher on the high tom")
local _, r1 = I.resolve(D, 52.6, 0, { low = 48, high = 60, kit = full })
local _, r2 = I.resolve(D, 53.4, 0, { low = 48, high = 60, kit = full })
check(r2 > r1 and rLow >= 2 ^ (-2 / 12) and rHigh <= 2 ^ (2 / 12), "toms follow pitch a little (within 2 semitones)")
check(I.songRange(PlayIt.Song.parse("", 120)) == nil, "drums: empty song")
local lo, hi = I.songRange(PlayIt.Song.parse("c3,e3-g4", 120)); check(lo == 48 and hi == 67, "song range")
local pitched = I.resolve(I.defs["PlayIt.GrandPiano"], 60, 0)
check(pitched == "PlayIt_Grand_C4", "pianos resolve like the hand-held instruments")
