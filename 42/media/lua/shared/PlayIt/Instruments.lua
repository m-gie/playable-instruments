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

-- the playing loop (AnimSets/player/actions/<anim>.xml; seated variants pick themselves) and, when the hands show
-- something other than the held item, the model scripts for the main and off hand
Instruments.anims = {
    ["Base.GuitarAcoustic"] = { anim = "PlayItGuitar" },
    ["Base.Violin"] = { anim = "PlayItViolin", models = { "Violin", "PlayIt_ViolinBow" } },
    ["Base.Trumpet"] = { anim = "PlayItTrumpet" },
    ["Base.Harmonica"] = { anim = "PlayItHarmonica" },
    ["Base.Flute"] = { anim = "PlayItFlute" },
    ["Base.Saxophone"] = { anim = "PlayItSaxophone" },
    ["Base.Keytar"] = { anim = "PlayItKeytar" },
    ["PlayIt.WesternPiano"] = { anim = "PlayItPiano" },
    ["PlayIt.GrandPiano"] = { anim = "PlayItPiano" },
    ["PlayIt.ChurchOrgan"] = { anim = "PlayItPiano" },
    ["PlayIt.Drums"] = { anim = "PlayItDrums", models = { "Drumstick", "PlayIt_DrumstickL" } },
}

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

-- which drum a note hits, by the song's range in quarters: kick, toms, snare, hi-hat; the song's highest note is a
-- crash (an accent: a whole band of crash would be unbearable)
function Instruments.drumPiece(midi, low, high)
    local quarter = (high - low) / 4
    if quarter == 0 then return "snare" end
    if midi >= high then return "crash" end
    if midi <= low + quarter then return "kick" end
    if midi < low + 2 * quarter then return "tom" end
    if midi < low + 3 * quarter then return "snare" end
    return "hihat"
end

-- General MIDI percussion (drum parts, %%MIDI channel 10) folded onto the kit: piece, and for toms which one
-- and a pitch step within its group. Anything not listed is a snare hit.
local GM = {}
for _, n in ipairs({ 35, 36 }) do GM[n] = { "kick" } end
for _, n in ipairs({ 31, 37, 38, 39, 40, 75, 76, 77 }) do GM[n] = { "snare" } end
for _, n in ipairs({ 42, 44, 46, 51, 53, 54, 56, 58, 59, 67, 68, 69, 70, 71, 72, 73, 74, 78, 79, 80, 81, 82 }) do
    GM[n] = { "hihat" }
end
for _, n in ipairs({ 49, 52, 55, 57 }) do GM[n] = { "crash" } end
-- toms: low floor .. high, then hand drums (bongos, congas, timbales); -1..1 places them within their sample
GM[41] = { "tom", "tomLow", -1 }; GM[43] = { "tom", "tomLow", 0 }; GM[45] = { "tom", "tomLow", 1 }
GM[47] = { "tom", "tomHigh", -1 }; GM[48] = { "tom", "tomHigh", 0 }; GM[50] = { "tom", "tomHigh", 1 }
GM[60] = { "tom", "tomHigh", 1 }; GM[61] = { "tom", "tomHigh", 0 }
GM[62] = { "tom", "tomHigh", 0 }; GM[63] = { "tom", "tomHigh", -1 }; GM[64] = { "tom", "tomLow", 1 }
GM[65] = { "tom", "tomHigh", 0 }; GM[66] = { "tom", "tomLow", 0 }

-- which drum a GM percussion number hits (kick, snare, tom, hihat, crash)
function Instruments.gmPiece(midi)
    return (GM[midi] or { "snare" })[1]
end

-- the furniture a sound needs: the snare's stand holds the hi-hat, the tom's the crash cymbal (vanilla sprites)
local PLAYED_ON = { kick = "kick", tom = "tom", snare = "snare", hihat = "snare", crash = "tom" }

-- ctx: { gm, low, high, kit = { kick = true, ... } }; nil when the note's drum isn't in the kit
local function resolveDrum(samples, midi, ctx)
    if ctx.gm then
        local g = GM[midi] or { "snare" }
        if not ctx.kit[PLAYED_ON[g[1]]] then return nil end
        if g[1] ~= "tom" then return samples[g[1]].sound, 1 end
        return samples[g[2]].sound, 2 ^ (g[3] * Instruments.TOM_SPREAD / 12)
    end
    local piece = Instruments.drumPiece(midi, ctx.low, ctx.high)
    if not ctx.kit[PLAYED_ON[piece]] then return nil end
    if piece ~= "tom" then return samples[piece].sound, 1 end
    local quarter = (ctx.high - ctx.low) / 4
    local from = ctx.low + quarter
    local half = quarter / 2 -- > 0: a tom note lies strictly between from and from + quarter
    local mid = from + half
    local sample = midi < mid and samples.tomLow or samples.tomHigh
    -- each tom bends across its half of the band: -TOM_SPREAD at the low edge, +TOM_SPREAD at the high edge
    local x = midi < mid and (midi - from) / half or (midi - mid) / half
    return sample.sound, 2 ^ ((x * 2 - 1) * Instruments.TOM_SPREAD / 12)
end

-- the tones a player can pick for an instrument ({ {id, key, release}, ... }; empty when it has only one sound)
function Instruments.tonesOf(fullType)
    local d = Instruments.defs[fullType]
    return d and d.tones or {}
end

-- the sample set and release of a tone; no tone, or one the instrument doesn't have, is its first (default) sound
function Instruments.samplesFor(instrument, toneId)
    for _, t in ipairs(instrument.tones or {}) do
        if t.id == toneId then return PlayIt.Samples[t.key], t.release or instrument.release end
    end
    return instrument.samples, instrument.release
end

-- sound name and pitch ratio for a note; notes outside the range move by whole octaves into it,
-- sample.tune (cents, measured when the sample was made) is corrected. Drums need ctx (see resolveDrum).
-- toneId: which of the instrument's sounds (nil = the default)
function Instruments.resolve(instrument, midi, cents, ctx, toneId)
    local samples = Instruments.samplesFor(instrument, toneId)
    if instrument.drums then return resolveDrum(samples, midi, ctx) end
    while midi < instrument.low do midi = midi + 12 end
    while midi > instrument.high do midi = midi - 12 end
    local best
    for _, s in ipairs(samples) do
        if best == nil or math.abs(midi - s.midi) < math.abs(midi - best.midi) then best = s end
    end
    local ratio = 2 ^ ((midi - best.midi) / 12 + ((cents or 0) - (best.tune or 0)) / 1200)
    return best.sound, ratio
end
