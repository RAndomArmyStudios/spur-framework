// ========================================
// DIRECTOR — the test window (Test mode)
//
// While a test runs, a window over the game, top right (where the goals' cards leave room): the scenario's blueprint
// as the test plays it, and under it the run's steps as a trail of icons. H gives them the mouse and takes it back
// (client/director.lua; the page hears H, Esc and Done while it has it).
//
// ON THE MAP each card says how it went, on itself: a green ring and a tick when it ran (the outcome it took lit on its
// pin); a red ring, pulsing a few times, and a cross when that outcome failed or the run went wrong there; hatched grey
// with a crossed circle when a choice made it impossible to reach (a branch that never joins the run again); a dashed
// ring with an hourglass and a time while it waits (a Wait card's time left, any other's time waited so far).
//
// THE TRAIL under it: a step an icon (its card's kind), the newest at the right, red where an outcome failed, ringed
// where it waits. With the mouse, a step (or its card on the map) opens under the trail:
//   TAKE      a card that is waiting goes on from the outcome pressed (server/director/runtime.lua R.take)
//   REWIND    any step so far is gone back to, and the run goes on from another of its outcomes; what cards after
//             that step made is taken away, so they can make it again (R.rewind)
// Another resource's card waiting for its outcome is picked with the keys too (PgUp, PgDn: client/director.lua): its
// outcomes stay open under the trail while it waits, the one PgDn takes ringed.
//
// The grid is the editor's own (canvas.js), on a copy of the scenario: nothing here edits it.
// ========================================

import { nuiCallback, escapeHtml } from '../utils.js';
import { plural, clock } from '../wp/format.js';
import { Canvas, REROUTE, couldNot, pinLabel, pinsOf } from './canvas.js';
import { listOf } from './doc.js';

const e = escapeHtml;
const FOLLOW_MS = 260;   // the grid easing onto the card the run reached
const TRAIL_MAX = 60;    // the trail's newest steps; the ones before are counted at its start

let win = null;   // { col, el, grid, view, ...the run as it has come } while a test runs

const RESULT = { succeeded: 'Succeeded', failed: 'Failed', aborted: 'Called off', faulted: 'Went wrong' };

// Icons in 24-unit boxes, drawn in the colour they stand in.
const svg = (d) => `<svg viewBox="0 0 24 24" aria-hidden="true">${d}</svg>`;
const ICONS = {
    ok: '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
    bad: '<path d="M7 7l10 10M17 7L7 17"/>',
    gone: '<circle cx="12" cy="12" r="8.5"/><path d="M6 18L18 6"/>',
    wait: '<path d="M7 3h10M7 21h10M8 3v3l4 6-4 6v3M16 3v3l-4 6 4 6v3"/>',
    back: '<path d="M11 7l-6 5 6 5zM19 7l-6 5 6 5z"/>',
    again: '<path d="M4.5 12a7.5 7.5 0 1 0 2.2-5.3L4.5 9M4.5 4.5V9H9"/>',
    editor: '<path d="M4 20h4L19 9l-4-4L4 16z"/><path d="M13 7l4 4"/>',
    hide: '<path d="M3 12s3.5-6 9-6 9 6 9 6-3.5 6-9 6-9-6-9-6z"/><circle cx="12" cy="12" r="2.5"/><path d="M4 20L20 4"/>',
};
// A step's icon on the trail: its card's kind (another resource's kind of card: a dot).
const KIND_ICON = {
    scenario: '<path d="M8 5.5v13l10.5-6.5z"/>',
    events: '<path d="M13 3L5 14h6l-1 7 8-11h-6z"/>',
    flow: '<path d="M9 6h11M9 12h11M9 18h11M4.5 6h.5M4.5 12h.5M4.5 18h.5"/>',
    dialog: '<path d="M4 5h16v11H10l-5 4v-4H4z"/>',
    world: '<path d="M12 3l8 4.5v9L12 21l-8-4.5v-9zM4 7.5l8 4.5 8-4.5M12 12v9"/>',
    player: '<circle cx="12" cy="8" r="3.5"/><path d="M5 20c0-3.9 3.1-6 7-6s7 2.1 7 6"/>',
    goals: '<path d="M5 21V4h11l-2 4 2 4H5"/>',
    fail: '<circle cx="12" cy="12" r="8.5"/><path d="M9 9l6 6M15 9l-6 6"/>',
    lore: '<rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="9" cy="11" r="2"/><path d="M6 16c.6-1.4 1.7-2 3-2s2.4.6 3 2M14.5 10h4M14.5 14h3"/>',
};
const DOT = '<circle cx="12" cy="12" r="3.5"/>';
const MARKS = ['ok', 'bad', 'gone', 'wait'];

