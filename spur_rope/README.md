# spur_rope

A physics rope for spur_core on RedM (Red Dead Redemption 2). Players carry it as an item, tie it to wagons, props and
the map, tow with it and hang off it. Other resources can make ropes of their own through its exports.

spur_rope is a port of whip_rope 1.0.0 to RedM, made with its author's permission on two conditions: no one makes
money from it, and it credits Whippy and WLVF. It isn't WHIP and doesn't come from WHIP's author. `NOTICE.md` lists what changed.

## Features

- **Tie it anywhere.** Tie an end to a wagon, a prop, or the wall, rock or ground you look at.
- **Towing.** A taut rope stretches a little, then pulls. A light wagon moves more than a heavy one, and a towed wagon
  nobody drives rolls freely.
- **Hanging.** Players hang off a rope and swing on it.
- **Dragged along.** Hold an end tied to a wagon that drives off, and you're dragged behind it for a few seconds.
- **Part of the world.** The rope lies on the ground, props and wagons. People push it aside, explosions throw it, and
  ropes rest on each other.
- **The same for everyone.** Every player sees the same rope, and a towed wagon follows the one pulling it at any ping.
- **In the Director.** Cards to make, move and remove ropes, and goals for tying a rope, hanging on one or pulling one
  too far.
- **Nothing lost.** A player who leaves with ropes out gets them back as items. So does one whose ropes were out
  when the server stopped, even without warning (a crash or a panel restart).

## On RedM

- **The look.** whip_rope drew its rope with a custom model placed by `SetEntityMatrix`. RDR2 can't load that
  model and RedM has no `SetEntityMatrix`. spur_rope draws RDR2's own ropes instead, pinned along the simulated rope
  (`Config.Visuals.Style = 'rdr'`, `RdrRopeType`). The pin native is unnamed in RDR2's list, so the first rope checks
  that its ends follow. If they don't, the console says so and ropes are drawn as a small prop per node (`'balls'`).
  Tested in game: the pins hold (0.00 m off).
- **How RDR2's rope types bend.** RDR2 gives each rope type a fixed number of vertices, whatever its length:

  | Vertices | Types |
  | --- | --- |
  | 2 | 0, 12, 15 |
  | 5 | 1, 6, 10, 13, 16, 17, 18 |
  | 7 | 3, 9 |
  | 16 | 4, 7, 11 |
  | 31 | 8 |
  | 33 | 5, 14 |
  | 181 | 2 |

  A type with 2 vertices is a straight line, so spur_rope draws it as a chain of short ropes end to end (about one
  per 0.4 m, 16 at most), each pinned at both ends. The default, type 0, is drawn that way. `/ropevertices` prints
  the table above for your own game.
- **Hanging.** RedM has no Euphoria grab or dangle messages for scripts, so the ragdoll hangs by its right hand
  only. RDR2 refuses whip_rope's "balance" ragdoll, so `RagdollTask = 'balance'` is a limp ragdoll there. On whip_rope, your
  own body hangs on your own screen, hidden from everyone else. On RedM that would need `SET_PLAYER_VISIBLE_LOCALLY`
  every frame, and in testing that left the player unseen for good, even after letting go. So on RedM a stand-in
  hangs on your screen too, as everyone else sees you, and your hidden character waits under it. A stand-in is made
  with `ClonePed`: RDR2's `ClonePedToTarget` leaves the copy with no clothes or body at all, so nobody saw it. RDR2
  sometimes won't ragdoll a fresh stand-in at the first ask, so it is asked again every 10 frames for up to a second;
  one that still won't stands under the rope in its idle pose instead, as in the `'animation'` style. The stand-in's
  `'animation'` style uses an animation RDR2 doesn't have, so in that style a stand-in keeps its idle pose.
  - If a ragdoll is ever pulled more than 6 m from the rope, it lets go and is put back under the rope. Ragdoll
    hanging is then off on that game until the player rejoins.
- **Walking with an end.** The holding walk style is off (`'none'`): spur_core has no walk override on RedM.

## Requirements

- `spur_core` (the RedM port of whip_core).

## Installation

Put `spur_rope` in your `resources` folder and add this line to `server.cfg`, after `ensure spur_core`:

```cfg
ensure spur_rope
```

## For players

| To | Do |
| --- | --- |
| Put a rope out | Use the **Rope** item. You hold one end. |
| Tie the end you hold | Look at a wagon, a prop or the map within reach, and press the prompt's key. |
| Pick up or untie an end | Use the prompt on the end. |
| Hang on | Use the prompt on the rope. **Jump** lets go. |
| Put the end down, let go, or coil the rope up | Open the wheel (**F1**). Coiling puts the rope back in your pockets. |

While you hold an end, you can walk or jog but not sprint.

## Configuration

- **`/spur` → Settings → Rope:** who may handle a rope, whether tying to a wagon needs its keys, tying to the map,
  reach, the rope's length and node count, ropes per player, what a rope bumps into, hanging and holding.
- **`config.lua`:** how the rope pulls, moves and looks. Each setting is explained there.

## Admin commands

These need developer mode on (`/w`).

| Command | Does |
| --- | --- |
| `/ropedebug` | Shows each rope's ends, stretch and pull, for you only |
| `/ropestatus` | Prints the ropes your game has, the look it draws them in, and your character's state, in the F8 console |
| `/ropevertices [length]` | Prints how many vertices RDR2 gives each rope type, in the F8 console |
| `/ropevis <way>` | Shows your character again by one native (`entity`, `playervisible`, `playerinvisible`, `localinvisible`) |
| `/ropeclonetest` | Puts four copies of you in front of you for 15 s, each made another way, and prints how RDR2 draws them |
| `/ropes` | Lists every rope out, in the server console |
| `/clearropes` | Takes every rope in. Each owner gets theirs back as an item. |

`/ropes` and `/clearropes` also run from the server console.

## For developers

Other resources make and control ropes through `exports.spur_rope`: `CreateRope`, `SetRopeEnd`, `SetRopeRules`,
`RemoveRope` and `GetRope` on the server, and `GetRopeEndEntity` on the client. Events such as
`spur_rope:ropeStretched` report what happens to them. A rope's own `look` (its own model) is drawn only by the
`'segments'` look, which RedM can't draw, so on RedM every rope looks like a rope.

## License

spur_rope is licensed under the GNU LGPL 3.0; see `COPYING.LESSER`, and `COPYING` for the GPL 3.0 it builds on.
`NOTICE.md` says what the licence doesn't cover and what this copy changed.
