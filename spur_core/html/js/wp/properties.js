// ========================================
// /whip SECTION — Properties
//
// Every home on the server, what is wrong with each, and the changes an admin makes by hand. The
// Lua half is tools/panel_sections/properties.lua; the data and every rule are the server's
// (server/property_admin.lua), and this page only shows them.
//
// TWO VIEWS, ON TABS:
//   Properties         the list (filter, building, search) and one property in detail
//   Templates & packs  the interiors whip knows, their units, and the packs they came from
//
// LIVE: while this section is open the server pushes each changed row, so the list is never
// older than a quarter of a second, and the detail pane re-reads itself when its property changes.
//
// THE WIZARD ("New property", and Edit on one part of a property) takes the Properties tab's place
// while a property is being set up. Its draft is Lua's (tools/property_wizard.lua), which sends a
// summary of it as 'draft' after every change; this page shows that summary and keeps only the
// form fields. Save's answer comes back as 'saved'.
// ========================================

import { WhipPanel, WP } from '../whip-panel.js';
import { nuiCallback } from '../utils.js';
import { fixed } from './format.js';

let rows = [];
let selectedId = null;
let detail = null;
let filter = 'all';
let building = '';
let search = '';
let tab = 'properties';
let formAutolock = false;
// Where a sign placed on a shared unit goes: every property on the unit (the way to set up 36
// identical floors at once), or just this one. Remembered while the page lives.
let signScope = 'unit';
let els = {};
let built = false;

// ---- the wizard's state ----
let draft = null;          // Lua's summary of the property being set up, or null
let wiz = null;            // the WP.stepper
let wizKey = '';           // which draft the stepper was built for: 'new', or 'edit:<part>:<id>'
let noEntranceOk = false;  // the admin was told there is no entrance, and pressed Next anyway
const FORM_DEFAULT = { name: '', label: '', building: '', price: 0, maxObjects: 150,
                       autolock: false, autolockDelay: 10, owner: '' };
let form = { ...FORM_DEFAULT };
let editScope = 'unit';

// ---- Register here's state ----
let reg = null;            // Lua's summary of the interior being registered (tools/property_scale.lua)
let regTpl = null;         // which of its templates
let regForm = { building: '', namePattern: '{b} {u}', labelPattern: '', floor: '', start: 1, skip: {} };
let exportFor = null;      // the template the Export box is open for, on the Templates tab

// ---- what a row says about itself ----

function needsAttention(r) {
    return r.status === 'attention' || !!r.packIssue || r.shapes === 0 || r.unresolved;
}

function matches(r) {
    if (building && (r.building || '') !== building) return false;
    if (filter === 'attention' && !needsAttention(r)) return false;
    if (filter === 'unverified' && r.status !== 'unverified') return false;
    if (filter === 'unowned' && r.ownerCharId) return false;
    if (filter === 'owned' && !r.ownerCharId) return false;
    if (filter === 'closed' && r.active) return false;
    if (search) {
        const hay = [r.name, r.label, r.building, r.ownerName, '#' + r.id, r.packId].join(' ').toLowerCase();
        if (!hay.includes(search)) return false;
    }
    return true;
}

function ownerText(r) {
    if (!r.ownerCharId) return 'unowned';
    return (r.ownerName || 'character') + ' #' + r.ownerCharId;
}

// ---- list ----

function renderBuildings() {
    const names = [...new Set(rows.map((r) => r.building).filter(Boolean))].sort();
    const sel = els.buildingSel;
    const was = building;
    sel.innerHTML = '';
    const all = WP.el('option', null, 'Every building');
    all.value = '';
    sel.appendChild(all);
    for (const n of names) {
        const o = WP.el('option', null, n);
        o.value = n;
        sel.appendChild(o);
    }
    building = names.includes(was) ? was : '';
    sel.value = building;
}

function renderList() {
    els.list.innerHTML = '';
    let shown = 0;
    for (const r of rows) {
        if (!matches(r)) continue;
        shown += 1;
        const bits = ['#' + r.id];
        if (r.building) bits.push(r.building);
        if (r.label) bits.push(r.label);
        bits.push(ownerText(r));

        let pill = null, pillClass = '';
        if (needsAttention(r)) { pill = 'check'; pillClass = 'wp-pill-err'; }
        else if (!r.active) { pill = 'closed'; pillClass = 'wp-pill-warn'; }
        else if (r.ownerCharId) { pill = 'owned'; pillClass = 'wp-pill-ok'; }

        const item = WP.listItem({ title: r.name || ('Property #' + r.id), sub: bits.join('  ·  '),
                                   pill, pillClass, id: r.id, action: 'pcSelect' });
        if (needsAttention(r)) item.classList.add('wp-item-warn');
        if (r.id === selectedId) item.classList.add('active');
        els.list.appendChild(item);
    }
    if (shown === 0) {
        els.list.appendChild(WP.empty(rows.length === 0
            ? 'No properties yet. An MLO with a property pack adds its own when it starts; to set one up by hand, stand in it and press New property.'
            : 'Nothing matches'));
    }
    els.count.textContent = shown + ' of ' + rows.length;
}

// ---- detail ----

function loadDetail() {
    if (selectedId === null) { detail = null; renderDetail(); return; }
    const id = selectedId;
    nuiCallback('pcDetail', { id }).then((d) => {
        if (selectedId !== id) return;
        detail = d && d.id ? d : null;
        if (detail) formAutolock = !!(detail.effective && detail.effective.autolock);
        renderDetail();
    });
}

function partsRows(d) {
    const box = WP.el('div');
    const eff = d.effective || {};

    const interiorRow = {
        label: 'Interior', status: 'ok',
        detail: d.archetypeHash === 0 ? 'none: placed in the open world'
            : (d.archetype || ('hash ' + d.archetypeHash)) + (d.templateKey ? '  ·  ' + d.template : ''),
    };
    // Re-bind: stand in the interior as it is now and move the property onto it.
    if (d.archetypeHash !== 0) Object.assign(interiorRow, { action: 'pcEditPart', arg: 'interior', actionLabel: 'Re-bind' });
    box.appendChild(WP.statusRow(interiorRow));

    let spaceStatus = 'ok';
    let spaceText = d.shapes + ' shape' + (d.shapes === 1 ? '' : 's') + '  ·  ' + fixed(d.area, 1) + ' m²';
    if (d.shapes === 0 && d.unresolved) { spaceStatus = 'warn'; spaceText = 'needs the interior\'s rooms (Verify will find them)'; }
    else if (d.shapes === 0) { spaceStatus = 'err'; spaceText = 'none: furniture cannot be placed and nobody is "inside"'; }
    box.appendChild(WP.statusRow({ label: 'Space', status: spaceStatus, detail: spaceText,
                                   action: 'pcEditPart', arg: 'space', actionLabel: 'Edit' }));

    const managed = (d.doorList || []).filter((x) => x.doorId);
    const entrances = (d.doorList || []).filter((x) => x.role === 'entrance');
    let doorStatus = 'ok';
    let doorText = managed.length
        ? managed.map((x) => x.key + ' #' + x.doorId + (x.locked ? ' (locked)' : ' (open)')).join(', ')
        : 'none managed';
    if (d.status === 'attention' && String(d.statusReason || '').includes('door')) { doorStatus = 'err'; doorText = d.statusReason; }
    else if (entrances.length === 0) { doorStatus = 'warn'; doorText = 'no entrance door, so nothing locks'; }
    // Two ways in (a door missed, or one added since): Add doors keeps
    // the ones it has and adds to them; Edit starts fresh, for doors that moved (an MLO update).
    const doorBtns = [WP.btn('Add doors', 'pcAddDoors', 'ghost'), WP.btn('Edit', 'pcEditPart', 'ghost', 'doors')];
    doorBtns.forEach((b) => b.classList.add('wp-btn-sm'));
    box.appendChild(WP.statusRow({ label: 'Doors', status: doorStatus, detail: doorText, control: doorBtns }));

    // ---- the two signs, each with Place ----
    // Where each one's version comes from, in words.
    const layer = (l) => l === 'property' ? 'placed here for this property'
        : l === 'unit' ? 'placed here for every property on this unit'
        : l === 'base' ? (d.packId ? 'where its pack puts it' : 'from its setup') : null;
    if (d.unitUses > 1) {
        box.appendChild(WP.el('div', 'wp-hint',
            'This unit is shared by ' + d.unitUses + ' properties. A sign you place applies to:'));
        const scope = WP.tabs({
            id: 'pc-sign-scope', inline: true, active: signScope,
            tabs: [{ key: 'unit', label: 'All ' + d.unitUses + ' on this unit' }, { key: 'property', label: 'Only this one' }],
            onChange: (k) => { signScope = k; },
        });
        box.appendChild(scope.root);
    }
    // On a sign post or on its own: Sign post puts it up, or moves the one there; the other
    // button places the prompt on its own, which takes a post away.
    const signBtns = [
        d.signPosts ? WP.btn(d.signPost ? 'Move post' : 'Sign post', 'pcPlaceSignPost', 'ghost') : null,
        WP.btn(d.signPost ? 'Prompt only' : d.hasSign ? 'Move' : 'Place', 'pcPlaceSign', 'ghost', 'sign'),
    ].filter(Boolean);
    signBtns.forEach((b) => b.classList.add('wp-btn-sm'));
    box.appendChild(WP.statusRow({
        label: 'Outside sign', status: d.hasSign ? 'ok' : 'warn',
        detail: d.hasSign ? 'for sale' + (d.signPost ? ' on a sign post, ' + d.signPost : '') + '  ·  ' + layer(d.signLayer)
            : 'none: nobody can see it is for sale',
        control: signBtns,
    }));
    box.appendChild(WP.statusRow({
        label: 'Manager', status: d.hasManager ? 'ok' : (d.hasSign ? 'warn' : 'err'),
        detail: d.hasManager ? 'inside, for the owner and keyholders  ·  ' + layer(d.managerLayer)
            : d.hasSign ? 'not placed: the owner uses the outside sign\'s spot until it is'
            : 'not placed: once owned there is nowhere to reach Keys or Furnish',
        action: 'pcPlaceSign', arg: 'manager', actionLabel: d.hasManager ? 'Move' : 'Place',
    }));
    box.appendChild(WP.statusRow({
        label: 'Garage', status: d.bays > 0 ? 'ok' : 'off',
        detail: d.bays > 0 ? d.bays + ' bay' + (d.bays === 1 ? '' : 's') + ', private to the owner and keyholders'
            + (d.garageCars ? '  ·  ' + d.garageCars + ' car' + (d.garageCars === 1 ? '' : 's') + ' in it' : '')
            : 'none',
        action: 'pcEditPart', arg: 'garage', actionLabel: d.bays > 0 ? 'Edit' : 'Add',
    }));
    box.appendChild(WP.statusRow({
        label: 'Settings', status: 'ok',
        detail: 'price ' + (eff.price || 0) + '  ·  up to ' + (eff.maxObjects || 0) + ' pieces'
            + '  ·  auto-lock ' + (eff.autolock ? (eff.autolockDelay || 10) + ' s' : 'off'),
    }));
    const vStatus = d.status === 'ok' ? 'ok' : d.status === 'attention' ? 'err' : 'todo';
    box.appendChild(WP.statusRow({
        label: 'Verify', status: vStatus,
        detail: d.status === 'ok' ? 'checked in the world'
            : d.status === 'attention' ? (d.statusReason || 'needs attention') : 'not checked in the world yet',
    }));
    return box;
}