/** The messages client/director.lua sends: the window on or off, its mouse, Isolate world, another resource's card to
 *  pick for, a line to say; and the run's steps. `ed` is the editor's (app.js): the scenario as it was tested, its
 *  cards, the look of the cards. */
export function testWindowMessage(d, ed, style) {
    if (d.action === 'directorTestWindow') {
        if (d.on === true) open(ed, style);
        else if (d.on === false) close();
        if (!win) return;
        // G: out of sight (it still follows the run, so it is up to date when it is back).
        if (typeof d.hidden === 'boolean') win.col.classList.toggle('hidden', d.hidden);
        if (typeof d.mouse === 'boolean') setMouse(d.mouse);
        if (typeof d.own === 'boolean') win.own = d.own;
        if (typeof d.freecam === 'boolean') win.freecam = d.freecam;
        if ('pick' in d) win.pick = d.pick && typeof d.pick === 'object' ? d.pick : null;
        if (typeof d.say === 'string') win.note = d.say;
        draw();
        return;
    }
    if (d.action !== 'directorTestFlow' || !win) return;
    if (d.reset === true) { clearRun(); draw(); return; }
    if (d.ended) {
        win.ended = d.ended;
        win.endedAt = Date.now();
        win.waiting = new Set();
        // (The card it went wrong at, red.)
        if (d.ended.node && d.ended.outcome === 'faulted') win.fault = d.ended.node;
        draw();
        return;
    }
    const steps = listOf(d.steps);
    let chose = false;
    for (const s of steps) {
        take(s);
        if (s && (s.kind === 'out' || s.kind === 'resume' || s.kind === 'rewind')) chose = true;
    }
    win.dropped += Number(d.dropped) || 0;
    win.waiting = new Set(listOf(d.waiting));
    win.queued = new Set(listOf(d.queued));
    win.status = d.status || win.status;
    if (chose) shutOff();
    draw();
}

// ---- the window ----

function open(ed, style) {
    if (!ed || !ed.doc) return;
    if (!win) {
        // The window, and the trail under it, in one column down the right of the screen. (Not a .dr-float: the pad takes
        // one of those for a question up, and this stays on the page after a test.)
        const col = document.createElement('div');
        col.className = 'dr-twcol';
        col.innerHTML = '<div id="dr-testwin" class="dr-tw"><div class="dr-tw-head"><span class="dr-tw-title">Test map</span>'
            + '<span class="dr-tw-name"></span><span class="dr-tw-own">Own world</span><span class="dr-tw-state"></span>'
            + '<span class="dr-tw-key"></span><button class="dr-tw-x dr-tw-cam" type="button" data-tw="freecam"></button>'
            + '<button class="dr-tw-x" type="button" data-tw="done" title="Back to the game">Done</button></div>'
            + '<div class="dr-tw-body"><div class="dr-tw-grid"><div class="dr-tw-canvas"></div></div></div></div>'
            + '<div class="dr-tw-trail"><div class="dr-tw-steps"></div><div class="dr-tw-tip" hidden></div>'
            + '<div class="dr-tw-bar"><i class="dr-tw-dot"></i><span class="dr-tw-clock">0:00</span><span class="dr-tw-say"></span>'
            + `<span class="dr-tw-k" title="Start it again"><kbd>F5</kbd>${svg(ICONS.again)}</span>`
            + `<span class="dr-tw-k" title="Back to the editor"><kbd>F9</kbd>${svg(ICONS.editor)}</span>`
            + `<span class="dr-tw-k" title="Hide the test map (G again shows it)"><kbd>G</kbd>${svg(ICONS.hide)}</span></div></div>`;
        document.body.appendChild(col);
        const el = col.querySelector('#dr-testwin');
        win = { col, el, stepsEl: col.querySelector('.dr-tw-steps'), tipEl: col.querySelector('.dr-tw-tip'),
                clockEl: col.querySelector('.dr-tw-clock'), sayEl: col.querySelector('.dr-tw-say'), dotEl: col.querySelector('.dr-tw-dot') };
        bind(col, el);
    }
    win.own = false;
    win.pick = null;
    win.freecam = false;
    // A copy of the scenario as it was tested (its open variant's cards): the grid lights it, nothing changes it.
    const doc = JSON.parse(JSON.stringify({ nodes: ed.doc.nodes, links: ed.doc.links, comments: ed.doc.comments || [],
                                            world: ed.doc.world, vars: ed.doc.vars, settings: ed.doc.settings }));
    const view = {
        doc, cards: ed.cards, lore: ed.lore, selected: new Set(), selectedLink: null, selectedNote: null,
        problems: new Map(), lastTest: null,
        changed() {}, changedNoCommit() {}, select() {}, selectLink() {}, selectNote() {}, pressedPicked() {},
        ui: { status() {}, leftEdge: () => 0, rightEdge: () => Infinity, search() {}, cardMenu() {}, noteMenu() {}, reroute() {} },
        // Each draw of the grid makes its cards anew: their marks go back on (mark).
        afterRender: () => mark(),
    };
    win.view = view;
    win.name = ed.doc.name || ed.key || '';
    win.mouse = false;
    // A fresh host for each test's grid: the last one's listeners (and the scenario copy they hold) go with the old one
    const old = win.el.querySelector('.dr-tw-canvas');
    const host = old.cloneNode(false);
    old.replaceWith(host);
    win.grid = new Canvas(host, view);
    win.grid.setStyle(style === 'board' ? 'board' : 'classic');
    win.col.classList.add('on');
    win.col.classList.remove('mouse', 'hidden');
    win.el.classList.add('show');
    win.el.classList.remove('mouse');
    clearRun();
    win.grid.view = { x: 0, y: 0, z: 0.75 };
    win.grid.applyView();
    win.grid.render();
    const start = doc.nodes.find((n) => n.type === 'scenario.started');
    if (start) centreOn(start.id, true);
    if (!win.tick) win.tick = setInterval(tick, 1000);
    draw();
}

