-- spur_gunny: THE WEAPONS, one item per RDR2 weapon
--
-- RedM (spur_gunny, 24 Nov 2026): rewritten. whip_gunny's 100+ GTA weapons (and its remodelled add-on ones) are
-- replaced by RDR2's own, by their game names. Nothing is streamed: the game draws every one of them.
--
-- Fields:
--   weapon       the game's weapon name (WEAPON_...): what is put in the hands
--   label        the item's name
--   kind         'gun' (fired, loaded with loose cartridges), 'bow' (shoots arrows carried as items), 'melee'
--                (swung: no rounds) or 'throwable' (a stack: each one thrown is taken from it)
--   group        a gun's or bow's cartridges (items/ammo.lua Config.AmmoGroups)
--   capacity     the cartridges a gun holds (the server's number). The game's own clip size is compared with it as
--                the gun is drawn, and a difference is said in F8 with Gunny Debug on: UNTESTED against the game.
--   weight       kg
--   prop         the model it lies on the ground as (spur_core's default when nil). UNTESTED: the world models of
--                the base guns, from RDR2's data; the variants use their base gun's.
--   maxStack     a throwable's stack (25 if not said)
--   description  the item's text

Config.Weapons = {}

local function gun(item, weapon, label, group, capacity, weight, prop, description)
    Config.Weapons[item] = { weapon = weapon, label = label, kind = 'gun', group = group, capacity = capacity,
                             weight = weight, prop = prop, description = description }
end

local function bow(item, weapon, label, description)
    Config.Weapons[item] = { weapon = weapon, label = label, kind = 'bow', group = 'arrow', weight = 1.0,
                             description = description }
end

local function melee(item, weapon, label, weight, description)
    Config.Weapons[item] = { weapon = weapon, label = label, kind = 'melee', weight = weight, description = description }
end

local function throwable(item, weapon, label, weight, maxStack, description)
    Config.Weapons[item] = { weapon = weapon, label = label, kind = 'throwable', weight = weight, maxStack = maxStack,
                             description = description }
end

-- Revolvers
gun('gunny_cattleman', 'WEAPON_REVOLVER_CATTLEMAN', 'Cattleman Revolver', 'revolver', 6, 1.1, 'w_revolver_cattleman01',
    'A single-action revolver: dependable, and found everywhere.')
gun('gunny_cattleman_mexican', 'WEAPON_REVOLVER_CATTLEMAN_MEXICAN', 'Cattleman Revolver (Mexican)', 'revolver', 6, 1.1,
    'w_revolver_cattleman01', 'A Cattleman with Mexican engraving.')
gun('gunny_doubleaction', 'WEAPON_REVOLVER_DOUBLEACTION', 'Double-Action Revolver', 'revolver', 6, 1.0,
    'w_revolver_doubleaction01', 'Fires as fast as the trigger is pulled.')
gun('gunny_doubleaction_gambler', 'WEAPON_REVOLVER_DOUBLEACTION_GAMBLER', 'Double-Action Revolver (Gambler)', 'revolver', 6,
    1.0, 'w_revolver_doubleaction01', 'A gambler\'s Double-Action.')
gun('gunny_lemat', 'WEAPON_REVOLVER_LEMAT', 'LeMat Revolver', 'revolver', 9, 1.6, 'w_revolver_lemat01',
    'Nine chambers around a heavy frame.')
gun('gunny_navy', 'WEAPON_REVOLVER_NAVY', 'Navy Revolver', 'revolver', 6, 1.2, 'w_revolver_navy01',
    'A converted cap-and-ball revolver with a long reach.')
gun('gunny_navy_crossover', 'WEAPON_REVOLVER_NAVY_CROSSOVER', 'Navy Revolver (Crossover)', 'revolver', 6, 1.2,
    'w_revolver_navy01', 'A Navy Revolver with a crossover finish.')
gun('gunny_schofield', 'WEAPON_REVOLVER_SCHOFIELD', 'Schofield Revolver', 'revolver', 6, 1.2, 'w_revolver_schofield01',
    'A top-break revolver: quick to reload.')

-- Pistols
gun('gunny_m1899', 'WEAPON_PISTOL_M1899', 'M1899 Pistol', 'pistol', 8, 0.9, 'w_pistol_m189902',
    'The newest pistol money can buy.')
gun('gunny_mauser', 'WEAPON_PISTOL_MAUSER', 'Mauser Pistol', 'pistol', 10, 1.2, 'w_pistol_mauser01',
    'A German pistol with a ten-round box.')
gun('gunny_semiauto', 'WEAPON_PISTOL_SEMIAUTO', 'Semi-Automatic Pistol', 'pistol', 8, 0.9, 'w_pistol_semiauto01',
    'Fires as fast as the trigger is pulled.')
gun('gunny_volcanic', 'WEAPON_PISTOL_VOLCANIC', 'Volcanic Pistol', 'pistol', 8, 1.1, 'w_pistol_volcanic01',
    'A lever-action pistol: slow, but hits hard.')

-- Repeaters
gun('gunny_carbine', 'WEAPON_REPEATER_CARBINE', 'Carbine Repeater', 'repeater', 10, 3.2, 'w_repeater_carbine01',
    'A light lever-action carbine.')
gun('gunny_evans', 'WEAPON_REPEATER_EVANS', 'Evans Repeater', 'repeater', 26, 3.9, 'w_repeater_evans01',
    'A spiral magazine in the stock holds 26.')
gun('gunny_litchfield', 'WEAPON_REPEATER_HENRY', 'Litchfield Repeater', 'repeater', 10, 4.2, 'w_repeater_henry01',
    'A brass-framed repeater with a heavy round.')
gun('gunny_lancaster', 'WEAPON_REPEATER_WINCHESTER', 'Lancaster Repeater', 'repeater', 14, 3.8, 'w_repeater_winchester01',
    'A long-barrelled repeater with a big tube.')

-- Rifles
gun('gunny_boltaction', 'WEAPON_RIFLE_BOLTACTION', 'Bolt Action Rifle', 'rifle', 5, 4.0, 'w_rifle_boltaction01',
    'Accurate and powerful.')
gun('gunny_springfield', 'WEAPON_RIFLE_SPRINGFIELD', 'Springfield Rifle', 'rifle', 1, 4.1, 'w_rifle_springfield01',
    'One heavy round at a time.')
gun('gunny_elephant', 'WEAPON_RIFLE_ELEPHANT', 'Elephant Rifle', 'elephant', 2, 5.5, 'w_rifle_elephant01',
    'Two barrels for the biggest game there is.')
gun('gunny_varmint', 'WEAPON_RIFLE_VARMINT', 'Varmint Rifle', 'varmint', 16, 2.5, 'w_repeater_pumpaction01',
    'A small-bore pump rifle for small game.')
gun('gunny_carcano', 'WEAPON_SNIPERRIFLE_CARCANO', 'Carcano Rifle', 'rifle', 6, 4.0, 'w_rifle_carcano01',
    'An Italian bolt-action made for long shots.')
gun('gunny_rollingblock', 'WEAPON_SNIPERRIFLE_ROLLINGBLOCK', 'Rolling Block Rifle', 'rifle', 1, 4.5,
    'w_rifle_rollingblock01', 'A single-shot rifle that reaches a long way.')

-- Shotguns
gun('gunny_doublebarrel', 'WEAPON_SHOTGUN_DOUBLEBARREL', 'Double-Barreled Shotgun', 'shotgun', 2, 3.4,
    'w_shotgun_doublebarrel01', 'Two barrels, side by side.')
gun('gunny_doublebarrel_exotic', 'WEAPON_SHOTGUN_DOUBLEBARREL_EXOTIC', 'Double-Barreled Shotgun (Exotic)', 'shotgun', 2,
    3.4, 'w_shotgun_doublebarrel01', 'A finely made double-barrel.')
gun('gunny_pump', 'WEAPON_SHOTGUN_PUMP', 'Pump-Action Shotgun', 'shotgun', 5, 3.6, 'w_shotgun_pumpaction01',
    'Five shells, worked by the slide.')
gun('gunny_repeating', 'WEAPON_SHOTGUN_REPEATING', 'Repeating Shotgun', 'shotgun', 4, 3.6, 'w_shotgun_repeating01',
    'A lever-action shotgun.')
gun('gunny_sawedoff', 'WEAPON_SHOTGUN_SAWEDOFF', 'Sawed-Off Shotgun', 'shotgun', 2, 2.2, 'w_shotgun_sawed01',
    'Short barrels: brutal up close.')
gun('gunny_semiauto_shotgun', 'WEAPON_SHOTGUN_SEMIAUTO', 'Semi-Auto Shotgun', 'shotgun', 4, 3.8, 'w_shotgun_semiauto01',
    'Fires as fast as the trigger is pulled.')

-- Bows: the arrows are items of their own (items/ammo.lua), each one shot taken from the pockets.
bow('gunny_bow', 'WEAPON_BOW', 'Bow', 'A hunting bow. Quiet.')
bow('gunny_bow_improved', 'WEAPON_BOW_IMPROVED', 'Improved Bow', 'A stronger bow: draws faster, reaches further.')

-- Knives, machetes and the torch: swung, no rounds.
melee('gunny_knife', 'WEAPON_MELEE_KNIFE', 'Knife', 0.3, 'A hunting knife.')
melee('gunny_knife_jawbone', 'WEAPON_MELEE_KNIFE_JAWBONE', 'Jawbone Knife', 0.3, 'A knife with a jawbone handle.')
melee('gunny_knife_trader', 'WEAPON_MELEE_KNIFE_TRADER', 'Trader Knife', 0.3, 'A trader\'s knife.')
melee('gunny_knife_horror', 'WEAPON_MELEE_KNIFE_HORROR', 'Horror Knife', 0.3, 'An ugly-looking knife.')
melee('gunny_knife_rustic', 'WEAPON_MELEE_KNIFE_RUSTIC', 'Rustic Knife', 0.3, 'A plain old knife.')
melee('gunny_machete', 'WEAPON_MELEE_MACHETE', 'Machete', 0.8, 'A long blade for brush, and worse.')
melee('gunny_machete_horror', 'WEAPON_MELEE_MACHETE_HORROR', 'Horror Machete', 0.8, 'An ugly-looking machete.')
melee('gunny_machete_collector', 'WEAPON_MELEE_MACHETE_COLLECTOR', 'Collector\'s Machete', 0.8, 'A collector\'s machete.')
melee('gunny_torch', 'WEAPON_MELEE_TORCH', 'Torch', 0.6, 'A burning torch: light, and fire.')

-- Lassos: no rounds, as a melee weapon.
melee('gunny_lasso', 'WEAPON_LASSO', 'Lasso', 0.8, 'A rope lasso.')
melee('gunny_lasso_reinforced', 'WEAPON_LASSO_REINFORCED', 'Reinforced Lasso', 0.9, 'A lasso that holds longer.')

-- Thrown: a stack, and each one thrown is taken from it. RedM (spur_gunny, 24 Nov 2026): dynamite and the fire
-- bottle stand in for GTA's sticky bombs and grenades: a lit fuse, thrown, with no remote detonation.
throwable('gunny_hatchet', 'WEAPON_MELEE_HATCHET', 'Hatchet', 0.8, 5, 'Swing it, or throw it.')
throwable('gunny_hatchet_hunter', 'WEAPON_MELEE_HATCHET_HUNTER', 'Hunter Hatchet', 0.8, 5, 'A hunter\'s hatchet: swing it, or throw it.')
throwable('gunny_hatchet_doublebit', 'WEAPON_MELEE_HATCHET_DOUBLE_BIT', 'Double Bit Hatchet', 0.9, 5, 'Two edges: swing it, or throw it.')
throwable('gunny_cleaver', 'WEAPON_MELEE_CLEAVER', 'Cleaver', 0.6, 5, 'A butcher\'s cleaver: swing it, or throw it.')
throwable('gunny_tomahawk', 'WEAPON_THROWN_TOMAHAWK', 'Tomahawk', 0.6, 10, 'Made to be thrown.')
throwable('gunny_tomahawk_ancient', 'WEAPON_THROWN_TOMAHAWK_ANCIENT', 'Ancient Tomahawk', 0.6, 10, 'An old tomahawk, still sharp.')
throwable('gunny_throwing_knives', 'WEAPON_THROWN_THROWING_KNIVES', 'Throwing Knives', 0.15, 20, 'Light knives made to be thrown.')
throwable('gunny_dynamite', 'WEAPON_THROWN_DYNAMITE', 'Dynamite', 0.25, 10, 'Light the fuse and throw. It goes off when the fuse burns down.')
throwable('gunny_fire_bottle', 'WEAPON_THROWN_MOLOTOV', 'Fire Bottle', 0.6, 10, 'A bottle of fuel with a burning rag.')
throwable('gunny_poison_bottle', 'WEAPON_THROWN_POISONBOTTLE', 'Poison Bottle', 0.5, 10, 'Breaks into a poison cloud.')
throwable('gunny_bolas', 'WEAPON_THROWN_BOLAS', 'Bolas', 0.5, 10, 'Weights on a cord: brings down what it wraps.')
throwable('gunny_bolas_hawkmoth', 'WEAPON_THROWN_BOLAS_HAWKMOTH', 'Hawkmoth Bolas', 0.5, 10, 'Bolas that hold longer.')
throwable('gunny_bolas_ironspiked', 'WEAPON_THROWN_BOLAS_IRONSPIKED', 'Ironspiked Bolas', 0.6, 10, 'Bolas with iron spikes.')
throwable('gunny_bolas_intertwined', 'WEAPON_THROWN_BOLAS_INTERTWINED', 'Intertwined Bolas', 0.5, 10, 'Bolas of plaited cord.')
