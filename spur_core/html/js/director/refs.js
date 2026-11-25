// ========================================
// REFS — every reference in a scenario, walked one way
// ========================================
//
// What names a placed thing, a variable or another card: a card's field or a step's (by its kind: what it names,
// what is named inside it, the key it makes name something: refs-data.js FIELD_REFS, from server/director/fields.lua),
// a value that reads a variable, another placed thing's own settings (NAMED_IN: a car's riders, its key's spot) and
// the scenario's Settings (SETTINGS_NAMED). Renaming, counting who names something and the like all walk it here,
// so a new place a reference can live is said once, in the Lua (then dev/director/export_data.lua).
// ========================================

import { FIELD_REFS, NAMED_IN, SETTINGS_NAMED } from './refs-data.js';

// ---- groups: a 'worlds' field with `groups` may hold 'group:<name>', every placed thing of its kind whose page puts it
// in that group (its Group), read as server/director/nodes.lua DirectorNodes.expandThings reads it ----

export const GROUP = 'group:';

/** A group entry's name, or null (a placed thing's id). */
export function groupName(v) {
    if (typeof v !== 'string' || !v.startsWith(GROUP)) return null;
    const name = v.slice(GROUP.length).trim();
    return name || null;
}

/** A placed thing's group, trimmed, or null. */
export function groupOfThing(w) {
    const g = w && w.def && typeof w.def.group === 'string' ? w.def.group.trim() : '';
    return g || null;
}

/** The placed things a list names, each once, in order: a group as its members of `kind` (none: any), by id. */
export function expandThings(world, list, kind) {
    const out = [];
    const add = (id) => { if (!out.includes(id)) out.push(id); };
    for (const x of Array.isArray(list) ? list : typeof list === 'string' && list ? [list] : []) {
        const g = groupName(x);
        if (g) {
            (world || []).filter((w) => (!kind || w.kind === kind) && groupOfThing(w) === g).map((w) => w.id).sort().forEach(add);
        } else if (typeof x === 'string' && x) {
            add(x);
        }
    }
    return out;
}

/** Each value a path names in `obj`, with how to change it: visit(value, set). A path is keys with dots; `[]` is each
 *  of a list, `{}` each key of a table (only last: the key itself is the reference). */
function at(obj, path, visit) {
    const parts = path.split('.');
    const walk = (o, i) => {
        if (!o || typeof o !== 'object') return;
        const p = parts[i];
        const last = i === parts.length - 1;
        if (p.endsWith('[]')) {
            const list = o[p.slice(0, -2)];
            if (!Array.isArray(list)) return;
            if (last) list.forEach((v, j) => visit(v, (nv) => { list[j] = nv; }));
            else list.forEach((x) => walk(x, i + 1));
        } else if (p.endsWith('{}')) {
            const map = o[p.slice(0, -2)];
            if (!map || typeof map !== 'object') return;
            for (const key of Object.keys(map)) {
                visit(key, (nv) => { if (nv !== key) { map[nv] = map[key]; delete map[key]; } });
            }
        } else if (last) {
            visit(o[p], (nv) => { o[p] = nv; });
        } else {
            walk(o[p], i + 1);
        }
    };
    walk(obj, 0);
}

/** Every reference in a document (one variant's cards and things, and the Settings), each as fn({ kind ('world' |
 *  'var' | 'card'), id, set(newId), and where: node + field (a card's), thing + step + field (a step's), thing + named
 *  (a placed thing's own setting: a NAMED_IN entry, its path and says), or settings (a SETTINGS_NAMED entry) }), as
 *  server/director/refs.lua walks it. `cards`: the card types (ed.cards); `taskTypes`: the step types
 *  (ed.tasks.types), or null for cards and settings alone. */
