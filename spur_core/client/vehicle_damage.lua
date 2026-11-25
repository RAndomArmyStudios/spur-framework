-- ============================================
-- Vehicle damage — this game's half
-- ============================================
--
-- server/vehicle_damage.lua keeps an owned car's damage. This game does three things for it:
--   * puts the stored damage back on a car the server hands it (it runs the car, or drives it);
--   * while driving, reports the doors torn off and the burst tyres, which the server cannot see.
--     Health it reads off the car itself;
--   * says when the car it drove is wrecked: blown up, or sunk (below).

--- GTA's tyre numbers: front left, front right, the middle pair of a six-wheeler, rear left, rear
--- right, a trailer's middle pair. Bit i-1 of a tyre mask is TYRES[i]. A bike's are 0 and 4.
local TYRES = { 0, 1, 2, 3, 4, 5, 45, 47 }

--- Doors 0-7 (front left, front right, rear left, rear right, bonnet, boot, then a few models' extra
--- two). Bit n of the door mask is door n.
local LAST_DOOR = 7

--- How often the driver's game looks while driving. Reported only when something changed.
local CHECK_MS = 2000

local function bit(n) return 1 << n end

--- The doors gone and the tyres burst on a car, as the server's three masks.
---@return integer doors, integer flat, integer rim
local function readMarks(veh)
    local doors, flat, rim = 0, 0, 0
    for door = 0, LAST_DOOR do
        -- A door the model does not have is not one it lost.
        if GetIsDoorValid(veh, door) and IsVehicleDoorDamaged(veh, door) then
            doors = doors | bit(door)
        end
    end
    for i, tyre in ipairs(TYRES) do
        if IsVehicleTyreBurst(veh, tyre, true) then
            rim = rim | bit(i - 1)
        elseif IsVehicleTyreBurst(veh, tyre, false) then
            flat = flat | bit(i - 1)
        end
    end
    return doors, flat, rim
end

-- ============================================
-- Reporting doors and tyres while driving
-- ============================================

--- The car this game is driving: { vehicleId, entity, sent }. `sent` is the last report; nil sends the
--- next look whatever it finds (the first one, and after a put-back).
local driving = nil

local function report(w)
    if not DoesEntityExist(w.entity) then return end
    local doors, flat, rim = readMarks(w.entity)
    local key = ('%d:%d:%d'):format(doors, flat, rim)
    if key == w.sent then return end
    w.sent = key
    TriggerServerEvent('spur_core:server:vehicleDamageReport', w.vehicleId, doors, flat, rim)
end

