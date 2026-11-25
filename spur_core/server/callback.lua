-- ========================================
-- Awaitable callback system (server)
-- ========================================
-- External resources register handlers here.
-- Client calls Callback(name, ...) → server runs handler → returns result.

local _serverCallbacks = {}   -- [name] = handler

-- Global for use within spur_core. The transport only: WHO owns a name is SecureCallback's
-- question, answered by its own registry (secure.lua, _callbackNames), which refuses another
-- resource's name before it gets here. When an owner stops, secure.lua marks its entry dead and the
-- wrapper registered here answers "That is no longer available".
function RegisterCallback(name, handler)
    _serverCallbacks[name] = handler
end

-- Handle incoming callback requests from clients.
--
-- The one unguarded door in the framework, and it has to be: SecureCallback is built on top of this
-- event, so it cannot itself be a SecureCallback. Everything SecureCallback does (schema, ACE,
-- session check, per-action rate limit) happens INSIDE the handler this looks up.
--
-- What it still has is a ceiling: a call rate, and a bound on what an unknown name may print (on a
-- txAdmin server every print is a disk write).
--
-- The ceiling is deliberately generous (25 ms with a burst of 40): a FLOOD CEILING, nothing more.
-- Every SecureCallback has its own rateLimit/burst in its schema, and this runs first, so it sits
-- above every burst a schema declares (a furnished tower streaming in fires a furniture fetch per
-- room in one tick). A flood is still orders of magnitude above this.
-- Refusals are dropped silently rather than answered, because replying to a flood means generating
-- one outbound message per inbound one. The caller's own 10-second timeout (client/callback.lua)
-- answers it: `false, 'No answer from the server'`.
local CALLBACK_RATE_MS    = 25
local CALLBACK_RATE_BURST = 40

--- Unknown names are counted, not printed. A name is client-supplied text and must never reach
--- the console unbounded; the count still surfaces a genuinely broken satellite.
---
--- CAPPED AT UNKNOWN_NAMES_MAX DISTINCT NAMES. Each NEW name was a table entry and a console line,
--- so a client sending a fresh name every call grew both without limit (about twenty a second at
--- the rate limit, forever, from anyone connected). A broken satellite's name is among the first
--- seen, so the cap costs no diagnosis; names past it are only counted in _unknownOverflow.
local _unknownCallbackHits = {}
local _unknownNames        = 0
local _unknownOverflow     = 0
local UNKNOWN_NAMES_MAX    = 64

--- [src] = { n = <dropped since the last print>, at = <ms of the last print> }
---
--- Drops are visible, but throttled: one line per player per five seconds, carrying the COUNT, so it
--- never becomes the flood it is reporting. (A dropped callback is answered by the client's own
--- 10-second timeout, which surfaces as a UI that simply does not open.)
local _cbDropLog = {}
local CB_DROP_LOG_MS = 5000

RegisterNetEvent('spur_core:server:triggerCallback', function(cbId, name, ...)
    local src = source

    if not RateLimit(src, 'triggerCallback', CALLBACK_RATE_MS, CALLBACK_RATE_BURST) then
        if Config.LogSecureRejections ~= false then
            local rec = _cbDropLog[src]
            if not rec then rec = { n = 0, at = 0 }; _cbDropLog[src] = rec end
            rec.n = rec.n + 1

            local now = GetGameTimer()
            if now - rec.at >= CB_DROP_LOG_MS then
                rec.at = now
                print(('[spur_core:callback] REFUSED %d callback(s) from src %s in the last %dms '
                    .. '— rate limit %dms/burst %d. The client is seeing these as timeouts.')
                    :format(rec.n, tostring(src), CB_DROP_LOG_MS, CALLBACK_RATE_MS, CALLBACK_RATE_BURST))
                rec.n = 0
            end
        end
        return
    end

    -- Anything the client sends is text of its choosing. Bound it before it is used as a table
    -- key, compared, or logged. 128, SecureCallback's own limit on a name.
    if type(name) ~= 'string' or #name > 128 then return end

    local handler = _serverCallbacks[name]
    if handler then
        local ok, err = pcall(function(...)
            local results = table.pack(handler(src, ...))
            TriggerClientEvent('spur_core:client:callbackResponse', src, cbId, results)
        end, ...)
        if not ok then
            print(('[spur_core] ERROR in callback "%s": %s'):format(name, tostring(err)))
            -- `false, reason`, the same shape as a refusal (never a truthy table a caller would take
            -- for success). The error's own text stays here in the console.
            TriggerClientEvent('spur_core:client:callbackResponse', src, cbId,
                table.pack(false, 'Server error'))
        end
    else
        -- First sighting of a given name prints once; repeats only increment. A satellite that
        -- forgot to register something still shows up, and a flood cannot ride the log.
        local hits = _unknownCallbackHits[name]
        if hits then
            _unknownCallbackHits[name] = hits + 1
        elseif _unknownNames < UNKNOWN_NAMES_MAX then
            _unknownNames = _unknownNames + 1
            _unknownCallbackHits[name] = 1
            -- One line: the name is the client's text, and a newline in it would forge a line in the
            -- console and the txAdmin log. Control characters become '?'.
            -- (Not %q: Lua writes a newline there as a backslash and a real newline.)
            print(('[spur_core] WARNING: unknown callback "%s" (first sighting, from player %d)')
                :format((name:gsub('%c', '?')), src))
        else
            _unknownOverflow = _unknownOverflow + 1
        end
        -- Answered at once, so the client is not left waiting out its timeout, and answered the
        -- way every refusal is.
        TriggerClientEvent('spur_core:client:callbackResponse', src, cbId,
            table.pack(false, 'Unknown callback'))
    end
end)

-- The drop counter is keyed on a source, and sources are reused. Left alone it would hand the
-- next player to take that slot somebody else's backlog, and print a count for refusals that
-- happened to a player who has already gone.
AddEventHandler('playerDropped', function()
    _cbDropLog[source] = nil
end)

-- ---- Deliberately not exported ----
--
-- RegisterCallback has no schema, no session check, no rate limit of its own and no Event Monitor
-- entry. SecureCallback is the only public way in: the same handler, plus a schema:
--
--     exports.spur_core:SecureCallback('myapp:getBalance', {
--         rateLimit = 250,
--         params = { { 'accountId', 'id' } },
--     }, function(source, player, accountId) ... end)
--
-- The global stays available INSIDE spur_core, where the transport and the dev tools need it.
