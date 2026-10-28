-- ABC notation songs (abcnotation.com; the subset real files and the playit-midi converter use).
-- A file holds one or more tunes (X:), a tune may hold voices (V:); each tune or voice is a part a musician plays.
-- One pass over the text, no backtracking patterns, every number clamped: the server parses what players send.

PlayIt = PlayIt or {}
PlayIt.Song = PlayIt.Song or {}
local Song = PlayIt.Song

Song.BPM_MIN = 12
Song.BPM_MAX = 600
Song.BPM_DEFAULT = 120
Song.MAX_EVENTS = 10000 -- notes, chords and rests per part after repeats (the converter counts the same way)
Song.BEATS_MIN = 1 / 64 -- a note's length in quarter notes
Song.BEATS_MAX = 64

local OFFSET = { C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11 }
local SHARPS = { "F", "C", "G", "D", "A", "E", "B" } -- order sharps are added to a key; flats go backwards
local MAJOR_SHARPS = { C = 0, G = 1, D = 2, A = 3, E = 4, B = 5, ["F#"] = 6, ["C#"] = 7,
    F = -1, Bb = -2, Eb = -3, Ab = -4, Db = -5, Gb = -6, Cb = -7,
    ["G#"] = 8, ["D#"] = 9, ["A#"] = 10, ["E#"] = 11, ["B#"] = 12, Fb = -8 }
local MODE_SHIFT = { maj = 0, ion = 0, mix = -1, dor = -2, aeo = -3, min = -3, m = -3, phr = -4, loc = -5, lyd = 1 }

-- General MIDI percussion names (%%percmap), as abcm2ps and abcjs spell them
local GM_NAMES = {
    ["acoustic-bass-drum"] = 35, ["bass-drum-1"] = 36, ["side-stick"] = 37, ["acoustic-snare"] = 38,
    ["hand-clap"] = 39, ["electric-snare"] = 40, ["low-floor-tom"] = 41, ["closed-hi-hat"] = 42,
    ["high-floor-tom"] = 43, ["pedal-hi-hat"] = 44, ["low-tom"] = 45, ["open-hi-hat"] = 46, ["low-mid-tom"] = 47,
    ["hi-mid-tom"] = 48, ["crash-cymbal-1"] = 49, ["high-tom"] = 50, ["ride-cymbal-1"] = 51,
    ["chinese-cymbal"] = 52, ["ride-bell"] = 53, ["tambourine"] = 54, ["splash-cymbal"] = 55, ["cowbell"] = 56,
    ["crash-cymbal-2"] = 57, ["vibraslap"] = 58, ["ride-cymbal-2"] = 59, ["hi-bongo"] = 60, ["low-bongo"] = 61,
    ["mute-hi-conga"] = 62, ["open-hi-conga"] = 63, ["low-conga"] = 64, ["high-timbale"] = 65,
    ["low-timbale"] = 66, ["high-agogo"] = 67, ["low-agogo"] = 68, ["cabasa"] = 69, ["maracas"] = 70,
    ["short-whistle"] = 71, ["long-whistle"] = 72, ["short-guiro"] = 73, ["long-guiro"] = 74, ["claves"] = 75,
    ["hi-wood-block"] = 76, ["low-wood-block"] = 77, ["mute-cuica"] = 78, ["open-cuica"] = 79,
    ["mute-triangle"] = 80, ["open-triangle"] = 81,
}

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function clampBpm(bpm) return clamp(bpm, Song.BPM_MIN, Song.BPM_MAX) end
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function splitLines(text)
    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = (line:gsub("\r", ""))
    end
    -- a BOM, written as the literal character: Kahlua strings hold it as one char (U+FEFF), lupa as its 3 bytes
    if lines[1] then lines[1] = lines[1]:gsub("^﻿", "") end
    return lines
end

local function fieldOf(line)
    local f, value = line:match("^%s*([A-Za-z]):(.*)$")
    return f, value
end

local function isDirective(line) return line:sub(1, 2) == "%%" end

local function channel10(line)
    return line:lower():match("^%%%%midi%s+channel%s+10%s*$") ~= nil
end

