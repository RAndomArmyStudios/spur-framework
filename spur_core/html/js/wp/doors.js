// ========================================
// /whip SECTION — Doors
//
// The Door Manager half of the old doors.js on the WP vocabulary; the Door Editor HUD
// half lives on as html/js/door-editor.js (shows while this panel is suspended).
//
// Same protocol split as wp/zones.js: mutation callbacks in tools/zones.lua answer
// with the LEGACY 'dmRefresh' router action, registered here; fresh 'all' payloads
// arrive via wpSectionData on section enter and on editor exit.
//
// A door's page is a column of rows, each one thing and how it stands, its control on the
// row's right edge: its state (Lock / Unlock), where it is (Teleport), what it is linked to, who
// manages it; whether it locks itself and can be picked; and who can lock and unlock it — jobs, on
// duty only, an ACE, some characters, keys — every one a row, every toggle an on/off chip. The list
// is grouped under its folders.
//
// A NEW DOOR IS SET UP WITH A WIZARD, WP.stepper in the list's place as the garage and shop wizards are:
//
//   Door     picked in the world: the door editor opens to pick it (tools/zones.lua, "Picking for the wizard"),
//            one leaf, or both leaves of a double door (linked: they open and lock together)
//   Name     what the list calls it, and its folder (one it has, or a new one)
//   Locking  starts locked or open, locks itself after a while, can be picked
//   Access   who can lock and unlock it: anyone, or some people — jobs, on duty only, an ACE, characters
//   Create   the lot, checked: spur_core:doorWizardCreate, and the page opens on the new door
//
// The editor's quick way stays (Open the editor: G saves whatever is aimed at as a plain door).
// ========================================

import { NuiRouter } from '../router.js';
import { nuiCallback } from '../utils.js';
import { WhipPanel, WP } from '../whip-panel.js';
import { personSearch } from './pickers.js';

let doors = [];
let selectedId = null;   // numeric doorId
let search = '';
let els = {};
let built = false;       // render() has run: onData may draw

let draft = null;        // the door being set up, while the wizard is open
let wiz = null;          // its WP.stepper
let wizAt = 'door';      // the step it is on, so the panel reopens there
let jobs = null;         // dwJobs: [{ key, name }], read once
let jobsAsk = null;
let pendingSelect = null;   // a door the wizard just made: opened once the list has it
// The list's folders that are shut ('' = No folder). Module state, so they stay as left across
// visits to the section until spur_core restarts. searchShut: the same while a search is typed.
const closedFolders = new Set();
const searchShut = new Set();

// A folder heading's caret, the shell's group one: points right while shut, turned down when open.
const CARET = '<svg viewBox="0 0 16 16" width="16" height="16" fill="none" stroke="currentColor"'
    + ' stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 3l5 5-5 5"/></svg>';

/** A Lua list from the bridge: an empty one can arrive as {} rather than []. */
function listOf(v) {
    return Array.isArray(v) ? v : (v && typeof v === 'object' ? Object.values(v) : []);
}

function findDoor(id) {
    return doors.find((d) => d.doorId === id);
}

// A door a system manages (a property's front door) carries metadata.managedBy; its access is
// that system's to set, and the server refuses edits from here. See "Managed doors" in
// server/doors.lua.
function managerOf(d) {
    const mb = d && d.metadata && d.metadata.managedBy;
    return mb && typeof mb === 'object' ? mb : null;
}

function managerName(mb) {
    return mb.label || ((mb.system || '?') + ' #' + mb.id);
}

// A satellite's doors ('resource:<name>'), which the Door Manager may release once that
// resource is gone. spur_core's own systems release theirs from their own panels.
function managerResource(mb) {
    const m = /^resource:(.+)$/.exec(mb.system || '');
    return m ? m[1] : null;
}

// ---- adopt ----

function adopt(list) {
    doors = list || [];
    if (!built) return;
    // A door the wizard just made: its page, once the list has it.
    if (pendingSelect != null && findDoor(pendingSelect) && !wizardOpen()) {
        const id = pendingSelect;
        pendingSelect = null;
        selectDoor(id);
        return;
    }
    renderList();
    const d = selectedId != null && findDoor(selectedId);
    if (d) renderDetail(d);
    else if (selectedId != null) clearDetail();
}

// ---- list: grouped under its folders, loose doors last ----

