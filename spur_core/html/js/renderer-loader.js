// ========================================
// CUSTOM INVENTORY RENDERER LOADER — the seam's config half
//
// Config.InventoryRenderer (or the whip_inventory_renderer convar) names a resource; this loads
// `renderer.js` from it (dynamic import over the cfx-nui scheme — same cross-resource mechanism
// themes use) and seats whatever its factory returns in place of the default renderer. The wire
// layer never notices the swap: it keeps calling the same interface on whatever holds the seat.
//
// THE FACTORY CONTRACT (docs/nui-inventory.md has the full interface):
//
//     export default function createRenderer({ api, mount, close, addStylesheet, signal }) {
//         return { render() {...} };
//     }
//
// ONE METHOD IS ENOUGH. A renderer needs only `render()`: draw everything from `api.inv`. This file
// fills in every other method the wire calls (api.RENDERER_METHODS) with "render", coalesced to one
// call per turn, plus sensible answers for the questions (isMidDrag false, notify = whip's own
// toast). A renderer that gives any of those methods itself has its own called instead. A renderer
// of the first contract (all twenty methods, no render) still works as it is.
//
// `api` is a COPY of the core facade (core/inventory.js) for this renderer alone: its `events.on`
// and `setViewRenderHook` are undone when the renderer is swapped out. `mount` is
// #inv-custom-root — a bare div the custom UI owns completely, shown by whip while the inventory is
// open. `close` is the core's closeInventory (state teardown + pending-op discard + the server
// callback — a custom UI's close button must call THIS, never fake a close by hiding its own DOM).
// It is handed over here rather than re-exported by the facade because inv-wire imports the facade
// for the renderer seat — the loader sits above both, so passing it through keeps the module graph
// a DAG. `addStylesheet(path)` adds a stylesheet from the renderer's resource that leaves with it;
// `signal` aborts when it is swapped out (for listeners on document/window, timers).
//
// SWAPPED LIVE. `swapInventoryRenderer` (client/ready.lua: the /whip_inventory_ui developer command,
// and the renderer's resource restarting) closes the inventory, takes the old UI out — its mount
// emptied, its stylesheets removed, its subscriptions undone, its signal aborted, its destroy()
// called — and imports the new one under a fresh `?v=` so the browser cannot hand back the old
// module. The renderer's own imports keep their first version unless it adds that same `?v=` to
// them (the docs show how).
//
// FAILS SOFT, LOUDLY: a missing resource, a 404, a factory that returns garbage, or a renderer
// without render() and without the full interface leaves (or puts back) the default renderer and
// prints exactly what was wrong. A method that throws is caught and printed, and the wire carries
// on. A broken custom UI must degrade to whip's own, never to a dead inventory.
// ========================================

import { NuiRouter } from './router.js';
import * as core from './core/inventory.js';
import { closeInventory } from './core/inv-wire.js';
import { inv } from './core/inv-state.js';

// A RESOURCE NAME, NOTHING ELSE. The name is concatenated into the URL below, and a value such
// as `x.evil.com/p.js#` turned `https://cfx-nui-<name>/renderer.js` into a URL on somebody else's
// host — running their code inside spur_core's own page, with its origin. Letters, digits, `_` and
// `-` only; anything else is refused before a URL is built. Both messages below come only from
// spur_core's own client Lua, and only a resource the server runs answers at cfx-nui-<name>.
const RESOURCE_NAME = /^[A-Za-z0-9_-]{1,64}$/;

const TAG = '[spur_core:renderer]';

// The wire's methods a render-only renderer leaves to "render": every redraw, and the panel chrome.
const REDRAWS = [
    'renderAll', 'refreshSlots', 'renderWeights', 'renderGround', 'renderContainer', 'renderContainerInfo',
    'renderIgnition', 'renderPanelStack', 'renderPlayerInv', 'renderPlayerInvInfo', 'renderAccessories',
    'tagItemSlots', 'setPanels', 'flashPanels', 'cancelInteractions',
];
// Optional members the key scope (js/inventory.js) reads off the seat.
const INPUT = ['onKey', 'onNav', 'onAnalog', 'padHints'];

