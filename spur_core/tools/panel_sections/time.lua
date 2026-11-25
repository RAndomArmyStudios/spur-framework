-- ============================================
-- /whip SECTION — Time & Weather (client wiring)
-- ============================================
--
-- The reference shape for every section's Lua half: register enter/leave into
-- PanelSections, forward the tool's existing server responses through WhipPanelData
-- (no focus, no open dance — the shell owns those), and carry the tool's mutation
-- NUI callbacks. Every server event named here is UNCHANGED from the standalone tool
-- this section replaced — the server never noticed the consolidation.

PanelSections['time'] = {
    enter = function()
        TriggerServerEvent('spur_core:server:twGetAll')
    end,
    leave = function()
        TriggerServerEvent('spur_core:server:twClosed')
    end,
}

RegisterNetEvent('spur_core:client:twAllData', function(data)
    WhipPanelData('time', 'all', data)
end)

RegisterNetEvent('spur_core:client:twRefresh', function(data)
    WhipPanelData('time', 'refresh', data)
end)

-- ---- mutations (moved verbatim from tools/misc_tools.lua) ----

RegisterNUICallback('twSetTime', function(data, cb)
    TriggerServerEvent('spur_core:server:twSetTime', data.hour or 12, data.minute or 0)
    cb('ok')
end)

RegisterNUICallback('twSetWeather', function(data, cb)
    TriggerServerEvent('spur_core:server:twSetWeather', data.weather or 'CLEAR')
    cb('ok')
end)

RegisterNUICallback('twSetFrozen', function(data, cb)
    TriggerServerEvent('spur_core:server:twSetFrozen', data.frozen and true or false)
    cb('ok')
end)

RegisterNUICallback('twSetBlackout', function(data, cb)
    TriggerServerEvent('spur_core:server:twSetBlackout', data.blackout and true or false)
    cb('ok')
end)

RegisterNUICallback('twSetTimeScale', function(data, cb)
    TriggerServerEvent('spur_core:server:twSetTimeScale', data.scale or 1.0)
    cb('ok')
end)

RegisterNUICallback('twSetPreset', function(data, cb)
    local presets = { dawn = {6,0}, noon = {12,0}, sunset = {19,0}, midnight = {0,0} }
    local p = presets[data.preset]
    if p then
        TriggerServerEvent('spur_core:server:twSetTime', p[1], p[2])
    end
    cb('ok')
end)
