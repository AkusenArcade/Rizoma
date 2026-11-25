--!strict
-- The tabs, under the path and over the panes, when there is more than one:
-- each a capsule with what its panes show. The path above is the one seen's.
local g = require("@genoma")
local exchange = require("core/exchange")
local menu = require("ui/menu")
local panes = require("core/panes")
local paths = require("core/paths")
local look = require("ui/look")
local ui = require("ui/controls")

local M = {}

local H, PAD, GAP, CLOSE, NAME_MAX, SEAM = look.action_height, 14, 8, 20, 180, 17
M.HEIGHT = H

local function name_w(name: string, room: number): number
    local w = g.text_width { text = name, font = look.expressive(), size = look.font_secondary, weight = 600 }
    return math.min(math.ceil(w) + 1, room)
end
local function named(p: any): string return paths.called(p.here.value) end

-- A closed one is there until it has gone back.
type Shown = { tab: panes.Tab, names: { string }, leaving: boolean, fresh: boolean }
local shown = g.signal({} :: { Shown })
local going: any = nil
g.watch(function() return panes.tabs.value end, function(tabs: { panes.Tab })
    local before = g.untracked(function() return shown.value end)
    local after: { Shown } = {}
    local had: { [any]: boolean } = {}
    for _, s in before do if not s.leaving then had[s.tab] = true end end
    for _, t in tabs do table.insert(after, { tab = t, names = {}, leaving = false, fresh = #before > 0 and not had[t] }) end
    for i, s in before do
        local kept = table.find(tabs, s.tab) ~= nil
        if not kept and not s.leaving and #tabs > 1 then
            table.insert(after, math.min(i, #after + 1), { tab = s.tab, names = s.names, leaving = true, fresh = false })
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

local function words(tab: () -> panes.Tab, place: number, room: () -> number, seen: () -> boolean): any
    local function pane(): any return tab().panes.value[place] end
    local function lit(): boolean
        local t = tab()
        return seen() and (#t.panes.value < 2 or t.at.value == place)
    end
    return g.text {
        present = function() return pane() ~= nil end,
        text = function()
            local p = pane()
            return if p then named(p) else ""
        end,
        max_width = room,
        ellipsize = "middle",
        color = function() return if lit() then look.text() else look.text_muted() end,
        font = look.expressive,
        size = look.font_secondary,
        weight = function() return if lit() then 600 else 400 end,
        transition = { color = "ui_change" },
    }
end

-- `width()`: the row's room.
function M.new(width: () -> number): any
    local DASHED = H
    -- What a name may take, when they do not all fit.
    local function room(): number
        local n = 0
        for _, t in panes.tabs.value do n += #t.panes.value end
        local count = #panes.tabs.value
        local free = width() - DASHED - GAP * count - count * (PAD * 2 + CLOSE) - (n - count) * SEAM
        return math.clamp(math.floor(free / math.max(1, n)), 24, NAME_MAX)
    end
    local function tab_w(t: panes.Tab): number
        local w = PAD * 2 + CLOSE
        for i, p in t.panes.value do w += name_w(named(p), room()) + (if i > 1 then SEAM else 0) end
        return w
    end
    local held: any = nil
    local function row(item: () -> Shown, _: any): any
        local first = g.untracked(item)
        local function tab(): panes.Tab return item().tab end
        local grown = g.signal(not first.fresh)
        if first.fresh then g.after(0, function() grown.value = true end) end
        local over = g.signal(false)
        local function seen(): boolean return panes.tab.value == tab() end
        local function out(): boolean return grown.value and not item().leaving end
        local function timing(): string return if out() then "cell_open" else "cell_close" end
        -- Where its folder is, for what is dropped on it.
        local function folder(): string?
            local s = item()
            if s.leaving then return nil end
            local list = s.tab.panes.value
            local p = list[math.clamp(s.tab.at.value, 1, #list)]
            return if p then p.here.value else nil
        end
        local function edge(): string
            local f = folder()
            if f and not seen() and exchange.welcome(`tab:{tab().id}`, f) then return look.primary() end
            if seen() then return look.rim() end
            return if over.value then look.node() else look.line()
        end
        local last = H
        local function wide(): number
            -- Going, it is no longer asked what it holds.
            if not item().leaving then last = tab_w(tab()) end
            return last
        end
        local node: { [any]: any } = exchange.target({
            id = "tab",
            role = "button",
            name = "Tab",
            width = function() return if out() then wide() else H * 0.4 end,
            height = H,
            radius = look.round(H / 2),
            clip = true,
            opacity = function() return if out() then 1 else 0 end,
            fill = function() return if seen() then look.cell() else look.glass() end,
            rim_top = edge,
            rim_bottom = function() return if seen() then look.line() else edge() end,
            transition = { width = timing, opacity = timing, fill = "ui_change", rim_top = "ui_change", rim_bottom = "ui_change" },
            on_hover = function(on: boolean) over.value = on end,
            on_press = function(button: number)
                if button == 272 then
                    panes.show(g.untracked(tab))
                    held = { tab = g.untracked(tab), x = select(1, g.pressed_at()), at = table.find(g.untracked(function() return panes.tabs.value end), g.untracked(tab)) }
                end
            end,
            -- Dragged past the middle of the one beside it, it takes its place.
            on_drag = function(x: number)
                if held == nil then return end
                local list = g.untracked(function() return panes.tabs.value end)
                local at = table.find(list, held.tab)
                if at == nil then return end
                local w = g.untracked(function() return tab_w(held.tab) end)
                local next_one, before = list[at + 1], list[at - 1]
                if next_one and x > w + GAP + g.untracked(function() return tab_w(next_one) end) / 2 then
                    panes.move(held.tab, at + 1)
                elseif before and x < -GAP - g.untracked(function() return tab_w(before) end) / 2 then
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
            g.box {
                overlay = true,
                attach = "corner",
                offset_x = PAD,
                height = H,
                direction = "row",
                align = "center",
                gap = 0,
                words(tab, 1, room, seen),
                -- Two folders, one seam.
                g.box {
                    present = function() return #tab().panes.value > 1 end,
                    width = SEAM,
                    height = H,
                    align = "center",
                    justify = "center",
                    g.capsule { width = 1, height = 14, crisp = true, radius = 0, fill = look.node, rim_top = look.CLEAR, rim_bottom = look.CLEAR },
                },
                words(tab, 2, room, seen),
                g.box {
                    id = "tab-close",
                    role = "button",
                    name = "Close the tab",
                    width = CLOSE + 6,
                    height = H,
                    align = "center",
                    justify = "center",
                    opacity = function() return if over.value or seen() then 1 else 0 end,
                    transition = { opacity = "ui_change" },
                    on_hover = function(on: boolean) over.value = on end,
                    on_press = function() end,
                    on_click = function(button: number) if button == 272 then panes.close(g.untracked(tab)) end end,
                    ui.glyph("close", 12, function() return false end, look.text_muted),
                },
            },
        }, `tab:{first.tab.id}`, folder, function(_: string) panes.show(g.untracked(tab)) end)
        return g.capsule(node)
    end
    return g.box {
        present = M.any,
        direction = "row",
        align = "center",
        gap = GAP,
        height = H,
        g.each {
            direction = "row",
            align = "center",
            gap = GAP,
            items = function() return shown.value end,
            key = function(s: Shown) return s.tab.id end,
            row = row,
        },
        ui.action { id = "new-tab", name = "New tab", glyph = "plus", kind = "dashed", on_click = function() panes.new_tab() end },
    }
end

return M
