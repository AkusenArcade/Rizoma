--!strict
-- The places: a panel beside the folder where there is room, a cell that
-- grows from its button where there is not.
local g = require("@genoma")
local browser = require("core/browser")
local panes = require("core/panes")
local paths = require("core/paths")
local drives = require("core/drives")
local places = require("core/places")
local exchange = require("core/exchange")
local actions = require("ui/actions")
local look = require("ui/look")
local ui = require("ui/controls")
local scroll_mark = require("ui/scroll_mark")

local M = {}

M.WIDTH = 240
local PAD, BUTTON, ROW, ICON = 6, look.cell_height, 40, 22

-- A row's, concentric with the panel it is in.
local pinned = function(): boolean return true end
local function row_radius(): number
    return if pinned() then look.in_corner(look.margin_edge + PAD)() else look.within(PAD)()
end

-- The bookmark whose name is being written.
M.naming = g.signal(nil :: string?)
M.typed = g.signal("")
local function name_it(place: any)
    M.typed.value = place.name
    M.naming.value = place.path
end
function M.named()
    local path = g.untracked(function() return M.naming.value end)
    M.naming.value = nil
    if path then places.rename(path, g.untracked(function() return M.typed.value end)) end
end

-- Elsewhere gone, or something chosen: what was written is meant.
g.watch(function() return browser.here.value .. "\0" .. (browser.cursor.value or "") end, function()
    if g.untracked(function() return M.naming.value end) ~= nil then M.named() end
end)

-- A bookmark being dragged along the others, and the one it would go beside.
local moving = g.signal(nil :: { path: string, beside: string, after: boolean }?)

