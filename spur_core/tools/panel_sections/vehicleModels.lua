-- ============================================
-- /whip SECTION — Vehicle Adjustments (client wiring)
-- ============================================
--
-- Trunk and glovebox per category (`vehicle_class_meta`, every model of one game vehicle class) and per model
-- (`vehicle_meta`). The section in html/js/wp/vehicleModels.js is the screen, and every change is one of
-- server/vehicle_manager.lua's whip.devtools-gated callbacks. This file only asks.

--- What the server holds now; the catalog to list it by only on entering (a save does not change it).
local function snapshot(withCatalog)
    local data, why = Callback('spur_core:vm:modelStorage', withCatalog == true)
    if type(data) ~= 'table' then
        WhipPanelResult('Could not load vehicle adjustments: ' .. tostring(why or 'no answer'), 'err')
        return
    end
    WhipPanelData('vehicleModels', 'all', data)
end

PanelSections['vehicleModels'] = {
    enter = function()
        CreateThread(function() snapshot(true) end)
    end,
    leave = function() end,
}

--- Ask, then show what the server now holds. Answers the page with { ok, why }.
local function ask(name, ...)
    local ok, why = Callback(name, ...)
    if not ok then return { ok = false, why = tostring(why or 'refused') } end
    snapshot(false)
    return { ok = true }
end

RegisterNUICallback('vmmSave', function(data, cb)
    cb(ask('spur_core:vm:setModelStorage', data and data.model, data and data.fields))
end)

RegisterNUICallback('vmmClear', function(data, cb)
    cb(ask('spur_core:vm:clearModelStorage', data and data.model))
end)

RegisterNUICallback('vmmClassSave', function(data, cb)
    cb(ask('spur_core:vm:setClassStorage', data and data.class, data and data.fields))
end)

RegisterNUICallback('vmmClassClear', function(data, cb)
    cb(ask('spur_core:vm:clearClassStorage', data and data.class))
end)
