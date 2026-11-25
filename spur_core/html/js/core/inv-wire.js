// Inventory core, wire layer: every NUI message the inventory receives lands here. Each handler mutates core state,
// then tells the seated renderer what to draw through the renderer interface. No DOM here, which is what lets a
// custom renderer get the whole message protocol, op engine and state machine. The DOM's answers the wire needs
// (isMidDrag(), hasPlayerGrid()) come back through the same interface.
// R() null-guards every handler: a message arriving before any renderer has loaded mutates state and skips drawing;
// the next render-bearing message repaints from state.

import { NuiRouter } from '../router.js';
import { nuiCallback } from '../utils.js';
import { adoptItemDefs } from './item-defs.js';
import { inv, shop, invShopHooks, invHotbarHooks, adoptSlotDefs,
         panelKeyFor, panelById } from './inv-state.js';
import { confirmOldestOp, confirmOp, hasPendingOps, revertOp, discardAllPendingOps, holdPush, takeHeldPush, sweepOps } from './inv-ops.js';
import { invEvents } from './emitter.js';
import { getRenderer } from './inventory.js';

const R = getRenderer;

/** The player-half adoption every open path shares — one copy, so the seven callers can
 *  never drift on which fields exist. */
function adoptPlayerHalf(data) {
    inv.state = data.inventory || { player: {} };
    if (!inv.state.accessory) inv.state.accessory = {};
    adoptItemDefs(data);
    inv.weights    = data.weights      || { player: 0 };
    inv.maxSlots   = data.maxSlots     || { player: 30 };
    inv.maxWeight  = data.maxWeight    || { player: 80 };
    inv.charName   = data.charName      || '';
    inv.charId     = data.charId        || 0;
    inv.accountNum = data.accountNumber || '';
}

// ------------------------------------------
// OPEN / CLOSE
// ------------------------------------------

export function openInventory(data) {
    if (inv.open) return;
    inv.open = true;
    if (invHotbarHooks) invHotbarHooks.hideHotbar();

    if (data) {
        adoptPlayerHalf(data);
        inv.groundItems = data.groundItems || {};
    } else {
        console.warn('[spur_core:inv-wire] openInventory called with no data!');
    }

    const r = R();
    if (r) {
        // NEARBY BELONGS TO THIS PATH AND ONLY THIS PATH. Stated explicitly rather than left
        // to whatever the last session happened to leave behind: a previous open that hid it
        // (a boot, a stash, sitting in a car) would otherwise keep it hidden here.
        r.setPanels({ ground: true });
        r.renderAll();
        r.showOverlay();
    }
    invEvents.emit('open', { kind: 'plain' });
}

// `{ echo: false }` WHEN LUA ASKED FOR THIS CLOSE (the 'closeInventory' message below). Lua's
// CloseInventory has already done the whole teardown before it tells the page, so there is nothing
// to report back — and reporting it anyway ran CloseInventory a SECOND time, a frame or more
// later, by which point something new could be open. A panel closed and another opened straight
// after (whip_test 21, 09-24) lost the new one to the echo of the old one's close; the echo also
// cancelled any open the player had just asked for. Every close the PAGE starts (Escape, the
// renderer's close, closePlayerInventory) still reports back: Lua has not heard of those yet.
export function closeInventory(opts) {
    if (!inv.open) return;
    const echo = !(opts && opts.echo === false);
    inv.open = false;
    const r = R();
    if (r) r.cancelInteractions();

    // Any in-flight optimistic change is moot once the UI is gone — and the pre-engine code
    // leaked three of the five snapshots here, so a reply arriving after a close could
    // restore a stale view over the top of whatever the server had since sent.
    discardAllPendingOps();

    // Reset container + ignition state through the shared helper, so this and the live
    // panel swap can never clear different sets of fields. The panel displays stay
    // conditional: only the CLOSE path restores ground-visible as a resting state, and only
    // when a container had actually been open, exactly as before.
    const wasContainerOpen = inv.containerOpen;
    clearContainerState();
    if (r && wasContainerOpen) r.setPanels({ container: false, ground: true });
    if (r) r.setPanels({ ignition: false });

    // EVERY open panel goes, not "the" panel. Emptying the array is the whole teardown now —
    // the six fields this replaced each had to be reset by hand, and the live-swap path and
    // this one were two chances to reset different subsets of them.
    if (inv.panels.length) {
        inv.panels = [];
        if (r) r.renderPanelStack();
    }

    if (inv.playerInvOpen) {
        inv.playerInvOpen = false;
        inv.playerInvItems = { player: {} };
        inv.playerInvCharName = '';
        inv.playerInvCharId = 0;
        inv.playerInvWeights = { player: 0 };
        inv.playerInvMaxSlots = { player: 30 };
        inv.playerInvMaxWeight = { player: 80 };
        if (r) r.setPanels({ playerInv: false, ground: true });
    }

    // Shop teardown is shops.js's job (visual only — Lua CloseInventory handles the server).
    if (shop.open && invShopHooks) invShopHooks.closeShop();

    if (r) r.hideOverlay();
    invEvents.emit('close', {});
    if (echo) nuiCallback('closeInventory');
}

