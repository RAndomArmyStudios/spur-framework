// ========================================
// THE SEAT MAP (Seats on the F1 wheel, /seats)
//
// The seats of the vehicle the player is in, laid out as rows inside the car's outline: two to a row
// with the driver front left, or one behind another on a bike. Each is Free, Occupied or You. Pick a
// free one to move there. client/seats.lua owns everything that happens: it sends what to show (and
// again whenever a seat changes, while the map is open) and does the move. This page only draws and
// says what was picked.
//
// Lua → page:  seatsOpen { data }   seatsUpdate { data }   seatsClose
//              data = { title, inline, seats: [{ seat, label, row, col, state, turret }] }
//              state is 'free' | 'occupied' | 'you'; col 0 is the driver's side
// Page → Lua:  seatsPick { seat }   seatsClose
//
// Mouse: click a free seat; right-click or Escape closes. Keys: arrows choose, Enter moves.
// Pad: the D-pad or stick chooses, A moves, B closes (controller.js sends them here as nav).
// ========================================

import { NuiRouter } from './router.js';
import { nuiCallback, escapeHtml } from './utils.js';

const $ = (id) => document.getElementById(id);

let open = false;
let data = { title: '', inline: false, seats: [] };
let focus = null;   // the seat number the keys and the pad point at

// A steering wheel, on the driver's tile.
const WHEEL = '<svg class="st-wheel" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"'
    + ' stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'
    + '<circle cx="12" cy="12" r="8.6"/><circle cx="12" cy="12" r="2.2"/>'
    + '<path d="M3.6 10.6h6.2"/><path d="M14.2 10.6h6.2"/><path d="M12 14.2v6.2"/></svg>';

const STATE_WORD = { free: 'Free', occupied: 'Occupied', you: 'You' };

function seatGlyph() {
    const g = window.WhipGlyphs && window.WhipGlyphs.glyphs && window.WhipGlyphs.glyphs.seat;
    return g ? '<span class="st-glyph" aria-hidden="true">' + g + '</span>' : '';
}

function seatBy(n) {
    return data.seats.find((s) => s.seat === n) || null;
}

/** The rows, front first; a row is its seats, driver's side first. */
function rows() {
    const byRow = new Map();
    for (const s of data.seats) {
        if (!byRow.has(s.row)) byRow.set(s.row, []);
        byRow.get(s.row).push(s);
    }
    return [...byRow.keys()].sort((a, b) => a - b).map((r) => byRow.get(r).sort((a, b) => a.col - b.col));
}

/** Where a seat sits on the map, for arrow and stick moves: its row, and across (a lone seat is centred). */
function placeOf(s) {
    const mates = data.seats.filter((o) => o.row === s.row).length;
    return { y: s.row, x: (data.inline || mates === 1) ? 0.5 : s.col };
}

// ---- rendering ----

function render() {
    const car = $('st-car');
    if (car) car.textContent = data.title || '';

    const body = $('st-body');
    if (!body) return;
    const list = rows();
    // Taller tiles for a car, shorter for a bus: the map has to fit 8 rows.
    const n = list.length;
    body.style.setProperty('--st-tile-h', (n <= 2 ? 76 : n <= 4 ? 60 : n <= 6 ? 50 : 44) + 'px');

    let html = '<div class="st-shell' + (data.inline ? ' st-inline' : '') + '">';
    html += '<div class="st-front">Front</div>';
    for (const row of list) {
        html += '<div class="st-row' + (row.length === 1 ? ' st-row-one' : '') + '">';
        for (const s of row) {
            const cls = ['st-seat', 'st-' + s.state];
            if (s.seat === focus) cls.push('st-focus');
            html += '<button type="button" class="' + cls.join(' ') + '" data-seat="' + s.seat + '"'
                + (s.state === 'free' ? '' : ' tabindex="-1"') + '>'
                + seatGlyph()
                + '<span class="st-text">'
                + '<span class="st-label">' + escapeHtml(s.label) + '</span>'
                + '<span class="st-state">' + STATE_WORD[s.state] + '</span>'
                + '</span>'
                + (s.seat === -1 && !data.inline ? WHEEL : '')
                + (s.turret ? '<span class="st-badge">Turret</span>' : '')
                + '</button>';
        }
        html += '</div>';
    }
    html += '</div>';
    body.innerHTML = html;
}

