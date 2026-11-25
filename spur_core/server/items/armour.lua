-- ============================================
-- Item: armour
-- Equipment — a 5 second bar, then full armour.
-- ============================================
--
-- A timed use, declared: one RegisterUseHandler table (see server/inventory.lua, "A TIMED USE,
-- DECLARED"). The bar is timed by the server, so a modified client cannot skip it mid-firefight; the
-- armour must still be where the use started; it is taken, and only then does onComplete put the
-- armour on.
--
-- spur_core's functions, not its exports: see food.lua. (A satellite: RegisterUseHandler / SetStat.)

local CORE = GetCurrentResourceName()

Inventory.registerUseHandler('armour', {
    label    = 'Equipping armour...',
    duration = 5000,
    reason   = 'put on as armour',
    -- RedM (spur_core, 25 Nov 2026): the player may walk while the bar runs (whip's default holds them still, which with no
    -- animation on RedM read as a freeze). Fighting stays blocked, and the server still times the bar.
    disable  = { move = false },
    -- Stats.set's answer is onComplete's: `false, 'why'` puts the armour back instead of losing it.
    onComplete = function(source)
        return Stats.set(source, 'armour', 100, 'item:armour')
    end,
}, CORE)
