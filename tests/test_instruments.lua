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
