// ========================================
// /whip SECTION — Jobs
//
// The list of jobs on the left; on the right, the picked job's page: what it is called, its ranks,
// who owns it and who works there (each with Change), its business account and the shops it runs.
//
// ONE WIZARD SETS JOBS UP AND CHANGES THEM, as the Shops section's does — WP.stepper in the section's
// place:
//
//   Name    what it is called, and its key (made from the name; fixed once the job exists)
//   Ranks   from a template, then each rank's name, level, what it may do and its share of the
//           business account. The top rank, level 100, is the owner's.
//   Owner   found by name; they hold the top rank and the business account
//   Staff   people found by name, each given a rank; on a job that exists, moved or let go
//   Create / Save
//
// + New Job starts it empty. Change on a job's page opens it filled in with the job as it is, on that
// part, every step open from the rail; the last step marks what changed and Save writes only that
// (spur_core:jmWizardSave, in server/devtools.lua, in the order that works: ranks before the people
// moved onto them, a rank removed after its people moved off). Nothing is written before Save.
//
// The old callbacks (jmCreateJob, jmHire...) are still in tools/panel_sections/jobs.lua, unchanged,
// for anything else that speaks them.
// ========================================

import { WhipPanel, WP } from '../whip-panel.js';
import { nuiCallback } from '../utils.js';
import { personSearch, avatar } from './pickers.js';
import { plural, money } from './format.js';

let jobs = {};          // { [jobId]: { jobId, name, key, ownerCharId, settings, ... } }
let roles = {};         // { [jobId]: { [roleId]: { roleId, name, level, permissions } } }
let employees = {};     // { [jobId]: { [charId]: { charId, roleId, hiredAt, hiredBy } } }
let clockedOn = {};     // { [charId]: { [jobId]: true } }
let charNames = {};     // { [charId]: "Name" }
let bankAccounts = {};  // { [jobId]: { [accountId]: { accountNumber, label, balance, frozen } } }
let jobShops = {};      // { [jobId]: [ { shopId, name, mode } ] }
let permissionDefs = {};    // { [jobId]: [ { key, label, custom } ] } — every permission the job knows
let defaultRanks = [];      // config.lua's Config.JobDefaultRoles: the first template
let builtinPermissions = [];   // [ { key, label } ]: the long labels, for the toggles' tooltips
let selectedJobId = null;   // the job whose page is open
let search = '';
let els = {};

let draft = null;        // the job being set up or changed, while the wizard is open
let wiz = null;          // its WP.stepper
let wizAt = 'name';      // the step it is on, so the panel reopens there
let pendingSelect = null;   // a job just made: opened once the list has it
let uidSeq = 0;
const newUid = () => 'r' + (++uidSeq);

// Short names for the built-in permissions (the server's labels are sentences, kept as tooltips).
const PERM_LABELS = {
    canHire: 'Hire', canFire: 'Fire', canPromote: 'Promote', canDemote: 'Demote', canManage: 'Manage',
};
const BUILTIN_PERMS = Object.keys(PERM_LABELS).map((key) => ({ key, label: PERM_LABELS[key], custom: false }));

// ---- A RANK'S ACCOUNT BOX: REMOVED FOR NOW (Josh, 10 Nov 2026: "confusing") ----
// The Ranks step no longer shows each rank's share of the business account (No access / Can see it / Can pay
// in / Can take out / Full control). A rank keeps the access it already has: its starting set's (TEMPLATES
// below), an existing job's saved one, or none for a rank added here. It is still saved (r.bank, saveDraft).

const ALL_PERMS = { canHire: true, canFire: true, canPromote: true, canDemote: true, canManage: true };
const STAFF_PERMS = { canHire: true, canFire: true, canPromote: true, canDemote: true };

/** The ranks a new job can start from. The first is config.lua's own (Config.JobDefaultRoles). */
const TEMPLATES = [
    { key: 'standard', label: 'Owner, Manager, Employee', ranks: () => (defaultRanks.length ? defaultRanks : [
        { name: 'Owner', level: 100, permissions: Object.assign({ bankAccess: 'manager' }, ALL_PERMS) },
        { name: 'Manager', level: 50, permissions: Object.assign({ bankAccess: 'withdraw' }, STAFF_PERMS) },
        { name: 'Employee', level: 1, permissions: { bankAccess: 'view' } },
    ]) },
    { key: 'service', label: 'Emergency service', ranks: () => [
        { name: 'Chief', level: 100, permissions: Object.assign({ bankAccess: 'manager' }, ALL_PERMS) },
        { name: 'Captain', level: 80, permissions: Object.assign({ bankAccess: 'withdraw' }, STAFF_PERMS) },
        { name: 'Sergeant', level: 60, permissions: { canPromote: true, canDemote: true, bankAccess: 'view' } },
        { name: 'Officer', level: 30, permissions: {} },
        { name: 'Cadet', level: 1, permissions: {} },
    ] },
    { key: 'simple', label: 'Owner and staff', ranks: () => [
        { name: 'Owner', level: 100, permissions: Object.assign({ bankAccess: 'manager' }, ALL_PERMS) },
        { name: 'Staff', level: 1, permissions: {} },
    ] },
];

/** The permissions a job knows: the built-ins, then its resource's own. */
function permsFor(jobId) {
    const list = jobId ? permissionDefs[String(jobId)] : null;
    if (!Array.isArray(list) || list.length === 0) return BUILTIN_PERMS;
    return list.map((p) => ({ key: p.key, label: p.custom ? p.label : (PERM_LABELS[p.key] || p.label), custom: !!p.custom }));
}

