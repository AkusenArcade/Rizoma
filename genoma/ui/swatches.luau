--!strict
-- The colours in a row: what one is pressed for is the caller's.
local g = require("@genoma")
local colours = require("core/colours")
local look = require("ui/look")
local ui = require("ui/controls")

local M = {}

local DOT, GAP = 18, 8
M.COUNT = #colours.list + 1
-- How wide `n` of them are.
function M.width(n: number): number return n * DOT + (n - 1) * GAP end

-- t: id, chosen() the key of the one that is, on_pick(key or nil), none whether
-- the row ends with the one that takes the colour off, hot() the place the keys
-- are on.
function M.new(t: { [string]: any }): any
    local row: { [any]: any } = { direction = "row", align = "center", gap = GAP }
    local function dot(place: number, key: string?, name: string): any
        local over = g.signal(false)
        local function chosen(): boolean return key ~= nil and t.chosen() == key end
        local function lit(): boolean return over.value or (t.hot ~= nil and t.hot() == place) end
        return g.box {
            id = `{t.id}-{key or "none"}`,
            role = "button",
            name = name,
            width = DOT,
            height = DOT,
            align = "center",
            justify = "center",
            on_hover = function(on: boolean) over.value = on end,
            on_press = function() end,
            on_click = function(button: number) if button == 272 then t.on_pick(key) end end,
            -- Its ring, when it is the one, or could be.
            g.capsule {
                overlay = true,
                attach = "center",
                width = DOT,
                height = DOT,
                radius = DOT / 2,
                fill = look.CLEAR,
                rim_top = function() return if chosen() then look.text() elseif lit() then look.node() else look.CLEAR end,
                rim_bottom = function() return if chosen() then look.text() elseif lit() then look.node() else look.CLEAR end,
                transition = { rim_top = "ui_change", rim_bottom = "ui_change" },
            },
            if key then g.capsule {
                width = 12,
                height = 12,
                radius = 6,
                fill = function() return look.gradient_top(colours.hex(key, look.is_dark())) end,
                fill_bottom = function() return look.gradient_bottom(colours.hex(key, look.is_dark())) end,
                rim_top = look.CLEAR,
                rim_bottom = look.CLEAR,
            } else ui.glyph("close", 12, function() return false end, function() return if lit() then look.text() else look.text_faint() end),
        }
    end
    for i, c in colours.list do table.insert(row, dot(i, c.key, c.name)) end
    if t.none then table.insert(row, dot(#colours.list + 1, nil, "No colour")) end
    return g.box(row)
end

return M
