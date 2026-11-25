-- ============================================
-- Item: duffle_bag (Duffle Bag)
-- 25 slots — accepts anything
-- ============================================
--
-- THIS REPLACES THE BACKPACK, AND THE DIFFERENCE IS THE POINT.
--
-- The backpack was a hardcoded third pocket every character had whether they wanted one or
-- not: its own slot count, its own weight budget, its own panel welded into the inventory UI,
-- and its name spelled out in thirty-one places across the server and client. It could not be
-- dropped, stolen, or found. Everyone simply had one.
--
-- A duffle bag is an item. You find it, carry it, fill it, drop it, and someone else can pick
-- it up with everything still inside — because contents live in the item's own metadata and
-- travel with it. That is the same mechanism a wallet uses to hold cash, and a weapon uses to
-- hold a magazine.
--
-- Want a bigger bag? Register another item with more slots. A locked one? It is a panel item,
-- so give it a canOpen hook. None of that needs spur_core to change.
--
-- NO allowedItems: a duffle takes whatever fits. The wallet whitelists because a wallet full
-- of rifles is silly; a holdall has no such opinion.
--
-- WEIGHT IS NOT DECLARED HERE and must not be. The bag's own 1.5kg is its weight EMPTY —
-- Inventory.effectiveWeight walks the contents and adds them on top, recursively, so a duffle
-- holding a loaded weapon costs the bag, the weapon, its magazine and the rounds in it. That
-- is what stops a bag being a hole you pour weight into.

-- Registered inline — see wallet.lua for why this no longer needs a CreateThread + Wait. spur_core's
-- function, not its export: see food.lua. (A satellite: RegisterPanelItem.)
Panels.registerItem('duffle_bag', {
    slots      = 25,
    label      = 'Duffle Bag',
    storageKey = 'slots',
}, GetCurrentResourceName())
