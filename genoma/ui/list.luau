--!strict
-- The folder as lines: name, size, when it changed, what it is. A column's
-- title sorts by it; pressed again, the other way round.
local g = require("@genoma")
local mime = require("@genoma/mime")
local browser = require("core/browser")
local config = require("core/config")
local operations = require("core/operations")
local format = require("core/format")
local look = require("ui/look")
local ui = require("ui/controls")
local selection = require("core/selection")
local band = require("ui/band")
local scroll_mark = require("ui/scroll_mark")
local entry_ui = require("ui/entry")

local M = {}

local ROW, PAD, GAP, HEAD = 38, 10, 14, 32
local SIZE_W, MODIFIED_W, TYPE_W = 84, 150, 170

local function wide(width: number): (boolean, boolean, boolean)
    return width >= 380, width >= 540, width >= 740
end
local function name_room(width: number): number
    local size, modified, kind = wide(width)
    local room = width - PAD * 2 - 28 - 10
    if size then room -= SIZE_W + GAP end
    if modified then room -= MODIFIED_W + GAP end
    if kind then room -= TYPE_W + GAP end
    return math.max(60, room)
end

local descriptions: { [string]: string } = {}
local function described(kind: string): string
    local hit = descriptions[kind]
    if hit == nil then
        hit = mime:description(kind)
        descriptions[kind] = hit
    end
    return hit
end

-- Numbers and dates are first wanted from the top: the largest, the latest.
function M.sort_by(key: string)
    if g.untracked(function() return config.get("sort") end) == key then
        config.set("descending", not g.untracked(function() return config.get("descending") end))
    else
        g.batch(function()
            config.set("sort", key)
            config.set("descending", key == "size" or key == "modified")
        end)
    end
end

local function title(key: string, label: string | () -> string, width: () -> number, justify: string, present: (() -> boolean)?): any
    local over = g.signal(false)
    local function current(): boolean return config.get("sort") == key end
    return g.box {
        id = "sort-" .. key,
        role = "button",
        name = "Sort by " .. key,
        present = present,
        width = width,
        height = HEAD,
        direction = "row",
        align = "center",
        justify = justify,
        gap = 4,
        on_hover = function(on: boolean) over.value = on end,
        on_press = function() end,
        on_click = function(button: number) if button == 272 then M.sort_by(key) end end,
        ui.label(label, function() return if current() or over.value then look.text() else look.text_faint() end),
        g.box {
            present = function() return current() and config.get("descending") end,
            ui.glyph("chevron-down", 14),
        },
        g.box {
            present = function() return current() and not config.get("descending") end,
            ui.glyph("chevron-up", 14),
        },
    }
end

-- The row under the pointer.
local over = g.signal(nil :: number?)

local function row(width: () -> number): (() -> number, any) -> any
    return function(item: () -> number, _: any): any
        local e = g.computed(function(): any return browser.dir:at(item()) end)
        local function chosen(): boolean
            local it = e.value
            return it ~= nil and selection.has(it.path)
        end
        local function stood(): boolean
            local it = e.value
            return it ~= nil and browser.cursor.value == it.path
        end
        local function edge(): string
            if entry_ui.welcoming(e.value) then return look.primary() end
            return if stood() and not chosen() then look.node() else look.CLEAR
        end
        local function name_w(): number
            local it = e.value
            local room = name_room(width())
            if it == nil or it.within == nil then return room end
            return math.max(60, math.floor(room * 0.62))
        end
        local function figure(text: () -> string, w: number, align: string, present: () -> boolean): any
            return g.box {
                present = present,
                width = w,
                direction = "row",
                justify = align,
                g.text {
                    text = text,
                    color = look.text_muted,
                    font = look.technical,
                    size = look.font_meta,
                    weight = 400,
                    tabular = true,
                },
            }
        end
        -- The picture and the name are the entry, dragged from there; the
        -- rest of the row answers a click, and is where a rubber band starts.
        return g.capsule {
            width = width,
            height = ROW,
            padding_x = PAD,
            direction = "row",
            align = "center",
            justify = "start",
            gap = GAP,
            radius = look.radius_well,
            fill = function()
                if chosen() or entry_ui.welcoming(e.value) then return look.chosen() end
                return if over.value == item() then look.hovered() else look.CLEAR
            end,
            rim_top = edge,
            rim_bottom = edge,
            g.box {
                width = function() return name_room(width()) + 38 end,
                direction = "row",
                align = "center",
                justify = "start",
                g.box(entry_ui.handlers({
                    role = "button",
                    height = ROW,
                    direction = "row",
                    align = "center",
                    gap = 10,
                    opacity = function() return entry_ui.faded(e.value) end,
                    entry_ui.picture(function() return e.value end, 28, false),
                    g.text {
                        text = function() return if e.value then e.value.name else "" end,
                        max_width = name_w,
                        ellipsize = "middle",
                        color = look.text,
                        font = look.expressive,
                        size = look.font_name,
                        weight = look.weight_name,
                        opacity = function()
                            local it = e.value
                            local r = operations.renaming.value
                            return if it and r and r.path == it.path then 0 else 1
                        end,
                    },
                    -- Found below, the way to it.
                    g.text {
                        present = function() return e.value ~= nil and e.value.within ~= nil end,
                        text = function() return if e.value and e.value.within then e.value.within else "" end,
                        max_width = function() return math.max(40, name_room(width()) - name_w() - 10) end,
                        ellipsize = "start",
                        color = look.text_faint,
                        font = look.expressive,
                        size = look.font_secondary,
                    },
                }, function() return e.value end)),
            },
            figure(function()
                local it = e.value
                return if it and not it.dir then format.size(it.size) else ""
            end, SIZE_W, "end", function() return (wide(width())) end),
            figure(function()
                local it = e.value
                return if it then format.moment(it.modified) else ""
            end, MODIFIED_W, "start", function()
                local _, modified = wide(width())
                return modified
            end),
            g.text {
                present = function()
                    local _, _, kind = wide(width())
                    return kind
                end,
                text = function() return if e.value then described(e.value.mime) else "" end,
                max_width = TYPE_W,
                ellipsize = "end",
                color = look.text_muted,
                font = look.expressive,
                size = look.font_text,
            },
        }
    end
