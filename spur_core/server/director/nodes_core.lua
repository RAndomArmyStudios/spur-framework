-- The core cards every scenario needs: flow, variables, ending a run. Titles are plain English for non-coders.

local define = DirectorKit.define

local function asNumber(v)
    if type(v) == 'number' then return v end
    if type(v) == 'string' then return tonumber(v) end
    return nil
end

--- The value a text field holds, as a number when the variable it is compared with is one.
local function coerce(text, like)
    if type(text) == type(like) then return text end   -- read through a variable: already its type
    if type(like) == 'number' then return asNumber(text) end
    if type(like) == 'boolean' then
        if text == 'true' or text == 'yes' then return true end
        if text == 'false' or text == 'no' then return false end
        return nil
    end
    return text
end

-- Start and end

-- Scenario Enabled: every run begins here. With a Scenario Started By Player card after it, what comes before that
-- card is a lead-in that never counts (runtime.lua run.pre) and the job starts there; without one it starts here.
define({
    type = 'scenario.started', v = 1, category = 'events', title = 'Scenario Enabled',
    desc = 'Triggers when the conditions for a scenario to start have been met. Cards activated after Scenario Enabled, but before '
        .. 'Scenario Started By Player, do not trigger failures or cooldowns, therefore it is recommended to only use cards '
        .. 'between Scenario Enabled and Scenario Started By Player as pre-scenario conditions, such as preparing to start a '
        .. 'job, creating an environment, staging an event, etc. Use the card "Scenario Started By Player" to safely spawn '
        .. 'items, activate failures and cooldowns.',
    outputs = { 'out' },
    event = { name = 'scenario.started', once = true },   -- a run starts once: its listener goes after
})

--- The job starts here: the run can now fail, counts in its history, and starts its players' cooldown at the end.
--- Not now: Runs at once is full, a player is cooling down, or nobody has joined yet.
define({
    type = 'scenario.begin', v = 1, category = 'scenario', title = 'Scenario Started By Player',
    desc = 'The job starts here: before it nothing fails or counts. Not now: the job is already going, or someone is cooling down.',
    outputs = { 'started', 'notnow' },
    labels = { started = 'Started', notnow = 'Not now' },
    bad = { 'notnow' },
    run = function(ctx)
        if not ctx.run.pre then return 'started' end
        if next(ctx.run.players) == nil then
            ctx:log('not now: no player has joined yet (a Dialog Line, Wait for Press, Player Arrives or Interaction Menu before it lets the first one join)')
            return 'notnow'
        end
        local why = Director.beginRun(ctx.run)
        if why then
            ctx:log('not now: %s', why)
            return 'notnow'
        end
        return 'started'
    end,
})

define({
    type = 'scenario.succeed', v = 1, category = 'scenario', title = 'Succeed',
    desc = 'Ends the scenario: it went well.',
    props = { { key = 'reason', kind = 'text', label = 'Reason', maxLength = 120 } },
    run = function(ctx)
        ctx:finish('success', ctx:prop('reason'))
        return nil
    end,
})

define({
    type = 'scenario.fail', v = 1, category = 'scenario', title = 'Fail',
    desc = 'Ends the scenario: it did not go well.',
    props = { { key = 'reason', kind = 'text', label = 'Reason', maxLength = 120 } },
    run = function(ctx)
        ctx:finish('failure', ctx:prop('reason'))
        return nil
    end,
})

--- "No, thanks": a run that never really began. Not a failure in the scenario's numbers, and nobody is
--- told it was called off.
define({
    type = 'scenario.calloff', v = 1, category = 'scenario', title = 'Call Off',
    desc = 'Ends the scenario with no result: not a success, not a failure (the player said no).',
    props = { { key = 'reason', kind = 'text', label = 'Reason', maxLength = 120 } },
    run = function(ctx)
        ctx:finish('calloff', ctx:prop('reason'))
        return nil
    end,
})

-- Flow

local OPS = { 'is', 'is not', 'more than', 'less than', 'at least', 'at most', 'is set', 'is empty' }
DirectorNodes.VAR_OPS = OPS

--- Does a variable's value pass one of If's tests (OPS)? `value` as typed on the card. If and Fail If a Variable
--- (nodes_conditions.lua) ask the same.
---@return boolean
function DirectorNodes.varMatches(have, op, value)
    if op == 'is set' then return have ~= nil end
    if op == 'is empty' then return have == nil end
    local want = coerce(value, have)
    if op == 'is' then return have == want end
    if op == 'is not' then return have ~= want end
    local a, b = asNumber(have), asNumber(want)
    if a == nil or b == nil then return false end
    if op == 'more than' then return a > b end
    if op == 'less than' then return a < b end
    if op == 'at least' then return a >= b end
    return a <= b
end