// ------------------------------------------
// LIGHTWEIGHT LOGIN SYNC
// ------------------------------------------

// Populates inv.state + item defs so the hotbar works before the player ever opens the
// inventory. NOTE the payload is FLAT (d.inventory, d.itemDefs) — this predates the
// `.data` envelope the other actions use.
export function inventoryFlagsSync(d) {
    if (d.inventory) {
        inv.state = d.inventory;
        if (!inv.state.accessory) inv.state.accessory = {};
    }
    adoptItemDefs(d);
    // Late-join half of the slot registry: a player who connects after every satellite
    // registered never saw the broadcasts, so the login sync carries the current table.
    if (d.slotDefs) registerInvSlotDefs({ data: d.slotDefs });
}

/** The accessory-strip + ignition-key registry arriving (broadcast or login sync). */
export function registerInvSlotDefs(d) {
    adoptSlotDefs(d.data);
    const r = R();
    if (r) r.renderAccessories();
    invEvents.emit('slot-defs', d.data);
}

// ------------------------------------------
// CONTAINER
// ------------------------------------------

/**
 * Adopt a container payload into core state.
 *
 * Shared by the cold open and the live ground->glovebox swap so the two can never drift on
 * which fields exist — a missed inv.containerStoreId means storeDelta traffic stops
 * matching and the grid just stops updating. Deliberately does NOT touch inv.open or the
 * panels — the caller owns both, because a cold open and a live swap want different things.
 */
function applyContainerState(data) {
    if (!data) return;

    adoptPlayerHalf(data);

    // A store newly on screen, not a re-send of the one already there (a glovebox's open completing,
    // a reconcile). Shift-click sends to whatever was opened most recently, so a re-send must not
    // make this "newer" than a wallet opened after it.
    if (!inv.containerOpen || inv.containerStoreId !== (data.storeId || null)) {
        inv.containerOpenedAt = Date.now();
    }
    // GROUND IS NOT WIPED HERE: panels stack, so Nearby can stay beside the container.
    // Nothing needs to repopulate it: ground is proximity-driven and refreshGroundItems is
    // ungated, so client/ground.lua's sweep keeps it current whatever else is open.

    inv.containerOpen   = true;
    inv.containerId     = data.containerId;
    inv.containerDef    = data.containerDef || { name: 'Stash', slots: 20, maxWeight: 100 };
    inv.containerItems  = data.containerInv || {};
    inv.containerWeight = data.containerWeight || 0;
    // Which store this grid IS, so updates caused by other people looking at the same one
    // can be matched to it: 'container:42' versus 'vehicle:7:trunk'.
    inv.containerStoreId = data.storeId || null;

    inv.stockMode   = data.stockMode || false;
    inv.stockShopId = data.stockShopId || null;
    inv.stockPrices = data.stockPrices || {};

    if (data.showIgnition) {
        inv.ignitionOpen = true;
        inv.ignitionSlot = data.ignitionSlot || null;
        inv.ignitionVehicleId = data.ignitionVehicleId || null;
    } else {
        inv.ignitionOpen = false;
        inv.ignitionSlot = null;
        inv.ignitionVehicleId = null;
    }
}

