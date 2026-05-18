-- Wrapper around dkjson exposing KOReader's `json` module surface
-- (capitalised `encode` / `decode`).
--
-- dkjson encodes empty Lua tables as `[]` by default, which matches what
-- the dashboard frontend expects for empty arrays (books = {}, daily = {},
-- annotations = {}, etc.). Populated objects keep their object shape.

local dkjson = require("dkjson")

return {
    encode = function(value) return dkjson.encode(value) end,
    decode = function(text) return dkjson.decode(text) end,
    null   = dkjson.null,
}
