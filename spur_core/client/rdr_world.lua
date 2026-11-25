-- ============================================
-- RDR2'S WORLD, ON WHIP'S PROMPTS — client/rdr_world.lua
-- ============================================
--
-- RedM (spur_core, 25 Nov 2026). New with the port: whip_core (by Whippy and WLVF) has no such file, because GTA has
-- nothing to replace. client/rdr_interactions.lua switches RDR2's own interactions off (the lock-on's Greet and
-- Antagonize, Loot, Pick Up, the hat); this file gives the same things back as whip prompts (client/actions.lua), on
-- E, where the player looks:
--
--   a townsperson       Greet, Antagonize                 (Config.RdrWorld.people)
--   a body              Search (once; the server decides what it gives), Pick up
--   an animal's carcass Pick up                           (Config.RdrWorld.carry)
--   while carrying      Put down (looking at the ground), Put on horse (looking at one)
--   the player's hat    Put on, where it fell             (Config.RdrWorld.hat)
--
-- The work itself is RDR2's: its loot, carry and hat tasks, and its speech. What a search gives is whip's
-- (server/rdr_world.lua). Only the game's own people and animals: a ped a script made (a Director NPC, a shop keeper)
-- has whip's prompts already, and a player is never offered here.

RdrWorld = {}

local function cfg() return type(Config.RdrWorld) == 'table' and Config.RdrWorld or {} end
local function on(what) return cfg()[what] ~= false end

--- RedM's BOOL natives can answer a number, and 0 is true in Lua.
local function yes(v) return v == true or (type(v) == 'number' and v ~= 0) end

local TASK_LOOT_ENTITY          = 0x48FAE038401A2888
local TASK_PICKUP_CARRIABLE     = 0x502EC17B1BED4BFA
local IS_PED_CARRYING_SOMETHING = 0xA911EE21EDF69DAF
local GET_LAST_DROPPED_HAT      = 0x1F714E7A9DADFC42
local IS_PED_HUMAN              = 0xB980061DA992779D
local SET_LOOTING_FLAG          = 0x6569F31A01B4C097
local PLAY_PED_AMBIENT_SPEECH   = 0x8E04FEDD28D42462
local VAR_STRING                = 0xFA925AC00EB830B9

local SET_PLAYER_CAN_PICKUP     = 0xD1A70C1E8D1031FE
local TASK_PLAY_EMOTE_WITH_HASH = 0xB31A277C1AC7B7FF
local DOES_CONTEXT_EXIST        = 0x49B99BF3FDA89A7A

-- Until this game time RDR2's own pick-up is wanted on: a pick-up task this file starts needs it from its first
-- frame (tried in game: with it off the task hangs), before the ped carries anything.
local pickingUntil = 0

-- Until this game time the carried thing is being let go: RDR2's pick-up is taken away, and the game drops what
-- the ped carries at once (tried in game: 60 to 80 ms).
local dropUntil = 0

local function carryingNow()
    return yes(Citizen.InvokeNative(IS_PED_CARRYING_SOMETHING, PlayerPedId()))
end

--- Is the player's own ped carrying something, or picking it up? client/rdr_interactions.lua gives RDR2's pick-up
--- back for as long: with it off the game drops the carried thing. (RDR2 drew a Drop of its own once in three
--- game sessions and never a Stow, so putting down is a whip prompt too: below.)
function RdrWorld.carrying()
    local now = GetGameTimer()
    if now < dropUntil then return false end
    return now < pickingUntil or carryingNow()
end

--- RDR2's own pick-up on from now, for `ms` at least.
local function wantPickup(ms)
    pickingUntil = GetGameTimer() + ms
    Citizen.InvokeNative(SET_PLAYER_CAN_PICKUP, PlayerId(), true)
end

-- While set, client/rdr_interactions.lua leaves the player's looting switches alone (a search under way).
RdrWorld.looting = false

