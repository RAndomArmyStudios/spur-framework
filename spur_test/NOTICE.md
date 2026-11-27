# whip_test: licence notice

Copyright (c) 2026 Whippy

whip_test is part of WHIP. Its code is licensed under the GNU Lesser General Public License 3.0 (`COPYING.LESSER`),
with the GPL 3.0 it builds on in `COPYING`. The licence covers WHIP's own code: not the WHIP name and logo, not the
Rockstar Games material (the game's names, data and files), and not the third-party parts, which keep their own
licences.

whip_test has no third-party parts of its own.

whip_core's `NOTICE.md` is the full notice for WHIP: the WHIP name and logo, the Rockstar Games material, and every
third-party part, each with its licence.

## This copy: spur_test

spur_test is a modified copy of whip_test 1.0.0, changed on 23 Nov 2026 to run on RedM (Red Dead Redemption 2) beside
spur_core, the RedM port of whip_core. It isn't WHIP and doesn't come from WHIP's author, so it has its own name.
Whippy allowed the port on two conditions: no one makes money from it, and it credits Whippy and WLVF. The changes:

- The resource and the names it uses are spur_ ones: `spur_test`, `spur_core`, and their events and exports.
- `fxmanifest.lua` says `game 'rdr3'`, a new name, author and description, and no update check against WHIP's
  releases.
- The runner also writes each failure and skip, and the totals, to the server console.
- Tests of what RDR2 doesn't have are skipped on RedM, with the reason.
- RDR2's things replace the original game's in the tests, named once in `shared/redm.lua`: the test vehicles, people, props,
  weapons, the Director tests' field (the original field, an airport, is empty sky on RDR2's map), `mp_male`/`mp_female` and the
  `SUNNY` weather. The emote, voice and progress-bar tests watch RDR2 scenarios instead of the original game's clips and props.
- spur_core's compat layer and emote list are loaded here too, so a test reads a native, and the emotes, the way
  spur_core does.
- Some tests that had fallen behind spur_core's own API are brought up to date: `CreateGroundItem`'s one table,
  accessory slots' `accepts` lists and key slots, and `AddAction` reading `distance` as `reach`.
- Clean-up fixes: going home after the Director tests lands on the floor, not the roof, and a test stranger's
  bank accounts are cleared before the stranger is removed.
- `README.md` describes this copy.

Every code change is marked `RedM (spur_test, 23 Nov 2026)`. The licence is unchanged: LGPL 3.0 (`COPYING.LESSER`,
with `COPYING`).
