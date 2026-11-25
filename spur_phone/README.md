# spur_phone

A pocket notebook for spur_core on RedM (Red Dead Redemption 2). Players send telegrams from a telegraph office,
keep their contacts, a bank passbook and a business ledger. Telephone calls are off unless a server turns them on. Every page is a module: leave out
the ones you don't want, or add your own from another resource.

spur_phone is a port of whip_phone 1.1.0 to RedM, made with its author's permission on two conditions: no one makes
money from it, and it credits Whippy and WLVF. Credit: whip_phone is by Whippy and WLVF. It isn't WHIP and doesn't
come from WHIP's author. `NOTICE.md` lists what changed.

## Features

- **A notebook, not a phone.** Closed, it sits in the bottom-right corner; open, it is a two-page spread in the middle
  of the screen. Paper, ink and a leather cover, drawn flat: no 3D, nothing to download.
- **Telegrams.** Write one anywhere and read them anywhere. It is sent only from a telegraph office: away from one,
  the page says where the nearest office is and keeps your telegram until you get there.
- **Telephone calls are off by default** (25 Nov 2026, `Config.Calls = false`): a notebook is for telegrams. The
  Telephone page is then a **Contacts** page (names and telegraph addresses, Telegram, Block), nobody can place a
  call, and a lore character's call comes as a telegram. With `Config.Calls = true`: placed only from a telephone. A call ringing in can be answered anywhere (see
  [On RedM](#on-redm)). Players talk with their usual key, over the server's voice system.
- **Telegraph address cards.** An address (the number people wire and telephone) lives on its card. Put a card in any
  notebook and you send and call as that address, with its contacts and telegrams. Its owner can lock an address so
  its card stops working.
- **Passbook.** Balances and activity read anywhere. Transfers, opening and closing an account, and sharing one are
  done at a bank counter.
- **Ledger.** Your jobs and duty and, for ranks that may, hiring, firing and ranks. Works anywhere.
- **Make it yours.** Covers and paper, a telephone bell and chimes, Do Not Disturb, and a contact card with your name
  and photograph.
- **Block a number.** Its telegrams and calls stop reaching your card, and its owner isn't told. Block from a
  number's telegrams or its page in Telephone, and unblock in **Settings > Blocked numbers**. Lore characters can't
  be blocked.
- **Notices.** They peek up from the corner while the notebook is put away, and a ringing call can be answered
  without taking it out.
- **Mouse, keyboard or controller.** The layout follows what the player is using.
- **Skill check games.** Seven games on the open notebook, such as Safe Crack and Reroute, for spur_core's skill
  checks and the Director.
- **Lore characters.** The Director's characters have addresses. They wire players and telephone them.

## Pages are modules

The notebook's core has no pages of its own. Each is a module, and these come with it:

| Page | Module id | What it does |
| --- | --- | --- |
| Contacts (Telephone with `Config.Calls`) | `phone` | Contacts; with calls on, also Recents, the number to ask for and the call screen |
| Telegrams | `messages` | Telegram conversations |
| Passbook | `bank` | Accounts and their activity, transfers, opening savings and shared accounts, and sharing one |
| Ledger | `business` | Your jobs and duty and, for ranks that may, hiring, firing and ranks |
| Settings | `settings` | Your contact card, cover and paper, bell and chime, address card, blocked numbers, Do Not Disturb and installed pages |

`Config.Modules` lists the ones that load. Take an id out and that page is gone from every notebook. The notebook
works with any set, or none. Keep `skillcheck` for the skill check games: it has no place on the index.

The Passbook and Ledger act as the character holding the notebook, whatever address card is in it. Sharing an account
and hiring send an invite that the other player accepts in their own notebook (accepting an account share is done at
a bank counter).

## On RedM

- **Where things are done.** `config.lua` has three lists of places: `Config.TelegraphOffices`, `Config.Telephones`
  and `Config.BankSpots`. Each place is a label, a position and a radius. The server checks the player's position
  for every telegram sent, call placed and money moved, and the page names the nearest place. `Config.PlaceChecks =
  false` lets everything be done anywhere (for testing).
- **The places.** The telegraph offices are the telegraph windows of eight towns' stations and post offices
  (Valentine, Rhodes, Saint Denis, Blackwater, Armadillo, Annesburg, Strawberry, Emerald Ranch), each taken in game
  where a player stands at the window, with a radius of 4 m. The telephones are the station agent's telephone at five
  of them (Saint Denis, Valentine, Rhodes, Blackwater, Annesburg). The bank counters are spur_core's own
  (`Config.BankCounters`); Valentine's has been used in game. To add a place, stand there, take the position
  (`/vec4`) and give it a radius of about 4 m.
- **Answering anywhere.** A call is placed from a telephone, but one ringing in is answered wherever the player is.
  Read it as being sent for to the nearest telephone: the alternative, calls that only reach players standing at a
  telephone, would mean almost no call is ever answered.
- **The voice system.** Calls use whatever spur_core's voice system offers, and nothing more. spur_voice has telephone
  lines but no speaker, so a call is heard only by the one holding the receiver, and the speaker button isn't shown.
  A voice system with a speaker gets it back (`Config.SpeakerRange`). With no voice system running, the Telephone
  page says the lines are down (`Config.VoiceDownText`); telegrams, the Passbook and the Ledger still work.
- **Lore calls.** A lore character's call with a recording needs a voice bot. Without one (spur_voice has none), the
  character sends the call's **Telegram instead** text, or a line saying they telephoned and could not get through.
- **A pigeon goes up with a telegram** (25 Nov 2026, `Config.Pigeon`, `client/pigeon.lua`). RDR2 has no animation
  of letting a bird go, so it is built from parts: the sender takes the bird from the satchel (the Naturalist's
  herb clip), a real pigeon sits in the hands, then flies off and is removed. Players near see it. It is skipped on a
  horse, in a wagon and in the water. Other resources can call `exports.spur_phone:ReleasePigeon()`.
- **No prop, no animation.** whip_phone held a GTA phone. No RDR2 notebook animation has been tried in game yet, so
  `Config.Emotes` holds nothing: name a spur_core emote there once one has been.

## Requirements

- `spur_core` (the RedM port of whip_core) and oxmysql.
- For telephone calls, a voice system set up in spur_core, such as spur_voice. Everything else works without one.

## Installation

Put `spur_phone` in your `resources` folder and add this line to `server.cfg`, after `ensure spur_core`:

```cfg
ensure spur_phone
```

spur_phone creates its own tables on its first start. There's no SQL to import. It uses whip_phone's tables as they
are, so an existing database carries over.

## Getting a notebook

1. Get a **Pocket Notebook** (`phone`) and a **Telegraph Address Card** (`sim_card`): sell them in a shop, or take
   them from `/spur` → Economy → Items.
2. Right-click the notebook in the inventory, choose **Address card pocket**, and put the card in.
3. Press **F3**.

An address card gets a fresh address for whoever it's given to or bought by. One made for nobody, such as a card in a
stash or a Director reward, gets an address when it's first put in a notebook.

## For players

| Key | Does |
| --- | --- |
| **F3** | Take the notebook out or put it away |
| **Y** | Answer a ringing call |
| **U** | Decline a ringing call |

Players can rebind these in the game's key binding settings ("Notebook: open / close", "Notebook: answer a call",
"Notebook: decline a call"). The notebook is also on the F1 wheel and, on a controller, on D-pad up.