--- One of the game's own people or animals: not a player, not a ped a script made, not the player's mount.
local function ambient(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) or GetEntityType(ped) ~= 1 then return false end
    if ped == PlayerPedId() or IsPedAPlayer(ped) then return false end
    if yes(IsEntityAMissionEntity(ped)) then return false end
    return true
end

local function human(ped) return yes(Citizen.InvokeNative(IS_PED_HUMAN, ped)) end
local function dead(ped) return yes(IsEntityDead(ped)) end

local searchedHere = {}   -- [ped] = true: searched from this game

local function searched(ped)
    if searchedHere[ped] then return true end
    local ok, v = pcall(function() return Entity(ped).state.spurSearched end)
    return ok and v == true
end

-- ── Speech ────────────────────────────────────────────────────────────────────────────────────────────────────────
-- PLAY_PED_AMBIENT_SPEECH_NATIVE takes a struct on RDR2: the line, the voice (0: the ped's own), a variation, the
-- way it is said, who hears it, and three flags.

local function varString(s)
    return Citizen.InvokeNative(VAR_STRING, 10, 'LITERAL_STRING', s, Citizen.ResultAsLong())
end

--- `ped` says `line` (a speech name of its own voice). False when the game has no such line for that voice. Tried in
--- game: a townsperson says it; the player's own ped (the multiplayer model) has no voice and says nothing.
function RdrWorld.say(ped, line, listener)
    if not yes(Citizen.InvokeNative(DOES_CONTEXT_EXIST, ped, line, false)) then return false end
    local params = cfg().speechParams or 'SPEECH_PARAMS_BEAT_SHOUTED_CLEAR'
    local struct = string.pack('<i8i8i8i8i8i8i8i8', varString(line), 0, 0, GetHashKey(params) & 0xFFFFFFFF,
        listener or 0, 1, 1, 1)
    return yes(Citizen.InvokeNative(PLAY_PED_AMBIENT_SPEECH, ped, struct))
end

--- The first of `lines` the ped's voice has.
local function sayAny(ped, lines, listener)
    for _, line in ipairs(lines) do
        if RdrWorld.say(ped, line, listener) then return true end
    end
    return false
end

local function speak(kind, target)
    local me = PlayerPedId()
    local lines = type(cfg().Speech) == 'table' and cfg().Speech[kind] or nil
    if type(lines) ~= 'table' then return end
    TaskLookAtEntity(me, target, 2500, 0, 51, 0)
    -- The player has no voice, so theirs is a gesture: one of RDR2's own emotes.
    local emote = lines.emote
    -- Not while carrying: a greeting with a body on the shoulder dropped it, one time in two.
    if type(emote) == 'table' and emote.name and not carryingNow() then
        pcall(Citizen.InvokeNative, TASK_PLAY_EMOTE_WITH_HASH, me, tonumber(emote.type) or 3,
            tonumber(emote.mode) or 0, GetHashKey(emote.name), true, true, false, false, false)
    end
    SetTimeout(900, function()
        if DoesEntityExist(target) and not dead(target) then
            TaskLookAtEntity(target, PlayerPedId(), 3000, 0, 51, 0)
            sayAny(target, lines.reply or {}, PlayerPedId())
        end
    end)
end

-- ── Search, carry, hat ────────────────────────────────────────────────────────────────────────────────────────────

local busy = false

local function search(ctx)
    local body = ctx.entity
    if busy or not ambient(body) or not dead(body) or searched(body) then return end
    busy = true
    searchedHere[body] = true
    local me = PlayerPedId()
    -- RDR2's own looting is off for the player (client/rdr_interactions.lua): given back for this one task.
    RdrWorld.looting = true
    Citizen.InvokeNative(SET_LOOTING_FLAG, me, 2, true)
    Citizen.InvokeNative(SET_LOOTING_FLAG, me, 3, true)
    Citizen.InvokeNative(SET_LOOTING_FLAG, me, 18, false)
    -- Tried in game: the loot plays where the player stands, with no walk over, so they are turned to the body first.
    Citizen.InvokeNative(0x5AD23D40115353AC, me, body, 600, 0.0, 0.0, 0.0)   -- TASK_TURN_PED_TO_FACE_ENTITY
    Wait(600)
    Citizen.InvokeNative(TASK_LOOT_ENTITY, me, body)
    local netId = NetworkGetEntityIsNetworked(body) and NetworkGetNetworkIdFromEntity(body) or nil
    local untilAt = GetGameTimer() + (tonumber(cfg().searchMs) or 3000)
    while GetGameTimer() < untilAt and DoesEntityExist(body) do
        if #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(body)) > 6.0 then netId = nil; break end
        Wait(100)
    end
    RdrWorld.looting = false
    busy = false
    if netId then
        TriggerServerEvent('spur_core:server:rdrSearchBody', netId)
    elseif DoesEntityExist(body) and not NetworkGetEntityIsNetworked(body) then
        UI.Notify('Nothing on them', 'info', 2500)   -- a body only this game has: nothing the server can count
    else
        searchedHere[body] = nil
    end
end

RegisterNetEvent('spur_core:client:rdrSearched', function(_, found)
    if type(found) ~= 'table' or #found == 0 then
        UI.Notify('Nothing on them', 'info', 2500)
        return
    end
    local parts = {}
    for _, f in ipairs(found) do
        if f.item == 'cash' then
            parts[#parts + 1] = ('$%d'):format(f.amount)
        else
            parts[#parts + 1] = ('%s x%d'):format(tostring(f.name or f.item), f.amount)
        end
    end
    UI.Notify('Found ' .. table.concat(parts, ', '), 'success', 3500)
end)

local function carry(ctx)
    local what = ctx.entity
    if not ambient(what) or not dead(what) or RdrWorld.carrying() then return end
    wantPickup(10000)   -- a second lift of the same body took 5.1 s when tried
    Citizen.InvokeNative(TASK_PICKUP_CARRIABLE, PlayerPedId(), what)
    UI.Notify('Look at the ground and press your interact key to put it down', 'info', 5000)
end

local GET_CARRIED          = 0xD806CD2A4F2C2996   -- _GET_FIRST_ENTITY_PED_IS_CARRYING
local TASK_PLACE_AT_COORD  = 0xC7F0B43DCDC57E3D   -- TASK_PLACE_CARRIED_ENTITY_AT_COORD
local TASK_PLACE_ON_MOUNT  = 0x6D3D87C57B3D52C7   -- TASK_PLACE_CARRIED_ENTITY_ON_MOUNT
local IS_MODEL_A_HORSE     = 0x772A1969F649E902

local function horse(ped)
    return ped and ped ~= 0 and DoesEntityExist(ped) and GetEntityType(ped) == 1
        and yes(Citizen.InvokeNative(IS_MODEL_A_HORSE, GetEntityModel(ped))) and not dead(ped)
end

--- Wait until the ped carries nothing, `ms` at most. True when it let go.
local function waitDropped(ms)
    local untilAt = GetGameTimer() + ms
    while GetGameTimer() < untilAt do
        if not carryingNow() then return true end
        Wait(100)
    end
    return not carryingNow()
end

--- Let go at once: RDR2's pick-up off for a moment, and the game drops the thing at the player's feet.
local function letGo()
    pickingUntil = 0
    dropUntil = GetGameTimer() + 1500
    Citizen.InvokeNative(SET_PLAYER_CAN_PICKUP, PlayerId(), false)
end

local function putDown(ctx)
    if busy or not carryingNow() then return end
    busy = true
    local me = PlayerPedId()
    local what = Citizen.InvokeNative(GET_CARRIED, me)
    local at = GetOffsetFromEntityInWorldCoords(me, 0.0, 0.9, -0.9)
    if ctx and ctx.world == true and ctx.coords and #(vector3(ctx.coords.x, ctx.coords.y, ctx.coords.z) - GetEntityCoords(me)) < 2.5 then
        at = ctx.coords
    end
    if what and what ~= 0 and DoesEntityExist(what) then
        Citizen.InvokeNative(TASK_PLACE_AT_COORD, me, what, at.x, at.y, at.z, 0.0, 0)
    end
    if not waitDropped(5000) then letGo() end   -- RDR2's own put-down took 3.1 s when tried
    busy = false
end

--- A living, riderless horse right in front of the player (within 2.5 m, and faced), or nil. Not by the look:
--- whip's look ray for people does not meet a horse (tried in game), the map behind it is what it finds.
local function horseAhead()
    local me = PlayerPedId()
    local at, fwd = GetEntityCoords(me), GetEntityForwardVector(me)
    local best, bestD = nil, 2.5
    for _, ped in ipairs(GetGamePool('CPed')) do
        if ped ~= me and horse(ped) then
            local to = GetEntityCoords(ped) - at
            local d = #to
            -- A networked horse only (tried in game: the task gave up on a horse this game alone had; a saddle
            -- made no difference)
            if d < bestD and d > 0.01 and (to.x * fwd.x + to.y * fwd.y) / d > 0.5
                and NetworkGetEntityIsNetworked(ped)
                and (Citizen.InvokeNative(0xB676EFDA03DADA52, ped, true) or 0) == 0 then   -- _GET_RIDER_OF_MOUNT: nobody on it
                best, bestD = ped, d
            end
        end
    end
    return best
end

local function putOnHorse()
    local mount = horseAhead()
    if busy or not carryingNow() or not horse(mount) then return end
    busy = true
    local me = PlayerPedId()
    local what = Citizen.InvokeNative(GET_CARRIED, me)
    if what and what ~= 0 and DoesEntityExist(what) then
        Citizen.InvokeNative(TASK_PLACE_ON_MOUNT, me, what, mount, 0.0)
        if not waitDropped(8000) then
            ClearPedTasks(me)
            UI.Notify('That will not go on the horse', 'error', 3000)
        end
    end
    busy = false
end

-- The hat the player wears, as its shop item: read while it is worn, because the prop lying on the ground does not
-- say which hat it was. RDR2's own hat pick-up and _TASK_EQUIP_HAT both did nothing when tried in game (twice, both
-- argument orders), so the hat is put back on as clothing and the prop removed.
local HAT_CATEGORY = 0x9925C067
local wornHat = nil

local function readWornHat()
    local me = PlayerPedId()
    if not yes(Citizen.InvokeNative(0xFB4891BD7578CDC1, me, HAT_CATEGORY)) then return nil end   -- _IS_METAPED_USING_COMPONENT
    local n = Citizen.InvokeNative(0x90403E8107B60E81, me) or 0                                  -- _GET_NUM_COMPONENTS_IN_PED
    local kind = IsPedMale(me) and 0 or 1
    for i = 0, (tonumber(n) or 0) - 1 do
        local item = Citizen.InvokeNative(0x77BA37622E22023B, me, i, true, Citizen.PointerValueInt(),
            Citizen.PointerValueInt(), Citizen.ResultAsInteger())                                -- _GET_SHOP_ITEM_COMPONENT_AT_INDEX
        if type(item) == 'number' and item ~= 0 then
            local cat = Citizen.InvokeNative(0x5FF9A878C3D115B8, item, kind, true, Citizen.ResultAsInteger())
            if type(cat) == 'number' and (cat & 0xFFFFFFFF) == HAT_CATEGORY then return item end
        end
    end
    return nil
end

--- For a test, and for anyone asking: the hat last seen worn (its shop item hash), or nil.
function RdrWorld.wornHat() return wornHat end

local function putHatOn(hat)
    if not wornHat or not DoesEntityExist(hat) then return end
    local me = PlayerPedId()
    TaskTurnPedToFaceEntity(me, hat, 500)
    Wait(500)
    Citizen.InvokeNative(0xD3A7B003ED343FD9, me, wornHat, true, true, true)          -- _APPLY_SHOP_ITEM_TO_PED
    Citizen.InvokeNative(0xCC8CA3E88256E58F, me, false, true, true, true, false)     -- _UPDATE_PED_VARIATION
    if DoesEntityExist(hat) then
        SetEntityAsMissionEntity(hat, true, true)
        DeleteEntity(hat)
    end
end

--- The player's hat where it fell, or nil.
local function droppedHat()
    local hat = Citizen.InvokeNative(GET_LAST_DROPPED_HAT, PlayerPedId())
    if not hat or hat == 0 or not DoesEntityExist(hat) or IsEntityAttached(hat) then return nil end
    return hat
end

-- ── The prompts ───────────────────────────────────────────────────────────────────────────────────────────────────

local function alivePerson(ctx)
    local p = ctx.entity
    return on('people') and ambient(p) and human(p) and not dead(p) and not IsPedInAnyVehicle(p, false)
end

AddEventHandler('spur_core:onReady', function()
    local me = GetCurrentResourceName()
    if cfg().enabled == false then return end

    Actions.add(me, {
        id    = 'rdr_person',
        at    = { aimBox = 'ped' },
        label = 'Stranger',
        icon  = 'talk',
        reach = 3.0,
        canInteract = alivePerson,
        options = {
            { id = 'greet', label = 'Greet', icon = 'talk',
              onSelect = function(ctx) speak('greet', ctx.entity) end },
            { id = 'antagonize', label = 'Antagonize', icon = 'chat',
              onSelect = function(ctx) speak('antagonize', ctx.entity) end },
        },
    })

    -- RDR2 draws no Drop or Stow for what this file had the player lift (tried in game), so both are whip's.
    Actions.add(me, {
        id    = 'rdr_carry',
        at    = { aimBox = { 'world', 'ped' } },
        label = 'Carrying',
        icon  = 'pickup',
        reach = 4.0,
        -- Whatever the look meets: the ground, a horse, or the carried thing itself (it hangs in the look).
        canInteract = function(ctx)
            if busy or not on('carry') or not carryingNow() then return false end
            -- Not on someone else: a townsperson keeps their own prompt (Greet) while the player carries.
            return ctx.world == true or ctx.entity == Citizen.InvokeNative(GET_CARRIED, PlayerPedId())
        end,
        options = {
            { id = 'stow', label = 'Put on horse', icon = 'give',
              canInteract = function() return horseAhead() ~= nil and not IsPedOnMount(PlayerPedId()) end,
              onSelect = putOnHorse },
            { id = 'down', label = 'Put down', icon = 'pickup',
              onSelect = putDown },
        },
    })

    Actions.add(me, {
        id    = 'rdr_body',
        at    = { aimBox = 'ped' },
        label = 'Body',
        icon  = 'pickup',
        reach = 2.3,   -- the prompt sits on the body's far side: 1.6 only caught it from under a metre
        canInteract = function(ctx)
            local p = ctx.entity
            return ambient(p) and dead(p) and not busy and not RdrWorld.carrying()
        end,
        options = {
            { id = 'search', label = 'Search', icon = 'give', holdMs = 800,
              canInteract = function(ctx)
                  return on('search') and human(ctx.entity) and not searched(ctx.entity)
              end,
              onSelect = search },
            { id = 'carry', label = 'Pick up', icon = 'pickup',
              canInteract = function() return on('carry') end,
              onSelect = carry },
        },
    })
end)

-- The hat: a prompt riding on it while it lies where it fell.
CreateThread(function()
    local shown = nil
    while true do
        Wait(1000)
        local okHat, item = pcall(readWornHat)
        if okHat and item then wornHat = item end
        local hat = (cfg().enabled ~= false and on('hat') and wornHat) and droppedHat() or nil
        if hat ~= shown then
            if shown then Actions.remove(GetCurrentResourceName(), 'rdr_hat') end
            shown = hat
            if hat then
                Actions.add(GetCurrentResourceName(), {
                    id    = 'rdr_hat',
                    at    = { entity = hat },
                    label = 'Put on hat',
                    icon  = 'pickup',
                    reach = 2.0,
                    onSelect = function() putHatOn(hat) end,
                })
            end
        end
    end
end)
