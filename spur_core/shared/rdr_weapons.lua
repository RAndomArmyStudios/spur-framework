-- ============================================
-- RDR2 WEAPONS — the game's own weapons an NPC can be given, and each firearm's world model
-- ============================================
--
-- RedM (spur_core, 24 Nov 2026): NEW, in place of whip_core's two weapon lists (the original game's 108
-- weapons, none of which RDR2 has, so every Director weapon list was empty). The fxmanifest loads this instead; the
-- two lists are not in this copy.
--
-- The tables keep the game's names, GameWeapons and GameWeaponModels, because shared/weapon_catalog.lua (which everything
-- reads weapons through: the Director's NPC weapons, its Hold a Weapon step, its Fixed Weapons, Dungeon Mode, the
-- Object Viewer's Give a weapon) reads them by those names.
--
-- The weapons: the 55 spur_gunny gives as items (spur_gunny/items/weapons.lua), by RDR2's own names and gunny's
-- labels. Where a list is offered, the game is still asked which it has (IsWeaponValid), as before.
-- The world models: gunny's, from RDR2's data, for the base guns only (a variant, "Cattleman Revolver (Mexican)",
-- shares its base gun's model, and a model must name one gun). The world builder offers only those the game has
-- (IsModelInCdimage), so a wrong one is left out, not broken.

local function w(name, label, group) return { name = name, label = label, group = group } end

GameWeapons = {
    list = {
    -- Revolvers
    w('WEAPON_REVOLVER_CATTLEMAN', 'Cattleman Revolver', 'revolver'),
    w('WEAPON_REVOLVER_CATTLEMAN_MEXICAN', 'Cattleman Revolver (Mexican)', 'revolver'),
    w('WEAPON_REVOLVER_DOUBLEACTION', 'Double-Action Revolver', 'revolver'),
    w('WEAPON_REVOLVER_DOUBLEACTION_GAMBLER', 'Double-Action Revolver (Gambler)', 'revolver'),
    w('WEAPON_REVOLVER_LEMAT', 'LeMat Revolver', 'revolver'),
    w('WEAPON_REVOLVER_NAVY', 'Navy Revolver', 'revolver'),
    w('WEAPON_REVOLVER_NAVY_CROSSOVER', 'Navy Revolver (Crossover)', 'revolver'),
    w('WEAPON_REVOLVER_SCHOFIELD', 'Schofield Revolver', 'revolver'),
    -- Pistols
    w('WEAPON_PISTOL_M1899', 'M1899 Pistol', 'pistol'),
    w('WEAPON_PISTOL_MAUSER', 'Mauser Pistol', 'pistol'),
    w('WEAPON_PISTOL_SEMIAUTO', 'Semi-Automatic Pistol', 'pistol'),
    w('WEAPON_PISTOL_VOLCANIC', 'Volcanic Pistol', 'pistol'),
    -- Repeaters
    w('WEAPON_REPEATER_CARBINE', 'Carbine Repeater', 'repeater'),
    w('WEAPON_REPEATER_EVANS', 'Evans Repeater', 'repeater'),
    w('WEAPON_REPEATER_HENRY', 'Litchfield Repeater', 'repeater'),
    w('WEAPON_REPEATER_WINCHESTER', 'Lancaster Repeater', 'repeater'),
    -- Rifles
    w('WEAPON_RIFLE_BOLTACTION', 'Bolt Action Rifle', 'rifle'),
    w('WEAPON_RIFLE_ELEPHANT', 'Elephant Rifle', 'rifle'),
    w('WEAPON_RIFLE_SPRINGFIELD', 'Springfield Rifle', 'rifle'),
    w('WEAPON_RIFLE_VARMINT', 'Varmint Rifle', 'rifle'),
    -- Sniper rifles
    w('WEAPON_SNIPERRIFLE_CARCANO', 'Carcano Rifle', 'sniper'),
    w('WEAPON_SNIPERRIFLE_ROLLINGBLOCK', 'Rolling Block Rifle', 'sniper'),
    -- Shotguns
    w('WEAPON_SHOTGUN_DOUBLEBARREL', 'Double-Barreled Shotgun', 'shotgun'),
    w('WEAPON_SHOTGUN_DOUBLEBARREL_EXOTIC', 'Double-Barreled Shotgun (Exotic)', 'shotgun'),
    w('WEAPON_SHOTGUN_PUMP', 'Pump-Action Shotgun', 'shotgun'),
    w('WEAPON_SHOTGUN_REPEATING', 'Repeating Shotgun', 'shotgun'),
    w('WEAPON_SHOTGUN_SAWEDOFF', 'Sawed-Off Shotgun', 'shotgun'),
    w('WEAPON_SHOTGUN_SEMIAUTO', 'Semi-Auto Shotgun', 'shotgun'),
    -- Bows
    w('WEAPON_BOW', 'Bow', 'bow'),
    w('WEAPON_BOW_IMPROVED', 'Improved Bow', 'bow'),
    -- Thrown
    w('WEAPON_THROWN_BOLAS', 'Bolas', 'thrown'),
    w('WEAPON_THROWN_BOLAS_HAWKMOTH', 'Hawkmoth Bolas', 'thrown'),
    w('WEAPON_THROWN_BOLAS_INTERTWINED', 'Intertwined Bolas', 'thrown'),
    w('WEAPON_THROWN_BOLAS_IRONSPIKED', 'Ironspiked Bolas', 'thrown'),
    w('WEAPON_THROWN_DYNAMITE', 'Dynamite', 'thrown'),
    w('WEAPON_THROWN_MOLOTOV', 'Fire Bottle', 'thrown'),
    w('WEAPON_THROWN_POISONBOTTLE', 'Poison Bottle', 'thrown'),
    w('WEAPON_THROWN_THROWING_KNIVES', 'Throwing Knives', 'thrown'),
    w('WEAPON_THROWN_TOMAHAWK', 'Tomahawk', 'thrown'),
    w('WEAPON_THROWN_TOMAHAWK_ANCIENT', 'Ancient Tomahawk', 'thrown'),
    -- Melee
    w('WEAPON_MELEE_CLEAVER', 'Cleaver', 'melee'),
    w('WEAPON_MELEE_HATCHET', 'Hatchet', 'melee'),
    w('WEAPON_MELEE_HATCHET_DOUBLE_BIT', 'Double Bit Hatchet', 'melee'),
    w('WEAPON_MELEE_HATCHET_HUNTER', 'Hunter Hatchet', 'melee'),
    w('WEAPON_MELEE_KNIFE', 'Knife', 'melee'),
    w('WEAPON_MELEE_KNIFE_HORROR', 'Horror Knife', 'melee'),
    w('WEAPON_MELEE_KNIFE_JAWBONE', 'Jawbone Knife', 'melee'),
    w('WEAPON_MELEE_KNIFE_RUSTIC', 'Rustic Knife', 'melee'),
    w('WEAPON_MELEE_KNIFE_TRADER', 'Trader Knife', 'melee'),
    w('WEAPON_MELEE_MACHETE', 'Machete', 'melee'),
    w('WEAPON_MELEE_MACHETE_COLLECTOR', "Collector's Machete", 'melee'),
    w('WEAPON_MELEE_MACHETE_HORROR', 'Horror Machete', 'melee'),
    w('WEAPON_MELEE_TORCH', 'Torch', 'melee'),
    -- Lassos
    w('WEAPON_LASSO', 'Lasso', 'lasso'),
    w('WEAPON_LASSO_REINFORCED', 'Reinforced Lasso', 'lasso'),
    },
    byName = {},
}
for _, x in ipairs(GameWeapons.list) do GameWeapons.byName[x.name] = x end

GameWeaponModels = {
    -- The groups a Fixed Weapon may be, in the builder's order.
    groups = { 'revolver', 'pistol', 'repeater', 'rifle', 'sniper', 'shotgun' },
    byName = {
        WEAPON_REVOLVER_CATTLEMAN = 'w_revolver_cattleman01',
        WEAPON_REVOLVER_DOUBLEACTION = 'w_revolver_doubleaction01',
        WEAPON_REVOLVER_LEMAT = 'w_revolver_lemat01',
        WEAPON_REVOLVER_NAVY = 'w_revolver_navy01',
        WEAPON_REVOLVER_SCHOFIELD = 'w_revolver_schofield01',
        WEAPON_PISTOL_M1899 = 'w_pistol_m189902',
        WEAPON_PISTOL_MAUSER = 'w_pistol_mauser01',
        WEAPON_PISTOL_SEMIAUTO = 'w_pistol_semiauto01',
        WEAPON_PISTOL_VOLCANIC = 'w_pistol_volcanic01',
        WEAPON_REPEATER_CARBINE = 'w_repeater_carbine01',
        WEAPON_REPEATER_EVANS = 'w_repeater_evans01',
        WEAPON_REPEATER_HENRY = 'w_repeater_henry01',
        WEAPON_REPEATER_WINCHESTER = 'w_repeater_winchester01',
        WEAPON_RIFLE_BOLTACTION = 'w_rifle_boltaction01',
        WEAPON_RIFLE_ELEPHANT = 'w_rifle_elephant01',
        WEAPON_RIFLE_SPRINGFIELD = 'w_rifle_springfield01',
        WEAPON_RIFLE_VARMINT = 'w_repeater_pumpaction01',
        WEAPON_SNIPERRIFLE_CARCANO = 'w_rifle_carcano01',
        WEAPON_SNIPERRIFLE_ROLLINGBLOCK = 'w_rifle_rollingblock01',
        WEAPON_SHOTGUN_DOUBLEBARREL = 'w_shotgun_doublebarrel01',
        WEAPON_SHOTGUN_PUMP = 'w_shotgun_pumpaction01',
        WEAPON_SHOTGUN_REPEATING = 'w_shotgun_repeating01',
        WEAPON_SHOTGUN_SAWEDOFF = 'w_shotgun_sawed01',
        WEAPON_SHOTGUN_SEMIAUTO = 'w_shotgun_semiauto01',
    },
}

--- A firearm's world model, or nil when the name is no firearm here.
function GameWeaponModels.modelOf(name)
    return type(name) == 'string' and GameWeaponModels.byName[name:upper()] or nil
end

local byModel = {}
for name, m in pairs(GameWeaponModels.byName) do byModel[m] = name end

--- The firearm a world model is, or nil (a Fixed Weapon placed before its gun was kept with it is known again by this).
function GameWeaponModels.weaponOf(model)
    return type(model) == 'string' and byModel[model:lower()] or nil
end
