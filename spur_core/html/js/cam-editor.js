// ========================================
// THE CAMERA CREATOR — a timeline of camera shots (tools/camera.lua)
//
// Three parts over the world:
//   the card (top left)     the sequence: its name, New / Open / Save / Copy code, its own settings
//                           (length, anchor, loop, letterbox, spacing) and what a new key gets
//   the inspector (right)   the picked key: its kind of shot and subject, its numbers, how the camera goes
//                           on to the next key (cut, glide, spring, orbit), its layers (shake, filter, punch)
//   the dock (bottom)       play, the time, look through or fly, add a key, undo; the TIMELINE: a ruler, the
//                           keys (drag to move them), the moves between them, and the playhead (drag to scrub)
//
// IT DRAWS; LUA DECIDES (the furnisher's rule). Every change goes to tools/camera.lua as a callback and
// comes back as the whole state (camEdState), so the screen never holds a second opinion about the
// sequence. The page owns only how it looks at the timeline: its zoom and scroll.
//
// THE MOUSE: the pointer works this page; the RIGHT button held flies the camera (Lua adds .ce-looking,
// the cursor goes, and this page goes inert). KEYS (Space, G, E, F, V, Delete, the arrows, Ctrl+Z ...) are
// read here, and dead while a box has focus — the game reads the keyboard too (KeepInput), so the page
// tells Lua when typing starts and stops. A controller drives from Lua and this page only shows it.
//
// 2022-SAFE (CEF is Chromium 103): no :has(), no CSS nesting, no color-mix().
// ========================================

import { NuiRouter } from './router.js';
import { nuiCallback } from './utils.js';
import { padGlyph } from './pad-glyphs.js';

// The transport's and the mouse's pictures, drawn (the ⏮ ▶ characters come out as emoji on some PCs).
const ICON = {
    prev: '<svg viewBox="0 0 16 16" fill="currentColor"><path d="M3 3h2v10H3zM13 3v10L6 8z"/></svg>',
    next: '<svg viewBox="0 0 16 16" fill="currentColor"><path d="M11 3h2v10h-2zM3 3v10l7-5z"/></svg>',
    play: '<svg viewBox="0 0 16 16" fill="currentColor"><path d="M4.5 2.5v11l9-5.5z"/></svg>',
    pause: '<svg viewBox="0 0 16 16" fill="currentColor"><path d="M4 3h3v10H4zM9 3h3v10H9z"/></svg>',
    close: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M4 4l8 8M12 4l-8 8"/></svg>',
    zoomOut: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M3.5 8h9"/></svg>',
    zoomIn: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M3.5 8h9M8 3.5v9"/></svg>',
    plus: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M3.5 8h9M8 3.5v9"/></svg>',
    // A camera point: the body and the view frame its gizmo draws in the world; struck through when hidden.
    points: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"><path d="M2 5.5h6.5v5H2zM8.5 8l5-3v6z"/></svg>',
    pointsOff: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round" stroke-linecap="round"><path d="M2 5.5h6.5v5H2zM8.5 8l5-3v6z" opacity="0.45"/><path d="M2.5 2.5l11 11"/></svg>',
    // The screen's frame with nothing in it.
    hud: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><path d="M2 5V3h3M11 3h3v2M14 11v2h-3M5 13H2v-2"/></svg>',
    exit: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M6.5 2.5h-3a1 1 0 0 0-1 1v9a1 1 0 0 0 1 1h3M10 5l3 3-3 3M13 8H6"/></svg>',
    // A clapperboard: playing in game, the shots ready to roll.
    game: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"><path d="M2.5 6.5h11v7h-11zM2.5 6.5l1-3.5 10 2.5-1 1"/><path d="M6 4l1.4 2.4M9.4 4.9l1.4 2.4" stroke-linecap="round"/></svg>',
    rmb: '<svg viewBox="0 0 14 20"><rect x="1.8" y="1.8" width="10.4" height="16.4" rx="5.2" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M7 1.8V8M1.8 8h10.4" stroke="currentColor" stroke-width="1.4"/><path d="M7 1.8a5.2 5.2 0 0 1 5.2 5.2V8H7z" fill="currentColor"/></svg>',
    wheel: '<svg viewBox="0 0 14 20"><rect x="1.8" y="1.8" width="10.4" height="16.4" rx="5.2" fill="none" stroke="currentColor" stroke-width="1.6"/><rect x="5.8" y="4" width="2.4" height="5" rx="1.2" fill="currentColor"/></svg>',
};
const GLYPHS = () => (window.WhipGlyphs && window.WhipGlyphs.glyphs) || {};
const SAYS_MARK = { ok: 'success', err: 'fail', warn: 'warning', info: 'info' };

const KINDS = [
    { key: 'fixed', label: 'Fixed', tip: 'Where the camera is' },
    { key: 'orbit', label: 'Orbit', tip: 'Round a subject' },
    { key: 'chase', label: 'Chase', tip: 'Behind it on a spring' },
    { key: 'mounted', label: 'Mounted', tip: 'Fixed to it' },
    { key: 'track', label: 'Track', tip: 'Stands still, keeps it in frame' },
];
const MOVES = [
    { key: 'cut', label: 'Cut' },
    { key: 'glide', label: 'Glide' },
    { key: 'spring', label: 'Spring' },
    { key: 'orbit', label: 'Orbit' },
];
const EASES = [
    { key: 'linear', label: 'Steady' },
    { key: 'smooth', label: 'Smooth' },
    { key: 'in', label: 'Slow start' },
    { key: 'out', label: 'Slow end' },
    { key: 'strong', label: 'Strong' },
];
/** Key j (from 1) glides on into the next. Gliding keys in a row are one move (shared/cam_sequence.lua). */
function glidesOn(ks, j) {
    const k = ks[j - 1], nk = ks[j];
    return !!(k && nk && (k.move || 'glide') === 'glide' && nk.t > k.t);
}
/** The first key of the glide key j is in, and the key it ends at. */
function glideSpan(ks, j) {
    let first = j, end = j;
    while (first > 1 && glidesOn(ks, first - 1)) first--;
    while (glidesOn(ks, end)) end++;
    return [first, end];
}

const SUBJECTS = [
    { key: 'player', label: 'You' },
    { key: 'vehicle', label: 'Your vehicle' },
    { key: 'target', label: 'The picked thing' },
];

