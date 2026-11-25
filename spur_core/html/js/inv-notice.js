/* ========================================
   NOTICES IN A SCREEN'S HEADER — the inventory's pockets, and the /whip panel

   A notice's home is the player capsule (ui.js §1), which these screens hide; the stack at the top
   right was the fallback, away from where the player is looking, and under the /whip panel (z 9500 over
   950) not seen at all. While one of them is up, a notice shows in its header instead, as the shop
   screen's talk rows show a /me (js/shop-talk.js, the same capsule and classes): the notice's coloured
   disc with its mark (the player capsule's notification bubble), its words opening beside it.

       the pockets   between the name and the weight, centred      #inv-notice-row (index.html)
       /whip         at the header's right, beside the close       #wp-notice-row (whip-panel.js)
       the builder   at the top of the screen, in the middle       #fz-notice-row (index.html: the furnisher's)

   ONE AT A TIME, as the player capsule does: the next waits, and a notice with another waiting goes after
   2 seconds instead of its full time. A notice older than 8 seconds by its turn is dropped (it describes
   a drag long finished). A notice whose screen has gone by its turn goes back to ui.js, which shows it
   where it now can.
   ======================================== */

import { inv } from './core/inv-state.js';

const NEXT_MS = 2000;      // a notice's time when another is waiting
const STALE_MS = 8000;     // ui.js's NOTIF_MAX_STALE_MS
const FOLD_MS = 400;       // the words folding back before the capsule fades (css: width 0.4s)
const SWAP_MS = 150;       // the old words fade before the new ones are written (as shop-talk.js)

const pocketsEl = document.getElementById('inv-player-panel');
const panelOverlay = document.getElementById('whip-panel-overlay');
const furnisherEl = document.getElementById('furnisher');

/** The headers, first match wins. /whip first: it draws over everything, the inventory included. The
 *  panel's row is rebuilt with the panel (whip-panel.js buildSkeleton), so it is looked up each time. */
const HOSTS = [
    {
        row: () => document.getElementById('wp-notice-row'),
        measure: () => document.getElementById('wp-notice-measure'),
        up: () => !!panelOverlay && panelOverlay.style.display !== 'none' && panelOverlay.style.display !== ''
            && !panelOverlay.classList.contains('wp-suspended'),
    },
    {
        // The world builder and the furnisher (js/furnisher.js), while open: at the top in the middle (its saves).
        row: () => document.getElementById('fz-notice-row'),
        measure: () => document.getElementById('fz-notice-measure'),
        up: () => !!furnisherEl && furnisherEl.classList.contains('fz-open'),
    },
    {
        row: () => document.getElementById('inv-notice-row'),
        measure: () => document.getElementById('inv-notice-measure'),
        // A shop's goods take the pockets' place: a notice then goes to the shop's talk row (ui.js).
        up: () => inv.open && !!pocketsEl && pocketsEl.offsetParent !== null,
    },
];

const queue = [];          // [{ text, type, duration, glyph, color, at }]
let current = null;
let host = null;           // { row, measure } the current notice is on
let shownAt = 0;
let timer = 0;
let swapTimer = 0;
// Each header's fold, by its row: the end of a notice takes its disc away FOLD_MS later. One per header, so a
// notice starting on another header in that time never cancels this one's (its disc stayed, wordless and red
// or green, for good: Josh).
const foldTimers = new Map();
let fallback = null;

/** Where a notice goes when no header can take it any more (ui.js's uiNotify). */
export function setHeaderNoticeFallback(fn) {
    fallback = fn;
}

/** The header that can show a notice now, as { row, measure }, or null. */
function liveHost() {
    for (const h of HOSTS) {
        if (!h.up()) continue;
        const row = h.row();
        const measure = h.measure();
        if (row && measure && row.isConnected) return { row, measure };
    }
    return null;
}

/** Can a header show a notice now. */
export function headerNoticeAvailable() {
    return liveHost() !== null;
}

/** A line's width: its words measured at the row's own size, so the capsule grows to fit them. */
function widthFor(h, text) {
    h.measure.textContent = text;
    return h.measure.offsetWidth + 2;
}

function parts(row) {
    return { mark: row.querySelector('.inv-talk-pic'), text: row.querySelector('.inv-talk-text') };
}

function write(h, n) {
    const p = parts(h.row);
    p.mark.innerHTML = n.glyph || '';
    h.row.style.setProperty('--notice-color', n.color || 'var(--ui-info)');
    p.text.textContent = n.text;
    p.text.style.width = widthFor(h, n.text) + 'px';
    // A success's edge and ring green, an error's red, as the shop screen colours a sale and a refusal.
    h.row.classList.toggle('sale', n.type === 'success');
    h.row.classList.toggle('refused', n.type === 'error');
}

function fold(h) {
    clearTimeout(swapTimer);
    if (!h) return;
    const row = h.row;
    clearTimeout(foldTimers.get(row));
    row.classList.remove('talking', 'swapping');
    parts(row).text.style.width = '';
    foldTimers.set(row, setTimeout(() => {
        foldTimers.delete(row);
        row.classList.remove('shown', 'sale', 'refused');
    }, FOLD_MS));
}

function show(h, n) {
    clearTimeout(swapTimer);
    // This header was folding away: it shows again instead (another header's fold carries on).
    clearTimeout(foldTimers.get(h.row));
    foldTimers.delete(h.row);
    // A different header from the last notice's (the panel opened over the inventory): fold that one.
    if (host && host.row !== h.row) fold(host);
    host = h;
    if (!h.row.classList.contains('talking')) {
        write(h, n);
        h.row.classList.add('shown', 'talking');
        return;
    }
    h.row.classList.add('swapping');
    swapTimer = setTimeout(() => {
        write(h, n);
        h.row.classList.remove('swapping');
    }, SWAP_MS);
}

/** When the current notice goes: its own time, or 2 seconds if another is waiting (from when it showed). */
function schedule() {
    clearTimeout(timer);
    const full = Math.max(500, Number(current.duration) || 3000);
    const wait = (queue.length ? Math.min(NEXT_MS, full) : full) - (Date.now() - shownAt);
    timer = setTimeout(next, Math.max(0, wait));
}

function next() {
    timer = 0;
    current = null;
    while (queue.length) {
        const n = queue.shift();
        if (Date.now() - n.at > STALE_MS) continue;
        const h = liveHost();
        if (!h) {
            // Its screen closed while it waited: back to ui.js, which shows it in the player capsule, the
            // shop's talk row or the stack.
            fold(host);
            host = null;
            if (fallback) fallback({ text: n.text, type: n.type, duration: n.duration });
            continue;
        }
        current = n;
        shownAt = Date.now();
        show(h, n);
        schedule();
        return;
    }
    fold(host);
    host = null;
}

/** Show a notice in a header: `{ text, type, duration, glyph, color }` (ui.js gives the type's mark and
 *  colour). */
export function showHeaderNotice(n) {
    if (!n || typeof n.text !== 'string' || n.text === '') return;
    queue.push(Object.assign({}, n, { at: Date.now() }));
    if (!current) next();
    else schedule();
}
