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

-- B42.21 getFileWriter only writes ini/cfg/txt/log/json and returns nil for anything else
local files = {}
local ALLOWED = { ini = true, cfg = true, txt = true, log = true, json = true }
getFileWriter = function(path)
    if not ALLOWED[path:match("%.([^.]+)$") or ""] then return nil end
    return { write = function(_, s) files[path] = s end, close = function() end }
end
getFileReader = function(path)
    local s = files[path]
    if s == nil then return nil end
    local lines = {}
    for l in (s .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = l end
    if s:sub(-1) == "\n" then lines[#lines] = nil end
    local i = 0
    return { readLine = function() i = i + 1; return lines[i] end, close = function() end }
end

check(F.save("New Song", "X:1\nK:C\nCDE") == "New Song", "save works with the game's extension whitelist")
check(F.load("New Song") == "X:1\nK:C\nCDE", "saved song loads back")
check(F.list()[1] == "New Song", "saved song is in the index")
files["PlayIt/abc/Old Song.abc"] = "X:1\nK:C\nGAB"
check(F.load("Old Song") == "X:1\nK:C\nGAB", "songs saved earlier as .abc still load")
local saved, why = F.save("!!", "x")
check(saved == nil and why == "name", "bad name reported as such")
getFileWriter = function() return nil end
saved, why = F.save("Another", "x")
check(saved == nil and why == "write", "failed write reported instead of crashing")
