-- One local musician's state: what is playing, where it was paused, the blunder seed and chance segments.
-- Game access comes in through deps so the rules can be tested offline (see client/PlayIt/Controls.lua).

require "PlayIt/Song"
require "PlayIt/Timeline"
require "PlayIt/Session"

PlayIt = PlayIt or {}
PlayIt.Controller = PlayIt.Controller or {}
local Controller = PlayIt.Controller
Controller.__index = Controller

Controller.CHANCE_STEP = 0.01 -- smaller changes in the blunder chance are not worth a network message
Controller.LOOKAHEAD_CHORDS = 4 -- a new chance applies this many chords ahead, so listeners get it in time

-- deps: net {start, pause, stop, segments}, newSeed(), position() -> ms|nil, currentChord(), level(),
-- config() -> {skillOn, p0, p10}, mood() -> intoxication, panic (0-100)
function Controller.new(player, deps)
    return setmetatable({ player = player, deps = deps, playing = false }, Controller)
end

function Controller:chance()
    local cfg = self.deps.config()
    local intox, panic = self.deps.mood()
    return PlayIt.Timeline.chance(self.deps.level(), cfg.p0, cfg.p10, intox, panic, cfg.skillOn)
end

-- starts the song, or resumes it where it was paused if text, tempo and instrument are unchanged
function Controller:play(text, bpm, volume, fullType)
    local resume = self.pausedAt ~= nil and text == self.text and bpm == self.bpm and fullType == self.fullType
    if not resume then
        self.text, self.bpm, self.fullType = text, bpm, fullType
        self.seed = self.deps.newSeed()
        self.lastChance = self:chance()
        self.segments = { { fromChord = 1, chance = self.lastChance } }
    end
    local song = PlayIt.Song.parse(text, bpm)
    local perf = {
        text = text, bpm = song.bpm, seed = self.seed, segments = self.segments, volume = volume,
        length = PlayIt.Timeline.build(song, self.seed, self.segments).length, level = self.deps.level(),
    }
    self.deps.net.start(self.player, fullType, perf, resume and self.pausedAt or 0)
    self.pausedAt, self.playing = nil, true
end

function Controller:pause()
    if not self.playing then return end
    self.pausedAt = self.deps.net.pause(self.player) -- nil when the song had already ended
    self.playing = false
end

function Controller:stop()
    if self.playing or self.pausedAt then self.deps.net.stop(self.player) end
    self.playing, self.pausedAt = false, nil
end

function Controller:isPlaying() return self.playing end
function Controller:isPaused() return not self.playing and self.pausedAt ~= nil end
function Controller:instrument() return self.fullType end

function Controller:positionMs()
    if self.playing then return self.deps.position() end
    return self.pausedAt
end

-- call every few seconds while playing: drunkenness and panic change the blunder chance from a little ahead
function Controller:updateChance()
    if not self.playing then return end
    local chance = self:chance()
    if math.abs(chance - self.lastChance) <= Controller.CHANCE_STEP then return end
    self.lastChance = chance
    local from = self.deps.currentChord() + Controller.LOOKAHEAD_CHORDS
    local last = self.segments[#self.segments]
    if from <= last.fromChord or #self.segments >= PlayIt.Session.MAX_SEGMENTS then
        last.chance = chance
    else
        table.insert(self.segments, { fromChord = from, chance = chance })
    end
    self.deps.net.segments(self.player, self.segments)
end

-- call every tick: notices the song ending by itself
function Controller:tick()
    if self.playing and self.deps.position() == nil then
        self.playing = false
    end
end
