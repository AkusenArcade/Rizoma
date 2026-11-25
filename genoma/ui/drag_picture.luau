--!strict
-- What is seen under the pointer while files are dragged out: the first of
-- them, one over the other, and how they are called or how many they are.
local g = require("@genoma")
local exchange = require("core/exchange")
local look = require("ui/look")
local entry_ui = require("ui/entry")

local M = {}

local ICON, STACK, STEP, TILT, NAME_MAX = 64, 3, 7, 7, 180

-- What a drag begun on the pressed entry would carry.
local carried = g.computed(function(): { entries: { any }, count: number }
    local path = entry_ui.pressed.value
    local pane = entry_ui.pressed_in.value
    if path == "" or pane == nil then return { entries = {}, count = 0 } end
    if pane.selection.has(path) then
        return { entries = pane.selection.entries(STACK), count = pane.selection.count() }
    end
    local i = pane.dir:index(path)
    local e = if i then pane.dir:at(i) else nil
    return if e then { entries = { e }, count = 1 } else { entries = {}, count = 0 }
end)

local function card(k: number): any
    local function entry(): any return carried.value.entries[k] end
    return g.box {
        overlay = true,
        attach = "corner",
        present = function() return entry() ~= nil end,
        -- The first on top, the others behind it, a little aside.
        offset_x = (k - 1) * STEP,
        offset_y = (STACK - k) * 2,
        rotate = (k - 1) * TILT,
        opacity = 1 - (k - 1) * 0.22,
        entry_ui.picture(entry, ICON, true),
    }
end

function M.new(): any
    local stack: { [any]: any } = { width = ICON + (STACK - 1) * STEP, height = ICON + 6 }
    for k = STACK, 1, -1 do table.insert(stack, card(k)) end
    local function label(): string
        local would = exchange.would()
        if would then return would end
        local c = carried.value
        if c.count > 1 then return `{c.count} items` end
        return if c.entries[1] then c.entries[1].name else ""
    end
    return g.drag_picture {
        x = 10,
        y = 8,
        g.box {
            direction = "column",
            align = "start",
            gap = 4,
            -- Room for what is turned.
            padding = 8,
            g.box(stack),
            g.capsule {
                height = 28,
                padding_x = 12,
                radius = 14,
                direction = "row",
                align = "center",
                fill = look.glass_over,
                rim_top = look.rim,
                rim_bottom = look.line,
                g.text {
                    text = label,
                    max_width = NAME_MAX,
                    ellipsize = "middle",
                    color = look.text,
                    font = look.expressive,
                    size = look.font_text,
                    weight = look.weight_name,
                },
            },
        },
    }
end

return M
