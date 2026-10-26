require "PlayIt/SongFiles"
local F = PlayIt.SongFiles

check(F.sanitizeName("My Song!") == "My Song", "punctuation dropped")
check(F.sanitizeName("../x") == "x", "no path tricks")
check(F.sanitizeName("") == nil and F.sanitizeName("  !! ") == nil, "empty names rejected")
check(#F.sanitizeName(string.rep("a", 60)) == 40, "cut to 40 characters")
check(F.sanitizeName("  Ode - to_Joy  ") == "Ode - to_Joy", "trimmed, keeps spaces, dashes, underscores")

local content = F.encode("c,d,e\nf,g", 96)
check(content == "BPM: 96\nc,d,e\nf,g", "stored with a BPM header")
local text, bpm = F.decode(content)
check(text == "c,d,e\nf,g" and bpm == 96, "decoded back")
text, bpm = F.decode(F.encode("BPM: 60\nc", 140))
check(text == "c" and bpm == 140, "an old header in the text is replaced")
text, bpm = F.decode("c,d")
check(text == "c,d" and bpm == nil, "no header: bpm nil")

check(F.addToIndex({ "a", "b" }, "b")[3] == nil, "index has no duplicates")
check(F.addToIndex({ "b" }, "a")[1] == "a", "index sorted")

-- Final review #8
check(F.INDEX:find(F.DIR, 1, true) == nil, "index lives outside the songs folder")
local idx = F.addToIndex({ "Song" }, "song"); check(#idx == 1, "names are case-insensitive")