function packBox(d) {
    const box = WP.el('div');
    if (!d.packIssue) return box;
    box.appendChild(WP.el('div', 'wp-hint', d.packIssue));
    const row = WP.el('div', 'wp-actions-row');
    if (d.packIssue.startsWith('orphaned')) {
        row.appendChild(WP.btn('Keep it here', 'pcAdopt', 'primary'));
    } else if (d.packIssue.startsWith('conflict')) {
        row.appendChild(WP.btn('Keep mine', 'pcKeepMine', 'primary'));
        row.appendChild(WP.btn('Use the pack\'s', 'pcUsePack'));
    }
    box.appendChild(row);
    return box;
}

function ownershipGroup(d) {
    const g = WP.group('pc-owner', 'Owner & keys', true);

    const info = WP.el('div', 'wp-info-grid');
    info.appendChild(WP.el('span', 'wp-info-label', 'Owner'));
    info.appendChild(WP.el('span', 'wp-info-value', ownerText(d)));
    g.body.appendChild(info);

    const ownerRow = WP.el('div', 'wp-cols-2');
    els.ownerInput = WP.input({ placeholder: 'Name or character id', enterAction: 'pcSetOwner' });
    WP.attachCharPicker(els.ownerInput);
    ownerRow.appendChild(WP.field('New owner', els.ownerInput));
    const ownerBtns = WP.el('div', 'wp-actions-row');
    ownerBtns.appendChild(WP.btn('Set owner', 'pcSetOwner', 'primary'));
    if (d.ownerCharId) ownerBtns.appendChild(WP.btn('Make unowned', 'pcClearOwner', 'ghost'));
    ownerRow.appendChild(ownerBtns);
    g.body.appendChild(ownerRow);
    g.body.appendChild(WP.el('div', 'wp-hint',
        'A new owner starts with no keyholders, and the doors lock as it changes hands.'));

    g.body.appendChild(WP.el('div', 'wp-field-label', 'Keyholders'));
    const holders = d.keyholders || [];
    if (holders.length === 0) g.body.appendChild(WP.el('div', 'wp-hint', 'Nobody else has a key.'));
    for (const k of holders) {
        g.body.appendChild(WP.statusRow({ label: k.name, status: 'ok', detail: '#' + k.charId,
                                          action: 'pcRevokeKey', arg: k.charId, actionLabel: 'Take back' }));
    }
    const keyRow = WP.el('div', 'wp-cols-2');
    els.keyInput = WP.input({ placeholder: 'Name or character id', enterAction: 'pcGrantKey' });
    WP.attachCharPicker(els.keyInput);
    keyRow.appendChild(WP.field('Give a key to', els.keyInput));
    const keyBtns = WP.el('div', 'wp-actions-row');
    keyBtns.appendChild(WP.btn('Give key', 'pcGrantKey'));
    keyRow.appendChild(keyBtns);
    g.body.appendChild(keyRow);
    g.body.appendChild(WP.el('div', 'wp-hint',
        'Players hand keys over face to face at the sign; here an admin can give or take one for anybody.'));
    return g.root;
}

function settingsGroup(d) {
    const g = WP.group('pc-settings', 'Name & settings', false);
    const eff = d.effective || {};

    const names = WP.el('div', 'wp-cols-2');
    els.nameInput = WP.input({ value: d.name || '' });
    names.appendChild(WP.field('Name', els.nameInput, true));
    els.labelInput = WP.input({ value: d.label || '', placeholder: 'e.g. 3-1' });
    names.appendChild(WP.field('Unit', els.labelInput));
    els.buildingInput = WP.input({ value: d.building || '', placeholder: 'e.g. Mega Tower B' });
    names.appendChild(WP.field('Building', els.buildingInput));
    g.body.appendChild(names);

    const nums = WP.el('div', 'wp-cols-2');
    els.priceInput = WP.input({ type: 'number', value: eff.price || 0 });
    nums.appendChild(WP.field('Price (shown only)', els.priceInput));
    els.maxInput = WP.input({ type: 'number', value: eff.maxObjects || 0 });
    nums.appendChild(WP.field('Furniture limit', els.maxInput));
    g.body.appendChild(nums);

    const lock = WP.el('div', 'wp-cols-2');
    els.autolockBtn = WP.btn('Door auto-lock: ' + (formAutolock ? 'ON' : 'OFF'), 'pcToggleAutolock',
        formAutolock ? 'primary' : 'ghost');
    lock.appendChild(els.autolockBtn);
    els.delayInput = WP.input({ type: 'number', value: eff.autolockDelay || 10 });
    lock.appendChild(WP.field('Lock after (seconds)', els.delayInput));
    g.body.appendChild(lock);

    const save = WP.el('div', 'wp-actions-row');
    save.appendChild(WP.el('span', 'wp-actions-split'));
    save.appendChild(WP.btn('Save', 'pcSaveSettings', 'primary'));
    g.body.appendChild(save);
    return g.root;
}

// ---- its looks (server/property_themes.lua) ----

/** A theme's chip: walls over trim over floor, as a strip of the room. */
function themeDot(t) {
    const dot = WP.el('span', 'wp-swatch-dot');
    const walls = t.walls || '#6b6b6b', trim = t.trim || walls, floor = t.floor || walls;
    dot.style.background = 'linear-gradient(to bottom, ' + walls + ' 0 56%, ' + trim + ' 56% 68%, ' + floor + ' 68% 100%)';
    return dot;
}

/** The themes as swatches, `chosen` marked; each names its theme to `action`. */
function themeSwatches(themes, chosen, action) {
    const box = WP.el('div', 'wp-swatches');
    for (const t of themes || []) {
        const b = WP.el('button', 'wp-swatch' + (t.id === chosen ? ' active' : ''));
        b.type = 'button';
        b.dataset.action = action;
        b.dataset.arg = t.id;
        b.appendChild(themeDot(t));
        b.appendChild(WP.el('span', null, t.name));
        box.appendChild(b);
    }
    return box;
}

function themesGroup(d) {
    const g = WP.group('pc-themes', 'Theme', false);
    const th = d.themes;
    g.body.appendChild(WP.el('div', 'wp-hint', th.label + ' gives this home ' + th.themes.length
        + ' looks (it is their ' + th.home + '). The owner changes it at the sign, beside Furnish; picking one here changes it now.'));
    g.body.appendChild(themeSwatches(th.themes, th.current, 'pcSetTheme'));
    return g.root;
}

function furnitureGroup(d) {
    const g = WP.group('pc-furniture', 'Furniture', false);
    g.body.appendChild(WP.el('div', 'wp-hint', d.objects + ' of ' + (d.maxObjects || 0) + ' pieces placed. '
        + 'Manage furniture takes you inside and opens the furnisher, as the owner has it.'));
    const row = WP.el('div', 'wp-actions-row');
    row.appendChild(WP.btn('Manage furniture', 'pcManageFurniture', 'primary'));
    row.appendChild(WP.el('span', 'wp-actions-split'));
    if (d.objects > 0) row.appendChild(WP.btn('Clear all furniture', 'pcClearFurniture', 'danger'));
    g.body.appendChild(row);
    return g.root;
}

/** Its stashes: the furniture that holds things. Inspect storage opens one from here, as the
 *  Container Manager does (past its lock and the distance). */
function storageGroup(d) {
    const list = d.stashes || [];
    const g = WP.group('pc-storage', 'Storage' + (list.length ? ' (' + list.length + ')' : ''), false);
    if (!list.length) {
        g.body.appendChild(WP.empty('No storage furniture placed'));
        return g.root;
    }
    for (const s of list) {
        const bits = [s.slots + ' slots', fixed(s.maxWeight, 0) + ' kg'];
        if (typeof s.used === 'number') bits.push(s.used === 0 ? 'empty' : s.used + ' in use');
        g.body.appendChild(WP.statusRow({
            label: s.name || 'Stash', status: s.used ? 'ok' : 'off', detail: bits.join('  ·  '),
            action: 'pcInspectStash', arg: String(s.containerId), actionLabel: 'Inspect storage',
        }));
    }
    return g.root;
}

function renderDetail() {
    if (!built) return;
    const body = els.detailBody;
    body.innerHTML = '';
    if (!detail) {
        els.detailTitle.textContent = selectedId === null ? 'Select a property' : 'Loading…';
        if (selectedId === null) body.appendChild(WP.empty('Pick a property from the list'));
        return;
    }
    const d = detail;
    els.detailTitle.textContent = (d.name || 'Property') + '  #' + d.id;

    const actions = WP.el('div', 'wp-actions-row');
    actions.appendChild(WP.btn('Go to sign', 'pcGoEntry'));
    actions.appendChild(WP.btn('Go inside', 'pcGoInside', 'primary'));
    actions.appendChild(WP.btn('Show space', 'pcShowSpace'));
    actions.appendChild(WP.btn('Verify now', 'pcVerifyOne'));
    actions.appendChild(WP.el('span', 'wp-actions-split'));
    actions.appendChild(WP.btn('Delete', 'pcDelete', 'danger'));
    body.appendChild(actions);

    body.appendChild(packBox(d));

    const info = WP.el('div', 'wp-info-grid');
    const add = (label, value) => {
        info.appendChild(WP.el('span', 'wp-info-label', label));
        info.appendChild(WP.el('span', 'wp-info-value', value));
    };
    add('Source', d.packId
        ? 'Pack ' + d.packId + (d.pack && d.pack.resource ? ' (' + d.pack.resource + ', ' + (d.pack.running ? 'running' : 'NOT running') + ')' : '')
        : 'Set up here');
    add('Unit', (d.template || '?') + '  ·  ' + (d.unit || d.unitKey));
    if (d.place) add('Placement', 'on the map below  ·  turned ' + fixed(d.place.yaw, 1) + '°');
    if ((d.overrides || []).length) add('Changed here', d.overrides.join(', '));
    if ((d.overlay || []).length) add('Unit changed', d.overlay.join(', ') + ' (for every property using it)');
    body.appendChild(info);
    if (d.place) body.appendChild(WP.place({ x: d.place.x, y: d.place.y, name: d.name || 'The property' }));

    body.appendChild(partsRows(d));
    body.appendChild(ownershipGroup(d));
    body.appendChild(settingsGroup(d));
    if (d.themes && d.themes.themes && d.themes.themes.length) body.appendChild(themesGroup(d));
    body.appendChild(furnitureGroup(d));
    body.appendChild(storageGroup(d));
}

// ---- templates & packs ----

