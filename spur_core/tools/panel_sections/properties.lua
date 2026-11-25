-- ============================================
-- /whip SECTION — Properties (client wiring)
-- ============================================
--
-- The Lua half of html/js/wp/properties.js. Reads go to the server (server/property_admin.lua),
-- because the admin view carries what the ordinary property wire does not — keyholders, door ids,
-- status, pack state. Writes go there too, ACE-gated. While the section is open this client is a
-- VIEWER, and the server pushes each change as it happens.
--
-- WHAT STAYS ON THIS CLIENT: where to teleport and what to draw. Every client already holds every
-- property's space, sign and visit point (client/properties.lua), so "Go inside" and "Show space"
-- read those rather than asking.

local open = false

local function push(kind, payload)
    if open then WhipPanelData('properties', kind, payload) end
end

PanelSections['properties'] = {
    enter = function()
        open = true
        TriggerServerEvent('spur_core:server:propertyAdminOpen')
        CreateThread(function()
            push('all', { rows = Callback('spur_core:property:adminList') or {} })
            -- A property half set up is still there when the panel comes back (tools/property_wizard.lua).
            if PropertyWizard and PropertyWizard.active() then PropertyWizard.push() end
            -- And so is Register here (tools/property_scale.lua).
            if PropertyScale then PropertyScale.pushRegister() end
        end)
    end,
    leave = function()
        open = false
        TriggerServerEvent('spur_core:server:propertyAdminClosed')
    end,
}

RegisterNetEvent('spur_core:client:propertyAdminRows', function(rows, removed)
    push('rows', { rows = rows or {}, removed = removed or {} })
end)

-- ---- reads ----

RegisterNUICallback('pcDetail', function(data, cb)
    local id = tonumber(data and data.id)
    cb(id and Callback('spur_core:property:adminDetail', id) or false)
end)

RegisterNUICallback('pcTemplates', function(_, cb)
    cb(Callback('spur_core:property:adminTemplates') or false)
end)

