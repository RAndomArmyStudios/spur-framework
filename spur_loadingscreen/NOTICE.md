# whip_loadingscreen: licence notice

Copyright (c) 2026 Whippy

whip_loadingscreen is part of WHIP. Its code is licensed under the GNU Lesser General Public License 3.0
(`COPYING.LESSER`), with the GPL 3.0 it builds on in `COPYING`. The licence covers WHIP's own code: not the WHIP name
and logo, not the Rockstar Games material (the game's names, data and files), and not the third-party parts, which
keep their own licences.

Third-party parts in this resource:

- three.js (threejs.org), MIT: its licence is at the top of each of its files.
- The Barlow, Bricolage Grotesque, IBM Plex Mono and Plus Jakarta Sans fonts, SIL Open Font License 1.1: their
  `OFL-*.txt` files beside them.

whip_core's `NOTICE.md` is the full notice for WHIP: the WHIP name and logo, the Rockstar Games material, and every
third-party part, each with its licence.

## This copy: spur_loadingscreen

spur_loadingscreen is a modified copy of whip_loadingscreen 1.6.2, changed on 23 Nov 2026 to run on RedM (Red Dead
Redemption 2) beside spur_core, the RedM port of whip_core. It isn't WHIP and doesn't come from WHIP's author, so it
has its own name. Whippy allowed the port on two conditions: no one makes money from it, and it credits Whippy and WLVF. The changes:

- The WHIP logo is gone. The SPUR wordmark (spur_core's, drawn for the port) takes its place in `html/index.html`, and
  the loading light (`html/js/logo.js`, whip_loadingscreen's) runs along the four circles in the bar under its letters.
- The blueprint is gone: three.js, its scene and picture atlas (`html/bp`), the `dev/` tools that made them, and the
  browser preview page. A backdrop drawn in CSS takes its place (`html/css/loading.css`). So this copy carries none
  of the third-party parts listed above: no three.js and no fonts.
- The light shows only the interaction icons that fit 1899: no cars, fuel, phone or dev tools (`NOT_1899` in
  `html/js/logo.js`). `html/js/icons.js` is otherwise whip_loadingscreen's copy of the icons.
- `fxmanifest.lua` says `game 'rdr3'`, a new name, author and description, and no update check against WHIP's
  releases.
- `README.md` describes this copy.

Every change is marked `RedM (spur_loadingscreen, 23 Nov 2026)`. The licence is unchanged: LGPL 3.0
(`COPYING.LESSER`, with `COPYING`).
