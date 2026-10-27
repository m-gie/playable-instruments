require "PlayIt/Furniture"
local F = PlayIt.Furniture

check(F.classify("Piano", "Western") == "PlayIt.WesternPiano", "western piano")
check(F.classify("Grand Piano", "Black") == "PlayIt.GrandPiano", "classify: any tile counts") -- every tile has the same names
check(F.classify("Organ", "Church") == "PlayIt.ChurchOrgan", "church organ")
local ft, piece = F.classify("Drum", "Snare"); check(ft == "PlayIt.Drums" and piece == "snare", "snare")
check(F.classify("Stool", "Piano") == nil and F.classify("Metal Drum", nil) == nil, "stools and barrels aren't instruments")

check(F.inReach(10.5, 11.9, 0, 10, 10, 0), "standing next to the tile")
check(not F.inReach(10.5, 13.0, 0, 10, 10, 0), "two tiles away")
check(not F.inReach(10.5, 10.5, 1, 10, 10, 0), "reach: other floor")

local pianoAt = function(x, y, z) return (x == 10 and y == 10 and z == 0) and { { fullType = "PlayIt.WesternPiano" } } or {} end
local here = { px = 10.5, py = 11.5, pz = 0, hasStick = false, look = pianoAt }
check(F.check("PlayIt.WesternPiano", { x = 10, y = 10, z = 0 }, here), "may play the piano")
local gone = { px = 10.5, py = 11.5, pz = 0, look = function() return {} end }
local ok, why = F.check("PlayIt.WesternPiano", { x = 10, y = 10, z = 0 }, gone); check(not ok and why == "Gone", "check: instrument gone")
local far = { px = 10.5, py = 14, pz = 0, look = pianoAt }
ok, why = F.check("PlayIt.WesternPiano", { x = 10, y = 10, z = 0 }, far); check(not ok and why == "TooFar", "too far")

local kit = F.kitAround({ { x = 10, y = 10, z = 0, piece = "kick" }, { x = 11, y = 10, z = 0, piece = "snare" },
    { x = 20, y = 20, z = 0, piece = "tom" } }, 10.5, 11.2, 0)
local set = F.kitSet(kit); check(set.kick and set.snare and not set.tom, "kit = pieces in reach")
local drumsAt = function(x, y) return (x == 10 or x == 11) and y == 10 and { { fullType = "PlayIt.Drums" } } or {} end
ok, why = F.check("PlayIt.Drums", { x = 10, y = 10, z = 0, kit = kit }, { px = 10.5, py = 11.2, pz = 0, hasStick = false, look = drumsAt })
check(not ok and why == "NoSticks", "drums need a drumstick")
check(F.check("PlayIt.Drums", { x = 10, y = 10, z = 0, kit = kit }, { px = 11.5, py = 11.2, pz = 0, hasStick = true, look = drumsAt }), "near one piece is enough")
ok, why = F.check("PlayIt.Drums", { x = 10, y = 10, z = 0, kit = kit }, { px = 10.5, py = 11.2, pz = 0, hasStick = true, look = function() return {} end })
check(not ok and why == "Gone", "every kit piece gone")
local two = F.kitAround({ { x = 10, y = 10, z = 0, piece = "kick" }, { x = 10, y = 11, z = 0, piece = "kick" } }, 10.5, 11.6, 0)
check(#two == 1 and two[1].y == 11, "one piece of each kind, the nearest")

-- final review: reach counts from any tile of the instrument, not only the clicked one
local grandAt = function(x, y, z)
    return (z == 0 and x >= 10 and x <= 11 and y >= 10 and y <= 12) and { { fullType = "PlayIt.GrandPiano" } } or {}
end
check(F.check("PlayIt.GrandPiano", { x = 10, y = 12, z = 0 }, { px = 10.5, py = 9.5, pz = 0, look = grandAt }),
    "clicked the tail, playing at the keyboard end")
local tailGone = function(x, y, z) if x == 10 and y == 12 then return {} end return grandAt(x, y, z) end
check(F.check("PlayIt.GrandPiano", { x = 10, y = 12, z = 0 }, { px = 10.5, py = 9.5, pz = 0, look = tailGone }),
    "the clicked tile was removed, the rest of the piano still stands")
ok, why = F.check("PlayIt.GrandPiano", { x = 10, y = 12, z = 0 }, { px = 10.5, py = 6, pz = 0, look = grandAt })
check(not ok and why == "TooFar", "far from every tile of the piano")

-- final review: the organ's upper row stands on the floor above and is not an instrument
check(F.isUpperTile("2,0,1") and not F.isUpperTile("0,0") and not F.isUpperTile("1,2,0") and not F.isUpperTile(nil),
    "upper-row tiles are recognised by SpriteGridPos")

-- drums put a drumstick in the main hand when playing starts (user, 2026-10-27)
check(F.needsStickInHand("PlayIt.Drums", nil), "empty hand: equip a stick")
check(F.needsStickInHand("PlayIt.Drums", "Base.BaseballBat"), "holding something else: swap to a stick")
check(not F.needsStickInHand("PlayIt.Drums", "Base.Drumstick"), "already holding a stick")
check(not F.needsStickInHand("PlayIt.GrandPiano", nil), "pianos need no stick")
