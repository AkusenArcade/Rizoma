--!strict
-- The folder as pictures with a name under each, as many across as fit.
-- A list of rows: a row asks only for the entries it shows.
local g = require("@genoma")
local browser = require("core/browser")
local config = require("core/config")
local look = require("ui/look")
local selection = require("core/selection")
local band = require("ui/band")
local scroll_mark = require("ui/scroll_mark")
local entry_ui = require("ui/entry")

local M = {}

local GAP, PAD, LINES = 8, 8, 2

-- A name on two lines at most: longer, it loses its middle, so it keeps
-- how it begins and its extension. Measured once for each name and width.
local fitted: { [string]: string } = {}
local held = 0
local function fit(name: string, width: number, font: string): string
    local key = `{width}:{font}:{name}`
    local hit = fitted[key]
    if hit then return hit end
    local function fits(text: string): boolean
        local h = g.text_height { text = text, font = font, size = look.font_name, weight = look.weight_name, width = width }
        local one = g.text_height { text = "X", font = font, size = look.font_name, weight = look.weight_name, width = width }
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

-- Where an entry is drawn, from the view's corner, whether in view or not.
local place = g.signal({ pitch = 1, cell_w = 0, cell_h = 0, gap = 0 })
local scrolled = g.signal(0)
function M.rect(index: number): { x: number, y: number, w: number, h: number }
    local c, p = M.columns.value, place.value
    local row, col = math.floor((index - 1) / c), (index - 1) % c
    return { x = col * (p.cell_w + p.gap), y = row * p.pitch - scrolled.value, w = p.cell_w, h = p.cell_h }
end

local function cell(entry: () -> any, icon: number, width: number, height: number): any
    local over = g.signal(false)
    local e = g.computed(entry)
    local function chosen(): boolean
        local it = e.value
        return it ~= nil and selection.has(it.path)
    end
    -- The keys' place, when it is not among the chosen.
    local function stood(): boolean
        local it = e.value
        return it ~= nil and browser.cursor.value == it.path
    end
    -- The picture and the name take the presses; the rest of the cell is the
    -- folder's own ground, where a rubber band starts.
    return g.capsule {
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
        rim_top = function() return if chosen() then look.primary() elseif stood() then look.node() else look.CLEAR end,
        rim_bottom = function() return if chosen() then look.primary() elseif stood() then look.node() else look.CLEAR end,
        transition = { fill = "ui_change" },
        g.box(entry_ui.handlers({
            role = "button",
            on_hover = function(on: boolean) over.value = on end,
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
                -- No wider than it is: what is beside a short name is ground.
                max_width = function()
                    local it = e.value
                    local room = width - PAD * 2
                    if it == nil then return room end
                    local w = g.text_width { text = it.name, font = look.expressive(), size = look.font_name, weight = look.weight_name }
                    return math.min(room, math.ceil(w) + 2)
                end,
                wrap = true,
                text_align = "center",
                color = look.text,
                font = look.expressive,
                size = look.font_name,
                weight = look.weight_name,
            },
        }, function() return e.value end)),
    }
end

-- `width()`, `height()`: the room it has. `foot`: what floats over its
-- foot, so the last row can be scrolled clear of it.
function M.new(width: () -> number, height: () -> number): any
    local icon = g.untracked(function() return config.get("icon") end)
    local cell_w = math.max(icon + 56, 132)
    local line = g.text_height { text = "X", font = g.untracked(look.expressive), size = look.font_name, weight = look.weight_name, width = 100 }
    local cell_h = math.ceil(icon + 6 + line * LINES + PAD * 2)
    local columns = g.computed(function(): number
        return math.max(1, math.floor((width() + GAP) / (cell_w + GAP)))
    end)
    -- What is left over goes between the columns.
    local function gap(): number
        local c = columns.value
        return if c > 1 then math.floor((width() - c * cell_w) / (c - 1)) else GAP
    end
    g.effect(function()
        place.value = { pitch = cell_h + GAP, cell_w = cell_w, cell_h = cell_h, gap = gap() }
        M.columns.value = columns.value
        M.rows_in_view.value = math.max(1, math.floor(height() / (cell_h + GAP)))
    end)
    local scroller = scroll_mark.new { height = height, x = function() return width() - 1 end }
    local view = g.list {
        id = "entries",
        clip = true,
        fade_bottom = scroller.fade,
        width = width,
        height = height,
        gap = GAP,
        row_height = cell_h,
        on_scroll = function(offset: number, room: number)
            scrolled.value = offset
            scroller.follow(offset, room)
        end,
        count = function() return math.ceil(browser.dir.count / columns.value) end,
        item = function(i: number) return i end,
        -- Another number across is another row.
        key = function(i: number) return `{columns.value}:{i}` end,
        reveal = function()
            local banded = band.row.value
            if banded then return banded end
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
    local pitch = cell_h + GAP
    local function row_at(y: number): number return math.floor(y / pitch) + 1 end
    return band.new({
        scroll = function() return scrolled.value end,
        width = width,
        height = height,
        row_at = row_at,
        rows = function() return math.ceil(browser.dir.count / columns.value) end,
        hits = function(x0: number, y0: number, x1: number, y1: number): { string }
            return g.untracked(function(): { string }
                local c, step = columns.value, cell_w + gap()
                -- The cells it touches, not the space between them.
                local first = math.max(0, math.floor((x0 + step - cell_w) / step))
                local last = math.min(c - 1, math.floor(x1 / step))
                local out: { string } = {}
                if first > last then return out end
                for row = math.max(1, math.floor((y0 + GAP) / pitch) + 1), math.min(row_at(y1), math.ceil(browser.dir.count / c)) do
                    for _, p in browser.dir:paths((row - 1) * c + first + 1, (row - 1) * c + last + 1) do
                        table.insert(out, p)
                    end
                end
                return out
            end)
        end,
        mark = scroller.mark,
    }, view)
end

return M
