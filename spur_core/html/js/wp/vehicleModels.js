// ========================================
// /whip SECTION — Vehicle Adjustments
//
// Trunk and glovebox for a whole CATEGORY of vehicles (`vehicle_class_meta`: the game's vehicle class, so every
// motorbike, every industrial) and for one MODEL over its category (`vehicle_meta`). A car's storage is its own
// size (given when it was made) first, then its model's, then its category's, then config.lua. Either can turn the
// trunk or glovebox off (a motorbike with no trunk); a model's on or off is over its category's (an emergency
// truck with a trunk where the category has none).
//
// Josh's layout (his mock, 12 Nov): the vehicles on the left half, each category a row that opens to its vehicles
// as pictures three across; on the right, the one picked large, its trunk and glovebox as sliders (the number
// beside each can be typed), and under them the trunk and glovebox as the inventory would show them opened, drawn
// by the inventory's own parts (inventory.css's panel and slot tiles, inventory.js's slot and weight line), so a
// change to how the inventory looks reaches this preview. It follows the sliders as they move.
//
// EACH STORAGE IS OVERRIDDEN OR NOT (Josh: an "Enable override?" switch). Off, it is what the level below gives (a
// model its category's, a category config.lua's), shown in the sliders, dimmed. On, this level's own: the sliders'
// sizes, and whether it has one at all (Has a trunk). Every change is the server's to allow
// (tools/panel_sections/vehicleModels.lua → server/vehicle_manager.lua), and the page is redrawn from what the server
// then holds, never from what we hoped.
// ========================================

import { WhipPanel, WP } from '../whip-panel.js';
import { nuiCallback, vehicleImageUrl } from '../utils.js';
import { VEHICLE_CLASSES, vehiclePortrait, vehicleTile } from './pickers.js';
import { createSlotElement, weightLine } from '../inventory.js';

const KINDS = [
    { key: 'trunk',    label: 'Trunk',    slots: 'trunkSlots',    kg: 'trunkMaxWeight',    has: 'hasTrunk' },
    { key: 'glovebox', label: 'Glovebox', slots: 'gloveboxSlots', kg: 'gloveboxMaxWeight', has: 'hasGlovebox' },
];
const KIND = { trunk: KINDS[0], glovebox: KINDS[1] };
// Where the sliders end. A bigger number can be typed (500 slots at most, the server's limit); the slider then
// reaches it.
const RANGE = {
    trunk:    { slots: 100, kg: 1000, kgStep: 5 },
    glovebox: { slots: 30,  kg: 100,  kgStep: 1 },
};
const MAX_SLOTS = 500;
const BICYCLES = 13;   // a bicycle never has a glovebox (Vehicles.isBicycle), whatever is set here
const PREVIEW = 'vmm-preview';   // the preview's slots' container: no store holds it, so they are empty

const CARET = '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" '
    + 'stroke-linejoin="round" aria-hidden="true"><path d="M6 3.5 10.5 8 6 12.5"/></svg>';

let catalog = [];        // [{ model, name, cls, img, url }], read on entering
let classRows = {};      // class -> { row, config }
let modelRows = {};      // model -> its own row
let config = {};         // config.lua's sizes, for a model the catalog has no category for
let byClass = new Map(); // class -> [catalog rows]
let opened = new Set();  // categories open in the list
let pick = null;         // { kind: 'class', cls } | { kind: 'model', model } | null
let draft = null;        // per storage key: { override, slots, kg, has }
let saved = '';          // fields() as the server holds them, to tell an unsaved change
let search = '';
let els = {};

// ---- what each level gets ----

const carOf = (model) => catalog.find((c) => c.model === model) || null;
const className = (cls) => VEHICLE_CLASSES[cls] || 'Category ' + cls;
const kgText = (n) => String(Math.round((Number(n) || 0) * 10) / 10);

/** The picked thing's category: its own for a category, a model's from the catalog. */
function pickClass() {
    if (!pick) return null;
    if (pick.kind === 'class') return pick.cls;
    const car = carOf(pick.model);
    return car ? car.cls : null;
}

/** One storage as the level below the picked one gives it: { slots, kg, on, from }. A model's: its category's over
 *  config.lua. A category's: config.lua's for it. */
