-- Voice system, client side: which resource carries the voices (server/voice_system.lua). The server announces every
-- change and on character load. Callers ask GetVoiceSystem and listen for the local event spur_core:voice:systemChanged.

local current = false   -- { resource, label, features }, or false

local function running(v)
    return v and GetResourceState(v.resource) == 'started' and v or false
end

local function changed()
    local v = running(current)
    WhipEmit('spur_core:voice:systemChanged', {
        resource = v and v.resource or nil, label = v and v.label or nil, features = v and v.features or nil,
    })
end

RegisterNetEvent('spur_core:client:voiceSystem', function(v)
    v = (type(v) == 'table' and type(v.resource) == 'string') and v or false
    local was = current and current.resource or nil
    current = v
    if (v and v.resource or nil) ~= was then changed() end
end)

-- Noticed here first, as the server's word arrives later.
AddEventHandler('onClientResourceStop', function(res)
    if current and res == current.resource then changed() end
end)

exports('GetVoiceSystem', function()
    local v = running(current)
    if not v then return false end
    local f = {}
    for k, x in pairs(v.features or {}) do f[k] = x end
    return { resource = v.resource, label = v.label, features = f }
end)
