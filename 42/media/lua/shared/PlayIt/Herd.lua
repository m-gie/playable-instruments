-- Now and then a tame animal that trusts the musician wanders over to the music; everything else reacts to
-- the noise the vanilla way (wild animals flee). Runs where animals are simulated: the server in MP, the client in SP.

PlayIt = PlayIt or {}
PlayIt.Herd = PlayIt.Herd or {}
local Herd = PlayIt.Herd

Herd.MIN_ACCEPTANCE = 40 -- same threshold vanilla uses for animals answering a call-out
Herd.CALL_DELAY_MS = 200 -- after the noise, so the walk-over replaces any startle from it
Herd.CALL_CHANCE = 0.02 -- per animal per noise tick (every 2 s): about once every 1.5-2 minutes of music

-- does this animal come over this time? roll: a random number in [0, 1)
function Herd.answers(wild, distance, radius, acceptance, roll)
    return not wild and distance <= radius and acceptance >= Herd.MIN_ACCEPTANCE and roll < Herd.CALL_CHANCE
end

local pending = {}

function Herd.call(player, radius, nowMs)
    local animals = getCell():getAnimals()
    for i = 0, animals:size() - 1 do
        local a = animals:get(i)
        if Herd.answers(a:isWild(), a:DistTo(player), radius, a:getPlayerAcceptance(player), ZombRandFloat(0, 1)) then
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
