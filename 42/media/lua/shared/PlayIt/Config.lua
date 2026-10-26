-- Sandbox settings (world settings page "Play it!"), with defaults when SandboxVars or the group is missing.

PlayIt = PlayIt or {}
PlayIt.Config = PlayIt.Config or {}
local Config = PlayIt.Config

local DEFAULTS = { SkillEnabled = true, BlunderLevel0 = 50, BlunderLevel10 = 0.01, BlundersAnnoy = true, NoiseMultiplier = 1.0 }

local function value(group, name)
    local v = group and group[name]
    if v == nil then return DEFAULTS[name] end
    return v
end

-- { skillOn, p0, p10 (fractions), annoy, noiseMult }
function Config.get()
    local group = SandboxVars and SandboxVars.PlayIt
    return {
        skillOn = value(group, "SkillEnabled"),
        p0 = value(group, "BlunderLevel0") / 100,
        p10 = value(group, "BlunderLevel10") / 100,
        annoy = value(group, "BlundersAnnoy"),
        noiseMult = value(group, "NoiseMultiplier"),
    }
end
