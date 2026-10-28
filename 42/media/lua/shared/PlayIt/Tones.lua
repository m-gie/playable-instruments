-- The tone each instrument was last played with, on the player's own computer (Zomboid/Lua/PlayIt/tones.txt, one
-- "fullType=tone" line each), so the music window opens with it on every character and server.

require "PlayIt/Instruments"

PlayIt = PlayIt or {}
PlayIt.Tones = PlayIt.Tones or {}
local Tones = PlayIt.Tones

Tones.FILE = "PlayIt/tones.txt"

-- file access, replaceable for tests: read() -> text or nil, write(text)
Tones.io = {
    read = function()
        local reader = getFileReader(Tones.FILE, false)
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
        local writer = getFileWriter(Tones.FILE, true, false)
        writer:write(text)
        writer:close()
    end,
}

function Tones.parse(text)
    local map = {}
    for line in (text or ""):gmatch("[^\r\n]+") do
        local fullType, tone = line:match("^%s*([%w%._]+)%s*=%s*([%w_]+)%s*$")
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

local cache

-- forget the cached file (tests)
function Tones.reset() cache = nil end

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
