-- ============================================
-- Director kit, the game's half — what the Director modules ask the tester's game (server/director_kit.lua)
-- ============================================
--
-- Each ask is answered once, with plain data: where the tester is put, the ground's height, and what this game
-- sees of a thing a run made (its entity by netId, or a local prop by its model near a point). Every read is
-- guarded: one this game cannot make answers nil, and the test says so.

local ASK = {}

local function safe(fn, ...)
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
    return nil
end

--- A yes or no read, as true or false: some natives answer 1 and 0 (DoesEntityExist among them). nil stays nil.
local function yes(v)
    if v == nil then return nil end
    return v == true or v == 1
end

local function netOf(ent)
    if not ent or ent == 0 or not yes(DoesEntityExist(ent)) then return false end
    if not yes(NetworkGetEntityIsNetworked(ent)) then return false end
    return NetworkGetNetworkIdFromEntity(ent)
end

--- The entity a probe names: a networked one by netId, or the nearest object of a model to a point.
local function entityOf(q)
    if type(q) ~= 'table' then return 0 end
    if q.net then
        if not yes(NetworkDoesNetworkIdExist(q.net)) then return 0 end
        return NetworkGetEntityFromNetworkId(q.net) or 0
    end
    if q.model and q.at then
        local hash = type(q.model) == 'number' and q.model or GetHashKey(q.model)
        return GetClosestObjectOfType(q.at.x + 0.0, q.at.y + 0.0, q.at.z + 0.0, (q.radius or 3.0) + 0.0, hash, false, false, false) or 0
    end
    return 0
end

local KINDS = { [1] = 'ped', [2] = 'vehicle', [3] = 'object' }

local function readPed(ped, q, out)
    local veh = GetVehiclePedIsIn(ped, false)
    out.inVehicle = veh ~= 0 and netOf(veh) or false
    if veh ~= 0 then
        for seat = -1, GetVehicleMaxNumberOfPassengers(veh) - 1 do
            if GetPedInVehicleSeat(veh, seat) == ped then out.seat = seat break end
        end
    end
    out.weapon = safe(GetSelectedPedWeapon, ped)
    out.armed = yes(safe(IsPedArmed, ped, 7))
    -- RedM (spur_test, 24 Nov 2026): RDR2's IS_PED_ARMED flags are not the original game's, so also whether the weapon in its hand
    -- is a gun (IS_WEAPON_A_GUN).
    out.gun = out.weapon ~= nil and out.weapon ~= 0
        and yes(safe(Citizen.InvokeNative, 0x705BE297EEBDB95D, out.weapon, Citizen.ResultAsInteger())) or false
    out.fleeing = yes(safe(IsPedFleeing, ped))
    out.cover = yes(safe(IsPedInCover, ped, false))
    out.ragdoll = yes(safe(IsPedRagdoll, ped))
    out.dying = yes(safe(IsPedDeadOrDying, ped, true))
    out.writhe = yes(safe(IsPedInWrithe, ped))
    out.scenario = yes(safe(IsPedUsingAnyScenario, ped))
    out.shooting = yes(safe(IsPedShooting, ped))
    out.combat = yes(safe(IsPedInCombat, ped, 0))
    out.still = yes(safe(IsPedStill, ped))
    -- Its combat task: 0 waiting to start, 1 running, 7 none (GetScriptTaskStatus).
    out.combatTask = safe(GetScriptTaskStatus, ped, GetHashKey('SCRIPT_TASK_COMBAT'))
    -- In combat with one named thing (`vs`, a netId): the other NPC of Fight an NPC.
    if q.vs and yes(NetworkDoesNetworkIdExist(q.vs)) then
        local other = NetworkGetEntityFromNetworkId(q.vs)
        if other ~= 0 then out.combatVs = yes(safe(IsPedInCombat, ped, other)) end
    end
    if q.anim and q.anim.dict and q.anim.clip then
        out.anim = yes(safe(IsEntityPlayingAnim, ped, q.anim.dict, q.anim.clip, 3))
    end
    if q.scenarioName then out.scenarioNamed = yes(safe(IsPedUsingScenario, ped, q.scenarioName)) end
end

