-- ============================================
-- /whip SECTION — UI Library (client wiring)
-- ============================================
--
-- Replaces the standalone UI Library Tester: the uit-* blocks in tools/misc_tools.lua
-- plus html/js/ui-tester.js and its overlay/stylesheet. Every demo here borrows the
-- ACTUAL game screen — a progress bar, a skill check, the radial wheel — and the whole
-- UI layer stack renders below the panel overlay, so each demo runs the suspend
-- pattern: WhipPanelSuspend() hides the panel and yields focus, the demo plays where
-- it can be seen, then WhipPanelResume() brings the panel back and WhipPanelData
-- carries the result to the section's result line. The old per-demo
-- SetNuiFocus/closeUITester/openUITester dance this replaces is exactly what the
-- suspend seam was generalized for.
--
-- Server side untouched: uitGetAccess still gates entry, but its granted response now
-- only confirms access — the shell already owns focus and the open.

PanelSections['uitester'] = {
    enter = function()
        TriggerServerEvent('spur_core:server:uitGetAccess')
    end,
    leave = function()
        -- No viewer session and no closed event existed for this tool — nothing to say.
    end,
}

RegisterNetEvent('spur_core:client:uitAccessGranted', function()
    WhipPanelData('uitester', 'ready', {})
end)

-- ============================================
-- Demos (moved from tools/misc_tools.lua)
-- ============================================

-- Even the fire-and-forget toast suspends: toasts render at z 900, under the panel
-- overlay, so without hiding the panel the demo would play to a dimmed wall. The wait
-- is the toast's default life (client/ui.lua).
RegisterNUICallback('uitTestNotify', function(data, cb)
    WhipPanelSuspend()
    CreateThread(function()
        UI.Notify(data.text or 'Test notification', data.type or 'info')
        Wait(3000)
        WhipPanelResume()
        WhipPanelData('uitester', 'result', { demo = 'notify', result = data.type or 'info' })
    end)
    cb('ok')
end)

RegisterNUICallback('uitTestProgress', function(data, cb)
    WhipPanelSuspend()
    CreateThread(function()
        local ok = UI.Progress(data.label or 'Processing...', data.duration or 5000, { canCancel = data.canCancel })
        WhipPanelResume()
        WhipPanelData('uitester', 'result', { demo = 'progress', result = ok })
    end)
    cb('ok')
end)

RegisterNUICallback('uitTestInput', function(_, cb)
    WhipPanelSuspend()
    CreateThread(function()
        local result = UI.Input('Test Input Dialog', {
            { label = 'Name', type = 'text', placeholder = 'Enter your name...', required = true },
            { label = 'Age', type = 'number', placeholder = '18', min = 1, max = 120 },
            { label = 'Role', type = 'select', options = {
                { label = 'Civilian', value = 'civilian' },
                { label = 'Police', value = 'police' },
                { label = 'EMS', value = 'ems' },
                { label = 'Mechanic', value = 'mechanic' },
            }},
            { label = 'Agree to rules', type = 'checkbox', placeholder = 'I agree to the server rules' },
        })
        WhipPanelResume()
        WhipPanelData('uitester', 'result', { demo = 'input', result = result })
    end)
    cb('ok')
end)

RegisterNUICallback('uitTestSkillCheck', function(data, cb)
    WhipPanelSuspend()
    CreateThread(function()
        -- The three difficulties in config.lua (Config.SkillCheckDifficulty); anything else plays easy.
        local known = { easy = true, medium = true, hard = true }
        local ok = UI.SkillCheck(known[data.difficulty] and data.difficulty or 'easy')
        WhipPanelResume()
        WhipPanelData('uitester', 'result', { demo = 'skillcheck', result = ok })
    end)
    cb('ok')
end)

RegisterNUICallback('uitTestAlert', function(_, cb)
    WhipPanelSuspend()
    CreateThread(function()
        UI.Alert('Server Notice', 'The server will restart in 5 minutes. Please save your progress.')
        WhipPanelResume()
        WhipPanelData('uitester', 'result', { demo = 'alert', result = 'dismissed' })
    end)
    cb('ok')
end)

RegisterNUICallback('uitTestConfirm', function(_, cb)
    WhipPanelSuspend()
    CreateThread(function()
        local ok = UI.Confirm('Delete Vehicle', 'Are you sure you want to delete this vehicle? This action cannot be undone.', 'Delete', 'Keep')
        WhipPanelResume()
        WhipPanelData('uitester', 'result', { demo = 'confirm', result = ok })
    end)
    cb('ok')
end)

