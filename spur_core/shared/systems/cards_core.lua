-- ============================================
-- SYSTEMS — the cards every system has: flow, maths, variables, lists, time
-- ============================================
--
-- Side 'both': they run in either lane, because they touch nothing but the system itself. whip's API
-- cards (money, items, cars, areas) come in their own files, one per area, each server or client.

local C = SystemCards

--- Every card here touches only the system itself, so it runs in either lane. (whip's API cards say
--- their side themselves: C.define has no default.)
local function define(def)
    def.side = def.side or 'both'
    local ok, why = C.define(def)
    if not ok then print('^1[spur_core:systems] card type refused: ' .. tostring(why) .. '^0') end
end

local function num(v, fallback) v = tonumber(v); if v == nil or v ~= v then return fallback end return v end

-- ============================================
-- Starting: when the system switches on, and on a clock
-- ============================================

define({
    type = 'when.switchedOn', category = 'when', kind = 'trigger', title = 'When Switched On',
    desc = 'Once, each time the system switches on (the server starting, an admin switching it on).',
    onStart = true,
})

define({
    type = 'when.every', category = 'when', kind = 'trigger', title = 'Every Few Seconds',
    desc = 'Again and again, for as long as the system is on. It is nobody\'s: to do something for each player, read the players and use For Each.',
    props = { { key = 'seconds', kind = 'duration', label = 'Every (seconds)', default = 5, min = 0.25, max = 3600 } },
    timer = function(props) return num(props.seconds, 5) * 1000 end,
})

-- ============================================
-- Watching a value (walk.lua, Watches): checked again and again, starting only on a change
-- ============================================

local PER = { 'for each player', 'once for the server' }
local function watchEvery(props) return math.max(0.25, num(props.every, 0.5)) * 1000 end
local function watchPerPlayer(props) return props.per ~= PER[2] end

define({
    type = 'watch.crosses', category = 'when', kind = 'trigger', title = 'When a Number Goes Above or Below',
    desc = 'Checks a number again and again (a car\'s speed, a stat) and starts when it crosses its limit: going above it, below it, or either. Once for each crossing, not on every check. Wire what to watch into Number: for each player, its Player is the one being checked.',
    props = { { key = 'goes', kind = 'select', label = 'When it goes', options = { 'above', 'below', 'either way' }, default = 'above' },
              { key = 'per', kind = 'select', label = 'Checked', options = PER, default = PER[1] },
              { key = 'every', kind = 'duration', label = 'Every (seconds)', default = 0.5, min = 0.25, max = 60 } },
    values = { inputs = { { key = 'value', type = 'number', label = 'Number' }, { key = 'limit', type = 'number', label = 'Limit', default = 0 } },
               outputs = { { key = 'player', type = 'player', label = 'Player' }, { key = 'now', type = 'number', label = 'Now' },
                           { key = 'was', type = 'number', label = 'Was' } } },
    cost = 2,
    watch = {
        every = watchEvery,
        perPlayer = watchPerPlayer,
        check = function(ctx, last)
            local v, lim = ctx:input('value'), ctx:input('limit')
            if v == nil or lim == nil then return nil end   -- no reading now (on foot: no car speed)
            local side = v > lim and 1 or -1                  -- level with the limit counts as below
            local fire = false
            if last and last.side ~= side then
                local goes = ctx:prop('goes')
                fire = goes == 'either way' or (goes == 'above' and side == 1) or (goes == 'below' and side == -1)
            end
            return { side = side, value = v }, fire and { now = v, was = last.value } or nil
        end,
    },
})

