require "PlayIt/Playback"
local P = PlayIt.Playback

-- fake voices: record notes and stopAll per musician
local log = {}
P.newVoices = function(getPos, release)
    local v = { notes = {}, stopped = 0, release = release }
    function v:noteOn(sound, ratio, dur, now, gain) table.insert(self.notes, { sound = sound, dur = dur, now = now, gain = gain }) end
    function v:update() end
    function v:stopAll() self.stopped = self.stopped + 1 end
    table.insert(log, v)
    return v
end
local events = {}
P.onEvent = function(id, e) table.insert(events, { id = id, chord = e.chord }) end

local function source(silent)
    return { getPos = function() return 0, 0, 0 end, isSilent = function() return silent end }
end
local function perf(text) return { text = text, bpm = 120, seed = 1, segments = { { fromChord = 1, chance = 0 } }, volume = 0.5 } end

P.start("A", source(false), "Base.GuitarAcoustic", perf("c,d,e,f"), 0, 1000)
P.update(1000)
local v = log[1]
check(#v.notes == 1 and v.notes[1].gain == 0.5 and v.notes[1].dur == 500, "chord 1 at once, gain = volume, dur = beat")
check(v.release == 400, "voices get the instrument's release")
P.update(1499); check(#v.notes == 1, "chord 2 not before 500 ms")
P.update(1500); check(#v.notes == 2, "chord 2 at 500 ms")
check(#events == 2 and events[2].chord == 2 and events[2].id == "A", "onEvent per played chord")
check(P.position("A", 1750) == 750, "position")
check(P.pause("A", 1750) == 750 and v.stopped == 1, "pause returns the position and stops voices")
P.update(5000); check(#v.notes == 2 and P.position("A", 5000) == nil, "nothing plays after pause")

P.start("A", source(false), "Base.GuitarAcoustic", perf("c,d,e,f"), 750, 10000)
local v2 = log[2]
P.update(10000); check(#v2.notes == 0, "resume at 750 waits for chord 3")
P.update(10250); check(#v2.notes == 1, "chord 3 at +250 ms")

-- Review Focus 3: starting at or past the end
P.start("B", source(false), "Base.Violin", perf("c,d"), 1000, 0)
P.update(0); P.update(5000)
check(#log[3].notes == 0 and P.position("B", 5000) == nil, "start at the end plays nothing and leaves no timeline")

P.stop("A"); check(v2.stopped >= 1 and P.position("A", 10300) == nil, "stop stops voices and forgets the musician")

-- setSegments keeps the position and never replays
events = {}
P.start("C", source(false), "Base.Trumpet", perf("c,d,e,f"), 0, 0)
P.update(0); P.update(500); P.update(600)
P.setSegments("C", { { fromChord = 1, chance = 0 }, { fromChord = 3, chance = 0.5 } })
P.update(600)
local c = log[#log]
check(#c.notes == 2, "setSegments does not replay chords 1-2")
P.update(1000); check(#c.notes == 3, "chord 3 still plays after setSegments")

-- two musicians at once
P.start("D", source(false), "Base.Harmonica", perf("c,c"), 0, 0)
P.start("E", source(false), "Base.Harmonica", perf("c,c,c"), 0, 0)
P.update(0); P.update(500); P.update(1000)
local d, e = log[#log - 1], log[#log]
check(#d.notes == 2 and #e.notes == 3, "two musicians play independently")

-- invisible musician: silent, no listener effects
events = {}
P.start("F", source(true), "Base.Trumpet", perf("c,d"), 0, 0)
P.update(0); P.update(500)
check(#log[#log].notes == 0 and #events == 0, "invisible musician makes no sound and no events")
check(P.position("F", 500) == 500, "but the song keeps its place")
