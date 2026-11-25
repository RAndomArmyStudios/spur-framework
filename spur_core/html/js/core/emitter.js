// ========================================
// INVENTORY CORE — EVENT EMITTER
//
// The seam between the core and whatever draws it. The wire layer (core/inv-wire.js)
// mutates core state and then announces WHAT HAPPENED here; renderers subscribe and decide
// what that means on screen. The core never names a renderer function — that is the whole
// property that makes a custom inventory UI possible (docs/nui-inventory.md lists the
// events and their payloads; that list is the third-party contract).
//
// Deliberately tiny: named events, multiple subscribers, synchronous dispatch in
// subscription order. Synchronous MATTERS — the wire relies on "state mutated, then event
// handled, then next message" staying one uninterruptible sequence, the same way the op
// engine relies on a gesture being synchronous.
// ========================================

const listeners = new Map();   // event name -> [fn, fn, ...]

export const invEvents = {
    /** Subscribe. Returns an unsubscribe function. */
    on(event, fn) {
        let list = listeners.get(event);
        if (!list) { list = []; listeners.set(event, list); }
        list.push(fn);
        return () => {
            const i = list.indexOf(fn);
            if (i !== -1) list.splice(i, 1);
        };
    },

    /** Announce. Subscriber errors are caught and logged so one broken renderer cannot
     *  stop the wire from finishing its sequence. */
    emit(event, payload) {
        const list = listeners.get(event);
        if (!list) return;
        for (let i = 0; i < list.length; i++) {
            try { list[i](payload); }
            catch (err) { console.error(`[spur_core:inv-events] '${event}' subscriber threw:`, err); }
        }
    },
};
