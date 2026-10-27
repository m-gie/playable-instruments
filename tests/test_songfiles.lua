require "PlayIt/SongFiles"
local F = PlayIt.SongFiles

check(F.sanitizeName("My Song!") == "My Song", "punctuation dropped")
check(F.sanitizeName("../x") == "x", "no path tricks")
check(F.sanitizeName("") == nil and F.sanitizeName("  !! ") == nil, "empty names rejected")
check(#F.sanitizeName(string.rep("a", 60)) == 40, "cut to 40 characters")
check(F.sanitizeName("  Ode - to_Joy  ") == "Ode - to_Joy", "trimmed, keeps spaces, dashes, underscores")

check(F.addToIndex({ "a", "b" }, "b")[3] == nil, "index has no duplicates")
check(F.addToIndex({ "b" }, "a")[1] == "a", "index sorted")

-- Final review #8
check(F.INDEX:find(F.DIR, 1, true) == nil, "index lives outside the songs folder")
local idx = F.addToIndex({ "Song" }, "song"); check(#idx == 1, "names are case-insensitive")