/** Drop container + ignition state, leaving the inventory itself open. Clearing the
 *  ignition trio matters as much as the container one: leave it set and a stale Ignition
 *  panel survives the swap back to the ground. */
function clearContainerState() {
    inv.containerOpen    = false;
    inv.containerId      = null;
    inv.containerStoreId = null;
    inv.containerDef     = null;
    inv.containerItems   = {};
    inv.containerWeight  = 0;
    inv.containerOpenedAt = 0;
    inv.stockMode        = false;
    inv.stockShopId      = null;
    inv.stockPrices      = {};

    inv.ignitionOpen      = false;
    inv.ignitionSlot      = null;
    inv.ignitionVehicleId = null;
}

export function openInventoryWithContainer(data) {
    if (inv.open) return;
    inv.open = true;
    if (invHotbarHooks) invHotbarHooks.hideHotbar();

    applyContainerState(data);

    const r = R();
    if (r) {
        // NEARBY IS HIDDEN. Wallets and other item panels still stack; Nearby shows only on foot
        // and not when the inventory came from a boot, a stash or the like — standing at a boot
        // is not standing on the pavement.
        r.setPanels({ ground: false, container: true, ignition: inv.ignitionOpen });
        if (inv.ignitionOpen) r.renderIgnition();
        r.renderAll();
        r.showOverlay();
    }
    invEvents.emit('open', { kind: 'container' });
}

/**
 * Update the CONTAINER panel (and the ignition slot with it) without closing the inventory.
 * Driven from client/vehicles.lua's state reconcile, not from an entry/exit event — so this
 * is called whenever the player's seated state changes for ANY reason.
 *
 * It touches only its own panel; anything else open stays open.
 */
export function swapSecondaryPanel(data) {
    // The Lua side gates this too (Inventory.isSwappable), but these are cheap and the
    // failure they prevent is a shop or admin panel being replaced by a glovebox.
    //
    // An open wallet is no reason to refuse: panels stack, the setPanels calls below name only
    // `container` and `ignition`, and getting into a car with a wallet open gives you both. Shop and admin
    // player-inspect stay guarded: those are whole modes, not panels.
    if (!inv.open) return;
    if (shop.open || inv.playerInvOpen) return;

    const r = R();
    // A drag whose panel is about to vanish cannot complete meaningfully — and the rebuild
    // below detaches its source node, whose datasets the drag's emit would still read.
    if (r) r.cancelInteractions();

    if (data && data.toGround) {
        clearContainerState();
        if (r) {
            r.setPanels({ ground: true, container: false, ignition: false });
            r.renderAll();
            r.flashPanels(['ground']);
        }
    } else {
        applyContainerState(data);
        if (r) {
            // Ground off: this branch is the player getting INTO a vehicle, so they are no
            // longer on foot. The `toGround` branch above is the mirror — climbing out turns
            // Nearby back on. Between them they are the whole "only on foot" rule for the
            // vehicle case, and they need no new signal to do it.
            r.setPanels({ ground: false, container: true, ignition: inv.ignitionOpen });
            if (inv.ignitionOpen) r.renderIgnition();
            r.renderAll();
            // `noFlash` is the reconcile case, not a swap: the glovebox opens
            // optimistically and this payload is the open COMPLETING, not a panel moving.
            if (!data.noFlash) r.flashPanels(inv.ignitionOpen ? ['container', 'ignition'] : ['container']);
        }
    }
    invEvents.emit('panel-swap', { toGround: !!(data && data.toGround) });
}

