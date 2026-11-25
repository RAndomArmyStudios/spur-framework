// ========================================
// DIRECTOR — the blueprint canvas: the grid, the cards, the wires, the mouse
//
// A full-screen field (the column overlays its left side). Inside it one WORLD layer carries the
// cards and the wires and is moved by a single transform: translate(pan) scale(zoom). The grid is
// the field's own background, its spacing and offset set from the same pan and zoom, so the lines
// move and scale with the cards (16 world units fine, 128 strong; the fine one goes when far out).
//
// GEOMETRY IS COMPUTED, NEVER MEASURED. A card's pin rows sit at fixed heights (GEO), so a wire's
// end is known from the card's position and the pin's row alone; nothing reads layout back from
// the DOM, and a hundred cards redraw in one pass.
//
// THE MOUSE, UE5's way:
//   right-drag (or middle-drag)  pan            wheel             zoom about the cursor
//   right-click empty            add a card     right-click card  its menu    right-click pin  break its wires
//   left on a card               select, drag   shift/ctrl        add to the selection
//   left-drag on empty ground    a box: the cards it touches are selected (shift/ctrl: added)
//   left-drag from a pin         a wire: drop it on a pin to connect, on empty ground to add a card there
//   left on a wire               select it      alt-click a pin   break its wires
//   double-click a wire          a Reroute dot on it, to bend it round other cards
//   a comment box                its title drags it and the cards inside it; its corner resizes it;
//                                double-click the title to name it
//
// Zoomed far out (under half size) a card shows its title alone, larger, and a comment its name, so
// the shape of a big scenario still reads (CSS: .dr-far).
//
// It knows nothing of saving or the column: it changes ed.doc and calls ed.changed(label), and
// reports what it cannot do itself (a search, a menu) through ed.ui.
//
// TYPED VALUE PINS (the Systems Creator, html/js/systems/): an editor that sets `ed.typed` gives its
// cards VALUE pins as well, listed on each side after the exec pins, so a pin's row is still its place
// in its side's list. ed.typed = {
//     pinsOf(node, def, doc)  { inputs, outputs }: the card's value pins now, each { pin, label, type, fam,
//                             konst (an unwired input's typed-in value, as text), gone (still wired, no longer named) }
//     canConnect(from, to)    null when a value wire may join these two pin records, else why not
// }. Value wires wear their type's colour, a value input takes ONE wire (a new one replaces it), and an
// exec pin never wires to a value pin. `ed.badPins` (a Set) adds outcomes to wear the error colour.
// Without ed.typed (the Director), none of it runs: its cards draw as they always have.
// ========================================

import { escapeHtml } from '../utils.js';
import { findNode, addLink, breakPin, isWired, removeLink, findComment, COMMENT_MIN, COMMENT_TEXT_MAX } from './doc.js';
import { holds } from './when.js';
import { groupName } from './refs.js';

export const GEO = { W: 236, W_WIDE: 284, HEAD: 30, PAD: 6, ROW: 22, SNAP: 16, DOT_W: 32, DOT_H: 24 };
// THE CARD STYLES (each builder's own pick, kept on their PC: app.js cardStyle; Canvas.setStyle). Each has its own head,
// pin row and padding, which its CSS matches, so a wire still ends on its pin; BODY, WHO and QUOTE are the room its face
// takes in boxes (cardHeight). Classic is GEO's own; Board is the heist board look (css .dr-board).
export const STYLES = {
    classic: { HEAD: GEO.HEAD, PAD: GEO.PAD, ROW: GEO.ROW, BODY: 40, WHO: 26, QUOTE: 17 },
    board: { HEAD: 42, PAD: 8, ROW: 26, BODY: 96, WHO: 36, QUOTE: 18 },
};
export const REROUTE = 'flow.reroute';
const PULSE_MS = 700;
const SETTLE_MS = 150;                     // how long the view must be still before the cards are drawn afresh (settle)
const SHOW_AT_MS = [120, 300, 600, 1000];  // the frames asked for after that, to put the fresh picture on screen
const ZOOM_MIN = 0.25;
const ZOOM_MAX = 2;
const DRAG_START_PX = 4;
const SVG = 'http://www.w3.org/2000/svg';

// Outcomes that mean "it did not happen": their pins wear the error colour (a state, so semantic). A
// card of another resource names its own (def.bad), and every one has Didn't Work.
const BAD_PINS = new Set(['failed', 'missing', 'timeout', 'left', 'lost', 'cancelled', 'nothing', 'walked', 'angry', 'bad', 'didntWork']);

/** Does this outcome mean "it did not happen" (its pin wears the error colour)? Its card's `bad` ones are, too (a
 *  Dialog Line's failed answers). (A Bad deal or Walked away is a branch like any other once a test has run: couldNot
 *  says what is red then.) */
export function badPin(node, def, pin) {
    return BAD_PINS.has(pin) || (!!def && Array.isArray(def.bad) && def.bad.includes(pin));
}

// After a test, red whatever the run did: the card could not do its work (Could not, Took too long, Didn't work).
const COULD_NOT = new Set(['failed', 'timeout', 'didntWork']);
export function couldNot(pin) { return COULD_NOT.has(pin); }

function cap(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : s; }

/** The words of the field an outcome is called by (its card's pinText: an answer's text), '' when there are none. */
function pinWords(node, def, pin) {
    const pt = node && def && def.pinText && def.pinText[pin];
    const v = pt ? node.props[pt.key] : null;
    return typeof v === 'string' ? v.trim() : '';
}

/** What a pin is called beside its card: the words of its field (pinText: an answer's, with its `after`), the type's
 *  label, or its name ('' for in/out). */
export function pinLabel(node, def, pin) {
    const words = pinWords(node, def, pin);
    if (words) return words + (def.pinText[pin].after || '');
    if (def && def.labels && def.labels[pin]) return def.labels[pin];
    return pin === 'in' || pin === 'out' ? '' : cap(pin);
}

/** An Interaction Menu choice's text ('' when empty). */
function menuText(node, i) {
    const v = node.props['item' + i];
    return typeof v === 'string' ? v.trim() : '';
}

/** Does an Interaction Menu choice open choices of its own (so it is never chosen itself)? */
export function opensMenu(node, i) {
    for (let j = 1; j <= 8; j++) {
        if (String(j) !== String(i) && menuText(node, j) && String(node.props['item' + j + 'Under']) === String(i)) return true;
    }
    return false;
}

// How wide a card is and what its face is are its type's ui (server/director/nodes.lua): `defs` is the card types of
// the editor the canvas draws for (its ed.cards; the Director's and the Systems Creator's are each their own).
const uiOf = (node, defs) => { const d = defs && defs.get(node.type); return (d && d.ui) || {}; };

/** The width of a card on the canvas (a Reroute is a dot; a card whose ui says wide, a Dialog Line, is wide). */
export function cardWidth(node, defs) {
    if (node.type === REROUTE) return GEO.DOT_W;
    return uiOf(node, defs).wide ? GEO.W_WIDE : GEO.W;
}

/** A card's height for boxes (the marquee, a comment's contents, framing): its head and pin rows,
 *  and room for its face, in the style's sizes (`geo`: STYLES). Computed, as everything here is. */
function cardHeight(node, pins, geo, defs) {
    if (node.type === REROUTE) return GEO.DOT_H;
    const rows = Math.max(pins.inputs.length, pins.outputs.length, 1);
    // A quote face (a Dialog Line's) shows all it says (about 44 letters a line on its wide card), its name above.
    if (uiOf(node, defs).face === 'quote') {
        const len = typeof node.props.line === 'string' ? node.props.line.length + 2 : 16;
        return geo.HEAD + geo.PAD * 2 + rows * geo.ROW + geo.WHO + Math.ceil(len / 44) * geo.QUOTE;
    }
    return geo.HEAD + geo.PAD * 2 + rows * geo.ROW + geo.BODY;
}

/** HOW BIG A CARD'S NAME CAN BE, ZOOMED FAR OUT (css .dr-far): the largest size, in the card's own px, at which its
 *  title fits across the card (w x h, less the 12/8 px padding) in up to three lines, its longest word on one line.
 *  Far out the name is all a card shows, drawn at a size that reads on screen until this stops it. Letters are taken
 *  as 0.58 of the size wide, lines as 1.12 of it; words do not break evenly, so two or three lines keep room spare. */
