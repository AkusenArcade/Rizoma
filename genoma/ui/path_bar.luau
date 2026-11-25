--!strict
-- Where one is, as a rhizome: each folder a capsule, each thread the way
-- from one to the next. Going into a folder grows a shoot from the last
-- capsule; coming out, it goes back into it. Ctrl+L makes it a field.
local g = require("@genoma")
local browser = require("core/browser")
local paths = require("core/paths")
local look = require("ui/look")
local ui = require("ui/controls")

local M = {}

local H, PAD, THREAD, NAME_MAX = 32, 14, 14, 220

M.editing = g.signal(false)

type Shoot = { name: string, path: string, leaving: boolean, grown: boolean }

local function shoots(steps: { paths.Step }, grown: boolean): { Shoot }
    local out: { Shoot } = {}
    for _, s in steps do table.insert(out, { name = s.name, path = s.path, leaving = false, grown = grown }) end
    return out
end

local chain = g.signal(shoots(paths.steps(g.untracked(function() return browser.here.value end)), true))
local clearing: any = nil

local function alive(list: { Shoot }): { Shoot }
    local out: { Shoot } = {}
    for _, s in list do
        if not s.leaving then table.insert(out, s) end
    end
    return out
end

-- The new path beside the old one: what they share stays, what was added
-- grows, and what one came out of retracts before it goes. Elsewhere
-- entirely, the old way is simply no longer there.
g.watch(function() return browser.here.value end, function(path: string)
    if clearing then clearing:stop() end
    clearing = nil
    local before = alive(g.untracked(function() return chain.value end))
    local after = shoots(paths.steps(path), false)
    local shared = 0
    while shared < #before and shared < #after and before[shared + 1].path == after[shared + 1].path do
        shared += 1
        after[shared].grown = true
    end
    if shared == #after and #before > shared then
        for i = shared + 1, #before do
            local s = table.clone(before[i])
            s.leaving = true
            table.insert(after, s)
        end
        clearing = g.after(look.CLOSE, function()
            clearing = nil
            chain.value = alive(g.untracked(function() return chain.value end))
        end)
    end
    chain.value = after
end)

local function name_width(name: string, current: boolean): number
    local w = g.text_width { text = name, font = look.expressive(), size = look.font_secondary, weight = if current then 600 else 400 }
    return math.min(math.ceil(w) + 1, NAME_MAX)
end
local function width_of(s: { name: string }): number
    -- As wide as it is when it is the current one: nothing beside it moves
    -- when it becomes it.
    return name_width(s.name, true) + PAD * 2
end

local function row(shoot: () -> any, place: () -> number, last: () -> string): any
    -- The shoot of a folder just gone into starts as nothing and opens.
    local grown = g.signal(g.untracked(shoot).grown)
    if not g.untracked(function() return grown.value end) then
        g.after(0, function() grown.value = true end)
    end
    local over = g.signal(false)
    local function out(): boolean return grown.value and not shoot().leaving end
    local function current(): boolean return shoot().path == last() end
    local function thread(): number return if place() > 1 then THREAD else 0 end
    local function timing(): string return if out() then "shoot_open" else "shoot_close" end
    return g.box {
        direction = "row",
        align = "center",
        g.capsule {
            width = function() return if out() then thread() else 0 end,
            height = look.thread,
            crisp = true,
            radius = 0,
            fill = look.line,
            rim_top = look.CLEAR,
            rim_bottom = look.CLEAR,
            transition = { width = timing },
        },
        g.capsule {
            role = "button",
            width = function() return if out() then width_of(shoot()) else 0 end,
            height = H,
            radius = H / 2,
            clip = true,
            align = "center",
            justify = "center",
            fill = function()
                if current() then return look.glass() end
                return if over.value then look.hovered() else look.CLEAR
            end,
            rim_top = function() return if current() then look.rim() elseif over.value then look.node() else look.line() end,
            rim_bottom = look.line,
            opacity = function() return if out() then 1 else 0 end,
            transition = { width = timing, opacity = timing, fill = "ui_change", rim_top = "ui_change" },
            on_hover = function(on: boolean) over.value = on end,
            on_press = function() end,
            on_click = function(button: number)
                if button ~= 272 then return end
                local s = g.untracked(shoot)
                if s.leaving then return end
                if s.path == g.untracked(last) then
                    M.editing.value = true
                    return
                end
                -- Standing on the folder the way leads into.
                local steps = paths.steps(g.untracked(function() return browser.here.value end))
                local came: string? = nil
                for i, step in steps do
                    if step.path == s.path and steps[i + 1] then came = steps[i + 1].path end
                end
                browser.go(s.path, came)
            end,
            g.text {
                text = function() return shoot().name end,
                max_width = NAME_MAX,
                ellipsize = "middle",
                color = function() return if current() or over.value then look.text() else look.text_muted() end,
                font = look.expressive,
                size = look.font_secondary,
                weight = function() return if current() then 600 else 400 end,
                opacity = function() return if out() then 1 else 0 end,
                transition = { color = "ui_change", opacity = function() return if out() then "content_in" else "content_out" end },
            },
        },
    }