function permTip(key) {
    const b = builtinPermissions.find((p) => p.key === key);
    return b ? b.label : '';
}

// ---- helpers ----

function parseJobs(raw) {
    const out = {};
    if (Array.isArray(raw)) {
        for (const j of raw) { if (j && j.jobId) out[String(j.jobId)] = j; }
    } else if (raw) {
        for (const key of Object.keys(raw)) {
            const j = raw[key];
            if (j && j.jobId) out[String(j.jobId)] = j;
        }
    }
    return out;
}

function adopt(data, isRefresh) {
    jobs = parseJobs(data.jobs);
    if (data.permissionDefs) permissionDefs = data.permissionDefs;
    roles = data.roles || {};
    employees = data.employees || {};
    clockedOn = data.clockedOn || {};
    // Refresh payloads may omit the slow-moving maps; keep the old ones then.
    if (!isRefresh || data.charNames) charNames = data.charNames || {};
    if (!isRefresh || data.bankAccounts) bankAccounts = data.bankAccounts || {};
    if (data.shops) jobShops = data.shops;
    if (Array.isArray(data.defaultRanks)) defaultRanks = data.defaultRanks;
    if (Array.isArray(data.builtinPermissions)) builtinPermissions = data.builtinPermissions;
}

function employeeCount(jobId) {
    return Object.keys(employees[String(jobId)] || {}).length;
}

function charName(charId) {
    return charNames[charId] || charNames[String(charId)] || ('Character #' + charId);
}

function isClockedOn(charId, jobId) {
    const clocked = clockedOn[charId] || clockedOn[String(charId)];
    if (!clocked) return false;
    return clocked[jobId] === true || clocked[String(jobId)] === true;
}

function sortedRoles(jobId) {
    return Object.values(roles[String(jobId)] || {}).sort((a, b) => b.level - a.level);
}

const KEY_RE = /^[A-Za-z_][A-Za-z0-9_]*$/;

/** A key made from the name, free for use: the server's own rule (Jobs.keyFromName). */
function keyFromName(name) {
    let base = String(name || '').toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+/, '').replace(/_+$/, '');
    if (base === '' || /^\d/.test(base)) base = 'job_' + base;
    base = base.slice(0, 44);
    const used = new Set(Object.values(jobs).map((j) => j.key));
    let key = base, n = 1;
    while (used.has(key)) { n += 1; key = base + '_' + n; }
    return key;
}

// ---- drafts: the job as the wizard holds it ----

/** A rank as the wizard edits it: the permissions it may use, and its bank access apart. */
function rankFrom(def, roleId) {
    const p = (def && def.permissions) || {};
    const perms = {};
    for (const k of Object.keys(p)) if (k !== 'bankAccess' && p[k] === true) perms[k] = true;
    return { uid: newUid(), roleId: roleId || null, name: (def && def.name) || '', level: (def && def.level) || 1,
             perms, bank: p.bankAccess || 'none' };
}

function newDraft() {
    return {
        editing: null,
        name: '', key: '', keyTouched: false,
        template: 'standard',
        ranks: TEMPLATES[0].ranks().map((r) => rankFrom(r)),
        ranksTouched: false,
        ownerCharId: 0, ownerName: '',
        staff: [],                 // [{ charId, name, rank: uid | null, existing, onDuty }]
    };
}

function draftFromJob(id) {
    const j = jobs[String(id)];
    const ranks = sortedRoles(id).map((r) => rankFrom(r, r.roleId));
    const byRoleId = {};
    for (const r of ranks) byRoleId[r.roleId] = r.uid;
    const emps = employees[String(id)] || {};
    const staff = Object.keys(emps).sort((a, b) => charName(a).localeCompare(charName(b))).map((cid) => ({
        charId: Number(cid), name: charName(cid), rank: byRoleId[emps[cid].roleId] || null,
        existing: true, onDuty: isClockedOn(cid, id),
    }));
    return {
        editing: String(id),
        name: j.name || '', key: j.key || '', keyTouched: true,
        ranks, ranksTouched: true,
        ownerCharId: Number(j.ownerCharId) || 0, ownerName: j.ownerCharId ? charName(j.ownerCharId) : '',
        staff,
    };
}

function ranksShape(d) {
    return JSON.stringify(d.ranks.map((r) => [r.uid, r.roleId, r.name.trim(), Number(r.level),
        Object.keys(r.perms).filter((k) => r.perms[k]).sort(), Number(r.level) >= 100 ? 'manager' : r.bank]).sort());
}
function staffShape(d) {
    return JSON.stringify(d.staff.map((s) => [s.charId, s.rank]).sort((a, b) => a[0] - b[0]));
}
function snapshot(d) {
    return { name: d.name, ownerCharId: d.ownerCharId, ranks: ranksShape(d), staff: staffShape(d) };
}

/** The parts of a job being changed that differ from the job as it is, by step. */
function changedParts(d) {
    const out = new Set();
    const o = d && d.original;
    if (!o) return out;
    if (d.name.trim() !== o.name.trim()) out.add('name');
    if (Number(d.ownerCharId) !== Number(o.ownerCharId)) out.add('owner');
    if (ranksShape(d) !== o.ranks) out.add('ranks');
    if (staffShape(d) !== o.staff) out.add('staff');
    return out;
}

const rankOf = (d, uid) => d.ranks.find((r) => r.uid === uid) || null;
const rankRef = (r) => (r.roleId ? Number(r.roleId) : r.name.trim());
const sortRanks = (d) => d.ranks.sort((a, b) => Number(b.level) - Number(a.level));
const lowestRank = (d) => d.ranks.reduce((lo, r) => (!lo || Number(r.level) < Number(lo.level) ? r : lo), null);
const topRank = (d) => d.ranks.reduce((hi, r) => (!hi || Number(r.level) > Number(hi.level) ? r : hi), null);

