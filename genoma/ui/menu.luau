--!strict
-- The menu of the right button (and of a finger held): a cell that grows from
-- where it was pressed. A row with more of its own opens it in place.
local g = require("@genoma")
local look = require("ui/look")
local colours = require("core/colours")
local scroll_mark = require("ui/scroll_mark")
local swatches = require("ui/swatches")

local M = {}

export type Item = {
    text: string,
    act: (() -> ())?,
    -- The keys that do the same.
    keys: string?,
    off: boolean?,
    -- A picture of the icon theme's, before the words.
    icon: string?,
    -- What it opens, in place.
    more: { Item }?,
    -- Instead of words, the colours: the one that is, and what picks one.
    colours: { chosen: string?, pick: (key: string?) -> () }?,
}
type Line = { kind: "item" | "line" | "colours", item: Item?, key: string, inner: boolean }

local ROW, RULE, SWATCHES, PAD, MIN, MAX = 32, 11, 36, 8, 220, 320

local shown = g.signal(nil :: { items: { Item | string }, x: number, y: number, at: number }?)
local grown = g.signal(false)
local there = g.signal(false)
-- The row the keys or the pointer are on, and the one opened, by key.
local on = g.signal(nil :: string?)
local opened = g.signal(nil :: string?)
local going: any = nil
local count = 0

function M.is_open(): boolean return shown.value ~= nil and grown.value end

function M.close()
    if not g.untracked(function() return there.value end) then return end
    grown.value = false
    if going then going:stop() end
    going = g.after(look.CLOSE, function()
        going = nil
        there.value = false
        shown.value = nil
    end)
end

function M.open(items: { Item | string }, x: number, y: number)
    if going then going:stop() end
    going = nil
    count += 1
    g.batch(function()
        grown.value = false
        on.value = nil
        opened.value = nil
        shown.value = { items = items, x = x, y = y, at = count }
        there.value = true
    end)
    g.after(0, function() grown.value = g.untracked(function() return there.value end) end)
end

local lines = g.computed(function(): { Line }
    local s = shown.value
    local out: { Line } = {}
    if s == nil then return out end
    for i, it in s.items do
        if type(it) == "string" then
            table.insert(out, { kind = "line", item = nil, key = `{s.at}:{i}`, inner = false })
        else
            local item: Item = it
            local key = `{s.at}:{i}`
            table.insert(out, { kind = if item.colours then "colours" else "item", item = item, key = key, inner = false })
            if item.more and opened.value == key then
                for k, m in item.more do
                    table.insert(out, { kind = "item", item = m, key = `{key}:{k}`, inner = true })
                end
            end
        end
    end
    return out
end)

-- The colour the keys are on, in their row.
local swatch = g.signal(1)

local function usable(l: Line): boolean return l.kind ~= "line" and (l.item :: Item).off ~= true end

local function press(l: Line)
    if not usable(l) then return end
    local item = l.item :: Item
    if item.colours then
        local c = colours.list[g.untracked(function() return swatch.value end)]
        M.close()
        item.colours.pick(if c then c.key else nil)
        return
    end
    if item.more then
        opened.value = if g.untracked(function() return opened.value end) == l.key then nil else l.key
        return
    end
    M.close()
    if item.act then item.act() end
end

local function walk(by: number)
    local list = g.untracked(function() return lines.value end)
    local at = 0
    for i, l in list do
        if l.key == g.untracked(function() return on.value end) then at = i end
    end
    if at == 0 and by < 0 then at = #list + 1 end
    for _ = 1, #list do
        at = (at + by - 1) % #list + 1
        if usable(list[at]) then
            on.value = list[at].key
            return
        end
    end
end

local function current(): Line?
    local key = g.untracked(function() return on.value end)
    for _, l in g.untracked(function() return lines.value end) do
        if l.key == key then return l end
    end
    return nil
end

