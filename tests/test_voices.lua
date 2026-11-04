require "PlayIt/Voices"
local V = PlayIt.Voices

-- fake pooled emitters: each records its calls
local made = {}
local nextRef = 0
local function newEmitter(x, y, z)
    local em = { pos = { x, y, z }, vol = {}, pitch = {}, stopped = {}, playing = {} }
    -- playSound(name) on an MP client also broadcasts an unpitched copy to other players: must not be used
    function em:playSound() error("networked playSound used") end
    function em:playSoundImpl(name, loop, parent)
        assert(loop == false and parent == nil, "local one-shot")
        nextRef = nextRef + 1; self.playing[nextRef] = name; return nextRef
    end
    function em:setPitch(ref, p) self.pitch[ref] = p end
    function em:setVolume(ref, v) self.vol[ref] = v end
    function em:stopSound(ref) self.stopped[ref] = true end
    function em:setPos(a, b, c) self.pos = { a, b, c } end
    function em:isPlaying() return true end
    table.insert(made, em)
    return em
end

local px = 10
local voices = V.new(function() return px, 20, 0 end, 12, newEmitter)
voices:noteOn("S", 1.5, 1000, 0, 0.8)
local em = made[1]
check(em.playing[1] == "S" and em.pitch[1] == 1.5, "noteOn plays and pitches its own emitter")
check(em.pos[1] == 10 and em.pos[2] == 20, "emitter starts at the musician")
voices:update(500); check(em.vol[1] == 0.8, "full gain during the note")
px = 15; voices:update(600); check(em.pos[1] == 15, "emitter follows the musician")
voices:update(1150); check(math.abs(em.vol[1] - 0.4) < 1e-9, "half gain halfway through the release")
voices:update(1300); check(em.stopped[1], "stopped after the release")

made = {}
for i = 1, 13 do voices:noteOn("S", 1, 5000, 0, 1) end
check(#made == 13 and next(made[1].stopped) ~= nil, "13th voice stops the oldest")
check(next(made[2].stopped) == nil, "second voice still playing")

made = {}
local short = V.new(function() return 0, 0, 0 end, 12, newEmitter, 100)
short:noteOn("S", 1, 1000, 0, 1)
short:update(1050); check(math.abs(made[1].vol[next(made[1].vol)] - 0.5) < 1e-9, "custom release: half gain 50 ms into a 100 ms release")
short:update(1100); check(next(made[1].stopped) ~= nil, "custom release: stopped after 100 ms")

-- Review Focus 5: voices are per musician
made = {}
local a = V.new(function() return 0, 0, 0 end, 12, newEmitter)
local b = V.new(function() return 5, 5, 0 end, 12, newEmitter)
a:noteOn("A", 1, 1000, 0, 1); b:noteOn("B", 1, 1000, 0, 1)
a:stopAll()
check(next(made[1].stopped) ~= nil and next(made[2].stopped) == nil, "voices are per musician")

local failing = V.new(function() return 0, 0, 0 end, 12, function()
    return { playSoundImpl = function() return 0 end, isPlaying = function() return false end, setPitch = function() error("pitched a failed sound") end }
end)
failing:noteOn("X", 1, 100, 0, 1); failing:update(1000)
check(true, "a sound that fails to start is ignored")

-- Final review #6: a voice whose sample ended releases its emitter to the pool at once
made = {}
local ended = V.new(function() return 0, 0, 0 end, 12, newEmitter)
ended:noteOn("S", 1, 10000, 0, 1)
local e1 = made[1]
e1.isPlaying = function() return false end
ended:update(4000)
e1.pos = "untouched"
ended:update(5000)
check(e1.pos == "untouched" and #ended.list == 0, "finished sample: emitter no longer moved")

-- echo (2026-10-28): a tail voice beside the note; the next note cuts tails and finished notes
made = {}
local ev = V.new(function() return 0, 0, 0 end, 20, newEmitter)
ev:noteOn("S", 1, 400, 0, 0.8)
check(#made == 1 and #ev.list == 1, "no tail: one voice")
ev:noteOn("S", 1, 400, 100, 0.8)
check(next(made[1].stopped) == nil and made[1].vol[next(made[1].vol)] == 0.8, "no echo: nothing is cut")
made = {}
local echo = V.new(function() return 0, 0, 0 end, 20, newEmitter)
echo:noteOn("Dry", 1.2, 400, 0, 0.8, "Tail", 0.4)
check(#made == 2 and made[2].playing[next(made[2].playing)] == "Tail", "a tail starts on a second voice")
local tailRef = next(made[2].playing)
check(made[2].vol[tailRef] == 0.4 and made[2].pitch[tailRef] == 1.2, "tail at its gain and the note's pitch")
echo:noteOn("Held", 1, 5000, 0, 0.8, "HeldTail", 0.4)
check(next(made[1].stopped) == nil and next(made[2].stopped) == nil, "notes of the same chord never cut each other")
echo:update(2000)
check(next(made[2].stopped) == nil, "a tail rings past the release")
echo:noteOn("Next", 1, 400, 2000, 0.8, "NextTail", 0.4)
echo:update(2060)
check(math.abs(made[2].vol[tailRef] - 0.2) < 1e-9, "the next note fades a ringing tail (half way at 60 ms)")
check(made[3].vol[next(made[3].vol)] == 0.8, "a note within its written length keeps full volume")
echo:update(2120)
check(next(made[2].stopped) ~= nil, "the tail stops after the cut")
check(next(made[3].stopped) == nil and next(made[4].stopped) ~= nil, "held note kept, its tail cut")
check(V.MAX_VOICES == 20 and V.CUT_MS == 120, "cap 20, cut 120 ms")

-- live volume and echo (2026-11-04): ringing voices follow at once
made = {}
local lg = V.new(function() return 0, 0, 0 end, 20, newEmitter)
lg:noteOn("N", 1, 1000, 0, 0.8, "T", 0.4)
local nRef, tRef = next(made[1].playing), next(made[2].playing)
lg:setGains(0.5, 0.1, 100)
lg:update(100)
check(made[1].vol[nRef] == 0.5 and made[2].vol[tRef] == 0.1, "a ringing note and its tail take the new gains")
lg:update(1200)
check(math.abs(made[1].vol[nRef] - 0.5 * (1 - 200 / V.RELEASE_MS)) < 1e-9, "the release fades from the new gain")
lg:setGains(0.5, 0, 1200)
lg:update(1260)
check(math.abs(made[2].vol[tRef] - 0.05) < 1e-9, "echo off: a ringing tail fades over CUT_MS")
lg:update(1320)
check(made[2].stopped[tRef], "and stops")
lg:setRelease(50)
lg:noteOn("M", 1, 100, 2000, 0.5)
lg:update(2125)
check(math.abs(made[3].vol[next(made[3].playing)] - 0.25) < 1e-9, "a new tone's release applies to new notes")