/** Server confirms a container move. */
export function updateContainerInventory(data) {
    if (data.inventory) inv.containerItems = data.inventory;
    if (data.containerWeight !== undefined) inv.containerWeight = data.containerWeight;

    // Deliberately does NOT discard pending ops: this is a PARTIAL reply about one
    // container, and it says nothing about player-side ops still in flight — discarding
    // here would orphan their snapshots (see discardAllPendingOps in core/inv-ops.js).

    const r = R();
    if (!r) return;
    if (r.isMidDrag()) {
        r.refreshSlots();
        r.renderContainerInfo();
        return;
    }
    r.renderContainer();
    r.renderContainerInfo();
    r.tagItemSlots();
}

// ------------------------------------------
// OTHER OPEN PATHS
// ------------------------------------------

export function openInventoryWithPanel(data) {
    if (inv.open) return;
    inv.open = true;
    if (invHotbarHooks) invHotbarHooks.hideHotbar();

    if (data) {
        adoptPlayerHalf(data);
        // Not wiped any more — same reasoning as applyContainerState. Opening straight into a
        // wallet no longer means giving up the Nearby panel.
    }
    if (data && data.panel) openExternalPanel(data.panel);

    const r = R();
    if (r) {
        // NEARBY STAYS ON. Using an item out of your own pockets is not like opening a boot or a
        // stash — you are still standing on the pavement, and the panel stacks beneath Nearby.
        //
        // KNOWN EDGE: a wallet opened while SEATED shows Nearby
        // until the next seated-state change, because swapSecondaryPanel fires on change and
        // there is no change here. Rare — it needs a hotbar or satellite open from a car seat —
        // and the cost is one panel too many, not a wrong one. Fixing it properly means the
        // client telling the NUI whether the player is on foot, which is a signal worth adding
        // when something else needs it too.
        r.setPanels({ ground: true });
        r.renderAll();
        r.showOverlay();
    }
    invEvents.emit('open', { kind: 'panel' });
}

export function openInventoryWithShop(data) {
    if (inv.open) return;
    inv.open = true;
    if (invHotbarHooks) invHotbarHooks.hideHotbar();

    if (data) {
        adoptPlayerHalf(data);
        inv.groundItems = {};   // No ground items when shop is open
    }

    // No container/ignition when shop is open
    inv.containerOpen = false;
    inv.ignitionOpen = false;

    // THE SHOP OPENS FIRST: from here R() can be a different renderer (whip's own, for a custom one
    // that does not draw shops: core/inventory.js getRenderer), so it is asked after.
    if (invShopHooks) invShopHooks.openShop(data);

    const r = R();
    if (r) {
        r.setPanels({ container: false, ignition: false });
        r.renderAll();
        r.showOverlay();
    }
    invEvents.emit('open', { kind: 'shop' });
}

export function openInventoryWithPlayer(data) {
    if (inv.open) return;
    inv.open = true;
    if (invHotbarHooks) invHotbarHooks.hideHotbar();

    if (data) {
        adoptPlayerHalf(data);
        inv.groundItems = {};   // No ground items when player inv is open

        inv.playerInvOpen      = true;
        inv.playerInvCharName  = data.targetCharName || 'Player';
        inv.playerInvCharId    = data.targetCharId   || 0;
        inv.playerInvMaxSlots  = data.targetMaxSlots  || { player: 30 };
        inv.playerInvMaxWeight = data.targetMaxWeight || { player: 80 };
        inv.playerInvWeights   = data.targetWeights   || { player: 0 };
        inv.playerInvItems     = normalizeTargetInv(data.targetInv);
    }

    const r = R();
    if (r) {
        r.setPanels({ ground: false, container: false, playerInv: true });
        r.renderAll();
        r.renderPlayerInv();
        r.showOverlay();
    }
    invEvents.emit('open', { kind: 'playerInv' });
}

/** Lua numeric-keyed tables arrive as arrays or sparse maps; normalize to 1-based keys. */
function normalizeTargetInv(targetInv) {
    const out = { player: {} };
    const src = (targetInv && targetInv.player) || {};
    for (const k in src) {
        if (src[k]) out.player[String(k)] = src[k];
    }
    return out;
}

