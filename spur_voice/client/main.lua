--[[
    spur_voice — THIS PLAYER'S VOICE, on RedM's own Mumble voice

    RedM (spur_voice, 24 Nov 2026): whip_voice sent each player's microphone to a LiveKit voice server through a NUI page.
    spur_voice uses the Mumble voice built into RedM instead. Each player joins a voice channel of their own (their server
    id) and listens there. What they say goes to one voice target: the channels of the players near them (as far as
    their range, Z), and of everyone on a line with them (the server says who: server/lines.lua). The people on a line
    with them are heard at full volume wherever they are.

    The microphone itself, open mic or push to talk, and its key are the player's own RedM voice settings.
]]

local TARGET = 1            -- our voice target: who hears what we say

local myId = 0              -- our server id, which is also our channel
local joined = false        -- in our own channel, with the target set
local range = Config.Ranges.Normal
local levelName = 'Normal'
local lineTalk = {}         -- [serverId] = true: on a line with us, and we are not muted there (they hear us)
local lineHear = {}         -- [serverId] = true: on a line with us, not muted there (we hear them at full volume)
local overridden = {}       -- [serverId] = true: their volume is ours to put back
local targetKey = nil       -- what the target holds now, so it is built again only when that changes
local targetIds = {}        -- the server ids it holds now, for /voicestatus
local talkingShown = false

