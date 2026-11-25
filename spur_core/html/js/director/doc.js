// ========================================
// DIRECTOR — the scenario document in the editor, and undo
//
// The document is the server's (server/director/graph.lua has the shape): { format, name,
// description, settings, vars[], world[], nodes[], links[] }. Everything the editor changes is a
// change to this one object; the canvas and the column draw from it, and saving sends it whole.
//
// A DOCUMENT FROM LUA IS NORMALISED FIRST. Lua has one table type, so an empty list arrives as {}
// and an empty props map as [] — normalise() makes lists lists and maps maps before anything reads
// them. Keys this editor does not know are KEPT (a newer server's field must survive an older page).
//
// UNDO IS SNAPSHOTS: the document as JSON after every change (commit). Cheap at this size (a
// hundred cards is tens of KB) and it cannot drift from the document, which a list of inverse
// operations can.
// ========================================

import { renameRef, cardUses, cardUsesAll, eachRef } from './refs.js';

export const FORMAT = 2;   // (server/director/doc.lua DirectorDoc.FORMAT: the server says which it reads, catalogue.format)
const UNDO_LIMIT = 120;
const UNDO_BYTES = 24 * 1024 * 1024;

const isObj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x);

/** A list the server sent, as an array. A Lua list with a hole (or an empty one) arrives as an object
 *  ({ "1": ..., "3": ... }): its values in key order. Anything else is none. */
export function listOf(x) {
    if (Array.isArray(x)) return x;
    if (isObj(x)) return Object.keys(x).sort((a, b) => Number(a) - Number(b)).map((k) => x[k]);
    return [];
}

function list(x) {
    return listOf(x).filter(isObj);
}

const map = (x) => (isObj(x) ? x : {});
const num = (x, d) => (typeof x === 'number' && isFinite(x) ? x : d);
const str = (x) => (typeof x === 'string' ? x : '');

/** A document as the editor reads it: lists are lists, maps are maps, unknown keys kept. */
export function normalise(raw) {
    const d = map(raw);
    const doc = {};
    for (const k of Object.keys(d)) doc[k] = d[k];
    doc.format = num(d.format, FORMAT);
    doc.name = str(d.name) || 'Untitled';
    doc.description = str(d.description);
    doc.settings = map(d.settings);
    doc.settings.start = map(doc.settings.start);
    if (!doc.settings.start.mode) doc.settings.start.mode = 'admin';
    doc.vars = list(d.vars);
    doc.world = list(d.world);
    doc.nodes = list(d.nodes);
    doc.links = list(d.links);
    for (const n of doc.nodes) {
        n.props = map(n.props);
        n.x = num(n.x, 0);
        n.y = num(n.y, 0);
    }
    for (const w of doc.world) w.def = map(w.def);
    for (const l of doc.links) {
        l.from = map(l.from);
        l.to = map(l.to);
    }
    // Comment boxes: the editor's alone. The server keeps them with the rest and never
    // reads them.
    // One box per id (a hand-edited file could name two the same: the second could never be taken).
    const noteIds = new Set();
    doc.comments = list(d.comments).filter((c) => isId(c.id) && !noteIds.has(c.id) && noteIds.add(c.id));
    for (const c of doc.comments) {
        c.x = num(c.x, 0);
        c.y = num(c.y, 0);
        c.w = Math.max(COMMENT_MIN.w, num(c.w, 320));
        c.h = Math.max(COMMENT_MIN.h, num(c.h, 200));
        c.text = str(c.text).slice(0, COMMENT_TEXT_MAX);
    }
    // Its other variants (Multi Run Variants: server/director/graph.lua), each read as the document is. None: no key
    // at all (a document with none is saved exactly as it came).
    if (d.variants !== undefined) {
        const seen = new Set(['v1']);
        doc.variants = list(d.variants).filter((v) => typeof v.id === 'string' && /^v\d+$/.test(v.id) && !seen.has(v.id) && seen.add(v.id))
            .map((v) => {
                const one = normalise({ nodes: v.nodes, links: v.links, world: v.world, comments: v.comments });
                return { ...v, name: str(v.name).slice(0, 40), nodes: one.nodes, links: one.links, world: one.world, comments: one.comments };
            });
        if (!doc.variants.length) delete doc.variants;
    }
    return doc;
}