-- The keys while it is open: all of them are its.
function M.key(name: string)
    if name == "Escape" or name == "Menu" then M.close()
    elseif name == "Down" or name == "Tab" then walk(1)
    elseif name == "Up" or name == "ISO_Left_Tab" then walk(-1)
    elseif name == "Home" then
        on.value = nil
        walk(1)
    elseif name == "End" then
        on.value = nil
        walk(-1)
    elseif name == "Return" or name == "KP_Enter" or name == "space" then
        local l = current()
        if l then press(l) end
    elseif name == "Right" or name == "Left" and current() and (current() :: Line).kind == "colours" then
        local l = current()
        if l and l.kind == "colours" then
            swatch.value = math.clamp(g.untracked(function() return swatch.value end) + (if name == "Right" then 1 else -1), 1, swatches.COUNT)
            return
        end
        if l and usable(l) and (l.item :: Item).more and g.untracked(function() return opened.value end) ~= l.key then press(l) end
    elseif name == "Left" then
        local key = g.untracked(function() return opened.value end)
        if key then
            opened.value = nil
            on.value = key
        end
    end
end

local function wide(text: string): number
    return g.text_width { text = text, font = look.technical(), size = look.font_menu, weight = 500, tracking = 0.02 }
end
local width = g.computed(function(): number
    local w = MIN
    local s = shown.value
    local function add(it: Item, inner: boolean)
        if it.colours then return end
        local need = wide(it.text) + PAD * 2 + 24 + (if inner then 12 else 0) + (if it.icon then 26 else 0) + (if it.more then 28 else 0)
        if it.keys then need += 24 + g.text_width { text = it.keys, font = look.technical(), size = look.font_meta } end
        w = math.max(w, math.ceil(need))
    end
    if s then
        for _, it in s.items do
            if type(it) == "string" then continue end
            add(it, false)
            for _, m in it.more or {} do add(m, true) end
        end
    end
    return math.min(w, MAX)
end)
local content_h = g.computed(function(): number
    local h = PAD * 2
    for _, l in lines.value do h += if l.kind == "line" then RULE elseif l.kind == "colours" then SWATCHES else ROW end
    return h
end)

local function row(line: () -> Line, _: any): any
    local first = g.untracked(line)
    if first.kind == "line" then
        return g.box {
            height = RULE,
            direction = "column",
            justify = "center",
            align = "stretch",
            g.capsule {
                height = 1,
                crisp = true,
                radius = 0,
                fill = function() return g.colour.alpha(look.line(), 0.6) end,
                rim_top = look.CLEAR,
                rim_bottom = look.CLEAR,
            },
        }
    end
    local function item(): Item return line().item or { text = "" } end
    if first.kind == "colours" then
        local c = (first.item :: Item).colours :: any
        return g.box {
            height = SWATCHES,
            direction = "row",
            align = "center",
            justify = "center",
            on_hover = function(o: boolean) if o then on.value = nil end end,
            swatches.new {
                id = "colour",
                none = true,
                chosen = function() return c.chosen end,
                hot = function() return if on.value == line().key then swatch.value else 0 end,
                on_pick = function(key: string?)
                    M.close()
                    c.pick(key)
                end,
            },
        }
    end
    local function lit(): boolean return on.value == line().key end
    local function off(): boolean return item().off == true end
    local function open(): boolean return opened.value == line().key end
    return g.capsule {
        id = "menu-" .. string.lower((string.gsub(first.item and first.item.text or "", "[^%w]+", "-"))),
        role = "button",
        name = first.item and first.item.text,
        height = ROW,
        direction = "row",
        align = "center",
        justify = "start",
        gap = 10,
        padding_left = if first.inner then 24 else 12,
        padding_right = 12,
        radius = look.within(PAD),
        fill = function() return if lit() then look.hovered() else look.CLEAR end,
        rim_top = look.CLEAR,
        rim_bottom = look.CLEAR,
        opacity = function() return if off() then 0.4 else 1 end,
        on_hover = function(o: boolean)
            if o then
                if usable(g.untracked(line)) then on.value = g.untracked(line).key end
            elseif g.untracked(lit) then
                on.value = nil
            end
        end,
        on_press = function() end,
        on_click = function(button: number) if button == 272 then press(g.untracked(line)) end end,
        g.icon {
            present = function() return item().icon ~= nil end,
            width = 18,
            height = 18,
            icon = function() return item().icon or "" end,
        },
        g.text {
            text = function() return item().text end,
            max_width = function() return width.value - PAD * 2 - 24 - (if item().icon then 28 else 0) end,
            ellipsize = "end",
            color = function() return if lit() then look.text() else look.text() end,
            font = look.technical,
            size = look.font_menu,
            weight = 500,
            tracking = 0.02,
        },
        g.box { grow = 1 },
        g.text {
            present = function() return item().keys ~= nil end,
            text = function() return item().keys or "" end,
            color = look.text_faint,
            font = look.technical,
            size = look.font_meta,
        },
        g.box {
            present = function() return item().more ~= nil end,
            g.icon {
                width = 14,
                height = 14,
                icon = "icons/chevron-down",
                rotate = function() return if open() then 180 else 0 end,
                color = look.text_muted,
                transition = { rotate = "ui_change" },
            },
        },
    }