function markFocus() {
    document.querySelectorAll('#seats .st-seat').forEach((el) => {
        el.classList.toggle('st-focus', Number(el.dataset.seat) === focus);
    });
}

// ---- open / close ----

function show(d) {
    data = (d && d.data) || data;
    const mine = data.seats.find((s) => s.state === 'you');
    focus = mine ? mine.seat : (data.seats[0] ? data.seats[0].seat : null);
    open = true;
    const root = $('seats');
    if (root) root.classList.add('st-open');
    render();
}

function update(d) {
    data = (d && d.data) || data;
    if (focus !== null && !seatBy(focus)) focus = data.seats[0] ? data.seats[0].seat : null;
    if (open) render();
}

function hide() {
    if (!open) return;
    open = false;
    const root = $('seats');
    if (root) root.classList.remove('st-open');
}

/** The page asks; Lua closes (it owns the focus) and tells the page back. hide() is safe twice. */
function requestClose() {
    hide();
    nuiCallback('seatsClose', {});
}

function pick(n) {
    const s = seatBy(n);
    if (!s || s.state !== 'free') return;
    hide();
    nuiCallback('seatsPick', { seat: n });
}

/** Arrow keys and the pad: the nearest seat that way, if there is one. */
function step(dir) {
    const from = seatBy(focus);
    if (!from) return;
    const at = placeOf(from);
    let best = null;
    let bestScore = Infinity;
    for (const s of data.seats) {
        if (s.seat === focus) continue;
        const p = placeOf(s);
        const dx = p.x - at.x;
        const dy = p.y - at.y;
        const ahead = dir === 'up' ? -dy : dir === 'down' ? dy : dir === 'left' ? -dx : dx;
        if (ahead <= 0) continue;
        // Straight on counts most; off to the side costs twice as much.
        const side = (dir === 'up' || dir === 'down') ? Math.abs(dx) : Math.abs(dy);
        const score = ahead + side * 2;
        if (score < bestScore) { bestScore = score; best = s; }
    }
    if (best) {
        focus = best.seat;
        markFocus();
    }
}

// ---- input ----

(function bindSeatActions() {
    const root = $('seats');
    if (!root) return;

    root.addEventListener('click', (e) => {
        if (!open) return;
        if (e.target.closest('[data-st="close"]')) { requestClose(); return; }
        const el = e.target.closest('.st-seat');
        if (!el) return;
        el.blur();
        pick(Number(el.dataset.seat));
    });

    // The mouse and the keys share one highlight: pointing at a seat chooses it.
    root.addEventListener('mouseover', (e) => {
        if (!open) return;
        const el = e.target.closest('.st-seat');
        if (!el) return;
        const n = Number(el.dataset.seat);
        if (n !== focus) { focus = n; markFocus(); }
    });

    root.addEventListener('contextmenu', (e) => {
        if (!open) return;
        e.preventDefault();
        requestClose();
    });
})();

NuiRouter.register('seatsOpen', (d) => show(d));
NuiRouter.register('seatsUpdate', (d) => update(d));
NuiRouter.register('seatsClose', () => hide());

const ARROWS = { ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'left', ArrowRight: 'right' };

// 112: a free slot between the old dev panels (see router.js). It takes every key while open.
NuiRouter.registerKeyScope({
    name: 'seats',
    priority: 112,
    isOpen: () => open,
    onKey: (e) => {
        if (e.key === 'Escape') {
            e.preventDefault();
            requestClose();
        } else if (ARROWS[e.key]) {
            e.preventDefault();
            step(ARROWS[e.key]);
        } else if (e.key === 'Enter' || e.key === ' ') {
            e.preventDefault();
            pick(focus);
        }
    },
    onNav: (nav) => {
        if (nav === 'back') requestClose();
        else if (nav === 'select') pick(focus);
        else if (nav === 'up' || nav === 'down' || nav === 'left' || nav === 'right') step(nav);
    },
    padHints: () => {
        const s = seatBy(focus);
        const hints = [['dpad', 'Choose']];
        if (s && s.state === 'free') hints.push(['a', 'Move here']);
        hints.push(['b', 'Close']);
        return hints;
    },
});
