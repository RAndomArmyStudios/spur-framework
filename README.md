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

**With txAdmin:** use [recipe.yaml](recipe.yaml) as a custom recipe (txAdmin setup → Custom Template → paste the
recipe's raw URL). It downloads SPUR and oxmysql, writes `server.cfg`, and connects the database.

**By hand:**

1. A recent FXServer started as RedM with OneSync, MariaDB 10.2.3+ or MySQL 8.0.16+, and
   [oxmysql](https://github.com/overextended/oxmysql).
2. Copy the `spur_*` folders into `resources/[spur]/`.
3. Copy [server.cfg.example](server.cfg.example) to `server.cfg` and fill in your licence key, database and admin
   identifier.
4. Start the server. There is no SQL to import: the tables are made on the first start. The console prints a setup
   report, and each line marked **FIX** says what to change.

Don't run it beside another framework (VORP, RSG, RedEM:RP, QBR), inventory or target resource.
[spur_core/README.md](spur_core/README.md) has the first-run steps, the admin tools and the keys.

## Licence and credits

LGPL-3.0, as WHIP is (each resource's `COPYING.LESSER` and `COPYING`); see [NOTICE.md](NOTICE.md) and each
resource's `NOTICE.md` for the parts under other licences.

- **Whippy** and **WLVF**: WHIP, the original code.
- **RyuuTheKitsune**: the RedM port and its changes.
- **femga** (rdr3_discoveries) and **Halen84**: RDR2 data lists and flag names the port uses.
- Red Dead Redemption 2 and its names and data belong to Rockstar Games and Take-Two Interactive. SPUR is not
  affiliated with or endorsed by them.
