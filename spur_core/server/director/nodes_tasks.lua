-- ============================================
-- Director — Start Tasks and Stop Tasks, and starting a placed thing's tasks
-- ============================================
--
-- A placed thing's TASKS (its page: server/director/tasks.lua) play on what the run made for it:
--   an NPC   every NPC the run made for it (one, or each wave of it): its brain (server/npcs.lua)
--   a car    the run's car (Spawn Car): Actors (server/actors.lua)
--   a prop   the run's prop (Show Prop): a timeline every game plays in step (server/prop_sets.lua)
-- The spawn cards start them with "Start its tasks"; Start Tasks starts them later, again from the top or
-- from where they were stopped; Stop Tasks stops them.
--
-- WHO A STEP POINTS AT is worked out by the server as the step starts, never by the game running it:
--   the nearest of the run's players (to the NPC, then), the one who set the card off, a placed thing (the
--   run's NPC or car, by its netId, else where it was placed), or a point. A car to get in is the run's car.
--
-- run.tasks[worldId] = { live = how many still play, why = how the last one ended, doneAt = a prop's end,
-- stoppedAt = { [member] = step }, stopped = one was stopped (Stop Tasks, or a list put in its place) }: where Stop
-- Tasks left them. Each start is a record of its own, handed to the card that started it: Start Tasks waits on its
-- own, never on a later card's (another Start Tasks, Play Take), so it is Finished only when its own lists finished.

local CORE = GetCurrentResourceName()

local define = DirectorKit.define

local LEAD_MS = 400   -- a prop's timeline starts this far ahead, so every game has it before it moves

local function dist2(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return dx * dx + dy * dy + dz * dz
end

--- The run player nearest a point (server ids), or nil.
local function nearestPlayer(run, at)
    local best, bestD
    for s in pairs(run.players) do
        local ped = GetPlayerPed(s)
        if ped and ped ~= 0 then
            local d = dist2(GetEntityCoords(ped), at)
            if not bestD or d < bestD then best, bestD = s, d end
        end
    end
    return best
end

--- What a placed thing is in the world now: the run's NPC (the first of its group still up) or car, by its
--- netId; else where it was placed.
local function thingNow(run, wid)
    local w = run.graph.world[wid]
    if not w then return nil end
    local h = Director.handleOf(run, wid)
    if w.kind == 'npc' and type(h) == 'table' then
        for _, id in ipairs(DirectorNodes.npcIds(h)) do
            local info = Npcs.get(id)
            if info and info.alive then return { tNet = info.netId } end
        end
    elseif w.kind == 'vehicle' and type(h) == 'table' and h.vehicleId then
        local ent = Vehicles.getEntity(h.vehicleId)
        if ent then return { tNet = NetworkGetNetworkIdFromEntity(ent) } end
    end
    local place = DirectorRuntime.place(run, wid)
    local c = type(place) == 'table' and type(place.def) == 'table' and place.def.coords or nil
    if type(c) == 'table' and tonumber(c.x) and tonumber(c.y) and tonumber(c.z) then
        return { tAt = { x = tonumber(c.x), y = tonumber(c.y), z = tonumber(c.z) } }
    end
    return nil
end

local emoteAnim = DirectorTasks.emoteAnim

local TAKE_LEAD_MS = 600   -- a take starts this far ahead, so the game playing it has it in hand

--- The game a run's takes play on (server/actors.lua's pin): ONE for all of them, so cars that hit each other
--- do so on one game and the recorded crash happens again. The player the card is about, else the run player
--- nearest the car; kept for the run's next take while they are still in it.
local function takePin(ctx, at)
    local run = ctx.run
    local pin = run.takePin
    if pin and run.players[pin] and GetPlayerName(pin) then return pin end
    pin = Director.playerOf(ctx)
    if not pin and at then pin = nearestPlayer(run, at) end
    run.takePin = pin
    return pin
end

--- The run's car for a placed one (its server entity), or nil.
local function vehicleOf(run, wid)
    local h = Director.handleOf(run, wid)
    local id = type(h) == 'table' and h.vehicleId or nil
    return id and Vehicles.getDef(id) and Vehicles.getEntity(id) or nil
end

