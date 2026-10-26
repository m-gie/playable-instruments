require "PlayIt/Session"
local S = PlayIt.Session

local function perf(over)
    local p = { text = "c,d,e,f", bpm = 120, seed = 7, segments = { { fromChord = 1, chance = 0 } }, volume = 0.7, length = 2000, level = 3 }
    for k, v in pairs(over or {}) do p[k] = v end
    return p
end

local s = S.new()
s:start(1, perf(), 0, 1000)
check(s:positionAt(1, 1000) == 0 and s:positionAt(1, 1600) == 600, "position advances while playing")
s:pause(1, 600)
check(s:positionAt(1, 5000) == nil and s:pausedAt(1) == 600, "paused: no position, remembers where")
s:start(1, perf(), 600, 9000)
check(s:positionAt(1, 9100) == 700, "resume continues from the paused spot")
-- Review Focus 3
check(s:positionAt(1, 9000 + 1400) == nil, "nil once the song has ended")
s:stop(1); check(s:positionAt(1, 9100) == nil and s:get(1) == nil, "stop forgets")

-- Review Focus 4
s:start(2, perf(), 0, 0)
s:removePlayer(2); check(s:get(2) == nil, "removePlayer forgets the session")

s:start(3, perf(), 0, 0)
s:setSegments(3, { { fromChord = 1, chance = 0 }, { fromChord = 9, chance = 0.4 } })
check(#s:get(3).perf.segments == 2, "segments replaced")

-- listeners who already have the session
s:start(4, perf(), 0, 0)
check(not s:hasListener(4, 99), "nobody has it yet")
s:addListener(4, 99); check(s:hasListener(4, 99), "listener recorded")
s:start(4, perf(), 500, 100); check(not s:hasListener(4, 99), "a new start resends to everyone")

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
bad({ text = string.rep("c,", 16001) }, "text over 32000 bytes rejected")
check(S.validate(perf({ text = string.rep("c,", 15999) })), "text under 32000 bytes accepted")
-- Final review #3: a song received before its musician loaded starts late, at the right place
check(S.lateStart(1000, 5000, 6500, 10000) == 2500, "late start catches up by the wait")
check(S.lateStart(1000, 5000, 20000, 10000) == nil, "too late: song already over")