local function readVehicle(veh, out)
    out.engine = yes(safe(GetIsVehicleEngineRunning, veh))
    out.siren = yes(safe(IsVehicleSirenOn, veh))
    local _, lightsOn, highbeams = safe(GetVehicleLightsState, veh)
    out.lightsRaw = tostring(lightsOn) .. '/' .. tostring(highbeams)
    out.lightsOn, out.highbeams = yes(lightsOn) == true, yes(highbeams) == true
    out.indicators = safe(GetVehicleIndicatorLights, veh)
    out.horn = yes(safe(IsHornActive, veh))
    out.alarm = yes(safe(IsVehicleAlarmActivated, veh))
    out.lock = safe(GetVehicleDoorLockStatus, veh)
    out.doors, out.windows, out.tyres = {}, {}, {}
    for d = 0, 5 do out.doors[d + 1] = safe(GetVehicleDoorAngleRatio, veh, d) or 0.0 end
    for w = 0, 3 do out.windows[w + 1] = yes(safe(IsVehicleWindowIntact, veh, w)) end
    for t = 0, 5 do out.tyres[t + 1] = yes(safe(IsVehicleTyreBurst, veh, t, false)) end
    out.roof = safe(GetConvertibleRoofState, veh)
    out.dirt = safe(GetVehicleDirtLevel, veh)
    out.engineHealth = safe(GetVehicleEngineHealth, veh)
    out.bodyHealth = safe(GetVehicleBodyHealth, veh)
    out.driver = netOf(GetPedInVehicleSeat(veh, -1))
    out.plate = safe(GetVehicleNumberPlateText, veh)
    out.stopped = yes(safe(IsVehicleStopped, veh))
    -- RedM (spur_test, 24 Nov 2026): an RDR2 wagon moves only with horses in its harness. Whether it is one
    -- (_IS_DRAFT_VEHICLE) and how many are there (_GET_PED_IN_DRAFT_HARNESS at each of its six places).
    local N = Citizen.InvokeNative
    if yes(safe(N, 0xEA44E97849E9F3DD, veh, Citizen.ResultAsInteger())) then
        local n = 0
        for i = 0, 5 do
            local p = safe(N, 0xA8BA0BAE0173457B, veh, i, Citizen.ResultAsInteger())
            if p and p ~= 0 then n = n + 1 end
        end
        out.draft, out.horses = true, n
    end
end

--- What this game sees of each thing: { exists, kind, x, y, z, heading, health, ... } (by its kind).
ASK.probe = function(list)
    local out = {}
    for i, q in ipairs(type(list) == 'table' and list or {}) do
        local ent = entityOf(q)
        local o = { exists = ent ~= 0 and yes(DoesEntityExist(ent)) == true }
        if o.exists then
            local c = GetEntityCoords(ent)
            o.x, o.y, o.z = c.x, c.y, c.z
            o.heading = GetEntityHeading(ent)
            o.kind = KINDS[GetEntityType(ent)] or 'other'
            o.health, o.maxHealth = GetEntityHealth(ent), GetEntityMaxHealth(ent)
            o.speed = GetEntitySpeed(ent)
            o.visible = yes(safe(IsEntityVisible, ent))
            o.alpha = safe(GetEntityAlpha, ent)
            o.dead = yes(safe(IsEntityDead, ent))
            o.onFire = yes(safe(IsEntityOnFire, ent))
            o.model = GetEntityModel(ent)
            o.local_ = not yes(NetworkGetEntityIsNetworked(ent))
            if o.kind == 'ped' then readPed(ent, q, o) elseif o.kind == 'vehicle' then readVehicle(ent, o) end
        end
        out[i] = o
    end
    return out
end

