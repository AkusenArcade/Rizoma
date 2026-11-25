--!strict
-- Where one is, as a rhizome: each folder a capsule, each thread the way
-- from one to the next. Going into a folder buds a shoot out of the last
-- capsule, its neck thinning until only the thread is left; coming out, the
-- thread is taken back and the shoot with it. Ctrl+L makes it a field, which
-- says where what is typed may be going.
local g = require("@genoma")
local browser = require("core/browser")
local completion = require("core/completion")
local exchange = require("core/exchange")
local actions = require("ui/actions")
local paths = require("core/paths")
local look = require("ui/look")
local ui = require("ui/controls")

local M = {}

local H, PAD, THREAD, NAME_MAX = 32, 14, 16, 220
local NODE = 4

M.editing = g.signal(false)

-- `turn`: which of those that came together it is, 0 one that was there; which
-- to go, of those leaving.
type Shoot = { name: string, path: string, leaving: boolean, turn: number }

local function shoots(steps: { paths.Step }, turn: number): { Shoot }
    local out: { Shoot } = {}
    for _, s in steps do table.insert(out, { name = s.name, path = s.path, leaving = false, turn = turn }) end
    return out
end

local chain = g.signal(shoots(paths.steps(g.untracked(function() return browser.here.value end)), 0))
local clearing: any = nil

local function alive(list: { Shoot }): { Shoot }
    local out: { Shoot } = {}
    for _, s in list do
        if not s.leaving then table.insert(out, s) end
    end
    return out
end