let seat = null;            // the custom UI drawing now: { resource, renderer, abort, links, own }
let attempt = 0;            // the newest load; an older one that finishes late is dropped
let configAnswered = false; // the configured UI is chosen once; a swap counts as the answer

const mountEl = () => document.getElementById('inv-custom-root');

/** Print a renderer's error, three times per method at most (a render that throws would flood F8). */
function reporter(resource) {
    const seen = {};
    return (method, err) => {
        seen[method] = (seen[method] || 0) + 1;
        if (seen[method] > 3) return;
        console.error(`${TAG} ${resource}: ${method}() threw — ${(err && err.stack) || err}`
            + (seen[method] === 3 ? ' (further errors from it are not shown)' : ''));
    };
}

/**
 * The renderer the wire sees: the renderer's own methods where it has them, the rest filled in.
 * Every call is caught, so a throwing method cannot cut the wire's sequence short.
 */
function complete(own, el, resource) {
    const hasRender = typeof own.render === 'function';
    if (!hasRender) {
        const missing = core.RENDERER_METHODS.filter((m) => typeof own[m] !== 'function');
        if (missing.length) {
            throw new Error('the renderer has no render() function (or it is missing '
                + missing.join(', ') + '): docs/nui-inventory.md');
        }
    }
    const report = reporter(resource);
    const call = (name, args, fallback) => {
        try { return own[name](...args); }
        catch (err) { report(name, err); return fallback; }
    };

    let queued = false;
    const renderSoon = () => {
        if (queued) return;
        queued = true;
        queueMicrotask(() => {
            queued = false;
            if (seat && seat.own === own) call('render', []);
        });
    };
    const has = (name) => typeof own[name] === 'function';

    const r = {
        // whip shows and hides the mount; the renderer's own show/hide runs on top.
        showOverlay() {
            el.hidden = false;
            if (has('showOverlay')) call('showOverlay', []);
            else renderSoon();
        },
        hideOverlay() {
            if (has('hideOverlay')) call('hideOverlay', []);
            el.hidden = true;
        },
        isMidDrag: () => (has('isMidDrag') ? call('isMidDrag', [], false) === true : false),
        hasPlayerGrid: () => (has('hasPlayerGrid') ? call('hasPlayerGrid', [], true) !== false : true),
        notify(text) {
            if (has('notify')) return call('notify', [text]);
            if (text && typeof window.uiNotify === 'function') window.uiNotify({ text, type: 'error', duration: 4000 });
        },
        drawsShop: own.drawsShop === true,
    };
    for (const name of REDRAWS) {
        r[name] = (...args) => (has(name) ? call(name, args) : renderSoon());
    }
    for (const name of INPUT) {
        if (has(name)) r[name] = (...args) => call(name, args, name === 'padHints' ? null : undefined);
    }
    return r;
}

/** A copy of the core facade for one renderer: its subscriptions and view hooks are its own. */
function apiFor(signal) {
    const viewHooks = {};
    const offs = [];
    const events = {
        on(name, fn) {
            const off = core.events.on(name, fn);
            offs.push(off);
            return off;
        },
    };
    const api = Object.assign({}, core, {
        events,
        setViewRenderHook(name, fn) { if (typeof fn === 'function') viewHooks[name] = fn; },
    });
    // The seat's own levers stay the loader's.
    delete api.registerRenderer;
    delete api.seatDefaultRenderer;
    signal.addEventListener('abort', () => { for (const off of offs) off(); });
    return { api, viewHooks };
}

