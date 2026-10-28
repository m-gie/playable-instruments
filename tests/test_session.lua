require "PlayIt/Session"
local S = PlayIt.Session

local function perf(over)
    local p = { text = "c,d,e,f", bpm = 120, seed = 7, segments = { { fromChord = 1, chance = 0 } }, volume = 0.7, length = 2000, level = 3 }
    for k, v in pairs(over or {}) do p[k] = v end
    return p
end

local s = S.new()
s:start(1, perf(), 1000) -- origin: server ms of the part's timeline 0
check(s:positionAt(1, 1000) == 0 and s:positionAt(1, 1600) == 600, "position advances while playing")
s:pause(1, 600)
check(s:positionAt(1, 5000) == nil and s:pausedAt(1) == 600, "paused: no position, remembers where")
s:start(1, perf(), 9000 - 600)
check(s:positionAt(1, 9100) == 700, "resume continues from the paused spot")
-- Review Focus 3
check(s:positionAt(1, 9000 + 1400) == nil, "nil once the song has ended")
s:stop(1); check(s:positionAt(1, 9100) == nil and s:get(1) == nil, "stop forgets")

-- Review Focus 4
s:start(2, perf(), 0)
s:removePlayer(2); check(s:get(2) == nil, "removePlayer forgets the session")

