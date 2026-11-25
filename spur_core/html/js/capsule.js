/* ========================================
   THE CAPSULE — one element, three states.

   The player capsule at the bottom left shows one of three things, and this file is the only
   thing that decides which.

       .mode-stats      the gauges. The default, and what it falls back to.
       .mode-composer   a text field. Owned by composer.js.
       .mode-notify     a notification. Owned by ui.js.

   (A load shows whip's logo over the curtain, bottom right — js/curtain.js — not the capsule.)

   WHY A FILE OF ITS OWN RATHER THAN A FLAG IN status-hud.js.

   Three modules need this answer and two of them need to CHANGE it. status-hud.js owns the
   gauges, composer.js owns the input, ui.js owns notifications — and ui.js has to ask "is the
   capsule free?" before it routes a notification anywhere. If the state lived in any one of
   them, the other two would import it and the import graph would close a loop the first time
   the owner needed something back. A leaf that nobody imports FROM is the cheap way out.

   ARBITRATION, AND THE ONE RULE THAT MATTERS.

   The composer outranks notifications. A player mid-sentence must not have the field yanked out
   from under them because a pickup succeeded somewhere — so a notification arriving during a
   compose does not wait for a turn here, it is routed to the top-right stack by ui.js instead.
   That decision is made where the notification arrives, not here; this file only answers
   whether the capsule is free.
   ======================================== */

const MODES = ['stats', 'composer', 'notify'];

const container = document.getElementById('statusHudContainer');
const statusHud = document.getElementById('status-hud');

let _mode = 'stats';

// Called whenever the capsule goes back to the gauges — ui.js uses it to show the notifications
// that waited for it. See onCapsuleFree.
const _freeListeners = [];

/** Which state is the capsule in right now? */
export function capsuleMode() {
    return _mode;
}

/**
 * Put the capsule into a state.
 *
 * Every class is removed before the new one is added rather than toggled individually: a mode
 * is exclusive by definition, and a toggle-per-class version can leave two on at once the first
 * time somebody adds a fourth state and forgets a line.
 */
export function setCapsuleMode(mode) {
    if (!container) return;
    if (MODES.indexOf(mode) === -1) mode = 'stats';
    if (mode === _mode) return;

    // NOBODY CAN SEE IT, SO IT DOES NOT MORPH (.cap-snap, status-hud.css): a hidden HUD fading in
    // for the composer shows the field already there. Asked of the opacity on screen rather than
    // of the classes, so a HUD that is only starting to fade still counts as seen.
    const snap = !!statusHud && parseFloat(getComputedStyle(statusHud).opacity) < 0.02;
    if (snap) container.classList.add('cap-snap');

    // THE CAPSULE NEVER GETS NARROWER THAN THE STATS IT NORMALLY SHOWS, or a short notification
    // reads as the capsule being REPLACED rather than changing what it holds. Growing past it is fine.
    //
    // Measured, not hardcoded: the stats width depends on how many gauges are registered (satellites
    // add them at runtime) and on --ui-scale. Measured BEFORE the class changes, the only moment the
    // answer is there; a line later the gauges are collapsing. Everything is border-box (base.css), so
    // the figure round-trips into min-width exactly. Cleared on the way back so a removed gauge can
    // still shrink the capsule.
    if (_mode === 'stats' && mode !== 'stats') {
        container.style.minWidth = container.offsetWidth + 'px';
    } else if (mode === 'stats') {
        container.style.minWidth = '';
    }

    for (let i = 0; i < MODES.length; i++) {
        container.classList.remove('mode-' + MODES[i]);
    }
    container.classList.add('mode-' + mode);
    _mode = mode;

    // A TEXT FIELD MUST BE VISIBLE, EVEN WHEN THE HUD IS NOT. #status-hud fades out while a UI is
    // open or the player is dead (WhipRefreshHudVisibility in client/hud.lua), and chatting while
    // dead is normal: without this, T opens the composer into an invisible capsule that has the
    // keyboard. .mode-composer still hides the gauges, so only the field shows.
    //
    // Not for notifications: ui.js sends those to the top-right stack while the HUD is down.
    if (statusHud) statusHud.classList.toggle('composer-visible', mode === 'composer');

    if (snap) {
        void container.offsetWidth;                 // the new look lands with no transitions...
        container.classList.remove('cap-snap');     // ...and the next change animates again
    }

    if (mode === 'stats') {
        for (let i = 0; i < _freeListeners.length; i++) {
            try { _freeListeners[i](); } catch (e) { console.error('[capsule] onCapsuleFree:', e); }
        }
    }
}

/** Run `fn` every time the capsule goes back to the gauges. */
export function onCapsuleFree(fn) {
    if (typeof fn === 'function') _freeListeners.push(fn);
}

/**
 * Can the capsule take a notification right now?
 *
 * TWO QUESTIONS, NOT ONE, AND THE SECOND IS THE ONE THAT BITES. Being in stats mode is not
 * enough — the whole HUD is faded out whenever a UI is open or the player is dead
 * (client/hud.lua's WhipRefreshHudVisibility), and a notification put into an invisible capsule
 * is a notification nobody ever sees. The inventory's own drag-and-drop errors are exactly that
 * case: they fire while the inventory is open, which is precisely when the capsule is hidden.
 *
 * So ui.js asks this at ARRIVAL and sends anything that fails it to the top-right stack, which
 * is why that stack still exists and is not going anywhere.
 */
export function capsuleAvailable() {
    if (!container || !statusHud) return false;
    if (_mode !== 'stats') return false;
    return statusHud.classList.contains('visible');
}
