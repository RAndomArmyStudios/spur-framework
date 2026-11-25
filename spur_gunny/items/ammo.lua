-- spur_gunny: CARTRIDGES, one item per kind
--
-- RedM (spur_gunny, 24 Nov 2026): replaces whip_gunny's items/calibers.lua. RDR2 sorts ammunition into groups (what a
-- gun chambers) and kinds within a group (regular, express, high velocity, split point...). Each kind here is one
-- stackable item, loaded loose into the gun (no magazines): a gun holds one kind at a time, the first it is loaded
-- with, and Switch Cartridges on its menu empties it so another kind can go in.
--
-- `type` is RDR2's own ammunition name, which the game is given while the gun is out. UNTESTED: these names come from
-- RDR2's data as published (femga's rdr3_discoveries); a name the game does not know is said in F8 when that gun is
-- drawn (/gunnyammoprobe shows what the game says). AMMO_22 for the Varmint Rifle in particular is not confirmed.
--
-- Fields: label, type, group (Config.AmmoGroups), weight (kg per cartridge), description.

--- Each group, its label, and its kinds in the order a gun with none loaded picks from (the first carried wins).
Config.AmmoGroups = {
    revolver = { label = 'Revolver', kinds = { 'gunny_ammo_revolver', 'gunny_ammo_revolver_express',
                 'gunny_ammo_revolver_velocity', 'gunny_ammo_revolver_splitpoint' } },
    pistol   = { label = 'Pistol', kinds = { 'gunny_ammo_pistol', 'gunny_ammo_pistol_express',
                 'gunny_ammo_pistol_velocity', 'gunny_ammo_pistol_splitpoint' } },
    repeater = { label = 'Repeater', kinds = { 'gunny_ammo_repeater', 'gunny_ammo_repeater_express',
                 'gunny_ammo_repeater_velocity', 'gunny_ammo_repeater_splitpoint' } },
    rifle    = { label = 'Rifle', kinds = { 'gunny_ammo_rifle', 'gunny_ammo_rifle_express',
                 'gunny_ammo_rifle_velocity', 'gunny_ammo_rifle_splitpoint' } },
    elephant = { label = 'Elephant Rifle', kinds = { 'gunny_ammo_elephant' } },
    varmint  = { label = 'Varmint Rifle', kinds = { 'gunny_ammo_varmint' } },
    shotgun  = { label = 'Shotgun', kinds = { 'gunny_ammo_shotgun', 'gunny_ammo_shotgun_slug',
                 'gunny_ammo_shotgun_incendiary' } },
    arrow    = { label = 'Arrow', kinds = { 'gunny_arrow', 'gunny_arrow_improved', 'gunny_arrow_smallgame',
                 'gunny_arrow_fire', 'gunny_arrow_poison', 'gunny_arrow_dynamite' } },
}

