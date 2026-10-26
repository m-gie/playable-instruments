-- Tame animals that trust the musician walk over to the music; everything else reacts to the noise the
-- vanilla way (wild animals flee). Runs where animals are simulated: the server in MP, the client in SP.

PlayIt = PlayIt or {}
PlayIt.Herd = PlayIt.Herd or {}
local Herd = PlayIt.Herd

Herd.MIN_ACCEPTANCE = 40 -- same threshold vanilla uses for animals answering a call-out
Herd.CALL_DELAY_MS = 200 -- after the noise, so the walk-over replaces any startle from it

local pending = {}

function Herd.call(player, radius, nowMs)
    local animals = getCell():getAnimals()
    for i = 0, animals:size() - 1 do
        local a = animals:get(i)
        if not a:isWild() and a:DistTo(player) <= radius and a:getPlayerAcceptance(player) >= Herd.MIN_ACCEPTANCE then
            table.insert(pending, { animal = a, player = player, at = nowMs + Herd.CALL_DELAY_MS })
        end
    end
end

function Herd.update(nowMs)
    for i = #pending, 1, -1 do
        local p = pending[i]
        if nowMs >= p.at then
            table.remove(pending, i)
            if not p.animal:isDead() and not p.player:isDead() then p.animal:pathToCharacter(p.player) end
        end
    end
end