// ---- variants: one open at a time ----
//
// THE DOCUMENT KEEPS VARIANT 1 AT ITS TOP (nodes, links, comments, world) and the others in doc.variants, each with its
// own cards, wires, comment boxes and the things only it has. The things every variant SHARES (sharedIds, the server's
// rule) live once, in Variant 1's world.
//
// THE EDITOR WORKS ON A VIEW of the open one (unpackDoc): its cards, wires and boxes at the top, its world the shared
// things (the same objects) then its own. Variant 1's view is the document itself. Everything that leaves the editor
// (a save, a check, a test, undo's snapshots) is packed back (packDoc) into the document as the server keeps it.

export const MAX_VARIANTS = 8;

/** The things every variant shares: what is always present, the start's thing (one start for all), and what those name
 *  (a task step's thing: refs.js). As server/director/graph.lua sharedIds. `taskTypes`: the tasks' catalogue
 *  (ed.tasks.types), which says a step's fields that name a thing. */
export function sharedIds(doc, taskTypes) {
    const byId = new Map((doc.world || []).map((w) => [w.id, w]));
    // What each thing's own steps name.
    const named = new Map();
    eachRef({ world: doc.world || [] }, null, taskTypes, (r) => {
        if (r.kind === 'world' && r.step) named.set(r.thing.id, [...(named.get(r.thing.id) || []), r.id]);
    });
    const shared = new Set(), queue = [];
    const add = (id) => { if (typeof id === 'string' && byId.has(id) && !shared.has(id)) { shared.add(id); queue.push(id); } };
    for (const w of doc.world || []) if (w.layer === 'standing') add(w.id);
    const st = (doc.settings && doc.settings.start) || {};
    if (['interaction', 'press', 'area', 'timer'].includes(st.mode)) add(st.world);
    for (let i = 0; i < queue.length; i++) for (const id of named.get(queue[i]) || []) add(id);
    return shared;
}

/** The variants, in order: [{ id, name }], Variant 1 first. */
export function variantList(doc) {
    return [{ id: 'v1', name: str(doc.variantName) }].concat((doc.variants || []).map((v) => ({ id: v.id, name: str(v.name) })));
}

/** A variant's name as its button says it: its own, else "Variant 2" by where it is. */
export function variantLabel(doc, id) {
    const list = variantList(doc);
    const i = list.findIndex((v) => v.id === id);
    return i < 0 ? id : (list[i].name || `Variant ${i + 1}`);
}

/** The view of variant `id` (see above). Variant 1, or one not there: the document itself. */
export function unpackDoc(canon, id, taskTypes) {
    const v = id && id !== 'v1' && (canon.variants || []).find((x) => x.id === id);
    if (!v) return canon;
    const shared = sharedIds(canon, taskTypes);
    const view = { ...canon };
    view.variantOpen = id;
    view.nodes = v.nodes;
    view.links = v.links;
    view.comments = v.comments;
    view.world = canon.world.filter((w) => shared.has(w.id)).concat(v.world);
    view.variants = canon.variants.map((x) => (x.id === id ? { id: x.id, name: x.name } : x));
    // Variant 1's own, kept out of sight (never serialised with the view).
    Object.defineProperty(view, '_base', { value: { nodes: canon.nodes, links: canon.links, comments: canon.comments, world: canon.world, shared },
                                           enumerable: false, writable: true });
    return view;
}

/** The document as the server keeps it, from a view (unpackDoc). A thing shared when the view was made stays Variant
 *  1's (as it is now in the view, or gone if the view removed it); one that has become shared since (set to Always
 *  present) moves to Variant 1's world; the rest of the view's things are the open variant's own. */
