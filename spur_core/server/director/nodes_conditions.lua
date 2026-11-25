-- ============================================
-- Director — Fail Conditions: rules that fail a run whenever they are broken
-- ============================================
--
-- A FAIL CONDITION is a card with no wires. Put on the grid, it watches the whole run, from its start to its end, and
-- the moment its rule is broken it fails the run for everyone, or (a rule about one player) takes only that player
-- out of the run. So a job does not need a Fail wired from every card that could go wrong: "the car must not be
-- lost" is said once.
--
--   Fail If a Player Goes Down    one of them (or all of them at once) is down
--   Fail If a Player Strays       one of them is further than a distance from a placed thing, for a while
--   Fail If the Car Is Lost       the run's car is blown up, sunk or gone (once a card has made it)
--   Fail If the Car Is Damaged    the run's car takes more damage than a share
--   Fail If an NPC Dies           an NPC the run made (any of its group, or all of them) is killed
--   Fail If a Variable            a variable passes a test (If's: "alarms at least 3")
--
-- ANOTHER RESOURCE'S, its own rule (Whip.card's `fail`: arrested, a wanted level): a fail condition of that resource's
-- event (SendDirectorEvent), broken when it comes about one of the run's players (cards_api.lua failFilter), with the
-- same When it is broken and Why.
--
-- HOW THEY WORK: each card's `watch` looks at the run once a second (runtime.lua: a watch, for the whole run, which
-- never keeps it going nor starts it). A rule broken is ctx:broken(player, onlyThem): the runtime fails the run with
-- the card's Why, or takes that player out, once a run and once a player, and its step names the card.

local function define(def)
    def.category = 'fail'
    def.condition = true
    def.inputs, def.outputs = {}, {}
    return DirectorKit.define(def)
end

local ENDS = { 'everyone', 'them' }
local ENDS_LABELS = { everyone = 'Fail the scenario for everyone', them = 'Take only that player out' }
local function endsField(default)
    return { key = 'ends', kind = 'select', label = 'When it is broken', options = ENDS, optionLabels = ENDS_LABELS, default = default or 'everyone' }
end
local function reasonField(default)
    return { key = 'reason', kind = 'text', label = 'Why (said to the player)', default = default, maxLength = 120 }
end

local playerPos = DirectorKit.playerPos
local vec = DirectorKit.vec3

-- ============================================
-- Players
-- ============================================

