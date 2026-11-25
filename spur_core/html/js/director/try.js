// ============================================================
// TRYING A CARD HERE — Skill Check's ring and Progress's bar, as a player gets them
// ============================================================
//
// The page's own ring and bar (ui.js), started through the router as client/ui.lua starts them, under an id
// no Lua call gave out: their answer goes to Lua as ever, which has no one waiting for it and lets it go
// (client/ui.lua uiResult). Nothing in the game happens. In the game the ring's dot is moved by the hands
// the game reads; here the editor has the cursor, so the page's own mouse moves it. Esc stops either.

import { NuiRouter } from '../router.js';

// Page px to the game's mouse look (the numbers the ring is given in the game): about as far a move.
const MOUSE = 1 / 140;

let n = 0;
let trying = null;   // { stop }: the one going now

function stopTrying() {
    if (trying) trying.stop();
}

/** Take Esc while one is going: it stops it, and nothing else on the page hears it. */
function escStops(id) {
    const key = (ev) => {
        if (ev.key !== 'Escape') return;
        ev.preventDefault();
        ev.stopPropagation();
        NuiRouter.dispatch({ action: 'uiCancel', id });
    };
    document.addEventListener('keydown', key, true);
    return () => document.removeEventListener('keydown', key, true);
}

/** Play the ring at a difficulty's settings (`level`, as SkillCheckLevel makes them). onDone(true: passed, false:
 *  missed, null: stopped). */
export function trySkillCheck(level, onDone) {
    stopTrying();
    const id = 'dr-try-' + (++n);
    const ring = document.getElementById('ui-skillcheck');
    let result = null, done = false;
    const move = (ev) => NuiRouter.dispatch({ action: 'uiSkillMouse', id, x: ev.movementX * MOUSE, y: ev.movementY * MOUSE });
    const unEsc = escStops(id);
    const end = () => {
        if (done) return;
        done = true;
        clearInterval(watch);
        document.removeEventListener('mousemove', move, true);
        unEsc();
        document.documentElement.classList.remove('dr-trying', 'dr-try-up');
        if (trying && trying.id === id) trying = null;
        // Still up (stopped from here): taken down, its answer let go as any other.
        if (ring && ring.style.display !== 'none') NuiRouter.dispatch({ action: 'uiCancel', id });
        if (onDone) onDone(result);
    };
    // How it went is read off the ring itself: lit whole (passed) or marked (missed), then gone.
    const watch = setInterval(() => {
        const box = ring && ring.firstElementChild;
        if (box && box.classList.contains('sk-done')) result = true;
        else if (box && box.classList.contains('sk-miss')) result = false;
        if (!ring || ring.style.display === 'none' || !box) end();
    }, 60);
    document.addEventListener('mousemove', move, true);
    // The pointer hidden (the dot is the mouse), and the ring over the editor (director.css).
    document.documentElement.classList.add('dr-trying', 'dr-try-up');
    trying = { id, stop: end };
    NuiRouter.dispatch({ action: 'uiSkillCheck', id, level });
}

/** Run the bar for its length: { label, seconds, canCancel }. */
export function tryProgress(o) {
    stopTrying();
    const id = 'dr-try-' + (++n);
    const unEsc = escStops(id);
    const ms = Math.max(1, Math.min(120, Number(o.seconds) || 8)) * 1000;
    const end = () => {
        clearTimeout(timer);
        unEsc();
        document.documentElement.classList.remove('dr-try-up');
        if (trying && trying.id === id) trying = null;
    };
    const timer = setTimeout(end, ms + 500);
    document.documentElement.classList.add('dr-try-up');   // the bar over the editor (director.css)
    trying = { id, stop: () => { NuiRouter.dispatch({ action: 'uiCancel', id }); end(); } };
    NuiRouter.dispatch({ action: 'uiProgressBar', id, label: o.label || 'Working...', duration: ms, canCancel: o.canCancel !== false });
}