export function packDoc(view, taskTypes) {
    if (!view || !view.variantOpen || !view._base) return view;
    const base = view._base;
    const nowShared = sharedIds(view, taskTypes);
    const inView = new Map(view.world.map((w) => [w.id, w]));
    const baseIds = new Set(base.world.map((w) => w.id));
    const world = [];
    for (const w of base.world) {
        if (!base.shared.has(w.id)) world.push(w);
        else if (inView.has(w.id)) world.push(inView.get(w.id));
    }
    const moved = new Set();
    for (const w of view.world) {
        if (!base.shared.has(w.id) && nowShared.has(w.id) && !baseIds.has(w.id)) { world.push(w); moved.add(w.id); }
    }
    const own = view.world.filter((w) => !base.shared.has(w.id) && !moved.has(w.id));
    const canon = {};
    for (const k of Object.keys(view)) if (k !== 'variantOpen') canon[k] = view[k];
    canon.nodes = base.nodes;
    canon.links = base.links;
    canon.comments = base.comments;
    canon.world = world;
    canon.variants = view.variants.map((x) => (x.id === view.variantOpen
        ? { ...x, nodes: view.nodes, links: view.links, comments: view.comments, world: own } : x));
    return canon;
}

/** Run `fn` on every variant's view (Variant 1's is the document); answers the document with what it changed. */
export function eachVariant(canon, fn, taskTypes) {
    fn(canon);
    let doc = canon;
    for (const v of variantList(canon).slice(1)) {
        const view = unpackDoc(doc, v.id, taskTypes);
        fn(view);
        doc = packDoc(view, taskTypes);
    }
    return doc;
}

/** A new variant: a copy of `fromId`'s cards, wires, boxes and own things, their ids kept (so a card named in the
 *  scenario's settings, or allowed by a gated card's rule, is the same in each). Answers its id, or null at the most. */
export function newVariant(canon, fromId, taskTypes) {
    const ids = variantList(canon);
    if (ids.length >= MAX_VARIANTS) return null;
    const top = Math.max(1, ...ids.map((v) => Number(v.id.slice(1)) || 1));
    const id = 'v' + (top + 1);
    const from = unpackDoc(canon, fromId, taskTypes);
    const shared = sharedIds(canon, taskTypes);
    const copy = (x) => JSON.parse(JSON.stringify(x));
    canon.variants = (canon.variants || []).concat([{ id, name: '', nodes: copy(from.nodes), links: copy(from.links),
        comments: copy(from.comments || []), world: copy(from.world.filter((w) => !shared.has(w.id))) }]);
    return id;
}

/** Take a variant out (never Variant 1), and out of the In order list. The last one gone: no variants at all. */
export function removeVariant(canon, id) {
    if (!id || id === 'v1') return;
    canon.variants = (canon.variants || []).filter((v) => v.id !== id);
    const s = canon.settings || {};
    if (Array.isArray(s.variantOrder)) s.variantOrder = s.variantOrder.filter((x) => x !== id);
    if (!canon.variants.length) {
        delete canon.variants;
        delete canon.variantName;
        delete s.variantPick;
        delete s.variantOrder;
    }
}

/** A variant's name (Variant 1's is the document's variantName). */
export function renameVariant(canon, id, name) {
    const n = str(name).trim().slice(0, 40);
    if (id === 'v1') { if (n) canon.variantName = n; else delete canon.variantName; return; }
    const v = (canon.variants || []).find((x) => x.id === id);
    if (v) v.name = n;
}

/** Move a variant one place earlier (-1) or later (+1) among the others (Variant 1 stays first: it is the document). */
export function moveVariant(canon, id, by) {
    const list = canon.variants || [];
    const i = list.findIndex((v) => v.id === id);
    const j = i + by;
    if (i < 0 || j < 0 || j >= list.length) return;
    [list[i], list[j]] = [list[j], list[i]];
}

export const COMMENT_MIN = { w: 160, h: 80 };
export const COMMENT_TEXT_MAX = 120;

// ---- ids ----

const ID_OK = /^[A-Za-z0-9_-]{1,64}$/;
export function isId(s) { return typeof s === 'string' && ID_OK.test(s); }