define({
    type = 'fail.playerDown', v = 1, title = 'Fail If a Player Goes Down',
    desc = 'Whenever a player in the scenario goes down (or every player in it at once), the scenario fails, or that player is out of it.',
    props = {
        DirectorNodes.anyAllField('Who'),
        endsField('everyone'),
        reasonField('Someone went down'),
    },
    watch = function(ctx)
        local players, down = ctx:players(), {}
        for _, s in ipairs(players) do
            local p = Players[s]
            if p and p.isDead then down[#down + 1] = s end
        end
        if #down == 0 then return end
        local all = DirectorNodes.wantsAll(ctx)
        if all and #down < #players then return end
        if not all and ctx:prop('ends') == 'them' then
            for _, s in ipairs(down) do ctx:broken(s, true) end
        else
            ctx:broken(down[1], false)
        end
    end,
})

define({
    type = 'fail.strays', v = 1, title = 'Fail If a Player Strays',
    desc = 'The scenario fails, or that player is out of it, when a player stays too far from a placed thing for too long.',
    props = {
        { key = 'at', kind = 'world', label = 'From (a placed thing)', required = true },
        { key = 'radius', kind = 'number', label = 'Further than (metres)', default = 200, min = 10, max = 5000 },
        { key = 'grace', kind = 'number', label = 'For (seconds)', default = 10, min = 0, max = 300 },
        endsField('them'),
        reasonField('You left the area'),
    },
    watch = function(ctx)
        local w = ctx:place(ctx.node.props.at)
        local at = vec(type(w) == 'table' and type(w.def) == 'table' and w.def.coords or nil)
        if not at then return end
        local radius = tonumber(ctx:prop('radius')) or 200
        local grace = tonumber(ctx:prop('grace')) or 10
        local away = ctx:state()   -- [player] = when they went past it
        local now = GetGameTimer()
        for _, s in ipairs(ctx:players()) do
            local p = playerPos(s)
            if p and #(p - at) > radius then
                if not away[s] then
                    away[s] = now
                    if grace > 0 and not ctx.run.test then
                        NotifyPlayer(s, ('Go back: you have %d seconds'):format(math.floor(grace)), 'warning')
                    end
                end
                if now - away[s] >= grace * 1000 then ctx:broken(s, ctx:prop('ends') == 'them') end
            else
                away[s] = nil
            end
        end
    end,
})

-- ============================================
-- The run's car
-- ============================================

define({
    type = 'fail.carLost', v = 2, title = 'Fail If the Car Is Lost',
    desc = 'Whenever one of the cars picked is blown up, sunk or gone (once a card has made it), the scenario fails.',
    upgrade = function(props) return DirectorNodes.toList(props, 'car') end,
    props = {
        DirectorNodes.thingsField('car', 'vehicle', 'Cars'),
        reasonField('The car was lost'),
    },
    watch = function(ctx)
        local s = ctx:state()
        s.wrecked = s.wrecked or {}
        for _, carW in ipairs(DirectorNodes.things(ctx, 'car')) do
            local ent, gone, made = DirectorNodes.runCar(ctx, carW)
            if made then
                if gone then return ctx:broken(nil, false) end
                -- (Three looks in a row: a game taking the car over reads it as wrecked for a moment.)
                if ent and VehicleDamage.isWrecked(ent) then s.wrecked[carW] = (s.wrecked[carW] or 0) + 1 else s.wrecked[carW] = 0 end
                if s.wrecked[carW] >= 3 then return ctx:broken(nil, false) end
            end
        end
    end,
})

define({
    type = 'fail.carDamaged', v = 2, title = 'Fail If the Car Is Damaged',
    desc = 'Whenever one of the cars picked has taken more damage than the share you set (counted from when it was made), the scenario fails: "deliver it without a scratch".',
    upgrade = function(props) return DirectorNodes.toList(props, 'car') end,
    props = {
        DirectorNodes.thingsField('car', 'vehicle', 'Cars'),
        { key = 'percent', kind = 'number', label = 'More than (% damage)', default = 25, min = 1, max = 100 },
        reasonField('The car was too badly damaged'),
    },
    watch = function(ctx)
        local all = ctx:state()
        local limit = math.max(1, math.min(100, tonumber(ctx:prop('percent')) or 25))
        -- Each car counted on its own, from its own first reading.
        for _, carW in ipairs(DirectorNodes.things(ctx, 'car')) do
            all[carW] = all[carW] or {}
            local s = all[carW]
            local ent = DirectorNodes.runCar(ctx, carW)
            if not ent then
                s.base = nil
            else
                local d = DirectorNodes.carDamage(ent)
                -- Where it starts: the first real reading of this car (a car made damaged is not damage done).
                if d ~= nil and (s.base == nil or s.baseEnt ~= ent) then
                    if GetEntityHealth(ent) > 0 then s.base, s.baseEnt, s.over = d, ent, 0 end
                elseif d ~= nil then
                    if d - s.base > limit then s.over = (s.over or 0) + 1 else s.over = 0 end
                    if s.over >= 2 then return ctx:broken(nil, false) end
                end
            end
        end
    end,
})

-- ============================================
-- NPCs
-- ============================================

define({
    type = 'fail.npcDies', v = 2, title = 'Fail If an NPC Dies',
    desc = 'Whenever one of the NPCs picked is killed (or all of them), the scenario fails: a hostage, someone to escort.',
    upgrade = function(props) return DirectorNodes.toList(props, 'npc') end,
    props = {
        DirectorNodes.thingsField('npc', 'npc', 'Who (NPCs or groups)'),
        DirectorNodes.anyAllField('Of them', 'npcs'),
        reasonField('They were killed'),
    },
    watch = function(ctx)
        -- Every NPC the scenario made for each of them (a placed thing's copies too), once.
        local ids, seen = {}, {}
        for _, wid in ipairs(DirectorNodes.things(ctx, 'npc')) do
            local h = Director.handleOf(ctx.run, wid)
            for _, id in ipairs(DirectorNodes.npcIds(h)) do
                if not seen[id] then seen[id] = true; ids[#ids + 1] = id end
            end
        end
        if #ids == 0 then return end
        local dead, known = 0, 0
        for _, id in ipairs(ids) do
            local info = Npcs.get(id)
            if info then
                known = known + 1
                if info.alive == false then dead = dead + 1 end
            end
        end
        if dead == 0 then return end
        if DirectorNodes.wantsAll(ctx) and dead < known then return end
        ctx:broken(nil, false)
    end,
})

-- ============================================
-- Variables
-- ============================================

define({
    type = 'fail.variable', v = 1, title = 'Fail If a Variable',
    desc = 'Whenever a variable passes a test (as If tests it: "alarms at least 3"), the scenario fails.',
    props = {
        { key = 'var', kind = 'var', label = 'Variable', required = true },
        { key = 'op', kind = 'select', label = 'Is', options = DirectorNodes.VAR_OPS, default = 'at least' },
        { key = 'value', kind = 'text', label = 'Value', maxLength = 100 },
        reasonField('It went wrong'),
    },
    watch = function(ctx)
        if DirectorNodes.varMatches(ctx:var(ctx.node.props.var), ctx:prop('op'), ctx:prop('value')) then
            ctx:broken(nil, false)
        end
    end,
})

-- ============================================
-- After the end: what happens once a run has failed or succeeded
-- ============================================
--
-- No input: when the run fails (succeeds), for whatever reason, what is wired to the card plays: a text from the
-- contact, a payment, a line from the NPC. Everything else of the run has stopped; its chain has two minutes, and then
-- the run is over as it was (a Succeed or Fail in the chain changes nothing). runtime.lua startAfter. With these
-- (category 'fail'), not wrappers of `define` above: they are no conditions.

local function after(def)
    def.category, def.inputs, def.outputs = 'fail', {}, { 'out' }
    def.run = function() return 'out' end
    local ok, why = DirectorNodes.define(def)
    if not ok then print('^1[spur_core:director] card type refused: ' .. tostring(why) .. '^0') end
end

after({
    type = 'run.afterFail', v = 1, title = 'Activate After Failure', after = 'failed',
    desc = 'When the scenario fails, for any reason, what is wired to this plays (a text, a payment, a word from the NPC): two minutes at most, then it is over.',
})

after({
    type = 'run.afterSuccess', v = 1, title = 'Activate After Success', after = 'succeeded',
    desc = 'When the scenario succeeds, what is wired to this plays (a text, a payment, a word from the NPC): two minutes at most, then it is over.',
})
