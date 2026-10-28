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
Controller.PENDING_TIMEOUT_MS = 5000 -- a start the server neither placed nor acknowledged as a wait by then is lost

-- deps: net {start, startLocal, stopLocal, unalong, pause, stop, segments}, newSeed(), position() -> ms|nil,
-- currentChord(), level(), config() -> {skillOn, p0, p10}, mood() -> intoxication, panic (0-100),
-- serverNow() -> the server's clock in ms
function Controller.new(player, deps)
    return setmetatable({ player = player, deps = deps, playing = false, members = {}, waiters = {} }, Controller)
end

function Controller:chance()
    local cfg = self.deps.config()
    local intox, panic = self.deps.mood()
    return PlayIt.Timeline.chance(self.deps.level(), cfg.p0, cfg.p10, intox, panic, cfg.skillOn)
end

local function samePlace(a, b)
    if a == nil or b == nil then return a == b end
    return a.x == b.x and a.y == b.y and a.z == b.z
end

-- starts the song, or resumes it where it was paused if text, tempo, instrument and place are unchanged.
-- place: where a furniture instrument stands (nil for hand-held ones).
-- text is one part (PlayIt.Song.parts). The compacted part is what plays and travels; false and "TooLong" if
-- even that is too big to send or has too many notes.
-- echo: 0..1 strength of the echo tails (0 = off)
function Controller:play(text, bpm, volume, fullType, place, tone, echo)
    text = PlayIt.Song.compact(text)
    if #text > PlayIt.Session.MAX_TEXT then return false, "TooLong" end
    local song = PlayIt.Song.parse(text, bpm)
    if song.events >= PlayIt.Song.MAX_EVENTS then return false, "TooLong" end
    if echo ~= nil and echo <= 0 then echo = nil end
    local resume = self.pausedAt ~= nil and text == self.text and bpm == self.bpm and fullType == self.fullType
        and samePlace(place, self.where) and tone == self.tone and echo == self.echo
    self.where = place
    if not resume then
        self.text, self.bpm, self.fullType, self.tone, self.echo = text, bpm, fullType, tone, echo
        self.seed = self.deps.newSeed()
        self.lastChance = self:chance()
        self.segments = { { fromChord = 1, chance = self.lastChance } }
    end
    local perf = {
        text = text, bpm = song.bpm, seed = self.seed, segments = self.segments, volume = volume,
        length = PlayIt.Timeline.build(song, self.seed, self.segments).length, level = self.deps.level(),
        place = place, tone = tone, echo = echo,
    }
    local pos = resume and self.pausedAt or 0
    self.perf, self.ended, self.startAt = perf, nil, nil
    -- playing along, back into a band, or with someone waiting to start with us: the server says when
    local wait = self.along ~= nil or #self.waiters > 0 or (resume and self.inBand)
    if wait then
        self.pending, self.acked, self.pendingSince = true, false, self.deps.serverNow()
        self.deps.net.start(self.player, fullType, perf, pos, {
            wait = true, along = self.along and self.along.id, resume = (resume and self.inBand) or nil,
        })
    else
        self.deps.net.start(self.player, fullType, perf, pos)
    end
    self.pausedAt, self.playing, self.vol = nil, true, volume
    return true
end

-- the server placed our part: timeline 0 at origin (server ms), from fromMs, at the band's bpm; startAt is the
-- count-in's first beat (nil when joining a running song)
function Controller:onGo(origin, fromMs, bpm, startAt)
    if not self.pending then return end
    self.pending = false
    local perf = {}
    for k, v in pairs(self.perf) do perf[k] = v end
    perf.bpm, perf.fromMs = bpm, fromMs
    perf.length = PlayIt.Timeline.build(PlayIt.Song.parse(perf.text, bpm), perf.seed, perf.segments).length
    self.perf, self.goBpm, self.startAt = perf, bpm, startAt
    self.deps.net.startLocal(self.player, self.fullType, perf, self.deps.serverNow() - origin)
end

function Controller:playAlong(targetId, name)
    self.along = { id = targetId, name = name }
    self.ended = nil
end

function Controller:onBand(members, bpm)
    self.members = members or {}
    self.goBpm = bpm
end

function Controller:onWaiters(names) self.waiters = names or {} end

-- the server keeps our start until the player we play along with starts
function Controller:onWaiting() self.acked = true end

-- the server took us out (too far, the other player left): reason is an IGUI_PlayIt_Along_* key suffix
function Controller:onAlongEnded(reason)
    self.deps.net.stopLocal(self.player)
    self.playing, self.pending, self.pausedAt, self.along = false, false, nil, nil
    self.members, self.ended = {}, reason
end

-- the tempo the window must show and keep while playing with others; nil when playing alone
function Controller:bandBpm()
    if self.along or #self.members > 1 then return self.goBpm end
    return nil
end

-- what the window says about playing together: key (IGUI_PlayIt_Along_<key>) and its argument, or nil
function Controller:alongStatus()
    if self.ended then return self.ended end
    if self.pending then
        if self.along then return "WaitingFor", self.along.name end
        return nil
    end
    if self.startAt and self.playing then
        local left = self.startAt - self.deps.serverNow()
        if left > 0 then return "StartingIn", math.ceil(left / 1000) end
    end
    if self.along then
        if self.playing then return "PlayingAlong", self.along.name end
        return "PlayingAlongReady", self.along.name
    end
    if #self.members > 1 then return "InSong", table.concat(self.members, ", ") end
    if #self.waiters > 0 then return "Waiters", table.concat(self.waiters, ", ") end
    return nil
end

function Controller:pause()
    if not self.playing then return end
    if self.pending then -- the server hasn't placed us yet: give up instead
        self:stop()
        return
    end
    self.pausedAt = self.deps.net.pause(self.player) -- nil when the song had already ended
    if self.pausedAt and self.pausedAt < 0 then self.pausedAt = 0 end -- paused during the count-in
    self.playing = false
    self.inBand, self.members = #self.members > 1, {}
end

function Controller:stop()
    if self.pending then
        self.deps.net.unalong(self.player) -- no session on the server yet, only the wait
    elseif self.playing or self.pausedAt then
        self.deps.net.stop(self.player)
    end
    self.playing, self.pausedAt, self.pending = false, nil, false
    self.along, self.members, self.inBand, self.ended, self.startAt = nil, {}, false, nil, nil
end

function Controller:isPlaying() return self.playing end
function Controller:isPaused() return not self.playing and self.pausedAt ~= nil end
function Controller:instrument() return self.fullType end
function Controller:place() return self.where end
function Controller:volume() return self.vol end

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
    if self.pending and not self.acked
        and self.deps.serverNow() - self.pendingSince >= Controller.PENDING_TIMEOUT_MS then
        self.deps.net.unalong(self.player) -- refused or lost on the way: give up
        self:onAlongEnded("NoAnswer")
        return
    end
    if self.playing and not self.pending and self.deps.position() == nil then
        self.members, self.startAt, self.goBpm = {}, nil, nil -- the song is over: nothing to keep in time with
        self.playing = false
    end
end