--- A take's TRAILERS (its car's page keeps them with it: DirectorTakes.towOf), played with it. Each trailer the run has
--- made plays its own recorded track, its own take step from the same moment on the same game, so it goes where it went
--- (not where GTA would drag it); the car's step `p` carries the moments it was hitched and let go (p.tow: client/
--- actors.lua). A trailer the run has not made is left out, and said (Play Take makes them; a car's own Tasks need a
--- card that does). Each plays beside `car`'s list, and stops with it (Actors.runTasks opts.with).
local function towTracks(ctx, p, car)
    local tow = DirectorTakes.towOf(ctx.run.graph, p.take)
    if not tow then return end
    local nets = {}
    local ids = {}
    for wid in pairs(tow.tracks) do ids[#ids + 1] = wid end
    table.sort(ids)
    for _, wid in ipairs(ids) do
        local tid = tow.tracks[wid]
        local ent = vehicleOf(ctx.run, wid)
        local track = DirectorTakes.get(tid)
        if not ent then
            ctx:log('its trailer %s is not in the world: the driving event plays without it', wid)
        elseif not track then
            ctx:log('its trailer %s: its movement %s is not read yet (or is gone)', wid, tostring(tid))
        else
            local q = { take = tid, startAt = p.startAt, pin = p.pin }
            local ok, why = Actors.runTasks(CORE, ent, { steps = { { k = 'take', t = 'take', timing = 'until',
                giveUpMs = track.lengthMs + TAKE_LEAD_MS + 15000, p = q } }, after = 'stop', fight = false }, {
                tag = ctx:tag(), with = car,
                resolve = function(step)
                    local c = {}
                    for k, v in pairs(step.p) do c[k] = v end
                    return c
                end,
                log = function(t) ctx:log('%s: %s', wid, t) end,
            })
            if ok then nets[wid] = NetworkGetNetworkIdFromEntity(ent)
            else ctx:log('its trailer %s: %s', wid, tostring(why)) end
        end
    end
    local list = {}
    for _, e in ipairs(tow.events) do
        if nets[e.w] then list[#list + 1] = { t = e.t, on = e.on, net = nets[e.w] } end
    end
    if #list > 0 then p.tow = list end
end

--- The function that works out a step's targets as it starts. `here()` is where the one playing it is now.
--- Another resource's step (Whip.task): each field of it that names a placed thing, as that resource's code is
--- handed it on the game that plays it (client/director_tasks.lua): { thing = id, net = netId | nil, at = { x, y, z }
--- | nil }. `find(id)` answers { tNet, tAt } or nil, as thingNow does.
local function satThings(step, p, find)
    local d = DirectorTasks.get(step.t)
    if not (d and d.satellite) then return end
    for _, f in ipairs(d.fields) do
        local id = p[f.key]
        if f.kind == 'world' and type(id) == 'string' then
            local got = find(id)
            p[f.key] = { thing = id, net = got and got.tNet or nil, at = got and got.tAt or nil }
        end
    end
end

--- ONE WAY A STEP'S TARGETS ARE WORKED OUT, as the step starts: what it points at (the nearest player, the one who set
--- it off, a placed thing, a point), the NPC it fights, the players it fights, its emote's animation, another
--- resource's placed things. `src` says where they come from, a run's (resolverFor) or a standing NPC's (playStanding):
---   skip(step) -> why|nil            a step it cannot play at all (a standing NPC's standingSkip, its Wait for a card)
---   nearest() -> sid|nil, why        the player nearest it
---   trigger() -> sid|nil             the player who set it off, while they can be pointed at (nil: the nearest)
---   thing(id) -> { tNet, tAt }|nil, why   a placed thing as it is now
---   npc(id) -> netId|nil, why        an NPC it fights
---   players() -> { sid }|nil         whom Fight the Run's Players and Writhe look at
---   own(step, p) -> p|nil, why, doneWhen   the run's own steps last (Get In's car, a take, a Wait for a card)
local function stepResolver(src)
    return function(step)
        local skip = src.skip and src.skip(step)
        if skip then return nil, skip end
        local p = {}
        for k, v in pairs(step.p) do p[k] = v end
        local t = p.target
        local trigger = t == 'trigger' and src.trigger and src.trigger() or nil
        if t == 'trigger' and not trigger then t = 'nearest' end
        if t == 'nearest' then
            local s, why = src.nearest()
            if not s then return nil, why end
            p.tSid = s
        elseif t == 'trigger' then
            p.tSid = trigger
        elseif t == 'thing' then
            local got, why = src.thing(p.thing)
            if not got then return nil, why or 'its placed thing is not in the world' end
            p.tNet, p.tAt = got.tNet, got.tAt
        elseif t == 'point' then
            p.tAt = p.at
        end
        -- (What the step's catalogue says it is given as it starts: shared/director/steps.lua.)
        local d = DirectorSteps.get(step.t)
        if d and d.fights then
            local net, why = src.npc(p[d.fights])
            if not net then return nil, why end
            p.tNet = net
        end
        if d and d.seesPlayers then p.players = src.players and src.players() or nil end
        if d and d.emoteAnim then
            p.anim = emoteAnim(p[d.emoteAnim])
            if not p.anim then return nil, ('"%s" is not an emote with an animation'):format(tostring(p[d.emoteAnim])) end
        end
        satThings(step, p, src.thing)
        if src.own then return src.own(step, p) end
        return p
    end
end

--- A run's: its players, its placed things as the run made them, and its own steps. `car`: the car the list plays on
--- (its trailers' takes play beside it).
local function resolverFor(ctx, here, car)
    local run = ctx.run
    local trigger = Director.playerOf(ctx)
    local function thing(id) return thingNow(run, id) end
    return stepResolver({
        nearest = function()
            local at = here()
            local s = at and nearestPlayer(run, at)
            if not s then return nil, 'there is no player of the run to point at' end
            return s
        end,
        trigger = function() return trigger and run.players[trigger] and trigger or nil end,
        thing = thing,
        npc = function(id)
            local got = thingNow(run, id)
            if not got or not got.tNet then return nil, 'that NPC is not made yet' end
            return got.tNet
        end,
        players = function() return ctx:players() end,
        own = function(step, p)
            local d = DirectorSteps.get(step.t)
            if d and d.seatsIn then
                local got = thingNow(run, p[d.seatsIn])
                if not got or not got.tNet then return nil, 'its car is not made yet (Spawn Car)' end
                p.carNet = got.tNet
            elseif d and d.playsTake then
                -- (Read as the run started: DirectorTakes.preload.) Its moment, how long it may take, and its game.
                local take = DirectorTakes.get(p.take)
                if not take then return nil, ('driving event %s is not read yet (or is gone)'):format(tostring(p.take)) end
                p.startAt = GetGameTimer() + TAKE_LEAD_MS
                p.giveUpMs = take.lengthMs + TAKE_LEAD_MS + 15000
                p.pin = takePin(ctx, here())
                -- (Its trailers, each on its own recorded track from the same moment.)
                towTracks(ctx, p, car)
            elseif DirectorSteps.waitsOnCard(step.t, p) then
                -- A Wait for a card: done once the card gives one of the outcomes picked, counted from now (its game
                -- just waits: server/task_seq.lua asks this).
                local node = p.card
                if type(node) ~= 'string' or not run.graph.nodes[node] then return nil, 'its card is not in the scenario' end
                local pins = type(p.outs) == 'table' and p.outs or {}
                if #pins == 0 then return nil, 'no outcome of its card is picked' end
                local before = {}
                for i, pin in ipairs(pins) do before[i] = DirectorRuntime.firedCount(run, node, pin) end
                return p, nil, function()
                    for i, pin in ipairs(pins) do
                        if DirectorRuntime.firedCount(run, node, pin) > before[i] then return true end
                    end
                    return false
                end
            end
            return p
        end,
    })
end

-- WHAT A CAR'S OWN TASKS SET that its driving events set too (a step's leftByDrives: a recording's lights,
-- indicators, siren and engine): a drive on a car whose task list sets one leaves that one to the tasks (its step's
-- `leave`: client/actors.lua). A drive recorded with its lights off turned off, as it started, the lights a Lights
-- task had just put on.
local leftToTasks = DirectorSteps.leftByDrives

--- `resolve` with each driving event step told what to leave alone.
local function leaving(resolve, leave)
    if not leave then return resolve end
    return function(step)
        local p, why, doneWhen = resolve(step)
        if p and DirectorSteps.is(step.t, 'playsTake') then p.leave = leave end
        return p, why, doneWhen
    end
end

local function tasksOf(run)
    local t = run.tasks
    if not t then t = {}; run.tasks = t end
    return t
end

--- Start a placed thing's tasks on what the run made for it. Answers how many started and this start's own record
--- (DirectorTasks.over reads it), or 0 and why when none did.
---@param opts table|nil  { fromStopped = true: each from the step it was stopped at }
function DirectorTasks.start(ctx, worldId, opts)
    opts = opts or {}
    local run = ctx.run
    local w = ctx:place(worldId)
    if type(w) ~= 'table' then return 0, 'it is not placed' end
    local plan, problems = DirectorTasks.compile(w.kind, type(w.def) == 'table' and w.def.tasks or nil, run.graph.world, w)
    for _, pr in ipairs(problems) do ctx:log('%s, task %d (%s): %s', tostring(worldId), pr.i, pr.label, pr.why) end
    if not plan then return 0, 'it has no tasks to play' end
    local all = tasksOf(run)
    local old = all[worldId]
    local st = { live = 0, stoppedAt = {}, played = 0 }
    all[worldId] = st
    local function ended(why)
        st.live = math.max(0, st.live - 1)
        st.why = why
        -- (A list with no step it could play, or on a thing gone, never played: Start Tasks says Could not. One
        -- stopped, by Stop Tasks or by a list put in its place, did not finish: Stopped.)
        if why ~= 'nothing to do' and why ~= 'gone' then st.played = st.played + 1 end
        if why == 'stopped' then st.stopped = true end
    end
    local log = function(text) ctx:log('%s: %s', tostring(worldId), text) end
    local function from(key) return opts.fromStopped and old and old.stoppedAt[key] or 1 end
    -- (Counted before each starts: a list with no step it can play ends inside runTasks, `ended` already.)
    local started = 0

    if w.kind == 'npc' then
        for _, id in ipairs(DirectorNodes.npcIds(ctx:handle(worldId))) do
            local npc = id
            local here = function()
                local info = Npcs.get(npc)
                return info and info.coords or nil
            end
            st.live = st.live + 1
            local ok, why = Npcs.runTasks(CORE, npc, plan, { resolve = resolverFor(ctx, here), onEnd = ended, log = log,
                                                             from = from('npc:' .. npc) })
            if ok then
                started = started + 1
            else
                st.live = math.max(0, st.live - 1)
                ctx:log('NPC %s: %s', tostring(npc), tostring(why))
            end
        end
        if started == 0 then return 0, 'the run has not made that NPC yet (Spawn NPC)' end
    elseif w.kind == 'vehicle' then
        local h = ctx:handle(worldId)
        local ent = type(h) == 'table' and h.vehicleId and Vehicles.getEntity(h.vehicleId) or nil
        if not ent then return 0, 'the run has not made that car yet (Spawn Car)' end
        local here = function() return DoesEntityExist(ent) and GetEntityCoords(ent) or nil end
        st.live = 1
        local id, why = Actors.runTasks(CORE, ent, plan, { tag = ctx:tag(), resolve = leaving(resolverFor(ctx, here, ent), leftToTasks(plan.steps)),
                                                           onEnd = ended, log = log, from = from('car') })
        if not id then st.live = 0 return 0, why end
        st.actorId = id
        started = 1
    elseif w.kind == 'prop' then
        local setId, index = DirectorTasks.propSlot(run, worldId)
        if not setId then return 0, 'the run has not shown that prop (Show Prop)' end
        local steps = plan.steps
        local start = opts.fromStopped and old and old.stoppedAt.prop or 1
        if start > 1 then
            steps = {}
            for i = start, #plan.steps do steps[#steps + 1] = plan.steps[i] end
        end
        local motion = { steps = steps, startAt = GetGameTimer() + LEAD_MS, after = plan.after }
        run.propMotions = run.propMotions or {}
        run.propMotions[worldId] = motion
        local ok, why = PropSets.move(CORE, setId, index, motion)
        if not ok then return 0, why end
        st.prop, st.startAt, st.steps = true, motion.startAt, steps
        local len = DirectorTasks.length({ steps = steps })
        if plan.after ~= 'loop' and len then st.doneAt = motion.startAt + len end
        st.live, started = 1, 1
    else
        return 0, 'only an NPC, a car or a prop has tasks'
    end
    return started, st
end

--- Is anything of one start still playing?
local function stillPlaying(st)
    if st.prop then return not st.stopped and (not st.doneAt or GetGameTimer() < st.doneAt) end
    return st.live > 0
end

--- HOW ONE START WENT (DirectorTasks.start's record), once none of it plays: nil while some does; 'stopped' when one
--- was stopped or started again from another card (it did not finish); 'nothing' when not one list played a step
--- (each ended with none it could play, or on a thing gone: why, how the last ended); else 'done'. A prop's timeline
--- always plays.
---@return string|nil how
---@return string|nil why
function DirectorTasks.over(run, worldId, st)
    if stillPlaying(st) then return nil end
    if st.stopped or (run.tasks and run.tasks[worldId]) ~= st then return 'stopped' end
    if not st.prop and st.played == 0 then return 'nothing', st.why end
    return 'done'
end

--- Where a prop's timeline is: the step it is on (from the top), by the server's clock.
local function propStep(st, now)
    local t, at = now - st.startAt, 0
    for i, s in ipairs(st.steps) do
        at = at + (s.ms or 0)
        if t < at then return i end
    end
    return #st.steps
end

--- Stop a placed thing's tasks. `stay`: an NPC stays where it got to; otherwise it goes back to its idle.
function DirectorTasks.stop(ctx, worldId, stay)
    local run = ctx.run
    local st = tasksOf(run)[worldId]
    if not st then return 0 end
    local n = 0
    for _, id in ipairs(DirectorNodes.npcIds(ctx:handle(worldId))) do
        local at = Npcs.stopTasks(CORE, id, stay)
        if at then st.stoppedAt['npc:' .. id] = at; n = n + 1 end
    end
    if st.actorId then
        local at = Actors.stopTasks(CORE, st.actorId)
        if at then st.stoppedAt.car = at; n = n + 1 end
    end
    if st.prop then
        local now = GetGameTimer()
        local setId, index = DirectorTasks.propSlot(run, worldId)
        local m = run.propMotions and run.propMotions[worldId]
        if setId and m then
            m.stopAt = now
            PropSets.move(CORE, setId, index, m)
            st.stoppedAt.prop = propStep(st, now)
            n = n + 1
        end
        st.live, st.why, st.stopped = 0, 'stopped', true
    end
    return n
end

--- Is anything still playing a placed thing's tasks (whichever card started them)?
function DirectorTasks.playing(run, worldId)
    local st = run.tasks and run.tasks[worldId]
    return st ~= nil and stillPlaying(st)
end

--- Start its tasks, for a spawn card with "Start its tasks" on: said in the log when it cannot.
function DirectorTasks.startFor(ctx, worldId)
    local w = ctx.run.graph.world[worldId]
    if not DirectorTasks.has(w) then return end
    local n, why = DirectorTasks.start(ctx, worldId)
    if n == 0 then ctx:log('%s: its tasks did not start: %s', tostring(worldId), tostring(why)) end
end

-- ============================================
-- A standing NPC's tasks
-- ============================================
--
-- An NPC that is always there (the scenario's standing layer: server/director/main.lua) has no run to start its
-- list, so it plays it by itself whenever nothing else has it, as its idle (server/npcs.lua's IDLE TASKS): from the
-- top the first time, and from the Go To nearest it after a fight. Who a step points at: the nearest player in its
-- world (within STANDING_REACH), a standing thing, or a point. What needs a run is passed over (a step's standingSkip).

local STANDING_REACH = 150.0

--- The player nearest a point in this routing bucket, within STANDING_REACH, or nil.
local function nearestInWorld(at, bucket)
    local best, bestD = nil, STANDING_REACH * STANDING_REACH
    for _, s in ipairs(GetPlayers()) do
        local src = tonumber(s)
        if src and GetPlayerRoutingBucket(src) == bucket then
            local ped = GetPlayerPed(src)
            if ped and ped ~= 0 then
                local d = dist2(GetEntityCoords(ped), at)
                if d < bestD then best, bestD = src, d end
            end
        end
    end
    return best
end

--- A standing NPC's alive self, by its scenario's id: { netId }, or nil.
local function standingNpc(sc, wid)
    local h = sc.standing[wid]
    local info = type(h) == 'table' and h.npcId and Npcs.get(h.npcId) or nil
    return info and info.alive and info or nil
end

--- Give a standing NPC its list, played as its idle. `log(text)` says what is passed over and why.
function DirectorTasks.playStanding(sc, worldId, w, npcId, log)
    if not DirectorTasks.has(w) then return false end
    local plan, problems = DirectorTasks.compile('npc', w.def.tasks, sc.graph.world)
    for _, pr in ipairs(problems) do log(('%s, task %d (%s): %s'):format(tostring(worldId), pr.i, pr.label, pr.why)) end
    if not plan then return false end
    local bucket = sc.bucket or 0
    -- (Who points at: the player nearest it in its world; another standing NPC, else where a thing was placed.)
    local resolve = stepResolver({
        skip = function(step)
            local skip = DirectorTasks.standingSkip(step.t)
            if skip then return skip end
            if DirectorSteps.waitsOnCard(step.t, step.p) then return 'a standing NPC has no run to wait on' end
            return nil
        end,
        nearest = function()
            local me = Npcs.get(npcId)
            local s = me and me.coords and nearestInWorld(me.coords, bucket)
            if not s then return nil, 'there is no player near it' end
            return s
        end,
        thing = function(id)
            local other = standingNpc(sc, id)
            if other then return { tNet = other.netId } end
            local at = DirectorKit.place(type(sc.graph.world[id]) == 'table' and type(sc.graph.world[id].def) == 'table'
                and sc.graph.world[id].def.coords or nil)
            if not at then return nil, 'its placed thing is not in the world' end
            return { tAt = { x = at.x, y = at.y, z = at.z } }
        end,
        npc = function(id)
            local other = standingNpc(sc, id)
            if not other then return nil, 'that NPC is not a standing one' end
            return other.netId
        end,
    })
    local ok, why = Npcs.setIdleTasks(CORE, npcId, plan, { resolve = resolve, fromTop = true })
    if not ok then log(('%s: its tasks: %s'):format(tostring(worldId), tostring(why))) end
    return ok
end

-- ============================================
-- The cards
-- ============================================

local FROM = { 'the first task', 'where they stopped' }
local THEN = { 'goes back to its idle', 'stays where it is' }

local function worldOf(doc, id)
    for _, w in ipairs(type(doc) == 'table' and type(doc.world) == 'table' and doc.world or {}) do
        if type(w) == 'table' and w.id == id then return w end
    end
    return nil
end

--- Does a card of the scenario make this placed thing? Each card says what it makes (its definition's `makes`:
--- Spawn NPC, Spawn Car, Play Take with its riders, Show Prop with its group, another resource's own); and a car that
--- tows it (its Tows, or a take that hitched it) being made makes a trailer too.
local function madeByACard(doc, w, seen)
    local wid = w.id
    -- (A trailer: made with the car whose Tows names it, or by the take that hitched it.)
    if w.kind == 'vehicle' then
        seen = seen or { [wid] = true }
        for _, o in ipairs(type(doc.world) == 'table' and doc.world or {}) do
            local od = type(o) == 'table' and o.kind == 'vehicle' and type(o.def) == 'table' and o.def or nil
            if od and not seen[o.id] then
                local tows = od.tow == wid
                for _, tk in ipairs(not tows and type(od.takes) == 'table' and od.takes or {}) do
                    if type(tk) == 'table' and type(tk.tow) == 'table' and type(tk.tow.tracks) == 'table' and tk.tow.tracks[wid] then tows = true end
                end
                if tows then
                    seen[o.id] = true
                    if madeByACard(doc, o, seen) then return true end
                end
            end
        end
    end
    for _, n in ipairs(type(doc.nodes) == 'table' and doc.nodes or {}) do
        if DirectorNodes.makesOf(n, doc)[wid] then return true end
    end
    return false
end

local MAKER = { npc = 'Spawn NPC', vehicle = 'Spawn Car', prop = 'Show Prop' }

--- Check: the thing has tasks, and is one a run makes, and a card of the scenario makes it (with none, the card
--- could only ever go out Could not).
local function hasTasks(v, doc)
    local w = worldOf(doc, v)
    if not w then return nil end
    local name = tostring(w.label or w.id)
    if not DirectorThings.is(w.kind, 'tasks') then
        return ('"%s" is a %s: only an NPC, a car or a prop has tasks'):format(name, tostring(DirectorThings.is(w.kind, 'noun') or w.kind))
    end
    if w.layer == 'standing' and w.kind ~= 'vehicle' then
        return ('"%s" is standing: tasks play on what a run makes (Spawn NPC, Show Prop)'):format(name)
    end
    if not DirectorTasks.has(w) then
        return ('"%s" has no tasks yet (its page: Tasks)'):format(name)
    end
    if not madeByACard(doc, w) then
        return ('no card makes "%s", so its tasks have nothing to play on: add a %s card for it, wired before this one')
            :format(name, MAKER[w.kind])
    end
    return nil
end

--- Check, for a Start Tasks card's list: each of them as hasTasks.
local function eachHasTasks(list, doc)
    for _, v in ipairs(type(list) == 'table' and list or {}) do
        local why = hasTasks(v, doc)
        if why then return why end
    end
    return nil
end

--- Check for a list that takes groups too (Stop Tasks): each thing picked one by one has tasks; a group's members
--- without any are passed over.
local function pickedHaveTasks(v, doc)
    for _, x in ipairs(type(v) == 'table' and v or { v }) do
        if not DirectorNodes.groupName(x) then
            local why = hasTasks(x, doc)
            if why then return why end
        end
    end
    return nil
end

local MAX_STARTS = 24

--- The things a Start Tasks card starts (its list `things`), each once.
local function startList(props)
    local out, seen = {}, {}
    for _, v in ipairs(type(props.things) == 'table' and props.things or {}) do
        if type(v) == 'string' and v ~= '' and not seen[v] then seen[v] = true; out[#out + 1] = v end
    end
    return out
end

local MADE_WAIT_MS = 30000   -- Start Tasks waits this long for one it starts to be made (Spawn Car's own is 15 s and more)

--- Has the run made this placed thing (its NPC or group, its car, its prop shown)? Anything else has nothing to wait for.
local function madeNow(run, wid)
    local w = run.graph.world[wid]
    if not w then return true end
    local h = Director.handleOf(run, wid)
    if w.kind == 'npc' then
        return #DirectorNodes.npcIds(h) > 0
    elseif w.kind == 'vehicle' then
        return type(h) == 'table' and h.vehicleId ~= nil and Vehicles.getEntity(h.vehicleId) ~= nil
    elseif w.kind == 'prop' then
        return DirectorTasks.propSlot(run, wid) ~= nil
    end
    return true
end

--- Start Tasks' start: each one's tasks from one moment; Started now (ctx:emit), and once none of ITS lists plays any
--- more: Finished, Stopped (one was stopped, or started again by another card), or Could not.
local function startAll(ctx, list)
    local fromStopped = ctx:prop('from') == FROM[2]
    local started, mine = {}, {}
    for _, wid in ipairs(list) do
        local n, st = DirectorTasks.start(ctx, wid, { fromStopped = fromStopped })   -- (st: why not, when none started)
        if n == 0 then ctx:log('%s: %s', tostring(wid), tostring(st))
        else started[#started + 1] = wid; mine[wid] = st end
    end
    if #started == 0 then return 'failed' end
    -- Over already: not one step could play (each was passed over, the console and Check say why). Said once each.
    local said = {}
    -- Could not when not one of them played a step; Stopped when one was stopped; else Finished (a prop's timeline at
    -- its end).
    local function over()
        local hows = {}
        for i, wid in ipairs(started) do
            local how = DirectorTasks.over(ctx.run, wid, mine[wid])
            if not how then return nil end
            hows[i] = how
        end
        local none = true
        for i, wid in ipairs(started) do
            if hows[i] == 'stopped' then return 'stopped' end
            if hows[i] ~= 'nothing' then
                none = false
            elseif not said[wid] then
                said[wid] = true
                ctx:log('%s: none of its tasks could play (%s)', tostring(wid), tostring(mine[wid].why))
            end
        end
        return none and 'failed' or 'done'
    end
    if over() == 'failed' then return 'failed' end
    ctx:poll(500, over)
    ctx:emit('out')
    return nil
end

define({
    type = 'tasks.start', v = 1, category = 'world', title = 'Start Tasks',
    desc = 'Starts the tasks of NPCs, cars and props this scenario made, all at once. Finished: all done. Stopped: something else took them first.',
    outputs = { 'out', 'done', 'failed', 'stopped' },
    labels = { out = 'Started', done = 'Finished', failed = 'Could not', stopped = 'Stopped' },
    -- (Stopped is the card that stopped them's to follow on from: it need not be wired.)
    quietPins = { stopped = true },
    latent = true,
    -- (Started goes on at once, ctx:emit, while it still waits for Finished or Could not: graph.lua's dead ends.)
    goesOn = 'out',
    -- Whose tasks it starts (Check: one wired after a card that starts them itself: nodes.lua `startsTasksFor`).
    startsTasksFor = function(props) return startList(props) end,
    -- Finished never comes for tasks that start again when they end (its Tasks: When the last one ends, It starts again):
    -- Check says so, and a run whose only way to Succeed is through it can never succeed (graph.lua).
    neverPin = function(props, pin, world)
        if pin ~= 'done' then return nil end
        for _, wid in ipairs(startList(props)) do
            local w = world[wid]
            local t = w and type(w.def) == 'table' and type(w.def.tasks) == 'table' and w.def.tasks or nil
            if t and t.after == 'loop' then
                return ('"%s"\'s tasks start again each time they end (its Tasks: When the last one ends, It starts again), so they never finish')
                    :format(tostring(w.label or w.id))
            end
        end
        return nil
    end,
    props = {
        -- (`withTasks`: its list offers only the things whose tasks it can start: panels.js worldsField.)
        { key = 'things', kind = 'worlds', label = 'Whose tasks', max = MAX_STARTS, withTasks = true, check = eachHasTasks },
        { key = 'from', kind = 'select', label = 'From', options = FROM, default = FROM[1] },
    },
    check = function(props)
        local n = #startList(props)
        if n == 0 then return 'Pick whose tasks it starts' end
        if n > MAX_STARTS then return ('%d at most on one card'):format(MAX_STARTS) end
        return nil
    end,
    run = function(ctx)
        local list = startList(ctx.node.props)
        -- One the run has not made yet (its Spawn card, wired in beside this one, still at work): waited for (MADE_WAIT_MS
        -- at most), so they all start together from one moment. Meanwhile the card is busy: the other Spawn card's pulse
        -- when it finishes joins this start instead of starting them all again from the top.
        local function unmade()
            local out = {}
            for _, wid in ipairs(list) do if not madeNow(ctx.run, wid) then out[#out + 1] = wid end end
            return out
        end
        if #unmade() == 0 then return startAll(ctx, list) end
        ctx:call(function()
            local untilAt = GetGameTimer() + MADE_WAIT_MS
            -- (Its own card still at work, not only the run: an After chain or a test's Rewind ends the card, and the
            -- list it was waiting to start must not start then.)
            while #unmade() > 0 and GetGameTimer() < untilAt do
                Wait(100)
                if not ctx:alive() then return 'failed' end
            end
            if not ctx:alive() then return 'failed' end
            local late = unmade()
            if #late > 0 then ctx:log('not made after %d s, started without: %s', MADE_WAIT_MS // 1000, table.concat(late, ', ')) end
            return startAll(ctx, list)
        end)
        return nil
    end,
})

define({
    type = 'tasks.stop', v = 2, category = 'world', title = 'Stop Tasks',
    desc = 'Stops the tasks of the things (or groups) picked. An NPC goes back to its idle where it was, or stays where it got to. Start Tasks can pick them up from there.',
    outputs = { 'out' },
    upgrade = function(props) return DirectorNodes.toList(props, 'what') end,
    props = {
        DirectorNodes.thingsField('what', nil, 'Whose tasks (things or groups)', { check = pickedHaveTasks, max = MAX_STARTS }),
        { key = 'then', kind = 'select', label = 'Then it', options = THEN, default = THEN[1] },
    },
    run = function(ctx)
        for _, wid in ipairs(DirectorNodes.things(ctx, 'what')) do
            DirectorTasks.stop(ctx, wid, ctx:prop('then') == THEN[2])
        end
        return 'out'
    end,
})

-- ============================================
-- Play Take: a car's recorded drive, with whoever rides in it
-- ============================================
--
-- The run's car (made where the take starts, if the run has not made it: Spawn Car's way), its RIDERS (the NPCs
-- its page seats in it: made there too, and kept in their seats by their brains: server/npcs.lua's ride), and
-- the take played on one game (server/actors.lua's pin). When it ends: the car brakes, everyone gets out, their
-- tasks start (the riders' own lists, a rider with none just gets out, and the car's), or the driver drives on.
--
-- RIDE ALONG (the card's switch): a player at the wheel instead of its driver, the take played on their game. Their game
-- seats them (client/director_takes.lua) and says so, and only then does the take start. They count as a rider with no
-- tasks when it ends. A car the card makes for the ride has its key in the ignition, so they can drive on; one the run
-- made already keeps its own Key settings.

local ENDINGS = { 'it stops, the driver brakes', 'everyone gets out', 'their tasks start', 'it drives on' }
local TAKE_LIMIT_MS = 5 * 60 * 1000
local DRIVE_ON_MS = 60 * 60 * 1000
local RIDE_SEAT_MS = 10000    -- how long their game has to seat them (its own limits add up to less: client/director_takes.lua)
local RIDE_LATE_MS = 30000    -- past the take's length: their game lets go by itself, if nothing has told it to

--- The run's car for a placed one (its entity), or nil.
local function runCarEntity(ctx, wid) return (DirectorNodes.runCar(ctx, wid)) end

--- The run's car, made where a take starts, as Spawn Car makes one (its key nobody's, or `keyIn`: in the ignition).
--- Waits: a thread.
local function makeCarAt(ctx, wid, at, keyIn)
    local w = ctx:place(wid)
    local def = type(w) == 'table' and type(w.def) == 'table' and w.def or {}
    local model = DirectorGraph.carModel(def)   -- (a random vehicle's: one of its models)
    if type(model) ~= 'string' or model == '' then return nil, 'it has no model' end
    local id, err = Vehicles.spawnTempFor(model, vector4(at.x, at.y, at.z, at.heading or 0.0), {
        plate = type(def.plate) == 'string' and def.plate ~= '' and def.plate or nil,
        locked = def.locked ~= false, secure = def.secure == true, keyInIgnition = keyIn or nil,
        idleDespawn = false, tag = ctx:tag(), bucket = ctx.run.bucket,
    }, CORE)
    if not id then return nil, err end
    local ent = Vehicles.getEntity(id)
    ctx:remember(wid, { vehicleId = id, netId = ent and NetworkGetNetworkIdFromEntity(ent) or nil })
    return ent
end

--- A car's riders as its page lists them: { { npc = worldId, seat = the game's seat number } }. `noDriver`: all but the
--- one at the wheel (a player rides there).
local function ridersOf(run, carW, noDriver)
    local out = {}
    local w = run.graph.world[carW]
    local list = w and type(w.def) == 'table' and w.def.riders or nil
    for _, r in ipairs(type(list) == 'table' and list or {}) do
        local n = type(r) == 'table' and r.npc and run.graph.world[r.npc]
        local seat = type(r) == 'table' and DirectorSteps.SEAT_N[r.seat] or -1
        if n and n.kind == 'npc' and not (noDriver and seat == -1) then out[#out + 1] = { npc = r.npc, seat = seat } end
    end
    return out
end

--- Each rider in its seat: the run's NPC for it, made beside the car when the run has none (as Spawn NPC
--- makes one). Answers { { npc = worldId, id = npcId, seat } }.
local function seatRiders(ctx, carW, ent, at, noDriver)
    local seated = {}
    local carNet = NetworkGetNetworkIdFromEntity(ent)
    for _, r in ipairs(ridersOf(ctx.run, carW, noDriver)) do
        local id = DirectorNodes.npcIds(ctx:handle(r.npc))[1]
        if not id then
            local w = ctx:place(r.npc)
            local d = DirectorRoutes.npcDef(type(w) == 'table' and w.def or nil)   -- (a copy)
            d.coords = { x = at.x, y = at.y, z = at.z + 1.0, heading = at.heading or 0.0 }
            d.interior = nil
            local npcId, netId = Npcs.spawn(CORE, d, { tag = ctx:tag(), corpseMs = not ctx.run.always and 0 or nil,
                                                       bucket = ctx.run.bucket })
            if npcId then
                id = npcId
                local h = { npcId = npcId, netId = netId, group = { npcId } }
                ctx:remember(r.npc, h)
                -- RedM (spur_core, 23 Nov 2026): a ped still being made (server/npcs.lua) gets its netId when it comes.
                if not netId then Npcs.whenMade(npcId, function(net) if net then h.netId = net end end) end
            else
                ctx:log('%s: its rider %s could not be made: %s', carW, r.npc, tostring(netId))
            end
        end
        if id then
            local ok, why = Npcs.setState(CORE, id, { ride = { net = carNet, seat = r.seat } }, ctx.node.def.title)
            if ok then seated[#seated + 1] = { npc = r.npc, id = id, seat = r.seat }
            else ctx:log('%s: rider %s: %s', carW, r.npc, tostring(why)) end
        end
    end
    return seated
end

local function oneStep(step) return { steps = { step }, after = 'stop', fight = true } end
local same = function(s) return s.p end

--- What the riders and the car do once the take is over (ENDINGS).
local function afterTake(ctx, carW, riders, ending)
    if ending == ENDINGS[1] then return end   -- they stay sat; the car braked (the take's own last step)
    if ending == ENDINGS[4] then
        -- The driver drives on, the rest stay sat.
        for _, r in ipairs(riders) do
            if r.seat == -1 then
                Npcs.runTasks(CORE, r.id, oneStep({ k = 'on', t = 'cruise', timing = 'timed', ms = DRIVE_ON_MS, lasting = true,
                                                     p = { mps = 50 / 3.6, styleN = DirectorSteps.STYLE_N.normal } }), { resolve = same })
            end
        end
        return
    end
    local started = {}
    for _, r in ipairs(riders) do
        Npcs.setState(CORE, r.id, { ride = false })
        local own = ending == ENDINGS[3] and DirectorTasks.has(ctx.run.graph.world[r.npc])
        if own and not started[r.npc] then
            started[r.npc] = true
            DirectorTasks.startFor(ctx, r.npc)
        elseif not own then
            Npcs.runTasks(CORE, r.id, oneStep({ k = 'out', t = 'getOut', timing = 'until', giveUpMs = 10000, p = {} }), { resolve = same })
        end
    end
    if ending == ENDINGS[3] then DirectorTasks.startFor(ctx, carW) end
end

local rides, lastRide = {}, 0   -- [token] = { src, answer } while a player's game seats them

SecureEvent('spur_core:server:takeRideSeated', {
    whileDead = true, rateLimit = 200, burst = 4,
    params = { { 'token', 'id' }, { 'ok', 'bool' } },
}, function(source, _, token, ok)
    local r = rides[token]
    if r and r.src == source and r.p.state == 0 then r.p:resolve(ok == true) end
end)

--- A player at the wheel of the car: the one the card is about, else the run player nearest it. Answers { src, token }
--- once they are seated, the run's takes playing on their game from here (takePin), or nil and why the take goes on
--- without them. Waits: a thread.
local function rideBegin(ctx, ent, take)
    local at = GetEntityCoords(ent)
    local src = Director.playerOf(ctx) or nearestPlayer(ctx.run, at)
    if not src then return nil, 'no player to ride along' end
    lastRide = lastRide + 1
    local token = lastRide
    -- Woken by their game's answer (takeRideSeated), the card ending, or RIDE_SEAT_MS going by: never looked at again
    -- and again.
    local r = { src = src, p = promise.new() }
    rides[token] = r
    local function noAnswer() if r.p.state == 0 then r.p:resolve(nil) end end
    SetTimeout(RIDE_SEAT_MS, noAnswer)
    ctx:onEnd(noAnswer)
    TriggerClientEvent('spur_core:client:takeRide', src, token, NetworkGetNetworkIdFromEntity(ent),
        { x = at.x, y = at.y, z = at.z }, take.lengthMs + TAKE_LEAD_MS + RIDE_LATE_MS)
    local answer = Citizen.Await(r.p)
    rides[token] = nil
    if answer ~= true or not GetPlayerName(src) then
        TriggerClientEvent('spur_core:client:takeRideOver', src, token, false)
        return nil, ('player %s could not be put at the wheel'):format(tostring(src))
    end
    ctx.run.takePin = src
    return { src = src, token = token }
end

--- The ride over: their controls back, and out of the car if `getOut`.
local function rideEnd(ride, getOut)
    if ride then TriggerClientEvent('spur_core:client:takeRideOver', ride.src, ride.token, getOut == true) end
end

define({
    type = 'vehicle.playTake', v = 1, category = 'world', title = 'Play Scripted Driving Event',
    desc = 'Drives the car exactly as one of its recorded Scripted Driving Events, with whoever rides in it. Ride along puts the player at the wheel.',
    outputs = { 'done', 'failed', 'timeout' },
    labels = { done = 'Finished', failed = 'Could not' },
    latent = true, yields = true, heavy = true,
    -- What it makes (Check, Start Tasks: nodes.lua `makes`): its car, and with Its riders too the NPCs its page seats (all
    -- but the one at the wheel, with Ride along).
    makes = function(props, doc)
        local out = DirectorKit.idSet({ props.car })
        if props.riders == false then return out end
        local car = worldOf(doc, props.car)
        for _, r in ipairs(car and type(car.def) == 'table' and type(car.def.riders) == 'table' and car.def.riders or {}) do
            if type(r) == 'table' and type(r.npc) == 'string'
                and not (props.ride == true and (DirectorSteps.SEAT_N[r.seat] or -1) == -1) then
                out[r.npc] = true
            end
        end
        return out
    end,
    props = {
        { key = 'car', kind = 'world', worldKind = 'vehicle', label = 'Car', required = true },
        { key = 'take', kind = 'take', of = 'car', label = 'Driving event', required = true },
        { key = 'riders', kind = 'bool', label = 'Its riders too', default = true, hint = 'The NPCs its page seats in it, made in their seats' },
        { key = 'ride', kind = 'bool', label = 'Ride along', default = false, hint = 'The player is put at the wheel in place of any NPC driver, with only the camera, chat and pause working until it ends. A car this card makes has its key in the ignition' },
        { key = 'ending', kind = 'select', label = 'When it ends', options = ENDINGS, default = ENDINGS[1] },
    },
    run = function(ctx)
        local carW = ctx.node.props.car
        local takeId = ctx:prop('take')
        local ending = ctx:prop('ending') or ENDINGS[1]
        local withRiders = ctx:prop('riders') ~= false
        local wantsRide = ctx:prop('ride') == true
        ctx:call(function()
            -- (One the car no longer has, removed from its page, is never played: its row is kept for older revisions.)
            if not DirectorTakes.onCar(ctx:place(carW), takeId) then
                ctx:log('%s: driving event %s was removed from the car: pick another on the card', tostring(carW), tostring(takeId))
                return 'failed'
            end
            local take, why = DirectorTakes.load(takeId)
            if not take then ctx:log('%s: %s', tostring(carW), tostring(why)) return 'failed' end
            local ent = runCarEntity(ctx, carW)
            if not ent then ent, why = makeCarAt(ctx, carW, take.start, wantsRide) end
            if not ent then ctx:log('%s: the car could not be made: %s', tostring(carW), tostring(why)) return 'failed' end
            -- Its trailers (the take's tow), each made where its own track starts if the run has not made it, as the car is:
            -- the take hitches them when it did. A trailer its page's Tows keeps on is the take's to hitch from now.
            local tow = DirectorTakes.towOf(ctx.run.graph, take.id)
            if tow then
                local wids = {}
                for wid in pairs(tow.tracks) do wids[#wids + 1] = wid end
                table.sort(wids)
                for _, wid in ipairs(wids) do
                    if not runCarEntity(ctx, wid) then
                        local track, twhy = DirectorTakes.load(tow.tracks[wid])
                        local made = track and makeCarAt(ctx, wid, track.start)
                        if not made then ctx:log('%s: its trailer %s could not be made: %s', tostring(carW), wid, tostring(twhy or 'it would not spawn')) end
                    end
                end
                Actors.setTow(CORE, ent, nil)
            end
            local riders = withRiders and seatRiders(ctx, carW, ent, take.start, wantsRide) or {}
            local ride, rideWhy = nil, nil
            if wantsRide then
                ride, rideWhy = rideBegin(ctx, ent, take)
                if rideWhy then ctx:log('%s: %s: it plays without them', tostring(carW), rideWhy) end
                if not ctx:alive() then rideEnd(ride) return 'failed' end
            end
            local steps = { { k = 'take', t = 'take', timing = 'until', giveUpMs = take.lengthMs + 20000, p = { take = take.id } } }
            if ending == ENDINGS[1] then steps[2] = { k = 'brake', t = 'brake', timing = 'timed', ms = 3000, p = {} } end
            local over = promise.new()   -- how the take ended (Actors' onEnd), or false: its card ended first
            local here = function() return DoesEntityExist(ent) and GetEntityCoords(ent) or nil end
            -- (The car's own tasks, once this run started them: what they set, the drive leaves to them.)
            local carPlace = ctx:place(carW)
            local leave = ctx.run.tasks and ctx.run.tasks[carW] and type(carPlace) == 'table' and type(carPlace.def) == 'table'
                and type(carPlace.def.tasks) == 'table' and leftToTasks(carPlace.def.tasks.list) or nil
            local id, aerr = Actors.runTasks(CORE, ent, { steps = steps, after = 'stop', fight = false }, {
                tag = ctx:tag(), resolve = leaving(resolverFor(ctx, here, ent), leave),
                onEnd = function(w) if over.state == 0 then over:resolve(w) end end,
                log = function(t) ctx:log('%s: %s', tostring(carW), t) end,
            })
            if not id then
                rideEnd(ride)
                ctx:log('%s: %s', tostring(carW), tostring(aerr))
                return 'failed'
            end
            -- (A thread of its own: woken when the take is over, or by its card ending (an After chain, a Rewind), then
            -- it says how it went.)
            ctx:onEnd(function() if over.state == 0 then over:resolve(false) end end)
            local how = Citizen.Await(over)
            if not ctx:alive() then
                rideEnd(ride)
                return 'failed'
            end
            rideEnd(ride, how == 'done' and (ending == ENDINGS[2] or ending == ENDINGS[3]))
            if how ~= 'done' then ctx:log('%s: the driving event did not finish (%s)', tostring(carW), tostring(how)) return 'failed' end
            if not ctx:alive() then return 'failed' end
            afterTake(ctx, carW, riders, ending)
            return 'done'
        end)
        ctx:after(TAKE_LIMIT_MS, 'timeout')
        return nil
    end,
})