function renderTemplates(data) {
    const root = els.tplBody;
    root.innerHTML = '';
    if (!data) { root.appendChild(WP.empty('Could not read the templates')); return; }

    const packs = WP.group('pc-packs', 'Packs', true);
    const list = (data.packs && data.packs.packs) || [];
    if (list.length === 0) packs.body.appendChild(WP.el('div', 'wp-hint',
        'No MLO has sent a property pack. A pack is one file an MLO ships (see spur_core/docs/properties.md).'));
    for (const p of list) {
        packs.body.appendChild(WP.statusRow({
            label: p.label || p.id, status: p.running ? 'ok' : 'warn',
            detail: p.id + '  ·  v' + (p.version || '?') + '  ·  ' + p.resource + (p.running ? '' : ' (not running, so its homes are closed)'),
        }));
    }
    for (const pr of (data.packs && data.packs.problems) || []) {
        // "resource:file" — the resource is the name an admin knows it by; the file and the
        // reason are the detail.
        const at = String(pr.file || '').indexOf(':');
        const res = at > 0 ? pr.file.slice(0, at) : pr.file;
        const file = at > 0 ? pr.file.slice(at + 1) : '';
        packs.body.appendChild(WP.statusRow({ label: res, status: 'err',
                                              detail: 'REFUSED ' + file + ': ' + pr.error }));
    }
    root.appendChild(packs.root);

    // Export pack, for the template picked below: its file, and the text to copy.
    if (exportFor) root.appendChild(exportBox(data));

    const tpls = WP.group('pc-templates', 'Templates', true);
    if ((data.templates || []).length === 0) tpls.body.appendChild(WP.el('div', 'wp-hint', 'None yet.'));
    for (const t of data.templates || []) {
        const src = t.source && t.source.startsWith('pack:') ? 'pack ' + t.source.slice(5) : 'set up here';
        const row = {
            label: t.label || t.templateKey, status: t.units.some((u) => u.conflict) ? 'err' : 'ok',
            detail: (t.archetype || (t.archetypeHash ? 'hash ' + t.archetypeHash : 'no interior')) + '  ·  ' + src
                + '  ·  ' + t.units.length + ' unit' + (t.units.length === 1 ? '' : 's')
                + '  ·  ' + t.properties + ' propert' + (t.properties === 1 ? 'y' : 'ies')
                + (t.rooms ? '  ·  ' + t.rooms + ' rooms known' : ''),
        };
        // An interior can ship as a pack; a house in the open world has nothing to ship with.
        if (t.archetypeHash) Object.assign(row, { action: 'pcExportPick', arg: t.templateId, actionLabel: 'Export' });
        tpls.body.appendChild(WP.statusRow(row));
        for (const u of t.units) {
            const row = WP.statusRow({
                sub: true,
                label: u.label || u.key, status: u.conflict ? 'err' : u.edited ? 'warn' : 'todo',
                detail: u.properties + ' propert' + (u.properties === 1 ? 'y' : 'ies')
                    + (u.conflict ? '  ·  the pack and an admin both changed it' : u.edited ? '  ·  changed here' : ''),
            });
            tpls.body.appendChild(row);
        }
    }
    root.appendChild(tpls.root);
}

function wizardOpen() { return !!(draft && draft.active); }
function registerOpen() { return !!(reg && reg.active); }

/** The Properties tab shows the list; or the wizard while a property is being set up; or
 *  Register here while that is open. */
function showView() {
    if (!built) return;
    const w = wizardOpen();
    const r = !w && registerOpen();
    els.propsView.style.display = tab === 'properties' && !w && !r ? '' : 'none';
    els.wizView.style.display = tab === 'properties' && w ? '' : 'none';
    els.regView.style.display = tab === 'properties' && r ? '' : 'none';
    els.tplView.style.display = tab === 'templates' ? '' : 'none';
}

// ---- names from a pattern ----
//
// THE SAME RULES AS tools/property_scale.lua's PropertyScale.name, which makes the names for real:
//   {b} building  {u} unit label  {k} unit key  {f} floor  {n} number  {nn} number, two digits
// The number is the start number plus the unit's place in its template, from 0.

function patternName(pattern, f, unit, index) {
    const startNum = Number(f.start);
    const n = Math.floor(f.start === '' || !Number.isFinite(startNum) ? 1 : startNum) + index;
    const floorNum = Number(f.floor);
    const values = {
        b: f.building || '', u: unit.label || unit.key || '', k: unit.key || '',
        f: f.floor !== '' && Number.isFinite(floorNum) ? String(Math.floor(floorNum)) : '',
        n: String(n), nn: String(n).padStart(2, '0'),
    };
    return String(pattern || '').replace(/\{([A-Za-z]+)\}/g, (m, tok) => (tok in values ? values[tok] : m))
        .replace(/\s+/g, ' ').trim();
}

function regNames(t) {
    return (t.units || []).map((u, i) => ({
        unit: u,
        name: patternName(regForm.namePattern || '{b} {u}', regForm, u, i) || u.label || u.key,
        label: regForm.labelPattern ? patternName(regForm.labelPattern, regForm, u, i) : '',
    }));
}

/** What the page sends: the form, with the numbers as numbers. */
function regFormPayload() {
    return {
        building: regForm.building.trim(), namePattern: regForm.namePattern, labelPattern: regForm.labelPattern,
        floor: regForm.floor === '' ? null : Number(regForm.floor), start: Number(regForm.start) || 1,
        skip: regForm.skip,
    };
}

function setFilter(key) {
    filter = key;
    if (els.filterSel) els.filterSel.value = key;
    renderList();
}

/** The properties the list is showing right now: what Verify… and Quick check work through. */
function shownIds() {
    return rows.filter(matches).map((r) => r.id);
}

function currentRegTemplate() {
    const list = (reg && reg.templates) || [];
    return list.find((t) => t.templateId === regTpl) || list[0] || null;
}

// ---- Register here ----

function renderRegister() {
    if (!built) return;
    const body = els.regBody;
    body.innerHTML = '';
    if (!reg) return;

    if (!reg.read) {
        body.appendChild(WP.statusRow({ label: 'Interior', status: 'err', detail: reg.why || 'Not read yet' }));
        body.appendChild(WP.el('div', 'wp-hint',
            'Stand inside a copy of an interior whip already knows (one with a template) and press Read again.'));
        buttons(body, [['Read again', 'prRead', 'primary']]);
        return;
    }
    if (!(reg.templates || []).length) {
        body.appendChild(WP.statusRow({ label: 'Interior', status: 'warn',
            detail: 'hash ' + reg.hash + ': whip has no template for this interior yet' }));
        body.appendChild(WP.el('div', 'wp-hint',
            'Set one of its homes up with New property first. Every other copy of the interior can then be registered '
            + 'from here in one go.'));
        buttons(body, [['Read again', 'prRead']]);
        return;
    }

    const list = reg.templates;
    if (!list.some((t) => t.templateId === regTpl)) regTpl = list[0].templateId;
    if (list.length > 1) {
        const tabs = WP.tabs({
            id: 'pc-reg-tpl', inline: true, active: String(regTpl),
            tabs: list.map((t) => ({ key: String(t.templateId), label: t.label || ('#' + t.templateId) })),
            onChange: (k) => { regTpl = Number(k); renderRegUnits(); },
        });
        body.appendChild(tabs.root);
    }
    info(body, [['Interior', 'hash ' + reg.hash], ['Placement', placeText(reg.place)]]);

    const row1 = WP.el('div', 'wp-cols-2');
    const input = (field, opts) => {
        const i = WP.input({ ...opts, value: regForm[field], inputAction: 'prForm' });
        i.dataset.field = field;
        return i;
    };
    row1.appendChild(WP.field('Building', input('building', { placeholder: 'e.g. Mega Tower B' })));
    row1.appendChild(WP.field('Floor', input('floor', { type: 'number', placeholder: 'optional' })));
    body.appendChild(row1);
    const row2 = WP.el('div', 'wp-cols-2');
    row2.appendChild(WP.field('Name', input('namePattern', { placeholder: '{b} {u}' })));
    row2.appendChild(WP.field('Unit label', input('labelPattern', { placeholder: 'e.g. {f}{nn} (optional)' })));
    body.appendChild(row2);
    const row3 = WP.el('div', 'wp-cols-2');
    row3.appendChild(WP.field('Numbers start at', input('start', { type: 'number' })));
    body.appendChild(row3);
    body.appendChild(WP.el('div', 'wp-hint',
        'In a name: {b} building, {u} the unit\'s label, {f} floor, {n} a number, {nn} the number with two digits. '
        + 'The number counts up from the start through the interior\'s units: "B{f}{nn}" on floor 8 from 5 is B805, B806…'));

    els.regUnits = WP.el('div');
    body.appendChild(els.regUnits);
    renderRegUnits();
}

function renderRegUnits() {
    const box = els.regUnits;
    if (!box) return;
    box.innerHTML = '';
    const t = currentRegTemplate();
    if (!t) return;
    const names = regNames(t);
    let count = 0;
    for (const e of names) {
        const u = e.unit;
        const skipped = !!regForm.skip[u.key];
        let status = 'todo', detail, action = null, actionLabel = null;
        if (u.registered) {
            status = 'ok';
            detail = 'already ' + u.registered.name + ' #' + u.registered.id;
        } else if (u.clash) {
            status = 'err';
            detail = 'overlaps ' + u.clash;
        } else if (skipped) {
            status = 'off';
            detail = 'skipped';
            action = 'prSkip'; actionLabel = 'Include';
        } else {
            count += 1;
            detail = e.name + (e.label ? '  ·  ' + e.label : '') + (u.unresolved ? '  ·  its space needs Verify' : '');
            action = 'prSkip'; actionLabel = 'Skip';
        }
        box.appendChild(WP.statusRow({ label: u.label || u.key, status, detail,
                                       action: action || undefined, arg: u.key, actionLabel }));
    }
    buttons(box, [
        ['Register ' + count + (count === 1 ? ' unit' : ' units'), 'prRegister', 'primary', undefined, count === 0],
        ['Show units', 'prShow'],
        ['Stamp mode', 'prStamp'],
    ]);
    box.appendChild(WP.el('div', 'wp-hint',
        'Stamp mode flies you through the building: every copy of an interior with a template lights up, E registers it '
        + 'with these names, PgUp and PgDn change the floor, Tab and Q the numbers.'));
}

function switchTab(key) {
    tab = key;
    showView();
    if (key === 'templates') loadTemplates();
}

let tplData = null;

function loadTemplates() {
    els.tplBody.innerHTML = '';
    els.tplBody.appendChild(WP.empty('Reading…'));
    nuiCallback('pcTemplates', {}).then((d) => { tplData = d || null; renderTemplates(tplData); });
}

// ---- Export pack ----

