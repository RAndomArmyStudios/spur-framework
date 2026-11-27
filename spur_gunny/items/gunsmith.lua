-- spur_gunny: THE GUNSMITH'S PARTS
--
-- RedM (spur_gunny, 24 Nov 2026): replaces whip_gunny's items/attachments.lua (suppressors, grips, flashlights and
-- the original game's scopes). A part is an item; the gunsmith fits it to a gun (server/gunsmith.lua), and the gun shows RDR2's own
-- weapon component for it while drawn.
--
-- RedM (spur_gunny, 24 Nov 2026): every name below is RDR2's as femga's rdr3_discoveries lists it
-- (weapons/weapon_components.lua), and was asked of the game with /gunnypartlab: each barrel and scope has a model in
-- the game, and a Cattleman took and gave back its short and long barrels. Repeaters have no barrels of their own.
-- Rifling is one part for each class, COMPONENT_SHORTARM_ / COMPONENT_LONGARM_BARREL_RIFLING_1, and shotguns take none.
-- Put on in game and read back: the Cattleman's barrels and rifling; the Bolt Action's, Springfield's, Carcano's and
-- Rolling Block's rifling and scopes (SCOPED, below); the Elephant Rifle's barrels and rifling. Not tried: the other
-- revolvers, the pistols, the repeaters, the Varmint and the shotguns.
-- A name the game does not take is said in F8 as the drawn gun is given it (client/gunsmith.lua). Change them here;
-- nothing else names them.

--- The slots a gun can have, and each slot's label.
Config.AttachmentCategories = {
    scope   = 'Scope',
    barrel  = 'Barrel',
    rifling = 'Rifling',
}

--- The part items: category (a slot above) and tier (which of the gun's components for that slot it fits).
Config.Attachments = {
    gunny_scope_short  = { label = 'Short Scope', category = 'scope', tier = 'short', weight = 0.4,
                           description = 'A short telescopic sight for a rifle.' },
    gunny_scope_medium = { label = 'Medium Scope', category = 'scope', tier = 'medium', weight = 0.5,
                           description = 'A medium telescopic sight for a rifle.' },
    gunny_scope_long   = { label = 'Long Scope', category = 'scope', tier = 'long', weight = 0.6,
                           description = 'A long telescopic sight for a rifle.' },
    gunny_barrel_short = { label = 'Short Barrel', category = 'barrel', tier = 'short', weight = 0.5,
                           description = 'A shorter barrel: quicker to bring up.' },
    gunny_barrel_long  = { label = 'Long Barrel', category = 'barrel', tier = 'long', weight = 0.7,
                           description = 'A longer barrel: reaches further.' },
    gunny_rifling      = { label = 'Barrel Rifling', category = 'rifling', tier = 'rifled', weight = 0.2,
                           description = 'Cut rifling: steadier at range.' },
}

--- [gun item] = { [category] = { [tier] = 'COMPONENT_...' } }: what each gun takes. Built from the lists below.
Config.WeaponAttachments = {}

-- Scopes: RDR2's rifle scopes fit the rifles.
-- RedM (spur_gunny, 24 Nov 2026): which scopes each takes, from /gunnypartlab. The long scope (SCOPE04) went on the
-- Carcano and the Rolling Block, and the Bolt Action and the Springfield refused it at once. The short and medium
-- scopes went on all four. The Varmint is not tried in game yet, so it is given the two the other rifles took.
local SCOPES = { short = 'COMPONENT_RIFLE_SCOPE02', medium = 'COMPONENT_RIFLE_SCOPE03', long = 'COMPONENT_RIFLE_SCOPE04' }
local SCOPED = {
    gunny_boltaction   = { 'short', 'medium' },
    gunny_springfield  = { 'short', 'medium' },
    gunny_carcano      = { 'short', 'medium', 'long' },
    gunny_rollingblock = { 'short', 'medium', 'long' },
    gunny_varmint      = { 'short', 'medium' },   -- not tried in game
}

-- A gun's own barrels are named after it: COMPONENT_<NAME>_BARREL_SHORT and _BARREL_LONG. Rifling is the class's.
-- [gun item] = { name part, has short/long barrels, rifling class (nil: none) }
local OWN = {
    gunny_cattleman      = { 'REVOLVER_CATTLEMAN', true, 'SHORTARM' },
    gunny_doubleaction   = { 'REVOLVER_DOUBLEACTION', true, 'SHORTARM' },
    gunny_lemat          = { 'REVOLVER_LEMAT', true, 'SHORTARM' },
    gunny_navy           = { 'REVOLVER_NAVY', true, 'SHORTARM' },
    gunny_schofield      = { 'REVOLVER_SCHOFIELD', true, 'SHORTARM' },
    gunny_m1899          = { 'PISTOL_M1899', true, 'SHORTARM' },
    gunny_mauser         = { 'PISTOL_MAUSER', true, 'SHORTARM' },
    gunny_semiauto       = { 'PISTOL_SEMIAUTO', true, 'SHORTARM' },
    gunny_volcanic       = { 'PISTOL_VOLCANIC', true, 'SHORTARM' },
    gunny_carbine        = { 'REPEATER_CARBINE', false, 'LONGARM' },
    gunny_evans          = { 'REPEATER_EVANS', false, 'LONGARM' },
    gunny_litchfield     = { 'REPEATER_HENRY', false, 'LONGARM' },
    gunny_lancaster      = { 'REPEATER_WINCHESTER', false, 'LONGARM' },
    gunny_boltaction     = { 'RIFLE_BOLTACTION', false, 'LONGARM' },
    gunny_springfield    = { 'RIFLE_SPRINGFIELD', false, 'LONGARM' },
    gunny_varmint        = { 'RIFLE_VARMINT', false, 'LONGARM' },
    gunny_elephant       = { 'RIFLE_ELEPHANT', true, 'LONGARM' },
    gunny_carcano        = { 'SNIPERRIFLE_CARCANO', false, 'LONGARM' },
    gunny_rollingblock   = { 'SNIPERRIFLE_ROLLINGBLOCK', false, 'LONGARM' },
    gunny_pump           = { 'SHOTGUN_PUMP', true, nil },
    gunny_repeating      = { 'SHOTGUN_REPEATING', true, nil },
    gunny_semiauto_shotgun = { 'SHOTGUN_SEMIAUTO', true, nil },
    gunny_doublebarrel   = { 'SHOTGUN_DOUBLEBARREL', true, nil },
}

local function slotsOf(item)
    local t = Config.WeaponAttachments[item]
    if not t then t = {}; Config.WeaponAttachments[item] = t end
    return t
end

for item, tiers in pairs(SCOPED) do
    local s = {}
    for _, tier in ipairs(tiers) do s[tier] = SCOPES[tier] end
    slotsOf(item).scope = s
end
for item, own in pairs(OWN) do
    local name, barrels, rifling = own[1], own[2], own[3]
    if barrels then
        slotsOf(item).barrel = { short = ('COMPONENT_%s_BARREL_SHORT'):format(name),
                                 long  = ('COMPONENT_%s_BARREL_LONG'):format(name) }
    end
    if rifling then
        slotsOf(item).rifling = { rifled = ('COMPONENT_%s_BARREL_RIFLING_1'):format(rifling) }
    end
end