// Each kind's numbers in the inspector: [field, label, step, min, max, unit]. Shot fields are 'shot.*'.
const FIELDS = {
    fixed: [
        ['shot.rot.x', 'Pitch', 0.5, -89, 89, '°'], ['shot.rot.z', 'Heading', 1, -360, 360, '°'],
        ['shot.rot.y', 'Roll', 0.5, -180, 180, '°'], ['shot.fov', 'Lens', 0.5, 1, 130, '°'],
    ],
    orbit: [
        ['shot.yaw', 'Around', 1, -720, 720, '°'], ['shot.pitch', 'Height', 0.5, -80, 85, '°'],
        ['shot.fit', 'Fill', 0.05, 0.05, 20, '×'], ['shot.dist', 'Distance', 0.1, 0.3, 500, 'm'],
        ['shot.aim.x', 'Aim right', 0.05, -10, 10, ''], ['shot.aim.y', 'Aim front', 0.05, -10, 10, ''],
        ['shot.aim.z', 'Aim up', 0.05, -10, 10, ''], ['shot.look.pitch', 'Tilt', 0.5, -90, 90, '°'],
        ['shot.look.yaw', 'Pan', 0.5, -180, 180, '°'], ['shot.turn', 'Spin', 0.5, -180, 180, '°/s'],
        ['shot.clear', 'Off the ground', 0.05, -1, 10, 'm'], ['shot.roll', 'Roll', 0.5, -180, 180, '°'],
        ['shot.fov', 'Lens', 0.5, 1, 130, '°'],
    ],
    chase: [
        ['shot.dist', 'Behind', 0.1, 0.5, 60, 'm'], ['shot.height', 'Above', 0.1, -5, 30, 'm'],
        ['shot.ahead', 'Look ahead', 0.1, 0, 30, 'm'], ['shot.slip', 'Lean into slides', 0.05, 0, 1, ''],
        ['shot.stiff', 'Tightness', 0.5, 0.5, 40, ''], ['shot.turnRate', 'Turn speed', 0.5, 0.5, 40, ''],
        ['shot.fovAdd', 'Wider at speed', 0.5, -40, 60, '°'], ['shot.distAdd', 'Further at speed', 0.1, -10, 20, 'm'],
        ['shot.fov', 'Lens', 0.5, 1, 130, '°'],
    ],
    mounted: [
        ['shot.offset.x', 'Right', 0.02, -200, 200, 'm'], ['shot.offset.y', 'Forward', 0.02, -200, 200, 'm'],
        ['shot.offset.z', 'Up', 0.02, -200, 200, 'm'], ['shot.rot.x', 'Pitch', 0.5, -89, 89, '°'],
        ['shot.rot.z', 'Heading', 1, -360, 360, '°'], ['shot.rot.y', 'Roll', 0.5, -180, 180, '°'],
        ['shot.fov', 'Lens', 0.5, 1, 130, '°'],
    ],
    track: [
        ['shot.aim.x', 'Aim right', 0.05, -10, 10, ''], ['shot.aim.y', 'Aim front', 0.05, -10, 10, ''],
        ['shot.aim.z', 'Aim up', 0.05, -10, 10, ''], ['shot.look.pitch', 'Tilt', 0.5, -90, 90, '°'],
        ['shot.look.yaw', 'Pan', 0.5, -180, 180, '°'], ['shot.roll', 'Roll', 0.5, -180, 180, '°'],
        ['shot.fov', 'Lens', 0.5, 1, 130, '°'],
    ],
};

// The timeline's ruler steps, ms: the smallest that leaves room between labels.
const TICKS = [100, 200, 500, 1000, 2000, 5000, 10000, 15000, 30000, 60000];
const SNAP = 50, SNAP_SHIFT = 250;

let open = false;
let st = null;                 // the last camEdState
let playhead = 0, playing = false, viewing = false;
let looking = false, pad = false;
let viewStart = 0, viewSpan = 12000;   // the timeline's window, ms
let userZoomed = false;
let typing = false;
let modal = null;              // 'open' | 'save' | null
let savedList = [], mayEdit = false;
// The saved sequence whose Delete was pressed: its row asks "Delete it?" right there (a screen confirms inside
// itself, as WP.confirm does; the Lua dialog was refused while this screen held the focus: audit 20, CLI-1)
let askingDelete = null;
let sayTimer = null, sayGone = null;
let hintsShape = '';           // what the controls row was built for (rebuilt only when it changes)
let playShape = '';
const el = {};

// ---- small helpers ----

function h(tag, cls, text) {
    const n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text !== undefined) n.textContent = text;
    return n;
}

function fmtTime(ms) {
    const t = Math.max(0, Math.round(ms / 10));
    const cs = t % 100, s = Math.floor(t / 100) % 60, m = Math.floor(t / 6000);
    return m + ':' + String(s).padStart(2, '0') + '.' + String(cs).padStart(2, '0');
}

function fmtNum(v) {
    if (typeof v !== 'number' || !isFinite(v)) return '';
    return String(Math.round(v * 1000) / 1000);
}

function get(obj, path) {
    let t = obj;
    for (const p of path.split('.')) { if (t == null) return undefined; t = t[p]; }
    return t;
}

const keys = () => (st && st.seq && Array.isArray(st.seq.keys) ? st.seq.keys : []);
const seqLength = () => (st && st.seq ? Math.max(st.seq.length || 0, 0) : 0);

function cbk(name, data) { return nuiCallback(name, data || {}); }

/** A choice as pill tabs, the chosen one the white pill. `dots`: each wears its kind's colour. */
function segButtons(items, current, onPick, dots) {
    const row = h('div', 'ce-tabs' + (dots ? ' ce-tabs-kinds' : ''));
    for (const it of items) {
        const b = h('button', 'ce-tab' + (it.key === current ? ' on' : ''));
        b.type = 'button';
        if (dots) b.appendChild(h('span', 'ce-kdot ce-kind-' + it.key));
        b.appendChild(h('span', null, it.label));
        if (it.tip) b.title = it.tip;
        b.addEventListener('click', () => onPick(it.key));
        row.appendChild(b);
    }
    return row;
}

/** A section of a panel: a hairline over it, its name in the label role. */
function section(parent, label, first) {
    const s = h('div', 'ce-section' + (first ? ' ce-section-first' : ''));
    if (label) s.appendChild(h('div', 'ce-sec', label));
    parent.appendChild(s);
    return s;
}

/** A panel's head: its disc (a glyph's name, or a number), its title, and what it is now. */
function head(parent, disc, title) {
    const row = h('div', 'ce-head');
    const d = h('div', 'ce-disc');
    if (typeof disc === 'number') { d.classList.add('ce-disc-num'); d.textContent = String(disc); }
    else d.innerHTML = GLYPHS()[disc] || '';
    const text = h('div', 'ce-head-text');
    text.appendChild(h('div', 'ce-title', title));
    const now = h('div', 'ce-now');
    text.appendChild(now);
    row.appendChild(d);
    row.appendChild(text);
    parent.appendChild(row);
    return { row, disc: d, now };
}

// ---- the controls: keycaps on a keyboard, the buttons' pictures on a pad ----

/** A keyboard key as caps: 'Ctrl + Z' is two caps joined by +, '← / →' two joined by /. RMB and Wheel
 *  are the mouse's, drawn. */
function keyCaps(key) {
    const box = h('span', 'ce-caps ce-k-kbm');
    String(key).split(/\s+([+/])\s+/).forEach((part) => {
        if (part === '+' || part === '/') { box.appendChild(h('span', 'ce-join', part)); return; }
        if (part === '') return;
        const cap = h('span', 'ce-cap');
        if (part === 'RMB') cap.innerHTML = ICON.rmb;
        else if (part === 'Wheel') cap.innerHTML = ICON.wheel;
        else cap.textContent = part;
        box.appendChild(cap);
    });
    return box;
}

/** A pad's buttons as their pictures (a name, or a list joined by / — or by `join`, '+' for held together). */
function padCaps(pad, join) {
    const box = h('span', 'ce-caps ce-k-pad');
    (Array.isArray(pad) ? pad : [pad]).forEach((name, i) => {
        if (i > 0) box.appendChild(h('span', 'ce-join', join || '/'));
        const img = padGlyph(String(name), 'ce-padg');
        if (img) box.appendChild(img);
    });
    return box;
}

/** One control: { key, pad, text, off, padJoin }. `key = null`: a pad's alone; `pad = null`: a keyboard's
 *  alone. `padJoin = '+'`: the pad's buttons are held together (LB + R3). */
function hintEl(c) {
    const cls = 'ce-hint' + (c.off ? ' off' : '') + (c.pad == null ? ' kbm-only' : '') + (c.key == null ? ' pad-only' : '');
    const row = h('span', cls);
    if (c.key != null) row.appendChild(keyCaps(c.key));
    if (c.pad != null) row.appendChild(padCaps(c.pad, c.padJoin));
    row.appendChild(h('span', null, c.text));
    return row;
}

// ---- dropdowns: the editor's own list, not the browser's ----
//
// CEF's native <select> list is a popup of its own, and over the game (the page shares the keyboard with
// it, keep-input) it did not always open: "I click the dropdown and nothing happens". This one is drawn in
// the page: a box showing the choice, and a list under it (above, without room) that closes on a pick, a
// click elsewhere, Esc, a scroll, or the page being drawn again.

let ddOpen = null;   // { list, anchor } while a list is open

function closeDropdown() {
    if (!ddOpen) return;
    ddOpen.list.remove();
    ddOpen.anchor.classList.remove('open');
    ddOpen = null;
}

