// ========================================
// /whip SECTION — Garages
//
// List on the left, the picked garage's page on the right: what it is, said in words, then its parking
// bays and the cars in it, each a collapsible group.
//
// A GARAGE IS SET UP AND CHANGED WITH ONE WIZARD, WP.stepper as
// the shop and job wizards use it, in the list's place:
//
//   Name    what players see; the key it is stored under is made from it (and fixed once made)
//   Bays    set out in the world: aim at the ground, turn, put down; aim at one to move it or take it
//           away (gwPlaceBays: the one bay tool, PropertyEditor.placeBays — every garage's)
//   Map     its marker (the bays' middle, where you stand, or where it is) and its blip's icon and colour
//   Create  the lot, checked: the server makes the garage and every bay at once (gwCreate), from
//           where the admin stands (each bay leashed to them: Config.GarageWizardReach)
//
// A GARAGE'S PAGE IS ITS SUMMARY, as a shop's is: Name, Bays and Map, each with Change — the wizard,
// filled in with the garage (draftFromGarage), on that part; every step open from the rail. Its last
// step is Save: what changed only (changedParts), at once (gwSave → spur_core:gmWizardSave), its bays
// carrying their spotIds so a moved bay stays that bay. The old form (key and name boxes, four marker
// coordinates, blip numbers, Update) went with it, and so did the bay list's Delete and its own Set out
// button: one way to change a garage. A private garage (a property's) is shown, never changed here.
//
// Mutation callbacks live in tools/panel_sections/garages.lua. onData('all'): the first payload after
// enter seeds the view, every later one adopts idempotently around the page that is open.
// ========================================

import { WhipPanel, WP } from '../whip-panel.js';
import { nuiCallback } from '../utils.js';
import { BLIP_COLOURS } from './pickers.js';
import { plural, fixed } from './format.js';

let garages = {};        // keyed by garage key
let vehicleCounts = {};  // { [key]: number }
let spotCounts = {};     // { [key]: number } — bays per garage, for the unreachable flag
let editingKey = null;   // the garage whose page is open, or null
let vehicles = [];       // vehicles in the selected garage
let spots = [];          // parking bays belonging to the selected garage
let spotsFor = null;     // the garage `spots` came for: a garage is changed only once its own bays are here
let els = {};
let search = '';
let seeded = false;      // first 'all' after enter resets the form; later ones adopt

// HAS render() BUILT THE DOM YET? The shell delivers data to every registered section whenever it
// arrives, but only builds a section's elements the first time the PANEL is opened — so a push that
// beats the first open reaches handlers whose els.* are all undefined. Bay counts are pushed
// whenever the spot set changes, and that set syncs at login.
//
// Dropping early data loses nothing: entering the section re-fetches everything.
let built = false;

let draft = null;          // the garage being set up, while the wizard is open
let wiz = null;            // its WP.stepper
let wizAt = 'name';        // the step it is on, so the panel reopens there
let pendingSelect = null;  // a garage just made: opened once the list has it

/** Map icons a garage is likely to want, by GTA blip sprite. Any other number can
 *  be typed. */
// RedM (spur_core, 24 Nov 2026): only the numbers shared/rdr_compat.lua turns into an RDR2 icon (its SPRITE table).
// GTA's Garage door, Shutter, Hangar, Sports car and Tow hook have none and all showed as the same plain point.
const GARAGE_BLIPS = [
    [357, 'Wagon'], [225, 'Coach'], [40, 'Home'], [1, 'Point'],
];
const GW_MAX_BAYS = 40;   // tools/panel_sections/garages.lua and server/devtools.lua say the same

const dist = (a, b) => Math.hypot((a.x || 0) - (b.x || 0), (a.y || 0) - (b.y || 0), (a.z || 0) - (b.z || 0));

function normalize(raw) {
    garages = {};
    if (Array.isArray(raw)) {
        for (const g of raw) { if (g && g.key) garages[g.key] = g; }
    } else if (raw) {
        for (const k of Object.keys(raw)) {
            const g = raw[k];
            if (g) {
                if (!g.key) g.key = k;
                garages[g.key] = g;
            }
        }
    }
}

// ---- list ----

function renderList() {
    els.list.innerHTML = '';
    const keys = Object.keys(garages).sort();
    let shown = 0;

    for (const key of keys) {
        const g = garages[key];
        const hay = ((g.name || '') + ' ' + key).toLowerCase();
        if (search && !hay.includes(search)) continue;
        shown += 1;

        // THE SUBTITLE SAYS WHETHER IT WORKS. Bays are the only way into a garage, so one with
        // none is a name and a blip with no door — and until this said so, such a garage was
        // indistinguishable in the list from a working one. Reading "NO BAYS" here is what sends
        // an admin to the button that fixes it.
        const bays = spotCounts[key] || 0;
        const item = WP.listItem({
            title: g.name || key,
            sub: g.private
                ? 'private  ·  ' + (g.managedBy || key)
                : bays === 0
                ? key + '  ·  NO BAYS, unreachable'
                : key + '  ·  ' + bays + (bays === 1 ? ' bay' : ' bays'),
            pill: vehicleCounts[key] || 0,
            id: key,
            action: 'gmSelect',
        });
        if (bays === 0) item.classList.add('wp-item-warn');
        if (editingKey === key) item.classList.add('active');
        els.list.appendChild(item);
    }

    if (shown === 0) {
        els.list.appendChild(WP.empty(search ? 'No garages match "' + search + '"' : 'No garages'));
    }
    els.count.textContent = shown + ' of ' + keys.length;
}

// ---- a garage's page ----

