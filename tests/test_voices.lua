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
    return { playSoundImpl = function() return 0 end, setPitch = function() error("pitched a failed sound") end }
end)
failing:noteOn("X", 1, 100, 0, 1); failing:update(1000)
check(true, "a sound that fails to start is ignored")
