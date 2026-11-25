--!strict
-- Rizoma, a file manager. This version reads: no operation here can change
-- a file (docs/plan.md, phase 1).
--
--   genoma Rizoma/genoma                   (RIZOMA_FOLDER: where it opens)
--   genoma ipc rizoma open <folder>        (GENOMA_IPC names the socket)
local g = require("@genoma")
local browser = require("core/browser")
local config = require("core/config")
local format = require("core/format")
local paths = require("core/paths")
local mime = require("@genoma/mime")
local look = require("ui/look")
local ui = require("ui/controls")
local path_bar = require("ui/path_bar")
local sidebar = require("ui/sidebar")
local grid = require("ui/grid")
local list = require("ui/list")
local preview = require("ui/preview")
local view_cell = require("ui/view_cell")

local E, GAP, H = look.margin_edge, look.gap, look.cell_height
-- Narrower than this, the places float over the folder.
local WIDE = 800

local area = g.signal({ w = 1100, h = 700 })
local floating = g.signal(false)
local filtering = g.signal(false)

local function pinned(): boolean return config.get("places") and area.value.w >= WIDE end
local function left(): number return if pinned() then E + sidebar.WIDTH + GAP else E end
-- What the folder and its preview share; with less than this, the preview
-- floats over the folder.
local SHARED = 660
local function across_all(): number return area.value.w - left() - E end
local peeking = g.signal(false)
local function roomy(): boolean return across_all() >= SHARED end
local function preview_pinned(): boolean return config.get("preview") and roomy() end
local function width(): number
    return math.max(120, across_all() - (if preview_pinned() then preview.WIDTH + GAP else 0))
end
local top = E + H + GAP
-- The folder ends above what floats at the foot: nothing is read through it.
local function height(): number return math.max(80, area.value.h - top - E - H - 8) end

g.watch(pinned, function(on: boolean) if on then floating.value = false end end)
g.watch(preview_pinned, function(on: boolean) if on then peeking.value = false end end)

sidebar.chose = function(path: string)
    floating.value = false
    browser.go(path)
end

-- ---- Filter -------------------------------------------------------------------------

local function filter(text: string)
    browser.filter.value = text
    if text ~= "" then filtering.value = true end
end
local function stop_filtering()
    filtering.value = false
    browser.filter.value = ""
end
-- Another folder is another search.
g.watch(function() return browser.here.value end, function() filtering.value = false end)
-- The best guess stands ready for Return.
g.watch(function() return browser.filter.value .. "\0" .. browser.dir.count end, function()
    if g.untracked(function() return browser.filter.value end) ~= ""
        and g.untracked(function() return browser.index.value end) == nil then
        browser.stand(1)
    end
end)

-- ---- Keys ---------------------------------------------------------------------------

local function open_chosen()
    local e = g.untracked(browser.selected)
    if e then browser.open(e) end
end

local function across(): number
    return if g.untracked(function() return config.get("view") end) == "grid"
        then g.untracked(function() return grid.columns.value end) else 1
end
local function page(): number
    if g.untracked(function() return config.get("view") end) == "grid" then
        return g.untracked(function() return grid.columns.value * grid.rows_in_view.value end)
    end
    return math.max(1, math.floor((g.untracked(height) - list.head) / list.row_height) - 1)
end

local function moved(name: string): boolean
    if name == "Down" then browser.move(across())
    elseif name == "Up" then browser.move(-across())
    elseif name == "Next" then browser.move(page())
    elseif name == "Prior" then browser.move(-page())
    else return false end
    return true
end

local function toggle(key: string)
    config.set(key, not g.untracked(function() return config.get(key) end))
end

local function toggle_places()
    if g.untracked(function() return area.value.w end) >= WIDE then
        toggle("places")
    else
        floating.value = not g.untracked(function() return floating.value end)
    end
end

local function toggle_preview()
    if g.untracked(roomy) then
        toggle("preview")
    else
        peeking.value = not g.untracked(function() return peeking.value end)
    end
end

local function escape()
    if g.untracked(function() return view_cell.open.value end) then
        view_cell.open.value = false
    elseif g.untracked(function() return peeking.value end) then
        peeking.value = false
    elseif g.untracked(function() return floating.value end) then
        floating.value = false
    elseif g.untracked(function() return browser.notice.value end) ~= nil then
        browser.say(nil)
    elseif g.untracked(function() return filtering.value or browser.filter.value ~= "" end) then
        stop_filtering()
    else
        browser.cursor.value = nil
    end