function renderList() {
    els.list.innerHTML = '';
    let filtered = doors;
    if (search) {
        filtered = doors.filter((d) =>
            (d.label || '').toLowerCase().includes(search) ||
            (d.folder || '').toLowerCase().includes(search) ||
            String(d.doorId).includes(search));
    }

    const sorted = [...filtered].sort((a, b) => {
        const fa = a.folder || '￿', fb = b.folder || '￿';
        if (fa !== fb) return fa < fb ? -1 : 1;
        return a.doorId - b.doorId;
    });

    // One heading per folder that opens and closes it. Loose doors go last,
    // under "No folder". While searching, every folder with a match shows open — a search never
    // hides what it found — and a heading closed during the search reopens when the search changes.
    const byFolder = new Map();
    for (const d of sorted) {
        const f = d.folder || '';
        if (!byFolder.has(f)) byFolder.set(f, []);
        byFolder.get(f).push(d);
    }
    const shut = search ? searchShut : closedFolders;
    for (const [f, list] of byFolder) {
        const open = !shut.has(f);
        const head = WP.el('button', 'wp-list-folder' + (open ? ' open' : ''));
        head.type = 'button';
        head.dataset.action = 'dmToggleFolder';
        head.dataset.arg = f;
        head.setAttribute('aria-expanded', open ? 'true' : 'false');
        const caret = WP.el('span', 'wp-group-caret');
        caret.innerHTML = CARET;   // a fixed icon, no data
        head.appendChild(caret);
        head.appendChild(WP.el('span', 'wp-list-folder-name', f || 'No folder'));
        const locked = list.filter((d) => d.locked).length;
        head.appendChild(WP.el('span', 'wp-list-folder-count',
            list.length + (locked && locked < list.length ? '  ·  ' + locked + ' locked' : locked ? '  ·  all locked' : '')));
        els.list.appendChild(head);
        if (open) for (const d of list) els.list.appendChild(doorRow(d));
    }

    if (sorted.length === 0) {
        els.list.appendChild(WP.empty(search ? 'No doors match "' + search + '"' : 'No doors saved'));
    }
    els.count.textContent = sorted.length + ' of ' + doors.length + ' door' + (doors.length !== 1 ? 's' : '');
    // "Close all" while any folder shows open, else "Open all".
    els.shownFolders = [...byFolder.keys()];
    const anyOpen = els.shownFolders.some((f) => !shut.has(f));
    els.foldAll.textContent = anyOpen ? 'Close all' : 'Open all';
    els.foldAll.hidden = byFolder.size < 2;
}

function doorRow(d) {
    const subBits = ['#' + d.doorId];
    if (d.linkedDoorId) subBits.push('linked to #' + d.linkedDoorId);
    const mb = managerOf(d);
    if (mb) subBits.push(managerName(mb));
    const item = WP.listItem({
        title: d.label || 'Door',
        sub: subBits.join(' · '),
        pill: d.locked ? 'LOCKED' : 'OPEN',
        pillClass: '',   // a plain state: LOCKED is neutral everywhere, as on containers and phones
        id: d.doorId,
        action: 'dmSelect',
    });
    if (d.doorId === selectedId) item.classList.add('active');
    return item;
}

// ---- detail ----

function clearDetail() {
    selectedId = null;
    els.detailTitle.textContent = 'Doors';
    els.detailBody.innerHTML = '';
    els.detailBody.appendChild(WP.el('div', 'wp-hint',
        'Pick a door to lock it, find it, or change who can unlock it. Or set a new one up: the wizard walks you '
        + 'through picking it in the world (a double door too), its name, how it locks, and who can open it.'));
    const go = WP.el('div', 'wp-actions-row');
    go.appendChild(WP.btn('Set up a new door', 'dwNew', 'primary'));
    els.detailBody.appendChild(go);
}

/** An on/off chip: the house's toggle (.wp-toggle), its state in its words. */
function toggle(label, on, action) {
    const b = WP.el('button', 'wp-toggle' + (on ? ' active' : ''), label + (on ? ' · on' : ' · off'));
    b.type = 'button';
    b.dataset.action = action;
    return b;
}

/** A text box for a row's right edge, saved when it is left (change): a field capsule with no
 *  label of its own (the row names it), or `unit` after the value ('seconds'). */
function rowInput(value, placeholder, action, type, unit) {
    const i = WP.input({ value: value === undefined || value === null ? '' : value, placeholder, type });
    i.dataset.change = action;
    const f = WP.el('label', 'wp-field');
    f.appendChild(i);
    if (unit) {
        i.classList.add('wp-input-short');
        f.appendChild(WP.el('span', 'wp-field-label', unit));
    } else {
        f.style.width = '260px';
    }
    return { field: f, input: i };
}

/** A row's button, at the row's height. */
function rowBtn(label, action, kind, id) {
    const b = WP.btn(label, action, kind || 'ghost');
    if (id != null) b.dataset.id = id;
    return b;
}

