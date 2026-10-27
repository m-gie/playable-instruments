require "PlayIt/Controller"
local C = PlayIt.Controller

local calls, pausePos, livePos, liveChord = {}, 750, 0, 0
local net = {
    start = function(_, fullType, perf, pos) table.insert(calls, { "start", fullType = fullType, perf = perf, pos = pos }) end,
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
}
local c = C.new("player", deps)
local last = function() return calls[#calls] end

c:play("c,d,e,f", 120, 0.7, "Base.Violin")
local s1 = last()
check(s1[1] == "start" and s1.pos == 0 and s1.perf.seed == 101 and s1.perf.length == 2000, "fresh start at 0 with a new seed and the song length")
check(s1.perf.level == 3 and s1.perf.volume == 0.7 and s1.perf.bpm == 120, "perf carries level, volume, bpm")
check(math.abs(s1.perf.segments[1].chance - 0.5 * (0.0001 / 0.5) ^ 0.09) < 1e-9 and s1.perf.segments[1].fromChord == 1, "first segment = current chance")
check(c:isPlaying() and not c:isPaused() and c:instrument() == "Base.Violin", "playing")

c:pause()
check(c:isPaused() and not c:isPlaying() and c:positionMs() == 750, "pause remembers the position")
c:play("c,d,e,f", 120, 0.3, "Base.Violin")
check(last().pos == 750 and last().perf.seed == 101 and last().perf.volume == 0.3, "resume: same seed, same place, new volume")

c:pause(); c:play("c,d,e", 120, 0.3, "Base.Violin")
check(last().pos == 0 and last().perf.seed == 102, "changed text restarts with a new seed")
c:pause(); c:play("c,d,e", 90, 0.3, "Base.Violin")
check(last().pos == 0, "changed bpm restarts")

pausePos = nil -- the song had already ended when paused
c:pause(); c:play("c,d,e", 90, 0.3, "Base.Violin")
check(last().pos == 0, "after the song ended, play starts over")

c:stop(); check(last()[1] == "stop" and not c:isPlaying() and not c:isPaused(), "stop")
c:play("c,d,e", 90, 0.3, "Base.Violin"); check(last().pos == 0, "after stop, play starts over")

-- blunder chance follows drunk/panic mid-song
liveChord = 10
deps.mood = function() return 100, 0 end
c:updateChance()
check(last()[1] == "segments" and last().segs[2].fromChord == 14, "new segment 4 chords ahead")
local n = #calls; c:updateChance(); check(#calls == n, "no update when the chance hasn't changed")

-- the song ends by itself
livePos = nil; c:tick(); check(not c:isPlaying() and not c:isPaused(), "song end stops the controller")

c:play("c,d", 120, 0.4, "Base.Trumpet"); check(c:volume() == 0.4, "controller remembers the volume")

-- Final review #1: the compact song is what gets sent; too long refuses
c:stop()
c:play("BPM: 90\nC-E,\tD\r\n", 90, 0.5, "Base.Violin"); check(last().perf.text == "BPM: 90\nc-e,d", "compact text sent")
local before = #calls
local ok, why = c:play(string.rep("c-e-g/2,", 30) .. "\n" .. string.rep(string.rep("c-e-g/2,", 30) .. "\n", 160), 90, 0.5, "Base.Violin")
check(ok == false and why == "TooLong" and #calls == before, "a song too long to send is refused, nothing sent")

-- Review Focus 5: world instruments resume only where they were paused
pausePos = 750 -- paused mid-song again
local c2 = C.new("player2", deps)
c2:play("c,d", 120, 0.7, "PlayIt.WesternPiano", { x = 1, y = 1, z = 0 }); c2:pause()
c2:play("c,d", 120, 0.7, "PlayIt.WesternPiano", { x = 9, y = 9, z = 0 })
check(last().pos == 0 and last().perf.place.x == 9, "resume needs the same place")
c2:pause()
c2:play("c,d", 120, 0.7, "PlayIt.WesternPiano", { x = 9, y = 9, z = 0 })
check(last().pos == pausePos and c2:place().x == 9, "same place resumes")
