-- Playable instruments: range, noise radius and samples, and which sample + pitch ratio plays a note.

require "PlayIt/Samples"

PlayIt = PlayIt or {}
PlayIt.Instruments = PlayIt.Instruments or {}
local Instruments = PlayIt.Instruments

local function def(key, low, high, maxRadius)
    return { key = key, low = low, high = high, maxRadius = maxRadius, samples = PlayIt.Samples[key] }
end

Instruments.defs = {
    ["Base.GuitarAcoustic"] = def("Guitar", 40, 76, 30),
    ["Base.Violin"] = def("Violin", 55, 93, 25),
    ["Base.Trumpet"] = def("Trumpet", 54, 82, 45),
    ["Base.Harmonica"] = def("Harmonica", 48, 84, 20),
}

-- sound name and pitch ratio for a note; notes outside the range move by whole octaves into it,
-- sample.tune (cents, measured when the sample was made) is corrected
function Instruments.resolve(instrument, midi, cents)
    while midi < instrument.low do midi = midi + 12 end
    while midi > instrument.high do midi = midi - 12 end
    local best
    for _, s in ipairs(instrument.samples) do
        if best == nil or math.abs(midi - s.midi) < math.abs(midi - best.midi) then best = s end
    end
    local ratio = 2 ^ ((midi - best.midi) / 12 + ((cents or 0) - (best.tune or 0)) / 1200)
    return best.sound, ratio
end
