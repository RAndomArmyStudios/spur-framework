-- ============================================
-- HAIR FADES — the ones the character editor offers (HairFades)
-- ============================================
--
-- RedM (spur_core, 26 Nov 2026): whip_core listed GTA V's scalp fades here, another game's, and they are gone.
-- The list is empty until RDR2's are gathered, so the editor's Hair tab offers no fade and the server keeps
-- none (server/events_misc.lua, sanitizeAppearance). Data only.
--
-- collections   the decoration collections: { name = <the game's collection name>, label = <shown> }
-- list          one fade a line: { collection (its place in collections), overlay name, body ('m' | 'f' | 'mf') }
-- A saved fade is hairFade = { collection = <name>, overlay = <name> } in the character's appearance.

HairFades = {
    collections = {},
    list = {},
}
