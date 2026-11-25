-- RedM (spur_phone, 25 Nov 2026): new. A telegram that goes off sends a pigeon up with it.
--
-- RDR2 has no "let a bird go" animation (femga's rdr3_discoveries lists were searched for one), so this is put
-- together from parts the game does have:
--   the player   script_mp@naturalist@spirit_animal_herbs / toss_herbs_01 (takes something from the satchel, holds it
--                in both hands, lets it go)
--   the pigeon   a_c_pigeon, held in mech_skin@small_pickup@pigeon / base (the pose of a small bird in a hand),
--                fixed to the right hand, then let loose with TASK_FLY_AWAY and removed once it is far off
-- The bird is a networked ped, so players standing near see it too. Nothing is taken from the player and nothing
-- depends on it: where a bird cannot be made, the telegram has gone all the same.
--
-- Config.Pigeon (config.lua) turns it off or changes the bird. Other resources: exports.spur_phone:ReleasePigeon().
-- whip_phone has nothing like it. Non-commercial, LGPL-3.0, with thanks to Whippy and WLVF for the phone it sits in.

local N = Citizen.InvokeNative

local PLAYER_DICT, PLAYER_CLIP = 'script_mp@naturalist@spirit_animal_herbs', 'toss_herbs_01'
local BIRD_DICT, BIRD_CLIP = 'mech_skin@small_pickup@pigeon', 'base'
local SHOW_AT = 1500      -- ms: the hands are out of the satchel
local RELEASE_AT = 4300   -- ms: the hands open
local STOP_AT = 5600      -- ms: the rest of the clip is brushing the hands off
local FLY_FOR = 12000     -- ms the bird is left to fly before it is removed (about 60 m away by then)

local busy = false
local held          -- the bird, while there is one

local function setting()
    local c = Config.Pigeon
    if c == false then return nil end
    if type(c) ~= 'table' then c = {} end
    if c.enabled == false then return nil end
    return c
end

local function load(kind, name, ms)
    local has = kind == 'model' and HasModelLoaded or HasAnimDictLoaded
    if kind == 'model' then RequestModel(name) else RequestAnimDict(name) end
    local t = GetGameTimer()
    while not has(name) do
        if GetGameTimer() - t > ms then return false end
        Wait(20)
    end
    return true
end

--- Play it. Returns false where it does not suit (riding, driving, down, already playing) or a part is missing.
local function release()
    local cfg = setting()
    if not cfg or busy then return false end
    local me = PlayerPedId()
    if IsEntityDead(me) or IsPedOnMount(me) or IsPedInAnyVehicle(me, true) or IsPedSwimming(me) or IsPedFalling(me)
        or IsPedRagdoll(me) then
        return false
    end
    local model = GetHashKey(cfg.model or 'a_c_pigeon')
    if not IsModelValid(model) or not DoesAnimDictExist(PLAYER_DICT) or not DoesAnimDictExist(BIRD_DICT) then return false end
    busy = true
    CreateThread(function()
        local bird
        local ok, err = pcall(function()
            if not (load('model', model, 5000) and load('dict', PLAYER_DICT, 5000) and load('dict', BIRD_DICT, 5000)) then return end
            local c = GetEntityCoords(me)
            bird = N(0xD49F9B0955C367DE, model, c.x, c.y, c.z + 0.5, GetEntityHeading(me), true, false, false, false,
                Citizen.ResultAsInteger())                                                      -- CREATE_PED
            if not bird or bird == 0 then bird = nil return end
            held = bird
            N(0x283978A15512B2FE, bird, true)                                                   -- _SET_RANDOM_OUTFIT_VARIATION
            SetEntityInvincible(bird, true)
            SetBlockingOfNonTemporaryEvents(bird, true)
            SetEntityVisible(bird, false)
            AttachEntityToEntity(bird, me, GetEntityBoneIndexByName(me, 'SKEL_R_Hand'), 0.10, 0.02, -0.06, 0.0, 0.0, 0.0,
                false, false, false, false, 2, true, false, false)
            TaskPlayAnim(bird, BIRD_DICT, BIRD_CLIP, 8.0, -8.0, -1, 1, 0.0, false, false, false)
            TaskPlayAnim(me, PLAYER_DICT, PLAYER_CLIP, 4.0, -4.0, -1, 0, 0.0, false, false, false)
            local t0 = GetGameTimer()
            local shown, let = false, false
            while GetGameTimer() - t0 < STOP_AT do
                Wait(50)
                local t = GetGameTimer() - t0
                -- knocked down, shot or pulled away mid-way: the bird goes at once
                local broken = t > 400 and not IsEntityPlayingAnim(me, PLAYER_DICT, PLAYER_CLIP, 3)
                if not shown and (t >= SHOW_AT or broken) then SetEntityVisible(bird, true) shown = true end
                if not let and (t >= RELEASE_AT or broken) then
                    let = true
                    DetachEntity(bird, true, true)
                    ClearPedTasksImmediately(bird)
                    N(0xE86A537B5A3C297C, bird, me)                                             -- TASK_FLY_AWAY
                end
                if broken then break end
            end
            if IsEntityPlayingAnim(me, PLAYER_DICT, PLAYER_CLIP, 3) then StopAnimTask(me, PLAYER_DICT, PLAYER_CLIP, 2.0) end
            Wait(FLY_FOR)
        end)
        if bird and DoesEntityExist(bird) then DeleteEntity(bird) end
        held = nil
        SetModelAsNoLongerNeeded(model)
        RemoveAnimDict(PLAYER_DICT)
        RemoveAnimDict(BIRD_DICT)
        busy = false
        if not ok and Config.Debug then print('[spur_phone] pigeon: ' .. tostring(err)) end
    end)
    return true
end

RegisterNetEvent('spur_phone:client:pigeon', function() release() end)
exports('ReleasePigeon', release)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    -- a bird in the hand when the resource stops would stay there
    if held and DoesEntityExist(held) then DeleteEntity(held) end
    local me = PlayerPedId()
    if IsEntityPlayingAnim(me, PLAYER_DICT, PLAYER_CLIP, 3) then StopAnimTask(me, PLAYER_DICT, PLAYER_CLIP, 2.0) end
end)