--- Stop watching, with one last look (getting out, or sliding out of the driver's seat).
local function stopDriving()
    local w = driving
    driving = nil
    if w then report(w) end
end

-- ============================================
-- Wrecked: blown up, or sunk
-- ============================================
--
-- No server native tells a sunk car from a sound one: its health stays up as it fills with water. This
-- game sees it: dead (blown up), or under water to the roof for a few seconds (not a boat: a submarine
-- dives). Not GTA's "undriveable", which whip's own ignition sets on a car with its engine off. Said
-- for the car this game drove, while it still runs that car and is near it (getting out and swimming
-- off), and said again if it turns back (repaired, lifted out).

local WRECK_MS = 1000
local SUNK_LEVEL = 0.85    -- how far under water (0 to 1) is sunk
local SUNK_LOOKS = 5       -- that many looks in a row (seconds)
local WRECK_NEAR = 150.0   -- metres: out of it and further than this, it is no longer this game's to watch
local wreckWatch = nil     -- { vehicleId, entity, wrecked, sunkFor }

local function looksWrecked(w)
    local e = w.entity
    if IsEntityDead(e) then return true end
    if GetVehicleClass(e) ~= 14 and GetEntitySubmergedLevel(e) >= SUNK_LEVEL then
        w.sunkFor = w.sunkFor + 1
    else
        w.sunkFor = 0
    end
    return w.sunkFor >= SUNK_LOOKS
end

local function watchWreck(vehicleId, entity)
    if wreckWatch and wreckWatch.vehicleId == vehicleId and wreckWatch.entity == entity then return end
    local w = { vehicleId = vehicleId, entity = entity, wrecked = false, sunkFor = 0 }
    wreckWatch = w
    CreateThread(function()
        while wreckWatch == w do
            Wait(WRECK_MS)
            if wreckWatch ~= w then break end
            if not DoesEntityExist(w.entity) then wreckWatch = nil break end
            -- (Another game running it now: its word, not this one's.)
            if NetworkGetEntityOwner(w.entity) == PlayerId() then
                local now = looksWrecked(w)
                if now ~= w.wrecked then
                    w.wrecked = now
                    TriggerServerEvent('spur_core:server:vehicleWrecked', w.vehicleId, now)
                end
            end
            local ped = PlayerPedId()
            if GetVehiclePedIsIn(ped, false) ~= w.entity
               and #(GetEntityCoords(ped) - GetEntityCoords(w.entity)) > WRECK_NEAR then
                wreckWatch = nil
            end
        end
    end)
end

AddEventHandler('spur_core:vehicle:entered', function(data)
    if type(data) ~= 'table' then return end
    if data.seat == -1 and data.vehicleId and data.entity then watchWreck(data.vehicleId, data.entity) end
    if data.seat ~= -1 or not data.vehicleId or not data.entity then
        if driving and driving.vehicleId == data.vehicleId then stopDriving() end
        return
    end
    if driving and driving.vehicleId == data.vehicleId then return end
    stopDriving()

    local w = { vehicleId = data.vehicleId, entity = data.entity }
    driving = w
    -- Lives while this car is driven: ends when another takes its place, or nothing does.
    CreateThread(function()
        while driving == w do
            Wait(CHECK_MS)
            if driving ~= w then break end
            if not DoesEntityExist(w.entity) then driving = nil; break end
            report(w)
        end
    end)
end)

AddEventHandler('spur_core:vehicle:exited', function(data)
    if driving and type(data) == 'table' and data.vehicleId == driving.vehicleId then stopDriving() end
end)

-- ============================================
-- Putting stored damage back on
-- ============================================

--- Only ever more damage: the lower health, the doors and tyres it does not already lack. So a put-back
--- that arrives twice, or onto a car hit since it spawned, takes nothing off it.
local function putBack(veh, d)
    local engine, body = tonumber(d.engine), tonumber(d.body)
    if engine and engine < GetVehicleEngineHealth(veh) then SetVehicleEngineHealth(veh, engine + 0.0) end
    if body and body < GetVehicleBodyHealth(veh) then SetVehicleBodyHealth(veh, body + 0.0) end
    -- RedM (spur_core, 24 Nov 2026): the car's own health (a wagon's is what wrecks it)
    local health = tonumber(d.health)
    if health and health > 0 and health < GetEntityHealth(veh) then SetEntityHealth(veh, math.floor(health)) end

    local doors = math.floor(tonumber(d.doors) or 0)
    for door = 0, LAST_DOOR do
        if (doors & bit(door)) ~= 0 and GetIsDoorValid(veh, door) and not IsVehicleDoorDamaged(veh, door) then
            SetVehicleDoorBroken(veh, door, true)   -- true: gone, not left lying in the road
        end
    end

    local flat, rim = math.floor(tonumber(d.flat) or 0), math.floor(tonumber(d.rim) or 0)
    for i, tyre in ipairs(TYRES) do
        local b = bit(i - 1)
        if (rim & b) ~= 0 then
            if not IsVehicleTyreBurst(veh, tyre, true) then SetVehicleTyreBurst(veh, tyre, true, 1000.0) end
        elseif (flat & b) ~= 0 then
            if not IsVehicleTyreBurst(veh, tyre, false) then SetVehicleTyreBurst(veh, tyre, false, 1000.0) end
        end
    end
end

RegisterNetEvent('spur_core:client:vehicleDamagePutBack', function(vehicleId, netId, d)
    if type(vehicleId) ~= 'number' or type(netId) ~= 'number' or type(d) ~= 'table' then return end
    -- Sent to the game running the car, which has it. One that does not (it left range since) says
    -- nothing, and the server offers it again.
    if not NetworkDoesNetworkIdExist(netId) then return end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end

    CreateThread(function()
        if not Vehicles.takeControl(veh, { attempts = 2 }) then return end
        putBack(veh, d)
        TriggerServerEvent('spur_core:server:vehicleDamagePutBack', vehicleId)
        -- The server ignored what this game reported before now: report afresh.
        if driving and driving.vehicleId == vehicleId then driving.sent = nil end
    end)
end)