function exportBox(data) {
    const interiors = (data.templates || []).filter((x) => x.archetypeHash);
    exportFor.templateIds = exportFor.templateIds.filter((id) => interiors.some((x) => x.templateId === id));
    const chosen = interiors.filter((x) => exportFor.templateIds.includes(x.templateId));
    const g = WP.group('pc-export', 'Export a pack', true);
    if (chosen.length === 0) { g.body.appendChild(WP.el('div', 'wp-hint', 'That template is gone.')); return g.root; }

    g.body.appendChild(WP.el('div', 'wp-hint',
        'Writes the file an MLO ships (spur_core/docs/properties.md): put it in the MLO\'s resource as whip_properties.lua '
        + 'and every server that ensures it gets these homes. One MLO is one pack: add every interior it has.'));
    const row = WP.el('div', 'wp-cols-2');
    els.exportId = WP.input({ value: exportFor.packId || '', placeholder: 'pack id, e.g. yourname.mlo (optional)' });
    row.appendChild(WP.field('Pack id', els.exportId));
    els.exportLabel = WP.input({ value: exportFor.label || '', placeholder: 'e.g. Mega Apartments (optional)' });
    row.appendChild(WP.field('Pack name', els.exportLabel));
    g.body.appendChild(row);

    g.body.appendChild(WP.el('div', 'wp-field-label', 'Interiors in this pack'));
    for (const t of interiors) {
        const inPack = exportFor.templateIds.includes(t.templateId);
        g.body.appendChild(WP.statusRow({
            label: t.label || t.templateKey, status: inPack ? 'ok' : 'off',
            detail: (t.archetype || 'hash ' + t.archetypeHash) + '  ·  ' + t.units.length + ' unit'
                + (t.units.length === 1 ? '' : 's') + '  ·  ' + t.properties + ' propert' + (t.properties === 1 ? 'y' : 'ies'),
            action: inPack && chosen.length === 1 ? undefined : 'pcExportToggle', arg: t.templateId,
            actionLabel: inPack ? 'Remove' : 'Add',
        }));
    }
    const placed = chosen.reduce((n, t) => n + t.properties, 0);
    buttons(g.body, [
        [(exportFor.placements ? 'With' : 'Without') + ' their ' + placed + ' placement' + (placed === 1 ? '' : 's'),
            'pcExportPlacements', exportFor.placements ? 'primary' : 'ghost'],
        ['Export', 'pcExportRun', 'primary'],
        ['Close', 'pcExportClose', 'ghost'],
    ]);

    const res = exportFor.result;
    if (res && res.ok === false) {
        g.body.appendChild(WP.statusRow({ label: 'Not exported', status: 'err', detail: res.why || 'It did not work' }));
    } else if (res) {
        g.body.appendChild(WP.statusRow({ label: 'Written', status: res.path ? 'ok' : 'warn',
            detail: res.path ? res.path : 'could not be saved to disk: copy it from below',
        }));
        g.body.appendChild(WP.statusRow({ label: 'In it', status: 'ok',
            detail: res.templates + ' interior' + (res.templates === 1 ? '' : 's') + ', '
                + res.units + ' unit' + (res.units === 1 ? '' : 's') + ', ' + res.properties + ' propert'
                + (res.properties === 1 ? 'y' : 'ies') + '  ·  pack id ' + res.id }));
        for (const w of res.warnings || []) g.body.appendChild(WP.statusRow({ label: 'Left out', status: 'warn', detail: w }));
        const text = WP.el('textarea', 'wp-input wp-export-text');
        text.readOnly = true;
        text.value = res.text || '';
        els.exportText = text;
        g.body.appendChild(text);
        buttons(g.body, [['Copy', 'pcExportCopy']]);
    }
    return g.root;
}

// ---- the wizard ----
//
// Every button asks Lua and gets { ok, why }; Lua then sends the draft again, and the step
// redraws from it. So the page never shows what it hoped happened, only what the draft says.

const NEW_STEPS = [
    { key: 'interior', label: 'Interior' },
    { key: 'space', label: 'Space' },
    { key: 'doors', label: 'Doors' },
    { key: 'signs', label: 'Signs' },
    { key: 'garage', label: 'Garage', optional: true },
    { key: 'settings', label: 'Name & settings' },
    { key: 'review', label: 'Review' },
];

const PART_LABEL = { interior: 'Re-bind', space: 'Space', doors: 'Doors', garage: 'Garage' };
/** An edit's name: its part's, or "Add doors" when the doors it has are kept and added to. */
const partLabel = (d) => (d.part === 'doors' && d.adding) ? 'Add doors' : (PART_LABEL[d.part] || d.part);

const ROLE_OPTIONS = [
    { value: 'none', label: 'Not this unit\'s' },
    { value: 'entrance', label: 'Entrance' },
    { value: 'lockable', label: 'Inner door, locked' },
    { value: 'interior', label: 'Inner door, not locked' },
    { value: 'garage', label: 'Garage door' },
];

function said(res) {
    if (!wiz || !res) return;
    if (res.ok === false) wiz.say(res.why || 'That did not work', 'err');
    else if (res.why) wiz.say(res.why, 'ok');
}

function ask(name, payload) {
    return nuiCallback(name, payload || {}).then((res) => { said(res); return res; });
}

function stepsFor(d) {
    if (d.mode === 'new') return NEW_STEPS;
    return [{ key: d.part, label: partLabel(d) }, { key: 'review', label: 'Save' }];
}

/** Build the stepper for this draft, unless it is already the one on screen. */
function ensureWizard() {
    const key = draft.mode === 'new' ? 'new'
        : 'edit:' + draft.part + (draft.adding ? '+add' : '') + ':' + draft.propertyId;
    if (wiz && wizKey === key && els.wizBody.contains(wiz.root)) return false;
    wizKey = key;
    els.wizBody.innerHTML = '';
    wiz = WP.stepper({
        id: 'pc-wizard',
        steps: stepsFor(draft),
        onGo: (k, from, body) => fillStep(k, body),
        canLeave: (from) => canLeave(from),
        onFinish: finish,
        finishLabel: draft.mode === 'new' ? 'Save property' : 'Save',
    });
    els.wizBody.appendChild(wiz.root);
    wiz.start();
    return true;
}

function renderWizHead() {
    const d = draft;
    els.wizTitle.textContent = d.mode === 'new'
        ? 'New property' + (form.name ? ' — ' + form.name : '')
        : (partLabel(d) || 'Edit') + ' — ' + (d.name || 'Property #' + d.propertyId);
    els.wizDiscard.textContent = d.mode === 'new' ? 'Discard' : 'Cancel';
}

function fillStep(key, body) {
    if (!draft) return;
    body.innerHTML = '';
    const fill = { interior: stepInterior, space: stepSpace, doors: stepDoors, signs: stepSigns,
                   garage: stepGarage, settings: stepSettings, review: stepReview }[key];
    if (fill) fill(body);
}

function redrawStep() {
    if (wiz && wiz.current()) fillStep(wiz.current(), wiz.body);
}

function info(body, pairs) {
    const grid = WP.el('div', 'wp-info-grid');
    for (const [label, value] of pairs) {
        grid.appendChild(WP.el('span', 'wp-info-label', label));
        grid.appendChild(WP.el('span', 'wp-info-value', String(value)));
    }
    body.appendChild(grid);
}

function buttons(body, list) {
    const row = WP.el('div', 'wp-actions-row');
    for (const b of list) {
        if (!b) continue;
        const el = WP.btn(b[0], b[1], b[2], b[3]);
        if (b[4]) el.disabled = true;
        row.appendChild(el);
    }
    body.appendChild(row);
}

function placeText(p) {
    return p ? fixed(p.x, 2) + ', ' + fixed(p.y, 2) + ', ' + fixed(p.z, 2) + '  ·  ' + fixed(p.yaw, 1) + '°' : '—';
}

function spaceText(s) {
    return s.shapes + ' shape' + (s.shapes === 1 ? '' : 's') + '  ·  ' + fixed(s.area, 1) + ' m²';
}

// ---- step: interior ----

function stepInterior(body) {
    const d = draft;
    const i = d.interior || {};

    if (d.mode === 'edit') {
        // Re-bind: the saved placement against the interior as it stands.
        body.appendChild(WP.el('div', 'wp-hint',
            'Re-bind takes you inside the property and reads its interior as it is now. If the MLO was moved, or '
            + 're-exported with a new origin, Save moves this property onto it, and its space, doors and signs all '
            + 'follow. If an update changed its rooms, Save takes them as they are now.'));
        body.appendChild(WP.statusRow({ label: 'Saved placement', status: 'ok', detail: placeText(i.place) }));
        const m = i.moved;
        const lay = i.layout;
        if (!i.read) {
            body.appendChild(WP.statusRow({ label: 'Here', status: 'err', detail: i.why || 'Not read yet' }));
        } else if (!m || !m.sameHash) {
            body.appendChild(WP.statusRow({ label: 'Here', status: 'err', detail: 'a different interior from the one this property is built on' }));
        } else if (m.same) {
            body.appendChild(WP.statusRow({ label: 'Here', status: 'ok', detail: 'exactly where it was saved'
                + (lay && lay.changed ? '' : ': nothing to re-bind') }));
        } else {
            body.appendChild(WP.statusRow({ label: 'Here', status: 'warn',
                detail: 'moved ' + fixed(m.dist, 2) + ' m and ' + fixed(m.yaw, 1) + '°: Save moves the property onto it' }));
        }
        // ITS ROOMS: an MLO update that changed them (a garage moved out of the home) would fail Verify
        // for good. Save takes the new layout, for every property on it.
        if (i.read && m && m.sameHash && lay) {
            body.appendChild(WP.statusRow(lay.changed
                ? { label: 'Rooms', status: 'warn', detail: 'the MLO has changed: ' + lay.rooms + ' rooms and ' + lay.portals
                    + ' doorways, it had ' + lay.wasRooms + ' and ' + lay.wasPortals
                    + '. Save takes it as it is now, for every property built on it' }
                : { label: 'Rooms', status: 'ok', detail: lay.rooms + ' rooms and ' + lay.portals + ' doorways, as saved' }));
        }
        buttons(body, [['Read again', 'pwRead', 'primary']]);
        return;
    }

    if (d.world) {
        body.appendChild(WP.statusRow({ label: 'Interior', status: 'ok',
            detail: 'none: an open-world property, measured from where you stood' }));
        info(body, [['Measured from', placeText(i.place)]]);
        body.appendChild(WP.el('div', 'wp-hint',
            'Its space is drawn by hand on the next step. To set up an MLO instead, stand inside it and read it.'));
        buttons(body, [['Read the interior instead', 'pwRead']]);
        return;
    }

    if (!i.read) {
        body.appendChild(WP.statusRow({ label: 'Interior', status: 'err', detail: i.why || 'Not read yet' }));
        body.appendChild(WP.el('div', 'wp-hint',
            'Stand inside the MLO you want to set up and press Read. A house with no interior (a plain '
            + 'building on the map) can be set up with No interior.'));
        buttons(body, [['Read', 'pwRead', 'primary'], ['No interior', 'pwWorld']]);
        return;
    }

    body.appendChild(WP.statusRow({
        label: 'Interior', status: i.yawOnly === false ? 'err' : 'ok',
        detail: i.yawOnly === false ? 'this interior is tilted, and whip only handles interiors standing upright'
            : 'hash ' + i.hash + (i.currentRoom ? '  ·  you are in "' + i.currentRoom + '"' : ''),
    }));
    info(body, [
        ['Rooms', i.roomCount || 0],
        ['Doorways', i.portalCount === undefined || i.portalCount === null ? '—' : i.portalCount],
        ['Placement', placeText(i.place)],
    ]);

    const k = i.known || {};
    for (const t of k.templates || []) {
        body.appendChild(WP.statusRow({ label: 'Known', status: 'ok',
            detail: (t.label || 'template #' + t.templateId) + '  ·  ' + t.units + ' unit' + (t.units === 1 ? '' : 's')
                + (t.source && t.source.startsWith('pack:') ? '  ·  from pack ' + t.source.slice(5) : '') }));
    }
    for (const h of k.here || []) {
        body.appendChild(WP.statusRow({ label: 'Already here', status: 'warn', sub: true,
            detail: h.name + ' #' + h.id + '  ·  ' + h.unit }));
    }
    if ((k.here || []).length) {
        body.appendChild(WP.el('div', 'wp-hint',
            'This copy of the interior already has properties. Another one here must be a different part of it, '
            + 'like a second flat on the same floor.'));
    }
    buttons(body, [
        ['Read again', 'pwRead'],
        ['Show rooms', 'pwShowRooms', null, undefined, !(i.roomCount > 0)],
        ['No interior', 'pwWorld', 'ghost'],
    ]);
}

// ---- step: space ----