function openDropdown(anchor, items, current, onPick) {
    closeDropdown();
    const list = h('div', 'ce-dd-list');
    for (const it of items) {
        const o = h('button', 'ce-dd-opt' + (it.key === current ? ' on' : ''), it.label);
        o.type = 'button';
        o.addEventListener('click', (e) => {
            e.stopPropagation();
            closeDropdown();
            if (it.key !== current) onPick(it.key);
        });
        list.appendChild(o);
    }
    // Placed in the scaled box, in its own pixels: the screen's over the scale.
    const box = el.root.querySelector('.ce-scale');
    const r = anchor.getBoundingClientRect();
    const b = box.getBoundingClientRect();
    const zoom = (r.width / anchor.offsetWidth) || 1;
    list.style.left = ((r.left - b.left) / zoom) + 'px';
    list.style.minWidth = anchor.offsetWidth + 'px';
    box.appendChild(list);
    const below = (r.bottom - b.top) / zoom + 4;
    const above = (r.top - b.top) / zoom - 4 - list.offsetHeight;
    list.style.top = (below + list.offsetHeight > box.offsetHeight && above > 0 ? above : below) + 'px';
    anchor.classList.add('open');
    ddOpen = { list, anchor };
}

/** A choice of `items` ({ key, label }) in a box: its list opens under it. */
function select(items, current, onPick) {
    const s = h('button', 'ce-select');
    s.type = 'button';
    const cur = items.find((it) => it.key === current);
    s.textContent = cur ? cur.label : (current == null ? '' : String(current));
    s.addEventListener('click', (e) => {
        e.preventDefault();
        e.stopPropagation();
        if (ddOpen && ddOpen.anchor === s) { closeDropdown(); return; }
        openDropdown(s, items, current, onPick);
    });
    return s;
}

/** On / off: the /w menu's switch, then its name. */
function toggle(label, on, onFlip) {
    const b = h('button', 'ce-switch-row' + (on ? ' on' : ''));
    b.type = 'button';
    b.appendChild(h('span', 'ce-switch'));
    b.appendChild(h('span', null, label));
    b.addEventListener('click', () => onFlip(!on));
    return b;
}

/** A button. `icon` (an ICON name) goes before the label, or is the whole button with no label. */
function btn(label, onClick, cls, title, icon) {
    const b = h('button', 'ce-btn' + (cls ? ' ' + cls : ''));
    b.type = 'button';
    if (icon) b.insertAdjacentHTML('beforeend', ICON[icon]);
    if (label) b.appendChild(h('span', null, label));
    if (title) b.title = title;
    b.addEventListener('click', onClick);
    return b;
}

/** A labelled number box. `onCommit(value|null)` on Enter / leaving the box / the spinner. */
function numberField(label, value, step, min, max, unit, onCommit) {
    const wrap = h('label', 'ce-field');
    wrap.appendChild(h('span', 'ce-field-label', label));
    const box = h('span', 'ce-field-box');
    const i = h('input', 'ce-input');
    i.type = 'number';
    i.step = String(step);
    if (min !== undefined) i.min = String(min);
    if (max !== undefined) i.max = String(max);
    i.value = fmtNum(value);
    i.placeholder = '—';
    i.addEventListener('change', () => {
        const v = i.value.trim() === '' ? null : Number(i.value);
        onCommit(v === null || Number.isFinite(v) ? v : null);
    });
    box.appendChild(i);
    if (unit) box.appendChild(h('span', 'ce-unit', unit));
    wrap.appendChild(box);
    return wrap;
}

// ---- the card: the sequence ----

function renderCard() {
    const c = el.cardBody;
    c.innerHTML = '';
    const top = head(c, 'camera', 'Camera Creator');
    const changed = st.savedAs ? st.dirty : keys().length > 0;
    const name = st.savedAs ? st.savedAs + (st.dirty ? ' · changed' : '') : (keys().length ? 'Not saved' : 'New sequence');
    top.now.appendChild(h('span', 'ce-chip-static' + (st.savedAs && !st.dirty ? ' ok' : ''), name));
    top.now.appendChild(h('span', null, keys().length === 1 ? '1 key' : keys().length + ' keys'));

    // Save is the white pill while there is something to save.
    const files = section(c, null);
    const row = h('div', 'ce-btns');
    row.appendChild(btn('New', () => cbk('ceNew'), '', 'Start an empty sequence'));
    row.appendChild(btn('Open', () => { modal = 'open'; renderModal(); cbk('ceList'); }, '', 'A saved sequence'));
    row.appendChild(btn('Save', () => { if (st.savedAs) cbk('ceSave', { name: st.savedAs }); else { modal = 'save'; renderModal(); } },
        changed ? 'primary' : '', 'On the server, by name (Ctrl+S)'));
    row.appendChild(btn('Copy code', () => cbk('ceCopy'), '', 'As a Lua call, to paste into a script'));
    files.appendChild(row);

    const sq = section(c, 'Sequence');
    const seq = st.seq || {};
    const grid = h('div', 'ce-grid');
    grid.appendChild(numberField('Length', seqLength() / 1000, 0.1, 0, 1800, 's', (v) => cbk('ceSeq', { field: 'length', value: (v || 0) * 1000 })));
    const anchorWrap = h('label', 'ce-field');
    anchorWrap.appendChild(h('span', 'ce-field-label', 'Plays round'));
    anchorWrap.appendChild(select([{ key: 'none', label: 'The world' }].concat(SUBJECTS), seq.anchor || 'none',
        (v) => cbk('ceSeq', { field: 'anchor', value: v })));
    grid.appendChild(anchorWrap);
    // (No whole-timeline pace: it bent time, so keys stopped happening where the timeline shows them. Each
    // glide has its own pace.)
    const evenWrap = h('div', 'ce-field');
    evenWrap.appendChild(h('span', 'ce-field-label', 'Spacing'));
    evenWrap.appendChild(btn('Even speed', () => cbk('ceEven'), '', 'Space the keys so the camera keeps one speed'));
    grid.appendChild(evenWrap);
    sq.appendChild(grid);
    const flags = h('div', 'ce-row');
    flags.appendChild(toggle('Loop', !!seq.loop, (on) => cbk('ceSeq', { field: 'loop', value: on })));
    flags.appendChild(h('span', 'ce-spacer'));
    flags.appendChild(toggle('Cinema bars', !!seq.letterbox, (on) => cbk('ceSeq', { field: 'letterbox', value: on })));
    flags.appendChild(h('span', 'ce-spacer'));
    sq.appendChild(flags);

    const nk = section(c, 'New keys');
    nk.appendChild(segButtons(KINDS, st.newKind, (k) => cbk('ceSeq', { field: 'newKind', value: k }), true));
    if (st.newKind !== 'fixed') {
        const of = h('div', 'ce-row');
        of.appendChild(select(SUBJECTS, st.newSubject, (v) => cbk('ceSeq', { field: 'newSubject', value: v })));
        of.appendChild(btn('Pick', () => cbk('cePick'), '', 'The car, person or prop in the middle of the screen'));
        nk.appendChild(of);
    }
    if (st.target) nk.appendChild(h('div', 'ce-note', 'Picked: ' + st.target));

    // Playing in game: how cameras switch, and how clean the screen is (this PC's own choices).
    const pg = section(c, 'Playing in game');
    const sw = h('div', 'ce-row');
    sw.appendChild(h('span', 'ce-field-label', 'Switching'));
    const swTabs = segButtons([{ key: 'cut', label: 'Cut' }, { key: 'smooth', label: 'Smooth' }], st.smooth ? 'smooth' : 'cut',
        (v) => cbk('cePref', { field: 'smooth', value: v === 'smooth' }));
    swTabs.classList.add('ce-seg');
    sw.appendChild(h('span', 'ce-spacer'));
    sw.appendChild(swTabs);
    pg.appendChild(sw);
    pg.appendChild(toggle('Clean screen the whole time', st.cleanAll !== false, (on) => cbk('cePref', { field: 'cleanAll', value: on })));
    pg.appendChild(h('div', 'ce-note', 'F9 plays in game: F5 rolls the shots, Page Up / Down or Num 1–9 cut between cameras, F9 comes back. Record the screen.'));

    // The camera, as it flies: the editor card's readings.
    const cam = section(c, null);
    const rd = h('div', 'ce-readings');
    el.read = {};
    for (const [k, label] of [['pos', 'Position'], ['look', 'Pitch · heading'], ['lens', 'Lens · speed']]) {
        rd.appendChild(h('span', 'ce-r-label', label));
        el.read[k] = h('span', 'ce-r-value', '—');
        rd.appendChild(el.read[k]);
    }
    cam.appendChild(rd);
    if (lastCam) showCamera(lastCam);
}

