require "PlayIt/Band"
local B = PlayIt.Band

-- a part: timeline 0 at its first note, leadMs of silence before it, bar starts every 2000 ms
local function part(leadMs, length)
    local bars = {}
    for t = -leadMs, length - 1, 2000 do bars[#bars + 1] = t end
    return { leadMs = leadMs, length = length, bars = bars }
end

-- solo: the clock starts at the starter's first note
local b = B.new()
check(b:startSolo(1, part(4000, 20000), 120, 10000) == 10000, "solo: part starts now")
local band = b:of(1)
check(band and band.origin == 6000 and band.bpm == 120, "solo: song time 0 is the lead before now")
check(#b:members(band) == 1 and b:members(band)[1] == 1, "band of one")

-- joining mid-song lands on the next bar of the joiner's part
local origin, fromMs = b:join(2, band, part(0, 20000), 15000)
check(origin == 6000, "joiner's part 0 is song time 0 (no lead)")
check(fromMs == 10000 and fromMs >= 15000 + B.JOIN_MARGIN_MS - origin, "comes in on the first bar after the margin")
check(b:of(2) == band and #b:members(band) == 2, "joiner is a member")
-- a joiner whose part is already over gets nil (the caller starts it solo)
check(b:join(3, band, part(0, 5000), 15000) == nil and b:of(3) == nil, "part over: no join")

-- count-in with waiters: earliest first note among ready parts starts at startAt
local w = B.new()
w:wait(5, 4); w:wait(6, 4); w:wait(7, 9)
local ws = w:waitersOf(4)
check(#ws == 2 and ws[1] == 5 and ws[2] == 6, "waiters of a player")
local starts = w:startWithWaiters(4, part(2000, 20000), 90, 1000, { [5] = part(0, 20000) })
local startAt = 1000 + B.COUNT_IN_MS
check(starts[5] == startAt and starts[4] == startAt + 2000, "waiter starts at the count-in, starter after its lead")
check(w:of(4).origin == startAt and w:of(4).bpm == 90 and w:of(5) == w:of(4), "one band at the starter's bpm")
check(#w:waitersOf(4) == 1 and w:waitersOf(4)[1] == 6, "only ready waiters leave the wait")
w:unwait(6); check(#w:waitersOf(4) == 0, "unwait")
check(#w:waitersOf(9) == 1, "other waits untouched")

-- leaving, the empty grace period and resuming into a running band
local l = B.new()
l:startSolo(1, part(0, 60000), 120, 0)
local lb = l:of(1)
l:join(2, lb, part(0, 60000), 1000)
l:leave(1, 5000)
check(l:of(1) == nil and l:lastBand(1) == lb, "the starter paused; the band remembers it")
check(#l:tick(100000) == 0 and l:of(2) == lb, "a band with members never ends")
local o2, f2 = l:join(1, l:lastBand(1), part(0, 60000), 9000)
check(o2 == 0 and f2 == 10000, "resume rejoins at the next bar, not the paused spot")
l:leave(1, 20000); l:leave(2, 20000)
check(#l:tick(29999) == 0 and l:lastBand(2) == lb, "empty: kept for the grace period")
local ended = l:tick(30000)
check(#ended == 1 and ended[1] == lb.id and l:lastBand(2) == nil, "empty for 10 s: over")
-- a new solo start leaves the old band first
local n = B.new()
n:startSolo(1, part(0, 10000), 120, 0); local first = n:of(1)
n:startSolo(1, part(0, 10000), 120, 500)
check(n:of(1) ~= first and #n:members(first) == 0, "starting again makes a new band")