export function eachRef(doc, cards, taskTypes, fn) {
    const emit = (kind, id, set, where) => { if (typeof id === 'string' && id) fn({ kind, id, set, ...where }); };
    const field = (f, holder, where) => {
        const v = holder[f.key];
        // Any field's value may read a variable instead ({ var }).
        if (v && typeof v === 'object' && !Array.isArray(v) && typeof v.var === 'string') emit('var', v.var, (nv) => { v.var = nv; }, where);
        const r = FIELD_REFS[f.kind];
        if (!r) return;
        if (r.names === 'worlds') {
            // (A group names each of its members; there is nothing in it to rename: the group is its name.)
            if (Array.isArray(v)) {
                v.forEach((x, j) => {
                    if (f.groups && groupName(x)) expandThings(doc.world, [x], f.worldKind).forEach((id) => emit('world', id, () => {}, where));
                    else emit('world', x, (nv) => { v[j] = nv; }, where);
                });
            } else if (f.groups && typeof v === 'string') {
                emit('world', v, (nv) => { holder[f.key] = nv; }, where);   // (one, as saved before its upgrade)
            }
        } else if (r.names) {
            emit(r.names, v, (nv) => { holder[f.key] = nv; }, where);
        }
        if (r.refs && v && typeof v === 'object') {
            for (const [kind, keys] of Object.entries(r.refs)) for (const k of keys) emit(kind, v[k], (nv) => { v[k] = nv; }, where);
        }
        const sib = r.sibling;
        if (sib && (v !== undefined ? v : f.default) === sib.when) emit(sib.names, holder[sib.key], (nv) => { holder[sib.key] = nv; }, where);
    };
    for (const n of doc.nodes || []) {
        const def = cards && cards.get(n.type);
        if (n.props) for (const f of (def && def.props) || []) field(f, n.props, { node: n, field: f });
    }
    for (const w of doc.world || []) {
        const t = w.def && w.def.tasks;
        for (const s of (taskTypes && t && Array.isArray(t.list) ? t.list : [])) {
            const d = s && taskTypes.get(s.t);
            for (const f of (d && d.fields) || []) field(f, s, { thing: w, step: s, stepDef: d, field: f });
        }
        for (const p of NAMED_IN) {
            if (p.kind === w.kind && w.def) at(w.def, p.path, (id, set) => emit('world', id, set, { thing: w, named: p }));
        }
    }
    if (doc.settings) for (const p of SETTINGS_NAMED) at(doc.settings, p.path, (id, set) => emit('world', id, set, { settings: p }));
}

/** Rename a placed thing, a variable or a card (`kind`) everywhere it is named. */
export function renameRef(doc, cards, taskTypes, kind, oldId, newId) {
    eachRef(doc, cards, taskTypes, (r) => { if (r.kind === kind && r.id === oldId) r.set(newId); });
}

/** What a reference says in a list of who names a thing (the world builder map's mark cards): its card, its thing's
 *  task, its thing's own setting, a Setting (server/director/refs.lua namerText says the same). */
export function namerText(r, cards) {
    if (r.node) {
        const def = cards && cards.get(r.node.type);
        return (def && def.title) || r.node.type;
    }
    const name = r.thing ? String(r.thing.label || r.thing.id) : '';
    if (r.step) return `${name}'s task: ${(r.stepDef && r.stepDef.label) || r.step.t}`;
    if (r.named) return `${name}: ${r.named.says}`;
    return r.settings ? r.settings.says : '?';
}

/** The cards that name it: [{ node, field }], each field once. */
export function cardUses(doc, cards, kind, id) {
    const out = [];
    eachRef(doc, cards, null, (r) => {
        if (r.node && r.kind === kind && r.id === id && !out.some((u) => u.node === r.node && u.field === r.field)) out.push({ node: r.node, field: r.field });
    });
    return out;
}

/** cardUses for every id of a kind at once, in one walk of the cards: Map id -> [{ node, field }]. */
export function cardUsesAll(doc, cards, kind) {
    const out = new Map();
    eachRef(doc, cards, null, (r) => {
        if (!r.node || r.kind !== kind) return;
        let list = out.get(r.id);
        if (!list) { list = []; out.set(r.id, list); }
        if (!list.some((u) => u.node === r.node && u.field === r.field)) list.push({ node: r.node, field: r.field });
    });
    return out;
}