end

-- `area()`: the window's { w, h }.
function M.new(area: () -> { w: number, h: number }): any
    local E = look.margin_edge
    local function tall(): number return math.min(content_h.value, area().h - E * 2) end
    local function x0(): number return if shown.value then shown.value.x else 0 end
    local function y0(): number return if shown.value then shown.value.y else 0 end
    -- Towards where there is room.
    local function left(): number
        local w = width.value
        return math.max(E, if x0() + w <= area().w - E then x0() else math.min(x0(), area().w - E) - w)
    end
    local function top(): number
        local h = tall()
        if y0() + h <= area().h - E then return y0() end
        return if y0() - h >= E then y0() - h else math.max(E, area().h - E - h)
    end
    local function timing(): string return if grown.value then "cell_open" else "cell_close" end
    local scroller = scroll_mark.new { height = function() return tall() - PAD * 2 end, x = function() return width.value - 5 end, room = function() return math.max(0, content_h.value - tall()) end }
    return g.box {
        overlay = true,
        attach = "corner",
        present = function() return there.value end,
        width = function() return area().w end,
        height = function() return area().h end,
        -- A press beside it puts it away, and does nothing else.
        g.box {
            overlay = true,
            attach = "corner",
            present = function() return shown.value ~= nil end,
            width = function() return area().w end,
            height = function() return area().h end,
            on_press = function() M.close() end,
            on_click = function() end,
        },
        g.capsule {
            id = "menu",
            name = "Menu",
            overlay = true,
            attach = "corner",
            offset_x = function() return if grown.value then left() else x0() end,
            offset_y = function() return if grown.value then top() else y0() end,
            width = function() return if grown.value then width.value else 8 end,
            height = function() return if grown.value then tall() else 8 end,
            radius = function() return look.shaped(if grown.value then look.radius_panel else 4) end,
            opacity = function() return if grown.value then 1 else 0 end,
            clip = true,
            fill = look.glass_over,
            rim_top = look.rim,
            rim_bottom = look.line,
            backdrop_blur = look.glass_blur,
            transition = {
                offset_x = function() return if grown.value then "cell_open" else "placed" end,
                offset_y = function() return if grown.value then "cell_open" else "placed" end,
                width = timing,
                height = timing,
                radius = timing,
                opacity = timing,
            },
            on_press = function() end,
            on_click = function() end,
            g.box {
                overlay = true,
                attach = "corner",
                offset_x = PAD,
                offset_y = PAD,
                width = function() return width.value - PAD * 2 end,
                height = function() return tall() - PAD * 2 end,
                radius = look.within(PAD),
                scroll = "y",
                clip = true,
                fade_bottom = scroller.fade,
                on_scroll = function(_: number, y: number) scroller.follow(y, 0) end,
                direction = "column",
                align = "stretch",
                opacity = function() return if grown.value then 1 else 0 end,
                transition = { opacity = function() return if grown.value then "content_in" else "content_out" end },
                g.each {
                    direction = "column",
                    align = "stretch",
                    items = function() return lines.value end,
                    key = function(l: Line) return l.key end,
                    row = row,
                },
            },
        },
    }
end

return M