function close() {
    if (!win) return;
    win.col.classList.remove('on', 'mouse');
    win.el.classList.remove('show', 'mouse');
    win.mouse = false;
    win.open = null;
    if (win.tick) clearInterval(win.tick);
    win.tick = null;
}

/** A run of its own: started, or started again (F5). */
function clearRun() {
    win.steps = [];         // { n, node, pins, whys, ms, at, kind, undone } in the order the run reached them
    win.pinsAt = new Map();  // [card] = the step it last reached it at
    win.waiting = new Set();
    win.queued = new Set();  // cards the run has yet to enter (its queue between passes)
    win.status = 'running';
    win.ended = null;
    win.fault = null;        // the card the run went wrong at
    win.startedAt = Date.now();
    win.endedAt = 0;
    win.dropped = 0;
    win.open = null;         // the step open under the trail
    win.note = '';
    win.view.lastTest = { nodes: new Set(), links: new Set(), shownNodes: new Set(), shownLinks: new Set(),
                          badNodes: new Set(), badLinks: new Set(), tone: 'ok', done: false, end: null, fault: null };
    // Where the run can go: on from Scenario Enabled, and from every event card (which can fire while it runs).
    const start = win.view.doc.nodes.filter((n) => n.type === 'scenario.started').map((n) => n.id);
    win.reach = reachFrom(start.concat(eventCards()));
    win.greyed = new Set();  // cards a choice made impossible to reach (a rewind can bring them back)
    if (win.grid) win.grid.render();
}

function setMouse(on) {
    win.mouse = on;
    win.el.classList.toggle('mouse', on);
    win.col.classList.toggle('mouse', on);
    if (!on) win.open = null;
    draw();
    if (!on && win.at) centreOn(win.at);
}

// ---- the run's steps ----

const linkOf = (s) => {
    if (!s.from) return null;
    const l = win.view.doc.links.find((k) => k.from.node === s.from && k.from.pin === s.fromPin && k.to.node === s.node && k.to.pin === s.pin);
    return l ? l.id : null;
};

