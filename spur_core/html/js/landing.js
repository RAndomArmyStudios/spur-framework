import { NuiRouter } from './router.js';
import { nuiCallback } from './utils.js';
import { logoMarkup, logoLight } from './logo-light.js';

/* ========================================
   LANDING PAGE — the logo over a camera shot, waiting for a press

   Between the loading screen and the character screen, on joining. client/landing.lua puts the
   camera up and says when (`landingShow`, `landingHide`); this runs the logo's light and listens.

   THE LIGHT IS THE LOADING SCREEN'S (spur_loadingscreen/html/js/logo.js): the four circles in the
   bar under the letters light one at a time, each at once and with a random interaction icon on it, and
   fade as the light moves on. The icons come from js/glyphs.js, all but NOT_LIT's (js/logo-light.js).

   ANY BUTTON: a key, a mouse button, or a pad button. Keys and pad buttons arrive through a key
   scope (router.js) — a pad reaches the page through client/controller.lua only for a scope with
   onNav. Mouse buttons are heard on the layer itself. Keys that are not a deliberate press are
   ignored: modifiers on their own, a key held down from before, Alt-Tab and the F keys (F8 is the
   console).
   ======================================== */

const root = document.getElementById('landing');
const prompt = root ? root.querySelector('.ld-prompt') : null;

/* ---- The light: runs only while the page is up (js/logo-light.js, shared with the pause menu) ---- */

// RedM (spur_core, 23 Nov 2026): the logo is built here (the SPUR wordmark), before the light looks for its circles.
const logoEl = root ? root.querySelector('.ld-logo') : null;
if (logoEl) logoEl.innerHTML = logoMarkup('ld-clip');
const light = logoLight(root);
const startLight = () => light.start();
const stopLight = () => light.stop();

/* ---- Showing, and hearing the press ---- */

/** Up and waiting for a press. False again the moment one lands, so a second press does nothing. */
let waiting = false;

function carryOn() {
    if (!waiting) return;
    waiting = false;
    root.classList.add('leaving');
    nuiCallback('landingContinue', {});
}

NuiRouter.register('landingShow', (d) => {
    if (!root) return;
    if (prompt && d && typeof d.prompt === 'string' && d.prompt !== '') prompt.textContent = d.prompt;
    root.classList.remove('leaving');
    root.classList.add('shown');
    waiting = true;
    startLight();
});

NuiRouter.register('landingHide', () => {
    if (!root) return;
    waiting = false;
    root.classList.remove('shown', 'leaving');
    stopLight();
});

/** Keys that are not a press of their own. */
const NOT_A_PRESS = new Set([
    'Alt', 'AltGraph', 'Control', 'Shift', 'Meta', 'OS', 'CapsLock', 'NumLock', 'ScrollLock',
    'ContextMenu', 'PrintScreen', 'Unidentified',
]);

NuiRouter.registerKeyScope({
    name: 'landing',
    priority: 3,   // between ui-dialog (1) and character-select (5); see router.js
    isOpen: () => waiting,
    onKey: (e) => {
        if (e.repeat || e.altKey || e.metaKey) return;
        if (NOT_A_PRESS.has(e.key) || /^F\d{1,2}$/.test(e.key)) return;
        e.preventDefault();
        carryOn();
    },
    // Any pad button: whatever the bridge sends is a press.
    onNav: () => carryOn(),
});

if (root) {
    root.addEventListener('mousedown', (e) => {
        if (!waiting) return;
        e.preventDefault();
        carryOn();
    });
}