// ------------------------------------------
// AUTHORITATIVE UPDATES
// ------------------------------------------

export function updateInventory(data) {
    // A REPLY IS ONLY AUTHORITATIVE ONCE IT IS THE LAST ONE OUTSTANDING.
    //
    // Right-clicking a stack fires one op per click, and each reply carries the inventory
    // as it looked when the server handled THAT click — several clicks out of date by the
    // time it lands. Replies arrive in order, so each one confirms the OLDEST outstanding
    // op; only when that leaves nothing pending is the payload actually current, and only
    // then is it applied. Everything in between is held (the newest wins, for a moveAck or a
    // revert that empties the queue with no payload of its own), and the optimistic state —
    // which is ahead and correct — stays on screen untouched. (The full history of why
    // lives in core/inv-ops.js's header.)
    //
    // UNLESS THE SERVER SAYS IT IS NOT A REPLY, which is now every push except the few that
    // answer a drag (see SyncInventoryToClient in server/helpers.lua). A give arriving, a
    // satellite's AddItem, a panel fold: counting those confirmed the wrong op. They are applied
    // below when nothing is pending, and held until the queue empties when something is.
    if (!data.unsolicited) confirmOldestOp();

    // An op nobody will answer (the server stalled, the reply was lost) must not hold every push
    // until the NEXT drag's sweep: swept here too, on every update.
    sweepOps();

    if (!hasPendingOps()) {
        takeHeldPush();   // older than this one
        applyPush(data);
    } else {
        // HELD, REPLY OR NOT: each push is newer than the last one held, so when a moveAck or a
        // revert empties the queue it is the newest that gets applied (an older one would snap
        // accepted moves back).
        holdPush(data);
    }

    renderPush();
}

/** Adopt an authoritative push's player half. */
function applyPush(data) {
    if (data.inventory) {
        inv.state = data.inventory;
        if (!inv.state.accessory) inv.state.accessory = {};
    }
    if (data.weights) inv.weights = data.weights;
}

/** The queue just emptied without a payload of its own (a moveAck, a revert): apply whatever
 *  push was held while it was busy. */
function releaseHeldPush() {
    if (hasPendingOps()) return;
    const held = takeHeldPush();
    if (!held) return;
    applyPush(held);
    renderPush();
}

/** The server accepted a drag whose answer is not an inventory push. */
export function ackMove(opId) {
    confirmOp(opId);
    releaseHeldPush();
}

function renderPush() {
    const r = R();
    if (!r) return;
    // The lightweight path is the normal path: the player grids have a FIXED slot count, so
    // refreshing contents in place is both correct and invisible. A rebuild is only needed
    // before the grid exists at all.
    if (inv.open && r.hasPlayerGrid()) {
        r.refreshSlots();
        r.renderWeights();
        if (invHotbarHooks) invHotbarHooks.syncHotbar();
        return;
    }
    r.renderAll();
    if (invHotbarHooks) invHotbarHooks.syncHotbar();
}

/**
 * The server rejected an optimistic change — put the view back.
 * The op engine redraws through the registered view render hooks, so exactly the views the
 * reverted op had touched repaint, and nothing else.
 */
export function revertInventory(err, opId) {
    console.warn('[spur_core:inv-wire] revert:', err, 'op', opId);
    revertOp(opId);
    // A push held while this op was in flight is newer than the snapshot just restored.
    releaseHeldPush();
    invEvents.emit('op-reverted', { error: err, opId });
    const r = R();
    if (r && err) r.notify(err);
}

/**
 * Another viewer changed a store this player has open.
 *
 * The container grid is the shared one — a stash or a car boot, which several people can
 * be inside. Player pockets are included too, not because anyone else can be in them, but
 * because a REFUSED move sends the truth back down this same path, and the slot it
 * corrects may well be one of yours.
 *
 * It deliberately does not renderAll() (that would cancel an in-flight drag) and does not
 * touch the pending-op queue (a foreign change says nothing about whether THIS player's
 * pending ops succeeded).
 */
