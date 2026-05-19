#!/usr/bin/env lua
-- KoDashboard standalone HTTP server.
--
-- Replaces KOReader's plugin host with a tiny luasocket-based server so the
-- existing api.lua / dataloader.lua / web/ assets can run inside a Docker
-- container against a mounted KOReader data dir.

local socket = require("socket")
local logger = require("logger")
local JSON   = require("json")
local DataLoader = require("dataloader")
local Api = require("api")

local PORT      = tonumber(os.getenv("PORT") or "8686")
local HOST      = os.getenv("HOST") or "0.0.0.0"
local WEB_DIR   = os.getenv("WEB_DIR") or "/app/web"
local READ_TIMEOUT = 30

local HTTP_REASON = {
    [200] = "OK",
    [302] = "Found",
    [400] = "Bad Request",
    [404] = "Not Found",
    [405] = "Method Not Allowed",
    [500] = "Internal Server Error",
}

local EXT_TO_CTYPE = {
    [".html"] = "text/html",
    [".htm"]  = "text/html",
    [".css"]  = "text/css",
    [".js"]   = "application/javascript",
    [".mjs"]  = "application/javascript",
    [".json"] = "application/json",
    [".png"]  = "image/png",
    [".jpg"]  = "image/jpeg",
    [".jpeg"] = "image/jpeg",
    [".webp"] = "image/webp",
    [".gif"]  = "image/gif",
    [".svg"]  = "image/svg+xml",
    [".ico"]  = "image/x-icon",
    [".txt"]  = "text/plain",
    [".woff"] = "font/woff",
    [".woff2"]= "font/woff2",
}

local function url_decode(s)
    s = s:gsub("+", " ")
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

-- The plugin's api.lua expects a "server" object with sendResponse and stop.
-- We build one per-request that buffers a response into a table; the request
-- loop reads the table and writes it back to the socket.
local function new_response_buffer(client)
    local buf = { status = nil, content_type = nil, body = nil, extra_headers = {} }
    local server_iface = {}

    function server_iface:sendResponse(reqinfo, status, content_type, body)
        buf.status       = status or 200
        buf.content_type = content_type
        buf.body         = body or ""
        return nil
    end

    function server_iface:stop()
        -- Used by /api/server/stop; honoured by setting a flag the main loop
        -- checks after the response is flushed.
        _G._KODASHBOARD_SHOULD_EXIT = true
    end

    return server_iface, buf
end

