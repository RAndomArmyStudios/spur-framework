# spur_test

The automated test suite for [spur_core](../spur_core) on RedM, ported from whip_test by Whippy. It runs spur_core's
real exports, events and screens on a running server and reports what passed and what failed. It also has a load
test, which measures what spur_core costs with a full server without needing the players. Non-commercial and credited: Whippy allowed the port on the condition that no one makes money from it and that it
credits Whippy and WLVF.

**For a test server only.** A run gives and takes items and money on the tester's character, makes test doors,
containers and vehicles, and the load test deliberately strains the server. Never ensure it on a live server.

## Requirements

- `spur_core`, and `oxmysql`.
- A tester with the `whip.devtools` ACE (spur_core keeps that name) and developer mode on (`/w`).
- A chat resource (`spur_chat`) to see the results in game. Every failure and skip, and the totals, also go to the
  server console as `[spur_test]` lines.

## Installation

Put `spur_test` in your test server's `resources` folder, but don't add it to `server.cfg`. Start it from the server
console when you want it (`ensure spur_test`) and stop it afterwards (`stop spur_test`).

## Commands

| Command | Does |
| --- | --- |
| `/test` | Opens the test menu: a card per section, and the full suite. |
| `/test all` | Runs the full suite. |
| `/test <section>` | Runs one section, by its id in `shared/sections.lua`. |
| `/teststop` | Stops a run. |
| `/testlong` | The endurance run. |
| `/testload` | The load test. Every dial has a default, so bare `/testload` is a full run. |
| `/testloadstop` | Stops a load test. Works from the server console. |
| `/testloadclean` | Counts what a load test left behind, and deletes it only with `confirm`. |

`/testpanel`, `/testpanelro`, `/dumpster`, `/lootcrate`, `/medkit`, `/evidence`, `/vendingmachine`, `/toolbox`,
`/dropoff`, `/safebox`, `/trashcan` and `/showcase` open demo panels.

## On RedM

The suite was written for another game. Tests of what RDR2 doesn't have (cars and their parts, for example) report as
skipped on RedM with the reason, rather than failing. The rest test spur_core itself: a failure there is a bug in
the port.

The RDR2 vehicles, people, props and weapons the tests use, and where the Director tests take you, are named once in
`shared/redm.lua`. The Director tests try each of its `TEST_FIELDS` in turn and use the first that is flat where you
land; if none is, they're skipped and say so. Change a name there if a model doesn't load on your server.

## License

spur_test is licensed under the GNU LGPL 3.0; see `COPYING.LESSER`, and `COPYING` for the GPL 3.0 it builds on.
`NOTICE.md` is whip_test's notice with what this copy changed.