/** Take the seated custom UI out and give whip's own renderer the seat. */
function unseat() {
    if (!seat) return;
    const old = seat;
    seat = null;
    core.seatDefaultRenderer();
    try { old.abort.abort(); } catch (_) { /* a listener threw */ }
    if (typeof old.own.destroy === 'function') {
        try { old.own.destroy(); } catch (err) { console.error(`${TAG} ${old.resource}: destroy() threw — ${err}`); }
    }
    for (const link of old.links) link.remove();
    const el = mountEl();
    if (el) {
        el.replaceChildren();
        el.removeAttribute('style');
        el.removeAttribute('class');
        el.hidden = true;
    }
}

/**
 * Import `resource`'s renderer.js and seat it, in place of whatever draws now.
 * @param {string} resource
 * @param {string} [version]  a fresh value for every live swap, so the import is not the cached module
 */
async function load(resource, version) {
    const my = ++attempt;
    const base = 'https://cfx-nui-' + resource + '/';
    const q = version ? '?v=' + encodeURIComponent(version) : '';
    let mod;
    try {
        mod = await import(base + 'renderer.js' + q);
    } catch (err) {
        if (my !== attempt) return;
        unseat();
        console.error(`${TAG} could not load renderer from "${resource}" — using whip's own inventory. `
            + `Is the resource started, and renderer.js in its files{}? (${err.message})`);
        return;
    }
    if (my !== attempt) return;   // a newer load began while this one was on the wire

    // Out with the old first: the new factory builds into an empty mount.
    if (inv.open) closeInventory();
    unseat();

    const el = mountEl();
    const abort = new AbortController();
    const links = [];
    const addStylesheet = (path) => {
        const url = new URL(String(path), base);
        if (version) url.searchParams.set('v', version);
        const link = document.createElement('link');
        link.rel = 'stylesheet';
        link.href = url.href;
        link.dataset.whipRenderer = resource;
        document.head.appendChild(link);
        links.push(link);
        return link;
    };
    const { api, viewHooks } = apiFor(abort.signal);
    try {
        if (typeof mod.default !== 'function') {
            throw new Error('renderer.js must `export default` a factory function');
        }
        el.hidden = true;
        const own = mod.default({ api, events: api.events, mount: el, close: closeInventory, addStylesheet, signal: abort.signal });
        if (!own || typeof own !== 'object') {
            throw new Error('the factory must return a renderer object');
        }
        const renderer = complete(own, el, resource);
        seat = { resource, renderer, abort, links, own };
        core.registerRenderer(renderer, viewHooks);
        console.log(`${TAG} custom inventory renderer active: ${resource}${version ? ' (reloaded)' : ''}`);
    } catch (err) {
        try { abort.abort(); } catch (_) { /* a listener threw */ }
        for (const link of links) link.remove();
        el.replaceChildren();
        el.hidden = true;
        console.error(`${TAG} could not start the renderer from "${resource}" — using whip's own inventory. `
            + `(${err.message})`);
    }
}

function nameOk(resource) {
    if (typeof resource === 'string' && RESOURCE_NAME.test(resource)) return true;
    console.error(`${TAG} refusing renderer resource name — not a plain resource name`);
    return false;
}

// The configured UI, at load and again at login (client/ready.lua). THE FIRST ANSWER SEATS, EVEN
// "NONE": the configuration is read once a page; changing it after that is a swap.
NuiRouter.register('setInventoryRenderer', (d) => {
    if (configAnswered) return;
    configAnswered = true;
    if (!d.resource) return;
    if (!nameOk(d.resource)) return;
    load(d.resource);
});

// A live change (client/ready.lua): another UI, the same one again from its newly restarted files,
// or none (whip's own).
NuiRouter.register('swapInventoryRenderer', (d) => {
    configAnswered = true;
    if (!d.resource) {
        attempt++;   // a load still on the wire must not land after this
        if (inv.open && seat) closeInventory();
        unseat();
        return;
    }
    if (!nameOk(d.resource)) return;
    load(d.resource, String(Date.now()));
});
