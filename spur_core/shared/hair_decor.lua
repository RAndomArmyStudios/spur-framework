-- ============================================
-- HAIR DECORATIONS — a scalp decoration put under a haircut (HairDecor)
-- ============================================
--
-- client/appearance.lua (applyTattoos) puts one on when the character has no hair fade of their own
-- (`hairFade`, shared/hair_fades.lua), so the hair blends into the scalp. It is never saved: it follows the cut.
--
-- RedM (spur_core, 26 Nov 2026): whip_core's table was GTA V's (its online barber's decorations), another game's,
-- and is gone. Empty, with no fallback: no haircut gets one.
--
-- byBody[body][drawable] = { collection, overlay }, or false for "no decoration" (a bald head, say).
-- A drawable not listed is looked up in the game's own shop data (client/appearance.lua, hairDecorFor), and
-- failing that gets `fallback` ({ collection, overlay }, or nil for nothing). Data and one lookup only.

HairDecor = {
    fallback = nil,
    byBody = { m = {}, f = {} },
}

--- This table's entry for a haircut.
---@param body string    'm' | 'f'
---@param drawable number the hair component's drawable
---@return table|false|nil  { collection, overlay }; false: no decoration; nil: not listed (ask the game, then `fallback`)
function HairDecor.listed(body, drawable)
    local t = HairDecor.byBody[body]
    if not t then return nil end
    return t[tonumber(drawable) or -1]
end
