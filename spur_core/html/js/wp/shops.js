// ========================================
// /whip SECTION — Shops
//
// The list of shops on the left; on the right, the picked shop as a summary — what kind it is,
// where it stands, who serves, what it sells, its map icon — each part with a Change button.
//
// ONE WIZARD SETS SHOPS UP AND CHANGES THEM. WP.stepper, as the property Configurator uses it, in the section's place:
//
//   Kind        its name, and which of the three kinds it is (and a business's job)
//   Where       stand where the shopkeeper will stand (in the world: E)
//   Shopkeeper  an NPC from the world builder's list, with its picture, seen standing on the spot
//               through a camera; or a prop; or nobody
//   Stock room  a stocked shop's container
//   Goods       the Item Browser's list beside the shelf being made, each with a price
//               (a stocked shop's step is Prices: what it sells is what its staff stock)
//   Map         its blip: an icon and a colour, or none
//   Create/Save the lot, checked
//
// + New Shop starts it empty, a step at a time. Change on a shop's page opens it filled in with the
// shop as it is, on that part, every step open from the rail; the last step says what changed and
// Save writes it. Esc there goes back to that summary, then out.
//
// The calls are in tools/panel_sections/shops.lua: smWizardCreate / smWizardUpdate answer the
// wizard, smStockPrices reads a stock room's prices, smPlaceSpot and smPreviewKeeper are the two
// steps done in the world. smCreateShop / smUpdateShop / smDeleteShop are the old events, unchanged.
// ========================================

import { WhipPanel, WP } from '../whip-panel.js';
import { nuiCallback, itemImageUrl } from '../utils.js';
import { pedPicker, pedName, pedPortrait, itemList, BLIP_COLOURS } from './pickers.js';
import { plural, fixed, number } from './format.js';

let shops = {};          // keyed by String(shopId)
let jobs = {};           // keyed by String(jobId)
let selectedId = null;   // the shop whose page is open
let els = {};
let search = '';

let items = {};          // every item, as the Item Browser lists them (smGetAll): the Goods step
let stockRooms = [];     // the saved containers (smGetAll): a stocked shop's Stock room step
let roomPrices = {};     // containerId -> { item: price } on sale there now (smStockPrices)
let configShops = [];    // the keys config.lua's Config.Shops starts shops with (smGetAll)
let draft = null;        // the shop being set up or changed, while the wizard is open
let wiz = null;          // its WP.stepper
let wizAt = 'kind';      // the step it is on, so the panel reopens there
let pendingSelect = null;   // a shop just made: opened once the list has it

// A shop's kind is a kind, not a state: neutral for all three (amber and red are for what needs you).
const MODE_PILL = { npc: '', infinite: '', stocked: '' };

// ---- the wizard's choices ----

const KINDS = [
    { mode: 'npc', title: 'Open to everyone',
      text: 'Run by the server. Sells from a list you set and never runs out. The money it takes leaves the economy.' },
    { mode: 'infinite', title: 'A business, never runs out',
      text: 'Sells from a list you set and never runs out. A job runs it, and the money goes to its business account.' },
    { mode: 'stocked', title: 'A business with real stock',
      text: 'Sells only what its staff put in its stock room, so it can sell out. The money goes to the job.' },
];

/** People who look like they work in a shop: the Shopkeeper step's first chip.
 *  RedM (spur_core, 24 Nov 2026): RDR2's own shop people (store owners, gunsmiths, bartenders, barbers, butchers,
 *  doctors, a tailor, vendors), in place of GTA's; every name checked against femga's rdr3_discoveries ped list. */
const SHOP_STAFF = [
    'u_m_m_valgenstoreowner_01', 'u_m_m_rhdgenstoreowner_01', 'u_m_m_strgenstoreowner_01', 'u_f_m_tumgeneralstoreowner_01',
    'u_m_m_nbxgeneralstoreowner_01', 'u_m_m_armgeneralstoreowner_01', 'u_m_o_blwgeneralstoreowner_01',
    'u_m_m_walgeneralstoreowner_01', 'u_m_m_sdexoticsshopkeeper_01', 'u_m_o_vhtexoticshopkeeper_01',
    'u_m_m_valgunsmith_01', 'u_m_m_rhdgunsmith_01', 'u_m_m_nbxgunsmith_01', 'u_m_m_valbartender_01',
    'u_f_m_vhtbartender_01', 'u_m_m_valbarber_01', 's_m_m_barber_01', 'u_m_m_valbutcher_01', 'u_m_m_valdoctor_01',
    's_m_m_tailor_01', 's_m_m_marketvendor_01', 'u_m_m_sdcustomvendor_01',
];
const DEFAULT_KEEPER = 'u_m_m_valgenstoreowner_01';   // RedM (spur_core, 24 Nov 2026): was GTA's mp_m_shopkeep_01

/** Map icons a shop is likely to want, by GTA blip sprite. Any other number can be typed. */
// RedM (spur_core, 24 Nov 2026): only the numbers shared/rdr_compat.lua turns into an RDR2 icon (its SPRITE table:
// store, tailor, barber, gunsmith, saloon, doctor, bank). GTA's Fuel, Car mods, Pizza, Weed and the rest have no
// RDR2 icon and all showed as the same plain point. Labels in RDR2's words.
const BLIPS = [
    [52, 'General store'], [73, 'Tailor'], [71, 'Barber'], [110, 'Gunsmith'], [93, 'Saloon'], [51, 'Doctor'],
    [500, 'Bank'], [1, 'Point'],
];

// Blip colours: wp/pickers.js (BLIP_COLOURS), shared with the garage wizard. RedM (spur_core, 24 Nov 2026): no
// tinted picture any more (the tiles above have none), so blipTintFilter is not used here.

const business = (mode) => mode === 'infinite' || mode === 'stocked';

function stepsFor(mode, editing) {
    const last = { key: 'review', label: editing ? 'Save' : 'Create' };
    return mode === 'stocked'
        ? [{ key: 'kind', label: 'Kind' }, { key: 'where', label: 'Where' }, { key: 'keeper', label: 'Shopkeeper' },
           { key: 'stock', label: 'Stock room' }, { key: 'goods', label: 'Prices' }, { key: 'map', label: 'Map' }, last]
        : [{ key: 'kind', label: 'Kind' }, { key: 'where', label: 'Where' }, { key: 'keeper', label: 'Shopkeeper' },
           { key: 'goods', label: 'Goods' }, { key: 'map', label: 'Map' }, last];
}

