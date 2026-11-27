--!strict
-- What is being done to files: a ring at the foot that fills as it goes, and
-- the cell that grows from it. What has to be asked opens it.
local g = require("@genoma")
local files = require("@genoma/files")
local format = require("core/format")
local operations = require("core/operations")
local paths = require("core/paths")
local look = require("ui/look")
local ui = require("ui/controls")
local foot_cell = require("ui/foot_cell")
local view_cell = require("ui/view_cell")

local M = {}

M.open = g.signal(false)

local PAD, WIDTH, BUTTON, RING = 18, 440, foot_cell.BUTTON, 22
-- What its content has, in a window however narrow.
local inner = g.signal(WIDTH - PAD * 2)
local BAR = 3
-- What is over in less than this is not worth a ring.
local SOON = 0.5

type Job = any

local jobs = g.computed(function(): { Job } return files.jobs end)
local function asking(): Job?
    for _, j in jobs.value do
        if j.state == "asking" then return j end
    end
    return nil
end

-- There once something takes a while or asks, until nothing is left.
local there = g.signal(false)
do
    local waiting: any = nil
    g.watch(function() return #jobs.value > 0 end, function(some: boolean)
        if waiting then waiting:stop() end
        waiting = nil
        if some then
            waiting = g.after(SOON, function()
                waiting = nil
                there.value = #g.untracked(function() return jobs.value end) > 0
            end)
        else
            there.value = false
            M.open.value = false
        end
    end)
    g.watch(function()
        local j = asking()
        return if j then j.id else nil
    end, function(id: number?)
        if id == nil then return end
        there.value = true
        M.open.value = true
    end)
end
M.there = there
-- Nothing is asked: it can be put away.
function M.quiet(): boolean return asking() == nil end

-- How far a job is, 0 to 1: by its bytes, or by its files where it only
-- changes names.
local function far(j: Job): number
    if j.total_bytes > 0 then return math.clamp(j.bytes / j.total_bytes, 0, 1) end
    if j.total_files > 0 then return math.clamp(j.files / j.total_files, 0, 1) end
    return 0
end
local function all(): number
    local done, total = 0, 0
    for _, j in jobs.value do
        -- One that has not been counted yet is not known to be small.
        local w = math.max(1, j.total_bytes)
        done += far(j) * w
        total += w
    end
    return if total > 0 then done / total else 0
end

local DOING = { copy = "Copying", move = "Moving", link = "Linking", delete = "Deleting", restore = "Putting back", erase = "Erasing" }
local function title(j: Job): string
    local what = if j.count == 1 then "1 item" else `{j.count} items`
    if j.kind == "trash" then return `Moving {what} to the trash` end
    if j.kind == "extract" then return if j.to then `Extracting into {paths.called(j.to)}` else "Extracting" end
    if j.kind == "compress" then return `Compressing {what}` end
    local to = if j.to then ` to {paths.called(j.to)}` else ""
    return `{(DOING :: any)[j.kind] or j.kind} {what}{to}`
end

