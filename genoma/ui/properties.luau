--!strict
-- What there is to know of some entries: a cell that grows from them. Read only,
-- but for what opens a kind of file.
local g = require("@genoma")
local files = require("@genoma/files")
local mime = require("@genoma/mime")
local colours = require("core/colours")
local format = require("core/format")
local icons = require("core/icons")
local paths = require("core/paths")
local look = require("ui/look")
local ui = require("ui/controls")
local scroll_mark = require("ui/scroll_mark")

local M = {}

local WIDTH, PAD, ICON, APPS = 440, 22, 64, 8

-- What is shown: the paths, and the entry when it is one.
type Shown = { list: { string }, entry: any, key: number }
local shown = g.signal(nil :: Shown?)
local grown = g.signal(false)
local from = g.signal({ x = 0, y = 0, w = 40, h = 40 })
local facts = g.signal(nil :: any)
local total = g.signal(nil :: { it: any, whole: boolean }?)
local measuring: any = nil
local going: any = nil
local count = 0

function M.is_open(): boolean return shown.value ~= nil and grown.value end

local function stop()
    if measuring then measuring:stop() end
    measuring = nil
end

function M.close()
    if not g.untracked(function() return grown.value end) then return end
    grown.value = false
    stop()
    if going then going:stop() end
    going = g.after(look.CLOSE, function()
        going = nil
        shown.value = nil
    end)
end

-- `origin`: where they are drawn, { x, y, w, h }.
function M.open(list: { string }, entry: any, origin: any)
    if #list == 0 then return end
    if going then going:stop() end
    going = nil
    stop()
    count += 1
    local key = count
    g.batch(function()
        facts.value = nil
        total.value = nil
        from.value = origin
        grown.value = false
        shown.value = { list = list, entry = entry, key = key }
    end)
    g.after(0, function() grown.value = true end)
    if #list == 1 then
        files:facts(list[1], function(f: any)
            if key == count then facts.value = f or false end
        end)
    end
    measuring = files:measure(list, function(it: any, whole: boolean)
        if key == count then total.value = { it = it, whole = whole } end
    end)
end

local function some(n: number, one: string): string return `{n} {one}{if n == 1 then "" else "s"}` end

-- `own`: how many of the folders counted are the ones asked about.
local function inside(own: number): string
    local t = total.value
    if t == nil then return "" end
    local it = t.it
    local folders = math.max(0, it.folders - own)
    local what = if folders > 0 then `{some(it.files, "file")}, {some(folders, "folder")}` else some(it.files, "file")
    if it.unread > 0 then what ..= `, {it.unread} not to be read` end
    return what
end
local function size(): string
    local t = total.value
    if t == nil then return "" end
    local text = format.size(t.it.bytes)
    -- Holes, or many small files.
    if math.abs(t.it.on_disk - t.it.bytes) > math.max(t.it.bytes * 0.1, 64e3) then text ..= `   {format.size(t.it.on_disk)} on the disk` end
    return if t.whole then text else text .. " …"
end

local function may(bits: number, dir: boolean): string
    local out: { string } = {}
    if bit32.btest(bits, 4) then table.insert(out, "read") end
    if bit32.btest(bits, 2) then table.insert(out, "write") end
    if bit32.btest(bits, 1) then table.insert(out, if dir then "enter" else "run") end
    return if #out > 0 then table.concat(out, ", ") else "nothing"
end

local function fact(name: string, value: () -> string, human: boolean?): any
    return g.box {
        present = function() return value() ~= "" end,
        direction = "row",
        align = "center",
        justify = "between",
        gap = 12,
        height = 24,
        ui.label(name, look.text_faint),
        g.text {
            text = value,
            max_width = WIDTH - PAD * 2 - 110,
            ellipsize = "middle",
            color = look.text,
            font = if human then look.expressive else look.technical,
            size = if human then look.font_text else look.font_meta,
            tabular = true,
        },
    }
end
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

-- What opens its kind: the one chosen, for every file of it.
local function openers(e: any): any
    local chosen = g.signal(nil :: string?)
    local list = g.computed(function(): { any }
        local _ = chosen.value
        local out: { any } = {}
        for i, app in mime:apps(e.mime) do
            if i <= APPS then table.insert(out, app) end
        end
        return out
    end)
    local first = g.untracked(function() return list.value end)
    if #first == 0 then return g.box {} end
    chosen.value = first[1].id
    local rows: { [any]: any } = { direction = "column", align = "stretch", gap = 2 }
    for _, app in first do
        local over = g.signal(false)
        local function on(): boolean return chosen.value == app.id end
        table.insert(rows, g.capsule {
            role = "button",
            name = app.name,
            height = 32,
            padding_x = 12,
            gap = 10,
            direction = "row",
            align = "center",
            justify = "start",
            radius = look.round(look.radius_well),
            fill = function() return if on() then look.chosen() elseif over.value then look.hovered() else look.CLEAR end,
            rim_top = look.CLEAR,
            rim_bottom = look.CLEAR,
            transition = { fill = "ui_change" },
            on_hover = function(o: boolean) over.value = o end,
            on_press = function() end,
            on_click = function(button: number)
                if button ~= 272 or g.untracked(on) then return end
                local ok = pcall(function() mime:set_default(e.mime, app.id) end)
                if ok then chosen.value = app.id end
            end,
            g.icon { width = 18, height = 18, icon = app.icon },
            g.text { text = app.name, color = look.text, font = look.technical, size = look.font_menu, weight = function() return if on() then 700 else 500 end, tracking = 0.02 },
        })
    end
    return g.box {
        direction = "column",
        align = "stretch",
        gap = 8,
        rule(),
        ui.label(`Every {mime:description(e.mime)} opens with`, look.text_faint),
        g.box(rows),
    }