function ranksPayload(d) {
    return d.ranks.map((r) => {
        const permissions = {};
        for (const k of Object.keys(r.perms)) if (r.perms[k]) permissions[k] = true;
        permissions.bankAccess = Number(r.level) >= 100 ? 'manager' : r.bank;
        return { roleId: r.roleId || undefined, name: r.name.trim(), level: Number(r.level), permissions };
    });
}

// ========================================
// THE JOB'S PAGE
// ========================================

function renderList() {
    els.list.innerHTML = '';
    const ids = Object.keys(jobs).sort((a, b) => String(jobs[a].name || '').localeCompare(String(jobs[b].name || '')));
    let shown = 0;

    for (const id of ids) {
        const j = jobs[id];
        const hay = ((j.name || '') + ' #' + id + ' ' + (j.key || '')).toLowerCase();
        if (search && !hay.includes(search)) continue;
        shown += 1;
        const n = employeeCount(id);
        const item = WP.listItem({
            title: j.name || 'Unnamed',
            sub: (j.ownerCharId ? charName(j.ownerCharId) : 'no owner') + ' · ' + plural(n, 'person', 'people'),
            id: id,
            action: 'jmSelectJob',
        });
        if (selectedJobId === id) item.classList.add('active');
        els.list.appendChild(item);
    }

    if (shown === 0) {
        els.list.appendChild(WP.empty(search ? 'No jobs match "' + search + '"' : 'No jobs'));
    }
    els.count.textContent = shown + ' of ' + ids.length;
}

function selectJob(jobId) {
    if (!jobs[String(jobId)]) return;
    selectedJobId = String(jobId);
    renderList();
    renderDetail();
}

function noJob() {
    selectedJobId = null;
    renderList();
    renderDetail();
}

/** One row per part of the job, each with `rowOpts(stepKey)`'s button. `changed` marks what a Save
 *  would write. */
function summaryRows(body, d, rowOpts, changed) {
    const mark = (key, text) => (changed && changed.has(key) ? text + '  ·  changed' : text);
    const row = (label, key, status, detail) => {
        body.appendChild(WP.statusRow({ label, status, detail: mark(key, detail), ...rowOpts(key) }));
    };
    row('Name', 'name', d.name.trim() ? 'ok' : 'err', d.name.trim() ? d.name.trim() + '  ·  key ' + (d.key || '—') : 'none');
    const ranks = d.ranks.slice().sort((a, b) => Number(b.level) - Number(a.level));
    row('Ranks', 'ranks', ranks.length ? 'ok' : 'err', ranks.length
        ? plural(ranks.length, 'rank') + ':  ' + ranks.map((r) => (r.name.trim() || 'unnamed') + ' ' + r.level).join(', ')
        : 'none');
    row('Owner', 'owner', d.ownerCharId ? 'ok' : 'off', d.ownerCharId
        ? d.ownerName + '  ·  #' + d.ownerCharId + '  ·  holds ' + ((topRank(d) && topRank(d).name.trim()) || 'the top rank')
        : 'nobody yet: no business account until it has one');
    const unranked = d.staff.filter((s) => !rankOf(d, s.rank)).length;
    row('Staff', 'staff', unranked ? 'err' : d.staff.length ? 'ok' : 'off', d.staff.length
        ? plural(d.staff.length, 'person', 'people') + ':  ' + d.staff.slice(0, 4).map((s) => s.name).join(', ')
          + (d.staff.length > 4 ? ', …' : '') + (unranked ? '  ·  ' + unranked + ' without a rank' : '')
        : 'nobody yet');
}

/** One person: their portrait (or initials) with the on-duty light, their name and a line under it. */
function personLine(name, sub, onDuty, charId) {
    const line = WP.el('div', 'wp-line wp-line-wide');
    line.appendChild(avatar(name, onDuty, charId));
    const text = WP.el('div');
    text.appendChild(WP.el('div', 'wp-item-title', name));
    text.appendChild(WP.el('div', 'wp-item-sub', sub));
    line.appendChild(text);
    return line;
}

