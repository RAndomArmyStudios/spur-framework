-- ============================================
-- /whip SECTION — Jobs (client wiring)
-- ============================================
--
-- Replaces tools/jobs.lua. The section lifecycle speaks the SAME server events the
-- standalone tool did (jmGetAll / jmClosed) — the server never noticed the
-- consolidation. Mutation callbacks moved verbatim. The two destructive flows
-- (delete job, fire) confirmed IN-WORLD for a while — first the hand-rolled
-- jmSuspend/jmResume dance, then WhipPanelConfirmFlow — but the panel's own
-- WP.confirm dialog asks the same question without hiding the panel, so the JS side
-- confirms now and these callbacks just forward. jmClose and the suspend messages
-- stay dead — the shell owns close, focus, and the suspend seam.

PanelSections['jobs'] = {
    enter = function()
        TriggerServerEvent('spur_core:server:jmGetAll')
    end,
    leave = function()
        TriggerServerEvent('spur_core:server:jmClosed')
    end,
}

RegisterNetEvent('spur_core:client:jmAllJobs', function(data)
    WhipPanelData('jobs', 'all', data)
end)

RegisterNetEvent('spur_core:client:jmRefresh', function(data)
    WhipPanelData('jobs', 'refresh', data)
end)

-- ---- mutations (moved verbatim from tools/jobs.lua) ----

RegisterNUICallback('jmCreateJob', function(data, cb)
    TriggerServerEvent('spur_core:server:jmCreateJob', data)
    cb('ok')
end)

RegisterNUICallback('jmUpdateJob', function(data, cb)
    TriggerServerEvent('spur_core:server:jmUpdateJob', data.jobId, data)
    cb('ok')
end)

-- The confirm already happened in-panel (WP.confirm, jobs.js) — this is the answer.
RegisterNUICallback('jmDeleteJob', function(data, cb)
    TriggerServerEvent('spur_core:server:jmDeleteJob', data.jobId)
    cb('ok')
end)

RegisterNUICallback('jmCreateRole', function(data, cb)
    TriggerServerEvent('spur_core:server:jmCreateRole', data)
    cb('ok')
end)

RegisterNUICallback('jmUpdateRole', function(data, cb)
    TriggerServerEvent('spur_core:server:jmUpdateRole', data.roleId, data)
    cb('ok')
end)

RegisterNUICallback('jmDeleteRole', function(data, cb)
    TriggerServerEvent('spur_core:server:jmDeleteRole', data.roleId)
    cb('ok')
end)

RegisterNUICallback('jmHire', function(data, cb)
    TriggerServerEvent('spur_core:server:jmHire', data)
    cb('ok')
end)

-- Confirmed in-panel too (WP.confirm, jobs.js) — forward straight through.
RegisterNUICallback('jmFire', function(data, cb)
    TriggerServerEvent('spur_core:server:jmFire', data.jobId, data.charId)
    cb('ok')
end)

RegisterNUICallback('jmSetRole', function(data, cb)
    TriggerServerEvent('spur_core:server:jmSetRole', data.jobId, data.charId, data.roleId)
    cb('ok')
end)

-- ---- the job wizard (html/js/wp/jobs.js): Create and Save answer it, { ok, why, problems } ----

local function ask(name, ...)
    local res, why = Callback(name, ...)
    if type(res) ~= 'table' then res = { ok = false, why = why or 'The server did not answer' } end
    return res
end

RegisterNUICallback('jmWizardCreate', function(data, cb)
    cb(ask('spur_core:jmWizardCreate', data))
end)

RegisterNUICallback('jmWizardSave', function(data, cb)
    cb(ask('spur_core:jmWizardSave', type(data) == 'table' and data.jobId, type(data) == 'table' and data.data))
end)
