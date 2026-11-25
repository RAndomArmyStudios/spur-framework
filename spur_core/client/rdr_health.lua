-- ============================================
-- RedM (spur_core, 24 Nov 2026): a ped's health, told to the server
-- ============================================
--
-- RedM's server reads 0 for every ped's health and max health, living or dead (seen in game: a shopkeeper read
-- 0 / 0 on the server while the game that ran it read 200 / 200). whip's server reads them for its death checks
-- (server/stats.lua, server/events_misc.lua), shop talk (server/shop_talk.lua), NPC damage (server/npcs.lua) and
-- the Director. So the game that owns a ped puts the health it reads, on whip's scale (0 dead, else 101 to 200:
-- shared/rdr_compat.lua), in the ped's state bag as spurHp, and server/rdr_health.lua reads that when RedM's own
-- read is 0. Written only when it changes (the bag itself is the record, so a change of owner or a handle used
-- again is no trouble). A game may write only the bags of entities it owns, so it is told only of those: the
-- player's own ped (below, client/stats.lua and client/death.lua) and the NPCs this game runs (client/npcs.lua).
-- Ported from whip_core by Whippy and WLVF.

RdrHealth = {}

--- Puts the ped's health in its state bag when that has changed.
---@param ped number a networked ped this game owns
---@param value number|nil its health on whip's scale (0 = dead); read from the ped when nil
function RdrHealth.tell(ped, value)
    if not ped or ped == 0 or not DoesEntityExist(ped) or not NetworkGetEntityIsNetworked(ped) then return end
    value = math.floor(tonumber(value or GetEntityHealth(ped)) or 0)
    local state = Entity(ped).state
    if state.spurHp ~= value then state:set('spurHp', value, true) end
end

-- RedM (spur_core, 24 Nov 2026): a wagon's health too. RedM's server reads 0 for an RDR2 wagon's health, max health, engine and
-- body, so kept damage (server/vehicle_damage.lua) saved nothing and the Director couldn't tell a wagon's damage
-- (DirectorNodes.carDamage, Fail If the Car Is Damaged). The game running one of spur_core's vehicles (it has a
-- spurPlate) puts what it reads in the vehicle's spurVeh state bag: { hp, max, engine, body }, whole numbers,
-- written only when one changes. A wagon has no engine: an engine reading of 0 on a wagon that isn't wrecked is
-- left out, and the server takes the body's for it (server/rdr_health.lua).
local VEH_HP_MS = 1000
local vehToldOnce = false

local function tellVehicle(veh)
    local hp, max = GetEntityHealth(veh), GetEntityMaxHealth(veh)
    local engine, body = GetVehicleEngineHealth(veh), GetVehicleBodyHealth(veh)
    local v = {
        hp = math.floor((tonumber(hp) or 0) + 0.5), max = math.floor((tonumber(max) or 0) + 0.5),
        body = math.floor((tonumber(body) or 0) + 0.5),
    }
    local e = math.floor((tonumber(engine) or 0) + 0.5)
    if e ~= 0 or v.hp <= 0 then v.engine = e end
    local state = Entity(veh).state
    local was = state.spurVeh
    if type(was) == 'table' and was.hp == v.hp and was.max == v.max and was.engine == v.engine and was.body == v.body then
        return
    end
    state:set('spurVeh', v, true)
    if not vehToldOnce then   -- F8, once: what RDR2 reads for a wagon
        vehToldOnce = true
        print(('[spur_core] RedM: a vehicle\'s health, told to the server: hp %d of %d, engine %s, body %d')
            :format(v.hp, v.max, tostring(v.engine), v.body))
    end
end

CreateThread(function()
    while true do
        Wait(VEH_HP_MS)
        for _, veh in ipairs(GetGamePool('CVehicle')) do
            if DoesEntityExist(veh) and NetworkGetEntityIsNetworked(veh) and NetworkHasControlOfEntity(veh)
                and Entity(veh).state.spurPlate ~= nil then
                tellVehicle(veh)
            end
        end
    end
end)

-- The player's own ped, dead or alive: client/stats.lua's vitals loop rests while the player is dead, and a new ped
-- (a respawn, a model change) at the same health would otherwise go untold.
CreateThread(function()
    while true do
        Wait(250)
        local ped = PlayerPedId()
        RdrHealth.tell(ped, IsEntityDead(ped) and 0 or nil)
    end
end)