function selectGarage(key) {
    const g = garages[key];
    if (!g) return;
    editingKey = key;
    els.intro.style.display = 'none';
    els.form.style.display = '';
    vehicles = [];
    // Cleared rather than left showing the previous garage's bays while the new list arrives, and not
    // changeable until they have come (spotsFor): a draft made without them would save a garage with none.
    spots = [];
    spotsFor = null;
    renderDetail();
    renderVehicles();
    renderSpots();
    renderList();

    // Request vehicles for this garage. The Lua side also treats this as "the selection changed"
    // and answers separately with the bays — see gmGetGarageVehicles in the panel section.
    nuiCallback('gmGetGarageVehicles', { garageKey: key });
}

/** No garage picked: the pane offers the wizard (Set up a new garage). */
function noGarage() {
    editingKey = null;
    vehicles = [];
    spots = [];
    spotsFor = null;
    els.intro.style.display = '';
    els.form.style.display = 'none';
    renderList();
}

/** A garage's page: its parts said in words, each with Change (the wizard, on that part), and Delete, Teleport
 *  there and Change everything. A PRIVATE GARAGE IS CHANGED WHERE IT IS OWNED: a property's garage follows its
 *  property — name, position and bays — so changing it here would be undone at the next change there, and the
 *  server refuses its key anyway. Its page has no Change; its cars are still listed, and can still be moved out. */
function renderDetail() {
    const g = editingKey && garages[editingKey];
    if (!g) return;
    const body = els.summary;
    body.innerHTML = '';
    els.formTitle.textContent = g.name || editingKey;
    const managed = !!g.private;
    const d = draftFromGarage(g, spotsFor === editingKey ? spots : null);
    body.appendChild(WP.el('div', 'wp-item-sub', 'Key ' + editingKey
        + (managed ? '  ·  private' : '  ·  Change opens the wizard on that part')));
    summaryRows(body, d, managed ? () => ({}) : (key) => ({ action: 'gmEdit', arg: key, actionLabel: 'Change' }));
    if (managed) {
        body.appendChild(WP.el('div', 'wp-hint', 'Private: ' + (g.managedBy || 'managed elsewhere')
            + '. Its name, position and bays follow the property: change them in /spur → Properties. Only its '   // RedM (spur_core, 24 Nov 2026): /spur is spur_core's admin panel (was /whip)
            + 'owner and keyholders can use it.'));
    }
    // Destructive far-left, the rest far-right — Delete never neighbours the others.
    const actions = WP.el('div', 'wp-actions-row');
    if (!managed) actions.appendChild(WP.btn('Delete', 'gmDelete', 'danger'));
    actions.appendChild(WP.el('span', 'wp-actions-split'));
    actions.appendChild(WP.btn('Teleport there', 'gmTeleport'));
    if (!managed) actions.appendChild(WP.btn('Change everything', 'gmEdit', 'primary', 'name'));
    body.appendChild(actions);
}

// ---- vehicles group (the old gmRenderVehicles) ----

function renderVehicles() {
    els.vehTitle.textContent = 'Vehicles in this Garage (' + vehicles.length + ')';
    els.vehList.innerHTML = '';

    if (vehicles.length === 0) {
        els.vehList.appendChild(WP.empty('No vehicles in this garage'));
        return;
    }

    // Move-target options: every public garage except the one being viewed. Not into a private
    // one — that is somebody's home, and the server refuses its key.
    const options = [{ value: '', label: 'Move to…' }];
    for (const key of Object.keys(garages).sort()) {
        if (key === editingKey || garages[key].private) continue;
        options.push({ value: key, label: garages[key].name || key });
    }

    for (const v of vehicles) {
        const row = WP.el('div', 'wp-feed-row');
        row.appendChild(WP.el('span', 'wp-pill', v.plate || '???'));
        row.appendChild(WP.el('span', 'wp-item-title', v.model || 'unknown'));
        row.appendChild(WP.el('span', 'wp-info-value wp-info-value-mono', 'CID:' + (v.ownerCharId || '?')));
        const sel = WP.select(options, { changeAction: 'gmMoveVehicle' });
        sel.dataset.id = v.vehicleId;
        row.appendChild(WP.field('Move', sel));
        els.vehList.appendChild(row);
    }
}

// ---- parking bays group ----
//
// THE BAYS A GARAGE IS REACHED THROUGH. A spot is an entry point, and a car park is one garage with
// many of them rather than many garages. See
// server/garage_spots.lua.
//
// SET OUT IN THE WORLD, with the one bay tool every garage uses: Change on the Bays row (the wizard's Bays
// step). This list is where they are: Teleport To on a row takes you to a bay.

function renderSpots() {
    els.spotTitle.textContent = 'Parking Bays (' + spots.length + ')';
    els.spotList.innerHTML = '';

    if (spots.length === 0) {
        // THE STRONGEST WORDING ON THIS SCREEN, because this is the one state that silently
        // breaks a garage: bays are the only way in, so no bays means the cars listed below are
        // unreachable. The old copy said the garage "still works from its own position", which
        // stopped being true when the old prompt was removed.
        els.spotList.appendChild(WP.empty(
            'No parking bays, so players cannot reach this garage. '
            + 'Go to it and press Change on Bays.'));
        return;
    }

    for (const s of spots) {
        const row = WP.el('div', 'wp-feed-row');
        row.appendChild(WP.el('span', 'wp-pill', '#' + s.spotId));
        row.appendChild(WP.el('span', 'wp-item-title',
            s.dist === null || s.dist === undefined
                ? 'position unknown'
                : s.dist.toFixed(1) + 'm from the garage'));
        row.appendChild(WP.el('span', 'wp-actions-split'));

        const tp = WP.btn('Teleport To', 'gmSpotTeleport');
        tp.dataset.id = s.spotId;
        row.appendChild(tp);

        els.spotList.appendChild(row);
    }
}

