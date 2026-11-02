-- Saved songs: one ABC file per song under Zomboid/Lua/PlayIt/abc/, plus an index (Lua can't list folders).
-- Files are saved as .txt: since B42.21 getFileWriter only writes ini/cfg/txt/log/json. Older .abc files still load.
-- They live on the player's own computer, so they follow them across characters and servers. (Songs saved in the
-- old SS13 format, under PlayIt/songs/, are left alone.)

PlayIt = PlayIt or {}
PlayIt.SongFiles = PlayIt.SongFiles or {}
local SongFiles = PlayIt.SongFiles

SongFiles.DIR = "PlayIt/abc/"
SongFiles.INDEX = "PlayIt/abc_index.txt" -- outside DIR, so no song name can overwrite it
SongFiles.MAX_NAME = 40

function SongFiles.sanitizeName(name)
    local clean = (name or ""):gsub("[^%w %-_]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    clean = clean:sub(1, SongFiles.MAX_NAME):gsub("%s+$", "")
    if clean == "" then return nil end
    return clean
end

function SongFiles.addToIndex(names, name)
    -- case-insensitive: "Song" and "song" are the same file on Windows
    local out, seen = {}, {}
    for _, n in ipairs(names) do
        if not seen[n:lower()] then out[#out + 1] = n; seen[n:lower()] = true end
    end
    if not seen[name:lower()] then out[#out + 1] = name end
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

-- false if the game refused to open the file
local function writeAll(path, content)
    local writer = getFileWriter(path, true, false)
    if writer == nil then return false end
    writer:write(content)
    writer:close()
    return true
end

function SongFiles.list()
    return readAll(SongFiles.INDEX) or {}
end

-- returns the saved name, or nil plus "name" (unusable name) or "write" (file could not be written);
-- the text is kept as pasted
function SongFiles.save(name, text)
    name = SongFiles.sanitizeName(name)
    if name == nil then return nil, "name" end
    if not writeAll(SongFiles.DIR .. name .. ".txt", text) then return nil, "write" end
    if not writeAll(SongFiles.INDEX, table.concat(SongFiles.addToIndex(SongFiles.list(), name), "\n") .. "\n") then
        return nil, "write"
    end
    return name
end

-- the song's text; nil if missing
function SongFiles.load(name)
    local lines = readAll(SongFiles.DIR .. name .. ".txt") or readAll(SongFiles.DIR .. name .. ".abc")
    if lines == nil then return nil end
    return table.concat(lines, "\n")
end
