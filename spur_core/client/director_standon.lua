-- ============================================
-- Director — standing on a scenario's car while it moves (client)
-- ============================================
--
-- A car's "Players and NPCs can stand on it while it moves" (its General tab: def.standOn) puts VehicleData directorStandOn
-- on every car the scenario makes for it (server/director/satellite_api.lua). The game throws a player standing on most
-- moving cars off (a ragdoll; trucks and trailers are made to be stood on). While this player stands on a car that
-- carries it, their own game blocks that fall every frame (the ped reset flag BlockRagdollFromVehicleFallOff), and
-- for a moment after (a bump lifts them off the roof for a frame or two). Nothing else changes: a very sharp turn can
-- still slide them off, and they can jump off, be pushed or shot off as anywhere.
--
-- Looked at four times a second, and only past IsPedOnVehicle when standing on one; every frame only while on a car
-- that carries it.

local KEY = 'directorStandOn'
local RESET_NO_VEHICLE_FALL_OFF = 274   -- CPED_RESET_FLAG_BlockRagdollFromVehicleFallOff
local LOOK_MS = 250
local NEAR_M = 20.0                     -- a car whose middle is further than this cannot be the one under you
local GRACE_MS = 600                    -- off its roof this long (a bump) still counts as on it

-- The cars here that carry it, [entity] = true: kept by whip's vehicle data watcher (client/vehicle_data.lua) as their
-- data comes and goes, as client/npcs.lua and client/take_copies.lua keep theirs, so nothing reads a car's whole data
-- block to ask.
local carrying = {}
VehicleData.watch(KEY, {
    id = 'standOn',
    onGained = function(entity, value) carrying[entity] = value == true or nil end,
    onLost = function(entity) carrying[entity] = nil end,
})

local function carries(veh) return carrying[veh] == true end

--- The car this ped stands on, when it carries it; else nil.
local function standingOn(ped)
    if not IsPedOnVehicle(ped) or IsPedInAnyVehicle(ped, false) then return nil end
    local at = GetEntityCoords(ped)
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if #(GetEntityCoords(veh) - at) <= NEAR_M and IsPedOnSpecificVehicle(ped, veh) then
            return carries(veh) and veh or nil
        end
    end
    return nil
end

CreateThread(function()
    while true do
        local veh = standingOn(PlayerPedId())
        if not veh then
            Wait(LOOK_MS)
        else
            local lastOn = GetGameTimer()
            while DoesEntityExist(veh) and GetGameTimer() - lastOn <= GRACE_MS do
                local ped = PlayerPedId()
                if IsPedInAnyVehicle(ped, false) then break end
                if IsPedOnSpecificVehicle(ped, veh) then lastOn = GetGameTimer() end
                SetPedResetFlag(ped, RESET_NO_VEHICLE_FALL_OFF, true)
                Wait(0)
            end
        end
    end
end)
