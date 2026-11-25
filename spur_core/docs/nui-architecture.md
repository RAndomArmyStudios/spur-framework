# whip NUI architecture

One page (`html/index.html`), one module entry (`html/js/main.js`), plain ES modules, no
build step. Everything ships readable.

## The layers

```
base.css            design tokens + fonts + element base — THE theme contract
router.js           action dispatch (Map, multi-subscriber) + keyboard scopes
utils.js            nuiCallback, escapers, image URL resolution
core/               the inventory system's DOM-free half:
  item-defs.js        item definitions (absent-means-unchanged adoption)
  inv-state.js        all state as two objects (inv, shop) + optimistic views + slot registry
  inv-ops.js          the optimistic-operation engine (keyed snapshots, explicit opIds)
  emitter.js          the announcement stream
  inv-wire.js         every inbound message: state mutation + renderer-interface calls
  inventory.js        the facade: renderer seat + one-line third-party import
inventory.js        the DEFAULT renderer (DOM, drag, tooltips, menus) — replaceable
<feature>.js        one module per PLAYER-FACING panel; registers its own actions, key
                    scope, binders
whip-panel.js       the /whip admin panel SHELL: chrome, group words + tabs, section registry,
                    the WP helpers, ONE key scope, ONE zoom, ONE delegated binder
wp/<section>.js     one module per ADMIN section, hosted by the shell (see below)
theme.js            the skin seam: injects a theme resource's theme.css last (nui-theming.md)
renderer-loader.js  the renderer seam: dynamic-imports Config.InventoryRenderer's factory
main.js             the import list (= load order) + two DOM listeners
```

## The rules that keep it clean

- **`core/` is DOM-free.** Enforced by grep: `grep -n "document\.\|getElementById" html/js/core/*.js`
  must return nothing. The wire asks the seated renderer through its interface instead.
- **A module registers its own actions**: `NuiRouter.register('actionName', fn)` in the
  file that owns the feature. The two central artifacts — main.js's import list and
  index.html's stylesheet `<link>` block — carry no logic.
- **Keyboard handling is a scope registry**: `NuiRouter.registerKeyScope({ name, priority,
  isOpen, onKey })` — the first open scope consumes the key. Canonical priorities are
  documented in router.js's header; slot new panels between existing numbers. Do NOT
  handle keys with your own `document.addEventListener('keydown', …)` in a panel module —
  it bypasses the priority chain, and your Escape will fire even while a higher-priority
  panel (or the character creator's swallow-all scope) is open on top of you.
- **A controller rides the same scopes**: `onNav(nav, mods)` takes the pad's intents
  (`'up'`, `'select'`, `'back'`, `'buttonX'`... — `mods.rb` is true when RB is held under the
  press), `analog: true` + `onAnalog(a)` takes the sticks as numbers, and `padHints` draws
  the hint strip (a hint's button may be a list: `[['rb', 'a'], 'Quick move']`). A scope with
  no `onNav` is left to the keyboard and mouse. router.js and controller.js have the details;
  inventory.js's CONTROLLER section is the fullest example.
- **No inline `on*=` handlers, ever.** Panels install delegated listeners on their root —
  one per event kind they need (`click` on `data-action`, `change` on `data-change`,
  `input` on `data-input`) — and dispatch through a Map. Params ride `data-*` attributes
  and are **cast in the binder** (`Number(el.dataset.slot)`) — datasets are always
  strings, and an uncast id will fail `===` against the numeric id in your state. See
  creator.js's `bindCreatorActions` for the reference shape.
- **Imported state is read-only.** `inv`/`shop` are objects, so property assignment works
  from anywhere; a module that needs to *replace* an exported `let` calls the owning
  module's setter or owns the binding itself.
- **XSS boundary**: developer-authored display strings (context-option icons/labels,
  meta-field labels, registered slot defs) may pass through `decodeTextEntities`;
  player-typed values render via `textContent`, exactly as typed, always.
- **Write 2022-safe CSS** (CEF is Chromium 103) and take every repeated value from a
  base.css token.

## Adding a new panel

First decide WHICH KIND of panel it is:

- **A player-facing surface** (something regular players see) → a free-standing module,
  recipe below.
- **An admin/dev tool** → a SECTION of the /whip panel. Never a new free-standing
  overlay: the fourteen that used to exist each reinvented chrome, zoom, focus, close
  paths and Escape, and every one of those was a recurring bug class.

### Adding a /whip SECTION

1. A module in `html/js/wp/<section>.js`:

   ```js
   import { WhipPanel, WP } from '../whip-panel.js';
   import { nuiCallback } from '../utils.js';

   WhipPanel.registerSection({
       id: 'mytool',            // stable key; must match the Lua side
       group: 'world',          // players | vehicles | economy | world | system
       label: 'My Tool',
       order: 40,               // position within the group
       render(root)   { /* build the skeleton ONCE with the WP helpers */ },
       onData(kind, payload) { /* wpSectionData messages for this id */ },
       onEscape()     { /* return true if you consumed it (closed a drill-down) */ },
       actions: { myAction: (el) => { /* data-action dispatch, shell-delegated */ } },
   });
   ```

   Build DOM with the `WP` helpers (`el/listItem/group/field/input/select/btn/toolbar/
   empty/confirm`) and the `wp-*` classes in whip-panel.css — that IS the shared admin
   vocabulary; a section adds no stylesheet of its own. Data strings render via
   `textContent` (the helpers do this for you). NO `addEventListener` in a section —
   the shell's one delegated listener dispatches your `actions` map. NO key scope —
   the shell stages Escape and calls your `onEscape`.

2. The Lua half in `tools/panel_sections/<section>.lua`:

   ```lua
   PanelSections['mytool'] = {
       enter = function() TriggerServerEvent('spur_core:server:mtGetAll') end,
       leave = function() TriggerServerEvent('spur_core:server:mtClosed') end,
   }
   -- net-event handlers forward payloads into the section:
   RegisterNetEvent('spur_core:client:mtAllData', function(data)
       WhipPanelData('mytool', 'all', data)
   end)
   ```

   `enter`/`leave` fire when the section becomes/stops being the active one — leave is
   where viewer sessions end and world debris (blips, markers) is cleaned up. Flows
   that need the game screen wrap in `WhipPanelSuspend()`/`WhipPanelResume()` (or
   `WhipPanelConfirmFlow(fn)` for a UI.Confirm); flows that open the inventory call
   `WhipPanelClose()` instead.

3. Add `./wp/<section>.js` to main.js's import list. The manifest globs
   (`html/js/wp/*.js`, `tools/panel_sections/*.lua`) pick both files up.

### Adding a player-facing panel

1. Markup in index.html (`data-action` attributes, no inline handlers). Styling in its own
   css file, built from tokens — **and a `<link>` for it in index.html's stylesheet block**
   (the manifest globs serve the file, but the page hand-lists its sheets; base.css must
   stay first, yours goes anywhere after).
2. A module in `html/js/`: state, renderers, a delegated binder on the panel root,
   `NuiRouter.register(...)` for its messages, `registerKeyScope` if Escape should close it.
3. Add the module to main.js's import list.

That's all three edits: the css `<link>`, the module file, the import line. The manifest
needs nothing — its globs pick both files up.

## Verification

`node --check` every touched file before restarting — the js folder's package.json makes
node parse ESM. One module's syntax error fails the whole graph, which is exactly why the
check is a hard gate. (That package.json is deliberately NOT in the manifest's files —
it exists for node, not for the browser.)
