-- Server-side performances that several musicians share. A performance is a clock: song time 0 (leading
-- silence included) at `origin` in server ms, played at `bpm`. Players attach to it, never to each other, so
-- anyone can leave and come back; it ends once nobody has played in it for EMPTY_MS.
-- part: a timeline (PlayIt.Timeline.build) built at the performance's bpm: { leadMs, length, bars }.

require "PlayIt/Timeline"

PlayIt = PlayIt or {}
PlayIt.Band = PlayIt.Band or {}
local Band = PlayIt.Band
Band.__index = Band

Band.EMPTY_MS = 10000 -- a performance nobody plays in ends after this
Band.COUNT_IN_MS = 3000 -- from the starter's Play to the first beat when others are waiting
Band.JOIN_MARGIN_MS = 1000 -- a joiner comes in on the first bar at least this far ahead (covers the round trip)

function Band.new()
    return setmetatable({ list = {}, byPlayer = {}, waits = {}, last = {}, nextId = 1 }, Band)
end

function Band:of(playerId) return self.byPlayer[playerId] end

function Band:members(band)
    local ids = {}
    for id in pairs(band.members) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

local function add(self, band, playerId)
    band.members[playerId] = true
    band.emptySince = nil
    self.byPlayer[playerId] = band
    self.last[playerId] = nil
end

local function create(self, origin, bpm)
    local band = { id = self.nextId, origin = origin, bpm = bpm, members = {} }
    self.nextId = self.nextId + 1
    self.list[band.id] = band
    return band
end

-- a waiter pressed Play while playing along with targetId, who isn't playing yet
function Band:wait(playerId, targetId) self.waits[playerId] = targetId end
function Band:unwait(playerId) self.waits[playerId] = nil end

function Band:waitersOf(targetId)
    local ids = {}
    for id, target in pairs(self.waits) do
        if target == targetId then ids[#ids + 1] = id end
    end
    table.sort(ids)
    return ids
end

-- a new performance of one; the part starts now (its leading silence skipped). Returns the part's origin.
function Band:startSolo(playerId, part, bpm, now)
    self:leave(playerId, now)
    local band = create(self, now - part.leadMs, bpm)
    add(self, band, playerId)
    return now
end

-- the starter plus the waiters who are ready ({ [id] = part }) start together after the count-in, the earliest
-- first note among them on the first beat. Returns { [playerId] = part origin }.
function Band:startWithWaiters(playerId, part, bpm, now, ready)
    local startAt = now + Band.COUNT_IN_MS
    local minLead = part.leadMs
    for _, p in pairs(ready) do minLead = math.min(minLead, p.leadMs) end
    self:leave(playerId, now)
    local band = create(self, startAt - minLead, bpm)
    local starts = {}
    add(self, band, playerId)
    starts[playerId] = band.origin + part.leadMs
    for id, p in pairs(ready) do
        self:leave(id, now)
        self:unwait(id)
        add(self, band, id)
        starts[id] = band.origin + p.leadMs
    end
    return starts
end

-- joins a running performance on the first bar of the part at least JOIN_MARGIN_MS ahead. Returns the part's
-- origin and the timeline ms to start from, or nil when the part is already over there (play it solo instead).
function Band:join(playerId, band, part, now)
    local origin = band.origin + part.leadMs
    local fromMs = PlayIt.Timeline.nextBar(part, now + Band.JOIN_MARGIN_MS - origin)
    if fromMs == nil then return nil end
    self:leave(playerId, now)
    self:unwait(playerId)
    add(self, band, playerId)
    return origin, fromMs
end

-- pause, stop or song over: out of the performance, which remembers the player for a resume
function Band:leave(playerId, now)
    local band = self.byPlayer[playerId]
    if band == nil then return end
    band.members[playerId] = nil
    self.byPlayer[playerId] = nil
    self.last[playerId] = band.id
    for _ in pairs(band.members) do return end
    band.emptySince = now
end

-- the performance a player left, while it still runs
function Band:lastBand(playerId)
    local id = self.last[playerId]
    return id and self.list[id]
end

-- ends performances nobody has played in for EMPTY_MS; returns their ids
function Band:tick(now)
    local ended = {}
    for id, band in pairs(self.list) do
        if band.emptySince and now - band.emptySince >= Band.EMPTY_MS then
            self.list[id] = nil
            ended[#ended + 1] = id
        end
    end
    for playerId, id in pairs(self.last) do
        if self.list[id] == nil then self.last[playerId] = nil end
    end
    return ended
end
