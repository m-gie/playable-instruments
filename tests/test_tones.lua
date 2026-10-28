require "PlayIt/Tones"
local T = PlayIt.Tones

local m = T.parse("Base.GuitarElectric=jazz\ngarbage line\nBase.Violin=plucked\n")
check(m["Base.GuitarElectric"] == "jazz" and m["Base.Violin"] == "plucked", "parse")
local back = T.parse(T.format(m))
check(back["Base.GuitarElectric"] == "jazz" and back["Base.Violin"] == "plucked", "format round-trips")
check(T.valid("Base.GuitarElectric", "distorted") and not T.valid("Base.GuitarElectric", "plucked"), "only the instrument's tones")
check(not T.valid("Base.Trumpet", "anything"), "one-sound instruments have none")
-- the remembered choice, through an in-memory store
local stored = ""
T.io = { read = function() return stored end, write = function(text) stored = text end }
T.reset()
check(T.get("Base.GuitarElectric") == nil, "nothing remembered yet: nil (the default)")
T.set("Base.GuitarElectric", "jazz")
T.reset()
check(T.get("Base.GuitarElectric") == "jazz", "remembered across a reload")
stored = "Base.GuitarElectric=plucked\n"; T.reset()
check(T.get("Base.GuitarElectric") == nil, "a remembered tone the instrument doesn't have is ignored")

-- echo strength (2026-10-28): PlayIt/echo.txt, "fullType=0.40" lines
local echoStored = ""
T.echoIo = { read = function() return echoStored end, write = function(text) echoStored = text end }
T.reset()
check(T.getEcho("Base.Harmonica") == 0, "no echo remembered: 0")
T.setEcho("Base.Harmonica", 0.4)
T.reset()
check(math.abs(T.getEcho("Base.Harmonica") - 0.4) < 1e-9, "echo remembered across a reload")
check(echoStored:find("Base.Harmonica=0.40", 1, true) ~= nil, "stored as fullType=0.40")
echoStored = "Base.Harmonica=3\nBase.Flute=-1\nBase.Violin=abc\n"; T.reset()
check(T.getEcho("Base.Harmonica") == 1 and T.getEcho("Base.Flute") == 0 and T.getEcho("Base.Violin") == 0, "out of range clamps, junk is 0")
echoStored = "PlayIt.Drums=0.5\n"; T.reset()
check(T.getEcho("PlayIt.Drums") == 0, "drums: always 0")