end

-- Every key the window is given; while a field has them, those it leaves
-- (Escape, the arrows up and down, the commands).
local function key(name: string, text: string?, mods: any)
    if mods.logo then return end
    if g.untracked(function() return path_bar.editing.value end) then
        if name == "Escape" then path_bar.editing.value = false end
        return
    end
    if mods.ctrl then
        local letter = string.lower(name)
        if letter == "h" then toggle("hidden")
        elseif letter == "l" then path_bar.editing.value = true
        elseif letter == "f" then filtering.value = true
        elseif letter == "r" then browser.dir:reload()
        elseif name == "1" then config.set("view", "grid")
        elseif name == "2" then config.set("view", "list")
        end
        return
    end
    if mods.alt then
        if name == "Left" then browser.back()
        elseif name == "Right" then browser.forward()
        elseif name == "Up" then browser.up()
        elseif name == "Down" then open_chosen()
        elseif name == "Home" then browser.go("~")
        end
        return
    end
    if moved(name) then return end
    if name == "Left" then browser.move(-1)
    elseif name == "Right" then browser.move(1)
    elseif name == "Home" then browser.stand(1)
    elseif name == "End" then browser.stand(g.untracked(function() return browser.dir.count end))
    elseif name == "Return" or name == "KP_Enter" then
        local notice = g.untracked(function() return browser.notice.value end)
        if notice and notice.act then notice.act() else open_chosen() end
    elseif name == "BackSpace" then
        if g.untracked(function() return filtering.value end) then stop_filtering() else browser.up() end
    elseif name == "Escape" then escape()
    elseif name == "F5" then browser.dir:reload()
    elseif name == "F9" then toggle_places()
    elseif name == "space" then toggle_preview()
    elseif name == "XF86Back" then browser.back()
    elseif name == "XF86Forward" then browser.forward()
    elseif text and #text > 0 and string.match(text, "^[^%c ]") then
        -- Typed over the folder, a name is looked for in it.
        filter(g.untracked(function() return browser.filter.value end) .. text)
    end
end

-- ---- The folder ---------------------------------------------------------------------

-- Each folder is another one: it starts from its top, and comes in.
local function folder(): any
    local in_now = g.signal(false)
    g.after(0, function() in_now.value = true end)
    local view = g.untracked(function() return config.get("view") end)
    return g.box {
        width = width,
        height = height,
        opacity = function() return if in_now.value then 1 else 0 end,
        offset_y = function() return if in_now.value then 0 else 4 end,
        transition = { opacity = "folder_in", offset_y = "folder_in" },
        if view == "grid" then grid.new(width, height) else list.new(width, height),
    }
end

local shown = g.computed(function(): { string }
    local view = config.get("view")
    return { `{view}:{if view == "grid" then config.get("icon") else 0}:{browser.dir.path}` }
end)

-- Why there is nothing to see, when there is nothing.
local WORDS = { ["not found"] = "This folder is not there", ["permission denied"] = "This folder is not yours to read", ["not a folder"] = "This is not a folder" }
local function empty_text(): string
    local why = browser.dir.error
    if why then return (WORDS :: any)[why] or `This folder cannot be read: {why}` end
    if browser.dir.count > 0 or browser.dir.loading then return "" end
    if browser.filter.value ~= "" then return "Nothing by that name" end
    if browser.dir.total > 0 then return "Only hidden files" end
    return "Nothing here"
end

local content = g.box {
    overlay = true,
    attach = "corner",
    offset_x = left,
    offset_y = top,
    width = width,
    height = height,
    transition = { offset_x = "cell_open" },
    -- A press beside the entries stands on none.
    on_press = function() end,
    on_click = function(button: number)
        if button == 272 then browser.cursor.value = nil
        elseif button == 275 then browser.back()
        elseif button == 276 then browser.forward()
        end
    end,
    g.each {
        direction = "column",
        items = function() return shown.value end,
        key = function(k: string) return k end,
        row = function(_) return folder() end,
    },
    g.box {
        present = function() return empty_text() ~= "" end,
        overlay = true,
        attach = "center",
        g.text {
            text = empty_text,
            color = look.text_faint,
            font = look.expressive,
            size = look.font_label,
            italic = true,
        },
    },
}