// ========================================
// THE WIZARD (see the header)
// ========================================

function newDraft() {
    return {
        editing: null,                     // the key of the garage being changed, or null for a new one
        name: '', key: '', keyEdited: false,
        bays: [],                          // [{ x, y, z, heading, id? }] in the order set out; id = a saved bay's spotId
        marker: null, markerSet: false,    // the map marker: where the admin stood, or (unset) the bays' middle
        markerSaved: false,                // a changed garage's marker, where it is now
        blipSprite: 357, blipColor: 3,
        saving: false,
    };
}

/** A garage as a draft: the wizard filled in with it as it is. `bays` are its spots (with their spotIds), or null
 *  while they are still being read (its page says so; the wizard waits for them). */
function draftFromGarage(g, bays) {
    return Object.assign(newDraft(), {
        editing: g.key,
        name: g.name || g.key, key: g.key, keyEdited: true,
        bays: bays ? bays.map((s) => ({ x: Number(s.x), y: Number(s.y), z: Number(s.z), heading: Number(s.heading) || 0,
                                        id: Number(s.spotId) })) : null,
        marker: { x: Number(g.x) || 0, y: Number(g.y) || 0, z: Number(g.z) || 0, heading: Number(g.heading) || 0 },
        markerSet: true, markerSaved: true,
        blipSprite: Number(g.blipSprite) || 357,
        blipColor: g.blipColor === undefined || g.blipColor === null ? 3 : Number(g.blipColor),
    });
}

/** What a changed garage was when its wizard opened, to say what changed against. */
function snapshot(d) {
    return JSON.parse(JSON.stringify({ name: d.name, bays: d.bays, marker: markerOf(d),
                                       blipSprite: d.blipSprite, blipColor: d.blipColor }));
}

const nearly = (a, b) => Math.abs((Number(a) || 0) - (Number(b) || 0)) <= 0.005;
const turned = (a, b) => Math.abs(((((Number(a) || 0) - (Number(b) || 0)) % 360) + 540) % 360 - 180) > 0.05;

/** Do two bay lists differ? The bay tool keeps a list's order (a moved bay keeps its place), so place by place. */
function baysDiffer(a, b) {
    if (!a || !b || a.length !== b.length) return true;
    return a.some((x, i) => {
        const y = b[i];
        return x.id !== y.id || !nearly(x.x, y.x) || !nearly(x.y, y.y) || !nearly(x.z, y.z) || turned(x.heading, y.heading);
    });
}

/** The parts of a garage being changed that differ from the garage as it is, by step. */
function changedParts(d) {
    const out = new Set();
    const o = d && d.original;
    if (!o) return out;
    if (d.name.trim() !== o.name.trim()) out.add('name');
    if (baysDiffer(d.bays, o.bays)) out.add('bays');
    const a = markerOf(d), b = o.marker;
    if (!a || !b || !nearly(a.x, b.x) || !nearly(a.y, b.y) || !nearly(a.z, b.z)
        || Number(d.blipSprite) !== Number(o.blipSprite) || Number(d.blipColor) !== Number(o.blipColor)) out.add('map');
    return out;
}

/** A key made from a name, as the server's Sanitize.key keeps it: letters, digits, _ and -. */
function keyFromName(name) {
    return String(name || '').normalize('NFKD').replace(/[̀-ͯ]/g, '').toLowerCase()
        .replace(/[^a-z0-9_-]+/g, '_').replace(/_+/g, '_').replace(/^_+|_+$/g, '').slice(0, 60);
}

const middle = (bays) => {
    if (!bays || !bays.length) return null;
    let x = 0, y = 0, z = 0;
    for (const b of bays) { x += b.x; y += b.y; z += b.z; }
    return { x: x / bays.length, y: y / bays.length, z: z / bays.length, heading: 0 };
};
const markerOf = (d) => (d.markerSet && d.marker ? d.marker : middle(d.bays));
/** Where the marker is, in words (the map under the row shows it): where it is now, where the admin stood, or the
 *  bays' middle. */
const markerWords = (d) => {
    const m = markerOf(d);
    if (!m) return 'no marker';
    return !d.markerSet ? 'in the bays\' middle' : d.markerSaved ? 'set' : 'where you stood';
};

/** The steps: the last one Creates a new garage, or Saves a changed one. */
const stepsFor = (editing) => [
    { key: 'name', label: 'Name' }, { key: 'bays', label: 'Bays' }, { key: 'map', label: 'Map' },
    { key: 'review', label: editing ? 'Save' : 'Create' },
];

/** One row per part of a garage, each with `rowOpts(stepKey)`'s button (Change): its page and the wizard's last
 *  step share these. `changed` marks the parts a Save would write. */
function summaryRows(body, d, rowOpts, changed) {
    const mark = (key, text) => (changed && changed.has(key) ? text + '  ·  changed' : text);
    const row = (label, key, status, detail) =>
        body.appendChild(WP.statusRow({ label, status, detail: mark(key, detail), ...rowOpts(key) }));
    const name = d.name.trim();
    row('Name', 'name', name ? 'ok' : 'err', name ? name + '  ·  key ' + d.key : 'none');
    row('Bays', 'bays', d.bays === null ? 'todo' : d.bays.length ? 'ok' : 'err',
        d.bays === null ? 'reading its bays…' : d.bays.length ? plural(d.bays.length, 'bay') : 'none: nobody can reach it');
    const icon = GARAGE_BLIPS.find((b) => b[0] === Number(d.blipSprite));
    const colour = BLIP_COLOURS.find((c) => c[0] === Number(d.blipColor));
    row('Map', 'map', markerOf(d) ? 'ok' : 'err', markerWords(d)
        + '  ·  ' + (icon ? icon[1] : 'icon ' + d.blipSprite) + ', ' + (colour ? colour[1].toLowerCase() : 'colour ' + d.blipColor));
    // The garage on the map, with its own icon and colour.
    const m = markerOf(d);
    if (m) body.appendChild(WP.place({ x: m.x, y: m.y, name: d.name.trim() || 'The garage', sprite: Number(d.blipSprite) || 1,
        colour: colour ? colour[2] : '#ffffff' }));
}

