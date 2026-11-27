# whip_vehicle_hud

The 3D rev dial from the vehicle HUD mock, written as a standalone NUI resource. spur_core embeds this folder's page
files; the standalone wrapper (`html/index.html`, `html/main.js`) and `client.lua` aren't in this copy. The dial:
- **Position:** the bottom-right corner, at the reference screenshot's size, a little lower than its position
  (`bottom` 1.35 dial radii from the screen's edge to the dial's centre; it was 1.575).
- **Dial:** status lights (each with the segment under it), a rev range scalable from 2,000 to 20,000 rpm, and up to
  five extra gauges on the dial's rim, from the lower-left up its left side.
- **Files:** everything is local (three.js r170, a Roboto subset); no internet needed.

`client.lua` is a reference feeder: it is untested in game, and the framework may replace or merge it. The NUI side
(`html/`) is the part that matters, and it only listens to the messages below.

## Files

| File | What |
|---|---|
| `html/index.html` | The standalone resource page: one canvas, import map for three.js, loads `main.js` |
| `html/main.js` | Standalone wrapper: NUI messages, resize listener, fade |
| `html/hud.js` | `createVehicleHud(canvas)`: the API a host page calls (smoothing, lean / shift kick / limiter, placement, fonts) |
| `html/hud3d.js` | The 3D dial (three.js) |
| `html/dial.js` | Layout box, status lights, rev scale, speed and gear formatting |
| `html/gauges.js` | Extra gauges: the orbit and the aircraft fan, icons (built-in glyphs + SVG paths), the gauge contract |
| `html/air.js`, `html/air3d.js` | Aircraft mode: the flight instruments' layout, and their shaders |
| `html/boat.js` | Boat mode: the power scale |
| `html/vendor/three.module.min.js` | three.js r170 (MIT), the same file whip_phone ships |
| `html/fonts/*.woff2` | Roboto (open-licence Google Font), cut to the characters the dial draws, one variable file per style; registered by `hud.js` as `whip-hud-roboto` |
| `client.lua` | Reference feeder + exports (`SetGauge`, `RemoveGauge`, `SetLayout`) |

To avoid shipping three.js twice, the import map in `index.html` can point at whip_phone's copy instead:
`https://cfx-nui-whip_phone/html/vendor/three/three.module.min.js`. That makes whip_phone a dependency.

## Embedding in a host page (spur_core)

```js
const { createVehicleHud } = await import('./vehicle_hud/hud.js');   // e.g. on first vehicle entry
const hud = createVehicleHud(canvas);   // canvas: position: fixed at body level; the dial places itself bottom-right
hud.setState({ maxRpm: 7.5, rpm: 0.9, speed: 0, gear: 'N', units: 'kmh' });
hud.setGauge({ id: 'fuel', icon: 'fuel', order: 1, value: 0.42, text: '42%', dangerLow: 0.15 });
hud.show();                              // hide() stops rendering at once: fade the canvas first if you want motion
hud.setConfig({ scale: uiScale });      // size (1 = reference); right / bottom move the dial from the corner
addEventListener('resize', () => hud.resize());
hud.dispose();                           // when done for good
```

- The factory adds no listeners and no fade.
- It registers the bundled fonts itself (via `import.meta.url`, so keep `fonts/` next to `hud.js`).
- The host page needs an import map entry for `three` (`hud3d.js` imports it by that name), pointing at
  `vendor/three.module.min.js` or whip_phone's copy.

## Messages (standalone resource: SendNUIMessage, handled by main.js)

| type | payload | effect |
|---|---|---|
| `vhud:show` | | fades the dial in and starts rendering |
| `vhud:hide` | | fades it out and stops rendering |
| `vhud:state` | `state`: any subset of the fields below | merged into the current state |
| `vhud:gauge` | `gauge`: `{ id, icon, value, text?, danger?, dangerLow?, order? }` | adds or updates an extra gauge |
| `vhud:gaugeRemove` | `id` | removes it (it fades out and the others close up) |
| `vhud:config` | `config`: `{ scale?, right?, bottom?, attitude? }` | size (1 = reference) and dial centre from the corner, in dial radii; `attitude`: `'ball'` (default) or `'flat'` |

Send state at 15-30 Hz while driving. The dial smooths rpm and speed between updates, so the needle moves at the
screen's frame rate. When nothing moves (parked, idling), the dial skips rendering entirely.

## State

