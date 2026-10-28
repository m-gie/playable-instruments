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
