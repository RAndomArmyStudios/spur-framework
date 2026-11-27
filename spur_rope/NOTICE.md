# whip_rope: licence notice (spur_rope is a modified copy: see the end)

Copyright (c) 2026 Whippy

whip_rope is part of WHIP. Its code is licensed under the GNU Lesser General Public License 3.0 (`COPYING.LESSER`),
with the GPL 3.0 it builds on in `COPYING`. The licence covers WHIP's own code: not the WHIP name and logo, not the
Rockstar Games material (the game's names, data and files), and not the third-party parts, which keep their own
licences.

whip_core's `NOTICE.md` is the full notice for WHIP: the WHIP name and logo, the Rockstar Games material, and every
third-party part, each with its licence.

## This copy: spur_rope

spur_rope is a modified copy of whip_rope 1.0.0, changed on 24 Nov 2026 to run on RedM (Red Dead Redemption 2) beside
spur_core, the RedM port of whip_core. It isn't WHIP and doesn't come from WHIP's author, so it has its own name.
Whippy allowed the port on two conditions: no one makes money from it, and it credits Whippy and WLVF. The changes:

- The resource and the names it uses are spur_ ones: `spur_rope`, `spur_core`, and their events and exports.
- `fxmanifest.lua` says `game 'rdr3'`, a new name, author and description. It loads spur_core's RedM compatibility
  files, and it no longer streams the rope-piece model.
- The rope piece `whip_rope_seg` (by 3D Clanker, a model made for another game that RDR2 can't load) is not part of this copy. It is
  kept outside the resource, unchanged. The rope is drawn with RDR2's own rope instead (`client/mesh.lua`).
- whip_rope's props, bone numbers, ped flags, markers and Euphoria messages are replaced or turned off for RDR2, and the
  text says wagon where it said car.
- Hanging works around RDR2: a stand-in made by `ClonePed` hangs in place of your own body, a ragdoll RDR2 refuses is
  asked again, and one pulled 6 m off the rope lets go (`client/visuals.lua`, `client/hang_ragdoll.lua`).
- Ropes out are kept on the books in the resource's KVP, so a server that stops without warning still gives them back
  (`server/state.lua`).
- Admin commands to look into RDR2's ropes and peds: `/ropevertices`, `/ropevis`, `/ropeclonetest`.
- `README.md` describes this copy.

Every code change is marked `RedM (spur_rope, 24 Nov 2026)`. The licence is unchanged: LGPL 3.0 (`COPYING.LESSER`,
with `COPYING`).
