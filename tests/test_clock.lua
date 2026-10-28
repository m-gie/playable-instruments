require "PlayIt/Clock"
local C = PlayIt.Clock

local c = C.new()
check(c:offset() == 0, "no samples: offset 0")
c:sample(1000, 5050, 1100) -- 100 ms round trip, server read at the midpoint
check(c:offset() == 4000, "offset from one ping")
c:sample(2000, 9000, 2600) -- slower round trip: less trustworthy
check(c:offset() == 4000, "the fastest round trip wins")
c:sample(3000, 7020, 3040)
check(c:offset() == 4000, "faster sample replaces it")
check(c:toServer(c:toLocal(12345)) == 12345 and c:toServer(100) == 4100, "toServer and toLocal invert")
local d = C.new()
for i = 1, 9 do d:sample(i * 1000, i * 1000 + 10, i * 1000 + 20 + (i == 1 and 0 or 50)) end
check(d:offset() == -25, "only the latest 8 samples count")
