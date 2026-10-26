require "PlayIt/Song"; require "PlayIt/Timeline"
local T, S = PlayIt.Timeline, PlayIt.Song
local function near(a, b, e) return math.abs(a - b) < (e or 1e-6) end
check(near(T.chance(0, 0.5, 0.0001, 0, 0, true), 0.5), "level 0 = p0")
check(near(T.chance(10, 0.5, 0.0001, 0, 0, true), 0.0001), "level 10 = p10")
-- falls slowly at first, fast at the end: p0 * (p10/p0)^((level/10)^2) (user, 2026-10-26: about 5% at level 5)
check(near(T.chance(5, 0.5, 0.0001, 0, 0, true), 0.5 * (0.0002 ^ 0.25)), "level 5 about 6%")
check(math.abs(T.chance(3, 0.5, 0.0001, 0, 0, true) - 0.232) < 0.001, "level 3 about 23%")
check(math.abs(T.chance(7, 0.5, 0.0001, 0, 0, true) - 0.0077) < 0.0002, "level 7 under 1%")
check(T.chance(10, 0.5, 0.0001, 0, 0, false) == 0, "skill off, sober: no blunders")
check(near(T.chance(10, 0.5, 0.0001, 100, 0, false), 0.3), "drunk blunders with skill off")
check(T.chance(0, 0.5, 0.0001, 100, 100, true) == 0.6, "capped at 0.6")
local a, b = T.rng(42, 7), T.rng(42, 7); check(a() == b() and a() == b(), "rng deterministic")
check(T.rng(42, 7)() ~= T.rng(42, 8)(), "rng differs per chord")

local song = S.parse("c,d,e,f", 120)
local clean = T.build(song, 1, {{fromChord = 1, chance = 0}})
check(#clean.events == 4 and clean.events[2].t == 500 and clean.length == 2000, "120 bpm = 500 ms per beat")
local x1 = T.build(song, 99, {{fromChord = 1, chance = 0.5}})
local x2 = T.build(song, 99, {{fromChord = 1, chance = 0.5}})
local same = true; for i = 1, 4 do same = same and x1.events[i].t == x2.events[i].t and x1.events[i].blunder == x2.events[i].blunder end
check(same, "same seed, same blunders and timing")
-- 200 chords over 40 lines (one 400-char line would be dropped by the 300-char line limit)
local all = T.build(S.parse(string.rep("c,c,c,c,c\n", 40), 120), 5, {{fromChord = 1, chance = 1}})
check(#all.events == 200, "200 chords built")
local kinds = {}; for _, e in ipairs(all.events) do if e.blunder then kinds[e.blunder] = true end end
check(kinds.wrong and kinds.sour and kinds.pause, "all three blunder kinds occur")
local seg = T.build(S.parse(string.rep("c,", 40), 120), 3, {{fromChord = 1, chance = 0}, {fromChord = 21, chance = 1}})
local early, late = 0, 0; for _, e in ipairs(seg.events) do if e.blunder then if e.chord < 21 then early = early + 1 else late = late + 1 end end end
check(early == 0 and late == 20, "chance segment applies from its chord")
local r = T.build(S.parse("c,,d", 120), 1, {{fromChord = 1, chance = 1}}); check(r.events[2].blunder == nil, "rests never blunder")
-- Review Focus 3
check(T.firstEventAt(clean, 0) == 1 and T.firstEventAt(clean, 501) == 3, "firstEventAt")
check(T.firstEventAt(clean, 2000) == nil and T.firstEventAt(clean, 999999) == nil, "past the end is nil")