function below(kind) {
    const cls = pickClass();
    const c = cls != null ? classRows[cls] : null;
    const base = c ? c.config : config;
    const row = pick && pick.kind !== 'class' ? (c && c.row) || {} : {};
    const fromClass = row[kind.slots] != null || row[kind.kg] != null || row[kind.has] === false;
    return {
        slots: row[kind.slots] || base[kind.slots],
        kg: row[kind.kg] || base[kind.kg],
        on: row[kind.has] !== false,
        from: fromClass ? className(cls) : 'config.lua',
    };
}

/** One storage as the draft has it now: { slots, kg, on }. */
function current(kind) {
    const s = draft[kind.key];
    if (s.override) return { slots: s.slots, kg: s.kg, on: s.has };
    const b = below(kind);
    return { slots: b.slots, kg: b.kg, on: b.on };
}

/** A short line: "no trunk · glovebox 1 / 20 kg". */
function classSummary(cls) {
    const c = classRows[cls];
    if (!c || !c.row) return 'config.lua';
    return KINDS.map((k) => c.row[k.has] === false ? 'no ' + k.label.toLowerCase()
        : k.label.toLowerCase() + ' ' + (c.row[k.slots] || c.config[k.slots]) + ' / ' + (c.row[k.kg] || c.config[k.kg]) + ' kg')
        .join('  ·  ');
}

// ---- the list ----

function matches(c) {
    if (!search) return true;
    const q = search.toLowerCase();
    return c.model.includes(q) || (c.name || '').toLowerCase().includes(q) || className(c.cls).toLowerCase().includes(q);
}

function carTile(c) {
    const b = vehicleTile(c);
    b.dataset.action = 'vmmPickModel';
    b.dataset.id = c.model;
    if (modelRows[c.model]) b.appendChild(WP.el('span', 'wp-tile-badge', 'Own'));
    if (pick && pick.kind === 'model' && pick.model === c.model) b.classList.add('active');
    return b;
}

function catRow(cls, cars, shown, open) {
    const b = WP.el('button', 'wp-list-item vmm-cat' + (open ? ' open' : ''));
    b.type = 'button';
    b.dataset.action = 'vmmPickClass';
    b.dataset.arg = cls;
    b.setAttribute('aria-expanded', open ? 'true' : 'false');
    const caret = WP.el('span', 'wp-group-caret');
    caret.innerHTML = CARET;   // a fixed icon, no data
    b.appendChild(caret);
    const text = WP.el('span', 'vmm-cat-text');
    text.appendChild(WP.el('span', 'wp-item-title', className(cls)));
    text.appendChild(WP.el('span', 'wp-item-sub', classSummary(cls)));
    b.appendChild(text);
    b.appendChild(WP.el('span', 'vmm-cat-count', search ? shown + ' of ' + cars.length : String(cars.length)));
    if (pick && pick.kind === 'class' && pick.cls === cls) b.classList.add('active');
    return b;
}

function renderList() {
    // Drawn again on every pick: where the admin had scrolled to stays.
    const scroll = els.list.scrollTop;
    els.list.innerHTML = '';
    for (const [cls, cars] of byClass) {
        const hits = cars.filter(matches);
        const nameHit = search && className(cls).toLowerCase().includes(search.toLowerCase());
        if (search && !hits.length && !nameHit) continue;
        // Searching opens every category with a match; otherwise the ones the admin opened.
        const open = search ? hits.length > 0 : opened.has(cls);
        els.list.appendChild(catRow(cls, cars, hits.length, open));
        if (open) {
            const grid = WP.el('div', 'wp-tiles vmm-grid');
            for (const c of hits) grid.appendChild(carTile(c));
            els.list.appendChild(grid);
        }
    }
    // Models with a row of their own the catalog does not list (an add-on whose pack has stopped, or one set by name
    // before): still shown, so what they have can be seen and given back.
    const others = Object.keys(modelRows).filter((m) => !carOf(m) && (!search || m.includes(search.toLowerCase())));
    if (others.length) {
        els.list.appendChild(WP.el('div', 'wp-section-title vmm-others', 'Models not in the vehicle list'));
        const grid = WP.el('div', 'wp-tiles vmm-grid');
        for (const m of others) grid.appendChild(carTile({ model: m, name: null, img: false }));
        els.list.appendChild(grid);
    }
    if (!els.list.children.length) {
        els.list.appendChild(WP.empty(catalog.length ? 'Nothing matches "' + search + '"' : 'The vehicle list has not arrived yet'));
    }
    els.list.scrollTop = scroll;
}