/** A word for an id from any text: "Courier boss" -> "courier_boss". */
export function slug(text, fallback) {
    const s = String(text || '').toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 40);
    return s || fallback || 'thing';
}

/** The first `base1`, `base2`... not in `used`. */
export function freeId(used, base) {
    base = slug(base, 'n');
    let i = 1;
    while (used.has(base + i)) i++;
    return base + i;
}

export function nodeIds(doc) { return new Set(doc.nodes.map((n) => n.id)); }
export function worldIds(doc) { return new Set(doc.world.map((w) => w.id)); }

export function findNode(doc, id) { return doc.nodes.find((n) => n.id === id) || null; }
export function findWorld(doc, id) { return doc.world.find((w) => w.id === id) || null; }

// ---- cards and wires ----

/** A new card of a type, its fields at their defaults. */
export function makeNode(doc, def, x, y) {
    const short = def.type.split('.').pop();
    const props = {};
    for (const f of def.props || []) {
        if (f.default !== undefined && f.default !== null) props[f.key] = f.default;
    }
    const node = { id: freeId(nodeIds(doc), short), type: def.type, v: def.v, x: Math.round(x), y: Math.round(y), props };
    doc.nodes.push(node);
    return node;
}

/** A copy of cards (and the wires between them), moved by dx/dy. Answers the new ids. */
export function duplicateNodes(doc, ids, dx, dy) {
    const used = nodeIds(doc);
    const remap = new Map();
    const made = [];
    for (const id of ids) {
        const n = findNode(doc, id);
        if (!n) continue;
        const copy = JSON.parse(JSON.stringify(n));
        copy.id = freeId(used, n.type.split('.').pop());
        used.add(copy.id);
        copy.x = n.x + dx;
        copy.y = n.y + dy;
        remap.set(id, copy.id);
        doc.nodes.push(copy);
        made.push(copy.id);
    }
    for (const l of doc.links.slice()) {
        if (remap.has(l.from.node) && remap.has(l.to.node)) {
            addLink(doc, { node: remap.get(l.from.node), pin: l.from.pin }, { node: remap.get(l.to.node), pin: l.to.pin });
        }
    }
    return made;
}

export function removeNodes(doc, ids) {
    const gone = new Set(ids);
    doc.nodes = doc.nodes.filter((n) => !gone.has(n.id));
    doc.links = doc.links.filter((l) => !gone.has(l.from.node) && !gone.has(l.to.node));
}

// ---- copy and paste ----

/** What Copy keeps: the cards (deep copies) and the wires between them. Plain data, so it can go
 *  into another scenario: what it names there (a placed thing, a variable) is Check's to judge. */
export function copyNodes(doc, ids) {
    const keep = new Set(ids);
    const nodes = doc.nodes.filter((n) => keep.has(n.id)).map((n) => JSON.parse(JSON.stringify(n)));
    const links = doc.links.filter((l) => keep.has(l.from.node) && keep.has(l.to.node))
        .map((l) => ({ from: { node: l.from.node, pin: l.from.pin }, to: { node: l.to.node, pin: l.to.pin } }));
    return nodes.length ? { nodes, links } : null;
}

/** Put a copy in: its top-left card at `at` (world units, snapped to `snap`), new ids, its wires
 *  between the new cards. Answers the new ids. */
export function pasteNodes(doc, clip, at, snap) {
    if (!clip || !Array.isArray(clip.nodes) || !clip.nodes.length) return [];
    let x0 = Infinity, y0 = Infinity;
    for (const n of clip.nodes) { x0 = Math.min(x0, n.x); y0 = Math.min(y0, n.y); }
    const s = snap || 1;
    const dx = Math.round((at.x - x0) / s) * s, dy = Math.round((at.y - y0) / s) * s;
    const used = nodeIds(doc);
    const remap = new Map();
    const made = [];
    for (const n of clip.nodes) {
        const copy = JSON.parse(JSON.stringify(n));
        copy.id = freeId(used, String(n.type || 'card').split('.').pop());
        used.add(copy.id);
        copy.x = n.x + dx;
        copy.y = n.y + dy;
        remap.set(n.id, copy.id);
        doc.nodes.push(copy);
        made.push(copy.id);
    }
    for (const l of clip.links || []) {
        if (remap.has(l.from.node) && remap.has(l.to.node)) {
            addLink(doc, { node: remap.get(l.from.node), pin: l.from.pin }, { node: remap.get(l.to.node), pin: l.to.pin });
        }
    }
    return made;
}

