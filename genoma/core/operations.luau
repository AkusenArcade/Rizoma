--!strict
-- What is done to files: paste, drop, rename, new folder. @genoma/files does
-- it and asks what only a person can say; here is what is asked of it, and
-- what comes after.
local g = require("@genoma")
local files = require("@genoma/files")
local trash = require("@genoma/trash")
local browser = require("core/browser")
local colours = require("core/colours")
local exchange = require("core/exchange")
local format = require("core/format")
local panes = require("core/panes")
local paths = require("core/paths")
local selection = require("core/selection")

local M = {}

local function here(): string return g.untracked(function() return browser.here.value end) end

-- What was found is not followed: it is looked at again after a change.
local function look_again()
    for _, p in g.untracked(panes.shown) do
        if g.untracked(p.looking) then p.dir:reload() end
    end
end

-- ---- What comes of it -----------------------------------------------------------------

-- What was made, chosen as soon as the folder shows it.
local coming = g.signal(nil :: { string }?)
local giving_up: any = nil
function M.arrive(list: { string })
    local mine: { string } = {}
    local shown: { [string]: boolean } = {}
    for _, pane in g.untracked(panes.shown) do shown[g.untracked(function() return pane.here.value end)] = true end
    for _, p in list do
        if shown[paths.parent(p) or ""] then table.insert(mine, p) end
    end
    if #mine == 0 then return end
    coming.value = mine
    if giving_up then giving_up:stop() end
    giving_up = g.after(3, function()
        giving_up = nil
        coming.value = nil
    end)
end
g.effect(function()
    local list = coming.value
    for _, p in panes.shown() do local _ = p.dir.count end
    if list == nil then return end
    g.untracked(function()
        for _, pane in panes.shown() do
            local shown: { string } = {}
            for _, p in list do
                if pane.dir:index(p) then table.insert(shown, p) end
            end
            if #shown == #list then
                coming.value = nil
                g.batch(function()
                    pane.cursor.value = shown[1]
                    pane.selection.only(shown[1])
                    if #shown > 1 then pane.selection.these(shown) end
                end)
            end
        end
    end)
end)

local function many(n: number): string return if n == 1 then "1 item" else `{n} items` end

local LOST = { permissions = "permissions", times = "dates", attributes = "attributes" }
local function kept_words(lost: { string }): string
    local out: { string } = {}
    for _, l in lost do
        if l == "changes" then continue end
        table.insert(out, (LOST :: any)[l] or l)
    end
    return table.concat(out, " and ")
end

-- The way back of the last thing done: what can be put as it was.
export type Undo = { said: string, act: () -> () }
M.undo = g.signal(nil :: Undo?)
function M.undo_last()
    local u = g.untracked(function() return M.undo.value end)
    M.undo.value = nil
    if u == nil then
        browser.say { text = "Nothing to undo" }
        return
    end
    browser.say { text = u.said }
    u.act()
end
-- The last thing done is the only one that can be: nothing older comes back
-- in its place.
local function can_undo(said: string, act: () -> ())
    M.undo.value = { said = said, act = act }
end

-- What was made is thrown away, not deleted: the trash keeps it.
local function take_away(list: { string })
    files:trash(list, function() look_again() end)
end

-- ---- The trash --------------------------------------------------------------------------

-- Its place once it has gone: the next one is stood on.
local leaving = g.signal(nil :: { list: { string }, place: number }?)
g.effect(function()
    local l = leaving.value
    local count = browser.dir.count
    if l == nil then return end
    g.untracked(function()
        for _, p in l.list do
            if browser.dir:index(p) then return end
        end
        leaving.value = nil
        if count > 0 and browser.cursor.value == nil or browser.index.value == nil and count > 0 then
            browser.stand(math.clamp(l.place, 1, count))
        end
    end)
end)
local function leave(list: { string })
    local first: number? = nil
    for _, p in list do
        local i = g.untracked(function() return browser.dir:index(p) end)
        if i and (first == nil or i < first) then first = i end
    end
    leaving.value = if first then { list = list, place = first } else nil
end

-- Back where it was, by where it is now. What was thrown away a moment ago the
-- trash may not have seen yet.
local function put_out(list: { string }, on_done: ((r: any) -> ())?)
    local tries = 0
    local function go()
        tries += 1
        local known: { [string]: boolean } = {}
        for _, t in g.untracked(function() return trash.items end) do known[t.file] = true end
        local all = true
        for _, p in list do all = all and known[p] == true end
        if not all and tries < 12 then
            if tries == 1 then trash:reload() end
            g.after(0.15, go)
            return
        end
        trash:restore(list, function(r: any)
            look_again()
            if on_done then on_done(r) end
        end)
    end
    go()
end

function M.throw(list: { string })
    if #list == 0 or g.untracked(browser.in_trash) then return end
    leave(list)
    files:trash(list, function(r: any)
        look_again()
        if #r.made == 0 then
            leaving.value = nil
            return
        end
        can_undo("Back from the trash", function()
            put_out(r.made, function(back: any) M.arrive(back.made) end)
        end)
        browser.say { text = `{many(#r.made)} in the trash`, label = "Undo", act = M.undo_last, passing = true }
    end)
