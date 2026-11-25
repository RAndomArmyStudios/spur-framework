-- ============================================
-- spur_core's own stop, in one fixed order — server/lifecycle.lua
-- ============================================
--
-- Several stop steps must run before another: panels, shops and money holds only QUEUE what they hand
-- back, and player_lifecycle's step is the one that SENDS the queue.
--
-- CfxLua does not call a resource's handlers for one event in the order they were added: it files
-- them under keys from ONE counter shared by every AddEventHandler and exports() call in the
-- resource, and walks them with pairs() (citizen/scripting/lua/scheduler.lua), hash order, which
-- moves whenever a handler or an export is added anywhere.
--
-- So there is ONE stop handler, here, and each file that must do something when spur_core stops adds
-- a numbered step with CoreStop.add. The steps run in number order, ties in the order they were added.
--
-- EACH STEP RUNS IN ITS OWN THREAD. A stop handler that waits never comes back — the resource is gone
-- — and everything after the wait is lost. The world clock's save waits; so did a bank refund. In its
-- own thread a waiting step loses only its own tail (its query is already with oxmysql), and every
-- step after it still runs.
--
-- The numbers, so a new step finds its place (each line names the files that add it; grep
-- "CoreStop.add(" to check this table against the code):
--    5  end what runs on its own: the Director's runs (director/main), the Systems (systems/main),
--       and write down what the run containers held (containers)
--   10  stop being ready (player_lifecycle), freeze the stats cache (player_lifecycle), take back
--       temporary dev tools (devtools), the test seams (testseams)
--   15  delete what spur_core made in the world: held props (held_props), NPCs (npcs)
--   20  hand back what exists only in memory: open panels (panels), shop baskets (shops), money held for
--       a metered service — a pump's fill (money_holds)
--   40  mark what moved: players (player), cars (vehicles)
--   60  send every owed write — stores, rows, car stats, log rows (player_lifecycle — Stores.dispatchOwed)
--   90  anything that waits on the database: the world clock (time)
-- ============================================

CoreStop = { _steps = {} }

--- True from the moment spur_core's own stop begins. For code that must not wait then — a wait in a
--- stop step never comes back — and has a way to send its write without waiting (Money's bank
--- refund).
CoreStop.running = false

--- Add a step to spur_core's own stop. Server files of spur_core only.
---@param order number  see the table above
---@param name string   for the console, when a step fails
---@param fn function   must not rely on anything that runs at a higher number
function CoreStop.add(order, name, fn)
    local steps = CoreStop._steps
    steps[#steps + 1] = { order = order, name = name, fn = fn, seq = #steps + 1 }
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    CoreStop.running = true

    local steps = {}
    for i, s in ipairs(CoreStop._steps) do steps[i] = s end
    table.sort(steps, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.seq < b.seq
    end)

    for _, s in ipairs(steps) do
        Citizen.CreateThreadNow(function()
            local ok, err = pcall(s.fn)
            if not ok then
                print(('[spur_core] stop step "%s" failed: %s'):format(s.name, tostring(err)))
            end
        end)
    end
end)

