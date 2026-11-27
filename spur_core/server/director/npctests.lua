-- NPC test scenarios built where you stand.
--   /director npctest <1-6>   build and start a test round you, with /npcdebug on
--   /director npctest stop    switch every test off (their NPCs go)
-- 1 plain, 2 six guards, 3 MLO hold only, 4 guards without the MLO hold, 5 walk, 6 car.
-- Tests are not saved: each ends after three minutes, or when its NPC is killed.

local function N(id, t, props) return { id = id, type = t, v = 1, x = 0, y = 0, props = props or {} } end

--- A spot `dist` ahead of the player and `side` to their right, facing them.
local function around(src, dist, side)
    local ped = GetPlayerPed(src)
    local c = GetEntityCoords(ped)
    local h = GetEntityHeading(ped)
    local r = math.rad(h)
    local fx, fy = -math.sin(r), math.cos(r)       -- the game: heading 0 faces +Y
    local rx, ry = fy, -fx
    return { x = c.x + fx * dist + rx * (side or 0), y = c.y + fy * dist + ry * (side or 0), z = c.z,
             heading = (h + 180.0) % 360.0 }
end

local function npcDef(at, over)
    local d = { model = 's_m_m_valdealer_01', coords = at, behaviour = 'stand', conditions = { canMove = true },
                weapon = 'WEAPON_REVOLVER_CATTLEMAN' }
    for k, v in pairs(over or {}) do d[k] = v end
    return d
end

--- Six NPCs alike in a ring 4 m round one spot, and their ids (one Spawn NPC makes them, working together).
local function sixAround(at, label, over)
    local world, ids = {}, {}
    for i = 1, 6 do
        local a = math.rad(i * 60)
        local c = { x = at.x + math.cos(a) * 4, y = at.y + math.sin(a) * 4, z = at.z, heading = at.heading }
        ids[i] = 'npc' .. i
        world[i] = { id = ids[i], kind = 'npc', layer = 'run', label = ('%s %d'):format(label, i), def = npcDef(c, over) }
    end
    return world, ids
end

local TESTS = {
    {
        name = 'plain', says = 'one NPC, nothing special set. It should come at you and shoot',
        build = function(src)
            local world = { { id = 'npc', kind = 'npc', layer = 'run', label = 'Plain NPC', def = npcDef(around(src, 15)) } }
            return world, { N('spawn', 'npc.spawn', { npcs = { 'npc' }, hostile = true }) }, 'spawn', true
        end,
    },
    {
        name = 'bigtest2', says = 'bigtest2\'s guards exactly (6, guard, invincible, armour, MLO hold). Do they move?',
        build = function(src)
            local world, ids = sixAround(around(src, 18), 'bigtest2 guard', {
                behaviour = 'guard', conditions = { invincible = true, canMove = true }, armour = 100, fightBack = true, interior = true })
            return world, { N('spawn', 'npc.spawn', { npcs = ids, hostile = true }) }, 'spawn', false
        end,
    },
    {
        name = 'MLO hold', says = 'test 1 with only "inside an interior" set. If this one stands still, that setting is it',
        build = function(src)
            local world = { { id = 'npc', kind = 'npc', layer = 'run', label = 'MLO-held NPC', def = npcDef(around(src, 15), { interior = true }) } }
            return world, { N('spawn', 'npc.spawn', { npcs = { 'npc' }, hostile = true }) }, 'spawn', true
        end,
    },
    {
        name = 'guard', says = 'bigtest2\'s guards with the MLO hold off. If these move, the MLO hold was it',
        build = function(src)
            local world, ids = sixAround(around(src, 18), 'Guard', {
                behaviour = 'guard', conditions = { invincible = true, canMove = true }, armour = 100, fightBack = true })
            return world, { N('spawn', 'npc.spawn', { npcs = ids, hostile = true }) }, 'spawn', false
        end,
    },
    {
        name = 'walk', says = 'a calm NPC walks to a spot on your right, then follows you. Movement alone, no fight',
        build = function(src)
            local world = {
                { id = 'npc', kind = 'npc', layer = 'run', label = 'Walker', def = npcDef(around(src, 8), { weapon = nil }) },
                { id = 'spot', kind = 'spot', layer = 'run', label = 'Over there', def = { coords = around(src, 8, 20) } },
            }
            local cards = {
                N('spawn', 'npc.spawn', { npcs = { 'npc' } }),
                N('walk', 'npc.walkTo', { npc = 'npc', at = 'spot', seconds = 60 }),
                N('there', 'player.message', { text = 'NPC test: it got there. Now it follows you', kind = 'success' }),
                N('late', 'player.message', { text = 'NPC test: it did NOT get there in a minute', kind = 'error' }),
                N('lost', 'player.message', { text = 'NPC test: it died or went on the way', kind = 'error' }),
                N('follow', 'npc.follow', { npc = 'npc' }),
            }
            local links = {
                { from = { node = 'spawn', pin = 'out' }, to = { node = 'walk', pin = 'in' } },
                { from = { node = 'walk', pin = 'arrived' }, to = { node = 'there', pin = 'in' } },
                { from = { node = 'walk', pin = 'timeout' }, to = { node = 'late', pin = 'in' } },
                { from = { node = 'walk', pin = 'failed' }, to = { node = 'lost', pin = 'in' } },
                { from = { node = 'there', pin = 'out' }, to = { node = 'follow', pin = 'in' } },
            }
            return world, cards, 'spawn', false, links
        end,
    },
    {
        name = 'car', says = 'get in the car beside you: the NPC 30 m ahead should come at you, in the car too',
        build = function(src)
            local world = {
                { id = 'npc', kind = 'npc', layer = 'run', label = 'Car test NPC', def = npcDef(around(src, 30)) },
                -- RedM (spur_core, 23 Nov 2026): an RDR2 buggy, not the original game's Sultan.
                { id = 'car', kind = 'vehicle', layer = 'run', label = 'Test car', def = { model = 'buggy01', coords = around(src, 0, 4), locked = false,
                  key = { exists = true, where = 'ignition' } } },
            }
            local cards = {
                N('car1', 'vehicle.spawn', { cars = { 'car' } }),
                N('spawn', 'npc.spawn', { npcs = { 'npc' }, hostile = true }),
            }
            local links = {
                { from = { node = 'car1', pin = 'out' }, to = { node = 'spawn', pin = 'in' } },
            }
            return world, cards, 'car1', true, links
        end,
    },
}