define({
    type = 'flow.if', v = 1, category = 'flow', title = 'If',
    desc = 'Goes one way or the other, by what a variable holds.',
    outputs = { 'yes', 'no' },
    branch = true,
    props = {
        { key = 'var', kind = 'var', label = 'Variable', required = true },
        { key = 'op', kind = 'select', label = 'Is', options = OPS, default = 'is' },
        { key = 'value', kind = 'text', label = 'Value', maxLength = 100 },
    },
    run = function(ctx)
        return DirectorNodes.varMatches(ctx:var(ctx.node.props.var), ctx:prop('op'), ctx:prop('value')) and 'yes' or 'no'
    end,
})

define({
    type = 'flow.sequence', v = 1, category = 'flow', title = 'Do in Order',
    desc = 'Starts everything wired to it at the same moment, top one first. It does not wait for one to finish before the next.',
    outputs = { 'then1', 'then2', 'then3', 'then4' },
    labels = { then1 = 'Then 1', then2 = 'Then 2', then3 = 'Then 3', then4 = 'Then 4' },
    -- All outputs fire at once: the run stops here only if every branch stops.
    together = true,
    run = function() return { 'then1', 'then2', 'then3', 'then4' } end,
})

-- A dot on a wire that only bends it; the pulse goes straight through.
define({
    type = 'flow.reroute', v = 1, category = 'flow', title = 'Reroute',
    desc = 'A dot to bend a wire round other cards: whatever comes in goes straight out.',
    outputs = { 'out' },
    -- A dot that leads nowhere is reported by Check like the outcome it came from.
    branch = true,
    pinName = function() return 'this Reroute dot' end,
    run = function() return 'out' end,
})

define({
    type = 'flow.once', v = 1, category = 'flow', title = 'First Time Only',
    desc = 'Goes on the first time the scenario reaches it. Every time after, it stops there.',
    outputs = { 'out' },
    run = function(ctx)
        local s = ctx:state()
        if s.done then return nil end
        s.done = true
        return 'out'
    end,
})

define({
    type = 'flow.wait', v = 1, category = 'flow', title = 'Wait',
    desc = 'Waits, then carries on.',
    outputs = { 'done' },
    props = { { key = 'seconds', kind = 'duration', label = 'Seconds', default = 5, min = 0, max = 86400 } },
    latent = true,
    run = function(ctx)
        local s = tonumber(ctx:prop('seconds')) or 0
        if s ~= s then s = 0 end
        s = math.min(math.max(s, 0), 86400)
        ctx:after(s * 1000.0, 'done')
        return nil
    end,
})

--- Goes on once every wired input has been reached (any order), then resets.
--- Latent for Check (it holds pulses); it registers no waits, so the runtime ends its activation at once.
define({
    type = 'flow.waitAll', v = 1, category = 'flow', title = 'Wait for All',
    desc = 'Goes on once every input with a wire into it has been reached, in any order: the safe is open AND the guards are down.',
    inputs = { 'a', 'b', 'c', 'd' },
    labels = { a = 'A', b = 'B', c = 'C', d = 'D' },
    outputs = { 'done' },
    latent = true,
    -- Each input is kept with the step it came at, so a rewound test forgets later ones.
    rewind = function(s, seq)
        for p, at in pairs(s.seen or {}) do
            if at > seq then s.seen[p] = nil end
        end
    end,
    run = function(ctx)
        local s = ctx:state()
        s.seen = s.seen or {}
        s.seen[ctx.pin] = ctx.seq or 0
        for _, p in ipairs({ 'a', 'b', 'c', 'd' }) do
            if ctx:wired(p) and not s.seen[p] then return nil end
        end
        s.seen = {}
        return 'done'
    end,
})

-- Variables

define({
    type = 'var.set', v = 1, category = 'scenario', title = 'Set Variable',
    desc = 'Puts a value in a variable.',
    outputs = { 'out' },
    props = {
        { key = 'var', kind = 'var', label = 'Variable', required = true },
        { key = 'value', kind = 'text', label = 'Value', maxLength = 100 },
    },
    run = function(ctx)
        local name = ctx.node.props.var
        local decl = ctx.run.graph.vars[name]
        local raw = ctx:prop('value')
        local v = raw
        if decl and decl.type == 'number' then v = asNumber(raw) or 0
        elseif decl and decl.type == 'bool' then v = (raw == true or raw == 'true' or raw == 'yes') end
        ctx:setVar(name, v)
        return 'out'
    end,
})

define({
    type = 'var.add', v = 1, category = 'scenario', title = 'Add to Variable',
    desc = 'Adds to a number variable (a minus number takes away).',
    outputs = { 'out' },
    props = {
        { key = 'var', kind = 'var', label = 'Variable', required = true },
        { key = 'amount', kind = 'number', label = 'Add', default = 1 },
    },
    run = function(ctx)
        local name = ctx.node.props.var
        ctx:setVar(name, (asNumber(ctx:var(name)) or 0) + (tonumber(ctx:prop('amount')) or 0))
        return 'out'
    end,
})
