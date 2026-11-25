--!strict
-- How folders are shown: a button at the window's corner, and the cell that
-- buds from it and opens above it.
local g = require("@genoma")
local config = require("core/config")
local desktop = require("core/desktop")
local look = require("ui/look")
local ui = require("ui/controls")
local foot_cell = require("ui/foot_cell")

local M = {}

M.open = g.signal(false)

local PAD, LABEL_W, WIDTH = 22, 108, 460

local function row(name: string, control: any, present: (() -> boolean)?): any
    return g.box {
        present = present,
        direction = "row",
        align = "center",
        gap = 12,
        height = 30,
        g.box { width = LABEL_W, ui.label(name) },
        control,
    }
end

local function toggle(name: string, key: string): any
    return row(name, ui.switch {
        id = "switch-" .. key,
        name = name,
        on = function() return config.get(key) end,
        on_toggle = function(on: boolean) config.set(key, on) end,
    })
end

local SPAN = config.ICON_MAX - config.ICON_MIN

-- Where its button is.
function M.x(area: { w: number, h: number }): number return area.w - look.margin_edge - foot_cell.BUTTON end

-- `area()`: the window's { w, h }.
function M.new(area: () -> { w: number, h: number }): any
    local content = g.box {
        direction = "column",
        align = "stretch",
        gap = look.gap,
        padding = PAD,
        row("View", ui.segmented {
            id = "view",
            options = { { key = "grid", label = "Grid" }, { key = "list", label = "List" } },
            current = function() return config.get("view") end,
            on_choose = function(key: string) config.set("view", key) end,
        }),
        row("Sort", ui.segmented {
            id = "sort",
            options = {
                { key = "name", label = "Name" },
                { key = "size", label = "Size" },
                { key = "modified", label = "Date" },
                { key = "type", label = "Type" },
            },
            current = function() return config.get("sort") end,
            on_choose = function(key: string)
                g.batch(function()
                    config.set("sort", key)
                    config.set("descending", key == "size" or key == "modified")
                end)
            end,
        }),
        toggle("Reversed", "descending"),
        toggle("Folders first", "folders_first"),
        toggle("Hidden files", "hidden"),
        toggle("Places", "places"),
        toggle("Preview", "preview"),
        row("Size", ui.slider {
            id = "icon",
            name = "Icon size",
            width = WIDTH - PAD * 2 - LABEL_W - 12,
            step = config.ICON_STEP / SPAN,
            value = function() return (config.get("icon") - config.ICON_MIN) / SPAN end,
            on_move = function(v: number)
                config.set("icon", config.ICON_MIN + math.floor(v * SPAN / config.ICON_STEP + 0.5) * config.ICON_STEP)
            end,
        }, function() return config.get("view") == "grid" end),
        row("Default", ui.switch {
            id = "switch-default",
            name = "The default file manager",
            on = desktop.is_default,
            on_toggle = desktop.set_default,
        }, desktop.can_be_default),
    }

    return foot_cell.new {
        id = "view",
        name = "View",
        area = area,
        x = function() return M.x(area()) end,
        open = M.open,
        width = WIDTH,
        outside = true,
        content = content,
        button = function(bx: () -> number, by: () -> number): any
            return ui.round {
                id = "view-button",
                name = "View",
                glyph = "rizoma",
                glyph_size = 20,
                lit = function() return M.open.value end,
                on_click = function() M.open.value = not g.untracked(function() return M.open.value end) end,
                props = {
                    overlay = true,
                    attach = "corner",
                    offset_x = bx,
                    offset_y = by,
                    backdrop_blur = look.glass_blur,
                },
            }
        end,
    }
end

return M
