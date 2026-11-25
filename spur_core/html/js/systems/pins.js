// ========================================
// SYSTEMS — value pins, as the canvas draws them (ed.typed: director/canvas.js)
//
// A card's value pins are its type's (def.values) plus, for a card whose pins come from its fields,
// what those fields make now:
//   Formula             the names its line reads (formula.js, a copy of formula.lua's reader)
//   Get / Set Variable  one Value pin of the variable's type
//   Ask With a Form     one answer pin per question written in
//   anything else      what the server's Check last said (ed.serverPins), until it answers again
// A pin still wired but no longer named (a name taken out of a Formula) is kept, marked gone, so its
// wire shows where it was instead of vanishing.
//
// TYPES: the server's SystemCards.TYPES says each type's colour group (six a builder sees: number,
// text, yes/no, place, person, thing; `any` grey). The wire rule is cards.lua's C.compatible, here so
// a drag is refused at once; Check has the last word.
// ========================================

import { formulaPins } from './formula.js';
import { isWired } from './doc.js';

export const FAMILY_TITLE = { number: 'Number', text: 'Text', bool: 'Yes / no', place: 'Place', person: 'Person', thing: 'Thing', any: 'Anything' };

const TYPE_TITLE = {
    number: 'a number', text: 'text', bool: 'a yes/no', vector: 'a place', area: 'an area', point: 'a point',
    player: 'a player', character: 'a character', vehicle: 'a car', npc: 'an NPC', item: 'an item', door: 'a door',
    container: 'a container', job: 'a job', shop: 'a shop', account: 'an account', receipt: 'a receipt',
    list: 'a list', record: 'a record', any: 'anything',
};

export function typeTitle(t) { return TYPE_TITLE[t] || t || 'anything'; }

/** cards.lua C.compatible: can a wire carry `from` into `to`? */
export function compatible(from, to) {
    if (to === 'receipt' || from === 'receipt') return from === to;
    if (from === to || from === 'any' || to === 'any') return true;
    if (from === 'player' && to === 'character') return true;
    return false;
}

/** A typed-in value, as a card shows it beside its pin. */
export function constText(type, v) {
    if (v === undefined || v === null) return '';
    if (typeof v === 'boolean') return v ? 'yes' : 'no';
    if (typeof v === 'number') return String(Math.round(v * 1000) / 1000);
    if (typeof v === 'string') return v.length > 16 ? `“${v.slice(0, 15)}…”` : `“${v}”`;
    if (typeof v === 'object' && typeof v.x === 'number') return 'a place';
    return '…';
}

/** The typed-in value a value input has (node.values), else its default. */
export function constOf(node, pin) {
    const v = node.values ? node.values[pin.key] : undefined;
    if (v !== undefined && v !== null) return { value: v, typed: true };
    if (pin.default !== undefined && pin.default !== null) return { value: pin.default, typed: false };
    return null;
}

const list = (x) => (Array.isArray(x) ? x : Object.values(x || {}));

// Ask With a Form (cards_server.lua): how many questions, and the pin type each kind answers.
const ASK_FIELDS = 3;
const FIELD_PIN = { text: 'text', number: 'number', 'yes/no': 'bool', 'pick one': 'text' };

/**
 * Make the canvas's ed.typed for an editor: `types` is the server's SystemCards.TYPES (type -> family).
 * `ed` supplies doc, cards, serverPins (Map id -> { inputs, outputs }).
 */
