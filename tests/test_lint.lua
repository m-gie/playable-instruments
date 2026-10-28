-- Static checks over every shipped file, for what the offline Lua accepts but the game's Kahlua doesn't.
local function read(path) local f = io.open(ROOT .. "/" .. path, "rb"); local s = f:read("*a"); f:close(); return s end

local nextUsers, badPercent = {}, {}
for _, path in ipairs(SHIPPED) do
    if path:match("%.lua$") then
        local code = read(path):gsub("%-%-[^\n]*", "") -- comments don't run
        if code:find("[^%w_%.:]next%s*%(") then table.insert(nextUsers, path) end
    elseif path:match("/Translate/.*%.json$") then
        -- the game formats translations: a percent sign is "%%", "%1".."%9" are arguments
        local text = read(path):gsub("%%%%", ""):gsub("%%%d", "")
        if text:find("%%") then table.insert(badPercent, path) end
    end
end
check(#nextUsers == 0, "Kahlua has no next(): " .. table.concat(nextUsers, ", "))
check(#badPercent == 0, "bare % in translations: " .. table.concat(badPercent, ", "))

-- every shipped Lua file at least compiles (client and server code have no offline tests of their own)
local broken = {}
for _, path in ipairs(SHIPPED) do
    if path:match("%.lua$") then
        local fn, err = loadstring(read(path), path)
        if not fn then table.insert(broken, err) end
    end
end
check(#broken == 0, "Lua that doesn't compile: " .. table.concat(broken, "; "))