-- The new path beside the old one: what they share stays, what was added
-- buds, and what one came out of retracts before it goes. Elsewhere
-- entirely, the old way is simply no longer there.
g.watch(function() return browser.here.value end, function(path: string)
    if clearing then clearing:stop() end
    clearing = nil
    local before = alive(g.untracked(function() return chain.value end))
    local after = shoots(paths.steps(path), 0)
    local shared = 0
    while shared < #before and shared < #after and before[shared + 1].path == after[shared + 1].path do
        shared += 1
    end
    for i = shared + 1, #after do after[i].turn = i - shared end
    if shared == #after and #before > shared then
        for i = shared + 1, #before do
            local s = table.clone(before[i])
            s.leaving = true
            s.turn = #before - i + 1
            table.insert(after, s)
        end
        clearing = g.after(look.shoots_back(#before - shared), function()
            clearing = nil
            chain.value = alive(g.untracked(function() return chain.value end))
        end)
    end
    chain.value = after
end)

local function name_width(name: string): number
    -- As wide as it is when it is the current one: nothing beside it moves
    -- when it becomes it.
    local w = g.text_width { text = name, font = look.expressive(), size = look.font_secondary, weight = 600 }
    return math.min(math.ceil(w) + 1, NAME_MAX)
end
local function width_of(s: { name: string }): number return name_width(s.name) + PAD * 2 end

local function pressed(s: Shoot, last: string)
    if s.leaving then return end
    if s.path == last then
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
end

-- One step and, inside it, the next: a shape buds out of the one holding it.
local function step(index: number, shoot: () -> any, list: () -> { Shoot }, last: () -> string): any
    local first = g.untracked(shoot)
    local grown = g.signal(index == 1 or first.turn == 0)
    if not g.untracked(function() return grown.value end) then
        g.after(0, function() grown.value = true end)
    end
    local over = g.signal(false)
    local function out(): boolean return grown.value and not shoot().leaving end
    local function current(): boolean return shoot().path == last() end
    local turn = math.clamp(first.turn, 1, look.TURNS)
    local function back(): number return math.clamp(shoot().turn, 1, look.TURNS) end
    local function shape(): string return if out() then "shoot_" .. turn else "shoot_close_" .. back() end
    local function neck(): string return if out() then "neck_" .. turn else "neck_close_" .. back() end
    local function words(): string return if out() then "shoot_words_" .. turn else "content_out" end
    local function width(): number return width_of(shoot()) end

    local node: { [any]: any } = {
        width = width,
        height = H,
        radius = H / 2,
        fill = look.glass,
        rim_top = function()
            if exchange.welcome(shoot().path) then return look.primary() end
            return if current() then look.rim() elseif over.value then look.node() else look.line()
        end,
        rim_bottom = function() return if exchange.welcome(shoot().path) then look.primary() else look.line() end,
        -- The shape's own, over nothing: what takes the presses is inside.
        g.box(exchange.target({
            overlay = true,
            attach = "corner",
            width = width,
            height = H,
            role = "button",
            align = "center",
            justify = "center",
            opacity = function() return if out() then 1 else 0 end,
            transition = { opacity = words },
            on_hover = function(on: boolean) over.value = on end,
            on_press = function() end,
            on_click = function(button: number)
                if button == 272 then pressed(g.untracked(shoot), g.untracked(last))
                elseif button == 273 and not g.untracked(shoot).leaving then
                    local s = g.untracked(shoot)
                    actions.on_place(s.path, function() pressed(s, g.untracked(last)) end)
                end
            end,
            g.text {
                text = function() return shoot().name end,
                max_width = NAME_MAX,
                ellipsize = "middle",
                color = function() return if current() or over.value then look.text() else look.text_muted() end,
                font = look.expressive,
                size = look.font_secondary,
                weight = function() return if current() then 600 else 400 end,
                transition = { color = "ui_change" },
            },
        }, function() return if shoot().leaving then nil else shoot().path end, true)),
    }
    if index > 1 then
        node.overlay = true
        node.attach = "right"
        node.offset_x = function() return if out() then THREAD else 0 end
        node.growth = function() return if out() then 1 else 0 end
        -- The neck: soft and wide as it leaves, gone once it is out.
        node.bud = function() return if out() then 0 else H end
        node.transition = { offset_x = shape, growth = shape, bud = neck, rim_top = "ui_change" }
        -- The thread that stays once it has parted, taken back first.
        table.insert(node, g.thread {
            overlay = true,
            attach = "corner",
            offset_x = -THREAD,
            offset_y = H / 2 - NODE / 2,
            width = THREAD,
            height = NODE,
            stroke = look.thread,
            crisp = true,
            node = NODE,
            fill = look.line,
            color = look.node,
            from_x = 0,
            to_x = THREAD,
            from_y = NODE / 2,
            to_y = NODE / 2,
            growth = function() return if out() then 1 else 0 end,
            transition = { growth = function() return if out() then "thread_" .. turn else "thread_close_" .. back() end },
        })
    else
        node.transition = { rim_top = "ui_change" }
    end
    table.insert(node, g.each {
        overlay = true,
        attach = "corner",
        width = width,
        height = H,
        items = function(): { Shoot }
            local s = list()[index + 1]
            return if s then { s } else {}
        end,
        key = function(s) return if s.name == "…" then "…" else s.path end,
        row = function(s, _) return step(index + 1, s, list, last) end,
    })
    return g.capsule(node)
end

-- ---- The field ------------------------------------------------------------------------

local ROW = 36

-- A folder's name being offered.
local function offered(item: () -> any, place: () -> number): any
    local over = g.signal(false)
    local function lit(): boolean return completion.at.value == place() end
    return g.capsule {
        role = "button",
        height = ROW,
        padding_x = 12,
        gap = 10,
        direction = "row",
        align = "center",
        justify = "start",
        radius = look.radius_well,
        fill = function()
            if lit() then return look.chosen() end
            return if over.value then look.hovered() else look.CLEAR
        end,
        rim_top = look.CLEAR,
        rim_bottom = look.CLEAR,
        on_hover = function(on: boolean) over.value = on end,
        on_press = function() end,
        on_click = function(button: number)
            if button ~= 272 then return end
            M.editing.value = false
            browser.go(g.untracked(item).path)
        end,
        ui.glyph("folder", 18, lit, look.text_muted),
        g.text {
            text = function() return item().name end,
            max_width = 400,
            ellipsize = "middle",
            color = look.text,
            font = look.expressive,
            size = look.font_name,
            weight = look.weight_name,
        },
        g.box { grow = 1 },
        -- What Tab would take.
        g.box {
            present = function()
                local n = completion.next()
                return n ~= nil and n.path == item().path
            end,
            ui.label("Tab", look.text_faint),
        },
    }
end

-- Keys the field leaves, while it has them.
function M.key(name: string)
    if name == "Escape" then
        M.editing.value = false
    elseif name == "Down" then
        completion.choose(1)
    elseif name == "Up" then
        completion.choose(-1)
    elseif name == "Tab" then
        local n = g.untracked(completion.next)
        if n then completion.typed.value = n.text end
    end
end

g.watch(function() return M.editing.value end, function(on: boolean)
    if not on then return end
    local here = g.untracked(function() return browser.here.value end)
    if here == paths.TRASH then here = paths.home end
    completion.typed.value = if here == "/" then "/" else here .. "/"
    completion.at.value = 0
end)

local function submit(text: string)
    local chosen = g.untracked(completion.chosen)
    M.editing.value = false
    if chosen then
        browser.go(chosen.path)
        return
    end
    local path = string.match(text, "^%s*(.-)%s*$") or ""
    if path == "" then return end
    if string.sub(path, 1, 1) ~= "/" and string.sub(path, 1, 1) ~= "~" then
        path = g.untracked(function() return browser.here.value end) .. "/" .. path
    end
    browser.go(path)
end

-- The folders offered are there while there are any, and until they have gone
-- back; the first frame they are still the field's foot.
local there, grown = g.signal(false), g.signal(false)
do
    local leaving: any = nil
    g.watch(function() return M.editing.value and #completion.list.value > 0 end, function(on: boolean)
        if leaving then leaving:stop() end
        leaving = nil
        if on then
            there.value = true
            g.after(0, function() grown.value = true end)
        else
            grown.value = false
            leaving = g.after(look.CLOSE, function()
                leaving = nil
                there.value = false
            end)
        end
    end)
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
        local out = { list[1], { name = "…", path = list[from - 1].path, leaving = false, turn = 0 } }
        for i = from, #list do table.insert(out, list[i]) end
        return out
    end)
    local function last(): string
        local list = alive(chain.value)
        return if #list > 0 then list[#list].path else ""
    end
    local function open(): boolean return grown.value end
    local function tall(): number return math.max(1, #completion.list.value) * ROW + 16 end
    local function shape(): string return if open() then "cell_open" else "cell_close" end
    local FIELD_PAD = 18
    local function typed_width(): number
        return g.text_width { text = completion.typed.value, font = look.expressive(), size = look.font_label }
    end

    return g.box {
        height = look.cell_height,
        direction = "row",
        align = "center",
        g.each {
            present = function() return not M.editing.value end,
            direction = "row",
            align = "center",
            items = function(): { Shoot } return { shown.value[1] } end,
            key = function(s) return s.path end,
            row = function(s, _) return step(1, s, function() return shown.value end, last) end,
        },
        g.capsule {
            present = function() return M.editing.value end,
            width = room,
            height = look.cell_height,
            radius = look.cell_height / 2,
            padding_x = FIELD_PAD,
            direction = "row",
            align = "center",
            fill = look.glass,
            rim_top = look.primary,
            rim_bottom = look.primary,
            g.field {
                id = "path-field",
                width = function() return room() - FIELD_PAD * 2 end,
                size = look.font_label,
                font = look.expressive,
                color = look.text,
                caret_color = look.primary,
                selection_color = look.chosen,
                placeholder = "A folder's path",
                focused = function() return M.editing.value end,
                text = function() return completion.typed.value end,
                on_change = function(text: string) completion.typed.value = text end,
                on_submit = submit,
            },
            -- Where it may be going, after what is typed.
            g.text {
                overlay = true,
                attach = "corner",
                present = function() return completion.rest() ~= "" and typed_width() + 40 < room() - FIELD_PAD * 2 end,
                offset_x = function() return FIELD_PAD + typed_width() + 2 end,
                offset_y = function()
                    local h = g.text_height { text = "X", font = look.expressive(), size = look.font_label, width = 100 }
                    return (look.cell_height - h) / 2
                end,
                max_width = function() return math.max(20, room() - FIELD_PAD * 2 - typed_width()) end,
                text = completion.rest,
                color = look.text_faint,
                font = look.expressive,
                size = look.font_label,
            },
            -- The folders offered, budding out of the field.
            g.capsule {
                name = "Folders",
                overlay = true,
                attach = "below",
                present = function() return there.value end,
                offset_y = function() return if open() then 8 else 0 end,
                width = room,
                height = tall,
                radius = look.radius_panel,
                growth = function() return if open() then 1 else 0 end,
                bud = function() return if open() then 0 else look.cell_height end,
                fill = look.cell,
                rim_top = look.rim,
                rim_bottom = look.line,
                transition = { offset_y = shape, growth = shape, bud = shape },
                on_press = function() end,
                on_click = function() end,
                g.each {
                    overlay = true,
                    attach = "corner",
                    offset_x = 8,
                    offset_y = 8,
                    width = function() return room() - 16 end,
                    direction = "column",
                    align = "stretch",
                    opacity = function() return if open() then 1 else 0 end,
                    transition = { opacity = function() return if open() then "content_in" else "content_out" end },
                    items = function() return completion.list.value end,
                    key = function(s) return s.path end,
                    row = offered,
                },
            },
        },
    }
end

return M