// ---- the editor ----

/** The draft for the picked level from its saved row: per storage, overridden when the row says anything about it. */
function draftOf(row) {
    const d = {};
    for (const k of KINDS) {
        const b = below(k);
        const own = !!row && (row[k.slots] != null || row[k.kg] != null || row[k.has] === true || row[k.has] === false);
        d[k.key] = {
            override: own,
            slots: own && row[k.slots] != null ? Number(row[k.slots]) : b.slots,
            kg: own && row[k.kg] != null ? Number(row[k.kg]) : b.kg,
            has: own && (row[k.has] === true || row[k.has] === false) ? row[k.has] : b.on,
        };
    }
    return d;
}

/** The fields as the server takes them: an overridden storage's sizes and whether it has one (a category says only
 *  "none": having one is config.lua's); a storage not overridden says nothing, so the level below decides. */
function fields() {
    const out = {};
    for (const k of KINDS) {
        const s = draft[k.key];
        if (!s.override) continue;
        out[k.slots] = Math.round(s.slots);
        out[k.kg] = Math.round(s.kg * 10) / 10;
        if (pick.kind === 'class') { if (!s.has) out[k.has] = false; } else out[k.has] = s.has;
    }
    return out;
}

/** Save lights up (the white pill) once something differs from what the server holds. */
function markDirty() {
    if (!els.save) return;
    els.save.classList.toggle('wp-btn-primary', !!pick && JSON.stringify(fields()) !== saved);
}

/** A switch (the Director's, .wd-sw): its words, and the white pill when on. */
function switchEl(label, on, action, kind, disabled) {
    const b = WP.el('button', 'wd-sw vmm-sw');
    b.type = 'button';
    b.setAttribute('role', 'switch');
    b.setAttribute('aria-checked', String(on));
    b.dataset.action = action;
    b.dataset.kind = kind;
    b.disabled = !!disabled;
    b.appendChild(WP.el('span', 'wd-sw-name', label));
    b.appendChild(WP.el('span', 'wd-switch' + (on ? ' on' : '')));
    return b;
}

/** One size: its name, its number (typed or slid), and its slider. */
function slider(k, isSlots, s, live) {
    const what = isSlots ? 'slots' : 'kg';
    const value = isSlots ? s.slots : s.kg;
    const r = RANGE[k.key];
    const wrap = WP.el('div', 'vmm-slider' + (s.override ? ' vmm-own' : ''));

    const top = WP.el('div', 'vmm-slider-top');
    top.appendChild(WP.el('span', 'vmm-slider-label', isSlots ? 'Slots' : 'Weight'));
    const num = WP.input({ type: 'number', value: isSlots ? String(Math.round(value)) : kgText(value), enterAction: 'vmmNumber' });
    num.classList.add('vmm-num');
    num.dataset.change = 'vmmNumber';
    num.dataset.kind = k.key;
    num.dataset.what = what;
    num.step = isSlots ? '1' : '0.1';
    num.min = isSlots ? '1' : '0.1';
    num.disabled = !live;
    num.setAttribute('aria-label', k.label + (isSlots ? ' slots' : ' weight'));
    top.appendChild(num);
    top.appendChild(WP.el('span', 'vmm-unit', isSlots ? 'slots' : 'kg'));
    wrap.appendChild(top);

    const range = document.createElement('input');
    range.type = 'range';
    range.className = 'vmm-range';
    range.min = isSlots ? '1' : String(r.kgStep);
    range.max = String(Math.max(isSlots ? r.slots : r.kg, Math.ceil(value)));
    range.step = isSlots ? '1' : String(r.kgStep);
    range.value = String(value);
    range.dataset.input = 'vmmSlide';
    range.dataset.kind = k.key;
    range.dataset.what = what;
    range.disabled = !live;
    range.setAttribute('aria-label', k.label + (isSlots ? ' slots' : ' weight'));
    wrap.appendChild(range);
    return wrap;
}

/** One storage: its name and Enable override?; overridden, whether it has one at all; then its two sliders, live only
 *  while overridden and it has one. */
