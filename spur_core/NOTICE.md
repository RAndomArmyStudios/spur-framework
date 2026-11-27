# WHIP: licence notice

Copyright (c) 2026 Whippy

This is WHIP's licence notice, shortened to what this copy, spur_core, contains. The last section says how this copy
differs from WHIP.

## WHIP's own code

whip_core and WHIP's own resources (whip_autos, whip_autos_shop, whip_chat, whip_dealership, whip_fuel,
whip_gunny, whip_loadingscreen, whip_phone, whip_rope, whip_voice) are licensed under the GNU Lesser General Public License 3.0:
each resource's `COPYING.LESSER`, with the GPL 3.0 it builds on in `COPYING`. The code in WHIP's map packs and media
packs is under the same licence, in each pack's own `COPYING.LESSER` and `COPYING`.

In WHIP, one file is under the GNU General Public License 3.0 instead: whip_core's `shared/emote_list.lua`, because it
is made from RPEmotes (below). This copy doesn't carry that list: its `shared/emote_list.lua` is new, under the LGPL 3.0.

The example resources (names ending in `_example` or `_examples`) are under the MIT licence, in their own `LICENSE`:
copy them into your own resources freely.

Your own resources that use WHIP through its exports are yours, under any licence you choose: see **Selling on
WHIP** in the docs.

## The WHIP name and logo

The licence covers WHIP's code, not its name or its logo. A modified copy or a fork must not be called WHIP, or use
WHIP's logo, in a way that suggests it is WHIP or comes from WHIP's author. Saying that your resource works with WHIP
is fine.

## Game material

WHIP's full notice lists pictures, videos, map files, logos and game data that belong to Rockstar Games and Take-Two
Interactive, made for the game WHIP was written for. WHIP's licence does not cover them and gives you no rights to
them. None of them is part of this copy.

WHIP is not affiliated with, endorsed or sponsored by Rockstar Games or Take-Two Interactive.

## Third-party parts

Each keeps its own licence.

| What | Where | Licence |
|---|---|---|
| txAdmin's death reasons, by André Tabarra (github.com/tabarra/txAdmin): the names of the shared death causes (fall, drowning, fire and the rest) | client/stats.lua, with its licence above the list | MIT, Copyright (c) 2019-2025 Take-Two Interactive Software, Inc. |
| three.js | html/js/vehicle_hud/vendor | MIT |
| Material Design Icons: the turbocharger glyph | html/js/glyphs.js | Apache 2.0 |
| Fonts: Archivo Narrow, Arimo, Barlow, Barlow Condensed, Big Shoulders, Bricolage Grotesque, Michroma, Orbitron, Plus Jakarta Sans, Rajdhani, Roboto, Russo One, Saira, Saira Condensed, Saira Semi Condensed | html/fonts and html/js/vehicle_hud/fonts | SIL Open Font License 1.1 |
| The English keyboard words, from hermitdave's FrequencyWords (OpenSubtitles 2018) | html/keyboard/en.txt | CC BY-SA 4.0 |

WHIP's emote list is made from RPEmotes, by TayMcKenzieNZ, Mathu_lmn, MadsL and the RPEmotes community, which grew
from DullPear's dpemotes (it carries on as rpemotes-reborn, github.com/alberttheprince/rpemotes-reborn). That list
is not part of this copy.

## Contributing

WHIP's own code is owned by one author, which keeps its licence open to change for future versions. By sending code,
art or text to WHIP, you license it to WHIP's author under the MIT licence, so it can be released under WHIP's licence
or any later one.

## This copy: spur_core

spur_core is a modified copy of whip_core 1.3.0, changed from 23 Nov 2026 by RyuuTheKitsune to run on RedM (Red Dead
Redemption 2). It isn't WHIP and doesn't come from WHIP's author, so it has its own name and no WHIP logo. Whippy
allowed the port on two conditions: no one makes money from it, and it credits Whippy and WLVF. The sections above are
WHIP's own notice, shortened to what this copy contains: where they name a whip_ resource, this copy's is the spur_
one.

- Every change is marked in the code with `RedM (spur_core, <date>)` and listed in `CONVERSION.md`.
- RDR2 lists and flag names come from femga's rdr3_discoveries and from Halen84.
- The map data in `map/` was made for this copy from a survey of the game (`dev/`).
- Red Dead Redemption 2, its names and its data belong to Rockstar Games and Take-Two Interactive. This copy is not
  affiliated with, endorsed or sponsored by them.