// ---- comment boxes ----

export function findComment(doc, id) { return (doc.comments || []).find((c) => c.id === id) || null; }

/** A comment box round a rectangle (world units). Answers it. */
export function makeComment(doc, rect, text) {
    if (!Array.isArray(doc.comments)) doc.comments = [];
    const c = {
        id: freeId(new Set(doc.comments.map((x) => x.id)), 'note'),
        x: Math.round(rect.x), y: Math.round(rect.y),
        w: Math.max(COMMENT_MIN.w, Math.round(rect.w)), h: Math.max(COMMENT_MIN.h, Math.round(rect.h)),
        text: String(text || '').slice(0, COMMENT_TEXT_MAX),
    };
    doc.comments.push(c);
    return c;
}

export function removeComment(doc, id) { doc.comments = (doc.comments || []).filter((c) => c.id !== id); }

// ---- reroutes ----

/** Put a Reroute dot on a wire: from -> dot -> to. Answers the dot's card, or null. */
export function insertReroute(doc, linkId, def, at) {
    const l = doc.links.find((k) => k.id === linkId);
    if (!l || !def) return null;
    const from = { node: l.from.node, pin: l.from.pin }, to = { node: l.to.node, pin: l.to.pin };
    const dot = makeNode(doc, def, at.x, at.y);
    removeLink(doc, linkId);
    addLink(doc, from, { node: dot.id, pin: def.inputs[0] });
    addLink(doc, { node: dot.id, pin: def.outputs[0] }, to);
    return dot;
}

function linkIds(doc) { return new Set(doc.links.map((l) => l.id)); }

/** Wire an OUTPUT to an INPUT. An output may lead to several places (Car Entered to a Countdown AND
 *  a Goal): each wire's card starts at the same moment, the oldest wire first, as
 *  Do in Order does. The same wire twice is a no-op. Answers the link. */
export function addLink(doc, from, to) {
    const same = doc.links.find((l) => l.from.node === from.node && l.from.pin === from.pin
        && l.to.node === to.node && l.to.pin === to.pin);
    if (same) return same;
    const link = { id: freeId(linkIds(doc), 'w'), from: { node: from.node, pin: from.pin }, to: { node: to.node, pin: to.pin } };
    doc.links.push(link);
    return link;
}

/** Break every wire on one pin. `side` is 'in' or 'out'. Answers how many went. */
export function breakPin(doc, nodeId, pin, side) {
    const before = doc.links.length;
    doc.links = doc.links.filter((l) => {
        const end = side === 'out' ? l.from : l.to;
        return !(end.node === nodeId && end.pin === pin);
    });
    return before - doc.links.length;
}

export function removeLink(doc, id) { doc.links = doc.links.filter((l) => l.id !== id); }

/** Is anything wired to this pin? */
export function isWired(doc, nodeId, pin, side) {
    return doc.links.some((l) => {
        const end = side === 'out' ? l.from : l.to;
        return end.node === nodeId && end.pin === pin;
    });
}

// ---- placed things and variables: rename everywhere they are named (refs.js walks every place one can be) ----

/** A placed thing renamed everywhere: cards' and steps' fields, other things' settings (a car's riders, its key's spot,
 *  its trailers), the Settings. `taskTypes`: the step types (ed.tasks.types). */
export function renameWorld(doc, cards, taskTypes, oldId, newId) { renameRef(doc, cards, taskTypes, 'world', oldId, newId); }

