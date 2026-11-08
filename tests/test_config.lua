require "PlayIt/Config"
local C = PlayIt.Config
local function near(a, b) return math.abs(a - b) < 1e-9 end

SandboxVars = nil
local c = C.get()
check(c.skillOn == true and near(c.p0, 0.5) and near(c.p10, 0.0001) and c.annoy == true and c.noiseMult == 1.0, "defaults without SandboxVars")
SandboxVars = {}
c = C.get(); check(c.skillOn == true and near(c.p0, 0.5), "defaults without the PlayIt group")
SandboxVars = { PlayIt = { SkillEnabled = false, BlunderLevel0 = 20, BlunderLevel10 = 1, BlundersAnnoy = false, NoiseMultiplier = 2 } }
c = C.get()
check(c.skillOn == false and near(c.p0, 0.2) and near(c.p10, 0.01) and c.annoy == false and c.noiseMult == 2, "sandbox values, percentages as fractions")

-- sandbox and perk files define what Config reads
local function read(path) local f = io.open(ROOT .. "/" .. path); local s = f and f:read("*a"); if f then f:close() end; return s or "" end
local sandbox = read("42/media/sandbox-options.txt")
for _, name in ipairs({ "SkillEnabled", "BlunderLevel0", "BlunderLevel10", "BlundersAnnoy", "NoiseMultiplier" }) do
    check(sandbox:find("option PlayIt." .. name, 1, true) ~= nil, "sandbox option " .. name)
end
-- the engine reads "MultiplierConfig.<perk>" when the global XP multiplier is off (Outbreak preset): without
-- this option AddXP throws and no Music XP is ever gained (user report, 2026-11-08)
check(sandbox:find("option MultiplierConfig.PlayItMusic", 1, true) ~= nil, "per-skill XP multiplier option")
local perks = read("42/media/perks.txt")
check(perks:find("perk PlayItMusic", 1, true) ~= nil and perks:find("xp10 = 6000", 1, true) ~= nil, "Music perk defined")
for _, lang in ipairs({ "EN", "PL" }) do
    local sb = read("42/media/lua/shared/Translate/" .. lang .. "/Sandbox.json")
    local ui = read("42/media/lua/shared/Translate/" .. lang .. "/IG_UI.json")
    check(sb:find('"Sandbox_PlayIt_BlunderLevel0"', 1, true) ~= nil, lang .. " sandbox strings")
    check(ui:find('"IGUI_perks_PlayItMusic"', 1, true) ~= nil, lang .. " perk name")
    check(sb:find('"Sandbox_PlayIt_MusicXP"', 1, true) ~= nil, lang .. " XP multiplier string")
end