// ---- the inspector: the picked key ----

function renderInspector() {
    const p = el.insp;
    p.innerHTML = '';
    const i = st.sel;
    const k = i ? keys()[i - 1] : null;
    p.classList.toggle('ce-hidden', !k);
    if (!k) return;
    const shot = k.shot || {};
    const set = (field, value) => cbk('ceEditKey', { i, field, value });

    // The head: the key's number in a disc ringed in its kind's colour (its gizmo in the world wears the
    // number too), its time, and putting it down.
    const top = head(p, i, 'Key ' + i);
    top.disc.classList.add('ce-kind-' + shot.kind);
    top.now.appendChild(h('span', 'ce-chip-static', fmtTime(k.t)));
    top.now.appendChild(h('span', null, (KINDS.find((x) => x.key === shot.kind) || {}).label || ''));
    top.row.appendChild(btn('', () => cbk('ceSelect', { i: 0 }), 'ghost small icon', 'Put it down (Esc)', 'close'));

    const what = section(p, 'Shot');
    what.appendChild(segButtons(KINDS, shot.kind, (kind) => cbk('ceSetKind', { i, kind }), true));
    if (shot.kind !== 'fixed') {
        const row = h('label', 'ce-field');
        row.appendChild(h('span', 'ce-field-label', 'Of'));
        row.appendChild(select(SUBJECTS, shot.subject, (v) => set('shot.subject', v)));
        what.appendChild(row);
    }
    const grid = h('div', 'ce-grid');
    grid.appendChild(numberField('Time', k.t / 1000, 0.05, 0, 1800, 's', (v) => set('t', (v || 0) * 1000)));
    for (const [field, label, step, min, max, unit] of (FIELDS[shot.kind] || [])) {
        // An orbit is a fill OR a distance: the other is shown empty.
        grid.appendChild(numberField(label, get(k, field), step, min, max, unit, (v) => set(field, v)));
    }
    what.appendChild(grid);
    if (shot.kind === 'chase') {
        what.appendChild(toggle('Pull in at walls', shot.collision !== false, (on) => set('shot.collision', on)));
    }

    const last = i === keys().length;
    const then = section(p, last ? 'Then (the last key: it holds)' : 'Then, to key ' + (i + 1));
    if (!last) {
        then.appendChild(segButtons(MOVES, k.move || 'glide', (m) => set('move', m)));
        if ((k.move || 'glide') !== 'cut') {
            const g2 = h('div', 'ce-grid');
            const ks = keys();
            const gliding = (k.move || 'glide') === 'glide';
            const [first, end] = gliding ? glideSpan(ks, i) : [i, i + 1];
            let note = null;
            if (k.move === 'spring') {
                g2.appendChild(numberField('Briskness', k.rate || 4, 0.5, 0.5, 30, '', (v) => set('rate', v)));
            } else if (gliding && first < i) {
                // Inside a glide: it flows through; the glide's pace is its first key's.
                note = 'Part of the glide from key ' + first + ': the camera flows through here without stopping. Its pace is on key ' + first + '.';
            } else {
                const ew = h('label', 'ce-field');
                ew.appendChild(h('span', 'ce-field-label', 'Pace'));
                ew.appendChild(select(EASES, k.ease || 'smooth', (v) => set('ease', v)));
                g2.appendChild(ew);
                if (gliding && end > i + 1) {
                    note = 'Keys ' + i + ' to ' + end + ' glide as one move: it starts and ends at this pace and flows through the keys between without stopping.';
                }
            }
            if (k.move === 'orbit') {
                const aw = h('label', 'ce-field');
                aw.appendChild(h('span', 'ce-field-label', 'Way round'));
                aw.appendChild(select([{ key: 'short', label: 'Shortest' }, { key: 'left', label: 'Left' }, { key: 'right', label: 'Right' }],
                    k.around || 'short', (v) => set('around', v)));
                g2.appendChild(aw);
            }
            if (g2.childNodes.length) then.appendChild(g2);
            if (note) then.appendChild(h('div', 'ce-note', note));
        }
    }

    // Weight: a move arrives here, and the camera can carry on past this key instead of stopping on it
    // (shared/cam_sequence.lua, coast). It does where the camera stops: the last key, or one cut from.
    const ksAll = keys();
    const prevKey = ksAll[i - 2];
    if (prevKey && (prevKey.move || 'glide') !== 'cut' && prevKey.t < k.t) {
        const wt = section(p, 'Weight');
        const on = typeof k.coast === 'number';
        wt.appendChild(toggle('Carries on past this key', on, (yes) => set('coast', yes ? 2 : null)));
        if (on) {
            const g = h('div', 'ce-grid');
            g.appendChild(numberField('Resistance', k.coast, 0.1, 0.2, 50, '', (v) => set('coast', v === null ? null : v)));
            wt.appendChild(g);
        }
        const stops = last || (k.move || 'glide') === 'cut' || (ksAll[i] && ksAll[i].t <= k.t);
        wt.appendChild(h('div', 'ce-note', !stops
            ? 'It carries on only where the camera stops: make this the last key, or set Then to Cut.'
            : on ? 'The camera arrives at the speed it was going and drifts on the same way, turning and zooming as it was, slowing to a stop. Low resistance goes further.'
                 : 'A heavy camera: it arrives at the speed it was going and drifts on past this key instead of stopping on it.'));
    }

    const layers = section(p, 'Layers');
    const g3 = h('div', 'ce-grid');
    g3.appendChild(numberField('Shake', k.shake ? k.shake.amount : null, 0.05, 0, 10, '°', (v) => set('shake.amount', v)));
    g3.appendChild(numberField('Shake speed', k.shake ? k.shake.freq : null, 0.5, 0.2, 40, 'Hz', (v) => set('shake.freq', v)));
    g3.appendChild(numberField('Lens kick', k.punch ? k.punch.fov : null, 0.5, -60, 60, '°', (v) => set('punch.fov', v)));
    g3.appendChild(numberField('Kick fades', k.punch ? k.punch.decay : null, 0.5, 0.2, 30, '', (v) => set('punch.decay', v)));
    const fw = h('label', 'ce-field ce-field-wide');
    fw.appendChild(h('span', 'ce-field-label', 'Filter from here'));
    const filters = (st.filters || ['none']).map((f) => ({ key: f, label: f === 'none' ? 'None' : f }));
    fw.appendChild(select(filters, k.filter || 'none', (v) => set('filter', v)));
    g3.appendChild(fw);
    layers.appendChild(g3);

    // The white pill is this panel's one: putting the key where the camera is.
    const acts = section(p, null);
    const two = h('div', 'ce-btns ce-btns-2');
    two.appendChild(btn('Set to camera', () => cbk('ceSetFromCamera', { i }), 'primary', 'This key, where the camera is now (E)'));
    two.appendChild(btn('Look through', () => cbk('ceLookThrough', { i }), '', 'The camera to this key, to fly on from it (F)'));
    two.appendChild(btn('Duplicate', () => cbk('ceDuplicate', { i }), '', 'Ctrl+D'));
    two.appendChild(btn('Delete', () => cbk('ceDelete', { i }), 'danger', 'Delete'));
    acts.appendChild(two);
}

// ---- the dock: transport and timeline ----