-- ============================================================================
-- THE RANGE (Z, on spur_core's HUD)
-- ============================================================================

local function setLevel(name)
    levelName = Config.Ranges[name] and name or 'Normal'
    range = Config.Ranges[levelName] or 8.0
    MumbleSetTalkerProximity(range + 0.0)
    targetKey = nil   -- who is near enough changes with it
end

AddEventHandler('spur_core:voice:rangeChanged', function(e)
    if type(e) == 'table' then setLevel(e.name) end
end)

local function levelFromCore()
    local ok, name = pcall(function() return exports.spur_core:GetVoiceName() end)
    return ok and type(name) == 'string' and name or 'Normal'
end

-- ============================================================================
-- OUR CHANNEL, AND WHO HEARS US
-- ============================================================================

--- Into our own channel (Mumble makes it as we ask), listening there, our target set. Waits; true once in.
local function join()
    myId = GetPlayerServerId(PlayerId())
    joined = false
    local deadline = GetGameTimer() + 15000
    MumbleSetVoiceChannel(myId)
    while MumbleGetVoiceChannelFromServerId(myId) ~= myId and GetGameTimer() < deadline do
        Wait(250)
        MumbleSetVoiceChannel(myId)
    end
    if MumbleGetVoiceChannelFromServerId(myId) ~= myId then return false end
    MumbleAddVoiceChannelListen(myId)
    MumbleClearVoiceTarget(TARGET)
    MumbleSetVoiceTarget(TARGET)
    setLevel(levelName)
    targetKey = nil
    joined = true
    TriggerServerEvent('spur_voice:server:inVoice', true)
    return true
end

local function canTalk()
    if Config.DeadCanTalk then return true end
    return not IsEntityDead(PlayerPedId())
end

--- Who should hear us now: the server ids of the players near enough, and of our lines.
local function wanted()
    local ids, seen = {}, {}
    if not canTalk() then return ids end
    local me = GetEntityCoords(PlayerPedId())
    local reach = range + (Config.Margin or 0)
    for _, ply in ipairs(GetActivePlayers()) do
        if ply ~= PlayerId() then
            local ped = GetPlayerPed(ply)
            if ped ~= 0 and #(GetEntityCoords(ped) - me) <= reach then
                local id = GetPlayerServerId(ply)
                if not seen[id] then seen[id] = true; ids[#ids + 1] = id end
            end
        end
    end
    for id in pairs(lineTalk) do
        if not seen[id] then seen[id] = true; ids[#ids + 1] = id end
    end
    table.sort(ids)
    return ids
end

--- The target holds exactly `ids` (their channels), built again only when they, or the channels, change.
local function aim(ids)
    local parts, channels = {}, {}
    for _, id in ipairs(ids) do
        local ch = MumbleGetVoiceChannelFromServerId(id)
        if ch and ch > 0 then
            channels[#channels + 1] = ch
            parts[#parts + 1] = id .. ':' .. ch
        end
    end
    local key = table.concat(parts, ',')
    if key == targetKey then return end
    targetKey = key
    MumbleClearVoiceTargetChannels(TARGET)
    MumbleAddVoiceTargetChannel(TARGET, myId)   -- our own (nobody else is in it): the target is never empty
    for _, ch in ipairs(channels) do MumbleAddVoiceTargetChannel(TARGET, ch) end
    targetIds = ids
end

-- The lines we are on, from the server: who hears us (talk) and whom we hear at full volume (hear).
RegisterNetEvent('spur_voice:client:lines', function(talk, hear)
    local t, h = {}, {}
    for _, id in ipairs(type(talk) == 'table' and talk or {}) do t[tonumber(id)] = true end
    for _, id in ipairs(type(hear) == 'table' and hear or {}) do h[tonumber(id)] = true end
    lineTalk, lineHear = t, h
    for id in pairs(overridden) do
        if not h[id] then MumbleSetVolumeOverrideByServerId(id, -1.0); overridden[id] = nil end
    end
    for id in pairs(h) do
        MumbleSetVolumeOverrideByServerId(id, (Config.LineVolume or 1.0) + 0.0)
        overridden[id] = true
    end
    targetKey = nil
end)

-- ============================================================================
-- THE LOOPS
-- ============================================================================

CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(500) end
    levelName = levelFromCore()
    while true do
        if not MumbleIsConnected() then
            if joined then
                joined = false
                targetKey = nil
                TriggerServerEvent('spur_voice:server:inVoice', false)
            end
            Wait(1000)
        elseif not joined then
            if not join() then Wait(2000) end
        else
            aim(wanted())
            Wait(Config.RefreshMs or 250)
        end
    end
end)

-- The HUD mic: blue while we talk.
CreateThread(function()
    while true do
        local talking = joined and MumbleIsPlayerTalking(PlayerId())   -- (RDR2 has no NETWORK_IS_PLAYER_TALKING)
        talking = talking == true or talking == 1
        if talking ~= talkingShown then
            talkingShown = talking
            pcall(function() exports.spur_core:SetVoiceTalking(talking) end)
        end
        Wait(100)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(overridden) do MumbleSetVolumeOverrideByServerId(id, -1.0) end
    MumbleClearVoiceTargetChannels(TARGET)
end)

-- ============================================================================
-- FOR spur_core: a lore character's voice is heard here?
-- ============================================================================
-- whip_voice played lore characters' lines through its voice bot. Mumble has no voice bot, so none is ever heard here:
-- spur_core shows a line's subtitle at once (client/bubbles.lua).

exports('HearsEntity', function() return false, false end)

-- ============================================================================
-- /voicestatus
-- ============================================================================

local function devAllowed()
    local ok, on = pcall(function() return Whip.core:HasDevTools() end)
    if ok and on == true then return true end
    print('[spur_voice] /voicestatus needs developer mode on (/w)')
    return false
end

local function yes(v) return tostring(v == true or v == 1) end

RegisterCommand('voicestatus', function()
    if not devAllowed() then return end
    local me = GetPlayerServerId(PlayerId())
    print('=== spur_voice ===')
    print(('Mumble: connected=%s active=%s'):format(yes(MumbleIsConnected()), yes(MumbleIsActive())))
    print(('Channel: ours %s, Mumble has us in %s, joined=%s'):format(tostring(me),
        tostring(MumbleGetVoiceChannelFromServerId(me)), tostring(joined)))
    print(('Range: %s = %.1f m, Mumble proximity %.1f'):format(levelName, range, MumbleGetTalkerProximity() + 0.0))
    print(('Talking: %s (HUD %s)'):format(yes(MumbleIsPlayerTalking(PlayerId())), tostring(talkingShown)))
    for _, name in ipairs({ 'voice_use3dAudio', 'voice_useSendingRangeOnly', 'voice_useNativeAudio', 'voice_use2dAudio',
                            'profile_voiceEnable', 'profile_voiceTalkEnabled' }) do
        print(('Convar %s = %s'):format(name, GetConvar(name, '(unset)')))
    end
    local ids = {}
    for _, id in ipairs(targetIds) do ids[#ids + 1] = tostring(id) end
    print('Talking to: ' .. (#ids > 0 and table.concat(ids, ', ') or 'nobody near'))
    local lt, lh = {}, {}
    for id in pairs(lineTalk) do lt[#lt + 1] = tostring(id) end
    for id in pairs(lineHear) do lh[#lh + 1] = tostring(id) end
    print(('Lines: they hear us %s; we hear %s'):format(#lt > 0 and table.concat(lt, ', ') or '-',
        #lh > 0 and table.concat(lh, ', ') or '-'))
    for _, ply in ipairs(GetActivePlayers()) do
        if ply ~= PlayerId() then
            local id = GetPlayerServerId(ply)
            print(('  player %d: channel %s, talking %s, %.1f m'):format(id, tostring(MumbleGetVoiceChannelFromServerId(id)),
                yes(MumbleIsPlayerTalking(ply)),
                #(GetEntityCoords(GetPlayerPed(ply)) - GetEntityCoords(PlayerPedId()))))
        end
    end
end, false)