function stepSpace(body) {
    const d = draft;
    const s = d.space || {};

    const tabs = [];
    if (!d.world && s.roomsKnown) {
        tabs.push({ key: 'interior', label: 'Whole interior' }, { key: 'rooms', label: 'Pick rooms' });
    }
    tabs.push({ key: 'draw', label: 'Draw area' });
    const active = tabs.some((t) => t.key === s.kind) ? s.kind : tabs[0].key;
    const t = WP.tabs({
        id: 'pc-space-tabs', inline: true, active, tabs,
        onChange: (k) => ask('pwSpace', { kind: k }),
    });
    body.appendChild(t.root);

    if (active === 'interior') {
        body.appendChild(WP.el('div', 'wp-hint',
            'Everything inside the interior is this property: right for a house, wrong for a floor of flats. '
            + 'The rooms are the MLO\'s own boxes and are only as good as its author made them. Show them to check.'));
    } else if (active === 'rooms') {
        body.appendChild(WP.el('div', 'wp-hint', 'The rooms that are this property. Show them to see which is which.'));
        for (const r of d.rooms || []) {
            body.appendChild(WP.statusRow({
                label: r.name, status: r.picked ? 'ok' : 'off',
                detail: fixed(r.w, 1) + ' × ' + fixed(r.l, 1) + ' × ' + fixed(r.h, 1) + ' m',
                action: 'pwRoom', arg: r.name, actionLabel: r.picked ? 'Remove' : 'Add',
            }));
        }
    } else {
        body.appendChild(WP.el('div', 'wp-hint',
            'Aim at the floor and press E at each corner. R changes between a rectangle square to the interior, '
            + 'a rectangle along a wall (two corners, then how deep) and an outline; the wheel sets the height.'));
        (s.drawn || []).forEach((sh, n) => {
            body.appendChild(WP.statusRow({
                label: 'Shape ' + (n + 1), status: 'ok',
                detail: (sh.type === 'box' ? 'rectangle' : 'outline of ' + sh.points + ' corners') + '  ·  ' + fixed(sh.area, 1) + ' m²',
                action: 'pwDrawRemove', arg: n + 1, actionLabel: 'Remove',
            }));
        });
        buttons(body, [['Draw in the world', 'pwDraw', 'primary']]);
    }

    body.appendChild(WP.el('div', 'wp-field-label', 'This property'));
    let status = s.shapes > 0 ? 'ok' : 'err';
    let text = s.shapes > 0 ? spaceText(s)
        : active === 'draw' ? 'nothing drawn yet' : active === 'rooms' ? 'no rooms picked' : 'no rooms read';
    if (s.clash) { status = 'err'; text = 'overlaps ' + s.clash; }
    body.appendChild(WP.statusRow({ label: 'Space', status, detail: text }));
    body.appendChild(WP.statusRow({
        label: 'Stand-in point',
        status: !s.visitSet ? 'todo' : s.visitInside ? 'ok' : 'err',
        detail: !s.visitSet ? 'the middle of the space, where Go inside puts you'
            : s.visitInside ? 'where you stood' : 'outside the space: set it again from inside',
    }));
    buttons(body, [
        ['Show', 'pwShowSpace', null, undefined, !(s.shapes > 0)],
        ['Set stand-in point where I am', 'pwVisit'],
        s.visitSet ? ['Clear it', 'pwVisitClear', 'ghost'] : null,
    ]);
}

// ---- step: doors ----

function stepDoors(body) {
    const d = draft;
    const dl = (d.doors && d.doors.list) || [];

    body.appendChild(WP.el('div', 'wp-hint',
        'Scan finds the interior\'s doorways, anything door-shaped at the edge of the space, and garage doors near it. '
        + 'Give each one a role, or walk round and pick them in the world: each door lights up in its role\'s colour, '
        + 'E changes the role of the one you aim at, G adds any door you aim at (a garage door, one the scan missed), '
        + 'L pairs the two leaves of a double door. Nothing is locked or changed until Save.'));
    // Editing, the step starts fresh (tools/property_wizard.lua PropertyWizard.edit). Adding doors keeps
    // the ones it has.
    if (d.mode === 'edit' && d.adding) body.appendChild(WP.el('div', 'wp-hint',
        'The doors it has are listed, as they are. Scan or pick in the world to add the ones it is missing '
        + '(a door already listed is not added twice) and Save: the doors it had stay, and the new ones join them. '
        + 'If its doors have moved, use Edit instead, which starts fresh.'));
    else if (d.mode === 'edit') body.appendChild(WP.el('div', 'wp-hint',
        'This starts fresh: the doors it had are not brought in. Scan, give each door its role, and Save: '
        + 'the old doors are removed and these take their place.'));
    buttons(body, [
        ['Scan for doors', 'pwScan', d.doors && d.doors.scanned ? null : 'primary'],
        // No scan needed first: G adds a door by hand.
        ['Pick in the world', 'pwPick', d.doors && d.doors.scanned ? 'primary' : null, undefined, !(d.space && d.space.shapes > 0)],
        ['Show', 'pwShowSpace', null, undefined, !(d.space && d.space.shapes > 0)],
    ]);

    if (dl.length === 0) {
        body.appendChild(WP.empty(d.doors && d.doors.scanned ? 'No doors found near the space' : 'Not scanned yet'));
        return;
    }
    const withRole = dl.filter((c) => c.role !== 'none');
    for (const c of dl) {
        const role = WP.select(ROLE_OPTIONS, { changeAction: 'pwDoorRole' });
        role.value = c.role;
        role.dataset.i = c.i;
        const controls = [role];
        if (c.role !== 'none') {
            const opts = [{ value: '', label: 'Not paired' }].concat(
                withRole.filter((o) => o.i !== c.i).map((o) => ({ value: String(o.i), label: 'Paired with ' + o.i })));
            const pair = WP.select(opts, { changeAction: 'pwDoorPair' });
            pair.value = c.pair ? String(c.pair) : '';
            pair.dataset.i = c.i;
            controls.push(pair);
        }
        const bits = [(c.kind === 'garage' ? 'garage-sized' : 'door') + (c.source === 'doorway' ? ' in a doorway'
            : c.source === 'saved' ? ', saved' : c.source === 'picked' ? ', picked by hand' : ''),
                      fixed(c.dist, 1) + ' m away'];
        if (c.conflict) bits.push('already ' + c.conflict + '\'s');
        else if (c.doorId) bits.push('whip door #' + c.doorId);
        else if (c.adopt) bits.push('whip door #' + c.adopt + ' (taken over)');
        body.appendChild(WP.statusRow({
            label: String(c.i) + (c.key ? '  ·  ' + c.key : ''),
            status: c.conflict ? 'err' : c.role === 'none' ? 'off' : 'ok',
            detail: bits.join('  ·  '),
            control: controls,
        }));
    }
    const entrances = dl.filter((c) => c.role === 'entrance').length;
    body.appendChild(WP.el('div', 'wp-hint', entrances
        ? entrances + ' entrance' + (entrances === 1 ? '' : 's') + '. Entrances and garage doors lock to the owner and keyholders; '
            + 'inner doors only if you pick "locked".'
        : 'No entrance yet: without one, nothing about this property locks.'));
}

// ---- step: signs ----

function stepSigns(body) {
    const d = draft;
    body.appendChild(WP.el('div', 'wp-hint',
        'The outside sign shows while nobody owns it: its name, its price, that it is for sale. Once somebody does, '
        + 'the manager inside takes over: keys, furniture, everything the people who live there need.'));
    for (const [which, label, placed, none] of [
        ['sign', 'Outside sign', d.sign, 'none: nobody can see it is for sale'],
        ['manager', 'Manager', d.manager, 'none: once owned, the outside sign\'s spot is used'],
    ]) {
        const onPost = which === 'sign' && d.signPost;
        body.appendChild(WP.statusRow({ label, status: placed ? 'ok' : 'warn',
            detail: onPost ? 'on a sign post, ' + d.signPost : placed ? 'placed' : none }));
        buttons(body, [
            ['Use suggested spot', 'pwSuggest', null, which, !d.canSuggest],
            // The outside sign on a sign post: the prompt goes on its board by itself.
            which === 'sign' && d.posts ? [onPost ? 'Move the sign post' : 'Put up a sign post', 'pwSignPost',
                placed ? null : 'primary'] : null,
            [which === 'sign' && d.posts ? 'Prompt only' : 'Place in the world', 'pwPlace',
                placed || (which === 'sign' && d.posts) ? null : 'primary', which],
            placed ? ['Clear', 'pwSignClear', 'ghost', which] : null,
        ]);
        if (which === 'sign' && d.posts) {
            body.appendChild(WP.el('div', 'wp-hint',
                'A sign post stands in the garden with the listing printed on its board and More… to buy: aim at the ground where it goes, '
                + 'Q / E turn it, X changes the sign, Enter puts it there. It comes down once somebody owns the place. '
                + 'Prompt only puts the prompt on a wall instead, with no post.'));
        }
    }
    if (!d.canSuggest) body.appendChild(WP.el('div', 'wp-hint', 'A suggestion needs an entrance door: it goes beside it.'));
}

// ---- step: garage ----

function stepGarage(body) {
    const bays = (draft.garage && draft.garage.bays) || [];
    body.appendChild(WP.el('div', 'wp-hint',
        'A private garage: its bays are for the owner and keyholders, nobody else, and it has no map blip. '
        + 'Set them out with the bay tool every garage uses: aim at the ground where a car should park and press '
        + 'Enter, or aim at a bay to pick it up and move it; Q / E turn it, ↑ / ↓ raise it, X takes it away. '
        + 'The card in the corner shows the keys, and the controller\'s. '
        + (draft.mode === 'new' ? 'No bays, no garage: Skip if it has none.' : 'Remove every bay to take the garage away.')));
    body.appendChild(WP.statusRow({
        label: 'Garage', status: bays.length ? 'ok' : 'off',
        detail: bays.length ? bays.length + ' bay' + (bays.length === 1 ? '' : 's') + ', private'
            : 'none' + (draft.mode === 'edit' ? ': Save takes it away, and its cars go to a public garage' : ''),
    }));
    for (const b of bays) {
        body.appendChild(WP.statusRow({
            label: 'Bay ' + b.i, status: 'ok', sub: true, detail: fixed(b.dist, 1) + ' m away',
            action: 'pwBayRemove', arg: b.i, actionLabel: 'Remove',
        }));
    }
    // Changing a garage, or one with bays already set out, says so ("Place & Edit Garage Locations").
    buttons(body, [
        [bays.length || draft.mode === 'edit' ? 'Place & Edit Garage Locations' : 'Set out bays in the world', 'pwBays', 'primary'],
        ['Show', 'pwShowSpace', null, undefined, !(draft.space && draft.space.shapes > 0)],
    ]);
}

// ---- step: settings ----

function formInput(field, opts) {
    const i = WP.input({ ...opts, value: form[field], inputAction: 'pwForm' });
    i.dataset.field = field;
    return i;
}