function renderDetail(d) {
    els.detailTitle.textContent = d.label || ('Door #' + d.doorId);
    const body = els.detailBody;
    body.innerHTML = '';
    const mb = managerOf(d);
    const req = d.requirements || {};

    body.appendChild(WP.el('div', 'wp-item-sub', 'Door #' + d.doorId + '  ·  model ' + d.model
        + (d.folder ? '  ·  in ' + d.folder : '')));

    // ---- the door ----
    body.appendChild(WP.statusRow({ label: 'State', status: d.locked ? 'err' : 'ok',
        detail: d.locked ? 'locked' : 'unlocked',
        control: [rowBtn(d.locked ? 'Unlock' : 'Lock', 'dmToggleLock', 'primary')] }));
    body.appendChild(WP.statusRow({ label: 'Where', status: 'ok', detail: 'on the map',
        control: [rowBtn('Teleport', 'dmTeleport')] }));
    body.appendChild(WP.place({ x: d.x, y: d.y, name: d.label || 'The door' }));
    if (d.linkedDoorId) {
        const other = findDoor(d.linkedDoorId);
        const controls = [rowBtn('Show', 'dmSelect', 'ghost', d.linkedDoorId)];
        // A managed door's link is its manager's to change.
        if (!mb) controls.push(rowBtn('Unlink', 'dmUnlink'));
        body.appendChild(WP.statusRow({ label: 'Linked to', status: 'ok',
            detail: '#' + d.linkedDoorId + (other && other.label ? '  ·  ' + other.label : '') + '  ·  they open and lock together',
            control: controls }));
    }
    if (mb) {
        body.appendChild(WP.statusRow({ label: 'Managed by', status: 'warn',
            detail: managerName(mb) + (mb.key ? '  ·  ' + mb.key : '') }));
    }

    // ---- its name and folder ----
    const idRow = WP.el('div', 'wp-cols-2 wp-apart');
    const nameInput = WP.input({ value: d.label || '' });
    nameInput.dataset.change = 'dmSetLabel';
    idRow.appendChild(WP.field('Name', nameInput));
    const folderInput = WP.input({ value: d.folder || '', placeholder: 'none' });
    folderInput.dataset.change = 'dmSetFolder';
    idRow.appendChild(WP.field('Folder', folderInput));
    body.appendChild(idRow);

    // Who can unlock it, and when it locks itself, are the manager's to set: it writes them back every
    // time it reconciles. The name and folder above stay editable.
    if (mb) {
        const res = managerResource(mb);
        body.appendChild(WP.el('div', 'wp-hint', res
            ? 'Who can unlock it and when it locks itself are set by the ' + res + ' resource. Release gives the '
              + 'door back as it was, and only works while ' + res + ' is stopped.'
            : 'Who can unlock it and when it locks itself are set by ' + managerName(mb) + '. Change them there.'));
        if (res) {
            const actions = WP.el('div', 'wp-actions-row');
            actions.appendChild(WP.btn('Release', 'dmRelease', 'danger'));
            body.appendChild(actions);
        }
        return;
    }

    // ---- locking ----
    body.appendChild(WP.el('div', 'wp-section-title', 'Locking'));
    const lockControls = [];
    if (d.autolock) {
        const delay = rowInput(d.autolockDelay || 10, '10', 'dmSetAutolockDelay', 'number', 'seconds');
        delay.input.min = 1;
        delay.input.max = 300;
        lockControls.push(delay.field);
    }
    lockControls.push(toggle('Locks itself', !!d.autolock, 'dmToggleAutolock'));
    // A press or a script unlocking it starts the clock; a pick does not (server/doors.lua, M48).
    body.appendChild(WP.statusRow({ label: 'Auto-lock', status: d.autolock ? 'ok' : 'off',
        detail: d.autolock ? 'locks again ' + (d.autolockDelay || 10) + ' s after someone unlocks it'
            + (req.lockpick ? ' (a picked door stays open)' : '') : 'stays as it is left',
        control: lockControls }));
    // Not an access rule: a pick is its own way in (server/doors.lua, "The lockpick").
    body.appendChild(WP.statusRow({ label: 'Lockpick', status: req.lockpick ? 'warn' : 'off',
        detail: req.lockpick ? 'anyone carrying a lockpick can try to pick it' : 'cannot be picked',
        control: [toggle('Can be picked', !!req.lockpick, 'dmToggleLockpick')] }));

    // ---- who can lock and unlock it (Doors.requirementsMet: any one rule that matches will do) ----
    body.appendChild(WP.el('div', 'wp-section-title', 'Who can lock and unlock it'));
    const jobs = listOf(req.jobs);
    const chars = listOf(req.charIds);
    const items = listOf(req.items);
    // A character or key list that is THERE but empty names nobody, and the server keeps it so
    // (normaliseRequirements): a rule nobody matches. An empty job list it drops.
    const charsNobody = req.charIds != null && chars.length === 0;
    const itemsNobody = req.items != null && items.length === 0;
    const anyRule = jobs.length || req.onDuty || req.ace || chars.length || items.length || charsNobody || itemsNobody;
    body.appendChild(WP.el('div', 'wp-hint', anyRule
        ? 'Anyone who matches any one of these can.'
        : req.lockpick
            ? 'Nothing set below, and it can be picked: nobody can unlock it but with a lockpick.'
            : 'Nothing set below: everybody can.'));
    body.appendChild(WP.statusRow({ label: 'Jobs', status: jobs.length ? 'ok' : 'off',
        detail: jobs.length ? 'whoever works at ' + jobs.join(', ') : 'no job named',
        control: [rowInput(jobs.join(', '), 'e.g. police, ems', 'dmSetReqJobs').field] }));
    body.appendChild(WP.statusRow({ label: 'On duty only', status: req.onDuty ? 'ok' : 'off', sub: true,
        detail: req.onDuty ? (jobs.length ? 'and only while on duty there' : 'anyone on duty at any job') : 'on duty or not',
        control: [toggle('On duty', !!req.onDuty, 'dmToggleReqOnDuty')] }));
    body.appendChild(WP.statusRow({ label: 'Permission', status: req.ace ? 'ok' : 'off',
        detail: req.ace ? 'whoever has the ' + req.ace + ' permission' : 'no permission named',
        control: [rowInput(req.ace || '', 'e.g. whip.admin', 'dmSetReqAce').field] }));
    body.appendChild(WP.statusRow({ label: 'Characters', status: charsNobody ? 'err' : chars.length ? 'ok' : 'off',
        detail: charsNobody ? 'an empty list: no character matches'
            : chars.length ? 'character' + (chars.length === 1 ? ' ' : 's ') + chars.map((c) => '#' + c).join(', ') : 'nobody by name',
        control: [rowInput(chars.join(', '), 'e.g. 1, 5', 'dmSetReqChars').field] }));
    // Keys are set by the resource that made the door (no box for them here); shown so the list is whole.
    if (items.length || itemsNobody) {
        const keyName = (it) => (typeof it === 'string' ? it : (it && (it.key || it.item)) || '?');
        body.appendChild(WP.statusRow({ label: 'Keys', status: itemsNobody ? 'err' : 'ok',
            detail: itemsNobody ? 'an empty list: no key matches'
                : 'whoever carries ' + items.map((it) => (it && it.count > 1 ? it.count + '× ' : '') + keyName(it)).join(' or ') }));
    }

    // Destructive far left, on its own row at the foot.
    const actions = WP.el('div', 'wp-actions-row wp-apart');
    actions.appendChild(WP.btn('Delete', 'dmDelete', 'danger'));
    body.appendChild(actions);
}

