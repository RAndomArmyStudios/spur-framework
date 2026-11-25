# spur_core: the RedM conversion

spur_core is [whip_core](https://github.com/WHIPFX/whip_core) 1.3.0 by Whippy, converted from FiveM (GTA V) to
RedM (Red Dead Redemption 2). Whippy allowed the port on one condition: **no one makes money from it.** It isn't WHIP
and doesn't come from WHIP's author. NOTICE.md says a fork can't be called WHIP, so it has its own name.

This file covers what the conversion changed, what doesn't work on RDR2, and what hasn't been tried in game yet.

**Status (23 Nov 2026): runs on RedM and has been played in game.** On a RedM FXServer (game build 1491) with
MariaDB 12.3 and oxmysql 2.14.3, spur_core makes its tables, starts with no warnings or script errors, and the setup
report has nothing to fix. In game, these have been tried and work: joining, the landing screen, the character
screen and creator, spawning, the HUD, the inventory (F2), the hotbar (Tab), the radial menu (F1), chat, a bank
counter (balance, withdraw and deposit), the Dev Tools (`/w`), the admin panel (`/spur`), `/charedit` and `/tp`. All
425 Lua files parse, and a check against the Cfx native reference (docs.fivem.net/natives) and RDR2's native list
finds no GTA-only native left uncovered.

## How the conversion works

whip_core calls about 500 GTA V natives. They aren't all rewritten in place. Two files load before the rest of the
resource and give every GTA-only name something to call on RDR2:

- `shared/rdr_compat.lua` **maps** a GTA native onto RDR2's, for example text drawing, blips, weather names,
  scenarios, doors, ped creation, proofs, sounds, weapons, tasks, particle effects, control numbers, health,
  outfits and vehicles' classes. It uses `def` where RedM lacks the name, and `force` where RedM has the same name
  with different arguments.
- `shared/rdr_compat_stubs.lua` makes every remaining GTA-only name a **stub**. A stub is a safe no-op that returns
  a harmless value. The first call to each stub prints one line:
  `[spur_core] RedM: <Name> has no RDR2 equivalent: skipped`. `/spurcompat` (F8) or `spurcompat` (server console)
  lists every stub hit so far. `setr spur_compat_log 0` silences the lines.

Every file that was edited by hand is marked `RedM (spur_core, 23 Nov 2026)` where it changed, as the LGPL asks.

## What changed

| Area | Change |
|---|---|
| Manifest | `game 'rdr3'` with the `rdr3_warning` line. The two compat files load first. GTA's streamed props and scaleform are gone. Name, author and description say what the resource is. |
| Characters | An RDR2 freemode ped (`mp_male`, `mp_female`) has no head or body until shop items for them are put on, and is invisible until it is dressed. The creator's head blend picks the **body**: the mother card the head, the father card the build (1-5) and the skin mix the skin tone (1-6). The eye colour picks the eyes, hair slot 2 and its colour (17 RDR2 colours) the hair, and the beard overlay (1) and its colour the beard. Clothing slot 11 ("Tops") picks one of the model's **outfit presets** (`mp_male` has 138; 0, 1 and 4 are underwear or trousers, 2 a hooded costume, 3 a shirt, trousers and belt), and a ped with none gets preset 0. A preset replaces every item when it lands, so the body goes back on after it. A ped made a moment ago (the character screen's, the inventory's) drops a preset asked for before it's ready to render, so the first preset on a ped is asked for again once it is. Face features, makeup, the other overlays, tattoos and props are stubs. |
| Health | GTA counts 100 (dead) to 200 (full); RDR2 counts 0 to a per-model maximum. The client and the server both read and write peds on GTA's scale, so whip's needs, stats and death logic work unchanged. |
| Death | GTA's `dead` animation dictionary doesn't exist. A downed player lies in the `WORLD_HUMAN_SLEEP_GROUND_ARM` scenario. Verified in game (24 Nov 2026): the scenario plays and holds, the death screen shows, and `whip_reviveme` stands the player up at full health. While the pose holds, RDR2 has the ped alive at 200 health and whip has it dead. whip's death checks read its own dead flag first, so that's expected. |
| Health on the server | RedM's server reads 0 for every ped's health and max health, living or dead. In game a shopkeeper read 0 of 0 on the server while its game read 200 of 200. So three things were broken: shop talk never spoke (`server/shop_talk.lua` wants a living customer), `server/npcs.lua` never saw an NPC hurt, and the Director's health reads were all 0. The fix: the game that owns a ped tells its health, on whip's scale, in the ped's state bag as `spurHp`, and `server/rdr_health.lua` reads that when RedM's own read is 0 (RedM's read wins whenever it gives anything). `client/rdr_health.lua` tells it for the player's own ped every 250 ms, at death and with the vitals report, and `client/npcs.lua` for the NPCs it runs. A player's game could already tell its own health through the vitals report, so nothing new is trusted. Once it's live, `server/npcs.lua`'s damage announcements fire. The server's `GetPedSourceOfDamage` probably still reads 0, though, so a group has no attacker to turn on (deployed 24 Nov 2026). Verified in game (24 Nov 2026, play3): Kill Me took the player down and the server marked the death (`whip_reviveme` answered "You have been revived", and it refuses a player the server hasn't marked dead), the revive stood the player up at 200 of 200, and the server read the Director's Courier boss at 200 of 200 (`/npcdebug`'s numbers come from the server's `GetEntityHealth`), with `spurHp` 200 told by the game running it. Shop talk verified in game (24 Nov 2026): a shop made with the shop wizard at Valentine's general store counter (keeper `u_m_m_valgenstoreowner_01`, no G or Enter needed at any step) answered on its screen at each step: opening, adding to the basket, paying and closing without buying, the customer's line then the keeper's. The bubbles over their heads don't show (Known gaps: World-space pages). Wagons the same way (24 Nov 2026, deployed): the game running one of spur_core's vehicles puts its health, max health, engine and body in the `spurVeh` state bag every second when they change, and the server's `GetEntityHealth`, `GetEntityMaxHealth`, `GetVehicleEngineHealth` and `GetVehicleBodyHealth` read it when RedM's own read is 0. A wagon has no engine: an engine reading of 0 on a wagon that isn't wrecked isn't told, and the server takes the body's. |
| Health cores | RDR2 caps a player's health by its health core. A new ped's core is 50, which stops health at two thirds, so whip's "full" (spawn, a revive, Restore Player Cores) read 67% and the HUD never filled. `client/ped_hold.lua` holds RDR2's health and stamina cores at 100 and checks them every 30 s. whip keeps its own health, food and drink. Verified in game: at core 50, setting health to 150 stopped at 100; at core 100 it reached 150 (24 Nov 2026). |
| World data (config.lua) | Spawn, respawn points, spawn picker, character-select shots, landing camera and character creator all moved to Valentine, Saint Denis, Blackwater, Rhodes and Armadillo. Weather uses RDR2's names. GTA's arrival "switch" scenes are off. The Legion Square garage seed is gone. Every coordinate walked in game (24 Nov 2026): each is on the ground or a floor, none under the map or in a wall. The shared spawn point is inside Valentine's doctor's office and the first character-select shot is its waiting room; the Saint Denis and Rhodes spawn points are on station platforms, Blackwater's on the boardwalk and Armadillo's at the edge of town; the four bank counters are indoors, facing their counters; the landing camera is 45 m up over Valentine. `Config.Creator.spawn`'s comment says Valentine's main street, which it isn't (the coordinate is fine). |
| Items | Every item prop is an RDR2 model (`p_cs_sandwich01x`, `p_canteen01x`, `p_moneystack01x` and so on). The food, drink, ID, bag, armour and tonic names and descriptions fit 1899. |
| Banking | RDR2 has no cash machines. `client/rdr_bank_counters.lua` (new) puts a hidden marker prop at each bank's teller window (`Config.BankCounters`), so whip's ATM prompt appears there. `server/atm_positions.lua` is empty. All four windows (Valentine, Blackwater, Saint Denis, Rhodes) were walked in game. Their points are on the counter in front of the customer, and the badge and the bank prompt work at each one (24 Nov 2026). Checked again at Valentine after the flags4 deploy (play3): the bank glyph and Check Balance show at 0.9 m from the point. spur_phone's `BankSpots` Valentine point moved to match. |
| GTA stores | `server/gta_stores.lua` is empty: its 14 24/7s and LTDs were on GTA's map. |
| Prompts | `Config.InteractRenderer = 'nui'`. The 3D world renderer draws with `DrawTexturedPoly`, which RDR2 doesn't have. The NUI badges show each prompt's glyph. Typing a value into a prompt (an amount at a bank counter) shows its capsule on screen, low in the middle, and always uses the keyboard. |
| Runtime textures | `CreateRuntimeTxd` and `CreateRuntimeTextureFromDuiHandle` are FiveM-only and are stubbed, so DUI pages can't become in-world textures. `client/dui_page.lua` makes no DUI browser at all on RedM: with one up, typing into a prompt crashed RedM (`glue.dll`) twice in testing. |
| Loading screen | WHIP's loading screen is ported too, as **spur_loadingscreen** (`ensure spur_loadingscreen`). WHIP's logo and its blueprint (pictures of GTA's world) aren't in it: the SPUR wordmark sits on an 1899 backdrop drawn in CSS, with the same loading light. The setup report's second-loading-screen check names it. |
| Chat | WHIP's chat is ported too, as **spur_chat** (its own resource, `ensure spur_chat` after spur_core). FXServer's own `chat` still works in its place: spur_core gives it a theme (`chat_theme` in fxmanifest.lua) that moves it right of the Dev Tools column. |
| Setup report | Doesn't ask for a GTA game build. It also flags VORP, RSG, RedEM:RP and QBR cores and the VORP and RSG inventories as clashing frameworks. It doesn't ask for WHIP's media packs or whip_voice. |
| Media packs | WHIP's `whip_media_*` packs are pictures of GTA's clothing, props, cars, peds and tattoos, emote videos and GTA's map. The pack index (`shared/assets_index.lua`, `html/js/assets-index.js`) is empty, so nothing looks for them and every picture lookup answers "none". |
| Clothing pictures | `data/clothing-pictures.json` (GTA's clothing) is gone. It would have hidden RDR2 outfit presets by whether GTA's item of the same number had a picture. Without it the editor hides nothing. |
| Ped flags | whip sets GTA's ped config and reset flags by number, and RDR2 numbers them its own way: GTA's config 48 (BlockWeaponSwitching) was RDR2's ShouldFixIfNoCollision, and the reset flag whip sets every frame to keep action mode off (GTA's 200) was RDR2's EnableEagleEyeInVehicle. `shared/rdr_compat.lua` maps each GTA number whip uses to RDR2's (femga's rdr3_discoveries lists, 24 Nov 2026), so `SetPedConfigFlag`, `GetPedConfigFlag`, `SetPedResetFlag` and `GetPedResetFlag` take whip's numbers. GTA's DoesntDropWeaponsWhenDead (14) becomes `SET_PED_DROPS_WEAPONS_WHEN_DEAD`. Flags RDR2 lacks (the bike helmet, IsInjured, HasHurtStarted, DisableHurt, no ragdoll from melee, no shuffle for an injured driver, no fall off a vehicle) aren't passed on; a read gives back what was set. Nor is BlockWeaponSwitching (48): whip keeps it on whenever the player isn't in a turret seat, RDR2's own (249) on all that time could stop spur_gunny's equips, and whip's control blocks hold the weapon wheel off anyway. A resource that wants RDR2's own numbers calls `RdrCompat.rawPedConfigFlag` / `RdrCompat.rawPedResetFlag`. Combat attributes need no map: RDR2 numbers them as GTA does, apart from 13 (GTA's aggressive, RDR2's cover search). Verified in game (24 Nov 2026): riding as a passenger, in seat 0 of wagon #54, the player stayed seated for 15 s, not shuffled to the driver's seat, with RDR2's flag 65 on (GTA's 184, PreventAutoShuffleToDriversSeat). |
| Giving and throwing items | Give mode (an item's Give) equipped GTA's tennis ball (WEAPON_BALL) and threw the item when the ball left the hand. RDR2 has no ball, so nothing could be thrown. Now give mode puts away whatever is in hand, holds off punching, aiming and the grapple, and the attack button (LMB / RT) throws the item; the hint says so (24 Nov 2026). Handing it to a player in reach with E is unchanged. |
| Ped bones | whip finds a ped's bones by GTA's bone tags (the head 31086, the right hand's prop holder 28422, the left hand 18905), and RDR2 numbers its bones its own way, so held props, the camera item's eye, prompt and bubble heights and /charedit's framing asked for bones RDR2 doesn't have. `shared/rdr_compat.lua` maps the 26 GTA tags whip uses (pelvis, spine, neck, head, arms, hands, legs and feet) to RDR2's in `GetPedBoneIndex` and `GetPedBoneCoords` (femga's rdr3_discoveries bone list, 24 Nov 2026). RDR2's tags are hashes of the bone names, so one number serves the male and the female model. `RdrCompat.boneTag(tag)` gives the mapped tag. Give mode's hold is RDR2's now (Items in the hand, below), with RDR2's hand axes; other held props' offsets (emotes' and progress bars') were set for GTA's hand, so one may sit off in an RDR2 hand. Verified in game (24 Nov 2026): `RdrCompat.boneTag(31086)` gives 21030 and the head reads 1.62 m above the ground; the camera item's prop sits in the right hand; an NPC's Talk prompt shows at the upper body and its line-of-sight check works. |
| Items in the hand | Give mode holds the item out in the hand (`server/events_inventory.lua` giveProp). GTA's hold (0.05, 0, 0 from the hand's bone, no turn) sits an item in the middle of the hand's thickness, and in RDR2's hand a flat item (the sandwich, and the package that stands in for every item without a prop) came through the back of the hand. RDR2's `SKEL_R_Hand` has x along the fingers, y to the thumb and z out of the back of the hand; its `SKEL_L_Hand` has x along the fingers, y into the palm and z backwards (each measured by moving a prop 10 cm along one axis). The defaults are now (0.06, 0, -0.035) for the right hand, and (0.06, 0.035, 0) turned -90° about x for the left (`GIVE_OFFSET`, and new `GIVE_OFFSET_L` and `GIVE_ROT_L`), and the hand editor (`tools/hand_edit.lua`) starts from the same. Tried first through a client bar's prop (play9): all 13 item props other than the camera are in RDR2 and went in the hand in 0.6 to 1.3 s, and at these values the sandwich and the package sit in the palm. Deployed 24 Nov 2026 and verified live through `spur_core:server:giveHold` (play10): the bandage and the package each landed on the new default in both hands (0.0 cm and 0° from a local prop tied there, 3.6 cm from where GTA's would be), the package flat in the left palm and the bandage gripped in the right. The bandage's cloth is bigger than the hand and drapes round it. Big and long items want holds of their own (Known gaps: Big and long items in the hand). |
| Camera item | The camera gave up when GTA's paparazzi clips wouldn't load, so using it did nothing. It now comes up without them, and the prop in the hand is RDR2's box camera (`p_camera01x`) in place of GTA's `prop_pap_camera_01`. Through the lens the player's own ped is hidden on their screen only: GTA's `SET_ENTITY_LOCALLY_INVISIBLE` is mapped, for player peds, to RDR2's `SET_LOCAL_PLAYER_INVISIBLE_LOCALLY` and `SET_PLAYER_INVISIBLE_LOCALLY` (`shared/rdr_compat.lua`); other entities stay seen. GTA's first-person view under it is a stub, so the ped turns with the lens and walks where it looks (24 Nov 2026). Verified in game: it comes up with the prop in the hand, the lens sits at eye height with the viewfinder, and putting it away takes the prop off. |
| World effects | The Director's live smoke, sparks, flames and steam (`client/live_world.lua`) were GTA's particle effects, which RDR2 doesn't have. They're RDR2's nearest from its `core` set now: `ent_amb_smoke_chimney`, `ent_amb_robot_sparks`, `ent_amb_campfire_sma` and `ent_amb_steam_vent_round` (femga's rdr3_discoveries ptfx_assets_looped.lua, 24 Nov 2026). The Director's preview of Blow Up used GTA's car explosion number (7), RDR2's petrol pump; it's RDR2's car explosion (5) now. New storage containers placed from the wizard got GTA's cardboard box; they get `Config.ContainerDefaultProp` (`p_package01x`). Verified in game (24 Nov 2026): smoke, flames and steam show at their scale; Blow Up wrecks a wagon; the container wizard places a `p_package01x`, which opens and deletes. Sparks show nothing (Known gaps). |
| Death causes | The stats page names a death's cause from txAdmin's list of GTA's weapons, then the weapon catalog (spur_gunny's guns), then shows the hash. RDR2's animal attacks (bear, cougar, wolf, alligator, snake and the rest) and being rammed by a wagon are named too now (`client/stats.lua`, femga's rdr3_discoveries weapons.lua, 24 Nov 2026). The causes RDR2 shares with GTA (fall, drowning, fire, explosion, bleeding, run over) were named already. |
| Director examples | The three example scenarios (Courier, Steal the Car, The Vault) had GTA's peds, guns and car. A GTA gun gives an NPC nothing on RDR2, so the guards stood there unarmed, and GTA's `sultan` fails the vehicle model check, so Steal the Car stopped at "The job could not be set up". They use RDR2's now: Valentine townsfolk and criminals, Duster gang guards with a Cattleman revolver, a sawed-off and a carbine repeater, Valentine's bank guards, a livery worker as the buyer and a `coach2` coach. The Dungeon Master places everything (`"spot"`), so no positions changed. The NPC tests' dealer had lost its stand-still behaviour to a misplaced comment, and has it back. The guards' guns are given with `bIgnoreUnlocks`. If a ped doesn't appear, pick another in the World tab. Verified in game (24 Nov 2026), Steal the Car from start to end: the fixer's line and the team page, the coach with its 4 horses, three armed guards fighting with their card's gun only (NPCs' own guns), the key dropped where the guard died and picked up, the key in the coach's ignition, the drop-off reached and the buyer's line answered, and the run closed with the buyer, the coach and its horses gone. Run 1076 paid $1500 cash (the admin activity log: `gained` 1500 cash, `director:steal_car@1 run 1076`). It isn't in the Director's run history, which lists stored scenarios' runs (`/director load` runs an example file, "No scenario called steal_car"). Not verified: driving the whole route (steering held by script doesn't turn a coach, so it was moved near the drop-off) and the coach staying locked (Known gaps: locks). Courier from start to end (play9): the boss's Talk, both lines and the team page, the package put down at its spot with "Find the package", picked up ("Take the package back to the courier boss"), "Got it?" answered, the package taken from the pockets, $250 cash paid, the objective cleared and the run closed (the boss's Talk back to the one that starts a run). Courier has no armed NPC. The Vault is still to run (Not yet tried: The Vault). |
| Take Cover | The Director's Take Cover step (`STEP.cover`, `client/npcs.lua`) seeks a cover point and then turns the NPC to the side asked for. RDR2's `TaskSeekCoverToCoverPoint` with the step's arguments works (in cover in 5.1 s, 1.0 m from the point), but three things didn't. RDR2's `IsPedInCoverFacingLeft` answers 1 or false, so the step's `~= faceLeft` put a ped already facing left into cover again: it reads 1 or `true` as left now (cover7). `ClearPedTasks` doesn't reliably take a ped out of cover (`IsPedInCover` reads false in the same frame, yet the ped comes back facing the way it was), so a ped in cover on the wrong side gets `ClearPedTasksImmediately` before it is put into cover with the way in played; a ped not in cover keeps the soft clear (cover8). And the step's cover point was open to both sides (`AddCoverPoint` usage 2), so the NPC's own cover AI picked its side after the forced first facing: right after left held 1 time in 4, the NPC turning to face left about 0.7 s after the step was done. The point's usage follows the side now, 1 (a wall to the right) for left and 0 (a wall to the left) for right (cover9). With usage 0, a forced left went back to right in 0.3 s. Deployed 24 Nov 2026 and verified live through the step's own code (`NpcSteps.run`, as the Director's preview runs it) on an armed NPC on Valentine's main street (play10): right, left, right, left, right, left, right, 7 of 7 in cover on the side asked for, each held 4.5 s after the step was done, 0.03 to 0.09 m from the point, the NPC keeping its revolver. Done in 3.6 s from standing, 2.3 to 2.4 s turning to the left and 1.5 to 1.6 s turning to the right. The node editor with a scenario that uses it is still to try with the mouse (Not yet tried). |
| Vehicles with no model | `Vehicles.create` fell back to GTA's `adder` when no model was given, which RDR2 doesn't have, so the vehicle was refused. It falls back to `wagon02x` now. Verified in game: the Vehicle Manager with no model made a wagon02x (24 Nov 2026). |
| Scenario packs | A scenario exported as a pack (*Export as a pack* in /spur's Director tab) came with a `game 'gta5'` manifest, which RedM won't start. The manifest says `game 'rdr3'` with the `rdr3_warning` line now. |
| The admin panel's name | Help text, notices and the Director's tutorial told admins to open `/whip`. spur_core has no `/whip`: its admin panel is `/spur`, and they say so now. Code names (`whip-panel.js`, `WhipPanel`), the `whip_interact_*` key mappings (renaming them would reset every player's binding) and the `whip_director_scenario` manifest key stay as they are. |
| Weapon guard | `client/weapon_guard.lua` takes away a weapon nothing handed out (one looted off a body, say). It listed GTA's weapons only, so on RDR2 it never took anything. It guards RDR2's 55 now (`shared/rdr_weapons.lua`: spur_gunny's guns, bows, throwables, knives and the lasso), and reads `HasPedGotWeapon` as a number too, since RedM answers some yes-or-no natives that way. spur_gunny permits each gun before it gives it (`PermitNativeWeapon`) and has a guard of its own. Another resource that hands a player an RDR2 weapon must permit it, or name it in `Config.WeaponGuard.Allow` (its `GADGET_PARACHUTE` is GTA's and does nothing). The pickup layer is skipped: RDR2 has no `GetPickupHashFromWeapon`, and a gun taken off a body is swept instead. The ped doesn't drop its gun on death (GTA's flag 14, mapped to `SET_PED_DROPS_WEAPONS_WHEN_DEAD`). Verified in game (24 Nov 2026): a spur_gunny Cattleman drawn from its item stayed, and one sweep took only an unpermitted Carbine Repeater, with the F8 line. Fired once (aim and attack held by script): the clip went 5 to 4, gunny's probe read clip 4 and pool 4, the gun was still in hand after the sweep, and F8 had no `took` line. Checked again after the flags4 deploy (24 Nov 2026, play3): a gun given by script, with nothing handing it out, was taken in 0.06 s by spur_gunny's guard, and a gunny Cattleman drawn from its item stayed through a forced spur_core sweep with no `took` line. |
| Pause menu | RDR2 has no `ActivateFrontendMenu`. Its pause menu (Map, Settings with Controls, Quit Game) and its map are uiapps, opened with `LAUNCH_UIAPP_BY_HASH` (`pause_menu` and `map`, verified in game). whip's pause menu holds Esc and P, so these were a player's only way to RDR2's own settings. Its Map, Settings and Key Bindings now open them (`client/pause.lua`, `html/js/pause.js`). While one is up, the HUD steps aside and Esc belongs to RDR2 (deployed 24 Nov 2026). Verified in game (24 Nov 2026, play3): Esc opens whip's menu; its Map opens RDR2's map with whip's HUD gone, and Back returns to the game with the HUD back; its Game Settings opens RDR2's pause menu, with Settings in its list. |
| The map | (25 Nov 2026) whip's map pages need a data file of the world, and whip ships GTA's. RDR2's is made from the game: `dev/map_survey.lua` (run in game) asks the game for the ground height on a 20 m grid, the water and the road nodes over the whole map; `dev/map_survey_read.py` reads its log; `dev/map3d_rdr.py` writes `map/rdr-map3d.js` in whip's format (551 x 456 points, water and three road widths). The game answers nothing along its own section seams (x and y = 0, -5120 ...), which left 40 m holes; the builder closes gaps up to two points wide and small pockets. The renderer (`html/js/map3d/map3d.js`) takes two optional settings from the file: `topShade` (slope shading seen from above) and `landRgb`, since RDR2's file has no buildings and the land is the picture. The map is kept flat: `map.turnable = false` (pause.js), the minimap's tilts are 0 (minimap.js) and the spawn picker's view is straight down (spawnselect.js). `Config.Map3D = false` switches to RDR2's own radar and map with the fog lifted (`client/hud.lua`). Verified in game: the minimap, the pause map (pan, zoom, centre), the spawn picker, no cost in frame rate. |
| RDR2's own interactions | (25 Nov 2026) NEW `client/rdr_interactions.lua`, with `Config.RdrInteractions`. RDR2's right-click lock-on (Greet, Antagonize, Rob) is off by disabling its control (0xF8982F00) every frame; gun aiming stays (SET_PLAYER_LOCKON(false) would take it too). RDR2's own picking up and looting are off at their source, not by hiding every prompt: `_UI_PROMPT_DISABLE_PROMPTS_THIS_FRAME` was tried first and also stopped a player getting on a horse. Now: `_SET_PLAYER_CAN_PICKUP_ABILITY` and `_SET_PLAYER_CAN_PICKUP_HAT` false, the player ped's looting flags 2 and 3 (CanLongLootTargets, CanQuickLootTargets) off and 18 on (set again every second), and prompt type 5 (Pick Up on a carcass) hidden every frame. Prompt types above 40 crash the game. whip's prompts are NUI and its E a key mapping, so they stay (checked at the Valentine bank counter). The same file turns off RDR2's idle cinematic camera (`_DISABLE_CINEMATIC_MODE_THIS_FRAME`), which FiveM's `DisableIdleCamera` (a stub here) did for GTA. Tried in game before the deploy, on ambient peds, with these exact lines run by script: a dropped hat, a dead townsman (Loot and Pick up) and a pig carcass showed no prompt, and the carcass press did nothing; an ambient horse was mounted, a stagecoach boarded (2 of 2) and a shop door opened; aiming, RDR2's weapon wheel and whip's E at the bank all worked. Under the all-prompts switch the mount failed 0 of 5 and the wagon 0 of 2. The pickup ability alone hides every Pick up seen (the hat line and type 5 back it up); flag 18, or flags 2 and 3, alone remove Loot. Known gaps: no prompt type hides Search Saddle Bag on someone else's horse; looting a dead player or a script-made ped was not tried. |
| The weapon wheel | (25 Nov 2026) whip switches GTA's weapon wheel off and shows its own hotbar on Tab. RedM cannot block RDR2's wheel, so both came up together. Now Tab is RDR2's wheel alone (`Config.RdrWeaponWheel`; the hotbar still shows on the keys 1-5), and spur_gunny puts the pockets' guns on it (its `Config.Wheel`, client/wheel.lua): each is carried holstered and empty, and picking one draws it through the server exactly as Equip does; picking the fists puts it away. Rounds stay with their items. Throwables and whip's other items are not on the wheel. RDR2 shows two long guns (shoulder and back), so only the two in the lowest pocket slots are carried; the rest stay items. A gun put away always writes its true loaded count back to its item (the pocket copy could keep a stale one). Item pictures: whip_gunny's are GTA's guns, so spur_gunny shipped none and every gun showed the "no picture" glyph; it now has one drawn picture per class of item (html/img/items/class/*.svg, chosen in server/items.lua from the weapon's game name or the cartridge group; a gunsmith part's from its kind: scope, barrel, rifling). |
| RDR2's world on whip's prompts | (25 Nov 2026) NEW `client/rdr_world.lua` and `server/rdr_world.lua`, with `Config.RdrWorld`. What `client/rdr_interactions.lua` switches off comes back as whip prompts on E (client/actions.lua), for the game's own people and animals only (never a player, never a ped a script made). **A townsperson:** Greet and Antagonize. The player's ped (the multiplayer model) has no voice, so the player makes one of RDR2's emotes (TASK_PLAY_EMOTE_WITH_HASH) and the townsperson answers in their own voice (PLAY_PED_AMBIENT_SPEECH_NATIVE with RDR2's struct; DOES_CONTEXT_EXIST_FOR_THIS_PED picks a line the voice has). **A body:** Search, held, from 2.3 m: the player turns to it and RDR2's TASK_LOOT_ENTITY plays (it plays where the player stands, so the reach is short); the player's looting flags are given back for that task only. RDR2's own loot is nothing to whip, so the server decides what is found from `Config.RdrWorld.Loot` (cash and items through Inventory.give), once per body by network id, within 6 m, one search every 2 s. **A body or a carcass:** Pick up, RDR2's TASK_PICKUP_CARRIABLE_ENTITY. That task needs RDR2's own pick-up on from its first frame until the drop, so `RdrWorld.carrying()` reports the pick-up and the carry and `rdr_interactions.lua` gives the switches back for as long. RDR2 drew its own Drop once in three sessions and never a Stow, so those are whip prompts too: Put down, looking at the ground (TASK_PLACE_CARRIED_ENTITY_AT_COORD, and after 5 s the pick-up is switched off for a moment, which drops it at once), and Put on horse, standing in front of a riderless, networked one (whip's look ray does not meet a horse; TASK_PLACE_CARRIED_ENTITY_ON_MOUNT). **The player's hat:** Put on, where it fell (`_GET_PED_LAST_DROPPED_HAT`). `_TASK_EQUIP_HAT` and RDR2's own hat pick-up both did nothing in game, so the hat's shop item is read while it is worn and put back on as clothing (`_APPLY_SHOP_ITEM_TO_PED`), and the prop removed. For the prompt on a carried body, look prompts are now scored from the camera, not the player's feet (`client/interact.lua`, `client/actions.lua`: `reg.aimed`, InteractComputeScore's 15th argument `aimThing`), and one whose thing stands more than 0.6 m behind the player along the camera's way is left out (someone at the player's back, between camera and player). Checked in game over six builds. Robbing is left out: a held-up townsman shot the player in the trial. Speech and scenario names from the rdr2mods wiki's lists; looting flags from femga and Halen84. |
| Doors, near prompts and the engine (core7) | (25 Nov 2026) From a regression pass in game. **Doors:** `GetClosestObjectOfType` answers 0 for RDR2's own doors, so a door's prompt sat on the floor at its hinge; `doorEntity` (client/doors.lua) now also asks RDR2's door system by the door's hash (`_GET_ENTITY_BY_DOORHASH`) and then the objects around by model. **Near prompts:** a walk-up prompt under a metre away read as behind the camera when RDR2's camera looked down at it and lost focus; that near it must be well behind to be cut (`InteractComputeScore`, client/interact.lua). **Engine:** RDR2 has no engine-running native and the stub's flat false made the radial's Engine only ever turn on; `GetIsVehicleEngineRunning` now answers what this game last set through `SetVehicleEngineOn` (shared/rdr_compat_stubs.lua). The HUD's reversing check no longer reads the stubbed gear. |
| Using items | (25 Nov 2026) Players said items froze them. Nothing was frozen: the inventory stays open after Use and takes every key, and armour's 5 s bar held the player still with no animation. Use on a consumable, medicine or equipment now closes the inventory (`Config.InventoryCloseOnUse`, server/events_inventory.lua), and the armour bar lets the player walk (`disable = { move = false }`). |
| `/charedit` indoors | GTA's camera offsets put the opening shot behind a wall or a counter indoors: at Valentine's bank window it showed the counter and not the character. The camera is now kept in front of walls. The view from it is probed at four heights on the character, and when one is blocked the character turns to the first heading that clears it (`client/appearance.lua`, TurnToRoom). Deployed first with the smallest 30° step first. In game at Valentine's bank window that turned the character +30°, which no probe found blocked, but the camera then sat behind the teller glass and the shot showed the character through it, lettering reversed. No shape-test flag hits that glass (1, 16, 17, 32, 64, 81, 128, 256, 511 and -1 tried), and the camera's interior is the same as the character's. So the turns now go from 180° down (180, ±150, ±120, ±90, ±60, ±30): what blocks the face-on shot is in front, so the room is behind. Verified in game: at the bank window 180° clears all four rays and frames the character in the lobby (24 Nov 2026). Deployed, and verified live after the restart: at the bank window the character turned from 198.69° to 18.69°, back to the counter, and the shot was the character in the lobby. At Valentine's general store, facing the counter, it still failed (24 Nov 2026): the probes went from the unslid camera, which cleared all four, so the character kept facing the counter, but the page slides the camera sideways (creatorStage, ComputeCamPose), so the torso shot sat across the counter and the Legs tab's camera was pulled in to 0.45 m (CAM_MIN_ROOM): the screen was trousers. TurnToRoom now probes from where the torso and legs cameras really are, slid as the page asks (taken as half the screen until the page first says). Tried by a test chunk before writing it: at the store face-on blocked 4 probes and 180° 8 (shelves), 150° none, and both shots showed the character in the store; at the bank window it still turns 180° and both shots are the lobby. Deployed (fixes7) and verified live (24 Nov 2026): at the general store counter the character turned from 270° to 60° (150°), and the opening shot and the Legs tab both showed the character in the store, the camera 2.17 and 2.18 m off; at the bank window it turned from 198.69° to 18.69° with the lobby behind, the bank's lettering the right way round, the Legs tab at 2.18 m. |
| Shop and garage icons | The shop and garage wizards' icon pickers listed GTA's blips with GTA's pictures, and those pictures (`html/img/blips`) don't ship, so every tile showed a broken image. Most of the numbers have no RDR2 icon anyway. The pickers now list only the numbers `shared/rdr_compat.lua` turns into an RDR2 icon, as named tiles. Shops: General store, Tailor, Barber, Gunsmith, Saloon, Doctor, Bank and Point. Garages: Wagon (357), Coach (225), Home (40) and Point (1). The shop wizard rounds an item's weight: a bandage read "0.19999999999998 kg" (24 Nov 2026). |
| Furniture catalog | The GTA world seed file is gone: about 15,000 GTA V props that RDR2 doesn't have, all sent to every player at login. Migration `048_redm_gta_prop_seed` removes them from a database that was seeded with them. The seed (`server/prop_catalog_seed.lua`) is RDR2's now (props1, 24 Nov 2026): 13,294 props in 35 categories, made by `dev/prop_catalog_rdr.py` from femga's rdr3_discoveries object list, less the 429 the game won't spawn (`dev/prop_catalog_rdr_nospawn.txt`). A seed row's category and name are set when it is first inserted and never changed after: rerunning the script adds only models not in the table yet, so fixing a row already seeded needs a migration. Add more with `Config.PropSeeds` or `/prop add <category>`. |
| NPCs' own guns | RDR2 gives gang and lawman models guns of their own when they're made (a `g_m_m_uniduster_01` came with a Winchester, a double-action revolver and a knife), and in a fight a ped draws the best it has: Steal the Car's guards were given a Cattleman and a sawed-off and drew a Henry and a Winchester. GTA's script-made peds carry nothing. Now an NPC's own guns are taken once, before anything is given (`client/npcs.lua` applyBrain, `RemoveAllPedWeapons`), and the `spurBare` state bag tells every game that takes it over that it's done. Tried in game on a test ped: the three went, and the Cattleman given after stayed. Deployed 24 Nov 2026 (fixes5). Verified in game after the deploy: Steal the Car's three guards came with their card's gun and nothing else (checked against 31 RDR2 guns), and in 22 s of fighting each drew and fired only that one. |
| Wagons and the key | A wagon's horses go on RDR2's draft controls (W, Shift for the whip, S), not on GTA's accelerate (71), so whip's no-key rule didn't stop one. While the ignition is off, the draft controls are held too (`client/vehicles.lua` HoldThrottle), and S only while it's all but stopped (S backs a stopped wagon: 4.9 m in 4 s). So a wagon moves only with its key in and the ignition on, as a car does: Vehicle: Engine On (the mouse wheel up, RedM's own key mapping) or the pad's engine action. Tried in game, W and forward held by script for 5 s: 0 m with the hold, 5.4 m without. Deployed 24 Nov 2026 (fixes5). Verified in game after the deploy (wagon #54, key in its ignition): with the ignition off, the draft controls were held; Vehicle: Engine On let them go (the server's stat block read engine 1). Done again with no cap write during the off and on test: Engine Off, W held by script moved it 0 m in 4 s; Engine On, W walked it 5.4 m in 5 s. play3's wagons, never given a cap, walked on W too (7 m in 6 s), so W doesn't need fixes6's write. (The zeros on W at (413, 423) after a revive came from the player still slumped in the seat, and two at Valentine are unexplained: see Known gaps, Wagons and coaches in game.) Found then: the whip (Shift) puts the horses into a gait they keep on their own, following the road, so turning the ignition off didn't stop a moving wagon. It ran on at 10 m/s with no control pressed (50 m in 5 s), and a script-held S didn't slow it. RDR2's draft speed is a cap, 50 when left alone: held at 0 (`_SET_DRAFT_VEHICLE_DESIRED_SPEED`) it stopped the wagon from 10.8 m/s in about 1 s, and W can't move it; given back 50, W walked it again (9 m in 5 s). So the hold also caps a wagon at 0 and gives the cap it found back on letting go, or 50 if it found 0. Deployed 24 Nov 2026 (fixes6). Verified after the deploy (wagon #54): on getting on with the ignition off, the cap read 0 and the controls were held; Engine On gave back 50, and the whip took it to 10.6 m/s; Engine Off stopped it in 0.93 s (5.5 m rolled); with the ignition off, W and the whip moved it 0 m in 4 s; Engine On again gave back 50 and W walked it 5.5 m in 5 s. |
| Locked wagons | RDR2's door lock shuts doors, and a wagon has none, nor has a coach's driver's bench. At lock 2 `TaskEnterVehicle` put the player on a wagon's bench at once (22 ms, no walk up), and RDR2's TCF_NotConsideredForEntryByLocalPlayer, its transport usage flags, and SET_VEHICLE_DOORS_LOCKED_FOR_ALL_PLAYERS with SET_DONT_ALLOW_PLAYER_TO_ENTER_VEHICLE_IF_LOCKED_FOR_PLAYER didn't stop it. So a player found on one of spur's draft vehicles that is locked, without its key, is put back down beside it, after a second look 1.5 s later (a claimed car is sat in by the server before its key comes). A script putting the player in a seat (`SetPedIntoVehicle`, `TaskWarpPedIntoVehicle`) is noted in the player's own state bag (`spurSeatedAt`, `shared/rdr_compat.lua`) and isn't put down. Getting off a locked draft vehicle doesn't unlock it any more (`server/events_vehicles.lua` unlockOnExit: no door to open from inside). Tried in game, the client side copied into a test chunk: no key, put down 1.5 s after getting on; seated by script, left there; with the key, left there. Deployed 24 Nov 2026 (fixes5). Verified in game after the deploy, wagon #54 locked with its key in its ignition (not the player's): `TaskEnterVehicle` put the player on at 0.05 s, the guard put them back down at 3.6 s, and it stayed locked; getting off it locked left it locked (lock 2, 3 s after). |
| Doors | RDR2's door system takes only the game's own hash for each door (`_ADD_DOOR_TO_SYSTEM_NEW`), and nothing in the game turns a door into its hash. whip made a door's hash from its position, which on RDR2 registered a door tied to nothing: it took a lock state and the door stayed free. `client/doors.lua` (makeDoorHash) now looks the hash up in `client/rdr_door_hashes.lua` (new): RDR2's 1751 door hashes for 307 door models, from femga's rdr3_discoveries door list (`doorHashes/doorhashes.lua`, data only; credit femga), made by `dev/door_hashes_rdr.py`. A door takes the hash of the nearest listed door of its model within 1.5 m. A door with none keeps the made hash, and F8 says once that its locks won't hold it. Deployed 25 Nov 2026 (doors1). Verified in game (play11): a whip door made from Valentine bank's left front door (`p_door_val_bank00_lx`) came as door #66 and registered under the game's hash 2642457609; locked, the player walked into it from outside and from inside and was stopped, the leaf not moving; unlocked, it swung 89.9° and the player walked through; deleted, it left the door system. A test door 3 m from any listed spot printed its F8 line once. |

## Server-made entities

whip_core makes props, vehicles and NPCs on the server. RedM's server natives work differently (probed on the
server, 23 Nov 2026), so `server/rdr_entities.lua` (new, `RdrEntity`) sits between them:

- `CreateVehicleServerSetter` answers 0. RedM has no server-side setter.
- `CreateObject`, `CreateObjectNoOffset` and `CreateVehicle` hand the job to the nearest player's game. The handle
  names nothing for the first 100 to 500 ms, and every native on it fails ("Tried to access invalid entity"). The
  entity then belongs to that player and sits in that player's routing bucket, so spur_core sets the bucket again
  once it's there. Objects and vehicles are made as before, then waited for (`RdrEntity.await`, `whenReady`).
  Held props (`server/held_props.lua`) and the Director's physical props (`nodes_props.lua`) don't wait. They're
  handed over when they arrive, and deleted if they turn up after they were let go.
- **Vehicles are made by a player's game** (since 24 Nov 2026). A wagon the server's `CreateVehicle` makes has no
  harness to fill: RDR2 counts 0 draft animals expected, and every horse put to it is refused (seen in game with
  Steal the Car's coach and a Vehicle Manager wagon). So `RdrEntity.vehicle` asks the nearest player's game to make
  the vehicle with RDR2's own `CreateVehicle` (`client/rdr_entities.lua`), which puts the wagon's animals in, and
  takes it once the server sees it: the right model, that player's, within 10 m of the spot. Nobody answering in
  6 s, the server's `CreateVehicle` is used as before, and that wagon comes without horses (F8 and the server log
  say so). A vehicle made after the server gave up is deleted. Seen in game (24 Nov 2026): a wagon02x made by a
  player's game this way had both horses in the harness at once, and the player stayed seated. RDR2 itself puts a
  player out of a wagon with an empty harness, after 2 s as a passenger and about 5 s as the driver, so a wagon
  without horses can't be ridden either. Verified through spur_core after the deploy (24 Nov 2026): a Vehicle
  Manager wagon with no model came with its horses and drove, F8 said `made a wagon for the server`, and its horses
  went with it when it was stored; the wagons remade at the join (play5) came with both horses each. Checked on
  paper (24 Nov 2026): every `CreateVehicle` call passes seven arguments, so RDR2 still puts horses on a wagon (its
  eighth means "no draft animals"), and `TaskEnterVehicle`'s seventh is 0.
- `CreatePed` makes nothing, for people or animals. A player's game near the spot makes the ped
  (`client/rdr_entities.lua`) and reports its network id. The server checks the model and position before it
  takes the ped. `Npcs.spawn` waits up to 8 s when it can wait (`opts.wait = false` doesn't wait). An NPC asked
  for with nobody near stays pending, without a network id, and is made when someone comes within 250 m. It's
  retried every 2 s, five times at most. `Npcs.whenMade` runs once the ped exists. Shop keepers, quest givers and
  Director NPCs all use this.
- **Somebody has to be near.** With no player in game, nothing is made. Saved vehicles are put back once someone
  has joined (three tries, a minute apart), not at server start.
- RDR2 vehicles have no number plates, and RedM's server always reads a vehicle's lock as 0. Since 24 Nov 2026 both
  are kept on the vehicle as state bags (`shared/rdr_compat.lua`). `spurPlate` holds the plate:
  `Get`/`SetVehicleNumberPlateText` read and write it on both sides, so anything that finds a vehicle by its plate
  works. `spurLock` holds the lock: the server's `SetVehicleDoorsLocked` writes it and `GetVehicleDoorLockStatus`
  reads it back. Each player's game applies it to the vehicle when it changes. The plate is also kept in the database
  as before.
- **Draft animals.** The game running one of spur_core's wagons looks at its harness once (`client/draft_animals.lua`).
  If the wagon came with its animals (made by a player's game, above), it names them to the server. If the harness
  is empty, it asks RDR2 for the wagon's own animals, and failing that makes a draft horse for each place and puts
  it in. The server keeps the animals named to it while the wagon is there and deletes them once it's gone, however
  it went (`server/draft_animals.lua`). It takes any ped but a player, run by the wagon's game, within 25 m of the
  wagon, and deletes it only if its model is still the one it had. The `spurDraft` state bag marks a wagon as done,
  so horses shot or cut loose later aren't replaced. F8 says which way each wagon was filled. On a server-made wagon
  (the fallback) neither of the two last steps works: it counts no harness places to fill.
- **Who sits where.** RedM's server sees a ped get into a vehicle but never sees it get out. `GetVehiclePedIsIn(ped,
  false)` still names the wagon after the player has climbed down and walked 6 m away, and `GetPedInVehicleSeat`
  never names anyone, even the driver (spur_test 05 "seat probe", 24 Nov 2026). whip_core asks those two natives in
  about 50 places on the server (key in the ignition, glovebox, seat changes, entered/exited events, the Director's
  car cards). Since 24 Nov 2026 each game reports where its own player sits, and where the script-made NPCs it runs
  sit, in the `spurSeat` state bag. The server's two natives answer from that (`shared/rdr_compat.lua`, SEATS). An
  "in" is believed only for a vehicle the server saw the ped get into, or one the ped is standing at (within 5 m), so
  no game can put its player in a car across the map. An "out" is believed at once. An ambient ped (not made by a
  script) reads as in no vehicle on the server.

## The vehicle list

whip_core's catalog was GTA V's 700 cars, none of which RDR2 has. `server/vehicle_catalog_list.lua` is now RDR2's
wagons, coaches, carts, boats, the rail handcart and army guns (67, 24 Nov 2026). Migration
`049_redm_gta_vehicle_catalog` runs once and deletes every catalog row whose model isn't on that list. That includes any
vehicle added by hand before it ran, so add your own vehicles to the list file, not only in game.

The classes are still GTA's numbers, as the catalog and `GetVehicleClass` keep them. The pickers (`html/js/wp/pickers.js`,
the Director's vehicle categories in `client/director.lua`) show the ones used under 1899 names:

- Compacts → Buggies & carts
- Sedans → Coaches
- Vans → Wagons
- Emergency → Law
- Trains → Rail

RDR2 has no motorbikes, cars or aircraft, so a test or a card that wants one of those finds none and says so.

## Known gaps

These are known and expected. The conversion can't fix them without RDR2 assets or more work:

- **Clothing editor.** Only slot 11 changes anything, and it picks a whole outfit. The editor's other pages, and the
  clothing pictures (GTA's), don't match RDR2. An RDR2 metaped editor would be new work.
- **The emote list** (`shared/emote_list.lua`) is RDR2 scenarios, which bring their own props. It has no walk styles,
  moods, held-prop emotes (so no megaphone or radio to hold up) or animation emotes yet. `Config.Creator.pose` is
  `false` for this reason. A client-run progress bar may hold any configured item's prop (`server/held_props.lua`).
- **`shared/director_props.lua`** (80 GTA props) is not loaded: it's not in the fxmanifest and nothing reads it. The
  world builder's Props tab reads the furniture catalog, which is RDR2's since 24 Nov 2026 (see below). A model typed
  in by hand is checked against the game and works. (The weapon lists are RDR2's since 24 Nov 2026 too.)
- **Item pictures** (`html/img/items`) are GTA-themed.
- **Vehicles.** Whip's car features (mods, colours, neon, fuel, RPM, gears, windows, sirens, the 3D dial) are
  stubs: 101 natives. Wagons and coaches use the ordinary entity natives; spawning, locks and garages pass spur_test
  with them. A wagon has no engine, lights, indicators, doors, windows, tyres, dirt level or alarm, so the
  Director's car tasks for those do nothing. GTA's explode call (the Blow Up step, the object viewer's explode) is
  RDR2's EXPLODE_VEHICLE since 24 Nov 2026 (`shared/rdr_compat.lua`); it was a stub before. Horses aren't
  vehicles to whip.
- **Kept vehicle damage** (`server/vehicle_damage.lua`). RedM's server reads an RDR2 wagon's health, engine and body
  as 0. Since 24 Nov 2026 the game running the wagon tells them (What changed: Health on the server), so damage is
  saved and put back, the Director can tell how damaged a wagon is, and a wagon at 0 health counts as wrecked. Tried
  in game since (Wagons and coaches in game, below): health and body are kept since flags5. Doors torn off and burst
  tyres stay GTA's: a wagon has neither.
- **Wagons and coaches in game** (24 Nov 2026, after the flags4 deploy: the results of the tries "Wagon damage on the
  server" and "Wagons made by a player's game", since settled and out of Not yet tried):
  - Verified: a Vehicle Manager wagon with no model (wagon02x) was made by the player's game with both horses in the
    harness (F8: `draft animals 0/0 at once, 2/2 after 3 s`), and the player stayed seated. With its key in the
    ignition, W (RDR2's INPUT_VEH_DRAFT_MOVE_UP_ONLY) drove it, the horses pulling: 7 m in 6 s. Deleted, the wagon was
    gone in 0.13 s and both horses in 0.2 s; stored, in 0.11 s and 0.18 s. F8 said `0 told to the server` for each
    such wagon, with an empty plate in that line: the harnessed horses go with the wagon in the game itself, not
    through the server's list. Steal the Car's coach (coach2) came with all 4 of its horses, and they went with it.
    That F8 line now says how many stand in the harness and how many of those are on the network and told (flags5),
    and names the wagon's model by its hash when RedM gives no name. After the flags5 deploy it said `2 in the
    harness, 0 on the network and told to the server` for wagon #54 each time it was taken out: a harnessed horse
    isn't on the network on its own (checked in game: `NetworkGetEntityIsNetworked` false for both of #54's
    harnessed horses, true for the wagon).
  - Kept damage keeps the body, not the wagon's health. Revolver bullets took a wagon from hp 1000 and body 700 to
    hp 680 and body 380. Stored and taken out, it came back with body 380 and hp 1000. whip keeps engine and body only
    (`server/vehicle_damage.lua`), and on RDR2 it's a wagon's own health that wrecks it at 0. RDR2 reads 1000 for a
    wagon's engine, not 0, and bullets didn't lower it, so F8 says `engine 1000`, not `nil`. Fixed in flags5: kept
    damage keeps a car's own health too when it's below the car's max (the `entityHealth` stat), and puts it back no
    lower than the engine floor (`Config.VehicleDamage.engineFloor`, 100). Verified after the deploy: wagon #54
    came out at hp 617 and body 618, as it was left; knocked about to hp 536 and body 537, then stored and taken out,
    it came back at hp 536 and body 537 with both horses in the harness.
  - Saved wagons put back at join: F8 showed the player's game making one for the server with 2/2 horses (netId 2),
    but the wagon there afterwards (netId 8, by Valentine's bank) was server-made, with an empty harness. The fallback
    made 2 Suffolk horses for it that couldn't be put to it; they stand loose beside it, and more come each join.
    The server log said why: `REFUSED spur_core:server:rdrVehicleMade ... No player session`, then `no player's game
    made vehicle`. Saved vehicles are put back as a player joins, before their session is there, so the game's
    answer was refused and the server made the wagon itself. Fixed in flags5 (deployed 24 Nov 2026): that answer
    needs no session (the server still believes only the player it asked), and a fallback horse RDR2 won't put in
    the harness is deleted rather than left standing. Retested after that deploy: no loose horses, but the wagon
    still came back without them. The answer got through, and the server ignored the wagon (`answered a vehicle ask
    with something else`): the player's game made it while still at character select, and the wagon was gone by
    PLAY. Fixed in flags5b (deployed 24 Nov 2026): saved vehicles are put back once a player has a character
    loaded, a vehicle is asked of a player in the world before one who isn't, and the server log says why a
    vehicle a game made is ignored. Verified after the deploy: no wagon was made at character select; after PLAY
    the player's game made both saved wagons for the server, #51 by Valentine's bank (netId 2) and #54 (netId 9),
    F8 saying `draft animals 0/0 at once, 2/2 after 3 s` for each. One of each, both horses in each harness, no
    loose horse by either, and #54 kept its hp 536 and body 537.
  - Every report of a wagon's looks put a line in the server log (`ignored a client report of mod 4(reported 0,
    stored nil), ...`). RedM's stand-in for GTA's `GetVehicleMod` answered 0, which is GTA's first part; it answers
    -1, GTA's "no part", since flags5 (`shared/rdr_compat_stubs.lua`; deployed 24 Nov 2026). Checked in game after
    the deploy: `GetVehicleMod` on wagon #54 answered -1 for mod 4. Verified (24 Nov 2026): getting off #54, which
    sends a looks report, put no line in the server log, and `ignored a client report of mod` was there 0 times
    since the restart.
  - Locks don't stop anyone getting on. RDR2's door lock shuts doors, and a wagon has none, nor has a coach's
    driver's bench: `TaskEnterVehicle` put the player on the bench of Steal the Car's locked coach, and on a locked
    wagon with the lock at 2, 3, 4 and 10. Fixed (What changed: Locked wagons; deployed and verified 24 Nov 2026): a
    player without the key is put back down. A real E press on a locked wagon is still to try (Not yet tried: For you, with a real keyboard and mouse).
  - The key rule doesn't stop a wagon. With no key in the ignition whip holds off the car accelerate control (GTA's
    71), but a wagon's horses go on RDR2's draft controls (W, Shift, S, A and D): with the key out, W still moved it.
    Fixed (What changed: Wagons and the key; deployed and verified 24 Nov 2026). A wagon already moving ran on with
    the ignition off: fixed in fixes6 (deployed and verified 24 Nov 2026; same row).
  - Seen once, not reproduced: after a death on wagon #54's bench (its cause not seen) and a revive (/w Restore
    Player Cores, then `whip_reviveme`), the player sat slumped on the bench at 200 health, RDR2 reading the ped as
    dying (`IsPedDeadOrDying` true, `IsEntityDead` false), and the horses didn't answer W or S. A script's
    `ClearPedTasksImmediately` ended the slump and left the player on the bench, and W walked the wagon after it.
    A death on the bench by /w Kill Me followed by `whip_reviveme` came back driving (W 3.9 m in 4 s), so the
    revive in a seat (`client/death.lua`) works; what left the slump is not known.
  - Unexplained: two W tries at Valentine's bank earlier the same day moved wagon #54 0.03 m and 0.002 m in 6 s.
    The player was alive and had been put in the driver's seat by `SetPedIntoVehicle` 10 to 13 s before, the wagon
    taken out 40 s before, the server's engine at 1, the draft controls free, and no speed cap written yet. The whip
    got it going two minutes later. If a real W press doesn't move a wagon just taken out, this is why to look.
- **The Director's guards fight with their model's guns.** RDR2 gives gang and lawman models weapons of their own
  when they're made. Steal the Car's guards were given theirs (the Cattleman, the sawed-off, the Carbine Repeater:
  `bIgnoreUnlocks` works) and all three fought and fired (24 Nov 2026), but in the fight the guard drew its model's
  Henry repeater and guard2 its Winchester. Guard3 kept the Carbine. Fixed (What changed: NPCs' own guns), deployed
  24 Nov 2026 and verified after: each guard drew and fired only its card's gun.
- **Pause menu, scaleform and GTA HUD pieces** are stubs (29 natives), so GTA's game-settings page is unavailable.
  The pause menu's Map and Settings open RDR2's own screens instead (What changed: Pause menu).
- **Synchronised scenes** (16 natives) are stubs. Anything whip plays as a synced scene with a camera doesn't play.
- **Blips.** They're made, named, coloured and given sprites, and kept in a registry of the port's own
  (`shared/rdr_compat.lua`), which is what whip's map pages read (RDR2 has no blip iteration). Alpha, short-range,
  categories, routes and the big map are stubs. GTA's minimap clip and positioning don't apply.
- **Waypoints.** RDR2 has no `SetNewWaypoint`. whip's waypoint reads go through `RdrCompat.waypoint()`, and setting one
  is mapped to a GPS route.
- **The Director's Writhe step** does nothing. GTA's `TASK_WRITHE` (wounded on the ground, shooting at the nearest
  player) has no RDR2 counterpart, so the NPC is left as it is and its task list goes on (`client/npcs.lua`).
- **Armour.** RDR2 has none. whip's value is kept per ped so the UI reads it back, but it stops no damage.
- **Weapon damage.** `GetWeaponDamage` returns 0, so the Director shows 0.
- **Streets.** Street names are stubs.
- **Interiors.** Portal and room queries (the property wizard's probes) are stubs, because RDR2 has no room or portal
  natives (its INTERIOR namespace has none). In game the property wizard read the interior's hash, but 0 rooms and 0
  doorways, so draw a property's space by hand (24 Nov 2026).
- **Doors not in RDR2's door list.** whip's doors lock through the game's own door hashes, taken from femga's list
  (What changed: Doors). A door with no listed door of its model within 1.5 m (a door added by a map mod, or one
  femga's list misses) registers but its locks don't hold it, and F8 says so once with its id, model and position.
  Add it to the list by hand or rerun `dev/door_hashes_rdr.py` on a newer copy of femga's file (25 Nov 2026).
- **Seen in game, not fixed yet** (24 Nov 2026):
  - indoors, the death camera frames the wall;
  - the admin panel's place maps are GTA's;
  - Capture Player's Game shows no picture;
  - the Vehicle Adjustments text still talks of motorbikes and SUVs;
  - Walks lists only Normal;
  - the server's `GetPedScriptTaskCommand` reads "none";
  - the Director's live sparks (`ent_amb_robot_sparks`) show nothing in daylight, and the other spark effects tried
    from femga's looped list didn't either (smoke, flames and steam do show);
  - the container wizard's size presets say kg while the rest of the page says lb.
- **The aim dot and RDR2's reticle.** whip hides GTA's reticle (HUD component 14) while it draws its dot, and that
  call does nothing on RDR2, whose own small dot stays in the middle of the screen, aiming or not. Verified in game
  (24 Nov 2026): aiming a Cattleman sends the dot to the middle, letting go hides it, and the page draws it (a red
  "blocked" dot showed where it was sent). The two dots sit on each other in the middle, so it looks like one; a
  blocked dot shows red beside RDR2's. femga's list of RDR2's HUD contexts has none for the reticle. Set
  `Config.AimDot = false` to keep only RDR2's.
- **The Vault example** can't be run without the mouse. Its vault world is a door with none picked, so
  `/director load vault` fails its check ("has no door picked yet") until one is picked in the World tab (G and
  Enter). A picked door now locks (What changed: Doors). Its drill emote was GTA's `mechanic`, which also
  failed the check; it's `hammer` now (24 Nov 2026).
- **Faces.** Face features, makeup, the other head overlays, tattoos and props do nothing. The creator still lists
  GTA's hair names ("Close Shave") over RDR2's hairs, and its Face camera framing is GTA's. `/charedit`'s Face tab
  shows GTA's heritage cards.
- **World-space pages.** Everything whip draws as a DUI page in the world doesn't show: speech bubbles (/me), the
  Director's spots and talk marks, the vision overlay, the garage helper, world marks and property listings. A pad can't type into
  a prompt (the pad keyboard is a DUI page); it needs a keyboard. The conversation dialog is the exception: on RedM
  it shows low on the screen instead of beside the NPC (html/js/conv-screen.js, the same dialog.html page), verified
  in game with a Director Dialog Line of two answers: moving the selection lit the second answer, and the 1 key and E
  both answered (24 Nov 2026). A team page (more than four answers, the window moving) is not tried yet.
- **E is RDR2's grapple too.** At a prompt beside an NPC (the Director's Talk), E also grabbed the NPC by the collar.
  client/interact.lua now holds off INPUT_MELEE_GRAPPLE (GTA control 141 through rdr_compat) while a prompt has the
  focus. Verified in game: E talks and answers, no grapple (24 Nov 2026).
- **The Director's NPC list is RDR2's** (24 Nov 2026). html/js/builder-peds.js is generated by
  dev/builder_peds_rdr.py from femga's rdr3_discoveries peds_list.lua: 1974 peds with readable names, in People,
  Story & Missions, Online and Animals. Verified in game: a Valentine townsman and a Suffolk Punch horse placed from
  the list. The cards have no pictures yet (a glyph shows). The shop wizard's staff, the Make NPC card's default and
  the Dungeon Master's hunters are RDR2 peds and guns too.
- **The Director's weapon lists are RDR2's** (24 Nov 2026). shared/rdr_weapons.lua, loaded in place of
  shared/gta_weapons.lua and shared/gta_weapon_models.lua, fills the same GtaWeapons and GtaWeaponModels tables with
  the 55 weapons spur_gunny gives (its names and labels) and the world models of the 24 base guns. The world builder's
  Fixed Weapons, an NPC's Weapon, Hold a Weapon, Dungeon Mode and the Object Viewer all read them through
  shared/weapon_catalog.lua. The Throw step offers dynamite, fire bottle, poison bottle, tomahawk, throwing knives and
  bolas (a step saved with one of GTA's items fails Check until re-picked; a run reads it as dynamite). Verified in game: all 24 guns listed and one placed,
  the NPC weapon dropdown lists every group, an NPC threw a throwing knife to its marker.
- **The furniture catalog and the world builder's props are RDR2's** (24 Nov 2026). server/prop_catalog_seed.lua is
  generated by dev/prop_catalog_rdr.py from femga's rdr3_discoveries objects/object_list.lua: 13,294 props in 35
  categories, filed by the archive each comes from and the words in its name, with readable names (p_barberchair01x
  is "Barber chair 01"). Map pieces, LODs, collision and weapon-blocker boxes, playing cards and weapon parts are left
  out. Verified in game: every group in the world builder's Props tab fills, search finds props by name and by model,
  and a chair, a set of barrels and an artichoke crop were placed. A seed row's category and name are set when it is
  first inserted and never changed after: rerunning the script only adds models the table doesn't have, so a fix to
  rows already seeded needs a migration (050_redm_rdr_prop_seed_fixes re-filed the first seed's clamps and took out
  its weapon blockers). The login check (is the name in the game?) finds nothing missing, since the list is the game's
  own. /propcheck, which makes each prop once, found 429 of the first seed's 13,723 the game won't spawn: nearly all
  doors and gates (the 141 doors left, like p_door02xl_static, do spawn), plus three safes, a money box and two weapon
  models. It marked them unavailable, so the furnisher hides them, and dev/prop_catalog_rdr_nospawn.txt keeps them out
  of the seed. The props have no pictures yet (a glyph shows).
- **GTA animations.** RDR2 has none of GTA's animation dictionaries, and there are no RDR2 clips in their place yet, so these happen without a body animation: handing an item over (`mp_common`), picking one up off the ground (`gen_grab`), whip's own hand press and cover grab (`whip@interact@...`, a streamed pack spur_core doesn't carry), the key fob (`key_fob`), NPC talking gestures (`gestures@...`) and the camera coming up (paparazzi). Each one plays its clip in a thread of its own that gives up when the dictionary won't load, and what it goes with (the give, the pickup, the lock) still happens. The progress bar examples in `server/timed_action.lua` and `server/inventory.lua` still name GTA's `mp_player_intdrink`: use an RDR2 dictionary there.
- **GTA names left in examples and lists nothing uses.** `Camera.Filters` (`client/camera.lua`) lists GTA timecycle modifiers for scripted shots, and `shared/cam_sequence.lua`'s example asks for `NG_filmic04`. RDR2's timecycles have other names, so a filter does nothing on RedM; nothing in spur_core picks one. Code comments that show how to call something still name GTA models (doors, prop sets, actions, the progress bar's prop, config.lua's vehicle examples), and `html/js/picture-bounds.js` lists GTA models for the media packs, which are empty. None of these runs (checked 24 Nov 2026).
  Three lists are loaded but name only GTA things, so they find nothing on RDR2: `client/stats.lua`'s weapon names
  (RDR2's guns get theirs from the weapon catalog, which it reads next), `data/rpm_by_model.lua` and
  `data/dash_skins.lua` (the 3D dial's GTA cars; the dial is a stub). `html/js/blip-names.js` is GTA's sprite names,
  which the pause menu's legend falls back on for a blip with no name of its own (checked 24 Nov 2026).
- **The Director's speech list is GTA's.** The NPC Speech task offers GTA's 715 voices and
  lines (html/js/director/speech-voices.js) through GTA's ambient speech calls, likely silent on RDR2 (not tried).
  The example scenarios use RDR2's peds, guns and a coach (24 Nov 2026), but their words are still whip's: a car
  and its key, a keypad to hack.
  Shops saved before 24 Nov 2026 keep GTA's mp_m_shopkeep_01 as their keeper: re-pick it in the shop wizard.
- **The example resources in docs/examples are GTA's.** `whip_cafe_example` and `whip_delivery_example` go with
  whip's tutorial: `game 'gta5'`, Los Santos positions, GTA's van, coffee clip and van blip. They never start by
  themselves (they sit inside spur_core's folder). To use one on RedM, give its manifest `game 'rdr3'` and the
  `rdr3_warning` line, and move its spots, model, clip and blip to RDR2's.
- **Voice.** There's no voice resource. whip_voice is FiveM's; add one made for RedM.
- **The map** (25 Nov 2026). whip's map pages (the minimap box, the pause map and the spawn picker) draw RDR2 now,
  from `map/rdr-map3d.js`: a survey of the game itself (ground heights every 20 m, water, roads and trails), not
  Rockstar's map art. Kept flat: no 3D toggle, no turning, and the spawn picker looks straight down. What it lacks:
  buildings, town names on the map, blip icon pictures (a blip is a plain dot), and smooth water edges. No shops are
  seeded (GTA's store list is empty here), so there are no shop blips until shops are made in /whip > Economy >
  Shops. `Config.Map3D = false` gives RDR2's own radar and map screen with the fog of war lifted, and no spawn
  picker. The pause map's place line names the town, district or state the player is in (`GetNameOfZone` in
  `shared/rdr_compat.lua`, from RDR2's map zones); RDR2 has no street names.
- **Control numbers with no RDR2 control.** whip's GTA control numbers map to RDR2's control hashes. A check of every
  number spur_core's client reads or blocks (24 Nov 2026) found only the radio's (81-85) and an aircraft throttle's
  (88) without one. They read as never pressed, and RDR2 has neither a radio nor aircraft, so nothing is lost.
- **Big and long items in the hand** (24 Nov 2026, play9). Give mode's default hold suits flat items (What changed:
  Items in the hand). The canteen (25 by 28 cm) and the satchel (40 by 31 cm) cover the whole hand, and a long
  item (the medicine bottle, the screwdriver) goes through the hand unless turned: 90° about x put the bottle in the
  palm, cork forward. Each wants a hold of its own, set by eye in the admin panel's Items, Edit hand position
  (`tools/hand_edit.lua`, kept in `whip_item_holds`). Seen on paper: that editor's poses are GTA's
  (`weapons@projectile@`, the `veh@drivebystd_*` clips and a `tailgater` car), so it needs RDR2 poses first. And a
  left hand with no hold of its own takes the right's (`ItemHolds.get`), which RDR2's differently turned left hand
  bone puts in the wrong place, so set both.

## Not yet tried in game

All of the following need a pass on a running server. Each one says what to fix if it's wrong.

- **For you, with a real keyboard and mouse.** Testing without the mouse (the MCP link) can't reach these. The
  panels themselves open.
  - E on a locked wagon without its key (What changed: Locked wagons): the player should be put back down within
    about 2 s, with "It's locked", and getting off it shouldn't unlock it. A script-held E doesn't start RDR2's
    get-in, so only `TaskEnterVehicle` was tried, and that passed.
  - S on a moving wagon with the ignition on (What changed: Wagons and the key): it should slow. A script-held S
    didn't. The stop on Engine Off is verified (fixes6).
  - The mouse wheel on a prompt's options (the `whip_interact_up` and `whip_interact_down` key mappings). A wheel
    sent by test automation didn't step them, which may be the automation rather than the binding.
  - Give mode, with a second player: Give on an item's right-click menu, LMB or RT throws, the cancel key, and E
    hands it over. `TriggerEvent('__cfx_nui:giveItem', ...)` from the game doesn't reach the page's callback.
  - The door pick (G and Enter).
  - Drawing a zone (WASD, the wheel and G).
  - Garage bays (Enter, Q, E and the arrows).
  - The Director's node editor, with a scenario that uses Take Cover (What changed) and one that uses Fail If the
    Car Is Damaged. That check is done on paper (24 Nov 2026): `DirectorNodes.carDamage`
    (`server/director/nodes.lua`) takes the worse of the server's body and engine readings, which on RedM come
    from the game running the wagon (`spurVeh`, the relay that kept damage uses, verified), so a wagon at body 537
    reads about 46% damaged.
  - Drawing a property's space, and the furnisher.
  - Drawing a holstered gun by aiming: an aim held by script (`_SET_CONTROL_NORMAL` on INPUT_AIM) aims a drawn gun
    but doesn't draw a holstered one, so try it with the real right mouse button.
- **The Vault** (the Director's example). `/director load vault` fails its check with its spots set ("vault did not
  pass its check"): its vault door has none picked, and picking one is the door pick in the list above (Known gaps:
  The Vault example). Run it from start to end once a door is picked: whip's doors lock on RedM now (What changed:
  Doors, verified at Valentine bank's front door, 25 Nov 2026). Courier and Steal the Car are verified (What
  changed: Director examples).

## Server setup

- **FXServer started as RedM** (`set gamename rdr3` in server.cfg), with OneSync, oxmysql, and MariaDB or MySQL.
- **`ensure spur_chat`** after `ensure spur_core` (or FXServer's `ensure chat`, not both). Without a chat
  resource, T opens nothing and players can't type commands. The setup report says so.
- **`ensure spur_loadingscreen`** for the loading screen (optional; without it RedM shows its own).
- **Don't run it beside another framework** (VORP, RSG, RedEM:RP, QBR), inventory or target. The setup report names any
  it finds.
- **Turn spawnmanager's autospawn off**, or leave out `basic-gamemode`. spur_core spawns players itself.

## The MCP link: testing without the mouse

RedM (spur_core, 24 Nov 2026): new. `dev/mcp/spur_mcp.mjs` is an MCP server (Node 18+, nothing to install) that lets
an AI client such as Claude Code drive a spur_core game on the same PC. The game can sit behind other windows (not
minimized), and nothing takes the mouse, the keyboard or the focus. It drives whip's own screen probe, screenshot and
error log, which Whippy and WLVF made for their whip_devlink "AI link". Verified in game on 24 Nov 2026: launch,
landing, character screen, Play, status, Lua, commands, the error log, the client log and screenshots, all without the
mouse.

- **How it talks.** The MCP client runs `spur_mcp.mjs` and talks to it on stdin/stdout. It also listens on
  `http://127.0.0.1:47130/link`, this PC only. spur_core's page (`html/js/mcp-link.js`) long-polls it for the next job
  and posts the answer back. `client/mcp_link.lua` does the job. Jobs come only from the MCP client. Nothing on the
  HTTP side can give the game an order.
- **Who it answers.** RedM's NUI sends its fetches with `Origin: null`, even though the page is
  `https://cfx-nui-spur_core`. So the server answers spur_core's origin, or `null` from a browser whose user agent says
  `CitizenFX/`. A web page can't set its user agent. Another resource's page in the same game browser could pose as
  spur_core while the server runs, but the most it can do is take a job or answer one wrongly.
- **Off until turned on.** The game side does nothing until it's switched on once per PC: `/mcplink on [port]` in F8,
  or `spur_mcplink <server id|all> on [port]` in the server console. It stays on (KVP `spur:mcplink`) and needs
  whip.devtools. `/mcplink off` turns it off. Reading and pressing the screen, commands and Lua also need dev mode
  (`game_dev_mode`).
- **Tools.**
  - `game_launch`: starts RedM through WMI, connecting to `SPUR_MCP_CONNECT`. The game isn't the MCP server's child, so
    closing the session leaves it running.
  - `game_quit`.
  - `game_status`: the link, the server id, coords, health, dev mode, whether a character is loaded. Never the
    player's name.
  - `game_dev_mode`.
  - `game_read_screen`, `game_press`: whip's ReadScreen and PressScreen.
  - `game_wait_for_text`.
  - `game_command`: ExecuteCommand.
  - `game_lua`: a chunk run in spur_core's client, with 30 s to finish.
  - `game_screenshot`.
  - `game_errors`: spur_core's caught errors.
  - `game_log`: the newest CitizenFX client log, with licences masked and lines naming players left out.
- **Screenshots come from Windows.** RedM's pages are handed no game picture: `CfxGameViewRenderer` and the older
  texture both stayed blue for 240 frames. So on Windows `game_screenshot` reads the game window with PrintWindow
  (`PW_RENDERFULLCONTENT`), which works with the window behind others. It shows everything in the window, chat
  included. `source: 'page'` is the in-game way (works on FiveM).
- **The landing** ("Press any button to continue") has no control to press. Use `game_lua` `Landing.Continue()`.
- **Setup**, once, user scope. Keep the server address out of repo files.
  `claude mcp add --scope user spur-game --env SPUR_MCP_CONNECT=<ip:port> -- node "<path>\spur_core\dev\mcp\spur_mcp.mjs"`.
  The other settings are `SPUR_MCP_PORT`, `SPUR_REDM_EXE`, `SPUR_REDM_LOGS`, `SPUR_MCP_SHOTS` and
  `SPUR_MCP_ORIGINS` (see the file's header).
- **The panel console** (RocketNode's websocket) runs a command only when it ends with `\r`. Without it the text is
  only echoed.
- **Handy while testing** (24 Nov 2026):
  - `game_press` takes a control's `id` or its `label`. `text` together with an `id` types into that field; `text`
    alone fails.
  - With Dev Tools open (`w`), world prompts are hidden.
  - A shop's prompts are world prompts, so close Dev Tools before walking to a counter.
  - `whip_reviveme` (`game_command`) revives the player.
  - `Inventory.close()` shuts the shop screen.
  - `PropertyWizard.active()` says whether the property wizard is up.
  - `TriggerEvent('spur_core:client:fadeTeleport', x, y, z, h)` moves the player with a fade.
  - Never reconnect from inside the game: RedM crashes. Quit and launch again instead.
  - A prompt is pressed by calling it: `Interactions.getAll()[id]` gives each prompt, and its `callback` (a ground
    pile, `ground_<id>`) or `options[1].callback` (a Director Talk, `act:spur_core:rpoint:<id>`) does what E does.
    `/director start` opens no conversation: a Dialog Line needs a Talk press (it has no `useId` otherwise), so press
    the NPC's Talk point after it. A conversation's answers: `Conversations.answerByNumber(n)`.
  - A wagon is driven on RDR2's draft controls, held with `_SET_CONTROL_NORMAL` (0xE8A25867FBA3B05E): W is
    0x29A5E51E with MOVE_UD 0x23595CEA at -1, S 0x25493EB3, the whip (Shift) 0xE99D2B05, which gallops at once.
    Steering held that way (TURN_LR 0xA7DFAE8A, A 0x198AFC64, D 0x5E371EA7) didn't turn a coach, and neither did
    `TaskVehicleDriveToCoord`.
  - A key goes in the ignition with `spur_core:server:storeMove` from its pocket slot
    (`Inventory.nuiStoreAddr('player', slot)`) to `{ kind = 'vehicle', id = vehicleId, sub = 'key', slot = 1 }`, while
    in the driver's seat.
  - Key bindings (verified 24 Nov 2026): F2, E, F1, Tab, and T for chat (spur_chat) work, T straight after spawning
    too. Typing `whip_interact_up` or `whip_interact_down` in F8 steps a prompt's options (tried at a bank counter).
    Test automation that typed a Shift character (`_`, `+`) into the chat line or F8 sometimes left Shift held as far
    as key mappings go, and T and F2 did nothing until Shift was pressed on its own. Walking was unaffected. If a
    player reports chat "won't open", that's the first thing to try.
  - An item's prop goes in the hand with `TriggerServerEvent('spur_core:server:barProp', model, bone, {x, y, z},
    {x, y, z})` (a client bar's way, for any item's prop) and comes out with `spur_core:server:heldPropsDrop` `'bar'`.
    `UI.ownHeldProp(hash, 'bar')` finds it. A scripted camera (`CreateCam`, `PointCamAtCoord`, `RenderScriptCams`)
    shows the hand close up.
  - RDR2's idle camera (letterboxed, framing whoever passes) comes on after a while with no real input. Moves made by
    script don't end it, so screenshots then show its view.

## Stubbed natives, by area

These are GTA V natives that whip_core calls with no RDR2 counterpart. Each one is a no-op on RedM. The list is
generated from `shared/rdr_compat_stubs.lua` and leaves out names that `shared/rdr_compat.lua` maps.

**Ped clothing, faces and headshots** (29): `AddPedDecorationFromHashes`, `ClearPedDecorationsLeaveScars`, `ClearPedProp`, `GetForcedComponent`, `GetHashNameForComponent`, `GetNumMakeupColors`, `GetNumberOfPedPropDrawableVariations`, `GetNumberOfPedPropTextureVariations`, `GetPedCollectionLocalIndexFromDrawable`, `GetPedCollectionLocalIndexFromProp`, `GetPedCollectionName`, `GetPedCollectionNameFromDrawable`, `GetPedCollectionNameFromProp`, `GetPedDecorationZoneFromHashes`, `GetPedDrawableGlobalIndexFromCollection`, `GetPedMakeupRgbColor`, `GetPedPropIndex`, `GetPedPropTextureIndex`, `GetPedTextureVariation`, `GetPedheadshotTxdString`, `GetShopPedApparelForcedComponentCount`, `IsPedheadshotReady`, `IsPedheadshotValid`, `RegisterPedheadshot`, `RegisterPedheadshotTransparent`, `ResetPedVisibleDamage`, `SetPedFaceFeature`, `SetPedPropIndex`, `UnregisterPedheadshot`

**Vehicles** (101): `AttachVehicleToTrailer`, `BlockWeaponWheelThisFrame`, `DetachVehicleFromTrailer`, `DisableVehiclePassengerIdleCamera`, `GetFollowVehicleCamViewMode`, `GetIsDoorValid`, `GetIsVehicleEngineRunning`, `GetIsVehiclePrimaryColourCustom`, `GetIsVehicleSecondaryColourCustom`, `GetNumberOfVehicleDoors`, `GetVehicleColours`, `GetVehicleCurrentGear`, `GetVehicleCurrentRpm`, `GetVehicleCustomPrimaryColour`, `GetVehicleCustomSecondaryColour`, `GetVehicleDashboardColour`, `GetVehicleDirtLevel`, `GetVehicleDoorAngleRatio`, `GetVehicleExtraColours`, `GetVehicleFuelLevel`, `GetVehicleGearRatio`, `GetVehicleHandbrake`, `GetVehicleHandlingFloat`, `GetVehicleHandlingInt`, `GetVehicleHeadlightsColour`, `GetVehicleHighGear`, `GetVehicleIndicatorLights`, `GetVehicleInteriorColour`, `GetVehicleLightsState`, `GetVehicleMod`, `GetVehicleModelEstimatedMaxSpeed`, `GetVehicleNeonLightsColour`, `GetVehicleNumberPlateTextIndex`, `GetVehiclePedIsTryingToEnter`, `GetVehicleSteeringAngle`, `GetVehicleThrottleOffset`, `GetVehicleTyreSmokeColor`, `GetVehicleWheelBrakePressure`, `GetVehicleWheelRotationSpeed`, `GetVehicleWheelSpeed`, `GetVehicleWheelType`, `GetVehicleWindowTint`, `InvalidateVehicleIdleCam`, `IsPedDoingDriveby`, `IsThisModelABicycle`, `IsThisModelABike`, `IsThisModelAHeli`, `IsThisModelAPlane`, `IsThisModelAQuadbike`, `IsToggleModOn`, `IsTurretSeat`, `IsVehicleAConvertible`, `IsVehicleDoorDamaged`, `IsVehicleNeonLightEnabled`, `IsVehicleSirenOn`, `IsVehicleTyreBurst`, `LowerConvertibleRoof`, `NetworkExplodeVehicle`, `RaiseConvertibleRoof`, `RemoveVehicleMod`, `RollDownWindow`, `RollUpWindow`, `SetVehRadioStation`, `SetVehicleAlarm`, `SetVehicleBrakeLights`, `SetVehicleCheatPowerIncrease`, `SetVehicleColours`, `SetVehicleCurrentRpm`, `SetVehicleCustomPrimaryColour`, `SetVehicleCustomSecondaryColour`, `SetVehicleDashboardColour`, `SetVehicleExtraColours`, `SetVehicleFuelLevel`, `SetVehicleFullbeam`, `SetVehicleHandlingFloat`, `SetVehicleHandlingInt`, `SetVehicleHeadlightsColour`, `SetVehicleHighGear`, `SetVehicleIndicatorLights`, `SetVehicleInteriorColour`, `SetVehicleInteriorlight`, `SetVehicleMaxSpeed`, `SetVehicleMod`, `SetVehicleModKit`, `SetVehicleNeonLightEnabled`, `SetVehicleNeonLightsColour`, `SetVehicleNumberPlateText`, `SetVehicleNumberPlateTextIndex`, `SetVehicleSiren`, `SetVehicleSteeringAngle`, `SetVehicleTyreSmokeColor`, `SetVehicleWheelRotationSpeed`, `SetVehicleWheelType`, `SetVehicleWindowTint`, `SmashVehicleWindow`, `SoundVehicleHornThisFrame`, `StartVehicleAlarm`, `TaskVehicleDriveToCoordLongrange`, `TaskVehicleFollow`, `ToggleVehicleMod`, `WashDecalsFromVehicle`

**GTA pause menu, scaleform, HUD and frontend** (29): `ActivateFrontendMenu`, `AddReplaceTexture`, `BeginScaleformMovieMethod`, `BeginScaleformMovieMethodOnFrontend`, `ClearPedInPauseMenu`, `CreateRuntimeTextureFromDuiHandle`, `DrawTexturedPoly`, `EndScaleformMovieMethod`, `EndScaleformMovieMethodReturnValue`, `GetControlInstructionalButton`, `GetHudColour`, `GetProfileSetting`, `GetScaleformMovieMethodReturnValueString`, `GivePedToPauseMenu`, `HideHudComponentThisFrame`, `IsFrontendReadyForControl`, `IsPauseMenuRestarting`, `IsScaleformMovieMethodReturnValueReady`, `IsWarningMessageActive`, `RemoveReplaceTexture`, `ReplaceHudColourWithRgba`, `RequestScaleformMovie`, `ScaleformMovieMethodAddParamInt`, `ScaleformMovieMethodAddParamTextureNameString`, `SetHudComponentPosition`, `SetPauseMenuPedLighting`, `SetPauseMenuPedSleepState`, `TriggerScreenblurFadeIn`, `TriggerScreenblurFadeOut`

**Synchronised scenes and cameras** (16): `CreateSynchronizedScene`, `DisableIdleCamera`, `GetFollowPedCamViewMode`, `GetSynchronizedScenePhase`, `IsSynchronizedSceneRunning`, `NetworkAddEntityToSynchronisedScene`, `NetworkAddPedToSynchronisedScene`, `NetworkCreateSynchronisedScene`, `NetworkStartSynchronisedScene`, `NetworkStopSynchronisedScene`, `PlaySynchronizedCamAnim`, `SetCamAnimCurrentPhase`, `SetFollowPedCamViewMode`, `SetSynchronizedScenePhase`, `SetSynchronizedSceneRate`, `TaskSynchronizedScene`

**Blips and the map** (22): `GetBlipAlpha`, `GetBlipInfoIdDisplay`, `GetBlipInfoIdEntityIndex`, `GetBlipInfoIdType`, `GetBlipRotation`, `GetFirstBlipInfoId`, `GetNextBlipInfoId`, `IsBigmapActive`, `IsBlipFlashing`, `IsBlipShortRange`, `IsMinimapRendering`, `SetBlipAlpha`, `SetBlipAsShortRange`, `SetBlipCategory`, `SetBlipDisplay`, `SetBlipRoute`, `SetBlipRouteColour`, `SetMinimapClipType`, `SetMinimapComponentPosition`, `SetRadarBigmapEnabled`, `ShowHeadingIndicatorOnBlip`, `ShowNumberOnBlip`

**Interiors** (9): `GetInteriorPortalCount`, `GetInteriorPortalEntityArchetype`, `GetInteriorPortalEntityCount`, `GetInteriorPortalEntityPosition`, `GetInteriorPortalEntityRotation`, `GetInteriorRoomCount`, `GetInteriorRoomExtents`, `GetInteriorRoomName`, `GetRoomKeyForGameViewport`

**Streets** (2): `GetStreetNameAtCoord`, `GetStreetNameFromHashKey`

**Other** (30): `CreateRuntimeTxd`, `GetEntityArchetypeName`, `GetEntityBoneCount`, `GetPickupHashFromWeapon`, `HaveAllStreamingRequestsCompleted`, `IsCamPlayingAnim`, `IsPedInHighCover`, `IsPedInParachuteFreeFall`, `NetworkGetLocalSceneFromNetworkId`, `PlayPedAmbientSpeechWithVoiceNative`, `RemoveAllProjectilesOfType`, `ResetPedMovementClipset`, `SetBlackout`, `SetCanAttackFriendly`, `SetEntityAngularVelocity`, `SetEntityLocallyInvisible`, `SetEntityLocallyVisible`, `SetEntityMaxSpeed`, `SetLocalPlayerVisibleLocally`, `SetNetworkIdCanMigrate`, `SetObjectTextureVariation`, `SetPedAlertness`, `SetPedCanBeDraggedOut`, `SetPedDiesWhenInjured`, `SetPedMovementClipset`, `SetPedSuffersCriticalHits`, `SetPlayerCanDoDriveBy`, `SetUserRadioControlEnabled`, `ShootSingleBulletBetweenCoordsIgnoreEntity`, `ToggleUsePickupsForPlayer`

