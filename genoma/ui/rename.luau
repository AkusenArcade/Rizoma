--!strict
-- A name being written where it is: a field that grows from the name.
local g = require("@genoma")
local operations = require("core/operations")
local look = require("ui/look")

local M = {}

local H, PAD, MIN, MAX = 36, 14, 180, 460

-- `t`: at() where the entry's name is, { x, y, w, h, centred } in the window, nil
-- out of view; area() the window's { w, h }; left() where the folder starts.
function M.new(t: { [string]: any }): any
    local there, grown = g.signal(false), g.signal(false)
    local started = g.signal({ w = 60 })
    local going: any = nil
    g.watch(function() return operations.renaming.value ~= nil end, function(on: boolean)
        if going then going:stop() end
        going = nil
        if on then
            local at = g.untracked(t.at)
            started.value = { w = if at then at.w else 60 }
            there.value = true
            g.after(0, function() grown.value = g.untracked(function() return operations.renaming.value ~= nil end) end)
        else
            grown.value = false
            going = g.after(look.CLOSE, function()
                going = nil
                there.value = false
            end)
        end
    end)
    local last = { x = 0, y = 0, w = 60, h = H, centred = false }
    local function at(): any
        local now = t.at()
        if now then last = now end
        return last
    end
    local function wanted(): number
        local w = g.text_width { text = operations.typed.value, font = look.expressive(), size = look.font_name, weight = look.weight_name }
        return math.clamp(math.ceil(w) + PAD * 2 + 12, MIN, math.min(MAX, t.area().w - t.left() - look.margin_edge))
    end
    local function width(): number return if grown.value then wanted() else math.min(wanted(), started.value.w + PAD) end
    local function wrong(): boolean return operations.wrong() ~= nil end
    local function timing(): string return if grown.value then "cell_open" else "cell_close" end
    return g.capsule {
        id = "rename",
        overlay = true,
        attach = "corner",
        present = function() return there.value end,
        offset_x = function()
            local a = at()
            local w = width()
            local x = if a.centred then a.x + (a.w - w) / 2 else a.x - PAD
            return math.clamp(x, t.left(), math.max(t.left(), t.area().w - look.margin_edge - w))
        end,
        offset_y = function()
            local a = at()
            return if a.centred then a.y - 6 else a.y + (a.h - H) / 2
        end,
        width = width,
        height = H,
        radius = look.round(H / 2),
        padding_x = PAD,
        direction = "row",
        align = "center",
        clip = true,
        opacity = function() return if grown.value then 1 else 0 end,
        fill = look.cell,
        rim_top = function() return if wrong() then look.node() else look.primary() end,
        rim_bottom = function() return if wrong() then look.node() else look.primary() end,
        transition = { width = timing, opacity = timing, rim_top = "ui_change", rim_bottom = "ui_change" },
        on_press = function() end,
        on_click = function() end,
        g.field {
            id = "rename-field",
            grow = 1,
            size = look.font_name,
            font = look.expressive,
            weight = look.weight_name,
            color = look.text,
            caret_color = look.primary,
            selection_color = look.chosen,
            select = function()
                local r = operations.renaming.value
                return if r and r.dir then "all" else "stem"
            end,
            focused = function() return operations.renaming.value ~= nil end,
            text = function() return operations.typed.value end,
            on_change = function(text: string) operations.typed.value = text end,
            on_submit = operations.finish_renaming,
        },
    }
end

return M