/** One step from the server (hub.lua flowOf), into the trail and onto the grid. */
function take(s) {
    if (!s || typeof s.node !== 'string') return;
    const t = win.view.lastTest;
    const at = Date.now();
    if (s.kind === 'enter' || s.kind === 'skipped') {
        const link = linkOf(s);
        const step = { n: s.n, node: s.node, pins: [], whys: [], ms: s.ms, at, kind: s.kind, link };
        if (s.kind === 'skipped') step.whys.push('only once: skipped');
        win.steps.push(step);
        win.pinsAt.set(s.node, step);
        t.nodes.add(s.node);
        if (link) t.links.add(link);
        win.grid.reveal(s.node, link, true);
        win.at = s.node;
        if (!win.mouse) centreOn(s.node);
    } else if ((s.kind === 'out' || s.kind === 'resume') && s.pin) {
        // On its step: its outcome (an event card that fired has no step yet: one of its own).
        let step = win.pinsAt.get(s.node);
        if (!step || (s.kind === 'resume' && step.pins.length)) {
            step = { n: s.n, node: s.node, pins: [], whys: [], ms: s.ms, at, kind: 'event' };
            win.steps.push(step);
            win.pinsAt.set(s.node, step);
            t.nodes.add(s.node);
            win.grid.reveal(s.node, null, true);
        }
        step.pins.push(s.pin);
        if (s.text) step.whys.push(s.text);
        if (couldNot(s.pin)) t.badNodes.add(s.node);
    } else if (s.kind === 'log' && typeof s.text === 'string') {
        const step = win.pinsAt.get(s.node);
        if (step && step.whys.join('; ').length < 300) step.whys.push(s.text);
    } else if (s.kind === 'rewind') {
        // Gone back: the steps after the one gone back to are undone (still on the trail, faded), the grid lit again from
        // what stands, and the run goes on from the outcome taken there.
        const to = Number(String(s.text || '').replace(/\D+/g, '')) || 0;
        for (const st of win.steps) if (st.n > to) st.undone = true;
        const step = { n: s.n, node: s.node, pins: [s.pin], whys: [`back to step ${to}, taken by the tester`], ms: s.ms, at, kind: 'rewind' };
        win.steps.push(step);
        win.pinsAt.set(s.node, step);
        relight();
    } else if (s.kind === 'busy' || s.kind === 'ignored') {
        win.steps.push({ n: s.n, node: s.node, pins: [], whys: [s.kind === 'busy' ? 'already busy' : 'ignored: still waiting'], ms: s.ms, at, kind: s.kind });
    } else if (s.kind === 'broken') {
        // A Fail Condition's rule broken (runtime.lua R.broken): its own step, red, with its Why.
        const step = { n: s.n, node: s.node, pins: [], whys: [`rule broken: ${s.text || ''}`], ms: s.ms, at, kind: 'broken' };
        win.steps.push(step);
        win.pinsAt.set(s.node, step);
        t.nodes.add(s.node);
        t.badNodes.add(s.node);
        win.grid.reveal(s.node, null, true);
    }
}

/** The grid lit from the steps that stand (after a rewind). */
function relight() {
    const t = win.view.lastTest;
    t.nodes = new Set(); t.links = new Set(); t.shownNodes = new Set(); t.shownLinks = new Set(); t.badNodes = new Set();
    for (const st of win.steps) {
        if (st.undone) continue;
        t.shownNodes.add(st.node);
        if (st.link) t.shownLinks.add(st.link);
        if (st.pins.some((p) => couldNot(p))) t.badNodes.add(st.node);
    }
    win.grid.render();
}

// ---- what can no longer be reached ----

/** Every card a run at `sources` can still go on to, along the wires (the sources too). */
function reachFrom(sources) {
    const next = new Map();
    for (const l of win.view.doc.links) {
        if (!next.has(l.from.node)) next.set(l.from.node, []);
        next.get(l.from.node).push(l.to.node);
    }
    const seen = new Set(), todo = [...sources];
    while (todo.length) {
        const id = todo.pop();
        if (seen.has(id)) continue;
        seen.add(id);
        for (const to of next.get(id) || []) todo.push(to);
    }
    return seen;
}

/** The event cards but Scenario Enabled: they can fire while the run goes, so what they lead to stays in reach. */
const eventCards = () => win.view.doc.nodes.filter((n) => n.type !== 'scenario.started' && (defOf(n) || {}).event).map((n) => n.id);

/** After an outcome: the cards the run could reach before and cannot now (from what waits, what is queued and the event
 *  cards), that it has not played, greyed out on the map. A rewind can bring some back into reach. */
