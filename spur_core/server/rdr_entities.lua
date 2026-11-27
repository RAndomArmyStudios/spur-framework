-- ============================================
-- RDR ENTITIES — making world things from the server on RedM
-- ============================================
--
-- RedM (spur_core, 23 Nov 2026). A new file: whip_core made its entities on the server with Cfx.re's server-side
-- natives, and on RedM those work differently (probed on the server, 23 Nov 2026):
--
--   * CreateVehicleServerSetter answers 0: there is no server-side setter for RDR2's entities.
--   * CreateObject, CreateObjectNoOffset and CreateVehicle are Cfx.re's older natives that hand the job to the
--     nearest player's game. The handle they answer names nothing yet: the entity is there 100 to 500 ms later,
--     owned by that player and in that player's routing bucket. Until then every native on it fails ("Tried to
--     access invalid entity").
--   * CreatePed makes nothing at all, for people or animals.
--
-- So objects and vehicles are made as before and WAITED FOR (RdrEntity.await, RdrEntity.whenReady), and peds are
-- made by a player's game near the spot and handed to the server by network id (RdrEntity.makePed,
-- client/rdr_entities.lua). Either way somebody has to be near: with nobody there, nothing is made.
-- CONVERSION.md: "Server-made entities".

RdrEntity = {}
local R = RdrEntity

local AWAIT_MS     = 3000    -- how long an object or a vehicle is waited for
local PED_MS       = 6000    -- how long a player's game has to make a ped and say so
local PED_REACH    = 250.0   -- a player further than this from the spot is not asked to make it
local LITTER_MS    = 10000   -- a thing given up on is looked for this long, and deleted if it turns up
local VEH_MS       = 6000    -- RedM (spur_core, 24 Nov 2026): how long a player's game has to make a vehicle and say so

local asks = {}      -- [nonce] = { src, hash, x, y, z, cb, at }: peds asked for (below)
local serial = 0     -- the asks' nonces, peds' and vehicles'

--- Whether the code running now may Wait: a scheduler thread (an event, a command, an export, a CreateThread), not
--- the Director's or the Systems Creator's card runners (RdrGuarded, shared/rdr_compat.lua), which fault a card
--- that waits.
---@return boolean
function R.canWait()
    local co, main = coroutine.running()
    if not co or main or not coroutine.isyieldable() then return false end
    return not (RdrGuarded and RdrGuarded[co])
end

--- Whether a server-made entity is there now, with a network id.
---@param ent number|nil
---@return boolean
function R.ready(ent)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return false end
    local ok, net = pcall(NetworkGetNetworkIdFromEntity, ent)
    return ok and type(net) == 'number' and net > 0
end

--- Wait (when the caller may: R.canWait) for an entity CreateObject or CreateVehicle answered to be there.
--- Answers whether it is. One that is not is the caller's to give up on (R.litter).
---@param ent number|nil
---@param ms number|nil
---@return boolean
function R.await(ent, ms)
    if not ent or ent == 0 then return false end
    if R.ready(ent) then return true end
    if not R.canWait() then return false end
    local deadline = GetGameTimer() + (ms or AWAIT_MS)
    repeat
        Wait(50)
        if R.ready(ent) then return true end
    until GetGameTimer() >= deadline
    return false
end

--- The same, never waiting: `cb(true)` once the entity is there, `cb(false)` when it has not come in `ms`.
---@param ent number|nil
---@param cb fun(ready: boolean)
---@param ms number|nil
function R.whenReady(ent, cb, ms)
    if not ent or ent == 0 then cb(false) return end
    CreateThread(function()
        local deadline = GetGameTimer() + (ms or AWAIT_MS)
        while not R.ready(ent) do
            if GetGameTimer() >= deadline then cb(false) return end
            Wait(50)
        end
        cb(true)
    end)
end

--- An entity given up on: deleted if it turns up after all.
---@param ent number|nil
function R.litter(ent)
    if not ent or ent == 0 then return end
    CreateThread(function()
        local deadline = GetGameTimer() + LITTER_MS
        while GetGameTimer() < deadline do
            if DoesEntityExist(ent) then DeleteEntity(ent) return end
            Wait(250)
        end
    end)
end

