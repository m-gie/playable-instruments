require "PlayIt/Song"
local S = PlayIt.Song
local function notes(song, i) return table.concat(song.chords[i].notes, " ") end

local s = S.parse("c,d,e")
check(#s.chords == 3 and notes(s,1) == "48" and notes(s,2) == "50", "default octave 3")
check(s.bpm == 120, "default bpm 120")
check(S.readBpmHeader("BPM: 90\nc") == 90, "header read")
check(S.parse("BPM: 90\nc").bpm == 90 and #S.parse("BPM: 90\nc").chords == 1, "header used and dropped")
check(S.parse("BPM: 90\nc", 140).bpm == 140, "field wins over header")
check(S.readBpmHeader("bpm: 90\nc") == 90, "header is not case-sensitive (pasted text, final review #7)")
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

-- Final review #5: divisors clamped to [1/16, 64]
check(S.parse("c/0.0001").chords[1].beats == 16, "tiny divisor clamped: at most 16 beats")
check(S.parse("c/1e9").chords[1].beats == 1 / 64, "huge divisor clamped: at least 1/64 beat")
-- Final review #7: header variants
check(S.readBpmHeader("bpm: 200\nc") == 200, "lowercase header")
check(S.readBpmHeader("  BPM:200\nc") == 200, "spaces and no space after the colon")
check(S.readBpmHeader("\239\187\191BPM: 90\nc") == 90, "BOM before the header")
s = S.parse("bpm: 200\nc"); check(#s.chords == 1 and notes(s, 1) == "48" and s.bpm == 200, "lowercase header is not played as notes")
-- Final review #1: compact form sent over the network
local messy = "BPM: 90\r\n" .. string.rep("C-E-G, \t D \226\153\170\r\n", 3) .. "\n\n" .. string.rep("x", 400) .. "\nf"
local compact = S.compact(messy)
check(compact == "BPM: 90\nc-e-g,d\nc-e-g,d\nc-e-g,d\nf", "compact keeps only what plays")
local a, b = S.parse(messy, 90), S.parse(compact, 90)
local same = #a.chords == #b.chords
for i = 1, #a.chords do same = same and table.concat(a.chords[i].notes, " ") == table.concat(b.chords[i].notes, " ") and a.chords[i].beats == b.chords[i].beats end
check(same, "compact text plays exactly like the original")
check(S.compact(string.rep("c\n", 400)):gsub("[^\n]", ""):len() == 299, "compact keeps only the first 300 lines")
