--!strict
-- What has to be said once: a file nothing opens, a question before a program
-- runs. `act` is what its button does.
local g = require("@genoma")

local M = {}

-- `passing`: offered, not asked: it goes by itself.
-- `grave`: what it asks cannot be undone.
export type Notice = { text: string, label: string?, act: (() -> ())?, passing: boolean?, grave: boolean? }

M.now = g.signal(nil :: Notice?)
local quiet: any = nil
function M.say(notice: Notice?)
    if quiet then quiet:stop() end
    quiet = nil
    M.now.value = notice
    -- A question waits for its answer; the rest goes by itself.
    if notice and (notice.act == nil or notice.passing) then
        quiet = g.after(if notice.passing then 8 else 5, function()
            quiet = nil
            M.now.value = nil
        end)
    end
end

return M