function farFit(title, w, h) {
    const text = String(title);
    const len = Math.max(4, text.length);
    const longest = Math.max(1, ...text.split(/\s+/).map((word) => word.length));
    let best = 0;
    for (let lines = 1; lines <= 3; lines++) {
        const byWidth = ((w - 24) * lines) / (len * 0.58) * (lines > 1 ? 0.82 : 1);
        const byHeight = (h - 16) / (lines * 1.12);
        best = Math.max(best, Math.min(byWidth, byHeight));
    }
    best = Math.min(best, (w - 24) / (longest * 0.6));
    return Math.max(8, Math.floor(Math.min(best, 72)));
}

/** A card's pins as drawn: the type's, minus an outcome that is one only some of the time while it is not (its
 *  pinWhen, when.js: a Dialog Line's empty answer, No answer with no time limit) and an Interaction Menu's empty
 *  choices, unless one is wired, so its wire never vanishes. An unknown type draws the pins its wires use. */
export function pinsOf(doc, node, def) {
    const label = (pin) => {
        if (def && def.labels && def.labels[pin]) return def.labels[pin];
        return pin === 'in' || pin === 'out' ? '' : cap(pin);
    };
    if (!def) {
        const ins = new Set(), outs = new Set();
        for (const l of doc.links) {
            if (l.to.node === node.id) ins.add(l.to.pin);
            if (l.from.node === node.id) outs.add(l.from.pin);
        }
        return {
            inputs: [...ins].map((pin) => ({ pin, label: pin })),
            outputs: [...outs].map((pin) => ({ pin, label: pin, tone: '' })),
        };
    }
    const inputs = (def.inputs || []).map((pin) => ({ pin, label: label(pin) }));
    const outputs = [];
    for (const pin of def.outputs || []) {
        const when = def.pinWhen ? def.pinWhen[pin] : undefined;
        if (when !== undefined && when !== null && !holds(when, node.props, def.props) && !isWired(doc, node.id, pin, 'out')) continue;
        if (def.prompt && def.prompt.menu && /^item[1-8]$/.test(pin)) {
            // An empty choice, or one that opens a menu, is no outcome: no pin, unless one is wired (the server's own
            // rule, nodes_heist.lua's unusedPin).
            const i = pin.slice(4);
            if ((!menuText(node, i) || opensMenu(node, i)) && !isWired(doc, node.id, pin, 'out')) continue;
        }
        // (One called by a field's words: those, or its `empty` while there are none.)
        const pt = def.pinText && def.pinText[pin];
        const text = pt && !pinWords(node, def, pin) && pt.empty ? pt.empty : pt ? pinLabel(node, def, pin) : label(pin);
        outputs.push({ pin, label: text, tone: badPin(node, def, pin) ? 'bad' : '' });
    }
    return { inputs, outputs };
}

/** Where a pin's dot is, in world units, in the style's sizes (`geo`: STYLES). */
function pinPoint(node, pins, side, pin, geo, defs) {
    const listed = side === 'in' ? pins.inputs : pins.outputs;
    const i = listed.findIndex((p) => p.pin === pin);
    if (i < 0) return null;
    if (node.type === REROUTE) {
        return { x: side === 'in' ? node.x : node.x + GEO.DOT_W, y: node.y + GEO.DOT_H / 2 };
    }
    return {
        x: side === 'in' ? node.x : node.x + cardWidth(node, defs),
        y: node.y + geo.HEAD + geo.PAD + i * geo.ROW + geo.ROW / 2,
    };
}

function wirePath(a, b) {
    const dx = Math.max(48, Math.abs(b.x - a.x) * 0.5);
    return `M ${a.x} ${a.y} C ${a.x + dx} ${a.y}, ${b.x - dx} ${b.y}, ${b.x} ${b.y}`;
}

/** What a card says on its face, under its pins: its settings in a few words. `lore`: the lore characters, to
 *  name one a field picks; `cards`: the card list, to name a card one picks. */
function summaryOf(doc, node, def, lore, cards) {
    if (!def) return `<div class="dr-card-line dr-bad">Unknown card: ${escapeHtml(node.type)}</div>`;
    const p = node.props;
    const worldName = (id) => {
        if (groupName(id)) return `Group: ${groupName(id)}`;
        const w = (doc.world || []).find((x) => x.id === id);
        return w ? (w.label || w.id) : (id ? id + ' (missing)' : '');
    };
    // A face of its own (its ui.face): a talking card's who and what they say ('quote': its npc, Name shown and line,
    // the NPC's own name unless it is an Alternative name, server/director/nodes_world.lua shownName), an Interaction
    // Menu's ('menu').
    const face = (def.ui && def.ui.face) || '';
    if (face === 'quote') {
        const typed = typeof p.speaker === 'string' ? p.speaker.trim() : '';
        const who = (p.nameShown === 'other' && typed) || worldName(p.npc) || 'Nobody yet';
        const line = typeof p.line === 'string' && p.line ? `“${p.line}”` : 'Nothing said yet';
        return `<div class="dr-card-who">${escapeHtml(who)}</div><div class="dr-card-quote">${escapeHtml(line)}</div>`;
    }
    if (face === 'menu') {
        // On what, the prompt, and how many choices (with how many open a menu): not "Under top".
        let n = 0, menus = 0;
        for (let i = 1; i <= 8; i++) {
            if (menuText(node, i)) { n++; if (opensMenu(node, i)) menus++; }
        }
        const line = (k, v) => `<div class="dr-card-line"><span>${escapeHtml(k)}</span> <em>${escapeHtml(v)}</em></div>`;
        return line('On', worldName(p.at) || 'nothing yet') + line('Prompt', typeof p.label === 'string' && p.label ? p.label : 'Use')
            + line('Choices', `${n}${menus ? ` (${menus} open${menus === 1 ? 's' : ''} more)` : ''}`);
    }
    const rows = [];
    for (const f of def.props || []) {
        let v = p[f.key];
        if (v === undefined || v === null || v === '') continue;
        if (f.key === 'onlyOnce') continue;   // (on its head instead: "Once")
        if (f.kind === 'world') v = worldName(v);
        else if (f.kind === 'worlds') {
            if (typeof v === 'string') v = [v];   // (one, as a card saved it before its upgrade)
            if (!Array.isArray(v) || !v.length) continue;
            v = v.length <= 2 ? v.map(worldName).join(', ') : `${worldName(v[0])} and ${v.length - 1} more`;
        }
        else if (f.kind === 'lore' && typeof v === 'string') {
            const c = (lore || []).find((x) => x.key === v);
            v = c ? c.name : v + ' (missing)';
        }
        else if (f.kind === 'card' && typeof v === 'string') {
            const n = (doc.nodes || []).find((x) => x.id === v);
            const d = n && cards ? cards.get(n.type) : null;
            v = n ? (d ? d.title : n.type) : 'a card that is gone';
        }
        else if (f.kind === 'entries') {
            // Another resource's list: how many (the one entry's own words when there is one).
            if (!Array.isArray(v) || !v.length) continue;
            v = v.length === 1 && v[0] && typeof v[0].text === 'string' && v[0].text ? v[0].text : `${v.length} of them`;
        }
        else if ((f.kind === 'select' || f.kind === 'players') && f.optionLabels && typeof v === 'string' && f.optionLabels[v]) v = f.optionLabels[v];
        else if (f.kind === 'bool') v = v ? 'yes' : 'no';
        else if (f.kind === 'duration') v = `${v} s`;
        else if (f.kind === 'take') {
            // One of the car's takes (the car the field `of` names), by its name.
            const car = f.of ? (doc.world || []).find((x) => x.id === p[f.of]) : null;
            const t = car && car.def && Array.isArray(car.def.takes) ? car.def.takes.find((x) => String(x.id) === String(v)) : null;
            v = t ? (t.label || 'Driving event ' + t.id) : 'a driving event that is gone';
        }
        else if (typeof v === 'object') v = v.var !== undefined ? `{${v.var}}` : '…';
        // (A recording's link, a field whose ui is hearLink: its file's name, not the whole address.)
        if (f.ui === 'hearLink') v = String(v).split('/').pop();
        rows.push(`<div class="dr-card-line"><span>${escapeHtml(f.label || f.key)}</span> <em>${escapeHtml(String(v))}</em></div>`);
        if (rows.length >= 3) break;
    }
    return rows.join('');
}

