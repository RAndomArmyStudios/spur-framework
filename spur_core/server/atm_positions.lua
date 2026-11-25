-- ============================================
-- ATM POSITIONS — server/atm_positions.lua (generated: do not edit by hand)
-- ============================================
--
-- Every cash machine GTA V places in its own map (prop_atm_01, prop_atm_02, prop_atm_03, prop_fleeca_atm), outdoors and
-- inside its interiors (an interior's machines turned and moved to where that interior stands), read from the game's
-- map files. The point is the machine's base, on the floor. 121 machines. Machines a map mod or an MLO adds are not here:
-- config.lua's Config.AtmExtraPositions adds them. Read by server/atm.lua (IsNearAtm, GetNearestAtm).

-- RedM (spur_core, 23 Nov 2026): the list above was GTA V's machines; RDR2 has none, so it is empty. Positions go in
-- config.lua's Config.AtmExtraPositions.
AtmPositions = {}
