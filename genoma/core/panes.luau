--!strict
-- The tabs, each with one pane or two, and which is the one the keys, the path
-- and the buttons are about.
local g = require("@genoma")
local pane = require("core/pane")
local paths = require("core/paths")

local M = {}

-- `at`: which of its panes has the keys.
export type Tab = { id: number, panes: any, at: any }

local START = paths.expand(g.env("RIZOMA_FOLDER") or "~")

-- Kept through a reload while Rizoma is written: only where they are.
local kept = g.state("rizoma.tabs", { tabs = { { START } }, at = { 1 }, tab = 1 } :: any)

local count = 0
local function made(list: { string }, at: number): Tab
    count += 1
    local all: { any } = {}
    for _, path in list do table.insert(all, pane.open(path)) end
    return { id = count, panes = g.signal(all), at = g.signal(math.clamp(at, 1, math.max(1, #all))) }
end

local first: { Tab } = {}
do
    local was = g.untracked(function() return kept.value end)
    for i, list in was.tabs do table.insert(first, made(list, was.at[i] or 1)) end
    if #first == 0 then table.insert(first, made({ START }, 1)) end
    M.tabs = g.signal(first)
    M.tab = g.signal(first[math.clamp(was.tab, 1, #first)])
end
g.effect(function()
    local out: any = { tabs = {}, at = {}, tab = 1 }
    for i, t in M.tabs.value do
        local list: { string } = {}
        for _, p in t.panes.value do table.insert(list, p.here.value) end
        table.insert(out.tabs, list)
        table.insert(out.at, t.at.value)
        if t == M.tab.value then out.tab = i end
    end
    g.untracked(function() kept.value = out end)
end)

local function now<T>(f: () -> T): T return g.untracked(f) end

-- The pane the keys are for, followed.
function M.active(): any
    local t = M.tab.value
    local list = t.panes.value
    return list[math.clamp(t.at.value, 1, #list)]
end
-- Those of the tab that is seen.
function M.shown(): { any } return M.tab.value.panes.value end
function M.two(): boolean return #M.shown() > 1 end
-- The other one of two, or nil.
function M.other(): any
    local list = M.shown()
    if #list < 2 then return nil end
    return list[3 - math.clamp(M.tab.value.at.value, 1, 2)]
end

function M.focus(p: any)
    now(function()
        for i, q in M.shown() do
            if q == p and M.tab.value.at.value ~= i then M.tab.value.at.value = i end
        end
    end)
end
function M.swap()
    now(function()
        if M.two() then M.tab.value.at.value = 3 - M.tab.value.at.value end
    end)
end

-- A second pane beside the one there is, on the same folder; or the one that
-- has the keys alone.
function M.split(path: string?)
    now(function()
        local t = M.tab.value
        local list = t.panes.value
        if #list > 1 then return end
        g.batch(function()
            t.panes.value = { list[1], pane.open(path or list[1].here.value) }
            t.at.value = 2
        end)
    end)
end
function M.join()
    now(function()
        local t = M.tab.value
        local list = t.panes.value
        if #list < 2 then return end
        local keep, drop = M.active(), M.other()
        g.batch(function()
            t.panes.value = { keep }
            t.at.value = 1
        end)
        pane.close(drop)
    end)
end

-- A tab after the one that is seen; `aside`, it is not gone to.
function M.new_tab(path: string?, aside: boolean?)
    now(function()
        local t = made({ path or M.active().here.value }, 1)
        local list = table.clone(M.tabs.value)
        -- Several opened aside stand in the order they were opened.
        local at = table.find(list, M.tab.value) or #list
        table.insert(list, if aside then #list + 1 else at + 1, t)
        g.batch(function()
            M.tabs.value = list
            if not aside then M.tab.value = t end
        end)
    end)
end
function M.show(t: Tab)
    if now(function() return M.tab.value end) ~= t then M.tab.value = t end
end
function M.step(by: number)
    now(function()
        local list = M.tabs.value
        local at = table.find(list, M.tab.value) or 1
        M.tab.value = list[(at + by - 1) % #list + 1]
    end)
end
-- Its place among them.
function M.move(t: Tab, to: number)
    now(function()
        local list = table.clone(M.tabs.value)
        local at = table.find(list, t)
        if at == nil then return end
        to = math.clamp(to, 1, #list)
        if to == at then return end
        table.remove(list, at)
        table.insert(list, to, t)
        M.tabs.value = list
    end)
end
-- Closed; false when it is the only one.
function M.close(t: Tab?): boolean
    return now(function(): boolean
        local gone = t or M.tab.value
        local list = table.clone(M.tabs.value)
        local at = table.find(list, gone)
        if at == nil or #list < 2 then return false end
        table.remove(list, at)
        g.batch(function()
            if M.tab.value == gone then M.tab.value = list[math.min(at, #list)] end
            M.tabs.value = list
        end)
        for _, p in gone.panes.value do pane.close(p) end
        return true
    end)
end

-- The pane that has the keys, spoken of as if there were only one: its values
-- followed as they change hands, its functions those of whichever it is then.
function M.facade(part: (p: any) -> any, own: { [string]: any }): any
    local calls: { [string]: any } = {}
    return setmetatable(own, {
        __index = function(_: any, key: string): any
            local call = calls[key]
            if call then return call end
            local value = part(M.active())[key]
            if type(value) ~= "function" then return value end
            call = function(...: any): any return part(M.active())[key](...) end
            calls[key] = call
            return call
        end,
    })
end

return M