| Field | Type | Native (client.lua) |
|---|---|---|
| `rpm` | thousand rpm | `GetVehicleCurrentRpm` (0.2 idle .. 1.0 limiter) mapped onto the dial's idle .. limiter (see Rev ranges); 0 with the engine off |
| `maxRpm` | 2-20, thousand rpm | per class, or set by a resource (see Rev ranges); send on entering a vehicle |
| `redline` | thousand rpm, optional | per model; defaults to 87% of `maxRpm` (the reference's 6.5 of 7.5) |
| `speed` | km/h | `GetEntitySpeed` x 3.6 |
| `units` | `'kmh'` / `'mph'` | `ShouldUseMetricMeasurements()` |
| `gear` | number, `'R'` or `'N'` | `GetVehicleCurrentGear` (0 = R), or a forward gear a resource set with `SetVehicleDialGear`; `'N'` when stopped with the handbrake on |
| `handbrake` | 0 / 1 | `GetVehicleHandbrake` (no light of its own any more: see `engine`) |
| `engine` | bool | `GetIsVehicleEngineRunning` (the engine light, lit while it runs: in whip, where the P light was) |
| `lights` | `'off'` / `'low'` / `'high'` | `GetVehicleLightsState` (grey / green / blue light) |
| `locked` | bool | `GetVehicleDoorLockStatus` (lock light: lit when locked) |
| `damage` | bool | `GetVehicleEngineHealth` < 400 (warning light flashes) |
| `kind` | `'car'` / `'air'` | `'air'` for helicopters and planes (classes 15, 16): see Aircraft mode |
| `pitch` | degrees, nose up + | `GetEntityPitch` (aircraft) |
| `roll` | degrees, right wing down + | `GetEntityRoll` x `Config.rollSign` (aircraft; the sign is unverified in game) |
| `altitude` | metres above sea level | `GetEntityCoords(veh).z` (aircraft; shown in feet) |
| `gearState` | `'down'` / `'up'` / `'moving'` / `'none'` | `GetLandingGearState`: 0 down, 1 retracting and 3 deploying = moving, 4 up, 5 broken (shown as moving); `'none'` without retractable gear (aircraft) |
| `kind: 'boat'` | | boats (class 14): see Boat mode |
| `power` | 0 idle .. 1 full revs (boats) | (`GetVehicleCurrentRpm` - 0.2) / 0.8; without it the dial works power out from `rpm` and `maxRpm` |
| `anchored` | bool | `IsBoatAnchored` (boats; unverified, whip may track its own anchor) |

**Worked out by `hud.js`, never sent:**
- the lean: the dial tips back accelerating and forward braking, from the speed's rate of change;
- the four segments in the ring's gap: each lights with the status light above it, in that light's colour (green / blue
  headlights, red warning flashing with it); there's no `meter` field any more (9 Oct 2026);
- the shift kick, from a change of gear number;
- the limiter judder, from rpm held at 97% of `maxRpm` or more (in whip the outer light pipe also flashes red and
  white then, 150 ms each);
- in whip, each extra gauge's ring easing toward its value between updates (`GaugeLayout`; text stays exact).

**whip's edits (8 Oct 2026, each marked `WHIP EDIT` in the code):** the speed unit label at 2.1x;
the engine light in place of the P; the gauges' easing; the limiter flash; a dark edge on lit tick blades near the
needle, so they still read as lines on the bright sweep. 16 Oct 2026: the padlocks (the dial's lock light in dial.js,
the `hack` gauge icon in gauges.js) have a full shackle — straight legs and an arch — instead of a stub on the body.
19 Oct 2026, hud.js: a launch's needle bounce follows the needle, not the flash. It starts the moment the needle
reaches the top and stops as soon as the revs drop under 95% of it (`atTop`, `BOUNCE_OUT`); the flash keeps its 0.15 s
hold and 0.25 s release. Before, the needle waited out the hold at the top and bounced on its way down.
whip's dial skins (a dashboard look per car model) aren't in this copy: every dial is as designed.

## Rev ranges (`data/rpm_by_model.lua`)

`GetVehicleCurrentRpm` is 0.2 at idle and 1.0 at the limiter for every vehicle, so a dial's range has to come from
somewhere else. whip measured an idle and a limiter for each car model of its original game; that list isn't in this
copy (26 Nov 2026). What's left:

- `models`: empty. Give a vehicle a range of its own as `{ idle, limiter }` in thousand rpm under its spawn name.
- `classMax`: the top of the dial for anything not listed:

  | Class | Top of dial |
  |---|---|
  | military, commercial | 2.5k |
  | industrial | 3k |
  | service, utility | 3.5k |
  | vans | 5.5k |
  | suvs, offroad | 6k |
  | sportsclassics, muscle, emergency | 6.5k |
  | compacts, sedans | 7k |
  | sports, coupes | 7.5k |
  | super | 8.5k |
  | openwheel | 9k |
  | motorcycles | 12k |

- spur_core takes a range from the vehicle's engine (its own, or the one a resource gives it through
  `SetVehicleRevRange`), first match wins: config.lua's `rpmByModel`, `rpmElectric` for an electric engine, then
  `rpmByClass`, the class top above and `rpmMax`. The idle is 0 for an electric engine, else config.lua's
  `idleRpm`, or about 11% of the dial.
