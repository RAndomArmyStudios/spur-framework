-- ============================================
-- Player Flags — what a character has done, kept for good (spur_core/server/player_flags.lua, Director slice 5)
-- ============================================
--
-- On the tester's own character, through the real exports. The two flags set here (test_flag_*) are
-- cleared in teardown.

local NAME, COUNT = 'test_flag_a', 'test_flag_count'

RegisterTestModule({
    order    = 73,
    category = 'Player Flags',
    teardown = function(ctx)
        if ctx.source then
            pcall(exports.spur_core.SetPlayerFlag, exports.spur_core, ctx.source, NAME, nil)
            pcall(exports.spur_core.SetPlayerFlag, exports.spur_core, ctx.source, COUNT, nil)
        end
    end,
    setup = function(source, ctx) ctx.source = source end,
    tests = {
        {
            name = 'Not set, then set, then cleared',
            fn = function(source)
                exports.spur_core:SetPlayerFlag(source, NAME, nil)
                assertNil(exports.spur_core:GetPlayerFlag(source, NAME), 'not set before')
                local ok, why = exports.spur_core:SetPlayerFlag(source, NAME, true)
                assertTrue(ok == true, 'set (' .. tostring(why) .. ')')
                assertTrue(exports.spur_core:GetPlayerFlag(source, NAME) == true, 'read back')
                local all = exports.spur_core:GetPlayerFlags(source)
                assertTrue(type(all) == 'table' and all[NAME] == true, 'in the list of their flags')
                assertTrue(exports.spur_core:SetPlayerFlag(source, NAME, false) == true, 'false clears')
                assertNil(exports.spur_core:GetPlayerFlag(source, NAME), 'gone')
            end,
        },
        {
            name = 'A number, read back as a number; by charId too',
            fn = function(source)
                local p = exports.spur_core:GetPlayer(source)
                assertNotNil(p and p.charId, 'the tester has a character')
                assertTrue(exports.spur_core:SetPlayerFlag({ charId = p.charId }, COUNT, 3) == true, 'set by charId')
                assertEqual(exports.spur_core:GetPlayerFlag(source, COUNT), 3, 'read by server id')
            end,
        },
        {
            name = 'Refused: whip\'s own names, a bad name, a table, long text',
            fn = function(source)
                assertFalse(exports.spur_core:SetPlayerFlag(source, '_once:x', true), 'a name starting with _')
                assertFalse(exports.spur_core:SetPlayerFlag(source, '9lives', true), 'a name starting with a digit')
                assertFalse(exports.spur_core:SetPlayerFlag(source, NAME, {}), 'a table')
                assertFalse(exports.spur_core:SetPlayerFlag(source, NAME, ('x'):rep(101)), 'text over 100 characters')
            end,
        },
        {
            name = 'Saved with the character (its metadata)',
            fn = function(source)
                exports.spur_core:SetPlayerFlag(source, NAME, 'saved')
                local md = exports.spur_core:GetPlayerMetadata(source, 'whipFlags')
                assertTrue(type(md) == 'table' and md[NAME] == 'saved', 'in the character\'s metadata')
            end,
        },
    },
})
