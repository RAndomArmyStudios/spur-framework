-- ============================================
-- Voice Items — which voice system runs, and what it says it can do
-- ============================================
--
-- RedM (spur_test, 26 Nov 2026): whip_voice's megaphone and radio items, their pictures, the megaphone model and the
-- 3D radio were the original game's or made for it, and spur_voice ships without them, so their tests are gone.
--
-- WHICH ONE RUNS is spur_core's answer (GetVoiceSystem, 13 Oct 2026): spur_voice or spur_voice_simple.

--- The voice resource running, or a skip.
local function voiceRes()
    local v = exports.spur_core:GetVoiceSystem()
    if type(v) ~= 'table' or GetResourceState(v.resource) ~= 'started' then
        skip('needs a voice system running (spur_voice or spur_voice_simple)')
    end
    return v.resource
end

RegisterTestModule({
    order    = 70,
    category = 'Voice Items',
    tests = {
        {
            name = 'One voice system is running, and says what it can do',
            fn = function()
                local res = voiceRes()
                local v = exports.spur_core:GetVoiceSystem()
                assertTrue(res == 'spur_voice' or res == 'spur_voice_simple', 'it is one of whip\'s: ' .. tostring(res))
                assertType(v.features, 'table', 'its features')
                assertTrue(v.features.lines == true, 'it carries voice lines (spur_phone\'s calls)')
                assertTrue(v.features.sounds == 'full' or v.features.sounds == 'basic', 'sounds is full or basic')
            end,
        },
    },
})
