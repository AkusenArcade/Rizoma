--!strict
-- The rubber band: pressed beside the entries and dragged, it selects what
-- it touches, and past an edge the view goes on. A mouse's: a finger there
-- scrolls.
local g = require("@genoma")
local browser = require("core/browser")
local selection = require("core/selection")
local look = require("ui/look")

local M = {}

-- The row to keep in view while the band is past an edge, or nil.
M.row = g.signal(nil :: number?)

local EDGE = 0.09

-- `t`: scroll() how far the view is scrolled, hits(x0, y0, x1, y1) the paths
-- in a rectangle of its content, row_at(y) the row there, rows() how many,
-- width() and height() the view's, mark its scroll mark; `inner` the list.
-- Where the ground is an entry's too (a list's rows): ground(y, count) is a
-- press on it at that height, held(y) a finger held there, over(y) the pointer
-- on it, nil once off. Coordinates are the list's.
function M.new(t: { [string]: any }, inner: any): any
    local box = g.signal(nil :: any)
    local from: any, at: any, base: any, edge: any = nil, nil, nil, nil
    local far = false

    local function update()
        local s = g.untracked(t.scroll)
        local x0, x1 = math.min(from.x, at.x), math.max(from.x, at.x)
        local y0, y1 = math.min(from.y, at.y + s), math.max(from.y, at.y + s)
        box.value = { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
        g.batch(function() selection.these(t.hits(x0, y0, x1, y1), base) end)
    end
    local function rest()
        if edge then edge:stop() end
        edge = nil
        M.row.value = nil
    end
    local function past_edge()
        local h = g.untracked(t.height)
        local s = g.untracked(t.scroll)
        local out = at.y < 0 or at.y > h
        if not out then
            rest()
        elseif edge == nil then
            edge = g.timer {
                every = EDGE,
                on_tick = function()
                    local top = g.untracked(t.scroll)
                    local row = if at.y < 0 then t.row_at(top) - 1 else t.row_at(top + h) + 1
                    M.row.value = math.clamp(row, 1, math.max(1, g.untracked(t.rows)))
                    update()
                end,
            }
        end
        local _ = s
    end

    -- Scrolled under a band that is held still, it reaches further.
    g.watch(t.scroll, function() if from and far then update() end end)

    return g.box {
        on_move = if t.over then function(_: number, y: number) t.over(y + g.untracked(t.scroll)) end else nil,
        on_hover = if t.over then function(on: boolean) if not on then t.over(nil) end end else nil,
        on_long_press = function(_: number, y: number, touch: boolean): boolean
            if not touch or t.held == nil then return false end
            t.held(y + g.untracked(t.scroll))
            return true
        end,
        on_press = function(button: number, x: number, y: number, touch: boolean)
            if t.pressed then t.pressed(touch) end
            if button ~= 272 or touch then return end
            local m = g.untracked(g.modifiers)
            from = { x = x, y = y + g.untracked(t.scroll) }
            at = { x = x, y = y }
            far = false
            base = if m.ctrl or m.shift then table.clone(selection.held()) else nil
        end,
        on_drag = function(x: number, y: number)
            if from == nil then return end
            at = { x = x, y = y }
            if not far then
                local s = g.untracked(t.scroll)
                if math.abs(x - from.x) + math.abs(y + s - from.y) < 5 then return end
                far = true
                browser.cursor.value = nil
            end
            update()
            past_edge()
        end,
        on_release = function()
            if from == nil then return end
            local banded = far
            from, base = nil, nil
            box.value = nil
            rest()
            -- The click that follows is the band's own end.
            if banded then g.after(0, function() far = false end) end
        end,
        on_click = function(button: number, _: number, y: number, count: number)
            if button == 275 then browser.back() return end
            if button == 276 then browser.forward() return end
            if button ~= 272 or far then return end
            if t.ground and t.ground(y + g.untracked(t.scroll), count) then return end
            local m = g.untracked(g.modifiers)
            if m.ctrl or m.shift then return end
            browser.leave()
        end,
        inner,
        t.mark,
        g.capsule {
            present = function() return box.value ~= nil end,
            overlay = true,
            attach = "corner",
            offset_x = function() return if box.value then math.max(0, box.value.x) else 0 end,
            offset_y = function() return if box.value then math.max(0, box.value.y - t.scroll()) else 0 end,
            width = function()
                local b = box.value
                return if b then math.max(1, math.min(b.x + b.w, t.width()) - math.max(0, b.x)) else 0
            end,
            height = function()
                local b = box.value
                if b == nil then return 0 end
                local top = b.y - t.scroll()
                return math.max(1, math.min(top + b.h, t.height()) - math.max(0, top))
            end,
            radius = 8,
            fill = function() return g.colour.alpha(look.primary(), 0.12) end,
            rim_top = look.primary,
            rim_bottom = look.primary,
        },
    }
end

return M