--- The tester, put somewhere: collision loaded there, then on the ground. Where they ended up (z: the ground).
ASK.teleport = function(a)
    local ped = PlayerPedId()
    local x, y, z = a.x + 0.0, a.y + 0.0, a.z + 0.0
    FreezeEntityPosition(ped, true)
    RequestCollisionAtCoord(x, y, z)
    SetEntityCoordsNoOffset(ped, x, y, z + 1.0, false, false, false)
    SetEntityHeading(ped, (tonumber(a.heading) or 0.0) + 0.0)
    local deadline = GetGameTimer() + 6000
    while not yes(HasCollisionLoadedAroundEntity(ped)) and GetGameTimer() < deadline do
        RequestCollisionAtCoord(x, y, z)
        Wait(50)
    end
    -- RedM (spur_test, 23 Nov 2026): `exact` (going home): look down from just above where they stood, so the floor of the room
    -- they were in is found, not the roof over it.
    local found, gz = GetGroundZFor_3dCoord(x, y, z + (a.exact and 1.0 or 50.0), false)
    -- RedM (spur_test, 24 Nov 2026): after a long teleport the ground can stream in a few seconds after
    -- HasCollisionLoadedAroundEntity says it has, and a place's z in a list can be a guess. Keep looking for up to 4 s,
    -- from 1000 m up as well.
    if not yes(found) and not a.exact then
        local giveUp = GetGameTimer() + 4000
        repeat
            RequestCollisionAtCoord(x, y, z)
            Wait(100)
            found, gz = GetGroundZFor_3dCoord(x, y, z + 50.0, false)
            if not yes(found) then found, gz = GetGroundZFor_3dCoord(x, y, 1000.0, false) end
        until yes(found) or GetGameTimer() > giveUp
    end
    found = yes(found) == true
    if found then SetEntityCoordsNoOffset(ped, x, y, gz + 1.0, false, false, false) end
    -- RedM (spur_test, 23 Nov 2026): no ground found, the tester stays held where they were put rather than drop
    -- from a look-down height (a field candidate is tried that way); the next teleport, or going home, lets go.
    if found or a.exact then FreezeEntityPosition(ped, false) end
    Wait(500)
    local c = GetEntityCoords(ped)
    return { x = c.x, y = c.y, z = found and gz or (c.z - 1.0), heading = GetEntityHeading(ped), ground = found }   -- RedM (spur_test, 24 Nov 2026): ground
end

--- The ground's height at each { x, y, z? } (z: where to look down from), or false.
-- RedM (spur_test, 24 Nov 2026): up to three passes half a second apart. A point the first pass finds no ground at is
-- looked at again, from 1000 m up as well, because ground a little way off can still be streaming in.
ASK.ground = function(points)
    local list, out = type(points) == 'table' and points or {}, {}
    for pass = 1, 3 do
        local missing = false
        for i, p in ipairs(list) do
            if out[i] == nil then
                local from = (tonumber(p.z) or 0.0) + 50.0
                RequestCollisionAtCoord(p.x + 0.0, p.y + 0.0, from)
                local found, gz = GetGroundZFor_3dCoord(p.x + 0.0, p.y + 0.0, from, false)
                if not yes(found) and pass > 1 then found, gz = GetGroundZFor_3dCoord(p.x + 0.0, p.y + 0.0, 1000.0, false) end
                if yes(found) then out[i] = gz else missing = true end
            end
        end
        if not missing then break end
        Wait(500)
    end
    for i = 1, #list do if out[i] == nil then out[i] = false end end
    return out
end

--- The tester's own state: where, in what, how they are.
ASK.me = function()
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local veh = GetVehiclePedIsIn(ped, false)
    return { x = c.x, y = c.y, z = c.z, heading = GetEntityHeading(ped), vehicle = veh ~= 0 and netOf(veh) or false,
             health = GetEntityHealth(ped), dead = IsEntityDead(ped) }
end

--- Into a car by its netId (a seat: -1 the driver), at once.
ASK.enter = function(a)
    local ped = PlayerPedId()
    if not yes(NetworkDoesNetworkIdExist(a.net)) then return { ok = false, why = 'no such car here' } end
    local veh = NetworkGetEntityFromNetworkId(a.net)
    if veh == 0 then return { ok = false, why = 'no such car here' } end
    SetPedIntoVehicle(ped, veh, a.seat or -1)
    Wait(400)
    return { ok = GetVehiclePedIsIn(ped, false) == veh }
end

RegisterNetEvent('spur_test:dk:ask', function(token, what, args)
    local fn = ASK[what]
    local ok, result = false, nil
    if fn then ok, result = pcall(fn, args) else result = 'no such ask: ' .. tostring(what) end
    if not ok then result = { error = tostring(result) } end
    TriggerServerEvent('spur_test:dk:answer', token, result)
end)
