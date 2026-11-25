// ========================================
// WHIP'S KEYBOARD — typing on a controller
//
// A controller has no keys, and whip had no way to type with one. This is whip's on-screen keyboard,
// for anything that asks a pad player to type: a field's text, then the keys. The D-pad (or the left
// stick) moves the highlight and A types it; the other buttons are the Xbox keyboard's: X deletes, Y is
// a space, LB is Caps, LT the symbols page (its key too: a / command's slash), RB is
// Done, B leaves the field as it was. The right stick moves the keyboard
// round the screen, off whatever it covers, and it opens where it was left (this PC). A keyboard works
// on it too (type, Backspace, Enter is Done, Esc leaves).
//
//   in whip's page:  openPadKeyboard({ id?, title, value, placeholder?, numeric?, maxLength?, dim?, predict?,
//                    commands?, fromA?, onDone(text), onCancel? }); closePadKeyboard(id) takes yours away without an answer
//                    (`fromA`: opened by the pad's A going down, as navAnalog says it: see skipA)
//   from Lua:        exports.spur_core:OpenKeyboard(opts) -> text | nil   (client/keyboard.lua: any
//                    resource, its own page or none; it waits)
//
// The text is typed into the keyboard's own window, above the keys, so the player sees what they type where
// they type it. The composer (js/composer.js) types a chat line here on a controller.
//
// WORDS (js/keyboard-words.js): over the keys, up to three ways to finish the word being
// typed (or the / command, from the opener's `commands`); RT takes the first, or D-pad up reaches them. The
// letters are the player's language's (its pack); a server with more than one has a language key on the last
// row, and holding A on a letter with accents (é è ê) opens them. `predict: false` turns the words off (a
// plate, a code); the number pad never has them.
//
// It is a scope of its own (priority 0.5: over every screen but the creator, whose scope stands down while
// it is up: the creator opens it for an outfit's name), so while it is up the pad is its alone. It takes
// the sticks as numbers (the right one moves it), so the left stick's directions are made here, with
// client/controller.lua's pause and repeat.
// ========================================

import { NuiRouter } from './router.js';
import { escapeHtml, nuiCallback } from './utils.js';
import {
    accentsOf, currentLanguage, languages, learn, loadPack, packNow, predicting, setLanguage, suggest,
} from './keyboard-words.js';

const NUMBER_ROW = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-'];
// English's letters: the keys until (or unless) the language's own pack says otherwise.
const ENGLISH_ROWS = [
    ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', "'"],
    ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', '.', ','],
    ['z', 'x', 'c', 'v', 'b', 'n', 'm', '?', '!'],
];
// The symbols page: every other character a keyboard types, the same shape as the letters (so the highlight
// keeps its place when the page turns), the numbers on top on both.
const SYMBOL_ROWS = [
    ['/', '@', '#', '$', '%', '&', '*', '(', ')', '_', '='],
    ['+', ':', ';', '"', "'", '[', ']', '{', '}', '<', '>'],
    ['~', '`', '^', '\\', '|', '£', '.', ',', '?', '!', 'back'],
];
const NUMBERS = [
    ['7', '8', '9'],
    ['4', '5', '6'],
    ['1', '2', '3'],
    ['-', '0', '.'],
    ['cancel', 'back', 'done'],
];
// What the named keys say, and how many of the 11 columns they take on the last row (Space takes what is left).
const NAMED = {
    shift: { label: 'Caps' }, back: { label: '⌫', aria: 'Delete' }, symbols: { label: 'Symbols', span: 2 },
    lang: { aria: 'Language', span: 1 }, cancel: { label: 'Cancel', span: 2 }, space: { label: 'Space' },
    done: { label: 'Done', span: 3 },
};
const TRIGGER_ON = 0.6, TRIGGER_OFF = 0.3;   // LT / RT pressed past this; let go below this
const HELD_AT_OPEN_MS = 250;                  // a trigger already down this soon after it opens was held from before
const ACCENT_HOLD_MS = 350;                   // A held this long on a letter with accents opens them

