--!strict
-- "Compress…": a cell that grows from what is compressed, as Nautilus's
-- dialog asks the same: the archive's name, its kind (.zip, a zip locked by
-- a password, .tar.xz, .7z) and, locked, the password. Return or COMPRESS
-- makes it, a job in the jobs cell like a copy; Escape or a press beside it
-- does not.
local g = require("@genoma")
local files = require("@genoma/files")
local archives = require("core/archives")
local browser = require("core/browser")
local look = require("ui/look")
local ui = require("ui/controls")

local M = {}

local WIDTH, PAD, FIELD = 460, 22, 34

type Shown = { list: { string }, folder: string, key: number }
local shown = g.signal(nil :: Shown?)
local grown = g.signal(false)
local from = g.signal({ x = 0, y = 0, w = 40, h = 40 })
local name = g.signal("")
local kind = g.signal("zip")
local password = g.signal("")
-- Which field has the keys: the name's or the password's.
local typing = g.signal("name")
local going: any = nil
local count = 0

function M.is_open(): boolean return shown.value ~= nil and grown.value end

function M.close()
    if not g.untracked(function() return grown.value end) then return end
    grown.value = false
    if going then going:stop() end
    going = g.after(look.CLOSE, function()
        going = nil
        shown.value = nil
        password.value = ""
    end)
end

-- `entries`: what is compressed, as the browser has them; `origin`: where
-- they are drawn, { x, y, w, h }.
function M.open(entries: { any }, origin: any)
    if #entries == 0 then return end
    if going then going:stop() end
    going = nil
    count += 1
    local list: { string } = {}
    for _, e in entries do table.insert(list, e.path) end
    g.batch(function()
        from.value = origin
        grown.value = false
        name.value = archives.proposed(entries)
        password.value = ""
        typing.value = "name"
        shown.value = { list = list, folder = g.untracked(function() return browser.here.value end), key = count }
    end)
    g.after(0, function() grown.value = true end)
end

local function chosen(): archives.Kind return archives.kind(kind.value) end

-- What is wrong with it, or "".
local function problem(): string
    local s = shown.value
    if s == nil then return "" end
    local n = string.match(name.value, "^%s*(.-)%s*$") or ""
    if n == "" then return "The archive needs a name." end
    local full = n .. chosen().ending
    local wrong = files:check_name(full)
    if wrong then return wrong end
    if browser.dir:index(s.folder .. "/" .. full) then return `{full} is already here.` end
    if chosen().locks and password.value == "" then return "A locked zip needs a password." end
    return ""
end

-- Made, and put away.
function M.submit()
    local s = g.untracked(function() return shown.value end)
    if s == nil or g.untracked(problem) ~= "" then return end
    local n = string.match(g.untracked(function() return name.value end), "^%s*(.-)%s*$") or ""
    archives.compress(s.list, s.folder, n, g.untracked(function() return kind.value end), g.untracked(function() return password.value end))
    M.close()
end

-- The keys while it is open: Return makes it, Escape puts it away, Tab goes
-- from the name to the password.
function M.key(name_: string)
    if name_ == "Escape" then
        M.close()
    elseif name_ == "Return" or name_ == "KP_Enter" then
        M.submit()
    elseif (name_ == "Tab" or name_ == "ISO_Left_Tab") and g.untracked(chosen).locks then
        typing.value = if g.untracked(function() return typing.value end) == "name" then "password" else "name"
    end
end

local function field(t: { [string]: any }): any
    local function on(): boolean return typing.value == t.which end
    local function edge(): string return if on() then look.primary() else look.node() end
    return g.capsule {
        height = FIELD,
        direction = "row",
        align = "center",
        gap = 6,
        padding_x = 14,
        radius = look.round(FIELD / 2),
        fill = look.glass,
        rim_top = edge,
        rim_bottom = edge,
        transition = { rim_top = "ui_change", rim_bottom = "ui_change" },
        on_press = function() typing.value = t.which end,
        on_click = function() end,
        g.field {
            id = "compress-" .. t.which,
            grow = 1,
            size = look.font_label,
            font = look.expressive,
            color = look.text,
            caret_color = look.primary,
            selection_color = look.chosen,
            placeholder = t.placeholder,
            secret = t.secret,
            select = t.select or "none",
            focused = function() return M.is_open() and on() end,
            on_press = function() typing.value = t.which end,
            text = t.text,
            on_change = t.on_change,
            on_submit = function() M.submit() end,
        },
        t.after,
    }
