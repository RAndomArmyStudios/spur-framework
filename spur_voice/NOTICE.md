# whip_voice: licence notice (spur_voice is a modified copy: see the end)

Copyright (c) 2026 Whippy

whip_voice is part of WHIP. Its code is licensed under the GNU Lesser General Public License 3.0 (`COPYING.LESSER`),
with the GPL 3.0 it builds on in `COPYING`. The licence covers WHIP's own code: not the WHIP name and logo, not the
Rockstar Games material (the game's names, data and files), and not the third-party parts, which keep their own
licences.

whip_core's `NOTICE.md` is the full notice for WHIP: the WHIP name and logo, the Rockstar Games material, and every
third-party part, each with its licence.

## This copy: spur_voice

spur_voice is a modified copy of whip_voice 1.0.0, changed on 24 Nov 2026 to run on RedM (Red Dead Redemption 2)
beside spur_core, the RedM port of whip_core. It isn't WHIP and doesn't come from WHIP's author, so it has its own
name. Whippy allowed the port on two conditions: no one makes money from it, and it credits Whippy and WLVF. The changes:

- The resource and the names it uses are spur_ ones: `spur_voice`, `spur_core`, and their events and exports.
- `fxmanifest.lua` says `game 'rdr3'`, a new name, author and description.
- The voice runs on RedM's own Mumble voice instead of a LiveKit voice server. None of these parts of whip_voice are
  in this copy: the LiveKit server and its download, the voice server's signalling and tokens, the NUI page and its
  JavaScript (with the LiveKit client and three.js), the voice bot service, the sound recipes' audio graph, rooms and
  acoustics, the radio, walkie-talkie, megaphone and speaker items, and their models and sounds. So none of their
  third-party licences apply to this copy.
- Kept from whip_voice: the voice ranges and dead players' silence (`config.lua`), and voice lines: the export
  contract of `docs/LINES.md`, with `server/lines.lua` and `server/lines_api.lua` changed to tell each member's game
  whom to talk to and hear. What Mumble can't do (a line on speaker, a line's sound) is answered as not supported.
- New: `client/main.lua` (each player's channel, the range, who hears them, the HUD mic, `/voicestatus`) and
  `server/world.lua` (the voice bot's exports, answering that there is none).
- `README.md` describes this copy.

Every code change is marked `RedM (spur_voice, 24 Nov 2026)`. The licence is unchanged: LGPL 3.0 (`COPYING.LESSER`,
with `COPYING`).
