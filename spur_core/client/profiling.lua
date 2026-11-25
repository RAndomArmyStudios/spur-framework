-- Client profiling: event handlers, statebag handlers and NUI callbacks run on no thread of their own, so
-- this wraps the four registration functions to give each handler a ProfilerEnterScope named after its event.
-- Loaded first in fxmanifest.lua: only registrations made after the wrappers are installed are caught.
--
-- A scope must not survive a yield (the rest of the frame would be charged to it): a handler's first call is
-- made without a scope, reading the frame counter either side; if the frame did not advance it is scoped
-- from then on, otherwise never.

-- Off unless asked for; the off path installs no wrappers (they cost every handler call). A replicated
-- convar, checked once at load.
--
--     setr whip_profiling 1      in server.cfg, then restart spur_core
local PROFILING_ON = GetConvarInt('whip_profiling', 0) == 1

if not PROFILING_ON then return end

--- Whether each handler is safe to scope: nil = not yet called, true = does not yield, false = yields.
local safe = {}

--- The real natives, captured before the wrappers replace them.
local _AddEventHandler          = AddEventHandler
local _RegisterNetEvent         = RegisterNetEvent
local _AddStateBagChangeHandler = AddStateBagChangeHandler
local _RegisterNUICallback      = RegisterNUICallback

-- The wrapper

--- Call `fn` under a profiler scope named `name`, learning on the first call whether that is safe.
--- Errors are caught and re-printed with the handler's name, since one escaping between Enter and Exit leaves the scope open.
---@param name string
---@param fn function
local function invoke(name, fn, ...)
    local known = safe[name]

    if known == nil then
        -- First call: measured, not scoped.
        local frame = GetFrameCount()
        local ok, err = pcall(fn, ...)
        safe[name] = (GetFrameCount() == frame)
        if not ok then
            print(('[spur_core:prof] handler "%s" errored: %s'):format(name, tostring(err)))
        end
        return
    end

    if not known then
        -- Known to yield. Never scoped.
        local ok, err = pcall(fn, ...)
        if not ok then
            print(('[spur_core:prof] handler "%s" errored: %s'):format(name, tostring(err)))
        end
        return
    end

    local frame = GetFrameCount()
    ProfilerEnterScope(name)
    local ok, err = pcall(fn, ...)
    ProfilerExitScope()

    -- It yielded after all (a Wait behind a branch not taken before): demote it.
    if GetFrameCount() ~= frame then
        safe[name] = false
    end

    if not ok then
        print(('[spur_core:prof] handler "%s" errored: %s'):format(name, tostring(err)))
    end
end

--- Every wrapper produced, so none is wrapped twice. Weak keys, so a removed handler is freed.
local isWrapped = setmetatable({}, { __mode = 'k' })

--- Wrap a handler so it reports under `name`. A wrapper is never wrapped: RegisterNetEvent(name, handler) calls
--- AddEventHandler with the same function, which would open the scope twice. The net event keeps the name whip:net:<name>.
---@param name string
---@param fn function
---@return function
local function wrap(name, fn)
    if isWrapped[fn] then return fn end

    local w = function(...) return invoke(name, fn, ...) end
    isWrapped[w] = true
    return w
end

-- The four registration functions, named with a prefix per kind so a capture groups events and NUI callbacks.

function AddEventHandler(eventName, handler)
    if type(handler) ~= 'function' then return _AddEventHandler(eventName, handler) end
    return _AddEventHandler(eventName, wrap('whip:ev:' .. tostring(eventName), handler))
end

--- `RegisterNetEvent(name)` takes no handler (passed straight through); `RegisterNetEvent(name, fn)`
--- registers and handles at once.
function RegisterNetEvent(eventName, handler)
    if handler == nil then return _RegisterNetEvent(eventName) end
    if type(handler) ~= 'function' then return _RegisterNetEvent(eventName, handler) end
    return _RegisterNetEvent(eventName, wrap('whip:net:' .. tostring(eventName), handler))
end

--- Named by key rather than by bag (bag names are per-entity), so the key says which subsystem is charged.
function AddStateBagChangeHandler(keyFilter, bagFilter, handler)
    if type(handler) ~= 'function' then
        return _AddStateBagChangeHandler(keyFilter, bagFilter, handler)
    end
    return _AddStateBagChangeHandler(keyFilter, bagFilter,
        wrap('whip:bag:' .. tostring(keyFilter or '*'), handler))
end

function RegisterNUICallback(name, handler)
    if type(handler) ~= 'function' then return _RegisterNUICallback(name, handler) end
    return _RegisterNUICallback(name, wrap('whip:nui:' .. tostring(name), handler))
end