The notebook works with the mouse, or with the arrow keys, **Enter**, and **Esc** or **Backspace** to go back. On a
controller, **Y** opens and closes it; with the mouse, use the ribbon at the top of the page. Players can keep walking
while the notebook is out.

## For admins

- **`/spur` → Phones** lists every address. Open one to see whose it is and what it holds, change it, give yourself
  its card, delete it, or read its telegrams and calls.
- **The Director's Lore cards** (Give Contact, Send Telegram and Telephone Call) put lore characters in players'
  notebooks. See [On RedM](#on-redm) for calls with a recording.
- **The Skill Check Tester** is a page that appears for admins with developer mode on (`/w`). It plays any skill check
  game at any level.

## Configuration

`config.lua` sets:

| Settings | What they control |
| --- | --- |
| `OpenKey`, `AnswerKey`, `DeclineKey` | The default keys |
| `Calls` | Telephone calls on or off (off: telegrams only, the default) |
| `Pigeon` | The pigeon let go when a telegram is sent: on or off, and which bird |
| `PhoneSize` | The closed notebook's height, as a share of the screen |
| `Modules`, `DeveloperApps` | Which pages load, for everyone and for developers |
| `Defaults` | A fresh notebook's cover, sounds and volume |
| `PlaceChecks`, `TelegraphOffices`, `Telephones`, `BankSpots` | Where telegrams are sent, calls placed and money moved |
| `NumberPrefixes`, `RingSeconds`, `MessageHistory`, `RecentCalls` | Addresses, how long a call rings, and how much history the notebook loads |
| `CallSound`, `SpeakerRange`, `VoiceDownText` | How a call sounds, how far a speaker carries (where there is one), and what the page says with no voice system |
| `Emotes` | What the player holds while the notebook is out (nothing by default) |
| `SkillGames` | Each skill check game's three levels |

## For developers

- **Your own page.** Register it from your resource with `exports.spur_phone:RegisterModule({ id, script })`; it goes
  when your resource stops. A page can use the notebook's UI kit, or draw itself with any library, and its CSS is
  scoped to it. whip_phone's `docs/MODULES.md` is the guide (read `whip_phone` as `spur_phone`).
- **Places and voice.** A page's `app.where` says where the player stands (`{ checks, telegraph, telephone, bank }`,
  each `{ here, nearest, dist }`), and `app.voice` what the voice system offers (`{ down, lines, speaker, pickup }`).
  The kit's `place(app, kind)` turns `app.where` into `{ ok, here, text }`.
- **Exports.** On the server: `Notify`, `Push`, `Open`, `Close`, `SetSession`, `ReloadCache`. On the client: `Open`,
  `Close`, `IsOpen`, `GetState`, `Notify`, `Push`, `RegisterModule`, `UnregisterModule`, `RunApp`, `IsHeld`. Events
  and callbacks are named `spur_phone:*`; whip_phone's `docs/FRAMEWORK.md` describes each.
- The Lua global `Whip` and the page's `window.WhipPhone` keep their names.

## License

spur_phone is licensed under the GNU LGPL 3.0; see `COPYING.LESSER`, and `COPYING` for the GPL 3.0 it builds on.
`NOTICE.md` says what the licence doesn't cover and what this copy changed.
