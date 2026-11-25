--!strict
-- Bioma's look, so the window reads as part of the shell: the colours
-- derived as Bioma derives them (genoma/core/theme.luau there) from the
-- desktop theme the kit follows, its two voices and its measures.
local g = require("@genoma")
local kit = require("@genoma/kit")

local theme = kit.theme

local M = {}

M.CLEAR = "#00000000"

function M.background(): string return theme.get("background") end
function M.text(): string return theme.get("text") end
function M.primary(): string return theme.get("accent") end

function M.is_dark(): boolean
    local d = theme.desktop()
    if d and type(d.dark) == "boolean" then return d.dark end
    return g.colour.luma(M.background()) < 0.5
end

-- Technical: what the machine measures. Expressive: names, what comes from
-- a person.
function M.technical(): string
    local d = theme.desktop()
    return (d and d.fonts and d.fonts.technical) or "Orbitron"
end
function M.expressive(): string
    local d = theme.desktop()
    return (d and d.fonts and d.fonts.expressive) or "Spectral"
end

local function lift(hex: string, amount: number): string
    return g.colour.lift(hex, amount, M.is_dark())
end

-- The outline's family: three lightnesses of the background's hue, never
-- the primary's.
local function structural(lightness: number): string
    local bg, accent = M.background(), M.primary()
    local bh, bs = g.colour.hsl(bg)
    if bh < 0 or bs <= 0 then
        return g.colour.hsla(0, 0, lightness, 1)
    end
    local _, as = g.colour.hsl(accent)
    local s = math.max(math.min(bs + 0.04, 0.40), math.min(as * 0.33, 0.28))
    return g.colour.hsla(bh, s, lightness, 1)
end

function M.cell(): string return lift(M.background(), 0.075) end
function M.line(): string return structural(if M.is_dark() then 0.32 else 0.72) end
function M.node(): string return structural(if M.is_dark() then 0.43 else 0.62) end
function M.rim(): string return structural(if M.is_dark() then 0.55 else 0.50) end
function M.text_muted(): string return g.colour.alpha(M.text(), 0.70) end
function M.text_faint(): string return g.colour.alpha(M.text(), 0.54) end

-- One light, from above: lighter at the top, darker at the bottom.
function M.gradient_top(hex: string): string
    local h, s, l, a = g.colour.hsl(hex)
    return g.colour.hsla(math.max(0, h), math.min(1, s + 0.14), math.min(1, l + 0.16), a)
end
function M.gradient_bottom(hex: string): string
    local h, s, l, a = g.colour.hsl(hex)
    return g.colour.hsla(math.max(0, h), math.max(0, s - 0.15), math.max(0, l - 0.15), a)
end
function M.primary_top(): string return M.gradient_top(M.primary()) end
function M.primary_bottom(): string return M.gradient_bottom(M.primary()) end

-- A cell's glass (cell.opacity 0.72 in Bioma), and one that floats over
-- names, which must not be read through it.
function M.glass(): string return g.colour.alpha(M.cell(), 0.72) end
function M.glass_over(): string return g.colour.alpha(M.cell(), 0.94) end
-- What is under the pointer, what the keys stand on.
function M.hovered(): string return g.colour.alpha(M.text(), 0.06) end
function M.chosen(): string return g.colour.alpha(M.primary(), 0.16) end

-- Bioma's measures at the normal density.
M.cell_height = 40
M.row_height = 30
M.radius_panel = 20
M.radius_well = 10
M.margin_edge = 12
M.gap = 12
M.thread = 1.3
M.font_label = 15
-- The names of files: 15, chosen beside Nautilus (Akusen, 2026-11-25).
-- Spectral's letters are low (an x-height of 0.45 against 0.55), so at the
-- same size it is read smaller; a weight more, so it is read as dark.
M.font_name = 15
M.weight_name = 500
M.font_text = 14
M.font_menu = 13
M.font_secondary = 13
M.font_meta = 11
M.label_tracking = 0.06
M.glass_blur = 14

-- The one place a duration is written.
g.timing {
    ui_change = { duration = 0.18, curve = { 0.2, 0, 0, 1 } },
    cell_open = { duration = 0.25, curve = { 0.2, 0.9, 0.3, 1 } },
    cell_close = { duration = 0.15, curve = { 0.5, 0, 0.9, 0.5 } },
    -- A shoot budding out of the capsule before it, each a little after the
    -- one it grows from; its words once it is at size, its thread as the neck
    -- thins (below). Coming back the words go first, then the thread, then the
    -- shape; of several, the last one first.
    content_in = { duration = 0.12, delay = 0.12, curve = { 0.2, 0, 0, 1 } },
    content_out = { duration = 0.06, curve = { 0.4, 0, 1, 1 } },
    -- Put where it is to grow from, before it is seen.
    placed = { duration = 0, curve = { 0, 0, 1, 1 } },
    folder_in = { duration = 0.16, curve = { 0.2, 0, 0, 1 } },
}
M.CLOSE = 0.16
-- How long `n` shoots take to go back.
local BACK, AFTER = 0.28, 0.12
function M.shoots_back(n: number): number return BACK + (math.min(n, 5) - 1) * AFTER end

-- How many shoots that come together wait their turn.
M.TURNS = 5
do
    local SHAPE, STAGGER = 0.36, 0.16
    local set: { [string]: any } = {}
    for i = 1, M.TURNS do
        local back = (i - 1) * AFTER
        set["shoot_close_" .. i] = { duration = 0.2, delay = back + 0.06, curve = { 0.5, 0, 0.8, 0.6 } }
        set["neck_close_" .. i] = { duration = 0.14, delay = back + 0.06, curve = { 0.2, 0, 0.4, 1 } }
        set["thread_close_" .. i] = { duration = 0.08, delay = back, curve = { 0.5, 0, 0.9, 0.5 } }
        local from = (i - 1) * STAGGER
        -- Slow to leave, so the neck is seen, and it parts last.
        set["shoot_" .. i] = { duration = SHAPE, delay = from, curve = { 0.45, 0.05, 0.2, 1 } }
        set["neck_" .. i] = { duration = SHAPE, delay = from + SHAPE * 0.15, curve = { 0.6, 0, 0.5, 1 } }
        set["thread_" .. i] = { duration = 0.12, delay = from + SHAPE * 0.7, curve = { 0.2, 0.9, 0.3, 1 } }
        set["shoot_words_" .. i] = { duration = 0.12, delay = from + SHAPE * 0.6, curve = { 0.2, 0, 0, 1 } }
    end
    g.timing(set)
end

return M
