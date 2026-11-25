--!strict
-- The trash as a folder is seen: the same questions a g.directory answers,
-- answered from what was thrown away. An entry is where it is now; `within`
-- is the folder it was in, `modified` when it was thrown away.
local g = require("@genoma")
local trash = require("@genoma/trash")
local config = require("core/config")
local paths = require("core/paths")

local M = {}

export type Looked = { filter: () -> string }

-- What sorts a name as people do: no case, a run of digits by its value.
local function natural(name: string): string
    return (string.gsub(string.lower(name), "%d+", function(d: string) return string.rep("0", math.max(0, 12 - #d)) .. d end))
end

local function short(path: string): string
    if path == paths.home then return "Home" end
    if paths.home ~= "/" and paths.inside(path, paths.home) then return string.sub(path, #paths.home + 2) end
    return path
end

local items = g.computed(function(): { any }
    local out: { any } = {}
    for _, t in trash.items do
        table.insert(out, {
            name = t.name,
            path = t.file,
            origin = t.path,
            within = short(paths.parent(t.path) or "/"),
            dir = t.dir,
            link = false,
            broken = false,
            hidden = false,
            executable = false,
            size = t.size,
            modified = t.deleted,
            deleted = t.deleted,
            mime = t.mime,
            key = natural(t.name),
        })
    end
    return out
end)

function M.count(): number return trash.count end

-- `t`: filter() what is typed.
function M.new(t: Looked): any
    local shown = g.computed(function(): { any }
        local filter = string.lower(t.filter())
        local out: { any } = {}
        for _, e in items.value do
            if filter == "" or string.find(string.lower(e.name), filter, 1, true) then table.insert(out, e) end
        end
        local by, down, folders = config.get("sort"), config.get("descending"), config.get("folders_first")
        local function value(e: any): any
            return if by == "size" then e.size elseif by == "modified" then e.modified elseif by == "type" then e.mime else e.key
        end
        table.sort(out, function(a: any, b: any): boolean
            if folders and a.dir ~= b.dir then return a.dir end
            local x, y = value(a), value(b)
            if x ~= y then
                if down then return x > y end
                return x < y
            end
            if a.key ~= b.key then return a.key < b.key end
            return a.path < b.path
        end)
        return out
    end)
    local places = g.computed(function(): { [string]: number }
        local out: { [string]: number } = {}
        for i, e in shown.value do out[e.path] = i end
        return out
    end)
    local dir: { [any]: any } = {}
    local fields: { [string]: () -> any } = {
        count = function() return #shown.value end,
        total = function() return #items.value end,
        path = function() return paths.TRASH end,
        loading = function() return trash.loading end,
        error = function() return nil end,
        searching = function() return false end,
        capped = function() return false end,
    }
    function dir.at(_: any, i: number): any return shown.value[i] end
    function dir.slice(_: any, first: number, last: number): { any }
        return table.move(shown.value, math.max(1, first), math.min(last, #shown.value), 1, {})
    end
    function dir.paths(_: any, first: number?, last: number?): { string }
        local out: { string } = {}
        for i = math.max(1, first or 1), math.min(last or #shown.value, #shown.value) do
            table.insert(out, shown.value[i].path)
        end
        return out
    end
    function dir.index(_: any, path: string): number? return places.value[path] end
    function dir.reload(_: any) trash:reload() end
    return setmetatable(dir, {
        __index = function(_: any, key: string): any
            local f = fields[key]
            return if f then f() else nil
        end,
    })
end

return M
