--!strict
-- What the person chose: ~/.config/rizoma/config.json. One choice for every
-- folder (plan §8), each key a signal a binding follows.
local g = require("@genoma")

local M = {}

local dir = (g.env("XDG_CONFIG_HOME") or ((g.env("HOME") or "") .. "/.config")) .. "/rizoma"
M.path = dir .. "/config.json"

M.defaults = {
    view = "grid",
    sort = "name",
    descending = false,
    folders_first = true,
    hidden = false,
    -- The grid's icons, logical units.
    icon = 80,
    -- The places, kept open beside the folder where there is room.
    places = true,
    -- The preview pane, kept open where there is room.
    preview = false,
    -- What opened folders before Rizoma did.
    before = "",
} :: { [string]: any }

local CHOICES: { [string]: { string } } = {
    view = { "grid", "list" },
    sort = { "name", "size", "modified", "type" },
}
M.ICON_MIN, M.ICON_MAX, M.ICON_STEP = 48, 176, 16

local file = g.file { path = M.path, watch = false }

local function valid(key: string, value: any): boolean
    if type(value) ~= type(M.defaults[key]) then return false end
    local choices = CHOICES[key]
    return choices == nil or table.find(choices, value) ~= nil
end

-- What was read and is not ours stays in the file: a newer Rizoma's key is
-- not lost by an older one.
local kept: { [string]: any } = {}
local signals: { [string]: any } = {}
do
    if file.text then
        local ok, parsed = pcall(g.parse_json, file.text)
        if ok and type(parsed) == "table" then kept = parsed end
    end
    for key, default in M.defaults do
        local value = kept[key]
        if not valid(key, value) then value = default end
        if key == "icon" then value = math.clamp(value, M.ICON_MIN, M.ICON_MAX) end
        signals[key] = g.signal(value)
    end
end

function M.get(key: string): any return signals[key].value end

local saving: any = nil
function M.set(key: string, value: any)
    if not valid(key, value) or g.untracked(function() return signals[key].value end) == value then return end
    signals[key].value = value
    -- A slider being dragged is one write, not fifty.
    if saving then saving:stop() end
    saving = g.after(0.4, function()
        saving = nil
        local out = table.clone(kept)
        for k, s in signals do out[k] = g.untracked(function() return s.value end) end
        file:write(g.to_json(out, true))
    end)
end

return M
