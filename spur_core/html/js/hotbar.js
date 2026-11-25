// ========================================
// HOTBAR — pocket slots 1-5 (inventory.css HOTBAR has the look)
// ========================================
//
// A capsule of five discs on the player capsule's row. Tab shows it while held; a 1-5 key uses a slot
// and shows it for a second with that slot lit. While the hint capsule (ui.js §9: a bar, a mode) is up
// at the bottom, the discs join that capsule instead of drawing a second one on the same spot: the
// segment (#hotbar-seg) moves into it, and back home when either goes.

import { NuiRouter } from './router.js';
import { setItemImage } from './utils.js';
import { invItemDefs } from './core/item-defs.js';
import { inv, invRegisterHotbarHooks } from './core/inv-state.js';

const SHOW_MS = 1000;    // a tap or a used slot
const MERGE_MS = 320;    // the segment closing out of the hint capsule (css: max-width 0.3s)

const hotbarEl = document.getElementById('hotbar');
const homeEl = document.getElementById('hotbar-cap');
const segEl = document.getElementById('hotbar-seg');
const drawtextEl = document.getElementById('ui-drawtext');

let hideTimer = null;
let shown = false;       // the player wants it on screen
let mergedCap = null;    // the hint capsule the segment sits in, while it does

function slotEl(n) {
    return segEl.querySelector(`.hb-slot[data-slot="${n}"]`);
}

// Sync the discs with pocket slots 1-5 (from the data store)
function syncHotbar() {
    for (let i = 1; i <= 5; i++) {
        const el = slotEl(i);
        const core = el && el.querySelector('.hb-core');
        if (!core) continue;

        const slotData = inv.state.player && inv.state.player[String(i)];
        const def = slotData && invItemDefs[slotData.item];

        // UNCHANGED SLOTS ARE LEFT ALONE, keyed on the same item|amount signature refreshSlotVisuals uses.
        const sig = def ? `${slotData.item}|${slotData.amount || 1}` : '';
        if (el.dataset.sig === sig) continue;
        el.dataset.sig = sig;

        core.innerHTML = '';
        const oldCount = el.querySelector('.hb-count');
        if (oldCount) oldCount.remove();
        el.classList.remove('no-art');   // the new picture's load says again
        el.classList.toggle('empty', !def);
        if (!def) continue;

        const img = document.createElement('img');
        img.alt = def.name || slotData.item;
        img.className = 'hb-img';
        img.draggable = false;
        // NO PICTURE (as the inventory's slots): one that fell back to missing.png marks the disc .no-art,
        // the outline glyph instead of a "?".
        img.addEventListener('load', () => {
            el.classList.toggle('no-art', /(^|\/)missing\.png$/.test(img.getAttribute('src') || ''));
        });
        setItemImage(img, slotData);   // the picture its state picks, as the inventory's slots do
        core.appendChild(img);

        // HOW MANY ARE LEFT, the question the hotbar answers mid-fight ("have I got a bandage?"): a stack's
        // count with the dim "×", and money always, as money ("$7,920").
        const amount = Number(slotData.amount) || 1;
        const money = def.type === 'currency';
        if (money || amount > 1) {
            const countEl = document.createElement('span');
            countEl.className = money ? 'hb-count money' : 'hb-count';
            countEl.textContent = (money ? '$' : '') + amount.toLocaleString('en-US');
            el.appendChild(countEl);
        }
    }
}

/** The hint capsule, while one is up at the bottom (ui.js §9 sets data-shown). */
function bottomHintCap() {
    if (!drawtextEl || drawtextEl.dataset.shown !== '1' || !drawtextEl.classList.contains('ui-drawtext-bottom')) return null;
    return drawtextEl.querySelector('.dt-cap');
}

/** Back into its own capsule at once: the hint capsule it sat in went, moved to the top, or was replaced. */
function goHome() {
    segEl.classList.remove('open');
    if (mergedCap) mergedCap.classList.remove('hb-merged');
    mergedCap = null;
    if (segEl.parentNode !== homeEl) homeEl.appendChild(segEl);
}

/** Into the hint capsule, opening from nothing. Its own capsule goes without a fade, so no empty glass
 *  lingers over the merged one. */