const STICK = 0.6;            // the left stick past this is a direction, as the D-pad
const REPEAT_DELAY = 380;     // a held direction: the pause before it repeats (as client/controller.lua)
const REPEAT_RATE = 110;      // and how often after that
const MOVE = 1.1;             // the right stick at a full push moves the keyboard this many screen heights a second
const SPOT_KEY = 'whip-pad-keyboard-at';   // where it was left (this PC: the page's own storage)

// { el, move, id, text, placeholder, caps, symbols, numeric, max, focus, lastKey, onDone, onCancel, openedAt,
//   lang, rows, predict, learn, commands, sugs, pending (A down on a letter with accents), accent (their row),
//   skipA (opened by A's state going down: its 'select' is still to come, and is not a key) }
//
// A IS SENT TWICE, its state (navAnalog `a`) and then its press ('select'), in that order in one frame
// (client/controller.lua DriveFrame). A screen that opens the keyboard on the first (the pad circle's A on a
// field) would have the second press the key it opens on, "q", so that one is let go by (fromA).
let kb = null;
const pad = { x: 0, y: 0, rx: 0, ry: 0, raf: 0, last: 0, dir: null, dirSince: 0, dirFired: 0, lt: false, rt: false, a: false };

/** Where it was left: an offset from its home (low in the middle), in screen pixels. */
let spot = { dx: 0, dy: 0 };
try { const s = JSON.parse(localStorage.getItem(SPOT_KEY) || 'null'); if (s && isFinite(s.dx) && isFinite(s.dy)) spot = s; } catch (_) { /* none kept */ }

export function padKeyboardOpen() { return kb !== null; }

function keyLabel(k) {
    if (k === 'symbols') return kb && kb.symbols ? 'ABC' : NAMED.symbols.label;
    if (k === 'lang') return kb ? kb.lang.toUpperCase() : '';
    if (NAMED[k]) return NAMED[k].label;
    return kb && kb.caps ? k.toUpperCase() : k;
}

/** The last row: with a language key when the server offers more than one language. */
function bottomRow() {
    return languages().length > 1 ? ['symbols', 'lang', 'cancel', 'space', 'done'] : ['symbols', 'cancel', 'space', 'done'];
}

function rowsNow() {
    if (kb.numeric) return NUMBERS;
    if (kb.symbols) return [NUMBER_ROW, ...SYMBOL_ROWS, bottomRow()];
    const r = kb.rows;
    return [NUMBER_ROW, r[0], r[1], ['shift', ...r[2], 'back'], bottomRow()];
}

function spanOf(k, row) {
    if (k === 'space') return 11 - row.reduce((n, o) => n + (o === 'space' ? 0 : (NAMED[o] && NAMED[o].span) || 1), 0);
    return NAMED[k] && NAMED[k].span;
}

function draw() {
    const rows = rowsNow();
    const cols = kb.numeric ? 3 : 11;
    // A highlight on a key this page does not have (another language's letters): the first letter.
    if (!kb.focus.startsWith('sug:') && !rows.some((row) => row.includes(kb.focus))) kb.focus = rows[1][0];
    const keysEl = kb.el.querySelector('.pk-keys');
    keysEl.style.gridTemplateColumns = `repeat(${cols}, 1fr)`;
    keysEl.innerHTML = rows.map((row) => row.map((k) => {
        const n = NAMED[k];
        const s = !kb.numeric && n ? spanOf(k, row) : 0;
        const span = s ? ` style="grid-column: span ${s}"` : '';
        const cls = 'pk-key' + (n ? ' pk-named pk-' + k : '') + (k === 'shift' && kb.caps ? ' on' : '');
        return `<button type="button" class="${cls}" data-k="${escapeHtml(k)}"${span}`
            + ` aria-label="${escapeHtml((n && n.aria) || keyLabel(k))}">${escapeHtml(keyLabel(k))}</button>`;
    }).join('')).join('');
    kb.el.classList.toggle('pk-numeric', kb.numeric);
    mark();
    drawText();
}