-- ============================================
-- spur_core's final save, before txAdmin kills the server
-- ============================================
--
-- txAdmin's stop and restart never stop resources: they fire txAdmin:events:serverShuttingDown, kick
-- everyone, wait the Shutdown Notice Delay and kill the process, so CoreStop does not run. The final
-- save runs inside that delay with the server still alive, so every write is waited for, most
-- valuable first. Each file adds its step with FinalSave.add. The same save runs at a scheduled
-- restart's last warning. CoreStop stays the fire-and-forget version for `restart spur_core`.
--
-- The numbers (each line names the files that add it; grep "FinalSave.add(" to check this table
-- against the code):
--    5  settle every money hold in full (money_holds: a pump's fill) — before 10 writes the stores
--    8  write down what the run containers held (containers)
--   10  stores: pockets, stashes, trunks (stores)
--   11  a console line per store unit kind, counting what it had waiting (stores, Stores.defineUnit)
--   20  character rows and positions (player)
--   40  vehicle positions (vehicles)
--   50  wait for the kicked players' own saves (player_lifecycle)
--   52  stores again, until nothing is owed (stores)
--   60  the activity log (activity_log)
--   70  the world clock (time)
-- ============================================

FinalSave = { _steps = {} }

--- txAdmin's Shutdown Notice Delay whip asks for (txAdmin → Settings → FXServer). 5 s is its default.
local SAFE_DELAY_MS = 15000
local KVP = 'whip:finalSave'

--- Add a step to the final save. Server files of spur_core only.
---@param order number  see the table above
---@param name string   for the console, when a step fails or is cut off
---@param fn fun(deadline: number, shutdown: boolean): boolean|nil  may wait; stop by `deadline`
---                    (GetGameTimer). Returns false when something it owed was not written.
---                    `shutdown` is true when txAdmin is killing the server and kicking everyone.
---@param waiting (fun(): number)|nil  how many of its things are waiting to be saved, for the
---                    console (FinalSave.waiting). Leave out for a step that repeats another's.
function FinalSave.add(order, name, fn, waiting)
    local steps = FinalSave._steps
    steps[#steps + 1] = { order = order, name = name, fn = fn, waiting = waiting, seq = #steps + 1 }
end

--- What is waiting to be saved right now, per step that can say: { { name, count } }, and the total.
---@return table[] list
---@return number total
function FinalSave.waiting()
    local list, total = {}, 0
    for _, s in ipairs(FinalSave._steps) do
        if s.waiting then
            local ok, n = pcall(s.waiting)
            n = ok and tonumber(n) or 0
            list[#list + 1] = { name = s.name, count = n, order = s.order }
            total = total + n
        end
    end
    table.sort(list, function(a, b) return a.order < b.order end)
    return list, total
end

--- Run every step in order, one after another, until the time is up.
---@param budgetMs number
---@param shutdown boolean
---@return string[] unsaved  names of the steps that did not write everything (empty = all saved)
---@return number tookMs
function FinalSave.run(budgetMs, shutdown)
    local t0 = GetGameTimer()
    local deadline = t0 + budgetMs

    local steps = {}
    for i, s in ipairs(FinalSave._steps) do steps[i] = s end
    table.sort(steps, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.seq < b.seq
    end)

    local unsaved = {}
    for i, s in ipairs(steps) do
        if GetGameTimer() >= deadline then
            local left = {}
            for j = i, #steps do
                left[#left + 1] = steps[j].name
                unsaved[#unsaved + 1] = steps[j].name
            end
            print(('^1[spur_core] final save: out of time, not reached: %s^0'):format(table.concat(left, ', ')))
            break
        end
        local ok, saved = pcall(s.fn, deadline, shutdown)
        if not ok then
            print(('[spur_core] final save step "%s" failed: %s'):format(s.name, tostring(saved)))
        end
        if not ok or saved == false then unsaved[#unsaved + 1] = s.name end
    end
    return unsaved, GetGameTimer() - t0
end

-- The KVP says "started" until the save ends, so a kill that cuts it short is found at the next boot.
AddEventHandler('txAdmin:events:serverShuttingDown', function(data)
    local delay = type(data) == 'table' and tonumber(data.delay) or 5000
    SetResourceKvp(KVP, ('started 0 %d'):format(delay))
    if delay < SAFE_DELAY_MS then
        print(('^3[spur_core] txAdmin kills the server %.1f s from now. Whip saves the most valuable things first; '
            .. 'whatever is not saved by then is lost. Raise txAdmin → Settings → FXServer → Shutdown Notice Delay to %d s.^0')
            :format(delay / 1000, SAFE_DELAY_MS // 1000))
    end
    print('[spur_core] server shutting down: final save started')

    -- Half a second short of the kill, so the last step is not cut off mid-write.
    local unsaved, took = FinalSave.run(math.max(delay - 500, 250), true)
    SetResourceKvp(KVP, ('%s %d %d %s'):format(#unsaved == 0 and 'done' or 'cut', took, delay, table.concat(unsaved, '|')))
    if #unsaved == 0 then
        print(('[spur_core] final save finished in %.1f s (txAdmin gives %.1f s)'):format(took / 1000, delay / 1000))
    else
        print(('^1[spur_core] final save could NOT write everything (%.1f s of %.1f s): %s — those changes are lost^0')
            :format(took / 1000, delay / 1000, table.concat(unsaved, ', ')))
    end
end)

-- A scheduled restart warns at 30, 15 … 1 minutes out; the last warning saves everything early.
AddEventHandler('txAdmin:events:scheduledRestart', function(data)
    local remaining = type(data) == 'table' and tonumber(data.secondsRemaining) or nil
    if remaining and remaining > 60 then return end
    local unsaved, took = FinalSave.run(30000, false)
    if #unsaved == 0 then
        print(('[spur_core] scheduled restart: everything saved early (%.1f s)'):format(took / 1000))
    else
        print(('^1[spur_core] scheduled restart: could not save %s early — still owed, retried until the restart^0')
            :format(table.concat(unsaved, ', ')))
    end
end)

-- The last shutdown's save, told once spur_core is up.
AddEventHandler('spur_core:onReady', function(info)
    if type(info) ~= 'table' or info.reason ~= 'coreStarted' then return end
    local last = GetResourceKvpString(KVP)
    if not last then return end
    DeleteResourceKvp(KVP)

    local state, took, delay, names = last:match('^(%a+) (%d+) (%d+) ?(.*)$')
    if not state then return end
    took, delay = tonumber(took), tonumber(delay)
    local fix = ('Raise txAdmin → Settings → FXServer → Shutdown Notice Delay to %d s.')
        :format(delay < SAFE_DELAY_MS and SAFE_DELAY_MS // 1000 or math.min(60, delay // 500))
    if state == 'started' then
        print(('^1[spur_core] the last shutdown killed the server before whip finished saving (txAdmin gave %.1f s): '
            .. 'changes from the last seconds before it may be lost. %s^0'):format(delay / 1000, fix))
    elseif state == 'cut' then
        -- Out of time, or the database would not take the writes: the console from then says which.
        print(('^1[spur_core] the last shutdown could not save everything (%s): changes from just before it are lost. '
            .. 'If the database was fine then, the time was too short — %s^0')
            :format(names ~= '' and (names:gsub('|', ', ')) or 'see the console from then', fix))
    elseif took > delay // 2 then
        print(('^3[spur_core] the last shutdown only just saved in time (%.1f of the %.1f s txAdmin gave). %s^0')
            :format(took / 1000, delay / 1000, fix))
    end
end)

-- ============================================
-- What starts once spur_core is ready — CoreStart
-- ============================================
--
-- Work that needs spur_core's tables and loads done, but must neither hold up start-up nor stop it when
-- it fails: the Director, the Systems Creator, the permission grants. Each step runs in its own thread
-- once spur_core is ready (player_lifecycle.lua's start), after the onReady announce, with no time
-- limit: a start that takes long (a slow first database, a big world) starts them later, never without
-- them. A start that halts never runs them; the halt says why.

CoreStart = { _steps = {} }

--- Run `fn` once spur_core is ready, in its own thread. Server files of spur_core only, at file scope.
---@param name string  for the console, when it fails
---@param fn function
function CoreStart.add(name, fn)
    local steps = CoreStart._steps
    steps[#steps + 1] = { name = name, fn = fn }
end

--- spur_core is ready: start every step. player_lifecycle.lua's start only.
function CoreStart.run()
    for _, s in ipairs(CoreStart._steps) do
        CreateThread(function()
            local ok, err = pcall(s.fn)
            if not ok then print(('^1[spur_core] %s failed to start: %s^0'):format(s.name, tostring(err))) end
        end)
    end
end

-- ============================================
-- spur_core's own periodic work — Every
-- ============================================
--
-- A loop that runs for the life of spur_core must survive one error: several bound a leak (the
-- session-car release, the idle stash unload) or keep players fed (the ground and door cell sync).
-- Here, with the stop, because this file loads first: every loop can use it from file scope.

--- Run `fn` every `ms` milliseconds for the life of spur_core: wait, run, wait, run. A pass that errors
--- is printed with `name` (the first five, then every hundredth) and the loop carries on. `fn` may
--- wait. It may also return a number of milliseconds to wait before the next pass instead of `ms` —
--- for a loop that sleeps longer while there is nothing to do.
---
--- `ms` MAY BE A FUNCTION answering the period, asked before each wait, for an interval that is a
--- setting: one changed in /whip → Settings takes effect from the next wait. An answer that is not a
--- number of 0 or more keeps the last good one (and the first ever falls back to 1 s), said once.
---@param name string   says which loop failed
---@param ms number|fun(): number
---@param fn fun(): number|nil
function Every(name, ms, fn)
    local last, warned = 1000, false
    local function period()
        if type(ms) ~= 'function' then return ms end
        local ok, answer = pcall(ms)
        local v = ok and tonumber(answer) or nil
        if v and v == v and v >= 0 and v ~= math.huge then
            last = v
        elseif not warned then
            -- %s, never %d: a period of 5000.5 ms is a number %d throws on, and this runs outside
            -- the pcall that keeps the loop alive.
            warned = true
            print(('^3[spur_core] %s: its period answered %s, not milliseconds; keeping %s ms^0')
                :format(name, ok and tostring(answer) or ('an error: ' .. tostring(answer)), tostring(last)))
        end
        return last
    end
    -- Named after `fn` (its file and lines), so the profiler shows each job, not this one loop for all of them
    ErrorTap.threadLike(fn, function()
        local fails, nextMs = 0, period()
        while true do
            Wait(nextMs)
            local ok, r = pcall(fn)
            if ok then
                nextMs = tonumber(r) or period()
            else
                fails = fails + 1
                if fails <= 5 or fails % 100 == 0 then
                    print(('^1[spur_core] %s failed (failure %d; it keeps running): %s^0'):format(name, fails, tostring(r)))
                end
                nextMs = period()
            end
        end
    end)
end
