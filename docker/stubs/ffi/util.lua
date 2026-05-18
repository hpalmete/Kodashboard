-- Minimal stub of KOReader's ffi/util. Only joinPath is used by the plugin
-- code we care about.

local M = {}

function M.joinPath(a, b)
    if a == nil or a == "" then return b end
    if b == nil or b == "" then return a end
    if a:sub(-1) == "/" then
        return a .. b
    end
    return a .. "/" .. b
end

function M.template(str, ...)
    local args = { ... }
    return (str:gsub("%%(%d+)", function(i)
        local v = args[tonumber(i)]
        return tostring(v)
    end))
end

return M