function selectDoor(id) {
    const d = findDoor(id);
    if (!d) return;
    selectedId = id;
    // A door reached from elsewhere (a linked door's Show) opens its folder, so its row is seen.
    closedFolders.delete(d.folder || '');
    searchShut.delete(d.folder || '');
    renderDetail(d);
    renderList();
}

// ========================================
// THE WIZARD (see the header)
// ========================================

const STEPS = [
    { key: 'door', label: 'Door' }, { key: 'name', label: 'Name' }, { key: 'locking', label: 'Locking' },
    { key: 'access', label: 'Access' }, { key: 'review', label: 'Create' },
];

function newDraft() {
    return {
        leaves: [],                                   // { model, x, y, z, heading }: one, or two for a double door
        label: '', folder: '',
        locked: true, autolock: false, autolockDelay: 10, lockpick: false,
        access: 'anyone',                             // 'anyone' | 'some'
        jobs: [], onDuty: false, ace: '', chars: [],  // chars: { charId, name }
        saving: false,
    };
}

function wizardOpen() { return !!draft; }

/** The list, or the wizard while a door is being set up. */
function showView() {
    if (!els.listView) return;
    els.listView.style.display = wizardOpen() ? 'none' : '';
    els.wizView.style.display = wizardOpen() ? '' : 'none';
}

function loadJobs() {
    if (jobs || jobsAsk) return;
    jobsAsk = Promise.resolve(nuiCallback('dwJobs', {})).then((res) => {
        jobsAsk = null;
        jobs = Array.isArray(res) ? res : [];
        if (wiz && wiz.current() === 'access') redrawStep();
    });
}

function openWizard() {
    draft = newDraft();
    loadJobs();
    buildWizard('door');
    showView();
}

function closeWizard() {
    draft = null;
    wiz = null;
    wizAt = 'door';
    if (els.wizBody) els.wizBody.innerHTML = '';
    showView();
}

async function discardWizard() {
    if (draft && (draft.leaves.length || draft.label.trim())) {
        const ok = await WP.confirm({
            title: 'Throw this door away?',
            body: 'Nothing has been saved yet: the door in the world stays as it is.',
            confirmLabel: 'Throw away', danger: true,
        });
        if (!ok) return;
    }
    closeWizard();
}

function buildWizard(at) {
    els.wizBody.innerHTML = '';
    wiz = WP.stepper({
        id: 'dw-wizard',
        steps: STEPS,
        onGo: (k, from, body) => { wizAt = k; fillStep(k, body); },
        canLeave: (from) => canLeave(from),
        onFinish: finish,
        finishLabel: 'Create door',
    });
    els.wizBody.appendChild(wiz.root);
    wiz.start(STEPS.some((s) => s.key === at) ? at : 'door');
    renderWizHead();
}

function renderWizHead() {
    const name = draft && draft.label.trim();
    els.wizTitle.textContent = (draft && draft.leaves.length === 2 ? 'New double door' : 'New door') + (name ? ' — ' + name : '');
}

function fillStep(key, body) {
    if (!draft) return;
    body.innerHTML = '';
    const fill = { door: stepDoor, name: stepName, locking: stepLocking, access: stepAccess, review: stepReview }[key];
    if (fill) fill(body);
}

function redrawStep() {
    if (wiz && wiz.current()) fillStep(wiz.current(), wiz.body);
}

/** A step just answered: the refusal its Next left is wrong now. */
function answered(key) {
    if (!wiz) return;
    wiz.say('');
    wiz.setStatus(key, null);
}

function hint(body, text) {
    const el = WP.el('div', 'wp-hint', text);
    body.appendChild(el);
    return el;
}

function choice(action, arg, active, title, text) {
    const b = WP.el('button', 'wp-choice' + (active ? ' active' : ''));
    b.type = 'button';
    b.dataset.action = action;
    b.dataset.arg = arg;
    b.appendChild(WP.el('span', 'wp-choice-title', title));
    b.appendChild(WP.el('span', 'wp-choice-text', text));
    return b;
}

function chip(label, on, action, arg) {
    const b = WP.el('button', 'wp-toggle' + (on ? ' active' : ''), label);
    b.type = 'button';
    b.dataset.action = action;
    if (arg !== undefined) b.dataset.arg = arg;
    return b;
}


function smallBtn(label, action, arg) {
    const b = WP.btn(label, action, 'ghost', arg);
    b.classList.add('wp-btn-sm');
    return b;
}

// ---- step: door ----