--- The scenario for one test, round `src`: its cards, plus the start, the objective, a three-minute
--- end and (where its NPC can be killed) NPC Killed ending it.
local function testDoc(src, n)
    local t = TESTS[n]
    local world, cards, first, killable, links = t.build(src)
    local nodes = {
        N('start', 'scenario.started'),
        N('say', 'player.objective', { text = ('NPC test %d (%s): %s'):format(n, t.name, t.says) }),
        N('clock', 'flow.wait', { seconds = 180 }),
        N('over', 'scenario.succeed', { reason = 'the test is over' }),
        N('nope', 'scenario.fail', { reason = 'a test card failed: see the server console' }),
    }
    links = links or {}
    for _, c in ipairs(cards) do nodes[#nodes + 1] = c end
    links[#links + 1] = { from = { node = 'start', pin = 'out' }, to = { node = 'say', pin = 'in' } }
    links[#links + 1] = { from = { node = 'say', pin = 'out' }, to = { node = first, pin = 'in' } }
    links[#links + 1] = { from = { node = 'start', pin = 'out' }, to = { node = 'clock', pin = 'in' } }
    links[#links + 1] = { from = { node = 'clock', pin = 'done' }, to = { node = 'over', pin = 'in' } }
    -- A card that can fail ends the test saying so.
    for _, c in ipairs(cards) do
        local def = DirectorNodes.get(c.type)
        for _, pin in ipairs(def and def.outputs or {}) do
            if pin == 'failed' and c.type ~= 'npc.walkTo' then
                links[#links + 1] = { from = { node = c.id, pin = 'failed' }, to = { node = 'nope', pin = 'in' } }
            elseif pin == 'timeout' and c.type ~= 'npc.walkTo' then
                links[#links + 1] = { from = { node = c.id, pin = 'timeout' }, to = { node = 'nope', pin = 'in' } }
            end
        end
    end
    if killable then
        nodes[#nodes + 1] = N('killed', 'npc.killed', { npc = 'npc' })
        nodes[#nodes + 1] = N('won', 'scenario.succeed', { reason = 'you killed it' })
        links[#links + 1] = { from = { node = 'killed', pin = 'out' }, to = { node = 'won', pin = 'in' } }
    end
    for i, l in ipairs(links) do l.id = 'w' .. i end
    return {
        format = DirectorDoc.FORMAT, name = ('NPC test %d: %s'):format(n, t.name),
        settings = { start = { mode = 'admin' }, maxConcurrentRuns = 1, maxRunSec = 600 },
        vars = {}, world = world, nodes = nodes, links = links,
    }
end

--- /director npctest <n | stop>. Answers a line to tell the player.
---@return string message
---@return string kind
function Director.npcTest(src, arg)
    if arg == 'stop' then
        local n = 0
        for i = 1, #TESTS do
            if Director.active['npctest' .. i] then
                Director.deactivate('npctest' .. i, 'the NPC test was stopped')
                n = n + 1
            end
        end
        if Npcs.debugFor then Npcs.debugFor(src, false) end
        return ('%d NPC test(s) stopped'):format(n), 'success'
    end
    local n = math.tointeger(tonumber(arg))
    if not n or not TESTS[n] then
        local names = {}
        for i, t in ipairs(TESTS) do names[#names + 1] = ('%d %s'):format(i, t.name) end
        return '/director npctest <' .. table.concat(names, ', ') .. '> | stop', 'info'
    end
    if src == 0 or not GetPlayerPed(src) or GetPlayerPed(src) == 0 then return 'stand somewhere first (in game)', 'error' end
    local key = 'npctest' .. n
    local ok, res = Director.activate(key, testDoc(src, n))
    if not ok then
        for _, p in ipairs(type(res) == 'table' and res or {}) do
            if p.severity == 'error' then print(('[spur_core:director] %s: %s%s'):format(key, p.node and (p.node .. ': ') or '', p.message)) end
        end
        return 'the test did not pass its check: see the server console', 'error'
    end
    local run, why = Director.startRun(Director.active[key], src, { source = src })
    if not run then return 'the test could not start: ' .. tostring(why), 'error' end
    if Npcs.debugFor then Npcs.debugFor(src, true) end
    return ('NPC test %d started. /npcdebug shows what each NPC is doing (and prints changes to F8)'):format(n), 'success'
end