function drawText() {
    const t = kb.el.querySelector('.pk-text');
    // Empty: the caret, and the ghost text saying what goes here (an input's placeholder).
    t.innerHTML = (!kb.text && kb.placeholder)
        ? '<i class="pk-caret"></i><span class="pk-placeholder">' + escapeHtml(kb.placeholder) + '</span>'
        : escapeHtml(kb.text) + '<i class="pk-caret"></i>';
    t.scrollTop = t.scrollHeight;
    kb.el.querySelector('.pk-count').textContent = kb.max ? `${kb.text.length} / ${kb.max}` : '';
    drawWords();
}

/** The ways to finish the word being typed, over the keys. */
function drawWords() {
    if (!kb.predict) return;
    const had = kb.sugs.length > 0;
    kb.sugs = suggest(kb.lang, kb.text, kb.commands);
    kb.el.querySelector('.pk-sugs').innerHTML = kb.sugs.map((s, i) =>
        `<button type="button" class="pk-key pk-sug${i === 0 ? ' pk-sug-first' : ''}" data-k="sug:${i}">${escapeHtml(s.word)}</button>`).join('');
    // The highlight on a suggestion that went: the last one left, else back on the keys.
    if (kb.focus.startsWith('sug:') && Number(kb.focus.slice(4)) >= kb.sugs.length) {
        kb.focus = kb.sugs.length ? 'sug:' + (kb.sugs.length - 1) : kb.lastKey;
    }
    mark();
    if (had !== kb.sugs.length > 0) NuiRouter.hintsChanged();   // RT says Word only while there is one
}

function keys() { return Array.from(kb.el.querySelectorAll('.pk-key')); }

function mark() {
    if (!kb.focus.startsWith('sug:')) kb.lastKey = kb.focus;   // where to come back to off the suggestions
    keys().forEach((b) => b.classList.toggle('focus', b.dataset.k === kb.focus));
}

/** The nearest key that way: distance that way, plus three times how far off to the side. */
function step(dir) {
    const cur = keys().find((b) => b.dataset.k === kb.focus) || keys()[0];
    const a = cur.getBoundingClientRect();
    const ax = (a.left + a.right) / 2, ay = (a.top + a.bottom) / 2;
    let best = null, bestScore = Infinity;
    for (const b of keys()) {
        if (b === cur) continue;
        const r = b.getBoundingClientRect();
        const bx = (r.left + r.right) / 2, by = (r.top + r.bottom) / 2;
        let along, across;
        if (dir === 'up' || dir === 'down') {
            if (dir === 'down' ? by <= ay + 1 : by >= ay - 1) continue;
            along = Math.abs(by - ay);
            across = Math.max(0, Math.max(a.left, r.left) - Math.min(a.right, r.right));
        } else {
            if (dir === 'right' ? bx <= ax + 1 : bx >= ax - 1) continue;
            along = Math.abs(bx - ax);
            across = Math.abs(by - ay) > 2 ? 1e6 : 0;   // left and right stay on the row
        }
        const score = along + across * 3;
        if (score < bestScore) { bestScore = score; best = b; }
    }
    // Off the end of a row: round to its other end, as a keyboard does.
    if (!best && (dir === 'left' || dir === 'right')) {
        const mid = (b) => { const r = b.getBoundingClientRect(); return (r.top + r.bottom) / 2; };
        const row = keys().filter((b) => Math.abs(mid(b) - ay) <= 2);
        best = dir === 'right' ? row[0] : row[row.length - 1];
    }
    if (best) { kb.focus = best.dataset.k; mark(); }
}

function type(ch) {
    if (kb.max && kb.text.length >= kb.max) return;
    if (kb.numeric && !/^[0-9.\-]$/.test(ch)) return;
    kb.text += ch;
    drawText();
}