function buildDock() {
    const d = el.dock;
    d.innerHTML = '';
    // The transport: the key before, play (the house disc), the key after, the time; flying or looking
    // through; adding a key (this panel's white pill). Then undo, the timeline's zoom, and the screen's
    // own: the camera points, the HUD, leaving.
    const bar = h('div', 'ce-transport');
    el.prev = btn('', () => cbk('ceStep', { dir: -1 }), 'ghost icon', 'The key before (←)', 'prev');
    el.play = btn('', () => cbk('cePlay', {}), 'ce-play', 'Play / pause (Space)', 'play');
    el.next = btn('', () => cbk('ceStep', { dir: 1 }), 'ghost icon', 'The next key (→)', 'next');
    bar.appendChild(el.prev); bar.appendChild(el.play); bar.appendChild(el.next);
    el.time = h('div', 'ce-time');
    el.timeNow = h('span', 'ce-time-now', '0:00.00');
    el.timeLen = h('span', 'ce-time-len', '/ 0:00.00');
    el.time.appendChild(el.timeNow);
    el.time.appendChild(el.timeLen);
    bar.appendChild(el.time);
    el.viewTabs = h('div', 'ce-tabs ce-seg');
    el.viewFly = h('button', 'ce-tab', 'Fly');
    el.viewLook = h('button', 'ce-tab', 'Look through');
    el.viewFly.type = el.viewLook.type = 'button';
    el.viewFly.title = 'Fly the camera (V)';
    el.viewLook.title = 'See the timeline\'s picture at the playhead (V). Holding the right mouse button flies on from it.';
    el.viewFly.addEventListener('click', () => { if (viewing) cbk('ceView', {}); });
    el.viewLook.addEventListener('click', () => { if (!viewing) cbk('ceView', {}); });
    el.viewTabs.appendChild(el.viewFly);
    el.viewTabs.appendChild(el.viewLook);
    bar.appendChild(el.viewTabs);
    el.add = btn('Key here', () => cbk('ceAdd', {}), 'primary', 'A key where the camera is, at the playhead (G)', 'plus');
    bar.appendChild(el.add);
    bar.appendChild(h('span', 'ce-spacer'));
    // Who has the controls: the camera (your character holds still) or the game (you drive and walk, the
    // camera holds still). Tab, or LB + R3 on a pad.
    const ctl = h('div', 'ce-ctl');
    ctl.appendChild(h('span', 'ce-field-label', 'Controls'));
    el.ctlTabs = h('div', 'ce-tabs ce-seg');
    el.ctlCam = h('button', 'ce-tab', 'Camera');
    el.ctlGame = h('button', 'ce-tab', 'Game');
    el.ctlCam.type = el.ctlGame.type = 'button';
    el.ctlCam.title = 'The editor has the controls: your character and your car hold still (Tab)';
    el.ctlGame.title = 'Your character has the controls: drive and walk with the editor still up (Tab)';
    el.ctlCam.addEventListener('click', () => cbk('ceControls', { game: false }));
    el.ctlGame.addEventListener('click', () => cbk('ceControls', { game: true }));
    el.ctlTabs.appendChild(el.ctlCam);
    el.ctlTabs.appendChild(el.ctlGame);
    ctl.appendChild(el.ctlTabs);
    bar.appendChild(ctl);
    bar.appendChild(h('span', 'ce-sep'));
    el.undo = btn('Undo', () => cbk('ceUndo'), 'ghost', 'Ctrl+Z');
    el.redo = btn('Redo', () => cbk('ceRedo'), 'ghost', 'Ctrl+Y');
    bar.appendChild(el.undo); bar.appendChild(el.redo);
    bar.appendChild(btn('', () => zoomBy(1.25), 'ghost icon', 'Show more of the timeline (wheel)', 'zoomOut'));
    bar.appendChild(btn('', () => zoomBy(0.8), 'ghost icon', 'Show less of it, closer', 'zoomIn'));
    bar.appendChild(h('span', 'ce-sep'));
    bar.appendChild(btn('Play in game', () => cbk('cePlayInGame'), '', 'Back to your character with the shots ready: F5 rolls them while you play, F9 comes back here (F9)', 'game'));
    el.points = btn('Hide points', () => cbk('cePoints', {}), '', 'The camera points and the path in the world (P)', 'points');
    bar.appendChild(el.points);
    bar.appendChild(btn('Hide HUD', () => cbk('ceHud', { on: true }), '', 'Everything on screen, for a clean picture (H; H again, Esc or a click brings it back)', 'hud'));
    bar.appendChild(btn('Exit', () => cbk('ceClose'), '', 'Leave the Camera Creator; your draft is kept (Esc)', 'exit'));
    d.appendChild(bar);

    // The timeline, and inside it the track its times are measured on: inset, so a key at the very start
    // or end shows whole rather than half outside.
    const tl = h('div', 'ce-timeline');
    const track = h('div', 'ce-track');
    el.ruler = h('div', 'ce-ruler');
    el.lane = h('div', 'ce-lane');
    el.head = h('div', 'ce-playhead');
    el.head.appendChild(h('div', 'ce-playhead-grip'));
    track.appendChild(el.ruler);
    track.appendChild(el.lane);
    track.appendChild(el.head);
    tl.appendChild(track);
    el.timeline = tl;
    d.appendChild(tl);

    el.hints = h('div', 'ce-hints', '');
    d.appendChild(el.hints);

    // Scrub: press on the ruler or the lane's empty part, and drag.
    const scrubFrom = (e) => {
        if (e.button !== 0 || looking) return;
        if (e.target.closest('.ce-key')) return;
        e.preventDefault();
        tl.setPointerCapture(e.pointerId);
        let queued = false, lastT = null;
        const go = (ev) => {
            lastT = snap(timeAt(ev.clientX), ev.shiftKey);
            playhead = lastT;
            placeHead();
            if (queued) return;
            queued = true;
            requestAnimationFrame(() => { queued = false; cbk('ceScrub', { t: lastT }); });
        };
        go(e);
        const move = (ev) => go(ev);
        const up = () => {
            tl.removeEventListener('pointermove', move);
            tl.removeEventListener('pointerup', up);
            tl.removeEventListener('pointercancel', up);
        };
        tl.addEventListener('pointermove', move);
        tl.addEventListener('pointerup', up);
        tl.addEventListener('pointercancel', up);
    };
    tl.addEventListener('pointerdown', scrubFrom);
    tl.addEventListener('dblclick', (e) => {
        if (e.target.closest('.ce-key')) return;
        cbk('ceAdd', { t: snap(timeAt(e.clientX), e.shiftKey) });
    });
    tl.addEventListener('wheel', (e) => {
        e.preventDefault();
        if (e.shiftKey) {
            viewStart = Math.max(0, viewStart + Math.sign(e.deltaY) * viewSpan * 0.15);
            userZoomed = true;
            renderTimeline();
        } else {
            zoomBy(e.deltaY > 0 ? 1.15 : 1 / 1.15, timeAt(e.clientX));
        }
    }, { passive: false });
}

function laneRect() { return el.lane.getBoundingClientRect(); }

/** The time under a screen x (the page is scaled: measured in screen pixels on both sides). */
function timeAt(clientX) {
    const r = laneRect();
    const f = (clientX - r.left) / Math.max(1, r.width);
    return Math.max(0, viewStart + f * viewSpan);
}

function xAt(t) { return ((t - viewStart) / viewSpan) * 100; }   // percent of the lane

function snap(t, coarse) {
    const s = coarse ? SNAP_SHIFT : SNAP;
    return Math.max(0, Math.round(t / s) * s);
}

function zoomBy(f, around) {
    const at = around !== undefined ? around : playhead;
    const share = (at - viewStart) / viewSpan;
    viewSpan = Math.min(Math.max(viewSpan * f, 1000), 30 * 60 * 1000);
    viewStart = Math.max(0, at - share * viewSpan);
    userZoomed = true;
    renderTimeline();
}

/** The window follows the sequence until the user zooms it themselves. */
function fitView() {
    if (userZoomed) return;
    viewStart = 0;
    viewSpan = Math.max(seqLength() * 1.12 + 1000, 8000);
}