end

local function page(s: Shown): any
    local function title(): string
        local list = s.list
        if #list == 1 then
            return "Compress " .. (string.match(list[1], "([^/]+)$") or list[1])
        end
        return `Compress {#list} items`
    end
    return g.box {
        direction = "column",
        align = "stretch",
        gap = look.gap,
        padding = PAD,
        ui.label(title),
        field {
            which = "name",
            placeholder = "The archive's name",
            select = "all",
            text = function() return name.value end,
            on_change = function(text: string) name.value = text end,
            after = g.text {
                text = function() return chosen().ending end,
                color = look.text_faint,
                font = look.expressive,
                size = look.font_label,
            },
        },
        ui.segmented {
            id = "compress-kind",
            options = (function()
                local out = {}
                for _, k in archives.KINDS do table.insert(out, { key = k.key, label = k.label }) end
                return out
            end)(),
            current = function() return kind.value end,
            on_choose = function(key: string)
                kind.value = key
                typing.value = if archives.kind(key).locks then "password" else "name"
            end,
        },
        g.text {
            text = function() return chosen().says end,
            max_width = WIDTH - PAD * 2,
            wrap = true,
            color = look.text_muted,
            font = look.expressive,
            size = look.font_secondary,
        },
        g.box {
            present = function() return chosen().locks end,
            direction = "column",
            align = "stretch",
            field {
                which = "password",
                placeholder = "Password",
                secret = true,
                text = function() return password.value end,
                on_change = function(text: string) password.value = text end,
            },
        },
        g.text {
            present = function() return problem() ~= "" and name.value ~= "" end,
            text = problem,
            max_width = WIDTH - PAD * 2,
            wrap = true,
            color = look.alert,
            font = look.expressive,
            size = look.font_secondary,
        },
        g.box {
            direction = "row",
            justify = "end",
            gap = 8,
            ui.action { id = "compress-cancel", label = "Cancel", on_click = M.close },
            ui.action {
                id = "compress-make",
                label = "Compress",
                kind = "filled",
                disabled = function() return problem() ~= "" end,
                on_click = M.submit,
            },
        },
    }
end

-- `area()`: the window's { w, h }.
function M.new(area: () -> { w: number, h: number }): any
    local E = look.margin_edge
    local content_h = g.signal(300)
    local function width(): number return math.min(WIDTH, area().w - E * 2) end
    local function tall(): number return math.min(content_h.value, area().h - E * 2) end
    local function timing(): string return if grown.value then "cell_open" else "cell_close" end
    return g.box {
        overlay = true,
        attach = "corner",
        present = function() return shown.value ~= nil end,
        width = function() return area().w end,
        height = function() return area().h end,
        g.box {
            overlay = true,
            attach = "corner",
            width = function() return area().w end,
            height = function() return area().h end,
            on_press = function() M.close() end,
            on_click = function() end,
        },
        g.capsule {
            id = "compress",
            name = "Compress",
            overlay = true,
            attach = "corner",
            offset_x = function() return if grown.value then (area().w - width()) / 2 else from.value.x end,
            offset_y = function() return if grown.value then (area().h - tall()) / 2 else from.value.y end,
            width = function() return if grown.value then width() else from.value.w end,
            height = function() return if grown.value then tall() else from.value.h end,
            radius = look.round(look.radius_panel),
            opacity = function() return if grown.value then 1 else 0 end,
            clip = true,
            fill = look.glass_over,
            rim_top = look.rim,
            rim_bottom = look.line,
            backdrop_blur = look.glass_blur,
            transition = { offset_x = timing, offset_y = timing, width = timing, height = timing, opacity = timing },
            on_press = function() end,
            on_click = function() end,
            g.box {
                overlay = true,
                attach = "corner",
                width = width,
                opacity = function() return if grown.value then 1 else 0 end,
                transition = { opacity = function() return if grown.value then "content_in" else "content_out" end },
                on_size = function(_: number, h: number) if h > 40 then content_h.value = h end end,
                g.each {
                    direction = "column",
                    align = "stretch",
                    items = function(): { Shown } return if shown.value then { shown.value } else {} end,
                    key = function(s: Shown) return s.key end,
                    row = function(s, _) return page(g.untracked(s)) end,
                },
            },
        },
    }
end

return M