function erase() {
    if (!kb.text) return;
    kb.text = [...kb.text].slice(0, -1).join('');   // a whole character, an accented one too
    drawText();
}

/** A suggestion: it takes the place of the word being typed, and a space follows. */
function takeWord(i) {
    const s = kb.sugs[i];
    if (!s) return;
    let t = kb.text.slice(0, s.from) + s.word + ' ';
    if (kb.max && t.length > kb.max) t = t.slice(0, kb.max);
    kb.text = t;
    if (kb.focus.startsWith('sug:')) kb.focus = kb.lastKey;   // back to the key it came up from
    drawText();
}

/** Letters ⇄ symbols, the highlight kept at the same row and column. */
function flipPage() {
    if (kb.numeric) return;
    const from = rowsNow();
    kb.symbols = !kb.symbols;
    const to = rowsNow();
    const r = from.findIndex((row) => row.includes(kb.focus));
    if (r >= 0) kb.focus = to[r][Math.min(from[r].indexOf(kb.focus), to[r].length - 1)];
    draw();
    NuiRouter.hintsChanged();   // LB and LT say something else on this page
}

/** The language's letters, once its pack is here (the first time, it is loading). */
function useLanguage(code) {
    kb.lang = code;
    const p = packNow(code);
    kb.rows = (p && p.rows) || ENGLISH_ROWS;
    if (!p) {
        loadPack(code).then((loaded) => {
            if (!kb || kb.lang !== code) return;
            kb.rows = (loaded && loaded.rows) || ENGLISH_ROWS;
            draw();   // its letters, and its words for what is typed already
        });
    }
}

/** The language key: the server's next language, kept as the player's choice. */
function nextLanguage() {
    const list = languages();
    if (list.length < 2) return;
    const code = list[(list.indexOf(kb.lang) + 1) % list.length];
    setLanguage(code);
    useLanguage(code);
    draw();
}

function press(k) {
    if (k.startsWith('sug:')) { takeWord(Number(k.slice(4))); return; }
    if (k === 'symbols') { flipPage(); return; }
    if (k === 'lang') { nextLanguage(); return; }
    if (k === 'shift') { kb.caps = !kb.caps; draw(); return; }
    if (k === 'back') { erase(); return; }
    if (k === 'space') { type(' '); return; }
    if (k === 'done') { finish(true); return; }
    if (k === 'cancel') { finish(false); return; }
    type(kb.caps ? k.toUpperCase() : k);
}

// ---- accents: A held on a letter that has them ----

/** A went down on a letter with accents: typed when it comes up, its accents if it is still down. */
function holdForAccents(k) {
    if (kb.pending) clearTimeout(kb.pending.timer);
    const p = { k, timer: 0 };
    p.timer = setTimeout(() => {
        if (!kb || kb.pending !== p) return;
        kb.pending = null;
        if (pad.a) openAccents(k); else press(k);   // (let go with no word of it: typed)
    }, ACCENT_HOLD_MS);
    kb.pending = p;
}

function openAccents(base) {
    const list = [base, ...accentsOf(kb.lang, base)];
    const keyEl = keys().find((b) => b.dataset.k === base);
    const box = kb.el.querySelector('.pk-box');
    const pop = document.createElement('div');
    pop.className = 'pk-accents';
    pop.innerHTML = list.map((c) => `<button type="button" class="pk-acc">${escapeHtml(kb.caps ? c.toUpperCase() : c)}</button>`).join('');
    box.appendChild(pop);
    // Over its key, in the box's own pixels (offsets, not screen rects: the box is zoomed), kept inside the box.
    if (keyEl) {
        const left = Math.max(0, Math.min(keyEl.offsetLeft, box.clientWidth - pop.offsetWidth));
        pop.style.left = left + 'px';
        pop.style.top = (keyEl.offsetTop - pop.offsetHeight - 6) + 'px';
    }
    kb.accent = { list, i: 0, el: pop };
    markAccent();
    NuiRouter.hintsChanged();
}