--- A value as a watch compares it: numbers, text and yes/no as they are; a place by its x, y and z; a
--- player by who; anything else by what it holds (a few levels, a few entries: a change in a big list
--- deep down may be missed, never invented).
local function sameKey(v, depth)
    local t = type(v)
    if t ~= 'table' then return t .. ':' .. tostring(v) end
    if v.source ~= nil then return 'p:' .. tostring(v.source) end
    if type(v.x) == 'number' and type(v.y) == 'number' then return ('v:%.2f,%.2f,%.2f'):format(v.x, v.y, tonumber(v.z) or 0) end
    depth = (depth or 0) + 1
    if depth > 3 then return '{…}' end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    local parts = {}
    for i = 1, math.min(#keys, 32) do parts[i] = keys[i] .. '=' .. sameKey(v[keys[i]] ~= nil and v[keys[i]] or v[tonumber(keys[i])], depth) end
    return '{' .. table.concat(parts, ',') .. (#keys > 32 and ',…}' or '}')
end

define({
    type = 'watch.changes', category = 'when', kind = 'trigger', title = 'When a Value Changes',
    desc = 'Checks a value again and again (who is driving, a job, a car stat) and starts each time it is different from the last check. The first check only notes it.',
    props = { { key = 'per', kind = 'select', label = 'Checked', options = PER, default = PER[1] },
              { key = 'every', kind = 'duration', label = 'Every (seconds)', default = 0.5, min = 0.25, max = 60 } },
    values = { inputs = { { key = 'value', type = 'any', label = 'Value' } },
               outputs = { { key = 'player', type = 'player', label = 'Player' }, { key = 'now', type = 'any', label = 'Now' },
                           { key = 'was', type = 'any', label = 'Was' } } },
    cost = 2,
    watch = {
        every = watchEvery,
        perPlayer = watchPerPlayer,
        check = function(ctx, last)
            local v = ctx:input('value')
            if v == nil then return nil end
            local k = sameKey(v)
            local fire = last ~= nil and last.key ~= k
            return { key = k, value = v }, fire and { now = v, was = last.value } or nil
        end,
    },
})

-- ============================================
-- Flow
-- ============================================

define({
    type = 'flow.branch', category = 'flow', kind = 'action', title = 'Branch',
    desc = 'Goes Yes or No by a yes/no value (a Compare, a Formula, Has Item?).',
    outputs = { 'yes', 'no' },
    values = { inputs = { { key = 'condition', type = 'bool', label = 'If' } } },
    run = function(ctx) return ctx:need('condition') and 'yes' or 'no' end,
})

define({
    type = 'flow.sequence', category = 'flow', kind = 'action', title = 'Do In Order',
    desc = 'Runs First, then Second, then Third, then Fourth: each to its end (or its first wait) before the next.',
    outputs = { 'first', 'second', 'third', 'fourth' },
    run = function() return { 'first', 'second', 'third', 'fourth' } end,
})

define({
    type = 'flow.chance', category = 'flow', kind = 'action', title = 'Random Chance',
    desc = 'Goes Yes some of the time (the chance), otherwise No.',
    outputs = { 'yes', 'no' },
    values = { inputs = { { key = 'chance', type = 'number', label = 'Chance of Yes (%)', default = 50 } } },
    run = function(ctx)
        local chance = math.max(0, math.min(100, ctx:need('chance')))
        return math.random() * 100 < chance and 'yes' or 'no'
    end,
})

define({
    type = 'flow.once', category = 'flow', kind = 'action', title = 'First Time Only',
    desc = 'Goes First the first time, Again every time after (for everyone, per player, or per car).',
    outputs = { 'first', 'again' },
    props = { { key = 'scope', kind = 'scope', label = 'Counted', default = 'everyone' } },
    run = function(ctx)
        local s = ctx:state(ctx:prop('scope'))
        if s.done then return 'again' end
        s.done = true
        return 'first'
    end,
})

define({
    type = 'flow.cooldown', category = 'flow', kind = 'action', title = 'Cooldown',
    desc = 'Goes Ready, then Cooling until the time has passed (for everyone, per player, or per car): one fine per car a minute.',
    outputs = { 'ready', 'cooling' },
    props = { { key = 'scope', kind = 'scope', label = 'Counted', default = 'player' } },
    values = { inputs = { { key = 'seconds', type = 'number', label = 'For (seconds)', default = 60 } } },
    run = function(ctx)
        local s = ctx:state(ctx:prop('scope'))
        local now = ctx:now()
        if s.until_ and now < s.until_ then return 'cooling' end
        s.until_ = now + math.max(0, ctx:need('seconds')) * 1000
        return 'ready'
    end,
})

define({
    type = 'flow.gate', category = 'flow', kind = 'action', title = 'Gate',
    desc = 'Lets pulses through In only while open. Open and Close set it (for everyone).',
    inputs = { 'in', 'open', 'close' },
    outputs = { 'out' },
    labels = { ['in'] = 'In', open = 'Open', close = 'Close' },
    props = { { key = 'startOpen', kind = 'bool', label = 'Starts open', default = true } },
    run = function(ctx)
        local s = ctx:state('everyone')
        if s.open == nil then s.open = ctx:prop('startOpen') ~= false end
        if ctx.pin == 'open' then s.open = true return nil end
        if ctx.pin == 'close' then s.open = false return nil end
        return s.open and 'out' or nil
    end,
})

define({
    type = 'flow.delay', category = 'flow', kind = 'wait', title = 'Delay',
    desc = 'Waits, then goes on.',
    outputs = { 'done' },
    values = { inputs = { { key = 'seconds', type = 'number', label = 'Seconds', default = 1 } } },
    run = function(ctx)
        ctx:after(math.max(0.05, ctx:need('seconds')) * 1000, 'done')
        return nil
    end,
})

define({
    type = 'flow.waitUntil', category = 'flow', kind = 'wait', title = 'Wait Until',
    desc = 'Waits until a yes/no value turns Yes (asked 4 times a second), or gives up.',
    outputs = { 'yes', 'timeout' },
    labels = { yes = 'It did', timeout = 'Gave up' },
    values = { inputs = { { key = 'condition', type = 'bool', label = 'Until' },
                          { key = 'seconds', type = 'number', label = 'Give up after (s; 0 never)', default = 30 } } },
    run = function(ctx)
        if ctx:input('condition') == true then return 'yes' end
        local s = ctx:input('seconds') or 30
        ctx:poll(250, function(pctx) if pctx:input('condition') == true then return 'yes' end end)
        if s > 0 then ctx:after(s * 1000, 'timeout') end
        return nil
    end,
})

define({
    type = 'flow.forEach', category = 'flow', kind = 'action', title = 'For Each',
    desc = 'Runs Each once for every thing in a list (64 at most), with that thing and its number, then Done. A turn that waits (a Delay) carries on later by itself: Done does not wait for it.',
    outputs = { 'each', 'done' },
    values = { inputs = { { key = 'list', type = 'list', label = 'List' } },
               outputs = { { key = 'item', type = 'any', label = 'Thing' }, { key = 'index', type = 'number', label = 'Number' } } },
    cost = 2,
    run = function(ctx)
        local list = ctx:input('list') or {}
        local turns = {}
        for i = 1, math.min(#list, C.MAX_LIST) do turns[i] = { item = list[i], index = i } end
        ctx:loop('each', turns, 'done')
        return nil
    end,
})

define({
    type = 'flow.repeat', category = 'flow', kind = 'action', title = 'Repeat',
    desc = 'Runs Each a number of times (100 at most), with the turn\'s number, then Done.',
    outputs = { 'each', 'done' },
    values = { inputs = { { key = 'times', type = 'number', label = 'Times', default = 3 } },
               outputs = { { key = 'index', type = 'number', label = 'Turn' } } },
    cost = 2,
    run = function(ctx)
        local asked = math.floor(math.max(0, ctx:need('times')))
        local n = math.min(asked, C.MAX_TURNS)
        if asked > n then ctx:log('Repeat runs %d times at most', C.MAX_TURNS) end
        local turns = {}
        for i = 1, n do turns[i] = { index = i } end
        ctx:loop('each', turns, 'done')
        return nil
    end,
})

define({
    type = 'flow.stop', category = 'flow', kind = 'action', title = 'Stop',
    desc = 'Ends this pulse here: every branch of it, and anything it is waiting for. It ends as finished, so a payment taken on the way is kept.',
    outputs = {},
    run = function(ctx) ctx:stopPulse() return nil end,
})

define({
    type = 'flow.callOff', category = 'flow', kind = 'action', title = 'Call Off',
    desc = 'Ends this pulse as if what it was for did not happen: any payment it took on the way (a Charge, a Fine) is given back. For "they paid, but the wash could not be done".',
    outputs = {},
    values = { inputs = { { key = 'why', type = 'text', label = 'Why (for the log)', default = 'called off' } } },
    run = function(ctx) ctx:callOff(ctx:input('why')) return nil end,
})

-- ============================================
-- Values and maths (value cards: worked out when something reads them)
-- ============================================

define({
    type = 'math.formula', category = 'maths', kind = 'value', title = 'Formula',
    desc = 'Works out a line of maths: speed * 3.6 > limit + 10. Each name in it becomes an input.',
    props = { { key = 'expr', kind = 'formula', label = 'Formula', default = 'a + b', required = true } },
    pinsFor = function(props)
        local ast, why = SystemFormula.parse(props.expr or 'a + b')
        if not ast then return nil, why end
        local types = SystemFormula.inputTypes(ast)
        local inputs = {}
        for _, name in ipairs(SystemFormula.names(ast)) do
            inputs[#inputs + 1] = { key = name, type = types[name] == 'vector' and 'vector' or 'any', label = name }
        end
        local rt = SystemFormula.resultType(ast)
        return { inputs = inputs, outputs = { { key = 'result', type = rt == 'bool' and 'bool' or rt == 'text' and 'text' or rt == 'number' and 'number' or 'any', label = 'Result' } } }
    end,
    value = function(ctx)
        -- Parsed once per card, not on every read (a long formula is slow to parse).
        local ast, why = ctx:cached('ast', function() return SystemFormula.parse(ctx:prop('expr') or 'a + b') end)
        if not ast then return nil, why end
        local env = {}
        for _, name in ipairs(SystemFormula.names(ast)) do env[name] = ctx:input(name) end
        local v, ewhy = SystemFormula.eval(ast, env)
        if v == nil then return nil, ewhy end
        return { result = v }
    end,
})

local COMPARE = { 'is', 'is not', 'more than', 'less than', 'at least', 'at most' }

define({
    type = 'math.compare', category = 'maths', kind = 'value', title = 'Compare',
    desc = 'Yes or no: is A more than, less than, or the same as B.',
    props = { { key = 'op', kind = 'select', label = 'A ... B', options = COMPARE, default = 'more than' } },
    values = { inputs = { { key = 'a', type = 'number', label = 'A' }, { key = 'b', type = 'number', label = 'B', default = 0 } },
               outputs = { { key = 'result', type = 'bool', label = 'Yes?' } } },
    value = function(ctx)
        local a, b, op = ctx:need('a'), ctx:need('b'), ctx:prop('op')
        local r
        if op == 'is' then r = a == b elseif op == 'is not' then r = a ~= b
        elseif op == 'more than' then r = a > b elseif op == 'less than' then r = a < b
        elseif op == 'at least' then r = a >= b else r = a <= b end
        return { result = r }
    end,
})

define({
    type = 'math.random', category = 'maths', kind = 'value', title = 'Random Number',
    desc = 'A whole number from Min to Max, new each time something reads it.',
    values = { inputs = { { key = 'min', type = 'number', label = 'Min', default = 1 }, { key = 'max', type = 'number', label = 'Max', default = 100 } },
               outputs = { { key = 'result', type = 'number', label = 'Number' } } },
    value = function(ctx)
        local lo, hi = math.floor(ctx:need('min')), math.floor(ctx:need('max'))
        if hi < lo then lo, hi = hi, lo end
        return { result = math.random(lo, hi) }
    end,
})

define({
    type = 'math.clamp', category = 'maths', kind = 'value', title = 'Clamp',
    desc = 'Keeps a number between a low and a high end (anything a player\'s game reports goes through one).',
    values = { inputs = { { key = 'value', type = 'number', label = 'Number' }, { key = 'min', type = 'number', label = 'Low', default = 0 },
                          { key = 'max', type = 'number', label = 'High', default = 100 } },
               outputs = { { key = 'result', type = 'number', label = 'Number' } } },
    value = function(ctx)
        local lo, hi = ctx:need('min'), ctx:need('max')
        if hi < lo then lo, hi = hi, lo end
        return { result = math.max(lo, math.min(hi, ctx:need('value'))) }
    end,
})

define({
    type = 'math.distance', category = 'maths', kind = 'value', title = 'Distance',
    desc = 'How far apart two places are, in metres.',
    values = { inputs = { { key = 'a', type = 'vector', label = 'From' }, { key = 'b', type = 'vector', label = 'To' } },
               outputs = { { key = 'result', type = 'number', label = 'Metres' } } },
    value = function(ctx)
        local a, b = ctx:need('a'), ctx:need('b')
        local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
        return { result = math.sqrt(dx * dx + dy * dy + dz * dz) }
    end,
})

define({
    type = 'math.makePlace', category = 'maths', kind = 'value', title = 'Make Place',
    desc = 'A place from its x, y and z.',
    values = { inputs = { { key = 'x', type = 'number', label = 'X', default = 0 }, { key = 'y', type = 'number', label = 'Y', default = 0 },
                          { key = 'z', type = 'number', label = 'Z', default = 0 } },
               outputs = { { key = 'result', type = 'vector', label = 'Place' } } },
    value = function(ctx) return { result = { x = ctx:need('x'), y = ctx:need('y'), z = ctx:need('z') } } end,
})

define({
    type = 'math.splitPlace', category = 'maths', kind = 'value', title = 'Split Place',
    desc = 'A place\'s x, y and z.',
    values = { inputs = { { key = 'place', type = 'vector', label = 'Place' } },
               outputs = { { key = 'x', type = 'number', label = 'X' }, { key = 'y', type = 'number', label = 'Y' },
                           { key = 'z', type = 'number', label = 'Z' } } },
    value = function(ctx) local p = ctx:need('place') return { x = p.x, y = p.y, z = p.z } end,
})

define({
    type = 'text.join', category = 'text', kind = 'value', title = 'Join Text',
    desc = 'Two pieces of text, one after the other (numbers are written out).',
    values = { inputs = { { key = 'a', type = 'any', label = 'First' }, { key = 'b', type = 'any', label = 'Then', default = '' } },
               outputs = { { key = 'result', type = 'text', label = 'Text' } } },
    value = function(ctx)
        local function s(v)
            if v == nil then return '' end
            if type(v) == 'number' then return (math.floor(v) == v and math.abs(v) < 1e15) and ('%d'):format(v) or ('%.2f'):format(v) end
            if type(v) == 'boolean' then return v and 'yes' or 'no' end
            if type(v) == 'string' then return v end
            return ''
        end
        return { result = (s(ctx:input('a')) .. s(ctx:input('b'))):sub(1, 4000) }
    end,
})

define({
    type = 'text.number', category = 'text', kind = 'value', title = 'Format Number',
    desc = 'A number as text, rounded: 42.5 -> "42.50", with a unit after it if you like ("km/h").',
    values = { inputs = { { key = 'value', type = 'number', label = 'Number' }, { key = 'places', type = 'number', label = 'Decimal places', default = 0 },
                          { key = 'unit', type = 'text', label = 'After it', default = '' } },
               outputs = { { key = 'result', type = 'text', label = 'Text' } } },
    value = function(ctx)
        local places = math.floor(math.max(0, math.min(6, ctx:need('places'))))
        local unit = ctx:input('unit') or ''
        return { result = ('%.' .. places .. 'f'):format(ctx:need('value')) .. (unit ~= '' and (' ' .. unit) or '') }
    end,
})

-- ============================================
-- Variables (kept for everyone, per player, or per car: the variable says)
-- ============================================

local function varPins(dir)
    return function(props, info)
        local v = info.vars and info.vars[props.var]
        if not v then return { inputs = {}, outputs = {} } end
        local pin = { { key = 'value', type = v.type, label = 'Value' } }
        if dir == 'out' then return { inputs = {}, outputs = pin } end
        return { inputs = pin, outputs = {} }
    end
end

define({
    type = 'var.get', category = 'variables', kind = 'value', title = 'Get Variable',
    desc = 'A variable\'s value now.',
    props = { { key = 'var', kind = 'var', label = 'Variable', required = true } },
    pinsFor = varPins('out'),
    value = function(ctx) return { value = ctx:var(ctx:prop('var')) } end,
})

define({
    type = 'var.set', category = 'variables', kind = 'action', title = 'Set Variable',
    desc = 'Gives a variable a new value.',
    props = { { key = 'var', kind = 'var', label = 'Variable', required = true } },
    pinsFor = varPins('in'),
    run = function(ctx)
        ctx:setVar(ctx:prop('var'), ctx:input('value'))
        return 'out'
    end,
})

define({
    type = 'var.add', category = 'variables', kind = 'action', title = 'Add to Variable',
    desc = 'Adds to a number variable (a minus number takes away), and gives the new value.',
    props = { { key = 'var', kind = 'var', label = 'Variable', varType = 'number', required = true } },
    values = { inputs = { { key = 'amount', type = 'number', label = 'Add', default = 1 } },
               outputs = { { key = 'new', type = 'number', label = 'Now' } } },
    run = function(ctx)
        local name = ctx:prop('var')
        local now = (ctx:var(name) or 0) + ctx:need('amount')
        ctx:setVar(name, now)
        ctx:set('new', now)
        return 'out'
    end,
})

-- ============================================
-- Lists (64 at most)
-- ============================================

define({
    type = 'list.add', category = 'lists', kind = 'action', title = 'Add to List',
    desc = 'Puts a thing at the end of a list variable (a full list, 64, refuses it).',
    outputs = { 'out', 'full' },
    props = { { key = 'var', kind = 'var', label = 'List variable', varType = 'list', required = true } },
    values = { inputs = { { key = 'item', type = 'any', label = 'Thing' } } },
    run = function(ctx)
        local name = ctx:prop('var')
        local list = ctx:var(name) or {}
        if #list >= C.MAX_LIST then return 'full' end
        list[#list + 1] = ctx:need('item')
        ctx:setVar(name, list)
        return 'out'
    end,
})

local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    if a.source ~= nil or b.source ~= nil then return a.source == b.source end   -- players
    if a.x ~= nil then return a.x == b.x and a.y == b.y and a.z == b.z end      -- places
    return false
end

define({
    type = 'list.remove', category = 'lists', kind = 'action', title = 'Take from List',
    desc = 'Takes a thing out of a list variable (the first one that is the same), if it is there.',
    outputs = { 'out', 'notThere' },
    labels = { notThere = 'Not there' },
    props = { { key = 'var', kind = 'var', label = 'List variable', varType = 'list', required = true } },
    values = { inputs = { { key = 'item', type = 'any', label = 'Thing' } } },
    run = function(ctx)
        local name = ctx:prop('var')
        local list = ctx:var(name) or {}
        local item = ctx:need('item')
        for i, v in ipairs(list) do
            if same(v, item) then
                table.remove(list, i)
                ctx:setVar(name, list)
                return 'out'
            end
        end
        return 'notThere'
    end,
})

define({
    type = 'list.has', category = 'lists', kind = 'value', title = 'List Has',
    desc = 'Yes or no: is this thing in the list.',
    values = { inputs = { { key = 'list', type = 'list', label = 'List' }, { key = 'item', type = 'any', label = 'Thing' } },
               outputs = { { key = 'result', type = 'bool', label = 'Yes?' } } },
    value = function(ctx)
        local list, item = ctx:input('list') or {}, ctx:need('item')
        for _, v in ipairs(list) do if same(v, item) then return { result = true } end end
        return { result = false }
    end,
})

define({
    type = 'list.count', category = 'lists', kind = 'value', title = 'List Count',
    desc = 'How many things are in a list.',
    values = { inputs = { { key = 'list', type = 'list', label = 'List' } },
               outputs = { { key = 'result', type = 'number', label = 'How many' } } },
    value = function(ctx) return { result = #(ctx:input('list') or {}) } end,
})

define({
    type = 'list.get', category = 'lists', kind = 'value', title = 'List Item',
    desc = 'The thing at a number in a list (1 is the first). Found says if there was one.',
    values = { inputs = { { key = 'list', type = 'list', label = 'List' }, { key = 'index', type = 'number', label = 'Number', default = 1 } },
               outputs = { { key = 'item', type = 'any', label = 'Thing' }, { key = 'found', type = 'bool', label = 'Found' } } },
    value = function(ctx)
        local list = ctx:input('list') or {}
        local i = math.floor(ctx:need('index'))
        local v = list[i]
        return { item = v, found = v ~= nil }
    end,
})

-- ============================================
-- Records (what whip's API cards hand back: a player's sheet, a bank account)
-- ============================================

define({
    type = 'record.field', category = 'values', kind = 'value', title = 'Get Field',
    desc = 'One field of a record (a bank account\'s balance). Found says if it had one.',
    props = { { key = 'field', kind = 'text', label = 'Field', maxLength = 40, required = true } },
    values = { inputs = { { key = 'record', type = 'record', label = 'Record' } },
               outputs = { { key = 'value', type = 'any', label = 'Value' }, { key = 'found', type = 'bool', label = 'Found' } } },
    value = function(ctx)
        local rec = ctx:input('record')
        local v = type(rec) == 'table' and rec[ctx:prop('field')] or nil
        return { value = v, found = v ~= nil }
    end,
})

-- ============================================
-- The log (Test mode's, and the hub's)
-- ============================================

define({
    type = 'debug.log', category = 'flow', kind = 'action', title = 'Write to Log',
    desc = 'Writes a line to the system\'s log (Test mode shows it).',
    values = { inputs = { { key = 'text', type = 'any', label = 'Text' } } },
    run = function(ctx)
        local v = ctx:input('text')
        ctx:log('%s', type(v) == 'table' and '(a table)' or tostring(v))
        return 'out'
    end,
})