function newDraft() {
    return {
        editing: null,                    // the shopId being changed, or null for a new shop
        name: '', mode: 'npc', jobId: 0,
        spot: null,                       // { x, y, z, heading }
        keeper: 'person',                 // 'person' | 'prop' | 'none'
        npcModel: DEFAULT_KEEPER, prop: '',
        containerId: 0,
        goods: [],                        // [{ key, price }] in the order picked; price as typed
        onMap: true, blipSprite: 52, blipColor: 2,
    };
}

/** { item: price } as goods lines: a catalog, or a stock room's prices. */
function goodsFrom(map) {
    return Object.keys(map || {}).map((k) => {
        const v = map[k];
        return { key: k, price: String(typeof v === 'object' && v !== null ? v.price : v) };
    });
}

/** A shop as a draft: the wizard filled in with it as it is. */
function draftFromShop(s) {
    const stocked = s.mode === 'stocked';
    const prices = stocked && s.containerId ? roomPrices[s.containerId] : null;
    return {
        editing: String(s.shopId),
        key: s.key || '',
        name: s.name || '', mode: s.mode || 'npc', jobId: Number(s.jobId) || 0,
        spot: { x: Number(s.x) || 0, y: Number(s.y) || 0, z: Number(s.z) || 0, heading: Number(s.heading) || 0 },
        keeper: s.npcModel ? 'person' : s.prop ? 'prop' : 'none',
        npcModel: s.npcModel || DEFAULT_KEEPER, prop: s.prop || '',
        containerId: Number(s.containerId) || 0,
        goods: stocked ? goodsFrom(prices) : goodsFrom(s.catalog),
        goodsLoading: stocked && !!s.containerId && !prices,
        onMap: !!s.blipSprite, blipSprite: Number(s.blipSprite) || 52,
        blipColor: s.blipColor === undefined || s.blipColor === null ? 2 : Number(s.blipColor),
    };
}

const PARTS = ['name', 'mode', 'jobId', 'spot', 'keeper', 'npcModel', 'prop', 'containerId', 'goods', 'onMap', 'blipSprite', 'blipColor'];
function snapshot(d) {
    const out = {};
    for (const k of PARTS) out[k] = d[k];
    return JSON.parse(JSON.stringify(out));
}

function priceMap(goods) {
    const out = {};
    for (const g of goods || []) out[g.key] = String(g.price).trim();
    return JSON.stringify(Object.keys(out).sort().map((k) => [k, out[k]]));
}

/** The parts of a shop being changed that differ from the shop as it is, by step. */
function changedParts(d) {
    const out = new Set();
    const o = d && d.original;
    if (!o) return out;
    if (d.name.trim() !== o.name.trim() || d.mode !== o.mode
        || (business(d.mode) && Number(d.jobId) !== Number(o.jobId))) out.add('kind');
    const a = d.spot || {}, b = o.spot || {};
    if (Math.abs(a.x - b.x) > 0.005 || Math.abs(a.y - b.y) > 0.005 || Math.abs(a.z - b.z) > 0.005
        || Math.abs(a.heading - b.heading) > 0.05) out.add('where');
    if (d.keeper !== o.keeper || (d.keeper === 'person' && d.npcModel !== o.npcModel)
        || (d.keeper === 'prop' && d.prop.trim() !== o.prop.trim())) out.add('keeper');
    if (d.mode === 'stocked' && Number(d.containerId) !== Number(o.containerId)) out.add('stock');
    if (!d.goodsLoading && priceMap(d.goods) !== priceMap(o.goods)) out.add('goods');
    if (d.onMap !== o.onMap || (d.onMap && (Number(d.blipSprite) !== Number(o.blipSprite)
        || Number(d.blipColor) !== Number(o.blipColor)))) out.add('map');
    return out;
}

function normalizeShops(raw) {
    shops = {};
    if (Array.isArray(raw)) {
        for (const s of raw) { if (s && s.shopId) shops[String(s.shopId)] = s; }
    } else if (raw) {
        for (const key of Object.keys(raw)) {
            const s = raw[key];
            if (s && s.shopId) shops[String(s.shopId)] = s;
        }
    }
}

function normalizeJobs(raw) {
    jobs = {};
    if (Array.isArray(raw)) {
        for (const j of raw) { if (j && j.jobId) jobs[String(j.jobId)] = j; }
    } else if (raw) {
        for (const key of Object.keys(raw)) {
            const j = raw[key];
            if (j && j.jobId) jobs[String(j.jobId)] = j;
        }
    }
}

const dist = (a, b) => Math.hypot((a.x || 0) - (b.x || 0), (a.y || 0) - (b.y || 0), (a.z || 0) - (b.z || 0));

/** What a stock room sells now, read once and kept (smStockPrices); one read at a time per room.
 *  null when it could not be read — and nothing waiting on it draws again, so a failing read is not
 *  asked for in a loop. */
const roomReads = {};
function loadRoomPrices(containerId) {
    if (!roomReads[containerId]) {
        roomReads[containerId] = Promise.resolve(nuiCallback('smStockPrices', { containerId: Number(containerId) }))
            .catch(() => null)
            .then((res) => {
                delete roomReads[containerId];
                if (!res || res.ok !== true) return null;   // nuiCallback answers {} when the call failed
                roomPrices[containerId] = res.prices || {};
                return roomPrices[containerId];
            });
    }
    return roomReads[containerId];
}

// ---- a shop, said in words: its page and the wizard's last step share these ----

/** Which way the shopkeeper faces: where the shop is, the map under the row shows (WP.place). */
function spotText(p) {
    return p ? 'facing ' + fixed(p.heading, 0) + '°' : '';
}

/** One row per part of the shop, each with `rowOpts(stepKey)`'s button (Change). `changed` marks
 *  the parts a Save would write. */
