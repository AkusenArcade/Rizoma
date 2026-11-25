--!strict
-- A size and a moment, as the list and the line below the grid say them.
local g = require("@genoma")

local M = {}

function M.size(bytes: number): string
    if bytes < 1000 then return `{math.floor(bytes)} B` end
    local units = { "kB", "MB", "GB", "TB", "PB" }
    local v, u = bytes / 1000, 1
    -- 999.95 would be written "1000": the next unit's 1.
    while v >= 999.5 and u < #units do v, u = v / 1000, u + 1 end
    return string.format(if v < 9.95 then "%.1f %s" else "%.0f %s", v, units[u])
end

local DAY = 86400

-- The day now, looked at again every minute: yesterday's "Today" goes.
local now = g.signal(os.time())
g.timer { every = 60, on_tick = function() now.value = os.time() end }

-- Days as the calendar counts them here, whatever the clocks did between.
local function day_of(seconds: number): number
    local t = os.date("*t", seconds) :: any
    return math.floor(os.time { year = t.year, month = t.month, day = t.day, hour = 12 } / DAY)
end

local today = g.computed(function(): number return day_of(now.value) end)

function M.moment(seconds: number): string
    if seconds <= 0 then return "" end
    local at = math.floor(seconds)
    local days = today.value - day_of(at)
    if days == 0 then return (os.date("Today %H:%M", at)) end
    if days == 1 then return (os.date("Yesterday %H:%M", at)) end
    local t = os.date("*t", at) :: any
    local this = os.date("*t", g.untracked(function() return now.value end)) :: any
    local day = string.gsub(os.date("%d %b", at), "^0", "")
    if t.year == this.year then return day .. (os.date(" %H:%M", at)) end
    return day .. (os.date(" %Y", at))
end

return M