function shutOff() {
    if (!win || win.ended || win.status !== 'running') return;
    const now = reachFrom([...win.waiting, ...win.queued, ...eventCards()]);
    const played = new Set();
    for (const s of win.steps) if (!s.undone) played.add(s.node);
    for (const id of win.reach) {
        const n = cardOf(id);
        if (n && n.type !== REROUTE && !now.has(id) && !played.has(id)) win.greyed.add(id);
    }
    for (const id of now) win.greyed.delete(id);
    win.reach = now;
}

// ---- the marks on the map ----

const cardOf = (id) => win.view.doc.nodes.find((n) => n.id === id) || null;
const defOf = (n) => (n ? win.view.cards.get(n.type) : null);
const titleOf = (id) => { const n = cardOf(id); const d = defOf(n); return d ? d.title : (n ? n.type : id); };
const outName = (id, pin) => { const n = cardOf(id); return pinLabel(n, defOf(n), pin) || 'Out'; };
const over = () => !!win.ended || (!!win.status && win.status !== 'running');

/** The cards the run has played (the steps that stand), each with the outcomes it took. */
function playedPins() {
    const out = new Map();
    for (const s of win.steps) {
        if (s.undone || s.kind === 'busy' || s.kind === 'ignored') continue;
        if (!out.has(s.node)) out.set(s.node, new Set());
        for (const p of s.pins) out.get(s.node).add(p);
    }
    return out;
}

/** Is the card waiting now (its outcome to come, or another resource's card picked for with the keys)? */
const waitingNow = (id) => !over() && (win.waiting.has(id) || !!(win.pick && win.pick.node === id));

function stateOf(id, played) {
    if (waitingNow(id)) return 'wait';
    if (win.fault === id || (played.has(id) && win.view.lastTest.badNodes.has(id))) return 'bad';
    if (played.has(id)) return 'ok';
    if (win.greyed.has(id)) return 'gone';
    return null;
}

/** Every card's mark from the run as it stands: its ring and badge, and the outcomes it took lit on their pins. */
function mark() {
    // (Not before the run's own: a new grid draws once as it is made.)
    if (!win || !win.grid || !win.steps || !win.view.lastTest) return;
    const played = playedPins();
    for (const card of win.grid.cardsEl.querySelectorAll('.dr-card[data-id]')) {
        if (card.classList.contains('dr-reroute')) continue;
        const id = card.dataset.id;
        const st = stateOf(id, played);
        for (const m of MARKS) card.classList.toggle('tw-' + m, m === st);
        let badge = card.querySelector(':scope > .dr-tw-mark');
        if (!st) {
            if (badge) badge.remove();
        } else {
            if (!badge) { badge = document.createElement('b'); card.appendChild(badge); }
            if (badge.dataset.st !== st) {
                badge.dataset.st = st;
                badge.className = 'dr-tw-mark ' + st;
                badge.innerHTML = svg(ICONS[st]) + (st === 'wait' ? '<em></em>' : '');
            }
        }
        const pins = played.get(id);
        for (const p of card.querySelectorAll('.dr-pin.out')) {
            const took = !!pins && pins.has(p.dataset.pin);
            p.classList.toggle('tw-took', took && !couldNot(p.dataset.pin));
            p.classList.toggle('tw-took-bad', took && couldNot(p.dataset.pin));
        }
    }
    waitTimes();
}

/** A waiting card's time: a Wait card's time left, any other's time waited so far. */
function waitText(id) {
    const step = win.pinsAt.get(id);
    const since = step && step.at ? (Date.now() - step.at) / 1000 : 0;
    const n = cardOf(id);
    if (n && n.type === 'flow.wait') {
        const f = ((defOf(n) || {}).props || []).find((p) => p.key === 'seconds');
        const total = Number(n.props && n.props.seconds !== undefined ? n.props.seconds : f && f.default);
        if (Number.isFinite(total)) return clock(total - since);
    }
    return clock(since);
}

function waitTimes() {
    for (const em of win.grid.cardsEl.querySelectorAll('.dr-tw-mark.wait em')) {
        const card = em.closest('.dr-card');
        if (card) em.textContent = waitText(card.dataset.id);
    }
}

/** Once a second while the window shows: the run's clock and the waiting cards' times. */
function tick() {
    if (!win || !win.el.classList.contains('show')) return;
    win.clockEl.textContent = clock(((win.endedAt || Date.now()) - win.startedAt) / 1000);
    if (win.grid) waitTimes();
}

// ---- the trail ----

