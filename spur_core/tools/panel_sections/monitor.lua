-- ============================================
-- /whip SECTION — Monitor (Event Monitor + Sentinel tab, client wiring)
-- ============================================
--
-- The one section holding TWO server viewer sessions: the secure-event stream (em*,
-- server half in server/secure.lua) and the Sentinel detection stream (sn*, in
-- server/sentinel.lua). Enter opens both, leave closes both — the plmClosed-leak
-- incident is why leave is never optional.
--
-- The forwarders keep their historical NUI action names ('openEventMonitor' for the
-- snapshot, plus the live-stream actions) because html/js/event-monitor.js registers
-- those actions itself — the documented exception to sections receiving everything via
-- wpSectionData: the streams exist whether or not the section is showing, and the
-- module adopts state either way.

PanelSections['monitor'] = {
    enter = function()
        TriggerServerEvent('spur_core:server:emGetAll')
        TriggerServerEvent('spur_core:server:snGetAll')
    end,
    leave = function()
        TriggerServerEvent('spur_core:server:emClosed')
        TriggerServerEvent('spur_core:server:snClosed')
    end,
}

RegisterNetEvent('spur_core:client:emAllData', function(data)
    SendNUIMessage({ action = 'openEventMonitor', data = data })
end)

-- The live feed arrives as a list, four times a second (server/secure.lua). One NUI message for the
-- batch, too.
RegisterNetEvent('spur_core:client:emNewEvents', function(entries)
    if type(entries) ~= 'table' then return end
    SendNUIMessage({ action = 'emNewEvents', data = entries })
end)

RegisterNetEvent('spur_core:client:emCleared', function()
    SendNUIMessage({ action = 'emCleared' })
end)

RegisterNetEvent('spur_core:client:snAllData', function(data)
    SendNUIMessage({ action = 'snAllData', data = data })
end)

RegisterNetEvent('spur_core:client:snNewDetection', function(entry)
    SendNUIMessage({ action = 'snNewDetection', data = entry })
end)

RegisterNetEvent('spur_core:client:snCleared', function()
    SendNUIMessage({ action = 'snCleared' })
end)

RegisterNUICallback('emClearLog', function(_, cb)
    TriggerServerEvent('spur_core:server:emClearLog')
    cb('ok')
end)

RegisterNUICallback('snClearLog', function(_, cb)
    TriggerServerEvent('spur_core:server:snClearLog')
    cb('ok')
end)