function renderDetail() {
    const body = els.detailBody;
    body.innerHTML = '';
    const j = selectedJobId && jobs[selectedJobId];
    if (!j) {
        els.detailTitle.textContent = 'Jobs';
        body.appendChild(WP.el('div', 'wp-hint',
            'Pick a job to see who works there and change it, or set a new one up: the wizard walks you through '
            + 'its name, its ranks, its owner and its staff.'));
        const go = WP.el('div', 'wp-actions-row');
        go.appendChild(WP.btn('Set up a new job', 'jmNew', 'primary'));
        body.appendChild(go);
        return;
    }
    els.detailTitle.textContent = j.name || 'Job';
    const id = selectedJobId;
    const d = draftFromJob(id);
    const by = j.settings && typeof j.settings === 'object' && j.settings.declaredBy;
    body.appendChild(WP.el('div', 'wp-item-sub', 'Job #' + id + '  ·  key "' + (j.key || '') + '"'
        + (by ? '  ·  declared by the resource ' + by + ' (EnsureJob)' : '') + '  ·  Change opens the wizard on that part'));
    summaryRows(body, d, (key) => ({ action: 'jmEdit', arg: key, actionLabel: 'Change' }));

    // ---- who works there, at a glance ----
    body.appendChild(WP.el('div', 'wp-section-title', 'People'));
    const people = WP.el('div', 'wp-lines');
    const top = topRank(d);
    if (j.ownerCharId) {
        people.appendChild(personLine(charName(j.ownerCharId), 'Owner  ·  holds ' + (top ? top.name : 'the top rank')
            + (isClockedOn(j.ownerCharId, id) ? '  ·  on duty' : ''), isClockedOn(j.ownerCharId, id), j.ownerCharId));
    }
    const staff = d.staff.slice().sort((a, b) => Number((rankOf(d, b.rank) || {}).level || 0) - Number((rankOf(d, a.rank) || {}).level || 0));
    for (const s of staff) {
        const r = rankOf(d, s.rank);
        people.appendChild(personLine(s.name, (r ? r.name : 'no rank') + '  ·  #' + s.charId + (s.onDuty ? '  ·  on duty' : ''), s.onDuty, s.charId));
    }
    if (!j.ownerCharId && !staff.length) people.appendChild(WP.empty('Nobody works here yet'));
    body.appendChild(people);

    // ---- its money and its shops ----
    const accounts = Object.values(bankAccounts[id] || {});
    body.appendChild(WP.el('div', 'wp-section-title', 'Business account'));
    if (!accounts.length) {
        body.appendChild(WP.el('div', 'wp-hint', j.ownerCharId ? 'None yet.' : 'None: one is made for the job when it has an owner.'));
    }
    for (const acc of accounts) {
        body.appendChild(WP.statusRow({ label: acc.label || 'Business account', status: acc.frozen ? 'err' : 'ok',
            detail: String(acc.accountNumber) + '  ·  ' + money(acc.balance) + (acc.frozen ? '  ·  frozen' : '') }));
    }
    const shops = jobShops[id] || [];
    if (shops.length) {
        body.appendChild(WP.el('div', 'wp-section-title', 'Shops it runs'));
        for (const s of shops) {
            body.appendChild(WP.statusRow({ label: s.name || 'Shop', status: 'ok',
                detail: '#' + s.shopId + '  ·  ' + (s.mode === 'stocked' ? 'real stock' : s.mode === 'infinite' ? 'never runs out' : s.mode) }));
        }
    }

    // Destructive far-left, the rest far-right — Delete never neighbours the others.
    const actions = WP.el('div', 'wp-actions-row');
    actions.appendChild(WP.btn('Delete', 'jmDelete', 'danger'));
    actions.appendChild(WP.el('span', 'wp-actions-split'));
    actions.appendChild(WP.btn('Change everything', 'jmEdit', 'primary', 'name'));
    body.appendChild(actions);
}

// ========================================
// THE WIZARD
// ========================================

function wizardOpen() { return !!draft; }

function showView() {
    if (!els.listView) return;
    els.listView.style.display = wizardOpen() ? 'none' : '';
    els.wizView.style.display = wizardOpen() ? '' : 'none';
}

function stepsFor(editing) {
    return [
        { key: 'name', label: 'Name' }, { key: 'ranks', label: 'Ranks' }, { key: 'owner', label: 'Owner' },
        { key: 'staff', label: 'Staff' }, { key: 'review', label: editing ? 'Save' : 'Create' },
    ];
}

function openWizard() {
    draft = newDraft();
    buildWizard('name');
    showView();
}

function openEdit(id, at) {
    if (!jobs[String(id)]) return;
    draft = draftFromJob(id);
    draft.original = snapshot(draft);
    buildWizard(at);
    showView();
}

function closeWizard() {
    draft = null;
    wiz = null;
    wizAt = 'name';
    if (els.wizBody) els.wizBody.innerHTML = '';
    showView();
}

function draftTouched() {
    if (!draft) return false;
    if (draft.editing) return changedParts(draft).size > 0;
    return !!(draft.name.trim() || draft.ownerCharId || draft.staff.length || draft.ranksTouched);
}

async function discardWizard() {
    if (draftTouched()) {
        const editing = !!draft.editing;
        const ok = await WP.confirm({
            title: editing ? 'Stop changing this job?' : 'Throw this job away?',
            body: editing ? 'Nothing you changed here is saved.' : 'Nothing has been made yet. Everything you set up for it goes.',
            confirmLabel: editing ? 'Stop' : 'Throw away', danger: true,
        });
        if (!ok) return;
    }
    closeWizard();
}