function summaryRows(body, d, rowOpts, changed) {
    const mark = (key, text) => (changed && changed.has(key) ? text + '  ·  changed' : text);
    const kind = KINDS.find((k) => k.mode === d.mode);
    const job = d.jobId ? jobs[String(d.jobId)] : null;
    const row = (label, key, status, detail) => {
        body.appendChild(WP.statusRow({ label, status, detail: mark(key, detail), ...rowOpts(key) }));
    };
    row('Name', 'kind', d.name.trim() ? 'ok' : 'err', d.name.trim() || 'none');
    row('Kind', 'kind', business(d.mode) && !job ? 'err' : 'ok',
        (kind ? kind.title : d.mode) + (business(d.mode) ? (job ? '  ·  run by ' + job.name : '  ·  no job') : ''));
    row('Where', 'where', d.spot ? 'ok' : 'err', d.spot ? spotText(d.spot) : 'not set');
    if (d.spot) body.appendChild(WP.place({ x: d.spot.x, y: d.spot.y, name: (d.name || '').trim() || 'The shop' }));
    row('Shopkeeper', 'keeper', 'ok',
        d.keeper === 'person' ? pedName(d.npcModel) + '  ·  ' + d.npcModel
            : d.keeper === 'prop' ? 'the prop ' + d.prop : 'nobody: no counter, so players cannot open it');
    if (d.mode === 'stocked') {
        const room = stockRooms.find((c) => Number(c.containerId) === Number(d.containerId));
        row('Stock room', 'stock', room ? 'ok' : 'err',
            room ? (room.name || 'Container') + ' #' + room.containerId : d.containerId ? 'container #' + d.containerId : 'not picked');
    }
    const names = d.goods.slice(0, 4).map((g) => ((items[g.key] && items[g.key].name) || g.key) + ' $' + g.price);
    row(d.mode === 'stocked' ? 'Prices' : 'Goods', 'goods',
        d.goodsLoading ? 'todo' : d.goods.length ? 'ok' : (d.mode === 'stocked' ? 'warn' : 'err'),
        d.goodsLoading ? 'reading its prices…'
            : d.goods.length ? plural(d.goods.length, 'item') + ':  ' + names.join(', ') + (d.goods.length > 4 ? ', …' : '')
            : (d.mode === 'stocked' ? 'none on sale: priced in the game, from Manage Stock' : 'nothing to sell'));
    const icon = BLIPS.find((b) => b[0] === Number(d.blipSprite));
    const colour = BLIP_COLOURS.find((c) => c[0] === Number(d.blipColor));
    row('Map', 'map', d.onMap ? 'ok' : 'off',
        d.onMap ? (icon ? icon[1] : 'icon ' + d.blipSprite) + ', ' + (colour ? colour[1].toLowerCase() : 'colour ' + d.blipColor) : 'not on the map');
}

// ---- list ----

function renderList() {
    els.list.innerHTML = '';
    const ids = Object.keys(shops).sort((a, b) => parseInt(a, 10) - parseInt(b, 10));
    let shown = 0;

    for (const id of ids) {
        const s = shops[id];
        const hay = (s.name + ' #' + s.shopId + ' ' + (s.key || '')).toLowerCase();
        if (search && !hay.includes(search)) continue;
        shown += 1;
        const job = s.jobId ? jobs[String(s.jobId)] : null;
        const item = WP.listItem({
            title: s.name || 'Shop',
            sub: '#' + s.shopId + ' · ' + (job ? job.name : (s.mode || 'npc')),
            pill: s.mode || 'npc',
            pillClass: MODE_PILL[s.mode] || '',
            id: id,
            action: 'smSelect',
        });
        if (selectedId === id) item.classList.add('active');
        els.list.appendChild(item);
    }

    if (shown === 0) {
        els.list.appendChild(WP.empty(search ? 'No shops match "' + search + '"' : 'No shops'));
    }
    els.count.textContent = shown + ' of ' + ids.length;
}

// ---- a shop's page ----

/** Where a shop with a key came from, in words (Shops.ownerOf's rules, and config.lua's seeds), or
 *  null for one an admin made. */
function originOf(s) {
    const set = s.settings && typeof s.settings === 'object' ? s.settings : {};
    if (set.ensured && typeof set.ensured.by === 'string') return 'declared by the resource ' + set.ensured.by + ' (EnsureShop)';
    if (typeof set.owner === 'string') return 'made by the resource ' + set.owner;
    if (s.key && configShops.indexOf(s.key) >= 0) return 'a starting shop from config.lua (Config.Shops, "' + s.key + '")';
    if (s.key) return 'key "' + s.key + '"';
    return null;
}

/** A starting shop from config.lua is made again at start-up whenever no shop has its key. */
const fromConfig = (s) => !!(s && s.key && configShops.indexOf(s.key) >= 0
    && !(s.settings && s.settings.ensured) && !(s.settings && typeof s.settings.owner === 'string'));

function selectShop(id) {
    if (!shops[String(id)]) return;
    selectedId = String(id);
    renderList();
    renderDetail();
}

function noShop() {
    selectedId = null;
    renderList();
    renderDetail();
}

function renderDetail() {
    const body = els.detailBody;
    body.innerHTML = '';
    const s = selectedId && shops[selectedId];
    if (!s) {
        els.detailTitle.textContent = 'Shops';
        body.appendChild(WP.el('div', 'wp-hint',
            'Pick a shop to change it, or set a new one up: the wizard walks you through where it stands, '
            + 'who serves, what it sells and its map icon.'));
        const go = WP.el('div', 'wp-actions-row');
        go.appendChild(WP.btn('Set up a new shop', 'smNew', 'primary'));
        body.appendChild(go);
        return;
    }
    els.detailTitle.textContent = s.name || 'Shop';

    // A stocked shop's goods are its stock room's prices: read once, then this page again.
    if (s.mode === 'stocked' && s.containerId && !roomPrices[s.containerId]) {
        const id = selectedId;
        loadRoomPrices(s.containerId).then((p) => { if (p && selectedId === id && !draft) renderDetail(); });
    }
    const d = draftFromShop(s);

    const split = WP.el('div', 'wp-info-split');
    const left = WP.el('div');
    left.style.flex = '1';
    left.style.minWidth = '0';
    const origin = originOf(s);
    left.appendChild(WP.el('div', 'wp-item-sub', 'Shop #' + s.shopId
        + (origin ? '  ·  ' + origin : '') + '  ·  Change opens the wizard on that part'));
    summaryRows(left, d, (key) => ({ action: 'smEdit', arg: key, actionLabel: 'Change' }));
    split.appendChild(left);
    if (d.keeper === 'person') split.appendChild(pedPortrait(d.npcModel));
    body.appendChild(split);

    body.appendChild(WP.el('div', 'wp-hint', 'Its shelf order and tabs are arranged in the game: Edit Shelf, on the shop screen.'));
    // Destructive far-left, the rest far-right — Delete never neighbours the others.
    const actions = WP.el('div', 'wp-actions-row');
    actions.appendChild(WP.btn('Delete', 'smDelete', 'danger'));
    actions.appendChild(WP.el('span', 'wp-actions-split'));
    actions.appendChild(WP.btn('Teleport there', 'smTeleport'));
    actions.appendChild(WP.btn('Change everything', 'smEdit', 'primary', 'kind'));
    body.appendChild(actions);
}

// ========================================
// THE WIZARD
// ========================================

function wizardOpen() { return !!draft; }

/** The list, or the wizard while a shop is being set up or changed. */
function showView() {
    if (!els.listView) return;
    els.listView.style.display = wizardOpen() ? 'none' : '';
    els.wizView.style.display = wizardOpen() ? '' : 'none';
}

function openWizard() {
    draft = newDraft();
    buildWizard('kind');
    showView();
}