end

-- `room()`: how wide it may be. A deep path keeps where it starts and as
-- many of its last steps as fit; those between are one "…".
function M.new(room: () -> number): any
    local shown = g.computed(function(): { Shoot }
        local list = chain.value
        local all = 0
        for i, s in list do all += width_of(s) + (if i > 1 then THREAD else 0) end
        if all <= room() or #list < 3 then return list end
        local more = width_of { name = "…" } + THREAD
        local used = width_of(list[1]) + more
        local from = #list + 1
        while from > 3 do
            local w = width_of(list[from - 1]) + THREAD
            if used + w > room() and from <= #list then break end
            used += w
            from -= 1
        end
        local out = { list[1], { name = "…", path = list[from - 1].path, leaving = false, grown = true } }
        for i = from, #list do table.insert(out, list[i]) end
        return out
    end)
    local function last(): string
        local list = alive(chain.value)
        return if #list > 0 then list[#list].path else ""
    end

    local typed = g.signal("")
    local wrong = g.signal(false)
    g.watch(function() return M.editing.value end, function(on: boolean)
        if on then
            wrong.value = false
            local here = g.untracked(function() return browser.here.value end)
            typed.value = if here == "/" then "/" else here .. "/"
        end
    end)

    return g.box {
        height = look.cell_height,
        direction = "row",
        align = "center",
        g.each {
            present = function() return not M.editing.value end,
            direction = "row",
            align = "center",
            gap = 0,
            items = function() return shown.value end,
            key = function(s) return if s.name == "…" then "…" else s.path end,
            row = function(s, place) return row(s, place, last) end,
        },
        g.capsule {
            present = function() return M.editing.value end,
            width = room,
            height = look.cell_height,
            radius = look.cell_height / 2,
            padding_x = 18,
            direction = "row",
            align = "center",
            fill = look.glass,
            rim_top = look.primary,
            rim_bottom = look.primary,
            g.field {
                id = "path-field",
                grow = 1,
                size = look.font_secondary,
                font = look.expressive,
                color = look.text,
                caret_color = look.primary,
                selection_color = look.chosen,
                placeholder = "A folder's path",
                focused = function() return M.editing.value end,
                text = function() return typed.value end,
                on_change = function(text: string) typed.value = text end,
                on_submit = function(text: string)
                    M.editing.value = false
                    local path = string.match(text, "^%s*(.-)%s*$") or ""
                    if path == "" then return end
                    if string.sub(path, 1, 1) ~= "/" and string.sub(path, 1, 1) ~= "~" then
                        path = g.untracked(function() return browser.here.value end) .. "/" .. path
                    end
                    browser.go(path)
                end,
            },
        },
    }
end

return M