end

local scrolled = g.signal(0)

function M.new(width: () -> number, height: () -> number): any
    local function tall(): number return math.max(ROW, height() - HEAD) end
    local scroller = scroll_mark.new { height = tall, x = function() return width() - 1 end }
    local function at(y: number): any
        return if y >= 0 then browser.dir:at(math.floor(y / ROW) + 1) else nil
    end
    return g.box {
        direction = "column",
        align = "stretch",
        width = width,
        g.box {
            width = width,
            height = HEAD,
            padding_x = PAD,
            direction = "row",
            align = "center",
            gap = GAP,
            title("name", "Name", function() return name_room(width()) + 38 end, "start"),
            title("size", "Size", function() return SIZE_W end, "end", function() return (wide(width())) end),
            title("modified", function() return if browser.in_trash() then "Thrown away" else "Modified" end, function() return MODIFIED_W end, "start", function()
                local _, modified = wide(width())
                return modified
            end),
            title("type", "Type", function() return TYPE_W end, "start", function()
                local _, _, kind = wide(width())
                return kind
            end),
        },
        band.new({
            scroll = function() return scrolled.value end,
            width = width,
            height = tall,
            mark = scroller.mark,
            row_at = function(y: number): number return math.floor(y / ROW) + 1 end,
            rows = function() return browser.dir.count end,
            hits = function(_: number, y0: number, _: number, y1: number): { string }
                return g.untracked(function(): { string }
                    local first, last = math.max(1, math.floor(y0 / ROW) + 1), math.floor(y1 / ROW) + 1
                    return if first > browser.dir.count then {} else browser.dir:paths(first, last)
                end)
            end,
            pressed = entry_ui.touched,
            over = function(y: number?)
                over.value = if y and y >= 0 and y < ROW * browser.dir.count then math.floor(y / ROW) + 1 else nil
            end,
            ground = function(y: number, count: number): boolean
                local e = g.untracked(function() return at(y) end)
                if e == nil then return false end
                entry_ui.clicked(e, count)
                return true
            end,
            menu = function(y: number): boolean
                local e = g.untracked(function() return at(y) end)
                if e == nil then return false end
                entry_ui.menu(e)
                return true
            end,
            held = function(y: number)
                local e = g.untracked(function() return at(y) end)
                if e then entry_ui.held(e) end
            end,
        }, g.list {
            id = "entries",
            width = width,
            height = tall,
            clip = true,
            fade_bottom = scroller.fade,
            row_height = ROW,
            on_scroll = function(offset: number, room: number)
                scrolled.value = offset
                scroller.follow(offset, room)
            end,
            count = function() return browser.dir.count end,
            item = function(i: number) return i end,
            key = function(i: number) return i end,
            reveal = function()
                return band.row.value or browser.index.value
            end,
            reveal_margin = scroll_mark.margin,
            row = row(width),
        }),
    }
end

-- Where an entry is drawn, from the view's corner.
function M.rect(index: number, width: number): { x: number, y: number, w: number, h: number }
    return { x = 0, y = HEAD + (index - 1) * ROW - scrolled.value, w = width, h = ROW }
end

-- Where an entry's name is, and how wide.
function M.name_rect(index: number, width: number): any
    local e = browser.dir:at(index)
    if e == nil then return nil end
    local r = M.rect(index, width)
    local w = g.text_width { text = e.name, font = look.expressive(), size = look.font_name, weight = look.weight_name }
    return { x = r.x + PAD + 38, y = r.y, w = math.min(math.ceil(w), name_room(width)), h = ROW, centred = false }
end

M.row_height = ROW
M.head = HEAD

return M