/** Change a shop: the wizard, filled in with it, on the part asked for. */
function openEdit(id, at) {
    const s = shops[String(id)];
    if (!s) return;
    draft = draftFromShop(s);
    draft.original = snapshot(draft);
    if (draft.goodsLoading) {
        const mine = draft;
        loadRoomPrices(s.containerId).then((prices) => {
            if (draft !== mine) return;
            mine.goodsLoading = false;
            mine.goods = goodsFrom(prices || {});
            mine.original.goods = JSON.parse(JSON.stringify(mine.goods));
            if (wiz && (wiz.current() === 'goods' || wiz.current() === 'review')) redrawStep();
            if (!prices && wiz) wiz.say('Its stock room\'s prices could not be read: Prices starts empty', 'err');
        });
    }
    buildWizard(at);
    showView();
}

function closeWizard() {
    draft = null;
    wiz = null;
    wizAt = 'kind';
    if (els.wizBody) els.wizBody.innerHTML = '';
    showView();
}

/** Something was set up (or changed) that leaving would throw away. */
function draftTouched() {
    if (!draft) return false;
    if (draft.editing) return changedParts(draft).size > 0;
    return !!(draft.name.trim() || draft.spot || draft.goods.length);
}

async function discardWizard() {
    if (draftTouched()) {
        const editing = !!draft.editing;
        const ok = await WP.confirm({
            title: editing ? 'Stop changing this shop?' : 'Throw this shop away?',
            body: editing ? 'Nothing you changed here is saved.' : 'Nothing has been made yet. Everything you set up for it goes.',
            confirmLabel: editing ? 'Stop' : 'Throw away', danger: true,
        });
        if (!ok) return;
    }
    closeWizard();
}

/** A stepper for the draft's kind (a stocked shop has a Stock room step, and Prices for Goods). A shop
 *  being changed has every step already: all of them are open from the rail. */
function buildWizard(at) {
    const steps = stepsFor(draft.mode, !!draft.editing);
    els.wizBody.innerHTML = '';
    wiz = WP.stepper({
        id: 'sm-wizard',
        steps,
        onGo: (k, from, body) => { wizAt = k; fillStep(k, body); },
        canLeave: (from) => canLeave(from),
        onFinish: finish,
        finishLabel: draft.editing ? 'Save changes' : 'Create shop',
    });
    els.wizBody.appendChild(wiz.root);
    const target = steps.some((s) => s.key === at) ? at : 'kind';
    if (draft.editing) {
        wiz.start('review');                 // the last step reached: every step can be jumped to
        if (target !== 'review') wiz.go(target);
    } else {
        wiz.start(target);
    }
    renderWizHead();
}

function renderWizHead() {
    const name = draft && draft.name.trim();
    els.wizTitle.textContent = draft && draft.editing
        ? 'Change — ' + (name || 'Shop #' + draft.editing)
        : 'New shop' + (name ? ' — ' + name : '');
    els.wizDiscard.textContent = draft && draft.editing ? 'Cancel' : 'Discard';
}

function fillStep(key, body) {
    if (!draft) return;
    body.innerHTML = '';
    const fill = { kind: stepKind, where: stepWhere, keeper: stepKeeper, stock: stepStock,
                   goods: stepGoods, map: stepMap, review: stepReview }[key];
    if (fill) fill(body);
}

function redrawStep() {
    if (wiz && wiz.current()) fillStep(wiz.current(), wiz.body);
}

function hint(body, text) {
    const el = WP.el('div', 'wp-hint', text);
    body.appendChild(el);
    return el;
}

function buttons(body, list) {
    const row = WP.el('div', 'wp-actions-row');
    for (const b of list) {
        if (b) row.appendChild(WP.btn(b[0], b[1], b[2], b[3]));
    }
    body.appendChild(row);
    return row;
}

function jobList() {
    return Object.keys(jobs).map((k) => jobs[k]).sort((a, b) => String(a.name).localeCompare(String(b.name)));
}

// ---- step: kind ----

function stepKind(body) {
    const name = WP.input({ placeholder: 'e.g. 24/7 Supermarket', value: draft.name, inputAction: 'swName' });
    name.maxLength = 100;
    body.appendChild(WP.field('Name', name, true));

    body.appendChild(WP.el('div', 'wp-section-title', 'What kind of shop'));
    const row = WP.el('div', 'wp-choices');
    for (const k of KINDS) {
        const b = WP.el('button', 'wp-choice' + (draft.mode === k.mode ? ' active' : ''));
        b.type = 'button';
        b.dataset.action = 'swKind';
        b.dataset.arg = k.mode;
        b.appendChild(WP.el('span', 'wp-choice-title', k.title));
        b.appendChild(WP.el('span', 'wp-choice-text', k.text));
        row.appendChild(b);
    }
    body.appendChild(row);
    if (draft.editing && draft.original && draft.original.mode !== draft.mode) {
        body.appendChild(WP.statusRow({ label: 'New kind', status: 'warn',
            detail: 'anybody shopping there when you save has their basket put back' }));
    }

    if (business(draft.mode)) {
        const list = jobList();
        if (!list.length) {
            body.appendChild(WP.statusRow({ label: 'Job', status: 'err',
                detail: 'there are no jobs yet: make the business in Jobs first' }));
            return;
        }
        const sel = WP.select([{ value: '0', label: '— pick the job that runs it —' }]
            .concat(list.map((j) => ({ value: String(j.jobId), label: j.name + ' (#' + j.jobId + ')' }))),
            { changeAction: 'swJob' });
        sel.value = String(draft.jobId || 0);
        if (sel.selectedIndex === -1) sel.value = '0';
        const cols = WP.el('div', 'wp-cols-2');
        cols.appendChild(WP.field('Job', sel));
        body.appendChild(cols);
        hint(body, draft.mode === 'stocked'
            ? "The job's managers restock it and arrange its shelf; the money goes to the job's business account."
            : "The job's managers arrange its shelf; the money goes to the job's business account.");
    }
}

// ---- step: where ----

function stepWhere(body) {
    hint(body, 'Go to the counter and stand where the shopkeeper will stand, facing the way they will face '
        + '(towards the customers). Its prompt is on the shopkeeper, or floats over this spot when there is none.');
    body.appendChild(WP.statusRow({ label: 'Shopkeeper stands', status: draft.spot ? 'ok' : 'todo',
        detail: draft.spot ? spotText(draft.spot) : 'not set yet' }));
    if (draft.spot) body.appendChild(WP.place({ x: draft.spot.x, y: draft.spot.y, name: (draft.name || '').trim() || 'The shop' }));

    if (draft.spot) {
        for (const id of Object.keys(shops)) {
            if (id === draft.editing) continue;
            const s = shops[id];
            const d = dist(s, draft.spot);
            if (d < 3) {
                body.appendChild(WP.statusRow({ label: 'Close by', status: 'warn', sub: true,
                    detail: '"' + (s.name || 'Shop') + '" (#' + s.shopId + ') is ' + fixed(d) + ' m away: its prompt and this one may overlap' }));
            }
        }
    }
    buttons(body, [
        ['Go and stand there', 'swPlace', 'primary'],
        ['Use where I am now', 'swHere'],
        draft.spot ? ['Teleport there', 'swTeleport', 'ghost'] : null,
    ]);
}

