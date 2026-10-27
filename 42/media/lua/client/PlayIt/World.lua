-- What music does to the world, client side: zombie noise from the local musician. In single player also mood,
-- animals and Music XP (the server does those in MP).
-- An invisible musician does none of it (Playback doesn't report their notes either).

require "PlayIt/Effects"
require "PlayIt/Herd"
require "PlayIt/Config"
require "PlayIt/Instruments"
require "PlayIt/Controls"
require "PlayIt/Playback"

local nextNoise, lastXp = {}, {}

local function musicianOf(id)
    if type(id) == "string" then return getSpecificPlayer(tonumber(id:sub(3))) end -- "spN" in single player
    return getPlayerByOnlineID(id)
end

local function localPlayers()
    local out = {}
    for n = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(n)
        if p and not p:isDead() then out[#out + 1] = p end
    end
    return out
end

local function musicianTick(player, now)
    local n = player:getPlayerNum()
    local c = PlayIt.Controls.get(player)
    if not c:isPlaying() then
        lastXp[n] = nil
        return
    end
    local cfg = PlayIt.Config.get()
    local def = PlayIt.Instruments.defs[c:instrument()]
    if def and not player:isInvisible() and now >= (nextNoise[n] or 0) then
        nextNoise[n] = now + PlayIt.Effects.NOISE_INTERVAL_MS
        local r = PlayIt.Effects.noiseRadius(def, c:volume() or 0, cfg.noiseMult)
        if r > 0 then
            addSound(player, player:getX(), player:getY(), player:getZ(), r, r)
            if not isClient() then PlayIt.Herd.call(player, r, now) end
        end
    end
    if not isClient() and cfg.skillOn and Perks.PlayItMusic then
        local dt = (now - (lastXp[n] or now)) / 1000
        if dt >= 1 then
            addXp(player, Perks.PlayItMusic, PlayIt.Effects.XP_PER_SECOND * dt)
            lastXp[n] = now
        elseif lastXp[n] == nil then
            lastXp[n] = now
        end
    end
end

Events.OnTick.Add(function()
    local now = getTimestampMs()
    for _, player in ipairs(localPlayers()) do musicianTick(player, now) end
    if not isClient() then PlayIt.Herd.update(now) end
end)

-- single player: each played chord cheers up (or, if botched, annoys) local players within earshot of its
-- musician. In MP these stats belong to the server, which applies the same effects (server/PlayIt/Server.lua).
PlayIt.Playback.onEvent = function(id, event, perf, def)
    if isClient() then return end
    local musician = musicianOf(id)
    if musician == nil then return end
    local cfg = PlayIt.Config.get()
    local earshot = PlayIt.Effects.earshot(def, perf.volume)
    for _, player in ipairs(localPlayers()) do
        local stats = player:getStats()
        local fx = PlayIt.Effects.forListener(event, player:DistTo(musician), earshot, perf.level or 0, cfg.annoy,
            player == musician, PlayIt.Effects.moodOf(stats))
        if fx then
            stats:remove(CharacterStat.BOREDOM, -fx.boredom)
            if fx.stress > 0 then stats:add(CharacterStat.STRESS, fx.stress) end
            if fx.unhappy > 0 then stats:add(CharacterStat.UNHAPPINESS, fx.unhappy) end
        end
    end
end
