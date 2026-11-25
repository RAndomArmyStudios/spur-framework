-- ============================================
-- /whip SECTION — Item Log (client wiring)
-- ============================================
--
-- The Item Log opens on everything that happened, and has an Economy tab (html/js/wp/itemlog.js). These carry its three reads to the server and answer the page with one
-- shape, { ok, why, ... }. One item's own life (alItem) and the teleport (alTeleport) are the Player
-- Manager's, in playerManager.lua, which both timelines share.

local function ask(name, ...)
    local res, why = Callback(name, ...)
    if res == false or res == nil then return { ok = false, why = why or 'The server did not answer' } end
    return res
end

RegisterNUICallback('alSetup', function(_, cb)
    cb(ask('spur_core:alSetup'))
end)

RegisterNUICallback('alFeed', function(data, cb)
    local rows, why = Callback('spur_core:alFeed', type(data) == 'table' and data or {})
    if type(rows) ~= 'table' then
        cb({ ok = false, why = why or 'The server did not answer' })
        return
    end
    cb({ ok = true, rows = rows })
end)

RegisterNUICallback('alItemActivity', function(data, cb)
    cb(ask('spur_core:alItemActivity', type(data) == 'table' and data.since))
end)

RegisterNUICallback('alItemInfo', function(data, cb)
    cb(ask('spur_core:alItemInfo', type(data) == 'table' and tostring(data.uid or '') or ''))
end)

RegisterNUICallback('alEconomy', function(data, cb)
    data = type(data) == 'table' and data or {}
    cb(ask('spur_core:alEconomy', data.since, data.itemKey, data.bucket))
end)
