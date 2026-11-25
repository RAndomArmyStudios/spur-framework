-- ============================================
-- GTA WEAPON MODELS — each firearm's world model: the gun lying in the world, not in a hand
-- ============================================
--
-- From DurtyFree's gta-v-data-dumps weapons.json (ModelName), for every firearm in shared/gta_weapons.lua (the pistol,
-- SMG, rifle, machine gun, shotgun, sniper and heavy groups: no melee, nothing thrown). The Director's Fixed Weapon is a
-- prop of one of these models that fires as its gun (server/director/nodes_weapons.lua); the world builder offers
-- them in More > Weapons (only those this game has: the builder asks). Data only.

GtaWeaponModels = {
    -- The groups a Fixed Weapon may be, in the builder's order.
    groups = { 'pistol', 'smg', 'rifle', 'machine gun', 'shotgun', 'sniper', 'heavy' },
    byName = {
        WEAPON_APPISTOL = 'w_pi_appistol',
        WEAPON_CERAMICPISTOL = 'w_pi_ceramic_pistol',
        WEAPON_COMBATPISTOL = 'w_pi_combatpistol',
        WEAPON_DOUBLEACTION = 'w_pi_wep1_gun',
        WEAPON_FLAREGUN = 'w_pi_flaregun',
        WEAPON_HEAVYPISTOL = 'w_pi_heavypistol',
        WEAPON_REVOLVER = 'w_pi_revolver',
        WEAPON_REVOLVER_MK2 = 'w_pi_revolvermk2',
        WEAPON_MARKSMANPISTOL = 'w_pi_singleshot',
        WEAPON_NAVYREVOLVER = 'w_pi_wep2_gun',
        WEAPON_GADGETPISTOL = 'w_pi_singleshoth4',
        WEAPON_PISTOL = 'w_pi_pistol',
        WEAPON_PISTOL50 = 'w_pi_pistol50',
        WEAPON_PISTOL_MK2 = 'w_pi_pistolmk2',
        WEAPON_SNSPISTOL = 'w_pi_sns_pistol',
        WEAPON_SNSPISTOL_MK2 = 'w_pi_sns_pistolmk2',
        WEAPON_RAYPISTOL = 'w_pi_raygun',
        WEAPON_VINTAGEPISTOL = 'w_pi_vintage_pistol',
        WEAPON_PISTOLXM3 = 'w_pi_pistol_xm3',
        WEAPON_ASSAULTSMG = 'w_sb_assaultsmg',
        WEAPON_COMBATPDW = 'w_sb_pdw',
        WEAPON_MACHINEPISTOL = 'w_sb_compactsmg',
        WEAPON_MICROSMG = 'w_sb_microsmg',
        WEAPON_MINISMG = 'w_sb_minismg',
        WEAPON_SMG = 'w_sb_smg',
        WEAPON_SMG_MK2 = 'w_sb_smgmk2',
        WEAPON_TECPISTOL = 'w_pi_pistolsmg_m31',
        WEAPON_ADVANCEDRIFLE = 'w_ar_advancedrifle',
        WEAPON_ASSAULTRIFLE = 'w_ar_assaultrifle',
        WEAPON_ASSAULTRIFLE_MK2 = 'w_ar_assaultriflemk2',
        WEAPON_BATTLERIFLE = 'w_sl_battlerifle_m32',
        WEAPON_BULLPUPRIFLE = 'w_ar_bullpuprifle',
        WEAPON_BULLPUPRIFLE_MK2 = 'w_ar_bullpupriflemk2',
        WEAPON_CARBINERIFLE = 'w_ar_carbinerifle',
        WEAPON_CARBINERIFLE_MK2 = 'w_ar_carbineriflemk2',
        WEAPON_COMPACTRIFLE = 'w_ar_assaultrifle_smg',
        WEAPON_STRICKLER = 'w_ar_bullpupriflem42',
        WEAPON_HEAVYRIFLE = 'w_ar_heavyrifleh',
        WEAPON_MILITARYRIFLE = 'w_ar_bullpuprifleh4',
        WEAPON_TACTICALRIFLE = 'w_ar_carbinerifle_reh',
        WEAPON_SPECIALCARBINE = 'w_ar_specialcarbine',
        WEAPON_SPECIALCARBINE_MK2 = 'w_ar_specialcarbinemk2',
        WEAPON_COMBATMG = 'w_mg_combatmg',
        WEAPON_COMBATMG_MK2 = 'w_mg_combatmgmk2',
        WEAPON_GUSENBERG = 'w_sb_gusenberg',
        WEAPON_MG = 'w_mg_mg',
        WEAPON_RAYCARBINE = 'w_ar_srifle',
        WEAPON_ASSAULTSHOTGUN = 'w_sg_assaultshotgun',
        WEAPON_BULLPUPSHOTGUN = 'w_sg_bullpupshotgun',
        WEAPON_COMBATSHOTGUN = 'w_sg_pumpshotgunh4',
        WEAPON_DBSHOTGUN = 'w_sg_doublebarrel',
        WEAPON_HEAVYSHOTGUN = 'w_sg_heavyshotgun',
        WEAPON_PUMPSHOTGUN = 'w_sg_pumpshotgun',
        WEAPON_PUMPSHOTGUN_MK2 = 'w_sg_pumpshotgunmk2',
        WEAPON_SAWNOFFSHOTGUN = 'w_sg_sawnoff',
        WEAPON_AUTOSHOTGUN = 'w_sg_sweeper',
        WEAPON_HEAVYSNIPER = 'w_sr_heavysniper',
        WEAPON_HEAVYSNIPER_MK2 = 'w_sr_heavysnipermk2',
        WEAPON_MARKSMANRIFLE = 'w_sr_marksmanrifle',
        WEAPON_MARKSMANRIFLE_MK2 = 'w_sr_marksmanriflemk2',
        WEAPON_MUSKET = 'w_ar_musket',
        WEAPON_PRECISIONRIFLE = 'w_sr_precisionrifle_reh',
        WEAPON_SNIPERRIFLE = 'w_sr_sniperrifle',
        WEAPON_EMPLAUNCHER = 'w_lr_compactml',
        WEAPON_COMPACTLAUNCHER = 'w_lr_compactgl',
        WEAPON_FIREWORK = 'w_lr_firework',
        WEAPON_GRENADELAUNCHER = 'w_lr_grenadelauncher',
        WEAPON_HOMINGLAUNCHER = 'w_lr_homing',
        WEAPON_MINIGUN = 'w_mg_minigun',
        WEAPON_RAILGUN = 'w_ar_railgun',
        WEAPON_RAILGUNXM3 = 'w_ar_railgun_xm3',
        WEAPON_RPG = 'w_lr_rpg',
        WEAPON_SNOWLAUNCHER = 'w_lr_compactsl_m32',
        WEAPON_GRENADELAUNCHER_SMOKE = 'w_lr_grenadelauncher',
        WEAPON_RAYMINIGUN = 'w_mg_sminigun',
    },
}

--- A firearm's world model, or nil when the name is no firearm here.
function GtaWeaponModels.modelOf(name)
    return type(name) == 'string' and GtaWeaponModels.byName[name:upper()] or nil
end

-- (A model two guns share, the grenade launcher's, is the first's: the order above.)
local byModel = {}
for _, name in ipairs((function()
    local names = {}
    for n in pairs(GtaWeaponModels.byName) do names[#names + 1] = n end
    table.sort(names)
    return names
end)()) do
    local m = GtaWeaponModels.byName[name]
    if not byModel[m] or name == 'WEAPON_GRENADELAUNCHER' then byModel[m] = name end
end

--- The firearm a world model is, or nil (a Fixed Weapon placed before its gun was kept with it is known again by this).
function GtaWeaponModels.weaponOf(model)
    return type(model) == 'string' and byModel[model:lower()] or nil
end