function storeBlock(k) {
    const block = WP.el('div', 'vmm-store');
    const head = WP.el('div', 'vmm-store-head');
    head.appendChild(WP.el('div', 'vmm-store-name', k.label));
    if (pickClass() === BICYCLES && k.key === 'glovebox') {
        head.appendChild(WP.el('span', 'vmm-store-note', 'A bicycle never has one'));
        block.appendChild(head);
        return block;
    }
    const s = draft[k.key];
    const b = below(k);
    head.appendChild(switchEl('Enable override?', s.override, 'vmmOverride', k.key));
    block.appendChild(head);

    if (s.override) {
        block.appendChild(switchEl('Has a ' + k.label.toLowerCase(), s.has, 'vmmHas', k.key));
    } else {
        block.appendChild(WP.el('div', 'vmm-store-note vmm-below', b.from + '\'s: '
            + (b.on ? b.slots + ' slots, ' + kgText(b.kg) + ' kg' : 'none')));
    }

    const live = s.override && s.has;
    const sliders = WP.el('div', 'vmm-sliders' + (live ? '' : ' vmm-off'));
    const shown = s.override ? s : { override: false, slots: b.slots, kg: b.kg };
    sliders.appendChild(slider(k, true, shown, live));
    sliders.appendChild(slider(k, false, shown, live));
    block.appendChild(sliders);
    return block;
}

/** The trunk or glovebox as the inventory shows it opened (its right column's panel): the inventory's own classes
 *  and slot tiles, empty, as many as the slider says, and its weight line. */
function invPanel(k, sub) {
    const panel = WP.el('div', 'inv-panel vmm-inv');
    const header = WP.el('div', 'inv-panel-header');
    const title = WP.el('div', 'inv-panel-title');
    const words = WP.el('div');
    words.appendChild(WP.el('span', null, k.label));
    if (sub) words.appendChild(WP.el('div', 'inv-panel-subtitle', sub));
    const bike = pickClass() === BICYCLES && k.key === 'glovebox';
    const s = current(k);
    const on = s.on && !bike;
    words.appendChild(WP.el('div', 'inv-panel-subtitle', on ? weightLine(0, s.kg) : 'None'));
    title.appendChild(words);
    header.appendChild(title);
    panel.appendChild(header);
    if (!on) {
        panel.classList.add('vmm-inv-off');
        panel.appendChild(WP.el('div', 'vmm-inv-none', bike ? 'A bicycle has no glovebox' : 'No ' + k.label.toLowerCase()
            + ': it is not offered, and cannot be opened'));
        return panel;
    }
    const grid = WP.el('div', 'inv-slots-grid');
    const n = Math.max(1, Math.min(MAX_SLOTS, Math.round(s.slots) || 1));
    for (let i = 1; i <= n; i++) grid.appendChild(createSlotElement(i, PREVIEW));
    panel.appendChild(grid);
    return panel;
}

function drawPreview() {
    if (!els.preview) return;
    els.preview.innerHTML = '';
    const sub = pick.kind === 'class' ? className(pick.cls) : ((carOf(pick.model) || {}).name || pick.model);
    for (const k of KINDS) els.preview.appendChild(invPanel(k, sub));
}

/** The picture at the top: the vehicle's, large; for a category, three of its vehicles side by side. */
function hero() {
    if (pick.kind === 'model') {
        const car = carOf(pick.model);
        const h = vehiclePortrait(pick.model, car ? car.img : false);
        h.classList.add('vmm-hero');
        return h;
    }
    const h = WP.el('div', 'wp-pick-hero wp-hero-wide vmm-hero vmm-hero-set');
    for (const c of (byClass.get(pick.cls) || []).filter((x) => x.img !== false).slice(0, 3)) {
        const img = document.createElement('img');
        img.alt = '';
        img.decoding = 'async';
        img.addEventListener('error', () => img.remove());
        img.src = c.url || vehicleImageUrl(c.model);
        h.appendChild(img);
    }
    return h;
}