end

-- Out of the trash, where each was.
function M.restore(list: { string })
    if #list == 0 then return end
    leave(list)
    put_out(list, function(r: any)
        M.undo.value = nil
        local n = #r.made
        if n == 0 then return end
        local to = paths.parent(r.made[1]) or "/"
        for _, p in r.made do
            if paths.parent(p) ~= to then to = "" end
        end
        browser.say {
            text = if to == "" then `{many(n)} back where they were` else `{many(n)} back in {paths.called(to)}`,
            label = if to == "" then nil else "Show",
            act = if to == "" then nil else function()
                browser.say(nil)
                browser.go(to, r.made[1])
            end,
            passing = true,
        }
    end)
end
browser.restore = function(e: any)
    browser.say(nil)
    M.restore { e.path }
end

-- For good, once it is said so: how many, and what they come to.
local function ask(text: string, list: { string }?, act: () -> ())
    local counting: any = nil
    local function say(more: string)
        browser.say {
            text = text .. more,
            label = "Delete",
            act = function()
                if counting then counting:stop() end
                browser.say(nil)
                act()
            end,
            grave = true,
        }
    end
    say("")
    if list == nil then return end
    counting = files:measure(list, function(total: any, whole: boolean)
        local n = g.untracked(function() return browser.notice.value end)
        -- Answered meanwhile, or asked something else.
        if n == nil or not n.grave then
            counting:stop()
            return
        end
        if whole and total.bytes > 0 then say(` {format.size(total.bytes)}.`) end
    end)
end

function M.delete(list: { string })
    if #list == 0 then return end
    local what = if #list == 1 then paths.name(list[1]) else many(#list)
    -- In the trash a thing is called as it was.
    if #list == 1 then
        local i = g.untracked(function() return browser.dir:index(list[1]) end)
        local e = if i then g.untracked(function() return browser.dir:at(i) end) else nil
        if e then what = e.name end
    end
    local in_trash = g.untracked(browser.in_trash)
    ask(`Delete {what} for good?`, list, function()
        leave(list)
        M.undo.value = nil
        if in_trash then
            trash:erase(list)
        else
            files:delete(list, function(r: any)
                if not r.cancelled and #r.skipped == 0 then colours.gone(list) end
                look_again()
            end)
        end
    end)
end

function M.empty()
    local all: { string } = {}
    for _, t in g.untracked(function() return trash.items end) do table.insert(all, t.file) end
    if #all == 0 then return end
    ask(`Delete all that is in the trash, {many(#all)}, for good?`, all, function()
        M.undo.value = nil
        -- What was asked about, and nothing thrown away since.
        trash:erase(all)
    end)
end

-- What a person was asked about and answered: merged with or put in the place
-- of something, it is no longer only what went there, and is not taken back.
local answered: { [number]: boolean } = {}
function M.answer(id: number, answer: string, for_all: boolean?)
    if answer == "replace" or answer == "merge" then answered[id] = true end
    files:answer(id, answer, for_all)
end

local put: (list: { string }, to: string, verb: exchange.Verb, after: (() -> ())?, quiet: boolean?) -> ()

-- Back where each was, as it was called.
local function put_back(from: { string }, now: { string })
    local by: { [string]: { string } } = {}
    for i, path in now do
        local home = from[i] and paths.parent(from[i])
        if home then
            by[home] = by[home] or {}
            table.insert(by[home], path)
        end
    end
    for home, list in by do put(list, home, "move", nil, true) end
end

function put(list: { string }, to: string, verb: exchange.Verb, after: (() -> ())?, quiet: boolean?)
    local ask: { string } = {}
    for _, p in list do
        -- Moved where it is already, there is nothing to do.
        if not (verb == "move" and paths.parent(p) == to) then table.insert(ask, p) end
    end
    if #ask == 0 then
        if not quiet then browser.say { text = "Already there" } end
        return
    end
    local id = 0
    local function done(r: any)
        local mixed = answered[id] == true
        answered[id] = nil
        if verb == "move" and #r.made == #ask then colours.moved(ask, r.made) end
        look_again()
        if after and not r.cancelled then after() end
        M.arrive(r.made)
        -- All of it went, so all of it can come back.
        if quiet then return end
        local whole = #r.made == #ask and #r.skipped == 0 and not r.cancelled and not mixed
        if not whole then
            M.undo.value = nil
        elseif verb == "move" then
            can_undo("Moved back", function() put_back(ask, r.made) end)
        else
            can_undo("The copies are in the trash", function() take_away(r.made) end)
        end
        local said: { string } = {}
        local elsewhere = true
        for _, pane in g.untracked(panes.shown) do
            if g.untracked(function() return pane.here.value end) == to then elsewhere = false end
        end
        if elsewhere and #r.made > 0 then
            table.insert(said, `{many(#r.made)} {if verb == "move" then "moved" else "copied"} to {paths.called(to)}`)
        end
        if #r.skipped > 0 then table.insert(said, `{many(#r.skipped)} left out`) end
        local lost = kept_words(r.lost)
        if lost ~= "" then table.insert(said, `without some {lost}`) end
        if #said == 0 then return end
        local back = whole and elsewhere
        browser.say {
            text = table.concat(said, ", "),
            label = if back then "Undo" else nil,
            act = if back then M.undo_last else nil,
            passing = true,
        }
    end
    id = if verb == "move" then files:move(ask, to, done) else files:copy(ask, to, done)