function placeHead() {
    el.head.style.left = xAt(playhead) + '%';
    el.head.style.display = playhead < viewStart - 1 || playhead > viewStart + viewSpan + 1 ? 'none' : '';
    el.timeNow.textContent = fmtTime(playhead);
    el.timeLen.textContent = '/ ' + fmtTime(seqLength());
}

function renderTimeline() {
    if (!el.lane) return;
    // The ruler.
    el.ruler.innerHTML = '';
    const pxPerMs = laneRect().width / viewSpan;
    let step = TICKS[TICKS.length - 1];
    for (const s of TICKS) { if (s * pxPerMs >= 64) { step = s; break; } }
    const first = Math.ceil(viewStart / step) * step;
    for (let t = first; t <= viewStart + viewSpan; t += step) {
        const tick = h('div', 'ce-tick');
        tick.style.left = xAt(t) + '%';
        tick.appendChild(h('span', 'ce-tick-label', step < 1000 ? (t / 1000).toFixed(1) + 's' : fmtTime(t).replace(/\.00$/, '')));
        el.ruler.appendChild(tick);
    }
    // The end of the sequence.
    el.lane.innerHTML = '';
    const end = h('div', 'ce-end');
    end.style.left = xAt(seqLength()) + '%';
    el.lane.appendChild(end);

    // The moves between keys, then the keys over them.
    const ks = keys();
    for (let i = 0; i < ks.length - 1; i++) {
        const a = ks[i], b = ks[i + 1];
        if (b.t <= a.t) continue;
        const move = a.move || 'glide';
        const seg = h('div', 'ce-move ce-move-' + move);
        seg.style.left = xAt(a.t) + '%';
        seg.style.width = (xAt(b.t) - xAt(a.t)) + '%';
        // A stretch inside a glide shows no pace: the glide's is on its first stretch. One into a weighted key
        // that the camera stops at does not brake: it says so instead of its pace's end.
        const inGlide = move === 'glide' && glidesOn(ks, i);
        const next = ks[i + 2];
        const intoWeight = typeof b.coast === 'number' && (!next || (b.move || 'glide') === 'cut' || next.t <= b.t);
        const word = move === 'cut' ? 'Cut' : (MOVES.find((m) => m.key === move) || {}).label
            + (intoWeight && move !== 'spring' ? ' · carries on'
                : move === 'spring' || inGlide ? '' : ' · ' + ((EASES.find((e) => e.key === (a.ease || 'smooth')) || {}).label || ''));
        seg.appendChild(h('span', 'ce-move-word', word));
        el.lane.appendChild(seg);
    }
    ks.forEach((k, idx) => {
        const i = idx + 1;
        const chip = h('div', 'ce-key ce-kind-' + (k.shot && k.shot.kind) + (st.sel === i ? ' on' : ''));
        chip.style.left = xAt(k.t) + '%';
        chip.title = (k.label ? k.label + ' · ' : '') + fmtTime(k.t) + ' · ' + ((KINDS.find((x) => x.key === k.shot.kind) || {}).label || '');
        chip.appendChild(h('span', 'ce-key-n', String(i)));
        const marks = (k.shake ? '≈' : '') + (k.punch ? '!' : '') + (k.filter ? '◐' : '') + (typeof k.coast === 'number' ? '»' : '');
        if (marks) chip.appendChild(h('span', 'ce-key-marks', marks));
        chip.addEventListener('pointerdown', (e) => keyDrag(e, i, k, chip));
        el.lane.appendChild(chip);
    });
    placeHead();
}

/** A key pressed: picked on release, moved if dragged. */
function keyDrag(e, i, k, chip) {
    if (e.button !== 0 || looking) return;
    e.preventDefault();
    e.stopPropagation();
    chip.setPointerCapture(e.pointerId);
    const startX = e.clientX;
    let moved = false, t = k.t;
    const move = (ev) => {
        if (!moved && Math.abs(ev.clientX - startX) < 4) return;
        moved = true;
        t = snap(timeAt(ev.clientX), ev.shiftKey);
        chip.style.left = xAt(t) + '%';
        chip.classList.add('dragging');
    };
    const up = () => {
        chip.removeEventListener('pointermove', move);
        chip.removeEventListener('pointerup', up);
        chip.removeEventListener('pointercancel', up);
        if (moved && t !== k.t) cbk('ceMoveKey', { i, t });
        else if (!moved) cbk('ceSelect', { i });
        else renderTimeline();
    };
    chip.addEventListener('pointermove', move);
    chip.addEventListener('pointerup', up);
    chip.addEventListener('pointercancel', up);
}

function renderTransport() {
    if (!el.play) return;
    const ps = playing ? 'pause' : 'play';
    if (ps !== playShape) {
        playShape = ps;
        el.play.innerHTML = ICON[ps];
        el.play.classList.toggle('on', playing);
    }
    el.viewFly.classList.toggle('on', !viewing);
    el.viewLook.classList.toggle('on', viewing);
    const driving = !!st.drive;
    el.ctlCam.classList.toggle('on', !driving);
    el.ctlGame.classList.toggle('on', driving);
    el.root.classList.toggle('ce-drive', driving);
    el.undo.disabled = !st.canUndo;
    el.redo.disabled = !st.canRedo;
    const hidden = !!st.hidePoints;
    el.points.innerHTML = ICON[hidden ? 'pointsOff' : 'points'];
    el.points.appendChild(h('span', null, hidden ? 'Show points' : 'Hide points'));
    el.root.classList.toggle('ce-nohud', !!st.hideHud);
    renderHints();
}

/** The controls row: what each key and button does now. Rebuilt only when what it says changes. */
function renderHints() {
    const picked = !!(st && st.sel);
    const driving = !!(st && st.drive);
    const shape = [picked, viewing, playing, !!(st && st.hidePoints), driving].join('|');
    if (shape === hintsShape) return;
    hintsShape = shape;
    const box = el.hints;
    box.innerHTML = '';
    // Your character has the controls: the game's keys drive; the editor's stand down but these.
    if (driving) {
        box.appendChild(h('span', 'ce-hint-group', 'Your character has the controls'));
        for (const c of [
            { key: 'Tab', pad: ['lb', 'r3'], padJoin: '+', text: 'Controls back to the camera' },
            { key: 'Esc', pad: null, text: 'Controls back to the camera' },
        ]) box.appendChild(hintEl(c));
        return;
    }
    box.appendChild(h('span', 'ce-hint-group', 'Camera'));
    const fly = [
        { key: 'RMB', pad: null, text: 'Hold to fly' },
        { key: 'WASD', pad: null, text: 'Move' },
        { key: 'Space / Ctrl', pad: null, text: 'Up / down' },
        { key: 'Shift', pad: null, text: 'Faster' },
        { key: 'Wheel', pad: null, text: 'Lens' },
        { key: null, pad: 'ls', text: 'Move' },
        { key: null, pad: 'rs', text: 'Look' },
        { key: null, pad: ['rt', 'lt'], text: 'Up / down' },
        { key: null, pad: 'l3', text: 'Faster' },
        { key: null, pad: ['dpad_up', 'dpad_down'], text: 'Lens' },
    ];
    for (const c of fly) box.appendChild(hintEl(c));
    box.appendChild(h('span', 'ce-hint-sep'));
    const acts = [
        { key: 'G', pad: 'a', text: 'Add a key' },
        { key: 'E', pad: 'x', text: 'Set here', off: !picked },
        { key: 'F', pad: null, text: 'Fly from the key', off: !picked },
        { key: 'V', pad: 'view', text: viewing ? 'Fly' : 'Look through' },
        { key: 'Space', pad: 'rb', text: playing ? 'Pause' : 'Play' },
        { key: '← / →', pad: ['dpad_left', 'dpad_right'], text: 'Keys' },
        { key: 'Del', pad: 'y', text: 'Delete', off: !picked },
        { key: 'Ctrl + Z', pad: null, text: 'Undo' },
        { key: null, pad: 'r3', text: 'Kind' },
        { key: null, pad: 'menu', text: 'Save' },
        { key: 'Tab', pad: ['lb', 'r3'], padJoin: '+', text: 'Controls to your character' },
        { key: 'F9', pad: null, text: 'Play in game' },
        { key: 'P', pad: null, text: st && st.hidePoints ? 'Show points' : 'Hide points' },
        { key: 'H', pad: null, text: 'Hide HUD' },
        { key: null, pad: 'view', text: 'Hold: hide HUD' },
        { key: 'Esc', pad: null, text: picked ? 'Put down' : 'Exit' },
        { key: null, pad: 'b', text: 'Exit' },
    ];
    for (const c of acts) box.appendChild(hintEl(c));
}