function wizardOpen() { return !!draft; }

/** The list, or the wizard while a garage is being set up. */
function showView() {
    if (!els.listView) return;
    els.listView.style.display = wizardOpen() ? 'none' : '';
    els.wizView.style.display = wizardOpen() ? '' : 'none';
}

function openWizard() {
    draft = newDraft();
    bayPicks.clear();
    buildWizard('name');
    showView();
}

/** Change a garage: the wizard, filled in with it, on the part asked for. Not before its bays have come: a draft
 *  without them would save a garage with none. */
function openEdit(key, at) {
    const g = garages[key];
    if (!g || g.private) return;
    if (spotsFor !== key) {
        WP.result('Its bays are still being read: a moment, then Change again', 'err');
        return;
    }
    draft = draftFromGarage(g, spots);
    draft.original = snapshot(draft);
    bayPicks.clear();
    buildWizard(at);
    showView();
}

function closeWizard() {
    draft = null;
    bayPicks.clear();
    wiz = null;
    wizAt = 'name';
    if (els.wizBody) els.wizBody.innerHTML = '';
    showView();
}

/** Something was set up (or changed) that leaving would throw away. */
function draftTouched() {
    if (!draft) return false;
    if (draft.editing) return changedParts(draft).size > 0;
    return !!(draft.name.trim() || draft.bays.length);
}

async function discardWizard() {
    if (draftTouched()) {
        const editing = !!draft.editing;
        const ok = await WP.confirm({
            title: editing ? 'Stop changing this garage?' : 'Throw this garage away?',
            body: editing ? 'Nothing you changed here is saved.' : 'Nothing has been made yet. Its name and the bays set out for it go.',
            confirmLabel: editing ? 'Stop' : 'Throw away', danger: true,
        });
        if (!ok) return;
    }
    closeWizard();
}

/** A garage being changed has every step already: all of them are open from the rail. */
function buildWizard(at) {
    const steps = stepsFor(!!draft.editing);
    els.wizBody.innerHTML = '';
    wiz = WP.stepper({
        id: 'gw-wizard',
        steps,
        onGo: (k, from, body) => { wizAt = k; fillStep(k, body); },
        canLeave: (from) => canLeave(from),
        onFinish: finish,
        finishLabel: draft.editing ? 'Save changes' : 'Create garage',
    });
    els.wizBody.appendChild(wiz.root);
    const target = steps.some((s) => s.key === at) ? at : 'name';
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
        ? 'Change — ' + (name || draft.editing)
        : 'New garage' + (name ? ' — ' + name : '');
    els.wizDiscard.textContent = draft && draft.editing ? 'Cancel' : 'Discard';
}

function fillStep(key, body) {
    if (!draft) return;
    body.innerHTML = '';
    const fill = { name: stepName, bays: stepBays, map: stepMap, review: stepReview }[key];
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
    for (const b of list) if (b) row.appendChild(WP.btn(b[0], b[1], b[2], b[3]));
    body.appendChild(row);
    return row;
}

// ---- step: name ----

function stepName(body) {
    const name = WP.input({ placeholder: 'e.g. Town Stables', value: draft.name, inputAction: 'gwName' });
    name.maxLength = 100;
    body.appendChild(WP.field('Name', name, true));
    const key = WP.input({ placeholder: 'made from the name', value: draft.key, inputAction: 'gwKey' });
    key.maxLength = 60;
    // A garage that exists keeps its key: every car parked there is filed under it.
    key.readOnly = !!draft.editing;
    els.gwKey = key;
    const cols = WP.el('div', 'wp-cols-2');
    cols.appendChild(WP.field('Key', key));
    body.appendChild(cols);
    hint(body, draft.editing
        ? 'Players see the name on the map and over its bays. The key stays: every car parked here is filed under it.'
        : 'Players see the name on the map and over its bays. The key is how it is stored: every car parked '
            + 'here is filed under it, so it is made from the name and cannot change once the garage exists.');
}

// ---- step: bays ----

