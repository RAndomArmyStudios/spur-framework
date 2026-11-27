-- ============================================
-- spur_test — what the tests use on RedM
-- ============================================
--
-- RedM (spur_test, 23 Nov 2026): new file. whip_test named the original game's things in its tests; on RedM they are
-- RDR2's, kept here so a test reads the same either way.

--- The car the vehicle tests make, keep, lock and park: an RDR2 buggy. The original game's car isn't in this game, and
--- spur_core refuses a model the players' games haven't reported ("There is no vehicle called ...").
TEST_CAR_MODEL = 'buggy01'
--- The test car's passenger seat. whip_test took rear seat 1 (the original game slides a front passenger across into an empty
--- driver's seat). The buggy has a driver's seat and seat 0 only; RDR2 doesn't slide a passenger across.
TEST_CAR_PASSENGER_SEAT = 0
--- A second, different vehicle (whip_test used a police car and a sports car): the police wagon. Both are in
--- spur_core's RDR2 vehicle list (shared/rdr_compat.lua).
TEST_CAR_MODEL_2 = 'policewagon01x'

--- The people the Director tests place (whip_test's were business people): Valentine townsfolk.
TEST_PED_MODEL = 'a_m_m_valtownfolk_01'
TEST_PED_MODEL_F = 'a_f_m_valtownfolk_01'

--- A prop to place, show and hide (whip_test's were a barrel and a cardboard box): spur_core's own default ground prop.
TEST_PROP_MODEL = 'p_package01x'

--- A prop held in the hand through a progress bar (whip_test's was a beer bottle): the canteen, the 'drink' item's
--- prop, which spur_core lets a client bar hold (server/held_props.lua).
TEST_HELD_PROP = 'p_canteen01x'

--- Weapons: a revolver (whip_test's was a pistol), its model lying on the ground, and a melee
--- weapon (whip_test's was a bat).
TEST_WEAPON = 'WEAPON_REVOLVER_CATTLEMAN'
TEST_WEAPON_MODEL = 'w_revolver_cattleman01'
TEST_MELEE = 'WEAPON_MELEE_HATCHET'

--- Where the Director tests take the tester: open, flat ground with room to drive (the original game's was the airport, which
--- on RDR2's map is empty sky). Tried in order; the first that is flat where the tester lands is used
--- (server/director_kit.lua, DK.toField), and if none is, those tests are skipped with the reason. z is a height
--- to look down from, not the ground.
TEST_FIELDS = {
    { x = -175.0, y = 650.0, z = 160.0, heading = 230.0 },    -- the fields south-east of Valentine
    { x = 420.0, y = 520.0, z = 160.0, heading = 90.0 },      -- the Heartlands
    { x = -1150.0, y = -1650.0, z = 130.0, heading = 0.0 },   -- the Great Plains, south of Blackwater
    { x = 1450.0, y = 120.0, z = 140.0, heading = 0.0 },      -- below Emerald Ranch
}
