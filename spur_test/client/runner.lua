-- ============================================
-- spur_test — Client Test Runner
-- ============================================

-- ============================================
-- Assert Helpers (mirror server)
-- ============================================

--- How many checks the current test has made; a test that finishes with none FAILS. See the server
--- runner for why.
AssertCount = 0

local function counted()
    AssertCount = AssertCount + 1
end

function assertEqual(actual, expected, label)
    counted()
    if actual ~= expected then
        error(('%s: expected %s, got %s'):format(label or 'assertEqual', tostring(expected), tostring(actual)), 2)
    end
end

function assertNotEqual(actual, notExpected, label)
    counted()
    if actual == notExpected then
        error(('%s: expected NOT %s'):format(label or 'assertNotEqual', tostring(notExpected)), 2)
    end
end

function assertType(value, expectedType, label)
    counted()
    if type(value) ~= expectedType then
        error(('%s: expected type %s, got %s'):format(label or 'assertType', expectedType, type(value)), 2)
    end
end

function assertNotNil(value, label)
    counted()
    if value == nil then
        error(('%s: expected non-nil'):format(label or 'assertNotNil'), 2)
    end
end

function assertNil(value, label)
    counted()
    if value ~= nil then
        error(('%s: expected nil, got %s'):format(label or 'assertNil', tostring(value)), 2)
    end
end

function assertTrue(value, label)
    counted()
    if value ~= true then
        error(('%s: expected true, got %s'):format(label or 'assertTrue', tostring(value)), 2)
    end
end

function assertFalse(value, label)
    counted()
    if value ~= false then
        error(('%s: expected false, got %s'):format(label or 'assertFalse', tostring(value)), 2)
    end
end

function assertGte(value, threshold, label)
    counted()
    if not (value >= threshold) then
        error(('%s: expected >= %s, got %s'):format(label or 'assertGte', tostring(threshold), tostring(value)), 2)
    end
end

--- Poll until fn() returns truthy, or timeout. Returns the value (or nil on timeout).
--- The client twin of the server's waitFor: use it instead of a fixed Wait wherever the thing
--- being waited for can be observed.
---@param fn function
---@param timeoutMs number|nil
---@return any
function waitFor(fn, timeoutMs)
    local deadline = GetGameTimer() + (timeoutMs or 3000)
    while GetGameTimer() < deadline do
        local ok, value = pcall(fn)
        if ok and value then return value end
        Wait(50)
    end
    return nil
end

-- Skip support. Mirrors the server runner — globals do not cross the client/server
-- boundary, so both sides need their own copy. A test that opts out must report as
-- SKIPPED, never as a pass.
SKIP_SENTINEL = '__spur_test_skip__'

--- Abort the current test and record it as SKIPPED rather than passed.
---@param reason string
function skip(reason)
    error({ [SKIP_SENTINEL] = true, reason = reason or 'no reason given' }, 2)
end

---@param err any
---@return boolean
function IsSkip(err)
    return type(err) == 'table' and err[SKIP_SENTINEL] == true
end

-- ============================================
-- Test Module Registry
-- ============================================

ClientTestModules = {}