function stepBays(body) {
    hint(body, 'Go to the car park and set its bays out in the world: aim at the ground where a car will park, turn '
        + 'the bay to face the way the car parks, and put it down. Players reach the garage from any of its bays, '
        + 'and a car comes out in the one they are standing in.');
    const n = draft.bays.length;
    body.appendChild(WP.statusRow({ label: 'Bays', status: n ? 'ok' : 'todo',
        detail: n ? plural(n, 'bay') + ' set out' + (n >= GW_MAX_BAYS ? '  ·  the most a garage has here' : '') : 'none yet' }));
    buttons(body, [
        // Once there are bays, the property wizard's words: it is the same tool.
        [n ? 'Place & Edit Garage Locations' : 'Set out bays in the world', 'gwBays', 'primary'],
        n ? ['Take them all away', 'gwBaysClear', 'ghost'] : null,
    ]);
    hint(body, 'In the world: Enter puts a bay down, or picks up the one you aim at to move it (Enter again puts it '
        + 'down). Q / E turn it, ↑ / ↓ raise or lower it (Alt, slowly; the height is kept as you aim), X takes the one '
        + 'you aim at away, Esc is done and C puts a carried bay back, or undoes the lot. On a controller: A, LT / RT, '
        + 'the D-pad, X, Menu and B. The card in the corner shows them.'
        + (draft.editing ? ' Nothing changes for players until Save changes.' : ''));
    // Bays are picked, then taken away together (the bar). Picked by their place in the list: any change to the
    // list clears the picks (bayPicks.clear).
    if (n) body.appendChild(bayPicks.bar());
    draft.bays.forEach((b, i) => {
        const row = WP.el('div', 'wp-feed-row');
        row.appendChild(bayPicks.box(i));
        // A saved bay by its number (the one its page lists); a new one as new, or by its place in a new garage.
        row.appendChild(WP.el('span', 'wp-pill', b.id !== undefined ? '#' + b.id : draft.editing ? 'new' : '#' + (i + 1)));
        row.appendChild(WP.el('span', 'wp-item-title', i === 0 ? 'the first bay' : fixed(dist(b, draft.bays[0])) + ' m from the first'));
        row.appendChild(WP.el('span', 'wp-info-value wp-info-value-mono', 'facing ' + fixed(b.heading, 0) + '°'));
        row.appendChild(WP.btn('Teleport', 'gwBayTeleport', undefined, i));
        body.appendChild(row);
    });
}

const bayPicks = WP.picks({ id: 'gw-bays', one: 'bay', many: 'bays',
    actions: [{ label: (n) => 'Remove ' + plural(n, 'bay'), action: 'gwBaysRemove', kind: 'danger' }] });

// ---- step: map ----

function stepMap(body) {
    const m = markerOf(draft);
    body.appendChild(WP.statusRow({ label: 'Map marker', status: m ? 'ok' : 'todo',
        detail: m ? markerWords(draft) : 'set its bays out first' }));
    // A changed garage's marker can go back to where it is, once moved.
    const was = draft.original && draft.original.marker;
    const moved = was && !(draft.markerSet && draft.markerSaved);
    buttons(body, [
        ['Where I am now', 'gwMarkerHere'],
        draft.markerSet ? ['Back to the middle of the bays', 'gwMarkerMiddle', 'ghost'] : null,
        moved ? ['Back to where it is', 'gwMarkerSaved', 'ghost'] : null,
    ]);
    hint(body, 'Where its blip sits on the map. Cars come out at its bays, not here.');

    body.appendChild(WP.el('div', 'wp-section-title', 'Icon'));
    // RedM (spur_core, 24 Nov 2026): named tiles with no picture. The pictures were GTA's blips (img/blips/<n>.webp,
    // which spur_core does not ship), so in game every tile showed a broken image (seen in the shop wizard).
    const icons = WP.el('div', 'wp-tiles wp-tiles-small');
    for (const [sprite, label] of GARAGE_BLIPS) {
        const b = WP.el('button', 'wp-tile' + (Number(draft.blipSprite) === sprite ? ' active' : ''));
        b.type = 'button';
        b.dataset.action = 'gwBlip';
        b.dataset.arg = sprite;
        b.appendChild(WP.el('span', 'wp-tile-name', label));
        icons.appendChild(b);
    }
    body.appendChild(icons);
    const other = WP.input({ type: 'number', placeholder: 'another blip number (one RedM does not know shows as a point)',
        value: GARAGE_BLIPS.some((b) => b[0] === Number(draft.blipSprite)) ? '' : draft.blipSprite, inputAction: 'gwBlipNumber' });
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
        b.dataset.action = 'gwColour';
        b.dataset.arg = id;
        const dot = WP.el('span', 'wp-swatch-dot');
        dot.style.background = hex;
        b.appendChild(dot);
        b.appendChild(WP.el('span', null, label));
        swatches.appendChild(b);
    }
    body.appendChild(swatches);
}

// ---- step: create ----

function stepReview(body) {
    const changed = draft.editing ? changedParts(draft) : null;
    summaryRows(body, draft, (key) => ({ action: 'gwJump', arg: key, actionLabel: 'Change' }), changed);
    const last = !draft.editing
        ? hint(body, 'Create makes the garage and all its bays at once. Press it at the car park: the server '
            + 'refuses bays that are far from you (Config.GarageWizardReach), so a garage is made from where it is.')
        : changed.size
        ? hint(body, 'Save changes writes what changed, at once. A moved marker or bay must be near you '
            + '(Config.GarageWizardReach): save at the car park. A new name or icon saves from anywhere.')
        : hint(body, 'Nothing has changed yet: Change any part above.');
    last.classList.add('wp-apart');
}

// ---- leaving a step, and creating ----

function canLeave(from) {
    const d = draft;
    if (!d) return 'There is no garage being set up';
    if (from === 'name') {
        if (!d.name.trim()) return 'Give the garage a name';
        const key = d.key.trim();
        if (!key) return 'Give it a key';
        if (!/^[A-Za-z0-9_-]+$/.test(key)) return 'A key is letters, numbers, _ and - only';
        if (garages[key] && key !== d.editing) return 'A garage with the key "' + key + '" exists already';
        return true;
    }
    if (from === 'bays') return d.bays.length ? true : 'Set out at least one bay: bays are the only way into a garage';
    if (from === 'map') {
        const n = Number(d.blipSprite);
        if (!(Number.isInteger(n) && n >= 1 && n <= 999)) return 'An icon number is 1 to 999';
        return true;
    }
    return true;
}

