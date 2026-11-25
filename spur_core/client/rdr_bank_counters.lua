-- ============================================
-- BANK COUNTERS — client/rdr_bank_counters.lua (RedM only)
-- ============================================
--
-- RedM (spur_core, 23 Nov 2026): a new file, not part of whip_core.
--
-- RDR2 has no cash machines, and whip's bank menu (client/atm.lua) sits on a prop it finds by model
-- (Config.AtmProps, through client/prop_prompts.lua). So at each teller window in Config.BankCounters this file puts
-- a hidden marker prop of the first Config.AtmProps model while the player is near it. It is made on this client only
-- (not networked), with no collision, and is deleted again when the player walks away. The teller window then has the
-- prompt a GTA ATM had: Check Balance, then Deposit and Withdraw.
--
-- The marker model is a cutscene prop (p_cs_ledger01x) so that no copy of it already in the world turns into a bank.
-- RedM (spur_core, 24 Nov 2026): all four windows walked in game, the badge over the counter in front of the customer.
-- If one is not at its window, move the point in Config.BankCounters (/vec4 while standing there, facing the window)
-- or the badge in Config.AtmBadgeOffset.

local NEAR = 60.0   -- metres: the marker is made inside this
local FAR  = 80.0   -- and deleted outside this (the gap stops it flickering at the edge)

--- [index in Config.BankCounters] = { entity = ..., model = 'name' }
local markers = {}
local warned = {}   -- [model] = true once its load has timed out

local function markerModel()
    local list = Config.AtmProps
    if type(list) ~= 'table' or type(list[1]) ~= 'string' or list[1] == '' then return nil end
    return list[1]
end

local function remove(i)
    local m = markers[i]
    markers[i] = nil
    if m and m.entity and DoesEntityExist(m.entity) then
        SetEntityAsMissionEntity(m.entity, true, true)
        DeleteEntity(m.entity)
    end
end

local function removeAll()
    for i in pairs(markers) do remove(i) end
end

--- The floor under a teller point (the point may be at the player's height rather than their feet).
local function floorZ(x, y, z)
    local ok, gz = GetGroundZFor_3dCoord(x, y, z + 1.0, false)
    if ok and gz and gz ~= 0.0 and math.abs(gz - z) < 3.0 then return gz end
    return z
end

local function place(i, c, model)
    local hash = GetHashKey(model)
    if not IsModelValid(hash) then
        if not warned[model] then
            warned[model] = true
            print(('^3[spur_core] bank counters: "%s" (Config.AtmProps[1]) is not a model in this game^7'):format(model))
        end
        return false
    end
    RequestModel(hash)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > deadline then
            if not warned[model] then
                warned[model] = true
                print(('^3[spur_core] bank counters: "%s" did not load in 5 s; retrying^7'):format(model))
            end
            return false
        end
        Wait(0)
    end
    local x, y, z = c.x + 0.0, c.y + 0.0, c.z + 0.0
    z = floorZ(x, y, z)
    local e = CreateObject(hash, x, y, z, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not e or e == 0 then return false end
    SetEntityHeading(e, (c.w or 0.0) + 0.0)
    FreezeEntityPosition(e, true)
    SetEntityCollision(e, false, false)
    SetEntityVisible(e, false)
    markers[i] = { entity = e, model = model }
    return true
end

CreateThread(function()
    while true do
        local list = Config.BankCounters
        local model = markerModel()
        if type(list) ~= 'table' or #list == 0 or not model then
            removeAll()
            Wait(5000)
        else
            local pos = GetEntityCoords(PlayerPedId())
            for i, c in ipairs(list) do
                local m = markers[i]
                if m and (m.model ~= model or not DoesEntityExist(m.entity)) then
                    remove(i)
                    m = nil
                end
                local d = #(pos - vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0))
                if not m and d < NEAR then
                    place(i, c, model)
                elseif m and d > FAR then
                    remove(i)
                end
            end
            for i in pairs(markers) do
                if not list[i] then remove(i) end
            end
            Wait(1500)
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then removeAll() end
end)
