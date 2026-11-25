--!strict
-- Rizoma, a file manager (docs/plan.md). What changes a file is asked of
-- core/operations, and nowhere else.
--
--   genoma Rizoma/genoma                   (RIZOMA_FOLDER: where it opens)
--   genoma ipc rizoma open <folder>        (GENOMA_IPC names the socket)
local g = require("@genoma")
local bin = require("core/bin")
local browser = require("core/browser")
local colours = require("core/colours")
local config = require("core/config")
local exchange = require("core/exchange")
local operations = require("core/operations")
local format = require("core/format")
local paths = require("core/paths")
local selection = require("core/selection")
local files = require("@genoma/files")
local mime = require("@genoma/mime")
local look = require("ui/look")
local ui = require("ui/controls")
local path_bar = require("ui/path_bar")
local sidebar = require("ui/sidebar")
local grid = require("ui/grid")
local list = require("ui/list")
local actions = require("ui/actions")
local drag_picture = require("ui/drag_picture")
local foot_field = require("ui/foot_field")
local jobs_cell = require("ui/jobs_cell")
local menu = require("ui/menu")
local rename = require("ui/rename")
local swatches = require("ui/swatches")
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

-- Whether the keys are the field's: until one of what was found is chosen, and
-- again as soon as something is typed.
local looking = g.signal(true)
local function filter(text: string)
    browser.filter.value = text
    looking.value = true
    if text ~= "" then filtering.value = true end
end
local function stop_filtering()
    filtering.value = false
    g.batch(function()
        browser.filter.value = ""
        browser.only.value = ""
    end)
end
g.watch(function() return filtering.value end, function(on: boolean) if on then looking.value = true end end)
-- Another folder is another search.
g.watch(function() return browser.here.value end, function() filtering.value = false end)
-- The best guess stands ready for Return, until one is chosen instead: as more
-- is found it stays the first.
local guessed: string? = nil
g.watch(function() return browser.filter.value .. "\0" .. browser.dir.count end, function()
    if g.untracked(function() return browser.filter.value end) == "" then return end
    local at = g.untracked(function() return browser.cursor.value end)
    local shown = g.untracked(function() return browser.index.value end)
    if shown == nil or at == guessed then
        local first = g.untracked(function() return browser.dir:at(1) end)
        guessed = if first then first.path else nil
        browser.stand(1)
    end
end)
g.watch(function() return browser.cursor.value end, function(at: string?)
    if at ~= nil and at ~= guessed then looking.value = false end
end)

-- ---- A new folder -------------------------------------------------------------------

local naming = g.signal(false)
local new_name = g.signal("")
local function new_folder()
    if g.untracked(browser.in_trash) then return end
    stop_filtering()
    new_name.value = operations.free_name("New folder")
    naming.value = true
end
actions.new_folder = new_folder
local function make_folder()
    local name = g.untracked(function() return new_name.value end)
    if files:check_name(name) then return end
    operations.make_folder(name, function() naming.value = false end)
end
g.watch(function() return browser.here.value end, function() naming.value = false end)
g.watch(function() return filtering.value end, function(on: boolean) if on then naming.value = false end end)

-- ---- Keys ---------------------------------------------------------------------------

local function open_chosen()
    if g.untracked(browser.in_trash) then
        operations.restore(selection.list())
        return
    end
    if g.untracked(selection.count) > 1 then
        browser.open_all(g.untracked(function() return selection.entries(1000) end))
        return
    end
    local e = g.untracked(browser.selected)
    if e then browser.open(e) end
end

-- Return: what is asked is answered yes; else what is chosen opens.
local function enter()
    local notice = g.untracked(function() return browser.notice.value end)
    if notice and notice.act and not notice.passing then notice.act() else open_chosen() end
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

-- The keys that walk: with shift the selection reaches to where they come,
-- with ctrl it stays as it is.
local function moved(name: string, mods: any, aside: boolean): boolean
    local how: browser.How = if mods.shift then "extend" elseif mods.ctrl then "keep" else "only"
    if name == "Down" then browser.move(across(), how)
    elseif name == "Up" then browser.move(-across(), how)
    elseif name == "Next" then browser.move(page(), how)
    elseif name == "Prior" then browser.move(-page(), how)
    elseif not aside then return false
    elseif name == "Left" then browser.move(-1, how)
    elseif name == "Right" then browser.move(1, how)
    elseif name == "Home" then browser.stand(1, how)
    elseif name == "End" then browser.stand(g.untracked(function() return browser.dir.count end), how)
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
    if g.untracked(function() return naming.value end) then
        naming.value = false
    elseif g.untracked(function() return jobs_cell.open.value end) and g.untracked(jobs_cell.quiet) then
        jobs_cell.open.value = false
    elseif g.untracked(function() return view_cell.open.value end) then
        view_cell.open.value = false
    elseif g.untracked(function() return peeking.value end) then
        peeking.value = false
    elseif g.untracked(function() return floating.value end) then
        floating.value = false
    elseif g.untracked(function() return browser.notice.value end) ~= nil then
        browser.say(nil)
    elseif g.untracked(function() return filtering.value or browser.looking() end) then
        stop_filtering()
    else
        browser.leave()
    end
