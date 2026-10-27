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
-- body: ABC notes, a quarter note (500 ms at 120) each unless written longer
local function perf(body, header)
    local text = "X:1\nL:1/4\nQ:1/4=120\n" .. (header or "") .. "K:C\n" .. body
    return { text = text, bpm = 120, seed = 1, segments = { { fromChord = 1, chance = 0 } }, volume = 0.5 }
end

P.start("A", source(false), "Base.GuitarAcoustic", perf("C D E F"), 0, 1000)
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

P.start("A", source(false), "Base.GuitarAcoustic", perf("C D E F"), 750, 10000)
local v2 = log[2]
P.update(10000); check(#v2.notes == 0, "resume at 750 waits for chord 3")
P.update(10250); check(#v2.notes == 1, "chord 3 at +250 ms")

-- Review Focus 3: starting at or past the end
P.start("B", source(false), "Base.Violin", perf("C D"), 1000, 0)
P.update(0); P.update(5000)
check(#log[3].notes == 0 and P.position("B", 5000) == nil, "start at the end plays nothing and leaves no timeline")

P.stop("A"); check(v2.stopped >= 1 and P.position("A", 10300) == nil, "stop stops voices and forgets the musician")

-- setSegments keeps the position and never replays
events = {}
P.start("C", source(false), "Base.Trumpet", perf("C D E F"), 0, 0)
P.update(0); P.update(500); P.update(600)
P.setSegments("C", { { fromChord = 1, chance = 0 }, { fromChord = 3, chance = 0.5 } })
P.update(600)
local c = log[#log]
check(#c.notes == 2, "setSegments does not replay chords 1-2")
P.update(1000); check(#c.notes == 3, "chord 3 still plays after setSegments")

-- two musicians at once
P.start("D", source(false), "Base.Harmonica", perf("C C"), 0, 0)
P.start("E", source(false), "Base.Harmonica", perf("C C C"), 0, 0)
P.update(0); P.update(500); P.update(1000)
local d, e = log[#log - 1], log[#log]
check(#d.notes == 2 and #e.notes == 3, "two musicians play independently")

-- invisible musician: silent, no listener effects
events = {}
P.start("F", source(true), "Base.Trumpet", perf("C D"), 0, 0)
P.update(0); P.update(500)
check(#log[#log].notes == 0 and #events == 0, "invisible musician makes no sound and no events")
check(P.position("F", 500) == 500, "but the song keeps its place")

P.start("G", source(false), "Base.Trumpet", perf("C D E"), 0, 0)
check(P.currentChord("G") == 0, "no chord played yet")
P.update(0); P.update(500); check(P.currentChord("G") == 2, "current chord after two")
check(P.currentChord("nobody") == 0, "unknown musician: 0")

local gotDef
P.onEvent = function(id, e, pf, def) gotDef = def end
P.start("H", source(false), "Base.Violin", perf("C"), 0, 0)
P.update(0); check(gotDef and gotDef.key == "Violin", "onEvent gets the instrument")

-- drums: only the pieces in the kit sound, but every chord still counts for mood and XP (2026-10-27)
P.onEvent = function(id, e) table.insert(events, { id = id, chord = e.chord }) end
local before = #events
local drums = perf("C, D c") -- kick, snare, crash
drums.place = { x = 1, y = 1, z = 0, kit = { { piece = "snare", x = 1, y = 1, z = 0 } } }
P.start("D", source(false), "PlayIt.Drums", drums, 0, 50000)
local vd = log[#log]
P.update(50000); P.update(50500); P.update(51000)
check(#vd.notes == 1 and vd.notes[1].sound == "PlayIt_Drums_Snare", "only the snare note is voiced")
local drumEvents = 0
for i = before + 1, #events do if events[i].id == "D" then drumEvents = drumEvents + 1 end end
check(drumEvents == 3, "onEvent for every chord")
check(vd.release == 800, "drums ring out")
local busy = { x = 1, y = 1, z = 0, kit = { { piece = "snare", x = 1, y = 1, z = 0 } } }
check(P.busyAt("PlayIt.Drums", busy, "E"), "client sees the snare in use")
check(not P.busyAt("PlayIt.Drums", busy, "D"), "but not for its own drummer")
P.stop("D")
check(not P.busyAt("PlayIt.Drums", busy, "E"), "free again once stopped")

-- drum parts (%%MIDI channel 10): GM numbers pick the piece; the snare stand also holds the hi-hat
local gm = perf("C,, D,, ^F,, ^C,", "%%MIDI channel 10\n") -- 36 kick, 38 snare, 42 hi-hat, 49 crash
gm.place = { x = 5, y = 5, z = 0, kit = { { piece = "snare", x = 5, y = 5, z = 0 } } }
P.start("GM", source(false), "PlayIt.Drums", gm, 0, 60000)
local vg = log[#log]
P.update(60000); P.update(60500); P.update(61000); P.update(61500)
check(#vg.notes == 2 and vg.notes[1].sound == "PlayIt_Drums_Snare" and vg.notes[2].sound == "PlayIt_Drums_Hihat",
    "drum part: snare and hi-hat sound on the snare stand, kick and crash need their pieces")
P.stop("GM")

-- solo play skips the silence before the first note
P.start("R", source(false), "Base.Violin", perf("z4 C D"), 0, 70000)
local vr = log[#log]
P.update(70000); check(#vr.notes == 1, "leading rests skipped: the first note plays at once")

-- a tied note sounds for its whole length
P.start("T", source(false), "Base.Violin", perf("C2- C D"), 0, 80000)
local vt = log[#log]
P.update(80000); P.update(81000); P.update(81500)
check(#vt.notes == 2 and vt.notes[1].dur == 1500, "a tie lengthens the note instead of striking it again")
