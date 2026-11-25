-- ============================================
-- /prop — the furniture catalog's entry for the prop you are looking at
-- ============================================
--
--   /prop add <category>   add it to the catalog (server/prop_catalog.lua's propAdd)
--   /prop remove           take it out (propRemove: marked unavailable, so the seed never puts it back)
--
-- ACE-GATED ON THE SERVER: both writes are SecureEvents with `ace = 'whip.devtools'`, so a player without it gets a
-- rejection in the Event Monitor and nothing else. The command is open because a client command can only ask.
--
-- LOOKING AT, NOT STANDING ON. A raycast from the camera picks one prop out of a room full of them; standing near is
-- ambiguous the moment two props touch, which in an interior is always.

RegisterCommand('prop', function(_, args)
    local sub = tostring(args[1] or ''):lower()

    if sub ~= 'add' and sub ~= 'remove' then
        print('[prop] /prop add <category>   add the prop you are looking at')
        print('[prop] /prop remove           remove the prop you are looking at')
        print('[prop] categories: ' .. (function()
            local out = {}
            for _, c in ipairs(Config.PropCategories or {}) do out[#out + 1] = c.key end
            return table.concat(out, ', ')
        end)())
        return
    end

    local ped = PlayerPedId()
    local cam = GetGameplayCamCoord()
    local rot = GetGameplayCamRot(2)
    local p, y = math.rad(rot.x), math.rad(rot.z)
    local dir = vector3(-math.sin(y) * math.cos(p), math.cos(y) * math.cos(p), math.sin(p))
    local dest = cam + dir * 12.0

    -- Flag 16 is objects only. A ray that also hit the world would return map geometry, whose
    -- archetype name is a chunk of the map rather than a placeable prop.
    local ray = StartShapeTestRay(cam.x, cam.y, cam.z, dest.x, dest.y, dest.z, 16, ped, 0)
    local _, hit, _, _, entity = GetShapeTestResult(ray)

    if hit ~= 1 or not entity or entity == 0 or not DoesEntityExist(entity) then
        print('[prop] nothing in front of you within 12m')
        if UI and UI.Notify then UI.Notify('Look at a prop first', 'error') end
        return
    end

    -- The Cfx-only native, guarded the way tools/objectviewer.lua guards it: it is documented as
    -- unreliable for entity types outside ped/vehicle/object, and missing entirely on older builds.
    local name
    if GetEntityType(entity) == 3 then
        local fn = rawget(_G, 'GetEntityArchetypeName')
        local ok, res
        if fn then ok, res = pcall(fn, entity)
        else ok, res = pcall(Citizen.InvokeNative, 0x47B870F5, entity, Citizen.ResultAsString()) end
        if ok and type(res) == 'string' and res ~= '' then name = res end
    end

    if not name then
        print('[prop] the game would not name that entity — it may not be an object')
        if UI and UI.Notify then UI.Notify('Could not read that model name', 'error') end
        return
    end

    if sub == 'remove' then
        TriggerServerEvent('spur_core:server:propRemove', name)
        return
    end

    local category = tostring(args[2] or 'misc'):lower()
    TriggerServerEvent('spur_core:server:propAdd', name, category, '')
end, false)
