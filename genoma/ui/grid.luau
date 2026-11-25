--!strict
-- The folder as pictures with a name under each, as many across as fit.
-- A list of rows: a row asks only for the entries it shows.
local g = require("@genoma")
local browser = require("core/browser")
local config = require("core/config")
local look = require("ui/look")
local entry_ui = require("ui/entry")

local M = {}

local GAP, PAD, LINE, LINES = 8, 8, 17, 2

-- A name on two lines at most: longer, it loses its middle, so it keeps
-- how it begins and its extension. Measured once for each name and width.
local fitted: { [string]: string } = {}
local held = 0
local function fit(name: string, width: number, font: string): string
    local key = `{width}:{font}:{name}`
    local hit = fitted[key]
    if hit then return hit end
    local function fits(text: string): boolean
        local h = g.text_height { text = text, font = font, size = look.font_secondary, width = width }
        local one = g.text_height { text = "X", font = font, size = look.font_secondary, width = width }
        return h <= one * LINES + 1
    end
    local out = name
    if not fits(name) then
        local letters: { string } = {}
        for _, code in utf8.codes(name) do table.insert(letters, utf8.char(code)) end
        local tail = math.min(10, math.floor(#letters / 2))
        local low, high = 1, #letters - tail
        while low < high do
            local mid = math.ceil((low + high) / 2)
            local text = table.concat(letters, "", 1, mid) .. "…" .. table.concat(letters, "", #letters - tail + 1)
            if fits(text) then low = mid else high = mid - 1 end
        end
        out = table.concat(letters, "", 1, low) .. "…" .. table.concat(letters, "", #letters - tail + 1)
    end
    -- A day's worth of folders, not a lifetime's.
    if held > 20000 then
        fitted, held = {}, 0
    end
    fitted[key] = out
    held += 1
    return out
end
M._fit = fit

M.columns = g.signal(1)
M.rows_in_view = g.signal(1)

local function cell(entry: () -> any, icon: number, width: number, height: number): any
    local over = g.signal(false)
    local e = g.computed(entry)
    local function chosen(): boolean
        local it = e.value
        return it ~= nil and browser.cursor.value == it.path
    end
    return g.capsule {
        role = "button",
        present = function() return e.value ~= nil end,
        width = width,
        height = height,
        radius = 14,
        padding = PAD,
        direction = "column",
        align = "center",
        justify = "start",
        gap = 6,
        fill = function()
            if chosen() then return look.chosen() end
            return if over.value then look.hovered() else look.CLEAR
        end,
        rim_top = function() return if chosen() then look.primary() else look.CLEAR end,
        rim_bottom = function() return if chosen() then look.primary() else look.CLEAR end,
        transition = { fill = "ui_change" },
        on_hover = function(on: boolean) over.value = on end,
        on_press = function() end,
        on_click = entry_ui.pressed(function() return e.value end),
        g.box {
            direction = "column",
            align = "center",
            gap = 6,
            opacity = function() return entry_ui.faded(e.value) end,
            entry_ui.picture(function() return e.value end, icon, true),
            g.text {
                text = function()
                    local it = e.value
                    return if it then fit(it.name, width - PAD * 2, look.expressive()) else ""
                end,
                max_width = width - PAD * 2,
                wrap = true,
                text_align = "center",
                color = look.text,
                font = look.expressive,
                size = look.font_secondary,
            },
        },
    }
end

-- `width()`, `height()`: the room it has. `foot`: what floats over its
-- foot, so the last row can be scrolled clear of it.
function M.new(width: () -> number, height: () -> number): any
    local icon = g.untracked(function() return config.get("icon") end)
    local cell_w = math.max(icon + 44, 112)
    local cell_h = icon + 6 + LINE * LINES + PAD * 2
    local columns = g.computed(function(): number
        return math.max(1, math.floor((width() + GAP) / (cell_w + GAP)))
    end)
    -- What is left over goes between the columns.
    local function gap(): number
        local c = columns.value
        return if c > 1 then math.floor((width() - c * cell_w) / (c - 1)) else GAP
    end
    g.effect(function()
        M.columns.value = columns.value
        M.rows_in_view.value = math.max(1, math.floor(height() / (cell_h + GAP)))
    end)
    return g.list {
        id = "entries",
        width = width,
        height = height,
        gap = GAP,
        row_height = cell_h,
        count = function() return math.ceil(browser.dir.count / columns.value) end,
        item = function(i: number) return i end,
        -- Another number across is another row.
        key = function(i: number) return `{columns.value}:{i}` end,
        reveal = function()
            local i = browser.index.value
            return if i then math.ceil(i / columns.value) else nil
        end,
        row = function(item: () -> number, _)
            local c = g.untracked(function() return columns.value end)
            local node: { [any]: any } = { direction = "row", align = "start", gap = gap }
            for k = 1, c do
                table.insert(node, cell(function(): any
                    return browser.dir:at((item() - 1) * c + k)
                end, icon, cell_w, cell_h))
            end
            return g.box(node)
        end,
    }
end

return M
