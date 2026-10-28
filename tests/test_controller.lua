require "PlayIt/Controller"
local C = PlayIt.Controller

local calls, pausePos, livePos, liveChord, serverNow = {}, 750, 0, 0, 0
local net = {
    start = function(_, fullType, perf, pos, opts) table.insert(calls, { "start", fullType = fullType, perf = perf, pos = pos, opts = opts }) end,
    startLocal = function(_, fullType, perf, pos) table.insert(calls, { "startLocal", perf = perf, pos = pos }) end,
    stopLocal = function() table.insert(calls, { "stopLocal" }) end,
    unalong = function() table.insert(calls, { "unalong" }) end,
    pause = function() table.insert(calls, { "pause" }); return pausePos end,
    stop = function() table.insert(calls, { "stop" }) end,
    segments = function(_, segs) table.insert(calls, { "segments", segs = segs }) end,
}
local seeds = 100
local deps = {
    net = net,
    newSeed = function() seeds = seeds + 1; return seeds end,
    position = function() return livePos end,
    currentChord = function() return liveChord end,
    level = function() return 3 end,
    config = function() return { skillOn = true, p0 = 0.5, p10 = 0.0001 } end,
    mood = function() return 0, 0 end,
    serverNow = function() return serverNow end,
}
local c = C.new("player", deps)
local last = function() return calls[#calls] end
-- a quarter note (500 ms at 120) per written note
local function abc(body) return "X:1\nL:1/4\nK:C\n" .. body end

c:play(abc("C D E F"), 120, 0.7, "Base.Violin")
local s1 = last()
check(s1[1] == "start" and s1.pos == 0 and s1.perf.seed == 101 and s1.perf.length == 2000, "fresh start at 0 with a new seed and the song length")
check(s1.perf.level == 3 and s1.perf.volume == 0.7 and s1.perf.bpm == 120, "perf carries level, volume, bpm")
check(math.abs(s1.perf.segments[1].chance - 0.5 * (0.0001 / 0.5) ^ 0.09) < 1e-9 and s1.perf.segments[1].fromChord == 1, "first segment = current chance")
check(c:isPlaying() and not c:isPaused() and c:instrument() == "Base.Violin", "playing")

c:pause()
check(c:isPaused() and not c:isPlaying() and c:positionMs() == 750, "pause remembers the position")
c:play(abc("C D E F"), 120, 0.3, "Base.Violin")
check(last().pos == 750 and last().perf.seed == 101 and last().perf.volume == 0.3, "resume: same seed, same place, new volume")

c:pause(); c:play(abc("C D E"), 120, 0.3, "Base.Violin")
check(last().pos == 0 and last().perf.seed == 102, "changed text restarts with a new seed")
c:pause(); c:play(abc("C D E"), 90, 0.3, "Base.Violin")
check(last().pos == 0, "changed bpm restarts")

pausePos = nil -- the song had already ended when paused
c:pause(); c:play(abc("C D E"), 90, 0.3, "Base.Violin")
check(last().pos == 0, "after the song ended, play starts over")

c:stop(); check(last()[1] == "stop" and not c:isPlaying() and not c:isPaused(), "stop")
c:play(abc("C D E"), 90, 0.3, "Base.Violin"); check(last().pos == 0, "after stop, play starts over")

-- blunder chance follows drunk/panic mid-song
liveChord = 10
deps.mood = function() return 100, 0 end
c:updateChance()
check(last()[1] == "segments" and last().segs[2].fromChord == 14, "new segment 4 chords ahead")
local n = #calls; c:updateChance(); check(#calls == n, "no update when the chance hasn't changed")

-- the song ends by itself
livePos = nil; c:tick(); check(not c:isPlaying() and not c:isPaused(), "song end stops the controller")

c:play(abc("C D"), 120, 0.4, "Base.Trumpet"); check(c:volume() == 0.4, "controller remembers the volume")

-- Final review #1: the compact song is what gets sent; too long refuses
c:stop()
c:play("X:1 % tune\r\nK:C\r\n[CE] D  \r\n\r\n", 90, 0.5, "Base.Violin"); check(last().perf.text == "X:1\nK:C\n[CE] D", "compact text sent")
local before = #calls
local ok, why = c:play(abc(string.rep("[CEG]/2 ", 4000)), 90, 0.5, "Base.Violin")
check(ok == false and why == "TooLong" and #calls == before, "a part too long to send is refused, nothing sent")
ok, why = c:play(abc(string.rep("C", 10001)), 90, 0.5, "Base.Violin")
check(ok == false and why == "TooLong" and #calls == before, "a part with too many notes is refused, nothing sent")

-- Review Focus 5: world instruments resume only where they were paused
pausePos = 750 -- paused mid-song again
local c2 = C.new("player2", deps)
c2:play(abc("C D"), 120, 0.7, "PlayIt.WesternPiano", { x = 1, y = 1, z = 0 }); c2:pause()
c2:play(abc("C D"), 120, 0.7, "PlayIt.WesternPiano", { x = 9, y = 9, z = 0 })
check(last().pos == 0 and last().perf.place.x == 9, "resume needs the same place")
c2:pause()
c2:play(abc("C D"), 120, 0.7, "PlayIt.WesternPiano", { x = 9, y = 9, z = 0 })
check(last().pos == pausePos and c2:place().x == 9, "same place resumes")

check(last().opts == nil, "solo play doesn't wait for the server")

-- play along (2026-10-28)
local function count(kind) local n = 0 for _, x in ipairs(calls) do if x[1] == kind then n = n + 1 end end return n end
livePos = nil -- no local playback until the server says go
local a = C.new("player3", deps)
a:playAlong(7, "Ann")
check(a:alongStatus() == "PlayingAlongReady", "chosen, not playing yet")
local locals = count("startLocal")
a:play(abc("z4 C D E F"), 120, 0.5, "Base.Violin")
check(last()[1] == "start" and last().opts.wait == true and last().opts.along == 7, "play along waits for the server")
check(count("startLocal") == locals and a:isPlaying(), "nothing sounds before go, but the action keeps running")
a:tick(); check(a:isPlaying(), "waiting is not a finished song")
local key, arg = a:alongStatus(); check(key == "WaitingFor" and arg == "Ann", "waiting for Ann")
serverNow = 1000
a:onGo(4000, 2000, 90, 4000)
check(last()[1] == "startLocal" and last().pos == -3000 and last().perf.fromMs == 2000 and last().perf.bpm == 90, "go starts local playback on the server clock")
key, arg = a:alongStatus(); check(key == "StartingIn" and arg == 3, "count-in 3")
serverNow = 3500; key, arg = a:alongStatus(); check(key == "StartingIn" and arg == 1, "count-in 1")
serverNow = 4100; key, arg = a:alongStatus(); check(key == "PlayingAlong" and arg == "Ann", "playing along")
a:onBand({ "Ann", "Me" }, 90); check(a:bandBpm() == 90, "the band's tempo")
livePos = 500
a:pause(); check(last()[1] == "pause", "pause leaves the band")
a:play(abc("z4 C D E F"), 120, 0.5, "Base.Violin")
check(last().opts.wait and last().opts.resume == true, "resume goes back into the band")
a:onAlongEnded("TooFarFromBand")
check(last()[1] == "stopLocal" and not a:isPlaying() and a:alongStatus() == "TooFarFromBand", "taken out of the band")

local w = C.new("player4", deps)
w:playAlong(8, "Bob"); w:play(abc("C D"), 120, 0.5, "Base.Violin"); w:stop()
check(last()[1] == "unalong" and w:alongStatus() == nil, "stop while waiting gives up the wait")

local st = C.new("player5", deps)
st:onWaiters({ "Cid" })
key, arg = st:alongStatus(); check(key == "Waiters" and arg == "Cid", "someone waits for us")
st:play(abc("C D"), 120, 0.5, "Base.Violin")
check(last().opts.wait == true and last().opts.along == nil, "with someone waiting, Play waits for the count-in")

-- final review (2026-10-28)
-- #1 pausing during the count-in resumes from the start, never from a negative spot
local ci = C.new("player6", deps)
ci:playAlong(9, "Dee"); ci:play(abc("C D"), 120, 0.5, "Base.Violin")
serverNow = 0; ci:onGo(3000, nil, 120, 3000)
pausePos = -1200; livePos = -1200
ci:pause(); check(ci:positionMs() == 0, "paused before the first beat: resume from 0")
ci:play(abc("C D"), 120, 0.5, "Base.Violin"); check(last().pos == 0, "resume sends a valid position")
-- #2 a start the server never answers doesn't wait forever; an acknowledged wait does
local na = C.new("player7", deps)
serverNow = 10000
na:playAlong(9, "Dee"); na:play(abc("C D"), 120, 0.5, "Base.Violin")
serverNow = 10000 + C.PENDING_TIMEOUT_MS - 1; na:tick(); check(na:isPlaying(), "still waiting for an answer")
serverNow = 10000 + C.PENDING_TIMEOUT_MS; na:tick()
check(not na:isPlaying() and na:alongStatus() == "NoAnswer", "no answer: gives up")
local ack = C.new("player8", deps)
ack:playAlong(9, "Dee"); ack:play(abc("C D"), 120, 0.5, "Base.Violin"); ack:onWaiting()
serverNow = serverNow + C.PENDING_TIMEOUT_MS * 10; ack:tick(); check(ack:isPlaying(), "an acknowledged wait lasts")
-- #6 a band song ending by itself unlocks the tempo and clears the member list
local en = C.new("player9", deps)
en:play(abc("C D"), 120, 0.5, "Base.Violin"); en:onBand({ "Ann", "Me" }, 90)
check(en:bandBpm() == 90, "locked while in the band")
livePos = nil; en:tick()
check(en:bandBpm() == nil and en:alongStatus() == nil, "song over: unlocked, no stale member list")

-- tones (2026-10-28)
local tc = C.new("player10", deps)
tc:play(abc("C D E F"), 120, 0.5, "Base.GuitarElectric", nil, "jazz")
check(last().perf.tone == "jazz", "the tone travels with the part")
pausePos = 500; livePos = 500; tc:pause()
tc:play(abc("C D E F"), 120, 0.5, "Base.GuitarElectric", nil, "jazz")
check(last().pos == 500, "same tone resumes")
tc:pause()
tc:play(abc("C D E F"), 120, 0.5, "Base.GuitarElectric", nil, "clean")
check(last().pos == 0 and last().perf.tone == "clean", "a changed tone starts over")