/** The outcomes a card shows on the grid (canvas.js pinsOf: an empty answer, a Walked away it never takes, are none),
 *  as buttons that take one: `act` 'take' (a card waiting) or 'rewind' (step `i`, gone back to). `onPin`: the one PgDn
 *  would take (another resource's card), ringed. */
const outButtons = (id, act, i, onPin) => {
    const n = cardOf(id);
    const outs = n ? pinsOf(win.view.doc, n, defOf(n)).outputs : [];
    return '<div class="dr-tw-outs">' + outs.map((o) => `<button type="button" class="dr-tw-out${o.tone === 'bad' || couldNot(o.pin) ? ' bad' : ''}${o.pin === onPin ? ' pick' : ''}"`
        + ` data-tw="${act}" data-node="${e(id)}" data-pin="${e(o.pin)}"${i !== undefined ? ` data-i="${i}"` : ''}${win.mouse ? '' : ' disabled'}`
        + ` title="${e(!win.mouse ? 'H: the mouse, to take one' : act === 'take' ? 'Take this outcome now' : 'Go back here and on from this')}">`
        + `${e(o.label || outName(id, o.pin))}</button>`).join('') + '</div>';
};

/** A step on the trail: its card's kind's icon in its colour; red with a cross where an outcome failed, an hourglass
 *  ringed while it waits, faded once a rewind undid it, small where the tester went back. */
function nodeHtml(s, i) {
    const n = cardOf(s.node), d = defOf(n);
    const latest = win.pinsAt.get(s.node) === s;
    const bad = s.pins.some((p) => couldNot(p)) || (win.fault === s.node && latest);
    const waiting = !s.undone && latest && waitingNow(s.node);
    const cls = ['dr-tw-node', 'kind-' + (d ? (d.tint || d.category) : 'unknown')];
    if (s.kind === 'rewind') cls.push('back');
    else if (bad) cls.push('bad');
    else if (waiting) cls.push('wait');
    if (s.kind === 'skipped') cls.push('skip');
    if (s.undone) cls.push('undone');
    if (win.open === i) cls.push('open');
    const icon = s.kind === 'rewind' ? ICONS.back : bad ? ICONS.bad : waiting ? ICONS.wait : (KIND_ICON[d && d.category] || DOT);
    const outs = s.pins.map((p) => outName(s.node, p)).join(', ');
    const tip = (s.kind === 'rewind' ? 'Went back to ' : '') + titleOf(s.node) + (outs ? ` → ${outs}` : '');
    return `<button type="button" class="${cls.join(' ')}" data-tw="step" data-i="${i}" title="${e(tip)}">${svg(icon)}</button>`;
}

function trailHtml() {
    const shown = [];
    win.steps.forEach((s, i) => { if (s.kind !== 'busy' && s.kind !== 'ignored') shown.push(i); });
    const cut = Math.max(0, shown.length - TRAIL_MAX) + win.dropped;
    let html = cut ? `<span class="dr-tw-more" title="${plural(cut, 'earlier step')} not shown">+${cut}</span>` : '';
    for (const i of shown.slice(-TRAIL_MAX)) html += nodeHtml(win.steps[i], i);
    return html || '<span class="dr-tw-none">Starting…</span>';
}

/** The step open under the trail: the one pressed, else another resource's card waiting for the keys. */
function openStep() {
    if (win.open !== null && win.steps[win.open]) return win.open;
    const node = !over() && win.pick && typeof win.pick.node === 'string' ? win.pick.node : null;
    const st = node && win.pinsAt.get(node);
    return st ? win.steps.indexOf(st) : -1;
}

/** Under the trail, the open step: its card, the outcome it took and why; then, waiting, its outcomes to take now, or
 *  gone by, its outcomes to go back and on from. */
