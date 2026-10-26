require "PlayIt/Song"
local S = PlayIt.Song
local function notes(song, i) return table.concat(song.chords[i].notes, " ") end

local s = S.parse("c,d,e")
check(#s.chords == 3 and notes(s,1) == "48" and notes(s,2) == "50", "default octave 3")
check(s.bpm == 120, "default bpm 120")
check(S.readBpmHeader("BPM: 90\nc") == 90, "header read")
check(S.parse("BPM: 90\nc").bpm == 90 and #S.parse("BPM: 90\nc").chords == 1, "header used and dropped")
check(S.parse("BPM: 90\nc", 140).bpm == 140, "field wins over header")
check(S.readBpmHeader("bpm: 90\nc") == nil, "header is case-sensitive")
s = S.parse("c-e-g/2"); check(notes(s,1) == "48 52 55" and s.chords[1].beats == 0.5, "chord with /2")
s = S.parse("c#4,c,cn,c"); check(notes(s,1) == "61" and notes(s,2) == "61" and notes(s,3) == "60" and notes(s,4) == "60", "accidental and octave sticky, n clears")
s = S.parse("eb,e\nd"); check(notes(s,1) == "51" and notes(s,2) == "51" and notes(s,3) == "50", "sticky across lines, per letter")
s = S.parse("c,,d"); check(#s.chords == 3 and #s.chords[2].notes == 0, "empty chord is a rest")
s = S.parse("a4"); check(notes(s,1) == "69", "a4 = 69")
s = S.parse("c9,d9"); check(notes(s,1) == "120" and notes(s,2) == "110", "C may reach 9, others clamp to 8")
-- Review Focus 1
s = S.parse("C-E-G,\tD \r\nE\226\153\170"); check(notes(s,1) == "48 52 55" and notes(s,2) == "50" and notes(s,3) == "52", "crlf and junk")
-- Review Focus 2
check(S.parse("c", 0).bpm == 12 and S.parse("c", 99999).bpm == 600, "bpm clamped")
check(S.readBpmHeader("BPM: -5\nc") == 12, "negative header clamped")
for _, t in ipairs({"c/0", "c/", "c/abc", "c/-2"}) do check(S.parse(t).chords[1].beats == 1, "bad divisor " .. t .. " is 1") end
local long = string.rep("c,", 200)
s = S.parse(long .. "\nd"); check(#s.chords == 1 and notes(s,1) == "50" and #s.warnings == 1, "over-long line dropped with warning")
s = S.parse(string.rep("c\n", 400)); check(#s.chords == 300 and #s.warnings == 1, "lines capped at 300")
s = S.parse("c\n\n\nd"); check(#s.chords == 2, "blank lines add no rests")
s = S.parse("c/0.5,d/1.5"); check(s.chords[1].beats == 2 and math.abs(s.chords[2].beats - 1 / 1.5) < 1e-9, "decimal divisors (SS13 allows them)")