function RegisterClientTestModule(mod)
    ClientTestModules[#ClientTestModules + 1] = mod
end

-- (autoResolveUI used to live here. It could never have worked — SendNUIMessage from spur_test
-- reaches spur_test's own page, not spur_core's, and 'uiResult' is a callback spur_core's page
-- SENDS rather than a message it handles — and nothing called it. Removed.)

-- ============================================
-- Run Client Tests
-- ============================================

--- sectionId: the /test menu section being run (shared/sections.lua), or nil for every module.
RegisterNetEvent('spur_test:runClientTests', function(sectionId)
    CreateThread(function()
        local results = {}

        table.sort(ClientTestModules, function(a, b) return (a.order or 99) < (b.order or 99) end)

        -- Only this run's modules: all of them, or the chosen section's.
        local modules = {}
        for _, mod in ipairs(ClientTestModules) do
            if sectionId == nil or TestSectionOf(mod.category) == sectionId then
                modules[#modules + 1] = mod
            end
        end

        -- What registered, so the server can see a module that never did. A test file that throws
        -- while loading does not register, and without this it simply vanished from the report.
        local info = { expected = 0, orders = {} }
        for _, mod in ipairs(modules) do
            info.expected = info.expected + #(mod.tests or {})
            if mod.order then info.orders[#info.orders + 1] = mod.order end
        end

        for _, mod in ipairs(modules) do
            -- Owned by the runner and filled by setup, as on the server: a setup that throws after
            -- creating something still leaves its teardown a way to find it.
            local ctx = {}
            local setupFailed  = nil
            local setupSkipped = nil

            -- Setup
            if mod.setup then
                local ok, result = pcall(mod.setup, ctx)
                if not ok then
                    -- skip() in setup is a skip, not "SETUP FAILED: table: 0x…".
                    if IsSkip(result) then setupSkipped = result.reason
                    else setupFailed = tostring(result) end
                elseif type(result) == 'table' then
                    ctx = result
                end
            end

            if setupFailed or setupSkipped then
                -- One row per test, so the report's denominator stays honest.
                for _, test in ipairs(mod.tests) do
                    results[#results + 1] = {
                        category = mod.category,
                        name     = ('%s: %s'):format(setupSkipped and 'SETUP SKIPPED' or 'SETUP FAILED', test.name),
                        passed   = false,
                        skipped  = setupSkipped and true or nil,
                        error    = setupSkipped or setupFailed,
                        duration = 0,
                        side     = 'client',
                    }
                end
            else
                -- Run tests
                for _, test in ipairs(mod.tests) do
                    local start = GetGameTimer()
                    AssertCount = 0
                    local ok, err = pcall(test.fn, ctx)
                    local duration = GetGameTimer() - start

                    if ok and AssertCount == 0 then
                        ok, err = false, 'no assertion ran — this test cannot fail as written'
                    end

                    local wasSkipped = (not ok) and IsSkip(err)
                    -- Written out: `ok and nil or X` is always X, so a PASS carried the error "nil".
                    local errText = nil
                    if not ok then errText = wasSkipped and err.reason or tostring(err) end

                    results[#results + 1] = {
                        category = mod.category,
                        name     = test.name,
                        passed   = ok,
                        skipped  = wasSkipped or nil,
                        error    = errText,
                        duration = duration,
                        side     = 'client',
                    }

                    -- Live chat output (same format as server)
                    if ok then
                        TriggerEvent('chat:addMessage', { args = { '[TEST]', ('^2✓ %s > %s ^7(%dms)'):format(mod.category, test.name, duration) } })
                    elseif wasSkipped then
                        TriggerEvent('chat:addMessage', { args = { '[TEST]', ('^3- %s > %s ^7(skipped: %s)'):format(mod.category, test.name, err.reason) } })
                    else
                        TriggerEvent('chat:addMessage', { args = { '[TEST]', ('^1✗ %s > %s^7: %s'):format(mod.category, test.name, tostring(err)) } })
                    end

                    Wait(50)
                end
            end

            -- Teardown — ALWAYS runs, and a failure is a recorded result rather than a
            -- silently discarded pcall.
            if mod.teardown then
                -- `ctx or {}` — teardown runs even after a failed setup; see server runner.
                local ok2, err2 = pcall(mod.teardown, ctx or {})
                if not ok2 then
                    results[#results + 1] = {
                        category = mod.category,
                        name     = 'TEARDOWN',
                        passed   = false,
                        error    = tostring(err2),
                        duration = 0,
                        side     = 'client',
                        meta     = true,
                    }
                end
            end
        end

        -- Send results back to server
        TriggerServerEvent('spur_test:clientResults', results, info)
    end)
end)

-- ============================================
-- Helper Events — Server asks client to trigger
-- spur_core events (SecureEvents need a real source)
-- ============================================

RegisterNetEvent('spur_test:clientExec', function(eventName, ...)
    TriggerServerEvent(eventName, ...)
end)

-- Each request carries a token from the server; echo it back so a late ack from a
-- timed-out call cannot be mistaken for the ack of the NEXT request. The server used to
-- share one boolean across all five wait helpers.
RegisterNetEvent('spur_test:clientExecWait', function(token, eventName, ...)
    TriggerServerEvent(eventName, ...)
    -- Small delay to let spur_core process
    Wait(500)
    TriggerServerEvent('spur_test:clientExecDone', token)
end)

-- Run a spur_core SecureCallback as this player and send back what it answered (ClientCallback on
-- the server). table.pack keeps a nil in the middle of the answer and records how many there were.
RegisterNetEvent('spur_test:clientCallback', function(token, name, ...)
    local results = table.pack(exports.spur_core:Callback(name, ...))
    TriggerServerEvent('spur_test:clientCallbackDone', token, results)
end)

-- Open a container via the normal interaction flow
RegisterNetEvent('spur_test:openContainer', function(token, containerId)
    TriggerServerEvent('spur_core:server:openContainer', containerId)
    Wait(500)
    TriggerServerEvent('spur_test:clientExecDone', token)
end)

-- Close a container (use spur_core's CloseInventory export)
RegisterNetEvent('spur_test:closeContainer', function(token, containerId)
    exports.spur_core:CloseInventory()
    Wait(300)
    TriggerServerEvent('spur_test:clientExecDone', token)
end)

-- Close whatever UI is open, then confirm.
--
-- Needed because spur_core's OpenInventoryUI refuses to open over an existing UI
-- (`if IsAnyUIOpen() then return false end`) and the caller then RELEASES whatever server
-- session it was told to show — which is correct, but means a test that opens a session
-- while a previous module left a panel up gets the session torn down underneath it.
RegisterNetEvent('spur_test:closeAllUI', function(token)
    pcall(exports.spur_core.CloseInventory, exports.spur_core)
    Wait(400)
    TriggerServerEvent('spur_test:clientExecDone', token)
end)

-- Cancel the progress bar spur_test put up (a server Progress call from a test draws a bar owned
-- by spur_test, so this resource's CancelProgress reaches it).
RegisterNetEvent('spur_test:cancelProgress', function(token)
    exports.spur_core:CancelProgress()
    Wait(100)
    TriggerServerEvent('spur_test:clientExecDone', token)
end)

-- Leave vehicle if in one
RegisterNetEvent('spur_test:leaveVehicle', function(token)
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        local veh = GetVehiclePedIsIn(ped, false)
        -- RedM (spur_test, 24 Nov 2026): 16 is the original game's "warp out", and an RDR2 tester given it stays aboard. 0 is the
        -- ordinary climb down (what an NPC's Everyone Out uses, and it works): up to 4 s for it. If the tester is
        -- still aboard after that, set them down beside the wagon. F8 says which way it went.
        TaskLeaveVehicle(ped, veh, 0)
        local t = GetGameTimer() + 4000
        while IsPedInAnyVehicle(ped, false) and GetGameTimer() < t do Wait(100) end
        local how = 'climbed down'
        if IsPedInAnyVehicle(ped, false) then
            local side = GetOffsetFromEntityInWorldCoords(veh, -2.5, 0.0, 0.0)
            ClearPedTasksImmediately(ped, true, true)
            SetEntityCoords(ped, side.x, side.y, side.z, false, false, false, false)
            Wait(500)
            how = IsPedInAnyVehicle(ped, false) and 'STILL ABOARD after being set down' or 'set down beside it'
        end
        print('[spur_test] RedM: leaving the wagon: ' .. how)
    end
    TriggerServerEvent('spur_test:clientExecDone', token)
end)

-- Get INTO a vehicle, by plate, in a named seat.
--
-- The counterpart to leaveVehicle above, which existed on its own for a long time because
-- nothing needed the other direction. The glovebox and the ignition now do: spur_core resolves
-- which vehicle those belong to from the seat the player is sitting in rather than from an id on
-- the wire, so a test that wants to open a glovebox has to actually be in the car.
--
-- Warps rather than walking. A TaskEnterVehicle animation takes several seconds and can fail on
-- geometry; a test wants the player seated, not a convincing performance of getting seated.
--
-- seat -1 is the driver. 0 is the front passenger, which is the seat that matters for proving a
-- PASSENGER can reach the glovebox.
RegisterNetEvent('spur_test:enterVehicle', function(token, plate, seat)
    local ped = PlayerPedId()
    local want = (plate or ''):upper():gsub('%s+', '')
    local found = nil

    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(veh) then
            local p = (GetVehicleNumberPlateText(veh) or ''):upper():gsub('%s+', '')
            if p == want then found = veh break end
        end
    end

    if found then
        SetPedIntoVehicle(ped, found, seat or -1)
        Wait(300)
    end

    TriggerServerEvent('spur_test:clientExecDone', token)
end)

-- Open vehicle storage (trunk/glovebox)
RegisterNetEvent('spur_test:openVehicleStorage', function(token, vehicleId, storageType)
    TriggerServerEvent('spur_core:server:openVehicleStorage', vehicleId, storageType)
    Wait(500)
    TriggerServerEvent('spur_test:clientExecDone', token)
end)

-- Close vehicle storage (use spur_core's CloseInventory export)
RegisterNetEvent('spur_test:closeVehicleStorage', function(token, vehicleId, storageType)
    exports.spur_core:CloseInventory()
    Wait(300)
    TriggerServerEvent('spur_test:clientExecDone', token)
end)

-- ============================================
-- Endurance Test HUD
-- ============================================

RegisterNetEvent('spur_test:enduranceStart', function()
    SendNUIMessage({ action = 'enduranceStart' })
end)

RegisterNetEvent('spur_test:enduranceStop', function()
    SendNUIMessage({ action = 'enduranceStop' })
end)

RegisterNetEvent('spur_test:enduranceUpdate', function(data)
    SendNUIMessage({ action = 'enduranceUpdate', data = data })
end)

-- ============================================
-- Cleanup — close inventory if open
-- ============================================

RegisterNetEvent('spur_test:cleanup', function()
    pcall(exports.spur_core.CloseInventory, exports.spur_core)
end)

-- ============================================
-- Report Card NUI
-- ============================================

RegisterNetEvent('spur_test:showReport', function(data)
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'showReport',
        data   = data,
    })
end)

RegisterNUICallback('closeReport', function(_, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

-- ============================================
-- The /test menu
-- ============================================
--
-- /test opens a card per section (shared/sections.lua). The server sends each card with its server
-- test count and last result; this side adds its own client tests, because only this side knows
-- which client modules registered.

RegisterNetEvent('spur_test:openMenu', function(data)
    local clientCounts = {}
    for _, mod in ipairs(ClientTestModules) do
        local sid = TestSectionOf(mod.category)
        clientCounts[sid] = (clientCounts[sid] or 0) + #(mod.tests or {})
    end

    local cards = {}
    for _, card in ipairs((data and data.sections) or {}) do
        card.client = clientCounts[card.id] or 0
        -- "Other" only earns a card when a module actually landed in it.
        if card.id ~= TEST_SECTION_OTHER.id or card.server + card.client > 0 then
            cards[#cards + 1] = card
        end
    end

    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'showMenu', data = { sections = cards } })
end)

--- A card or "Run full suite" was clicked. The menu hides itself; the cursor goes too, because the
--- tests need the game — an interaction prompt cannot take focus while this page holds it.
RegisterNUICallback('runSection', function(body, cb)
    SetNuiFocus(false, false)
    TriggerServerEvent('spur_test:runSection', body and body.section)
    cb('ok')
end)

RegisterNUICallback('closeMenu', function(_, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

--- The report's "Test menu" button: straight back to the cards to pick the next section.
RegisterNUICallback('openMenu', function(_, cb)
    TriggerServerEvent('spur_test:requestMenu')
    cb('ok')
end)