function tipHtml(i) {
    const s = win.steps[i];
    const n = cardOf(s.node), d = defOf(n);
    const outs = s.pins.map((p) => `<span class="${couldNot(p) ? 'bad' : ''}">→ ${e(outName(s.node, p))}</span>`).join(' ');
    let html = `<div class="dr-tw-tip-h"><i class="dr-dot kind-${e(d ? (d.tint || d.category) : 'unknown')}"></i><b>${e(titleOf(s.node))}</b>${outs}</div>`;
    if (s.whys.length) html += `<div class="dr-tw-why">${e(s.whys.join('; '))}</div>`;
    const p = win.pick;
    const picked = p && p.node === s.node;
    if (!s.undone && win.pinsAt.get(s.node) === s && waitingNow(s.node)) {
        const list = picked ? listOf(p.outcomes) : [];
        const on = list[(Number(p && p.at) || 1) - 1];
        if (picked) html += `<div class="dr-tw-why">Would: ${e(p.says || '?')}${p.owner ? ` (${e(p.owner)})` : ''}</div>`;
        html += outButtons(s.node, 'take', undefined, on && on.pin);
        if (picked) {
            html += `<div class="dr-tw-hint"><kbd>PgUp</kbd> next <kbd>PgDn</kbd> take`
                + `${p.seconds ? ` · the first goes by itself after ${Number(p.seconds)} s` : ''}</div>`;
        }
    } else if (over()) {
        html += '<div class="dr-tw-hint"><kbd>F5</kbd> starts it again</div>';
    } else if (!s.undone && s.kind !== 'rewind') {
        html += `<div class="dr-tw-tip-back">${svg(ICONS.back)}Go back here, on from</div>` + outButtons(s.node, 'rewind', i);
    }
    return html;
}

/** The tip's arrow under its step. */
function placeTip(i) {
    const node = win.stepsEl.querySelector(`.dr-tw-node[data-i="${i}"]`);
    if (!node || win.tipEl.hidden) return;
    const x = win.stepsEl.offsetLeft + node.offsetLeft - win.stepsEl.scrollLeft + node.offsetWidth / 2 - win.tipEl.offsetLeft;
    win.tipEl.style.setProperty('--ax', Math.max(12, Math.min(win.tipEl.offsetWidth - 12, x)) + 'px');
}

/** The trail scrolled so step `i` shows. */
function trailTo(i) {
    const node = win.stepsEl.querySelector(`.dr-tw-node[data-i="${i}"]`);
    if (!node) return;
    const box = win.stepsEl, l = node.offsetLeft, r = l + node.offsetWidth;
    if (l < box.scrollLeft) box.scrollLeft = l - 12;
    else if (r > box.scrollLeft + box.clientWidth) box.scrollLeft = r - box.clientWidth + 12;
}

// ---- drawing ----

function draw() {
    if (!win || !win.el.classList.contains('show')) return;
    const head = win.el;
    head.querySelector('.dr-tw-name').textContent = win.name;
    const st = head.querySelector('.dr-tw-state');
    const done = over();
    const result = win.ended ? win.ended.outcome : win.status;
    const tone = done ? (result === 'succeeded' ? 'ok' : 'bad') : 'live';
    st.textContent = done ? (RESULT[result] || 'Over') : 'Running';
    st.className = 'dr-tw-state ' + tone;
    head.querySelector('.dr-tw-key').innerHTML = win.mouse ? '<kbd>H</kbd> back to the game' : '<kbd>H</kbd> use the mouse';
    head.querySelector('.dr-tw-own').hidden = !win.own;
    head.querySelector('[data-tw="done"]').hidden = !win.mouse;
    // The free camera (client/director.lua): to watch the run from anywhere, the character left where it stands.
    const cam = head.querySelector('[data-tw="freecam"]');
    cam.textContent = win.freecam ? 'Free camera: on' : 'Free camera';
    cam.classList.toggle('on', !!win.freecam);
    cam.title = !win.mouse ? 'H: the mouse, to use it' : win.freecam ? 'Back to your character'
        : 'Fly round the test to watch it; your character stays where it stands';
    // The trail, kept at its newest step unless the tester has the mouse (and may have scrolled back).
    win.stepsEl.innerHTML = trailHtml();
    if (!win.mouse) win.stepsEl.scrollLeft = win.stepsEl.scrollWidth;
    const i = openStep();
    win.tipEl.hidden = i < 0;
    if (i >= 0) {
        win.tipEl.innerHTML = tipHtml(i);
        placeTip(i);
    }
    // The bar: the run's state and clock, and what there is to say (the run's end, a note).
    win.dotEl.className = 'dr-tw-dot ' + tone;
    const say = done ? ((win.ended && win.ended.reason) || '') + (win.ended && win.ended.node ? ` · at ${titleOf(win.ended.node)}` : '') : win.note;
    win.sayEl.textContent = say || '';
    win.sayEl.title = say || '';
    tick();
    mark();
}

// ---- the grid follows the run ----