-- what plays and travels: no comments, lyrics, blank lines or trailing spaces
function Song.compact(text)
    local out = {}
    for _, line in ipairs(splitLines(text or "")) do
        if not isDirective(line) then
            local cut = line:find("%", 1, true)
            if cut then line = line:sub(1, cut - 1) end
        end
        line = line:gsub("%s+$", "")
        local f = fieldOf(line)
        if line ~= "" and f ~= "w" and f ~= "W" then out[#out + 1] = line end
    end
    return table.concat(out, "\n")
end

-- the voice a V: field or [V:] names, and its name="..." if given
local function voiceOf(value)
    local id = value:match("^%s*([^%s%]]+)")
    local name = value:match('name%s*=%s*"([^"]*)"') or value:match('nm%s*=%s*"([^"]*)"')
    return id, name
end

-- one playable part per tune, or per voice when a tune has V: voices: { {title, text}, ... }
function Song.parts(text)
    local lines = splitLines(text or "")
    local fileHeader, tunes = {}, {}
    local cur
    for _, line in ipairs(lines) do
        local f, value = fieldOf(line)
        if f == "X" then
            cur = { number = trim(value), lines = {} }
            tunes[#tunes + 1] = cur
        elseif cur then
            cur.lines[#cur.lines + 1] = line
        elseif isDirective(line) then
            fileHeader[#fileHeader + 1] = line
        end
    end
    local parts = {}
    for _, t in ipairs(tunes) do
        local header, title, voices, order, inBody, voice = {}, nil, {}, {}, false, nil
        for _, line in ipairs(t.lines) do
            local f, value = fieldOf(line)
            local inline = line:match("^%s*%[V:([^%]]*)%]")
            if f == "V" or inline then
                local id, name = voiceOf(f == "V" and value or inline)
                if id then
                    if voices[id] == nil then
                        voices[id] = { name = name, lines = {} }
                        order[#order + 1] = id
                    elseif name then
                        voices[id].name = name
                    end
                    if inBody then voice = id end
                    if inline then
                        local rest = line:gsub("^%s*%[V:[^%]]*%]", "")
                        if inBody and rest ~= "" then table.insert(voices[id].lines, rest) end
                    end
                end
            elseif not inBody then
                if f == "T" and title == nil then title = trim(value) end
                header[#header + 1] = line
                if f == "K" then inBody = true end
            else
                if voice == nil and order[1] then voice = order[1] end
                if voice then
                    table.insert(voices[voice].lines, line)
                else
                    header[#header + 1] = line -- a tune without voices: its body
                end
            end
        end
        local base = {}
        for _, l in ipairs(fileHeader) do base[#base + 1] = l end
        base[#base + 1] = "X:" .. t.number
        for _, l in ipairs(header) do base[#base + 1] = l end
        title = (title and title ~= "") and title or t.number
        if #order == 0 then
            parts[#parts + 1] = { title = title, text = table.concat(base, "\n") }
        else
            for _, id in ipairs(order) do
                local v = voices[id]
                local all = {}
                for _, l in ipairs(base) do all[#all + 1] = l end
                for _, l in ipairs(v.lines) do all[#all + 1] = l end
                parts[#parts + 1] = { title = title .. ": " .. (v.name or id), text = table.concat(all, "\n") }
            end
        end
    end
    return parts
end

-- parsing state helpers ---------------------------------------------------------------------------------------

local function parseMeter(value)
    value = trim(value)
    if value == "C" then return 4, 4 end
    if value == "C|" then return 2, 2 end
    local nums, den = value:match("^([%d%+]+)%s*/%s*(%d+)")
    if nums == nil then return nil end
    local num = 0
    for n in nums:gmatch("%d+") do num = num + tonumber(n) end
    den = tonumber(den)
    if num <= 0 or den <= 0 then return nil end
    return clamp(num, 1, 64), clamp(den, 1, 64)
end

local function parseFraction(value)
    local n, d = value:match("^%s*(%d+)%s*/%s*(%d+)")
    n, d = tonumber(n), tonumber(d)
    if n == nil or d == nil or n <= 0 or d <= 0 then return nil end
    return n / d
end

-- quarter notes a minute, or nil
local function parseTempo(value)
    value = value:gsub('"[^"]*"', "")
    local beat, bpm = value:match("(%d+%s*/%s*%d+)%s*=%s*(%d+%.?%d*)")
    if beat then
        local f = parseFraction(beat)
        bpm = tonumber(bpm)
        if f == nil or bpm == nil or bpm <= 0 then return nil end
        return f * 4 * bpm
    end
    bpm = tonumber(value:match("^%s*(%d+%.?%d*)%s*$") or "")
    if bpm == nil or bpm <= 0 then return nil end
    return bpm
end

-- accidental per letter for a key: { F = 1, ... }
local function parseKey(value)
    local sig = {}
    value = trim(value)
    local tonic, acc, rest = value:match("^([A-G])([#b]?)(.*)$")
    if tonic == nil then return sig end -- none, HP, clef only: no signature
    local sharps = MAJOR_SHARPS[tonic .. acc]
    if sharps == nil then return sig end
    local mode = (rest:match("^%s*(%a+)") or ""):lower()
    local shift = MODE_SHIFT[mode:sub(1, 3)]
    if shift == nil and mode == "m" then shift = -3 end
    sharps = sharps + (shift or 0)
    sharps = clamp(sharps, -7, 7)
    if sharps > 0 then
        for i = 1, sharps do sig[SHARPS[i]] = 1 end
    else
        for i = 1, -sharps do sig[SHARPS[8 - i]] = -1 end
    end
    return sig
end

-- the parser ------------------------------------------------------------------------------------------------

local Parser = {}
Parser.__index = Parser

local function newParser()
    return setmetatable({
        unit = nil, meterNum = nil, meterDen = nil, key = {}, barAcc = {}, qpm = nil, title = nil,
        drums = false, percmap = {}, items = {}, tokens = 0, overflow = false,
        tuplet = nil, broken = nil, last = nil, headerDone = false,
    }, Parser)
end

function Parser:unitBeats()
    if self.unit then return self.unit end
    if self.meterNum and self.meterNum / self.meterDen < 0.75 then return 0.25 end -- 1/16
    return 0.5 -- 1/8
end

function Parser:barBeats()
    if self.meterNum then return self.meterNum * 4 / self.meterDen end
    return 4
end

function Parser:field(f, value)
    if f == "M" then
        local n, d = parseMeter(value)
        self.meterNum, self.meterDen = n, d
    elseif f == "L" then
        local u = parseFraction(value)
        if u then self.unit = clamp(u * 4, Song.BEATS_MIN, Song.BEATS_MAX) end
    elseif f == "Q" then
        local q = parseTempo(value)
        if q then self.qpm = clampBpm(q) end
    elseif f == "K" then
        self.key = parseKey(value)
        self.barAcc = {}
        self.headerDone = true
    elseif f == "T" then
        if self.title == nil then self.title = trim(value) end
    end
end

function Parser:directive(line)
    if channel10(line) then
        self.drums = true
        return
    end
    local note, target = line:match("^%%%%percmap%s+(%S+)%s+(%S+)")
    if note then
        local written = self:pitchOf(note, true)
        local gm = tonumber(target) or GM_NAMES[target:lower()]
        if written and gm then self.percmap[written] = clamp(math.floor(gm), 0, 127) end
    end
end

-- MIDI number of a written note ("^F,"); neutral = no key signature or bar accidentals (for %%percmap)
function Parser:pitchOf(text, neutral)
    local i, acc = 1, nil
    while text:sub(i, i) == "^" or text:sub(i, i) == "_" or text:sub(i, i) == "=" do
        local ch = text:sub(i, i)
        acc = (acc or 0) + (ch == "^" and 1 or ch == "_" and -1 or 0)
        if ch == "=" then acc = 0 end
        i = i + 1
    end
    local letter = text:sub(i, i)
    if OFFSET[letter:upper()] == nil then return nil end
    local midi = OFFSET[letter:upper()] + (letter == letter:upper() and 60 or 72)
    i = i + 1
    while text:sub(i, i) == "'" or text:sub(i, i) == "," do
        midi = midi + (text:sub(i, i) == "'" and 12 or -12)
        i = i + 1
    end
    if neutral then return clamp(midi + (acc or 0), 0, 127) end
    return midi, acc, letter:upper()
end

function Parser:add(item)
    if self.tokens >= Song.MAX_EVENTS * 2 then
        self.overflow = true
        return
    end
    if item.kind == "chord" then self.tokens = self.tokens + 1 end
    self.items[#self.items + 1] = item
end

-- reads a length at position i; returns multiplier, next i
local function readLength(s, i)
    local digits = s:match("^%d+", i)
    local num = 1
    if digits then
        num = tonumber(digits:sub(1, 6)) or 1
        i = i + #digits
    end
    local den = 1
    while s:sub(i, i) == "/" do
        i = i + 1
        local d = s:match("^%d+", i)
        if d then
            den = den * (tonumber(d:sub(1, 6)) or 1)
            i = i + #d
        else
            den = den * 2
        end
        if den > 4096 then den = 4096 end
    end
    if num == 0 or den == 0 then return 1, i end
    return num / den, i
end

-- reads one note at i (accidentals, letter, octave marks, length, tie); nil if none there
function Parser:readNote(s, i)
    local start = i
    while s:sub(i, i):match("^[%^_=]$") do i = i + 1 end
    local letter = s:sub(i, i)
    if letter == "" or OFFSET[letter:upper()] == nil then return nil, start end
    i = i + 1
    while s:sub(i, i) == "'" or s:sub(i, i) == "," do i = i + 1 end
    local midi, acc, upper = self:pitchOf(s:sub(start, i - 1))
    local octaveKey = upper .. (midi - OFFSET[upper]) -- same letter and octave
    if acc then
        self.barAcc[octaveKey] = acc
    else
        acc = self.barAcc[octaveKey] or self.key[upper] or 0
    end
    midi = clamp(midi + acc, 0, 127)
    local len
    len, i = readLength(s, i)
    local tie = false
    if s:sub(i, i) == "-" then
        tie = true
        i = i + 1
    end
    return { midi = midi, len = len, tie = tie }, i
end

function Parser:pushChord(notes, len, tieAll)
    local beats = clamp(self:unitBeats() * len, Song.BEATS_MIN, Song.BEATS_MAX)
    if self.tuplet then
        beats = clamp(beats * self.tuplet.factor, Song.BEATS_MIN, Song.BEATS_MAX)
        self.tuplet.left = self.tuplet.left - 1
        if self.tuplet.left <= 0 then self.tuplet = nil end
    end
    if self.broken then
        beats = clamp(beats * self.broken, Song.BEATS_MIN, Song.BEATS_MAX)
        self.broken = nil
    end
    for _, n in ipairs(notes) do
        if tieAll then n.tie = true end
        if self.drums then n.midi = self.percmap[n.midi] or n.midi end
    end
    local item = { kind = "chord", notes = notes, beats = beats, qpm = self.qpm or Song.BPM_DEFAULT }
    self:add(item)
    self.last = item
end

function Parser:bar()
    self.barAcc = {}
end

-- a run of bar characters at i: | || |] [| |: :| :: |1 :|2 ...
function Parser:readBar(s, i)
    local run = s:match("^[|:%]]+", i) or ""
    local j = i + #run
    local nums = s:match("^%d[%d,%-]*", j)
    if nums then j = j + #nums end
    local endRepeat = #run > 1 and run:sub(1, 1) == ":"
    local startRepeat = #run > 1 and run:sub(-1) == ":"
    self:bar()
    self:add({ kind = "bar" })
    if endRepeat then self:add({ kind = "end" }) end
    if startRepeat then self:add({ kind = "start" }) end
    if run:find("||", 1, true) or run:find("|]", 1, true) then self:add({ kind = "double" }) end
    if nums then self:add({ kind = "ending", nums = nums }) end
    if #run == 0 then return i + 1 end
    return j
end

local function endingHas(nums, pass)
    for a, b in nums:gmatch("(%d+)%-?(%d*)") do
        local lo, hi = tonumber(a), tonumber(b) or tonumber(a)
        if pass >= lo and pass <= hi then return true end
    end
    return false
end

function Parser:music(s)
    local i, n = 1, #s
    while i <= n do
        if self.overflow then return end
        local ch = s:sub(i, i)
        if ch == "%" then
            return
        elseif ch == "\"" then
            local close = s:find("\"", i + 1, true)
            i = close and close + 1 or n + 1
        elseif ch == "!" or ch == "+" then
            local close = s:find(ch, i + 1, true)
            i = close and close + 1 or n + 1
        elseif ch == "{" then
            local close = s:find("}", i + 1, true)
            i = close and close + 1 or n + 1
        elseif ch == "[" then
            local nxt = s:sub(i + 1, i + 1)
            if nxt:match("^%a$") and s:sub(i + 2, i + 2) == ":" then
                local close = s:find("]", i + 1, true)
                local body = s:sub(i + 3, (close or n + 1) - 1)
                self:field(nxt, body)
                i = close and close + 1 or n + 1
            elseif nxt:match("^%d$") then
                local nums = s:match("^%d[%d,%-]*", i + 1)
                self:add({ kind = "ending", nums = nums })
                i = i + 1 + #nums
            elseif nxt == "|" then
                self:bar()
                self:add({ kind = "double" })
                i = i + 2
            else
                -- a chord: notes up to ], then its length and tie
                local notes, j = {}, i + 1
                local firstLen
                while j <= n and s:sub(j, j) ~= "]" do
                    local note
                    note, j = self:readNote(s, j)
                    if note then
                        firstLen = firstLen or note.len
                        notes[#notes + 1] = note
                    else
                        j = j + 1
                    end
                end
                local len
                len, j = readLength(s, j + 1)
                local tieAll = false
                if s:sub(j, j) == "-" then
                    tieAll = true
                    j = j + 1
                end
                self:pushChord(notes, (firstLen or 1) * len, tieAll)
                i = j
            end
        elseif ch == "|" or ch == ":" then
            i = self:readBar(s, i)
        elseif ch == "(" then
            local p = s:match("^%d+", i + 1)
            if p then
                local q, r = s:match("^:(%d*):?(%d*)", i + 1 + #p)
                local skip = s:match("^:%d*:?%d*", i + 1 + #p) or ""
                p = tonumber(p:sub(1, 3))
                if p and p >= 2 and p <= 16 then
                    local compound = self.meterNum and self.meterNum % 3 == 0 and self.meterNum > 3
                    local qd = ({ [2] = 3, [3] = 2, [4] = 3, [6] = 2, [8] = 3 })[p] or (compound and 3 or 2)
                    q = clamp(tonumber(q or "") or qd, 1, 16)
                    r = clamp(tonumber(r or "") or p, 1, 16)
                    self.tuplet = { factor = q / p, left = r }
                end
                i = i + 1 + #(s:match("^%d+", i + 1)) + #skip
            else
                i = i + 1 -- a slur
            end
        elseif ch == ">" or ch == "<" then
            local run = s:match("^" .. (ch == ">" and ">+" or "<+"), i)
            local k = math.min(#run, 3)
            local small = 0.5 ^ k
            if self.last then
                local big = 2 - small
                self.last.beats = clamp(self.last.beats * (ch == ">" and big or small), Song.BEATS_MIN, Song.BEATS_MAX)
                self.broken = ch == ">" and small or big
            end
            i = i + #run
        elseif ch == "z" or ch == "x" then
            local len
            len, i = readLength(s, i + 1)
            self:pushChord({}, len, false)
        elseif ch == "Z" or ch == "X" then
            local count = tonumber((s:match("^%d+", i + 1) or "1"):sub(1, 4)) or 1
            i = i + 1 + #(s:match("^%d*", i + 1))
            local beats = clamp(self:barBeats() * clamp(count, 1, 64), Song.BEATS_MIN, Song.BEATS_MAX)
            if count > 0 then
                local item = { kind = "chord", notes = {}, beats = beats, qpm = self.qpm or Song.BPM_DEFAULT }
                self:add(item)
                self.last = item
            end
        elseif ch:match("^[%^_=]$") or OFFSET[ch:upper()] then
            local note
            note, i = self:readNote(s, i)
            if note then
                self:pushChord({ note }, note.len, false)
            else
                i = i + 1
            end
        elseif ch == "-" and self.last then
            for _, note in ipairs(self.last.notes) do note.tie = true end
            i = i + 1
        else
            i = i + 1 -- spaces, decorations (. ~ H L M O P S T u v), line continuation, anything unknown
        end
    end
end

-- repeats and endings played out; every :| jumps back once, so a piece at most doubles.
-- Also returns which chords start a bar: the first, the first after a bar line and the first after a jump.
local function expand(items)
    local out, bars, barNext = {}, {}, true
    local i, pass, start = 1, 1, 1
    local used = {}
    local guard = 0
    while i <= #items and #out < Song.MAX_EVENTS do
        guard = guard + 1
        if guard > Song.MAX_EVENTS * 8 then break end
        local it = items[i]
        if it.kind == "chord" then
            out[#out + 1] = it
            if barNext then bars[#out], barNext = true, false end
            i = i + 1
        elseif it.kind == "bar" then
            barNext = true
            i = i + 1
        elseif it.kind == "start" then
            start, pass = i + 1, 1
            i = i + 1
        elseif it.kind == "end" then
            if not used[i] then
                used[i] = true
                pass = 2
                i = start
                barNext = true
            else
                start = i + 1
                i = i + 1
            end
        elseif it.kind == "ending" and not endingHas(it.nums, pass) then
            local j = i + 1
            while j <= #items do
                local k = items[j]
                if (k.kind == "ending" and endingHas(k.nums, pass)) or k.kind == "start" or k.kind == "double"
                    or (k.kind == "end" and used[j]) then
                    break
                end
                j = j + 1
            end
            i = j
        else
            i = i + 1
        end
    end
    return out, bars
end

-- ties joined, per-note lengths: chords = { {notes = struck midis, lens = beats each, beats, qpm, bar} }
local function resolveTies(items, bars)
    local chords, held = {}, {}
    for idx, it in ipairs(items) do
        local chord = { notes = {}, lens = {}, beats = it.beats, qpm = it.qpm, bar = bars[idx] }
        local nextHeld = {}
        for _, n in ipairs(it.notes) do
            local origin = held[n.midi]
            if origin then
                local c = chords[origin.chord]
                c.lens[origin.slot] = c.lens[origin.slot] + it.beats
                held[n.midi] = nil
                if n.tie then nextHeld[n.midi] = origin end
            else
                chord.notes[#chord.notes + 1] = n.midi
                chord.lens[#chord.lens + 1] = it.beats
                if n.tie then nextHeld[n.midi] = { chord = idx, slot = #chord.notes } end
            end
        end
        chords[idx] = chord
        held = nextHeld
    end
    return chords
end

local function tuneText(text)
    local parts = Song.parts(text)
    if parts[1] then return parts[1].text end
    -- a tune pasted without X: still plays if it has a K: line
    for _, line in ipairs(splitLines(text)) do
        if fieldOf(line) == "K" then return text end
    end
    return nil
end

-- bpm: the menu field (quarter notes a minute); scales every tempo in the part. Returns
-- { bpm, title, drums, events, chords = { {notes, lens, beats, qpm, bar} }, warnings = { {key, line} } }
function Song.parse(text, bpm)
    local song = { chords = {}, warnings = {}, events = 0, drums = false }
    local tune = tuneText(text or "")
    if tune == nil then
        song.bpm = clampBpm(type(bpm) == "number" and bpm or Song.BPM_DEFAULT)
        table.insert(song.warnings, { key = "NotAbc", line = 0 })
        return song
    end
    local p = newParser()
    local startQpm, started = nil, false
    for _, line in ipairs(splitLines(tune)) do
        if p.overflow then break end
        if isDirective(line) then
            p:directive(line)
        else
            local f, value = fieldOf(line)
            if f and p.headerDone and value:match("^[|:]") then f = nil end -- "A:|" is music, not a field
            if f then
                if f ~= "w" and f ~= "W" then p:field(f, (value:gsub("%%.*$", ""))) end
            elseif p.headerDone then
                if not started then startQpm, started = p.qpm, true end
                p:music(line)
            end
        end
    end
    local base = (started and startQpm) or (not started and p.qpm) or Song.BPM_DEFAULT
    local scale = 1
    if type(bpm) == "number" then scale = clampBpm(bpm) / base end
    song.bpm = clampBpm(base * scale)
    local items, bars = expand(p.items)
    song.chords = resolveTies(items, bars)
    for _, c in ipairs(song.chords) do c.qpm = clampBpm(c.qpm * scale) end
    song.events = #song.chords
    song.title, song.drums = p.title, p.drums
    if not p.headerDone then table.insert(song.warnings, { key = "NotAbc", line = 0 }) end -- no K: line
    if p.overflow or song.events >= Song.MAX_EVENTS then
        table.insert(song.warnings, { key = "TooManyNotes", line = Song.MAX_EVENTS })
    end
    return song
end

-- the part's starting tempo, for the BPM field, without parsing the music
function Song.tempoOf(text)
    for _, line in ipairs(splitLines(text or "")) do
        local f, value = fieldOf(line)
        if f == "Q" then
            local q = parseTempo(value)
            if q then return clampBpm(q) end
        end
    end
    return Song.BPM_DEFAULT
end