--- The server's instant check of a list of properties (server/property_admin.lua, Quick check).
RegisterNUICallback('pcQuickCheck', function(data, cb)
    local ids = {}
    for _, v in ipairs(type(data and data.ids) == 'table' and data.ids or {}) do
        local id = tonumber(v)
        if id then ids[#ids + 1] = id end
    end
    cb(#ids > 0 and Callback('spur_core:property:adminQuickCheck', ids) or { checked = 0, problems = {} })
end)

--- Write templates out as one pack: the server saves it under spur_core/pack_exports/ and hands the
--- text back to be copied.
RegisterNUICallback('pcExport', function(data, cb)
    local ids = {}
    for _, v in ipairs(type(data and data.templateIds) == 'table' and data.templateIds or {}) do
        local id = tonumber(v)
        if id then ids[#ids + 1] = id end
    end
    if #ids == 0 then cb({ ok = false, why = 'Pick a template' }) return end
    -- The callback answers the pack or `false, why`; the page reads { ok, why }.
    local res, why = Callback('spur_core:property:adminExport', ids, data.placements == true,
        type(data.packId) == 'string' and data.packId or '', type(data.label) == 'string' and data.label or '')
    cb(res or { ok = false, why = why or 'No answer from the server' })
end)

-- ---- writes: each names a property and an intent; the server decides ----

local function relay(eventName, ...)
    TriggerServerEvent(eventName, ...)
end

RegisterNUICallback('pcSetOwner', function(data, cb)
    local id = tonumber(data and data.id)
    if id then relay('spur_core:server:propertyAdminSetOwner', id, tonumber(data.charId) or 0) end
    cb('ok')
end)

RegisterNUICallback('pcGrantKey', function(data, cb)
    local id, charId = tonumber(data and data.id), tonumber(data and data.charId)
    if id and charId then relay('spur_core:server:propertyAdminGrantKey', id, charId) end
    cb('ok')
end)

RegisterNUICallback('pcRevokeKey', function(data, cb)
    local id, charId = tonumber(data and data.id), tonumber(data and data.charId)
    if id and charId then relay('spur_core:server:propertyAdminRevokeKey', id, charId) end
    cb('ok')
end)

RegisterNUICallback('pcUpdate', function(data, cb)
    local id = tonumber(data and data.id)
    if id and type(data.fields) == 'table' then relay('spur_core:server:propertyAdminUpdate', id, data.fields) end
    cb('ok')
end)

--- Its look (server/property_themes.lua): the same event the owner's Theme sends; an admin's is
--- taken from anywhere.
RegisterNUICallback('pcSetTheme', function(data, cb)
    local id, theme = tonumber(data and data.id), tonumber(data and data.theme)
    if id and theme then relay('spur_core:server:propertySetTheme', id, theme) end
    cb('ok')
end)

RegisterNUICallback('pcDelete', function(data, cb)
    local id = tonumber(data and data.id)
    if id then relay('spur_core:server:propertyAdminDelete', id) end
    cb('ok')
end)

RegisterNUICallback('pcClearFurniture', function(data, cb)
    local id = tonumber(data and data.id)
    if id then relay('spur_core:server:propertyAdminClearFurniture', id) end
    cb('ok')
end)

RegisterNUICallback('pcResolve', function(data, cb)
    local id = tonumber(data and data.id)
    if id and (data.mode == 'keep' or data.mode == 'pack') then relay('spur_core:server:propertyAdminResolve', id, data.mode) end
    cb('ok')
end)

RegisterNUICallback('pcAdopt', function(data, cb)
    local id = tonumber(data and data.id)
    if id then relay('spur_core:server:propertyAdminAdopt', id) end
    cb('ok')
end)

-- ---- the world ----

local function defOf(data)
    return (GetPropertyDefs and GetPropertyDefs() or {})[tonumber(data and data.id) or -1]
end

--- Go to a property: to its sign ("entry"), standing in front of it and facing it, or into it
--- ("inside"), at its visit point. Either falls back to the middle of the property.
RegisterNUICallback('pcGo', function(data, cb)
    cb('ok')
    local p = defOf(data)
    if not p then return end
    local ped = PlayerPedId()
    local s = p.sign
    if data.where == 'entry' and s then
        -- A sign faces its heading; stand a metre and a half out along it, turned to read it.
        local h = math.rad(s.heading or 0.0)
        local x, y = s.x - math.sin(h) * 1.5, s.y + math.cos(h) * 1.5
        SetEntityCoords(ped, x, y, s.z - 0.8, false, false, false, false)
        SetEntityHeading(ped, ((s.heading or 0.0) + 180.0) % 360.0)
        return
    end
    local v = p.visit or p.anchor
    if v then SetEntityCoords(ped, v.x, v.y, v.z + 0.1, false, false, false, false) end
end)

--- Which property the admin is standing in (client/properties.lua), for the page to pick out: its id,
--- or false.
RegisterNUICallback('pcWhereAmI', function(_, cb)
    local p = GetCurrentProperty and GetCurrentProperty()
    cb({ id = p and p.id or false })
end)

--- Its furniture, as its owner furnishes it (client/property_furnish.lua): an admin may, from anywhere
--- (the server's lock and save let a developer past "your property" and "at the property"). The room's
--- furniture is only there close up, so the admin is taken inside first when they are not there,
--- and the furnisher opens once the property is streamed in round them.
local FURNISH_ARRIVE_MS = 8000

RegisterNUICallback('pcManageFurniture', function(data, cb)
    cb('ok')
    local p = defOf(data)
    if not p then return end
    WhipPanelClose()
    CreateThread(function()
        if not (CanFurnishProperty(p.id) and IsPropertyNear(p.id)) then
            local v = p.visit or p.anchor
            if v then SetEntityCoords(PlayerPedId(), v.x, v.y, v.z + 0.1, false, false, false, false) end
            local giveUp = GetGameTimer() + FURNISH_ARRIVE_MS
            while not (CanFurnishProperty(p.id) and IsPropertyNear(p.id)) and GetGameTimer() < giveUp do
                Wait(100)
            end
        end
        OpenFurnisher(p.id)   -- says why itself when it cannot open
    end)
end)

RegisterNUICallback('pcShowSpace', function(data, cb)
    cb('ok')
    local p = defOf(data)
    if not p then return end
    PropertyEditor.showSpace(p)
end)

--- Aim one of its signs: 'sign' (outside, for sale) or 'manager' (inside, for who lives there),
--- for this property alone or every property on its unit. The mode hides the panel and brings it
--- back; the server stores what was aimed (propertyAdminSetSign).
RegisterNUICallback('pcPlaceSign', function(data, cb)
    cb('ok')
    local p = defOf(data)
    if not p then return end
    local which = data.which == 'manager' and 'manager' or 'sign'
    local scope = data.scope == 'unit' and 'unit' or 'property'
    PropertyEditor.placeSign(p, which, scope, tonumber(data.uses))
end)

--- Put its outside sign on a sign post, or move the post (Config.PropertySignPosts). The same scope as the signs.
RegisterNUICallback('pcPlaceSignPost', function(data, cb)
    cb('ok')
    local p = defOf(data)
    if not p then return end
    PropertyEditor.placePropertyPost(p, data.scope == 'unit' and 'unit' or 'property', tonumber(data.uses))
end)
