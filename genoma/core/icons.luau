--!strict
-- The icon theme's drawing for an entry, asked once for each kind.
local g = require("@genoma")
local mime = require("@genoma/mime")
local portal = require("@genoma/portal")
local paths = require("core/paths")
local places = require("core/places")

local M = {}

local FOLDERS = {
    desktop = { "user-desktop" },
    documents = { "folder-documents" },
    download = { "folder-download", "folder-downloads" },
    music = { "folder-music" },
    pictures = { "folder-pictures" },
    videos = { "folder-videos" },
    home = { "user-home", "folder-home" },
    trash = { "user-trash" },
}

-- As the theme draws it for a size: at a list's, a shape alone.
local function first(names: { string }, size: number): string?
    for _, name in names do
        local path = g.icon_path(name, size)
        if path then return path end
    end
    return nil
end

-- What was found, by theme: another theme's is found again.
local found: { [string]: string } = {}
local found_in = ""

local special = g.computed(function(): { [string]: { string } }
    local out: { [string]: { string } } = {}
    for _, p in places.list.value do
        local names = (FOLDERS :: any)[p.glyph]
        if names then out[p.path] = names end
    end
    return out
end)

function M.of(e: any, size: number): string
    local theme = portal.icon_theme
    if theme ~= found_in then
        found, found_in = {}, theme
    end
    local own = if e.dir then special.value[e.path] else nil
    -- A broken link is a faded file, not the theme's own warning.
    local key = size .. (if own then e.path elseif e.broken then "broken" else e.mime)
    local hit = found[key]
    if hit == nil then
        hit = (if own then first(own, size) else nil)
            or (if e.broken then nil else mime:icon(e.mime, size))
            or first(if e.dir then { "folder" } else { "text-x-generic", "unknown" }, size)
            or ""
        found[key] = hit
    end
    return hit
end

return M
