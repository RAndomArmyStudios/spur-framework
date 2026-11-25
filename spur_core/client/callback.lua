-- ========================================
-- AWAITABLE CALLBACK SYSTEM (Client)
-- ========================================
-- Call Callback(name, ...) to send a request to the server and
-- await the response inline. Uses promise + Citizen.Await.
--
-- WHAT COMES BACK. Whatever the server's handler answered — or, when there was no answer to give,
-- `false, reason`:
--
--   refused by whip's gate   false, 'Rate limited' | 'Player is dead' | 'Too far away' | '<param>: …'
--   the handler crashed      false, 'Server error'
--   no such callback         false, 'Unknown callback'
--   its resource stopped     false, 'That is no longer available'
--   no answer in 10 seconds  false, 'No answer from the server'
--
-- `if not result then` catches them all; the second value says why.

local _cbs = {}
local _cbId = 0
local CALLBACK_TIMEOUT = 10000  -- 10 seconds

-- Global for use within spur_core
function Callback(name, ...)
    _cbId = _cbId + 1
    local id = _cbId
    local p = promise.new()
    _cbs[id] = p

    TriggerServerEvent('spur_core:server:triggerCallback', id, name, ...)

    -- Timeout so client doesn't hang forever if server never responds
    local cbId = id
    SetTimeout(CALLBACK_TIMEOUT, function()
        if _cbs[cbId] then
            _cbs[cbId]:resolve(nil)
            _cbs[cbId] = nil
        end
    end)

    local results = Citizen.Await(p)
    if results then
        -- Up to `n`, not to the first nil: the server packs its answer with table.pack, and
        -- `return ok, nil, extra` unpacked by length alone could lose everything after the nil.
        return table.unpack(results, 1, results.n or #results)
    end
    return false, 'No answer from the server'
end

-- Receive callback responses from server
RegisterNetEvent('spur_core:client:callbackResponse', function(cbId, results)
    if _cbs[cbId] then
        _cbs[cbId]:resolve(results)
        _cbs[cbId] = nil
    end
end)

-- Export for external resources
exports('Callback', Callback)
