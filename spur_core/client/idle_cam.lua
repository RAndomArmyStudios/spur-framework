-- ============================================
-- THE GAME'S IDLE CAMERA, OFF
-- ============================================
--
-- After about 30 s with no input the game swings the camera into a slow cinematic pan: on foot, as a
-- passenger, and in a parked car. Config.IdleCam.Disable = false keeps it.
--
-- ON FOOT AND AS A PASSENGER IT IS SWITCHED OFF ONCE: Cfx.re's DisableIdleCamera and
-- DisableVehiclePassengerIdleCamera turn it off and leave it off. Set again on spawn, in case the game
-- rebuilt something under them.
--
-- THE DRIVER'S HAS NO SWITCH, only a timer to reset (the game: "calling that in a loop once every few
-- seconds is enough"). So while in a car, and only then, its timer is reset every ResetMs.

local function enabled()
    return not (Config.IdleCam and Config.IdleCam.Disable == false)
end

local function switchOff()
    if not enabled() then return end
    DisableIdleCamera(true)
    DisableVehiclePassengerIdleCamera(true)
end

switchOff()
AddEventHandler('spur_core:player:spawned', switchOff)
-- And after a death: a death resurrects the player and never fires 'spawned'.
AddEventHandler('spur_core:player:revived', switchOff)

local resetting = false

--- While in a car, reset the driver's idle timer every ResetMs. Once per ride.
local function startResetting()
    if resetting or not enabled() then return end
    resetting = true
    CreateThread(function()
        local every = math.max(tonumber(Config.IdleCam and Config.IdleCam.ResetMs) or 10000, 1000)
        -- enabled() asked each time round, so turning the camera back on in /whip → Settings ends it.
        while IsPedInAnyVehicle(PlayerPedId(), false) and enabled() do
            InvalidateVehicleIdleCam()
            Wait(every)
        end
        resetting = false
    end)
end

AddEventHandler('spur_core:vehicle:entered', startResetting)

-- Changed in /whip → Settings. Off: switched off now, as at a spawn, and for the car they are in.
-- On: the game's camera given back now, as at a stop. ResetMs is read at each car and needs nothing.
Settings.onChange('IdleCam.Disable', function()
    if enabled() then
        switchOff()
        if IsPedInAnyVehicle(PlayerPedId(), false) then startResetting() end
    else
        DisableIdleCamera(false)
        DisableVehiclePassengerIdleCamera(false)
    end
end)

-- Stopping spur_core gives the game its camera back.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() or not enabled() then return end
    DisableIdleCamera(false)
    DisableVehiclePassengerIdleCamera(false)
end)
