-- The server's clock as seen from a client: an NTP-style offset from ping round trips. Songs travel with
-- server-time origins, so every client places every musician on the same clock whatever their latency.

PlayIt = PlayIt or {}
PlayIt.Clock = PlayIt.Clock or {}
local Clock = PlayIt.Clock
Clock.__index = Clock

Clock.KEEP = 8 -- latest samples kept; the one with the fastest round trip is trusted

function Clock.new()
    return setmetatable({ samples = {} }, Clock)
end

-- t0: local ms when the ping left, serverMs: the server's clock when it answered, t1: local ms when it came back
function Clock:sample(t0, serverMs, t1)
    table.insert(self.samples, { rtt = t1 - t0, offset = serverMs - (t0 + t1) / 2 })
    if #self.samples > Clock.KEEP then table.remove(self.samples, 1) end
end

-- server ms minus local ms; 0 until the first answer
function Clock:offset()
    local best
    for _, s in ipairs(self.samples) do
        if best == nil or s.rtt < best.rtt then best = s end
    end
    return best and best.offset or 0
end

function Clock:toServer(localMs) return localMs + self:offset() end
function Clock:toLocal(serverMs) return serverMs - self:offset() end
