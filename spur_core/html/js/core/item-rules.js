// ========================================
// ITEM RULES — an item's `when`, and its picture's path, on the page
//
// The page's half of server/item_options.lua (the rules are written out there): what to SHOW. An
// option whose `when` fails is left off the menu, and the first picture whose `when` passes is drawn.
// The server asks the same `when` again before an option runs, so the two must agree:
// dev/item_rules_test.js runs one list of cases through both.
//
// A leaf module, no imports: utils.js (pictures) and inventory.js (the menu) both read it.
// ========================================

const finite = (v) => typeof v === 'number' && Number.isFinite(v);

/** Nothing, false, '', 0, or a table with nothing in it. */
function isEmpty(v) {
    if (v === undefined || v === null || v === false || v === '' || v === 0) return true;
    if (typeof v === 'object') return Object.keys(v).length === 0;
    return false;
}

/** One field's test against its value. Only a number is a number: '5' is text. */
function passes(test, v) {
    if (test === null || typeof test !== 'object') return v === test;
    if (Array.isArray(test)) return test.some((x) => v === x);
    // `default`: what a field the item does not have counts as (a magazine with no ammo is empty).
    if ((v === undefined || v === null) && test.default !== undefined) v = test.default;
    if (test.empty !== undefined && isEmpty(v) !== test.empty) return false;
    const n = finite(v) ? v : null;
    if (test.above !== undefined && !(n !== null && n > test.above)) return false;
    if (test.below !== undefined && !(n !== null && n < test.below)) return false;
    if (test.atLeast !== undefined && !(n !== null && n >= test.atLeast)) return false;
    if (test.atMost !== undefined && !(n !== null && n <= test.atMost)) return false;
    return true;
}

/**
 * Does an item's metadata pass a `when`? No `when` passes.
 * @param {object|undefined} when  { field: test }, as the server checked it
 * @param {object|undefined} meta  the item's metadata
 */
export function whenMet(when, meta) {
    if (!when || typeof when !== 'object') return true;
    const m = meta && typeof meta === 'object' ? meta : {};
    for (const field of Object.keys(when)) {
        if (!passes(when[field], m[field])) return false;
    }
    return true;
}

/**
 * Does a slot's count pass a picture's `amount` (above / below / atLeast / atMost)? No `amount` passes; no count
 * (a shop's list, /whip → Items: no slot) fails, so the item's own picture is drawn there.
 * @param {object|undefined} amount  as the server checked it (server/item_options.lua cleanImages)
 * @param {number|undefined} count   the slot's amount
 */
export function amountMet(amount, count) {
    if (!amount || typeof amount !== 'object') return true;
    return passes(amount, finite(count) ? count : null);
}

/**
 * A picture path with its {field} parts filled from the item's metadata: lowercased, letters, digits,
 * _ and - only. {make} is the maker of the car the item's `model` names, when the metadata has no make
 * of its own: `makeOf(model)` answers it, '' for none, or undefined when the game has not been asked yet.
 * @returns {{ path: string|null, waitModel: string|null }}  path null when a part cannot be filled;
 *          waitModel set when the only thing missing is a maker not asked yet
 */
export function fillImagePath(path, meta, makeOf) {
    const m = meta && typeof meta === 'object' ? meta : {};
    let missing = false;
    let waitModel = null;
    const out = String(path).replace(/\{(\w+)\}/g, (_, name) => {
        let v = m[name];
        if ((v === undefined || v === null || v === '') && name === 'make' && typeof m.model === 'string' && m.model) {
            v = makeOf(m.model);
            if (v === undefined) waitModel = m.model;
        }
        const clean = v === undefined || v === null ? '' : String(v).toLowerCase().replace(/[^a-z0-9_-]/g, '');
        if (!clean) missing = true;
        return clean;
    });
    if (!missing) return { path: out, waitModel: null };
    return { path: null, waitModel };
}
