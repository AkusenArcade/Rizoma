--!strict
-- An entry's picture: its thumbnail where it can have one, the icon
-- theme's drawing of what it is otherwise.
local g = require("@genoma")
local thumbnails = require("@genoma/thumbnails")
local browser = require("core/browser")
local exchange = require("core/exchange")
local icons = require("core/icons")
local selection = require("core/selection")
local look = require("ui/look")
local ui = require("ui/controls")

local M = {}

-- `entry()` may be nil while its row goes.
function M.picture(entry: () -> any, size: number, pictured: boolean): any
    local thumb = g.computed(function(): string?
        local e = entry()
        if not pictured or e == nil or e.dir or e.broken or not thumbnails:can(e.mime) then return nil end
        return thumbnails:of(e.path, {
            size = if size > 128 then "x-large" elseif size > 64 then "large" else "normal",
            modified = e.modified,
            mime = e.mime,
        })
    end)
    return g.box {
        width = size,
        height = size,
        align = "center",
        justify = "center",
        g.icon {
            present = function() return thumb.value == nil end,
            width = size,
            height = size,
            icon = function()
                local e = entry()
                return if e then icons.of(e, size) else ""
            end,
        },
        g.image {
            present = function() return thumb.value ~= nil end,
            width = size,
            height = size,
            radius = math.min(8, size / 6),
            fit = "contain",
            src = function() return thumb.value or "" end,
        },
        -- A link says so at its corner.
        g.capsule {
            present = function()
                local e = entry()
                return e ~= nil and e.link
            end,
            overlay = true,
            right = 0,
            bottom = 0,
            width = math.max(12, size / 4),
            height = math.max(12, size / 4),
            radius = math.max(12, size / 4) / 2,
            align = "center",
            justify = "center",
            fill = look.cell,
            rim_top = look.rim,
            rim_bottom = look.line,
            ui.glyph("link", math.max(9, size / 6), function() return false end, look.text),
        },
    }
end

function M.faded(e: any): number
    if e == nil then return 0 end
    return if e.broken then 0.4 elseif e.hidden then 0.6 else 1
end

-- Where the last press was, for what it would drag.
local pressed = g.signal("")
M.pressed = pressed
-- A finger held on an entry starts choosing several: a tap is then one more
-- or one less, until none is left.
local tapping = g.signal(false)
g.watch(function() return selection.count() end, function(n: number) if n == 0 then tapping.value = false end end)
local touching = false

-- Whether a finger made the press under way.
function M.touched(touch: boolean) touching = touch end

-- A click on an entry, which of several in a row it is.
function M.clicked(e: any, count: number)
    local m = g.untracked(g.modifiers)
    browser.cursor.value = e.path
    if touching and g.untracked(function() return tapping.value end) then
        selection.toggle(e.path)
    elseif m.shift then
        selection.range(e.path, m.ctrl)
    elseif m.ctrl then
        selection.toggle(e.path)
    else
        selection.only(e.path)
        if count == 2 then browser.open(e) end
    end
end

-- A finger held on one.
function M.held(e: any)
    tapping.value = true
    browser.cursor.value = e.path
    selection.toggle(e.path)
end

-- What presses do to an entry, the same in both views: props for its node.
function M.handlers(node: { [any]: any }, entry: () -> any): { [any]: any }
    node.on_press = function(button: number, _: number, _: number, touch: boolean)
        local e = g.untracked(entry)
        if e == nil then return end
        touching = touch
        if button == 272 and not touch then
            local m = g.untracked(g.modifiers)
            -- Chosen as it is pressed, so it can be dragged at once; one of
            -- several already chosen is dragged with them.
            if not (m.ctrl or m.shift) and not g.untracked(function() return selection.has(e.path) end) then
                browser.cursor.value = e.path
                selection.only(e.path)
            end
        end
        pressed.value = e.path
    end
    node.on_click = function(button: number, _: number, _: number, count: number)
        local e = g.untracked(entry)
        if e == nil then return end
        if button == 275 then browser.back() return end
        if button == 276 then browser.forward() return end
        if button == 272 then M.clicked(e, count) end
    end
    node.on_long_press = function(_: number, _: number, touch: boolean): boolean
        local e = g.untracked(entry)
        if not touch or e == nil then return false end
        M.held(e)
        return true
    end
    node.drag_files = function(): string
        local e = entry()
        if e == nil or pressed.value ~= e.path then return "" end
        return exchange.dragged(if selection.has(e.path) then selection.list() else { e.path })
    end
    return node
end

return M