// ---- step: shopkeeper ----

function stepKeeper(body) {
    const tabs = WP.tabs({
        id: 'sm-keeper-tabs', inline: true, active: draft.keeper,
        tabs: [{ key: 'person', label: 'A person' }, { key: 'prop', label: 'A prop' }, { key: 'none', label: 'Nobody' }],
        onChange: (k) => { draft.keeper = k; redrawStep(); },
    });
    body.appendChild(tabs.root);

    if (draft.keeper === 'prop') {
        const prop = WP.input({ placeholder: 'e.g. p_register01x', value: draft.prop, inputAction: 'swProp' });   // RedM (spur_core, 24 Nov 2026): RDR2's till; was GTA's prop_till_01
        prop.maxLength = 60;
        const cols = WP.el('div', 'wp-cols-2');
        cols.appendChild(WP.field('Prop model', prop));
        body.appendChild(cols);
        hint(body, 'A prop stands on the spot instead of a person (a till, a vending machine), and the prompt floats over it. '
            + 'Check the name against the furnisher or the game\'s object list: a prop the game does not have shows nothing.');
        return;
    }
    if (draft.keeper === 'none') {
        hint(body, 'Nobody and nothing stands there, so the shop has no counter prompt and players cannot open it. '
            + 'Pick a person or a prop to give it one.');
        return;
    }

    const pick = pedPicker({
        id: 'sm-peds',
        value: draft.npcModel,
        suggested: SHOP_STAFF,
        suggestedLabel: 'Shop staff',
        side: [WP.el('div', 'wp-hint', draft.spot
            ? 'Standing on the shop\'s spot, through a camera. ←/→ shows the next person in this list.'
            : 'Set Where first to see them on the spot.'), WP.btn('See them in the world', 'swPreview', 'primary')],
        onPick: (m) => { draft.npcModel = m; },
    });
    els.pedPick = pick;
    body.appendChild(pick.root);
}

// ---- step: stock room ----

function stepStock(body) {
    hint(body, 'A stocked shop sells what its staff put in this container, and its Manage Stock opens it. '
        + 'Not here yet? Make it in Containers, then come back. A room that already has prices brings them to the next step.');
    const box = WP.input({ placeholder: 'Search containers…', value: draft.stockSearch || '', inputAction: 'swStockSearch' });
    box.classList.add('wp-section-search');
    const cols = WP.el('div', 'wp-cols-2');
    cols.appendChild(WP.field('Find', box));
    body.appendChild(cols);
    els.stockList = WP.el('div', 'wp-pick-scroll');
    els.stockList.style.maxWidth = '860px';   // a list to read, not a banner across the panel
    body.appendChild(els.stockList);
    renderStockList();
}

function renderStockList() {
    const list = els.stockList;
    if (!list || !draft) return;
    list.innerHTML = '';
    const q = String(draft.stockSearch || '').trim().toLowerCase();
    const here = draft.spot;
    const rows = stockRooms
        .filter((c) => !q || (String(c.name || '') + ' #' + c.containerId + ' ' + (c.type || '')).toLowerCase().indexOf(q) >= 0)
        .map((c) => ({ c, d: here ? dist(c, here) : null }))
        .sort((a, b) => (a.d === null || b.d === null) ? a.c.containerId - b.c.containerId : a.d - b.d);
    for (const { c, d } of rows) {
        const r = WP.listItem({
            title: c.name || 'Container',
            sub: '#' + c.containerId + (c.type ? ' · ' + c.type : '') + (d === null ? '' : ' · ' + (d < 1000 ? fixed(d) + ' m' : fixed(d / 1000) + ' km') + ' from the shop'),
            id: c.containerId,
            action: 'swStockPick',
        });
        if (Number(draft.containerId) === Number(c.containerId)) r.classList.add('active');
        list.appendChild(r);
    }
    if (!rows.length) list.appendChild(WP.empty(q ? 'No containers match' : 'There are no containers yet'));
}

/** A stock room picked: what it already sells joins the Prices step (what is there is kept). */
function pickStockRoom(id) {
    const d = draft;
    d.containerId = id;
    renderStockList();
    const merge = (prices) => {
        if (draft !== d || Number(d.containerId) !== Number(id) || !prices) return;
        let added = 0;
        for (const g of goodsFrom(prices)) {
            if (!d.goods.some((x) => x.key === g.key)) { d.goods.push(g); added += 1; }
        }
        if (added && wiz) wiz.say(plural(added, 'priced item') + ' from this room added to Prices', 'ok');
    };
    if (roomPrices[id]) merge(roomPrices[id]);
    else loadRoomPrices(id).then(merge);
}

// ---- step: goods / prices ----

function goodsLine(g) {
    const it = items[g.key] || {};
    const line = WP.el('div', 'wp-line');
    line.dataset.key = g.key;
    const img = document.createElement('img');
    img.dataset.itemImg = '';
    img.dataset.itemKey = g.key;
    img.src = itemImageUrl(g.key, it.img);
    line.appendChild(img);
    const text = WP.el('div');
    text.appendChild(WP.el('div', 'wp-item-title', it.name || g.key));
    // RedM (spur_core, 24 Nov 2026): the weight rounded (number, ./format.js). In game a bandage read
    // "0.19999999999998 kg": an item weight can come back from Lua with a float's tail.
    text.appendChild(WP.el('div', 'wp-item-sub', g.key + (it.weight ? ' · ' + number(it.weight) + ' kg' : '')
        + (items[g.key] || !Object.keys(items).length ? '' : ' · not a registered item')));
    line.appendChild(text);
    const price = WP.input({ type: 'number', placeholder: 'price', value: g.price, inputAction: 'swPrice' });
    price.min = 0;
    price.step = 1;
    price.dataset.key = g.key;
    line.appendChild(WP.field('$', price));
    line.appendChild(WP.btn('Remove', 'swUnpick', 'ghost', g.key));
    return line;
}

