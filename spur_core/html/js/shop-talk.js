/* ========================================
   SHOP TALK ON THE SHOP SCREEN — the visit's /me lines in the header

   The shop screen covers the world, so the bubbles above the shopper and the keeper
   (server/shop_talk.lua) are behind it; the server sends the same lines here too.

   TWO ROWS, ONE EACH, TALKING INDEPENDENTLY, so two /me's at once both show. The shopper on top,
   the keeper under them: each a capsule like the player HUD's (css/status-hud.css), its face always
   showing — the shopper's portrait (the game's headshot, js/portrait.js), the keeper's picture the admin
   panel shows of its NPC, cropped to the head — and that one's line unfolding beside it as a HUD notice
   does from its disc, at the in-world bubble's proportions. A shop with no keeper has the one row.

   THE QUEUE, PER ROW: a line stays 2 seconds when that speaker has another waiting, 5 when it is
   their last; then the row folds back to the face.
   ======================================== */

import { NuiRouter } from './router.js';
import { pedImageUrl } from './utils.js';
import { myPortrait } from './portrait.js';

const NEXT_MS = 2000;   // a line's time when the same speaker has another waiting
const LAST_MS = 5000;   // their last line's time, before the row folds back
const SWAP_MS = 150;    // the old words fade before the new ones are written
const NOTICE_STALE_MS = 8000;   // ui.js's NOTIF_MAX_STALE_MS

const PERSON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true">'
    + '<circle cx="12" cy="7.5" r="3.5"/><path d="M5 21c0-4 3.1-7 7-7s7 3 7 7"/></svg>';

// THE ROWS' SIZE (the whole height between the panel's top and the goods, the capsule's proportions
// kept): a row is as tall as two of them fill that room, at most the in-world bubble's own 67px.
const EDGE = 10;      // CSS px kept clear of the panel's top edge, and of the chips or goods under the header
const GAP = 0.14;     // the gap between the rows, of a row's height (css/shops.css --talk-gap)
const MAX_H = 67;     // the HUD capsule's ring, and the /me bubble's height
const MIN_H = 28;

const root = document.getElementById('inv-shop-talk');
const stack = root.querySelector('.inv-talk-stack');
const measureEl = document.getElementById('inv-talk-measure');
const panelEl = document.getElementById('inv-shopfront');
const tabsEl = document.getElementById('inv-shop-tabs');
const gridEl = document.getElementById('inv-shop-grid');

/** One speaker's row and its own queue. */
function rowOf(id) {
    const el = document.getElementById(id);
    return {
        el,
        pic: el.querySelector('.inv-talk-pic'),
        mark: el.querySelector('.inv-talk-mark'),   // the shopper's row only: a notice's disc over the face
        text: el.querySelector('.inv-talk-text'),
        queue: [],        // [{ text, kind: 'sale' | 'refused' | null, notice?: { glyph, color, duration, at } }]
        current: null,    // the line showing, or null
        shownAt: 0,
        timer: 0,
        swapTimer: 0,
    };
}

const rows = { me: rowOf('inv-talk-me'), keeper: rowOf('inv-talk-keeper') };

let open = false;
let visit = 0;   // bumped by each open and close: a late portrait or timer for an old visit does nothing

/** A face's picture: `url` in the disc, the person glyph until it loads (and for good if it fails).
 *  The keeper's crops a full-length picture to the head (css/shops.css, #inv-talk-keeper). */
function setFace(r, url) {
    const pic = r.pic;
    pic.innerHTML = PERSON;
    pic.classList.remove('has-img');
    if (!url) return;
    const img = new Image();
    img.alt = '';
    img.onload = () => {
        pic.innerHTML = '';
        pic.appendChild(img);
        pic.classList.add('has-img');
    };
    img.src = url;
}

/** A line's width: its words measured at the row's own size, so the capsule grows to fit them (and
 *  shrinks between lines) rather than to a fixed width. The row is held short of the search; a line
 *  past that ends in an ellipsis. offsetWidth is in the element's own CSS pixels, the inventory's zoom
 *  (--ui-scale) already taken out, which is what style.width is written in. */
function widthFor(text) {
    measureEl.textContent = text;
    return measureEl.offsetWidth + 2;
}

/** A line on the row: its words, its width, and its colour — a sale's is the success green, a refusal's
 *  (not enough money) the error red. */
function write(r, line) {
    r.text.textContent = line.text;
    r.text.style.width = widthFor(line.text) + 'px';
    r.el.classList.toggle('sale', line.kind === 'sale');
    r.el.classList.toggle('refused', line.kind === 'refused');
    // A notice (ui.js, talkNotice): its disc over the face for its time; the face comes back after it.
    if (r.mark) {
        if (line.notice) {
            r.mark.innerHTML = line.notice.glyph || '';
            r.el.style.setProperty('--notice-color', line.notice.color || 'var(--ui-info)');
        }
        r.el.classList.toggle('noticing', !!line.notice);
    }
}

function show(r, line) {
    clearTimeout(r.swapTimer);
    if (!r.el.classList.contains('talking')) {
        write(r, line);
        r.el.classList.add('talking');
        return;
    }
    // Already open: the words change in place.
    r.el.classList.add('swapping');
    r.swapTimer = setTimeout(() => {
        write(r, line);
        r.el.classList.remove('swapping');
    }, SWAP_MS);
}

function fold(r) {
    clearTimeout(r.swapTimer);
    r.el.classList.remove('talking', 'swapping', 'sale', 'refused', 'noticing');
    r.text.style.width = '';
}

/** When the row's line goes: at 2 s if that speaker has another waiting, else at 5 s (both from when
 *  it showed); a notice that is the last, at its own time. */
