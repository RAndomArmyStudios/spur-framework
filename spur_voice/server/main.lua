--[[
    spur_voice — THE SERVER: the voice system spur_core knows, and who is in voice

    RedM (spur_voice, 24 Nov 2026): whip_voice ran a LiveKit voice server and signed each player into it. RedM's own
    Mumble voice needs none of that: this side registers with spur_core as the voice system, sets RedM's voice settings
    for every player (Config.Convars), and keeps who is in voice for IsVoiceReady.
]]

Voice = {
    inVoice = {},   -- [src] = true: their game is in its voice channel (client/main.lua says)
}

function Voice.debug(fmt, ...)
    if Config.Debug then print(('[spur_voice] ' .. fmt):format(...)) end
end

-- RedM's voice settings, for every player (replicated). One server.cfg sets already is left alone.
do
    local set = {}
    for name, value in pairs(type(Config.Convars) == 'table' and Config.Convars or {}) do
        if GetConvar(name, '') == '' then
            SetConvarReplicated(name, tostring(value))
            set[#set + 1] = ('%s %s'):format(name, tostring(value))
        end
    end
    if #set > 0 then
        table.sort(set)
        print('[spur_voice] voice settings for every player: ' .. table.concat(set, ', '))
    end
end

RegisterNetEvent('spur_voice:server:inVoice', function(on)
    local src = source
    Voice.inVoice[src] = on == true or nil
    Voice.debug('%s %s voice', tostring(src), on == true and 'joined' or 'left')
    if on == true and Lines then Lines.push(src) end   -- a game back in voice is told its lines again
end)

AddEventHandler('playerDropped', function()
    Voice.inVoice[source] = nil
end)

-- The voice system, as spur_core asks for it: what this one can do. No speaker, pickup or quality on Mumble, and no
-- sound filters ('basic' is the least spur_core knows).
local function register()
    local ok, why = exports.spur_core:RegisterVoiceSystem({
        label = 'spur_voice (Mumble)',
        features = { lines = true, speaker = false, pickup = false, quality = false, sounds = 'basic' },
    })
    if not ok then
        print(('[spur_voice] not the voice system: %s'):format(tostring(why)))
    end
end

Whip.register(register)