export class Canvas {
    /**
     * @param {HTMLElement} root  the full-screen field
     * @param {object} ed         the editor: { doc, cards (Map), selected (Set), selectedLink,
     *                            problems (Map id -> { error, messages }), changed(label), select(ids),
     *                            ui: { search(at), cardMenu(at, id), status(text, tone), leftEdge(), rightEdge() } }
     */
    constructor(root, ed) {
        this.root = root;
        this.ed = ed;
        this.view = { x: 0, y: 0, z: 1 };
        this.pins = new Map();     // node id -> pinsOf(...) as last drawn
        this.drag = null;          // what the mouse is doing: pan | cards | wire | press | marquee | note | resize
        this.mouseAt = null;       // where the pointer last was over the field, on the screen (Paste)
        this.pulseTimers = new Map();   // element -> its pulse's end
        this.uses = null;               // the cards using the World row open in the column (setUses)
        this.style = 'classic';         // the cards' look (setStyle), and its sizes
        this.geo = STYLES.classic;
        this.settleTimer = null;        // settle(), once the view is still
        this.showTimers = [];

        root.classList.add('dr-canvas');
        root.innerHTML = '<div class="dr-world"><div class="dr-notes"></div><svg class="dr-wires"></svg><div class="dr-cards"></div></div>'
            + '<div class="dr-marquee"></div><div class="dr-empty"></div><i class="dr-ticker"></i>';
        this.world = root.querySelector('.dr-world');
        this.notesEl = root.querySelector('.dr-notes');
        this.svg = root.querySelector('.dr-wires');
        this.cardsEl = root.querySelector('.dr-cards');
        this.marqueeEl = root.querySelector('.dr-marquee');
        this.emptyEl = root.querySelector('.dr-empty');
        this.ticker = root.querySelector('.dr-ticker');

        // (The variant buttons over the field are their own: app.js drawVariants.)
        const own = (e) => !!(e.target && e.target.closest && e.target.closest('.dr-variants'));
        root.addEventListener('mousedown', (e) => { if (!own(e)) this.onDown(e); });
        root.addEventListener('dblclick', (e) => { if (!own(e)) this.onDouble(e); });
        // Where the pointer last was on the field, on the SCREEN: Paste asks it in world units then,
        // so a pan, a zoom or another scenario since does not send the cards somewhere off it.
        root.addEventListener('mousemove', (e) => { this.mouseAt = { x: e.clientX, y: e.clientY }; });
        root.addEventListener('wheel', (e) => { if (!own(e)) this.onWheel(e); }, { passive: false });
        root.addEventListener('contextmenu', (e) => e.preventDefault());
        this.onMoveBound = (e) => this.onMove(e);
        this.onUpBound = (e) => this.onUp(e);
        this.applyView();
    }

    /** A card's pins as drawn: its exec pins (pinsOf), and for a typed editor (ed.typed) its value pins
     *  after them on each side. */
    pinsFor(n) {
        const doc = this.ed.doc;
        const def = this.ed.cards.get(n.type);
        const pins = pinsOf(doc, n, def);
        const bad = this.ed.badPins;
        if (bad && def) for (const p of pins.outputs) if (bad.has(p.pin)) p.tone = 'bad';
        const T = this.ed.typed;
        if (T && def && n.type !== REROUTE) {
            const v = T.pinsOf(n, def, doc) || {};
            for (const r of v.inputs || []) pins.inputs.push(Object.assign({}, r, { value: true, tone: r.gone ? 'bad' : '' }));
            for (const r of v.outputs || []) pins.outputs.push(Object.assign({}, r, { value: true, tone: r.gone ? 'bad' : '' }));
        }
        return pins;
    }

    /** The pin record drawn for a card's pin, or null. */
    pinRecord(nodeId, side, pin) {
        const pins = this.pins.get(nodeId);
        if (!pins) return null;
        return (side === 'in' ? pins.inputs : pins.outputs).find((p) => p.pin === pin) || null;
    }

    // ---- the view ----

    applyView() {
        const { x, y, z } = this.view;
        this.world.style.transform = `translate(${x}px, ${y}px) scale(${z})`;
        const r = this.root.style;
        // The zoom, for what is drawn at a size that reads on screen however far out (css .dr-far: card names).
        r.setProperty('--dr-z', z.toFixed(3));
        if (this.style === 'board') {
            // The Board's one layer of dots: every second snap, every eighth far out (where they would crowd).
            const s = GEO.SNAP * (z < 0.5 ? 8 : 2) * z;
            r.backgroundSize = `${s}px ${s}px`;
            r.backgroundPosition = `${x}px ${y}px`;
        } else {
            const fine = GEO.SNAP * z, strong = GEO.SNAP * 8 * z;
            r.backgroundSize = `${strong}px ${strong}px, ${strong}px ${strong}px, ${fine}px ${fine}px, ${fine}px ${fine}px`;
            r.backgroundPosition = `${x}px ${y}px, ${x}px ${y}px, ${x}px ${y}px, ${x}px ${y}px`;
        }
        this.root.classList.toggle('dr-far', z < 0.5);
        clearTimeout(this.settleTimer);
        this.settleTimer = setTimeout(() => this.settle(), SETTLE_MS);
    }

    /** THE CARDS SHARP AGAIN, once the view is still. The world moves as one layer (css .dr-world, will-change:
     *  transform), so a pan or a zoom repaints nothing; but the browser may keep that layer's picture at the size it
     *  was drawn and stretch it, so zoomed in the cards stay soft. Or it draws them sharp, but FiveM's browser puts a new
     *  picture on screen only when something on the page changes, so the sharp one waits for a click or a drag (which
     *  is why one sometimes fixed it). So: the layer is let go for two frames and taken up again (drawn afresh at
     *  the zoom it is shown at), and then a few frames are asked for over the next second (the ticker, a dot nobody
     *  sees: each change of it is a new frame), so the fresh picture is shown however late it is ready. */
    settle() {
        const w = this.world;
        w.style.willChange = 'auto';
        requestAnimationFrame(() => requestAnimationFrame(() => {
            w.style.willChange = '';   // the stylesheet's again
            for (const t of this.showTimers) clearTimeout(t);
            this.showTimers = SHOW_AT_MS.map((ms, i) => setTimeout(() => {
                if (this.ticker) this.ticker.style.opacity = i % 2 ? '0.01' : '0.02';
            }, ms));
        }));
    }

    /** The cards' look: 'classic' or 'board' (STYLES; the CSS is .dr-board's). Draws everything again. */
    setStyle(name) {
        this.style = STYLES[name] ? name : 'classic';
        this.geo = STYLES[this.style];
        this.root.classList.toggle('dr-board', this.style === 'board');
        this.applyView();
        this.render();
    }

    /** The Board's step numbers: the order a run reaches the cards in, ONE PATH AT A TIME. From each card nothing leads
     *  into (top to bottom), a path is followed to its end before its branches are, each card's next ones taken as they
     *  sit on the board (the top one first), so a run's main line counts 01, 02, 03 with no gaps and the other
     *  starting cards' paths come after. (Level by level, it was, the paths' numbers took turns and skipped.) A Reroute
     *  is passed through, unnumbered; a card no wire reaches (a Fail Condition) has none. Map: card id -> number. */
    stepsOf(doc) {
        const byId = new Map(doc.nodes.map((n) => [n.id, n]));
        const into = new Set(), next = new Map();
        for (const l of doc.links) {
            into.add(l.to.node);
            if (!next.has(l.from.node)) next.set(l.from.node, []);
            next.get(l.from.node).push(l.to.node);
        }
        const byPlace = (a, b) => (a.y - b.y) || (a.x - b.x);
        const starts = doc.nodes.filter((n) => !into.has(n.id) && next.has(n.id)).sort(byPlace);
        const seen = new Set();
        const steps = new Map();
        for (const start of starts) {
            const stack = [start];
            while (stack.length) {
                const n = stack.pop();
                // (Two wires into the same card, or a loop back: it is numbered once, the first time it is reached.)
                if (seen.has(n.id)) continue;
                seen.add(n.id);
                if (n.type !== REROUTE) steps.set(n.id, steps.size + 1);
                const outs = (next.get(n.id) || []).map((id) => byId.get(id)).filter(Boolean).sort(byPlace);
                for (let i = outs.length - 1; i >= 0; i--) if (!seen.has(outs[i].id)) stack.push(outs[i]);
            }
        }
        return steps;
    }

