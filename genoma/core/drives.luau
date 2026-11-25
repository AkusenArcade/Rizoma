--!strict
-- The disks plugged in: each volume a place, whether it is mounted or not.
local g = require("@genoma")
local service = require("@genoma/drives")
local notice = require("core/notice")
local panes = require("core/panes")
local paths = require("core/paths")

local M = {}

-- `used`: how full, 0 to 1, nil while it is not known. `writing`: it is not
-- safe to pull. `busy` is what is being done to it, "" nothing.
export type Volume = {
    id: string,
    device: string,
    name: string,
    mount: string?,
    size: number,
    kind: string,
    used: number?,
    writing: boolean,
    busy: string,
}

-- Less is the disk's own bookkeeping.
local WRITING = 4096

M.list = g.computed(function(): { Volume }
    local out: { Volume } = {}
    for _, d in service.list do
        for _, v in d.volumes do
            local mount = v.mounts[1]
            table.insert(out, {
                id = d.id,
                device = v.device,
                name = if v.label ~= "" then v.label else d.name,
                mount = mount,
                size = v.size,
                kind = v.kind,
                used = if mount and v.free and v.size > 0 then math.clamp(1 - v.free / v.size, 0, 1) else nil,
                writing = d.rate >= WRITING,
                busy = d.busy,
            })
        end
    end
    return out
end)

local function now(device: string): Volume?
    for _, v in g.untracked(function() return M.list.value end) do
        if v.device == device then return v end
    end
    return nil
end

-- Gone to, mounted first when it is not. `beside`: in a tab of its own.
local wanted: { device: string, beside: boolean }? = nil
local function go(path: string, beside: boolean?)
    if beside then panes.new_tab(path, true) else g.untracked(panes.active).go(path) end
end
function M.open(device: string, beside: boolean?)
    local v = now(device)
    if v == nil or v.busy ~= "" then return end
    if v.mount then
        go(v.mount, beside)
    else
        wanted = { device = device, beside = beside == true }
        service:mount(device)
    end
end
function M.unmount(device: string) service:unmount(device) end
function M.eject(id: string) service:eject(id) end

-- What it was mounted for; and a folder on one that is no more is left.
local mounted: { [string]: boolean } = {}
g.effect(function()
    local list = M.list.value
    g.untracked(function()
        local still: { [string]: boolean } = {}
        for _, v in list do
            if v.mount then still[v.mount] = true end
            if wanted and wanted.device == v.device and v.mount then
                local beside = wanted.beside
                wanted = nil
                go(v.mount, beside)
            end
        end
        for mount in mounted do
            if still[mount] then continue end
            for _, t in panes.tabs.value do
                for _, p in t.panes.value do
                    if paths.inside(p.here.value, mount) then p.go("~") end
                end
            end
        end
        mounted = still
    end)
end)

-- Why something could not be done, said once.
local told: { [string]: string } = {}
g.effect(function()
    for _, d in service.list do
        local why = d.error
        if why ~= "" and told[d.id] ~= why then
            wanted = nil
            notice.say { text = `{d.name}: {why}` }
        end
        told[d.id] = why
    end
end)

return M
