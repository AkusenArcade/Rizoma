--!strict
-- What a file or a folder is marked with: one of a few colours. It is kept on
-- the thing itself, as an extended attribute, so it goes where the thing goes;
-- and in a file of our own by path, for what can have no attribute (a link, a
-- FAT disk, what is not ours to write) and for what a program saves by putting
-- another in its place.
local g = require("@genoma")
local files = require("@genoma/files")
local paths = require("core/paths")

local M = {}

M.ATTRIBUTE = "user.rizoma.colour"

export type Colour = { key: string, name: string, hue: number }
-- Hues of one lightness, none of them the theme's own.
M.list = {
    { key = "red", name = "Red", hue = 0.02 },
    { key = "amber", name = "Amber", hue = 0.11 },
    { key = "green", name = "Green", hue = 0.36 },
    { key = "teal", name = "Teal", hue = 0.49 },
    { key = "blue", name = "Blue", hue = 0.60 },
    { key = "violet", name = "Violet", hue = 0.78 },
} :: { Colour }

local by_key: { [string]: Colour } = {}
for _, c in M.list do by_key[c.key] = c end

-- The one of an entry: nothing that is not ours.
function M.of(e: any): string?
    local key = if e then e.attribute else nil
    return if key and by_key[key] then key else nil
end
function M.name(key: string): string return if by_key[key] then by_key[key].name else "" end
function M.hex(key: string, dark: boolean): string
    local c = by_key[key]
    return if c then g.colour.hsla(c.hue, 0.62, if dark then 0.66 else 0.46, 1) else "#00000000"
end

-- ---- By path ----------------------------------------------------------------------------

local home = g.env("XDG_DATA_HOME") or (paths.home .. "/.local/share")
local file = g.file { path = home .. "/rizoma/colours.json" }

local function read(text: string?): { [string]: string }
    local out: { [string]: string } = {}
    local ok, parsed = pcall(g.parse_json, text or "{}")
    if ok and type(parsed) == "table" then
        for path, key in parsed do
            if type(path) == "string" and type(key) == "string" and by_key[key] then out[path] = key end
        end
    end
    return out
end
-- Followed: another window of Rizoma's writes it too.
local written = ""
local known = g.signal(read(g.untracked(function() return file.text end)))
g.watch(function() return file.text end, function(text: string?)
    if text ~= nil and text ~= written then known.value = read(text) end
end)
function M.known(): { [string]: string } return known.value end

local function keep(next_known: { [string]: string })
    known.value = next_known
    written = g.to_json(next_known, true)
    file:write(written)
end
local function now(): { [string]: string } return g.untracked(function() return known.value end) end

-- Moved or renamed: what is known of it, and of what is in it, goes along.
function M.moved(from: { string }, to: { string })
    local before = now()
    if next(before) == nil then return end
    local after: { [string]: string } = {}
    local changed = false
    for path, key in before do
        local at = path
        for i, f in from do
            if to[i] and paths.inside(path, f) then
                at = to[i] .. string.sub(path, #f + 1)
                break
            end
        end
        changed = changed or at ~= path
        after[at] = key
    end
    if changed then keep(after) end
end

-- Gone for good.
function M.gone(list: { string })
    local before = now()
    if next(before) == nil then return end
    local after: { [string]: string } = {}
    local changed = false
    for path, key in before do
        local dead = false
        for _, p in list do dead = dead or paths.inside(path, p) end
        if dead then changed = true else after[path] = key end
    end
    if changed then keep(after) end
end

-- Marked, or with nil no longer.
function M.set(list: { string }, key: string?, on_done: (() -> ())?)
    if #list == 0 then return end
    local after = table.clone(now())
    for _, p in list do
        -- JSON is text: a name that is not has its attribute alone.
        if utf8.len(p) then after[p] = key end
    end
    keep(after)
    files:set_attribute(list, M.ATTRIBUTE, key, function()
        if on_done then on_done() end
    end)
end

return M
