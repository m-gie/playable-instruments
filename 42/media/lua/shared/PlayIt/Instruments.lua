-- Playable instruments: range, noise radius and samples, and which sample + pitch ratio plays a note.
-- Hand-held ones are keyed by item full type; furniture (pianos, organ, drums) by a PlayIt.* pseudo full type.

require "PlayIt/Samples"

PlayIt = PlayIt or {}
PlayIt.Instruments = PlayIt.Instruments or {}
local Instruments = PlayIt.Instruments

-- release: fade-out (ms) after a note's length; strings ring on, bowed and blown notes stop when the player stops
local function def(key, low, high, maxRadius, release)
    return { key = key, low = low, high = high, maxRadius = maxRadius, release = release, samples = PlayIt.Samples[key] }
end

Instruments.defs = {
    ["Base.GuitarAcoustic"] = def("Guitar", 40, 76, 30, 400),
    ["Base.Violin"] = def("Violin", 55, 93, 25, 100),
    ["Base.Trumpet"] = def("Trumpet", 54, 82, 45, 100),
    ["Base.Harmonica"] = def("Harmonica", 48, 84, 20, 100),
    ["Base.Flute"] = def("Flute", 60, 93, 25, 100),
    ["Base.Saxophone"] = def("Saxophone", 49, 80, 40, 100),
    ["Base.Keytar"] = def("Keytar", 48, 91, 35, 80),
    ["PlayIt.WesternPiano"] = def("Upright", 36, 96, 35, 400),
    ["PlayIt.GrandPiano"] = def("Grand", 36, 96, 45, 400),
    ["PlayIt.ChurchOrgan"] = def("Organ", 36, 84, 60, 100),
    ["PlayIt.Drums"] = { key = "Drums", maxRadius = 50, release = 800, drums = true, samples = PlayIt.Samples.Drums },
}
for fullType, d in pairs(Instruments.defs) do
    d.world = fullType:sub(1, 7) == "PlayIt."
end

Instruments.TOM_SPREAD = 2 -- semitones a tom bends up or down with the note's pitch

function Instruments.isWorld(fullType)
    local d = Instruments.defs[fullType]
    return d ~= nil and d.world
end

-- the name players see: the item's name, or for furniture IGUI_PlayIt_Name_<key>
function Instruments.displayName(fullType)
    if Instruments.isWorld(fullType) then return getText("IGUI_PlayIt_Name_" .. Instruments.defs[fullType].key) end
    return getItemNameFromFullType(fullType)
end

-- lowest and highest note of a song as written (blunders aside); nil when it has no notes
function Instruments.songRange(song)
    local low, high
    for _, chord in ipairs(song.chords) do
        for _, m in ipairs(chord.notes) do
            if low == nil or m < low then low = m end
            if high == nil or m > high then high = m end
        end
    end
    return low, high
end

-- which drum a note hits: the song's lowest third the kick, the top third the snare, the rest the toms
function Instruments.drumPiece(midi, low, high)
    local third = (high - low) / 3
    if third == 0 or midi >= high - third then return "snare" end
    if midi <= low + third then return "kick" end
    return "tom"
end

-- ctx: { low, high, kit = { kick = true, ... } }; nil when the note's drum isn't in the kit
local function resolveDrum(instrument, midi, ctx)
    local piece = Instruments.drumPiece(midi, ctx.low, ctx.high)
    if not ctx.kit[piece] then return nil end
    if piece ~= "tom" then return instrument.samples[piece].sound, 1 end
    local third = (ctx.high - ctx.low) / 3
    local from, to = ctx.low + third, ctx.high - third
    local mid = (from + to) / 2
    local half = (to - from) / 2 -- > 0: a tom note lies strictly between from and to
    local sample = midi < mid and instrument.samples.tomLow or instrument.samples.tomHigh
    -- each tom bends across its half of the band: -TOM_SPREAD at the low edge, +TOM_SPREAD at the high edge
    local x = midi < mid and (midi - from) / half or (midi - mid) / half
    return sample.sound, 2 ^ ((x * 2 - 1) * Instruments.TOM_SPREAD / 12)
end

-- sound name and pitch ratio for a note; notes outside the range move by whole octaves into it,
-- sample.tune (cents, measured when the sample was made) is corrected. Drums need ctx (see resolveDrum).
function Instruments.resolve(instrument, midi, cents, ctx)
    if instrument.drums then return resolveDrum(instrument, midi, ctx) end
    while midi < instrument.low do midi = midi + 12 end
    while midi > instrument.high do midi = midi - 12 end
    local best
    for _, s in ipairs(instrument.samples) do
        if best == nil or math.abs(midi - s.midi) < math.abs(midi - best.midi) then best = s end
    end
    local ratio = 2 ^ ((midi - best.midi) / 12 + ((cents or 0) - (best.tune or 0)) / 1200)
    return best.sound, ratio
end
