--!strict
-- Bioma's controls (genoma/components there: segmented, slider, switch,
-- choice), as far as they serve here, on ui/look.
local g = require("@genoma")
local look = require("ui/look")

local M = {}

local CLEAR = look.CLEAR

-- A drawing of the app's own, tinted as Bioma tints its glyphs. `lit()`:
-- in the primary's light; otherwise in one quiet colour.
function M.glyph(name: string, size: number, lit: (() -> boolean)?, quiet: (() -> string)?): any
    local faint = quiet or look.text_muted
    local function on(): boolean return lit == nil or (lit :: any)() end
    return g.svg {
        width = size,
        height = size,
        src = g.dir .. "/icons/" .. name .. ".svg",
        gradient_top = function() return if on() then look.primary_top() else faint() end,
        gradient_bottom = function() return if on() then look.primary_bottom() else faint() end,
    }
end

-- Upper-case, technical, spaced.
function M.label(text: string | () -> string, colour: (() -> string)?): any
    return g.text {
        text = function()
            return string.upper(if type(text) == "function" then text() else text)
        end,
        color = colour or look.text,
        font = look.technical,
        size = look.font_meta,
        weight = 500,
        tracking = look.label_tracking,
    }
end

-- A round button of a cell's height, with a drawing.
-- t: id, name, glyph, on_click, lit(), disabled(), present(), size, props.
function M.round(t: { [string]: any }): any
    local size = t.size or look.cell_height
    local over = g.signal(false)
    local function off(): boolean return t.disabled ~= nil and t.disabled() end
    local function lit(): boolean return t.lit ~= nil and t.lit() end
    local node: { [any]: any } = {
        id = t.id,
        role = "button",
        name = t.name,
        present = t.present,
        width = size,
        height = size,
        radius = size / 2,
        align = "center",
        justify = "center",
        fill = function()
            if lit() then return look.chosen() end
            return if over.value and not off() then look.cell() else look.glass()
        end,
        rim_top = function() return if lit() then look.primary() else look.rim() end,
        rim_bottom = function() return if lit() then look.primary() else look.line() end,
        opacity = function() return if off() then 0.45 else 1 end,
        transition = { fill = "ui_change", rim_top = "ui_change", rim_bottom = "ui_change", opacity = "ui_change" },
        on_hover = function(on: boolean) over.value = on end,
        on_press = function() end,
        on_click = function(button: number)
            if button == 272 and not g.untracked(off) then t.on_click() end
        end,
        M.glyph(t.glyph, t.glyph_size or 18, function() return not off() end, look.text_faint),
    }
    for k, v in t.props or {} do node[k] = v end
    return g.capsule(node)
end

-- One of a few: a track, the choice in a pill of the primary that slides.
-- t: options { { key, label } }, current(), on_choose(key).
function M.segmented(t: { [string]: any }): any
    local SIZE, PAD, GAP, H = 11, 3, 2, 24
    local function width_of(o: any): number
        return g.text_width { text = string.upper(o.label), font = look.technical(), size = SIZE, weight = 700, tracking = 0.04 } + 24
    end
    local function selection(): (number, number)
        local x = 0
        for _, o in t.options do
            local w = width_of(o)
            if o.key == t.current() then return x, w end
            x += w + GAP
        end
        return 0, 0
    end
    local function track_width(): number
        local w = 0
        for i, o in t.options do w += width_of(o) + (if i > 1 then GAP else 0) end
        return w + PAD * 2
    end
    local items: { [any]: any } = { overlay = true, attach = "corner", offset_x = PAD, offset_y = PAD, direction = "row", gap = GAP }
    for _, o in t.options do
        local function chosen(): boolean return o.key == t.current() end
        table.insert(items, g.box {
            id = if t.id then `{t.id}-{o.key}` else nil,
            role = "button",
            name = o.label,
            width = function() return width_of(o) end,
            height = H,
            align = "center",
            justify = "center",
            on_click = function() t.on_choose(o.key) end,
            g.text {
                text = string.upper(o.label),
                color = function() return if chosen() then look.background() else look.text_muted() end,
                font = look.technical,
                size = SIZE,
                weight = 700,
                tracking = 0.04,
                transition = { color = "ui_change" },
            },
        })
    end
    return g.capsule {
        role = "group",
        width = track_width,
        height = H + PAD * 2,
        radius = (H + PAD * 2) / 2,
        fill = function() return g.colour.alpha(look.background(), 0.8) end,
        rim_top = look.node,
        rim_bottom = look.node,
        g.capsule {
            overlay = true,
            attach = "corner",
            present = function() local _, w = selection() return w > 0 end,
            offset_x = function() local x = selection() return PAD + x end,
            offset_y = PAD,
            width = function() local _, w = selection() return w end,
            height = H,
            radius = H / 2,
            fill = look.primary_top,
            fill_bottom = look.primary_bottom,
            rim_top = CLEAR,
            rim_bottom = CLEAR,
            transition = { offset_x = "ui_change", width = "ui_change" },
        },
        g.box(items),
    }
