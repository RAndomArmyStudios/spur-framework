-- spur_gunny: SETTINGS
--
-- RedM (spur_gunny, 24 Nov 2026): rewritten for RDR2. The items gunny adds are in items/: ammo.lua (cartridges by
-- kind), weapons.lua (one item per RDR2 weapon) and gunsmith.lua (scopes, barrels, rifling).

Config = {}

-- The gunsmith's bench, where scopes, barrels and rifling go on and come off: walk up to it with the gun drawn and
-- choose Gunsmith. enabled = false: no bench. place is x, y, z and heading.
--   model  nil: no prop of our own (the shop's own counter is there). A model name ('p_gunsmithbench01x', say) puts
--          one down on each player's game. No model has been tried in game.
-- RedM (spur_gunny, 24 Nov 2026): the place is checked in game: behind Valentine's gunsmith counter. The Gunsmith
-- prompt shows within reach of it (2.5 m), and a Cattleman took a long barrel there.
Config.Gunsmith = {
    enabled = true,
    place   = vector4(-281.80, 780.70, 119.53, 0.0),   -- Valentine's gunsmith, behind the counter
    model   = nil,
    name    = 'Gunsmith',
}

-- Reloading. R (B on a controller) loads loose cartridges from your pockets into the drawn gun.
Config.Reload = {
    -- The last round fired: the gun reloads by itself, if you carry its kind. On foot, in the saddle and on a wagon.
    autoWhenEmpty = true,
    -- The game's reload not begun by then: it played none, and the gun is filled at once.
    settleMs  = 1000,
    -- Reloading, but no cartridge in for this long: the game is stuck, and the reload is ended.
    stallMs   = 4000,
    timeoutMs = 15000,
}

-- RedM (spur_gunny, 25 Nov 2026): RDR2's weapon wheel (Tab). On, every gun, bow and blade in the pockets is carried on the
-- body, holstered and empty, so the wheel shows them; picking one draws it as Equip does, and picking the fists puts
-- it away (client/wheel.lua). false: a gun is on the body only while drawn, and the wheel stays empty.
Config.Wheel = {
    enabled = true,
}

-- RDR2 hands out ammunition by itself: looted from bodies, picked up, from kits, from cheats. None of it is kept. A
-- drawn gun holds only what the server counts; everything else is taken back off the ped.
Config.Guard = {
    -- Every RDR2 weapon in items/weapons.lua the ped holds but has not drawn from the inventory (looted, picked up,
    -- given by another script) is taken away. false: left alone (the ammunition is still taken back).
    sweepWeapons = true,
    -- How often the ped's ammunition and weapons are looked over (also every time the weapon in hand changes).
    intervalMs   = 500,
    -- Weapons the sweep leaves alone, by game name (another resource's lasso, say).
    keep         = {},
    -- Ammunition kinds no item stands for, emptied too: RDR2's specials gunny does not sell. A name the game does not
    -- know is skipped.
    alsoZero = {
        'AMMO_REVOLVER_EXPRESS_EXPLOSIVE', 'AMMO_PISTOL_EXPRESS_EXPLOSIVE', 'AMMO_REPEATER_EXPRESS_EXPLOSIVE',
        'AMMO_RIFLE_EXPRESS_EXPLOSIVE', 'AMMO_SHOTGUN_EXPRESS_EXPLOSIVE', 'AMMO_22_TRANQUILIZER',
        'AMMO_ARROW_TRACKING', 'AMMO_ARROW_TRAIL', 'AMMO_ARROW_CONFUSION', 'AMMO_ARROW_DISORIENT',
        'AMMO_DYNAMITE_VOLATILE', 'AMMO_MOLOTOV_VOLATILE', 'AMMO_THROWING_KNIVES_IMPROVED',
        'AMMO_THROWING_KNIVES_POISON', 'AMMO_THROWING_KNIVES_CONFUSE', 'AMMO_THROWING_KNIVES_DISORIENT',
        'AMMO_TOMAHAWK_IMPROVED', 'AMMO_TOMAHAWK_HOMING',
    },
}
