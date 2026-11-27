--!strict
-- Archives, as Nautilus has them: one opened is extracted beside itself
-- (one thing alone as itself, more in a folder named after the archive);
-- "Extract here", "Extract to…" and "Compress…" from the right button. The
-- work is @genoma/files's (libarchive): a job like a copy, in the jobs cell,
-- that asks for a password when an archive is locked.
local g = require("@genoma")
local files = require("@genoma/files")
local mime = require("@genoma/mime")
local portal = require("@genoma/portal")
local browser = require("core/browser")
local operations = require("core/operations")
local paths = require("core/paths")

local M = {}

-- What can be opened: every kind libarchive reads that is an archive
-- (a disk image is mounted, not extracted; a package is installed).
M.TYPES = {
    "application/zip", "application/x-zip-compressed",
    "application/x-tar", "application/x-compressed-tar", "application/x-xz-compressed-tar",
    "application/x-zstd-compressed-tar", "application/x-bzip2-compressed-tar", "application/x-bzip-compressed-tar",
    "application/x-lzma-compressed-tar", "application/x-lz4-compressed-tar", "application/x-lzip-compressed-tar",
    "application/x-7z-compressed", "application/vnd.rar", "application/x-rar", "application/x-rar-compressed",
    "application/gzip", "application/x-gzip", "application/x-bzip2", "application/x-bzip", "application/x-xz",
    "application/zstd", "application/x-zstd", "application/x-lzma", "application/x-lzip",
    "application/x-cpio", "application/x-archive",
}
local KNOWN: { [string]: boolean } = {}
for _, t in M.TYPES do KNOWN[t] = true end

function M.is(e: any): boolean
    return e ~= nil and not e.dir and not e.deleted and KNOWN[e.mime or ""] == true
end

-- Whether a path is one, by what it is.
function M.is_path(path: string): boolean
    local ok, t = pcall(function() return mime:of(path) end)
    return ok and KNOWN[t or ""] == true
end

local function arrived(result: any)
    if result and not result.cancelled and #result.made > 0 then operations.arrive(result.made) end
end

-- Opened, it is extracted where Rizoma is what opens it, or nothing is.
browser.extracts = function(e: any): boolean
    if not M.is(e) then return false end
    local ok, app = pcall(function() return mime:default(e.mime) end)
    if ok and app and app.id ~= "dev.akusen.rizoma" then return false end
    M.extract({ e.path })
    return true
end

-- Each into the folder it is in, or `to`.
function M.extract(list: { string }, to: string?)
    for _, p in list do
        files:extract(p, to or paths.parent(p) or "/", arrived)
    end
end

-- Each into a folder chosen (the desktop's chooser), from where they are.
function M.extract_to(list: { string })
    if #list == 0 then return end
    portal:open_file({
        title = if #list == 1 then "Extract to" else `Extract {#list} archives to`,
        accept = "Extract",
        folders = true,
        folder = paths.parent(list[1]) or g.untracked(function() return browser.here.value end),
    }, function(chosen: { string }?)
        if chosen and chosen[1] then M.extract(list, chosen[1]) end
    end)
end

-- The kinds an archive is made as, Nautilus's three: one every system opens,
-- the smaller ones, and the zip locked by a password.
export type Kind = { key: string, ending: string, label: string, says: string, locks: boolean? }
M.KINDS = {
    { key = "zip", ending = ".zip", label = ".zip", says = "Opens on every system." },
    { key = "zip_locked", ending = ".zip", label = "Locked .zip", says = "Opens only with the password, on every system.", locks = true },
    { key = "tar.xz", ending = ".tar.xz", label = ".tar.xz", says = "Smaller. Opens on Linux and macOS as it is." },
    { key = "7z", ending = ".7z", label = ".7z", says = "Smaller. Windows and macOS need a program for it." },
} :: { Kind }
function M.kind(key: string): Kind
    for _, k in M.KINDS do
        if k.key == key then return k end
    end
    return M.KINDS[1]
end

-- The name proposed, without its ending: one thing's own (a file's
-- without its own ending), else the folder they are in. `entries`: the
-- browser's, what is selected.
function M.proposed(entries: { any }): string
    if #entries == 1 then
        local e = entries[1]
        local name = e.name or paths.name(e.path)
        local dot = string.find(name, "%.[^.]*$")
        if not e.dir and dot and dot > 1 then return string.sub(name, 1, dot - 1) end
        return name
    end
    local folder = if entries[1] then paths.parent(entries[1].path) or "/" else paths.home
    return if folder == paths.home then "Archive" else paths.name(folder)
end

-- `list` into "<name><ending>" in `folder`.
function M.compress(list: { string }, folder: string, name: string, key: string, password: string?)
    local k = M.kind(key)
    local archive = folder .. "/" .. name .. k.ending
    files:compress(list, archive, if k.locks and password and password ~= "" then { password = password } else nil, arrived)
end

return M