/** What a changed garage's Save sends: what changed only (the server leaves the rest as it is). Its bays go whole,
 *  with their ids: the server adds, moves and takes away to match. */
function savePayload(d, changed) {
    const payload = { key: d.editing };
    if (changed.has('name')) payload.name = d.name.trim();
    if (changed.has('map')) {
        const m = markerOf(d);
        payload.marker = { x: m.x, y: m.y, z: m.z, heading: m.heading || 0 };
        payload.blipSprite = Number(d.blipSprite);
        payload.blipColor = Number(d.blipColor);
    }
    if (changed.has('bays')) {
        payload.bays = d.bays.map((b) => (b.id !== undefined
            ? { x: b.x, y: b.y, z: b.z, heading: b.heading, id: b.id } : { x: b.x, y: b.y, z: b.z, heading: b.heading }));
    }
    return payload;
}

function finish() {
    const d = draft;
    if (!d || d.saving) return;
    const changed = d.editing ? changedParts(d) : null;
    if (changed && !changed.size) {
        wiz.say('Nothing has changed', 'err');
        return;
    }
    for (const s of stepsFor(!!d.editing)) {
        if (s.key === 'review') continue;
        const why = canLeave(s.key);
        if (why !== true) { wiz.setStatus(s.key, 'error'); wiz.say(why, 'err'); return; }
    }
    let call, payload;
    if (d.editing) {
        call = 'gwSave';
        payload = savePayload(d, changed);
    } else {
        const m = markerOf(d);
        call = 'gwCreate';
        payload = {
            key: d.key.trim(), name: d.name.trim(),
            x: m.x, y: m.y, z: m.z, heading: m.heading || 0,
            blipSprite: Number(d.blipSprite), blipColor: Number(d.blipColor),
            bays: d.bays.map((b) => ({ x: b.x, y: b.y, z: b.z, heading: b.heading })),
        };
    }
    d.saving = true;
    wiz.say(d.editing ? 'Saving…' : 'Creating…');
    nuiCallback(call, payload).then((res) => {
        if (draft !== d) return;
        d.saving = false;
        if (!res || res.ok !== true) {   // {} is a call that never reached the server: not a success
            wiz.say((res && res.why) || (d.editing ? 'The garage was not saved' : 'The garage was not made'), 'err');
            return;
        }
        const key = d.editing || res.key;
        const lost = res.failed ? '  ·  ' + plural(res.failed, d.editing ? 'bay change' : 'bay') + ' did not save' : '';
        WP.result((d.editing ? 'Garage saved: ' : 'Garage created: ') + key + lost, res.failed ? 'err' : 'ok');
        closeWizard();
        if (garages[key]) selectGarage(key); else pendingSelect = key;
    });
}

// ---- section ----