function buildWizard(at) {
    const steps = stepsFor(!!draft.editing);
    els.wizBody.innerHTML = '';
    wiz = WP.stepper({
        id: 'jm-wizard',
        steps,
        onGo: (k, from, body) => { wizAt = k; fillStep(k, body); },
        canLeave: (from) => canLeave(from),
        onFinish: finish,
        finishLabel: draft.editing ? 'Save changes' : 'Create job',
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
        ? 'Change — ' + (name || 'Job #' + draft.editing)
        : 'New job' + (name ? ' — ' + name : '');
    els.wizDiscard.textContent = draft && draft.editing ? 'Cancel' : 'Discard';
}

function fillStep(key, body) {
    if (!draft) return;
    body.innerHTML = '';
    const fill = { name: stepName, ranks: stepRanks, owner: stepOwner, staff: stepStaff, review: stepReview }[key];
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

// ---- step: name ----

function stepName(body) {
    const name = WP.input({ placeholder: 'e.g. Saloon', value: draft.name, inputAction: 'jwName' });
    name.maxLength = 100;
    body.appendChild(WP.field('Name', name, true));
    if (draft.editing) {
        body.appendChild(WP.statusRow({ label: 'Key', status: 'ok', detail: draft.key + '  ·  fixed: doors, shops and scripts know the job by it' }));
        const j = jobs[draft.editing];
        const by = j && j.settings && typeof j.settings === 'object' && j.settings.declaredBy;
        if (by) {
            body.appendChild(WP.statusRow({ label: 'Declared by', status: 'warn',
                detail: by + ': when it starts it may set the name back, and adds any rank of its own that is missing' }));
        }
        return;
    }
    const key = WP.input({ placeholder: 'made from the name', value: draft.key, inputAction: 'jwKey' });
    key.maxLength = 50;
    els.keyInput = key;
    const cols = WP.el('div', 'wp-cols-2 wp-after');
    cols.appendChild(WP.field('Key', key));
    body.appendChild(cols);
    hint(body, 'Doors, shops and scripts know the job by its key. It is made from the name; change it only if a script '
        + 'wants a particular one. It cannot be changed once the job is made.');
}

// ---- step: ranks ----

function stepRanks(body) {
    if (!draft.editing) {
        body.appendChild(WP.el('div', 'wp-section-title', 'Start from'));
        body.appendChild(WP.toggles('jwTemplate', TEMPLATES, draft.template));
    }
    hint(body, 'A level decides who outranks who: someone can only hire, fire or promote people on a lower level than '
        + 'their own. The top rank, level 100, is the owner\'s, and has full control of the business account.')
        .classList.add('wp-after');

    const list = WP.el('div', 'wp-ranks');
    const perms = permsFor(draft.editing);
    const tops = draft.ranks.filter((r) => Number(r.level) >= 100).length;
    for (const r of draft.ranks) {
        const top = Number(r.level) >= 100;
        const card = WP.el('div', 'wp-rank' + (top ? ' wp-rank-top' : ''));
        card.dataset.uid = r.uid;

        const name = WP.input({ placeholder: 'Rank name', value: r.name, inputAction: 'jwRankName' });
        name.maxLength = 60;
        name.dataset.uid = r.uid;
        card.appendChild(WP.field('Rank', name));
        const level = WP.input({ type: 'number', value: r.level, inputAction: 'jwRankLevel' });
        level.min = 1;
        level.max = 100;
        level.dataset.uid = r.uid;
        level.dataset.change = 'jwRankLevelDone';
        card.appendChild(WP.field('Level', level));
        const holders = draft.staff.filter((s) => s.rank === r.uid).length;
        card.appendChild(WP.el('span', 'wp-item-sub', (top ? 'the owner\'s' + (holders ? ' + ' : '') : '')
            + (holders || !top ? plural(holders, 'person', 'people') : '')));
        const remove = WP.btn('Remove', 'jwRankRemove', 'ghost', r.uid);
        if (top && tops === 1) { remove.disabled = true; remove.title = 'The job needs a level 100 rank'; }
        card.appendChild(remove);

        const toggles = WP.el('div', 'wp-toggles wp-toggles-many');
        for (const p of perms) {
            const t = WP.el('button', 'wp-toggle' + (r.perms[p.key] ? ' active' : ''), p.label);
            t.type = 'button';
            t.dataset.action = 'jwPerm';
            t.dataset.uid = r.uid;
            t.dataset.arg = p.key;
            t.title = p.custom ? p.label : permTip(p.key);
            toggles.appendChild(t);
        }
        card.appendChild(toggles);
        // (Its account box is gone for now: see the note at the top.)
        list.appendChild(card);
    }
    body.appendChild(list);
    const add = WP.el('div', 'wp-actions-row');
    add.appendChild(WP.btn('+ Add a rank', 'jwRankAdd'));
    body.appendChild(add);
}

// ---- step: owner ----

function stepOwner(body) {
    const top = topRank(draft);
    hint(body, 'The owner holds the top rank (' + ((top && top.name.trim()) || 'level 100') + ') without being on the staff list, '
        + 'and the job\'s business bank account is theirs: one is made for them if the job has none, and a new owner '
        + 'takes it over.');
    body.appendChild(WP.statusRow({ label: 'Owner', status: draft.ownerCharId ? 'ok' : 'off',
        detail: draft.ownerCharId ? draft.ownerName + '  ·  #' + draft.ownerCharId : 'nobody yet' }));
    const hasAccount = draft.editing && Object.keys(bankAccounts[draft.editing] || {}).length > 0;
    if (draft.ownerCharId) {
        const row = WP.el('div', 'wp-actions-row');
        const none = WP.btn('Nobody owns it', 'jwOwnerNone', 'ghost');
        if (hasAccount) { none.disabled = true; none.title = 'It has a business account, so it needs an owner: pick another instead'; }
        row.appendChild(none);
        body.appendChild(row);
    }
    body.appendChild(WP.el('div', 'wp-section-title', draft.ownerCharId ? 'Someone else' : 'Find them'));
    const find = personSearch({
        placeholder: 'Type their name or character id…',
        skip: (charId) => charId === Number(draft.ownerCharId),
        onPick: (p) => {
            draft.ownerCharId = p.charId;
            draft.ownerName = p.name;
            charNames[p.charId] = p.name;
            redrawStep();
        },
    });
    find.root.style.maxWidth = '640px';
    body.appendChild(find.root);
}

// ---- step: staff ----

function rankSelect(s) {
    const opts = [{ value: '', label: '— pick a rank —' }].concat(
        draft.ranks.slice().sort((a, b) => Number(b.level) - Number(a.level))
            .map((r) => ({ value: r.uid, label: (r.name.trim() || 'unnamed') + ' (' + r.level + ')' })));
    const sel = WP.select(opts, { changeAction: 'jwStaffRank' });
    sel.value = rankOf(draft, s.rank) ? s.rank : '';
    sel.dataset.char = s.charId;
    return sel;
}

function stepStaff(body) {
    hint(body, draft.editing
        ? 'Change anyone\'s rank, let people go, or hire someone new. It all happens when you Save: someone let go '
          + 'loses the job and its account access.'
        : 'Hire people now, or later from the job\'s page (and in the game, by its managers with the phone\'s Business app).');
    const lines = WP.el('div', 'wp-lines');
    if (draft.ownerCharId) {
        const top = topRank(draft);
        const line = WP.el('div', 'wp-line wp-line-wide');
        line.appendChild(avatar(draft.ownerName, undefined, draft.ownerCharId));
        const text = WP.el('div');
        text.appendChild(WP.el('div', 'wp-item-title', draft.ownerName));
        text.appendChild(WP.el('div', 'wp-item-sub', '#' + draft.ownerCharId + '  ·  the owner: change them on the Owner step'));
        line.appendChild(text);
        line.appendChild(WP.el('span', 'wp-item-sub', 'holds ' + ((top && top.name.trim()) || 'the top rank')));
        lines.appendChild(line);
    }
    for (const s of draft.staff) {
        const line = WP.el('div', 'wp-line wp-line-wide');
        if (!rankOf(draft, s.rank)) line.classList.add('wp-line-err');
        line.appendChild(avatar(s.name, s.existing ? !!s.onDuty : undefined, s.charId));
        const text = WP.el('div');
        text.appendChild(WP.el('div', 'wp-item-title', s.name));
        text.appendChild(WP.el('div', 'wp-item-sub', '#' + s.charId + (s.existing ? (s.onDuty ? '  ·  on duty' : '') : '  ·  new')));
        line.appendChild(text);
        line.appendChild(WP.field('Rank', rankSelect(s)));
        line.appendChild(WP.btn(s.existing ? 'Let go' : 'Remove', 'jwStaffRemove', 'ghost', s.charId));
        lines.appendChild(line);
    }
    if (!draft.staff.length && !draft.ownerCharId) lines.appendChild(WP.empty('Nobody yet'));
    body.appendChild(lines);

    body.appendChild(WP.el('div', 'wp-section-title', 'Hire someone'));
    const find = personSearch({
        placeholder: 'Type their name or character id…',
        skip: (charId) => charId === Number(draft.ownerCharId) || draft.staff.some((s) => s.charId === charId),
        onPick: (p) => {
            const lo = lowestRank(draft);
            draft.staff.push({ charId: p.charId, name: p.name, rank: lo ? lo.uid : null, existing: false });
            charNames[p.charId] = p.name;
            redrawStep();
        },
    });
    find.root.style.maxWidth = '640px';
    body.appendChild(find.root);
}

// ---- step: review ----

function stepReview(body) {
    const changed = draft.editing ? changedParts(draft) : null;
    summaryRows(body, draft, (key) => ({ action: 'jwJump', arg: key, actionLabel: 'Change' }), changed);
    // Who a Save moves, lets go or hires, by name: letting someone go is not taken back by Cancel later.
    if (changed && changed.has('staff')) {
        const diff = staffDiff(draft);
        const names = (list) => list.map((x) => charName(typeof x === 'object' ? x.charId : x)).join(', ');
        const rankName = (m) => { const r = draft.ranks.find((x) => x.roleId === m.rank || x.name.trim() === m.rank); return r ? r.name.trim() : '?'; };
        if (diff.fire.length) body.appendChild(WP.statusRow({ label: 'Let go', status: 'warn', sub: true, detail: names(diff.fire) }));
        if (diff.move.length) body.appendChild(WP.statusRow({ label: 'New rank', status: 'ok', sub: true,
            detail: diff.move.map((m) => charName(m.charId) + ' → ' + rankName(m)).join(', ') }));
        if (diff.hire.length) body.appendChild(WP.statusRow({ label: 'Hired', status: 'ok', sub: true,
            detail: diff.hire.map((h) => h.name + ' as ' + rankName(h)).join(', ') }));
    }
    const last = draft.editing
        ? hint(body, changed.size ? 'Save changes writes what changed, and nothing else.' : 'Nothing has changed yet: Change any part above.')
        : hint(body, 'Create makes the job with its ranks' + (draft.ownerCharId ? ', gives its owner the business account' : '')
            + (draft.staff.length ? ' and hires its staff' : '') + '.');
    last.classList.add('wp-apart');
}

// ---- leaving a step, and saving ----

function canLeave(from) {
    const d = draft;
    if (!d) return 'There is no job being set up';
    if (from === 'name') {
        if (!d.name.trim()) return 'Give the job a name';
        if (!d.editing) {
            const key = d.key.trim();
            if (key && (!KEY_RE.test(key) || key.length > 50)) return 'A key is letters, digits and _ (starting with a letter or _), up to 50';
            if (key && Object.values(jobs).some((j) => j.key === key)) return 'Another job already uses the key "' + key + '"';
        }
        return true;
    }
    if (from === 'ranks') {
        if (!d.ranks.length) return 'A job needs at least one rank';
        if (d.ranks.length > 20) return 'A job has at most 20 ranks';
        const seen = new Set();
        for (const r of d.ranks) {
            const n = r.name.trim();
            if (!n) return 'Every rank needs a name';
            if (seen.has(n.toLowerCase())) return 'Two ranks are called "' + n + '"';
            seen.add(n.toLowerCase());
            const lv = Number(r.level);
            if (!Number.isInteger(lv) || lv < 1 || lv > 100) return '"' + n + '": a level is a whole number from 1 to 100';
        }
        if (!d.ranks.some((r) => Number(r.level) === 100)) return 'The top rank must be level 100: the owner holds it';
        return true;
    }
    if (from === 'staff') {
        const lost = d.staff.find((s) => !rankOf(d, s.rank));
        return lost ? 'Give ' + lost.name + ' a rank' : true;
    }
    return true;
}

function firstProblem() {
    for (const s of stepsFor(!!draft.editing)) {
        if (s.key === 'review') continue;
        const why = canLeave(s.key);
        if (why !== true) return { key: s.key, why };
    }
    return null;
}

/** What changed in the staff: people let go, moved to another rank, and hired. */
function staffDiff(d) {
    const before = {};
    const o = JSON.parse(d.original.staff);
    for (const [charId, uid] of o) before[charId] = uid;
    const now = new Set(d.staff.map((s) => s.charId));
    const out = { fire: [], move: [], hire: [] };
    for (const charId of Object.keys(before)) if (!now.has(Number(charId))) out.fire.push(Number(charId));
    for (const s of d.staff) {
        const r = rankOf(d, s.rank);
        if (!r) continue;
        if (!s.existing) out.hire.push({ charId: s.charId, rank: rankRef(r), name: s.name });
        else if (before[s.charId] !== s.rank) out.move.push({ charId: s.charId, rank: rankRef(r) });
    }
    return out;
}

function finish() {
    const d = draft;
    if (!d || d.saving) return;
    const changed = d.editing ? changedParts(d) : null;
    if (changed && !changed.size) { wiz.say('Nothing has changed', 'err'); return; }
    const problem = firstProblem();
    if (problem) {
        wiz.setStatus(problem.key, 'error');
        wiz.say(problem.why, 'err');
        return;
    }

    const done = (res, id, made) => {
        if (draft !== d) return;
        d.saving = false;
        if (!res || (res.ok !== true && !(res.problems && res.problems.length))) {
            // Refused before anything was written: the wizard stays, with why.
            wiz.say((res && res.why) || (made ? 'The job was not made' : 'The job was not saved'), 'err');
            return;
        }
        const problems = res.problems || [];
        WP.result((made ? 'Job created' : 'Job saved') + (problems.length ? ', but: ' + problems.join('; ') : ''),
            problems.length ? 'err' : 'ok');
        closeWizard();
        if (id && jobs[id]) selectJob(id); else pendingSelect = id;
    };

    d.saving = true;
    if (d.editing) {
        const data = {};
        if (changed.has('name')) data.name = d.name.trim();
        if (changed.has('owner')) data.ownerCharId = Number(d.ownerCharId) || 0;
        if (changed.has('ranks')) data.ranks = ranksPayload(d);
        if (changed.has('staff')) data.staff = staffDiff(d);
        wiz.say('Saving…');
        nuiCallback('jmWizardSave', { jobId: Number(d.editing), data }).then((res) => done(res, d.editing, false));
    } else {
        const lo = lowestRank(d);
        wiz.say('Creating…');
        nuiCallback('jmWizardCreate', {
            name: d.name.trim(),
            key: d.key.trim(),
            ownerCharId: Number(d.ownerCharId) || 0,
            ranks: ranksPayload(d),
            hire: d.staff.map((s) => ({ charId: s.charId, name: s.name, rank: rankRef(rankOf(d, s.rank) || lo) })),
        }).then((res) => done(res, res && res.jobId !== undefined ? String(res.jobId) : null, true));
    }
}

// ---- the section ----

WhipPanel.registerSection({
    id: 'jobs',
    group: 'economy',
    label: 'Jobs',
    order: 40,

    render(root) {
        els = {};

        // ---- the wizard, in the list's place while a job is set up or changed ----
        els.wizView = WP.el('div', 'wp-section-solo wp-section-wide');
        els.wizView.style.display = 'none';
        const head = WP.el('div', 'wp-actions-row wp-head-row');
        els.wizTitle = WP.el('div', 'wp-pane-title', 'New job');
        head.appendChild(els.wizTitle);
        head.appendChild(WP.el('span', 'wp-actions-split'));
        els.wizDiscard = WP.btn('Discard', 'jwDiscard', 'ghost');
        head.appendChild(els.wizDiscard);
        els.wizView.appendChild(head);
        els.wizBody = WP.el('div', 'wp-view');
        els.wizView.appendChild(els.wizBody);
        root.appendChild(els.wizView);

        els.listView = WP.el('div', 'wp-view');
        const bar = WP.toolbar({
            left: [WP.btn('+ New Job', 'jmNew')],
            search: { inputAction: 'jmSearch', placeholder: 'Search jobs…' },
        });
        els.search = bar.querySelector('.wp-input');
        els.listView.appendChild(bar);

        const split = WP.el('div', 'wp-split');
        const listCol = WP.el('div', 'wp-list-col');
        els.count = WP.el('div', 'wp-list-count', '');
        listCol.appendChild(els.count);
        els.list = WP.el('div', 'wp-list');
        listCol.appendChild(els.list);
        split.appendChild(listCol);

        const detail = WP.el('div', 'wp-detail');
        els.detailTitle = WP.el('div', 'wp-pane-title', 'Jobs');
        detail.appendChild(els.detailTitle);
        els.detailBody = WP.el('div');
        detail.appendChild(els.detailBody);
        split.appendChild(detail);
        els.listView.appendChild(split);
        root.appendChild(els.listView);

        renderList();
        renderDetail();
        if (draft) buildWizard(wizAt);
        showView();
    },

    onData(kind, payload) {
        if (kind === 'all') {
            adopt(payload, false);
            search = '';
            if (els.search) els.search.value = '';
            if (selectedJobId && !jobs[selectedJobId]) selectedJobId = null;
            renderList();
            if (!wizardOpen()) renderDetail();
        } else if (kind === 'refresh') {
            adopt(payload, true);
            if (pendingSelect && jobs[pendingSelect] && !wizardOpen()) {
                const id = pendingSelect;
                pendingSelect = null;
                selectJob(id);
                return;
            }
            if (selectedJobId && !jobs[selectedJobId]) selectedJobId = null;
            renderList();
            if (!wizardOpen()) renderDetail();
        }
    },

    onEscape() {
        if (wizardOpen()) {
            if (draft.editing && wiz && wiz.current() !== 'review') { wiz.go('review'); return true; }
            if (draft.editing || !(wiz && wiz.escape())) discardWizard();
            return true;
        }
        if (selectedJobId !== null) { noJob(); return true; }
        return false;
    },

    actions: {
        jmSearch: (el) => { search = el.value.toLowerCase(); renderList(); },
        jmNew: () => openWizard(),
        jmSelectJob: (el) => selectJob(el.dataset.id),
        jmEdit: (el) => { if (selectedJobId) openEdit(selectedJobId, el.dataset.arg); },
        jmDelete: async () => {
            if (!selectedJobId) return;
            const j = jobs[selectedJobId];
            const ok = await WP.confirm({
                title: 'Delete job?',
                body: '"' + (j ? j.name : 'Unknown') + '" and its ranks will be removed, and everyone working there is let go. '
                    + 'A job whose business account still has money in it is refused: empty it first.',
                confirmLabel: 'Delete',
                danger: true,
            });
            if (!ok) return;
            nuiCallback('jmDeleteJob', { jobId: parseInt(selectedJobId, 10), jobName: j ? j.name : 'Unknown' });
        },

        // ---- the wizard ----
        jwDiscard: () => discardWizard(),
        jwJump: (el) => { if (wiz) wiz.jump(el.dataset.arg); },
        jwName: (el) => {
            if (!draft) return;
            draft.name = el.value;
            if (!draft.editing && !draft.keyTouched) {
                draft.key = draft.name.trim() ? keyFromName(draft.name) : '';
                if (els.keyInput) els.keyInput.value = draft.key;
            }
            renderWizHead();
        },
        jwKey: (el) => {
            if (!draft) return;
            draft.key = el.value;
            draft.keyTouched = el.value.trim() !== '';
        },
        jwTemplate: async (el) => {
            const t = TEMPLATES.find((x) => x.key === el.dataset.arg);
            if (!draft || !t || draft.template === t.key) return;
            if (draft.ranksTouched) {
                const ok = await WP.confirm({ title: 'Start the ranks again?', body: 'The ranks become "' + t.label
                    + '", and what you changed in them goes.', confirmLabel: 'Start again' });
                if (!ok) return;
            }
            draft.template = t.key;
            draft.ranks = t.ranks().map((r) => rankFrom(r));
            draft.ranksTouched = false;
            const lo = lowestRank(draft);
            for (const s of draft.staff) s.rank = lo ? lo.uid : null;
            redrawStep();
        },
        jwRankName: (el) => {
            const r = draft && rankOf(draft, el.dataset.uid);
            if (r) { r.name = el.value; draft.ranksTouched = true; }
        },
        jwRankLevel: (el) => {
            const r = draft && rankOf(draft, el.dataset.uid);
            if (r) { r.level = el.value; draft.ranksTouched = true; }
        },
        // The level box let go: the ranks fall into order, and a new top rank shows as one.
        jwRankLevelDone: () => { if (draft) { sortRanks(draft); redrawStep(); } },
        jwPerm: (el) => {
            const r = draft && rankOf(draft, el.dataset.uid);
            if (!r) return;
            r.perms[el.dataset.arg] = !r.perms[el.dataset.arg];
            el.classList.toggle('active', !!r.perms[el.dataset.arg]);
            draft.ranksTouched = true;
        },
        jwRankAdd: () => {
            if (!draft) return;
            const lo = lowestRank(draft);
            const level = lo ? Math.max(1, Math.min(99, Number(lo.level) > 1 ? Math.floor(Number(lo.level) / 2) : 1)) : 1;
            const r = rankFrom({ name: '', level, permissions: {} });
            draft.ranks.push(r);
            sortRanks(draft);
            draft.ranksTouched = true;
            redrawStep();
            const input = wiz.body.querySelector('.wp-rank[data-uid="' + r.uid + '"] input');
            if (input) { input.scrollIntoView({ block: 'nearest' }); input.focus(); }
        },
        jwRankRemove: (el) => {
            if (!draft) return;
            const uid = el.dataset.arg;
            draft.ranks = draft.ranks.filter((r) => r.uid !== uid);
            // Its people need another: the Staff step asks for one.
            for (const s of draft.staff) if (s.rank === uid) s.rank = null;
            draft.ranksTouched = true;
            redrawStep();
            const held = draft.staff.filter((s) => s.rank === null).length;
            if (held) wiz.say(plural(held, 'person', 'people') + ' held it: give them another rank on the Staff step', 'err');
        },
        jwOwnerNone: () => {
            if (!draft) return;
            draft.ownerCharId = 0;
            draft.ownerName = '';
            redrawStep();
        },
        jwStaffRank: (el) => {
            const s = draft && draft.staff.find((x) => x.charId === Number(el.dataset.char));
            if (!s) return;
            s.rank = el.value || null;
            el.closest('.wp-line').classList.toggle('wp-line-err', !s.rank);
        },
        jwStaffRemove: (el) => {
            if (!draft) return;
            draft.staff = draft.staff.filter((s) => s.charId !== Number(el.dataset.arg));
            redrawStep();
        },
    },
});
