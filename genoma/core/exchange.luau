--!strict
-- Files given to other programs and taken from them, by the clipboard and by
-- dragging; and what is dragged over a folder of ours.
local g = require("@genoma")
local clipboard = require("@genoma/clipboard")
local files = require("@genoma/files")
local browser = require("core/browser")
local paths = require("core/paths")
local selection = require("core/selection")

local M = {}

local GNOME, URIS, KDE = "x-special/gnome-copied-files", "text/uri-list", "application/x-kde-cutselection"

local function uris(list: { string }): { string }
    local out = table.create(#list)
    for _, p in list do table.insert(out, g.file_uri(p)) end
    return out
end

-- ---- The clipboard --------------------------------------------------------------------

-- What was cut here and is still to be pasted.
local cut = g.signal({} :: { [string]: boolean })
function M.is_cut(path: string): boolean return cut.value[path] == true end
local ours: string? = nil

local function offer(list: { string }, verb: "copy" | "cut")
    local all = uris(list)
    local plain = table.concat(list, "\n")
    local marked = verb .. "\n" .. table.concat(all, "\n")
    local types: { [string]: string } = {
        [URIS] = table.concat(all, "\r\n") .. "\r\n",
        [GNOME] = marked,
    }
    if verb == "cut" then types[KDE] = "1" end
    -- As text, the paths: what a terminal is pasted. A name that is not
    -- UTF-8 has none.
    if utf8.len(plain) then
        types["text/plain;charset=utf-8"] = plain
        types["text/plain"] = plain
        types["UTF8_STRING"] = plain
    end
    clipboard:offer(types)
    local set: { [string]: boolean } = {}
    if verb == "cut" then
        for _, p in list do set[p] = true end
    end
    ours = marked
    cut.value = set
end

function M.copy(list: { string }?)
    local chosen = list or selection.list()
    if #chosen == 0 then return end
    offer(chosen, "copy")
    browser.say { text = if #chosen == 1 then "Copied" else `{#chosen} items copied` }
end

function M.cut(list: { string }?)
    local chosen = list or selection.list()
    if #chosen == 0 then return end
    offer(chosen, "cut")
    browser.say { text = if #chosen == 1 then "Cut" else `{#chosen} items cut` }
end

-- A path, as text.
function M.copy_path(list: { string })
    local plain = table.concat(list, "\n")
    if not utf8.len(plain) then return end
    clipboard:set_text(plain)
    browser.say { text = if #list == 1 then "Path copied" else "Paths copied" }
end

local function forget()
    ours = nil
    if next(g.untracked(function() return cut.value end)) ~= nil then cut.value = {} end
end

-- Copied over by anyone, what was cut is no longer about to go.
g.watch(function() return clipboard.changed end, function()
    if ours == nil or next(g.untracked(function() return cut.value end)) == nil then return end
    clipboard:read(GNOME, function(data: string?)
        if data ~= ours then forget() end
    end)
end)

-- Whether there is anything to paste.
function M.holds(): boolean
    for _, t in clipboard.types do
        if t == GNOME or t == URIS then return true end
    end
    return false
end

local function offered(kind: string): boolean
    return table.find(g.untracked(function() return clipboard.types end), kind) ~= nil
end

local function local_paths(lines: string): { string }
    local out: { string } = {}
    for line in string.gmatch(lines, "[^\r\n]+") do
        if string.sub(line, 1, 1) ~= "#" then
            local path = g.uri_path(line)
            if path then table.insert(out, paths.expand(path)) end
        end
    end
    return out
end

export type Verb = "copy" | "move"

-- What was copied or cut, here or in any file manager.
function M.held(on_held: (list: { string }, verb: Verb) -> ())
    if offered(GNOME) then
        clipboard:read(GNOME, function(data: string?)
            local head, rest = string.match(data or "", "^(%a+)\r?\n(.*)$")
            on_held(local_paths(rest or ""), if head == "cut" then "move" else "copy")
        end)
    elseif offered(URIS) then
        local function listed(verb: Verb)
            clipboard:read(URIS, function(data: string?) on_held(local_paths(data or ""), verb) end)
        end
        if offered(KDE) then
            clipboard:read(KDE, function(data: string?) listed(if string.sub(data or "", 1, 1) == "1" then "move" else "copy") end)
        else
            listed("copy")
        end
    else
        on_held({}, "copy")
    end
end

-- Cut and pasted: it is there no more to be pasted again.
function M.spent()
    if offered(GNOME) then
        local was = ours
        clipboard:read(GNOME, function(data: string?)
            if data ~= nil and (was == nil or data == was) and string.sub(data, 1, 3) == "cut" then clipboard:clear() end
        end)
    end
    forget()
end

-- ---- Dragging -------------------------------------------------------------------------

-- What an entry's `drag_files` is: one a line, as a URI where a line or a
-- string could not hold the path.
function M.dragged(list: { string }): string
    local out = table.create(#list)
    for _, p in list do
        table.insert(out, if utf8.len(p) and not string.find(p, "[\r\n]") then p else g.file_uri(p))
    end
    return table.concat(out, "\n")
end

-- What a drag begun here carries; set by ui/entry.
M.carried = function(): { string } return {} end

-- The folder a drag is over, whether it was begun here, and whether what it
-- carries is on that folder's disk (nil: not known yet).
export type Over = { folder: string, own: boolean, same: boolean? }
local over = g.signal(nil :: Over?)
M.over = over

-- Moved on one disk, copied to another; Ctrl copies, Shift moves. From
-- another program it is copied, unless Shift says otherwise.
local function verb_of(o: Over): Verb
    local m = g.modifiers()
    if m.ctrl then return "copy" end
    if m.shift then return "move" end
    return if o.own and o.same ~= false then "move" else "copy"
end

-- What letting go now would do, in words, or nil.
function M.would(): string?
    local o = over.value
    if o == nil or not o.own or not M.takes(o.folder, g.untracked(M.carried)) then return nil end
    return (if verb_of(o) == "move" then "Move to " else "Copy to ") .. paths.called(o.folder)
end

-- Whether a folder can be given these: not itself, and not one of them.
function M.takes(folder: string, list: { string }): boolean
    for _, p in list do
        if paths.inside(folder, p) then return false end
    end
    return true
end

-- Set by core/operations: what is dropped is put there.
M.dropped = function(_: { string }, _: string, _: Verb) end

local OPEN_AFTER = 0.8

-- A node that takes what is dragged: props for it. `folder()` is where it
-- would go, nil for nowhere; `opens`: held over, it is gone into.
function M.target(node: { [any]: any }, folder: () -> string?, opens: boolean?): { [any]: any }
    local waiting: any = nil
    local function stop()
        if waiting then waiting:stop() end
        waiting = nil
    end
    node.on_drop_hover = function(on: boolean, own: boolean)
        local f = g.untracked(folder)
        stop()
        local now = g.untracked(function() return over.value end)
        if not on then
            if now and now.folder == f then over.value = nil end
            return
        end
        if f == nil then
            over.value = nil
            return
        end
        over.value = { folder = f, own = own, same = nil }
        local list = M.carried()
        if own and #list > 0 then
            files:same_disk(list, f, function(same: boolean)
                local o = g.untracked(function() return over.value end)
                if o and o.folder == f then over.value = { folder = f, own = o.own, same = same } end
            end)
        end
        if opens and not (own and not M.takes(f, list)) then
            waiting = g.after(OPEN_AFTER, function()
                waiting = nil
                if f ~= g.untracked(function() return browser.here.value end) then browser.go(f) end
            end)
        end
    end
    node.drop_action = function(): string
        local o = over.value
        return if o and o.folder == folder() then verb_of(o) elseif g.modifiers().shift then "move" else "copy"
    end
    node.on_drop = function(drop: any)
        stop()
        local f = g.untracked(folder)
        local o = g.untracked(function() return over.value end)
        over.value = nil
        local list: { string } = {}
        for _, p in drop.files do table.insert(list, paths.expand(p)) end
        if f == nil or #list == 0 then return end
        if not drop.own then
            M.dropped(list, f, drop.action)
            return
        end
        if o == nil or o.folder ~= f then o = { folder = f, own = true, same = nil } end
        local m = g.untracked(g.modifiers)
        if m.ctrl or m.shift or (o :: Over).same ~= nil then
            M.dropped(list, f, g.untracked(function() return verb_of(o :: Over) end))
        else
            -- Let go before it was known.
            files:same_disk(list, f, function(same: boolean) M.dropped(list, f, if same then "move" else "copy") end)
        end
    end
    g.cleanup(function()
        stop()
        local f = g.untracked(folder)
        local o = g.untracked(function() return over.value end)
        if o and o.folder == f then over.value = nil end
    end)
    return node
end

-- Whether a drag that this folder would take is over it.
function M.welcome(folder: string): boolean
    local o = over.value
    return o ~= nil and o.folder == folder and not (o.own and not M.takes(folder, g.untracked(M.carried)))
end

return M