function markAccent() {
    Array.from(kb.accent.el.children).forEach((b, i) => b.classList.toggle('focus', i === kb.accent.i));
}

function closeAccents() {
    if (!kb || !kb.accent) return;
    kb.accent.el.remove();
    kb.accent = null;
    NuiRouter.hintsChanged();
}

/** Close it. `keep`: Done (onDone gets the text), else Cancel (onCancel). `quiet`: neither is told (the
 *  one who opened it closed it). */
function finish(keep, quiet) {
    if (!kb) return;
    const k = kb;
    if (k.pending) clearTimeout(k.pending.timer);
    kb = null;
    if (pad.raf) { cancelAnimationFrame(pad.raf); pad.raf = 0; }
    pad.x = pad.y = pad.rx = pad.ry = 0;
    pad.dir = null;
    pad.lt = pad.rt = false;
    k.el.remove();
    NuiRouter.syncNavScope(true);   // the screen under it takes the pad back now, not on the next tick
    // What was sent teaches it the player's words (this PC).
    if (keep && k.predict && k.learn) learn(k.lang, k.text);
    if (quiet) return;
    if (keep) { if (k.onDone) k.onDone(k.text); }
    else if (k.onCancel) k.onCancel();
}

// ---- where it is: the right stick moves it ----

/** Keep it on the screen, and put it there. */
function placeBox() {
    if (!kb) return;
    kb.move.style.transform = `translate(${spot.dx}px, ${spot.dy}px)`;
    const r = kb.move.getBoundingClientRect();
    let dx = spot.dx, dy = spot.dy;
    if (r.left < 8) dx += 8 - r.left;
    if (r.right > innerWidth - 8) dx -= r.right - (innerWidth - 8);
    if (r.top < 8) dy += 8 - r.top;
    if (r.bottom > innerHeight - 8) dy -= r.bottom - (innerHeight - 8);
    if (dx !== spot.dx || dy !== spot.dy) {
        spot = { dx, dy };
        kb.move.style.transform = `translate(${dx}px, ${dy}px)`;
    }
}

function keepSpot() {
    try { localStorage.setItem(SPOT_KEY, JSON.stringify({ dx: Math.round(spot.dx), dy: Math.round(spot.dy) })); } catch (_) { /* not kept */ }
}

function run() {
    if (pad.raf || !kb) return;
    if (!(pad.x || pad.y || pad.rx || pad.ry) && !pad.dir) return;
    pad.last = performance.now();
    pad.raf = requestAnimationFrame(frame);
}

/** The left stick as a direction (the D-pad's repeat), the right stick moving the keyboard. */
function frame(now) {
    pad.raf = 0;
    if (!kb) return;
    const dt = Math.min(0.05, Math.max(0, (now - pad.last) / 1000));
    pad.last = now;

    let dir = null;
    if (Math.hypot(pad.x, pad.y) > STICK) {
        dir = Math.abs(pad.x) > Math.abs(pad.y) ? (pad.x > 0 ? 'right' : 'left') : (pad.y > 0 ? 'up' : 'down');   // up is +y
    }
    if (dir !== pad.dir) {
        pad.dir = dir;
        pad.dirSince = pad.dirFired = now;
        if (dir) nav(dir);
    } else if (dir && now - pad.dirSince >= REPEAT_DELAY && now - pad.dirFired >= REPEAT_RATE) {
        pad.dirFired = now;
        nav(dir);
    }

    if (pad.rx || pad.ry) {
        const v = MOVE * innerHeight * dt;
        spot = { dx: spot.dx + pad.rx * v, dy: spot.dy - pad.ry * v };   // stick up: up the screen
        placeBox();
        keepSpot();
    }
    if (dir || pad.rx || pad.ry) pad.raf = requestAnimationFrame(frame);
}