-- ============================================
-- Vehicles: made by a player's game
-- ============================================
--
-- RedM (spur_core, 24 Nov 2026): the server's CreateVehicle hands the job to the nearest game, but a wagon made that
-- way has no harness to fill: RDR2 counts 0 draft animals expected, and every horse put to it is refused (seen in
-- game: Steal the Car's coach and a Vehicle Manager wagon, 24 Nov 2026). So the nearest player's game is asked to make
-- the vehicle itself, with RDR2's own CreateVehicle, which puts the wagon's animals in its harness
-- (client/rdr_entities.lua), and answers with its network id, as for a ped. Nobody answering in time, the server's
-- CreateVehicle is used as before (such a wagon comes without horses). CONVERSION.md: "Server-made entities".

local vasks = {}     -- [nonce] = { src, hash, x, y, z, ent?, net?, why? }
local vlate = {}     -- [nonce] = { src, hash }: asks given up on; a vehicle made for one later is deleted

--- The player in game nearest (x, y, z), whatever their routing bucket and however far: the game that makes a
--- vehicle, as the server's CreateVehicle chose. (bindEntity sets the vehicle's own bucket.)
---@return number|nil
-- RedM (spur_core, 24 Nov 2026): a player in the world first. A game still at character select made a saved wagon at join that the
-- server couldn't take (it was ignored, and the server made a wagon without horses); one with a character loaded
-- is where the Vehicle Manager's asks come from, and those work. Anyone else only when nobody is in the world.
local function inWorld(src)
    local p = Players and Players[src]
    return p ~= nil and not p.closing
end

local function nearestPlayer(x, y, z)
    local best, bestD, loaded
    for _, s in ipairs(GetPlayers()) do
        local src = tonumber(s)
        local ped = src and GetPlayerPed(src)
        local here = src and inWorld(src)
        if ped and ped ~= 0 and DoesEntityExist(ped) and (here or not loaded) then
            if here and not loaded then best, bestD, loaded = nil, nil, true end
            local c = GetEntityCoords(ped)
            local dx, dy, dz = c.x - x, c.y - y, c.z - z
            local d = dx * dx + dy * dy + dz * dz
            if not bestD or d < bestD then best, bestD = src, d end
        end
    end
    return best
end

--- Ask the nearest player's game to make the vehicle, and wait for its answer. Answers the entity and its netId, or
--- nil and why: 'nobody', 'model' (that game has no such vehicle) or 'failed'.
local function askVehicle(hash, x, y, z, heading)
    local src = nearestPlayer(x, y, z)
    if not src then return nil, 'nobody' end
    serial = serial + 1
    local nonce = serial * 1000 + math.random(0, 999)
    local ask = { src = src, hash = hash, x = x, y = y, z = z }
    vasks[nonce] = ask
    TriggerClientEvent('spur_core:client:rdrMakeVehicle', src, nonce, hash, x + 0.0, y + 0.0, z + 0.0, (heading or 0.0) + 0.0)
    local deadline = GetGameTimer() + VEH_MS
    -- (An answer being checked, arrive below, gets up to 2.5 s more.)
    while not ask.ent and not ask.why
        and (GetGameTimer() < deadline or (ask.checking and GetGameTimer() < deadline + 2500)) do Wait(50) end
    if vasks[nonce] == ask then vasks[nonce] = nil end
    if ask.ent then return ask.ent, ask.net end
    if not ask.why and not ask.checking then
        -- No answer in time: a vehicle that game makes later for this ask is deleted when it says so.
        local late = { src = src, hash = hash }
        vlate[nonce] = late
        SetTimeout(LITTER_MS, function() if vlate[nonce] == late then vlate[nonce] = nil end end)
    end
    return nil, ask.why or 'failed'
end

--- A vehicle a game made for an ask: is it the one asked for, that game's, and (given a spot) where it was asked for?
--- RedM (spur_core, 24 Nov 2026): and if not, why (the server log says).
local function vehicleFits(ent, source, hash, x, y, z)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return false, 'it never reached the server' end
    if GetEntityType(ent) ~= 2 then return false, 'not a vehicle' end
    local model = GetEntityModel(ent) & 0xFFFFFFFF
    if model ~= (hash & 0xFFFFFFFF) then return false, ('model %d, not %d'):format(model, hash & 0xFFFFFFFF) end
    local owner = NetworkGetEntityOwner(ent)
    if owner ~= source then return false, ('owned by %s, not the player asked'):format(tostring(owner)) end
    if x then
        local c = GetEntityCoords(ent)
        local dx, dy, dz = c.x - x, c.y - y, c.z - z
        if dx * dx + dy * dy > 100.0 or math.abs(dz) > 50.0 then
            return false, ('%.0f m away across and %.0f m up or down from where it was asked for')
                :format(math.sqrt(dx * dx + dy * dy), math.abs(dz))
        end
    end
    return true
