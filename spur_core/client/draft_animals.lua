-- ============================================
-- Draft animals: horses in the harness of spur_core's wagons
-- RedM (spur_core, 24 Nov 2026)
-- ============================================
--
-- The server makes a car with CreateVehicle, an RPC: the nearest game makes the wagon. On current RedM servers that
-- wagon comes with an empty harness, so nothing pulls it and it can't move (spur_core CONVERSION.md, Server-made
-- entities). The game that runs one of spur_core's wagons (it has a spurPlate) fills its harness once:
--
--   1. RDR2 is asked to make the wagon's animals itself (_SET_DRAFT_VEHICLE_ALLOW_DRAFT_ANIMAL_AUTO_CREATION);
--   2. if the harness is still empty after a moment, this game makes a draft horse for each empty place and puts it
--      there (_ATTACH_DRAFT_VEHICLE_HARNESS_PED), and tells the server, which deletes them once the wagon is gone
--      (server/draft_animals.lua).
--
-- Once only, for every game: the spurDraft state bag says it was done, so horses shot or cut loose later stay gone.
-- F8 says which way each wagon was filled.

local N = Citizen.InvokeNative

local IS_DRAFT_VEHICLE     = 0xEA44E97849E9F3DD
local ALLOW_AUTO_CREATION  = 0x87344305778E5415   -- _SET_DRAFT_VEHICLE_ALLOW_DRAFT_ANIMAL_AUTO_CREATION
local NUM_HARNESS          = 0x5B1A26BB18E7D451   -- _GET_NUM_DRAFT_VEHICLE_HARNESS_PED (model)
local PED_IN_HARNESS       = 0xA8BA0BAE0173457B   -- _GET_PED_IN_DRAFT_HARNESS
local ATTACH_HARNESS_PED   = 0x316CDB5B6E8F4110   -- _ATTACH_DRAFT_VEHICLE_HARNESS_PED
local DRAFT_ANIMAL_COUNT   = 0xA19447D83294E29F   -- GET_DRAFT_ANIMAL_COUNT (vehicle, int* expected, int* actual)
local HARNESS_COUNT        = 6                    -- eDraftHarness: LR, RR, LM, RM, LF, RF

local DRAFT_KEY = 'spurDraft'
local AUTO_WAIT_MS = 6000   -- RedM (spur_core, 24 Nov 2026): the game took longer than 2.5 s once

--- The draft horses this game makes, one model per wagon.
local HORSES = { 'a_c_horse_shire_darkbay', 'a_c_horse_belgian_blondchestnut', 'a_c_horse_suffolkpunch_sorrel' }

local handled = {}   -- entity -> true: this game's own note (the state bag is everyone's)

local function isDraft(veh)
    local r = N(IS_DRAFT_VEHICLE, veh, Citizen.ResultAsInteger())
    return r ~= nil and r ~= 0 and r ~= false
end