/** A direction: along the accents while they are open, else round the keys. */
function nav(dir) {
    if (kb.accent) {
        if (dir === 'left' || dir === 'right') {
            const n = kb.accent.list.length;
            kb.accent.i = (kb.accent.i + (dir === 'right' ? 1 : n - 1)) % n;
            markAccent();
        }
        return;
    }
    step(dir);
}

/** A trigger went down this message (past TRIGGER_ON from below TRIGGER_OFF), and not one held as it opened. */
function triggerPressed(which, v) {
    if (v >= TRIGGER_ON) {
        const fresh = !pad[which] && performance.now() - kb.openedAt >= HELD_AT_OPEN_MS;
        pad[which] = true;
        return fresh;
    }
    if (v < TRIGGER_OFF) pad[which] = false;
    return false;
}

// ---- opening ----

export function openPadKeyboard(o) {
    if (kb) finish(false);
    const numeric = !!o.numeric;
    const predict = !numeric && o.predict !== false && predicting();
    const el = document.createElement('div');
    // `dim: false`: no dim over the screen — chat's, so the messages being answered stay readable.
    el.className = 'pk-root' + (o.dim === false ? ' pk-nodim' : '');
    el.innerHTML = '<div class="pk-move"><div class="pk-box">'
        + `<div class="pk-head"><span class="pk-title">${escapeHtml(o.title || 'Type')}</span><span class="pk-count"></span></div>`
        + '<div class="pk-text"></div>' + (predict ? '<div class="pk-sugs"></div>' : '') + '<div class="pk-keys"></div></div></div>';
    document.body.appendChild(el);
    kb = {
        el, move: el.querySelector('.pk-move'), id: o.id,
        text: String(o.value == null ? '' : o.value), placeholder: o.placeholder ? String(o.placeholder) : '',
        caps: false, symbols: false, numeric,
        max: Number(o.maxLength) > 0 ? Number(o.maxLength) : 0,
        focus: numeric ? '1' : 'q', lastKey: numeric ? '1' : 'q', onDone: o.onDone, onCancel: o.onCancel,
        openedAt: performance.now(), lang: 'en', rows: ENGLISH_ROWS,
        predict, learn: o.learn !== false, sugs: [],
        commands: Array.isArray(o.commands) ? o.commands.filter((c) => typeof c === 'string' && c[0] === '/') : null,
        pending: null, accent: null, skipA: o.fromA === true,
    };
    pad.lt = pad.rt = false;
    if (!numeric) useLanguage(currentLanguage());
    if (kb.max && kb.text.length > kb.max) kb.text = kb.text.slice(0, kb.max);
    draw();
    placeBox();
    el.addEventListener('mousedown', (e) => {
        const b = e.target.closest('.pk-key');
        const acc = e.target.closest('.pk-acc');
        e.preventDefault();
        if (acc && kb && kb.accent) {
            kb.accent.i = Array.from(kb.accent.el.children).indexOf(acc);
            pickAccent();
            return;
        }
        if (b && kb) { closeAccents(); kb.focus = b.dataset.k; mark(); press(b.dataset.k); }
    });
    NuiRouter.syncNavScope(true);
}

function pickAccent() {
    const c = kb.accent.list[kb.accent.i];
    closeAccents();
    type(kb.caps ? c.toUpperCase() : c);
}

/** Take away the keyboard `id` opened, if it is still up, telling no one (its opener is closing). */
export function closePadKeyboard(id) {
    if (kb && kb.id === id) finish(false, true);
}

// From Lua (client/keyboard.lua, the OpenKeyboard export): open it, and answer with the text or a cancel.
NuiRouter.register('padKeyboardOpen', (d) => {
    if (!d) return;
    const id = d.id;
    openPadKeyboard({
        id, title: d.title, value: d.value, placeholder: d.placeholder, numeric: d.numeric === true, maxLength: d.maxLength,
        predict: d.predict !== false,
        onDone: (text) => nuiCallback('padKeyboardDone', { id, text }),
        onCancel: () => nuiCallback('padKeyboardDone', { id, cancel: true }),
    });
});