    /** Where a wire really comes from, back through any Reroute dots: { node, pin } (the Board colours it by that card). */
    sourceOf(link) {
        const doc = this.ed.doc;
        let node = findNode(doc, link.from.node), pin = link.from.pin;
        for (let hops = 0; node && node.type === REROUTE && hops < 32; hops++) {
            const back = doc.links.find((l) => l.to.node === node.id);
            if (!back) break;
            node = findNode(doc, back.from.node);
            pin = back.from.pin;
        }
        return { node, pin };
    }

    /** A screen point in world units. */
    toWorld(cx, cy) {
        const rect = this.root.getBoundingClientRect();
        return { x: (cx - rect.left - this.view.x) / this.view.z, y: (cy - rect.top - this.view.y) / this.view.z };
    }

    /** The right edge of the uncovered field, on the screen: a card's page on the right covers the rest. */
    rightOf(rect) {
        return Math.min(rect.right, this.ed.ui.rightEdge ? this.ed.ui.rightEdge() : rect.right);
    }

    /** Where Paste puts cards: the pointer, if it is on the uncovered field now, else its middle. */
    pastePoint() {
        const p = this.mouseAt;
        const rect = this.root.getBoundingClientRect();
        const left = Math.max(rect.left, this.ed.ui.leftEdge());
        if (p && p.x >= left && p.x <= this.rightOf(rect) && p.y >= rect.top && p.y <= rect.bottom) return this.toWorld(p.x, p.y);
        return this.centre();
    }

    /** The middle of the part of the field the column (and a card's page on the right) does not cover, in world units. */
    centre() {
        const rect = this.root.getBoundingClientRect();
        const left = Math.max(rect.left, this.ed.ui.leftEdge());
        return this.toWorld((left + this.rightOf(rect)) / 2, (rect.top + rect.bottom) / 2);
    }

