-- ============================================
-- CLOCK — this game's reading of the server's time (server/clock.lua)
-- ============================================
--
-- Clock.now() is the server's GetGameTimer as this game makes it out: its own GetGameTimer plus an
-- offset. The offset comes from the server's answer with the shortest round trip of a few asks, so it
-- is off by at most half of that trip (a 200 ms ping: under 100 ms, usually far less). Something that
-- plays in step with the other games (a prop's tasks, a take) starts from a moment the server names,
-- and reads Clock.now() against it.
--
-- Asked as whip starts here, when the character loads, and again every five minutes; an ask with no answer is asked
-- again RETRY_MS later until one comes. Until the first answer it reads this game's own time, and Clock.synced()
-- says so: what plays in step waits for it (Clock.ready).

Clock = {}

local SAMPLES   = 5
local GAP_MS    = 150
local RESYNC_MS = 5 * 60 * 1000
local RETRY_MS  = 2000

local offset, rtt, synced, syncing = 0, nil, false, false
local resyncAt = 0

--- The server's time, in its milliseconds.
---@return number
function Clock.now() return GetGameTimer() + offset end

--- Has an answer come back yet?
function Clock.synced() return synced end

--- The shortest round trip seen in the last sync, ms (nil before one).
function Clock.roundTrip() return rtt end

local function sample()
    local t0 = GetGameTimer()
    local s = Callback('spur_core:clock:now')
    local t1 = GetGameTimer()
    if type(s) ~= 'number' then return nil end
    return t1 - t0, s - (t0 + t1) / 2
end

--- Take the offset again (a thread: each ask waits for the server).
function Clock.sync()
    if syncing then return end
    syncing = true
    CreateThread(function()
        local bestRtt, bestOff
        for i = 1, SAMPLES do
            local trip, off = sample()
            if trip and (not bestRtt or trip < bestRtt) then bestRtt, bestOff = trip, off end
            if i < SAMPLES then Wait(GAP_MS) end
        end
        if bestOff then
            offset, rtt, synced = math.floor(bestOff + 0.5), bestRtt, true
            resyncAt = GetGameTimer() + RESYNC_MS
        else
            resyncAt = GetGameTimer() + RETRY_MS   -- (no answer: again soon, not in five minutes)
        end
        syncing = false
    end)
end

--- Has an answer come, waiting for one (asked for if need be) up to `ms`? A thread.
function Clock.ready(ms)
    if synced then return true end
    Clock.sync()
    local untilAt = GetGameTimer() + (ms or 3000)
    while not synced and GetGameTimer() < untilAt do Wait(100) end
    return synced
end

-- Again every few minutes (two clocks drift apart slowly), and every RETRY_MS while no answer has come. One thread.
CreateThread(function()
    Wait(1000)
    Clock.sync()
    while true do
        Wait(synced and 30000 or RETRY_MS)
        if GetGameTimer() >= resyncAt then Clock.sync() end
    end
end)

AddEventHandler('spur_core:player:loaded', function() Clock.sync() end)
