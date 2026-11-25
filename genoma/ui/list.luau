--!strict
-- The folder as lines: name, size, when it changed, what it is. A column's
-- title sorts by it; pressed again, the other way round.
local g = require("@genoma")
local mime = require("@genoma/mime")
local browser = require("core/browser")
local config = require("core/config")
local format = require("core/format")
local look = require("ui/look")
local ui = require("ui/controls")
local entry_ui = require("ui/entry")

local M = {}

local ROW, PAD, GAP, HEAD = look.row_height + 2, 10, 14, 30
local SIZE_W, MODIFIED_W, TYPE_W = 84, 150, 170

local function wide(width: number): (boolean, boolean, boolean)
    return width >= 380, width >= 540, width >= 740
end
local function name_room(width: number): number
    local size, modified, kind = wide(width)
    local room = width - PAD * 2 - 24 - 10
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

local function title(key: string, label: string, width: () -> number, justify: string, present: (() -> boolean)?): any
    local over = g.signal(false)
    local function current(): boolean return config.get("sort") == key end
    return g.box {
        id = "sort-" .. key,
        role = "button",
        name = "Sort by " .. label,
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

local function row(width: () -> number): (() -> number, any) -> any
    return function(item: () -> number, _: any): any
        local over = g.signal(false)
        local e = g.computed(function(): any return browser.dir:at(item()) end)
        local function chosen(): boolean
            local it = e.value
            return it ~= nil and browser.cursor.value == it.path
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
        return g.capsule {
            role = "button",
            width = width,
            height = ROW,
            padding_x = PAD,
            direction = "row",
            align = "center",
            justify = "start",
            gap = GAP,
            radius = look.radius_well,
            fill = function()
                if chosen() then return look.chosen() end
                return if over.value then look.hovered() else look.CLEAR
            end,
            rim_top = look.CLEAR,
            rim_bottom = look.CLEAR,
            on_hover = function(on: boolean) over.value = on end,
            on_press = function() end,
            on_click = entry_ui.pressed(function() return e.value end),
            g.box {
                width = function() return name_room(width()) + 34 end,
                direction = "row",
                align = "center",
                gap = 10,
                opacity = function() return entry_ui.faded(e.value) end,
                entry_ui.picture(function() return e.value end, 24, false),
                g.text {
                    text = function() return if e.value then e.value.name else "" end,
                    max_width = function() return name_room(width()) end,
                    ellipsize = "middle",
                    color = look.text,
                    font = look.expressive,
                    size = look.font_secondary,
                },
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
                size = look.font_secondary,
            },
        }
    end
end

function M.new(width: () -> number, height: () -> number): any
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
            title("name", "Name", function() return name_room(width()) + 34 end, "start"),
            title("size", "Size", function() return SIZE_W end, "end", function() return (wide(width())) end),
            title("modified", "Modified", function() return MODIFIED_W end, "start", function()
                local _, modified = wide(width())
                return modified
            end),
            title("type", "Type", function() return TYPE_W end, "start", function()
                local _, _, kind = wide(width())
                return kind
            end),
        },
        g.list {
            id = "entries",
            width = width,
            height = function() return math.max(ROW, height() - HEAD) end,
            row_height = ROW,
            count = function() return browser.dir.count end,
            item = function(i: number) return i end,
            key = function(i: number) return i end,
            reveal = function() return browser.index.value end,
            row = row(width),
        },
    }
end

M.row_height = ROW
M.head = HEAD

return M
