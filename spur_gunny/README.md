# spur_gunny

Weapons for spur_core on RedM (Red Dead Redemption 2): RDR2's guns, bows, blades, lassos and throwables as inventory
items, loose cartridges the server counts, and a gunsmith who fits scopes, barrels and rifling.

spur_gunny is a port of whip_gunny 2.0.1 to RedM, made with its author's permission on two conditions: no one makes money
from it, and it credits Whippy and WLVF. It isn't WHIP and doesn't come from WHIP's author.
`NOTICE.md` lists what changed.

## Features

- **Every RDR2 weapon an item.** 28 guns (revolvers, pistols, repeaters, rifles and shotguns), 2 bows, 11 blades,
  torches and lassos, and 14 throwables. Nothing is streamed: the game draws every one of them.
- **Guns with state.** Each gun has a serial number and keeps the cartridges loaded in it, saved with the inventory.
- **Loose cartridges, no magazines.** **R** loads cartridges of the right kind from your pockets. There are 27 kinds:
  regular, express, high velocity and split point for revolvers, pistols, repeaters and rifles; elephant and varmint
  rounds; buckshot, slugs and incendiary buckshot; and six kinds of arrow. A gun holds one kind at a time, and
  **Switch Cartridges** empties it for another.
- **Server-side ammo.** The server records which gun each player has drawn and takes every round fired from its count.
- **Only what the server counts.** Ammunition the game hands out by itself is taken back (see below), and a weapon
  nobody drew from the inventory is taken away.
- **The gunsmith.** Scopes, barrels and rifling are items, fitted and taken off at the gunsmith's.
- **Dynamite and fire bottles.** Light the fuse and throw: they go off by themselves. Throwing knives, tomahawks,
  hatchets, bolas and poison bottles are throwables too. Each one thrown leaves the stack.
- **From the saddle and a wagon.** Shots count the same, and an empty gun reloads when you pull the trigger.
- **Weapon packs.** Add your own items for RDR2's weapons and cartridges from a resource of your own, without editing
  spur_gunny.
- **Controller support.**

## On RedM

- **Looted ammunition is not kept.** RDR2 hands out ammunition by itself: from bodies you loot, boxes you pick up,
  kits, cheats. None of it is kept. After every shot, on every reload, twice a second and whenever the weapon in hand
  changes, spur_gunny puts every ammunition pool back to what the items say: the drawn gun never holds more than the
  server counts, and every other kind is emptied. Cartridges come only as items (shops, `GiveAmmo`). Thrown knives,
  tomahawks and hatchets and shot arrows picked up again are not kept either: each one thrown or shot is gone. A gun
  picked up off a body is taken away (`Config.Guard`).
- **Drawing.** **Equip** puts the weapon straight into your hands, with no draw animation. Putting it away plays the
  game's own holster.
- **Pictures of its own.** whip_gunny's pictures are of another game's guns, so none of them ship. Each item shows
  the picture of its kind instead (`html/img/items/class/`: a revolver, a repeater, a box of cartridges...; the five
  guns are public-domain photographs from The Met's Open Access collection). Eighteen guns also have a picture of
  their own model in `html/img/items/`, cut from public-domain and CC0 photographs; `SOURCES.md` there says which
  gun each one is and which models still wait. To add or change one, put a file there named after the item
  (`gunny_cattleman.webp`, say).
- **Two weapon guards.** spur_core's guard knows RDR2's weapons, and spur_gunny permits each gun before it gives
  it (`PermitNativeWeapon`) and keeps a guard of its own as well.

## Requirements

- `spur_core` (the RedM port of whip_core).

## Installation

Put `spur_gunny` in your `resources` folder and add this line to `server.cfg`, after `ensure spur_core`:

```cfg
ensure spur_gunny
```

There's no SQL to import. The items appear in spur_core's item list, ready to sell in shops or hand out.

## For players

**Equip** a weapon in the inventory to draw it, and again to put it away. A gun's menu also has **Unload** (its
cartridges back into your pockets) and **Switch Cartridges**; a bow's has **Switch Arrows**.

| Key | Controller | Does |
| --- | --- | --- |
| **R** | **B** | Reload: loose cartridges of the kind in the gun, from your pockets |
| **G** | **LB + B** | Check how full the gun is |
| The **Gunsmith** prompt, with a gun drawn | | Fit a part you carry, or take one off |