WhipPanel.registerSection({
    id: 'garages',
    group: 'vehicles',
    label: 'Garages',
    order: 20,

    render(root) {
        els = {};

        // ---- the wizard, in the list's place while a garage is set up. First in the section, as the shop
        // wizard's is (the shell's '/' takes the first search). ----
        els.wizView = WP.el('div', 'wp-section-solo wp-section-wide');
        els.wizView.style.display = 'none';
        const head = WP.el('div', 'wp-actions-row wp-head-row');
        els.wizTitle = WP.el('div', 'wp-pane-title', 'New garage');
        head.appendChild(els.wizTitle);
        head.appendChild(WP.el('span', 'wp-actions-split'));
        els.wizDiscard = WP.btn('Discard', 'gwDiscard', 'ghost');
        head.appendChild(els.wizDiscard);
        els.wizView.appendChild(head);
        els.wizBody = WP.el('div', 'wp-view');
        els.wizView.appendChild(els.wizBody);
        root.appendChild(els.wizView);

        els.listView = WP.el('div', 'wp-view');
        root.appendChild(els.listView);
        els.listView.appendChild(WP.toolbar({
            left: [WP.btn('+ New Garage', 'gwNew')],
            search: { inputAction: 'gmSearch', placeholder: 'Search garages…' },
        }));

        const split = WP.el('div', 'wp-split');

        const listCol = WP.el('div', 'wp-list-col');
        els.count = WP.el('div', 'wp-list-count', '');
        listCol.appendChild(els.count);
        els.list = WP.el('div', 'wp-list');
        listCol.appendChild(els.list);
        split.appendChild(listCol);

        const detail = WP.el('div', 'wp-detail');
        // With no garage picked: the way to the wizard, in the form's place.
        els.intro = WP.el('div');
        els.intro.appendChild(WP.el('div', 'wp-pane-title', 'Garages'));
        els.intro.appendChild(WP.el('div', 'wp-hint',
            'Pick a garage to see it and change it, or set a new one up: the wizard walks you through its name, '
            + 'setting its bays out in the world, and its map icon.'));
        const go = WP.el('div', 'wp-actions-row');
        go.appendChild(WP.btn('Set up a new garage', 'gwNew', 'primary'));
        els.intro.appendChild(go);
        detail.appendChild(els.intro);
        // A picked garage's page: its summary (renderDetail), then its bays and cars.
        els.form = WP.el('div');
        detail.appendChild(els.form);
        els.formTitle = WP.el('div', 'wp-pane-title', 'Garage');
        els.form.appendChild(els.formTitle);
        els.summary = WP.el('div');
        els.form.appendChild(els.summary);

        // ---- Parking Bays ----
        //
        // A GROUP LIKE EVERY OTHER SETTING, not a pane bolted under the split.
        //
        // OPEN BY DEFAULT and first after identity, because bays are now the thing you actually
        // come here to manage. Everything below is set once and left alone.
        els.spotGroup = WP.group('bays', 'Parking Bays', true);
        els.spotTitle = els.spotGroup.root.querySelector('.wp-group-label');
        // ONE WAY TO CHANGE THEM: Change on the Bays row, the wizard's Bays step and the one bay tool.
        els.spotGroup.body.appendChild(WP.el('div', 'wp-hint',
            'The spaces players use to reach this garage. Cars come out in the bay the player is '
            + 'standing in: a car park is one garage with many bays, not many garages. Change on Bays '
            + 'sets them out in the world: add, move and take them away.'));
        els.spotList = WP.el('div');
        els.spotGroup.body.appendChild(els.spotList);
        els.form.appendChild(els.spotGroup.root);

        // ---- Vehicles ----
        //
        // Closed by default: it is a read-out of what happens to be parked here, not something you
        // came to change. The move-to-garage select is the one action, and it keeps.
        els.vehGroup = WP.group('vehicles', 'Vehicles in this Garage', false);
        els.vehTitle = els.vehGroup.root.querySelector('.wp-group-label');
        els.vehList = WP.el('div');
        els.vehGroup.body.appendChild(els.vehList);
        els.form.appendChild(els.vehGroup.root);

        split.appendChild(detail);
        els.listView.appendChild(split);

        noGarage();
        built = true;
        // The panel is built again each time it opens: a garage half set up comes back where it was.
        if (draft) buildWizard(wizAt);
        showView();
    },

    onEnter() {
        seeded = false;   // next 'all' is the enter snapshot — it may reseed the form
    },

    onData(kind, payload) {
        if (!built) return;
        if (kind === 'counts') {
            // Bays changed somewhere. Only the list cares — the detail pane gets its own 'spots'
            // payload — so this repaints that and nothing else.
            spotCounts = payload.spotCounts || {};
            renderList();
            return;
        }
        if (kind === 'all') {
            normalize(payload.garages);
            vehicleCounts = payload.vehicleCounts || {};
            spotCounts = payload.spotCounts || {};
            if (!seeded) {
                seeded = true;
                noGarage();
                return;
            }
            // Idempotent: keep the page that is open, refresh the list and counts, back out only if its
            // garage vanished.
            renderList();
            // A garage the wizard just made: opened once the list has it.
            if (pendingSelect && garages[pendingSelect] && !wizardOpen()) {
                const key = pendingSelect;
                pendingSelect = null;
                selectGarage(key);
            } else if (editingKey && !garages[editingKey]) {
                noGarage();
            } else if (editingKey) {
                renderDetail();     // a Save just landed: its name, marker or icon
                renderVehicles();   // move-target options may have changed
            }
        } else if (kind === 'vehicles') {
            if (payload.garageKey !== editingKey) return;
            vehicles = payload.vehicles || [];
            renderVehicles();
        } else if (kind === 'spots') {
            // Guarded the same way the vehicle payload is: this arrives unprompted whenever a bay
            // is created or deleted anywhere, and a payload for a garage nobody is looking at would
            // replace the list under the admin's cursor.
            if (payload.garageKey !== editingKey) return;
            spots = payload.spots || [];
            spotsFor = editingKey;
            renderSpots();
            renderDetail();
        } else if (kind === 'wizBays' && draft) {
            // The wizard's Bays, as set out in the world (gwPlaceBays, tools/panel_sections/garages.lua): a saved
            // garage's with their spotIds.
            draft.bays = (payload.bays || []).filter((b) => b && Number.isFinite(Number(b.x))).map((b) => {
                const bay = { x: Number(b.x), y: Number(b.y), z: Number(b.z), heading: Number(b.heading) || 0 };
                if (b.id !== undefined && b.id !== null) bay.id = Number(b.id);
                return bay;
            });
            bayPicks.clear();
            if (wiz && wiz.current() === 'bays') redrawStep();
        }
    },

    onEscape() {
        if (wizardOpen()) {
            // Changing a garage: back to the summary of what changed first, then out.
            if (draft.editing && wiz && wiz.current() !== 'review') { wiz.go('review'); return true; }
            // Setting one up: a step back at a time; on the first, Escape offers to throw it away.
            if (draft.editing || !(wiz && wiz.escape())) discardWizard();
            return true;
        }
        // Drill-down stage: an open garage closes before the panel does.
        if (editingKey !== null) { noGarage(); return true; }
        return false;
    },

    actions: {
        // ---- the wizard ----
        gwNew: () => openWizard(),
        gwDiscard: () => discardWizard(),
        gwJump: (el) => { if (wiz) wiz.jump(el.dataset.arg); },
        gwName: (el) => {
            if (!draft) return;
            draft.name = el.value;
            // The key follows the name until it is typed itself.
            if (!draft.keyEdited) {
                draft.key = keyFromName(el.value);
                if (els.gwKey) els.gwKey.value = draft.key;
            }
            renderWizHead();
        },
        gwKey: (el) => {
            if (!draft) return;
            draft.key = el.value.trim();
            draft.keyEdited = draft.key !== '';
            if (!draft.keyEdited) {
                draft.key = keyFromName(draft.name);
                el.value = draft.key;
            }
        },
        gwBays: () => {
            if (!draft) return;
            nuiCallback('gwPlaceBays', { name: draft.name.trim(), bays: draft.bays }).then((res) => {
                if (res && res.ok === false && wiz) wiz.say(res.why || 'The bay tool could not open', 'err');
            });
        },
        gwBaysClear: async () => {
            if (!draft || !draft.bays.length) return;
            const ok = await WP.confirm({ title: 'Take every bay away?', body: 'The ' + plural(draft.bays.length, 'bay')
                + ' set out so far go. Nothing is saved yet, so nothing in the world changes.', confirmLabel: 'Take them away', danger: true });
            if (!ok || !draft) return;
            draft.bays = [];
            bayPicks.clear();
            redrawStep();
        },
        // The picked bays, from the bar (bayPicks). Nothing is saved until the wizard's Save.
        gwBaysRemove: () => {
            if (!draft) return;
            const drop = new Set(bayPicks.keys().map(Number));
            draft.bays = draft.bays.filter((_, i) => !drop.has(i));
            bayPicks.clear();
            redrawStep();
        },
        gwBayTeleport: (el) => {
            const b = draft && draft.bays[Number(el.dataset.arg)];
            if (b) nuiCallback('gwTeleport', b);
        },
        gwMarkerHere: () => {
            nuiCallback('gmGetPlayerPos', {}).then((pos) => {
                if (!draft || !pos || pos.x === undefined) return;
                draft.marker = { x: pos.x, y: pos.y, z: pos.z, heading: pos.h || 0 };
                draft.markerSet = true;
                draft.markerSaved = false;
                redrawStep();
            });
        },
        gwMarkerMiddle: () => { if (draft) { draft.markerSet = false; draft.marker = null; draft.markerSaved = false; redrawStep(); } },
        gwMarkerSaved: () => {
            const was = draft && draft.original && draft.original.marker;
            if (!was) return;
            draft.marker = { x: was.x, y: was.y, z: was.z, heading: was.heading || 0 };
            draft.markerSet = true;
            draft.markerSaved = true;
            redrawStep();
        },
        gwBlip: (el) => { if (draft) { draft.blipSprite = Number(el.dataset.arg); redrawStep(); } },
        gwBlipNumber: (el) => {
            if (!draft) return;
            draft.blipSprite = el.value;
            const n = Number(el.value);
            for (const t of el.closest('.wp-step-body').querySelectorAll('.wp-tiles .wp-tile')) {
                t.classList.toggle('active', Number(t.dataset.arg) === n);
            }
        },
        gwColour: (el) => { if (draft) { draft.blipColor = Number(el.dataset.arg); redrawStep(); } },

        gmSearch: (el) => { search = el.value.toLowerCase(); renderList(); },
        gmNew: () => openWizard(),
        gmSelect: (el) => selectGarage(el.dataset.id),
        // Change (a row's, or Change everything): the wizard, filled in with this garage, on that part.
        gmEdit: (el) => { if (editingKey) openEdit(editingKey, el.dataset.arg); },
        gmDelete: async () => {
            if (!editingKey) return;
            const key = editingKey;
            const g = garages[key];
            const name = g && g.name ? g.name : key;
            const inside = vehicleCounts[key] || 0;
            if (inside === 0) {
                const ok = await WP.confirm({
                    title: 'Delete garage?',
                    body: `"${name}" (${key}) will be removed.`,
                    confirmLabel: 'Delete',
                    danger: true,
                });
                if (!ok) return;
                nuiCallback('gmDeleteGarage', { key });
                delete garages[key];
                delete vehicleCounts[key];
                noGarage();
                return;
            }

            // ITS CARS GO WHERE THE ADMIN SAYS, chosen before it can go: one garage they all move to. Any public
            // garage but this one; the server refuses the delete without it.
            const targets = Object.keys(garages).filter((k) => k !== key && !garages[k].private)
                .sort((a, b) => String(garages[a].name || a).localeCompare(String(garages[b].name || b)));
            const cars = plural(inside, 'car');
            if (targets.length === 0) {
                await WP.confirm({
                    title: 'Nowhere for its cars to go',
                    body: `"${name}" has ${cars} in it, and there is no other public garage to move them to. `
                        + 'Set another garage up first, then delete this one.',
                    confirmLabel: 'OK',
                });
                return;
            }
            const sel = WP.select([{ value: '', label: 'Choose a garage…' }]
                .concat(targets.map((k) => ({ value: k, label: (garages[k].name || k) + '  (' + k + ')' }))));
            const field = WP.field('Move them all to', sel);
            const ok = await WP.confirm({
                title: 'Delete garage?',
                body: `"${name}" (${key}) has ${cars} in it. Choose the garage they all move to first: `
                    + 'their owners are told where their car went.',
                content: field,
                canConfirm: () => sel.value !== '',
                confirmLabel: 'Move them and delete',
                danger: true,
            });
            if (!ok || !sel.value) return;
            // Not removed here: the server may refuse (its cars' garage gone meanwhile), and its list comes back
            // without this garage once it is deleted (onData 'all' backs out of a garage that vanished).
            nuiCallback('gmDeleteGarage', { key, moveTo: sel.value });
        },
        gmTeleport: () => {
            if (!editingKey) return;
            nuiCallback('gmTeleportGarage', { garageKey: editingKey });
        },
        // ---- parking spots ----
        //
        // The list only says where they are: the Lua side pushes a fresh 'spots' payload whenever the set
        // changes, for everyone with the section open. They are changed with the wizard (Change on Bays).
        gmSpotTeleport: (el) => {
            nuiCallback('gmTeleportSpot', { spotId: Number(el.dataset.id) });
        },
        gmMoveVehicle: (el) => {
            const toKey = el.value;
            if (!toKey) return;
            // Refresh when the move actually resolves — the old 300ms timer was a
            // guess that lost the race on a slow tick and refreshed too early.
            nuiCallback('gmMoveVehicle', { vehicleId: Number(el.dataset.id), toGarageKey: toKey }).then(() => {
                if (editingKey) nuiCallback('gmGetGarageVehicles', { garageKey: editingKey });
            });
        },
    },
});
