--!strict
-- Where the window is and how it got there. Nothing here changes a file:
-- it reads folders and hands files to the programs that open them.
local g = require("@genoma")
local apps = require("@genoma/apps")
local mime = require("@genoma/mime")
local config = require("core/config")
local paths = require("core/paths")

local M = {}

type Stop = { path: string, cursor: string? }

-- Kept through a reload while Rizoma is written.
local here = g.state("rizoma.here", paths.expand(g.env("RIZOMA_FOLDER") or "~"))
local back = g.state("rizoma.back", {} :: { Stop })
local forward = g.state("rizoma.forward", {} :: { Stop })

-- The entry the keys move from, by its path: it keeps it when the order
-- changes, and loses it when it goes.
M.cursor = g.signal(nil :: string?)
M.filter = g.signal("")

M.here = here
function M.can_back(): boolean return #back.value > 0 end
function M.can_forward(): boolean return #forward.value > 0 end
function M.can_up(): boolean return paths.parent(here.value) ~= nil end

M.dir = g.directory {
    path = function() return here.value end,
    sort = function() return config.get("sort") end,
    descending = function() return config.get("descending") end,
    folders_first = function() return config.get("folders_first") end,
    hidden = function() return config.get("hidden") end,
    filter = function() return M.filter.value end,
}

-- What has to be said once: a file nothing opens, a question before a
-- program runs. `act` is what its button does.
export type Notice = { text: string, label: string?, act: (() -> ())? }
M.notice = g.signal(nil :: Notice?)
local quiet: any = nil
function M.say(notice: Notice?)
    if quiet then quiet:stop() end
    quiet = nil
    M.notice.value = notice
    -- A question waits for its answer; the rest goes by itself.
    if notice and notice.act == nil then
        quiet = g.after(5, function()
            quiet = nil
            M.notice.value = nil
        end)
    end
end

local function untracked<T>(f: () -> T): T return g.untracked(f) end

local function put(stop: Stop)
    g.batch(function()
        M.filter.value = ""
        M.cursor.value = stop.cursor
        here.value = stop.path
    end)
    M.say(nil)
end

local function current(): Stop
    return untracked(function(): Stop return { path = here.value, cursor = M.cursor.value } end)
end

local function pushed(list: { Stop }, stop: Stop): { Stop }
    local out = table.clone(list)
    table.insert(out, stop)
    -- The way back is remembered, not all of a day's.
    if #out > 200 then table.remove(out, 1) end
    return out
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

-- Up, standing on the folder one came out of.
function M.up()
    local at = untracked(function() return here.value end)
    local parent = paths.parent(at)
    if parent then M.go(parent, at) end
end

-- What runs a program rather than opening a document: asked before.
local RUNS = {
    "application/x-executable", "application/x-pie-executable", "application/x-sharedlib", "application/x-desktop",
    "application/vnd.appimage", "application/x-iso9660-appimage", "application/x-java-archive", "application/java-archive",
    "application/vnd.microsoft.portable-executable", "application/x-msdownload", "application/x-ms-dos-executable",
    "application/x-dosexec", "application/x-msi", "application/x-ms-shortcut", "application/x-bat",
}
local function runs(kind: string): boolean
    for _, r in RUNS do
        if mime:is_a(kind, r) then return true end
    end
    return false
end
M._runs = runs

local function launch(app: any, path: string)
    g.activation_token {
        app_id = app.id,
        on_token = function(token: string?) apps:launch(app.id, nil, { path }, token) end,
    }
end

function M.open(e: any)
    if e.broken then
        M.say { text = `{e.name} points to something that is no longer there` }
        return
    end
    if e.dir then
        M.go(e.path)
        return
    end
    local app = mime:default(e.mime)
    if app == nil then
        M.say { text = `No application opens {e.name} ({mime:description(e.mime)})` }
    elseif runs(e.mime) then
        M.say {
            text = `{e.name} is a program. Run it with {app.name}?`,
            label = "Run",
            act = function()
                M.say(nil)
                launch(app, e.path)
            end,
        }
    else
        launch(app, e.path)
    end
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
function M.move(by: number)
    local count = untracked(function() return M.dir.count end)
    if count == 0 then return end
    local i = untracked(function() return M.index.value end)
    local to = if i == nil then (if by > 0 then 1 else count) else math.clamp(i + by, 1, count)
    M.stand(to)
end
function M.stand(place: number)
    local e = untracked(function() return M.dir:at(place) end)
    if e then M.cursor.value = e.path end
end

return M