function renderLines() {
    const box = els.lines;
    if (!box) return;
    box.innerHTML = '';
    if (draft.goodsLoading) {
        box.appendChild(WP.empty('Reading what its stock room sells…'));
        els.linesCount.textContent = '…';
        return;
    }
    for (const g of draft.goods) box.appendChild(goodsLine(g));
    if (!draft.goods.length) {
        box.appendChild(WP.empty(draft.mode === 'stocked'
            ? 'Nothing priced yet. Pick from the list what this shop will sell.'
            : 'Nothing on the shelf yet. Pick from the list what this shop sells.'));
    }
    els.linesCount.textContent = plural(draft.goods.length, 'item');
}

function stepGoods(body) {
    hint(body, draft.mode === 'stocked'
        ? 'A stocked shop sells whatever its staff put in its stock room. Price the goods it will sell here; '
          + 'anything else can be priced in the game, from Manage Stock. Removing one takes it off sale.'
        : 'Pick what it sells from the list. Each one gets a price, in whole dollars; 0 gives it away.');
    const pick = WP.el('div', 'wp-pick');
    const list = itemList({
        id: 'sm-items',
        items,
        picked: (k) => draft.goods.some((g) => g.key === k),
        pill: (k) => {
            const g = draft.goods.find((x) => x.key === k);
            return g && String(g.price).trim() !== '' ? '$' + g.price : 'Picked';
        },
        onToggle: (k) => { if (!draft.goodsLoading) toggleGood(k); },
    });
    els.itemList = list;
    pick.appendChild(list.root);

    const main = WP.el('div', 'wp-pick-main');
    const head = WP.el('div', 'wp-pick-head');
    head.appendChild(WP.el('div', 'wp-section-title', draft.mode === 'stocked' ? 'On sale' : 'On the shelf'));
    els.linesCount = WP.el('span', 'wp-pill');
    head.appendChild(els.linesCount);
    main.appendChild(head);
    const scroll = WP.el('div', 'wp-pick-scroll');
    els.lines = WP.el('div', 'wp-lines');
    scroll.appendChild(els.lines);
    main.appendChild(scroll);
    pick.appendChild(main);
    body.appendChild(pick);
    renderLines();
}

function toggleGood(key) {
    const at = draft.goods.findIndex((g) => g.key === key);
    if (at >= 0) {
        draft.goods.splice(at, 1);
    } else {
        draft.goods.push({ key, price: '' });
    }
    renderLines();
    if (els.itemList) els.itemList.refresh();
    if (at < 0) {
        // Straight to its price.
        const input = els.lines.querySelector('.wp-line[data-key="' + CSS.escape(key) + '"] input');
        if (input) { input.scrollIntoView({ block: 'nearest' }); input.focus(); }
    }
}

/** The goods checked: true, or what is wrong. `mark` paints the lines on screen. */
function goodsProblem(mark) {
    if (draft.goodsLoading) return 'Its prices are still being read';
    if (draft.mode !== 'stocked' && !draft.goods.length) return 'Pick at least one thing for it to sell';
    let bad = null;
    for (const g of draft.goods) {
        const n = Number(String(g.price).trim());
        const ok = String(g.price).trim() !== '' && Number.isInteger(n) && n >= 0;
        const line = mark && els.lines && els.lines.querySelector('.wp-line[data-key="' + CSS.escape(g.key) + '"]');
        if (line) line.classList.toggle('wp-line-err', !ok);
        if (!ok && !bad) bad = (items[g.key] && items[g.key].name) || g.key;
    }
    return bad ? 'Give ' + bad + ' a price: a whole number, 0 or more' : true;
}

// ---- step: map ----

function stepMap(body) {
    const tabs = WP.tabs({
        id: 'sm-map-tabs', inline: true, active: draft.onMap ? 'on' : 'off',
        tabs: [{ key: 'on', label: 'On the map' }, { key: 'off', label: 'Not on the map' }],
        onChange: (k) => { draft.onMap = k === 'on'; redrawStep(); },
    });
    body.appendChild(tabs.root);
    if (!draft.onMap) {
        hint(body, 'Nobody finds it from the map: they have to know where it is.');
        return;
    }
    body.appendChild(WP.el('div', 'wp-section-title', 'Icon'));
    // RedM (spur_core, 24 Nov 2026): named tiles with no picture. The pictures were GTA's blips (img/blips/<n>.webp,
    // which spur_core does not ship), so in game every tile showed a broken image.
    const icons = WP.el('div', 'wp-tiles wp-tiles-small');
    for (const [sprite, label] of BLIPS) {
        const b = WP.el('button', 'wp-tile' + (Number(draft.blipSprite) === sprite ? ' active' : ''));
        b.type = 'button';
        b.dataset.action = 'swBlip';
        b.dataset.arg = sprite;
        b.appendChild(WP.el('span', 'wp-tile-name', label));
        icons.appendChild(b);
    }
    body.appendChild(icons);
    const other = WP.input({ type: 'number', placeholder: 'another blip number (one RedM does not know shows as a point)',
        value: BLIPS.some((b) => b[0] === Number(draft.blipSprite)) ? '' : draft.blipSprite, inputAction: 'swBlipNumber' });
    other.min = 1;
    other.max = 999;
    const cols = WP.el('div', 'wp-cols-2 wp-after');
    cols.appendChild(WP.field('Or icon number', other));
    body.appendChild(cols);

    body.appendChild(WP.el('div', 'wp-section-title', 'Colour'));
    const swatches = WP.el('div', 'wp-swatches');
    for (const [id, label, hex] of BLIP_COLOURS) {
        const b = WP.el('button', 'wp-swatch' + (Number(draft.blipColor) === id ? ' active' : ''));
        b.type = 'button';
        b.dataset.action = 'swColour';
        b.dataset.arg = id;
        const dot = WP.el('span', 'wp-swatch-dot');
        dot.style.background = hex;
        b.appendChild(dot);
        b.appendChild(WP.el('span', null, label));
        swatches.appendChild(b);
    }
    body.appendChild(swatches);
}

// ---- step: review ----

function stepReview(body) {
    const changed = draft.editing ? changedParts(draft) : null;
    summaryRows(body, draft, (key) => ({ action: 'swJump', arg: key, actionLabel: 'Change' }), changed);
    const last = draft.editing
        ? hint(body, changed.size ? 'Save changes writes what changed. A new shopkeeper or a new spot makes the counter again.'
            : 'Nothing has changed yet: Change any part above.')
        : hint(body, 'Create makes it at once: the shopkeeper appears and the shop is open.');
    last.classList.add('wp-apart');
}

// ---- leaving a step, and saving ----

