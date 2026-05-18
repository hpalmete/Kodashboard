-- Tiny stdout/stderr logger compatible with KOReader's logger surface
-- (logger.dbg / logger.info / logger.warn / logger.err).

local function emit(level, stream, ...)
    local n = select("#", ...)
    local parts = { "[" .. level .. "]" }
    for i = 1, n do
        parts[#parts + 1] = tostring((select(i, ...)))
    end
    stream:write(table.concat(parts, " ") .. "\n")
end

local debug_enabled = (os.getenv("KO_LOG_DEBUG") or "") ~= ""

return {
    dbg  = function(...) if debug_enabled then emit("DBG", io.stdout, ...) end end,
    info = function(...) emit("INFO", io.stdout, ...) end,
    warn = function(...) emit("WARN", io.stderr, ...) end,
    err  = function(...) emit("ERR",  io.stderr, ...) end,
}
