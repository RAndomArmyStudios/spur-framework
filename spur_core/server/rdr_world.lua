-- ============================================
-- RDR2'S WORLD, ON WHIP'S PROMPTS — server/rdr_world.lua
-- ============================================
--
-- RedM (spur_core, 25 Nov 2026). New with the port: whip_core (by Whippy and WLVF) has no such file. RDR2's own
-- looting is switched off (client/rdr_interactions.lua), and searching a body is a whip prompt instead
-- (client/rdr_world.lua). What a body gives is decided here, from Config.RdrWorld.Loot, as whip items: RDR2's own
-- loot (its money, its ammunition) is nothing to whip.
--
-- The rules: a body is searched once (by its network id, remembered for an hour), the player stands within 6 m of
-- it, it is a ped and no player's, and one search every 2 s at most.

local SEARCHED_FOR_MS = 60 * 60 * 1000
local searched = {}   -- [netId] = when (GetGameTimer)

local function cfg() return type(Config.RdrWorld) == 'table' and Config.RdrWorld or {} end

local function bodyOf(netId)
    local ent = NetworkGetEntityFromNetworkId(netId)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return nil end
    if GetEntityType(ent) ~= 1 then return nil end
    if IsPedAPlayer(ent) then return nil end
    return ent
end

--- A whole number between the two ends of `range` ({ min, max }, or one number).
local function roll(range)
    if type(range) == 'number' then return math.floor(range) end
    if type(range) ~= 'table' then return 0 end
    local lo, hi = math.floor(tonumber(range[1]) or 0), math.floor(tonumber(range[2]) or 0)
    if hi < lo then lo, hi = hi, lo end
    return math.random(lo, hi)
end

SecureEvent('spur_core:server:rdrSearchBody', {
    rateLimit = 2000,
    params = { { 'netId', 'id', 1, 65535 } },
    near = {
        at = function(_, _, netId)
            local ent = bodyOf(netId)
            if ent then return GetEntityCoords(ent) end
        end,
        range = 6.0,
    },
}, function(source, _, netId)
    local c = cfg()
    local loot = type(c.Loot) == 'table' and c.Loot or nil
    if c.search == false or not loot then return end
    local ent = bodyOf(netId)
    if not ent then return end

    local now = GetGameTimer()
    for id, at in pairs(searched) do
        if now - at > SEARCHED_FOR_MS then searched[id] = nil end
    end
    if searched[netId] then
        TriggerClientEvent('spur_core:client:rdrSearched', source, netId, {})
        return
    end
    searched[netId] = now
    Entity(ent).state:set('spurSearched', true, true)

    local found = {}
    if math.random() < (tonumber(loot.cashChance) or 0) then
        local n = roll(loot.cash)
        if n > 0 and Inventory.give(source, 'cash', n, nil, 'searched a body') then
            found[#found + 1] = { item = 'cash', amount = n }
        end
    end
    local took = 0
    for _, row in ipairs(type(loot.items) == 'table' and loot.items or {}) do
        if took >= (tonumber(loot.maxItems) or 1) then break end
        if type(row) == 'table' and Config.Items[row.item] and math.random() < (tonumber(row.chance) or 0) then
            local n = math.max(1, roll(row.amount or 1))
            if Inventory.give(source, row.item, n, nil, 'searched a body') then
                found[#found + 1] = { item = row.item, amount = n, name = Config.Items[row.item].name }
                took = took + 1
            end
        end
    end
    TriggerClientEvent('spur_core:client:rdrSearched', source, netId, found)
end)
