--!strict
-- A folder seen: where one is in it and how one got there, what is looked for
-- in it, where one stands and what is chosen. A window has one, or two side by
-- side, in each of its tabs.
local g = require("@genoma")
local bin = require("core/bin")
local colours = require("core/colours")
local config = require("core/config")
local notice = require("core/notice")
local paths = require("core/paths")
local selecting = require("core/selecting")

local M = {}

type Stop = { path: string, cursor: string? }
export type How = "only" | "extend" | "keep"
export type Pane = any

local function untracked<T>(f: () -> T): T return g.untracked(f) end

local function pushed(list: { Stop }, stop: Stop): { Stop }
    local out = table.clone(list)
    table.insert(out, stop)
    -- The way back is remembered, not all of a day's.
    if #out > 200 then table.remove(out, 1) end
    return out
end


local count = 0

local function made(start: string): Pane
    count += 1
    local M: { [string]: any } = { id = count }

    local here = g.signal(start)
    local back = g.signal({} :: { Stop })
    local forward = g.signal({} :: { Stop })

    -- Whether the filter is open, and whether the keys are its: until one of
    -- what was found is chosen, and again as soon as something is typed.
    M.filtering = g.signal(false)
    M.typing = g.signal(true)
    -- The best guess, that stands ready for Return.
    M.guessed = nil :: string?

    -- The entry the keys move from, by its path: it keeps it when the order
    -- changes, and loses it when it goes.
    M.cursor = g.signal(nil :: string?)
    M.filter = g.signal("")
    -- Only what is marked with this colour; "" all.
    M.only = g.signal("")
    -- Whether something is looked for, here and below.
    function M.looking(): boolean return M.filter.value ~= "" or M.only.value ~= "" end

    M.here = here
    function M.can_back(): boolean return #back.value > 0 end
    function M.can_forward(): boolean return #forward.value > 0 end
    function M.can_up(): boolean return paths.parent(here.value) ~= nil end

    -- The folder last asked for: the trash is none.
    local folder = g.signal(paths.home)
    g.watch(function() return here.value end, function(path: string)
        if path ~= paths.TRASH then folder.value = path end
    end)
    function M.in_trash(): boolean return here.value == paths.TRASH end

    local real = g.directory {
        path = function() return folder.value end,
        sort = function() return config.get("sort") end,
        descending = function() return config.get("descending") end,
        folders_first = function() return config.get("folders_first") end,
        hidden = function() return config.get("hidden") end,
        filter = function() return M.filter.value end,
        -- What is typed is looked for in the folders below too.
        deep = true,
        attribute = colours.ATTRIBUTE,
        known = colours.known,
        only = function() return M.only.value end,
    }
    local thrown = bin.new { filter = function() return M.filter.value end }

    -- Which of the two is seen: the trash until the folder one goes to is read.
    local seen_thrown = g.signal(g.untracked(M.in_trash))
    g.effect(function()
        local now = M.in_trash()
        local ready = real.path == here.value or not real.loading
        g.untracked(function()
            if now then seen_thrown.value = true elseif ready then seen_thrown.value = false end
        end)
    end)

    -- What is shown, a folder or the trash, asked in the same words.
    local function seen(): any return if seen_thrown.value then thrown else real end
    local asked: { [string]: any } = {}
    for _, name in { "at", "slice", "paths", "index", "reload" } do
        asked[name] = function(_: any, ...: any): any
            local from = seen()
            return from[name](from, ...)
        end
    end
    M.dir = setmetatable(asked, { __index = function(_: any, key: string): any return seen()[key] end }) :: any

    -- How standing on an entry changes the selection: "only" it, "extend" the
    -- range to it, "keep" what is. Set by core/selecting.
    M.chosen = function(_: string?, _: How) end

    local function put(stop: Stop)
        g.batch(function()
            -- Another folder is another search.
            M.filter.value = ""
            M.only.value = ""
            M.filtering.value = false
            M.cursor.value = stop.cursor
            here.value = stop.path
            M.chosen(stop.cursor, "only")
        end)
        notice.say(nil)
    end

    local function current(): Stop
        return untracked(function(): Stop return { path = here.value, cursor = M.cursor.value } end)
    end

    -- To a folder. `cursor` is the entry to stand on there.
    function M.go(path: string, cursor: string?)
        path = paths.expand(path)
        local now = current()
        if path == now.path then
            M.filter.value = ""
            return
        end
        back.value = pushed(untracked(function() return back.value end), now)
        forward.value = {}
        put { path = path, cursor = cursor }
    end

    local function step(from: any, to: any)
        local list = untracked(function() return from.value end)
        local stop = list[#list]
        if stop == nil then return end
        to.value = pushed(untracked(function() return to.value end), current())
        local rest = table.clone(list)
        table.remove(rest)
        from.value = rest
        put(stop)
    end
    function M.back() step(back, forward) end
    function M.forward() step(forward, back) end

    -- A path that is a file's: the folder around it, standing on the file.
    g.watch(function() return M.dir.error end, function(why: string?)
        if why ~= "not a folder" then return end
        local at = untracked(function() return here.value end)
        local parent = paths.parent(at)
        if parent then put { path = parent, cursor = at } end
    end)

    -- Up, standing on the folder one came out of.
    function M.up()
        local at = untracked(function() return here.value end)
        local parent = paths.parent(at)
        if parent then M.go(parent, at) end
    end

    -- The entry under the cursor, while it is shown.
    M.index = g.computed(function(): number?
        local at = M.cursor.value
        local _ = M.dir.count
        return if at then M.dir:index(at) else nil
    end)
    function M.selected(): any
        local i = M.index.value
        return if i then M.dir:at(i) else nil
    end

    -- The cursor moved by places; from nowhere, to the first or the last.
    function M.move(by: number, how: How?)
        local count = untracked(function() return M.dir.count end)
        if count == 0 then return end
        local i = untracked(function() return M.index.value end)
        local to = if i == nil then (if by > 0 then 1 else count) else math.clamp(i + by, 1, count)
        M.stand(to, how)
    end
    function M.stand(place: number, how: How?)
        local e = untracked(function() return M.dir:at(place) end)
        if e then
            M.cursor.value = e.path
            M.chosen(e.path, how or "only")
        end
    end
    -- On nothing.
    function M.leave()
        M.cursor.value = nil
        M.chosen(nil, "only")
    end


    -- How its views stand (ui/grid, ui/list): kept while they are made again.
    M.view = {
        columns = g.signal(1),
        rows = g.signal(1),
        place = g.signal({ pitch = 1, cell_w = 0, cell_h = 0, gap = 0 }),
        scrolled = g.signal(0),
        lined = g.signal(0),
        over = g.signal(nil :: number?),
        banded = g.signal(nil :: number?),
    }

    M.selection = selecting.new(M)

    -- Closed: nothing of it is followed until it is opened again.
    function M.rest()
        g.batch(function()
            back.value, forward.value = {}, {}
            M.filter.value, M.only.value = "", ""
            M.filtering.value = false
            M.cursor.value = nil
            M.selection.clear()
        end)
    end
    function M.start(path: string)
        M.rest()
        here.value = path
    end
    return M
end

-- Panes closed are opened again as others: what follows a folder is made once.
local spare: { Pane } = {}

function M.open(path: string): Pane
    local p = table.remove(spare)
    if p then
        p.start(path)
        return p
    end
    return g.lasting(function() return made(path) end)
end
function M.close(p: Pane)
    p.rest()
    table.insert(spare, p)
end

return M