local function write_response(client, status, content_type, body, extra_headers)
    status = status or 200
    body = body or ""
    if type(body) ~= "string" then body = tostring(body) end
    local reason = HTTP_REASON[status] or "Unspecified"
    local lines = { string.format("HTTP/1.0 %d %s", status, reason) }
    if content_type then
        local charset = ""
        if content_type:sub(1, 5) == "text/" or content_type == "application/json" or content_type == "application/javascript" then
            charset = "; charset=utf-8"
        end
        lines[#lines + 1] = "Content-Type: " .. content_type .. charset
    end
    lines[#lines + 1] = "Access-Control-Allow-Origin: *"
    lines[#lines + 1] = "Cache-Control: no-store, no-cache, must-revalidate, max-age=0"
    lines[#lines + 1] = "Pragma: no-cache"
    lines[#lines + 1] = "Expires: 0"
    lines[#lines + 1] = "Content-Length: " .. tostring(#body)
    lines[#lines + 1] = "Connection: close"
    if extra_headers then
        for _, h in ipairs(extra_headers) do lines[#lines + 1] = h end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = body
    client:send(table.concat(lines, "\r\n"))
end

local function read_request(client)
    client:settimeout(READ_TIMEOUT)
    local head_lines = {}
    while true do
        local line, err = client:receive("*l")
        if not line then return nil, err or "read failed" end
        if line == "" then break end
        head_lines[#head_lines + 1] = line
    end
    if #head_lines == 0 then return nil, "empty request" end

    local request_line = head_lines[1]
    local method, uri = request_line:match("^(%u+)%s+(%S+)%s+HTTP/%d%.%d")
    if not method then return nil, "malformed request line" end

    local headers = {}
    for i = 2, #head_lines do
        local k, v = head_lines[i]:match("^([^:]+):%s*(.*)$")
        if k then headers[k:lower()] = v end
    end

    local body = ""
    local clen = tonumber(headers["content-length"] or "0") or 0
    if method ~= "GET" and clen > 0 then
        local chunk, err2, partial = client:receive(clen)
        body = chunk or partial or ""
        if not chunk and err2 ~= "closed" then
            logger.warn("KoDashboard: short POST body:", err2 or "?")
        end
    end

    return { method = method, uri = uri, headers = headers, body = body }
end

local function read_static_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*all")
    f:close()
    return data
end

local function safe_join(base, rel)
    -- rel is the URL path, already url-decoded. Strip leading slash and
    -- reject any path containing ".." segments.
    rel = rel:gsub("^/+", "")
    for seg in rel:gmatch("[^/]+") do
        if seg == ".." then return nil end
    end
    return base .. "/" .. rel
end

local function handle_api_refresh(client)
    DataLoader._dashboard_cache = nil
    local body = JSON.encode({ ok = true, refreshed_at = os.time() })
    write_response(client, 200, "application/json", body)
end

-- Diagnostic for "stats DB read silently returns nothing." Surfaces the
-- resolved DB path, table list, and row counts so we can tell whether the
-- file is missing, the schema differs (e.g. older `page_stat` vs newer
-- `page_stat_data`), or queries just hit zero rows.
local function handle_api_debug_stats(client)
    local DataStorage = require("datastorage")
    local lfs = require("libs/libkoreader-lfs")

    local out = {
        ko_data_dir = DataStorage:getDataDir(),
        ko_settings_dir = DataStorage:getSettingsDir(),
        candidates = {},
    }

    local function probe(p)
        local mode = lfs.attributes(p, "mode")
        local size = nil
        if mode == "file" then
            local f = io.open(p, "rb")
            if f then size = f:seek("end") or 0; f:close() end
        end
        table.insert(out.candidates, { path = p, exists = mode == "file", size = size })
    end

    probe((out.ko_settings_dir or "") .. "/statistics.sqlite3")
    probe((out.ko_data_dir or "") .. "/statistics.sqlite3")
    probe((out.ko_data_dir or "") .. "/settings/statistics.sqlite3")

    local picked
    for _, c in ipairs(out.candidates) do
        if c.exists and not picked then picked = c.path end
    end
    out.picked = picked

    if picked then
        local ok_sq, SQ3 = pcall(require, "lua-ljsqlite3/init")
        if not ok_sq then
            out.sqlite_error = "load failed: " .. tostring(SQ3)
        else
            local ok_open, conn = pcall(SQ3.open, picked)
            if not ok_open then
                out.sqlite_error = "open failed: " .. tostring(conn)
            else
                local function collect(sql, col)
                    local results = {}
                    local ok, err = pcall(function()
                        local stmt = conn:prepare(sql)
                        local r = stmt:step()
                        while r do
                            table.insert(results, tostring(r[col or 1]))
                            r = stmt:step()
                        end
                        stmt:close()
                    end)
                    if not ok then results._error = tostring(err) end
                    return results
                end

                out.tables = collect("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
                out.row_counts = {}
                for _, tname in ipairs(out.tables) do
                    local ok_c, count_or_err = pcall(function()
                        return conn:rowexec("SELECT count(*) FROM " .. tname)
                    end)
                    out.row_counts[tname] = ok_c and tostring(count_or_err) or ("err: " .. tostring(count_or_err))
                end
                out.columns = {}
                for _, tname in ipairs({ "book", "page_stat", "page_stat_data" }) do
                    local cols = collect("PRAGMA table_info(" .. tname .. ")", 2)
                    if #cols > 0 then out.columns[tname] = cols end
                end
                conn:close()
            end
        end
    end

    write_response(client, 200, "application/json", JSON.encode(out))
end

local function handle_api(client, req, path)
    if path == "/api/refresh" then
        if req.method ~= "POST" and req.method ~= "GET" then
            write_response(client, 405, "application/json", '{"ok":false,"error":"Use POST"}')
            return
        end
        handle_api_refresh(client)
        return
    end

    if path == "/api/_debug/stats" then
        handle_api_debug_stats(client)
        return
    end

    local reqinfo = {
        method = req.method,
        headers = req.headers,
        body = req.body,
    }

    local server_iface, buf = new_response_buffer(client)

    local ok, err = pcall(function()
        Api.handleRequest(server_iface, reqinfo, path, req.uri)
    end)

    if not ok then
        logger.err("KoDashboard: api dispatch error:", err)
        write_response(client, 500, "application/json",
            JSON.encode({ error = "internal server error", detail = tostring(err) }))
        return
    end

    if buf.status == nil then
        write_response(client, 500, "application/json",
            '{"error":"api handler did not respond"}')
        return
    end

    write_response(client, buf.status, buf.content_type, buf.body)
end

local function handle_static(client, req, path)
    if req.method ~= "GET" then
        write_response(client, 405, "text/plain", "Method not allowed")
        return
    end
    if path == "/" or path == "" then path = "/index.html" end
    local filepath = safe_join(WEB_DIR, path)
    if not filepath then
        write_response(client, 400, "text/plain", "Bad path")
        return
    end
    local data = read_static_file(filepath)
    if not data then
        write_response(client, 404, "text/plain", "Not found: " .. path)
        return
    end
    local ext = path:match("(%.[^.]+)$") or ""
    write_response(client, 200, EXT_TO_CTYPE[ext:lower()] or "application/octet-stream", data)
end

local function handle_client(client)
    local req, err = read_request(client)
    if not req then
        logger.warn("KoDashboard: bad request:", err)
        client:close()
        return
    end

    local uri = url_decode(req.uri)
    local path = uri:match("^([^?]*)") or uri

    local ok, dispatch_err = pcall(function()
        if path:sub(1, 5) == "/api/" then
            handle_api(client, req, path)
        else
            handle_static(client, req, path)
        end
    end)

    if not ok then
        logger.err("KoDashboard: handler error:", dispatch_err)
        local body = JSON.encode({ error = "internal server error", detail = tostring(dispatch_err) })
        pcall(write_response, client, 500, "application/json", body)
    end

    client:close()
end

local function main()
    local listener, err = socket.bind(HOST, PORT)
    if not listener then
        io.stderr:write("KoDashboard: failed to bind " .. HOST .. ":" .. tostring(PORT) .. ": " .. tostring(err) .. "\n")
        os.exit(1)
    end
    listener:settimeout(1)
    logger.info("KoDashboard listening on http://" .. HOST .. ":" .. tostring(PORT))
    logger.info("Serving static files from " .. WEB_DIR)
    logger.info("KO_DATA_DIR=" .. tostring(os.getenv("KO_DATA_DIR")))
    logger.info("KO_SETTINGS_DIR=" .. tostring(os.getenv("KO_SETTINGS_DIR")))

    while true do
        local client = listener:accept()
        if client then
            local ok, herr = pcall(handle_client, client)
            if not ok then logger.err("client handler crashed:", herr) end
        end
        if _G._KODASHBOARD_SHOULD_EXIT then
            logger.info("Shutdown requested via API; exiting.")
            break
        end
    end
    listener:close()
end

main()
