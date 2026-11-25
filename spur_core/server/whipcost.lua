-- ============================================
-- whipcost [seconds] — what each timed section costs on the SERVER (the server console)
-- ============================================
--
-- The server half of /whipcost (tools/whipcost.lua is the player's game's). Every resource that loads lib/cost.lua
-- on the server (spur_core does, a satellite with server_script '@spur_core/lib/cost.lua') times the sections it
-- marks with WhipCost.start / WhipCost.stop for a while (20 s unless asked; 5 to 120), then hands its totals here,
-- printed as one table, the dearest first: runs a second, microseconds a run, and milliseconds of the server's time a
-- second (1000 is all of one core). Time only: lib/cost.lua says why.

local DEFAULT_SECONDS, MIN_SECONDS, MAX_SECONDS = 20, 5, 120
local running = nil   -- { at, seconds, reports = { [resource] = report } } while one runs

AddEventHandler('spur_core:cost:serverReported', function(report)
    if running and type(report) == 'table' and type(report.resource) == 'string' then
        running.reports[report.resource] = report
    end
end)

local function printTable(run)
    local rows = {}
    for res, r in pairs(run.reports) do
        for name, ms in pairs(r.ms or {}) do
            local n = (r.runs or {})[name] or 0
            rows[#rows + 1] = { res = res, name = name, ms = ms, runs = n }
        end
    end
    table.sort(rows, function(a, b) return a.ms > b.ms end)
    local secs = run.seconds
    print(('[spur] ==== whipcost: %d s on the server, %d section%s ===='):format(secs, #rows, #rows == 1 and '' or 's'))
    if #rows == 0 then
        print('[spur] nothing was timed: mark a loop with WhipCost.start / WhipCost.stop (server_script \'@spur_core/lib/cost.lua\')')
    end
    print(('[spur] %-12s %-48s %10s %10s %10s'):format('resource', 'section', 'runs/s', 'us/run', 'ms/s'))
    for _, r in ipairs(rows) do
        print(('[spur] %-12s %-48s %10.1f %10.1f %10.3f'):format(r.res:sub(1, 12), r.name:sub(1, 48), r.runs / secs,
            r.runs > 0 and (r.ms * 1000 / r.runs) or 0, r.ms / secs))
    end
    print('[spur] ms/s is milliseconds of the server\'s CPU a second: 1000 is one whole core')
end

-- The server console, or a player with whip.devtools and developer mode on (the table goes to the console).
RegisterCommand('whipcost', function(source, args)
    if source ~= 0 and not DevTools.isAllowed(source) then return end
    if running then print('[spur] whipcost is already running') return end
    local secs = math.floor(tonumber(args[1]) or DEFAULT_SECONDS)
    secs = math.max(MIN_SECONDS, math.min(MAX_SECONDS, secs))
    local run = { at = GetGameTimer(), seconds = secs, reports = {} }
    running = run
    print(('[spur] whipcost: timing the server for %d s'):format(secs))
    TriggerEvent('spur_core:cost:serverStarted', { seconds = secs })
    SetTimeout(secs * 1000, function()
        TriggerEvent('spur_core:cost:serverStopped')
        -- The reports come back as each resource's handler runs, at once: a moment for them all.
        SetTimeout(500, function()
            if running == run then running = nil end
            printTable(run)
        end)
    end)
end, false)
