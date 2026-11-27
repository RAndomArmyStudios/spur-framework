-- ============================================
-- Client: Emotes — /e, what ends an emote, walks and moods
-- ============================================
--
-- Runs in the player's own game: it plays real emotes on the player's ped.
--
-- RedM (spur_test, 23 Nov 2026): reworked for RDR2. whip_test played the original game's 'drink' (a clip
-- and a bottle the server put in the hand); on RedM every emote in spur_core/shared/emote_list.lua is
-- an RDR2 SCENARIO, which brings its own props, loop and exit, and spur_core makes no props for it. So these
-- tests watch the scenario, read from that same list (loaded by fxmanifest.lua), and the spam test checks the
-- ped is left holding nothing new. The walk and mood tests use the list's first walk and mood, and are skipped,
-- with the reason, while the list has none (RDR2 walks and faces are not original-game clipsets; spur_core's CONVERSION.md).

local function emote(cmd)
    for _, e in ipairs(EmoteList and EmoteList.emotes or {}) do
        if e.cmd == cmd then return e end
    end
    return nil
end

--- The scenario /e drink plays (WORLD_HUMAN_DRINKING).
local DRINK = (emote('drink') or {}).scenario
--- Another scenario, for the progress bar: so "the bar's own animation" can't be the emote's.
local BAR_SCENARIO = (emote('coffee') or {}).scenario or 'WORLD_HUMAN_COFFEE_DRINK'

--- Is the player's ped in this scenario? IsPedUsingScenario takes the name here as in spur_core
--- (shared/rdr_compat.lua maps it to RDR2's hash). Truthy, not `== true`: it can answer 1.
local function using(scenario)
    return scenario ~= nil and IsPedUsingScenario(PlayerPedId(), scenario) and true or false
end

local function drinking() return using(DRINK) end

--- Objects attached to the player's ped: what a scenario put in the hand, or a prop left behind on it.
local function attachedCount()
    local n, ped = 0, PlayerPedId()
    for _, obj in ipairs(GetGamePool('CObject')) do
        if IsEntityAttachedToEntity(obj, ped) then n = n + 1 end
    end
    return n
end

local function meta()
    local data = exports.spur_core:GetPlayer()
    return data and data.metadata or {}
end

local function needDrink()
    if not DRINK then skip("spur_core's emote list has no 'drink' emote") end
end

RegisterClientTestModule({
    order    = 16,
    category = 'Client: Emotes',
    teardown = function()
        pcall(exports.spur_core.CancelEmote, exports.spur_core)
        ExecuteCommand('walk c')
        ExecuteCommand('mood c')
    end,
    tests = {
        {
            name = 'PlayEmote drink: the scenario plays, and IsEmoting names it',
            fn = function()
                needDrink()
                assertFalse(drinking(), 'not drinking before')
                local ok, why = exports.spur_core:PlayEmote('drink')
                assertTrue(ok, ('PlayEmote answered true (why: %s)'):format(tostring(why)))
                assertTrue(waitFor(drinking, 4000), 'the ped is in the drink scenario (' .. DRINK .. ')')
                assertEqual(exports.spur_core:IsEmoting(), 'drink', 'IsEmoting names it')
            end,
        },
        {
            name = 'CancelEmote: the scenario stops',
            fn = function()
                needDrink()
                exports.spur_core:PlayEmote('drink')
                assertTrue(waitFor(drinking, 4000), 'set up: drinking')
                assertTrue(exports.spur_core:CancelEmote(), 'CancelEmote answered true')
                -- RedM: an RDR2 scenario walks out of itself first (spur_core cuts it after 6 s at the latest).
                assertTrue(waitFor(function() return not drinking() end, 8000), 'the scenario stopped')
                assertEqual(exports.spur_core:IsEmoting(), false, 'IsEmoting is false')
            end,
        },
        {
            name = 'An unknown emote is refused with a reason',
            fn = function()
                local ok, why = exports.spur_core:PlayEmote('no_such_emote_here')
                assertFalse(ok, 'refused')
                assertType(why, 'string', 'with a reason')
            end,
        },
        {
            name = 'A progress bar ends the emote and plays its own scenario',
            fn = function()
                needDrink()
                exports.spur_core:PlayEmote('drink')
                assertTrue(waitFor(drinking, 4000), 'set up: drinking')

                local res
                CreateThread(function()
                    res = table.pack(exports.spur_core:Progress({
                        label = '[TEST] emote vs bar', duration = 2500,
                        anim  = { scenario = BAR_SCENARIO },
                        disable = { move = false },
                    }))
                end)
                local okDuring, errDuring = pcall(function()
                    assertTrue(waitFor(function() return exports.spur_core:IsEmoting() == false end, 1000),
                        'the emote ended when the bar began')
                    assertTrue(waitFor(function() return using(BAR_SCENARIO) end, 2500),
                        "the bar's own scenario plays (" .. BAR_SCENARIO .. ')')
                    assertFalse(drinking(), "the emote's scenario is gone")
                    local ok = exports.spur_core:PlayEmote('drink')
                    assertFalse(ok, 'no emote while a bar runs')
                end)
                if not okDuring then
                    exports.spur_core:CancelProgress()
                    waitFor(function() return res ~= nil end, 4000)
                    error(errDuring, 0)
                end
                assertTrue(waitFor(function() return res ~= nil end, 5000), 'the bar answered')
                assertTrue(res[1], ('the bar completed (why: %s)'):format(tostring(res[2])))
            end,
        },
        {
            -- whip's spam once piled props up in the hand, for everyone (26 Sep). On RDR2 a scenario makes its own
            -- props; this checks that a burst of emotes and one /e c leave the ped holding nothing new and in no
            -- scenario.
            name = 'Spamming emotes ends clean: no scenario left, nothing left in hand',
            fn = function()
                needDrink()
                local other = emote('smoke') and 'smoke' or 'coffee'
                local before = attachedCount()
                for i = 1, 16 do
                    exports.spur_core:PlayEmote(i % 2 == 0 and 'drink' or other)
                    Wait(75)
                end
                Wait(1500)   -- the last one's scenario starts, so stopping it is real
                exports.spur_core:CancelEmote()
                assertEqual(exports.spur_core:IsEmoting(), false, 'IsEmoting is false')
                assertTrue(waitFor(function() return not IsPedUsingAnyScenario(PlayerPedId()) end, 4000),
                    'the ped is in no scenario after /e c')
                assertTrue(waitFor(function() return attachedCount() <= before end, 4000),
                    ('nothing new is left in hand (%d attached, %d before)'):format(attachedCount(), before))
            end,
        },
        {
            name = '/walk saves the walk on the character; /walk c clears it',
            fn = function()
                local walk = EmoteList and EmoteList.walks and EmoteList.walks[1]
                if not walk then skip("RedM: spur_core's walk list is empty (shared/emote_list.lua)") end
                ExecuteCommand('walk ' .. walk.cmd)
                assertTrue(waitFor(function() return meta().walk == walk.cmd end, 3000), 'metadata.walk = ' .. walk.cmd)
                ExecuteCommand('walk c')
                assertTrue(waitFor(function() return meta().walk == nil end, 3000), 'metadata.walk cleared')
            end,
        },
        {
            name = "/mood puts the face on the player's statebag (for everyone); /mood c takes it off",
            fn = function()
                local mood = EmoteList and EmoteList.moods and EmoteList.moods[1]
                if not mood then skip("RedM: spur_core's mood list is empty (shared/emote_list.lua)") end
                ExecuteCommand('mood ' .. mood.cmd)
                assertTrue(waitFor(function() return LocalPlayer.state.whipMood == mood.cmd end, 3000), 'bag whipMood = ' .. mood.cmd)
                assertTrue(waitFor(function() return meta().mood == mood.cmd end, 3000), 'metadata.mood = ' .. mood.cmd)
                ExecuteCommand('mood c')
                assertTrue(waitFor(function() return LocalPlayer.state.whipMood == nil end, 3000), 'bag cleared')
            end,
        },
    },
})
