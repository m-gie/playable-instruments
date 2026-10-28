-- The tone each instrument was last played with, on the player's own computer (Zomboid/Lua/PlayIt/tones.txt, one
-- "fullType=tone" line each), so the music window opens with it on every character and server. Likewise its echo
-- strength (PlayIt/echo.txt, "fullType=0.40").

require "PlayIt/Instruments"

PlayIt = PlayIt or {}
PlayIt.Tones = PlayIt.Tones or {}
local Tones = PlayIt.Tones

Tones.FILE = "PlayIt/tones.txt"
Tones.ECHO_FILE = "PlayIt/echo.txt"

local function fileIo(path)
    return {
        read = function()
            local reader = getFileReader(path, false)
            if reader == nil then return nil end
            local lines, line = {}, reader:readLine()
            while line ~= nil do
                lines[#lines + 1] = line
                line = reader:readLine()
            end
            reader:close()
            return table.concat(lines, "\n")
        end,
        write = function(text)
            local writer = getFileWriter(path, true, false)
            writer:write(text)
            writer:close()
        end,
    }
end

-- file access, replaceable for tests: read() -> text or nil, write(text)
Tones.io = fileIo(Tones.FILE)
Tones.echoIo = fileIo(Tones.ECHO_FILE)

function Tones.parse(text, valuePattern)
    local map = {}
    for line in (text or ""):gmatch("[^\r\n]+") do
        local fullType, tone = line:match("^%s*([%w%._]+)%s*=%s*(" .. (valuePattern or "[%w_]+") .. ")%s*$")
        if fullType then map[fullType] = tone end
    end
    return map
end

function Tones.format(map)
    local keys = {}
    for k in pairs(map) do keys[#keys + 1] = k end
    table.sort(keys)
    local lines = {}
    for _, k in ipairs(keys) do lines[#lines + 1] = k .. "=" .. map[k] end
    return table.concat(lines, "\n") .. "\n"
end

-- is tone one of the instrument's tones?
function Tones.valid(fullType, tone)
    for _, t in ipairs(PlayIt.Instruments.tonesOf(fullType)) do
        if t.id == tone then return true end
    end
    return false
end

local cache, echoCache

-- forget the cached files (tests)
function Tones.reset() cache, echoCache = nil, nil end

local function load()
    if cache == nil then cache = Tones.parse(Tones.io.read()) end
    return cache
end

-- the remembered tone, or nil for the default (also when the remembered one isn't the instrument's any more)
function Tones.get(fullType)
    local tone = load()[fullType]
    if tone and Tones.valid(fullType, tone) then return tone end
    return nil
end

function Tones.set(fullType, tone)
    local map = load()
    map[fullType] = tone
    Tones.io.write(Tones.format(map))
end

-- the remembered echo strength 0..1 (0 when unset, unreadable or on the drums)
function Tones.getEcho(fullType)
    local def = PlayIt.Instruments.defs[fullType]
    if def and def.drums then return 0 end
    if echoCache == nil then echoCache = Tones.parse(Tones.echoIo.read(), "%-?[%d%.]+") end
    local value = tonumber(echoCache[fullType])
    if value == nil then return 0 end
    return math.max(0, math.min(1, value))
end

function Tones.setEcho(fullType, value)
    Tones.getEcho(fullType)
    echoCache[fullType] = string.format("%.2f", value)
    Tones.echoIo.write(Tones.format(echoCache))
end
