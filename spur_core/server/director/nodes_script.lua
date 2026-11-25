-- Send Signal and Wait for Script Event: cards for working with other resources.
-- Send Signal fires spur_core:run:signalled { run, name, data, source }; Wait for Script Event waits for
-- exports.spur_core:SendDirectorEvent. A Test sends and hears no real script events: /director send injects one.

local define = DirectorKit.define

local EVENT_NAME = '^[%a][%w_]*%.[%a][%w_.]*$'

define({
    type = 'script.signal', v = 1, category = 'scenario', title = 'Send Signal',
    desc = 'Tells other resources something happened in this scenario: a police script hears "alarm".',
    outputs = { 'out' },
    props = {
        { key = 'name', kind = 'text', label = 'Signal', required = true, maxLength = 40,
          check = function(v)
              if type(v) ~= 'string' or not v:match('^[%w_%-%.]+$') then return 'A signal is one word (letters, digits, _ - and .): alarm' end
          end },
        { key = 'value', kind = 'text', label = 'With (optional)', maxLength = 120 },
        { key = 'var', kind = 'var', label = 'Or a variable\'s value' },
    },
    run = function(ctx)
        local run = ctx.run
        local name = ctx:prop('name')
        local value = ctx:prop('value')
        local varName = ctx.node.props.var
        if type(varName) == 'string' and varName ~= '' then value = ctx:var(varName) end
        local src = Director.playerOf(ctx)
        Director.announce('run:signalled', { run = Director.view(run), name = name, data = { value = value }, source = src }, run.test)
        Director.event(run, ctx.node.id, 'signal', src, name)
        return 'out'
    end,
})

local WHO = { 'About a player in this run', 'Sent for this run', 'Any run waiting for it' }

define({
    type = 'script.wait', v = 1, category = 'flow', title = 'Wait for Script Event',
    desc = 'Carries on when another resource sends this event (SendDirectorEvent): police.backupArrived.',
    outputs = { 'heard', 'timeout' },
    labels = { heard = 'Heard it', timeout = 'Not in time' },
    latent = true,
    props = {
        { key = 'event', kind = 'text', label = 'Event', required = true, maxLength = 64,
          check = function(v)
              if type(v) ~= 'string' or not v:match(EVENT_NAME) then
                  return 'An event is the script\'s name for it, two words with a dot: police.backupArrived'
              end
          end },
        { key = 'who', kind = 'select', label = 'Only one', options = WHO, default = WHO[1],
          optionLabels = { [WHO[1]] = 'About a player in this scenario', [WHO[2]] = 'Sent for this scenario',
                           [WHO[3]] = 'Any scenario waiting for it' } },
        { key = 'seconds', kind = 'duration', label = 'Give up after (0: never)', default = 0, min = 0, max = 86400 },
    },
    -- With no time limit "Not in time" never fires.
    pinWhen = { timeout = { key = 'seconds', above = 0 } },
    run = function(ctx)
        local run = ctx.run
        local name, who = ctx:prop('event'), ctx:prop('who')
        ctx:on('script.event', function(p)
            if type(p) ~= 'table' or p.event ~= name then return nil end
            if (p.test == true) ~= (run.test == true) then return nil end   -- a Test hears only /director send
            local player = p.source ~= nil and ctx:isPlayer(p.source) and p.source or nil
            if who == WHO[1] and not player then return nil end
            if who == WHO[2] and p.runId ~= run.id then return nil end
            -- An event naming no player carries on for whoever the branch was for (`from`, read by Director.playerOf).
            local was = ctx.trigger
            local wasFor = type(was) == 'table' and (was.source or (type(was.from) == 'table' and was.from.source)) or nil
            return 'heard', { source = player, from = not player and wasFor and { source = wasFor } or nil,
                              event = p.event, sender = p.sender, data = p.data }
        end)
        local s = tonumber(ctx:prop('seconds')) or 0
        if s > 0 then ctx:after(s * 1000.0, 'timeout') end
        return nil
    end,
})
