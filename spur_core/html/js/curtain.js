import { NuiRouter } from './router.js';
import { nuiCallback } from './utils.js';
import { logoMarkup, logoLight } from './logo-light.js';

// ========================================
// CURTAIN — a blackout Lua can wait on
//
// Two actions and one report back. Lua asks for the screen to be covered and
// then WAITS to be told it actually is, before it moves a camera or builds
// anything; when the new scene is ready it asks for the curtain to lift.
//
// The waiting is the point. A fixed sleep would be a guess about how long a
// fade takes, and a guess that is too short shows the player the journey. The
// transition itself is what reports, so the two sides cannot drift apart.
//
// The token exists because the player can click faster than a scene can be
// built. Every cover carries one, the ack carries it back, and Lua ignores an
// ack that is not the cover it is currently waiting on — so an ack from an
// abandoned journey cannot release the one that replaced it.
// ========================================

const el = document.getElementById('curtain');

// The token of the cover that still owes an ack, or null when nothing is owed.
let pending = null;

function setDuration(ms) {
    const n = Math.max(0, Number(ms) || 0);
    el.style.transitionDuration = n + 'ms';
    return n;
}

function reportCovered() {
    if (pending === null) return;
    const token = pending;
    pending = null;
    nuiCallback('curtainCovered', { token: token });
}

/**
 * Report a cover only once the browser has actually PAINTED it.
 *
 * Adding a class does not put anything on screen — it schedules a style change that the
 * compositor applies on a later frame. Reporting in the same task therefore tells Lua the screen
 * is black while it demonstrably is not, and Lua acts on that immediately: it clears the game's
 * screen fade, which until that moment was the thing actually holding the blackout. For a frame
 * or two neither one is black and the scene being torn down is on screen.
 *
 * That is the flash of the character screen on the way into the world. It only showed on the
 * first load after a resource restart because a cold browser takes longer to get its first paint
 * out; once warm, the paint lands in the same frame and the gap closes on its own.
 *
 * Two frames, because one is not enough: the first callback runs before the pending change is
 * composited, the second after. The timeout is a backstop for the case rAF is not running at all
 * — better a late ack than none, and Lua's own deadline is the layer below that.
 */
function reportCoveredAfterPaint(token) {
    const fire = () => { if (pending === token) reportCovered(); };
    requestAnimationFrame(() => requestAnimationFrame(fire));
    setTimeout(fire, 100);
}

NuiRouter.register('curtainCover', (d) => {
    if (!el) return;
    const token = (d && d.token !== undefined) ? d.token : 0;

    // A REPEAT OF THE COVER ALREADY RUNNING. Lua re-sends the request every few hundred
    // milliseconds until it is answered, because on a fresh connect this page is often still
    // loading when the first one goes out and a message with nothing listening is dropped
    // outright. Once it HAS landed, the repeats must do nothing: restarting the transition would
    // stutter it, and falling through to the hand-ack below would report a fade finished while
    // it was still halfway down.
    if (pending === token) return;

    pending = token;

    const ms = setDuration(d && d.ms);
    const already = el.classList.contains('covered');

    // A transition only fires transitionend when something actually changes.
    // Covering an already-covered curtain, or covering instantly, both have to
    // report by hand or Lua would wait out its timeout for a screen that is
    // already black.
    //
    // AFTER A PAINT, not immediately — see reportCoveredAfterPaint. This is the
    // path Lua uses for the instant handovers between its two blackouts, which
    // is precisely where claiming black a frame early is visible. The animated
    // path below does not need it: transitionend cannot fire until the
    // transition has run, which means frames have already been composited.
    if (already || ms === 0) {
        el.classList.add('covered');
        reportCoveredAfterPaint(token);
        return;
    }

    // Reading a layout property flushes the pending style change, so a cover
    // issued in the same frame as an uncover still animates instead of the two
    // collapsing into no change at all.
    void el.offsetWidth;
    el.classList.add('covered');
});

NuiRouter.register('curtainUncover', (d) => {
    if (!el) return;
    // Nothing is owed once the curtain is on its way up; a late ack from the
    // cover that preceded it would be answering a question nobody is asking.
    pending = null;
    setDuration(d && d.ms);
    el.classList.remove('covered');
});

if (el) {
    el.addEventListener('transitionend', (e) => {
        if (e.propertyName !== 'opacity') return;
        // Only the arrival at black is worth reporting — the lift is not
        // something anyone waits on.
        if (!el.classList.contains('covered')) return;
        reportCovered();
    });
}

// ========================================
// THE LOGO OVER THE BLACK
//
// While the screen is black for a load, whip's logo shows in full at the bottom right, its I's
// light running: the landing page's and the pause menu's logo (js/logo-light.js), placed by
// css/curtain.css.
//
// client/curtain.lua says when (NUI message `loadingLogo`, { on }): from the first Cover to the
// Uncover that ends the blackout, across the game's fade in between. That stretch is the loading, and
// only Lua sees all of it — the curtain element itself is lifted part way through the long loads.
//
// Notifications wait out a load (ui.js asks loadingNow, and onLoadingEnd lets them through): the
// HUD is under the black.
// ========================================

const logoEl = document.getElementById('loadLogo');
if (logoEl) logoEl.innerHTML = logoMarkup('load-clip');
const light = logoLight(logoEl);

/** The light stops once the logo has faded out (css/curtain.css, #loadLogo's 0.4s), not as it starts to. */
const LOGO_FADE_MS = 450;

let loading = false;
let stopTimer = null;
const endListeners = [];

NuiRouter.register('loadingLogo', (d) => {
    const on = !!(d && d.on);
    if (on === loading) return;
    loading = on;
    clearTimeout(stopTimer);
    if (logoEl) logoEl.classList.toggle('shown', on);
    if (on) {
        light.start();
        return;
    }
    stopTimer = setTimeout(() => light.stop(), LOGO_FADE_MS);
    for (let i = 0; i < endListeners.length; i++) {
        try { endListeners[i](); } catch (e) { console.error('[curtain] onLoadingEnd:', e); }
    }
});

/** Is the screen black for a load right now? */
export function loadingNow() {
    return loading;
}

/** Run `fn` each time a load ends. */
export function onLoadingEnd(fn) {
    if (typeof fn === 'function') endListeners.push(fn);
}
