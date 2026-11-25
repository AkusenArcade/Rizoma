--!strict
-- A path being typed, and the folders it may be going to: those in the
-- folder already named, by how they begin.
local g = require("@genoma")
local browser = require("core/browser")
local paths = require("core/paths")

local M = {}

M.typed = g.signal("")
local MOST = 8

-- The folder named so far, what is written to show for it, and the
-- beginning of the next name.
local function split(text: string): (string, string, string)
    local head, tail = string.match(text, "^(.*/)([^/]*)$")
    if head == nil then
        if text == "~" then return paths.home, "~/", "" end
        return g.untracked(function() return browser.here.value end), "", text
    end
    local base = head :: string
    if string.sub(base, 1, 1) ~= "/" and string.sub(base, 1, 1) ~= "~" then
        base = g.untracked(function() return browser.here.value end) .. "/" .. base
    end
    return paths.expand(base), head :: string, tail :: string
end

local parts = g.computed(function(): { base: string, head: string, tail: string }
    local base, head, tail = split(M.typed.value)
    return { base = base, head = head, tail = tail }
end)

local dir = g.directory {
    path = function() return parts.value.base end,
    -- A dot says hidden ones are meant.
    hidden = function() return string.sub(parts.value.tail, 1, 1) == "." end,
    filter = function() return parts.value.tail end,
    folders_first = true,
}

export type Suggestion = { name: string, text: string, path: string }

M.list = g.computed(function(): { Suggestion }
    local out: { Suggestion } = {}
    local p = parts.value
    if dir.error or dir.path ~= p.base then return out end
    local tail = string.lower(p.tail)
    for i = 1, dir.count do
        local e = dir:at(i)
        if e == nil or not e.dir or #out >= MOST then break end
        if not e.broken and utf8.len(e.path) and string.sub(string.lower(e.name), 1, #tail) == tail then
            table.insert(out, { name = e.name, text = p.head .. e.name .. "/", path = e.path })
        end
    end
    return out
end)

-- Which of them the keys chose, 0 none.
M.at = g.signal(0)
g.watch(function() return M.typed.value end, function() M.at.value = 0 end)

function M.choose(by: number)
    local n = #g.untracked(function() return M.list.value end)
    if n == 0 then return end
    local to = g.untracked(function() return M.at.value end) + by
    -- Past an end it is none again, what was typed.
    M.at.value = if to < 0 then n elseif to > n then 0 else to
end

function M.chosen(): Suggestion?
    local list = M.list.value
    return list[M.at.value]
end

-- What would be completed now: the chosen one, else the first.
function M.next(): Suggestion?
    return M.chosen() or M.list.value[1]
end

-- The rest of the first suggestion, shown after what is typed: only when
-- what is typed is how it begins, letter by letter.
function M.rest(): string
    local n = M.next()
    local text = M.typed.value
    if n == nil or parts.value.tail == "" and M.at.value == 0 then return "" end
    if string.sub(n.text, 1, #text) ~= text then return "" end
    return string.sub(n.text, #text + 1)
end

return M