local function row(place: () -> any): any
    local over = g.signal(false)
    local bookmark = g.untracked(place).group == "bookmark"
    local function welcome(): boolean return exchange.welcome("place", place().path) end
    local function here(): boolean
        local p = places.of(browser.here.value)
        return p ~= nil and p.path == place().path
    end
    local function naming(): boolean return M.naming.value == place().path end
    local function beside(after: boolean): boolean
        local m = moving.value
        return m ~= nil and m.beside == place().path and m.after == after and m.path ~= place().path
    end
    local held, far = nil :: number?, false
    local node: { [any]: any } = {
        role = "button",
        height = ROW,
        padding_x = 12,
        gap = 12,
        direction = "row",
        align = "center",
        justify = "start",
        radius = row_radius,
        opacity = function() return if moving.value and moving.value.path == place().path then 0.5 else 1 end,
        fill = function()
            if here() or welcome() then return look.chosen() end
            return if over.value then look.hovered() else look.CLEAR
        end,
        rim_top = function() return if welcome() then look.primary() else look.CLEAR end,
        rim_bottom = function() return if welcome() then look.primary() else look.CLEAR end,
        transition = { fill = "ui_change" },
        on_hover = function(on: boolean) over.value = on end,
        on_press = function(button: number, _: number, y: number)
            held, far = if bookmark and button == 272 then y else nil, false
        end,
        on_click = function(button: number)
            if far then return end
            local p = g.untracked(place)
            if button == 274 then panes.new_tab(p.path, true)
            elseif button == 272 then M.chose(p.path)
            elseif button == 273 then
                actions.on_place(p.path, function() M.chose(p.path) end, if bookmark then function() name_it(p) end else nil)
            end
        end,
        ui.glyph(g.untracked(place).glyph, ICON, here, look.text_muted),
        g.text {
            present = function() return not naming() end,
            -- A menu's words, so the technical voice (Akusen, 2026-11-25); the
            -- names keep the case they were given.
            text = function() return place().name end,
            max_width = M.WIDTH - PAD * 2 - 24 - 12 - ICON,
            ellipsize = "end",
            color = look.text,
            font = look.technical,
            size = look.font_menu,
            weight = function() return if here() then 700 else 500 end,
            tracking = 0.02,
        },
    }
    if bookmark then
        -- Dragged up or down, it goes between two others.
        node.on_drag = function(_: number, y: number)
            if held == nil then return end
            if not far and math.abs(y - held) < 6 then return end
            far = true
            local list: { any } = {}
            for _, p in g.untracked(function() return places.list.value end) do
                if p.group == "bookmark" then table.insert(list, p) end
            end
            local me = g.untracked(place).path
            local at = 0
            for i, p in list do if p.path == me then at = i end end
            local over_at = math.clamp(at + math.floor(y / (ROW + 2)), 1, #list)
            local within = (y / (ROW + 2)) % 1
            moving.value = { path = me, beside = list[over_at].path, after = within > 0.5 }
        end
        node.on_release = function()
            local m = g.untracked(function() return moving.value end)
            held, moving.value = nil, nil
            if m and m.path ~= m.beside then places.move(m.path, m.beside, m.after) end
        end
        table.insert(node, g.field {
            present = naming,
            width = M.WIDTH - PAD * 2 - 24 - 12 - ICON,
            size = look.font_menu,
            font = look.technical,
            color = look.text,
            caret_color = look.primary,
            selection_color = look.chosen,
            placeholder = function() return paths.name(place().path) end,
            select = "all",
            focused = naming,
            text = function() return M.typed.value end,
            on_change = function(text: string) M.typed.value = text end,
            on_submit = M.named,
        })
        for _, after in { false, true } do
            table.insert(node, g.capsule {
                overlay = true,
                attach = "corner",
                present = function() return beside(after) end,
                offset_x = 8,
                offset_y = if after then ROW else -2,
                width = M.WIDTH - PAD * 2 - 16,
                height = 2,
                radius = 1,
                fill = look.primary,
                rim_top = look.CLEAR,
                rim_bottom = look.CLEAR,
            })
        end
    end
    return g.capsule(exchange.target(node, "place", function() return place().path end, function(path: string)
        if path ~= paths.TRASH then browser.go(path) end
    end))
end

-- A disk plugged in: its stick is filled as far as it is used; not mounted, it
-- stands back. It is ejected from here.
local function drive(v: () -> drives.Volume): any
    local over, over_eject = g.signal(false), g.signal(false)
    local function mounted(): boolean return v().mount ~= nil end
    local function here(): boolean
        local m = v().mount
        return m ~= nil and paths.inside(browser.here.value, m)
    end
    local function welcome(): boolean
        local m = v().mount
        return m ~= nil and exchange.welcome("place", m)
    end
    local function ink(): string return if here() then look.primary() elseif mounted() then look.text() else look.text_faint() end
    local function said(): string
        local it = v()
        if it.busy ~= "" then return it.busy end
        return if it.writing then "writing" else ""
    end
    local function level(): string
        local h = 9.5 * (v().used or 0)
        if h < 0.05 then return "M8.75 19.25 H15.25 Z" end
        local r, t = math.min(1.25, h / 2), 19.25 - h
        return string.format(
            "M8.75 %.3f a%.3f %.3f 0 0 1 %.3f %.3f H%.3f a%.3f %.3f 0 0 1 %.3f %.3f V%.3f a%.3f %.3f 0 0 1 %.3f %.3f H%.3f a%.3f %.3f 0 0 1 %.3f %.3f Z",
            t + r, r, r, r, -r, 15.25 - r, r, r, r, r, 19.25 - r, r, r, -r, r, 8.75 + r, r, r, -r, -r
        )
    end
    local EJECT = 28
    return g.capsule(exchange.target({
        role = "button",
        name = "Drive",
        height = ROW,
        padding_x = 12,
        gap = 12,
        direction = "row",
        align = "center",
        justify = "start",
        radius = row_radius,
        fill = function()
            if here() or welcome() then return look.chosen() end
            return if over.value then look.hovered() else look.CLEAR
        end,
        rim_top = function() return if welcome() then look.primary() else look.CLEAR end,
        rim_bottom = function() return if welcome() then look.primary() else look.CLEAR end,
        transition = { fill = "ui_change" },
        on_hover = function(on: boolean) over.value = on end,
        on_press = function() end,
        on_click = function(button: number)
            local it = g.untracked(v)
            if button == 274 then drives.open(it.device, true)
            elseif button == 272 then drives.open(it.device)
            elseif button == 273 then actions.on_drive(it)
            end
        end,
        g.svg {
            width = ICON,
            height = ICON,
            src = g.dir .. "/icons/drive.svg",
            color = ink,
            opacity = function() return if mounted() then 1 else 0.7 end,
            parts = { level = { d = level, fill = ink, opacity = 0.45, transition = { d = "ui_change" } } },
        },
        g.box {
            direction = "column",
            align = "start",
            justify = "center",
            width = M.WIDTH - PAD * 2 - 24 - 24 - ICON - EJECT,
            g.text {
                text = function() return v().name end,
                max_width = M.WIDTH - PAD * 2 - 24 - 24 - ICON - EJECT,
                ellipsize = "end",
                color = function() return if mounted() then look.text() else look.text_muted() end,
                font = look.technical,
                size = look.font_menu,
                weight = function() return if here() then 700 else 500 end,
                tracking = 0.02,
            },
            -- What is being done to it: until it is over it is not to be pulled.
            g.text {
                present = function() return said() ~= "" end,
                text = said,
                color = look.primary,
                font = look.technical,
                size = look.font_meta - 1,
            },
        },
        g.box {
            id = "eject",
            role = "button",
            name = "Eject",
            present = function() return mounted() and v().busy == "" end,
            width = EJECT,
            height = EJECT,
            align = "center",
            justify = "center",
            on_hover = function(on: boolean) over_eject.value = on end,
            on_press = function() end,
            on_click = function(button: number) if button == 272 then drives.eject(g.untracked(v).id) end end,
            ui.glyph("eject", 16, function() return false end, function() return if over_eject.value then look.text() else look.text_faint() end),
        },
    }, "place", function() return v().mount end, function(path: string) browser.go(path) end))
end

-- A rule between two groups.
local function rule(): any
    return g.capsule {
        height = 1,
        crisp = true,
        radius = 0,
        fill = function() return g.colour.alpha(look.line(), 0.6) end,
        rim_top = look.CLEAR,
        rim_bottom = look.CLEAR,
    }
end

local function group(name: string): any
    local items = g.computed(function(): { any }
        local out = {}
        for _, p in places.list.value do
            if p.group == name then table.insert(out, p) end
        end
        return out
    end)
    return g.box {
        present = function() return #items.value > 0 end,
        direction = "column",
        align = "stretch",
        gap = 8,
        g.box { present = name ~= "own", direction = "column", align = "stretch", rule() },
        g.each {
            direction = "column",
            align = "stretch",
            gap = 2,
            items = function() return items.value end,
            key = function(p) return p.glyph .. p.path end,
            row = row,
        },
    }
end

-- Going there puts a floating one away; set by the shell.
M.chose = function(_: string) end

-- `t`: pinned(), open(), top(), height() (the window's).
function M.new(t: { [string]: any }): any
    pinned = t.pinned
    local function shown(): boolean return t.pinned() or t.open() end
    local content = g.signal(400)
    local E = look.margin_edge
    local function full(): number
        local room = t.height() - (if t.pinned() then E else t.top()) - E
        return if t.pinned() then room else math.min(room, content.value + PAD * 2)
    end
    -- There while it is shown and until it has closed: what cannot be seen
    -- would still take the presses.
    local there = g.signal(g.untracked(shown))
    local putting_away: any = nil
    g.watch(shown, function(on: boolean)
        if putting_away then putting_away:stop() end
        putting_away = nil
        if on then
            there.value = true
        else
            putting_away = g.after(look.CLOSE, function()
                putting_away = nil
                there.value = false
            end)
        end
    end)
    -- Opened, it grows from the button: the first frame is still the button.
    local grown = g.signal(g.untracked(shown))
    g.watch(function() return there.value and shown() end, function(on: boolean)
        if on then g.after(0, function() grown.value = g.untracked(shown) end) else grown.value = false end
    end)
    local scroller = scroll_mark.new { height = function() return full() - PAD * 2 end, x = function() return M.WIDTH - PAD - 2 end, room = function() return math.max(0, content.value - (full() - PAD * 2)) end }
    local function timing(): string return if grown.value then "cell_open" else "cell_close" end

    return g.capsule {
        id = "places",
        name = "Places",
        overlay = true,
        attach = "corner",
        present = function() return there.value end,
        offset_x = E,
        offset_y = function() return if grown.value and not t.pinned() then t.top() else E end,
        width = function() return if grown.value then M.WIDTH else BUTTON end,
        height = function() return if grown.value then full() else BUTTON end,
        -- Pinned it stands in the window's corner; floating it is a cell.
        radius = function() return if t.pinned() then look.in_corner(E)() else look.shaped(look.radius_panel) end,
        clip = true,
        opacity = function() return if grown.value then 1 else 0 end,
        fill = function() return if t.pinned() then look.glass() else look.glass_over() end,
        rim_top = look.rim,
        rim_bottom = look.line,
        backdrop_blur = function() return if t.pinned() then 0 else look.glass_blur end,
        transition = { offset_y = timing, width = timing, opacity = timing },
        on_press = function() end,
        on_click = function() end,
        g.box {
            overlay = true,
            attach = "corner",
            offset_x = PAD,
            offset_y = PAD,
            width = M.WIDTH - PAD * 2,
            height = function() return full() - PAD * 2 end,
            radius = row_radius,
            scroll = "y",
            clip = true,
            fade_bottom = scroller.fade,
            on_scroll = function(_: number, y: number)
                scroller.follow(y, 0)
            end,
            direction = "column",
            align = "stretch",
            opacity = function() return if grown.value then 1 else 0 end,
            transition = { opacity = function() return if grown.value then "content_in" else "content_out" end },
            g.box {
                direction = "column",
                align = "stretch",
                gap = 8,
                width = M.WIDTH - PAD * 2,
                on_size = function(_: number, h: number) content.value = h end,
                group("own"),
                group("bookmark"),
                group("computer"),
                g.box {
                    present = function() return #drives.list.value > 0 end,
                    direction = "column",
                    align = "stretch",
                    gap = 8,
                    rule(),
                    g.each {
                        direction = "column",
                        align = "stretch",
                        gap = 2,
                        items = function() return drives.list.value end,
                        key = function(v) return v.device end,
                        row = drive,
                    },
                },
            },
        },
    }
end

return M