function schedule(r) {
    clearTimeout(r.timer);
    const v = visit;
    const last = r.current && r.current.notice ? Math.max(500, Number(r.current.notice.duration) || 3000) : LAST_MS;
    const wait = (r.queue.length ? Math.min(NEXT_MS, last) : last) - (Date.now() - r.shownAt);
    r.timer = setTimeout(() => {
        if (v !== visit) return;
        if (r.queue.length) next(r);
        else { r.current = null; fold(r); }
    }, Math.max(0, wait));
}

function next(r) {
    // A notice older than ui.js's 8 seconds by its turn is dropped: it describes something long over.
    while (r.queue.length && r.queue[0].notice && Date.now() - r.queue[0].notice.at > NOTICE_STALE_MS) r.queue.shift();
    if (!r.queue.length) { r.current = null; fold(r); return; }
    r.current = r.queue.shift();
    r.shownAt = Date.now();
    show(r, r.current);
    schedule(r);
}

function reset(r) {
    r.queue = [];
    r.current = null;
    clearTimeout(r.timer);
    fold(r);
}

/** Fit the rows to the room: from just under the panel's top edge to just above the category chips, or
 *  the goods when the shop has none. Measured on screen and turned back into CSS pixels by the talk
 *  box's own ratio, so the inventory's zoom (and its opening scale) cancel out. */
function fit(tries) {
    if (!open || root.hidden) return;
    const box = root.getBoundingClientRect();
    if (!root.offsetHeight || !box.height) {
        // Not laid out yet (the inventory is still opening): a few frames more.
        if (tries < 20) requestAnimationFrame(() => fit(tries + 1));
        return;
    }
    const scale = box.height / root.offsetHeight;
    const below = (tabsEl.offsetHeight > 0 ? tabsEl : gridEl).getBoundingClientRect();
    const top = (panelEl.getBoundingClientRect().top - box.top) / scale + EDGE;
    const room = (below.top - box.top) / scale - EDGE - top;
    if (!(room > 0)) return;
    const h = Math.max(MIN_H, Math.min(MAX_H, Math.floor(room / (2 + GAP))));
    root.style.setProperty('--talk-h', h + 'px');
    stack.style.top = top + 'px';
    stack.style.bottom = 'auto';
    stack.style.height = room + 'px';
    // A line already open was measured at the old size.
    for (const r of Object.values(rows)) if (r.current) r.text.style.width = widthFor(r.current.text) + 'px';
}

let fitFrame = 0;

/** Fit the rows on the next frame, after the layout just changed (shops.js: the chips are drawn, or the
 *  screen was resized). */
export function talkFit() {
    if (fitFrame) return;
    fitFrame = requestAnimationFrame(() => { fitFrame = 0; fit(0); });
}

window.addEventListener('resize', talkFit);

function say(who, text, kind) {
    const r = rows[who];
    if (!open || !r || typeof text !== 'string' || !text) return;
    r.queue.push({ text: text, kind: kind === 'sale' || kind === 'refused' ? kind : null });
    if (!r.current) next(r);
    else schedule(r);
}

/** The shop screen opened (shops.js openShop): the faces, and nothing said yet. */
export function talkOpen(data) {
    visit++;
    const v = visit;
    open = true;
    reset(rows.me);
    reset(rows.keeper);
    // Off at this server (Config.ShopTalk.enabled): no capsules at all, rather than silent faces.
    root.hidden = !(data && data.talk);
    if (root.hidden) return;
    // Nobody behind the counter (a prop shop): the shopper's row alone.
    rows.keeper.el.hidden = !data.keeper;
    setFace(rows.keeper, data.keeper ? pedImageUrl(data.keeper) : '');
    setFace(rows.me, '');
    myPortrait().then((url) => { if (v === visit && url) setFace(rows.me, url); });
    talkFit();
}

/** The shop screen closed (shops.js closeShop): anything waiting goes with it, except the notices, which go
 *  back to ui.js to show where they now can. */
export function talkClose() {
    visit++;
    open = false;
    const waiting = rows.me.queue.filter((l) => l.notice && Date.now() - l.notice.at <= NOTICE_STALE_MS);
    reset(rows.me);
    reset(rows.keeper);
    root.hidden = true;
    if (noticeFallback) {
        for (const l of waiting) noticeFallback({ text: l.text, type: l.notice.type, duration: l.notice.duration });
    }
}

// ---- notices on the shop screen ----
//
// The goods take the pockets' place, header and all (shops.js), so a notice that would show there
// (js/inv-notice.js) joins the shopper's row instead, in its queue with their /me's: the notice's disc over
// the face, the words as a line's, for the notice's own time.

let noticeFallback = null;

/** Where a notice still waiting goes when the shop closes (ui.js's uiNotify). */
export function setTalkNoticeFallback(fn) {
    noticeFallback = fn;
}

/** Can the shop screen take a notice now: open, with its talk rows (Config.ShopTalk on). */
export function talkNoticeAvailable() {
    return open && !root.hidden && !!rows.me.mark;
}

/** A notice on the shopper's row: `{ text, type, duration, glyph, color }` (ui.js gives the type's mark and
 *  colour). A success reads as a sale (green), an error as a refusal (red). */
export function talkNotice(n) {
    if (!talkNoticeAvailable() || !n || typeof n.text !== 'string' || n.text === '') return;
    const r = rows.me;
    r.queue.push({
        text: n.text,
        kind: n.type === 'success' ? 'sale' : n.type === 'error' ? 'refused' : null,
        notice: { type: n.type, glyph: n.glyph, color: n.color, duration: n.duration, at: Date.now() },
    });
    if (!r.current) next(r);
    else schedule(r);
}

NuiRouter.register('shopTalk', (d) => say(d && d.who, d && d.text, d && d.kind));
