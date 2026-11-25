// ========================================
// SYSTEMS — the system document in the editor
//
// The document is the server's (shared/systems/compile.lua has the shape): { format = 1, kind =
// 'system', name, description, settings, vars[], nodes[], links[], comments[] }, a node carrying its
// fields (props) AND the typed-in values of its unwired value inputs (values). One object; the canvas
// and the column draw from it, and saving sends it whole.
//
// A DOCUMENT FROM LUA IS NORMALISED FIRST (plan S1b's known gap): Lua has one table type, so an empty
// list arrives as {} and an empty map as []. normalise() makes lists lists and maps maps; a map left an
// array would lose every named key on its way back up. Keys this editor does not know are KEPT.
//
// The wire, id, comment, copy and undo helpers are the Director's (director/doc.js): the canvas is
// shared, and both editors' documents have the same nodes and links.
// ========================================

export {
    History, findNode, addLink, breakPin, removeLink, isWired, freeId, slug, isId, copyNodes, pasteNodes,
    makeComment, removeComment, findComment, duplicateNodes, removeNodes, problemCards, nodeIds,
} from '../director/doc.js';
import { freeId, nodeIds, COMMENT_MIN, COMMENT_TEXT_MAX, isId } from '../director/doc.js';

export const FORMAT = 1;
export const SCOPES = [['everyone', 'For everyone'], ['player', 'Per player'], ['car', 'Per car']];
export const VAR_TYPES = [['number', 'Number'], ['text', 'Text'], ['bool', 'Yes / no'], ['list', 'List'],
    ['player', 'Player'], ['vehicle', 'Car'], ['vector', 'Place']];
const REMEMBERABLE = new Set(['number', 'text', 'bool']);

const isObj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x);

function list(x) {
    if (Array.isArray(x)) return x.filter(isObj);
    if (isObj(x)) return Object.keys(x).sort((a, b) => Number(a) - Number(b)).map((k) => x[k]).filter(isObj);
    return [];
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
    doc.kind = 'system';
    doc.name = str(d.name) || 'Untitled';
    doc.description = str(d.description);
    doc.settings = map(d.settings);
    doc.vars = list(d.vars);
    for (const v of doc.vars) {
        if (!v.scope) v.scope = 'everyone';
        if (v.remember !== true) delete v.remember;
    }
    doc.nodes = list(d.nodes);
    doc.links = list(d.links);
    for (const n of doc.nodes) {
        n.props = map(n.props);
        n.values = map(n.values);
        n.x = num(n.x, 0);
        n.y = num(n.y, 0);
        // A place field from Lua: { x, y, z } (an empty one is no field at all).
        for (const k of Object.keys(n.props)) {
            const v = n.props[k];
            if (Array.isArray(v) && v.length === 0) delete n.props[k];
        }
    }
    for (const l of doc.links) {
        l.from = map(l.from);
        l.to = map(l.to);
    }
    const noteIds = new Set();
    doc.comments = list(d.comments).filter((c) => isId(c.id) && !noteIds.has(c.id) && noteIds.add(c.id));
    for (const c of doc.comments) {
        c.x = num(c.x, 0);
        c.y = num(c.y, 0);
        c.w = Math.max(COMMENT_MIN.w, num(c.w, 320));
        c.h = Math.max(COMMENT_MIN.h, num(c.h, 200));
        c.text = str(c.text).slice(0, COMMENT_TEXT_MAX);
    }
    return doc;
}

/** A card's definition from the server's `cards` answer: lists as lists, value pins as records. */
export function normaliseDef(def) {
    def.inputs = Array.isArray(def.inputs) ? def.inputs : Object.values(def.inputs || {});
    def.outputs = Array.isArray(def.outputs) ? def.outputs : Object.values(def.outputs || {});
    def.props = list(def.props);
    for (const f of def.props) if (f.options && !Array.isArray(f.options)) f.options = Object.values(f.options);
    const v = map(def.values);
    def.values = { inputs: list(v.inputs), outputs: list(v.outputs) };
    def.labels = map(def.labels);
    return def;
}

/** A new card of a type, its fields at their defaults. */
export function makeNode(doc, def, x, y) {
    const short = def.type.split('.').pop();
    const props = {};
    for (const f of def.props || []) {
        if (f.default !== undefined && f.default !== null) props[f.key] = f.default;
    }
    const node = { id: freeId(nodeIds(doc), short), type: def.type, v: def.v, x: Math.round(x), y: Math.round(y), props, values: {} };
    doc.nodes.push(node);
    return node;
}

/** Can a variable of this type be remembered (kept across restarts)? compile.lua's rule. */
export function canRemember(v) { return REMEMBERABLE.has(v.type) && v.scope !== 'car'; }

/** Every place field of every card, for the Places tab: [{ node, def, field, value }]. */
export function placesOf(doc, cards) {
    const out = [];
    for (const n of doc.nodes) {
        const def = cards.get(n.type);
        for (const f of (def && def.props) || []) {
            if (f.kind === 'place') out.push({ node: n, def, field: f, value: placeValue(n.props[f.key]) });
        }
    }
    return out;
}

/** A place field's value: { x, y, z } or null. */
export function placeValue(v) {
    return v && typeof v === 'object' && typeof v.x === 'number' && typeof v.y === 'number' && typeof v.z === 'number' ? v : null;
}

/** "123.4, -567.8, 30.1" */
export function placeText(v) {
    const p = placeValue(v);
    return p ? `${p.x.toFixed(1)}, ${p.y.toFixed(1)}, ${p.z.toFixed(1)}` : '';
}
