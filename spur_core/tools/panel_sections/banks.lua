-- ============================================
-- /whip SECTION — Banks (client wiring)
-- ============================================
--
-- The section lifecycle, and each thing the page asks of the server (server/bank_admin.lua). The page gets its answer
-- straight back from the callback: { ... }, or { ok = false, why } when the server refused or said nothing.

PanelSections['banks'] = {
    enter = function()
        CreateThread(function()
            -- Asking also registers this client as a viewer of balance changes.
            local data = Callback('spur_core:bank:directory')
            WhipPanelData('banks', 'all', type(data) == 'table' and data or { entries = {} })
        end)
    end,
    leave = function()
        TriggerServerEvent('spur_core:server:bankClosed')
    end,
}

RegisterNetEvent('spur_core:client:bankChanged', function(ids)
    WhipPanelData('banks', 'changed', { ids = type(ids) == 'table' and ids or {} })
end)

local function ask(name, ...)
    local res, why = Callback(name, ...)
    if type(res) ~= 'table' then res = { ok = false, why = why or 'The server did not answer' } end
    return res
end

RegisterNUICallback('bankDirectory', function(_, cb)
    cb(ask('spur_core:bank:directory'))
end)

RegisterNUICallback('bankDashboard', function(data, cb)
    cb(ask('spur_core:bank:dashboard', data.kind, tostring(data.id), tonumber(data.charId) or 0))
end)

RegisterNUICallback('bankLedger', function(data, cb)
    cb(ask('spur_core:bank:ledger', data.kind, tostring(data.id), tonumber(data.charId) or 0,
        tonumber(data.accountId) or 0, data.dir or 'all', tonumber(data.beforeId) or 0))
end)

RegisterNUICallback('bankCashLog', function(data, cb)
    cb(ask('spur_core:bank:cashLog', tostring(data.id), tonumber(data.charId) or 0, tonumber(data.beforeId) or 0))
end)

RegisterNUICallback('bankAccount', function(data, cb)
    cb(ask('spur_core:bank:account', tonumber(data.accountId) or 0))
end)

RegisterNUICallback('bankCreate', function(data, cb)
    cb(ask('spur_core:bank:create', data.kind, tostring(data.id), tonumber(data.charId) or 0, data.label or '',
        data.accountType or 'personal', tonumber(data.opening) or 0, data.reason or ''))
end)

RegisterNUICallback('bankChange', function(data, cb)
    cb(ask('spur_core:bank:change', tonumber(data.accountId) or 0, data.what, tostring(data.value or '')))
end)

RegisterNUICallback('bankMoney', function(data, cb)
    cb(ask('spur_core:bank:money', tonumber(data.accountId) or 0, data.way, tonumber(data.amount) or 0,
        data.reason or '', data.to or ''))
end)

RegisterNUICallback('bankClose', function(data, cb)
    cb(ask('spur_core:bank:close', tonumber(data.accountId) or 0, data.money or 'none', data.to or '', data.reason or ''))
end)

RegisterNUICallback('bankAccess', function(data, cb)
    cb(ask('spur_core:bank:access', tonumber(data.accountId) or 0, tonumber(data.charId) or 0, data.role))
end)