function canLeave(from) {
    const d = draft;
    if (!d) return 'There is no shop being set up';
    if (from === 'kind') {
        if (!d.name.trim()) return 'Give the shop a name';
        if (business(d.mode) && !(Number(d.jobId) > 0)) return 'Pick the job that runs it';
        return true;
    }
    if (from === 'where') return d.spot ? true : 'Set where the shopkeeper stands';
    if (from === 'keeper') {
        if (d.keeper === 'person' && !d.npcModel) return 'Pick a person';
        if (d.keeper === 'prop' && !/^[A-Za-z0-9_-]+$/.test(d.prop.trim())) return 'Type the prop\'s model name';
        return true;
    }
    if (from === 'stock') return Number(d.containerId) > 0 ? true : 'Pick its stock room';
    if (from === 'goods') return goodsProblem(true);
    if (from === 'map') {
        const n = Number(d.blipSprite);
        if (d.onMap && !(Number.isInteger(n) && n >= 1 && n <= 999)) return 'An icon number is 1 to 999';
        return true;
    }
    return true;
}

/** The first step that is not finished, and why: Create and Save check everything again. */
function firstProblem() {
    for (const s of stepsFor(draft.mode, !!draft.editing)) {
        if (s.key === 'review') continue;
        const why = s.key === 'goods' ? goodsProblem(false) : canLeave(s.key);
        if (why !== true) return { key: s.key, why };
    }
    return null;
}

/** What the server is sent: the shop whole (the same fields Create and Save take). A stocked shop's
 *  goods are prices on its room, and one taken off the list is taken off sale there. */
function payloadOf(d) {
    const priced = {};
    for (const g of d.goods) priced[g.key] = Number(g.price);
    const payload = {
        name: d.name.trim(),
        mode: d.mode,
        jobId: business(d.mode) ? Number(d.jobId) : 0,
        containerId: d.mode === 'stocked' ? Number(d.containerId) : 0,
        npcModel: d.keeper === 'person' ? d.npcModel : '',
        prop: d.keeper === 'prop' ? d.prop.trim() : '',
        x: d.spot.x, y: d.spot.y, z: d.spot.z, heading: d.spot.heading,
        blipSprite: d.onMap ? Number(d.blipSprite) : 0,
        blipColor: Number(d.blipColor),
    };
    if (d.mode === 'stocked') {
        payload.prices = priced;
        const before = roomPrices[d.containerId] || {};
        payload.unsell = Object.keys(before).filter((k) => !(k in priced));
    } else {
        payload.catalog = priced;
    }
    return payload;
}

function finish() {
    const d = draft;
    if (!d || d.saving) return;
    if (d.editing && !changedParts(d).size) {
        wiz.say('Nothing has changed', 'err');
        return;
    }
    const problem = firstProblem();
    if (problem) {
        wiz.setStatus(problem.key, 'error');
        wiz.say(problem.why, 'err');
        return;
    }
    const payload = payloadOf(d);
    // Changing a shop: its goods are written only when they (or its kind, or its room) changed — a
    // catalog sent again redraws every customer's screen for nothing.
    const changed = d.editing ? changedParts(d) : null;
    if (changed && !changed.has('goods') && !changed.has('kind') && !changed.has('stock')) {
        delete payload.catalog;
        delete payload.prices;
        delete payload.unsell;
    }
    const room = d.mode === 'stocked' ? Number(d.containerId) : 0;
    const done = (res, id, made) => {
        if (draft !== d) return;
        d.saving = false;
        if (!res || res.ok !== true) {   // {} is a call that never reached the server: not a success
            wiz.say((res && res.why) || (made ? 'The shop was not made' : 'The shop was not saved'), 'err');
            return;
        }
        if (room) delete roomPrices[room];   // read again for its page
        const note = res.unpriced ? '  ·  ' + plural(res.unpriced, 'price') + ' did not take' : '';
        WP.result((made ? 'Shop created: #' + id : 'Shop saved') + note, res.unpriced ? 'err' : 'ok');
        closeWizard();
        if (shops[id]) selectShop(id); else pendingSelect = id;
    };

    d.saving = true;
    if (d.editing) {
        wiz.say('Saving…');
        nuiCallback('smWizardUpdate', { shopId: Number(d.editing), data: payload })
            .then((res) => done(res, d.editing, false));
    } else {
        wiz.say('Creating…');
        nuiCallback('smWizardCreate', payload)
            .then((res) => done(res, res && res.shopId !== undefined ? String(res.shopId) : null, true));
    }
}

// ---- the section ----