-- ---- Above it -----------------------------------------------------------------------

local function places_button_shown(): boolean return not pinned() end
local function bar_x(): number return left() + (if places_button_shown() then H + 8 else 0) end
local NAV = 34
local nav_w = NAV * 3 + 4 * 2
local function path_x(): number return bar_x() + nav_w + GAP end

local header = g.box {
    overlay = true,
    attach = "corner",
    offset_x = left,
    offset_y = E,
    height = H,
    direction = "row",
    align = "center",
    gap = GAP,
    transition = { offset_x = "cell_open" },
    ui.round {
        id = "places-button",
        name = "Places",
        glyph = "places",
        present = places_button_shown,
        lit = function() return floating.value end,
        on_click = toggle_places,
    },
    g.box {
        direction = "row",
        align = "center",
        gap = 4,
        ui.round { id = "back", name = "Back", glyph = "chevron-left", size = NAV, disabled = function() return not browser.can_back() end, on_click = browser.back },
        ui.round { id = "forward", name = "Forward", glyph = "chevron-right", size = NAV, disabled = function() return not browser.can_forward() end, on_click = browser.forward },
        ui.round { id = "up", name = "Up", glyph = "chevron-up", size = NAV, disabled = function() return not browser.can_up() end, on_click = browser.up },
    },
    path_bar.new(function() return math.max(120, area.value.w - path_x() - E) end),
}

-- ---- Below it: what is stood on, what has to be said, the filter --------------------

local function foot_room(): number return math.max(160, width() - H - GAP) end

local function said(): (string, string)
    local e = browser.selected()
    -- The list says it in its columns, the preview in its own words.
    if e == nil or config.get("view") ~= "grid" or preview_pinned() or peeking.value then return "", "" end
    local kind = mime:description(e.mime)
    if e.dir then return e.name, format.moment(e.modified) end
    return e.name .. " — " .. kind, `{format.size(e.size)}   {format.moment(e.modified)}`
end

local function pill(present: () -> boolean, ...: any): any
    return g.capsule {
        present = present,
        height = H,
        radius = H / 2,
        padding_x = 18,
        direction = "row",
        align = "center",
        gap = 14,
        fill = look.glass_over,
        rim_top = look.rim,
        rim_bottom = look.line,
        backdrop_blur = look.glass_blur,
        on_press = function() end,
        on_click = function() end,
        ...,
    }
end

local foot = g.box {
    overlay = true,
    attach = "corner",
    offset_x = left,
    offset_y = function() return area.value.h - E - H end,
    height = H,
    direction = "row",
    align = "center",
    gap = GAP,
    transition = { offset_x = "cell_open" },
    g.capsule {
        present = function() return filtering.value end,
        width = function() return math.min(260, foot_room()) end,
        height = H,
        radius = H / 2,
        padding_x = 16,
        direction = "row",
        align = "center",
        gap = 10,
        fill = look.glass_over,
        rim_top = look.primary,
        rim_bottom = look.primary,
        backdrop_blur = look.glass_blur,
        ui.glyph("search", 18),
        g.field {
            id = "filter-field",
            grow = 1,
            size = look.font_label,
            font = look.expressive,
            color = look.text,
            caret_color = look.primary,
            selection_color = look.chosen,
            placeholder = "In this folder",
            focused = function() return filtering.value and not path_bar.editing.value end,
            text = function() return browser.filter.value end,
            on_change = function(text: string) browser.filter.value = text end,
            on_submit = open_chosen,
        },
    },
    pill(
        function() return browser.notice.value ~= nil end,
        g.text {
            text = function() return if browser.notice.value then browser.notice.value.text else "" end,
            max_width = function() return math.max(120, foot_room() - 200) end,
            ellipsize = "middle",
            color = look.text,
            font = look.expressive,
            size = look.font_label,
        },
        g.box {
            present = function() return browser.notice.value ~= nil and browser.notice.value.act ~= nil end,
            direction = "row",
            align = "center",
            gap = 8,
            ui.choice { id = "notice-no", label = "Cancel", on_click = function() browser.say(nil) end },
            ui.choice {
                id = "notice-yes",
                label = "Run",
                primary = true,
                on_click = function()
                    local n = g.untracked(function() return browser.notice.value end)
                    if n and n.act then n.act() end
                end,
            },
        }
    ),
    pill(
        function()
            local name = said()
            return name ~= "" and browser.notice.value == nil and not filtering.value
        end,
        g.text {
            text = function() return (said()) end,
            max_width = function() return math.max(100, foot_room() - 260) end,
            ellipsize = "middle",
            color = look.text,
            font = look.expressive,
            size = look.font_label,
        },
        g.text {
            text = function()
                local _, figures = said()
                return figures
            end,
            color = look.text_muted,
            font = look.technical,
            size = look.font_meta,
            tabular = true,
        }
    ),
}

