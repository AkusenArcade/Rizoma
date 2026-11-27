--!strict
-- The folder the keys are in, and what opens what is in it. Nothing here
-- changes a file: it reads folders and hands files to the programs that open
-- them.
local g = require("@genoma")
local apps = require("@genoma/apps")
local mime = require("@genoma/mime")
local notice = require("core/notice")
local panes = require("core/panes")
local paths = require("core/paths")

local M: { [string]: any } = {}

export type How = "only" | "extend" | "keep"

M.notice = notice.now
M.say = notice.say

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

-- Set by core/operations.
M.restore = function(_: any) end

-- With an application chosen for it.
function M.open_with(app: any, list: { string })
    g.activation_token {
        app_id = app.id,
        on_token = function(token: string?) apps:launch(app.id, nil, list, token) end,
    }
end

-- A folder in the desktop's terminal.
function M.terminal(folder: string)
    if folder == paths.TRASH then return end
    g.activation_token {
        on_token = function(token: string?)
            local ok, why = pcall(function() apps:terminal(folder, token) end)
            if not ok then M.say { text = if string.find(tostring(why), "no terminal") then "No terminal is installed" else "The terminal did not start" } end
        end,
    }
end

-- Several at once: the files, by what opens them. Folders and programs are
-- opened one at a time.
local MOST = 40
function M.open_all(entries: { any })
    local by: { [string]: { string } } = {}
    local n, left = 0, 0
    for _, e in entries do
        local app = if e.dir or e.broken then nil else mime:default(e.mime)
        if app and not runs(e.mime) then
            by[app.id] = by[app.id] or {}
            table.insert(by[app.id], e.path)
            n += 1
        else
            left += 1
        end
    end
    if n > MOST then
        M.say { text = `{n} files are too many to open at once` }
        return
    end
    for id, paths in by do
        g.activation_token { app_id = id, on_token = function(token: string?) apps:launch(id, nil, paths, token) end }
    end
    if left > 0 then M.say { text = `{left} left closed: folders and programs open one at a time` } end
end

-- Set by core/archives: an archive opened where Rizoma opens archives is
-- extracted beside itself, as Nautilus does; true when it was.
M.extracts = function(_: any): boolean return false end

function M.open(e: any)
    if e.deleted then
        M.say { text = `{e.name} is in the trash: put back, it can be opened`, label = "Restore", act = function() M.restore(e) end, passing = true }
        return
    end
    if e.broken then
        M.say { text = `{e.name} points to something that is no longer there` }
        return
    end
    if e.dir then
        M.go(e.path)
        return
    end
    if M.extracts(e) then return end
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


-- The rest is the pane's that has the keys.
return panes.facade(function(p: any): any return p end, M)