end

--- Wait (up to 2 s) for a network id a game named to reach the server: its creation comes with its next sync, which
--- can be just after the event.
local function arrive(netId)
    local deadline = GetGameTimer() + 2000
    local ent = NetworkGetEntityFromNetworkId(netId)
    while (not ent or ent == 0 or not DoesEntityExist(ent)) and GetGameTimer() < deadline do
        Wait(50)
        ent = NetworkGetEntityFromNetworkId(netId)
    end
    return ent
end

--- The game asked says how it went. Only the player asked is believed, and only for their own ask. Sized for many at
--- once: saved vehicles are put back together when somebody joins.
-- RedM (spur_core, 24 Nov 2026): no player session needed. Saved vehicles are put back as a player joins, before their session is
-- there: the answer was refused, the server made the wagon itself (no horses) and the one the game made was left
-- standing. Only the player asked is believed (ask.src), so a session adds nothing here.
SecureEvent('spur_core:server:rdrVehicleMade', {
    rateLimit = 50, burst = 40, whileDead = true, requirePlayer = false,
    params = { {'nonce', 'int', 1, 2000000000}, {'netId', 'int', 0, 65535}, {'why', 'enum', { 'ok', 'model', 'failed' }} },
}, function(source, _, nonce, netId, why)
    local ask = vasks[nonce]
    if not ask or ask.src ~= source then
        -- Too late: the server gave up on it (and made it its own way). Its vehicle goes, if it is that ask's.
        local late = vlate[nonce]
        if late and late.src == source and why == 'ok' and netId > 0 then
            vlate[nonce] = nil
            CreateThread(function()
                local ent = arrive(netId)
                if vehicleFits(ent, source, late.hash) and Entity(ent).state[RdrCompat.PLATE_BAG] == nil then
                    DeleteEntity(ent)
                    print(('[spur_core:entities] a vehicle made too late for the server (netId %d) was deleted'):format(netId))
                end
            end)
        end
        return
    end
    if why ~= 'ok' or netId == 0 then ask.why = why == 'model' and 'model' or 'failed' return end
    ask.checking = true
    CreateThread(function()
        local ent = arrive(netId)
        ask.checking = nil
        local fits, why = vehicleFits(ent, source, ask.hash, ask.x, ask.y, ask.z)
        if not fits then
            print(('[spur_core:entities] player %d answered a vehicle ask with something else (netId %d: %s): ignored')
                :format(source, netId, tostring(why)))   -- RedM (spur_core, 24 Nov 2026): with why
            ask.why = 'failed'
            return
        end
        if vasks[nonce] ~= ask then
            -- Checked after the server gave up waiting: it is not wanted now.
            if Entity(ent).state[RdrCompat.PLATE_BAG] == nil then DeleteEntity(ent) end
            return
        end
        ask.ent, ask.net = ent, netId
    end)
end)