end

-- Every key the window is given; while a field has them, those it leaves
-- (Escape, the arrows up and down, the commands).
local function key(name: string, text: string?, mods: any)
    if mods.logo then return end
    if g.untracked(menu.is_open) then
        menu.key(name)
        return
    end
    if g.untracked(function() return operations.renaming.value end) ~= nil then
        if name == "Escape" then operations.stop_renaming() end
        return
    end
    if g.untracked(function() return path_bar.editing.value end) then
        path_bar.key(name)
        return
    end
    if g.untracked(function() return naming.value end) and name ~= "Escape" then return end
    if mods.ctrl then
        local letter = string.lower(name)
        if letter == "h" then toggle("hidden")
        elseif letter == "l" then path_bar.editing.value = true
        elseif letter == "f" then
            filtering.value = true
            looking.value = true
        elseif letter == "r" then browser.dir:reload()
        elseif name == "1" then config.set("view", "grid")
        elseif name == "2" then config.set("view", "list")
        elseif letter == "a" then selection.all()
        elseif letter == "i" and mods.shift then selection.invert()
        elseif letter == "c" then exchange.copy()
        elseif letter == "x" then exchange.cut()
        elseif letter == "v" then operations.paste()
        elseif letter == "z" then operations.undo_last()
        elseif letter == "n" and mods.shift then new_folder()
        elseif name == "space" then
            local at = g.untracked(function() return browser.cursor.value end)
            if at then selection.toggle(at) end
        else moved(name, mods, true)
        end
        return
    end
    if mods.alt then
        if name == "Left" then browser.back()
        elseif name == "Right" then browser.forward()
        elseif name == "Up" then browser.up()
        elseif name == "Down" then open_chosen()
        elseif name == "Home" then browser.go("~")
        elseif string.match(name, "^[0-9]$") then
            -- Alt and a figure: that colour; 0, none.
            local c = colours.list[tonumber(name) :: number]
            if c or name == "0" then operations.colour(selection.list(), if c then c.key else nil) end
        end
        return
    end
    if moved(name, mods, true) then return end
    if name == "Return" or name == "KP_Enter" then
        enter()
    elseif name == "BackSpace" then
        local typed = g.untracked(function() return browser.filter.value end)
        if typed ~= "" then
            -- Back to what was typed, one letter shorter.
            local last = utf8.offset(typed, -1) or #typed
            filter(string.sub(typed, 1, last - 1))
        elseif g.untracked(function() return filtering.value end) then stop_filtering()
        else browser.up() end
    elseif name == "Escape" then escape()
    elseif name == "F2" then
        local e = g.untracked(browser.selected)
        if e and g.untracked(selection.count) < 2 then operations.rename(e) end
    elseif name == "Delete" or name == "KP_Delete" then
        local list = selection.list()
        if mods.shift or g.untracked(browser.in_trash) then operations.delete(list) else operations.throw(list) end
    elseif name == "F4" then
        browser.terminal(g.untracked(function() return browser.here.value end))
    elseif name == "Menu" or (name == "F10" and mods.shift) then
        local e = g.untracked(browser.selected)
        if e then actions.on_entry(e, true) else actions.on_ground(true) end
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
    if browser.in_trash() and browser.filter.value == "" then return "The trash is empty" end
    if browser.looking() then
        if browser.dir.searching then return "Looking in the folders below" end
        return if browser.only.value ~= "" then "Nothing of that colour" else "Nothing by that name"
    end
    if browser.dir.total > 0 then return "Only hidden files" end
    return "Nothing here"
end

local content = g.box(exchange.target({
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
        if button == 272 then browser.leave()
        elseif button == 273 then
            browser.leave()
            actions.on_ground()
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
}, function() return browser.here.value end))

-- ---- Above it -----------------------------------------------------------------------

