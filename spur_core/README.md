# spur_core

A non-commercial RedM (Red Dead Redemption 2) port of [whip_core](https://github.com/WHIPFX/whip_core) 1.3.0, the
core of Whippy's WHIP framework for FiveM. It provides characters, inventory, money and banks, jobs, shops, homes,
the UI, the Director and an in-game admin panel, now running on RDR2's natives.

> **Not WHIP.** spur_core is a fork. It isn't made, endorsed or supported by WHIP's author. Whippy allowed the port
> on two conditions: **nobody makes money from it** (don't sell it, bundle it into anything paid, or put it behind a
> paywall), and **it credits Whippy and WLVF**.

> **Status (23 Nov 2026): runs on RedM and has been played in game.** Joining, making a character, spawning, the HUD,
> the inventory, the radial menu, chat, the bank counters and the admin tools work. Read [CONVERSION.md](CONVERSION.md)
> before using it. It explains what works, what's a no-op on RDR2, and what still has to be tried in game.

## What carries over from whip_core

- **Characters.** Several per account, with a choice of where to arrive. On RDR2 the appearance editor sets the head,
  build, skin tone, eyes, hair, beard and an outfit preset (see CONVERSION.md).
- **Inventory.** Items are physical: cash is banknotes, bags weigh what they hold, and items can be dropped, thrown or
  stashed.
- **Money and banks.** Personal, savings, shared and business accounts. The bank menu is at each town's teller window.
- **Jobs.** Ranks, permissions, clocking on and off, and a business account.
- **Shops.** Unlimited stock, player-run stock, or the server's own.
- **Homes.** Players buy, furnish and store things in their homes, and hand out keys.
- **Health and needs.** Health, hunger, thirst, death with respawn and revive, and escorting.
- **The world.** Lockable doors, zones, shared time and weather (RDR2's), and server-run NPCs.
- **UI.** HUD, prompts, radial menu, notifications, progress bars and skill checks.
- **The Director.** Missions and stories built in game from cards.
- **Admin panel.** `/spur` manages players, items, shops, jobs, banks, homes, doors, zones and every setting.
- **Security.** The server validates what a player's game sends before any resource's code runs.

GTA's cars, clothing, emotes, scaleform pause menu and minimap features don't exist on RDR2. Their natives are safe
no-ops, listed in CONVERSION.md.

## Requirements

- FXServer (a recent artifact) started as RedM (`set gamename rdr3`; docs.fivem.net, Setting Up a Vanilla FXServer),
  with **OneSync** on.
- MariaDB 10.2.3+ or MySQL 8.0.16+, and [oxmysql](https://github.com/overextended/oxmysql) started before spur_core.

spur_core is a whole framework. Don't run it beside VORP, RSG, RedEM:RP, QBR, or another inventory or target
resource. The setup report names any clash it finds.

## Installation

1. Copy the `spur_core` folder into your server's `resources`.
2. In `server.cfg`:

   ```
   set gamename rdr3
   set onesync on
   sv_licenseKey "your key from portal.cfx.re"
   set mysql_connection_string "mysql://user:password@localhost/spur?charset=utf8mb4"
   ensure oxmysql
   ensure spur_core
   ensure spur_chat
   ensure spur_loadingscreen
   add_ace group.admin whip.devtools allow
   add_ace group.admin command allow
   add_principal identifier.license:YOUR_LICENSE group.admin
   ```

   `spur_chat` is the chat (whip_chat's RedM port, in its own folder). FXServer's own `chat` works too, but not
   both. Without a chat resource, T opens nothing and players can't type commands in game. The setup report says so.

   `spur_loadingscreen` is the loading screen (whip_loadingscreen's RedM port): the SPUR wordmark on an 1899
   backdrop. It's optional. Without it, players see RedM's own loading screen.

   oxmysql doesn't decode the `mysql://` form, so a password with `@ : / ? #` in it breaks it. Use the key=value
   form for such a password (it breaks only on `;`, `=` or `"`):
   `set mysql_connection_string "host=...;port=3306;user=...;password=...;database=spur;charset=utf8mb4"`

3. Don't start `basic-gamemode`, or turn spawnmanager's autospawn off. spur_core spawns players itself.

There's no SQL to import. spur_core creates its tables the first time it starts.

Recent FXServer builds have OneSync on already. On those, `set onesync on` only prints a warning that it can't be
changed, so leave the line out. The setup report's first line says whether OneSync is on.

Don't put a `;` in a server.cfg comment. FXServer treats it as the end of a command even after `#`, and runs the rest
of the line as a new command.

## First run

1. Start the server. The console prints a setup report, and each line marked **FIX** says what to change. Type
   `spursetup` in the console to see it again.
2. Join and make a character.
3. Type `/w` and turn on developer mode (needs the `whip.devtools` ACE).
4. Walk the spawn points, the character-select shots and the bank windows, and move any that are off with the in-game
   editors (`/spur` → Settings → Config).

`spursupport` in the server console prints the version, the setup report and recent errors in one block.
`spurcompat` lists every RDR2 no-op that has been hit so far.

## Admin tools

| Command | What it is |
| --- | --- |
| `/w` | Quick tools: noclip, invisibility, god mode, coordinates, the Object Viewer and debug overlays. Developer mode is switched on here |
| `/spur` | The admin panel: players and bans, the economy, the world, the Director and settings. Needs developer mode on |
| `/tp x y [z] [heading]` | Teleport to a point |

## Keys

| Key | What it does |
| --- | --- |
| E | Use the prompt you're looking at (a bank window, a door, an item) |
| Mouse wheel | Step through a prompt's options |
| F2 | Inventory |
| Tab | Hotbar |
| F1 | Radial menu |
| T | Chat |

## Configuration

`config.lua` controls characters, money, inventory sizes, items, needs, respawn, jobs, time and weather, garages,
shops and the HUD. Most settings can also be changed in game under `/spur` → Settings → Config. A value saved there
overrides `config.lua` until you reset it.

## For developers

[dev/mcp/README.md](dev/mcp/README.md) sets up the MCP link: an AI client such as Claude Code can then test the game
on your PC without taking your mouse or keyboard.

Resources built on spur_core declare `dependency 'spur_core'`, load
`shared_script '@spur_core/lib/satellite.lua'`, and call it through its exports (`exports.spur_core:AddItem(...)`).
The API is whip_core's, so [WHIP's documentation](https://github.com/WHIPFX/whip_core) applies to everything except
the GTA-specific parts. `types/` gives your editor autocomplete, and `docs/examples/` holds two example resources.

WHIP's other resources (whip_gunny, whip_fuel, whip_phone, whip_autos and the rest) are GTA V resources and aren't
part of this port.

## Credits and licence

- **WHIP is credited to Whippy and WLVF.** Keep this credit in every copy and every port: it is a condition of
  the permission to port it.
- **whip_core** is by **Whippy** and licensed under the GNU LGPL 3.0. spur_core keeps that licence: see
  `COPYING.LESSER`, and `COPYING` for the GPL 3.0 it builds on.
- `shared/emote_list.lua` is GPL 3.0, because it comes from RPEmotes.
- The example resources in `docs/examples/` are MIT.
- `NOTICE.md` (whip_core's, unchanged) lists the third-party code, fonts and data under their own licences, and what the
  licence doesn't cover.

**Modified by:** the RedM port, 23 Nov 2026. The conversion is described in CONVERSION.md. Every hand-edited place
in the code is marked `RedM (spur_core, 23 Nov 2026)`. The new files are `shared/rdr_compat.lua`,
`shared/rdr_compat_stubs.lua` and `client/rdr_bank_counters.lua`.

Red Dead Redemption 2 belongs to Rockstar Games and Take-Two Interactive. spur_core isn't affiliated with or endorsed
by them, or by Cfx.re.