-- Where what is stood on is drawn in the window, while it is in view.
local function stood_at(): any
    local i = browser.index.value
    if i == nil then return nil end
    local r = if config.get("view") == "grid" then grid.rect(i) else list.rect(i, width())
    if r.y + r.h < 0 or r.y > height() then return nil end
    return { x = left() + r.x, y = top + r.y, w = r.w, h = r.h }
end

local preview_pane = preview.new {
    pinned = preview_pinned,
    open = function() return peeking.value end,
    width = function() return math.min(preview.WIDTH, area.value.w - E * 2) end,
    -- Floating, on the side the entry is not: what is stood on stays seen.
    x = function()
        local right = area.value.w - E - math.min(preview.WIDTH, area.value.w - E * 2)
        if preview_pinned() then return right end
        local o = stood_at()
        return if o and o.x + o.w / 2 > area.value.w / 2 then E else right
    end,
    y = function() return top end,
    height = height,
    origin = stood_at,
}

-- A press beside the floating places puts them away.
local outside = g.box {
    overlay = true,
    attach = "corner",
    present = function() return floating.value end,
    offset_y = top - GAP / 2,
    width = function() return area.value.w end,
    height = function() return area.value.h end,
    on_press = function() end,
    on_click = function() floating.value = false end,
}

-- ---- From outside -------------------------------------------------------------------

g.ipc("rizoma", {
    open = function(...: string): string
        local path = table.concat({ ... }, " ")
        browser.go(if path == "" then "~" else path)
        return "ok"
    end,
    -- The folder around a path, standing on it.
    select = function(...: string): string
        local path = paths.expand(table.concat({ ... }, " "))
        browser.go(paths.parent(path) or "/", path)
        browser.cursor.value = path
        return "ok"
    end,
    here = function(): string return g.untracked(function() return browser.here.value end) end,
    back = function(): string browser.back() return "ok" end,
    forward = function(): string browser.forward() return "ok" end,
    up = function(): string browser.up() return "ok" end,
    stand = function(place: string): string browser.stand(tonumber(place) or 1) return "ok" end,
    activate = function(): string open_chosen() return "ok" end,
    set = function(name: string, value: string): string
        local v: any = value
        if value == "true" or value == "false" then v = value == "true" elseif tonumber(value) then v = tonumber(value) end
        config.set(name, v)
        return "ok"
    end,
    key = function(name: string, ctrl: string?): string
        key(name, if #name == 1 then name else nil, { ctrl = ctrl == "ctrl", alt = ctrl == "alt", shift = false, logo = false })
        return "ok"
    end,
})

return g.window {
    title = function() return paths.name(browser.here.value) end,
    app_id = "dev.akusen.rizoma",
    width = 1100,
    height = 700,
    min = { 420, 320 },
    on_close = function() g.quit() end,
    g.capsule {
        grow = 1,
        radius = 0,
        blur = true,
        -- Opaque: how much of the desktop shows through a window is the
        -- compositor's to say, as for any other.
        fill = look.background,
        rim_top = look.CLEAR,
        rim_bottom = look.CLEAR,
        catch = true,
        on_key = key,
        on_size = function(w: number, h: number) area.value = { w = w, h = h } end,
        content,
        header,
        preview_pane,
        foot,
        outside,
        sidebar.new {
            pinned = pinned,
            open = function() return floating.value end,
            top = function() return top end,
            height = function() return area.value.h end,
        },
        view_cell.new(function() return area.value end),
    },
}
