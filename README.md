# SPUR

A non-commercial RedM (Red Dead Redemption 2) port of [WHIP](https://github.com/WHIPFX/whip_core), Whippy's
framework. Ported and customised by **RyuuTheKitsune**.

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

3. Enter your licence key and your database details when it asks. On a game host the database is rarely on
   `localhost`: open "Show/Hide Database options" and put in the host, port, user, password and database name
   from your host's panel. If the database already exists and its user can't create databases (the usual case
   on a host), untick "delete existing database".
4. Let it run. It downloads the base server files, oxmysql and SPUR, writes `server.cfg`, and connects the
   database.
5. On the last step txAdmin shows `server.cfg`. If your server's port is not 30120, change the port in the two
   `endpoint_add` lines to yours. Then save and start the server.

The recipe makes you the admin (the txAdmin master account). It was run from start to end in txAdmin 8.1.2 on a
Pterodactyl host on 25 Nov 2026: every step passed, the eight resources started and spur_core made its tables in an
empty database. Joining it in the game worked too: landing screen, a new character, and a spawn in the world. If a step fails for you, please open an
issue with the step's name.

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
  [WHIP's documentation](https://github.com/WHIPFX/whip_core) applies, except for what CONVERSION.md lists as doing
  nothing on RDR2.
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
- **The Metropolitan Museum of Art**, Open Access (CC0), the **Armémuseum** (Swedish Army Museum), the **National
  Museum of American History**, the **US National Park Service** and **Wikimedia Commons** contributors: the
  public-domain and CC0 photographs behind spur_gunny's gun pictures (`spur_gunny/html/img/items/SOURCES.md`).
- Red Dead Redemption 2 and its names and data belong to Rockstar Games and Take-Two Interactive. SPUR is not
  affiliated with or endorsed by them.