// Lua closed it (the resource that asked stopped, or asked again): no answer.
NuiRouter.register('padKeyboardClose', (d) => {
    if (d) closePadKeyboard(d.id);
});

addEventListener('resize', () => placeBox());

NuiRouter.registerKeyScope({
    name: 'pad-keyboard',
    priority: 0.5,
    isOpen: () => kb !== null,
    onKey: (e) => {
        if (!kb) return;
        if (e.key === 'Escape') { e.preventDefault(); if (kb.accent) closeAccents(); else finish(false); }
        else if (e.key === 'Enter') { e.preventDefault(); finish(true); }
        else if (e.key === 'Backspace') { e.preventDefault(); erase(); }
        else if (e.key === 'Tab') { e.preventDefault(); takeWord(0); }
        else if (e.key.length === 1 && !e.ctrlKey && !e.metaKey) { e.preventDefault(); type(e.key); }
    },
    onNav: (n) => {
        if (!kb) return;
        if (kb.accent) {   // the accents' row has the pad: along it, A types one, B shuts it
            if (n === 'select') pickAccent();
            else if (n === 'back') closeAccents();
            else nav(n);
            return;
        }
        if (n === 'up' || n === 'down' || n === 'left' || n === 'right') nav(n);
        else if (n === 'select') {
            // The press that opened it, a moment behind its state (fromA): not a key.
            const opener = kb.skipA && performance.now() - kb.openedAt < HELD_AT_OPEN_MS;
            kb.skipA = false;
            if (opener) return;
            if (!kb.numeric && !kb.symbols && accentsOf(kb.lang, kb.focus).length) holdForAccents(kb.focus);
            else press(kb.focus);
        }
        else if (n === 'back') finish(false);
        else if (n === 'buttonX') erase();
        else if (n === 'buttonY') { if (!kb.numeric) type(' '); }
        else if (n === 'tabPrev') { if (!kb.numeric && !kb.symbols) { kb.caps = !kb.caps; draw(); } }
        else if (n === 'tabNext') finish(true);
    },
    analog: true,
    onAnalog: (a) => {
        if (!kb) return;
        pad.x = +a.x || 0; pad.y = +a.y || 0; pad.rx = +a.rx || 0; pad.ry = +a.ry || 0;
        // A let go before its accents opened: the letter, now.
        const aDown = a.a === true;
        if (pad.a && !aDown && kb.pending) {
            clearTimeout(kb.pending.timer);
            const k = kb.pending.k;
            kb.pending = null;
            press(k);
        }
        pad.a = aDown;
        // LT turns the page, RT takes the first word, each as it goes down. Down already as the keyboard
        // opened (its first word comes at once), it was held from before: let go and pressed again, it acts.
        if (triggerPressed('lt', +a.lt || 0) && !kb.accent) flipPage();
        if (triggerPressed('rt', +a.rt || 0) && !kb.accent) takeWord(0);
        run();
    },
    padHints: () => {
        if (kb && kb.accent) return [['dpad', 'Pick'], ['a', 'Type'], ['b', 'Back']];
        if (kb && kb.numeric) return [['a', 'Type'], ['x', 'Delete'], ['rs', 'Move'], ['rb', 'Done'], ['b', 'Cancel']];
        const word = kb && kb.sugs.length ? [['rt', 'Word']] : [];
        const page = kb && kb.symbols ? [['lt', 'Letters']] : [['lb', 'Caps'], ['lt', 'Symbols']];
        return [['a', 'Type'], ...word, ['x', 'Delete'], ['y', 'Space'], ...page, ['rs', 'Move'], ['rb', 'Done'], ['b', 'Cancel']];
    },
});
