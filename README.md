# SPUR

A non-commercial RedM (Red Dead Redemption 2) port of [WHIP](https://github.com/WHIPFX/whip_core), Whippy's
framework for FiveM. Ported and customised by **RyuuTheKitsune**.

> **Not WHIP.** SPUR is a fork. It isn't made, endorsed or supported by WHIP's authors.
> Original code by **Whippy** and **WLVF**. Whippy allowed the port on two conditions:
> **nobody makes money from it** (don't sell it, bundle it into anything paid, or put it behind a paywall), and
> **it credits Whippy and WLVF**. Keep both if you fork this.

> **Status: beta.** It runs on a live RedM server and has been played in game, but parts are untested or are
> no-ops on RDR2. Read [spur_core/CONVERSION.md](spur_core/CONVERSION.md) before you use it: it says what works,
> what does nothing on RDR2, and what is still to be tried.

## What's in here

| Resource | What it is | Port of |
| --- | --- | --- |
| [spur_core](spur_core/README.md) | The framework: characters, inventory, money and banks, jobs, shops, homes, doors, wagons, the HUD and prompts, the Director, the admin panel | whip_core |
| [spur_chat](spur_chat/README.md) | Chat and commands | whip_chat |
| [spur_loadingscreen](spur_loadingscreen/README.md) | Loading screen (optional) | whip_loadingscreen |
| [spur_gunny](spur_gunny/README.md) | RDR2's guns, cartridges and the gunsmith as items | whip_gunny |
| [spur_rope](spur_rope/README.md) | Rope | whip_rope |
| [spur_voice](spur_voice/README.md) | Voice | whip_voice |
| [spur_phone](spur_phone/README.md) | Phone | whip_phone |
| [spur_test](spur_test/README.md) | Test helpers for developers; leave it off on a live server | whip_test |

Each resource's README and NOTICE say what changed from the original.

## Install

SPUR is a whole framework. Don't run it beside another one (VORP, RSG, RedEM:RP, QBR), or beside another inventory
or target resource.

You need a MySQL or MariaDB database (MariaDB 10.2.3+ or MySQL 8.0.16+) and a server licence key from
[portal.cfx.re](https://portal.cfx.re). Most game hosts give you the database with the server.

### The easy way: txAdmin

txAdmin is the web panel that comes with FXServer. It can set SPUR up for you from a recipe.

1. Start a new server in txAdmin (on a host, that is usually "reinstall" or "new server"; at home, run FXServer
   and open the link it prints).
2. When txAdmin asks for the deployment type, pick **Remote URL Template** and paste:

   ```
   https://raw.githubusercontent.com/RAndomArmyStudios/spur-framework/main/recipe.yaml
   ```

3. Enter your licence key and your database details when it asks.
4. Let it run. It downloads the base server files, oxmysql and SPUR, writes `server.cfg`, and connects the
   database. Then save and start the server.

The recipe makes you the admin (the txAdmin master account). It has been dry-run step by step, but not yet run
through a real txAdmin from start to end: if a step fails, please open an issue with the step's name.

### By hand

1. Install a recent FXServer and [oxmysql](https://github.com/overextended/oxmysql).
2. Download this repository (the green **Code** button, then **Download ZIP**) and copy the `spur_*` folders into
   your server's `resources/[spur]/` folder.
3. Copy [server.cfg.example](server.cfg.example) to `server.cfg`. Fill in three things: your licence key, your
   database line, and your own identifier on the last line (take the `#` off it).
4. Don't start `basic-gamemode` (or turn spawnmanager's autospawn off). SPUR spawns players itself.
5. Start the server. There is no SQL to import: the tables are made on the first start.

### First start

1. Read the server console. It prints a setup report, and each line marked **FIX** says what to change. Type
   `spursetup` to see it again.
2. Join and make a character.
3. Type `/w` in chat and switch developer mode on. `/spur` then opens the admin panel.

[spur_core/README.md](spur_core/README.md) has the rest: the admin tools, the keys and the settings.

### Updating

Replace the `spur_*` folders with the new ones and restart the server. Settings you changed in game are kept in the
database. If you edited `config.lua` by hand, keep a copy first.

## For developers

- Resources built on SPUR use spur_core's exports. The API is whip_core's, so
  [WHIP's documentation](https://github.com/WHIPFX/whip_core) applies except for the GTA-only parts.
- [spur_core/CONVERSION.md](spur_core/CONVERSION.md) lists every change from WHIP, what does nothing on RDR2, and
  what is still untested.
- [spur_core/dev/mcp/README.md](spur_core/dev/mcp/README.md) sets up the MCP link, which lets an AI client such as
  Claude Code test the game on your PC without taking your mouse or keyboard.

## Licence and credits

LGPL-3.0, as WHIP is (each resource's `COPYING.LESSER` and `COPYING`); see [NOTICE.md](NOTICE.md) and each
resource's `NOTICE.md` for the parts under other licences.

- **Whippy** and **WLVF**: WHIP, the original code.
- **RyuuTheKitsune**: the RedM port and its changes.
- **femga** (rdr3_discoveries) and **Halen84**: RDR2 data lists and flag names the port uses.
- Red Dead Redemption 2 and its names and data belong to Rockstar Games and Take-Two Interactive. SPUR is not
  affiliated with or endorsed by them.