function stepDoor(body) {
    hint(body, 'Pick it in the world: the panel steps aside and the door editor opens. Aim at the door and press G '
        + '(A on a pad) to take it, then Enter (☰) to come back. A double door: take its other leaf too, and the two '
        + 'open and lock together. Nothing in the world changes until Create.');
    const n = draft.leaves.length;
    if (!n) body.appendChild(WP.statusRow({ label: 'Door', status: 'todo', detail: 'not picked yet' }));
    draft.leaves.forEach((l, i) => {
        body.appendChild(WP.statusRow({ label: n > 1 ? 'Leaf ' + (i + 1) : 'Door', status: 'ok',
            detail: 'model ' + l.model, control: [smallBtn('Teleport', 'dwTeleport', i)] }));
    });
    if (n) body.appendChild(WP.place({ x: draft.leaves[0].x, y: draft.leaves[0].y, name: draft.label.trim() || 'The door' }));
    if (n === 2) hint(body, 'A double door: the two leaves are linked, so they open and lock together.');
    const row = WP.el('div', 'wp-actions-row');
    row.appendChild(WP.btn(n ? 'Pick again' : 'Pick it in the world', 'dwPick', 'primary'));
    body.appendChild(row);
}

// ---- step: name ----

function folders() {
    return [...new Set(doors.map((d) => d.folder).filter(Boolean))].sort((a, b) => a.localeCompare(b));
}

function stepName(body) {
    const name = WP.input({ placeholder: 'e.g. Jail front door', value: draft.label, inputAction: 'dwLabel' });
    name.maxLength = 100;
    body.appendChild(WP.field('Name', name, true));
    setTimeout(() => name.focus(), 0);
    hint(body, 'What the Doors list calls it. Its folder keeps it with the others of a place (a police station, a '
        + 'house): pick one it has, or type a new one. A folder is optional.');
    const folder = WP.input({ placeholder: 'none', value: draft.folder, inputAction: 'dwFolder' });
    folder.maxLength = 100;
    els.dwFolder = folder;
    body.appendChild(WP.field('Folder', folder, true));
    const list = folders();
    if (list.length) {
        const row = WP.el('div', 'wp-toggles wp-near');
        for (const f of list) row.appendChild(chip(f, draft.folder === f, 'dwFolderPick', f));
        body.appendChild(row);
    }
}

// ---- step: locking ----

function stepLocking(body) {
    const row = WP.el('div', 'wp-choices');
    row.appendChild(choice('dwLocked', 'locked', draft.locked, 'Starts locked', 'Locked from the moment it is saved.'));
    row.appendChild(choice('dwLocked', 'open', !draft.locked, 'Starts unlocked',
        'Open from the moment it is saved, until someone locks it.'));
    body.appendChild(row);

    body.appendChild(WP.el('div', 'wp-section-title', 'Locking'));
    const controls = [];
    if (draft.autolock) {
        const i = WP.input({ type: 'number', value: draft.autolockDelay, inputAction: 'dwDelay' });
        i.min = 1;
        i.max = 300;
        i.classList.add('wp-input-short');
        const f = WP.el('label', 'wp-field');
        f.appendChild(i);
        f.appendChild(WP.el('span', 'wp-field-label', 'seconds'));
        controls.push(f);
    }
    body.appendChild(WP.statusRow({ label: 'Locks itself', yesNo: { on: draft.autolock, action: 'dwAutolock' },
        detail: draft.autolock ? 'locks again this long after someone unlocks it' : 'stays as it is left',
        control: controls.length ? controls : undefined }));
    body.appendChild(WP.statusRow({ label: 'Can be picked', yesNo: { on: draft.lockpick, action: 'dwLockpick' },
        detail: draft.lockpick ? 'anyone carrying a lockpick can try (a picked door stays open)' : 'a lockpick does nothing' }));
}

// ---- step: access ----

function stepAccess(body) {
    const row = WP.el('div', 'wp-choices');
    // With nobody named, a door that can be picked opens for nobody but a pick (server/doors.lua requirementsMet).
    row.appendChild(draft.lockpick
        ? choice('dwAccess', 'anyone', draft.access === 'anyone', 'Nobody but a lockpick',
            'It can be picked (Locking) and nobody is named, so only a pick gets it open.')
        : choice('dwAccess', 'anyone', draft.access === 'anyone', 'Anyone', 'Everybody can lock and unlock it.'));
    row.appendChild(choice('dwAccess', 'some', draft.access === 'some', 'Only some people',
        'Whoever has one of the jobs, the permission or is one of the characters you name here.'));
    body.appendChild(row);
    if (draft.access !== 'some') return;

    hint(body, 'Anyone who matches any one of these can.').classList.add('wp-after');

    body.appendChild(WP.el('div', 'wp-section-title', 'Jobs'));
    if (!jobs) {
        loadJobs();
        body.appendChild(WP.empty('Reading the jobs…'));
    } else if (!jobs.length) {
        hint(body, 'There are no jobs yet: make them in Jobs.');
    } else {
        const list = WP.el('div', 'wp-toggles wp-toggles-many');
        for (const j of jobs) list.appendChild(chip(j.name || j.key, draft.jobs.includes(j.key), 'dwJob', j.key));
        body.appendChild(list);
    }
    body.appendChild(WP.statusRow({ label: 'On duty only', yesNo: { on: draft.onDuty, action: 'dwOnDuty' },
        detail: draft.onDuty ? (draft.jobs.length ? 'and only while on duty there' : 'anyone on duty at any job')
            : 'on duty or not' }));

    body.appendChild(WP.el('div', 'wp-section-title', 'Permission'));
    const ace = WP.input({ placeholder: 'e.g. whip.admin, as written in server.cfg', value: draft.ace, inputAction: 'dwAce' });
    body.appendChild(WP.field('Permission name', ace, true));

    body.appendChild(WP.el('div', 'wp-section-title', 'Characters'));
    if (draft.chars.length) {
        const list = WP.el('div', 'wp-toggles wp-near-next');
        for (const c of draft.chars) {
            const b = chip(c.name + '  ·  #' + c.charId + '  ✕', true, 'dwCharRemove', c.charId);
            b.title = 'Take ' + c.name + ' off';
            list.appendChild(b);
        }
        body.appendChild(list);
    }
    const find = personSearch({
        placeholder: 'Add a character: type a name or an id…',
        skip: (charId) => draft.chars.some((c) => c.charId === charId),
        onPick: (p) => { draft.chars.push({ charId: p.charId, name: p.name }); answered('access'); redrawStep(); },
    });
    body.appendChild(find.root);
}

