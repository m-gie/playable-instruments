-- Server-side record of who is playing what, where in the song they are, and who already has it.

require "PlayIt/Song"
require "PlayIt/Instruments"

PlayIt = PlayIt or {}
PlayIt.Session = PlayIt.Session or {}
local Session = PlayIt.Session
Session.__index = Session

-- a part travels as one string, and PZ's network strings carry a signed 16-bit byte length (32,767 at most):
-- the compacted part (PlayIt.Song.compact) must stay below this
Session.MAX_TEXT = 30000
Session.MAX_SEGMENTS = 64

-- messages that make the server parse a song and send it on (start, segments): a burst of RATE_BURST, then one
-- per RATE_MS. Play, pause and play again stays well inside; a hacked client can't flood the players in range.
Session.RATE_BURST = 4
Session.RATE_MS = 2000 -- the client sends segments at most every 2 s (ISPlayItAction CHANCE_EVERY_MS)

function Session.new()
    return setmetatable({ list = {}, rate = {} }, Session)
end

-- true when player id may send another start or segments message now (and counts it)
function Session:allow(id, nowMs)
    local r = self.rate[id] or { tokens = Session.RATE_BURST, at = nowMs }
    self.rate[id] = r
    r.tokens = math.min(Session.RATE_BURST, r.tokens + (nowMs - r.at) / Session.RATE_MS)
    r.at = nowMs
    if r.tokens < 1 then return false end
    r.tokens = r.tokens - 1
    return true
end

local function isInt(v) return type(v) == "number" and v == math.floor(v) end
local function within(v, lo, hi) return type(v) == "number" and v >= lo and v <= hi end

local PIECES = { kick = true, snare = true, tom = true }
Session.SAME_INSTRUMENT = 3 -- tiles: two places of one instrument type closer than this are the same instrument

local function isTile(t) return type(t) == "table" and isInt(t.x) and isInt(t.y) and isInt(t.z) end

-- place of a world instrument: { x, y, z, kit = { {piece, x, y, z}, ... } (drums: 1-3 distinct pieces) }
local function validPlace(place)
    if not isTile(place) then return false end
    if place.kit == nil then return true end
    if type(place.kit) ~= "table" or #place.kit == 0 or #place.kit > 3 then return false end
    local seen = {}
    for _, k in ipairs(place.kit) do
        if not isTile(k) or not PIECES[k.piece] or seen[k.piece] then return false end
        seen[k.piece] = true
    end
    return true
end

-- perf as sent by a musician's client: { text, bpm, seed, segments, volume, length, level, place (furniture),
-- fromMs (where in its timeline the part comes in; nil = from its first note), tone (one of the instrument's
-- PlayIt.Instruments.tonesOf ids; nil = its default sound) }
function Session.validate(perf, fullType)
    if type(perf) ~= "table" then return false, "perf" end
    if type(perf.text) ~= "string" or #perf.text > Session.MAX_TEXT then return false, "text" end
    if type(perf.bpm) ~= "number" then return false, "bpm" end
    if not isInt(perf.seed) then return false, "seed" end
    if not within(perf.volume, 0, 1) then return false, "volume" end
    if not within(perf.length, 0, math.huge) then return false, "length" end
    if not (isInt(perf.level) and within(perf.level, 0, 10)) then return false, "level" end
    if perf.place ~= nil and not validPlace(perf.place) then return false, "place" end
    if perf.fromMs ~= nil and not within(perf.fromMs, 0, math.huge) then return false, "fromMs" end
    if perf.tone ~= nil then
        local known = false
        for _, t in ipairs(type(perf.tone) == "string" and PlayIt.Instruments.tonesOf(fullType) or {}) do
            known = known or t.id == perf.tone
        end
        if not known then return false, "tone" end
    end
    local segs = perf.segments
    if type(segs) ~= "table" or #segs == 0 or #segs > Session.MAX_SEGMENTS then return false, "segments" end
    for _, seg in ipairs(segs) do
        if type(seg) ~= "table" or not isInt(seg.fromChord) or seg.fromChord < 1 or not within(seg.chance, 0, 1) then
            return false, "segments"
        end
    end
    return true
end

-- the rest of a start message: posMs (where the musician means to start), along (the player they play along
-- with), wait (they wait for the server's "go" before playing), resume (back into the performance they left)
function Session.validStart(args)
    if not within(args.posMs, 0, math.huge) then return false end
    if args.along ~= nil and not isInt(args.along) then return false end
    if args.wait ~= nil and type(args.wait) ~= "boolean" then return false end
    if args.resume ~= nil and type(args.resume) ~= "boolean" then return false end
    return true
end

-- where a part is at nowMs, given its origin (when its timeline 0 is, on the same clock): negative before it
-- starts, nil once it is over
function Session.posAt(origin, nowMs, length)
    local pos = nowMs - origin
    if pos >= length then return nil end
    return pos
end

-- origin: server ms of the part's timeline 0
function Session:start(id, perf, origin)
    self.list[id] = { perf = perf, origin = origin, paused = nil, listeners = {} }
end

function Session:get(id) return self.list[id] end

function Session:pause(id, posMs)
    local s = self.list[id]
    if s then s.paused = posMs end
end

function Session:pausedAt(id)
    local s = self.list[id]
    return s and s.paused
end

function Session:stop(id) self.list[id] = nil end
Session.removePlayer = Session.stop

function Session:setSegments(id, segments)
    local s = self.list[id]
    if s then s.perf.segments = segments end
end

-- nil when there is no session, it is paused, or the song has ended
function Session:positionAt(id, nowMs)
    local s = self.list[id]
    if s == nil or s.paused then return nil end
    local pos = nowMs - s.origin
    if pos >= s.perf.length then return nil end
    return pos
end

local function sharesTile(a, b)
    for _, ka in ipairs(a.kit or {}) do
        for _, kb in ipairs(b.kit or {}) do
            if ka.x == kb.x and ka.y == kb.y and ka.z == kb.z then return true end
        end
    end
    return false
end

-- do two performances use the same instrument? Pianos and the organ: the same type within SAME_INSTRUMENT tiles;
-- drums: a shared piece
function Session.overlaps(fullType, place, otherType, other)
    if fullType ~= otherType or place == nil or other == nil then return false end
    if place.kit or other.kit then return sharesTile(place, other) end
    return other.z == place.z and math.abs(other.x - place.x) < Session.SAME_INSTRUMENT
        and math.abs(other.y - place.y) < Session.SAME_INSTRUMENT
end

-- id of another musician playing (not paused) the instrument at place, or nil. s.fullType is set by the server.
function Session:busyAt(fullType, place, exceptId)
    for id, s in pairs(self.list) do
        if id ~= exceptId and not s.paused and Session.overlaps(fullType, place, s.fullType, s.perf.place) then
            return id
        end
    end
    return nil
end

function Session:hasListener(id, playerId)
    local s = self.list[id]
    return s ~= nil and s.listeners[playerId] == true
end

function Session:addListener(id, playerId)
    local s = self.list[id]
    if s then s.listeners[playerId] = true end
end

function Session:listeners(id)
    local s = self.list[id]
    return s and s.listeners or {}
end
