// ========================================
// WHEN — a field or an outcome only some of the time
// ========================================
//
// The editor's reading of a field's `when` and a card's `pinWhen` ({ [pin]: when }), the same as the server's
// (server/director/fields.lua DirectorFields.holds), so a field the page hides is one Check does not count, and an
// outcome the card draws without is one Check does not ask to be wired:
//   { key, is }      its value (its field's default when it has none) is that     isnt: it is not
//   { key, set }     set true: it has a value saved, not empty; set false: it has none
//   { key, above }   its value (or default) is a number above that
//   { all: [...] }   every one holds          { any: [...] }  one of them does
//   false            never: an outcome a card no longer takes, drawn only while a wire still leaves it
// A key may be a path into a field that is a table ('opt1Rule.chance').
// ========================================

function valueAt(values, key) {
    let v = values;
    for (const part of String(key).split('.')) {
        if (!v || typeof v !== 'object') return undefined;
        v = v[part];
    }
    return v;
}

function defaultOf(fields, key) {
    const f = (fields || []).find((x) => x.key === key);
    return f ? f.default : undefined;
}

/** Does `c` hold for these values (a card's props, a step)? `fields`: theirs, for defaults. No `c`: it does. */
export function holds(c, values, fields) {
    if (c === false) return false;
    if (!c || typeof c !== 'object') return true;
    if (Array.isArray(c.all)) return c.all.every((x) => holds(x, values, fields));
    if (Array.isArray(c.any)) return c.any.some((x) => holds(x, values, fields));
    const raw = valueAt(values || {}, c.key);
    if (c.set !== undefined && c.set !== null) return (raw !== undefined && raw !== null && raw !== '') === c.set;
    const v = raw === undefined || raw === null ? defaultOf(fields, c.key) : raw;
    if (c.is !== undefined && c.is !== null) return v === c.is;
    if (c.isnt !== undefined && c.isnt !== null) return v !== c.isnt;
    if (c.above !== undefined && c.above !== null) return typeof v === 'number' && v > c.above;
    return true;
}

/** The keys a `when` reads (its fields that only say which others show). */
export function whenKeys(c, out = new Set()) {
    if (!c || typeof c !== 'object') return out;
    for (const x of c.all || c.any || []) whenKeys(x, out);
    if (typeof c.key === 'string') out.add(c.key.split('.')[0]);
    return out;
}
