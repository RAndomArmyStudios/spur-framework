-- ============================================
-- Database guard — no database call waits for ever
-- ============================================
-- oxmysql's waiting calls (MySQL.query.await and the rest) never answer when oxmysql cannot get a
-- connection: the error escapes rawQuery and rawTransaction to a promise nobody awaits (oxmysql
-- 2.12.0). The caller then waits for good, and when the caller is the save thread nothing in whip
-- saves again until a restart.
--
-- This wraps every waiting call in spur_core's MySQL table once, right after oxmysql's lib loads,
-- so a call that gets no answer fails like any other database error and every caller's existing
-- error handling takes over. Calls that do answer behave exactly as before.
--
-- Our oxmysql is also patched (dev/oxmysql-p001.diff), so a lost connection fails at once rather than
-- after ANSWER_MS. The patch is optional: whip runs on stock oxmysql, with this guard as what promises
-- every call an answer (the setup report says whether the patch is in: server/setup_report.lua).

--- How long a call may go unanswered. Above InnoDB's lock-wait timeout (50 s), so a slow but real
--- query always answers first, and a timeout means the call never reached the database.
local ANSWER_MS = 65000

--- A transaction waits far longer: given up while it can still commit, it lands AFTER
--- its retry: the retry was built against a snapshot that never heard of it, and an item ends up in two
--- places on disk. Each of its statements can wait out the lock timeout, so 65 s does not prove it never
--- reached the database. Every whip transaction is one save (Stores.runTransaction), and the stall
--- watchdog there tells admins each minute while one waits.
local TX_ANSWER_MS = 600000

--- Schema changes can legitimately run for minutes on a big table (a migration adding an index).
local function isSchemaChange(query)
    if type(query) ~= 'string' then return false end
    local verb = query:match('^%s*(%a+)')
    verb = verb and verb:upper()
    return verb == 'ALTER' or verb == 'CREATE' or verb == 'DROP' or verb == 'OPTIMIZE'
end

local function guard(method, original)
    local limit = method == 'transaction' and TX_ANSWER_MS or ANSWER_MS
    return function(query, parameters)
        if isSchemaChange(query) then return original(query, parameters) end

        local p, done, started = promise.new(), false, GetGameTimer()
        -- The give-up timer, CLEARED WHEN THE CALL ANSWERS (scale audit SC-DB-5): left running, every call
        -- kept one alive for 65 s (10 min for a transaction) — about 16k at once at 1000 players.
        local timer
        Citizen.CreateThreadNow(function()
            local ok, result = pcall(original, query, parameters)
            if done then
                print(('^3[spur_core:db] a %s answered %d s after it was given up as lost (%s)^0')
                    :format(method, (GetGameTimer() - started) // 1000, ok and tostring(result) or 'error'))
                return
            end
            done = true
            if timer then ClearTimeout(timer) end
            p:resolve({ ok, result })
        end)
        if not done then
            timer = SetTimeout(limit, function()
                if done then return end
                done = true
                p:resolve({ false, ('the database did not answer this %s within %d s'):format(method, limit // 1000) })
            end)
        end

        local r = Citizen.Await(p)
        if not r[1] then
            -- Is the database itself gone, or just this query? (db_health.lua, loaded after this file)
            if DbHealth then DbHealth.suspect(r[2]) end
            error(r[2], 0)
        end
        return r[2]
    end
end

for _, method in ipairs({ 'scalar', 'single', 'query', 'insert', 'update', 'prepare', 'transaction', 'rawExecute' }) do
    local entry = MySQL[method]
    if type(entry) == 'table' and entry.await then
        entry.await = guard(method, entry.await)
    end
end
