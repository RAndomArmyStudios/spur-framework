-- ============================================
-- TASK SEQ — playing a task list on an entity whose owner's game runs it
-- ============================================
--
-- The one set of rules for a list of steps (server/director/tasks.lua compiles them) that a networked
-- entity plays: an NPC (server/npcs.lua) and a car (server/actors.lua) both use it. The entity's record
-- holds the list; the game that owns the entity runs each step and says so; this file decides what the
-- next step is and when it starts. The record keeps, besides its own fields:
--   rec.seq   the list as it plays: { steps, i, last, after, fight, keepPost, idle, resolve, onEnd, log, jobId,
--             started, reported, keep, frozen, selfDeath, laps, ver, sentAt, warned }
--   rec.job   what the owner is sent now: { id, list, keep, fight, frozen }
--   rec.ver, rec.acked, rec.netOwner   the record's own push version, the version its owner applied,
--             and its owner (the host keeps these up to date)
--
-- A JOB is the instant steps in a row from where the list is and the step after them that takes time,
-- sent together. Its owner applies it (the host's ack of the version that carried it): an instant step
-- is then done, a timed one starts its clock there (a slow game loses none of it), and one that waits
-- for something is done when the owner says so (TaskSeq.report) or gives up. Steps that cannot play (a
-- dead NPC's walk, a target that is gone) are passed over; a list with nothing to play ends.
--
-- WALKING ON: a step that flows (a Go To: DirectorSteps) with another straight after it, the first one of a list going
-- round included, carries that one's params as `ahead`. Its game sets off for there by itself as it reaches this one,
-- so the NPC walks on through the point while the next job is on its way, instead of standing there for it.
--
-- The host hands in its hooks: { bump(rec, why) -> pushes the record's new version to its owner (and
-- bumps rec.ver); alive(rec) -> bool; started(rec, list) -> the owner has applied this job (an NPC's
-- Revive); ended(rec, why, seq) -> the list is over, before whoever started it hears; name(rec) -> how
-- the console names it }.
--
-- FROZEN, ONE RULE ON BOTH HOSTS: a list that ends 'done' (and does not go round) frozen by its Freeze leaves the
-- entity frozen (the host's rec.frozen), and the next list goes on so till a Freeze of its own says. A list put in
-- place of one still playing (`rec.replacing`, set by the host round TaskSeq.start) does not carry the old one's
-- Freeze: the new list starts unfrozen, on an NPC and on a car alike.

TaskSeq = {}

local WARN_MS   = 5000   -- a job its owner has not applied in this long is said in the console
local MAX_BATCH = 12     -- instant steps sent together in one job, at most
-- A list that starts again goes round at most once in this long: a round that is over at once (one Go To it is
-- already at, a teleport and back) would otherwise be sent to its game again on every answer.
local MIN_LAP_MS = 1000

local nextJob = 0

--- The list is over: the job goes, the host and whoever started it hear why ('done', 'stopped',
--- 'fought', 'died', 'gone', 'nothing to do'). Never waits.
function TaskSeq.finish(rec, why, hooks, extra)
    local seq = rec.seq
    if not seq then return end
    rec.seq, rec.job = nil, nil
    if hooks.ended then
        local ok, err = pcall(hooks.ended, rec, why, seq, extra)
        if not ok then print(('[spur_core:tasks] %s: ending its tasks failed: %s'):format(hooks.name(rec), tostring(err))) end
    end
    if seq.onEnd then
        local ok, err = pcall(seq.onEnd, why)
        if not ok then print(('[spur_core:tasks] %s: its tasks\' end hook failed: %s'):format(hooks.name(rec), tostring(err))) end
    end
end

local nextOf   -- (below: the two call each other)

--- Step j flows into the one after it (WALKING ON, above): that one's params, else nil.
local function aheadOf(seq, j)
    local s = seq.steps[j]
    if not s or s.timing ~= 'until' or not DirectorSteps.is(s.t, 'flows') then return nil end
    local nj = j + 1
    if nj > #seq.steps then
        if seq.after ~= 'loop' then return nil end
        nj = 1
    end
    local nxt = seq.steps[nj]
    if not nxt or nxt.timing ~= 'until' or not DirectorSteps.is(nxt.t, 'flows') then return nil end
    local ok, p = pcall(seq.resolve, nxt)
    return ok and type(p) == 'table' and p or nil
end

--- The next job, sent at once.
local function startJob(rec, now, hooks)
    local seq = rec.seq
    local n = #seq.steps
    local alive = not hooks.alive or hooks.alive(rec)
    local list, j = {}, seq.i
    seq.doneWhen = nil
    while j <= n and #list < MAX_BATCH do
        local s = seq.steps[j]
        local took = false
        if alive or DirectorSteps.is(s.t, 'whenDead') then   -- (what a dead NPC's list still does)
            -- (`doneWhen`: a step the server itself sees through, a Wait for a card, says here how it knows.)
            local p, why, doneWhen = seq.resolve(s)
            if p then
                seq.doneWhen = doneWhen
                -- (A step whose time is known only as it starts, a take's, says so in its params.)
                list[#list + 1] = { t = s.t, p = p, timing = s.timing, ms = s.ms, giveUpMs = p.giveUpMs or s.giveUpMs,
                                    once = s.once, lasting = s.lasting, ahead = aheadOf(seq, j) }
                took = true
            elseif seq.log then
                seq.log(('step %d (%s) passed over: %s'):format(j, s.t, tostring(why)))
            end
        end
        if took and s.timing ~= 'instant' then break end
        j = j + 1
    end
    seq.last = math.min(j, n)
    if #list == 0 then
        -- Nothing from here to the end can be played: on to the end (or round). From the top with nothing
        -- either, there is nothing to do at all.
        if seq.i == 1 then TaskSeq.finish(rec, 'nothing to do', hooks) return end
        seq.last = n
        nextOf(rec, now, hooks)
        return
    end
    -- A death from here on is the list's own Die (marked before the ack: the death can be read first).
    for _, s in ipairs(list) do if s.t == 'die' then seq.selfDeath = true end end
    -- Frozen as its own Freeze steps leave it (they are instant: they play first, with the step after them), sent
    -- with it. Worked out at the ack instead, the owner would hold each job by the last one's Freeze.
    local frozen = seq.frozen
    for _, s in ipairs(list) do
        if s.t == 'freeze' then frozen = (type(s.p) == 'table' and s.p.on == true) or nil end
    end
    seq.frozen = frozen
    nextJob = nextJob + 1
    rec.job = { id = nextJob, list = list, keep = seq.keep, fight = seq.fight, frozen = frozen }
    seq.jobId, seq.started, seq.reported, seq.warned, seq.sentAt = nextJob, nil, nil, false, now
    hooks.bump(rec, 'task')
    seq.ver = rec.ver
end

--- The job's steps are done: what lasts goes on under the next (a wander under a Wait), and the list
--- moves on, round again or to its end.
function nextOf(rec, now, hooks)
    local seq = rec.seq
    for _, s in ipairs(rec.job and rec.job.list or {}) do
        if s.lasting then seq.keep = s elseif s.t ~= 'wait' then seq.keep = nil end
    end
    seq.i = seq.last + 1
    if seq.i > #seq.steps then
        if seq.after ~= 'loop' then TaskSeq.finish(rec, 'done', hooks) return end
        seq.i = 1
        seq.laps = (seq.laps or 0) + 1
        -- (Round again no sooner than MIN_LAP_MS after the last round started: TaskSeq.tick starts it then.)
        if now - (seq.lapAt or 0) < MIN_LAP_MS then
            seq.holdUntil = (seq.lapAt or now) + MIN_LAP_MS
            return
        end
        seq.lapAt = now
    end
    startJob(rec, now, hooks)
end

--- Where a list stopped now would pick up again (Start Tasks: from where they were stopped): the step that takes time
--- once its game has applied the job (the instant steps sent with it have happened: a teleport again would put it
--- back), else the job's first step. nil with no list.
---@return integer|nil step
function TaskSeq.resumeAt(rec)
    local seq = rec.seq
    if not seq then return nil end
    return (seq.started and seq.last) or seq.i
end

--- Start a list on a record, in place of any it was playing (that one ends 'stopped').
---@param plan table  { steps, after = 'stop' | 'loop', fight = bool, keepPost = true (an NPC goes back where it was after,
---                    a look round: server/npcs.lua) }
---@param opts table  { resolve = fn(step) -> params | nil, why (and, for a step the server sees through itself, a
---                    third: fn() -> true once it is done); onEnd = fn(why); log = fn(text); from = step number;
---                    idle = true (what an NPC does when nothing else has it, its patrol: server/npcs.lua) }
function TaskSeq.start(rec, plan, opts, hooks)
    if rec.seq then TaskSeq.finish(rec, 'stopped', hooks) end
    local from = math.tointeger(tonumber(opts.from) or 1) or 1
    -- Left frozen by the last list (the host's rec.frozen): the new one goes on so, till a Freeze of its own says
    local wasFrozen = rec.frozen == true or nil
    rec.frozen = nil
    rec.seq = {
        steps = plan.steps, i = math.max(1, math.min(#plan.steps, from)), after = plan.after, fight = plan.fight ~= false,
        keepPost = plan.keepPost == true, idle = opts.idle == true, frozen = wasFrozen,
        resolve = opts.resolve, onEnd = opts.onEnd, log = opts.log, lapAt = GetGameTimer(),
    }
    startJob(rec, GetGameTimer(), hooks)
end

--- One look, from the host's tick (its owner and its acked version read just before).
function TaskSeq.tick(rec, now, hooks)
    local seq = rec.seq
    if not seq then return end
    -- A round over too soon waits for its time (nextOf), the last job still in place meanwhile.
    if seq.holdUntil then
        if now < seq.holdUntil then return end
        seq.lapAt, seq.holdUntil = seq.holdUntil, nil
        startJob(rec, now, hooks)
        return
    end
    if not seq.jobId then startJob(rec, now, hooks) return end
    if not seq.started then
        -- Its owner's game has the job once it has applied a version that carries it (a later one does too).
        if rec.netOwner and rec.acked >= seq.ver then
            seq.started = now   -- (its frozen went out with it: startJob)
            if hooks.started then hooks.started(rec, rec.job.list) end
        elseif not seq.warned and now - seq.sentAt >= WARN_MS then
            seq.warned = true
            local last = rec.job.list[#rec.job.list]
            print(('^3[spur_core:tasks] %s: its game has not applied task step %d (%s) in %d s (owner %s)^7')
                :format(hooks.name(rec), seq.i, tostring(last and last.t), WARN_MS // 1000,
                    rec.netOwner and tostring(rec.netOwner) or 'none: nobody near it'))
        end
        return
    end
    local s = rec.job.list[#rec.job.list]
    local done
    if not s or s.timing == 'instant' then
        done = true
    elseif s.timing == 'timed' then
        done = now - seq.started >= (s.ms or 0)
    else
        if not seq.reported and seq.doneWhen then
            local ok, yes = pcall(seq.doneWhen)
            if ok and yes then seq.reported = 'done' end
        end
        done = seq.reported ~= nil or now - seq.started >= (s.giveUpMs or 30000)
        if done and not seq.reported and seq.log then
            seq.log(('step %d (%s) gave up: not done in %d s'):format(seq.last, s.t, (s.giveUpMs or 30000) // 1000))
        end
    end
    if done then nextOf(rec, now, hooks) end
end

--- The owner says the step it was waiting on is done: only for the job it is on.
function TaskSeq.report(rec, jobId, how)
    local seq = rec.seq
    if not seq or not rec.job or rec.job.id ~= jobId then return end
    if seq.started and not seq.reported then seq.reported = how end
end

--- The job as its owner is sent it, with how long its step has run (another game started it).
function TaskSeq.wire(rec, now)
    local job = rec.job
    if not job then return nil end
    return { id = job.id, list = job.list, keep = job.keep, fight = job.fight, frozen = job.frozen,
             since = (rec.seq and rec.seq.started) and (now - rec.seq.started) or 0 }
end

--- What a debug overlay shows: the step, whether its game has it, how long it has run.
function TaskSeq.view(rec, now)
    local seq, job = rec.seq, rec.job
    if not seq or not job then return nil end
    local last = job.list[#job.list]
    return { i = seq.i, last = seq.last, n = #seq.steps, t = last and last.t or '-', id = job.id,
             applied = seq.started ~= nil, ms = seq.started and (now - seq.started) or 0, reported = seq.reported,
             idle = seq.idle or nil }
end

--- Where a list stands: { i, n, laps, applied }, or nil. An NPC's patrol (its idle) is not a list a card started.
function TaskSeq.state(rec)
    local seq = rec.seq
    if not seq or seq.idle then return nil end
    return { i = seq.i, n = #seq.steps, laps = seq.laps or 0, applied = seq.started ~= nil }
end
