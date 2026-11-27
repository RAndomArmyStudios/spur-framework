-- ============================================
-- SATELLITES BACK AFTER A RESTART — server/satellites_back.lua
-- ============================================
--
-- A satellite whose manifest says `dependency 'spur_core'` is stopped by Cfx.re when spur_core stops, and nothing
-- started it again: a `restart spur_core` left every one of them stopped. Started straight back WITH spur_core (a tool
-- restarting them all at once), they came up in the players' games before spur_core had, and spur_core was left
-- started but half working there: no exports, no HUD (Josh, 31 Oct; up first, it came up whole every time).
--
-- So spur_core brings them back itself, once it is up in every game:
--   its stop    the satellites that stopped with it (Cfx.re stops them first, in the same moment) are written down
--   its start   on a restart (a cold start is server.cfg's to do), once spur_core is ready here and every player's
--               game has said spur_core is up there (client/ready.lua), or WAIT_MS has gone by for a game that
--               never says so, each of them still stopped is started.
-- A satellite stopped by hand earlier is not on the list, and stays stopped.

local KVP = 'spur_core:satellitesStopped'
local SAME_MOMENT_MS = 1000   -- stopped this close before spur_core did: it went with spur_core
local FRESH_S = 300           -- a list older than this is not this restart's
local COLD_START_MS = 90000   -- the server process has been up less than this: a cold start
local WAIT_MS = 45000         -- for every game to have spur_core up

local SELF = GetCurrentResourceName()
local stoppedAt = {}   -- [resource] = GetGameTimer() when it stopped (resources that depend on spur_core only)
local upIn = {}        -- [source] = true: that player's game has had spur_core up since this start

--- `dependency 'spur_core'` is filed as 'dependency'; `dependencies { 'spur_core' }` (whip_autos, whip_fuel, whip_rope)
--- as 'dependencie': Cfx.re makes a plural key singular by dropping its last letter (seen on Legacy, 31 Oct).
local function dependsOnCore(res)
    for _, key in ipairs({ 'dependency', 'dependencie' }) do
        for i = 0, GetNumResourceMetadata(res, key) - 1 do
            if GetResourceMetadata(res, key, i) == SELF then return true end
        end
    end
    return false
end

--- Is `res` a satellite (its manifest depends on spur_core)? For the setup report (server/setup_report.lua).
Satellites = { dependsOnCore = dependsOnCore }

AddEventHandler('onResourceStop', function(res)
    if res ~= SELF and dependsOnCore(res) then stoppedAt[res] = GetGameTimer() end
end)

CoreStop.add(10, 'satellites: write down the ones stopping with spur_core', function()
    local now, list = GetGameTimer(), {}
    for res, at in pairs(stoppedAt) do
        if now - at <= SAME_MOMENT_MS then list[#list + 1] = res end
    end
    if #list == 0 then DeleteResourceKvp(KVP) return end
    table.sort(list)
    SetResourceKvp(KVP, json.encode({ at = os.time(), list = list }))
end)

--- A player's game saying spur_core is up there (client/ready.lua, as it announces). Nothing is trusted from it but
--- that this player need not be waited for.
SecureEvent('spur_core:server:coreUpHere', {
    requirePlayer = false, whileDead = true, rateLimit = 2000,
}, function(source)
    upIn[source] = true
end)

AddEventHandler('playerDropped', function()
    upIn[source] = nil
end)

AddEventHandler('spur_core:onReady', function(info)
    if type(info) ~= 'table' or info.reason ~= 'coreStarted' then return end
    local saved = GetResourceKvpString(KVP)
    if not saved then return end
    DeleteResourceKvp(KVP)
    local ok, rec = pcall(json.decode, saved)
    if not ok or type(rec) ~= 'table' or type(rec.list) ~= 'table' then return end
    if os.time() - (tonumber(rec.at) or 0) > FRESH_S then return end
    if GetGameTimer() < COLD_START_MS then
        -- A cold start: server.cfg starts them. Said, in case this was a restart by hand in the first 90 s and
        -- some of them are still stopped after all.
        local still = {}
        for _, res in ipairs(rec.list) do
            if GetResourceState(res) == 'stopped' then still[#still + 1] = res end
        end
        if #still > 0 then
            print(('[spur_core] not starting again what stopped with it (%s): the server started under %d s ago, so'
                .. ' server.cfg starts them. If you restarted spur_core by hand, start them yourself.')
                :format(table.concat(still, ', '), COLD_START_MS // 1000))
        end
        return
    end

    CreateThread(function()
        local t0 = GetGameTimer()
        local missing
        repeat
            missing = {}
            for _, id in ipairs(GetPlayers()) do
                local src = tonumber(id)
                if not upIn[src] then missing[#missing + 1] = ('%s (id %s)'):format(GetPlayerName(src) or '?', id) end
            end
            if #missing == 0 then break end
            Wait(250)
        until GetGameTimer() - t0 > WAIT_MS

        local back = {}
        for _, res in ipairs(rec.list) do
            if GetResourceState(res) == 'stopped' and StartResource(res) then back[#back + 1] = res end
        end
        if #back == 0 then return end
        print(('[spur_core] started again what stopped with it: %s (%.1f s after spur_core was ready%s)')
            :format(table.concat(back, ', '), (GetGameTimer() - t0) / 1000,
                #missing > 0 and ('; spur_core never said it was up in the game of ' .. table.concat(missing, ', ')) or ''))
    end)
end)