The last round fired reloads the gun by itself, if you carry its kind. In the saddle or on a wagon, pulling the
trigger on an empty gun reloads it too.

**R** and **G** are key mappings: players can rebind them in the game's key bindings.

## Configuration

`config.lua`:

- **`Config.Gunsmith`:** whether there is a gunsmith, and its place, prop model and name.
- **`Config.Reload`:** reloading by itself when the gun runs dry, and how long a reload may take.
- **`Config.Guard`:** whether weapons nobody drew are taken away, how often the ped is looked over, weapons to leave
  alone, and the special ammunition kinds no item stands for.

The weapons, cartridges and gunsmith's parts are in `items/`. Each file's header lists its fields.

With developer mode on, **/w > Debug > Gunny Debug** shows how the game, spur_gunny and the server each count the
drawn gun's rounds, the shots sent and confirmed, what the game handed out and spur_gunny took back, and the
cartridges you carry.

## Admin commands

These need developer mode on (`/w`).

| Command | Does |
| --- | --- |
| `/gunnydebugreset` | Zeroes Gunny Debug's counters |
| `/ammoledger [reset]` | Prints where the drawn gun's cartridges went, your game's half and the server's, in the F8 console. `reset` starts both again |
| `/gunnyammoprobe` | Prints what the game says about the drawn weapon's ammunition, in the F8 console |
| `/gunnydebugserver` | Says which weapon you have drawn; from the server console, everyone's |

## For developers

Add `dependency 'spur_gunny'` to your fxmanifest, then:

- **Server:** `GiveWeapon(source, item, overrides, reason)` hands out a gun with a serial you can track (loaded,
  with a kind of cartridge and fitted parts if you like), and `GiveAmmo(source, item, amount, reason)` hands out
  cartridges. The events `spur_gunny:weapon:drawn`, `spur_gunny:weapon:holstered` and `spur_gunny:weapon:fired`
  report every draw, holster and shot.
- **Client:** `GetDrawnWeapon` and `IsWeaponDrawn` read the weapon in hand; `DrawWeapon(slot, pocket)` draws one from
  the inventory.
- **Weapon packs:** `RegisterAmmo` and `RegisterWeapon` add your own items. Load `@spur_gunny/lib/pack.lua` as a
  shared script and call them inside `Gunny.register(function() ... end)`, cartridges first, on both sides. A pack's
  weapon is one of RDR2's own `WEAPON_` names: RedM streams no new weapons. `shared/packs.lua` explains each field.

## Not tested in game

spur_gunny has only been checked offline (its Lua, and its natives against RDR2's list). These are guessed, and each
can be changed in its file:

- **The gunsmith's parts.** Every weapon component name in `items/gunsmith.lua`. A name the game does not know shows
  nothing on the gun and is said in the F8 console.
- **Ammunition names** in `items/ammo.lua` (`AMMO_22` for the Varmint Rifle above all) and `Config.Guard.alsoZero`. A
  cartridge the game does not take for its gun is said in the F8 console as the gun is drawn.
- **The gunsmith's place** (Valentine's, by the counter) and any prop model for it.
- **How RDR2 counts a gun's ammunition.** Whether its pool includes the rounds in the gun is learned per gun the first
  time it is drawn (`client/ammo.lua`); `/gunnyammoprobe` shows what the game says.
- **Each gun's `capacity`** against the game's own clip size (Gunny Debug says in F8 when they differ), and the props
  guns lie on the ground as.
- **A shot the game shows but takes no round for** is charged one round. If the game takes the round late, that shot
  could be charged twice.
- **Reloading in the saddle and on a wagon,** and the draw and holster as described above.
- **The gunsmith's choice dialog** (spur_core's `Input` with a select field).
- **The keys and controller buttons** (`gunny_reload` and `gunny_check_ammo` on spur_core's pad).

Known limits: a shot fired during a reload is lost if the gun leaves your hands mid-reload (death, say), and RDR2's
special kinds with no item (explosive rounds, tranquilizer darts, volatile dynamite...) are only ever taken back.

## License

spur_gunny is licensed under the GNU LGPL 3.0; see `COPYING.LESSER`, and `COPYING` for the GPL 3.0 it builds on.
`NOTICE.md` says what the licence doesn't cover and what this copy changed.