// ---- step: create ----

function accessRules(d) {
    if (d.access !== 'some') return [];
    const out = [];
    if (d.jobs.length) {
        const names = d.jobs.map((k) => { const j = (jobs || []).find((x) => x.key === k); return j ? j.name || k : k; });
        out.push(names.join(', ') + (d.onDuty ? ' (on duty)' : ''));
    } else if (d.onDuty) {
        out.push('anyone on duty');
    }
    if (d.ace.trim()) out.push('the ' + d.ace.trim() + ' permission');
    if (d.chars.length) out.push(d.chars.map((c) => c.name).join(', '));
    return out;
}

function stepReview(body) {
    const d = draft;
    const row = (label, key, status, detail) =>
        body.appendChild(WP.statusRow({ label, status, detail, action: 'dwJump', arg: key, actionLabel: 'Change' }));
    row('Door', 'door', d.leaves.length ? 'ok' : 'err', !d.leaves.length ? 'not picked'
        : d.leaves.length === 2 ? 'a double door: two leaves, linked' : 'one door');
    if (d.leaves.length) body.appendChild(WP.place({ x: d.leaves[0].x, y: d.leaves[0].y, name: d.label.trim() || 'The door' }));
    row('Name', 'name', d.label.trim() ? 'ok' : 'err', d.label.trim()
        ? d.label.trim() + (d.folder.trim() ? '  ·  in ' + d.folder.trim() : '  ·  no folder') : 'no name yet');
    row('Locking', 'locking', 'ok', (d.locked ? 'starts locked' : 'starts unlocked')
        + (d.autolock ? '  ·  locks itself after ' + d.autolockDelay + ' s' : '') + (d.lockpick ? '  ·  can be picked' : ''));
    const rules = accessRules(d);
    row('Access', 'access', 'ok', d.access === 'some' ? 'only ' + rules.join(' or ')
        : d.lockpick ? 'nobody but a lockpick' : 'anyone');
    hint(body, 'Create saves it at once, and its page opens.').classList.add('wp-apart');
}

// ---- leaving a step, and creating ----

function canLeave(from) {
    const d = draft;
    if (!d) return 'There is no door being set up';
    if (from === 'door') return d.leaves.length ? true : 'Pick the door in the world';
    if (from === 'name') return d.label.trim() ? true : 'Give it a name';
    if (from === 'locking') {
        const n = Number(d.autolockDelay);
        if (d.autolock && !(n >= 1 && n <= 300 && n === Math.floor(n))) return 'It locks itself after 1 to 300 seconds';
        return true;
    }
    if (from === 'access') return d.access !== 'some' || accessRules(d).length ? true : 'Name who can, or let anyone';
    return true;
}

function finish() {
    const d = draft;
    if (!d || d.saving) return;
    for (const s of STEPS) {
        if (s.key === 'review') continue;
        const why = canLeave(s.key);
        if (why !== true) { wiz.setStatus(s.key, 'error'); wiz.say(why, 'err'); return; }
    }
    const req = {};
    if (d.access === 'some') {
        if (d.jobs.length) req.jobs = d.jobs.slice();
        if (d.onDuty) req.onDuty = true;
        if (d.ace.trim()) req.ace = d.ace.trim();
        if (d.chars.length) req.charIds = d.chars.map((c) => c.charId);
    }
    if (d.lockpick) req.lockpick = true;
    const payload = {
        leaves: d.leaves, label: d.label.trim(), folder: d.folder.trim(),
        locked: d.locked, autolock: d.autolock, autolockDelay: Number(d.autolockDelay) || 10,
        requirements: Object.keys(req).length ? req : undefined,
    };
    d.saving = true;
    wiz.say('Creating…');
    nuiCallback('dwCreate', payload).then((res) => {
        if (draft !== d) return;
        d.saving = false;
        if (!res || res.ok !== true) {   // {} is a call that never reached the server: not a success
            wiz.say((res && res.why) || 'The door was not saved', 'err');
            return;
        }
        // Its page opens when the list arrives with it (dmRefresh, sent after the answer).
        pendingSelect = Array.isArray(res.doorIds) ? res.doorIds[0] : null;
        WP.result(res.doorIds && res.doorIds.length === 2
            ? 'Double door saved: #' + res.doorIds[0] + ' and #' + res.doorIds[1]
            : 'Door saved: #' + (res.doorIds && res.doorIds[0]), 'ok');
        closeWizard();
        if (pendingSelect != null && findDoor(pendingSelect)) adopt(doors);
    });
}

// ---- section ----