function stepSettings(body) {
    const names = WP.el('div', 'wp-cols-2');
    els.wName = formInput('name', { placeholder: 'e.g. Mirror Park Bungalow' });
    names.appendChild(WP.field('Name', els.wName, true));
    els.wLabel = formInput('label', { placeholder: 'e.g. 3-1' });
    names.appendChild(WP.field('Unit', els.wLabel));
    els.wBuilding = formInput('building', { placeholder: 'e.g. Mega Tower B' });
    names.appendChild(WP.field('Building', els.wBuilding));
    body.appendChild(names);

    const nums = WP.el('div', 'wp-cols-2');
    els.wPrice = formInput('price', { type: 'number' });
    nums.appendChild(WP.field('Price (shown only)', els.wPrice));
    els.wMax = formInput('maxObjects', { type: 'number' });
    nums.appendChild(WP.field('Furniture limit', els.wMax));
    body.appendChild(nums);

    const lock = WP.el('div', 'wp-cols-2');
    lock.appendChild(WP.btn('Door auto-lock: ' + (form.autolock ? 'ON' : 'OFF'), 'pwFormAutolock',
        form.autolock ? 'primary' : 'ghost'));
    els.wDelay = formInput('autolockDelay', { type: 'number' });
    lock.appendChild(WP.field('Lock after (seconds)', els.wDelay));
    body.appendChild(lock);

    const owner = WP.el('div', 'wp-cols-2');
    // Typed ids reach `form` as they are typed; one picked from the list is read back at Next.
    els.wOwner = formInput('owner', { placeholder: 'Nobody yet, or a name or character id' });
    WP.attachCharPicker(els.wOwner);
    owner.appendChild(WP.field('Owner (optional)', els.wOwner));
    body.appendChild(owner);

    // ITS LOOKS, when the resource that built this interior offers some (found by the interior, when it
    // was read). The owner can change it later at the sign.
    const th = wizardThemes();
    if (th) {
        if (form.theme === undefined || !th.themes.some((t) => t.id === form.theme)) form.theme = th.current;
        body.appendChild(WP.el('div', 'wp-section-title', 'Theme'));
        body.appendChild(WP.el('div', 'wp-hint', th.label + ' has ' + th.themes.length
            + ' looks for this home (' + th.home + '). Pick the one it starts with; its owner can change it at the sign.'));
        els.wThemes = themeSwatches(th.themes, form.theme, 'pwFormTheme');
        body.appendChild(els.wThemes);
    }
}

/** The looks the interior being set up has, or null (the server's answer when it was read). */
function wizardThemes() {
    const k = draft && draft.mode === 'new' && draft.interior && draft.interior.known;
    const th = k && k.themes;
    return th && th.themes && th.themes.length ? th : null;
}

function themeName(th, id) {
    const t = th && th.themes.find((x) => x.id === id);
    return t ? t.name : 'theme ' + id;
}

/** The settings form checked, or a sentence saying what is wrong with it. */
function checkForm() {
    if (els.wOwner && document.contains(els.wOwner)) form.owner = els.wOwner.value.trim();
    if (!String(form.name).trim()) return 'A property needs a name';
    const price = Number(form.price);
    if (!Number.isFinite(price) || price < 0) return 'The price is zero or more';
    const max = Number(form.maxObjects);
    if (!Number.isInteger(max) || max < 0 || max > 1000) return 'The furniture limit is a whole number from 0 to 1000';
    const delay = Number(form.autolockDelay);
    if (!Number.isInteger(delay) || delay < 1 || delay > 300) return 'Auto-lock waits 1 to 300 seconds';
    if (form.owner && !(Number.isInteger(Number(form.owner)) && Number(form.owner) > 0)) {
        return 'Pick the owner from the list, or type a character id';
    }
    return true;
}

// ---- step: review ----

function stepReview(body) {
    const d = draft;
    const s = d.space || {};
    const dl = (d.doors && d.doors.list) || [];
    const picked = dl.filter((c) => c.role !== 'none');
    const entrances = picked.filter((c) => c.role === 'entrance').length;
    const conflicts = picked.filter((c) => c.conflict).length;
    const edit = (key) => d.mode === 'new' ? { action: 'pwJump', arg: key, actionLabel: 'Change' } : {};

    if (d.mode === 'edit') {
        if (d.part === 'interior') {
            const m = d.interior && d.interior.moved;
            const lay = d.interior && d.interior.layout;
            const layNew = !!(m && m.sameHash && lay && lay.changed);
            body.appendChild(WP.statusRow({ label: 'Re-bind', status: m && m.sameHash && !m.same ? 'warn' : (layNew ? 'ok' : 'err'),
                detail: m && m.sameHash && !m.same ? 'moves ' + fixed(m.dist, 2) + ' m onto the interior here'
                    : (layNew ? 'stays where it is' : 'nothing to move onto') }));
            if (layNew) {
                body.appendChild(WP.statusRow({ label: 'Rooms', status: 'warn',
                    detail: 'takes the MLO as it is now: ' + lay.rooms + ' rooms and ' + lay.portals + ' doorways (it had '
                        + lay.wasRooms + ' and ' + lay.wasPortals + '), for every property built on it' }));
            }
        } else {
            const bays = ((d.garage && d.garage.bays) || []).length;
            const added = picked.filter((c) => c.source !== 'saved').length;
            body.appendChild(WP.statusRow({ label: partLabel(d), status: d.part === 'garage' && !bays ? 'warn' : 'ok',
                detail: d.part === 'space' ? spaceText(s)
                    : d.part === 'garage' ? (bays ? bays + ' bay' + (bays === 1 ? '' : 's') : 'none: the garage goes, its cars to a public one')
                    : picked.length + ' door' + (picked.length === 1 ? '' : 's') + ', ' + entrances + ' entrance' + (entrances === 1 ? '' : 's')
                        + (d.adding ? ' (' + added + ' new)' : '') }));
            if (d.unitUses > 1) {
                body.appendChild(WP.el('div', 'wp-hint', 'This unit is shared by ' + d.unitUses + ' properties. Save it for:'));
                const scope = WP.tabs({
                    id: 'pc-edit-scope', inline: true, active: editScope,
                    tabs: [{ key: 'unit', label: 'All ' + d.unitUses + ' on this unit' }, { key: 'property', label: 'Only this one' }],
                    onChange: (k) => { editScope = k; },
                });
                body.appendChild(scope.root);
            }
        }
        if (d.saving) wiz.say('Saving…');
        return;
    }

    const i = d.interior || {};
    body.appendChild(WP.statusRow({ label: 'Interior', status: 'ok',
        detail: d.world ? 'none: open world' : 'hash ' + i.hash + '  ·  ' + (i.roomCount || 0) + ' rooms', ...edit('interior') }));
    body.appendChild(WP.statusRow({ label: 'Space', status: s.shapes > 0 && !s.clash ? 'ok' : 'err',
        detail: s.clash ? 'overlaps ' + s.clash : spaceText(s),
        ...edit('space') }));
    body.appendChild(WP.statusRow({ label: 'Doors', status: conflicts ? 'err' : entrances ? 'ok' : 'warn',
        detail: conflicts ? conflicts + ' already belong to something else'
            : picked.length + ' door' + (picked.length === 1 ? '' : 's') + ', ' + entrances + ' entrance' + (entrances === 1 ? '' : 's'),
        ...edit('doors') }));
    body.appendChild(WP.statusRow({ label: 'Signs', status: d.sign && d.manager ? 'ok' : 'warn',
        detail: 'outside ' + (d.sign ? 'placed' : 'none') + '  ·  manager ' + (d.manager ? 'placed' : 'none'),
        ...edit('signs') }));
    const bays = ((d.garage && d.garage.bays) || []).length;
    body.appendChild(WP.statusRow({ label: 'Garage', status: bays ? 'ok' : 'off',
        detail: bays ? bays + ' bay' + (bays === 1 ? '' : 's') + ', private' : 'none', ...edit('garage') }));
    body.appendChild(WP.statusRow({ label: 'Name', status: form.name ? 'ok' : 'err',
        detail: [form.name || 'none', form.label, form.building].filter(Boolean).join('  ·  '), ...edit('settings') }));
    body.appendChild(WP.statusRow({ label: 'Settings', status: 'ok',
        detail: (form.owner ? 'owner #' + form.owner : 'for sale') + '  ·  price ' + (Number(form.price) || 0)
            + '  ·  up to ' + form.maxObjects + ' pieces  ·  auto-lock ' + (form.autolock ? form.autolockDelay + ' s' : 'off'),
        ...edit('settings') }));
    const th = wizardThemes();
    if (th) {
        body.appendChild(WP.statusRow({ label: 'Theme', status: 'ok',
            detail: themeName(th, form.theme === undefined ? th.current : form.theme) + '  ·  from ' + th.label,
            ...edit('settings') }));
    }
    body.appendChild(WP.el('div', 'wp-hint',
        'Save writes it all at once. Whip then makes (or takes over) its doors and locks them to the owner.'));
    if (d.saving) wiz.say('Saving…');
}

// ---- leaving a step, and saving ----

function canLeave(from) {
    const d = draft;
    if (!d) return 'There is no property being set up';
    const s = d.space || {};
    if (from === 'interior') {
        const i = d.interior || {};
        if (d.mode === 'edit') {
            if (!i.read) return i.why || 'Read the interior first';
            if (!i.moved || !i.moved.sameHash) return 'You are in a different interior';
            if (i.moved.same && !(i.layout && i.layout.changed)) return 'It has not moved and its rooms are as saved: there is nothing to re-bind';
            return true;
        }
        if (!d.world && !i.read) return 'Read the interior you are standing in, or choose No interior';
        if (!d.world && i.yawOnly === false) return 'This interior is tilted, and cannot hold properties';
        return true;
    }
    if (from === 'space') {
        if (!(s.shapes > 0)) return 'Choose its space: the whole interior, some rooms, or draw it';
        if (s.clash) return 'That overlaps ' + s.clash;
        if (s.visitSet && !s.visitInside) return 'The stand-in point is outside the space';
        return true;
    }
    if (from === 'doors') {
        const dl = (d.doors && d.doors.list) || [];
        if (dl.some((c) => c.role !== 'none' && c.conflict)) return 'A door you picked already belongs to something else';
        if (!dl.some((c) => c.role === 'entrance') && !noEntranceOk) {
            noEntranceOk = true;
            return 'No entrance picked, so nothing will lock. Press Next again to go on without one.';
        }
        return true;
    }
    if (from === 'settings') return checkForm();
    return true;
}

function finish() {
    const d = draft;
    if (!d || d.saving) return;
    if (d.mode === 'new') {
        const ok = checkForm();
        if (ok !== true) { wiz.say(ok, 'err'); return; }
    }
    wiz.say('Saving…');
    nuiCallback('pwSave', {
        name: String(form.name).trim(), label: String(form.label).trim(), building: String(form.building).trim(),
        price: Number(form.price) || 0, maxObjects: Number(form.maxObjects), autolock: !!form.autolock,
        autolockDelay: Number(form.autolockDelay), ownerCharId: form.owner ? Number(form.owner) : 0,
        scope: d.unitUses > 1 ? editScope : 'property',
        theme: wizardThemes() && form.theme !== undefined ? Number(form.theme) : undefined,
    }).then(said);
}

function onDraft(payload) {
    draft = payload && payload.active ? payload : null;
    if (!draft) {
        wiz = null;
        wizKey = '';
        els.wizBody.innerHTML = '';
    } else {
        if (!ensureWizard()) redrawStep();
        renderWizHead();
    }
    showView();
}

function onSaved(payload) {
    if (payload.ok) {
        form = { ...FORM_DEFAULT };
        noEntranceOk = false;
        WP.result('Saved', 'ok');
        if (payload.id) {
            selectedId = Number(payload.id);
            detail = null;
            renderList();
            loadDetail();
        }
    } else if (wiz) {
        wiz.say(payload.why || 'It was not saved', 'err');
    }
}