export function applyStoreDelta(data) {
    if (!data || !data.storeId || !data.slots) return;

    let target = null;
    let isPanel = false;
    // A STACK LOOKUP, NOT A COMPARISON AGAINST "THE" PANEL. panelKeyFor mints the same
    // 'panel:<id>' string the server uses as a store id (Stores.addViewer), so a storeId off
    // the wire can be matched against a panel's key directly — which is exactly why the key
    // uses that grammar rather than an invented one.
    const hitPanel = inv.panels.find(p => p.key === data.storeId);
    if (inv.containerOpen && data.storeId === inv.containerStoreId) {
        target = inv.containerItems;
    } else if (hitPanel) {
        // A shared panel — a crafting bench several people are working out of. Its contents
        // live in ONE table on the server, so what arrives is the same change everyone else
        // sees rather than this client's private copy drifting.
        target = hitPanel.items;
        isPanel = true;
    } else {
        // 'player:<charId>:<container>' — only ever this player's own, since the server
        // sends it only to them, but the charId is checked rather than trusted by omission.
        const m = /^player:(\d+):(\w+)$/.exec(data.storeId);
        if (m && Number(m[1]) === inv.charId && inv.state[m[2]]) {
            target = inv.state[m[2]];
        }
    }
    if (!target) return;

    for (const slot in data.slots) {
        const v = data.slots[slot];
        // `false` means the slot is now empty. A slot that did not change is absent
        // entirely — the server only sends what it touched.
        if (v === false || v === null) {
            delete target[slot];
        } else {
            target[slot] = v;
        }
    }

    if (typeof data.weight === 'number' && target === inv.containerItems) {
        inv.containerWeight = data.weight;
    }

    const r = R();
    if (!r) return;
    if (isPanel) {
        r.renderPanelStack();
    } else {
        r.refreshSlots();
        if (inv.containerOpen) r.renderContainerInfo();
    }
    r.renderWeights();
}

export function refreshGroundItems(groundSlots) {
    // refreshSlots updates slot CONTENTS in place and skips the drag source, so a remote
    // ground change lands without disturbing an in-flight drag.
    inv.groundItems = groundSlots || {};
    const r = R();
    if (!r) return;
    r.renderGround();
    r.refreshSlots();
}

// ------------------------------------------
// IGNITION
// ------------------------------------------

export function updateIgnitionSlot(data) {
    inv.ignitionSlot = data.ignitionSlot || null;
    // Partial reply — pending player-side ops keep their snapshots (see updateContainerInventory).
    const r = R();
    if (r) r.renderIgnition();
}

// ------------------------------------------
// EXTERNAL PANEL (OpenPanel framework)
// ------------------------------------------

/**
 * Open a panel, or re-open one already on screen.
 *
 * APPENDS RATHER THAN REPLACES: a second wallet does not close the first.
 *
 * A REPEAT OF THE SAME ID UPDATES IN PLACE. The server refuses to hand out two sessions for
 * one panel id, so a second openExternalPanel for an id already here is a re-sync (a reconnect,
 * or the server re-sending contents), not a second panel. Pushing a duplicate would put two
 * grids with identical slot keys on screen and every drag would resolve to whichever came
 * first — a genuinely nasty bug, and this is the line that prevents it.
 */
