-- ============================================
-- TATTOOS — the ones the character editor offers (TattooList)
-- ============================================
--
-- RedM (spur_core, 26 Nov 2026): whip_core listed the original game's tattoos here (its tattoo shops' names and
-- collections), and they are gone. The list is empty until RDR2's are gathered, so the
-- editor offers none and the server keeps none (server/events_misc.lua, sanitizeAppearance). Data only.
--
-- collections   the decoration collections: { name = <the game's collection name>, label = <shown> }
-- list          one tattoo a line: { collection (its place in collections), overlay name,
--               zone ('head' | 'torso' | 'larm' | 'rarm' | 'lleg' | 'rleg'),
--               body ('m' | 'f' | 'mf'),
--               facing (the side it is on: 'front', 'back', 'left', 'right', 'frontleft', 'frontright',
--                       'chest', 'stomach', or ''),
--               name (its name, or '') }
-- A saved tattoo is { collection = <name>, overlay = <name> } in the character's appearance.

TattooList = {
    collections = {},
    list = {},
}