async function discard() {
    const ok = await WP.confirm({
        title: draft && draft.mode === 'edit' ? 'Stop editing?' : 'Throw this property away?',
        body: draft && draft.mode === 'edit' ? 'Nothing you changed here is saved.'
            : 'Nothing has been saved yet. Everything you set up for it goes.',
        confirmLabel: draft && draft.mode === 'edit' ? 'Stop' : 'Throw away', danger: true,
    });
    if (ok) nuiCallback('pwCancel', {});
    return ok;
}

// ---- the section ----

function selected() { return selectedId; }

function readCharId(input) {
    const raw = (input && input.value || '').trim();
    const n = Number(raw);
    if (!raw || !Number.isInteger(n) || n <= 0) {
        WP.fieldError(input, 'Pick somebody from the list, or type a character id.');
        return null;
    }
    return n;
}

WhipPanel.registerSection({
    id: 'properties',
    group: 'world',
    label: 'Properties',
    order: 35,

    render(root) {
        els = {};
        const tabs = WP.tabs({
            id: 'pc-tabs', active: tab,
            tabs: [{ key: 'properties', label: 'Properties' }, { key: 'templates', label: 'Templates & packs' }],
            onChange: (k) => switchTab(k),
        });
        root.appendChild(tabs.root);

        // ---- the list and one property ----
        els.propsView = WP.el('div', 'wp-view');

        const filterSel = WP.select([
            { value: 'all', label: 'All' },
            { value: 'attention', label: 'Needs attention' },
            { value: 'unverified', label: 'Not checked yet' },
            { value: 'unowned', label: 'Unowned' },
            { value: 'owned', label: 'Owned' },
            { value: 'closed', label: 'Closed (pack not running)' },
        ], { changeAction: 'pcFilter' });
        filterSel.value = filter;
        els.filterSel = filterSel;
        els.buildingSel = WP.select([{ value: '', label: 'Every building' }], { changeAction: 'pcBuilding' });
        els.propsView.appendChild(WP.toolbar({
            left: [WP.btn('What property am I in?', 'pcWhereAmI', 'ghost'), filterSel, els.buildingSel],
            search: { inputAction: 'pcSearch', placeholder: 'Search properties…', id: 'wp-pc-search' },
            right: [
                WP.btn('Quick check', 'pcQuickCheck', 'ghost'),
                WP.btn('Verify…', 'pcVerifyList'),
                WP.btn('Register here', 'pcRegister'),
                WP.btn('New property', 'pcNew', 'primary'),
            ],
        }));

        const split = WP.el('div', 'wp-split');
        const listCol = WP.el('div', 'wp-list-col');
        els.count = WP.el('div', 'wp-list-count', '');
        listCol.appendChild(els.count);
        els.list = WP.el('div', 'wp-list');
        listCol.appendChild(els.list);
        split.appendChild(listCol);

        const pane = WP.el('div', 'wp-detail');
        els.detailTitle = WP.el('div', 'wp-pane-title', 'Select a property');
        pane.appendChild(els.detailTitle);
        els.detailBody = WP.el('div');
        pane.appendChild(els.detailBody);
        split.appendChild(pane);
        els.propsView.appendChild(split);
        root.appendChild(els.propsView);

        // ---- the wizard, in the Properties tab's place while a property is set up. In the middle of the section,
        // not against its left edge; so are Register
        // here and the Templates tab below. ----
        els.wizView = WP.el('div', 'wp-section-solo wp-section-center');
        els.wizView.style.display = 'none';
        const head = WP.el('div', 'wp-actions-row');
        els.wizTitle = WP.el('div', 'wp-pane-title', 'New property');
        head.appendChild(els.wizTitle);
        head.appendChild(WP.el('span', 'wp-actions-split'));
        els.wizDiscard = WP.btn('Discard', 'pwDiscard', 'ghost');
        head.appendChild(els.wizDiscard);
        els.wizView.appendChild(head);
        els.wizBody = WP.el('div');
        els.wizView.appendChild(els.wizBody);
        root.appendChild(els.wizView);

        // ---- Register here, likewise ----
        els.regView = WP.el('div', 'wp-section-solo wp-section-center');
        els.regView.style.display = 'none';
        const regHead = WP.el('div', 'wp-actions-row');
        regHead.appendChild(WP.el('div', 'wp-pane-title', 'Register here'));
        regHead.appendChild(WP.el('span', 'wp-actions-split'));
        regHead.appendChild(WP.btn('Read again', 'prRead', 'ghost'));
        regHead.appendChild(WP.btn('Close', 'prClose', 'ghost'));
        els.regView.appendChild(regHead);
        els.regBody = WP.el('div');
        els.regView.appendChild(els.regBody);
        root.appendChild(els.regView);

        // ---- templates & packs ----
        els.tplView = WP.el('div', 'wp-section-solo wp-section-center');
        els.tplView.style.display = 'none';
        els.tplBody = WP.el('div');
        els.tplView.appendChild(els.tplBody);
        root.appendChild(els.tplView);

        built = true;
        wiz = null;
        wizKey = '';
        renderList();
        renderDetail();
        if (draft) onDraft(draft);
        renderRegister();
        showView();
    },

    onData(kind, payload) {
        if (!built) return;
        if (kind === 'draft') { onDraft(payload || {}); return; }
        if (kind === 'saved') { onSaved(payload || {}); return; }
        if (kind === 'register') {
            reg = payload && payload.active ? payload : null;
            renderRegister();
            showView();
            return;
        }
        if (kind === 'registered') {
            const made = (payload.created || []).length;
            const skipped = payload.skipped || [];
            if (made > 0) {
                WP.result(made + ' registered' + (skipped.length ? ', ' + skipped.length + ' skipped' : ''), 'ok');
            } else {
                WP.result(payload.why || (skipped[0] ? skipped[0].unit + ': ' + skipped[0].why : 'Nothing registered'), 'err');
            }
            return;
        }
        if (kind === 'stampDone') {
            WP.result('Stamp mode: ' + (payload.made || 0) + ' registered', 'ok');
            return;
        }
        if (kind === 'verifyDone') {
            WP.result('Verified ' + payload.checked + ': ' + payload.ok + ' OK, ' + payload.attention
                + ' need attention' + (payload.skipped ? ', ' + payload.skipped + ' skipped' : '')
                + (payload.stopped ? ' (stopped)' : ''), payload.attention ? 'err' : 'ok');
            if (payload.attention) setFilter('attention');
            return;
        }
        if (kind === 'all') {
            rows = payload.rows || [];
        } else if (kind === 'rows') {
            const byId = new Map(rows.map((r) => [r.id, r]));
            for (const r of payload.rows || []) byId.set(r.id, r);
            for (const id of payload.removed || []) byId.delete(id);
            rows = [...byId.values()].sort((a, b) => a.id - b.id);
            const touched = (payload.rows || []).some((r) => r.id === selectedId);
            if ((payload.removed || []).includes(selectedId)) { selectedId = null; detail = null; }
            else if (touched) loadDetail();
        } else {
            return;
        }
        renderBuildings();
        renderList();
        if (selectedId !== null && !rows.some((r) => r.id === selectedId)) { selectedId = null; detail = null; }
        if (kind === 'all') loadDetail();
        else renderDetail();
    },

    onEscape() {
        // In the wizard, Esc steps back; on its first step it asks whether to throw it away.
        if (tab === 'properties' && wizardOpen() && wiz) {
            if (!wiz.escape()) discard();
            return true;
        }
        if (tab === 'properties' && registerOpen()) { nuiCallback('prClose', {}); return true; }
        if (tab === 'templates' && exportFor) { exportFor = null; renderTemplates(tplData); return true; }
        if (selectedId !== null) { selectedId = null; detail = null; renderList(); renderDetail(); return true; }
        return false;
    },

    actions: {
        pcFilter: (el) => { filter = el.value; renderList(); },
        pcBuilding: (el) => { building = el.value; renderList(); },
        pcSearch: (el) => { search = el.value.toLowerCase(); renderList(); },
        pcSelect: (el) => {
            selectedId = Number(el.dataset.id);
            detail = null;
            renderList();
            renderDetail();
            loadDetail();
        },

        // The property the admin stands in, picked out in the list (the filters cleared when they hid it).
        pcWhereAmI: () => {
            nuiCallback('pcWhereAmI', {}).then((res) => {
                const id = res && res.id ? Number(res.id) : null;
                const r = id !== null && rows.find((x) => x.id === id);
                if (!r) { WP.result('You are not in a property', 'err'); return; }
                if (!matches(r)) {
                    filter = 'all'; building = ''; search = '';
                    if (els.filterSel) els.filterSel.value = 'all';
                    if (els.buildingSel) els.buildingSel.value = '';
                    const box = document.getElementById('wp-pc-search');
                    if (box) box.value = '';
                }
                selectedId = id;
                detail = null;
                renderList();
                renderDetail();
                loadDetail();
                const item = els.list.querySelector('.active');
                if (item) item.scrollIntoView({ block: 'nearest' });
                WP.result('You are in ' + (r.name || 'property #' + id), 'ok');
            });
        },
        pcManageFurniture: () => { if (selected() !== null) nuiCallback('pcManageFurniture', { id: selectedId }); },
        // One of its stashes, opened as the Container Manager opens one (tools/panel_sections/containers.lua).
        pcInspectStash: (el) => nuiCallback('cmOpenContainer', { containerId: Number(el.dataset.arg) }),

        pcGoEntry: () => { if (selected() !== null) nuiCallback('pcGo', { id: selectedId, where: 'entry' }); },
        pcGoInside: () => { if (selected() !== null) nuiCallback('pcGo', { id: selectedId, where: 'inside' }); },
        pcShowSpace: () => { if (selected() !== null) nuiCallback('pcShowSpace', { id: selectedId }); },
        pcPlaceSign: (el) => {
            if (selected() === null || !detail) return;
            const uses = detail.unitUses || 1;
            nuiCallback('pcPlaceSign', { id: selectedId, which: el.dataset.arg,
                                         scope: uses > 1 ? signScope : 'property', uses });
        },
        pcPlaceSignPost: () => {
            if (selected() === null || !detail) return;
            const uses = detail.unitUses || 1;
            nuiCallback('pcPlaceSignPost', { id: selectedId, scope: uses > 1 ? signScope : 'property', uses });
        },

        pcSetOwner: () => {
            const charId = readCharId(els.ownerInput);
            if (charId) nuiCallback('pcSetOwner', { id: selectedId, charId });
        },
        pcClearOwner: async () => {
            const ok = await WP.confirm({
                title: 'Make it unowned?',
                body: 'Every keyholder loses their key as well, and the doors lock to everyone.',
                confirmLabel: 'Make unowned', danger: true,
            });
            if (ok) nuiCallback('pcSetOwner', { id: selectedId, charId: 0 });
        },
        pcGrantKey: () => {
            const charId = readCharId(els.keyInput);
            if (charId) nuiCallback('pcGrantKey', { id: selectedId, charId });
        },
        pcRevokeKey: (el) => nuiCallback('pcRevokeKey', { id: selectedId, charId: Number(el.dataset.arg) }),

        pcToggleAutolock: () => {
            formAutolock = !formAutolock;
            els.autolockBtn.textContent = 'Door auto-lock: ' + (formAutolock ? 'ON' : 'OFF');
            els.autolockBtn.className = 'wp-btn ' + (formAutolock ? 'wp-btn-primary' : 'wp-btn-ghost');
        },
        pcSaveSettings: () => {
            const name = els.nameInput.value.trim();
            if (!name) { WP.fieldError(els.nameInput, 'A property needs a name.'); return; }
            const price = Number(els.priceInput.value);
            if (!Number.isFinite(price) || price < 0) { WP.fieldError(els.priceInput, 'Zero or more.'); return; }
            const maxObjects = Number(els.maxInput.value);
            if (!Number.isInteger(maxObjects) || maxObjects < 0 || maxObjects > 1000) {
                WP.fieldError(els.maxInput, 'A whole number from 0 to 1000.');
                return;
            }
            const delay = Number(els.delayInput.value);
            if (!Number.isInteger(delay) || delay < 1 || delay > 300) {
                WP.fieldError(els.delayInput, '1 to 300 seconds.');
                return;
            }
            nuiCallback('pcUpdate', { id: selectedId, fields: {
                name, label: els.labelInput.value, building: els.buildingInput.value,
                settings: { price, maxObjects, autolock: formAutolock, autolockDelay: delay },
            } });
        },

        pcClearFurniture: async () => {
            const ok = await WP.confirm({
                title: 'Clear all furniture?',
                body: 'Every piece placed in ' + (detail && detail.name || 'this property') + ' is removed. This cannot be undone.',
                confirmLabel: 'Clear', danger: true,
            });
            if (ok) nuiCallback('pcClearFurniture', { id: selectedId });
        },
        pcDelete: async () => {
            const d = detail;
            const ok = await WP.confirm({
                title: 'Delete property?',
                body: '"' + (d && d.name || '#' + selectedId) + '" goes, with its keys and furniture. Its doors are given back '
                    + '(a door it made is removed). ' + (d && d.packId
                        ? 'It came from a pack, which will not make it again.'
                        : 'The interior itself is not touched.'),
                confirmLabel: 'Delete', danger: true,
            });
            if (ok) nuiCallback('pcDelete', { id: selectedId });
        },

        // ---- scale: Register here, Stamp, Verify, Quick check, Export ----
        pcRegister: () => nuiCallback('prStart', {}),
        prRead: () => nuiCallback('prRead', {}),
        prClose: () => nuiCallback('prClose', {}),
        prForm: (el) => { regForm[el.dataset.field] = el.value; renderRegUnits(); },
        prSkip: (el) => {
            const k = el.dataset.arg;
            if (regForm.skip[k]) delete regForm.skip[k]; else regForm.skip[k] = true;
            renderRegUnits();
        },
        prRegister: () => {
            const t = currentRegTemplate();
            if (!t) return;
            nuiCallback('prRegister', { templateId: t.templateId, form: regFormPayload() }).then((res) => {
                if (res && res.ok === false) WP.result(res.why || 'Not registered', 'err');
            });
        },
        prShow: () => {
            const t = currentRegTemplate();
            if (t) nuiCallback('prShow', { templateId: t.templateId });
        },
        prStamp: () => {
            nuiCallback('prStamp', { form: regFormPayload() }).then((res) => {
                if (res && res.ok === false) WP.result(res.why || 'Stamp mode could not start', 'err');
            });
        },

        pcVerifyOne: () => {
            if (selected() === null) return;
            nuiCallback('pvStart', { ids: [selectedId] }).then((res) => {
                if (res && res.ok === false) WP.result(res.why || 'Verify could not start', 'err');
            });
        },
        pcVerifyList: async () => {
            const ids = shownIds();
            if (ids.length === 0) { WP.result('Nothing in the list to verify', 'err'); return; }
            const ok = await WP.confirm({
                title: 'Verify ' + ids.length + ' propert' + (ids.length === 1 ? 'y' : 'ies') + '?',
                body: 'You are taken to each one in turn (the ones the list is showing now) and brought back here at the end. '
                    + 'Space pauses, the right arrow skips one, Esc stops.',
                confirmLabel: 'Verify',
            });
            if (!ok) return;
            nuiCallback('pvStart', { ids }).then((res) => {
                if (res && res.ok === false) WP.result(res.why || 'Verify could not start', 'err');
            });
        },
        pcQuickCheck: () => {
            const ids = shownIds();
            if (ids.length === 0) { WP.result('Nothing in the list to check', 'err'); return; }
            WP.result('Checking ' + ids.length + '…');
            nuiCallback('pcQuickCheck', { ids }).then((res) => {
                if (!res) { WP.result('No answer from the server', 'err'); return; }
                const bad = res.problems || [];
                if (bad.length === 0) {
                    WP.result('Quick check: all ' + res.checked + ' fine', 'ok');
                } else {
                    WP.result('Quick check: ' + bad.length + ' of ' + res.checked + ' need attention. First, '
                        + bad[0].name + ': ' + bad[0].problems[0], 'err');
                    setFilter('attention');
                }
            });
        },

        pcExportPick: (el) => {
            exportFor = { templateIds: [Number(el.dataset.arg)], placements: true, packId: '', label: '', result: null };
            renderTemplates(tplData);
        },
        pcExportToggle: (el) => {
            if (!exportFor) return;
            const id = Number(el.dataset.arg);
            exportFor.packId = els.exportId ? els.exportId.value.trim() : exportFor.packId;
            exportFor.label = els.exportLabel ? els.exportLabel.value.trim() : exportFor.label;
            exportFor.templateIds = exportFor.templateIds.includes(id)
                ? exportFor.templateIds.filter((x) => x !== id) : exportFor.templateIds.concat([id]);
            exportFor.result = null;
            renderTemplates(tplData);
        },
        pcExportPlacements: () => {
            if (!exportFor) return;
            exportFor.placements = !exportFor.placements;
            exportFor.packId = els.exportId ? els.exportId.value.trim() : exportFor.packId;
            exportFor.label = els.exportLabel ? els.exportLabel.value.trim() : exportFor.label;
            renderTemplates(tplData);
        },
        pcExportClose: () => { exportFor = null; renderTemplates(tplData); },
        pcExportRun: () => {
            if (!exportFor) return;
            const packId = els.exportId ? els.exportId.value.trim() : '';
            if (packId && !/^[a-z0-9_.-]{3,48}$/.test(packId)) {
                WP.fieldError(els.exportId, '3 to 48 characters: lower-case letters, numbers, _ - and .');
                return;
            }
            exportFor.packId = packId;
            exportFor.label = els.exportLabel ? els.exportLabel.value.trim() : '';
            const want = exportFor;
            nuiCallback('pcExport', { templateIds: want.templateIds, placements: want.placements, packId,
                                      label: want.label }).then((res) => {
                if (exportFor !== want) return;
                want.result = res || { ok: false, why: 'No answer from the server' };
                renderTemplates(tplData);
            });
        },
        pcExportCopy: () => {
            const t = els.exportText;
            if (!t) return;
            t.focus();
            t.select();
            let copied = false;
            try { copied = document.execCommand('copy'); } catch (e) { copied = false; }
            WP.result(copied ? 'Copied' : 'Selected: press Ctrl+C to copy', copied ? 'ok' : undefined);
        },

        // ---- the wizard ----
        pcNew: () => {
            form = { ...FORM_DEFAULT };
            noEntranceOk = false;
            nuiCallback('pwStart', {});
        },
        pcEditPart: async (el) => {
            if (selected() === null) return;
            if (wizardOpen() && !(await discard())) return;
            editScope = 'unit';
            noEntranceOk = false;
            nuiCallback('pwEdit', { id: selectedId, part: el.dataset.arg }).then((res) => {
                if (res && res.ok === false) WP.result(res.why || 'Could not open that', 'err');
                // Re-bind reads as it opens, and says what it read, on the wizard's own line once it is up.
                else if (res && res.why) {
                    if (wiz) wiz.say(res.why, res.bad ? 'err' : 'ok');
                    else WP.result(res.why, res.bad ? 'err' : 'ok');
                }
            });
        },
        // The doors it has kept, and added to.
        pcAddDoors: async () => {
            if (selected() === null) return;
            if (wizardOpen() && !(await discard())) return;
            editScope = 'unit';
            noEntranceOk = false;
            nuiCallback('pwEdit', { id: selectedId, part: 'doors', add: true }).then((res) => {
                if (res && res.ok === false) WP.result(res.why || 'Could not open that', 'err');
            });
        },
        pwDiscard: () => discard(),
        pwJump: (el) => { if (wiz) wiz.jump(el.dataset.arg); },

        pwRead: () => ask('pwReadInterior'),
        pwWorld: () => ask('pwUseWorld'),
        pwShowRooms: () => ask('pwShow', { what: 'rooms' }),
        pwShowSpace: () => ask('pwShow', { what: 'space' }),

        pwRoom: (el) => ask('pwRoom', { name: el.dataset.arg }),
        pwDraw: () => ask('pwDraw'),
        pwDrawRemove: (el) => ask('pwDrawRemove', { i: Number(el.dataset.arg) }),
        pwVisit: () => ask('pwVisit'),
        pwVisitClear: () => ask('pwVisit', { clear: true }),

        pwScan: () => { if (wiz) wiz.say('Looking…'); ask('pwDoorsScan'); },
        pwPick: () => ask('pwDoorsPick'),
        pwDoorRole: (el) => ask('pwDoorSet', { i: Number(el.dataset.i), role: el.value }),
        pwDoorPair: (el) => ask('pwDoorPair', { i: Number(el.dataset.i), j: el.value ? Number(el.value) : 0 }),

        pwBays: () => ask('pwBays'),
        pwBayRemove: (el) => ask('pwBayRemove', { i: Number(el.dataset.arg) }),

        pwSuggest: (el) => ask('pwSignSuggest', { which: el.dataset.arg }),
        pwPlace: (el) => ask('pwSignPlace', { which: el.dataset.arg }),
        pwSignPost: () => ask('pwSignPost'),
        pwSignClear: (el) => ask('pwSignClear', { which: el.dataset.arg }),

        pwForm: (el) => {
            form[el.dataset.field] = el.value;
            if (el.dataset.field === 'name') renderWizHead();
        },
        pwFormAutolock: (el) => {
            form.autolock = !form.autolock;
            el.textContent = 'Door auto-lock: ' + (form.autolock ? 'ON' : 'OFF');
            el.className = 'wp-btn ' + (form.autolock ? 'wp-btn-primary' : 'wp-btn-ghost');
        },
        pwFormTheme: (el) => {
            form.theme = Number(el.dataset.arg);
            if (els.wThemes) {
                els.wThemes.querySelectorAll('.wp-swatch').forEach((b) => {
                    b.classList.toggle('active', Number(b.dataset.arg) === form.theme);
                });
            }
        },
        pcSetTheme: (el) => nuiCallback('pcSetTheme', { id: selectedId, theme: Number(el.dataset.arg) }),

        pcAdopt: () => nuiCallback('pcAdopt', { id: selectedId }),
        pcKeepMine: () => nuiCallback('pcResolve', { id: selectedId, mode: 'keep' }),
        pcUsePack: async () => {
            const ok = await WP.confirm({
                title: 'Use the pack\'s version?',
                body: 'Your change to this unit is dropped, for every property that uses it.',
                confirmLabel: 'Use the pack\'s', danger: true,
            });
            if (ok) nuiCallback('pcResolve', { id: selectedId, mode: 'pack' });
        },
    },
});