export function openExternalPanel(config) {
    if (!config || !config.id) return;

    const key = panelKeyFor(config.id);
    const items = {};
    // Lua numeric-keyed tables become JSON arrays (0-indexed); convert to 1-based slot keys.
    if (config.items) {
        if (Array.isArray(config.items)) {
            for (let i = 0; i < config.items.length; i++) {
                if (config.items[i]) items[String(i + 1)] = config.items[i];
            }
        } else {
            for (const k in config.items) {
                if (config.items[k]) items[String(k)] = config.items[k];
            }
        }
    }

    // Which items it takes, as a lookup (null = anything). Only for choosing where a shift-click goes:
    // the server decides every move. Lua sends a list of names; an empty list arrives as {} or [].
    let allowed = null;
    if (config.allowedItems && typeof config.allowedItems === 'object') {
        allowed = {};
        for (const k in config.allowedItems) allowed[config.allowedItems[k]] = true;
    }

    const existing = inv.panels.findIndex(p => p.key === key);
    const entry = {
        key,
        id:            config.id,
        label:         config.label || 'Panel',
        slots:         config.slots || 1,
        items,
        maxWeight:     config.maxWeight || null,
        currentWeight: config.currentWeight || 0,
        readOnly:      !!config.readOnly,
        allowed,
        // A re-sync keeps its place in the open order; only a new panel is "newest".
        openedAt:      existing >= 0 ? inv.panels[existing].openedAt : Date.now(),
    };

    if (existing >= 0) inv.panels[existing] = entry;
    else inv.panels.push(entry);

    const r = R();
    // `ground` is deliberately not touched. THE LINE THE OWNER REPORTED was `setPanels({
    // external: true, ground: false })` here — opening a wallet "just removes the nearby
    // panel". It never replaced Nearby by design; it replaced it because the column was
    // written as though it held one thing.
    if (r) r.renderPanelStack();
    invEvents.emit('external-open', { id: config.id });
}

/**
 * Close one panel, or every panel when called with no id.
 *
 * THE NO-ID FORM IS THE LEGACY SHAPE and it still has a caller: the server's own close event
 * carried no id while there could only be one session. Keep it meaning "all of them" rather
 * than "the first one" — closing an arbitrary panel is the kind of bug that looks like a
 * dropped message.
 */
export function closeExternalPanel(id) {
    const before = inv.panels.length;
    if (id === undefined || id === null) {
        inv.panels = [];
    } else {
        inv.panels = inv.panels.filter(p => p.key !== panelKeyFor(id));
    }
    if (inv.panels.length === before) return;

    // Only a full teardown invalidates every in-flight guess. Closing ONE panel of several
    // leaves the other panels' and the player-side ops perfectly valid, and discarding them
    // would strand their snapshots — the exact habit inv-ops' header warns about.
    if (inv.panels.length === 0) discardAllPendingOps();

    const r = R();
    if (r) r.renderPanelStack();
    invEvents.emit('external-close', { id: id === undefined ? null : id });
}

/** A single slot changed inside one panel. `panelId` may be absent on legacy payloads, in
 *  which case there is nothing to disambiguate unless several panels are open — and then
 *  guessing is worse than ignoring it. */
export function updateExternalPanelSlot(slot, slotData, panelId) {
    const panel = panelId !== undefined && panelId !== null
        ? panelById(panelId)
        : (inv.panels.length === 1 ? inv.panels[0] : null);
    if (!panel) return;

    // Partial reply — pending player-side ops keep their snapshots (see updateContainerInventory).
    if (slotData) {
        panel.items[String(slot)] = slotData;
    } else {
        delete panel.items[String(slot)];
    }
    const r = R();
    if (r) r.renderPanelStack();
}

export function updatePanelWeight(data) {
    const panel = data.panelId !== undefined && data.panelId !== null
        ? panelById(data.panelId)
        : (inv.panels.length === 1 ? inv.panels[0] : null);
    if (!panel) return;
    panel.maxWeight     = data.maxWeight || null;
    panel.currentWeight = data.currentWeight || 0;
    const r = R();
    if (r) r.renderPanelStack();
}

export function setPanelReadOnly(data) {
    const panel = data.panelId !== undefined && data.panelId !== null
        ? panelById(data.panelId)
        : (inv.panels.length === 1 ? inv.panels[0] : null);
    if (!panel) return;
    panel.readOnly = !!data.readOnly;
    const r = R();
    if (r) r.renderPanelStack();
}

