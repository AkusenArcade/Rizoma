--!strict
-- What is selected: entries by their paths, so it keeps them through another
-- order, and loses those that are no longer shown — what is done to a
-- selection is never done to something unseen.
local g = require("@genoma")
local browser = require("core/browser")
local path_of = require("core/paths")

local M = {}

type Set = { paths: { [string]: boolean }, count: number }

local EMPTY: Set = { paths = {}, count = 0 }
local selected = g.signal(EMPTY)
-- Where a range starts: the last entry chosen by itself.
local anchor: string? = nil

local function untracked<T>(f: () -> T): T return g.untracked(f) end
local function now(): Set return untracked(function(): Set return selected.value end) end

function M.has(path: string): boolean return selected.value.paths[path] == true end
function M.count(): number return selected.value.count end

local function put(paths: { [string]: boolean })
    local n = 0
    for _ in paths do n += 1 end
    selected.value = if n == 0 then EMPTY else { paths = paths, count = n }
end

function M.clear()
    anchor = nil
    if now().count > 0 then selected.value = EMPTY end
end

function M.only(path: string)
    anchor = path
    local s = now()
    if s.count == 1 and s.paths[path] then return end
    selected.value = { paths = { [path] = true }, count = 1 }
end

function M.toggle(path: string)
    anchor = path
    local paths = table.clone(now().paths)
    paths[path] = if paths[path] then nil else true
    put(paths)
end

-- From the anchor to an entry; `add` keeps what was selected besides.
function M.range(path: string, add: boolean?)
    local from = if anchor then untracked(function() return browser.dir:index(anchor :: string) end) else nil
    local to = untracked(function() return browser.dir:index(path) end)
    if to == nil then return end
    if from == nil then
        M.only(path)
        return
    end
    local paths = if add then table.clone(now().paths) else {}
    for _, p in untracked(function() return browser.dir:paths(math.min(from, to), math.max(from, to)) end) do
        paths[p] = true
    end
    put(paths)
end

-- Exactly these, and `base` besides: what a rubber band does as it moves.
function M.these(list: { string }, base: { [string]: boolean }?)
    local paths = if base then table.clone(base) else {}
    for _, p in list do paths[p] = true end
    if anchor == nil then anchor = list[1] end
    put(paths)
end

function M.all()
    M.these(untracked(function() return browser.dir:paths() end))
end

function M.invert()
    local before, paths = now().paths, {}
    for _, p in untracked(function() return browser.dir:paths() end) do
        if not before[p] then paths[p] = true end
    end
    put(paths)
end

-- The paths selected, and as they are now, for adding to.
function M.held(): { [string]: boolean } return now().paths end

-- The selected, in the order they are shown.
local function in_order(): { string }
    local s = selected.value
    if s.count == 0 then return {} end
    local out: { string } = {}
    for _, p in browser.dir:paths() do
        if s.paths[p] then table.insert(out, p) end
    end
    return out
end
function M.list(): { string } return untracked(in_order) end

-- Their entries, as many as `most`.
function M.entries(most: number): { any }
    local out = {}
    for _, p in in_order() do
        if #out >= most then break end
        local i = browser.dir:index(p)
        local e = if i then browser.dir:at(i) else nil
        if e then table.insert(out, e) end
    end
    return out
end

-- What they come to: how many folders, how many files and their bytes.
export type Sum = { folders: number, files: number, bytes: number? }
-- Past this many entries they are not looked at one by one.
local SUMMED = 4000
M.sum = g.computed(function(): Sum
    local s = selected.value
    local out = { folders = 0, files = 0, bytes = 0 } :: any
    if s.count < 2 then return out end
    if browser.dir.count > SUMMED then
        out.files, out.bytes = s.count, nil
        return out
    end
    for i = 1, browser.dir.count do
        local e = browser.dir:at(i)
        if e and s.paths[e.path] then
            if e.dir then
                out.folders += 1
            else
                out.files += 1
                out.bytes += e.size
            end
        end
    end
    return out
end)

browser.chosen = function(path: string?, how: string)
    if path == nil then
        M.clear()
    elseif how == "extend" then
        M.range(path)
    elseif how == "only" then
        M.only(path)
    end
end

-- What is gone, or filtered out, is no longer selected.
g.effect(function()
    local _ = browser.dir.count, browser.dir.path
    g.untracked(function()
        local s = selected.value
        if s.count == 0 or browser.dir.loading then return end
        -- Chosen in a folder not shown yet: it is on its way.
        local one = next(s.paths)
        if one and browser.dir.path ~= path_of.TRASH and not path_of.inside(one, browser.dir.path) then return end
        local shown: { [string]: boolean } = {}
        for _, p in browser.dir:paths() do
            if s.paths[p] then shown[p] = true end
        end
        local kept = 0
        for _ in shown do kept += 1 end
        if kept ~= s.count then
            selected.value = if kept == 0 then EMPTY else { paths = shown, count = kept }
        end
    end)
end)

return M