function merge(cap) {
    if (hotbarEl.classList.contains('visible')) {
        hotbarEl.classList.add('instant');
        hotbarEl.classList.remove('visible');
        requestAnimationFrame(() => hotbarEl.classList.remove('instant'));
    }
    if (segEl.parentNode !== cap) {
        segEl.classList.remove('open');
        cap.appendChild(segEl);
        void segEl.offsetWidth;   // start the opening from max-width 0
    }
    cap.classList.add('hb-merged');
    segEl.classList.add('open');
    mergedCap = cap;
}

/** Where it should be now: in the hint capsule if one is up at the bottom, else in its own. */
function place() {
    const cap = bottomHintCap();
    if (mergedCap && mergedCap !== cap) goHome();
    if (!shown) {
        hotbarEl.classList.remove('visible');
        return;
    }
    if (cap) {
        merge(cap);
        return;
    }
    // Its own capsule. The segment may still be closing out of a hint capsule (hideHotbar): fetch it now.
    if (segEl.parentNode !== homeEl) {
        segEl.classList.remove('open');
        homeEl.appendChild(segEl);
    }
    hotbarEl.classList.add('visible');
}

// The hint capsule came, went, moved or was redrawn inside (a redraw drops the segment out of it).
if (drawtextEl) {
    drawtextEl.addEventListener('whip:drawtext', () => {
        const cap = bottomHintCap();
        if (mergedCap && cap === mergedCap && segEl.parentNode !== cap) {
            cap.appendChild(segEl);   // the same capsule redrawn: back in, already open
            return;
        }
        if (shown || mergedCap) place();
    });
}

function clearHideTimer() {
    if (hideTimer) {
        clearTimeout(hideTimer);
        hideTimer = null;
    }
}

function showHotbar() {
    if (inv.open) return;
    syncHotbar();
    shown = true;
    place();
}

function hideHotbar() {
    clearHideTimer();
    shown = false;
    if (mergedCap) {
        // Close the seam: the segment shrinks out of the hint capsule, which stays, then goes home.
        const cap = mergedCap;
        mergedCap = null;
        cap.classList.remove('hb-merged');
        segEl.classList.remove('open');
        // (Not "still in cap": a redraw of the hint capsule's inside can have dropped it out already.)
        setTimeout(() => {
            if (!shown && !mergedCap && segEl.parentNode !== homeEl) homeEl.appendChild(segEl);
        }, MERGE_MS);
    } else {
        hotbarEl.classList.remove('visible');
    }
    setTimeout(() => {
        if (shown) return;
        for (let i = 1; i <= 5; i++) {
            const el = slotEl(i);
            if (el) el.classList.remove('active');
        }
    }, MERGE_MS);
}

// Tap: show briefly
function tapHotbar() {
    if (inv.open) return;
    showHotbar();
    clearHideTimer();
    hideTimer = setTimeout(hideHotbar, SHOW_MS);
}

// Hold: show until released
function holdHotbar() {
    if (inv.open) return;
    clearHideTimer();
    showHotbar();
}

function releaseHotbar() {
    hideHotbar();
}

// A slot used: lit until the hotbar goes, and shown for a second if it was not already
function useHotbarSlot(n) {
    if (inv.open) return;
    if (n < 1 || n > 5) return;
    const used = slotEl(n);
    if (!used) return;

    const wasHidden = !shown;
    for (let i = 1; i <= 5; i++) {
        const el = slotEl(i);
        if (el) el.classList.toggle('active', el === used);
    }
    showHotbar();

    if (wasHidden || hideTimer) {
        clearHideTimer();
        hideTimer = setTimeout(hideHotbar, SHOW_MS);
    }
}

// The against-the-grain call direction (inventory -> hotbar) goes through the shared hook
// registry — see core/inv-state.js. inventory.js never names these functions directly.
invRegisterHotbarHooks({
    syncHotbar: syncHotbar,
    hideHotbar: hideHotbar,
});


// ROUTER REGISTRATION — see router.js's header.
NuiRouter.register('holdHotbar', () => holdHotbar());
NuiRouter.register('tapHotbar', () => tapHotbar());
NuiRouter.register('releaseHotbar', () => releaseHotbar());
NuiRouter.register('useHotbarSlot', (d) => useHotbarSlot(d.slot));