/** The card in the middle of the grid, at its zoom (eased, unless `now`). */
function centreOn(id, now) {
    const g = win && win.grid;
    const card = g && g.cardsEl.querySelector(`.dr-card[data-id="${CSS.escape(id)}"]`);
    const host = g && g.root;
    if (!card || !host || !host.clientWidth) return;
    const z = g.view.z;
    const to = { x: host.clientWidth / 2 - (card.offsetLeft + card.offsetWidth / 2) * z,
                 y: host.clientHeight / 2 - (card.offsetTop + card.offsetHeight / 2) * z };
    if (now) { g.view = { x: to.x, y: to.y, z }; g.applyView(); return; }
    const from = { x: g.view.x, y: g.view.y }, t0 = performance.now();
    win.ease = t0;
    const step = (t) => {
        if (!win || win.ease !== t0) return;
        const k = Math.min(1, (t - t0) / FOLLOW_MS), q = k * (2 - k);
        g.view = { x: from.x + (to.x - from.x) * q, y: from.y + (to.y - from.y) * q, z: g.view.z };
        g.applyView();
        if (k < 1) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
}

// ---- the mouse ----

/** Step `i` open under the trail (or shut again), its card in the middle of the map. */
function openAt(i, toggle) {
    win.open = toggle && win.open === i ? null : i;
    draw();
    if (win.open === null) return;
    trailTo(i);
    placeTip(i);
    const s = win.steps[i];
    if (s) centreOn(s.node);
}

function bind(col, el) {
    // The grid is only looked at: a left press on a card opens its step under the trail (never a drag, a wire or a box);
    // the right button pans and the wheel zooms, as in the editor.
    const grid = el.querySelector('.dr-tw-grid');
    grid.addEventListener('mousedown', (ev) => {
        if (ev.button !== 0) return;
        ev.stopPropagation();
        ev.preventDefault();
        const card = ev.target.closest && ev.target.closest('.dr-card');
        if (!card || !win) return;
        let i = -1;
        for (let k = win.steps.length - 1; k >= 0; k--) if (win.steps[k].node === card.dataset.id && !win.steps[k].undone) { i = k; break; }
        if (i >= 0) openAt(i, false);
    }, true);
    grid.addEventListener('dblclick', (ev) => { ev.stopPropagation(); ev.preventDefault(); }, true);
    // The trail's wheel scrolls it along.
    const steps = col.querySelector('.dr-tw-steps');
    steps.addEventListener('wheel', (ev) => {
        ev.preventDefault();
        steps.scrollLeft += ev.deltaY || ev.deltaX;
        if (win && win.open !== null) placeTip(win.open);
    }, { passive: false });
    col.addEventListener('click', (ev) => {
        const b = ev.target.closest('[data-tw]');
        if (!b || !win || !win.mouse || b.disabled) return;
        const act = b.dataset.tw;
        if (act === 'done') { nuiCallback('directorTestMouse', { on: false }); return; }
        if (act === 'freecam') { nuiCallback('directorTestFreecam', {}); return; }
        if (act === 'take') {
            nuiCallback('directorTestTake', { node: b.dataset.node, pin: b.dataset.pin });
            win.note = `${titleOf(b.dataset.node)}: ${outName(b.dataset.node, b.dataset.pin)} taken`;
            win.open = null;
            draw();
            return;
        }
        if (act === 'step') { openAt(Number(b.dataset.i), true); return; }
        if (act === 'rewind') rewind(Number(b.dataset.i), b.dataset.pin);
    });
    // Back to the game: Esc, or H again (with the mouse the page has the keys, so the game's H mapping does not hear it).
    document.addEventListener('keydown', (ev) => {
        if (!win || !win.mouse || ev.repeat) return;
        if (ev.key === 'Escape' || ev.key === 'h' || ev.key === 'H') { ev.preventDefault(); nuiCallback('directorTestMouse', { on: false }); }
    });
}

async function rewind(i, pin) {
    const s = win.steps[i];
    if (!s) return;
    win.open = null;
    win.note = 'Going back…';
    draw();
    const r = await nuiCallback('directorTestRewind', { seq: s.n, node: s.node, pin });
    const ok = r && r.ok === true && r.data && r.data.ok === true;
    const n = ok ? Number(r.data.removed) || 0 : 0;
    win.note = ok ? `Back to step ${s.n}: on from ${outName(s.node, pin)}` + (n ? `, ${plural(n, 'thing')} made after it taken away` : '')
        : `Could not go back: ${(r && r.why) || 'no answer'}`;
    draw();
}
