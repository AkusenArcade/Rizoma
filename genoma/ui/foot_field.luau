--!strict
-- A button in the foot that becomes the field it opens.
local g = require("@genoma")
local look = require("ui/look")
local ui = require("ui/controls")

local M = {}

local H, PAD, GLYPH, GAP, STOP = look.action_height, 14, 16, 8, 24

function M.word(label: string): number
    return g.text_width { text = string.upper(label), font = look.technical(), size = look.font_action, weight = 700, tracking = 0.04 }
end
-- How wide the button is.
function M.width(label: string, bare: boolean): number
    return if bare then H else math.ceil(M.word(label)) + PAD * 2 + GLYPH + GAP
end

-- `t`: id, label, glyph, dashed, open(), on_open(), bare(), room() the field's
-- width, text(), on_change(text), on_submit(), on_stop(), placeholder, stop (what
-- its closing button is called), focused(), on_take() a press in it, select,
-- wrong().
function M.new(t: { [string]: any }): any
    local over = g.signal(false)
    local function on(): boolean return t.open() end
    local function bare(): boolean return t.bare() end
    local function edge(): string
        if on() then return if t.wrong and t.wrong() then look.node() else look.primary() end
        if over.value then return look.primary() end
        return if t.dashed then g.colour.alpha(look.node(), 0.7) else look.node()
    end
    local function ink(): string return if t.dashed and over.value then look.primary() else look.text() end
    local node: { [any]: any } = {
        id = t.id,
        role = "button",
        name = t.label,
        width = function() return if on() then t.room() else M.width(t.label, bare()) end,
        height = H,
        radius = look.round(H / 2),
        clip = true,
        fill = function() return if on() then look.glass() else look.CLEAR end,
        rim_top = edge,
        rim_bottom = edge,
        transition = { width = function() return if on() then "cell_open" else "cell_close" end, fill = "ui_change", rim_top = "ui_change", rim_bottom = "ui_change" },
        on_hover = function(o: boolean) over.value = o end,
        on_press = function() end,
        on_click = function(button: number)
            if button == 272 and not g.untracked(on) then t.on_open() end
        end,
        g.box {
            overlay = true,
            attach = "corner",
            offset_x = function() return if bare() and not on() then (H - GLYPH) / 2 else PAD end,
            height = H,
            direction = "row",
            align = "center",
            gap = GAP,
            ui.glyph(t.glyph, GLYPH, on, ink),
            g.text {
                present = function() return not on() and not bare() end,
                text = string.upper(t.label),
                color = ink,
                font = look.technical,
                size = look.font_action,
                weight = 500,
                tracking = 0.04,
            },
            g.field {
                id = t.id .. "-field",
                present = on,
                width = function() return t.room() - PAD * 2 - GLYPH - GAP - STOP end,
                size = look.font_label,
                font = look.expressive,
                color = look.text,
                caret_color = look.primary,
                selection_color = look.chosen,
                placeholder = t.placeholder,
                on_press = function() if t.on_take then t.on_take() end end,
                select = t.select or "none",
                focused = function() return on() and t.focused() end,
                text = t.text,
                on_change = t.on_change,
                on_submit = t.on_submit,
            },
            g.box {
                id = t.id .. "-stop",
                role = "button",
                name = t.stop,
                present = on,
                width = STOP,
                height = H,
                align = "center",
                justify = "center",
                on_press = function() end,
                on_click = function() t.on_stop() end,
                ui.glyph("close", 14, function() return false end, look.text_muted),
            },
        },
    }
    if t.dashed then
        node.dash = function() return if on() then 0 else 3 end
        node.dash_gap = 3
    end
    return g.capsule(node)
end

return M
