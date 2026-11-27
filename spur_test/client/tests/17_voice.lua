-- ============================================
-- Client: Voice — spur_voice's megaphone in the player's hand, and the radio's HUD light
-- ============================================
--
-- Runs in the player's own game: it plays the megaphone emote on the player's ped (spur_core's
-- shared/emote_list.lua `megaphone`, which spur_voice's megaphone item plays).
--
-- RedM (spur_test, 23 Nov 2026): the megaphone and its model come from spur_core's emote list (loaded by
-- fxmanifest.lua), not the original game's prop_megaphone_01. RDR2's list has no megaphone yet, so the test is skipped, with
-- the reason, until one is added.

local function megaphoneEmote()
    for _, e in ipairs(EmoteList and EmoteList.emotes or {}) do
        if e.cmd == 'megaphone' then return e end
    end
    return nil
end

local MEGAPHONE_DEF = megaphoneEmote()
local MEGAPHONE = MEGAPHONE_DEF and MEGAPHONE_DEF.props and MEGAPHONE_DEF.props[1]
    and GetHashKey(MEGAPHONE_DEF.props[1].model) or nil

--- The megaphone in the player's hand, or nil.
local function heldMegaphone()
    for _, obj in ipairs(GetGamePool('CObject')) do
        if GetEntityModel(obj) == MEGAPHONE and IsEntityAttachedToEntity(obj, PlayerPedId()) then return obj end
    end
    return nil
end

RegisterClientTestModule({
    order    = 17,
    category = 'Client: Voice',
    teardown = function()
        pcall(exports.spur_core.CancelEmote, exports.spur_core)
        pcall(exports.spur_core.SetVoiceTalking, exports.spur_core, false)
    end,
    tests = {
        {
            name = 'The megaphone emote holds a networked megaphone up, and goes away cleanly',
            fn = function()
                if not MEGAPHONE then
                    skip("RedM: spur_core's emote list has no megaphone emote with a prop yet (shared/emote_list.lua)")
                end
                assertNil(heldMegaphone(), 'no megaphone before')
                local ok, why = exports.spur_core:PlayEmote('megaphone')
                assertTrue(ok, ('PlayEmote answered true (why: %s)'):format(tostring(why)))
                assertEqual(exports.spur_core:IsEmoting(), 'megaphone', 'IsEmoting names it (spur_voice watches this)')
                assertTrue(waitFor(function() return heldMegaphone() ~= nil end, 3000), 'the megaphone is in hand')
                assertTrue(waitFor(function()
                    local m = heldMegaphone()
                    return m ~= nil and NetworkGetEntityIsNetworked(m) and true or false
                end, 2000), 'networked, so others see it')
                assertTrue(exports.spur_core:CancelEmote(), 'CancelEmote answered true')
                assertTrue(waitFor(function() return heldMegaphone() == nil end, 1500), 'the megaphone is gone')
                assertEqual(exports.spur_core:IsEmoting(), false, 'IsEmoting is false')
            end,
        },
        {
            name = 'The voice gauge takes the radio mode (and back)',
            fn = function()
                -- The look is checked by eye; this checks the export takes the mode and does not throw.
                assertTrue(pcall(exports.spur_core.SetVoiceTalking, exports.spur_core, true, 'radio'), 'radio mode taken')
                assertTrue(pcall(exports.spur_core.SetVoiceTalking, exports.spur_core, true), 'back to normal talking')
                assertTrue(pcall(exports.spur_core.SetVoiceTalking, exports.spur_core, false), 'off')
            end,
        },
    },
})