function renderPane() {
    const p = els.pane;
    p.innerHTML = '';
    els.save = null;
    els.preview = null;
    if (!pick) {
        p.appendChild(WP.el('div', 'wp-pane-title', 'Vehicle Adjustments'));
        p.appendChild(WP.el('div', 'wp-hint', 'The trunk and glovebox of a whole category (every motorbike, every SUV), '
            + 'or of one model over its category. Pick a category to set it for all of them, or open it and pick a '
            + 'vehicle. A car\'s own size (given when it was made) comes first, then its model\'s, then its category\'s, '
            + 'then config.lua.'));
        const set = [...byClass.keys()].filter((cls) => classRows[cls] && classRows[cls].row);
        if (set.length) {
            p.appendChild(WP.el('div', 'wp-section-title', 'Categories with their own'));
            for (const cls of set) {
                const item = WP.listItem({ title: className(cls), sub: classSummary(cls), action: 'vmmPickClass' });
                item.dataset.arg = cls;
                p.appendChild(item);
            }
        }
        return;
    }

    p.appendChild(hero());
    // Its name, and on the same line its verbs, so the sliders and the preview start high.
    const headRow = WP.el('div', 'vmm-head-row');
    const head = WP.el('div', 'vmm-head');
    headRow.appendChild(head);
    let hasRow;
    if (pick.kind === 'class') {
        hasRow = !!(classRows[pick.cls] && classRows[pick.cls].row);
        head.appendChild(WP.el('div', 'wp-pane-title', className(pick.cls)));
    } else {
        const car = carOf(pick.model);
        const cls = car ? car.cls : null;
        hasRow = !!modelRows[pick.model];
        head.appendChild(WP.el('div', 'wp-pane-title', (car && car.name) || pick.model));
        const sub = WP.el('div', 'vmm-sub');
        sub.appendChild(WP.el('span', 'vmm-model', pick.model));
        if (cls != null) {
            sub.appendChild(document.createTextNode('  ·  '));
            const link = WP.el('button', 'vmm-link', className(cls));
            link.type = 'button';
            link.dataset.action = 'vmmPickClass';
            link.dataset.arg = cls;
            sub.appendChild(link);
        }
        head.appendChild(sub);
    }

    // The destructive verb first, the working one last: the rule every section keeps.
    const actions = WP.el('div', 'wp-actions-row vmm-actions');
    if (hasRow) {
        actions.appendChild(WP.btn(pick.kind === 'class' ? 'Back to config.lua' : 'Back to its category\'s',
            pick.kind === 'class' ? 'vmmClassClear' : 'vmmClear', 'danger'));
    }
    els.save = WP.btn('Save', 'vmmSave');
    actions.appendChild(els.save);
    headRow.appendChild(actions);
    p.appendChild(headRow);

    for (const k of KINDS) p.appendChild(storeBlock(k));

    p.appendChild(WP.el('div', 'wp-section-title vmm-preview-title', 'Opened, it looks like this'));
    els.preview = WP.el('div', 'vmm-preview');
    p.appendChild(els.preview);
    drawPreview();
    markDirty();
}

function choose(next) {
    pick = next;
    draft = null;
    if (pick) draft = draftOf(pick.kind === 'class' ? classRows[pick.cls] && classRows[pick.cls].row : modelRows[pick.model]);
    saved = draft ? JSON.stringify(fields()) : '';
    renderList();
    renderPane();
}

async function confirmed(res, ok) {
    if (res && res.ok) { WP.result(ok, 'ok'); return true; }
    WP.result((res && res.why) || 'Could not save that', 'err');
    return false;
}

// ---- section ----

