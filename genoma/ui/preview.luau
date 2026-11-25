--!strict
-- What is stood on, seen without opening it: a pane beside the folder where
-- there is room, over it where there is not. It grows from the entry itself.
-- With nothing stood on, it is the folder's own.
local g = require("@genoma")
local apps_mime = require("@genoma/mime")
local thumbnails = require("@genoma/thumbnails")
local browser = require("core/browser")
local config = require("core/config")
local format = require("core/format")
local icons = require("core/icons")
local paths = require("core/paths")
local selection = require("core/selection")
local look = require("ui/look")
local ui = require("ui/controls")

local M = {}

M.WIDTH = 288
-- What the pane keeps of a text and of a folder: what it can show.
local BYTES, LINES, COLUMNS, NAMES = 12000, 80, 400, 14
local PAD = 18

-- The entry seen, a moment after it is stood on: walking through a folder
-- with the arrows does not read every file on the way.
local REST = 0.12
local seen = g.signal(nil :: any)
do
    local waiting: any = nil
    local function now(): any
        -- Several chosen, they are seen together.
        local n = selection.count()
        if n > 1 then
            return { name = `{n} selected`, path = `selection:{n}`, dir = false, link = false, broken = false, hidden = false, size = 0, modified = 0, mime = "", many = selection.entries(NAMES + 1), count = n, sum = selection.sum.value }
        end
        local e = browser.selected()
        if e then return e end
        -- The folder one is in, as an entry.
        local here = browser.dir.path
        return { name = paths.name(here), path = here, dir = true, link = false, broken = false, hidden = false, size = 0, modified = 0, mime = "inode/directory", own = true }
    end
    g.effect(function()
        local e = now()
        local _ = browser.dir.error
        g.untracked(function()
            if waiting then waiting:stop() end
            waiting = nil
            local before = seen.value
            if before == nil or (before.path == e.path and not e.many) then
                seen.value = e
                return
            end
            waiting = g.after(REST, function()
                waiting = nil
                seen.value = e
            end)
        end)
    end)
end

-- The desktop's fixed-width font, for what a machine reads: fontconfig's
-- own answer, asked once.
local mono = g.lasting(function()
    local name = g.signal("DejaVu Sans Mono")
    g.process {
        command = { "fc-match", "-f", "%{family[0]}", "monospace" },
        on_line = function(line: string) if line ~= "" then name.value = line end end,
    }
    return name
end)

-- ---- Kinds --------------------------------------------------------------------------

-- Pictures that may move are shown as they are; the rest by their thumbnail,
-- which any format has and which is the right way up.
local MOVING = { ["image/gif"] = true, ["image/webp"] = true, ["image/apng"] = true }
local function kind_of(e: any): string
    if e.broken or e.path == paths.TRASH then return "other" end
    if e.dir then return "folder" end
    if MOVING[e.mime] and e.size < 32e6 then return "moving" end
    if thumbnails:can(e.mime) then return "pictured" end
    if apps_mime:is_a(e.mime, "text/plain") or e.mime == "application/json" or e.mime == "application/xml" then
        -- An empty file is nothing to read, and a name may call a pipe text.
        if e.size > 0 then return "text" end
    end
    return "other"
end

local function emblem(e: any, size: number): any
    return g.box {
        direction = "row",
        justify = "center",
        g.icon { width = size, height = size, icon = function() return icons.of(e, size) end, opacity = if e.broken then 0.4 else 1 },
    }
end

-- As wide as the pane and as tall as it is, within the room it has.
local function picture(src: () -> string?, e: any, width: number, height: number): any
    return g.box {
        width = width,
        height = height,
        align = "center",
        justify = "center",
        g.image {
            present = function() return src() ~= nil end,
            width = width,
            height = height,
            radius = look.radius_well,
            fit = "contain",
            src = function() return src() or "" end,
        },
        g.box {
            present = function() return src() == nil end,
            emblem(e, 96),
        },
    }
end

local function text_head(e: any, width: number, height: number): any
    local text = g.signal("")
    local lines: { string } = {}
    local process = g.process {
        command = { "head", "-c", tostring(BYTES), "--", e.path },
        on_line = function(line: string)
            if #lines >= LINES then return end
            line = string.gsub(line, "\t", "    ")
            line = string.gsub(line, "%c", "")
            if utf8.len(line) and (utf8.len(line) :: number) > COLUMNS then
                line = string.sub(line, 1, (utf8.offset(line, COLUMNS + 1) or 1) - 1) .. "…"
            end
            table.insert(lines, line)
        end,
        on_exit = function() text.value = table.concat(lines, "\n") end,
    }
    g.cleanup(function()
        process:stop()
        process:kill()
    end)
    return g.capsule {
        width = width,
        height = height,
        radius = look.radius_well,
        clip = true,
        fade_bottom = 24,
        fill = function() return g.colour.alpha(look.background(), 0.8) end,
        rim_top = look.CLEAR,
        rim_bottom = look.CLEAR,
        direction = "column",
        align = "start",
        g.box {
            overlay = true,
            attach = "corner",
            offset_x = 10,
            offset_y = 8,
            g.text {
                text = function() return text.value end,
                max_width = width - 20,
                wrap = true,
                color = look.text_muted,
                font = function() return mono.value end,
                size = look.font_meta,
            },
        },
    }
