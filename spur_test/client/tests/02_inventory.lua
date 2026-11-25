-- ============================================
-- Client: Inventory
-- ============================================
--
-- THE CLIENT CANNOT GIVE ITSELF AN ITEM, and nothing in spur_test hands it one during the client
-- phase: the runner empties the tester's inventory before the server modules and clears whatever
-- a module leaves behind. So these tests are written to hold for ANY inventory rather than
-- assuming a particular one — each reads the real count first and asserts the answers that count
-- implies. With the usual empty inventory that exercises the "none" half; a tester who happens to
-- be carrying food exercises the other half with the same code.

RegisterClientTestModule({
    order    = 2,
    category = 'Client: Inventory',
    tests = {
        {
            name = 'CloseInventory closes it, and IsInventoryOpen says so',
            fn = function()
                -- Was "returns a boolean", which `invOpen` always is. The runner starts the run
                -- with no UI open, but a server module can leave one up; close it explicitly so
                -- the answer is known rather than assumed.
                exports.spur_core:CloseInventory()
                local closed = waitFor(function() return exports.spur_core:IsInventoryOpen() == false end, 2000)
                assertTrue(closed == true, 'IsInventoryOpen is false once the inventory is closed')
            end,
        },
        {
            name = 'GetItemDef returns known item, and GetItemDefs holds the same one',
            fn = function()
                local def = exports.spur_core:GetItemDef('food')
                assertNotNil(def, 'GetItemDef food')
                assertType(def.name, 'string', 'name type')

                -- Was its own test. Both read Config.Items, so the useful claim is that they agree.
                local all = exports.spur_core:GetItemDefs()
                assertType(all, 'table', 'GetItemDefs')
                assertNotNil(all.food, 'has food')
                assertEqual(all.food.name, def.name, 'both exports describe the same item')

                assertNil(exports.spur_core:GetItemDef('_test_no_such_item'), 'an unknown key has no definition')
            end,
        },
        {
            name = 'A flag registered for an item answers for what is actually held',
            fn = function()
                -- The flag's real value is "is a food in the pockets". Was a type check, which a
                -- flag stuck at false passes as happily as a working one.
                --
                -- NOTE: RegisterItemFlag sets the flag to false and it is only recomputed on the
                -- next inventory sync (client/inventory.lua, RegisterItemFlag / UpdateItemFlags).
                -- A tester carrying food therefore FAILS this until that is fixed — which is the
                -- behaviour a satellite registering a flag mid-session would see.
                exports.spur_core:RegisterItemFlag('_test_flag', 'food')
                local held = exports.spur_core:GetItemCount('food') > 0
                assertEqual(exports.spur_core:HasItemFlag('_test_flag'), held,
                    'the flag is true exactly when food is held')
            end,
        },
        {
            name = 'HasItemFlag returns false for unregistered flag',
            fn = function()
                local result = exports.spur_core:HasItemFlag('_nonexistent_flag_xyz')
                assertFalse(result, 'unregistered flag')
            end,
        },
        {
            name = 'HasItem with a NUMBER means "at least that many"',
            fn = function()
                -- A number in HasItem's second slot is a minimum amount, as on the server
                -- (client/inventory.lua, HasItem). Before that it was called as a filter and threw.
                -- Read the real count, then ask either side of it.
                --
                -- Before the first sync there is no cache and every HasItem answers false — even
                -- "at least zero" — so that state has nothing to say about the minimum rule.
                -- Before the first sync GetInventory answers `{}, 'Player not loaded'` (audit 3 DX-17).
                local _, notYet = exports.spur_core:GetInventory()
                if notYet then
                    skip('no inventory has reached this client yet')
                end
                local n = exports.spur_core:GetItemCount('food')
                assertType(n, 'number', 'GetItemCount type')
                assertTrue(n >= 0, 'a count is never negative')

                assertTrue(exports.spur_core:HasItem('food', n), ('at least %d (exactly what is held)'):format(n))
                assertFalse(exports.spur_core:HasItem('food', n + 1), ('not at least %d (one more than is held)'):format(n + 1))
                assertEqual(exports.spur_core:HasItem('food'), n > 0, 'plain HasItem is "any at all"')
                assertFalse(exports.spur_core:HasItem('_test_no_such_item'), 'an item nobody can hold')
                assertEqual(exports.spur_core:GetItemCount('_test_no_such_item'), 0, 'and it counts zero')
            end,
        },
        {
            name = 'HasItem with a FUNCTION filters on metadata across the export boundary',
            fn = function()
                -- A filter from another resource arrives as a callable reference, not a 'function';
                -- HasItem calls it rather than type-testing it. A filter that refuses everything
                -- must answer false whatever is held; one that accepts everything must agree with
                -- the plain count.
                local n = exports.spur_core:GetItemCount('food')
                assertFalse(exports.spur_core:HasItem('food', function() return false end),
                    'a filter refusing every stack finds nothing')
                assertEqual(exports.spur_core:HasItem('food', function() return true end), n > 0,
                    'a filter accepting every stack finds exactly what GetItemCount counts')
                assertEqual(exports.spur_core:GetItemCount('food', function() return false end), 0,
                    'GetItemCount honours the filter too')
            end,
        },
        {
            -- INV-20 (09-24): a number where the filter goes was called as the filter and threw.
            -- Counting has no minimum, so it is ignored; HasItem is the "at least N" question.
            name = 'GetItemCount ignores a number where a filter goes',
            fn = function()
                local plain = exports.spur_core:GetItemCount('food')
                local ok, withNumber = pcall(function() return exports.spur_core:GetItemCount('food', 5) end)
                assertTrue(ok, 'it answered rather than threw')
                assertEqual(withNumber, plain, 'and the answer is the plain count')
            end,
        },
        {
            -- INV-10 (09-24): flags are owned and answered, and a filter that throws is a "no" for
            -- that item rather than an error inside whip's own inventory update.
            name = 'RegisterItemFlag answers, and a throwing filter is a "no" rather than an error',
            fn = function()
                local bad, badErr = exports.spur_core:RegisterItemFlag(12345)
                assertFalse(bad, 'a flag name that is not a string is refused')
                assertNotNil(badErr, 'with a reason')

                local ok = exports.spur_core:RegisterItemFlag('_test_flag_throw', 'food', function()
                    error('[EXPECTED] spur_test client 02 is deliberately throwing in an item-flag filter')
                end)
                assertTrue(ok, 'the flag registered')
                assertFalse(exports.spur_core:HasItemFlag('_test_flag_throw'), 'a filter that throws matches nothing')

                -- And the inventory still answers — the throw did not take anything down with it.
                assertType(exports.spur_core:GetItemCount('food'), 'number', 'inventory reads still work')
            end,
        },
    }
})
