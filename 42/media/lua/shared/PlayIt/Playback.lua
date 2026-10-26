-- Plays performances locally: every client (the musician's included) builds the same timeline from the
-- performance and plays its due notes each tick on the musician's voices.

require "PlayIt/Song"
require "PlayIt/Timeline"
require "PlayIt/Instruments"
require "PlayIt/Voices"

PlayIt = PlayIt or {}
PlayIt.Playback = PlayIt.Playback or {}
local Playback = PlayIt.Playback

Playback.TAIL_MS = 1000 -- keep updating voices this long after the last note so releases finish
Playback.onEvent = nil -- function(musicianId, event, perf), for every chord played audibly

local active = {}

function Playback.newVoices(getPos, release)
    return PlayIt.Voices.new(getPos, nil, nil, release)
end

local function build(perf)
    return PlayIt.Timeline.build(PlayIt.Song.parse(perf.text, perf.bpm), perf.seed, perf.segments)
end

-- source: { getPos() -> x, y, z, isSilent() -> true while the musician must not be heard (invisible) }
-- perf: { text, bpm, seed, segments, volume (0-1) }; posMs: where in the song to begin
function Playback.start(id, source, fullType, perf, posMs, nowMs)
    Playback.stop(id)
    local def = PlayIt.Instruments.defs[fullType]
    if def == nil then return end
    local timeline = build(perf)
    active[id] = {
        source = source, def = def, perf = perf, timeline = timeline,
        origin = nowMs - posMs, lastChord = 0,
        nextIndex = PlayIt.Timeline.firstEventAt(timeline, posMs),
        voices = Playback.newVoices(source.getPos, def.release),
    }
end

local function play(id, p, event, nowMs)
    if p.source.isSilent() then return end
    for _, note in ipairs(event.notes) do
        local sound, ratio = PlayIt.Instruments.resolve(p.def, note.midi, note.cents)
        p.voices:noteOn(sound, ratio, event.dur, nowMs, p.perf.volume)
    end
    if Playback.onEvent then Playback.onEvent(id, event, p.perf) end
end

function Playback.update(nowMs)
    for id, p in pairs(active) do
        local pos = nowMs - p.origin
        local events = p.timeline.events
        while p.nextIndex and events[p.nextIndex] and events[p.nextIndex].t <= pos do
            local event = events[p.nextIndex]
            play(id, p, event, nowMs)
            p.lastChord = event.chord
            p.nextIndex = p.nextIndex + 1
        end
        p.voices:update(nowMs)
        if pos >= p.timeline.length + Playback.TAIL_MS then
            p.voices:stopAll()
            active[id] = nil
        end
    end
end

-- nil when the musician isn't playing or the song is over
function Playback.position(id, nowMs)
    local p = active[id]
    if p == nil then return nil end
    local pos = nowMs - p.origin
    if pos >= p.timeline.length then return nil end
    return pos
end

-- index of the last chord played (0 before the first)
function Playback.currentChord(id)
    local p = active[id]
    return p and p.lastChord or 0
end

function Playback.pause(id, nowMs)
    local pos = Playback.position(id, nowMs)
    Playback.stop(id)
    return pos
end

function Playback.stop(id)
    local p = active[id]
    if p == nil then return end
    p.voices:stopAll()
    active[id] = nil
end

-- new blunder chances from some chord on; keeps the place and never replays a chord
function Playback.setSegments(id, segments)
    local p = active[id]
    if p == nil then return end
    p.perf.segments = segments
    p.timeline = build(p.perf)
    p.nextIndex = nil
    for i, e in ipairs(p.timeline.events) do
        if e.chord > p.lastChord then p.nextIndex = i; break end
    end
end
