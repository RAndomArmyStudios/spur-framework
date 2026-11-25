// ========================================
// ITEM DEFINITIONS — the one shared item-def store
//
// Split into its own module because it sits UNDER everything: utils.js needs it to resolve
// icon URLs, inventory.js adopts server payloads into it, hotbar.js reads it to draw slots.
// When it lived in the inventory cluster, utils.js — which loads first — had to probe for it
// with a `typeof` guard; under module scoping that guard would throw in the TDZ instead of
// answering. A leaf module with no imports ends the problem: everyone imports from here and
// there is no cycle to race.
// ========================================

export let invItemDefs = {};   // [key] = { name, desc, weight, type, stack, css, usable,
                               //           contextOptions, metaFields, defaultAction, img }

/**
 * Adopt item definitions from any server payload that may carry them.
 *
 * ABSENT MEANS UNCHANGED, NOT NONE. Item defs are big — hundreds of items, generated
 * markup-adjacent fields — and sending them with every inventory open cost the server a
 * full msgpack encode of the set each time. The server now omits them once this client has
 * them, and `data.itemDefs || {}` would turn that omission into an inventory of nameless,
 * weightless, imageless items. Only assign when the field is actually present.
 */
export function adoptItemDefs(data) {
    if (data && data.itemDefs) {
        invItemDefs = data.itemDefs;
        // A fresh set of defs can carry a fresh set of icons — a satellite that was stopped when
        // its art last 404'd may be back. Anything learned about the old table is now a guess
        // about a table that no longer exists.
        _noIcon = new Set();
    }
}

/** For call sites that want the current table without holding a live binding (utils.js). */
export function getItemDefs() {
    return invItemDefs;
}

// ---- Which items have no icon, learned the hard way ----
//
// THE BROKEN-IMAGE FLICKER. An item with no art 404s, and the fallback in utils.js swaps in
// missing.png — but only after the request has already failed, and in between the browser draws
// its own broken-image glyph. Harmless once; the problem is that every re-render builds a fresh
// <img> and asks again, so the glyph flashed on EVERY inventory move, forever, for the same item.
// (Items that DO have art never flickered because the second request is a cache hit.)
//
// So the failure is remembered and itemImageUrl answers missing.png outright next time. Exactly
// what vehicleImageUrl already does for a model it knows has no picture — "goes straight to the
// placeholder rather than 404ing first" — applied to items.
//
// It lives HERE rather than in utils.js so the invalidation above can reach it. utils.js already
// imports from this module; importing the other way would build the cycle this file's header
// exists to explain away.
//
// STILL ONE FLICKER PER ITEM PER SESSION, on the first sighting, because nothing tells the client
// which icons exist before it asks. Killing that needs the server to ship a per-item `hasImage`
// the way the prop catalog does — worth doing, and a bigger change than this.
let _noIcon = new Set();

/** Record that this item's icon could not be found anywhere. */
export function noteItemIconMissing(itemKey) {
    if (itemKey) _noIcon.add(itemKey);
}

/** Have we already proven this item has no icon? */
export function itemIconIsMissing(itemKey) {
    return _noIcon.has(itemKey);
}