end

-- t: id, name, on(), on_toggle(on).
function M.switch(t: { [string]: any }): any
    local W, H, KNOB = 42, 24, 16
    local INSET = (H - KNOB) / 2
    return g.capsule {
        id = t.id,
        role = "button",
        name = t.name,
        width = W,
        height = H,
        radius = H / 2,
        fill = function() return if t.on() then look.primary_top() else g.colour.alpha(look.background(), 0.9) end,
        fill_bottom = function() return if t.on() then look.primary_bottom() else g.colour.alpha(look.background(), 0.9) end,
        rim_top = function() return if t.on() then CLEAR else look.node() end,
        rim_bottom = function() return if t.on() then CLEAR else look.node() end,
        transition = { fill = "ui_change", fill_bottom = "ui_change", rim_top = "ui_change", rim_bottom = "ui_change" },
        on_click = function() t.on_toggle(not g.untracked(t.on)) end,
        g.capsule {
            overlay = true,
            attach = "corner",
            width = KNOB,
            height = KNOB,
            radius = KNOB / 2,
            offset_x = function() return if t.on() then W - KNOB - INSET else INSET end,
            offset_y = INSET,
            fill = function() return if t.on() then look.background() else g.colour.alpha(look.text(), 0.45) end,
            rim_top = CLEAR,
            rim_bottom = CLEAR,
            transition = { offset_x = "ui_change", fill = "ui_change" },
        },
    }
end

-- A level: a thin track, what is behind the handle in the primary.
-- t: id, name, width, value() 0…1, step, on_move(v).
function M.slider(t: { [string]: any }): any
    local TRACK, HANDLE = 3, 14
    local held = false
    local function travel(): number return math.clamp(t.value(), 0, 1) end
    local function report(x: number) t.on_move(math.clamp(x / t.width, 0, 1)) end
    return g.box {
        id = t.id,
        role = "slider",
        name = t.name,
        width = t.width,
        height = HANDLE,
        on_press = function(button: number, x: number)
            if button ~= 272 then return end
            held = true
            report(x)
        end,
        on_drag = function(x: number) if held then report(x) end end,
        on_release = function() held = false end,
        on_click = function() end,
        on_wheel = function(_: number, dy: number): boolean
            local step = t.step or 0.05
            t.on_move(math.clamp(g.untracked(t.value) + (if dy < 0 then step else -step), 0, 1))
            return true
        end,
        g.capsule {
            overlay = true,
            attach = "corner",
            offset_y = (HANDLE - TRACK) / 2,
            width = t.width,
            height = TRACK,
            radius = TRACK / 2,
            fill = function() return g.colour.alpha(look.line(), 0.55) end,
            rim_top = CLEAR,
            rim_bottom = CLEAR,
        },
        g.capsule {
            overlay = true,
            attach = "corner",
            offset_y = (HANDLE - TRACK) / 2,
            width = function() return t.width * travel() end,
            height = TRACK,
            radius = TRACK / 2,
            fill = look.primary_top,
            fill_bottom = look.primary_bottom,
            rim_top = CLEAR,
            rim_bottom = CLEAR,
        },
        g.capsule {
            overlay = true,
            attach = "corner",
            offset_x = function() return t.width * travel() - HANDLE / 2 end,
            width = HANDLE,
            height = HANDLE,
            radius = HANDLE / 2,
            fill = look.primary_top,
            fill_bottom = look.primary_bottom,
            rim_top = CLEAR,
            rim_bottom = CLEAR,
        },
    }
end

-- An answer: the primary's light for the one that does something, an
-- outline for the way back.
-- t: id, label, primary, on_click.
function M.choice(t: { [string]: any }): any
    local over = g.signal(false)
    local H = 26
    return g.capsule {
        id = t.id,
        role = "button",
        name = t.label,
        height = H,
        padding_x = 14,
        radius = H / 2,
        align = "center",
        justify = "center",
        fill = function()
            if t.primary then return look.primary_top() end
            return if over.value then look.hovered() else CLEAR
        end,
        fill_bottom = function()
            if t.primary then return look.primary_bottom() end
            return if over.value then look.hovered() else CLEAR
        end,
        rim_top = function() return if t.primary then CLEAR else look.node() end,
        rim_bottom = function() return if t.primary then CLEAR else look.node() end,
        on_hover = function(on: boolean) over.value = on end,
        on_press = function() end,
        on_click = function() t.on_click() end,
        M.label(t.label, function() return if t.primary then look.background() else look.text() end),
    }
end

return M