end

local function page(s: Shown): any
    local e = s.entry
    local one = #s.list == 1
    local path = s.list[1]
    local where = paths.parent(path)
    local same = true
    for _, p in s.list do same = same and paths.parent(p) == where end
    local function f(key: string): any return if facts.value then facts.value[key] else nil end
    local function time(key: string): () -> string
        return function(): string
            local t = f(key)
            return if t then format.moment(t) else ""
        end
    end
    local function permitted(shift: number): () -> string
        return function(): string
            -- A link's are everybody's: what it leads to has its own.
            local mode = if f("target") then nil else f("mode")
            return if mode then may(bit32.band(bit32.rshift(mode, shift), 7), e ~= nil and e.dir) else ""
        end
    end
    local name = if not one then some(#s.list, "item") elseif e then e.name else paths.called(path)
    local key = if e then colours.of(e) else nil
    return g.box {
        direction = "column",
        align = "stretch",
        padding = PAD,
        gap = 14,
        g.box {
            direction = "row",
            align = "center",
            gap = 16,
            g.box {
                present = e ~= nil,
                g.icon { width = ICON, height = ICON, icon = function() return if e then icons.of(e, ICON) else "" end },
            },
            g.box {
                direction = "column",
                align = "start",
                gap = 3,
                g.text {
                    text = name,
                    max_width = WIDTH - PAD * 2 - (if e then ICON + 16 else 0),
                    wrap = true,
                    color = look.text,
                    font = look.expressive,
                    size = 17,
                    weight = 600,
                },
                g.text {
                    present = e ~= nil,
                    text = if e == nil then "" elseif e.broken then "Link to nothing" else mime:description(e.mime),
                    color = look.text_muted,
                    font = look.expressive,
                    size = look.font_text,
                },
            },
        },
        g.box {
            direction = "column",
            align = "stretch",
            fact("Where", function() return if same and where then where else "" end, true),
            fact("Leads to", function() return f("target") or "" end, true),
            fact("Inside", function() return if one and e and not e.dir then "" else inside(if one then 1 else 0) end),
            fact("Size", size),
            fact("Colour", function() return if key then colours.name(key) else "" end),
        },
        g.box {
            present = one,
            direction = "column",
            align = "stretch",
            gap = 14,
            rule(),
            g.box {
                direction = "column",
                align = "stretch",
                fact("Modified", time("modified")),
                fact("Made", time("created")),
                fact("Opened", time("accessed")),
            },
            rule(),
            g.box {
                direction = "column",
                align = "stretch",
                fact("Owner", function() return f("owner") or "" end),
                fact("The owner may", permitted(6)),
                fact("The group may", function()
                    local said = permitted(3)()
                    return if said == "" then "" else `{f("group")}: {said}`
                end),
                fact("Others may", permitted(0)),
                fact("Free on its disk", function()
                    local all = f("total")
                    return if all and all > 0 then `{format.size(f("free"))} of {format.size(all)}` else ""
                end),
            },
            if one and e and not e.dir and not e.broken then openers(e) else g.box {},
        },
    }
end

-- `area()`: the window's { w, h }.
function M.new(area: () -> { w: number, h: number }): any
    local E = look.margin_edge
    local content_h = g.signal(360)
    local scroller: any = nil
    local function width(): number return math.min(WIDTH, area().w - E * 2) end
    local function tall(): number return math.min(content_h.value, area().h - E * 2) end
    local function timing(): string return if grown.value then "cell_open" else "cell_close" end
    scroller = scroll_mark.new { height = tall, x = function() return width() - 6 end, room = function() return math.max(0, content_h.value - tall()) end }
    return g.box {
        overlay = true,
        attach = "corner",
        present = function() return shown.value ~= nil end,
        width = function() return area().w end,
        height = function() return area().h end,
        g.box {
            overlay = true,
            attach = "corner",
            width = function() return area().w end,
            height = function() return area().h end,
            on_press = function() M.close() end,
            on_click = function() end,
        },
        g.capsule {
            id = "properties",
            name = "Properties",
            overlay = true,
            attach = "corner",
            offset_x = function() return if grown.value then (area().w - width()) / 2 else from.value.x end,
            offset_y = function() return if grown.value then (area().h - tall()) / 2 else from.value.y end,
            width = function() return if grown.value then width() else from.value.w end,
            height = function() return if grown.value then tall() else from.value.h end,
            radius = look.round(look.radius_panel),
            opacity = function() return if grown.value then 1 else 0 end,
            clip = true,
            fill = look.glass_over,
            rim_top = look.rim,
            rim_bottom = look.line,
            backdrop_blur = look.glass_blur,
            transition = { offset_x = timing, offset_y = timing, width = timing, height = timing, opacity = timing },
            on_press = function() end,
            on_click = function() end,
            g.box {
                overlay = true,
                attach = "corner",
                width = width,
                height = tall,
                scroll = "y",
                clip = true,
                fade_bottom = scroller.fade,
                on_scroll = function(_: number, y: number) scroller.follow(y, 0) end,
                opacity = function() return if grown.value then 1 else 0 end,
                transition = { opacity = function() return if grown.value then "content_in" else "content_out" end },
                g.box {
                    width = width,
                    direction = "column",
                    align = "stretch",
                    on_size = function(_: number, h: number) if h > 40 then content_h.value = h end end,
                    g.each {
                        direction = "column",
                        align = "stretch",
                        items = function(): { Shown } return if shown.value then { shown.value } else {} end,
                        key = function(s: Shown) return s.key end,
                        row = function(s, _) return page(g.untracked(s)) end,
                    },
                },
            },
        },
    }
end

return M
