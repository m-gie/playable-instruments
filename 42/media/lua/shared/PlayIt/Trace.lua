-- Debug-mode-only tracing ("[PlayIt]" lines in console.txt), for chasing in-game problems.

PlayIt = PlayIt or {}

function PlayIt.trace(fmt, ...)
    if isDebugEnabled and isDebugEnabled() then print("[PlayIt] " .. string.format(fmt, ...)) end
end
