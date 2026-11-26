--!strict
-- The tabs, under the path and over the panes, when there is more than one:
-- the tab component of every Bioma-style app, as Floema has it
-- (genoma/ui/tabs.luau there). Each tab's name is what its panes show, two
-- folders with a seam between; they sit in a row on a track a little darker
-- than the window, with no outline, and the one seen is a pill in the
-- secondary colour (the primary is the interactive components'). Choosing
-- another, the pill goes to it as a drop would: the edge it moves towards
-- leads, quick and a little past, the other follows softer (`pill_lead`,
-- `pill_trail`). The path above is the one seen's. What is dragged over a
-- tab is welcomed by its outline in the primary, as everywhere here.
local g = require("@genoma")
local exchange = require("core/exchange")
local menu = require("ui/menu")
local panes = require("core/panes")
local paths = require("core/paths")
local look = require("ui/look")
local ui = require("ui/controls")

local M = {}

local H, INSET, PAD, CLOSE, NAME_MAX, SEAM, GAP = look.action_height, 3, 18, 16, 180, 17, 2
M.HEIGHT = H + INSET * 2

local function name_w(name: string, room: number): number
    local w = g.text_width { text = name, font = look.expressive(), size = look.font_label, weight = 600 }
    return math.min(math.ceil(w) + 1, room)
end
local function named(p: any): string return paths.called(p.here.value) end

-- A closed one is there until it has gone back.
type Shown = { tab: panes.Tab, leaving: boolean, fresh: boolean }
local shown = g.signal({} :: { Shown })
local going: any = nil
g.watch(function() return panes.tabs.value end, function(tabs: { panes.Tab })
    local before = g.untracked(function() return shown.value end)
    local after: { Shown } = {}
    local had: { [any]: boolean } = {}
    for _, s in before do if not s.leaving then had[s.tab] = true end end
    for _, t in tabs do table.insert(after, { tab = t, leaving = false, fresh = #before > 0 and not had[t] }) end
    for i, s in before do
        local kept = table.find(tabs, s.tab) ~= nil
        if not kept and not s.leaving and #tabs > 1 then
            table.insert(after, math.min(i, #after + 1), { tab = s.tab, leaving = true, fresh = false })
        end
    end
    shown.value = after
    if going then going:stop() end
    going = g.after(look.CLOSE + 0.02, function()
        going = nil
        local kept: { Shown } = {}
        for _, s in g.untracked(function() return shown.value end) do
            if not s.leaving then table.insert(kept, s) end
        end
        shown.value = kept
    end)
end)

-- Whether there are any to choose from.
function M.any(): boolean return #panes.tabs.value > 1 end

-- `width()`: the row's room.
function M.new(width: () -> number): any
    local DASHED = H
    -- What a name may take, when they do not all fit.
    local function room(): number
        local n = 0
        for _, t in panes.tabs.value do n += #t.panes.value end
        local count = #panes.tabs.value
        local free = width() - INSET * 2 - DASHED - 8 - GAP * count - count * (PAD * 2 + CLOSE) - (n - count) * SEAM
        return math.clamp(math.floor(free / math.max(1, n)), 24, NAME_MAX)
    end
    -- Its names and the room for its cross, padded alike either side.
    local function slot_w(t: panes.Tab): number
        local w = PAD * 2 + CLOSE
        for i, p in t.panes.value do w += name_w(named(p), room()) + (if i > 1 then SEAM else 0) end
        return w
    end
    local function width_of(t: panes.Tab): number return g.untracked(function() return slot_w(t) end) end
    -- Where a tab is in the row, and where the seen one is, from the widths
    -- the names are going to.
    local function x_of(t: panes.Tab): number
        local x = 0
        for _, s in shown.value do
            if s.tab == t then break end
            if not s.leaving then x += slot_w(s.tab) + GAP end
        end
        return x
    end
    local function edges(): { number }
        local seen = panes.tab.value
        for _, s in shown.value do
            if not s.leaving and s.tab == seen then
                local x = x_of(seen)
                return { x, x + slot_w(seen) }
            end
        end
        return { 0, 0 }
    end
    local function names_w(): number
        local x, n = 0, 0
        for _, s in shown.value do
            if not s.leaving then
                x += slot_w(s.tab) + (if n > 0 then GAP else 0)
                n += 1
            end
        end
        return x
    end

    -- The pill's two edges, each on its own spring: the one it moves
    -- towards leads.
    local first = g.untracked(edges)
    local left, right = g.animated(first[1]), g.animated(first[2])
    g.watch(function()
        local e = edges()
        return `{e[1]}:{e[2]}`
    end, function()
        local e = g.untracked(edges)
        local going_right = e[1] > g.untracked(function() return left.target end)
        left:set(e[1], if going_right then "pill_trail" else "pill_lead")
        right:set(e[2], if going_right then "pill_lead" else "pill_trail")
    end)

    local held: any = nil
    local function row(item: () -> Shown, _: any): any
        local first_item = g.untracked(item)
        local function tab(): panes.Tab return item().tab end
        local grown = g.signal(not first_item.fresh)
        if first_item.fresh then g.after(0, function() grown.value = true end) end
        local over = g.signal(false)
        local function seen(): boolean return panes.tab.value == tab() end
        local function out(): boolean return grown.value and not item().leaving end
        local function timing(): string return if out() then "cell_open" else "cell_close" end
        local last = H
        local function wide_now(): number
            -- Going, it is no longer asked what it holds.
            if not item().leaving then last = slot_w(tab()) end
            return last
        end
        -- Whether the pill is under the tab's middle now: its names are
        -- written dark at once, the pill passing is what changes them.
        local function covered(): boolean
            local middle = x_of(tab()) + wide_now() / 2
            return middle >= left.value and middle <= right.value
        end
        local function ink(lit: boolean): string
            if covered() then return look.background() end
            return if lit or over.value then look.text() else look.text_muted()
        end
        -- Where its folder is, for what is dropped on it.
        local function folder(): string?
            local s = item()
            if s.leaving then return nil end
            local list = s.tab.panes.value
            local p = list[math.clamp(s.tab.at.value, 1, #list)]
            return if p then p.here.value else nil
        end
        local function welcome(): boolean
            local f = folder()
            return f ~= nil and not seen() and exchange.welcome(`tab:{tab().id}`, f)
        end
        local function words(place: number): any
            local function pane(): any return tab().panes.value[place] end
            local function lit(): boolean
                local t = tab()
                return #t.panes.value < 2 or t.at.value == place
            end
            return g.text {
                present = function() return pane() ~= nil end,
                text = function()
                    local p = pane()
                    return if p then named(p) else ""
                end,
                max_width = room,
                ellipsize = "middle",
                color = function() return ink(seen() and lit()) end,
                font = look.expressive,
                size = look.font_label,
                weight = function() return if seen() and lit() then 600 else 500 end,
            }
        end
        local node: { [any]: any } = exchange.target({
            id = "tab",
            role = "button",
            name = "Tab",
            width = function() return if out() then wide_now() else 0 end,
            height = H,
            radius = look.round(H / 2),
            clip = true,
            opacity = function() return if out() then 1 else 0 end,
            fill = look.CLEAR,
            rim_top = function() return if welcome() then look.primary() else look.CLEAR end,
            rim_bottom = function() return if welcome() then look.primary() else look.CLEAR end,
            transition = { width = timing, opacity = timing, rim_top = "ui_change", rim_bottom = "ui_change" },
            on_hover = function(on: boolean) over.value = on end,
            on_press = function(button: number)
                if button == 272 then
                    panes.show(g.untracked(tab))
                    held = { tab = g.untracked(tab) }
                end
            end,
            -- Dragged past the middle of the one beside it, it takes its place.
            on_drag = function(x: number)
                if held == nil then return end
                local list = g.untracked(function() return panes.tabs.value end)
                local at = table.find(list, held.tab)
                if at == nil then return end
                local w = width_of(held.tab)
                local next_one, before = list[at + 1], list[at - 1]
                if next_one and x > w + GAP + width_of(next_one) / 2 then
                    panes.move(held.tab, at + 1)
                elseif before and x < -GAP - width_of(before) / 2 then
                    panes.move(held.tab, at - 1)
                end
            end,
            on_release = function() held = nil end,
            on_click = function(button: number)
                if button == 274 then
                    panes.close(g.untracked(tab))
                elseif button == 273 then
                    local x, y = g.pressed_at()
                    local t = g.untracked(tab)
                    menu.open({
                        { text = "New tab", keys = "Ctrl T", act = function() panes.new_tab() end },
                        "-",
                        { text = "Close", keys = "Ctrl W", act = function() panes.close(t) end },
                        {
                            text = "Close the others",
                            off = #g.untracked(function() return panes.tabs.value end) < 2,
                            act = function()
                                panes.show(t)
                                for _, o in g.untracked(function() return panes.tabs.value end) do
                                    if o ~= t then panes.close(o) end
                                end
                            end,
                        },
                    }, x, y)
                end
            end,
            -- The names in the middle; the cross in the room on the right.
            g.box {
                overlay = true,
                attach = "corner",
                width = wide_now,
                height = H,
                direction = "row",
                align = "center",
                justify = "center",
                words(1),
                -- Two folders, one seam.
                g.box {
                    present = function() return #tab().panes.value > 1 end,
                    width = SEAM,
                    height = H,
                    align = "center",
                    justify = "center",
                    g.capsule {
                        width = 1,
                        height = 14,
                        crisp = true,
                        radius = 0,
                        fill = function() return if covered() then g.colour.alpha(look.background(), 0.5) else look.node() end,
                        rim_top = look.CLEAR,
                        rim_bottom = look.CLEAR,
                    },
                },
                words(2),
            },
            g.box {
                overlay = true,
                attach = "corner",
                id = "tab-close",
                role = "button",
                name = "Close the tab",
                offset_x = function() return wide_now() - PAD / 2 - CLOSE end,
                width = CLOSE,
                height = H,
                align = "center",
                justify = "center",
                opacity = function() return if over.value then 1 else 0 end,
                transition = { opacity = "ui_change" },
                on_hover = function(on: boolean) over.value = on end,
                on_press = function() end,
                on_click = function(button: number) if button == 272 then panes.close(g.untracked(tab)) end end,
                ui.glyph("close", 10, function() return false end, function() return ink(false) end),
            },
        }, `tab:{first_item.tab.id}`, folder, function(_: string) panes.show(g.untracked(tab)) end)
        return g.capsule(node)
    end

    local function edge(): string
        local h, sat, l = g.colour.hsl(look.secondary())
        return g.colour.hsla(math.max(0, h), sat * 0.6, l * 0.42, 1)
    end
    local track = g.capsule {
        width = function() return names_w() + INSET * 2 end,
        height = H + INSET * 2,
        radius = look.round((H + INSET * 2) / 2),
        -- A well a little darker than the window, with no outline: an
        -- outline would make it the segmented choice of the settings.
        fill = g.colour.alpha("#000000", 0.28),
        rim_top = look.CLEAR,
        rim_bottom = look.CLEAR,
        transition = { width = "cell_open" },
        -- The pill under the seen one's names, kept inside the track
        -- however far a spring carries an edge.
        g.capsule {
            overlay = true,
            attach = "corner",
            offset_x = function() return INSET + math.clamp(left.value, 0, math.max(0, names_w() - H)) end,
            offset_y = INSET,
            width = function()
                local l = math.clamp(left.value, 0, math.max(0, names_w() - H))
                return math.max(H, math.min(right.value, names_w()) - l)
            end,
            height = H,
            radius = look.round(H / 2),
            fill = look.secondary_top,
            fill_bottom = look.secondary_bottom,
            -- Its edge in its own hue, darker.
            rim_top = edge,
            rim_bottom = edge,
        },
        g.each {
            overlay = true,
            attach = "corner",
            offset_x = INSET,
            offset_y = INSET,
            direction = "row",
            gap = GAP,
            items = function() return shown.value end,
            key = function(s: Shown) return s.tab.id end,
            row = row,
        },
    }
    return g.box {
        present = M.any,
        direction = "row",
        align = "center",
        gap = 8,
        height = H + INSET * 2,
        track,
        ui.action { id = "new-tab", name = "New tab", glyph = "plus", kind = "dashed", on_click = function() panes.new_tab() end },
    }
end

return M
