# whip_phone: licence notice (spur_phone is a modified copy: see the end)

Copyright (c) 2026 Whippy

whip_phone is part of WHIP. Its code is licensed under the GNU Lesser General Public License 3.0 (`COPYING.LESSER`),
with the GPL 3.0 it builds on in `COPYING`. The licence covers WHIP's own code: not the WHIP name and logo, not the
Rockstar Games material (the game's names, data and files), and not the third-party parts, which keep their own
licences.

Third-party parts in whip_phone:

- three.js (threejs.org) with its GLTFLoader, RoomEnvironment and BufferGeometryUtils, MIT:
  `html/vendor/three/LICENSE`.
- The phone's fonts (`html/core/fonts.js`), SIL Open Font License 1.1.

Neither is part of this copy (see below).

whip_core's `NOTICE.md` is the full notice for WHIP: the WHIP name and logo, the Rockstar Games material, and every
third-party part, each with its licence.

## This copy: spur_phone

spur_phone is a modified copy of whip_phone 1.1.0, changed on 24 Nov 2026 to run on RedM (Red Dead Redemption 2)
beside spur_core, the RedM port of whip_core. It isn't WHIP and doesn't come from WHIP's author, so it has its own
name. Whippy allowed the port on two conditions: no one makes money from it, and it credits Whippy and WLVF. The
changes:

- The resource and the names it uses are spur_ ones: `spur_phone`, `spur_core`, and their events, callbacks and
  exports (`spur_phone:*`, `exports.spur_phone`). The Lua global `Whip` and the page's `window.WhipPhone` keep their
  names: they are the API other resources write against.
- `fxmanifest.lua` says `game 'rdr3'`, a new name, author, description and version (`1.1.0-redm.1`), and has no
  `whip_updates` line. Its `files` list ships only what the game loads: not `html/dev`, `preview.html` or `docs`.
- The 3D Duo phone is gone: no three.js, no phone model, no web fonts. In its place is a flat pocket notebook drawn in
  HTML and CSS (`html/core/notebook.js`), closed in the corner and open as a two-page spread, on paper with the
  system's serif and typewriter faces (`html/core/themes.js`). Wallpapers are covers and paper
  (`html/core/wallpaper.js`); ringtones and alerts are bells, a chime and a telegraph sounder (`html/core/sounds.js`).
- The apps are the notebook's pages: Phone is Telephone, Messages is Telegrams, Bank is Passbook and Business is
  Ledger. The SIM card is a telegraph address card. What players read changed; the module ids, the item keys
  (`phone`, `sim_card`), the database tables and columns, and the requests stay whip_phone's.
- Errands have places (`shared/places.lua`, `config.lua`): a telegram is sent from a telegraph office, a call is
  placed from a telephone, and money is moved at a bank counter. The server checks each; the page says where the
  nearest one is. A telegram written elsewhere is kept as a draft.
- Calls go through spur_core's voice system and use only what it offers: on a voice system without a speaker (or
  without picking up the people near one), only the one holding the receiver hears the call. A lore character's call
  with a recording needs a voice bot; without one, the character sends a telegram instead (`server/lore.lua`).
- whip_phone's phone props and animations are gone (`Config.Emotes` holds nothing), controller rumble uses RDR2's
  `SET_CONTROL_SHAKE`, and the key bindings say Notebook.
- The inventory images (`html/img/items/phone.webp`, `html/img/items/sim_card.webp`) are new, drawn for this copy by
  a script; their lettering is set in Georgia and Courier New.
- `README.md` describes this copy.

Every code change is marked `RedM (spur_phone, 24 Nov 2026)`. The licence is unchanged: LGPL 3.0 (`COPYING.LESSER`,
with `COPYING`).
