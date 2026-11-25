// ========================================
// INVENTORY CORE — OPTIMISTIC OPERATION ENGINE
//
// WHY OPERATIONS ARE KEYED
//
// Every drag applies immediately in the UI and is confirmed or rejected by the server a
// round-trip later, so it needs a pre-move snapshot to roll back to. Drags overlap on a real
// connection (a second drag before the first's reply), so each op keeps its own snapshot:
// reverting op N restores the state captured before N and DISCARDS every op after it,
// because those were computed against a state the server never had.
//
// THE OPID IS EXPLICIT. beginOp returns the id, the gesture carries it, and emit() REFUSES
// a dead or missing id instead of guessing.
//
// THE COMMIT RULE lives in confirmOldestOp/hasPendingOps: replies arrive in order, so each
// authoritative inventory sync confirms the oldest op — and the payload it carries is only
// TRUSTED when nothing is left pending, because until then the optimistic state is ahead of
// the server's snapshot, not behind it. That rule is the single most important thing here;
// core/inv-wire.js applies it.
// ========================================

import { INV_VIEWS } from './inv-state.js';
import { nuiCallback } from '../utils.js';

/** opId -> { views: {name: deepCopy}, at: ms } — in flight, oldest first by insertion. */
const pendingOps = new Map();
let nextOpId = 1;

/** An unanswered op is meaningless after this long; its snapshot only grows staler. */
const OP_TIMEOUT_MS = 15000;

// structuredClone, not a JSON round-trip: same deep-copy semantics for these stores (plain
// objects/arrays all the way down), without silently mangling anything a future store might
// hold that JSON cannot represent.
function deepCopy(v) {
    return v === null || v === undefined ? v : structuredClone(v);
}

/**
 * Snapshot the given views and open an operation.
 * @param {string[]} viewNames keys of INV_VIEWS
 * @returns {number} opId — the gesture carries this to extendOp/emit/commitOp
 */
export function beginOp(viewNames) {
    sweepOps();
    const views = {};
    for (const name of viewNames) {
        const view = INV_VIEWS[name];
        if (view) views[name] = deepCopy(view.get());
    }
    const opId = nextOpId++;
    pendingOps.set(opId, { views, at: Date.now() });
    return opId;
}

/**
 * Add more views to an operation already in progress.
 *
 * A drag opens one op up front covering the common views, then individual branches discover
 * they also touch the panel, the ignition slot or a target player's inventory. Opening a
 * SECOND op there would leave the first pending until some sweep collected it, and would
 * decouple the emit from the snapshot it belongs to. Extending keeps the correlation exact.
 *
 * A view already snapshotted is left alone: the existing copy was taken earlier in the same
 * gesture, which is precisely the state a revert should return to.
 * @param {number} opId    the gesture's op (from beginOp)
 * @param {string[]} viewNames keys of INV_VIEWS
 * @returns {number} opId — same id back, so call sites can treat extend like begin
 */
export function extendOp(opId, viewNames) {
    const op = pendingOps.get(opId);
    if (!op) return beginOp(viewNames);

    for (const name of viewNames) {
        const view = INV_VIEWS[name];
        if (view && !(name in op.views)) op.views[name] = deepCopy(view.get());
    }
    return opId;
}

/**
 * Send a move to Lua, tagged with the op it belongs to.
 *
 * The server echoes opId back on rejection, so the revert rolls back exactly the move that
 * failed instead of guessing at the oldest one still pending.
 *
 * REFUSES a missing or already-settled op instead of stamping garbage: an emit whose op was
 * never opened (or was reverted underneath it) is a coding error at the call site, and a
 * payload stamped with a stale id would make the server revert somebody else's move.
 * @param {number} opId
 * @param {string} action  NUI callback name
 * @param {object} payload
 */
export function emit(opId, action, payload) {
    const op = pendingOps.get(opId);
    if (!op) {
        console.error(`[spur_core:inv-ops] emit('${action}') with dead opId ${opId} — dropped. `
            + 'Every emit must carry the id of a live beginOp from its own gesture.');
        return;
    }
    op.emitted = true;   // see settleUnsentOp
    payload.opId = opId;
    nuiCallback(action, payload);
}

/** The op finished without ever reaching the server (a locally-rejected drag) — or the
 *  server accepted it and its snapshot is no longer needed. */
export function commitOp(opId) {
    if (opId !== undefined && opId !== null) pendingOps.delete(opId);
}

/**
 * The gesture is over: an op it opened and never SENT goes.
 *
 * A drag opens its op before any branch decides, and a dozen branches refuse locally — an item the
 * accessory slot does not take, a read-only crossing, a ground no-op — without emitting or
 * committing. The orphan sat at the front of the queue: the next real reply confirmed IT, the real
 * op stayed pending, and from then on every reply was dropped and every push held, until a later
 * drag swept it 15 s on. The drag handler calls this once, however it ends; an op that was emitted
 * is left for its answer.
 * @param {number|null} opId
 */
