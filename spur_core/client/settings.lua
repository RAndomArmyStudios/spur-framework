-- ============================================
-- Settings — the client half
-- ============================================
--
-- This game read settings.json at load (shared/settings.lua), as the file stood when spur_core
-- started. Two things can be newer: a change an admin makes while we play, and anything changed
-- before we joined (or put in force at spur_core's start from the database). Both arrive as
-- spur_core:client:settingsChanged and go through Settings.apply, which sets the value in place
-- and runs the hooks the owning files registered (Settings.onChange).

RegisterNetEvent('spur_core:client:settingsChanged', function(list)
    if type(list) ~= 'table' then return end
    for _, c in ipairs(list) do
        if type(c) == 'table' and type(c.path) == 'string' then
            local owner = type(c.owner) == 'string' and c.owner or Settings.CORE
            Settings.apply(owner, c.path, Settings.decode(c.value))
        end
    end
end)

-- Ask what is newer than our file: now, as this game starts, and again when spur_core says it is
-- ready. The server answers only once it is ready (server/settings.lua), so during a restart the
-- first hello goes unanswered and the second one brings the values the boot put in force.
TriggerServerEvent('spur_core:server:settingsHello')
RegisterNetEvent('spur_core:client:coreReady', function()
    TriggerServerEvent('spur_core:server:settingsHello')
end)
