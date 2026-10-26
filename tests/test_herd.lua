require "PlayIt/Herd"
local H = PlayIt.Herd

check(H.CALL_CHANCE == 0.02, "2% per noise tick (every 2 s)")
check(H.answers(false, 5, 20, 50, 0.01), "tame, trusting, in range, lucky roll: comes over")
check(not H.answers(false, 5, 20, 50, 0.5), "unlucky roll: stays")
check(not H.answers(true, 5, 20, 100, 0.0), "wild: never")
check(not H.answers(false, 25, 20, 100, 0.0), "out of range: never")
check(not H.answers(false, 5, 20, 39, 0.0), "doesn't trust the player enough: never")
