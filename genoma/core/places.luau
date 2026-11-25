--!strict
-- Where one starts from: the user's own folders, the bookmarks every GTK
-- program shares, the computer.
local g = require("@genoma")
local paths = require("core/paths")

local M = {}

export type Place = { name: string, path: string, glyph: string, group: "own" | "bookmark" | "computer" }

local config_home = g.env("XDG_CONFIG_HOME") or (paths.home .. "/.config")
local own_file = g.file { path = config_home .. "/user-dirs.dirs" }
local bookmark_file = g.file { path = config_home .. "/gtk-3.0/bookmarks" }

local OWN = {
    { key = "DESKTOP", glyph = "desktop" },
    { key = "DOCUMENTS", glyph = "documents" },
    { key = "DOWNLOAD", glyph = "download" },
    { key = "MUSIC", glyph = "music" },
    { key = "PICTURES", glyph = "pictures" },
    { key = "VIDEOS", glyph = "videos" },
}

local parents: { [string]: any } = {}

-- Whether a folder is there, followed through the folder around it. Asked
-- of the user's own folders only: a bookmark may be on a NAS that answers
-- when it likes, and is shown whether or not it answers.
local function exists(path: string): boolean
    local parent = paths.parent(path)
    if parent == nil then return true end
    local f = parents[parent]
    if f == nil then
        f = g.lasting(function() return g.folder { path = parent, hidden = true } end)
        parents[parent] = f
    end
    for _, e in f.entries do
        if e.path == path then return true end
    end
    return false
end

M.list = g.computed(function(): { Place }
    local out: { Place } = { { name = "Home", path = paths.home, glyph = "home", group = "own" } }
    local seen: { [string]: boolean } = { [paths.home] = true }

    local found: { [string]: string } = {}
    for key, value in string.gmatch(own_file.text or "", "XDG_(%u+)_DIR=\"([^\"]*)\"") do
        found[key] = paths.expand((string.gsub(value, "%$HOME", function() return paths.home end)))
    end
    for _, o in OWN do
        local path = found[o.key]
        if path and not seen[path] and exists(path) then
            seen[path] = true
            table.insert(out, { name = paths.name(path), path = path, glyph = o.glyph, group = "own" })
        end
    end

    for line in string.gmatch(bookmark_file.text or "", "[^\r\n]+") do
        local uri, label = string.match(line, "^(%S+)%s*(.*)$")
        local path = if uri then g.uri_path(uri) else nil
        if path then
            path = paths.expand(path)
            if not seen[path] then
                seen[path] = true
                table.insert(out, {
                    name = if label and label ~= "" then label else paths.name(path),
                    path = path,
                    glyph = "star",
                    group = "bookmark",
                })
            end
        end
    end

    table.insert(out, { name = "Computer", path = "/", glyph = "computer", group = "computer" })
    table.insert(out, { name = "Trash", path = paths.TRASH, glyph = "trash", group = "computer" })
    return out
end)

-- ---- The bookmarks ------------------------------------------------------------------------

-- The file is every program's: a line changed is that line, and what is not
-- understood stays as it is.
local function lines(): { string }
    local out: { string } = {}
    for line in string.gmatch(g.untracked(function() return bookmark_file.text end) or "", "[^\r\n]+") do table.insert(out, line) end
    return out
end
local function path_of(line: string): string?
    local uri = string.match(line, "^(%S+)")
    local path = if uri then g.uri_path(uri) else nil
    return if path then paths.expand(path) else nil
end
local function write(list: { string })
    bookmark_file:write(if #list > 0 then table.concat(list, "\n") .. "\n" else "")
end
local function find(list: { string }, path: string): number?
    for i, line in list do
        if path_of(line) == path then return i end
    end
    return nil
end

-- Whether a folder is among the places already.
function M.has(path: string): boolean
    for _, p in M.list.value do
        if p.path == path then return true end
    end
    return false
end
function M.add(path: string)
    if path == paths.TRASH or g.untracked(function() return M.has(path) end) then return end
    local list = lines()
    table.insert(list, g.file_uri(path))
    write(list)
end
function M.remove(path: string)
    local list = lines()
    local at = find(list, path)
    if at == nil then return end
    table.remove(list, at)
    write(list)
end
-- Called so; with its own name, as its folder is.
function M.rename(path: string, name: string)
    local list = lines()
    local at = find(list, path)
    if at == nil then return end
    local uri = string.match(list[at], "^(%S+)") :: string
    name = string.match((string.gsub(name, "[\r\n]", " ")), "^%s*(.-)%s*$") or ""
    list[at] = if name == "" or name == paths.name(path) then uri else uri .. " " .. name
    write(list)
end
-- Before or after another of them.
function M.move(path: string, beside: string, after: boolean)
    local list = lines()
    local at = find(list, path)
    if at == nil then return end
    local line = table.remove(list, at) :: string
    local to = find(list, beside)
    if to == nil then return end
    table.insert(list, if after then to + 1 else to, line)
    write(list)
end

-- The place a path is in: the nearest one around it.
function M.of(path: string): Place?
    local best: Place? = nil
    for _, p in M.list.value do
        if paths.inside(path, p.path) and (best == nil or #p.path > #(best :: Place).path) then best = p end
    end
    return best
end

return M
