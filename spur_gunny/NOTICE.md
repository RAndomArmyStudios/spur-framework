# whip_gunny: licence notice (spur_gunny is a modified copy: see the end)

Copyright (c) 2026 Whippy

whip_gunny is part of WHIP. Its code is licensed under the GNU Lesser General Public License 3.0 (`COPYING.LESSER`),
with the GPL 3.0 it builds on in `COPYING`. The licence covers WHIP's own code: not the WHIP name and logo, not the
Rockstar Games material (the game's names, data and files), and not the third-party parts, which keep their own
licences.

whip_core's `NOTICE.md` is the full notice for WHIP: the WHIP name and logo, the Rockstar Games material, and every
third-party part, each with its licence.

## This copy: spur_gunny

spur_gunny is a modified copy of whip_gunny 2.0.1, changed on 24 Nov 2026 to run on RedM (Red Dead Redemption 2)
beside spur_core, the RedM port of whip_core. It isn't WHIP and doesn't come from WHIP's author, so it has its own name.
Whippy allowed the port on two conditions: no one makes money from it, and it credits Whippy and WLVF. The changes:

- The resource and the names it uses are spur_ ones: `spur_gunny`, `spur_core`, and their events and exports.
- `fxmanifest.lua` says `game 'rdr3'`, a new name, author, description and version (`2.0.1-redm.1`), and has no
  `whip_updates`. It loads spur_core's RedM compatibility files. It has no `ui_page`, no `data_file` and no `stream/`.
- whip_gunny's original weapons, its remodelled add-on weapons, and their models, metas, animations, sounds, props and item
  pictures are not part of this copy. The items are RDR2's own weapons by their game names (`items/weapons.lua`): 28
  guns, 2 bows, 11 blades, torches and lassos, and 14 throwables.
- There are no magazines. A gun keeps the cartridges loaded in it in its own metadata, and **R** loads loose
  cartridges of the right kind from the pockets. whip_gunny's 24 calibers became 27 cartridge and arrow items, one per
  RDR2 ammunition kind (`items/ammo.lua`). The magazine panel, Load Bullets and Unload Bullets are gone; a gun's menu
  has Unload and Switch Cartridges. `RegisterMagazine` and `GiveMagazine` became `RegisterAmmo` and `GiveAmmo`.
- The weapon bench became the gunsmith: a spur_core action at a set place, with spur_core's own dialog in place of
  the bench's page. Scopes, barrels and rifling are items, fitted as RDR2's weapon components (`items/gunsmith.lua`).
  Suppressors, grips and flashlights are gone.
- Sticky bombs and grenades became dynamite and fire bottles: lit, thrown, and set off by their own fuse, with no
  remote detonation. Throwing knives, tomahawks, hatchets, bolas and poison bottles are throwables. The jerry can is
  gone.
- RDR2 hands out ammunition and weapons by itself. A guard takes them back: every ammunition pool is put back to what
  the items say after every shot, on every reload, on a short timer and when the weapon changes, and a weapon nobody
  drew from the inventory is taken away (`client/ammo.lua`, `client/guard.lua`).
- Shooting from vehicles became shooting from the saddle and from a wagon (`client/mounted.lua`, in place of
  `client/vehicle.lua`). The double tap on **RB** that started aiming is gone.
- Gunny Debug draws with RDR2's text natives and also shows the game's ammunition pool, what the game handed out and
  gunny took back, and the weapons the guard took. A new admin command, `/gunnyammoprobe`, prints what the game says
  about the drawn weapon's ammunition.
- `README.md` describes this copy.

Every code change is marked `RedM (spur_gunny, 24 Nov 2026)`. The licence is unchanged: LGPL 3.0 (`COPYING.LESSER`,
with `COPYING`).