// ---- the modal: open / save ----

function renderModal() {
    const m = el.modal;
    m.innerHTML = '';
    m.classList.toggle('ce-hidden', !modal);
    if (!modal) return;
    const box = h('div', 'ce-modal-box');
    if (modal === 'save') {
        box.appendChild(h('div', 'ce-title', 'Save the sequence'));
        box.appendChild(h('div', 'ce-note', 'A name scripts play it by: letters, digits, _ and -.'));
        const i = h('input', 'ce-input ce-input-text');
        i.type = 'text';
        i.maxLength = 60;
        i.placeholder = 'intro_shot';
        i.value = st.savedAs || '';
        box.appendChild(i);
        const row = h('div', 'ce-row');
        const go = () => {
            const name = i.value.trim();
            if (!/^[A-Za-z0-9_-]{1,60}$/.test(name)) { i.classList.add('bad'); return; }
            cbk('ceSave', { name });
            modal = null;
            renderModal();
        };
        i.addEventListener('keydown', (e) => { if (e.key === 'Enter') go(); });
        row.appendChild(btn('Save', go, 'primary'));
        row.appendChild(btn('Cancel', () => { modal = null; renderModal(); }, ''));
        box.appendChild(row);
        m.appendChild(box);
        setTimeout(() => i.focus(), 0);
        return;
    }
    box.appendChild(h('div', 'ce-title', 'Open a sequence'));
    if (!savedList.length) box.appendChild(h('div', 'ce-note', 'None saved yet.'));
    const list = h('div', 'ce-list');
    for (const s of savedList) {
        const row = h('div', 'ce-list-row');
        if (askingDelete === s.name) {
            const ask = h('div', 'ce-list-open');
            ask.appendChild(h('span', 'ce-list-name', 'Delete ' + s.name + '?'));
            ask.appendChild(h('span', 'ce-list-sub', 'Scripts that play it by name will find nothing.'));
            row.appendChild(ask);
            row.appendChild(btn('Delete', () => { askingDelete = null; cbk('ceDeleteSaved', { name: s.name }); renderModal(); }, 'danger small'));
            row.appendChild(btn('Keep', () => { askingDelete = null; renderModal(); }, 'small'));
            list.appendChild(row);
            continue;
        }
        const open1 = h('button', 'ce-list-open');
        open1.type = 'button';
        open1.appendChild(h('span', 'ce-list-name', s.name));
        open1.appendChild(h('span', 'ce-list-sub', s.keys + ' keys · ' + fmtTime(s.length) + (s.by ? ' · ' + s.by : '')));
        open1.addEventListener('click', () => { cbk('ceLoad', { name: s.name }); modal = null; renderModal(); });
        row.appendChild(open1);
        if (mayEdit) row.appendChild(btn('Delete', () => { askingDelete = s.name; renderModal(); }, 'danger small'));
        list.appendChild(row);
    }
    box.appendChild(list);
    const foot = h('div', 'ce-row');
    foot.appendChild(btn('Close', () => { modal = null; renderModal(); }, ''));
    box.appendChild(foot);
    m.appendChild(box);
}

// ---- state from Lua ----

function render() {
    if (!st) return;
    closeDropdown();   // its box is about to be drawn again
    el.root.classList.toggle('ce-looking', looking);
    el.root.classList.toggle('ce-pad', pad);
    renderCard();
    renderInspector();
    fitView();
    renderTimeline();
    renderTransport();
}

function show() {
    if (!el.root) build();
    open = true;
    userZoomed = false;
    el.root.classList.add('ce-open');
}

function hide() {
    open = false;
    modal = null;
    closeDropdown();
    if (el.root) {
        el.root.classList.remove('ce-open');
        renderModal();
    }
    if (typing) { typing = false; cbk('ceTyping', { on: false }); }
}

function build() {
    const root = document.getElementById('cam-editor');
    el.root = root;
    root.innerHTML = '';
    const scale = h('div', 'ce-scale');
    el.card = h('aside', 'ce-panel ce-card');
    // The card's body is drawn again on every change; the status strip under it is not, so a message
    // does not replay its entrance each time.
    el.cardBody = h('div', 'ce-card-body');
    el.sayBox = h('div', 'ce-says-slot');
    el.card.appendChild(el.cardBody);
    el.card.appendChild(el.sayBox);
    el.insp = h('aside', 'ce-panel ce-insp ce-hidden');
    el.dock = h('div', 'ce-panel ce-dock');
    el.modal = h('div', 'ce-modal ce-hidden');
    // Your character has the controls: a capsule at the top says so, for as long as it is so.
    el.driveTip = h('div', 'ce-drivetip');
    const dd = h('div', 'ce-disc');
    dd.innerHTML = GLYPHS().car || '';
    const dBody = h('div', 'ce-pb-body');
    dBody.appendChild(h('div', 'ce-pb-title', 'You have the controls'));
    const dKeys = h('div', 'ce-pb-keys');
    dKeys.appendChild(hintEl({ key: 'Tab', pad: ['lb', 'r3'], padJoin: '+', text: 'Back to the camera' }));
    dBody.appendChild(dKeys);
    el.driveTip.appendChild(dd);
    el.driveTip.appendChild(dBody);
    // HUD hidden: a capsule says how to bring it back, for a moment.
    el.hudTip = h('div', 'ce-hudtip');
    el.hudTip.appendChild(hintEl({ key: 'H', pad: null, text: 'or a click shows the editor again' }));
    el.hudTip.appendChild(hintEl({ key: null, pad: 'b', text: 'Any button shows the editor again' }));
    scale.appendChild(el.card);
    scale.appendChild(el.insp);
    scale.appendChild(el.dock);
    scale.appendChild(el.modal);
    scale.appendChild(el.hudTip);
    scale.appendChild(el.driveTip);
    scale.appendChild(buildPlaybar());
    root.appendChild(scale);
    buildDock();

    // HUD hidden: a left click anywhere brings it back (the right button still flies).
    window.addEventListener('mousedown', (e) => {
        if (open && st && st.hideHud && e.button === 0) cbk('ceHud', { on: false });
    }, true);
    // A dropdown's list closes on a press anywhere but on it (its own box toggles it), and when the
    // inspector it hangs from scrolls.
    document.addEventListener('pointerdown', (e) => {
        if (ddOpen && !ddOpen.list.contains(e.target) && !ddOpen.anchor.contains(e.target)) closeDropdown();
    }, true);
    el.insp.addEventListener('scroll', closeDropdown);

    // Typing in a box: Lua stands its keys down (the game reads the keyboard too).
    root.addEventListener('focusin', (e) => {
        if (e.target.matches('input, select, textarea') && !typing) { typing = true; cbk('ceTyping', { on: true }); }
    });
    root.addEventListener('focusout', (e) => {
        if (e.target.matches('input, select, textarea') && typing) { typing = false; cbk('ceTyping', { on: false }); }
    });
    window.addEventListener('resize', () => { if (open) renderTimeline(); });
}

// ---- playing in game: the capsule (tools/camera.lua, "Playing in game") ----
//
// The editor is away and the player plays. A capsule at the top says the shots are ready and the keys,
// then fades by itself: whatever is on screen ends up in the recording. It comes back when a shot ends
// or something needs saying, and is never there while a shot rolls.

