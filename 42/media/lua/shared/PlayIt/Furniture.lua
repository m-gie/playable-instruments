-- Instruments that are furniture (pianos, organ, drum pieces): recognising their tiles, how close a musician must
-- be, which drum pieces make a kit, and whether someone may (still) play here. The rules take game access through
-- ctx so they can be tested offline; the adapters at the bottom are the game side.

require "PlayIt/Instruments"

PlayIt = PlayIt or {}
PlayIt.Furniture = PlayIt.Furniture or {}
local Furniture = PlayIt.Furniture

Furniture.REACH = 1.5 -- tiles from the musician to the edge of the instrument's tile
Furniture.SCAN = 2 -- tiles around the musician searched for drum pieces
Furniture.STICK = "Base.Drumstick"

-- CustomName / GroupName of the vanilla sprites (B42 newtiledefinitions)
local KINDS = {
    ["Piano/Western"] = { "PlayIt.WesternPiano" },
    ["Grand Piano/Black"] = { "PlayIt.GrandPiano" },
    ["Organ/Church"] = { "PlayIt.ChurchOrgan" },
    ["Drum/Kick"] = { "PlayIt.Drums", "kick" },
    ["Drum/Snare"] = { "PlayIt.Drums", "snare" },
    ["Drum/Tom"] = { "PlayIt.Drums", "tom" },
}

-- full type and drum piece (nil for pianos and the organ) of a tile, or nil when it isn't an instrument
function Furniture.classify(customName, groupName)
    local kind = KINDS[tostring(customName) .. "/" .. tostring(groupName)]
    if kind == nil then return nil end
    return kind[1], kind[2]
end

-- same floor, and the musician at (px, py) within REACH of the tile square [x, x+1] x [y, y+1]
function Furniture.inReach(px, py, pz, x, y, z)
    if math.floor(pz) ~= z then return false end
    local dx = math.max(x - px, 0, px - (x + 1))
    local dy = math.max(y - py, 0, py - (y + 1))
    return dx * dx + dy * dy <= Furniture.REACH * Furniture.REACH
end

local function dist2(px, py, t)
    local dx, dy = t.x + 0.5 - px, t.y + 0.5 - py
    return dx * dx + dy * dy
end

-- found: { {x, y, z, piece}, ... } drum tiles around; the kit is the nearest in-reach tile of each piece
function Furniture.kitAround(found, px, py, pz)
    local best = {}
    for _, t in ipairs(found) do
        if t.piece and Furniture.inReach(px, py, pz, t.x, t.y, t.z) then
            local b = best[t.piece]
            if b == nil or dist2(px, py, t) < dist2(px, py, b) then best[t.piece] = t end
        end
    end
    local kit = {}
    for _, piece in ipairs({ "kick", "snare", "tom" }) do
        local t = best[piece]
        if t then kit[#kit + 1] = { piece = piece, x = t.x, y = t.y, z = t.z } end
    end
    return kit
end

function Furniture.kitSet(kit)
    local set = {}
    for _, k in ipairs(kit or {}) do set[k.piece] = true end
    return set
end

local function has(list, fullType, piece)
    for _, f in ipairs(list) do
        if f.fullType == fullType and (piece == nil or f.piece == nil or f.piece == piece) then return true end
    end
    return false
end

-- may the musician play (or keep playing) the instrument at place? place: { x, y, z, kit (drums) };
-- ctx: { px, py, pz, hasStick, look(x, y, z) -> { {fullType, piece}, ... } }. Returns true, or false and
-- "Gone" | "TooFar" | "NoSticks"
function Furniture.check(fullType, place, ctx)
    if PlayIt.Instruments.defs[fullType] and PlayIt.Instruments.defs[fullType].drums then
        if not ctx.hasStick then return false, "NoSticks" end
        local present = false
        for _, k in ipairs(place.kit or {}) do
            if has(ctx.look(k.x, k.y, k.z), fullType, k.piece) then
                present = true
                if Furniture.inReach(ctx.px, ctx.py, ctx.pz, k.x, k.y, k.z) then return true end
            end
        end
        return false, present and "TooFar" or "Gone"
    end
    if not has(ctx.look(place.x, place.y, place.z), fullType) then return false, "Gone" end
    if not Furniture.inReach(ctx.px, ctx.py, ctx.pz, place.x, place.y, place.z) then return false, "TooFar" end
    return true
end

-- game side ------------------------------------------------------------------------------------------------

-- the instruments among one object's sprite properties: fullType, piece, or nil
function Furniture.ofObject(obj)
    local sprite = obj and obj:getSprite()
    local props = sprite and sprite:getProperties()
    if props == nil or not props:has("CustomName") then return nil end
    return Furniture.classify(props:get("CustomName"), props:has("GroupName") and props:get("GroupName") or nil)
end

-- { {fullType, piece, object}, ... } on the square at x, y, z (none when it isn't loaded)
function Furniture.look(x, y, z)
    local out = {}
    local square = getCell():getGridSquare(x, y, z)
    if square == nil then return out end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        local fullType, piece = Furniture.ofObject(obj)
        if fullType then out[#out + 1] = { fullType = fullType, piece = piece, object = obj } end
    end
    return out
end

-- every instrument tile within SCAN tiles of (px, py) on floor pz: { {x, y, z, fullType, piece}, ... }
function Furniture.scan(px, py, pz)
    local out = {}
    local cx, cy, z = math.floor(px), math.floor(py), math.floor(pz)
    for x = cx - Furniture.SCAN, cx + Furniture.SCAN do
        for y = cy - Furniture.SCAN, cy + Furniture.SCAN do
            for _, f in ipairs(Furniture.look(x, y, z)) do
                out[#out + 1] = { x = x, y = y, z = z, fullType = f.fullType, piece = f.piece }
            end
        end
    end
    return out
end

function Furniture.ctxFor(player)
    return {
        px = player:getX(), py = player:getY(), pz = player:getZ(),
        hasStick = player:getInventory():contains(Furniture.STICK),
        look = Furniture.look,
    }
end
