-- ============================================
-- Draft animals: the horses a game made for one of spur_core's wagons
-- RedM (spur_core, 24 Nov 2026)
-- ============================================
--
-- A wagon the server makes comes with an empty harness on current RedM servers; the game running it makes draft
-- horses and puts them in (client/draft_animals.lua), then names them here. They are kept (KeepEntity) while the
-- wagon is, and deleted once it is gone, however it went (stored, deleted, cleaned up): a sweep looks every few
-- seconds. Taken: any ped but a player, made by the wagon's own game, standing by the wagon, whatever its model (RDR2's
-- own animals for a wagon a player's game made, server/rdr_entities.lua, may be any breed). Each one's model is kept,
-- and a handle that names another model by the time the wagon goes is left alone. (RedM (spur_core, 24 Nov 2026):
-- was the three horse models client/draft_animals.lua makes.)

local function u32(h) return math.tointeger(h or 0) & 0xFFFFFFFF end   -- one form for signed and unsigned hashes

local MAX_PER_WAGON = 6     -- RDR2's harness has six places at most (eDraftHarness)
local SWEEP_MS = 3000
local NEAR = 25.0          -- RedM (spur_core, 24 Nov 2026): how near the wagon an animal of its harness stands

local teams = {}            -- wagon entity -> { { ent, model } }   (RedM (spur_core, 24 Nov 2026): was { horse entities })

SecureEvent('spur_core:server:draftHorses', {
    rateLimit = 500, burst = 6, whileDead = true,
    params = { {'netId', 'id', 1, 65535}, {'horses', 'list', {'horse', 'id', 1, 65535}, MAX_PER_WAGON} },
    ownerOf = 'netId',
}, function(source, _, netId, horses)
    local wagon = NetworkGetEntityFromNetworkId(netId)
    if not wagon or wagon == 0 or not DoesEntityExist(wagon) or GetEntityType(wagon) ~= 2 then return end
    if Entity(wagon).state[RdrCompat.PLATE_BAG] == nil then return end   -- spur_core's own wagons only
    local team = teams[wagon] or {}
    local wc = GetEntityCoords(wagon)
    for _, hNet in ipairs(horses) do
        local horse = NetworkGetEntityFromNetworkId(hNet)
        local known = false
        for _, t in ipairs(team) do if t.ent == horse then known = true end end
        -- RedM (spur_core, 24 Nov 2026): any animal of that game's by the wagon, not only three horse models
        if not known and #team < MAX_PER_WAGON and horse and horse ~= 0 and DoesEntityExist(horse) and GetEntityType(horse) == 1
            and not IsPedAPlayer(horse) and NetworkGetEntityOwner(horse) == source
            and #(GetEntityCoords(horse) - wc) <= NEAR then
            SetEntityOrphanMode(horse, 2)   -- KeepEntity: this file decides when it goes
            team[#team + 1] = { ent = horse, model = u32(GetEntityModel(horse)) }
        end
    end
    if #team > 0 then teams[wagon] = team end
end)

CreateThread(function()
    while true do
        Wait(SWEEP_MS)
        for wagon, team in pairs(teams) do
            if not DoesEntityExist(wagon) or GetEntityType(wagon) ~= 2 then
                for _, t in ipairs(team) do
                    local horse = t.ent
                    if DoesEntityExist(horse) and GetEntityType(horse) == 1 and not IsPedAPlayer(horse)
                        and u32(GetEntityModel(horse)) == t.model then   -- RedM (spur_core, 24 Nov 2026): its own model, as told
                        DeleteEntity(horse)
                    end
                end
                teams[wagon] = nil
            end
        end
    end
end)
