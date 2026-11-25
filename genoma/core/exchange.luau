--!strict
-- Files given to other programs, by the clipboard and by dragging. They are
-- given to be copied: nothing here lets another program move one.
local g = require("@genoma")
local clipboard = require("@genoma/clipboard")
local browser = require("core/browser")
local selection = require("core/selection")

local M = {}

local function uris(paths: { string }): { string }
    local out = table.create(#paths)
    for _, p in paths do table.insert(out, g.file_uri(p)) end
    return out
end

function M.copy()
    local paths = selection.list()
    if #paths == 0 then return end
    local list = uris(paths)
    local plain = table.concat(paths, "\n")
    local types: { [string]: string } = {
        ["text/uri-list"] = table.concat(list, "\r\n") .. "\r\n",
        ["x-special/gnome-copied-files"] = "copy\n" .. table.concat(list, "\n"),
    }
    -- As text, the paths: what a terminal is pasted. A name that is not
    -- UTF-8 has none.
    if utf8.len(plain) then
        types["text/plain;charset=utf-8"] = plain
        types["text/plain"] = plain
        types["UTF8_STRING"] = plain
    end
    clipboard:offer(types)
    browser.say { text = if #paths == 1 then "Copied" else `{#paths} items copied` }
end

-- What an entry's `drag_files` is: one a line, as a URI where a line or a
-- string could not hold the path.
function M.dragged(paths: { string }): string
    local out = table.create(#paths)
    for _, p in paths do
        table.insert(out, if utf8.len(p) and not string.find(p, "[\r\n]") then p else g.file_uri(p))
    end
    return table.concat(out, "\n")
end

return M
