--!strict
-- What is selected in the pane that has the keys (core/selecting).
local panes = require("core/panes")

return panes.facade(function(p: any): any return p.selection end, {})