    zoomAt(cx, cy, z) {
        z = Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, z));
        const rect = this.root.getBoundingClientRect();
        const px = cx - rect.left, py = cy - rect.top;
        const k = z / this.view.z;
        this.view.x = px - (px - this.view.x) * k;
        this.view.y = py - (py - this.view.y) * k;
        this.view.z = z;
        this.applyView();
    }

    /** Fit cards in the uncovered part of the field: these ids, or all of them. */
    frame(ids) {
        const doc = this.ed.doc;
        const nodes = (ids && ids.length ? ids.map((id) => findNode(doc, id)).filter(Boolean) : doc.nodes);
        const rect = this.root.getBoundingClientRect();
        const left = Math.max(0, this.ed.ui.leftEdge() - rect.left);
        const w = this.rightOf(rect) - rect.left - left, h = rect.height;
        const whole = !(ids && ids.length);
        if (!nodes.length && !(whole && (doc.comments || []).length)) {
            this.view = { x: left + w / 2 - 120, y: h / 2 - 60, z: 1 };
            this.applyView();
            return;
        }
        let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
        for (const n of nodes) {
            const pins = this.pins.get(n.id) || this.pinsFor(n);
            x0 = Math.min(x0, n.x);
            y0 = Math.min(y0, n.y);
            x1 = Math.max(x1, n.x + cardWidth(n, this.ed.cards));
            y1 = Math.max(y1, n.y + cardHeight(n, pins, this.geo, this.ed.cards) + 20);
        }
        // The whole scenario: its comment boxes too.
        if (whole) {
            for (const c of doc.comments || []) {
                x0 = Math.min(x0, c.x); y0 = Math.min(y0, c.y);
                x1 = Math.max(x1, c.x + c.w); y1 = Math.max(y1, c.y + c.h);
            }
        }
        const margin = 80;
        const z = Math.min(1.25, Math.max(ZOOM_MIN, Math.min((w - margin * 2) / (x1 - x0), (h - margin * 2) / (y1 - y0))));
        this.view.z = z;
        this.view.x = left + (w - (x1 - x0) * z) / 2 - x0 * z;
        this.view.y = (h - (y1 - y0) * z) / 2 - y0 * z;
        this.applyView();
    }

    // ---- drawing ----

    /** Everything, from the document. */
    render() {
        const ed = this.ed, doc = ed.doc;
        if (!doc) {
            this.cardsEl.innerHTML = '';
            this.notesEl.innerHTML = '';
            this.svg.innerHTML = '';
            return;
        }
        this.pins.clear();
        // (Not while a comment's name is being typed: its box would go from under the caret, and the keys to the game.
        // Its finish draws them once the name is kept or dropped.)
        if (!this.renaming) this.renderNotes();
        this.steps = this.style === 'board' ? this.stepsOf(doc) : null;
        this.cardsEl.innerHTML = doc.nodes.map((n) => this.cardHtml(n)).join('');
        // Far out each card shows its name alone, as large as fits the card as drawn (its face is as tall as what it
        // says, not the boxes' room for it). Measured once per draw; while the page is out of sight (0 tall) the
        // boxes' size stays.
        for (const el of this.cardsEl.querySelectorAll('.dr-card')) this.fitFar(el);
        this.renderWires();
        this.emptyEl.style.display = doc.nodes.length ? 'none' : '';
        // (What a view puts on its cards after each draw: the test map's marks, testwin.js.)
        if (ed.afterRender) ed.afterRender();
    }

    /** One card drawn again where it is (a field of its being typed in: everything else is as it was), and the wires,
     *  which its pins may have moved. Not drawn yet: everything (render). */
    renderCard(id) {
        const doc = this.ed.doc;
        const n = doc && findNode(doc, id);
        const el = n && this.cardsEl.querySelector(`.dr-card[data-id="${CSS.escape(id)}"]`);
        if (!el || this.steps === undefined) { this.render(); return; }
        const box = document.createElement('div');
        box.innerHTML = this.cardHtml(n);
        const fresh = box.firstElementChild;
        el.replaceWith(fresh);
        this.fitFar(fresh);
        this.renderWires();
        if (this.ed.afterRender) this.ed.afterRender();
    }

    /** A card's far-out name size, from its face as drawn. */
    fitFar(el) {
        const h = el.offsetHeight;
        const t = el.querySelector('.dr-card-title');
        if (h > 0 && t) el.style.setProperty('--dr-fit', farFit(t.textContent, el.offsetWidth, h) + 'px');
    }

    /** One card as drawn (its pins kept in this.pins), its step from the last whole draw (this.steps). */
    cardHtml(n) {
        const ed = this.ed, doc = ed.doc;
        const board = this.style === 'board';
        const steps = this.steps;
        const def = ed.cards.get(n.type);
        const pins = this.pinsFor(n);
        this.pins.set(n.id, pins);
        if (n.type === REROUTE && def) {
            // A dot: its two pins and nothing else; the middle drags it. Its problems (Check's, the
            // test's fault) show as a card's do, the messages in its tooltip.
            const cls = ['dr-card', 'dr-reroute', 'kind-flow'];
            if (ed.selected.has(n.id)) cls.push('selected');
            cls.push(...this.ranClasses(n.id));
            let prob = ed.problems.get(n.id);
            if (ed.lastTest && ed.lastTest.fault === n.id) {
                prob = { error: true, messages: [...(prob ? prob.messages : []), 'The test went wrong here: ' + (ed.lastTest.reason || '?')] };
            }
            if (prob) cls.push(prob.error ? 'has-error' : 'has-warn');
            const tip = prob ? 'Reroute\n' + prob.messages.join('\n') : 'Reroute';
            const pin = (side, name) => `<div class="dr-pin ${side}${isWired(doc, n.id, name, side) ? ' wired' : ''}" data-pin="${escapeHtml(name)}" data-side="${side}"><i></i></div>`;
            return `<div class="${cls.join(' ')}" data-id="${escapeHtml(n.id)}" title="${escapeHtml(tip)}" `
                + `style="left:${n.x}px;top:${n.y}px;width:${GEO.DOT_W}px;height:${GEO.DOT_H}px">`
                + pin('in', def.inputs[0] || 'in') + pin('out', def.outputs[0] || 'out') + '</div>';
        }
        let prob = ed.problems.get(n.id);
        // The card the last test went wrong at: an error like Check's.
        if (ed.lastTest && ed.lastTest.fault === n.id) {
            prob = { error: true, messages: [...(prob ? prob.messages : []), 'The test went wrong here: ' + (ed.lastTest.reason || '?')] };
        }
        // (Another resource's card: its own colour, def.tint, set where the card list is read.)
        const cls = ['dr-card', 'kind-' + (def ? (def.tint || def.category) : 'unknown')];
        if (ed.selected.has(n.id)) cls.push('selected');
        if (prob) cls.push(prob.error ? 'has-error' : 'has-warn');
        cls.push(...this.ranClasses(n.id));
        if (this.uses && this.uses.has(n.id)) cls.push('uses');
        if (def && def.event) cls.push('is-event');
        if (def && def.locked) cls.push('locked');   // another resource's, kept to a permission they lack
        const rows = Math.max(pins.inputs.length, pins.outputs.length);
        const pinRow = (p, side) => {
            const wired = isWired(doc, n.id, p.pin, side);
            // A value pin (ed.typed): its type's colour, the exact type on hover, and an unwired
            // input's typed-in value beside its name.
            const val = p.value ? ` val v-${escapeHtml(p.fam || 'any')}` : '';
            const tip = p.value ? ` title="${escapeHtml(p.gone ? 'No longer one of its pins: take the wire off' : (p.type || 'any'))}"` : '';
            const konst = p.value && side === 'in' && !wired && p.konst ? `<em class="dr-const">${escapeHtml(p.konst)}</em>` : '';
            return `<div class="dr-pin ${side}${wired ? ' wired' : ''}${p.tone ? ' tone-' + p.tone : ''}${val}" data-pin="${escapeHtml(p.pin)}" data-side="${side}"${tip}>`
                + (side === 'in' ? '<i></i>' : '')
                + `<span>${escapeHtml(p.label)}</span>${konst}`
                + (side === 'out' ? '<i></i>' : '')
                + '</div>';
        };
        // (The Board says how many things to fix, on its head; Classic a ! or a ?.)
        const badgeText = board ? `${prob ? prob.messages.length : 0} to fix` : (prob && prob.error ? '!' : '?');
        const badge = prob ? `<b class="dr-badge" title="${escapeHtml(prob.messages.join('\n'))}">${badgeText}</b>` : '';
        // Only Once switched on (server/director/nodes.lua): said on its head, where a glance finds it.
        const once = n.props && n.props.onlyOnce === true
            ? '<span class="dr-once" title="Only once: if the scenario comes back to it, it is skipped and goes straight on">Once</span>' : '';
        // The Board's step in the run (stepsOf), at the head's end.
        const step = steps && steps.has(n.id) ? `<span class="dr-step">${String(steps.get(n.id)).padStart(2, '0')}</span>` : '';
        const title = def ? def.title : n.type;
        const width = cardWidth(n, this.ed.cards);
        // (Its far-out name size from the boxes' height; measured again once drawn: fitFar.)
        const fit = farFit(title, width, cardHeight(n, pins, this.geo, this.ed.cards));
        return `<div class="${cls.join(' ')}" data-id="${escapeHtml(n.id)}" style="left:${n.x}px;top:${n.y}px;width:${width}px;--dr-fit:${fit}px">`
            + `<div class="dr-card-head"><span class="dr-card-title">${escapeHtml(title)}</span>${once}${badge}${step}</div>`
            + `<div class="dr-card-pins" style="height:${rows * this.geo.ROW + this.geo.PAD * 2}px">`
            + `<div class="dr-pin-col in">${pins.inputs.map((p) => pinRow(p, 'in')).join('')}</div>`
            + `<div class="dr-pin-col out">${pins.outputs.map((p) => pinRow(p, 'out')).join('')}</div>`
            + '</div>'
            + `<div class="dr-card-body">${summaryOf(doc, n, def, ed.lore, ed.cards)}</div>`
            + '</div>';
    }

    /** Only the wires (a drag moves cards without redrawing them). */
    renderWires() {
        const doc = this.ed.doc;
        const parts = [];
        for (const l of doc.links) {
            const a = findNode(doc, l.from.node), b = findNode(doc, l.to.node);
            if (!a || !b) continue;
            const pinsA = this.pins.get(a.id) || this.pinsFor(a);
            const pa = pinPoint(a, pinsA, 'out', l.from.pin, this.geo, this.ed.cards);
            const pb = pinPoint(b, this.pins.get(b.id) || this.pinsFor(b), 'in', l.to.pin, this.geo, this.ed.cards);
            if (!pa || !pb) continue;
            const d = wirePath(pa, pb);
            const t = this.ed.lastTest;
            const sel = this.ed.selectedLink === l.id ? ' selected'
                : (t && t.shownLinks.has(l.id) ? ' ran ran-' + (t.badLinks.has(l.id) ? 'bad' : t.tone) : '');
            // A value wire wears its type's colour (ed.typed).
            const rec = this.ed.typed ? pinsA.outputs.find((p) => p.pin === l.from.pin) : null;
            const val = rec && rec.value ? ` val v-${escapeHtml(rec.fam || 'any')}` : '';
            // The card it comes from (through any Reroute), for the Board, which wears its colour, and red from an outcome
            // that went wrong (css .dr-board .dr-wire).
            let from = '';
            if (this.style === 'board') {
                const src = this.sourceOf(l);
                const sd = src.node && this.ed.cards.get(src.node.type);
                const srec = src.node && (this.pins.get(src.node.id) || this.pinsFor(src.node)).outputs.find((p) => p.pin === src.pin);
                from = ` kind-${escapeHtml(sd ? (sd.tint || sd.category) : 'unknown')}${srec && srec.tone === 'bad' ? ' bad' : ''}`;
            }
            const id = escapeHtml(l.id);
            parts.push(`<path class="dr-wire${val}${from}${sel}" data-wire="${id}" d="${d}"/><path class="dr-wire-hit" data-link="${id}" d="${d}"/>`);
        }
        if (this.drag && this.drag.kind === 'wire' && this.drag.to) {
            const rec = this.drag.rec;
            const val = rec && rec.value ? ` val v-${escapeHtml(rec.fam || 'any')}` : '';
            parts.push(`<path class="dr-wire temp${val}" d="${this.tempWirePath()}"/>`);
        }
        this.svg.innerHTML = parts.join('');
    }

    /** The wire being drawn from a pin, to the pointer. */
    tempWirePath() {
        const a = this.drag.anchor, b = this.drag.to;
        return this.drag.side === 'out' ? wirePath(a, b) : wirePath(b, a);
    }

    /** A drag's wires, moved in place: only those of the cards in `ids` (a Set), their shapes, nothing rebuilt (a
     *  whole redraw a mouse move was every wire's). */
    moveWiresOf(ids) {
        const doc = this.ed.doc;
        const byId = new Map(doc.nodes.map((n) => [n.id, n]));
        for (const l of doc.links) {
            if (!ids.has(l.from.node) && !ids.has(l.to.node)) continue;
            const a = byId.get(l.from.node), b = byId.get(l.to.node);
            if (!a || !b) continue;
            const pa = pinPoint(a, this.pins.get(a.id) || this.pinsFor(a), 'out', l.from.pin, this.geo, this.ed.cards);
            const pb = pinPoint(b, this.pins.get(b.id) || this.pinsFor(b), 'in', l.to.pin, this.geo, this.ed.cards);
            if (!pa || !pb) continue;
            const d = wirePath(pa, pb);
            const id = CSS.escape(l.id);
            for (const p of this.svg.querySelectorAll(`[data-wire="${id}"], [data-link="${id}"]`)) p.setAttribute('d', d);
        }
    }

    /** Move a drawn card without a full redraw. */
    placeCard(node) {
        const el = this.cardsEl.querySelector(`.dr-card[data-id="${CSS.escape(node.id)}"]`);
        if (el) {
            el.style.left = node.x + 'px';
            el.style.top = node.y + 'px';
        }
    }

    // ---- comment boxes ----

    /** The comment boxes, under the wires and the cards. */
    renderNotes() {
        const ed = this.ed;
        // The bigger first, so a box inside another (or made round cards already boxed) is drawn on
        // top of it, its title and corner still there to take.
        const notes = (ed.doc.comments || []).slice().sort((a, b) => b.w * b.h - a.w * a.h);
        this.notesEl.innerHTML = notes.map((c) => {
            const sel = ed.selectedNote === c.id ? ' selected' : '';
            const text = c.text ? escapeHtml(c.text) : '<span class="dr-note-none">Comment (double-click to name it)</span>';
            return `<div class="dr-note${sel}" data-note="${escapeHtml(c.id)}" style="left:${c.x}px;top:${c.y}px;width:${c.w}px;height:${c.h}px">`
                + `<div class="dr-note-head">${text}</div><div class="dr-note-grip" title="Drag to resize"></div></div>`;
        }).join('');
    }

    placeNote(c) {
        const el = this.notesEl.querySelector(`.dr-note[data-note="${CSS.escape(c.id)}"]`);
        if (!el) return;
        el.style.left = c.x + 'px';
        el.style.top = c.y + 'px';
        el.style.width = c.w + 'px';
        el.style.height = c.h + 'px';
    }

    /** Is a card inside a comment box (its head within it)? What moves with the box. */
    inNote(n, c) {
        return n.x >= c.x && n.y >= c.y && n.x + cardWidth(n, this.ed.cards) <= c.x + c.w && n.y + Math.min(this.geo.HEAD, GEO.DOT_H) <= c.y + c.h;
    }

    /** Is a comment box wholly inside another? It moves with it. */
    noteInNote(o, c) {
        return o !== c && o.x >= c.x && o.y >= c.y && o.x + o.w <= c.x + c.w && o.y + o.h <= c.y + c.h;
    }

    /** The box round some cards, in world units, with room for a comment's title above them. */
    boxOf(ids) {
        const doc = this.ed.doc;
        let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
        for (const id of ids) {
            const n = findNode(doc, id);
            if (!n) continue;
            const pins = this.pins.get(n.id) || this.pinsFor(n);
            x0 = Math.min(x0, n.x); y0 = Math.min(y0, n.y);
            x1 = Math.max(x1, n.x + cardWidth(n, this.ed.cards)); y1 = Math.max(y1, n.y + cardHeight(n, pins, this.geo, this.ed.cards));
        }
        if (x0 === Infinity) return null;
        const pad = GEO.SNAP * 2;
        return { x: x0 - pad, y: y0 - pad - GEO.HEAD, w: x1 - x0 + pad * 2, h: y1 - y0 + pad * 2 + GEO.HEAD };
    }

    /** Name a comment box where it is: a field over its title (Enter keeps, Esc leaves it). */
    renameNote(id) {
        const c = findComment(this.ed.doc, id);
        const head = this.notesEl.querySelector(`.dr-note[data-note="${CSS.escape(id)}"] .dr-note-head`);
        if (!c || !head) return;
        head.innerHTML = `<input class="dr-note-input" type="text" maxlength="${COMMENT_TEXT_MAX}" spellcheck="false">`;
        const input = head.querySelector('input');
        input.value = c.text || '';
        // Once, whichever comes first: Enter, Esc, a save or a click on the grid (commitRename), or
        // leaving the field. A page without the focus fires no blur, so none of them waits for one.
        let done = false;
        const finish = (keep) => {
            if (done) return;
            done = true;
            if (this.renaming && this.renaming.input === input) this.renaming = null;
            const text = input.value.trim().slice(0, COMMENT_TEXT_MAX);
            if (keep && text !== (c.text || '')) {
                c.text = text;
                this.ed.changed('name comment');
            } else {
                this.renderNotes();
            }
        };
        this.renaming = { input, finish };
        input.addEventListener('keydown', (ev) => {
            if (ev.key === 'Enter') { ev.preventDefault(); finish(true); }
            else if (ev.key === 'Escape') { ev.preventDefault(); ev.stopPropagation(); finish(false); }
        });
        // A moment later: the blur can come from the field being taken away by a redraw, and a redraw
        // from inside that one breaks it (NotFoundError).
        input.addEventListener('blur', () => setTimeout(() => finish(true), 0));
        input.focus();
        input.select();
    }

    /** A comment's name being typed is kept now (a save, a click on the grid). */
    commitRename() {
        if (this.renaming) this.renaming.finish(true);
    }

    // ---- pulses: a live run going, a test played back ----

    /** Light a card, and the wire it came along, for a moment. */
    pulse(nodeId, linkId) {
        const card = this.cardsEl.querySelector(`.dr-card[data-id="${CSS.escape(nodeId)}"]`);
        if (card) this.flash(card);
        if (linkId) {
            const wire = this.svg.querySelector(`.dr-wire[data-wire="${CSS.escape(linkId)}"]`);
            if (wire) this.flash(wire);
        }
    }

    flash(el, cls = 'pulse') {
        el.classList.remove(cls);
        void el.getBoundingClientRect();   // so the animation starts again
        el.classList.add(cls);
        clearTimeout(this.pulseTimers.get(el));
        this.pulseTimers.set(el, setTimeout(() => { el.classList.remove(cls); this.pulseTimers.delete(el); }, PULSE_MS));
    }

    // ---- the last test, played back ----
    //
    // "it should only flash on the card you finished on / were last on, with the animation showing the
    // flow, but it just highlights the respondent colour, green for success, red for failure, yellow if
    // something couldn't continue / error". So: each card and wire the test went through is lit in the
    // run's colour as the playback reaches it (ed.lastTest.shownNodes / shownLinks, which a redraw keeps),
    // the wire's dashes running in towards the card and the card simply lit; when it is over, the card
    // it finished on (ed.lastTest.end) flashes a few times and stays marked. tone: ok | bad | stuck. A card that
    // went out of an outcome that means it did not happen (Could not, Timeout: badPin), and the wire it went
    // along, are red whatever the run did (ed.lastTest.badNodes / badLinks): a test that succeeded round a card
    // that failed must not light that card green.

    /** A card's colour from the last test: its own red, or the run's. */
    ranTone(id) {
        const t = this.ed.lastTest;
        return t.badNodes.has(id) ? 'bad' : t.tone;
    }

    /** A card's classes from the last test: lit once the playback has reached it, and the one it ended on. */
    ranClasses(id) {
        const t = this.ed.lastTest;
        if (!t) return [];
        const out = [];
        if (t.shownNodes.has(id)) out.push('ran', 'ran-' + this.ranTone(id));
        if (t.done && t.end === id) {
            out.push('ran-end');
            if (!t.shownNodes.has(id)) out.push('ran-' + this.ranTone(id));
        }
        return out;
    }

    /** The playback reached a card, along a wire (or none: the first card, a wait answered). */
    reveal(nodeId, linkId, animate) {
        const t = this.ed.lastTest;
        if (!t) return;
        t.shownNodes.add(nodeId);
        const card = this.cardsEl.querySelector(`.dr-card[data-id="${CSS.escape(nodeId)}"]`);
        if (card) card.classList.add('ran', 'ran-' + this.ranTone(nodeId));
        if (!linkId) return;
        t.shownLinks.add(linkId);
        const wire = this.svg.querySelector(`.dr-wire[data-wire="${CSS.escape(linkId)}"]`);
        if (!wire || wire.classList.contains('selected')) return;
        wire.classList.add('ran', 'ran-' + (t.badLinks.has(linkId) ? 'bad' : t.tone));
        if (animate) this.flash(wire, 'flow');
    }

    /** The playback is over: everything the test touched is lit, and the card it ended on flashes. */
    finishRun() {
        const t = this.ed.lastTest;
        if (!t) return;
        for (const id of t.nodes) t.shownNodes.add(id);
        for (const id of t.links) t.shownLinks.add(id);
        t.done = true;
        this.render();
        const end = t.end && this.cardsEl.querySelector(`.dr-card[data-id="${CSS.escape(t.end)}"]`);
        if (end) end.classList.add('ran-flash');   // (a redraw drops it: the flash is not played again)
    }

    // ---- the cards that use a placed thing ----

    /** Light white the cards that use the World row open in the column (app.js showUses), flashing them
     *  as it opens. Empty: none. */
    setUses(ids, flash) {
        const next = ids && ids.length ? new Set(ids) : null;
        this.uses = next;
        this.cardsEl.querySelectorAll('.dr-card.uses').forEach((el) => {
            if (!next || !next.has(el.dataset.id)) el.classList.remove('uses', 'uses-flash');
        });
        if (!next) return;
        for (const id of next) {
            const el = this.cardsEl.querySelector(`.dr-card[data-id="${CSS.escape(id)}"]`);
            if (!el) continue;
            el.classList.add('uses');
            if (flash) {
                el.classList.remove('uses-flash');
                void el.getBoundingClientRect();   // so the animation starts again
                el.classList.add('uses-flash');
            }
        }
    }

    // ---- the mouse ----

    onWheel(e) {
        e.preventDefault();
        if (!this.ed.doc) return;
        const k = Math.exp(-e.deltaY * 0.0015);
        this.zoomAt(e.clientX, e.clientY, this.view.z * k);
        this.rebaseDrag(e);
    }

    /** A zoom in the middle of a drag: the drag is measured again from here, where the pointer is now.
     *  Its numbers were taken against the old pan and zoom, so the next move put the view (or the cards)
     *  back where they would have been without the zoom: a pan zoomed about where it began, not about the
     *  pointer, and dragged cards jumped. */
    rebaseDrag(e) {
        const d = this.drag;
        if (!d) return;
        const at = { x: e.clientX, y: e.clientY };
        if (d.kind === 'press') {
            d.start = at;
            d.view0 = { x: this.view.x, y: this.view.y };
        } else if (d.kind === 'cards') {
            d.start = at;
            d.from = d.moving.map((n) => ({ x: n.x, y: n.y }));
        } else if (d.kind === 'note') {
            d.start = at;
            d.from = { x: d.note.x, y: d.note.y };
            d.fromCards = d.moving.map((n) => ({ x: n.x, y: n.y }));
            d.fromNotes = d.inner.map((o) => ({ x: o.x, y: o.y }));
        } else if (d.kind === 'resize') {
            d.start = at;
            d.from = { w: d.note.w, h: d.note.h };
        } else if (d.kind === 'wire') {
            d.to = this.toWorld(e.clientX, e.clientY);
            this.renderWires();
        }
    }

    onDown(e) {
        const ed = this.ed;
        if (!ed.doc || this.drag) return;
        const t = e.target;
        if (t.tagName === 'INPUT') return;   // a comment's name being typed
        // Anywhere else on the grid: that name is kept first, so nothing redraws over the field.
        this.commitRename();
        const pinEl = t.closest && t.closest('.dr-pin');
        const cardEl = t.closest && t.closest('.dr-card');
        const linkEl = t.closest && t.closest('.dr-wire-hit');
        const noteHead = t.closest && t.closest('.dr-note-head');
        const grip = t.closest && t.closest('.dr-note-grip');
        const start = { x: e.clientX, y: e.clientY };

        if (e.button === 1 || e.button === 2) {
            e.preventDefault();
            this.drag = {
                kind: 'press', button: e.button, start, moved: false,
                view0: { x: this.view.x, y: this.view.y },
                pin: pinEl ? { node: cardEl.dataset.id, pin: pinEl.dataset.pin, side: pinEl.dataset.side } : null,
                card: cardEl ? cardEl.dataset.id : null,
                note: !cardEl && (noteHead || grip) ? (noteHead || grip).closest('.dr-note').dataset.note : null,
            };
        } else if (e.button === 0 && pinEl && cardEl) {
            e.preventDefault();
            const node = findNode(ed.doc, cardEl.dataset.id);
            const side = pinEl.dataset.side, pin = pinEl.dataset.pin;
            if (e.altKey) {
                if (breakPin(ed.doc, node.id, pin, side)) ed.changed('break wires');
                return;
            }
            const anchor = pinPoint(node, this.pins.get(node.id), side, pin, this.geo, this.ed.cards);
            if (!anchor) return;
            const rec = this.pinRecord(node.id, side, pin);
            this.drag = { kind: 'wire', node: node.id, pin, side, anchor, to: null, start, rec };
            if (this.ed.typed) this.markTargets(rec, side);
        } else if (e.button === 0 && cardEl) {
            e.preventDefault();
            const id = cardEl.dataset.id;
            // (A Wait step picking its card, app.js task-card-pick: this one is it, selected already or not.)
            if (ed.cardPickFor) { ed.select([id]); return; }
            const additive = e.shiftKey || e.ctrlKey;
            if (additive) {
                const next = new Set(ed.selected);
                if (next.has(id)) next.delete(id); else next.add(id);
                ed.select([...next]);
            } else if (!ed.selected.has(id)) {
                ed.select([id]);
            } else if (ed.pressedPicked) {
                // (Picked already: the world builder's panel shows its page again if it is not showing it.)
                ed.pressedPicked();
            }
            if (!ed.selected.has(id)) return;
            const moving = [...ed.selected].map((sid) => findNode(ed.doc, sid)).filter(Boolean);
            this.drag = {
                kind: 'cards', start, moved: false, moving,
                from: moving.map((n) => ({ x: n.x, y: n.y })),
            };
        } else if (e.button === 0 && linkEl) {
            e.preventDefault();
            ed.selectLink(linkEl.dataset.link);
        } else if (e.button === 0 && (noteHead || grip)) {
            e.preventDefault();
            const c = findComment(ed.doc, (noteHead || grip).closest('.dr-note').dataset.note);
            if (!c) return;
            ed.selectNote(c.id);
            if (grip) {
                this.drag = { kind: 'resize', note: c, start, moved: false, from: { w: c.w, h: c.h } };
            } else {
                // The cards inside it go with it, and the boxes inside it.
                const moving = ed.doc.nodes.filter((n) => this.inNote(n, c));
                const inner = (ed.doc.comments || []).filter((o) => this.noteInNote(o, c));
                this.drag = { kind: 'note', note: c, start, moved: false, from: { x: c.x, y: c.y },
                              moving, fromCards: moving.map((n) => ({ x: n.x, y: n.y })),
                              inner, fromNotes: inner.map((o) => ({ x: o.x, y: o.y })) };
            }
        } else if (e.button === 0) {
            // Empty ground (or inside a comment box): a box to select with; a click alone clears.
            this.drag = { kind: 'marquee', start, moved: false, additive: e.shiftKey || e.ctrlKey };
        }
        if (this.drag) {
            window.addEventListener('mousemove', this.onMoveBound);
            window.addEventListener('mouseup', this.onUpBound);
        }
    }

    onMove(e) {
        const d = this.drag;
        if (!d) return;
        const dx = e.clientX - d.start.x, dy = e.clientY - d.start.y;
        if (d.kind === 'press') {
            if (!d.moved && Math.hypot(dx, dy) < DRAG_START_PX) return;
            d.moved = true;
            this.root.classList.add('dr-panning');
            this.view.x = d.view0.x + dx;
            this.view.y = d.view0.y + dy;
            this.applyView();
        } else if (d.kind === 'cards') {
            if (!d.moved && Math.hypot(dx, dy) < DRAG_START_PX) return;
            d.moved = true;
            const z = this.view.z;
            d.moving.forEach((n, i) => {
                n.x = Math.round((d.from[i].x + dx / z) / GEO.SNAP) * GEO.SNAP;
                n.y = Math.round((d.from[i].y + dy / z) / GEO.SNAP) * GEO.SNAP;
                this.placeCard(n);
            });
            this.moveWiresOf(d.movingIds || (d.movingIds = new Set(d.moving.map((n) => n.id))));
        } else if (d.kind === 'wire') {
            d.to = this.toWorld(e.clientX, e.clientY);
            // (The wire being drawn moves alone; drawn in full the first time.)
            const temp = this.svg.querySelector('.dr-wire.temp');
            if (temp) temp.setAttribute('d', this.tempWirePath()); else this.renderWires();
        } else if (d.kind === 'marquee') {
            if (!d.moved && Math.hypot(dx, dy) < DRAG_START_PX) return;
            d.moved = true;
            const rect = this.root.getBoundingClientRect();
            const s = this.marqueeEl.style;
            s.display = 'block';
            s.left = (Math.min(d.start.x, e.clientX) - rect.left) + 'px';
            s.top = (Math.min(d.start.y, e.clientY) - rect.top) + 'px';
            s.width = Math.abs(dx) + 'px';
            s.height = Math.abs(dy) + 'px';
        } else if (d.kind === 'note') {
            if (!d.moved && Math.hypot(dx, dy) < DRAG_START_PX) return;
            d.moved = true;
            const z = this.view.z, c = d.note;
            c.x = Math.round((d.from.x + dx / z) / GEO.SNAP) * GEO.SNAP;
            c.y = Math.round((d.from.y + dy / z) / GEO.SNAP) * GEO.SNAP;
            const mx = c.x - d.from.x, my = c.y - d.from.y;
            d.moving.forEach((n, i) => { n.x = d.fromCards[i].x + mx; n.y = d.fromCards[i].y + my; this.placeCard(n); });
            d.inner.forEach((o, i) => { o.x = d.fromNotes[i].x + mx; o.y = d.fromNotes[i].y + my; this.placeNote(o); });
            this.placeNote(c);
            this.moveWiresOf(d.movingIds || (d.movingIds = new Set(d.moving.map((n) => n.id))));
        } else if (d.kind === 'resize') {
            if (!d.moved && Math.hypot(dx, dy) < DRAG_START_PX) return;
            d.moved = true;
            const z = this.view.z, c = d.note;
            c.w = Math.max(COMMENT_MIN.w, Math.round((d.from.w + dx / z) / GEO.SNAP) * GEO.SNAP);
            c.h = Math.max(COMMENT_MIN.h, Math.round((d.from.h + dy / z) / GEO.SNAP) * GEO.SNAP);
            this.placeNote(c);
        }
    }

    /** Can a wire from pin record `a` (on `side`) go to pin record `b`? null when it can, else why not
     *  (ed.typed: exec to exec, value to value of a type that fits). */
    wireRefusal(a, side, b) {
        const T = this.ed.typed;
        if (!T || !a || !b) return null;
        if (!!a.value !== !!b.value) return 'A "then" wire joins white pins, a value wire coloured ones';
        if (!a.value) return null;
        const from = side === 'out' ? a : b, to = side === 'out' ? b : a;
        return T.canConnect(from, to);
    }

    /** While a wire is dragged (ed.typed): every pin it could go to is marked, the rest dimmed. */
    markTargets(rec, side) {
        this.root.classList.add('dr-wiring');
        for (const el of this.cardsEl.querySelectorAll('.dr-pin')) {
            const card = el.closest('.dr-card');
            const other = card && this.pinRecord(card.dataset.id, el.dataset.side, el.dataset.pin);
            const ok = el.dataset.side !== side && other && !this.wireRefusal(rec, side, other);
            el.classList.toggle('can', !!ok);
            el.classList.toggle('cannot', !ok);
        }
    }

    unmarkTargets() {
        if (!this.root.classList.contains('dr-wiring')) return;
        this.root.classList.remove('dr-wiring');
        for (const el of this.cardsEl.querySelectorAll('.dr-pin.can, .dr-pin.cannot')) el.classList.remove('can', 'cannot');
    }

    /** The cards a box on the screen touches (screen corners a and b). */
    cardsIn(a, b) {
        const p = this.toWorld(Math.min(a.x, b.x), Math.min(a.y, b.y));
        const q = this.toWorld(Math.max(a.x, b.x), Math.max(a.y, b.y));
        const doc = this.ed.doc;
        return doc.nodes.filter((n) => {
            const pins = this.pins.get(n.id) || this.pinsFor(n);
            return n.x <= q.x && n.x + cardWidth(n, this.ed.cards) >= p.x && n.y <= q.y && n.y + cardHeight(n, pins, this.geo, this.ed.cards) >= p.y;
        }).map((n) => n.id);
    }

    onDouble(e) {
        const ed = this.ed;
        if (!ed.doc) return;
        const t = e.target;
        const noteHead = t.closest && t.closest('.dr-note-head');
        const linkEl = t.closest && t.closest('.dr-wire-hit');
        if (noteHead && t.tagName !== 'INPUT') {
            this.renameNote(noteHead.closest('.dr-note').dataset.note);
        } else if (linkEl) {
            const at = this.toWorld(e.clientX, e.clientY);
            ed.ui.reroute(linkEl.dataset.link, { x: at.x - GEO.DOT_W / 2, y: at.y - GEO.DOT_H / 2 });
        }
    }

    onUp(e) {
        const d = this.drag;
        this.drag = null;
        window.removeEventListener('mousemove', this.onMoveBound);
        window.removeEventListener('mouseup', this.onUpBound);
        this.root.classList.remove('dr-panning');
        this.unmarkTargets();
        if (!d) return;
        const ed = this.ed;

        if (d.kind === 'press') {
            if (d.moved || d.button !== 2) return;
            // A right CLICK: on a pin breaks it, on a card is its menu, on the ground adds a card.
            if (d.pin) {
                if (breakPin(ed.doc, d.pin.node, d.pin.pin, d.pin.side)) ed.changed('break wires');
            } else if (d.card) {
                // The menu only, not the card's page as well (a click is that): a card not selected is picked as a
                // choice of the menu runs (ui.cardMenu).
                ed.ui.cardMenu({ x: e.clientX, y: e.clientY }, d.card);
            } else if (d.note) {
                ed.selectNote(d.note);
                ed.ui.noteMenu({ x: e.clientX, y: e.clientY }, d.note);
            } else {
                ed.ui.search({ x: e.clientX, y: e.clientY, world: this.toWorld(e.clientX, e.clientY) });
            }
        } else if (d.kind === 'cards') {
            if (d.moved) ed.changed('move');
        } else if (d.kind === 'marquee') {
            this.marqueeEl.style.display = 'none';
            if (!d.moved) { ed.select([]); return; }
            const ids = this.cardsIn(d.start, { x: e.clientX, y: e.clientY });
            if (d.additive) for (const id of ed.selected) if (!ids.includes(id)) ids.push(id);
            ed.select(ids);
        } else if (d.kind === 'note' || d.kind === 'resize') {
            if (d.moved) ed.changed(d.kind === 'note' ? 'move comment' : 'resize comment');
        } else if (d.kind === 'wire') {
            const under = document.elementFromPoint(e.clientX, e.clientY);
            let pinEl = under && under.closest && under.closest('.dr-pin');
            const cardEl = under && under.closest && under.closest('.dr-card');
            // Dropped on a Reroute dot's middle (its pins are only the dot's ends): the pin that fits.
            if (!pinEl && cardEl && cardEl.classList.contains('dr-reroute')) {
                pinEl = cardEl.querySelector(`.dr-pin.${d.side === 'out' ? 'in' : 'out'}`);
            }
            if (pinEl && cardEl) {
                const other = { node: cardEl.dataset.id, pin: pinEl.dataset.pin, side: pinEl.dataset.side };
                if (other.side === d.side) {
                    ed.ui.status('A wire goes from an output (right) to an input (left)', 'warn');
                    this.renderWires();
                    return;
                }
                const from = d.side === 'out' ? { node: d.node, pin: d.pin } : { node: other.node, pin: other.pin };
                const to = d.side === 'out' ? { node: other.node, pin: other.pin } : { node: d.node, pin: d.pin };
                if (ed.typed) {
                    const why = this.wireRefusal(d.rec, d.side, this.pinRecord(other.node, other.side, other.pin));
                    if (why) {
                        ed.ui.status(why, 'warn');
                        this.renderWires();
                        return;
                    }
                    // A value input takes one wire: the new one takes the old one's place.
                    if (d.rec && d.rec.value) breakPin(ed.doc, to.node, to.pin, 'in');
                }
                addLink(ed.doc, from, to);
                ed.changed('connect');
            } else if (d.to && d.rec && d.rec.gone && ed.typed) {
                // A pin no longer on its card is only there to show its wire: nothing new joins it.
                ed.ui.status('That pin is gone from its card: take its wire off', 'warn');
                this.renderWires();
            } else if (d.to && Math.hypot(e.clientX - d.start.x, e.clientY - d.start.y) >= DRAG_START_PX
                && !(under && under.closest && under.closest('.dr-col'))) {
                // Dropped on the ground: add a card there, wired to where this started (and, for a
                // value pin, its kind and type: the search offers only cards that take it).
                const rec = d.rec && d.rec.value ? { value: true, type: d.rec.type, fam: d.rec.fam } : {};
                ed.ui.search({ x: e.clientX, y: e.clientY, world: d.to, from: Object.assign({ node: d.node, pin: d.pin, side: d.side }, rec) });
                this.renderWires();
            } else {
                this.renderWires();
            }
        }
    }

    /** Delete what is selected: cards, or the picked wire. */
    deleteSelected() {
        const ed = this.ed;
        if (ed.selectedLink) {
            removeLink(ed.doc, ed.selectedLink);
            ed.selectedLink = null;
            ed.changed('delete wire');
            return true;
        }
        return false;
    }
}
