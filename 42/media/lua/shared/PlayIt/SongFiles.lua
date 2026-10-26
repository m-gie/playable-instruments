-- Saved songs: one file per song under Zomboid/Lua/PlayIt/songs/, plus an index (Lua can't list folders).
-- They live on the player's own computer, so they follow them across characters and servers.

require "PlayIt/Song"

PlayIt = PlayIt or {}
PlayIt.SongFiles = PlayIt.SongFiles or {}
local SongFiles = PlayIt.SongFiles

SongFiles.DIR = "PlayIt/songs/"
SongFiles.INDEX = SongFiles.DIR .. "index.txt"
SongFiles.MAX_NAME = 40

function SongFiles.sanitizeName(name)
    local clean = (name or ""):gsub("[^%w %-_]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    clean = clean:sub(1, SongFiles.MAX_NAME):gsub("%s+$", "")
    if clean == "" then return nil end
    return clean
end

-- file content: "BPM: n" header, then the song without any header of its own
function SongFiles.encode(text, bpm)
    local body = text
    if PlayIt.Song.readBpmHeader(text) then body = text:gsub("^[^\n]*\n?", "", 1) end
    return "BPM: " .. tostring(bpm) .. "\n" .. body
end

-- text without the header, and the header's bpm (nil if none)
function SongFiles.decode(content)
    local bpm = PlayIt.Song.readBpmHeader(content)
    if bpm == nil then return content, nil end
    return (content:gsub("^[^\n]*\n?", "", 1)), bpm
end

function SongFiles.addToIndex(names, name)
    local out, seen = {}, {}
    for _, n in ipairs(names) do
        if not seen[n] then out[#out + 1] = n; seen[n] = true end
    end
    if not seen[name] then out[#out + 1] = name end
    table.sort(out, function(a, b) return a:lower() < b:lower() end)
    return out
end

local function readAll(path)
    local reader = getFileReader(path, false)
    if reader == nil then return nil end
    local lines = {}
    local line = reader:readLine()
    while line ~= nil do
        lines[#lines + 1] = line
        line = reader:readLine()
    end
    reader:close()
    return lines
end

local function writeAll(path, content)
    local writer = getFileWriter(path, true, false)
    writer:write(content)
    writer:close()
end

function SongFiles.list()
    return readAll(SongFiles.INDEX) or {}
end

-- returns the saved name, or nil if the name is unusable
function SongFiles.save(name, text, bpm)
    name = SongFiles.sanitizeName(name)
    if name == nil then return nil end
    writeAll(SongFiles.DIR .. name .. ".txt", SongFiles.encode(text, bpm))
    writeAll(SongFiles.INDEX, table.concat(SongFiles.addToIndex(SongFiles.list(), name), "\n") .. "\n")
    return name
end

-- text, bpm (bpm nil if the file has no header); nil if missing
function SongFiles.load(name)
    local lines = readAll(SongFiles.DIR .. name .. ".txt")
    if lines == nil then return nil end
    return SongFiles.decode(table.concat(lines, "\n"))
end