s:start(3, perf(), 0)
s:setSegments(3, { { fromChord = 1, chance = 0 }, { fromChord = 9, chance = 0.4 } })
check(#s:get(3).perf.segments == 2, "segments replaced")

-- listeners who already have the session
s:start(4, perf(), 0)
check(not s:hasListener(4, 99), "nobody has it yet")
s:addListener(4, 99); check(s:hasListener(4, 99), "listener recorded")
s:start(4, perf(), -400); check(not s:hasListener(4, 99), "a new start resends to everyone")

local ok = S.validate(perf()); check(ok, "valid perf")
local function bad(over, what) local good = S.validate(perf(over)); check(not good, what) end
bad({ text = string.rep("c", 100000) }, "huge text rejected")
bad({ volume = 5 }, "volume above 1 rejected")
bad({ seed = 1.5 }, "non-integer seed rejected")
bad({ text = 42 }, "text must be a string")
bad({ level = 11 }, "level above 10 rejected")
bad({ length = -1 }, "negative length rejected")
local many = {}; for i = 1, 65 do many[i] = { fromChord = i, chance = 0 } end
bad({ segments = many }, "more than 64 segments rejected")
bad({ segments = { { fromChord = 1, chance = 2 } } }, "chance above 1 rejected")

-- Final review #1: network strings are limited to 32767 bytes
bad({ text = string.rep("C ", 15001) }, "text over 30000 bytes rejected")
check(S.validate(perf({ text = string.rep("C ", 14999) })), "text under 30000 bytes accepted")
-- Final review #3: a song received before its musician loaded starts late, at the right place (2026-10-28: by origin)
check(S.posAt(5000, 7500, 10000) == 2500, "late start: position from the origin")
check(S.posAt(5000, 4000, 10000) == -1000, "before the origin: not yet (negative)")
check(S.posAt(5000, 20000, 10000) == nil, "too late: song already over")

-- world instruments: the place travels with the performance (2026-10-27)
check(S.validate(perf({ place = { x = 1, y = 2, z = 0 } })), "a piano place is valid")
local ok, why = S.validate(perf({ place = { x = 1.5, y = 2, z = 0 } })); check(not ok and why == "place", "place needs whole tiles")
ok, why = S.validate(perf({ place = { x = 1, y = 2, z = 0, kit = { { piece = "cowbell", x = 1, y = 2, z = 0 } } } }))
check(not ok and why == "place", "unknown drum piece")
local four = {}
for i = 1, 4 do four[i] = { piece = "kick", x = i, y = 2, z = 0 } end
ok, why = S.validate(perf({ place = { x = 1, y = 2, z = 0, kit = four } })); check(not ok and why == "place", "at most three drum pieces")
ok, why = S.validate(perf({ place = { x = 1, y = 2, z = 0, kit = { { piece = "kick", x = 1, y = 2, z = 0 }, { piece = "kick", x = 2, y = 2, z = 0 } } } }))
check(not ok and why == "place", "one of each drum piece")

local b = S.new()
b:start(10, perf({ place = { x = 5, y = 5, z = 0 } }), 0); b:get(10).fullType = "PlayIt.WesternPiano"
check(b:busyAt("PlayIt.WesternPiano", { x = 6, y = 6, z = 0 }, 11) == 10, "someone plays a piano right there")
check(b:busyAt("PlayIt.WesternPiano", { x = 5, y = 5, z = 0 }, 10) == nil, "not busy for the musician themself")
check(b:busyAt("PlayIt.WesternPiano", { x = 15, y = 5, z = 0 }, 11) == nil, "another piano further away")
check(b:busyAt("PlayIt.GrandPiano", { x = 5, y = 5, z = 0 }, 11) == nil, "a different instrument")
b:pause(10, 100)
check(b:busyAt("PlayIt.WesternPiano", { x = 5, y = 5, z = 0 }, 11) == nil, "paused players don't lock the instrument")
local kitA = { { piece = "kick", x = 1, y = 1, z = 0 }, { piece = "snare", x = 2, y = 1, z = 0 } }
b:start(12, perf({ place = { x = 1, y = 1, z = 0, kit = kitA } }), 0); b:get(12).fullType = "PlayIt.Drums"
check(b:busyAt("PlayIt.Drums", { x = 2, y = 1, z = 0, kit = { { piece = "snare", x = 2, y = 1, z = 0 } } }, 13) == 12, "a shared drum is busy")
check(b:busyAt("PlayIt.Drums", { x = 3, y = 1, z = 0, kit = { { piece = "tom", x = 3, y = 1, z = 0 } } }, 13) == nil, "a drum nobody uses is free")

-- rate limit on start/segments: a burst, then one per RATE_MS
local r = S.new()
local okCount = 0
for i = 1, 20 do if r:allow(5, 1000) then okCount = okCount + 1 end end
check(okCount == S.RATE_BURST, "a burst of RATE_BURST messages passes, the rest are dropped")
check(not r:allow(5, 1000 + S.RATE_MS - 1), "nothing more before RATE_MS")
check(r:allow(5, 1000 + S.RATE_MS), "one more after RATE_MS")
check(not r:allow(5, 1000 + S.RATE_MS), "and only one")
check(r:allow(6, 1000), "players are limited separately")
local spam = 0
for t = 0, 60000, 100 do if r:allow(7, t) then spam = spam + 1 end end
check(spam <= S.RATE_BURST + 60000 / S.RATE_MS + 1, "ten messages a second for a minute: about one per RATE_MS passes")
local q = S.new()
check(q:allow(8, 0) and q:allow(8, 500) and q:allow(8, 900), "play, pause, play again quickly passes")

-- play along (2026-10-28): where a part starts in its own timeline travels with it
check(S.validate(perf({ fromMs = 4000 })), "fromMs accepted")
bad({ fromMs = -1 }, "negative fromMs rejected")
bad({ fromMs = "x" }, "fromMs must be a number")
check(S.validStart({ along = 12, wait = true, posMs = 0 }), "along a player id")
check(S.validStart({ posMs = 500 }), "plain start")
check(not S.validStart({ along = 1.5, posMs = 0 }), "along must be a whole id")
check(not S.validStart({ wait = "yes", posMs = 0 }), "wait must be a boolean")
check(not S.validStart({ resume = 1, posMs = 0 }), "resume must be a boolean")
check(not S.validStart({ posMs = -5 }), "posMs not negative")

-- tones (2026-10-28): only a tone the instrument has
PlayIt.Instruments.defs["Test.Toned"] = { low = 40, high = 80, tones = { { id = "a", key = "Guitar" }, { id = "b", key = "Guitar" } } }
check(S.validate(perf({ tone = "b" }), "Test.Toned"), "a known tone")
check(S.validate(perf(), "Test.Toned"), "no tone: the default")
check(not S.validate(perf({ tone = "zz" }), "Test.Toned"), "an unknown tone is rejected")
check(not S.validate(perf({ tone = "a" }), "Base.Flute"), "a tone on an instrument without tones is rejected")
check(not S.validate(perf({ tone = 5 }), "Test.Toned"), "tone must be a string")