local function left(seconds: number): string
    if seconds < 60 then return `{math.max(1, math.ceil(seconds))} s` end
    if seconds < 3600 then return `{math.ceil(seconds / 60)} min` end
    return string.format("%d h %02d min", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
end

local function figures(j: Job): string
    if j.state == "waiting" then return "Waiting for the one before" end
    if j.state == "preparing" then return "Counting" end
    if j.state == "finishing" then return "The disk is writing the last of it" end
    local out: { string } = {}
    if j.total_bytes > 0 then
        table.insert(out, `{format.size(j.bytes)} of {format.size(j.total_bytes)}`)
    else
        table.insert(out, `{j.files} of {j.total_files}`)
    end
    if j.state == "paused" then
        table.insert(out, "Paused")
    elseif j.state == "running" then
        if j.rate > 1 and j.total_bytes > 0 then table.insert(out, `{format.size(j.rate)}/s`) end
        if j.remaining then table.insert(out, left(j.remaining)) end
    end
    return table.concat(out, "     ")
end

-- ---- What is asked ----------------------------------------------------------------------

local ANSWER = { replace = "Replace", merge = "Merge", keep_both = "Keep both", skip = "Skip", retry = "Retry", cancel = "Stop" }
-- What loses nothing is the one that stands out.
local SAFE = { exists = "keep_both", failed = "retry", space = "retry", password = "retry" }

-- The password a locked archive is asked for, as it is typed.
local password = g.signal("")
-- Whether the keys are the password's: a locked archive is asking.
function M.typing(): boolean
    for _, j in jobs.value do
        if j.state == "asking" and j.question and j.question.kind == "password" then return true end
    end
    return false
end

local function asked(q: any): (string, string, string)
    if q.kind == "exists" then
        local name = paths.name(q.to or q.path)
        local folder = paths.called(paths.parent(q.to or q.path) or "/")
        local function seen(s: any): string
            if s == nil then return "" end
            return if s.dir then format.moment(s.modified) else `{format.size(s.size)}   {format.moment(s.modified)}`
        end
        return `{name} is already in {folder}`, `There   {seen(q.target)}`, `New   {seen(q.source)}`
    elseif q.kind == "space" then
        return "It does not fit there", `Needed   {format.size(q.needed or 0)}`, `Free   {format.size(q.available or 0)}`
    elseif q.kind == "password" then
        local name = paths.name(q.path)
        return if q.wrong then `That is not the password of {name}` else `{name} is locked by a password`, "", ""
    end
    local why = q.error or ""
    return `{paths.name(q.path)} could not be done`, string.upper(string.sub(why, 1, 1)) .. string.sub(why, 2), ""
end

local function question(job: () -> Job?): any
    local for_all = g.signal(false)
    local function q(): any
        local j = job()
        return if j then j.question else nil
    end
    local function words(k: number): string
        local it = q()
        if it == nil then return "" end
        local a, b, c = asked(it)
        return if k == 1 then a elseif k == 2 then b else c
    end
    local function text(k: number, size: number, colour: () -> string, font: () -> string): any
        return g.text {
            present = function() return words(k) ~= "" end,
            text = function() return words(k) end,
            max_width = function() return inner.value end,
            wrap = k == 1,
            ellipsize = if k == 1 then nil else "middle",
            color = colour,
            font = font,
            size = size,
            weight = if k == 1 then 500 else 400,
            tabular = k > 1,
        }
    end
    return g.box {
        present = function() return q() ~= nil end,
        direction = "column",
        align = "stretch",
        gap = 10,
        g.box {
            direction = "column",
            align = "stretch",
            gap = 5,
            text(1, look.font_name, look.text, look.expressive),
            text(2, look.font_meta, look.text_muted, look.technical),
            text(3, look.font_meta, look.text_muted, look.technical),
        },
        -- A locked archive: its password, never shown, Return opens it.
        g.capsule {
            present = function()
                local it = q()
                return it ~= nil and it.kind == "password"
            end,
            height = 34,
            padding_x = 14,
            direction = "row",
            align = "center",
            radius = look.round(17),
            fill = look.glass,
            rim_top = look.primary,
            rim_bottom = look.primary,
            g.field {
                id = "job-password",
                grow = 1,
                size = look.font_label,
                font = look.expressive,
                color = look.text,
                caret_color = look.primary,
                selection_color = look.chosen,
                placeholder = "Password",
                secret = true,
                focused = function()
                    local it = q()
                    return it ~= nil and it.kind == "password"
                end,
                text = function() return password.value end,
                on_change = function(text: string) password.value = text end,
                on_submit = function()
                    local j = g.untracked(job)
                    if j then
                        files:answer(j.id, "retry", false, g.untracked(function() return password.value end))
                        password.value = ""
                    end
                end,
            },
        },
        g.box {
            -- One answer for the rest of them, where there may be a rest.
            present = function()
                local j = job()
                local it = q()
                return it ~= nil and it.kind ~= "space" and it.kind ~= "password" and j ~= nil and (j.total_files > 1 or j.count > 1)
            end,
            direction = "row",
            align = "center",
            gap = 12,
            ui.switch {
                id = "for-all",
                name = "The same for the rest",
                on = function() return for_all.value end,
                on_toggle = function(on: boolean) for_all.value = on end,
            },
            ui.label("The same for the rest", look.text_muted),
        },
        g.each {
            direction = "row",
            align = "center",
            gap = 6,
            items = function(): { string }
                local it = q()
                return if it then it.answers else {}
            end,
            key = function(a: string) return a end,
            row = function(answer: () -> string, _)
                local a = g.untracked(answer)
                local locked = (g.untracked(q) or { kind = "" }).kind == "password"
                return ui.action {
                    id = "answer-" .. a,
                    label = if locked and a == "retry" then "Open" else (ANSWER :: any)[a] or a,
                    kind = if a == (SAFE :: any)[(g.untracked(q) or { kind = "" }).kind] then "filled" else "outline",
                    on_click = function()
                        local j = g.untracked(job)
                        if j == nil then return end
                        if locked and a == "retry" then
                            files:answer(j.id, "retry", false, g.untracked(function() return password.value end))
                            password.value = ""
                        else
                            operations.answer(j.id, a, g.untracked(function() return for_all.value end))
                        end
                    end,
                }
            end,
        },
    }
end

local function row(job: () -> Job, _: any): any
    local function paused(): boolean return job().state == "paused" end
    local function asks(): boolean return job().state == "asking" end
    local function room(): number return inner.value end
    local id = g.untracked(job).id
    return g.box {
        direction = "column",
        align = "stretch",
        gap = 8,
        g.box {
            direction = "row",
            align = "center",
            justify = "between",
            g.text {
                text = function() return title(job()) end,
                max_width = function() return room() - 90 end,
                ellipsize = "middle",
                color = look.text,
                font = look.expressive,
                size = look.font_label,
                weight = 600,
            },
            g.box {
                direction = "row",
                gap = 8,
                g.box {
                    present = function() return not asks() and not paused() and job().state ~= "finishing" end,
                    ui.action { id = "job-pause", name = "Pause", glyph = "pause", on_click = function() files:pause(id) end },
                },
                g.box {
                    present = paused,
                    ui.action { id = "job-resume", name = "Go on", glyph = "play", on_click = function() files:resume(id) end },
                },
                ui.action { id = "job-stop", name = "Stop", glyph = "close", on_click = function() files:cancel(id) end },
            },
        },
        g.text {
            present = function() return not asks() and job().current ~= "" end,
            text = function() return paths.name(job().current) end,
            max_width = room,
            ellipsize = "middle",
            color = look.text_muted,
            font = look.expressive,
            size = look.font_secondary,
        },
        g.box {
            width = room,
            height = BAR,
            g.capsule {
                overlay = true,
                attach = "corner",
                width = room,
                height = BAR,
                radius = look.round(BAR / 2),
                fill = function() return g.colour.alpha(look.line(), 0.55) end,
                rim_top = look.CLEAR,
                rim_bottom = look.CLEAR,
            },
            g.capsule {
                overlay = true,
                attach = "corner",
                present = function() return far(job()) > 0 end,
                width = function() return math.max(BAR, room() * far(job())) end,
                height = BAR,
                radius = look.round(BAR / 2),
                fill = look.primary_top,
                fill_bottom = look.primary_bottom,
                rim_top = look.CLEAR,
                rim_bottom = look.CLEAR,
                opacity = function() return if paused() or asks() then 0.5 else 1 end,
            },
        },
        g.text {
            present = function() return not asks() end,
            text = function() return figures(job()) end,
            color = look.text_muted,
            font = look.technical,
            size = look.font_meta,
            tabular = true,
        },
        question(function(): Job? return job() end),
    }
end

-- `area()`: the window's { w, h }.
function M.new(area: () -> { w: number, h: number }): any
    local function beside(): number return view_cell.x(area()) - BUTTON - 8 end
    -- It buds from the view's button, and goes back to it.
    local out = g.signal(false)
    local shown = g.signal(false)
    local going: any = nil
    g.watch(function() return there.value end, function(on: boolean)
        if going then going:stop() end
        going = nil
        if on then
            shown.value = true
            g.after(0, function() out.value = g.untracked(function() return there.value end) end)
        else
            out.value = false
            going = g.after(0.3, function()
                going = nil
                shown.value = false
            end)
        end
    end)
    local over = g.signal(false)
    g.effect(function() inner.value = math.min(WIDTH, area().w - look.margin_edge * 2) - PAD * 2 end)
    return foot_cell.new {
        id = "jobs",
        name = "What is being done",
        area = area,
        x = beside,
        open = M.open,
        width = WIDTH,
        content = g.box {
            direction = "column",
            align = "stretch",
            padding = PAD,
            g.each {
                direction = "column",
                align = "stretch",
                gap = 20,
                items = function() return jobs.value end,
                key = function(j: Job) return j.id end,
                row = row,
            },
        },
        button = function(_: () -> number, by: () -> number): any
            local function shape(): string return if out.value then "shoot_1" else "shoot_close_1" end
            local function neck(): string return if out.value then "neck_1" else "neck_close_1" end
            return g.box {
                overlay = true,
                attach = "corner",
                offset_x = function() return view_cell.x(area()) end,
                offset_y = by,
                width = BUTTON,
                height = BUTTON,
                g.capsule {
                    id = "jobs-button",
                    role = "button",
                    name = "What is being done",
                    present = function() return shown.value end,
                    overlay = true,
                    attach = "left",
                    offset_x = function() return if out.value then -8 else 0 end,
                    growth = function() return if out.value then 1 else 0 end,
                    bud = function() return if out.value then 0 else BUTTON end,
                    width = BUTTON,
                    height = BUTTON,
                    radius = look.round(BUTTON / 2),
                    fill = function() return if M.open.value then look.cell() elseif over.value then look.cell() else look.glass() end,
                    rim_top = function() return if M.open.value then look.primary() else look.rim() end,
                    rim_bottom = function() return if M.open.value then look.primary() else look.line() end,
                    transition = { offset_x = shape, growth = shape, bud = neck, rim_top = "ui_change", rim_bottom = "ui_change" },
                    g.box {
                        overlay = true,
                        attach = "corner",
                        width = BUTTON,
                        height = BUTTON,
                        align = "center",
                        justify = "center",
                        opacity = function() return if out.value then 1 else 0 end,
                        transition = { opacity = function() return if out.value then "shoot_words_1" else "content_out" end },
                        on_hover = function(on: boolean) over.value = on end,
                        on_press = function() end,
                        on_click = function(button: number)
                            if button == 272 then M.open.value = not g.untracked(function() return M.open.value end) end
                        end,
                        g.box {
                            width = RING,
                            height = RING,
                            g.capsule {
                                overlay = true,
                                attach = "center",
                                width = RING,
                                height = RING,
                                radius = RING / 2,
                                stroke = 2.5,
                                fill = look.CLEAR,
                                rim_top = look.line,
                                rim_bottom = look.line,
                            },
                            -- As far as it is.
                            g.capsule {
                                overlay = true,
                                attach = "center",
                                width = RING,
                                height = RING,
                                radius = RING / 2,
                                stroke = 2.5,
                                arc = all,
                                fill = look.CLEAR,
                                rim_top = look.primary_top,
                                rim_bottom = look.primary_bottom,
                            },
                        },
                    },
                },
            }
        end,
    }
end

return M
