-- ============================================
-- JOBS — Client Module
-- Tracks employment + clock state for local player
-- ============================================

local PlayerJobs   = {}   -- { [jobId] = { jobId, name, icon, roleId, roleName, roleLevel, clockedOn } }
local ClockedOnJobs = {}  -- { [jobId] = order } — a higher order clocked on more recently

--- The order the next clock-on gets: above everything already on duty.
local function nextDutyOrder()
    local top = 0
    for _, order in pairs(ClockedOnJobs) do
        if order > top then top = order end
    end
    return top + 1
end

-- ============================================
-- Events
-- ============================================

--- Receive full job data on character load (or after hire/fire/role change)
RegisterNetEvent('spur_core:client:jobsSync', function(jobs)
    PlayerJobs = jobs or {}
    -- Rebuild ClockedOnJobs from synced data, keeping the server's order (dutyOrder).
    ClockedOnJobs = {}
    for jobId, data in pairs(PlayerJobs) do
        if data.clockedOn then
            ClockedOnJobs[jobId] = tonumber(data.dutyOrder) or 1
        end
    end

    -- A local event for this client's resources: hired, fired, promoted, a job renamed — the list
    -- changed. { jobs } is the same map GetPlayerJobs answers.
    WhipEmit('spur_core:job:listChanged', { jobs = PlayerJobs })
end)

--- Clock state update from server
RegisterNetEvent('spur_core:client:jobClockState', function(jobId, state)
    if state then
        -- The newest clock-on is the current job, as it is on the server.
        ClockedOnJobs[jobId] = nextDutyOrder()
    else
        ClockedOnJobs[jobId] = nil
    end
    if PlayerJobs[jobId] then
        PlayerJobs[jobId].clockedOn = state or false
        PlayerJobs[jobId].dutyOrder = ClockedOnJobs[jobId]
    end

    -- Local events, the client's half of the server's spur_core:job:clockedOn / clockedOff: a
    -- uniform, a radio channel, a HUD badge can follow duty without polling IsPlayerClockedOn.
    local key = PlayerJobs[jobId] and PlayerJobs[jobId].key or nil
    WhipEmit(state and 'spur_core:job:clockedOn' or 'spur_core:job:clockedOff', { jobId = jobId, key = key })
end)

--- Clear state on logout (the local event; spur_core:client:playerLogout is the internal net one)
AddEventHandler('spur_core:player:logout', function()
    PlayerJobs = {}
    ClockedOnJobs = {}
end)

-- ============================================
-- Client Exports
-- ============================================

--- A job the player has, named either way — its jobId or its key, as on the server — as its jobId.
---@param ref number|string
---@return number|nil jobId
local function jobIdOf(ref)
    if type(ref) == 'number' then return PlayerJobs[ref] and ref or nil end
    if type(ref) == 'string' then
        for jobId, job in pairs(PlayerJobs) do
            if job.key == ref then return jobId end
        end
    end
    return nil
end

--- Get all jobs player is employed at. Global: client/zones.lua's job rules read it without the
--- export.
function GetPlayerJobs()
    return PlayerJobs
end
exports('GetPlayerJobs', GetPlayerJobs)

--- May the player do this at this job? What the server's job list said (`permissions` on each job):
--- a hint for what to OFFER, never the decision — the server checks again. Global, so spur_core's
--- own client files ask it without an export crossing.
---@param job number|string  jobId or key
---@param permission string
---@return boolean
function JobHasPermission(job, permission)
    local entry = PlayerJobs[jobIdOf(job) or false]
    return entry ~= nil and type(entry.permissions) == 'table' and entry.permissions[permission] == true
end

exports('HasJobPermission', JobHasPermission)

--- Does ANY of the player's jobs grant this permission — and, with `onDuty`, are they on duty there?
--- What `require = { jobPermission = 'x' }` with no job named asks (client/actions.lua).
---@param permission string
---@param onDuty boolean|nil
---@return boolean
function PlayerHasJobPermission(permission, onDuty)
    for jobId, entry in pairs(PlayerJobs) do
        if type(entry.permissions) == 'table' and entry.permissions[permission] == true
            and (not onDuty or ClockedOnJobs[jobId] ~= nil) then
            return true
        end
    end
    return false
end

--- Is the player on duty — at this job (jobId or key), or with none, anywhere? Global for spur_core's
--- own files (client/actions.lua's `require = { onDuty = true }`); the export below is the same.
---@param job number|string|nil
---@return boolean
function PlayerIsClockedOn(job)
    if job ~= nil then
        local jobId = jobIdOf(job)
        return jobId ~= nil and ClockedOnJobs[jobId] ~= nil
    end
    return next(ClockedOnJobs) ~= nil
end

exports('IsPlayerClockedOn', PlayerIsClockedOn)

--- Does the player have a role at this job (jobId or key) — employed, or owning it? Global for
--- spur_core's own files (client/actions.lua's `require = { job = ... }`).
---@param job number|string
---@return boolean
function PlayerHasJob(job)
    return jobIdOf(job) ~= nil
end

--- The job the player is on duty at: the one clocked on most recently, the same one the server's
--- GetPlayerJob and the whipJob statebag name. The same name as the server's, without the person.
exports('GetPlayerJob', function()
    local best, bestOrder = nil, nil
    for jobId, order in pairs(ClockedOnJobs) do
        if PlayerJobs[jobId] and (not bestOrder or order > bestOrder) then
            best, bestOrder = PlayerJobs[jobId], order
        end
    end
    return best
end)

-- ============================================
-- Clock On/Off Functions
-- ============================================
--
-- They answer true, or false and why in words: 'They do not work there', 'No such job', 'This job
-- puts people on duty itself', or whip's own refusal ('Rate limited', 'Player is dead'). They wait
-- for the server: call them from a thread (a command, a key binding, an interaction callback).

--- Go on duty at a job (jobId or key). The server's ClockOn, for this player.
exports('ClockOn', function(job)
    return Callback('spur_core:jobs:clockOn', job)
end)

--- Go off duty at a job (jobId or key) — or, with none, at every job. The server's ClockOff, for this player.
exports('ClockOff', function(job)
    return Callback('spur_core:jobs:clockOff', job)
end)
