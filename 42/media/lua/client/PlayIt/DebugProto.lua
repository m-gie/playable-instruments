-- Throwaway prototype (Task 1 gate): pitch, chords, fades, noise, paste and animal checks.
-- Debug mode only; removed in Task 4.

local queue = {}

local function at(ms, fn)
    table.insert(queue, { t = getTimestampMs() + ms, fn = fn })
end

local function onTick()
    if #queue == 0 then return end
    local now = getTimestampMs()
    for i = #queue, 1, -1 do
        local job = queue[i]
        if now >= job.t then
            table.remove(queue, i)
            job.fn(now - job.t)
        end
    end
end
Events.OnTick.Add(onTick)

local function note(emitter, semis, label)
    local ref = emitter:playSound("PlayIt_TestPluck")
    emitter:setPitch(ref, 2 ^ (semis / 12))
    print(string.format("[PlayIt] %s ref=%s semis=%d t=%d", label, tostring(ref), semis, getTimestampMs()))
    return ref
end

local function musicTest(player)
    local emitter = player:getEmitter()
    local scale = { 0, 2, 4, 5, 7, 9, 11, 12 }
    for i, s in ipairs(scale) do
        at((i - 1) * 500, function(late)
            note(emitter, s, "scale late=" .. late)
        end)
    end
    at(4500, function()
        for _, s in ipairs({ 0, 4, 7 }) do note(emitter, s, "chord") end
    end)
    at(6500, function()
        local ref = note(emitter, 7, "fade")
        for k = 1, 10 do
            at(k * 100, function() emitter:setVolume(ref, 1 - k / 10) end)
        end
    end)
    at(8000, function()
        addSound(player, player:getX(), player:getY(), player:getZ(), 30, 30)
        print("[PlayIt] addSound r=30")
    end)
end

local function pasteTest(player)
    local modal = ISTextBox:new(0, 0, 500, 400, "Paste a long song (Ctrl+V), then OK", "", nil,
        function(_, button)
            if button.internal == "OK" then
                local text = button.parent.entry:getText()
                print("[PlayIt] pasted length=" .. #text)
            end
        end, player:getPlayerNum())
    modal:initialise()
    modal:addToUIManager()
    -- entry only exists after createChildren (run by addToUIManager)
    modal.entry:setMultipleLine(true)
    modal.entry:setMaxLines(1000)
    modal.entry:setHeight(150)
end

local function nearbyAnimals(player, radius)
    local out = {}
    local list = getCell():getAnimals()
    for i = 0, list:size() - 1 do
        local a = list:get(i)
        if a:DistTo(player) <= radius then table.insert(out, a) end
    end
    return out
end

local function describe(player, a)
    return string.format("%s wild=%s acceptance=%.1f stress=%.2f dist=%.1f", a:getAnimalType(), tostring(a:isWild()),
        a:getPlayerAcceptance(player), a:getStress(), a:DistTo(player))
end

local function trustNearest(player)
    for _, a in ipairs(nearbyAnimals(player, 10)) do
        if not a:isWild() then
            a:setDebugAcceptance(player, 100)
            print("[PlayIt] trusted: " .. describe(player, a))
            return
        end
    end
    print("[PlayIt] no tame animal within 10 tiles")
end

local function animalTest(player)
    local animals = nearbyAnimals(player, 20)
    for _, a in ipairs(animals) do print("[PlayIt] before: " .. describe(player, a)) end
    addSound(player, player:getX(), player:getY(), player:getZ(), 20, 20)
    at(200, function()
        for _, a in ipairs(animals) do
            if not a:isWild() and a:getPlayerAcceptance(player) >= 40 then
                a:pathToCharacter(player)
                print("[PlayIt] calling: " .. describe(player, a))
            end
        end
    end)
    at(5000, function()
        for _, a in ipairs(animals) do print("[PlayIt] after 5s: " .. describe(player, a)) end
    end)
end

local SOUND_VARIANTS = { "PlayIt_TestPluck", "PlayIt_TestPluckRoot", "PlayIt_TestPluckCommon" }

-- Why does playSound return 0? Print what the engine knows about each variant, then try each.
local function soundDiag(player)
    -- the character emitter refuses to play (returns 0) while the character is invisible
    print("[PlayIt] diag invisible=" .. tostring(player:isInvisible()))
    local world = getWorld():getFreeEmitter(player:getX(), player:getY(), player:getZ())
    at(5000, function()
        local ref = world:playSound("PlayIt_TestPluck")
        print("[PlayIt] diag world emitter ref=" .. tostring(ref))
    end)
    at(6500, function()
        print("[PlayIt] diag UI sound ref=" .. tostring(getSoundManager():playUISound("PlayIt_TestPluck")))
    end)
    local emitter = player:getEmitter()
    for i, name in ipairs(SOUND_VARIANTS) do
        local gs = GameSounds.getSound(name)
        if gs == nil then
            print("[PlayIt] diag " .. name .. ": GameSounds.getSound = nil")
        else
            local clip = gs:getRandomClip()
            -- Java fields (gs.clips) aren't readable from Kahlua; getters only
            print(string.format("[PlayIt] diag %s: file=%s event=%s", name,
                tostring(clip and clip:getFile()), tostring(clip and clip:getEvent())))
        end
        at((i - 1) * 1500, function()
            local ref = emitter:playSound(name)
            print(string.format("[PlayIt] diag %s: emitter ref=%s", name, tostring(ref)))
            if ref ~= 0 then emitter:setPitch(ref, 1.5) end
        end)
    end
end

local function onFill(playerNum, context, items)
    if not isDebugEnabled() then return end
    local player = getSpecificPlayer(playerNum)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(context:addOption("PlayIt test"), sub)
    sub:addOption("Sound diagnostics", player, soundDiag)
    sub:addOption("Scale, chord, fade, noise", player, musicTest)
    sub:addOption("Paste test", player, pasteTest)
    sub:addOption("Animals: trust nearest tame", player, trustNearest)
    sub:addOption("Animals: noise + call trusting", player, animalTest)
end
Events.OnFillInventoryObjectContextMenu.Add(onFill)
