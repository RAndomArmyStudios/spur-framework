# Theming whip's UI

A whip skin is a **separate resource** containing an `fxmanifest.lua` and a `theme.css`.
It never touches spur_core, so it survives every framework update.

## How it works

Every visual decision whip's UI repeats — colors, fonts, radii, shadows, spacing — is a
CSS custom property declared once in `spur_core/html/css/base.css`. Your `theme.css`
redeclares whichever tokens you want changed; whip injects it **after** every framework
stylesheet, so your values win the cascade everywhere at once: inventory, HUD gauges,
prompts, dev tools, all of it.

```css
/* theme.css — override tokens, nothing else */
:root {
    --ui-accent: #fbbf24;
    --ui-surface: rgba(20, 15, 8, 0.78);
    --ui-radius-panel: 10px;
}
```

## Activating

1. Put the theme resource in `resources/` and `ensure` it in server.cfg.
2. `Config.Theme = 'your_theme_resource'` in `spur_core/config.lua` (§13 ADVANCED;
   default `nil` = base look).
3. Restart spur_core (the config value is read once, when a client's UI announces ready).

While iterating: `/whip_theme your_theme_resource` (requires the `whip.devtools` ACE)
re-applies live — edit theme.css, run the command, see it. `/whip_theme none` drops to the
base look; `/whip_theme` alone re-applies whatever the server currently says (the runtime
override below, else Config.Theme).

A theme resource that is stopped, misnamed, or missing its `files{}` entry fails **soft**:
the base look survives and the F8 console names the resource that could not load.

### Runtime override (start/stop skins)

Config.Theme is the *standing* theme. A skin can instead be a start/stoppable resource that
applies itself, via the override registry in `server/themes.lua`:

```lua
-- the skin's fxmanifest.lua includes whip's satellite helper:
--     shared_script '@spur_core/lib/satellite.lua'

-- the skin's server.lua, in full
Whip.register(function()
    exports.spur_core:SetActiveTheme('my_skin')
end)
```

`start my_skin` reskins every connected client live (no restart — the NUI hot-swaps the
link); `stop my_skin` reverts to Config.Theme automatically (the registry stamps the
registering resource as owner and unwinds on its onResourceStop). Late joiners receive the
active override with their login sync. Whip.register rather than file scope for the usual
reason: it runs again after a core restart, which is when the registry's state has died.

### Partial themes

theme.css does not have to reskin everything. Scope every selector under one panel root —
`#ui-notifications .ui-notif { … }` — and only that panel changes; the rest of the UI stays
stock. Because theme.css loads last, a scoped file still wins the cascade over the panel's
own sheet.

## The token catalog

`base.css` is the catalog — every token is declared and commented there. The families:

| Prefix group           | What it retunes                                             |
| ---------------------- | ----------------------------------------------------------- |
| `--ui-surface*`        | Panel grounds (the translucent dark slate)                  |
| `--ui-border*`         | The hairlines                                               |
| `--ui-shadow*`, `--ui-rim` | Panel lift, modals, world-facing text rims             |
| `--ui-radius-*`        | The shape ladder (panel/pop/row/slot + sm/xs/pill)          |
| `--ui-text*`           | Text tints                                                  |
| `--ui-accent/success/error/warning/info` + alpha variants, `--ui-on-accent` | Semantic color, and the text colour on an accent-filled button |
| `--ui-slot-*`          | The Slot tile: inventory grids and the accessory rail (fill, edge, hover, lift, focus, `-bg-chosen` for a controller's slot and the hotbar's used disc) |
| `--ui-hotbar-scale`    | How much bigger than a stat disc the hotbar's discs, keys and counts draw (1.5) |
| `--ui-ring`            | The white ring around a chosen card (the creator's 0.65 white) |
| `--ui-pill*`           | The white selection pill and its ink (drop targets, selected tabs, the house look's primary button) |
| `--ui-panel-glow`      | The house look's corner glow on menu-style panels (inventory, creator…); `none` for plain glass |
| `--ui-scrim`           | The dim behind the inventory (client Lua sends the live value; this is the fallback) |
| `--ui-item-shadow*`    | The shadow that lifts item art off its slot                 |
| `--ui-zoom-inventory`  | How much bigger than the rest of the UI the inventory draws (1.32) — tune with care, the shell is calibrated to it |
| `--ui-font`, `--ui-mono`, `--ui-fs-*`, `--ui-fw-*` | Typography             |
| `--ui-font-display`, `--ui-fw-display`, `--ui-fs-display` | The house look's titles (the real 800 ExtraBold, at the title size) |
| `--ui-ease*`           | Motion curves                                               |
| `--ui-sp-*`            | Spacing scale                                               |
| `--ui-scrollbar-*`     | The one scrollbar, and the heavier "reach" bar (`-reach`) the inventory uses where the bar is how you get to hidden slots |
| `--ui-select-option-bg/fg` | Native `<option>` dropdown rows (they ignore the normal surface tokens) |
| `--inv-*`              | Legacy inventory aliases — all `var(--ui-*)` passthroughs now, kept for themes written against the old names. whip's own inventory reads `--ui-*` only (since 24 Sep 2026), so override those |

Not themeable: `--ui-scale`. It looks like a token but JavaScript writes it as an inline
style on the root element (the UI-scale setting), and inline styles out-rank any `:root`
declaration — a theme override of it silently does nothing.

Constraint: the NUI browser is Chromium 103. Write 2022-safe CSS — custom properties are
fine; `:has()`, native nesting, `color-mix()` and container queries silently do nothing.
Derive tints as explicit rgba values, the way base.css itself does. The failure mode is
nasty precisely because it is silent: the rule parses, drops, and your theme just looks
subtly wrong — so when a value refuses to apply in game, suspect the syntax's *age*
before suspecting the cascade.

## Locked tokens

`--ui-fade` and `--it-fade` are mirrored as millisecond constants in whip's
JavaScript. A theme that changes them desyncs element teardown from its fade and prompts
blink instead of fading. They are marked LOCKED in base.css — leave them alone.

## Bringing your own fonts

Override `--ui-font` / `--ui-mono` and ship the font files in your theme resource:

```lua
-- fxmanifest.lua
files { 'theme.css', 'fonts/myfont.woff2' }
```

```css
@font-face {
    font-family: 'MyFont';
    src: url('https://cfx-nui-your_theme_resource/fonts/myfont.woff2') format('woff2');
}
:root { --ui-font: 'MyFont', 'Segoe UI', sans-serif; }
```

Any resource's declared files are servable at `https://cfx-nui-<resource>/<path>` — the
same mechanism satellite item icons already use.

## Token overrides vs selector overrides

Prefer retuning tokens over writing selectors against whip's markup. The tokens are the
**contract** — they will exist next update. Class names like `.ui-notif` are stable in
practice but *not promised*: a selector-heavy theme fails soft on a rename (the rule just
stops matching and that element falls back to base), which is survivable but silent.
So: reach for a selector when a token genuinely can't express the design (rotated labels,
say), and keep every selector scoped under its panel root while you do —
un-scoped element selectors (`span { … }`) leak into all 37 panels at once. Avoid
`!important`: theme.css already loads last and wins ties on order; `!important` only
matters when you're fighting a *more specific* whip selector, and winning that fight
pins styling whip's own states (hover, `.visible`, drag) can then no longer change.

## What a theme cannot reach

Layout (panel widths, grid columns, element structure) belongs to the renderer, not the
token layer. If you want a *differently shaped* inventory rather than a differently
dressed one, that is the custom renderer seam — see `docs/nui-inventory.md`.