local function places_button_shown(): boolean return not pinned() end
local function bar_x(): number return left() + (if places_button_shown() then H + 8 else 0) end
local NAV = look.action_height
local nav_w = NAV * 3 + 6 * 2
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
        gap = 6,
        ui.action { id = "back", name = "Back", glyph = "chevron-left", disabled = function() return not browser.can_back() end, on_click = browser.back },
        ui.action { id = "forward", name = "Forward", glyph = "chevron-right", disabled = function() return not browser.can_forward() end, on_click = browser.forward },
        ui.action { id = "up", name = "Up", glyph = "chevron-up", disabled = function() return not browser.can_up() end, on_click = browser.up },
    },
    path_bar.new(function() return math.max(120, area.value.w - path_x() - E) end),
}

-- ---- Below it: what is stood on, what has to be said, the filter --------------------

-- The foot: on the left what does something, then what there is to say; on
-- the right the cell that says how folders are shown.
local FIELD = 240
-- Beside the field, the colours: one pressed shows only what is marked so.
local COLOURS = swatches.width(#colours.list) + 24
local function colours_shown(): boolean
    return filtering.value and not browser.in_trash() and width() > 520
end
-- What the cells on the right take.
local function right_w(): number return if jobs_cell.there.value then H * 2 + 8 else H end
-- A question needs the room its answers take.
local function asking(): boolean return browser.notice.value ~= nil and browser.notice.value.act ~= nil and not browser.notice.value.passing end
local function wordless(): boolean
    return width() < (if asking() then 1040 else 760) + (if filtering.value then COLOURS + 60 else 0)
end
local function button_w(label: string): number return foot_field.width(label, wordless()) end
local function field_w(): number
    return math.min(FIELD, math.max(120, width() - right_w() - GAP * 2 - (look.action_height + 8) * 2))
end
local function foot_room(): number
    local used = (if filtering.value then field_w() else button_w("Filter")) + 8 + (if colours_shown() then COLOURS + 8 else 0) + button_w("Preview") + 8
        + (if browser.in_trash() then button_w("Put back") + 8 + button_w("Empty")
            elseif naming.value then field_w() else button_w("New folder")) + GAP
    return math.max(120, width() - right_w() - GAP - used)
end

-- FILTER and NEW FOLDER, which become the fields they open.
local filter_button = foot_field.new {
    id = "filter",
    label = "Filter",
    glyph = "search",
    open = function() return filtering.value end,
    on_open = function() filtering.value = true end,
    bare = wordless,
    room = field_w,
    placeholder = "Here and below",
    stop = "Stop filtering",
    focused = function() return looking.value and not path_bar.editing.value and operations.renaming.value == nil and not menu.is_open() end,
    on_take = function() looking.value = true end,
    text = function() return browser.filter.value end,
    on_change = function(text: string) browser.filter.value = text end,
    on_submit = enter,
    on_stop = stop_filtering,
}
local colour_filter = g.capsule {
    id = "colours",
    role = "group",
    name = "Colours",
    width = function() return if colours_shown() then COLOURS else 0 end,
    present = colours_shown,
    height = look.action_height,
    radius = look.action_height / 2,
    direction = "row",
    align = "center",
    justify = "center",
    fill = look.glass,
    rim_top = look.node,
    rim_bottom = look.node,
    on_press = function() end,
    on_click = function() end,
    swatches.new {
        id = "only",
        chosen = function() return browser.only.value end,
        on_pick = function(key: string?)
            local was = g.untracked(function() return browser.only.value end)
            browser.only.value = if key == nil or key == was then "" else key
        end,
    },
}
local naming_button = foot_field.new {
    id = "new-folder",
    label = "New folder",
    glyph = "plus",
    dashed = true,
    open = function() return naming.value end,
    on_open = new_folder,
    bare = wordless,
    room = field_w,
    placeholder = "Its name",
    stop = "No new folder",
    select = "all",
    focused = function() return not path_bar.editing.value and operations.renaming.value == nil and not menu.is_open() end,
    wrong = function() return files:check_name(new_name.value) ~= nil end,
    text = function() return new_name.value end,
    on_change = function(text: string) new_name.value = text end,
    on_submit = function() make_folder() end,
    on_stop = function() naming.value = false end,
}

local function said(): (string, string)
    local n = selection.count()
    if n < 2 and browser.looking() and (browser.dir.searching or browser.dir.capped) then
        local found = browser.dir.count
        return if browser.dir.searching then "Looking in the folders below" else "The first of many", if found > 0 then `{found} found` else ""
    end
    if n > 1 and not (preview_pinned() or peeking.value) then
        local sum = selection.sum.value
        return `{n} selected`, if sum.bytes and sum.files > 0 then format.size(sum.bytes) else ""
    end
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

local function notice_button(kind: string, passing: boolean): any
    return ui.action {
        id = "notice-yes-" .. kind,
        name = "Do it",
        kind = kind,
        present = function()
            local n = browser.notice.value
            return n ~= nil and (n.passing == true) == passing
        end,
        label = function() return if browser.notice.value then browser.notice.value.label or "" else "" end,
        on_click = function()
            local n = g.untracked(function() return browser.notice.value end)
            if n and n.act then n.act() end
        end,
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
    g.box {
        direction = "row",
        align = "center",
        gap = 8,
        filter_button,
        colour_filter,
        ui.action {
            id = "preview-button",
            label = "Preview",
            glyph = "preview",
            bare = wordless,
            lit = function() return preview_pinned() or peeking.value end,
            on_click = toggle_preview,
        },
        g.box { present = function() return not browser.in_trash() end, naming_button },
        ui.action {
            id = "restore",
            label = "Put back",
            glyph = "restore",
            bare = wordless,
            present = browser.in_trash,
            disabled = function() return selection.count() == 0 end,
            on_click = function() operations.restore(selection.list()) end,
        },
        ui.action {
            id = "empty",
            label = "Empty",
            glyph = "trash",
            bare = wordless,
            present = browser.in_trash,
            disabled = function() return bin.count() == 0 end,
            on_click = operations.empty,
        },
    },
    pill(
        function() return browser.notice.value ~= nil end,
        g.text {
            text = function() return if browser.notice.value then browser.notice.value.text else "" end,
            max_width = function() return math.max(60, foot_room() - (if asking() then 218 elseif browser.notice.value and browser.notice.value.act then 140 else 40)) end,
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
            ui.action {
                id = "notice-no",
                label = "Cancel",
                present = asking,
                on_click = function() browser.say(nil) end,
            },
            -- What is asked stands out, and Return is it; what is only offered
            -- does not.
            notice_button("filled", false),
            notice_button("outline", true),
        }
    ),
    pill(
        function()
            local name = said()
            return name ~= "" and browser.notice.value == nil and foot_room() > 180
        end,
        g.text {
            text = function() return (said()) end,
            max_width = function()
                local _, figures = said()
                local w = if foot_room() > 380 and figures ~= ""
                    then g.text_width { text = figures, font = look.technical(), size = look.font_meta } + 16 else 0
                return math.max(100, foot_room() - 40 - w)
            end,
            ellipsize = "middle",
            color = look.text,
            font = look.expressive,
            size = look.font_label,
        },
        g.text {
            present = function() return foot_room() > 380 end,
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
local function named_at(): any
    local r = operations.renaming.value
    local i = if r then browser.dir:index(r.path) else nil
    if i == nil then return nil end
    local n = if config.get("view") == "grid" then grid.name_rect(i) else list.name_rect(i, width())
    if n == nil then return nil end
    n.x += left()
    n.y += top
    return n
end

local function stood_at(): any
    local i = browser.index.value
    if i == nil then return nil end
    local r = if config.get("view") == "grid" then grid.rect(i) else list.rect(i, width())
    if r.y + r.h < 0 or r.y > height() then return nil end
    return { x = left() + r.x, y = top + r.y, w = r.w, h = r.h }
end

-- The menu, asked for by key, at what is stood on.
actions.at = function(items: any)
    local at = g.untracked(stood_at)
    if at then
        menu.open(items, at.x + at.w / 2, at.y + at.h / 2)
    else
        menu.open(items, g.untracked(left) + 24, top + 24)
    end
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
        selection.only(path)
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
    find = function(...: string): string filter(table.concat({ ... }, " ")) return "ok" end,
    only = function(key: string?): string
        filtering.value = true
        browser.only.value = key or ""
        return "ok"
    end,
    count = function(): string return tostring(g.untracked(function() return browser.dir.count end)) end,
    searching = function(): string return tostring(g.untracked(function() return browser.dir.searching end)) end,
    key = function(name: string, ctrl: string?): string
        key(name, if #name == 1 then name else nil, { ctrl = ctrl == "ctrl", alt = ctrl == "alt", shift = ctrl == "shift", logo = false })
        return "ok"
    end,
})

local window = g.window {
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
        preview_pane,
        foot,
        header,
        outside,
        sidebar.new {
            pinned = pinned,
            open = function() return floating.value end,
            top = function() return top end,
            height = function() return area.value.h end,
        },
        rename.new {
            at = named_at,
            area = function() return area.value end,
            left = left,
        },
        jobs_cell.new(function() return area.value end),
        view_cell.new(function() return area.value end),
        menu.new(function() return area.value end),
    },
}

-- A Genoma without it drags blind.
return if g.drag_picture then { window, drag_picture.new() } else window
