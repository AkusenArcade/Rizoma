--!strict
-- An entry's picture: its thumbnail where it can have one, the icon
-- theme's drawing of what it is otherwise.
local g = require("@genoma")
local thumbnails = require("@genoma/thumbnails")
local browser = require("core/browser")
local actions = require("ui/actions")
local colours = require("core/colours")
local exchange = require("core/exchange")
local operations = require("core/operations")
local icons = require("core/icons")
local panes = require("core/panes")
local selection = require("core/selection")
local look = require("ui/look")
local ui = require("ui/controls")

local M = {}

-- Where the last press was, for what it would drag: the entry, and its pane.
local pressed = g.signal("")
M.pressed = pressed
M.pressed_in = g.signal(nil :: any)
local function pressed_path(): string return g.untracked(function() return pressed.value end) end

-- The colour an entry is marked with, or nil.
function M.mark(e: any): string?
    local key = colours.of(e)
    return if key then colours.hex(key, look.is_dark()) else nil
end
-- What its name gives up to the capsule a colour puts it in.
M.MARKED = 18
function M.marked(e: any): number return if colours.of(e) then M.MARKED else 0 end

-- An entry's name, in a capsule of its colour when it is marked.
function M.name(entry: () -> any, text: any): any
    return g.capsule {
        padding_x = function() return M.marked(entry()) / 2 end,
        padding_y = 1,
        radius = 11,
        fill = function()
            local m = M.mark(entry())
            return if m then g.colour.alpha(m, 0.2) else look.CLEAR
        end,
        rim_top = function() return M.mark(entry()) or look.CLEAR end,
        rim_bottom = function()
            local m = M.mark(entry())
            return if m then g.colour.alpha(m, 0.5) else look.CLEAR
        end,
        -- Where its name is being written there is another shape.
        opacity = function()
            local it = entry()
            local r = operations.renaming.value
            return if it and r and r.path == it.path then 0 else 1
        end,
        transition = { fill = "ui_change", rim_top = "ui_change", rim_bottom = "ui_change" },
        text,
    }
end

-- `entry()` may be nil while its row goes.
function M.picture(entry: () -> any, size: number, pictured: boolean): any
    local thumb = g.computed(function(): string?
        local e = entry()
        if not pictured or e == nil or e.dir or e.broken or not thumbnails:can(e.mime) then return nil end
        return thumbnails:of(e.path, {
            size = if size > 128 then "x-large" elseif size > 64 then "large" else "normal",
            modified = if e.deleted then nil else e.modified,
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

-- Whether a drag that would go into it is over it.
function M.welcoming(pane: any, e: any): boolean
    return e ~= nil and e.dir and exchange.welcome(`entry:{pane.id}`, e.path)
end

function M.faded(e: any): number
    if e == nil then return 0 end
    -- Cut, it is on its way.
    if exchange.is_cut(e.path) then return 0.45 end
    return if e.broken then 0.4 elseif e.hidden then 0.6 else 1
end

-- What a drag from the entry last pressed carries.
exchange.carried = function(): { string }
    local path = pressed_path()
    local pane = g.untracked(function() return M.pressed_in.value end)
    if path == "" or pane == nil then return {} end
    return if g.untracked(function() return pane.selection.has(path) end) then pane.selection.list() else { path }
end

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
    if g.untracked(function() return selection.has(e.path) end) then actions.on_entry(e) end
end

-- The right button on one: it joins those chosen, or is chosen instead.
function M.menu(e: any)
    if not g.untracked(function() return selection.has(e.path) end) then
        browser.cursor.value = e.path
        selection.only(e.path)
    end
    actions.on_entry(e)
end

-- What presses do to an entry, the same in both views: props for its node.
function M.handlers(pane: any, node: { [any]: any }, entry: () -> any): { [any]: any }
    node.on_press = function(button: number, _: number, _: number, touch: boolean)
        panes.focus(pane)
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
        M.pressed_in.value = pane
        pressed.value = e.path
    end
    node.on_click = function(button: number, _: number, _: number, count: number)
        local e = g.untracked(entry)
        if e == nil then return end
        if button == 275 then browser.back() return end
        if button == 276 then browser.forward() return end
        if button == 274 then
            -- Beside this one, not instead of it.
            if e.dir and not e.deleted then panes.new_tab(e.path, true) end
            return
        end
        if button == 273 then M.menu(e) return end
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
        -- Out of the trash a thing goes by being put back.
        if e == nil or e.deleted or pressed.value ~= e.path or M.pressed_in.value ~= pane then return "" end
        return exchange.dragged(if pane.selection.has(e.path) then pane.selection.list() else { e.path })
    end
    node.drag_actions = "both"
    -- On a folder it goes into it, beside one where one is.
    return exchange.target(node, `entry:{pane.id}`, function(): string?
        local e = entry()
        if e == nil then return nil end
        return if e.dir and not e.broken and not e.deleted then e.path else pane.here.value
    end, pane.go)
end

return M
