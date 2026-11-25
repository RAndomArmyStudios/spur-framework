-- ============================================
-- GTA STORES — server/gta_stores.lua: the game's own 24/7s and LTDs, as whip shops
-- ============================================
--
-- Opened by Config.GtaStores (config.lua; on for a server WHIP's txAdmin recipe sets up). Each is made once, under
-- its key, when no shop has it (Shops.seedFromConfig), and is then a shop like any other: moved, priced and
-- stocked in /whip > Economy > Shops.
--
-- WHERE THE KEEPER STANDS, worked out from the game's own map: each store's interior as GTA places it (a v_shop_247
-- or a v_gasstation, its position and rotation in the map files) and that interior's first till (prop_till_01, from
-- its own entity list), half a metre behind it, facing the customers. The same spot in every copy of the room.

-- RedM (spur_core, 23 Nov 2026): empty. The 24/7s and LTDs above were GTA's map; RDR2's general stores are
-- interiors of their own, so Config.GtaStores on makes nothing. Set up stores in /whip > Economy > Shops.
GtaStores = {}