end

-- Several entries: their first names.
local function many_head(e: any, width: number, height: number): any
    local names = math.max(1, math.min(NAMES, math.floor((height - 20) / 26)))
    local shown = if e.count > names then names - 1 else e.count
    local rows: { [any]: any } = { direction = "column", align = "stretch", gap = 4, padding = 10 }
    for i = 1, math.min(shown, #e.many) do
        local it = e.many[i]
        table.insert(rows, g.box {
            direction = "row",
            align = "center",
            gap = 8,
            height = 22,
            g.icon { width = 18, height = 18, icon = function() return icons.of(it, 24) end },
            g.text { text = it.name, max_width = width - 60, ellipsize = "middle", color = look.text_muted, font = look.expressive, size = look.font_text },
        })
    end
    if e.count > shown then
        table.insert(rows, g.box {
            height = 22,
            direction = "row",
            align = "center",
            g.text { text = `and {e.count - shown} more`, color = look.text_faint, font = look.expressive, italic = true, size = look.font_text },
        })
    end
    return g.capsule {
        width = width,
        radius = look.radius_well,
        fill = function() return g.colour.alpha(look.background(), 0.8) end,
        rim_top = look.CLEAR,
        rim_bottom = look.CLEAR,
        direction = "column",
        align = "stretch",
        g.box(rows),
    }
end

local function folder_head(e: any, width: number, height: number): any
    -- Its own order and its own hidden files, whatever the window's are.
    local dir = g.directory { path = e.path, hidden = function() return config.get("hidden") end, watch = true }
    g.cleanup(function() dir:stop() end)
    local names = math.max(1, math.min(NAMES, math.floor((height - 20) / 26)))
    local rows: { [any]: any } = { direction = "column", align = "stretch", gap = 4, padding = 10 }
    for i = 1, names do
        local at = g.computed(function(): any return dir:at(i) end)
        table.insert(rows, g.box {
            present = function() return at.value ~= nil and (i < names or dir.count <= names) end,
            direction = "row",
            align = "center",
            gap = 8,
            height = 22,
            g.icon { width = 18, height = 18, icon = function() return if at.value then icons.of(at.value, 24) else "" end },
            g.text {
                text = function() return if at.value then at.value.name else "" end,
                max_width = width - 60,
                ellipsize = "middle",
                color = look.text_muted,
                font = look.expressive,
                size = look.font_text,
            },
        })
    end
    table.insert(rows, g.box {
        present = function() return dir.count > names end,
        height = 22,
        direction = "row",
        align = "center",
        g.text {
            text = function() return `and {dir.count - names + 1} more` end,
            color = look.text_faint,
            font = look.expressive,
            italic = true,
            size = look.font_text,
        },
    })
    local function said(): string
        if dir.error then return "Not to be read" end
        if dir.loading or dir.count > 0 then return "" end
        return "Nothing here"
    end
    return g.capsule {
        width = width,
        radius = look.radius_well,
        fill = function() return g.colour.alpha(look.background(), 0.8) end,
        rim_top = look.CLEAR,
        rim_bottom = look.CLEAR,
        direction = "column",
        align = "stretch",
        g.box(rows),
        g.box {
            present = function() return said() ~= "" end,
            padding = 12,
            direction = "row",
            justify = "center",
            g.text { text = said, color = look.text_faint, font = look.expressive, italic = true, size = look.font_text },
        },
    }, function(): string
        return if dir.error or dir.loading then "" else if dir.count == 1 then "1 item" else `{dir.count} items`
    end
end

local function fact(name: string, value: () -> string, human: boolean?): any
    return g.box {
        present = function() return value() ~= "" end,
        direction = "row",
        align = "center",
        justify = "between",
        gap = 12,
        height = 22,
        ui.label(name, look.text_faint),
        g.text {
            text = value,
            max_width = M.WIDTH - PAD * 2 - 90,
            ellipsize = "middle",
            color = look.text,
            font = if human then look.expressive else look.technical,
            size = if human then look.font_text else look.font_meta,
            tabular = true,
        },
    }
end

function M.said(sum: any): string
    local function some(n: number, one: string): string return `{n} {one}{if n == 1 then "" else "s"}` end
    if sum.bytes == nil then return "" end
    if sum.folders == 0 then return some(sum.files, "file") end
    if sum.files == 0 then return some(sum.folders, "folder") end
    return `{some(sum.folders, "folder")}, {some(sum.files, "file")}`
end

-- One entry, in a pane this wide and tall. Made again for each.
local function page(e: any, width: number, height: () -> number): any
    local inner = width - PAD * 2
    local room = math.max(80, math.min(g.untracked(height) - 210, inner * 1.25))
    local kind = if e.many then "many" else kind_of(e)
    local head: any, count: any = nil, nil
    if kind == "moving" then
        head = picture(function() return e.path end, e, inner, math.min(room, inner))
    elseif kind == "pictured" then
        local made = g.computed(function(): string?
            return thumbnails:of(e.path, { size = "x-large", modified = if e.deleted then nil else e.modified, mime = e.mime })
        end)
        head = picture(function() return made.value end, e, inner, math.min(room, inner))
    elseif kind == "text" then
        head = text_head(e, inner, room)
    elseif kind == "many" then
        head = many_head(e, inner, room)
    elseif kind == "folder" then
        head, count = folder_head(e, inner, room)
    end
    local opens = if e.dir or e.broken or e.many or e.deleted then nil else apps_mime:default(e.mime)
    local in_now = g.signal(false)
    g.after(0, function() in_now.value = true end)
    return g.box {
        overlay = true,
        attach = "corner",
        offset_x = PAD,
        offset_y = function() return PAD + (if in_now.value then 0 else 4) end,
        width = inner,
        direction = "column",
        align = "stretch",
        gap = 14,
        opacity = function() return if in_now.value then 1 else 0 end,
        transition = { opacity = "folder_in", offset_y = "folder_in" },
        head or emblem(e, 112),
        g.box {
            direction = "column",
            align = "stretch",
            gap = 2,
            g.text {
                text = if e.own and e.path == paths.home then "Home" else e.name,
                max_width = inner,
                wrap = true,
                color = look.text,
                font = look.expressive,
                size = look.font_name,
                weight = 600,
            },
            g.text {
                text = if e.broken then "Link to nothing" elseif e.many then M.said(e.sum) elseif e.path == paths.TRASH then "" else apps_mime:description(e.mime),
                max_width = inner,
                color = look.text_muted,
                font = look.expressive,
                size = look.font_text,
            },
        },
        g.box {
            direction = "column",
            align = "stretch",
            fact("Inside", function() return if count then count() else "" end),
            fact("Size", function()
                if e.many then return if e.sum.bytes and e.sum.files > 0 then format.size(e.sum.bytes) else "" end
                return if e.dir then "" else format.size(e.size)
            end),
            fact(if e.deleted then "Thrown away" else "Modified", function() return format.moment(e.modified) end),
            fact("Was in", function() return if e.deleted then e.within else "" end, true),
            fact("Opens with", function() return if opens then opens.name else "" end, true),
        },
    }
end

-- `t`: pinned(), open(), x(), y(), width(), height(), origin() → where the
-- entry stood on is drawn, { x, y, w, h }, or nil.
function M.new(t: { [string]: any }): any
    local function shown(): boolean return t.pinned() or t.open() end
    local there = g.signal(g.untracked(shown))
    local grown = g.signal(g.untracked(shown))
    local from = g.signal(nil :: any)
    local closing = g.signal(false)
    local putting_away: any = nil
    g.watch(shown, function(on: boolean)
        if putting_away then putting_away:stop() end
        putting_away = nil
        -- From the entry, and back to it, wherever it is by then.
        closing.value = not on
        from.value = g.untracked(t.origin)
        if on then
            there.value = true
            g.after(0, function() grown.value = g.untracked(shown) end)
        else
            grown.value = false
            putting_away = g.after(look.CLOSE, function()
                putting_away = nil
                there.value = false
                closing.value = false
            end)
        end
    end)
    local function at(k: string): number
        local o = from.value
        if o then return o[k] end
        -- Nothing to grow from: from its own outer edge.
        return if k == "x" then t.x() + t.width() elseif k == "y" then t.y() elseif k == "w" then 0.5 else t.height()
    end
    local function timing(): string
        return if grown.value then "cell_open" elseif closing.value then "cell_close" else "placed"
    end
    return g.capsule {
        id = "preview",
        name = "Preview",
        overlay = true,
        attach = "corner",
        present = function() return there.value end,
        offset_x = function() return if grown.value then t.x() else at("x") end,
        offset_y = function() return if grown.value then t.y() else at("y") end,
        width = function() return if grown.value then t.width() else at("w") end,
        height = function() return if grown.value then t.height() else at("h") end,
        radius = look.radius_panel,
        clip = true,
        opacity = function() return if grown.value then 1 else 0 end,
        fill = function() return if t.pinned() then look.glass() else look.glass_over() end,
        rim_top = look.rim,
        rim_bottom = look.line,
        backdrop_blur = function() return if t.pinned() then 0 else look.glass_blur end,
        transition = { offset_x = timing, offset_y = timing, width = timing, height = timing, opacity = timing },
        on_press = function() end,
        on_click = function() end,
        g.box {
            overlay = true,
            attach = "corner",
            width = t.width,
            height = t.height,
            direction = "column",
            align = "start",
            justify = "start",
            opacity = function() return if grown.value then 1 else 0 end,
            transition = { opacity = function() return if grown.value then "content_in" else "content_out" end },
            g.each {
                items = function(): { any } return if there.value and seen.value then { seen.value } else {} end,
                direction = "column",
                align = "start",
                justify = "start",
                width = t.width,
                height = t.height,
                key = function(e) return `{e.path}:{e.modified}:{e.mime}:{g.untracked(t.width)}` end,
                row = function(e, _) return page(g.untracked(e), g.untracked(t.width), t.height) end,
            },
        },
    }
end

return M