export function settleUnsentOp(opId) {
    if (opId === undefined || opId === null) return;
    const op = pendingOps.get(opId);
    if (op && !op.emitted) pendingOps.delete(opId);
}

/** Drop snapshots for ops that were never answered. */
export function sweepOps() {
    if (pendingOps.size === 0) return;
    const cutoff = Date.now() - OP_TIMEOUT_MS;
    for (const [opId, op] of pendingOps) {
        if (op.at < cutoff) pendingOps.delete(opId);
    }
}

/**
 * The panel stack as a revert should leave it: each panel that is STILL OPEN goes back to its
 * snapshot, and which panels are open is left as it is now: restoring the whole stack would close
 * a panel opened while the drag was in flight (its server session still open) and re-draw one
 * closed meanwhile.
 * @param {Array} now       inv.panels as it is
 * @param {Array} snapshot  inv.panels when the op began
 * @returns {Array}
 */
function restorePanels(now, snapshot) {
    const before = new Map();
    for (const p of snapshot || []) before.set(p.key, p);
    return (now || []).map(p => (before.has(p.key) ? before.get(p.key) : p));
}

/**
 * Roll back one operation and everything applied on top of it.
 * @param {number|undefined} opId  undefined falls back to the OLDEST pending op
 * @returns {boolean} whether anything was restored
 */
export function revertOp(opId) {
    if (pendingOps.size === 0) return false;

    // A reply from a server path that does not echo op ids: the oldest pending op is the
    // only defensible guess, and unwinding from it is at least deterministic.
    if (opId === undefined || opId === null) {
        opId = pendingOps.keys().next().value;
    } else if (!pendingOps.has(opId)) {
        // AN OP WE NO LONGER HOLD REVERTS NOTHING. It was swept (older than OP_TIMEOUT_MS) or
        // already settled; falling back to the oldest op would unwind one the server ACCEPTED — and
        // every op after it. The refusal also sends the truth for the two
        // slots it named (the server's reject), which is all the correcting the screen needs.
        return false;
    }

    const op = pendingOps.get(opId);
    if (!op) return false;

    const toRender = new Set();
    for (const name in op.views) {
        if (name === 'panels') {
            INV_VIEWS.panels.set(restorePanels(INV_VIEWS.panels.get(), op.views.panels));
        } else {
            INV_VIEWS[name].set(op.views[name]);
        }
        if (INV_VIEWS[name].render) toRender.add(name);
    }

    // Everything at or after this op was built on a state that never existed server-side.
    for (const [id] of pendingOps) {
        if (id >= opId) pendingOps.delete(id);
    }

    for (const name of toRender) INV_VIEWS[name].render();
    return true;
}

/** Confirm the oldest outstanding op — replies arrive in order, so each authoritative sync
 *  answers the front of the queue. */
export function confirmOldestOp() {
    const oldest = pendingOps.keys().next().value;
    if (oldest !== undefined) pendingOps.delete(oldest);
}

/** Confirm one op by id — the server's moveAck, for a drag whose answer is not an inventory
 *  push. An id that is already gone (reverted, swept) confirms nothing. */
export function confirmOp(opId) {
    if (opId !== undefined && opId !== null) pendingOps.delete(opId);
}

/** Is anything still in flight? While true, authoritative payloads describe an OLDER state
 *  than the screen and must not be applied. */
export function hasPendingOps() {
    return pendingOps.size > 0;
}

/**
 * The NEWEST push that arrived while ops were pending — an unsolicited one (a give, a satellite's
 * AddItem) or a reply that confirmed an op with others still behind it. It cannot be applied then —
 * the optimistic state is ahead of it — and it cannot be dropped either: an op the server answers
 * with a moveAck carries no state, so nothing else would ever deliver what this push says.
 * core/inv-wire.js applies it once the queue is empty, unless a newer payload got there first.
 * (Replies are held too, or an OLDER unsolicited push would be applied when a moveAck empties the
 * queue, and accepted moves would snap back.)
 */
let heldPush = null;

/** @param {object} data  an inventoryUpdate payload, newer than anything held */
export function holdPush(data) { heldPush = data; }

/** @returns {object|null} the held push, now released */
export function takeHeldPush() {
    const data = heldPush;
    heldPush = null;
    return data;
}

/**
 * Full resync — the server sent complete authoritative state (open, close, container
 * switch), so every optimistic guess in flight is moot. NOT for partial updates: a reply
 * about one container says nothing about the player-side ops still pending — those keep
 * their snapshots (the clearSnapshots-on-partial habit this replaces silently orphaned
 * them; see the engine header). A held push is older than a full resync, so it goes too.
 */
export function discardAllPendingOps() {
    pendingOps.clear();
    heldPush = null;
}