WhipPanel.registerSection({
    id: 'doors',
    group: 'world',
    label: 'Doors',
    order: 30,

    render(root) {
        els = {};
        built = false;

        // ---- the wizard, in the list's place while a door is set up. First in the section, as the garage
        // wizard's is (the shell's '/' takes the first search). ----
        els.wizView = WP.el('div', 'wp-section-solo wp-section-wide');
        els.wizView.style.display = 'none';
        const head = WP.el('div', 'wp-actions-row wp-head-row');
        els.wizTitle = WP.el('div', 'wp-pane-title', 'New door');
        head.appendChild(els.wizTitle);
        head.appendChild(WP.el('span', 'wp-actions-split'));
        head.appendChild(WP.btn('Discard', 'dwDiscard', 'ghost'));
        els.wizView.appendChild(head);
        els.wizBody = WP.el('div', 'wp-view');
        els.wizView.appendChild(els.wizBody);
        root.appendChild(els.wizView);

        els.listView = WP.el('div', 'wp-view');
        root.appendChild(els.listView);
        root = els.listView;
        root.appendChild(WP.toolbar({
            left: [WP.btn('+ New Door', 'dwNew'), WP.btn('Open the editor', 'dmEnterEditor', 'ghost')],
            search: { inputAction: 'dmSearch', placeholder: 'Search doors…' },
        }));

        const split = WP.el('div', 'wp-split');
        const listCol = WP.el('div', 'wp-list-col');
        const countRow = WP.el('div', 'wp-list-folder-bar');
        els.count = WP.el('div', 'wp-list-count', '');
        countRow.appendChild(els.count);
        els.foldAll = WP.btn('Close all', 'dmFoldAll', 'ghost');
        els.foldAll.classList.add('wp-btn-sm');
        countRow.appendChild(els.foldAll);
        listCol.appendChild(countRow);
        els.list = WP.el('div', 'wp-list');
        listCol.appendChild(els.list);
        split.appendChild(listCol);

        const detail = WP.el('div', 'wp-detail');
        els.detailTitle = WP.el('div', 'wp-pane-title', 'Doors');
        detail.appendChild(els.detailTitle);
        els.detailBody = WP.el('div');
        detail.appendChild(els.detailBody);
        split.appendChild(detail);
        root.appendChild(split);
        clearDetail();

        built = true;
        // The panel is built again each time it opens: a door half set up comes back where it was.
        if (draft) buildWizard(wizAt);
        showView();
    },

    onData(kind, payload) {
        if (!built) return;
        if (kind === 'all') adopt(payload.doors);
        else if (kind === 'wizPick' && draft) {
            // The editor's pick (tools/zones.lua dwPick): the leaves taken, or none when it went Back.
            if (Array.isArray(payload.leaves)) {
                draft.leaves = payload.leaves.filter((l) => l && Number.isFinite(Number(l.x))).slice(0, 2).map((l) => ({
                    model: Number(l.model), x: Number(l.x), y: Number(l.y), z: Number(l.z), heading: Number(l.heading) || 0,
                }));
                if (draft.leaves.length) answered('door');
                renderWizHead();
            }
            if (wiz && wiz.current() === 'door') redrawStep();
        }
    },

    onEscape() {
        if (wizardOpen()) {
            // A step back at a time; on the first, Escape offers to throw it away.
            if (!(wiz && wiz.escape())) discardWizard();
            return true;
        }
        if (selectedId !== null) { clearDetail(); renderList(); return true; }
        return false;
    },

    actions: {
        dmSearch: (el) => { search = el.value.toLowerCase(); searchShut.clear(); renderList(); },
        dmToggleFolder: (el) => {
            const shut = search ? searchShut : closedFolders;
            const f = el.dataset.arg || '';
            if (shut.has(f)) shut.delete(f); else shut.add(f);
            renderList();
        },
        dmFoldAll: () => {
            const shut = search ? searchShut : closedFolders;
            const folders = els.shownFolders || [];   // the folders the list shows now (renderList)
            const anyOpen = folders.some((f) => !shut.has(f));
            if (anyOpen) for (const f of folders) shut.add(f);
            else shut.clear();
            renderList();
        },
        dmSelect: (el) => selectDoor(Number(el.dataset.id)),
        dmEnterEditor: () => nuiCallback('dmEnterEditor', {}),

        // ---- the wizard ----
        dwNew: () => openWizard(),
        dwDiscard: () => discardWizard(),
        dwJump: (el) => { if (wiz) wiz.jump(el.dataset.arg); },
        dwPick: () => {
            if (!draft) return;
            nuiCallback('dwPick', { leaves: draft.leaves }).then((res) => {
                if (res && res.ok === false && wiz) wiz.say(res.why || 'The door editor could not open', 'err');
            });
        },
        dwTeleport: (el) => {
            const l = draft && draft.leaves[Number(el.dataset.arg)];
            if (l) nuiCallback('dwTeleport', l);
        },
        dwLabel: (el) => {
            if (!draft) return;
            draft.label = el.value;
            if (el.value.trim()) answered('name');
            renderWizHead();
        },
        dwFolder: (el) => {
            if (!draft) return;
            draft.folder = el.value;
            // The chips follow what is typed.
            for (const b of el.closest('.wp-step-body').querySelectorAll('[data-action="dwFolderPick"]')) {
                b.classList.toggle('active', b.dataset.arg === el.value.trim());
            }
        },
        dwFolderPick: (el) => {
            if (!draft) return;
            draft.folder = draft.folder === el.dataset.arg ? '' : el.dataset.arg;
            redrawStep();
        },
        dwLocked: (el) => { if (draft) { draft.locked = el.dataset.arg !== 'open'; redrawStep(); } },
        dwAutolock: () => { if (draft) { draft.autolock = !draft.autolock; answered('locking'); redrawStep(); } },
        dwDelay: (el) => { if (draft) draft.autolockDelay = el.value; },
        dwLockpick: () => { if (draft) { draft.lockpick = !draft.lockpick; redrawStep(); } },
        dwAccess: (el) => {
            if (!draft) return;
            draft.access = el.dataset.arg === 'some' ? 'some' : 'anyone';
            if (draft.access === 'anyone') answered('access');
            redrawStep();
        },
        dwJob: (el) => {
            if (!draft) return;
            const k = el.dataset.arg;
            draft.jobs = draft.jobs.includes(k) ? draft.jobs.filter((x) => x !== k) : draft.jobs.concat([k]);
            answered('access');
            redrawStep();
        },
        dwOnDuty: () => { if (draft) { draft.onDuty = !draft.onDuty; answered('access'); redrawStep(); } },
        dwAce: (el) => { if (draft) { draft.ace = el.value; if (el.value.trim()) answered('access'); } },
        dwCharRemove: (el) => {
            if (!draft) return;
            draft.chars = draft.chars.filter((c) => c.charId !== Number(el.dataset.arg));
            redrawStep();
        },
        dmToggleLock: () => { if (selectedId != null) nuiCallback('dmToggleLock', { doorId: selectedId }); },
        dmTeleport: () => { if (selectedId != null) nuiCallback('dmTeleport', { doorId: selectedId }); },
        dmToggleLockpick: () => { if (selectedId != null) nuiCallback('dmToggleLockpick', { doorId: selectedId }); },
        dmToggleAutolock: () => {
            const d = selectedId != null && findDoor(selectedId);
            if (d) nuiCallback('dmUpdateDoor', { doorId: d.doorId, field: 'autolock', value: !d.autolock });
        },
        dmDelete: async () => {
            if (selectedId == null) return;
            const d = findDoor(selectedId);
            const ok = await WP.confirm({
                title: 'Delete door?',
                body: '#' + selectedId + ' "' + ((d && d.label) || 'Door') + '" will be removed permanently.',
                confirmLabel: 'Delete',
                danger: true,
            });
            if (!ok) return;
            nuiCallback('dmDeleteDoor', { doorId: selectedId });
            clearDetail();
        },
        dmUnlink: () => {
            if (selectedId != null) nuiCallback('dmUnlinkDoor', { doorId: selectedId });
        },
        dmRelease: async () => {
            if (selectedId == null) return;
            const d = findDoor(selectedId);
            const mb = managerOf(d);
            if (!mb) return;
            const ok = await WP.confirm({
                title: 'Release door?',
                body: '#' + selectedId + ' stops belonging to ' + managerName(mb) + '. A door it made is '
                    + 'deleted; a door it took over goes back to how it was.',
                confirmLabel: 'Release',
                danger: true,
            });
            if (!ok) return;
            nuiCallback('dmReleaseDoor', { doorId: selectedId });
        },

        // change-driven edits. An emptied folder sends '' — the server reads it as "no folder"
        // (Doors.update). null cannot say it: it arrives in Lua as no key at all, and the update
        // would write nothing.
        dmSetLabel: (el) => {
            if (selectedId != null) nuiCallback('dmUpdateDoor', { doorId: selectedId, field: 'label', value: el.value });
        },
        dmSetFolder: (el) => {
            if (selectedId != null) nuiCallback('dmUpdateDoor', { doorId: selectedId, field: 'folder', value: el.value || '' });
        },
        dmSetAutolockDelay: (el) => {
            if (selectedId == null) return;
            const num = parseInt(el.value, 10);
            if (num > 0) nuiCallback('dmUpdateDoor', { doorId: selectedId, field: 'autolockDelay', value: num });
        },
        dmSetReqJobs: (el) => {
            if (selectedId == null) return;
            const jobs = el.value ? el.value.split(',').map((s) => s.trim()).filter(Boolean) : null;
            nuiCallback('dmSetRequirement', { doorId: selectedId, reqKey: 'jobs', value: jobs && jobs.length ? jobs : null });
        },
        dmToggleReqOnDuty: () => {
            if (selectedId == null) return;
            const d = findDoor(selectedId);
            const on = !!(d && d.requirements && d.requirements.onDuty);
            nuiCallback('dmSetRequirement', { doorId: selectedId, reqKey: 'onDuty', value: on ? null : true });
        },
        dmSetReqAce: (el) => {
            if (selectedId == null) return;
            nuiCallback('dmSetRequirement', { doorId: selectedId, reqKey: 'ace', value: el.value.trim() || null });
        },
        dmSetReqChars: (el) => {
            if (selectedId == null) return;
            const ids = el.value ? el.value.split(',').map((s) => parseInt(s.trim(), 10)).filter((n) => n > 0) : null;
            nuiCallback('dmSetRequirement', { doorId: selectedId, reqKey: 'charIds', value: ids && ids.length ? ids : null });
        },
    },
});

// LEGACY LIVE ACTION — tools/zones.lua's door mutation callbacks answer with this.
NuiRouter.register('dmRefresh', (d) => adopt(d.doors));