function buildPlaybar() {
    const bar = h('div', 'ce-playbar');
    const d = h('div', 'ce-disc');
    d.innerHTML = GLYPHS().camera || '';
    const body = h('div', 'ce-pb-body');
    el.pbTitle = h('div', 'ce-pb-title', 'Ready to roll');
    el.pbSub = h('div', 'ce-pb-sub', '');
    const keysRow = h('div', 'ce-pb-keys');
    for (const c of [
        { key: 'F5', pad: null, text: 'Action' },
        { key: 'PgUp / PgDn', pad: null, text: 'Cameras' },
        { key: 'Num 1–9', pad: null, text: 'Camera' },
        { key: 'F9', pad: null, text: 'Editor' },
    ]) keysRow.appendChild(hintEl(c));
    body.appendChild(el.pbTitle);
    body.appendChild(el.pbSub);
    body.appendChild(keysRow);
    bar.appendChild(d);
    bar.appendChild(body);
    el.playbar = bar;
    return bar;
}

/** Show the capsule again (its fade starts over). */
function flashPlaybar() {
    if (!el.playbar) return;
    el.playbar.classList.remove('show');
    void el.playbar.offsetWidth;   // the animation starts again from the top
    el.playbar.classList.add('show');
}

function showGame(d) {
    if (!el.root) build();
    const mode = d && d.mode;
    el.root.classList.toggle('ce-game', !!mode);
    el.root.classList.toggle('ce-live', mode === 'live');
    if (!mode) { el.playbar.classList.remove('show'); return; }
    if (mode === 'live') return;
    const n = d.cameras || 0;
    el.pbTitle.textContent = d.say || 'Ready to roll';
    el.pbTitle.className = 'ce-pb-title' + (d.say && d.kind === 'warn' ? ' warn' : '');
    el.pbSub.textContent = (d.name || 'Your draft') + ' · ' + n + (n === 1 ? ' camera' : ' cameras')
        + (d.cleanAll === false ? '' : ' · clean screen');
    flashPlaybar();
}

/** The status strip: what just happened, in its kind's colour with its drawn mark, for five seconds. */
function say(text, kind) {
    if (!el.sayBox) return;
    clearTimeout(sayTimer);
    clearTimeout(sayGone);
    el.sayBox.innerHTML = '';
    if (!text) return;
    const k = SAYS_MARK[kind] ? kind : 'info';
    const says = h('div', 'ce-says ' + k);
    says.innerHTML = GLYPHS()[SAYS_MARK[k]] || '';
    says.appendChild(h('span', null, text));
    el.sayBox.appendChild(says);
    sayTimer = setTimeout(() => {
        says.classList.add('gone');
        sayGone = setTimeout(() => { if (says.parentNode) says.remove(); }, 420);
    }, 5000);
}

/** The camera's readings on the card. */
let lastCam = null;
function showCamera(d) {
    lastCam = d;
    if (!el.read) return;
    el.read.pos.textContent = d.x.toFixed(1) + ', ' + d.y.toFixed(1) + ', ' + d.z.toFixed(1);
    el.read.look.textContent = d.pitch.toFixed(0) + '° · ' + ((d.yaw % 360 + 360) % 360).toFixed(0) + '°';
    el.read.lens.textContent = d.fov.toFixed(1) + '° · ×' + d.speed.toFixed(1);
}

NuiRouter.register('camEdOpen', () => show());
NuiRouter.register('camEdClose', () => hide());
NuiRouter.register('camEdState', (d) => {
    st = d;
    playhead = d.playhead || 0;
    playing = !!d.playing;
    viewing = !!d.view;
    looking = !!d.looking;
    pad = !!d.pad;
    if (!open) return;
    render();
});
NuiRouter.register('camEdTime', (d) => {
    playhead = d.playhead || 0;
    playing = !!d.playing;
    viewing = !!d.view;
    if (!open || !st) return;
    placeHead();
    renderTransport();
});
NuiRouter.register('camEdInput', (d) => {
    looking = !!d.looking;
    pad = !!d.pad;
    if (!el.root) return;
    el.root.classList.toggle('ce-looking', looking);
    el.root.classList.toggle('ce-pad', pad);
    if (st) renderTransport();
});
NuiRouter.register('camEdCamera', (d) => showCamera(d));
NuiRouter.register('camEdSay', (d) => say(d.text, d.kind));
NuiRouter.register('camEdGame', (d) => showGame(d));
NuiRouter.register('camEdList', (d) => {
    savedList = Array.isArray(d.list) ? d.list : [];
    mayEdit = !!d.mayEdit;
    if (modal === 'open') renderModal();
});
NuiRouter.register('camEdAskName', () => { modal = 'save'; renderModal(); });

// ---- keys ----

function onKey(e) {
    if (e.type !== 'keydown') return;
    // An open dropdown: Esc closes it, and nothing else is the editor's meanwhile.
    if (ddOpen) {
        if (e.key === 'Escape' || e.key === 'Tab') { closeDropdown(); e.preventDefault(); }
        return;
    }
    const inBox = e.target && e.target.matches && e.target.matches('input, select, textarea');
    // Tab: who has the controls, the camera or your character (not while typing in a box).
    if (e.key === 'Tab' && !(e.target && e.target.matches && e.target.matches('input, select, textarea')) && !modal) {
        cbk('ceControls', {});
        e.preventDefault();
        return;
    }
    // Your character has the controls: the game's keys are for driving and walking. The editor answers
    // Esc (the controls back) and nothing else.
    if (st && st.drive) {
        if (e.key === 'Escape') cbk('ceControls', { game: false });
        return;
    }
    if (e.key === 'Escape') {
        if (st && st.hideHud) { cbk('ceHud', { on: false }); return; }
        if (modal) { modal = null; renderModal(); return; }
        if (inBox) { e.target.blur(); return; }
        if (st && st.sel) { cbk('ceSelect', { i: 0 }); return; }
        cbk('ceClose');
        return;
    }
    if (inBox || looking || modal) return;
    const ctrl = e.ctrlKey || e.metaKey;
    const k = e.key.toLowerCase();
    if (ctrl && k === 'z' && !e.shiftKey) { cbk('ceUndo'); e.preventDefault(); return; }
    if (ctrl && (k === 'y' || (k === 'z' && e.shiftKey))) { cbk('ceRedo'); e.preventDefault(); return; }
    if (ctrl && k === 'd') { if (st.sel) cbk('ceDuplicate', { i: st.sel }); e.preventDefault(); return; }
    if (ctrl && k === 's') { if (st.savedAs) cbk('ceSave', { name: st.savedAs }); else { modal = 'save'; renderModal(); } e.preventDefault(); return; }
    if (ctrl) return;
    if (e.key === ' ') { cbk('cePlay', {}); e.preventDefault(); return; }
    if (k === 'g') { cbk('ceAdd', {}); return; }
    if (k === 'e') { if (st.sel) cbk('ceSetFromCamera', { i: st.sel }); return; }
    if (k === 'f') { if (st.sel) cbk('ceLookThrough', { i: st.sel }); return; }
    if (k === 'v') { cbk('ceView', {}); return; }
    if (k === 'h') { cbk('ceHud', {}); return; }
    if (e.key === 'F9') { cbk('cePlayInGame'); e.preventDefault(); return; }
    if (k === 'p') { cbk('cePoints', {}); return; }
    if (e.key === 'Delete' || e.key === 'Backspace') { if (st.sel) cbk('ceDelete', { i: st.sel }); return; }
    if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
        const dir = e.key === 'ArrowLeft' ? -1 : 1;
        if (e.shiftKey) cbk('ceScrub', { t: Math.max(0, playhead + dir * 100) });
        else cbk('ceStep', { dir });
        e.preventDefault();
        return;
    }
    if (e.key === 'Home') { cbk('ceScrub', { t: 0 }); return; }
    if (e.key === 'End') { cbk('ceScrub', { t: seqLength() }); }
}

NuiRouter.registerKeyScope({
    name: 'camEditor',
    priority: 31,
    isOpen: () => open,
    onKey,
});