// ------------------------------------------
// ADMIN PLAYER-INVENTORY VIEW
// ------------------------------------------

export function updatePlayerInv(data) {
    if (!inv.playerInvOpen) return;
    if (data.targetInv) inv.playerInvItems = normalizeTargetInv(data.targetInv);
    if (data.targetWeights) inv.playerInvWeights = data.targetWeights;
    if (data.inventory) {
        inv.state = data.inventory;
        if (!inv.state.accessory) inv.state.accessory = {};
    }
    if (data.weights) inv.weights = data.weights;

    // Partial reply — pending player-side ops keep their snapshots (see updateContainerInventory).

    const r = R();
    if (!r) return;
    if (r.isMidDrag()) {
        r.refreshSlots();
        r.renderPlayerInvInfo();
        r.renderWeights();
        return;
    }
    r.renderAll();
    r.renderPlayerInv();
}

export function closePlayerInventory() {
    if (!inv.playerInvOpen) return;
    inv.playerInvOpen = false;
    inv.playerInvItems = { player: {} };
    inv.playerInvCharName = '';
    inv.playerInvCharId = 0;
    inv.playerInvWeights = { player: 0 };
    inv.playerInvMaxSlots = { player: 30 };
    inv.playerInvMaxWeight = { player: 80 };
    discardAllPendingOps();

    const r = R();
    if (r) r.setPanels({ playerInv: false, ground: true });

    // Close the full overlay — Lua CloseInventory() handles server cleanup via ActivePlayerInv.
    if (inv.open) closeInventory();
}

// ------------------------------------------
// ROUTER REGISTRATION — the inventory system's whole inbound protocol
// ------------------------------------------

NuiRouter.register('openInventory', (d) => openInventory(d.data));
NuiRouter.register('closeInventory', () => closeInventory({ echo: false }));   // Lua already closed
NuiRouter.register('inventoryUpdate', (d) => updateInventory(d.data));
NuiRouter.register('inventoryRevert', (d) => revertInventory(d.error, d.opId));
NuiRouter.register('moveAck', (d) => ackMove(d.opId));
NuiRouter.register('inventoryFlagsSync', (d) => inventoryFlagsSync(d));
NuiRouter.register('groundItemsRefresh', (d) => refreshGroundItems(d.data));
NuiRouter.register('openInventoryWithContainer', (d) => openInventoryWithContainer(d.data));
NuiRouter.register('swapSecondaryPanel', (d) => swapSecondaryPanel(d.data));
NuiRouter.register('containerUpdate', (d) => updateContainerInventory(d.data));
NuiRouter.register('storeDelta', (d) => applyStoreDelta(d.data));
NuiRouter.register('openInventoryWithPlayer', (d) => openInventoryWithPlayer(d.data));
NuiRouter.register('playerInvUpdate', (d) => updatePlayerInv(d.data));
NuiRouter.register('closePlayerInventory', () => closePlayerInventory());
NuiRouter.register('updateIgnitionSlot', (d) => updateIgnitionSlot(d.data));
NuiRouter.register('openExternalPanel', (d) => openExternalPanel(d.data));
NuiRouter.register('openInventoryWithPanel', (d) => openInventoryWithPanel(d.data));
// `d.data && d.data.id` — the close message carries a panel id so one wallet can be closed while
// another stays open. Absent means "all of them"; see closeExternalPanel.
NuiRouter.register('closeExternalPanel', (d) => closeExternalPanel(d && d.data && d.data.id));
NuiRouter.register('updateExternalPanelSlot', (d) => updateExternalPanelSlot(d.slot, d.slotData, d.panelId));
NuiRouter.register('panelWeightInfo', (d) => updatePanelWeight(d.data));
NuiRouter.register('panelReadOnly', (d) => setPanelReadOnly(d.data));
NuiRouter.register('openInventoryWithShop', (d) => openInventoryWithShop(d.data));
NuiRouter.register('registerInvSlotDefs', (d) => registerInvSlotDefs(d));