--- The harness places of this wagon that nobody stands in, and how many it has.
local function emptyPlaces(veh)
    local places = N(NUM_HARNESS, GetEntityModel(veh), Citizen.ResultAsInteger()) or 0
    local empty = {}
    for i = 0, places - 1 do
        local p = N(PED_IN_HARNESS, veh, i, Citizen.ResultAsInteger())
        if not p or p == 0 then empty[#empty + 1] = i end
    end
    return empty, places
end

--- What the game itself counts: animals expected in this wagon's harness, and those there (F8 notes).
local function animalCount(veh)
    local ok, expected, actual = N(DRAFT_ANIMAL_COUNT, veh, Citizen.PointerValueInt(), Citizen.PointerValueInt(),
        Citizen.ReturnResultAnyway())
    return ('%s/%s'):format(tostring(actual), tostring(expected))
end

local function truthy(r) return r ~= nil and r ~= 0 and r ~= false end

--- RedM (spur_core, 24 Nov 2026): the animals RDR2 put in the harness itself (a wagon made by a player's game,
--- server/rdr_entities.lua) are told to the server too, so it keeps them with the wagon and deletes them after it.
local function tellHarness(veh, places)
    local nets, filled
    local deadline = GetGameTimer() + 3000   -- the game's animals can reach the network a moment after the wagon
    repeat
        nets, filled = {}, 0
        for i = 0, places - 1 do
            local p = N(PED_IN_HARNESS, veh, i, Citizen.ResultAsInteger())
            if p and p ~= 0 and DoesEntityExist(p) then
                filled = filled + 1
                if NetworkGetEntityIsNetworked(p) then
                    local net = NetworkGetNetworkIdFromEntity(p)
                    if net and net ~= 0 then nets[#nets + 1] = net end
                end
            end
        end
        if #nets >= filled or GetGameTimer() >= deadline or not DoesEntityExist(veh) then break end
        Wait(250)
    until false
    if #nets > 0 and DoesEntityExist(veh) then TriggerServerEvent('spur_core:server:draftHorses', NetworkGetNetworkIdFromEntity(veh), nets) end
    return #nets, filled   -- RedM (spur_core, 24 Nov 2026): and how many stand in it, for F8
end

--- RedM (spur_core, 24 Nov 2026): the wagon's model for F8 (RedM's GetEntityArchetypeName can answer nothing).
local function modelName(veh)
    local n = GetEntityArchetypeName and GetEntityArchetypeName(veh) or ''
    if n == nil or n == '' then n = tostring(GetEntityModel(veh)) end
    return n
end

--- A horse just made exists on this game a moment later, and on the network a moment after that.
local function settle(ent)
    local t = GetGameTimer() + 1500
    while GetGameTimer() < t and not (DoesEntityExist(ent) and NetworkGetEntityIsNetworked(ent)) do Wait(50) end
    Wait(250)
    return DoesEntityExist(ent)
end

--- Put a horse in the harness: its own place first, then any other free one. Returns the place it went to or nil,
--- and what each try answered (F8).
local function harness(horse, veh, place)
    local tries = {}
    local order = { place }
    for i = 0, HARNESS_COUNT - 1 do
        if i ~= place then order[#order + 1] = i end
    end
    for _, i in ipairs(order) do
        local inIt = N(PED_IN_HARNESS, veh, i, Citizen.ResultAsInteger())
        if not inIt or inIt == 0 then
            local r = N(ATTACH_HARNESS_PED, horse, veh, i, Citizen.ResultAsInteger())
            Wait(0)
            local now = N(PED_IN_HARNESS, veh, i, Citizen.ResultAsInteger())
            tries[#tries + 1] = ('%d:%s%s'):format(i, tostring(r), now == horse and '+' or '')
            if truthy(r) or now == horse then return i, table.concat(tries, ' ') end
        end
    end
    return nil, table.concat(tries, ' ')
end

local function loadModel(hash)
    if not IsModelInCdimage(hash) then return false end
    RequestModel(hash)
    local t = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < t do Wait(50) end
    return HasModelLoaded(hash)
end

local function fill(veh)
    local st = Entity(veh).state
    st:set(DRAFT_KEY, true, true)

    local empty, places = emptyPlaces(veh)
    if places == 0 then return end
    if #empty == 0 then   -- RedM (spur_core, 24 Nov 2026): it came with them (made by a player's game)
        local told, standing = tellHarness(veh, places)
        print(('[spur_core] RedM: a wagon (%s) came with its draft animals (game counts %s); %d in the harness, %d on '
            .. 'the network and told to the server'):format(modelName(veh), animalCount(veh), standing, told))
        return
    end
    print(('[spur_core] RedM: a wagon with %d harness place(s), %d empty (game counts %s)')
        :format(places, #empty, animalCount(veh)))
    local wanted = #empty

    -- 1. The game's own animals.
    N(ALLOW_AUTO_CREATION, veh, true)
    local t = GetGameTimer() + AUTO_WAIT_MS
    while #empty > 0 and GetGameTimer() < t do
        Wait(250)
        if not DoesEntityExist(veh) then return end
        empty = emptyPlaces(veh)
    end
    if #empty < wanted then
        print(('[spur_core] RedM: a wagon (%s) has its draft animals, made by the game (%d of %d places)')
            :format(GetEntityArchetypeName and GetEntityArchetypeName(veh) or tostring(GetEntityModel(veh)), places - #empty, places))
        tellHarness(veh, places)   -- RedM (spur_core, 24 Nov 2026): kept with the wagon, deleted after it
        return
    end

    -- 2. Horses made here, one in each empty place.
    local name = HORSES[(math.abs(NetworkGetNetworkIdFromEntity(veh)) % #HORSES) + 1]
    local model = GetHashKey(name)
    if not loadModel(model) then
        print('[spur_core] RedM: no draft horse model ' .. name .. '; the wagon stays without horses')
        return
    end
    local made, attached, notes = {}, 0, {}
    local peds = {}   -- every horse made here, networked yet or not
    local heading = GetEntityHeading(veh)
    for n, place in ipairs(empty) do
        if not DoesEntityExist(veh) then break end
        local c = GetOffsetFromEntityInWorldCoords(veh, 0.0, 3.0 + n * 1.5, 0.0)
        local horse = CreatePed(4, model, c.x, c.y, c.z, heading, true, true)
        if horse and horse ~= 0 then peds[#peds + 1] = horse end
        if horse and horse ~= 0 and settle(horse) then
            SetEntityAsMissionEntity(horse, true, true)
            local at, tried = harness(horse, veh, place)
            notes[#notes + 1] = tried
            if at then
                attached = attached + 1
                local net = NetworkGetNetworkIdFromEntity(horse)
                if net and net ~= 0 then made[#made + 1] = net end
            else
                -- RedM (spur_core, 24 Nov 2026): RDR2 wouldn't take it in the harness (a wagon the server made has a harness no
                -- horse goes in), and a loose horse by the wagon is no use: one was left standing at each join.
                DeleteEntity(horse)
            end
        end
    end
    SetModelAsNoLongerNeeded(model)
    -- RedM (spur_core, 24 Nov 2026): the wagon can go while its horses are made (a Director test takes its car away
    -- after a few seconds). The server then refuses them (no wagon to belong to), and they were left standing where the
    -- next car is made. Horses for a wagon that is gone go here.
    if not DoesEntityExist(veh) then
        for _, horse in ipairs(peds) do
            if DoesEntityExist(horse) then
                SetEntityAsMissionEntity(horse, true, true)
                DeleteEntity(horse)
            end
        end
        print(('[spur_core] RedM: a wagon went while its %d draft horse(s) were made; they were taken away'):format(#peds))
        return
    end
    if #made > 0 then
        TriggerServerEvent('spur_core:server:draftHorses', NetworkGetNetworkIdFromEntity(veh), made)
    end
    Wait(500)
    local still = emptyPlaces(veh)
    print(('[spur_core] RedM: a wagon had no draft animals; %d %s made here, %d attached, %d place(s) still empty '
        .. '(game counts %s; tries %s)'):format(#made, name, attached, #still, animalCount(veh), table.concat(notes, ' | ')))
end

CreateThread(function()
    while true do
        Wait(1000)
        for _, veh in ipairs(GetGamePool('CVehicle')) do
            if not handled[veh] and DoesEntityExist(veh) and NetworkGetEntityIsNetworked(veh)
                and NetworkHasControlOfEntity(veh) then
                local st = Entity(veh).state
                if st.spurPlate ~= nil and not st[DRAFT_KEY] and isDraft(veh) then
                    handled[veh] = true
                    local ok, err = pcall(fill, veh)
                    if not ok then print('[spur_core] RedM: filling a wagon\'s harness failed: ' .. tostring(err)) end
                end
            end
        end
        for veh in pairs(handled) do
            if not DoesEntityExist(veh) then handled[veh] = nil end
        end
    end
end)
