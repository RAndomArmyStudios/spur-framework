-- ============================================
-- RDR ENTITIES — this game makes a ped the server asked for
-- ============================================
--
-- RedM (spur_core, 23 Nov 2026). A new file. RedM's server cannot make a ped (its CreatePed makes nothing), so it asks
-- the nearest player's game to (server/rdr_entities.lua): this makes it, networked, in RDR2's way (shared/rdr_compat.lua's
-- CreatePed, which dresses it), and answers with its network id. From then on the ped is the server's like any
-- other: the server keeps it (orphan mode) and its brain goes to whichever game owns it (client/npcs.lua).

local NET_MS = 3000   -- how long the new ped has to get a network id

RegisterNetEvent('spur_core:client:rdrMakePed', function(nonce, hash, x, y, z, heading)
    if type(nonce) ~= 'number' or type(hash) ~= 'number' then return end
    local function answer(netId, why)
        TriggerServerEvent('spur_core:server:rdrPedMade', nonce, netId or 0, why)
    end
    if not IsModelInCdimage(hash) or (IsModelAPed and not IsModelAPed(hash)) then answer(0, 'model') return end
    local loaded, why = LoadModel(hash)
    if not loaded then answer(0, why == 'missing' and 'model' or 'failed') return end
    local ped = CreatePed(4, hash, x + 0.0, y + 0.0, z + 0.0, heading + 0.0, true, true)
    SetModelAsNoLongerNeeded(hash)
    if not ped or ped == 0 or not DoesEntityExist(ped) then answer(0, 'failed') return end
    SetEntityAsMissionEntity(ped, true, true)
    local deadline = GetGameTimer() + NET_MS
    while not NetworkGetEntityIsNetworked(ped) and GetGameTimer() < deadline do Wait(0) end
    local netId = NetworkGetEntityIsNetworked(ped) and NetworkGetNetworkIdFromEntity(ped) or 0
    if not netId or netId == 0 then
        DeleteEntity(ped)
        answer(0, 'failed')
        return
    end
    answer(netId, 'ok')
end)

-- RedM (spur_core, 24 Nov 2026): a vehicle the server asked for, made here. The server's own CreateVehicle gives a wagon
-- no harness to fill (RDR2 expects 0 draft animals), so the server asks this game instead (server/rdr_entities.lua,
-- askVehicle). RDR2's CreateVehicle takes two more arguments than the original game's: bDontAutoCreateDraftAnimals false puts the
-- wagon's own animals in its harness. client/draft_animals.lua tells the server of them, and fills an empty harness.
local DRAFT_ANIMAL_COUNT = 0xA19447D83294E29F   -- GET_DRAFT_ANIMAL_COUNT (vehicle, int* expected, int* actual)
local IS_DRAFT_VEHICLE   = 0xEA44E97849E9F3DD

RegisterNetEvent('spur_core:client:rdrMakeVehicle', function(nonce, hash, x, y, z, heading)
    if type(nonce) ~= 'number' or type(hash) ~= 'number' then return end
    local function answer(netId, why)
        TriggerServerEvent('spur_core:server:rdrVehicleMade', nonce, netId or 0, why)
    end
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then answer(0, 'model') return end
    local loaded, why = LoadModel(hash)
    if not loaded then answer(0, why == 'missing' and 'model' or 'failed') return end
    -- isNetwork, bScriptHostVeh, bDontAutoCreateDraftAnimals, p8
    local veh = CreateVehicle(hash, x + 0.0, y + 0.0, z + 0.0, heading + 0.0, true, true, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not veh or veh == 0 or not DoesEntityExist(veh) then answer(0, 'failed') return end
    SetEntityAsMissionEntity(veh, true, true)
    local deadline = GetGameTimer() + NET_MS
    while not NetworkGetEntityIsNetworked(veh) and GetGameTimer() < deadline do Wait(0) end
    local netId = NetworkGetEntityIsNetworked(veh) and NetworkGetNetworkIdFromEntity(veh) or 0
    if not netId or netId == 0 then
        DeleteEntity(veh)
        answer(0, 'failed')
        return
    end
    answer(netId, 'ok')
    -- F8: whether RDR2 put the animals in (once at once, and after 3 s).
    local draft = Citizen.InvokeNative(IS_DRAFT_VEHICLE, veh, Citizen.ResultAsInteger())
    if draft and draft ~= 0 then
        local function count()
            local _, expected, actual = Citizen.InvokeNative(DRAFT_ANIMAL_COUNT, veh, Citizen.PointerValueInt(),
                Citizen.PointerValueInt(), Citizen.ReturnResultAnyway())
            return ('%s/%s'):format(tostring(actual), tostring(expected))
        end
        local now = count()
        Wait(3000)
        if DoesEntityExist(veh) then
            print(('[spur_core] RedM: made a wagon for the server (netId %d): draft animals %s at once, %s after 3 s')
                :format(netId, now, count()))
        end
    end
end)
