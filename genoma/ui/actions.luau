--!strict
-- What the right button offers, by what it is pressed on.
local g = require("@genoma")
local mime = require("@genoma/mime")
local browser = require("core/browser")
local bin = require("core/bin")
local colours = require("core/colours")
local exchange = require("core/exchange")
local operations = require("core/operations")
local panes = require("core/panes")
local paths = require("core/paths")
local selection = require("core/selection")
local menu = require("ui/menu")

local M = {}

-- Set by the shell: what opens the field of the new folder's name.
M.new_folder = function() end

local function here(): string return g.untracked(function() return browser.here.value end) end
local function holds(): boolean return g.untracked(exchange.holds) end

-- Where the press was: the menu grows from there.
local function open(items: { menu.Item | string })
    local x, y = g.pressed_at()
    menu.open(items, x, y)
end
-- Asked for by key, it opens where the entry is.
M.at = nil :: ((items: { menu.Item | string }) -> ())?
local function show(items: { menu.Item | string }, by_key: boolean?)
    if by_key and M.at then M.at(items) else open(items) end
end

local APPS = 8

local function with(e: any): { menu.Item }
    local out: { menu.Item } = {}
    for i, app in mime:apps(e.mime) do
        if i > APPS then break end
        table.insert(out, { text = app.name, icon = app.icon, act = function() browser.open_with(app, { e.path }) end })
    end
    return out
end

-- The colour they all have, or nil.
local function common(list: { string }): string?
    local out: string? = nil
    for k, e in g.untracked(function() return selection.entries(200) end) do
        local c = colours.of(e)
        if k > 1 and c ~= out then return nil end
        out = c
    end
    return if #list > 0 then out else nil
end

local function thrown(e: any, list: { string }): { menu.Item | string }
    return {
        { text = if #list == 1 then "Put back" else `Put {#list} back`, keys = "Enter", act = function() operations.restore(list) end },
        "-",
        { text = "Delete for good", keys = "⇧ Del", act = function() operations.delete(list) end },
    }
end

-- On an entry: what is done is done to all that are selected.
function M.on_entry(e: any, by_key: boolean?)
    local list = selection.list()
    if #list == 0 then list = { e.path } end
    if e.deleted then
        show(thrown(e, list), by_key)
        return
    end
    local items: { menu.Item | string } = {}
    local function add(it: menu.Item | string) table.insert(items, it) end
    if #list > 1 then
        add { text = `Open {#list}`, keys = "Enter", act = function() browser.open_all(selection.entries(1000)) end }
    else
        add { text = "Open", keys = "Enter", off = e.broken, act = function() browser.open(e) end }
        if not e.dir and not e.broken then
            local apps = with(e)
            if #apps > 0 then add { text = "Open with", more = apps } end
        end
        if e.within then
            add { text = "Show in its folder", act = function() browser.go(paths.parent(e.path) or "/", e.path) end }
        end
    end
    if #list == 1 and e.dir and not e.broken then
        add { text = "Open in a new tab", act = function() panes.new_tab(e.path) end }
        add {
            text = if g.untracked(panes.two) then "Open in the other pane" else "Open beside",
            act = function()
                local other = g.untracked(panes.other)
                if other then other.go(e.path) else panes.split(e.path) end
            end,
        }
    end
    local folder = if #list == 1 and e.dir then e.path else (paths.parent(e.path) or here())
    add { text = "Open in the terminal", keys = "F4", act = function() browser.terminal(folder) end }
    add "-"
    add { text = "Cut", keys = "Ctrl X", act = function() exchange.cut(list) end }
    add { text = "Copy", keys = "Ctrl C", act = function() exchange.copy(list) end }
    if g.untracked(panes.two) then
        add { text = "Move to the other pane", keys = "F6", act = function() operations.across("move") end }
        add { text = "Copy to the other pane", keys = "⇧ F6", act = function() operations.across("copy") end }
    end
    if #list == 1 and e.dir then
        add { text = "Paste into it", off = not holds(), act = function() operations.paste(e.path) end }
    end
    add { text = if #list == 1 then "Copy its path" else "Copy their paths", act = function() exchange.copy_path(list) end }
    if #list == 1 then
        add "-"
        add { text = "Rename", keys = "F2", act = function() operations.rename(e) end }
    end
    add "-"
    add { text = "Colour", colours = { chosen = common(list), pick = function(key: string?) operations.colour(list, key) end } }
    add "-"
    add { text = "Move to the trash", keys = "Del", act = function() operations.throw(list) end }
    show(items, by_key)
end

-- On the folder's own ground.
function M.on_ground(by_key: boolean?)
    local at = here()
    if at == paths.TRASH then
        show({
            { text = "Select all", keys = "Ctrl A", act = selection.all },
            "-",
            { text = "Empty the trash", off = g.untracked(bin.count) == 0, act = operations.empty },
        }, by_key)
        return
    end
    show({
        { text = "New folder", keys = "Ctrl ⇧ N", act = function() M.new_folder() end },
        { text = "Paste", keys = "Ctrl V", off = not holds(), act = function() operations.paste() end },
        "-",
        { text = "Select all", keys = "Ctrl A", act = selection.all },
        { text = "Read again", keys = "F5", act = function() browser.dir:reload() end },
        "-",
        { text = "Open in the terminal", keys = "F4", act = function() browser.terminal(at) end },
        { text = "Copy its path", act = function() exchange.copy_path { at } end },
    }, by_key)
end

-- On a place, or a step of the path.
function M.on_place(path: string, go: () -> ())
    if path == paths.TRASH then
        show {
            { text = "Open", act = go },
            { text = "Open in a new tab", act = function() panes.new_tab(path) end },
            { text = "Empty the trash", off = g.untracked(bin.count) == 0, act = operations.empty },
        }
        return
    end
    show {
        { text = "Open", act = go },
        { text = "Open in a new tab", act = function() panes.new_tab(path) end },
        { text = "Open in the terminal", act = function() browser.terminal(path) end },
        "-",
        { text = "Paste into it", off = not holds(), act = function() operations.paste(path) end },
        { text = "Copy its path", act = function() exchange.copy_path { path } end },
    }
end

return M