export function makeTyped(ed, types) {
    const fam = (t) => (types && types[t]) || 'any';

    /** A card's value pins now: { inputs, outputs } of { key, type, label, optional, default }. */
    function valuePins(node, def, doc) {
        const vin = list(def.values && def.values.inputs).slice();
        const vout = list(def.values && def.values.outputs).slice();
        if (def.dynamicPins) {
            let extra = null;
            if (def.type === 'math.formula') {
                const p = formulaPins(node.props.expr == null ? defaultOf(def, 'expr') : node.props.expr);
                extra = p.error ? { inputs: [], outputs: [], error: p.error } : p;
            } else if (def.type === 'ask.form') {
                extra = { inputs: [], outputs: askFormPins(node.props, def) };
            } else if (def.type === 'var.get' || def.type === 'var.set') {
                const v = doc.vars.find((x) => x.id === node.props.var);
                const pin = v ? [{ key: 'value', type: v.type, label: 'Value' }] : [];
                extra = def.type === 'var.get' ? { inputs: [], outputs: pin } : { inputs: pin, outputs: [] };
            } else {
                const sp = ed.serverPins && ed.serverPins.get(node.id);
                if (sp) extra = { inputs: list(sp.inputs), outputs: list(sp.outputs) };
            }
            if (extra) {
                for (const p of list(extra.inputs)) vin.push(p);
                for (const p of list(extra.outputs)) vout.push(p);
            }
        }
        return { inputs: vin, outputs: vout };
    }

    function defaultOf(def, key) {
        const f = (def.props || []).find((x) => x.key === key);
        return f ? f.default : undefined;
    }

    /** Ask With a Form's answer pins: one per question written in (cards_server.lua's formFields). */
    function askFormPins(props, def) {
        const out = [];
        for (let i = 1; i <= ASK_FIELDS; i++) {
            const raw = props['label' + i];
            const label = raw === undefined || raw === null ? defaultOf(def, 'label' + i) : raw;
            // Lua's %S: anything but its six spaces (JS's \s also counts a no-break space as one).
            if (typeof label !== 'string' || !/[^ \t\n\v\f\r]/.test(label)) continue;
            const kind = FIELD_PIN[props['type' + i]] ? props['type' + i] : 'text';
            out.push({ key: 'answer' + i, type: FIELD_PIN[kind], label: label.slice(0, 60) });
        }
        return out;
    }

    function record(node, p, side) {
        const rec = { pin: p.key, label: p.label || p.key, type: p.type, fam: fam(p.type), optional: p.optional === true, def: p.default };
        if (side === 'in') {
            const c = constOf(node, p);
            if (c) rec.konst = constText(p.type, c.value);
        }
        return rec;
    }

    return {
        valuePins,
        family: fam,

        /** The canvas's question: every value pin of a card as drawn (director/canvas.js pinsFor). */
        pinsOf(node, def, doc) {
            if (!def) return { inputs: [], outputs: [] };
            const vp = valuePins(node, def, doc);
            const inputs = vp.inputs.map((p) => record(node, p, 'in'));
            const outputs = vp.outputs.map((p) => record(node, p, 'out'));
            // Still wired, no longer one of its pins: kept, marked gone, so the wire stays in view.
            const names = new Set([...(def.inputs || []), ...(def.outputs || []), ...inputs.map((p) => p.pin), ...outputs.map((p) => p.pin)]);
            for (const l of doc.links) {
                if (l.to.node === node.id && !names.has(l.to.pin)) {
                    names.add(l.to.pin);
                    inputs.push({ pin: l.to.pin, label: l.to.pin + ' (gone)', type: 'any', fam: 'any', gone: true });
                }
                if (l.from.node === node.id && !names.has(l.from.pin)) {
                    names.add(l.from.pin);
                    outputs.push({ pin: l.from.pin, label: l.from.pin + ' (gone)', type: 'any', fam: 'any', gone: true });
                }
            }
            return { inputs, outputs };
        },

        /** null when a value wire may carry `from`'s type into `to`, else why not. */
        canConnect(from, to) {
            if (from.gone || to.gone) return 'That pin is gone from its card: take its wire off';
            if (compatible(from.type, to.type)) return null;
            return `${to.label} takes ${typeTitle(to.type)}, and this is ${typeTitle(from.type)}`;
        },
    };
}

/** Is a value input wired (so its typed-in value is not used)? */
export function inputWired(doc, nodeId, key) { return isWired(doc, nodeId, key, 'in'); }
