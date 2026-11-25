--!strict
-- Rizoma among the desktop's programs: what it is started with, what other
-- programs ask of a file manager (org.freedesktop.FileManager1), and whether
-- folders open in it.
local g = require("@genoma")
local apps = require("@genoma/apps")
local mime = require("@genoma/mime")
local config = require("core/config")
local notice = require("core/notice")
local paths = require("core/paths")

local M = {}

M.ID = "dev.akusen.rizoma"
local NAME, PATH = "org.freedesktop.FileManager1", "/org/freedesktop/FileManager1"

M.mode = g.env("RIZOMA_MODE") or "open"
local self = g.env("RIZOMA_SELF")

local function located(text: string): string
    if string.find(text, "^%a[%w+.-]*://") then
        local path = g.uri_path(text)
        return if path then paths.expand(path) elseif string.sub(text, 1, 6) == "trash:" then paths.TRASH else paths.home
    end
    return paths.expand(text)
end

-- What it is asked to show at the start, as paths.
M.asked = {} :: { string }
for line in string.gmatch(g.env("RIZOMA_OPEN") or "", "[^\n]+") do table.insert(M.asked, located(line)) end

-- Whether there is a window: one that waits to be asked has none yet.
M.shown = g.state("rizoma.shown", M.mode ~= "service")

-- ---- Asked over D-Bus -------------------------------------------------------------------

-- Set by the shell: what shows some paths here.
M.show = function(_: string, _: { string }) end

-- Another window of its own, for what is asked while this one is somebody's.
local function another(mode: string, list: { string }, token: string)
    if self == nil then return end
    local command = { "setsid", "-f", self, "--" .. mode }
    if mode == "open" then command = { "setsid", "-f", self } end
    for _, p in list do table.insert(command, g.file_uri(p)) end
    g.process {
        command = command,
        env = { XDG_ACTIVATION_TOKEN = token, DESKTOP_STARTUP_ID = token, GENOMA = g.env("RIZOMA_GENOMA") or "" },
    }
end

local function asked(mode: string): (uris: { string }, startup: string) -> ()
    return function(uris: { string }, startup: string)
        local list: { string } = {}
        for _, uri in uris do
            local path = g.uri_path(uri)
            if path then table.insert(list, paths.expand(path)) end
        end
        if #list == 0 then return end
        if g.untracked(function() return M.shown.value end) then
            another(mode, list, startup)
            return
        end
        M.show(mode, list)
        M.shown.value = true
        g.activate(startup)
    end
end

-- Only one started to be asked answers: a window opened by hand takes nobody's
-- name.
if M.mode == "service" then
    g.dbus.serve {
        bus = "session",
        name = NAME,
        path = PATH,
        queue = true,
        interfaces = {
            [NAME] = {
                methods = {
                    ShowFolders = { args = "ass", call = asked("open") },
                    ShowItems = { args = "ass", call = asked("select") },
                    ShowItemProperties = { args = "ass", call = asked("properties") },
                },
            },
        },
    }
    -- Started, and nobody asked.
    g.after(20, function()
        if not g.untracked(function() return M.shown.value end) then g.quit() end
    end)
end

-- ---- The folders' program ----------------------------------------------------------------

local data = g.env("XDG_DATA_HOME") or (paths.home .. "/.local/share")
local service = data .. "/dbus-1/services/" .. NAME .. ".service"
local file = g.file { path = service }
-- Looked at again after a change of ours: the rest is followed.
local turned = g.signal(0)

-- Whether it can be: installed, and started by its own launcher.
function M.can_be_default(): boolean return self ~= nil and apps:find(M.ID) ~= nil end
local function opens_folders(): boolean
    local _ = turned.value
    local app = mime:default("inode/directory")
    return app ~= nil and app.id == M.ID
end
function M.is_default(): boolean
    return opens_folders() and string.find(file.text or "", "--service", 1, true) ~= nil and string.find(file.text or "", "rizoma", 1, true) ~= nil
end

local function again()
    turned.value += 1
    -- The bus reads what it starts only when it is told to.
    g.dbus.call {
        bus = "session",
        destination = "org.freedesktop.DBus",
        path = "/org/freedesktop/DBus",
        interface = "org.freedesktop.DBus",
        method = "ReloadConfig",
        reply = function() end,
    }
end

-- Folders opened with it, and "show in folder" asked of it; or back to what did
-- before.
function M.set_default(on: boolean)
    if not M.can_be_default() then return end
    if on then
        local was = mime:default("inode/directory")
        if was and was.id ~= M.ID then config.set("before", was.id) end
        local ok = pcall(function() mime:set_default("inode/directory", M.ID) end)
        if not ok then
            notice.say { text = "It could not be made the default" }
            return
        end
        file:write(`[D-BUS Service]\nName={NAME}\nExec={self} --service\n`)
    else
        local before = config.get("before")
        if before ~= "" then pcall(function() mime:set_default("inode/directory", before) end) end
        -- The file is ours: what is in it starts Rizoma.
        if string.find(file.text or "", "rizoma", 1, true) then
            g.process { command = { "rm", "-f", "--", service }, on_exit = again }
        end
    end
    g.after(0.3, again)
end

return M
