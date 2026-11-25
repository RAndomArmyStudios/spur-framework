-- Dev commands (whip.devtools), built only on Director.*, DirectorStore and DirectorPacks.
--   /director spot <worldId>     where you stand becomes that placed thing's spot
--   /director load <name>        server/director/examples/<name>.json, made active (not saved)
--   /director save <name>        that example into the store
--   /director on <key> [rev]     switch a stored scenario on (stays on across restarts)
--   /director stop <key>         switch it off
--   /director start <key>        a run for you
--   /director list | scenarios | history <key> | abort <runId>
--   /director npctest <1-6|stop> an NPC test scenario (npctests.lua)
--   /director send <event> [v]   a script's event into your own Test (any Director builder)
--   /director cards              other resources' cards and the scenarios using them
--   /director events             print every script's SendDirectorEvent (again: stop)

local R = DirectorRuntime
local CORE = GetCurrentResourceName()

local function say(fmt, ...) print(('[spur_core:director] ' .. fmt):format(...)) end

local spots = {}

local function allowed(src) return src == 0 or DevTools.isAllowed(src) end   -- developer mode on, too
local function reply(src, msg, kind)
    if src == 0 then say('%s', msg) else NotifyPlayer(src, msg, kind or 'info') end
end

local function readExample(name)
    if type(name) ~= 'string' or not name:match('^[%w_%-]+$') then return nil, 'a scenario name is letters, digits, _ and -' end
    local raw = LoadResourceFile(CORE, ('server/director/examples/%s.json'):format(name))
    if not raw then return nil, 'no example called ' .. name end
    local ok, doc = pcall(json.decode, raw)
    if not ok or type(doc) ~= 'table' then return nil, 'that file is not readable JSON' end
    -- Spots set with /director spot replace the file's; a file that says "spot" needs one.
    for _, w in ipairs(doc.world or {}) do
        local s = spots[w.id]
        w.def = w.def or {}
        if s then
            w.def.coords = s
        elseif w.def.coords == 'spot' then
            return nil, ('stand where "%s" goes and type /director spot %s first'):format(tostring(w.id), tostring(w.id))
        end
    end
    return doc
end

