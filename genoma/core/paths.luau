--!strict
-- Paths as text: taken apart, put together, said shortly.
local g = require("@genoma")

local M = {}

M.home = g.env("HOME") or "/"

-- "~", "~/x" and a trailing slash written out.
function M.expand(path: string): string
    if path == "~" then return M.home end
    if string.sub(path, 1, 2) == "~/" then path = M.home .. string.sub(path, 2) end
    path = string.gsub(path, "/+", "/")
    if #path > 1 and string.sub(path, -1) == "/" then path = string.sub(path, 1, -2) end
    return path
end

-- The folder around, or nil for the root.
function M.parent(path: string): string?
    if path == "/" then return nil end
    local up = string.match(path, "^(.*)/[^/]+/?$")
    if up == nil then return nil end
    return if up == "" then "/" else up
end

function M.name(path: string): string
    return string.match(path, "([^/]+)/?$") or "/"
end

-- What a folder is called where it is spoken of.
function M.called(path: string): string
    return if path == M.home then "Home" elseif path == "/" then "Computer" else M.name(path)
end

-- Whether `path` is `folder` or somewhere inside it.
function M.inside(path: string, folder: string): boolean
    if path == folder or folder == "/" then return true end
    return string.sub(path, 1, #folder + 1) == folder .. "/"
end

export type Step = { name: string, path: string }

-- A path as the steps that lead to it, from the home folder when it is
-- inside it, from the computer's root otherwise.
function M.steps(path: string): { Step }
    local out: { Step } = {}
    local walked, rest = "/", path
    if M.home ~= "/" and M.inside(path, M.home) then
        table.insert(out, { name = "Home", path = M.home })
        walked, rest = M.home, string.sub(path, #M.home + 1)
    else
        table.insert(out, { name = "Computer", path = "/" })
    end
    for part in string.gmatch(rest, "[^/]+") do
        walked = (if walked == "/" then "" else walked) .. "/" .. part
        table.insert(out, { name = part, path = walked })
    end
    return out
end

return M
