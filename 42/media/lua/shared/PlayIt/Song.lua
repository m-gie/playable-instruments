-- SS13 legacy song text parser (tgstation code/modules/instruments/songs/play_legacy.dm + editor.dm).
-- "BPM: n" header; lines of comma-separated chords; notes joined with "-"; "/n" divides a chord's length;
-- octave digit and accidental (# b n) stick to their letter for the rest of the song.

PlayIt = PlayIt or {}
PlayIt.Song = PlayIt.Song or {}
local Song = PlayIt.Song

Song.MAX_LINES = 300
Song.MAX_LINE_CHARS = 300
Song.BPM_MIN = 12
Song.BPM_MAX = 600
Song.BPM_DEFAULT = 120
Song.DIVISOR_MIN = 1 / 16 -- "/n" is clamped so a chord lasts between 16 beats and 1/64 of a beat
Song.DIVISOR_MAX = 64

local OFFSET = { c = 0, d = 2, e = 4, f = 5, g = 7, a = 9, b = 11 }
local ACCIDENTAL = { ["#"] = 1, b = -1, n = 0 }

local function clampBpm(bpm)
    return math.max(Song.BPM_MIN, math.min(Song.BPM_MAX, bpm))
end

local function splitLines(text)
    local lines = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = line:gsub("\r", "")
    end
    return lines
end

local function split(s, sep)
    local parts = {}
    for part in (s .. sep):gmatch("(.-)" .. sep) do parts[#parts + 1] = part end
    return parts
end

-- what follows "BPM:" on a header line, or nil; tolerant of a BOM, spaces and letter case (pasted text)
local function headerValue(line)
    if line == nil then return nil end
    -- the BOM is written as the literal character: Kahlua strings hold it as one char (U+FEFF)
    return (line:gsub("^﻿", "")):match("^%s*[Bb][Pp][Mm]:(.*)$")
end

local function hasHeader(line)
    return headerValue(line) ~= nil
end

-- nil when the first line is not a "BPM:" header
function Song.readBpmHeader(text)
    local value = headerValue(splitLines(text or "")[1])
    if value == nil then return nil end
    return clampBpm(tonumber(value:match("^%s*(%-?[%d%.]+)")) or Song.BPM_DEFAULT)
end

local function parseNote(note, state)
    local letter = note:sub(1, 1)
    if OFFSET[letter] == nil then return nil end
    for i = 2, #note do
        local ch = note:sub(i, i)
        local digit = tonumber(ch)
        if digit then
            if digit > 0 then
                state.octave[letter] = math.min(digit, letter == "c" and 9 or 8)
            end
        elseif ACCIDENTAL[ch] then
            state.accidental[letter] = ACCIDENTAL[ch]
        end
    end
    local octave = state.octave[letter] or 3
    return 12 * (octave + 1) + OFFSET[letter] + (state.accidental[letter] or 0)
end

local function parseChord(piece, state)
    local parts = split(piece, "/")
    local divisor = tonumber(parts[2] or "")
    if divisor == nil or divisor <= 0 then divisor = 1 end
    divisor = math.max(Song.DIVISOR_MIN, math.min(Song.DIVISOR_MAX, divisor))
    local notes = {}
    for _, note in ipairs(split(parts[1], "-")) do
        local midi = note ~= "" and parseNote(note, state) or nil
        if midi then notes[#notes + 1] = midi end
    end
    return { notes = notes, beats = 1 / divisor }
end

function Song.cleanLine(line)
    return (line:lower():gsub("[^a-g0-9#n,/%-%.]", ""))
end

-- the song reduced to what plays (ASCII only, no blank or skipped lines): what goes over the network
function Song.compact(text)
    local lines = splitLines(text or "")
    local out = {}
    local header = Song.readBpmHeader(text or "")
    if hasHeader(lines[1]) then
        table.remove(lines, 1)
        out[1] = "BPM: " .. tostring(header)
    end
    for n = 1, math.min(#lines, Song.MAX_LINES) do
        local line = lines[n]
        if #line <= Song.MAX_LINE_CHARS then
            local clean = Song.cleanLine(line)
            if clean ~= "" then out[#out + 1] = clean end
        end
    end
    return table.concat(out, "\n")
end

-- bpm: the menu field; wins over the header. Returns { bpm, chords = { {notes, beats} }, warnings = { {key, line} } }
function Song.parse(text, bpm)
    text = text or ""
    local lines = splitLines(text)
    local header = Song.readBpmHeader(text)
    if hasHeader(lines[1]) then table.remove(lines, 1) end

    local song = { chords = {}, warnings = {} }
    if type(bpm) == "number" then
        song.bpm = clampBpm(bpm)
    else
        song.bpm = header or Song.BPM_DEFAULT
    end

    if #lines > Song.MAX_LINES then
        for i = #lines, Song.MAX_LINES + 1, -1 do lines[i] = nil end
        table.insert(song.warnings, { key = "TooManyLines", line = Song.MAX_LINES })
    end

    local state = { octave = {}, accidental = {} }
    for n, line in ipairs(lines) do
        if #line > Song.MAX_LINE_CHARS then
            table.insert(song.warnings, { key = "LineTooLong", line = n })
        else
            local clean = Song.cleanLine(line)
            if clean ~= "" then
                for _, piece in ipairs(split(clean, ",")) do
                    table.insert(song.chords, parseChord(piece, state))
                end
            end
        end
    end
    return song
end
