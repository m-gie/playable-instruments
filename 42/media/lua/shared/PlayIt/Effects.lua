-- How far music carries and what it does to the people listening.

PlayIt = PlayIt or {}
PlayIt.Effects = PlayIt.Effects or {}
local Effects = PlayIt.Effects

Effects.NOISE_INTERVAL_MS = 2000
Effects.XP_PER_SECOND = 0.1
Effects.BOREDOM_BASE = 0.1 -- boredom (0-100) per real second at Music 0; a TV has no fixed rate to copy
Effects.ANNOY_STRESS = 0.01 -- stress is 0-1
Effects.ANNOY_UNHAPPY = 0.5 -- unhappiness is 0-100

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

-- stat changes for one played chord on a listener at `distance`; nil when out of earshot
function Effects.forListener(event, distance, earshot, musicianLevel, annoy)
    if distance > earshot then return nil end
    local blunder = event.blunder ~= nil and annoy
    return {
        boredom = -Effects.boredomPerSecond(musicianLevel) * event.dur / 1000,
        stress = blunder and Effects.ANNOY_STRESS or 0,
        unhappy = blunder and Effects.ANNOY_UNHAPPY or 0,
    }
end