Config.Ammo = {
    -- Revolver
    gunny_ammo_revolver            = { label = 'Revolver Cartridges', type = 'AMMO_REVOLVER', group = 'revolver', weight = 0.01,
                                       description = 'Regular revolver cartridges.' },
    gunny_ammo_revolver_express    = { label = 'Express Revolver Cartridges', type = 'AMMO_REVOLVER_EXPRESS', group = 'revolver', weight = 0.01,
                                       description = 'More powder: hits harder.' },
    gunny_ammo_revolver_velocity   = { label = 'High Velocity Revolver Cartridges', type = 'AMMO_REVOLVER_HIGH_VELOCITY', group = 'revolver', weight = 0.01,
                                       description = 'Flies faster and further.' },
    gunny_ammo_revolver_splitpoint = { label = 'Split Point Revolver Cartridges', type = 'AMMO_REVOLVER_SPLIT_POINT', group = 'revolver', weight = 0.01,
                                       description = 'Opens up on impact.' },
    -- Pistol
    gunny_ammo_pistol              = { label = 'Pistol Cartridges', type = 'AMMO_PISTOL', group = 'pistol', weight = 0.01,
                                       description = 'Regular pistol cartridges.' },
    gunny_ammo_pistol_express      = { label = 'Express Pistol Cartridges', type = 'AMMO_PISTOL_EXPRESS', group = 'pistol', weight = 0.01,
                                       description = 'More powder: hits harder.' },
    gunny_ammo_pistol_velocity     = { label = 'High Velocity Pistol Cartridges', type = 'AMMO_PISTOL_HIGH_VELOCITY', group = 'pistol', weight = 0.01,
                                       description = 'Flies faster and further.' },
    gunny_ammo_pistol_splitpoint   = { label = 'Split Point Pistol Cartridges', type = 'AMMO_PISTOL_SPLIT_POINT', group = 'pistol', weight = 0.01,
                                       description = 'Opens up on impact.' },
    -- Repeater
    gunny_ammo_repeater            = { label = 'Repeater Cartridges', type = 'AMMO_REPEATER', group = 'repeater', weight = 0.012,
                                       description = 'Regular repeater cartridges.' },
    gunny_ammo_repeater_express    = { label = 'Express Repeater Cartridges', type = 'AMMO_REPEATER_EXPRESS', group = 'repeater', weight = 0.012,
                                       description = 'More powder: hits harder.' },
    gunny_ammo_repeater_velocity   = { label = 'High Velocity Repeater Cartridges', type = 'AMMO_REPEATER_HIGH_VELOCITY', group = 'repeater', weight = 0.012,
                                       description = 'Flies faster and further.' },
    gunny_ammo_repeater_splitpoint = { label = 'Split Point Repeater Cartridges', type = 'AMMO_REPEATER_SPLIT_POINT', group = 'repeater', weight = 0.012,
                                       description = 'Opens up on impact.' },
    -- Rifle (the bolt-action, Springfield, Carcano and Rolling Block)
    gunny_ammo_rifle               = { label = 'Rifle Cartridges', type = 'AMMO_RIFLE', group = 'rifle', weight = 0.015,
                                       description = 'Regular rifle cartridges.' },
    gunny_ammo_rifle_express       = { label = 'Express Rifle Cartridges', type = 'AMMO_RIFLE_EXPRESS', group = 'rifle', weight = 0.015,
                                       description = 'More powder: hits harder.' },
    gunny_ammo_rifle_velocity      = { label = 'High Velocity Rifle Cartridges', type = 'AMMO_RIFLE_HIGH_VELOCITY', group = 'rifle', weight = 0.015,
                                       description = 'Flies faster and further.' },
    gunny_ammo_rifle_splitpoint    = { label = 'Split Point Rifle Cartridges', type = 'AMMO_RIFLE_SPLIT_POINT', group = 'rifle', weight = 0.015,
                                       description = 'Opens up on impact.' },
    -- Their own rifles
    gunny_ammo_elephant            = { label = 'Elephant Rifle Cartridges', type = 'AMMO_RIFLE_ELEPHANT', group = 'elephant', weight = 0.04,
                                       description = 'Big-game cartridges for the Elephant Rifle.' },
    gunny_ammo_varmint             = { label = 'Varmint Cartridges', type = 'AMMO_22', group = 'varmint', weight = 0.004,
                                       description = 'Small .22 cartridges for the Varmint Rifle.' },
    -- Shotgun
    gunny_ammo_shotgun             = { label = 'Shotgun Shells', type = 'AMMO_SHOTGUN', group = 'shotgun', weight = 0.03,
                                       description = 'Buckshot.' },
    gunny_ammo_shotgun_slug        = { label = 'Slugs', type = 'AMMO_SHOTGUN_SLUG', group = 'shotgun', weight = 0.03,
                                       description = 'One heavy ball: reaches further.' },
    gunny_ammo_shotgun_incendiary  = { label = 'Incendiary Buckshot', type = 'AMMO_SHOTGUN_BUCKSHOT_INCENDIARY', group = 'shotgun', weight = 0.03,
                                       description = 'Sets what it hits alight.' },
    -- Arrows (the bows)
    gunny_arrow                    = { label = 'Arrows', type = 'AMMO_ARROW', group = 'arrow', weight = 0.03,
                                       description = 'Plain arrows.' },
    gunny_arrow_improved           = { label = 'Improved Arrows', type = 'AMMO_ARROW_IMPROVED', group = 'arrow', weight = 0.03,
                                       description = 'Better heads: hit harder.' },
    gunny_arrow_smallgame          = { label = 'Small Game Arrows', type = 'AMMO_ARROW_SMALL_GAME', group = 'arrow', weight = 0.03,
                                       description = 'For small animals: keeps the pelt whole.' },
    gunny_arrow_fire               = { label = 'Fire Arrows', type = 'AMMO_ARROW_FIRE', group = 'arrow', weight = 0.04,
                                       description = 'Burn what they hit.' },
    gunny_arrow_poison             = { label = 'Poison Arrows', type = 'AMMO_ARROW_POISON', group = 'arrow', weight = 0.04,
                                       description = 'Poison what they hit.' },
    gunny_arrow_dynamite           = { label = 'Dynamite Arrows', type = 'AMMO_ARROW_DYNAMITE', group = 'arrow', weight = 0.08,
                                       description = 'Explode where they land.' },
}
