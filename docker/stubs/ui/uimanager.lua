-- Minimal UIManager stub. The Docker server doesn't have KOReader's event
-- loop; `scheduleIn` is only used by the API for delayed shutdown which we
-- handle directly in the server, so we just no-op.

local UIManager = {}

function UIManager:scheduleIn(_seconds, fn)
    -- Fire immediately and synchronously.
    if type(fn) == "function" then
        local ok, err = pcall(fn)
        if not ok then io.stderr:write("UIManager stub callback error: " .. tostring(err) .. "\n") end
    end
end

function UIManager:nextTick(fn)
    if type(fn) == "function" then pcall(fn) end
end

function UIManager:show() end
function UIManager:close() end

return UIManager
