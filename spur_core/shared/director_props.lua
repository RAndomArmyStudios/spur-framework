-- Director props: the World tab's prop list (crates, barriers, loot, bags, tools, lights). Any model can still be
-- typed; the editor checks it against the player's game when placed (IsModelInCdimage).
--
-- DirectorProps.list: { model, category, name }. Categories group the list in the editor. `light` marks a lamp:
-- inside an interior it is filed as the furnisher files lamps (client/interior_rooms.lua).

DirectorProps = {}

DirectorProps.list = {
    -- boxes and crates
    { 'prop_box_wood02a',        'boxes',    'Wooden crate' },
    { 'prop_box_wood05a',        'boxes',    'Wooden crate, large' },
    { 'prop_crate_11e',          'boxes',    'Crate' },
    { 'prop_ld_crate_01',        'boxes',    'Crate with lid' },
    { 'prop_mil_crate_01',       'boxes',    'Military crate' },
    { 'prop_mil_crate_02',       'boxes',    'Military crate, long' },
    { 'prop_box_ammo04a',        'boxes',    'Ammo box' },
    { 'prop_box_ammo03a_set',    'boxes',    'Ammo boxes' },
    { 'prop_ld_ammo_pack_01',    'boxes',    'Ammo pack' },
    { 'prop_cs_cardbox_01',      'boxes',    'Cardboard box' },
    { 'prop_boxpile_06a',        'boxes',    'Box pile' },
    { 'prop_boxpile_07d',        'boxes',    'Box pile, tall' },
    { 'prop_cash_crate_01',      'boxes',    'Cash crate' },
    { 'prop_barrel_02a',         'boxes',    'Barrel' },
    { 'prop_barrel_01a',         'boxes',    'Barrel, old' },
    { 'prop_gascyl_01a',         'boxes',    'Gas cylinder' },
    { 'prop_jerrycan_01a',       'boxes',    'Jerry can' },
    { 'prop_container_01a',      'boxes',    'Shipping container' },

    -- barriers and the street
    { 'prop_barrier_work01a',    'barriers', 'Road barrier' },
    { 'prop_barrier_work05',     'barriers', 'Road barrier, long' },
    { 'prop_barrier_work06a',    'barriers', 'Road barrier, striped' },
    { 'prop_mp_barrier_02b',     'barriers', 'Barrier' },
    { 'prop_mp_arrow_barrier_01','barriers', 'Arrow barrier' },
    { 'prop_barrier_wat_03a',    'barriers', 'Water barrier' },
    { 'prop_mp_cone_01',         'barriers', 'Traffic cone' },
    { 'prop_roadcone01a',        'barriers', 'Road cone' },
    { 'prop_sign_road_03a',      'barriers', 'Road sign' },
    { 'prop_fncsec_03b',         'barriers', 'Security fence' },
    { 'prop_fnclink_02gate2',    'barriers', 'Chain-link gate' },
    { 'prop_atm_01',             'barriers', 'ATM' },
    { 'prop_parknmeter_01',      'barriers', 'Parking meter' },
    { 'prop_dumpster_01a',       'barriers', 'Dumpster' },
    { 'prop_rub_binbag_01',      'barriers', 'Bin bag' },
    { 'prop_rub_binbag_04',      'barriers', 'Bin bags' },
    { 'prop_bench_01a',          'barriers', 'Bench' },

    -- loot
    { 'prop_cash_pile_01',       'loot',     'Cash pile' },
    { 'prop_cash_pile_02',       'loot',     'Cash pile, large' },
    { 'prop_money_bag_01',       'loot',     'Money bag' },
    { 'prop_cash_case_01',       'loot',     'Cash case' },
    { 'prop_cash_case_02',       'loot',     'Cash case, open' },
    { 'hei_prop_hei_cash_trolly_01', 'loot', 'Cash trolley' },
    { 'prop_gold_bar',           'loot',     'Gold bar' },
    { 'prop_gold_trolly_full',   'loot',     'Gold trolley' },
    { 'prop_coke_block_01',      'loot',     'Coke block' },
    { 'prop_weed_block_01',      'loot',     'Weed block' },
    { 'prop_drug_package',       'loot',     'Drug package' },
    { 'prop_drug_package_02',    'loot',     'Drug package, small' },
    { 'hei_prop_hei_drug_case',  'loot',     'Drug case' },

    -- bags and cases
    { 'prop_cs_heist_bag_01',    'bags',     'Duffel bag' },
    { 'prop_cs_heist_bag_02',    'bags',     'Duffel bag, full' },
    { 'prop_ld_case_01',         'bags',     'Briefcase' },
    { 'prop_security_case_01',   'bags',     'Security case' },
    { 'prop_ld_suitcase_01',     'bags',     'Suitcase' },
    { 'prop_paper_bag_small',    'bags',     'Paper bag' },
    { 'prop_ld_purse_01',        'bags',     'Purse' },
    { 'prop_amb_handbag_01',     'bags',     'Handbag' },
    { 'prop_med_bag_01',         'bags',     'Medical bag' },
    { 'prop_ld_health_pack',     'bags',     'Health pack' },

    -- tools and tech
    { 'prop_tool_box_04',        'tools',    'Toolbox' },
    { 'prop_tool_bench02',       'tools',    'Work bench' },
    { 'prop_tool_drill',         'tools',    'Drill' },
    { 'prop_tool_jackham',       'tools',    'Jackhammer' },
    { 'prop_generator_03b',      'tools',    'Generator' },
    { 'prop_laptop_01a',         'tools',    'Laptop' },
    { 'prop_laptop_lester',      'tools',    'Laptop (Lester\'s)' },
    { 'prop_cs_tablet',          'tools',    'Tablet' },
    { 'prop_npc_phone',          'tools',    'Phone' },
    { 'prop_cs_hand_radio',      'tools',    'Hand radio' },
    { 'prop_ld_keypad_01',       'tools',    'Keypad' },
    { 'prop_cctv_cam_01a',       'tools',    'CCTV camera' },
    { 'hei_prop_heist_thermite', 'tools',    'Thermite' },
    { 'prop_c4_final',           'tools',    'C4 charge' },
    { 'prop_ld_bomb',            'tools',    'Bomb' },

    -- lights and camp
    { 'prop_worklight_02a',      'camp',     'Work light', light = true },
    { 'prop_worklight_03a',      'camp',     'Work light, standing', light = true },
    { 'prop_worklight_04a',      'camp',     'Work light, tall', light = true },
    { 'prop_flare_01',           'camp',     'Flare', light = true },
    { 'prop_beach_fire',         'camp',     'Camp fire' },
    { 'prop_hobo_stove_01',      'camp',     'Fire barrel' },
    { 'prop_skid_tent_01',       'camp',     'Tent' },
    { 'prop_table_03',           'camp',     'Table' },
    { 'prop_chair_01a',          'camp',     'Chair' },
    { 'prop_rub_couch04',        'camp',     'Old couch' },
}

DirectorProps.categories = {
    { id = 'boxes', label = 'Boxes and crates' },
    { id = 'barriers', label = 'Barriers and the street' },
    { id = 'loot', label = 'Loot' },
    { id = 'bags', label = 'Bags and cases' },
    { id = 'tools', label = 'Tools and tech' },
    { id = 'camp', label = 'Lights and camp' },
}

--- [model] = its entry, for a quick look-up.
DirectorProps.byModel = {}
for _, p in ipairs(DirectorProps.list) do DirectorProps.byModel[p[1]] = p end