WhipPanel.registerSection({
    id: 'vehicleModels',
    group: 'vehicles',
    label: 'Vehicle Adjustments',
    order: 11,

    render(root) {
        els = {};
        root.appendChild(WP.toolbar({
            search: { inputAction: 'vmmSearch', placeholder: 'Search vehicles and categories…' },
        }));

        const split = WP.el('div', 'wp-split');
        const listCol = WP.el('div', 'wp-list-col vmm-browse');
        els.list = WP.el('div', 'wp-list');
        listCol.appendChild(els.list);
        split.appendChild(listCol);

        const detail = WP.el('div', 'wp-detail vmm-edit');
        els.pane = WP.el('div');
        detail.appendChild(els.pane);
        split.appendChild(detail);
        root.appendChild(split);
        renderList();
        renderPane();
    },

    onData(kind, payload) {
        if (kind !== 'all' || !payload) return;
        if (Array.isArray(payload.catalog)) {
            catalog = payload.catalog;
            byClass = new Map();
            for (const c of catalog) {
                const cls = Number(c.cls);
                if (!Number.isInteger(cls)) continue;
                if (!byClass.has(cls)) byClass.set(cls, []);
                byClass.get(cls).push(c);
            }
            byClass = new Map([...byClass.entries()].sort((a, b) => a[0] - b[0]));
        }
        classRows = {};
        for (const c of payload.classes || []) classRows[c.class] = { row: c.row || null, config: c.config || {} };
        modelRows = {};
        for (const m of payload.models || []) modelRows[m.model] = m;
        config = payload.config || {};
        // Stay where the admin was, on what the server now holds (a model whose row went back is still that model).
        if (pick && pick.kind === 'class' && !byClass.has(pick.cls)) pick = null;
        choose(pick);
    },

    onEscape() {
        if (pick !== null) { choose(null); return true; }
        return false;
    },

    actions: {
        vmmSearch: (el) => { search = el.value.trim(); renderList(); },
        vmmPickClass: (el) => {
            const cls = Number(el.dataset.arg);
            // A category picked opens; picked again while open, it closes (the list's dropdown).
            const already = pick && pick.kind === 'class' && pick.cls === cls;
            if (already && opened.has(cls)) opened.delete(cls); else opened.add(cls);
            if (already) { renderList(); return; }
            choose({ kind: 'class', cls });
        },
        vmmPickModel: (el) => choose({ kind: 'model', model: el.dataset.id }),
        // Overridden from here on, starting where the level below is; or not, and the level below decides again.
        vmmOverride: (el) => {
            const s = draft && draft[el.dataset.kind];
            if (!s) return;
            s.override = !s.override;
            if (s.override) {
                const b = below(KIND[el.dataset.kind]);
                s.slots = b.slots;
                s.kg = b.kg;
                s.has = b.on;
            }
            renderPane();
        },
        vmmHas: (el) => {
            const s = draft && draft[el.dataset.kind];
            if (!s) return;
            s.has = !s.has;
            renderPane();
        },
        // A slider moving: its number, and the preview, follow at once. Drawn in place, never again whole, or the
        // drag would end under the admin's hand.
        vmmSlide: (el) => {
            const s = draft && draft[el.dataset.kind];
            if (!s) return;
            const n = Number(el.value);
            if (el.dataset.what === 'slots') s.slots = n; else s.kg = n;
            const num = el.closest('.vmm-slider') && el.closest('.vmm-slider').querySelector('.vmm-num');
            if (num) num.value = el.dataset.what === 'slots' ? String(n) : kgText(n);
            drawPreview();
            markDirty();
        },
        // A number typed (Enter, or leaving the box): held to what the server takes, else put back.
        vmmNumber: (el) => {
            const s = draft && draft[el.dataset.kind];
            if (!s) return;
            const isSlots = el.dataset.what === 'slots';
            const n = Number(el.value);
            const ok = isSlots ? Number.isInteger(n) && n >= 1 && n <= MAX_SLOTS : Number.isFinite(n) && n > 0;
            if (!ok) {
                WP.result(isSlots ? 'Slots is a whole number from 1 to ' + MAX_SLOTS : 'Weight is a number above 0', 'err');
                renderPane();
                return;
            }
            if ((isSlots ? s.slots : s.kg) === n) return;
            if (isSlots) s.slots = n; else s.kg = n;
            renderPane();
        },
        vmmSave: async () => {
            if (!pick || !draft) return;
            if (pick.kind === 'class') {
                const res = await nuiCallback('vmmClassSave', { class: pick.cls, fields: fields() });
                await confirmed(res, 'Saved for every ' + className(pick.cls).toLowerCase() + ' vehicle');
                return;
            }
            const res = await nuiCallback('vmmSave', { model: pick.model, fields: fields() });
            await confirmed(res, 'Saved for ' + pick.model);
        },
        vmmClear: async () => {
            if (!pick || pick.kind !== 'model') return;
            const model = pick.model;
            const ok = await WP.confirm({
                title: 'Back to its category\'s?',
                body: 'Every ' + model + ' without a size of its own takes its category\'s trunk and glovebox again.',
                confirmLabel: 'Use its category\'s',
                danger: true,
            });
            if (!ok) return;
            await confirmed(await nuiCallback('vmmClear', { model }), model + ' takes its category\'s again');
        },
        vmmClassClear: async () => {
            if (!pick || pick.kind !== 'class') return;
            const cls = pick.cls;
            const ok = await WP.confirm({
                title: 'Back to config.lua?',
                body: 'Every ' + className(cls).toLowerCase() + ' vehicle without its own takes config.lua\'s trunk and glovebox again.',
                confirmLabel: 'Use config.lua',
                danger: true,
            });
            if (!ok) return;
            await confirmed(await nuiCallback('vmmClassClear', { class: cls }), className(cls) + ' takes config.lua\'s again');
        },
    },
});
