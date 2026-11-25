-- ============================================
-- EVENTS — the one naming rule
-- ============================================
--
-- Every LOCAL event whip fires for other resources:
--
--     spur_core:<domain>:<pastTense>      one table payload
--
--     spur_core:item:added        { source, item, count, reason, by }
--     spur_core:vehicle:entered   { source, vehicleId, seat, ... }
--     spur_core:player:died       { reconnected }
--
-- `spur_core:client:` and `spur_core:server:` are for NETWORK events only. A resource listening for
-- whip's news uses AddEventHandler on a name without either word. A table payload can gain fields
-- without breaking listeners. types/events.lua lists every event and its payload.

--- Fire one of whip's local events.
---
--- Local only (TriggerEvent): listeners on this side of the network, in any resource.
---@param name string       the event, 'spur_core:<domain>:<pastTense>'
---@param payload table     its one table payload
function WhipEmit(name, payload)
    TriggerEvent(name, payload)
end