- `rpm` = idle + (raw - 0.2) / 0.8 x (limiter - idle). A raw reading of 0.99 or more counts as the limiter, because
  the game hovers just under 1.0 there.

## Aircraft mode (`kind: 'air'`)

The dial keeps its shape and size, but its inside becomes the instruments of an aircraft's primary flight display:
- **Attitude indicator** filling the ring: blue sky over brown ground, the horizon moved by pitch and turned by roll.
  - By default it is a 3D ball, like a gyro horizon's: the painted sphere turns behind a fixed bank scale and aircraft
    symbol, so the horizon and rungs curve and crowd toward the rim, inside a dark case. `setConfig({ attitude:
    'flat' })` (or `vhud:config`) gives a flat disc instead. The ball turns 1.7x faster than the aircraft near level, so
    the ladder reads as large as on the flat disc; pitch 90 still brings the pole to the front.
  - A white pitch ladder: a rung every 2.5 deg, numbered every 10.
  - A bank scale on the upper arc (10, 20, 30, 45, 60 deg) with a fixed index, and a pointer that turns with the sky.
  - A fixed yellow aircraft symbol.
- **Airspeed tape** left of the ring, in mph (from `speed`, km/h). Ticks every 5, numbers every 10.
- **Altitude tape** right of the ring, in feet (from `altitude`, metres). Ticks every 20, numbers every 100.
- Both tapes scroll past a black readout box with a notch pointing at the ring. Its digits roll like a drum:
  - airspeed: the ones digit rolls continuously;
  - altitude: the last two digits roll in 20 ft steps;
  - every higher digit turns over only as the one below rolls past 9, like an odometer.
- **Status lights:** the first light (the lock, in a car) shows the landing gear: green down, red moving, grey up or
  none. The headlights, engine and warning lights are unchanged.
- **Extra gauges** fan over the top of the dial instead of running up its left side, clear of the tapes. They slide
  round when the kind changes.
- The ring is a plain bezel (no rev scale, no red zone); there is no needle, speed digits or gear.
- `hud.js` smooths pitch, roll (the short way round through +-180) and altitude between updates, like rpm and speed.
  The limiter judder is off.
- Everything that moves is drawn per pixel from one glyph texture (`air3d.js`): flying uploads no textures.

## Boat mode (`kind: 'boat'`)

The dial keeps its look; three things change:
- **Power instead of revs:** the scale reads engine power, 0 to 100% (numerals every 20, ticks every 2): idle at 0, full
  revs exactly at the end of the scale, and no red zone. Send `power` (0-1); without it the dial works it out from `rpm`.
  The limiter judder is off.
- **Gear:** the shift lever's F / N / R (`gear: 'F'`), rolling on the same drum.
- **Status lights:** the first light (the lock, in a car) shows the anchor, lit while it's down.
- The gauges orbit as in a car.

## Extra gauges

Any stat, for example turbo pressure, boost, fuel, coolant, hacking progress or a weapon cooldown.

| Field | Meaning |
|---|---|
| `id` | the stat's key |
| `icon` | `'turbo'`, `'nitro'`, `'fuel'` (WHIP EDIT: `'fuel_left'` / `'fuel_right'`, the pump with an arrow to the filler's side), `'coolant'`, `'hack'` or `'weapon'`, or an SVG path string in a 24x24 viewBox (e.g. a Material icon's `d`), drawn filled in the same box and colour. Anything that isn't a path draws a dot |
| `value` | 0-1 |
| `text` | shown in the gauge's bottom gap. The 3D dial spells digits, capitals, lowercase (WHIP EDIT: all of it, was `s x m h k`), `. , % ° : + - /` and space from a glyph atlas; other text falls back to a canvas texture |
| `ends` | WHIP EDIT: `['E', 'F']`, up to 3 characters each: markers at the arc's empty and full ends, in the bottom gap, shown instead of `text` (a fuel gauge) |
| `danger` | where a red zone at the top starts (turbo, coolant) |
| `dangerLow` | where a red zone at the bottom ends (fuel, health, oxygen) |
| `order` | slot order, lower first. Fuel uses 1 |

- A value inside either red zone makes the gauge critical: its icon flashes red and its text turns red.
- Up to five gauges orbit the dial, 1.42 dial radii out and 28 deg apart: slot 1 at the lower-left (-130 deg, as low as
  they go and stay on screen), each next one above the last, up the dial's left side. In aircraft mode they fan over
  the top instead, clear of the airspeed tape. They slide round the rim to make room, and round to the fan and back.

## Notes

- The page is display-only: no NUI focus, no input.
- Performance: no lights, no post-processing; changing numbers are atlas quads, not texture uploads. In the mock's
  benchmark the 3D dial took about 0.06 ms of CPU per frame.
- `client.lua` hides the dial on bicycles and trains (aircraft and boats get their own modes), and while the pause
  menu is open.
