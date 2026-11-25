-- ============================================
-- The voice system — which resource carries the players' voices
-- ============================================
--
-- whip's is whip_voice (its own voice server, voices in 3D through rooms and doorways, sound recipes); an
-- owner may write another. A server runs ONE. It registers here (RegisterVoiceSystem), and everything that
-- uses voice asks here which it is, never a resource by name: whip_phone's calls work on whichever runs
-- (lib/satellite.lua, Whip.voice).
--
-- ONE AT A TIME. The first to register holds it; a second is refused with the first one's name and
-- stands down. It is let go when its resource stops (the Registry's sweep). Every client is told on
-- each change and when a character loads (client/voice_system.lua).
--
-- FEATURES say what this voice system can do, so a resource offers only what works. All booleans but
-- `sounds`:
--   lines    voice lines: OpenLine and the rest (calls, radio frequencies)
--   speaker  SetLineSpeaker: a member's device plays the line out loud to the people near it
--   pickup   ...and on speaker, the people near the device are heard on the line too
--   quality  a line's `quality`: worse with distance, gone past its range
--   sounds   'full' (every sound block as written) or 'basic' (a phone or radio filter at most)

-- Global for the setup report (server/setup_report.lua), which names the voice system.
VoiceSystem = {}

local FEATURES = { 'lines', 'speaker', 'pickup', 'quality' }
local SOUNDS = { full = true, basic = true }

local current = nil   -- { resource, label, features } while one is registered

--- A copy for the wire and for callers: false when there is none.
local function view(v)
    if not v then return false end
    local f = {}
    for k, x in pairs(v.features) do f[k] = x end
    return { resource = v.resource, label = v.label, features = f }
end

local reg = Registry.new('voiceSystem', {
    label = 'voice system',
    onAdd = function(_, value)
        current = value
        TriggerClientEvent('spur_core:client:voiceSystem', -1, view(current))
    end,
    onRemove = function(_, value)
        if current == value then current = nil end
        TriggerClientEvent('spur_core:client:voiceSystem', -1, view(current))
    end,
})

--- Register the caller as the voice system. Answers true, or false and why (another one already is).
---@param owner string  Registry.caller()
---@param info table    { label, features }
function VoiceSystem.register(owner, info)
    if type(info) ~= 'table' then return false, 'RegisterVoiceSystem takes { label = ..., features = { ... } }' end
    local label = rawget(info, 'label')
    label = type(label) == 'string' and label ~= '' and label:sub(1, 60) or owner
    local given = rawget(info, 'features')
    given = type(given) == 'table' and given or {}
    local f = {}
    for _, k in ipairs(FEATURES) do f[k] = rawget(given, k) == true end
    local s = rawget(given, 'sounds')
    f.sounds = SOUNDS[s] and s or 'basic'

    if current and current.resource ~= owner and Registry.alive(current.resource) then
        return false, ('%s is already the voice system: run one voice resource, not both'):format(current.resource)
    end
    return reg:add(owner, 'voice', { resource = owner, label = label, features = f })
end

--- The voice system running now: { resource, label, features }, or false when there is none.
function VoiceSystem.get()
    if current and not Registry.alive(current.resource) then return false end
    return view(current)
end

-- A character coming on: which voice system there is (or none).
Character.onLife('loaded', function(e)
    if e and e.source then TriggerClientEvent('spur_core:client:voiceSystem', e.source, VoiceSystem.get()) end
end)

exports('RegisterVoiceSystem', function(info) return VoiceSystem.register(Registry.caller(), info) end)
exports('GetVoiceSystem', function() return VoiceSystem.get() end)
