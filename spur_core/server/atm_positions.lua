-- ============================================
-- ATM POSITIONS — server/atm_positions.lua
-- ============================================
--
-- The cash machines the game's own map places, each by its base on the floor. Read by server/atm.lua (IsNearAtm,
-- GetNearestAtm). Machines a map mod or an MLO adds go in config.lua's Config.AtmExtraPositions.

-- RedM (spur_core, 23 Nov 2026): whip_core's list was the original game's machines, read from its map files. RDR2's map
-- has none, so it is empty. Positions go in config.lua's Config.AtmExtraPositions.
AtmPositions = {}