--- The old tester toggled the bottom band on and off from its non-modal card. A
--- suspended panel has no reachable "hide" button, so the toggle became a timed
--- preview — the same shape the top-position demo already had.
RegisterNUICallback('uitTestDrawtext', function(_, cb)
    WhipPanelSuspend()
    CreateThread(function()
        UI.ShowText('[E] Search Vehicle', 'bottom')
        Wait(2500)
        UI.HideText()
        WhipPanelResume()
        WhipPanelData('uitester', 'result', { demo = 'drawtext', result = 'bottom shown for 2.5s' })
    end)
    cb('ok')
end)

--- The top position, which had no test until now — .ui-drawtext-top existed unexercised.
RegisterNUICallback('uitTestDrawtextTop', function(_, cb)
    WhipPanelSuspend()
    CreateThread(function()
        UI.ShowText('Shown at the top of the screen', 'top')
        Wait(2500)
        UI.HideText()
        WhipPanelResume()
        WhipPanelData('uitester', 'result', { demo = 'drawtext', result = 'top shown for 2.5s' })
    end)
    cb('ok')
end)

--- The MANUAL fill: the caller drives the percentage frame by frame, which is what the hold-E
--- respawn does. UI.Progress is the same band driven automatically — test that above.
RegisterNUICallback('uitTestDrawtextProgress', function(_, cb)
    WhipPanelSuspend()
    CreateThread(function()
        for i = 0, 100, 2 do
            UI.ShowText('Hold [E] to respawn', 'bottom', i)
            Wait(50)
        end
        Wait(500)
        UI.HideText()
        WhipPanelResume()
        WhipPanelData('uitester', 'result', { demo = 'drawtext', result = 'manual fill 0-100 complete' })
    end)
    cb('ok')
end)

-- ============================================
-- Radial menu — registration, not a dialog
-- ============================================
--
-- The tester registers sample options the same way any resource would, then opens the
-- wheel. It deliberately does NOT have a "show these options" call to make, because no
-- such call exists any more — that was the whole problem with the old radial.
--
-- The wheel owns its own focus and lifetime, so the panel cannot resume on a fixed
-- wait: a watcher polls IsRadialOpen and resumes when the wheel has come and gone —
-- selection or cancel alike. A selection's result lands via the option callback.

local uitRadialIds = {}

RegisterNUICallback('uitTestRadial', function(_, cb)
    cb('ok')

    if #uitRadialIds == 0 then
        local samples = { 'Inventory', 'Phone', 'Emotes' }
        for _, label in ipairs(samples) do
            -- The house-convention global (see radial.lua) — same registrar the export wraps.
            local id = WhipRadialAddOption({
                label = label,
                group = 'uitest',
                -- No condition: these are always offered, so the wheel opens on foot too. Real
                -- options gate themselves — the vehicle ones only appear when you are in a car.
                callback = function()
                    WhipPanelData('uitester', 'result', { demo = 'radial', result = label })
                end,
            })
            uitRadialIds[#uitRadialIds + 1] = id
        end
    end

    WhipPanelSuspend()
    CreateThread(function()
        Wait(50)
        ExecuteCommand('whip_radial')
        -- Wait for the wheel to appear (bounded — if something refused the open, resume
        -- rather than leave the panel hidden forever), then for it to close.
        local waited = 0
        while not RadialIsOpen() and waited < 2000 do
            Wait(50)
            waited = waited + 50
        end
        while RadialIsOpen() do
            Wait(100)
        end
        WhipPanelResume()
    end)
end)

RegisterNUICallback('uitTestRadialClear', function(_, cb)
    -- Nothing to see on screen — no suspend, just the registry change and its receipt.
    WhipRadialRemoveGroup('uitest')
    uitRadialIds = {}
    WhipPanelData('uitester', 'result', { demo = 'radial', result = 'sample options removed' })
    cb('ok')
end)

RegisterNUICallback('uitTestInteract', function(_, cb)
    WhipPanelSuspend()
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local fwd = GetEntityForwardVector(ped)
    local testId = 'ui_test_' .. tostring(math.random(1000, 9999))
    Interactions.register({
        id    = testId,
        x     = c.x + fwd.x * 3.0,
        y     = c.y + fwd.y * 3.0,
        z     = c.z,
        label = 'Test Interact',
        icon  = 'E',
        group = 'ui_test',
        callback = function()
            UI.Notify('Interaction triggered!', 'success')
            Interactions.remove(testId)
        end,
    })
    UI.Notify('Test interact point spawned 3m ahead (walk up to it)', 'info')
    -- Auto-cleanup after 30s
    SetTimeout(30000, function()
        Interactions.remove(testId)
    end)
    -- Long enough to read the toast and see the indicator appear; reaching it means
    -- closing the panel and walking, which is the admin's move to make.
    CreateThread(function()
        Wait(3000)
        WhipPanelResume()
        WhipPanelData('uitester', 'result', { demo = 'interact', result = 'spawned 3m ahead — 30s to reach it' })
    end)
    cb('ok')
end)
