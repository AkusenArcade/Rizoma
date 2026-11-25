--!strict
-- The places: a panel beside the folder where there is room, a cell that
-- grows from its button where there is not.
local g = require("@genoma")
local browser = require("core/browser")
local places = require("core/places")
local exchange = require("core/exchange")
local actions = require("ui/actions")
local look = require("ui/look")
local ui = require("ui/controls")
local scroll_mark = require("ui/scroll_mark")

local M = {}

M.WIDTH = 240
local PAD, BUTTON, ROW, ICON = 8, look.cell_height, 40, 22

local function row(place: () -> any): any
    local over = g.signal(false)
    local function welcome(): boolean return exchange.welcome(place().path) end
    local function here(): boolean
        local p = places.of(browser.here.value)
        return p ~= nil and p.path == place().path
    end
    return g.capsule(exchange.target({
        role = "button",
        height = ROW,
        padding_x = 12,
        gap = 12,
        direction = "row",
        align = "center",
        justify = "start",
        radius = look.radius_panel - PAD,
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
            if button == 272 then M.chose(g.untracked(place).path)
            elseif button == 273 then actions.on_place(g.untracked(place).path, function() M.chose(g.untracked(place).path) end)
            end
        end,
        ui.glyph(g.untracked(place).glyph, ICON, here, look.text_muted),
        g.text {
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
    }, function() return place().path end, true))
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
        g.capsule {
            present = name ~= "own",
            height = 1,
            crisp = true,
            radius = 0,
            fill = function() return g.colour.alpha(look.line(), 0.6) end,
            rim_top = look.CLEAR,
            rim_bottom = look.CLEAR,
        },
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
        radius = look.radius_panel,
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
            radius = look.radius_panel - PAD,
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
            },
        },
    }
end

return M
