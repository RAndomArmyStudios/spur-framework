-- ============================================
-- /whip SECTION — Items (client wiring)
-- ============================================
--
-- The Lua half of html/js/wp/items.js. The catalogue comes through WhipPanelData: asked for on enter,
-- and re-pushed by the server while the section is open (an item registered, or one's settings
-- changed), so live changes flow straight in. One item's settings are asked for when it is picked
-- (server/item_settings.lua); an Apply goes through the Config page's own cfgApply
-- (tools/panel_sections/config.lua), with this section's id, so the answer comes back here.

local entered = false

PanelSections['items'] = {
    enter = function()
        entered = true
        TriggerServerEvent('spur_core:server:ibGetAll')
    end,
    leave = function()
        entered = false
        TriggerServerEvent('spur_core:server:ibClosed')
    end,
}

RegisterNetEvent('spur_core:client:ibAllItems', function(items)
    WhipPanelData('items', 'all', items)
end)

-- Any admin saved settings (this one too): the item on screen is asked for again.
RegisterNetEvent('spur_core:client:settingsSaved', function()
    if entered then WhipPanelData('items', 'settingsSaved', {}) end
end)

-- One item's settings: { key, mayEdit, groups }, or { why }.
RegisterNUICallback('ibSettings', function(data, cb)
    local key = type(data) == 'table' and data.key
    if type(key) ~= 'string' or key == '' then
        cb({ why = 'No item' })
        return
    end
    local res, why = Callback('spur_core:itemSettings:get', key)
    if type(res) ~= 'table' then
        cb({ why = why or 'The settings could not be read' })
        return
    end
    cb(res)
end)

-- Every maker this game has a car from, spelled as an item's picture path spells {make}
-- (client/inventory.lua's itemVehicleMakes), so the page can show which makers have a picture. Worked
-- out once: the game's vehicles do not change while it runs.
local makers = nil
RegisterNUICallback('ibVehicleMakes', function(_, cb)
    if not makers then
        local seen = {}
        makers = {}
        for _, model in ipairs(GetAllVehicleModels and GetAllVehicleModels() or {}) do
            local ok, make = pcall(GetMakeNameFromVehicleModel, GetHashKey(model))
            if ok and type(make) == 'string' and make ~= '' and make ~= 'CARNOTFOUND' then
                make = make:lower()
                if not seen[make] then
                    seen[make] = true
                    makers[#makers + 1] = make
                end
            end
        end
        table.sort(makers)
    end
    cb({ makes = makers })
end)

-- ---- give (moved verbatim from tools/items.lua) ----

RegisterNUICallback('ibGiveItem', function(data, cb)
    TriggerServerEvent('spur_core:server:ibGiveItem', data.itemKey, data.amount)
    cb('ok')
end)
