-- Server-side record of who is playing what, where in the song they are, and who already has it.

require "PlayIt/Song"

PlayIt = PlayIt or {}
PlayIt.Session = PlayIt.Session or {}
local Session = PlayIt.Session
Session.__index = Session

-- network strings carry a 16-bit byte length; songs travel compacted (PlayIt.Song.compact, ASCII) below this
Session.MAX_TEXT = 32000
Session.MAX_SEGMENTS = 64

function Session.new()
    return setmetatable({ list = {} }, Session)
end

local function isInt(v) return type(v) == "number" and v == math.floor(v) end
local function within(v, lo, hi) return type(v) == "number" and v >= lo and v <= hi end

-- perf as sent by a musician's client: { text, bpm, seed, segments, volume, length, level }
function Session.validate(perf)
    if type(perf) ~= "table" then return false, "perf" end
    if type(perf.text) ~= "string" or #perf.text > Session.MAX_TEXT then return false, "text" end
    if type(perf.bpm) ~= "number" then return false, "bpm" end
    if not isInt(perf.seed) then return false, "seed" end
    if not within(perf.volume, 0, 1) then return false, "volume" end
    if not within(perf.length, 0, math.huge) then return false, "length" end
    if not (isInt(perf.level) and within(perf.level, 0, 10)) then return false, "level" end
    local segs = perf.segments
    if type(segs) ~= "table" or #segs == 0 or #segs > Session.MAX_SEGMENTS then return false, "segments" end
    for _, seg in ipairs(segs) do
        if type(seg) ~= "table" or not isInt(seg.fromChord) or seg.fromChord < 1 or not within(seg.chance, 0, 1) then
            return false, "segments"
        end
    end
    return true
end

-- where to begin a song received at receivedAt but only started at nowMs (its musician loaded late); nil if over
function Session.lateStart(posMs, receivedAt, nowMs, length)
    local pos = posMs + (nowMs - receivedAt)
    if pos >= length then return nil end
    return pos
end

function Session:start(id, perf, posMs, nowMs)
    self.list[id] = { perf = perf, origin = nowMs - posMs, paused = nil, listeners = {} }
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
