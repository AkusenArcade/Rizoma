--!strict
-- How folders are shown: a button at the window's corner, and the cell that
-- buds from it and opens above it.
local g = require("@genoma")
local config = require("core/config")
local look = require("ui/look")
local ui = require("ui/controls")

local M = {}

M.open = g.signal(false)

local BUTTON, GAP_UP, PAD, LABEL_W, WIDTH = look.cell_height, 10, 22, 108, 460

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

-- `area()`: the window's { w, h }.
function M.new(area: () -> { w: number, h: number }): any
    local content_h = g.signal(280)
    local there = g.signal(false)
    local grown = g.signal(false)
    local putting_away: any = nil
    g.watch(function() return M.open.value end, function(on: boolean)
        if putting_away then putting_away:stop() end
        putting_away = nil
        if on then
            there.value = true
            g.after(0, function() grown.value = g.untracked(function() return M.open.value end) end)
        else
            grown.value = false
            putting_away = g.after(look.CLOSE, function()
                putting_away = nil
                there.value = false
            end)
        end
    end)
    local function timing(): string return if grown.value then "cell_open" else "cell_close" end
    local E = look.margin_edge
    local function width(): number return math.min(WIDTH, area().w - E * 2) end
    local function bx(): number return area().w - E - BUTTON end
    local function by(): number return area().h - E - BUTTON end

    local content = g.box {
        direction = "column",
        align = "stretch",
        gap = look.gap,
        padding = PAD,
        opacity = function() return if grown.value then 1 else 0 end,
        transition = { opacity = function() return if grown.value then "content_in" else "content_out" end },
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
    }

    local outside = g.box {
        overlay = true,
        attach = "corner",
        present = function() return M.open.value end,
        width = function() return area().w end,
        height = function() return area().h end,
        on_press = function() end,
        on_click = function() M.open.value = false end,
    }
    local panel = g.capsule {
        id = "view-cell",
        name = "View",
        overlay = true,
        attach = "corner",
        present = function() return there.value end,
        offset_x = function() return if grown.value then area().w - E - width() else bx() end,
        offset_y = function() return if grown.value then by() - GAP_UP - content_h.value else by() end,
        width = function() return if grown.value then width() else BUTTON end,
        height = function() return if grown.value then content_h.value else BUTTON end,
        radius = function() return if grown.value then look.radius_panel else BUTTON / 2 end,
        opacity = function() return if grown.value then 1 else 0 end,
        clip = true,
        fill = look.glass_over,
        rim_top = look.rim,
        rim_bottom = look.line,
        backdrop_blur = look.glass_blur,
        transition = { offset_x = timing, offset_y = timing, width = timing, height = timing, radius = timing, opacity = timing },
        on_press = function() end,
        on_click = function() end,
        g.box {
            overlay = true,
            attach = "corner",
            width = width,
            direction = "column",
            align = "stretch",
            on_size = function(_: number, h: number) content_h.value = h end,
            content,
        },
    }
    local button = ui.round {
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
    return g.box {
        overlay = true,
        attach = "corner",
        width = function() return area().w end,
        height = function() return area().h end,
        outside,
        panel,
        button,
    }
end

return M
