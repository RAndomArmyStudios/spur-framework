-- ============================================
-- RedM (spur_core, 24 Nov 2026): a ped's health on the server
-- ============================================
--
-- RedM's server reads 0 for every ped's health and max health, living or dead (seen in game: a shopkeeper read
-- 0 / 0 here while the game that ran it read 200 / 200). So shop talk never spoke (server/shop_talk.lua needs a
-- living customer), NPC damage was never seen (server/npcs.lua) and the Director's health reads were all 0. The
-- game that owns a ped tells its health, on whip's scale (0 dead, else 101 to 200), in the ped's state bag as
-- spurHp (client/rdr_health.lua), and these read that when RedM's own read is 0. RedM's read wins whenever it
-- gives anything. A player's game can tell a wrong health for its own ped, as it already could through the vitals
-- report (server/stats.lua): nothing is trusted that was not before.
-- Ported from whip_core by Whippy and WLVF.

local rawGet, rawMax = GetEntityHealth, GetEntityMaxHealth   -- shared/rdr_compat.lua's, on whip's scale

local function told(e)
    if not e or e == 0 or not DoesEntityExist(e) then return nil end
    return tonumber(Entity(e).state.spurHp)
end

--- RedM (spur_core, 24 Nov 2026): a vehicle's health as the game running it told it (client/rdr_health.lua), or nil.
local function toldVehicle(e)
    if not e or e == 0 or not DoesEntityExist(e) or GetEntityType(e) ~= 2 then return nil end
    local v = Entity(e).state.spurVeh
    return type(v) == 'table' and v or nil
end

GetEntityHealth = function(e)
    local h = rawGet(e)
    if h and h > 0 then return h end
    local v = toldVehicle(e)   -- RedM (spur_core, 24 Nov 2026)
    if v then return tonumber(v.hp) or h end
    return told(e) or h
end

GetEntityMaxHealth = function(e)
    local max = rawMax(e)
    if max and max > 0 then return max end
    local v = toldVehicle(e)   -- RedM (spur_core, 24 Nov 2026): a vehicle's own max, not a ped's 200
    if v then return tonumber(v.max) or max end
    if told(e) then return 200 end
    return max
end

-- RedM (spur_core, 24 Nov 2026): a vehicle's engine and body health the same way. A wagon whose engine read nothing takes its
-- body's (a wagon has no engine).
local rawEngine, rawBody = GetVehicleEngineHealth, GetVehicleBodyHealth

GetVehicleEngineHealth = function(e)
    local x = rawEngine(e)
    if x and x ~= 0 then return x end
    local v = toldVehicle(e)
    if not v then return x end
    return tonumber(v.engine) or tonumber(v.body) or x
end

GetVehicleBodyHealth = function(e)
    local x = rawBody(e)
    if x and x ~= 0 then return x end
    local v = toldVehicle(e)
    return v and tonumber(v.body) or x
end