--- Make a vehicle and wait for it: a player's game makes it (above), or else the server's CreateVehicle (the
--- nearest player's game makes it, and a wagon comes without horses). Answers the entity and its netId, or nil and
--- why. Waits: call it where the caller may (R.canWait).
---@return number|nil entity
---@return number|string netIdOrWhy
function R.vehicle(hash, x, y, z, heading)
    if not R.canWait() then return nil, 'a vehicle cannot be made here without waiting (RedM)' end
    if #GetPlayers() == 0 then return nil, 'nobody is on the server to make it (RedM: a player\'s game makes it)' end
    local made, net = askVehicle(hash, x, y, z, heading)
    if made then return made, net end
    if net == 'model' then return nil, 'Could not create the vehicle (the game has no such model)' end
    print(('[spur_core:entities] no player\'s game made vehicle %s (%s): the server makes it, so a wagon comes without horses')
        :format(tostring(hash), tostring(net)))
    local ent = CreateVehicle(hash, x + 0.0, y + 0.0, z + 0.0, (heading or 0.0) + 0.0, true, true)
    if not ent or ent == 0 then return nil, 'Could not create the vehicle' end
    if not R.await(ent) then
        R.litter(ent)
        return nil, 'Could not create the vehicle (no player\'s game made it: is anyone near?)'
    end
    return ent, NetworkGetNetworkIdFromEntity(ent)
end

-- ============================================
-- Peds: made by a player's game
-- ============================================

--- The player whose game makes a thing at (x, y, z) in `bucket`: the nearest there, within PED_REACH. Or nil.
---@return number|nil
function R.makerFor(x, y, z, bucket)
    local best, bestD
    for _, s in ipairs(GetPlayers()) do
        local src = tonumber(s)
        if src and (GetPlayerRoutingBucket(src) or 0) == (bucket or 0) then
            local ped = GetPlayerPed(src)
            if ped and ped ~= 0 and DoesEntityExist(ped) then
                local c = GetEntityCoords(ped)
                local dx, dy, dz = c.x - x, c.y - y, c.z - z
                local d = dx * dx + dy * dy + dz * dz
                if d <= PED_REACH * PED_REACH and (not bestD or d < bestD) then best, bestD = src, d end
            end
        end
    end
    return best
end

--- Ask a player's game near (x, y, z) to make a networked ped. Never waits: `cb(entity, netId)` once the server has
--- it, or `cb(nil, why)`: 'nobody' (no player near enough: nothing was asked), 'model' (that game does not have the
--- model), or 'failed' (it could not, or did not answer in time). Answers whether anyone was asked.
---@return boolean asked
function R.makePed(hash, x, y, z, heading, bucket, cb)
    local src = R.makerFor(x, y, z, bucket)
    if not src then cb(nil, 'nobody') return false end
    serial = serial + 1
    local nonce = serial * 1000 + math.random(0, 999)
    local ask = { src = src, hash = hash, x = x, y = y, z = z, cb = cb, at = GetGameTimer() }
    asks[nonce] = ask
    TriggerClientEvent('spur_core:client:rdrMakePed', src, nonce, hash, x + 0.0, y + 0.0, z + 0.0, (heading or 0.0) + 0.0)
    SetTimeout(PED_MS, function()
        if asks[nonce] == ask then
            asks[nonce] = nil
            cb(nil, 'failed')
        end
    end)
    return true
end

--- Delete a ped a player's game made for an ask nobody wants any more: its owner is asked (spur_core's own
--- npcDelete, client/npcs.lua), and the server deletes it too.
local function dropPed(ent, netId, hash, owner)
    if owner then TriggerClientEvent('spur_core:client:npcDelete', owner, netId, hash) end
    SetTimeout(1500, function()
        if DoesEntityExist(ent) then DeleteEntity(ent) end
    end)
end

--- The game asked says how it went. Only the player asked is believed, and only for their own ask; the ped must be
--- a ped of the model asked for, near where it was asked for.
SecureEvent('spur_core:server:rdrPedMade', {
    rateLimit = 50, burst = 40, whileDead = true,
    params = { {'nonce', 'int', 1, 2000000000}, {'netId', 'int', 0, 65535}, {'why', 'enum', { 'ok', 'model', 'failed' }} },
}, function(source, _, nonce, netId, why)
    local ask = asks[nonce]
    if not ask or ask.src ~= source then return end
    asks[nonce] = nil
    if why ~= 'ok' or netId == 0 then ask.cb(nil, why == 'model' and 'model' or 'failed') return end
    -- The game's creation reaches the server with its next sync, which can be just after this event.
    CreateThread(function()
        local deadline = GetGameTimer() + 2000
        local ent = NetworkGetEntityFromNetworkId(netId)
        while (not ent or ent == 0 or not DoesEntityExist(ent)) and GetGameTimer() < deadline do
            Wait(50)
            ent = NetworkGetEntityFromNetworkId(netId)
        end
        if not ent or ent == 0 or not DoesEntityExist(ent) then ask.cb(nil, 'failed') return end
        local c = GetEntityCoords(ent)
        local dx, dy, dz = c.x - ask.x, c.y - ask.y, c.z - ask.z
        if GetEntityType(ent) ~= 1 or (GetEntityModel(ent) & 0xFFFFFFFF) ~= (ask.hash & 0xFFFFFFFF)
            or dx * dx + dy * dy > 100.0 or math.abs(dz) > 50.0 then
            print(('[spur_core:entities] player %d answered a ped ask with something else (netId %d): ignored'):format(source, netId))
            ask.cb(nil, 'failed')
            return
        end
        ask.cb(ent, netId)
    end)
end)

R.dropPed = dropPed

-- A player who leaves takes their unanswered asks with them.
AddEventHandler('playerDropped', function()
    local src = source
    for nonce, ask in pairs(asks) do
        if ask.src == src then
            asks[nonce] = nil
            ask.cb(nil, 'failed')
        end
    end
    -- RedM (spur_core, 24 Nov 2026): and their vehicle asks (the server makes those its own way, askVehicle).
    for _, ask in pairs(vasks) do
        if ask.src == src and not ask.ent then ask.why = 'failed' end
    end
end)