/** A variable renamed everywhere: the cards that name it, read it, or read it inside (an answer's Only if). */
export function renameVar(doc, cards, oldId, newId) { renameRef(doc, cards, null, 'var', oldId, newId); }

/** Cards that name a placed thing (a 'worlds' list holding it too): [{ node, field }]. */
export function usesOfWorld(doc, cards, id) { return cardUses(doc, cards, 'world', id); }

/** usesOfWorld for every placed thing at once (one walk of the cards): Map id -> [{ node, field }]. */
export function usesOfWorlds(doc, cards) { return cardUsesAll(doc, cards, 'world'); }

/** Cards that name or read a variable. */
export function usesOfVar(doc, cards, id) { return cardUses(doc, cards, 'var', id); }

export { eachRef };

// ---- problems (Check's answers) ----

/** The cards a problem is about: its own card, and every card that names the placed thing it is about. */
export function problemCards(p) {
    const ids = [];
    if (p.node) ids.push(p.node);
    const more = listOf(p.nodes);
    for (const id of more) if (typeof id === 'string' && !ids.includes(id)) ids.push(id);
    return ids;
}

// ---- undo ----

export class History {
    /** `pack`: the document as it is kept, from what the editor holds (a variant's view: packDoc); none, as it is.
     *  Each step remembers the variant it was made in (undo goes back to it: lastVariant). */
    constructor(doc, pack) {
        this.pack = typeof pack === 'function' ? pack : (d) => d;
        this.stack = [JSON.stringify(this.pack(doc))];
        this.made = [(doc && doc.variantOpen) || 'v1'];
        this.at = 0;
        this.saved = this.stack[0];
        this.lastVariant = null;
    }

    /** Record the document as it is now. Answers false when nothing changed. */
    commit(doc) {
        const s = JSON.stringify(this.pack(doc));
        if (s === this.stack[this.at]) return false;
        this.stack.length = this.at + 1;
        this.made.length = this.at + 1;
        this.stack.push(s);
        this.made.push((doc && doc.variantOpen) || 'v1');
        // At most UNDO_LIMIT steps, and (a scenario of eight variants is big) about 24 MB of them.
        let bytes = this.stack.reduce((n, x) => n + x.length, 0);
        while (this.stack.length > 1 && (this.stack.length > UNDO_LIMIT || bytes > UNDO_BYTES)) {
            bytes -= this.stack[0].length;
            this.stack.shift();
            this.made.shift();
        }
        this.at = this.stack.length - 1;
        return true;
    }

    /** The document (as kept) one step back, or null. A change not yet committed (half-typed) counts as a step. The
     *  variant the undone step was made in: lastVariant. */
    undo(doc) {
        this.commit(doc);
        if (this.at === 0) return null;
        this.lastVariant = this.made[this.at];
        this.at -= 1;
        return JSON.parse(this.stack[this.at]);
    }

    redo() {
        if (this.at >= this.stack.length - 1) return null;
        this.at += 1;
        this.lastVariant = this.made[this.at];
        return JSON.parse(this.stack[this.at]);
    }

    /** A change made under the builder, not by them (a lore character's new ped): `change(doc)` is folded into the step
     *  it is on, and into the saved copy when that step is it. Nothing to undo, and nothing new to save. */
    adopt(doc, change) {
        this.commit(doc);   // a change of theirs not yet committed stays a step of its own, and unsaved
        const was = this.stack[this.at];
        change(doc);
        const s = JSON.stringify(this.pack(doc));
        this.stack[this.at] = s;
        if (this.saved === was) this.saved = s;
    }

    canUndo() { return this.at > 0; }
    canRedo() { return this.at < this.stack.length - 1; }
    markSaved(doc) { this.saved = JSON.stringify(this.pack(doc)); }
    /** What a save sent, as it was sent (the packed document's text, taken before the reply): what is typed while the
     *  save is on its way stays unsaved. */
    markSavedText(text) { this.saved = text; }
    isDirty(doc) { return JSON.stringify(this.pack(doc)) !== this.saved; }
}