RegisterCommand('director', function(src, args)
    local sub, a = args[1], args[2]
    -- /director alone opens the Director for a builder; the rest are whip.devtools only.
    if sub == nil and src ~= 0 then
        if Permissions.has(src, 'director.build') then TriggerClientEvent('spur_core:client:openDirector', src) end
        return
    end
    -- /director send: only your own Test hears it; a real run hears only real SendDirectorEvent calls.
    if sub == 'send' and src ~= 0 then
        if not Permissions.has(src, 'director.build') then return reply(src, 'Director builders only', 'error') end
        if not a then return reply(src, '/director send <event> [value]', 'error') end
        local mine
        for _, run in ipairs(R.list()) do
            -- A script's TestDirectorCard or TestDirectorScenario run is not their Test.
            if run.test and run.starter == src and not (Director.isCardTest and Director.isCardTest(run))
                and not (Director.isScriptTest and Director.isScriptTest(run)) then mine = run end
        end
        if not mine then return reply(src, 'Start a Test first: this sends into your test', 'error') end
        local heard = Director.sendEvent(a, { source = src, value = args[3] }, { runId = mine.id }, 'console', true)
        return reply(src, ('%s: %s'):format(a, (tonumber(heard) or 0) > 0 and 'your test heard it' or 'nothing in your test was waiting for it'), 'info')
    end
    if not allowed(src) then return end
    if sub == 'spot' and a and src ~= 0 then
        local ped = GetPlayerPed(src)
        local c = GetEntityCoords(ped)
        spots[a] = { x = c.x, y = c.y, z = c.z, heading = GetEntityHeading(ped) }
        reply(src, ('Spot "%s" set here'):format(a), 'success')
    elseif sub == 'load' and a then
        local doc, why = readExample(a)
        if not doc then return reply(src, why, 'error') end
        local ok, res = Director.activate(a, doc)
        if not ok then
            if type(res) == 'table' then
                for _, p in ipairs(res) do
                    if p.severity == 'error' then say('%s: %s%s', a, p.node and ('card ' .. p.node .. ': ') or '', p.message) end
                end
                return reply(src, a .. ' did not pass its check: see the server console', 'error')
            end
            return reply(src, tostring(res), 'error')
        end
        reply(src, a .. ' is active', 'success')
    elseif sub == 'save' and a then
        if Director.off then return reply(src, 'The Director is off: ' .. Director.off, 'error') end
        local doc, why = readExample(a)
        if not doc then return reply(src, why, 'error') end
        local by = src ~= 0 and src or nil
        local row = DirectorStore.get(a)
        -- A shipped scenario is read-only: its pack changes it.
        if row and DirectorStore.packOf(a) then return reply(src, a .. ' is shipped by ' .. DirectorStore.packOf(a) .. ': it is read-only here', 'error') end
        if row then
            local rev, swhy = DirectorStore.save(a, row.draftRev, doc, by, 'saved from the example file')
            reply(src, rev and (('%s saved as revision %d'):format(a, rev)) or swhy, rev and 'success' or 'error')
        else
            local made, cwhy = DirectorStore.create(a, doc.name or a, doc, by)
            reply(src, made and (a .. ' is in the store (revision 1): /director on ' .. a) or cwhy, made and 'success' or 'error')
        end
    elseif sub == 'on' and a then
        if Director.off then return reply(src, 'The Director is off: ' .. Director.off, 'error') end
        local row = DirectorStore.get(a)
        if not row then return reply(src, 'no stored scenario called ' .. a .. ' (/director save it first)', 'error') end
        -- A shipped scenario is on only while its pack runs.
        local mayOn, packWhy = DirectorPacks.mayActivate(a)
        if not mayOn then return reply(src, packWhy, 'error') end
        local rev = tonumber(args[3]) or row.draftRev
        local doc, why = DirectorStore.revision(a, rev)
        if not doc then return reply(src, why, 'error') end
        local ok, res = Director.activate(a, doc, { dbId = row.id, rev = rev, by = src ~= 0 and src or nil })
        if not ok then
            if type(res) == 'table' then
                for _, p in ipairs(res) do
                    if p.severity == 'error' then say('%s: %s%s', a, p.node and ('card ' .. p.node .. ': ') or '', p.message) end
                end
                return reply(src, a .. ' did not pass its check: see the server console', 'error')
            end
            return reply(src, tostring(res), 'error')
        end
        DirectorStore.setStatus(a, 'active', rev, src ~= 0 and src or nil)
        -- Whoever switched it on is now the one accepted as providing its cards.
        Director.stampCards(a, doc, src)
        reply(src, ('%s is on at revision %d'):format(a, rev), 'success')
    elseif sub == 'stop' and a then
        local sc = Director.active[a]
        local by = src ~= 0 and src or nil
        local row = DirectorStore.get(a)
        if not sc and row and row.status == 'active' then
            -- Meant to be on but off in the world (script or pack stopped it): switching off keeps it off.
            Director.scriptSwitched[a] = nil
            local done = DirectorStore.setStatus(a, 'disabled', nil, by)
            return reply(src, done and (a .. ' is off') or DB_ERROR, done and 'success' or 'error')
        end
        local ok, why = Director.deactivate(a, nil, by)
        if ok and sc and sc.dbId then DirectorStore.setStatus(a, 'disabled', nil, by) end
        reply(src, ok and (a .. ' is off') or why, ok and 'success' or 'error')
    elseif sub == 'scenarios' then
        for _, s in ipairs(DirectorStore.list()) do
            say('%s "%s": %s, draft rev %d%s, by %s, last changed by %s', s.key, s.name, s.status, s.draftRev,
                s.activeRev and (', active rev ' .. s.activeRev) or '', tostring(s.createdBy), tostring(s.updatedBy))
        end
        reply(src, Director.off and ('The Director is off: ' .. Director.off) or 'Listed in the server console')
    elseif sub == 'history' and a then
        for _, h in ipairs(DirectorStore.history(a, 20)) do
            say('%s rev %d by %s%s', a, h.rev, tostring(h.editedBy), h.note and (': ' .. h.note) or '')
        end
        reply(src, 'Listed in the server console')
    elseif sub == 'start' and a and src ~= 0 then
        local sc = Director.active[a]
        if not sc then return reply(src, 'that scenario is not active', 'error') end
        local run, why = Director.startRun(sc, src, { source = src })
        reply(src, run and ('Run ' .. run.id .. ' started') or why, run and 'success' or 'error')
    elseif sub == 'abort' and a then
        local ok = Director.cutShort(tonumber(a), 'stopped by an admin')
        reply(src, ok and 'Aborted' or 'No such run', ok and 'success' or 'error')
    elseif sub == 'npctest' then
        -- NPC test scenarios built where you stand (server/director/npctests.lua).
        local msg, kind = Director.npcTest(src, a)
        reply(src, msg, kind)
    elseif sub == 'list' then
        for id, sc in pairs(Director.active) do say('active: %s (rev %s) tag %s', id, tostring(sc.rev), sc.tag) end
        for _, run in ipairs(R.list()) do
            local ps = {}
            for s in pairs(run.players) do ps[#ps + 1] = tostring(s) end
            say('run %d of %s: players %s, %d cards so far', run.id, tostring(run.scenarioId), table.concat(ps, ','), run.steps)
        end
        reply(src, 'Listed in the server console')
    elseif sub == 'cards' then
        for _, line in ipairs(Director.cardsReport and Director.cardsReport() or {}) do say('%s', line) end
        reply(src, 'Listed in the server console')
    elseif sub == 'events' then
        Director.watchEvents = not Director.watchEvents
        reply(src, Director.watchEvents and 'Scripts\' Director events are printed in the server console (/director events again to stop)'
            or 'Scripts\' Director events are no longer printed')
    else
        reply(src, '/director (the editor) | spot <id> | load <name> | save <name> | on <key> [rev] | stop <key> | start <key> | list | scenarios | history <key> | abort <runId> | npctest <1-6 | stop> | send <event> [value] | cards | events')
    end
end, false)