end
M.put = put

exchange.dropped = function(list: { string }, to: string, verb: exchange.Verb)
    if to == paths.TRASH then
        -- Given only to be copied, it is not ours to throw away.
        if verb == "move" then M.throw(list) else browser.say { text = "It cannot be thrown away from there" } end
        return
    end
    -- Let go where it was, it was not meant to go anywhere.
    local here_already = verb == "move"
    for _, p in list do here_already = here_already and paths.parent(p) == to end
    if not here_already then put(list, to, verb) end
end

-- What is selected, to the other pane's folder.
function M.across(verb: exchange.Verb)
    local other = g.untracked(panes.other)
    if other == nil or g.untracked(browser.in_trash) then return end
    local list = selection.list()
    if #list == 0 then return end
    local to = g.untracked(function() return other.here.value end)
    if to == paths.TRASH then M.throw(list) else put(list, to, verb) end
end

-- Into a folder; the one shown.
function M.paste(folder: string?)
    local to = folder or here()
    if to == paths.TRASH then return end
    exchange.held(function(list: { string }, verb: exchange.Verb)
        if #list == 0 then
            browser.say { text = "There are no files to paste" }
            return
        end
        put(list, to, verb, if verb == "move" then exchange.spent else nil)
    end)
end

-- ---- Colours ----------------------------------------------------------------------------

-- What is selected marked; with nil, no longer.
function M.colour(list: { string }, key: string?)
    if g.untracked(browser.in_trash) then return end
    colours.set(list, key, look_again)
end

-- ---- Names ------------------------------------------------------------------------------

local WHY = { ["File exists"] = "That name is taken" }
local function words(why: string?): string
    local w = why or "It could not be done"
    if string.find(string.lower(w), "exist") then return "That name is taken" end
    return (WHY :: any)[w] or (string.upper(string.sub(w, 1, 1)) .. string.sub(w, 2))
end

-- The entry whose name is being written, what is written, and what is wrong
-- with it.
M.renaming = g.signal(nil :: { path: string, name: string, dir: boolean }?)
M.typed = g.signal("")
function M.wrong(): string?
    local r = M.renaming.value
    if r == nil or M.typed.value == r.name then return nil end
    return files:check_name(M.typed.value)
end

function M.rename(e: any)
    if e.deleted then return end
    M.typed.value = e.name
    M.renaming.value = { path = e.path, name = e.name, dir = e.dir }
end
function M.stop_renaming() M.renaming.value = nil end

function M.finish_renaming()
    local r = g.untracked(function() return M.renaming.value end)
    if r == nil then return end
    local name = g.untracked(function() return M.typed.value end)
    if name == r.name or name == "" then
        M.renaming.value = nil
        return
    end
    local why = files:check_name(name)
    if why then
        browser.say { text = words(why) }
        return
    end
    M.renaming.value = nil
    files:rename(r.path, name, function(path: string?, err: string?)
        if path == nil then
            browser.say { text = words(err) }
            return
        end
        colours.moved({ r.path }, { path })
        look_again()
        M.arrive { path }
        can_undo("Its name is back", function()
            files:rename(path, r.name, function(was: string?, e: string?)
                if was then
                    colours.moved({ path }, { was })
                    M.arrive { was }
                else
                    browser.say { text = words(e) }
                end
                look_again()
            end)
        end)
    end)
end

-- Elsewhere chosen, or elsewhere gone: what was written is meant.
g.watch(function(): string?
    return browser.cursor.value
end, function(at: string?)
    local r = g.untracked(function() return M.renaming.value end)
    if r and at ~= r.path then M.finish_renaming() end
end)

-- A name nothing here has: "New folder", "New folder 2".
function M.free_name(name: string): string
    local at = here()
    local out, n = name, 1
    while g.untracked(function() return browser.dir:index(if at == "/" then "/" .. out else at .. "/" .. out) end) do
        n += 1
        out = `{name} {n}`
    end
    return out
end

function M.make_folder(name: string, on_made: (() -> ())?)
    files:make_folder(here(), name, function(path: string?, err: string?)
        if path == nil then
            browser.say { text = words(err) }
            return
        end
        if on_made then on_made() end
        M.arrive { path }
        can_undo("The new folder is in the trash", function() take_away { path } end)
    end)
end

return M