WhipPanel.registerSection({
    id: 'shops',
    group: 'economy',
    label: 'Shops',
    order: 20,

    render(root) {
        els = {};

        // ---- the wizard, in the list's place while a shop is set up or changed. First in the section,
        // so the shell's '/' finds a picker's search before the list's (sectionSearch takes the first). ----
        els.wizView = WP.el('div', 'wp-section-solo wp-section-wide');
        els.wizView.style.display = 'none';
        const head = WP.el('div', 'wp-actions-row wp-head-row');
        els.wizTitle = WP.el('div', 'wp-pane-title', 'New shop');
        head.appendChild(els.wizTitle);
        head.appendChild(WP.el('span', 'wp-actions-split'));
        els.wizDiscard = WP.btn('Discard', 'swDiscard', 'ghost');
        head.appendChild(els.wizDiscard);
        els.wizView.appendChild(head);
        els.wizBody = WP.el('div', 'wp-view');
        els.wizView.appendChild(els.wizBody);
        root.appendChild(els.wizView);

        els.listView = WP.el('div', 'wp-view');
        els.listView.appendChild(WP.toolbar({
            left: [WP.btn('+ New Shop', 'smNew')],
            search: { inputAction: 'smSearch', placeholder: 'Search shops…' },
        }));

        const split = WP.el('div', 'wp-split');
        const listCol = WP.el('div', 'wp-list-col');
        els.count = WP.el('div', 'wp-list-count', '');
        listCol.appendChild(els.count);
        els.list = WP.el('div', 'wp-list');
        listCol.appendChild(els.list);
        split.appendChild(listCol);

        const detail = WP.el('div', 'wp-detail');
        els.detailTitle = WP.el('div', 'wp-pane-title', 'Shops');
        detail.appendChild(els.detailTitle);
        els.detailBody = WP.el('div');
        detail.appendChild(els.detailBody);
        split.appendChild(detail);
        els.listView.appendChild(split);
        root.appendChild(els.listView);

        renderList();
        renderDetail();
        // The panel is built again each time it opens: a shop half set up comes back where it was.
        if (draft) buildWizard(wizAt);
        showView();
    },

    onData(kind, payload) {
        if (kind === 'all') {
            normalizeShops(payload.shops);
            normalizeJobs(payload.jobs || []);
            if (payload.items) items = payload.items;
            if (Array.isArray(payload.containers)) stockRooms = payload.containers;
            if (Array.isArray(payload.configShops)) configShops = payload.configShops;
            roomPrices = {};
            if (selectedId && !shops[selectedId]) selectedId = null;
            renderList();
            renderDetail();
        } else if (kind === 'refresh') {
            normalizeShops(payload.shops);
            if (payload.jobs) normalizeJobs(payload.jobs);
            if (pendingSelect && shops[pendingSelect] && !wizardOpen()) {
                const id = pendingSelect;
                pendingSelect = null;
                selectShop(id);
            } else {
                if (selectedId && !shops[selectedId]) selectedId = null;
                renderList();
                if (!wizardOpen()) renderDetail();
            }
        } else if (kind === 'spot' && draft) {
            // Where: the spot stood on in the world (tools/panel_sections/shops.lua).
            draft.spot = { x: Number(payload.x), y: Number(payload.y), z: Number(payload.z), heading: Number(payload.heading) };
            if (wiz && wiz.current() === 'where') redrawStep();
        } else if (kind === 'keeper' && draft) {
            // Shopkeeper: the one chosen while looking at them in the world.
            draft.keeper = 'person';
            draft.npcModel = String(payload.model || draft.npcModel);
            if (wiz && wiz.current() === 'keeper') redrawStep();
        }
    },

    onEscape() {
        if (wizardOpen()) {
            // Changing a shop: back to the summary of what changed first, then out.
            if (draft.editing && wiz && wiz.current() !== 'review') { wiz.go('review'); return true; }
            // Setting one up: a step back at a time; on the first, Escape offers to throw it away.
            if (draft.editing || !(wiz && wiz.escape())) discardWizard();
            return true;
        }
        // Drill-down stage: an open shop closes before the panel does.
        if (selectedId !== null) { noShop(); return true; }
        return false;
    },

    actions: {
        smSearch: (el) => { search = el.value.toLowerCase(); renderList(); },
        smNew: () => openWizard(),
        smSelect: (el) => selectShop(el.dataset.id),
        smEdit: (el) => { if (selectedId) openEdit(selectedId, el.dataset.arg); },
        smDelete: async () => {
            if (!selectedId) return;
            const s = shops[selectedId];
            const ok = await WP.confirm({
                title: 'Delete shop?',
                body: `#${selectedId} "${s ? s.name : ''}" will be removed, with its shopkeeper and map icon.`
                    + (fromConfig(s) ? ` It is a starting shop from config.lua: it comes back at the next restart unless "${s.key}" is taken out of Config.Shops.` : ''),
                confirmLabel: 'Delete',
                danger: true,
            });
            if (!ok) return;
            nuiCallback('smDeleteShop', { shopId: parseInt(selectedId, 10) });
            delete shops[selectedId];
            noShop();
        },
        smTeleport: () => {
            const s = selectedId && shops[selectedId];
            if (s) nuiCallback('smTeleport', { x: s.x, y: s.y, z: s.z, heading: s.heading });
        },

        // ---- the wizard ----
        swDiscard: () => discardWizard(),
        swJump: (el) => { if (wiz) wiz.jump(el.dataset.arg); },
        swName: (el) => { if (draft) { draft.name = el.value; renderWizHead(); } },
        swKind: (el) => {
            if (!draft || draft.mode === el.dataset.arg) return;
            const before = stepsFor(draft.mode).map((s) => s.label).join();
            draft.mode = el.dataset.arg;
            // A stocked shop has a Stock room step (and Prices for Goods): the rail changes with it.
            // Its goods are a room's prices, not a catalog: the other kind's list is not carried over.
            if (stepsFor(draft.mode).map((s) => s.label).join() !== before) {
                if (draft.editing) {
                    const s = shops[draft.editing];
                    const fresh = s ? draftFromShop(Object.assign({}, s, { mode: draft.mode })) : null;
                    draft.goods = fresh && !fresh.goodsLoading ? fresh.goods : [];
                }
                buildWizard('kind');
            } else {
                redrawStep();
            }
        },
        swJob: (el) => { if (draft) draft.jobId = parseInt(el.value, 10) || 0; },
        swPlace: () => {
            if (!draft) return;
            nuiCallback('smPlaceSpot', { name: draft.name.trim() }).then((res) => {
                if (res && res.ok === false && wiz) wiz.say('Something else is using the screen', 'err');
            });
        },
        swHere: () => {
            nuiCallback('smGetPlayerPos', {}).then((pos) => {
                if (!draft || !pos || pos.x === undefined) return;
                draft.spot = { x: pos.x, y: pos.y, z: pos.z, heading: pos.heading };
                redrawStep();
            });
        },
        swTeleport: () => {
            const p = draft && draft.spot;
            if (p) nuiCallback('smTeleport', { x: p.x, y: p.y, z: p.z, heading: p.heading });
        },
        swProp: (el) => { if (draft) draft.prop = el.value; },
        swPreview: () => {
            if (!draft || !els.pedPick) return;
            const list = els.pedPick.visible();
            let at = list.findIndex((p) => p.model === draft.npcModel);
            if (at < 0) { list.unshift({ model: draft.npcModel, name: pedName(draft.npcModel) }); at = 0; }
            const s = draft.spot || {};
            nuiCallback('smPreviewKeeper', {
                list: list.map((p) => ({ m: p.model, n: p.name })), index: at + 1,
                x: s.x, y: s.y, z: s.z, heading: s.heading, name: draft.name.trim(),
            }).then((res) => {
                if (res && res.ok === false && wiz) wiz.say(res.why || 'The preview could not start', 'err');
            });
        },
        swStockSearch: (el) => { if (draft) { draft.stockSearch = el.value; renderStockList(); } },
        swStockPick: (el) => { if (draft) pickStockRoom(Number(el.dataset.id)); },
        swPrice: (el) => {
            const g = draft && draft.goods.find((x) => x.key === el.dataset.key);
            if (!g) return;
            g.price = el.value;
            el.closest('.wp-line').classList.remove('wp-line-err');
            if (els.itemList) els.itemList.refresh();
        },
        swUnpick: (el) => { if (draft) toggleGood(el.dataset.arg); },
        swBlip: (el) => { if (draft) { draft.blipSprite = Number(el.dataset.arg); redrawStep(); } },
        swBlipNumber: (el) => {
            if (!draft) return;
            draft.blipSprite = el.value;
            const n = Number(el.value);
            for (const t of el.closest('.wp-step-body').querySelectorAll('.wp-tiles .wp-tile')) {
                t.classList.toggle('active', Number(t.dataset.arg) === n);
            }
        },
        swColour: (el) => { if (draft) { draft.blipColor = Number(el.dataset.arg); redrawStep(); } },
    },
});
