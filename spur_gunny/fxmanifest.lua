fx_version 'cerulean'
-- RedM (spur_gunny, 24 Nov 2026): RedM, not FiveM. A rework of whip_gunny 2.0.1 for spur_core and RDR2's own weapons
-- (README.md, NOTICE.md). No streamed models, metas, animations or sounds: every gun, round and part is the game's.
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

name 'spur_gunny'
description 'Guns as items for spur_core on RedM: serial numbers, loose cartridges counted by the server, a gunsmith, dynamite and fire bottles.'
author 'Whippy and WLVF (whip_gunny); RedM port, non-commercial'
version '2.0.1-redm.1'

dependencies { 'spur_core' }
whip_requires '1.0'   -- the spur_core it is built for: the setup report flags an older one

shared_scripts {
    -- spur_core's satellite helper, first: Whip.register declares to spur_core once it is ready. With the dependency
    -- above, a spur_core restart stops gunny first and starts it again, so nothing here cleans up after spur_core.
    '@spur_core/lib/satellite.lua',
    -- RedM (spur_gunny, 24 Nov 2026): spur_core's names for the GTA natives RDR2 lacks (GetSelectedPedWeapon and the
    -- rest), loaded into this resource as spur_rope loads them.
    '@spur_core/shared/rdr_compat.lua',
    '@spur_core/shared/rdr_compat_stubs.lua',

    'config.lua',                -- the settings (and Config itself)
    -- The items gunny adds, then the lookups into them. RedM (spur_gunny, 24 Nov 2026): cartridges by kind, no
    -- magazines, and the gunsmith's parts where the weapon bench's attachments were.
    'items/ammo.lua',
    'items/weapons.lua',
    'items/gunsmith.lua',
    'shared/catalog.lua',
    -- Weapons and cartridges from other resources (RegisterWeapon, RegisterAmmo).
    'shared/packs.lua',
}

server_scripts {
    'server/main.lua',          -- declaring callbacks and events, the drawn-weapon record
    'server/items.lua',         -- every item registered with spur_core, the context actions, the exports
    'server/weapons.lua',       -- drawing and putting away
    'server/reload.lua',        -- loose cartridges into the gun, unloading, switching the kind
    'server/shooting.lua',
    'server/throwables.lua',    -- thrown things, and arrows shot from a bow
    'server/gunsmith.lua',      -- the gunsmith's bench (whip_gunny's weapon bench)
    'server/debug.lua',
    'server/ledger.lua',        -- Gunny Debug's ammo ledger: where a gun's cartridges go
}

client_scripts {
    'client/main.lua',          -- asking the server, the drawn weapon, the one per-frame tick
    -- The one owner of the ped's ammunition: before weapons/reload/shooting, which all write through it.
    'client/ammo.lua',
    'client/weapons.lua',
    'client/reload.lua',
    'client/shooting.lua',
    'client/throwables.lua',
    'client/mounted.lua',       -- shooting from the saddle and from a wagon (whip_gunny's client/vehicle.lua)
    'client/guard.lua',         -- RDR2's own ammunition and loot taken back off the ped
    'client/wheel.lua',         -- RDR2's weapon wheel shows the pockets' guns (25 Nov 2026)
    'client/gunsmith.lua',      -- the gunsmith's bench
    'client/debug.lua',
}

files {
    -- A weapon pack's helper, `shared_script '@spur_gunny/lib/pack.lua'`: listed so a player's game can load it.
    'lib/pack.lua',

    -- Item pictures: spur_core looks for an item's picture in the resource that registered it, named after its item
    -- key. RedM (spur_gunny, 24 Nov 2026): this copy ships none (whip_gunny's are GTA's guns), and a glob that finds
    -- nothing is a warning at every start. To add your own, put them in html/img/items/ and uncomment these:
    -- 'html/img/items/*.webp',
    -- 'html/img/items/*.png',
    -- RedM (spur_gunny, 25 Nov 2026): one picture per class of item (server/items.lua), drawn for this copy.
    'html/img/items/class/*.svg',
}

-- RedM (spur_gunny, 24 Nov 2026): no ui_page (the gunsmith uses spur_core's own dialog), no data_file and no stream/:
-- whip_gunny's add-on GTA weapons, ammo boxes, gun props, clip sets and sounds are not part of this copy.
