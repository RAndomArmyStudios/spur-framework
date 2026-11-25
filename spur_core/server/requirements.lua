-- ============================================
-- Requirements — one reading of a `require` table, on the server
-- ============================================
--
-- AddAction's `require` (client/actions.lua, the words: shared/interact_spec.lua) is a hint on the client. Whatever the server does behind it reads the
-- same table here: points made in code (server/runtime_points.lua) and item options (server/item_options.lua,
-- inventory.lua). One rule for all.
--
--   Requirements.clean(raw)          the table cleaned to the keys the client knows, or nil
--   Requirements.lost(raw, clean)    the first key cleaning lost (a requirement that cannot be read must not
--                                    become no requirement: callers refuse it), or nil
--   Requirements.met(source, player, req)  true, or false and why in the player's words

Requirements = {}

local function strList(v, maxLen, maxItems)
    if type(v) ~= 'table' then v = { v } end
    local out = {}
    for _, s in ipairs(v) do
        if #out >= maxItems then break end
        local c = Sanitize.string(s, maxLen, '')
        if c ~= '' then out[#out + 1] = c end
    end
    return #out > 0 and out or nil
end

--- A `job` requirement: job keys, or job ids (whole numbers: "a key or a jobId", as the client takes them). An id is
--- kept as a number; met compares either way.
local function jobList(v)
    if type(v) ~= 'table' then v = { v } end
    local out = {}
    for _, s in ipairs(v) do
        if #out >= 10 then break end
        local id = type(s) == 'number' and math.tointeger(s) or nil
        if id and id > 0 then
            out[#out + 1] = id
        else
            local c = Sanitize.string(s, 50, '')
            if c ~= '' then out[#out + 1] = c end
        end
    end
    return #out > 0 and out or nil
end

--- A `require` table, cleaned to the keys AddAction's `require` knows (client/actions.lua), which is what the
--- client shows and what met below enforces.
---@return table|nil
function Requirements.clean(raw)
    if type(raw) ~= 'table' then return nil end
    local out = {}
    if raw.alive == false then out.alive = false end
    if raw.vehicle == 'in' or raw.vehicle == 'out' then out.vehicle = raw.vehicle end
    if raw.job ~= nil then out.job = jobList(raw.job) end
    if raw.onDuty == true then out.onDuty = true end
    if raw.jobPermission ~= nil then
        local p = Sanitize.string(raw.jobPermission, 40, '')
        if p ~= '' then out.jobPermission = p end
    end
    if raw.item ~= nil then
        local items = {}
        local list = (type(raw.item) == 'table' and raw.item.item == nil) and raw.item or { raw.item }
        for _, it in ipairs(list) do
            if #items >= 10 then break end
            local key, count = it, 1
            if type(it) == 'table' then key, count = it.item, it.count end
            key = Sanitize.string(key, 50, '')
            if key ~= '' then items[#items + 1] = { item = key, count = Sanitize.int(count, 1, 1000000, 1) } end
        end
        if #items > 0 then out.item = items end
    end
    if raw.held ~= nil then out.held = strList(raw.held, 50, 10) end
    if raw.zone ~= nil then out.zone = strList(raw.zone, 60, 10) end
    if raw.charId ~= nil then
        local ids = {}
        for _, c in ipairs(type(raw.charId) == 'table' and raw.charId or { raw.charId }) do
            local id = Sanitize.id(c)
            if id and #ids < 50 then ids[#ids + 1] = id end
        end
        if #ids > 0 then out.charId = ids end
    end
    if raw.ace ~= nil then
        local a = Sanitize.string(raw.ace, 64, '')
        if a ~= '' then out.ace = a end
    end
    return next(out) and out or nil
end

--- The first word of `raw` that cleaning lost (it said something, and `clean` has nothing for it), or nil. A
--- requirement that cannot be read must not become no requirement: its callers refuse it.
---@param raw table|nil
---@param clean table|nil  Requirements.clean(raw)
---@return string|nil key
function Requirements.lost(raw, clean)
    if type(raw) ~= 'table' then return nil end
    for k, v in pairs(raw) do
        -- (The defaults say nothing: alive = true, onDuty = false)
        local says = not ((k == 'alive' and v == true) or (k == 'onDuty' and v == false))
        if says and (clean == nil or clean[k] == nil) then return tostring(k) end
    end
    return nil
end

--- Does this player meet the requirements? The SERVER's answer — the client's was a hint.
---@return boolean
---@return string|nil why
function Requirements.met(source, player, req)
    -- DOWNED is `player.isDead`, the one reading the SecureEvent gate itself uses (secure.lua): a
    -- second source here could let an action disagree with every other event about who is down.
    local downed = player ~= nil and player.isDead == true
    if type(req) ~= 'table' then
        if downed then return false, 'Not while downed' end
        return true
    end
    if req.alive ~= false and downed then
        return false, 'Not while downed'
    end
    if req.vehicle == 'in' or req.vehicle == 'out' then
        local inVeh = GetVehiclePedIsIn(GetPlayerPed(source), false) ~= 0
        if req.vehicle == 'in' and not inVeh then return false, 'You need to be in a vehicle' end
        if req.vehicle == 'out' and inVeh then return false, 'Get out of the vehicle first' end
    end
    if req.job ~= nil then
        local jobs = Jobs.getPlayerJobs(source) or {}
        local any = false
        for _, want in ipairs(req.job) do
            for jobId, j in pairs(jobs) do
                if j.key == want or tostring(jobId) == tostring(want) then
                    if (not req.onDuty or j.clockedOn)
                        and (req.jobPermission == nil or (j.permissions and j.permissions[req.jobPermission] == true)) then
                        any = true
                    end
                end
            end
            if any then break end
        end
        if not any then return false, 'Not for your job' end
    elseif req.jobPermission ~= nil then
        -- A permission with no job named: any job whose role grants it, on duty there with onDuty. The
        -- same rule as the client's (client/actions.lua).
        local any = false
        for _, j in pairs(Jobs.getPlayerJobs(source) or {}) do
            if j.permissions and j.permissions[req.jobPermission] == true and (not req.onDuty or j.clockedOn) then
                any = true
                break
            end
        end
        if not any then return false, 'Not for your job' end
    elseif req.onDuty then
        local onDuty = false
        for _, j in pairs(Jobs.getPlayerJobs(source) or {}) do
            if j.clockedOn then onDuty = true break end
        end
        if not onDuty then return false, 'You need to be on duty' end
    end
    if req.item ~= nil then
        for _, it in ipairs(req.item) do
            -- Carried ANYWHERE on them (a keycard in the accessory strip too), as the client's
            -- GetItemCount counts and doors ask.
            if Inventory.getItemCountAcrossContainers(player.inventory, it.item) < (it.count or 1) then
                return false, 'You need ' .. tostring(it.item)
            end
        end
    end
    if req.held ~= nil then
        -- The server's own record of the hand (SetHeldItem), the same the player's game was told.
        local d = Stores.held(source)
        local ok = false
        for _, key in ipairs(req.held) do
            if d and d.item == key then ok = true break end
        end
        if not ok then return false, 'You need it in your hand' end
    end
    if req.zone ~= nil then
        local c = GetEntityCoords(GetPlayerPed(source))
        local inside = false
        -- The server's own zones only, never a client-reported mirror (Zones.containsTrusted).
        for _, z in ipairs(req.zone) do
            if Zones.containsTrusted(z, c) then inside = true break end
        end
        if not inside then return false, 'Not here' end
    end
    if req.charId ~= nil then
        local ok = false
        for _, c in ipairs(req.charId) do
            if c == player.charId then ok = true break end
        end
        if not ok then return false, 'Not for you' end
    end
    if req.ace ~= nil and not DevTools.hasAce(source, req.ace) then return false, 'Not permitted' end
    return true
end
