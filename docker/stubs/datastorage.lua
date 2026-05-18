-- Stub for KOReader's datastorage module.
-- Resolves the data/settings/cache paths from environment variables so the
-- existing plugin code can find statistics.sqlite3, history.lua and the
-- kodashboard cover cache when running in Docker.

local function env_or(name, fallback)
    local v = os.getenv(name)
    if v and v ~= "" then return v end
    return fallback
end

local DataStorage = {}

local DATA_DIR = env_or("KO_DATA_DIR", "/data/koreader")
local SETTINGS_DIR = env_or("KO_SETTINGS_DIR", DATA_DIR .. "/settings")

function DataStorage:getDataDir() return DATA_DIR end
function DataStorage:getSettingsDir() return SETTINGS_DIR end
function DataStorage:getFullDataDir() return DATA_DIR end

return DataStorage
