--!strict
-- An entry's picture: its thumbnail where it can have one, the icon
-- theme's drawing of what it is otherwise.
local g = require("@genoma")
local thumbnails = require("@genoma/thumbnails")
local browser = require("core/browser")
local icons = require("core/icons")
local look = require("ui/look")
local ui = require("ui/controls")

local M = {}

-- `entry()` may be nil while its row goes.
function M.picture(entry: () -> any, size: number, pictured: boolean): any
    local thumb = g.computed(function(): string?
        local e = entry()
        if not pictured or e == nil or e.dir or e.broken or not thumbnails:can(e.mime) then return nil end
        return thumbnails:of(e.path, {
            size = if size > 128 then "x-large" elseif size > 64 then "large" else "normal",
            modified = e.modified,
            mime = e.mime,
        })
    end)
    return g.box {
        width = size,
        height = size,
        align = "center",
        justify = "center",
        g.icon {
            present = function() return thumb.value == nil end,
            width = size,
            height = size,
            icon = function()
                local e = entry()
                return if e then icons.of(e, size) else ""
            end,
        },
        g.image {
            present = function() return thumb.value ~= nil end,
            width = size,
            height = size,
            radius = math.min(8, size / 6),
            fit = "contain",
            src = function() return thumb.value or "" end,
        },
        -- A link says so at its corner.
        g.capsule {
            present = function()
                local e = entry()
                return e ~= nil and e.link
            end,
            overlay = true,
            right = 0,
            bottom = 0,
            width = math.max(12, size / 4),
            height = math.max(12, size / 4),
            radius = math.max(12, size / 4) / 2,
            align = "center",
            justify = "center",
            fill = look.cell,
            rim_top = look.rim,
            rim_bottom = look.line,
            ui.glyph("link", math.max(9, size / 6), function() return false end, look.text),
        },
    }
end

function M.faded(e: any): number
    if e == nil then return 0 end
    return if e.broken then 0.4 elseif e.hidden then 0.6 else 1
end

-- What a press does, the same in both views: a click stands on it, a
-- double one opens it.
function M.pressed(entry: () -> any): (number, number, number, number) -> ()
    return function(button: number, _: number, _: number, count: number)
        if button ~= 272 then return end
        local e = g.untracked(entry)
        if e == nil then return end
        browser.cursor.value = e.path
        if count == 2 then browser.open(e) end
    end
end

return M
