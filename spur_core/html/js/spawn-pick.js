import { NuiRouter } from './router.js';
import { nuiCallback } from './utils.js';
import { PauseMap, whenMap3D, holdMap3D, letGoMap3D } from './pause-map.js';

// ========================================
// THE SPAWN PICKER — whip's side of the page
// ========================================
//
// After Play, the character screen's camera looks up and the 3D map comes down over it, and the player picks
// where to arrive (client/charselect.lua, "The spawn picker"). The picker itself is the map's own module,
// js/map3d/spawnselect.js (SpawnSelect: the map's edge, the list, the pin, the camera moves, the fade into the
// arrival). This file only hosts it:
//
//   spawnselWarm        the map is built and the module loaded (from the welcome screen on), and Lua is told it can
//                       (spawnselCan { ok: true }); a module or a map that cannot load tells it it cannot ({ ok:
//                       false }), and Lua has the fade. Lua holds the character screen back until it has heard.
//   spawnsel:*          Lua's messages, handed to the module as they come (open, closing, ready, started, cam, abort)
//   the module's calls  to Lua as NUI callbacks of the same names; on spawnsel:done the map is released
//   the 3D map          the picker's alone from open to done (holdMap3D): the minimap waits, and draws again after
//   the name strip      away while the picker is up, back when it has rolled up again
//   the keys            a scope above the character screen's, while the picker is open

const OWNER = 'spawnsel';

// The opening, from Play to the pin standing on the place, in 1.5 s all told (Josh, 31 Oct): the picker's own timings
// (look up 1500 + settle 1600 + pin drop 620 = 3720 ms) at 2.48 times the speed: 605 + 645 + 250. The look up is Lua's
// (CharSelect.PAN, which the map's edge and slide follow); these are the rest of it.
const OPENING_SPEED = 2.48;
const OPENING = ['settleMs', 'settleMaxMs', 'listAfter', 'pinDropMs'];

function openingTuning(defaults) {
    const out = {};
    for (const k of OPENING) if (Number.isFinite(defaults && defaults[k])) out[k] = Math.round(defaults[k] / OPENING_SPEED);
    return out;
}

let picker = null;        // the SpawnSelect, once loaded
let warming = false;
let closing = false;      // Back was answered: the strip comes back when the map has rolled up

function root() {
    let el = document.getElementById('spawnsel');
    if (!el) {
        el = document.createElement('div');
        el.id = 'spawnsel';
        document.body.appendChild(el);
    }
    return el;
}

function uiScale() {
    return parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--ui-scale')) || 1;
}

function stripAway(away) {
    const app = document.getElementById('app');
    if (app) app.classList.toggle('cs-away', away);
}

/** The module's calls to Lua. done is the map gone: faded off the arrival, rolled up, or sent away; or (failed) it
 *  could not open, and the strip comes straight back for the old way. */
function toGame(name, data) {
    if (name === 'spawnsel:done') {
        PauseMap.release();
        letGoMap3D(OWNER);
        if (closing || (data && data.failed)) { closing = false; stripAway(false); }
    }
    nuiCallback(name, data || {});
}

function warm() {
    if (picker) { nuiCallback('spawnselCan', { ok: true }); return; }
    if (warming) return;
    warming = true;
    if (!document.querySelector('link[data-spawnsel]')) {
        const css = document.createElement('link');
        css.rel = 'stylesheet';
        css.href = 'css/spawnselect.css';
        css.dataset.spawnsel = '1';
        document.head.appendChild(css);
    }
    // A map that cannot be built says so (pause-map.js logs why): Lua keeps the fade.
    whenMap3D((map) => {
        import('./map3d/spawnselect.js').then((mod) => {
            picker = new mod.SpawnSelect(root(), { map, nui: toGame, scale: uiScale,
                tuning: openingTuning(mod.SPAWNSEL_TUNING) });
            nuiCallback('spawnselCan', { ok: true });
        }).catch((e) => {
            warming = false;
            console.error('[spawn picker] js/map3d/spawnselect.js did not load; Play keeps the fade:', e);
            nuiCallback('spawnselCan', { ok: false });
        });
    }, () => {
        warming = false;
        nuiCallback('spawnselCan', { ok: false });
    });
}

NuiRouter.register('spawnselWarm', warm);

NuiRouter.register('spawnsel:open', (d) => {
    if (!picker) return;
    closing = false;
    stripAway(true);
    holdMap3D(OWNER);
    picker.open(d);
});
NuiRouter.register('spawnsel:closing', (d) => {
    if (!picker) return;
    closing = true;
    picker.closing(d);
});
NuiRouter.register('spawnsel:ready', (d) => { if (picker && picker.ready) picker.ready(d); });
NuiRouter.register('spawnsel:started', (d) => { if (picker) picker.started(d); });
NuiRouter.register('spawnsel:cam', (d) => { if (picker && picker.cam) picker.cam(d); });
NuiRouter.register('spawnsel:abort', () => {
    if (picker) picker.abort();
    else nuiCallback('spawnsel:done', {});
});

// The character screen shown again (a refused load, a fresh list): the strip is back whatever the picker did.
for (const action of ['show', 'showCharacters', 'hide']) {
    NuiRouter.register(action, () => { closing = false; stripAway(false); });
}

// Above the character screen's own (priority 5), while the picker is open.
NuiRouter.registerKeyScope({
    name: 'spawn-select',
    priority: 4,
    isOpen: () => !!picker && picker.isOpen(),
    onKey: (e) => picker.key(e),
    onNav: (nav) => picker.nav(nav),
    padHintsLook: 'bare',   // Whiplash's look, under the list, as on the character screen (css/ui.css)
    padHints: () => picker.padHints(),
});
