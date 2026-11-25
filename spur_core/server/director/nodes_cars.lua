-- Car cards: Claim Car, Give Car, Put in Car, Change Plate.
-- The run's car (Spawn Car) goes when the run ends; Claim Car makes it the player's own (server/vehicle_claim.lua).
-- In a Test, Claim Car and Give Car only say what they would have done.

local define = DirectorKit.define
local vec = DirectorKit.place

--- The car this run made for a placed thing, while whip still has it (its vehicleId).
local runCar = DirectorNodes.runCarId

--- Check: a plate field that cannot be a plate.
local function plateCheck(v)
    if v == nil or v == '' then return nil end
    return DirectorFields.plateProblem(v)
end

--- Check: a car model whip's vehicle catalog has never seen (a typo). Only when the catalog knows any.
local function modelCheck(v)
    if type(v) ~= 'string' or v == '' then return 'which car (a model name)' end
    if DirectorFields.isCarModel(v) == false then
        return ('"%s" is not a car in the vehicle catalog: check the spelling'):format(v)
    end
    return nil
end

local KEEP = { 'where it is', 'in their garage' }

--- Check, a warning: a plate typed on a card that makes an owned car is one car for good, so a second
--- run's car gets refused.
local function fixedPlate(props)
    local p = props.plate
    if type(p) == 'string' and p ~= '' then
        return ('the plate %s is one car for good: once a player keeps the scenario\'s car, the next time it is refused (leave Plate empty for a new one each time)')
            :format(p), 'warning'
    end
    return nil
end

define({
    type = 'vehicle.claim', v = 1, category = 'world', title = 'Claim Car',
    desc = 'Makes the scenario\'s car the player\'s own, saved like any other: a new plate (or the one given), what is in it kept.',
    outputs = { 'claimed', 'failed', 'timeout' },
    labels = { claimed = 'Theirs' },
    latent = true, yields = true,
    check = fixedPlate,
    props = {
        { key = 'car', kind = 'world', worldKind = 'vehicle', label = 'Car', required = true },
        { key = 'plate', kind = 'text', label = 'Plate (empty: a new one)', maxLength = 8, check = plateCheck },
        { key = 'keep', kind = 'select', label = 'Leave it', options = KEEP, default = KEEP[1] },
        { key = 'key', kind = 'bool', label = 'Give the player its key', default = true },
    },
    run = function(ctx)
        local run, carW = ctx.run, ctx.node.props.car
        local id = runCar(ctx, carW)
        local src = Director.playerOf(ctx)
        if not id or not src then
            ctx:log('%s: no car of this run to claim (Spawn Car first)', tostring(carW))
            return 'failed'
        end
        local data = { source = src }
        if run.test then
            NotifyPlayer(src, 'Test: this car would be yours now', 'info')
            Director.event(run, ctx.node.id, 'claimed (test)', src)
            return 'claimed', data
        end
        local plate = ctx:prop('plate')
        ctx:call(function()
            local newId, why = Vehicles.claim(id, src, { plate = plate ~= '' and plate or nil, here = ctx:prop('keep') ~= KEEP[2],
                                                         key = ctx:prop('key') ~= false, reason = Director.reason(run),
                -- Items the run put in the car stay with the run's car.
                leave = function(md) return type(md) == 'table' and md.director == run.id end })
            if not newId then
                ctx:log('claiming the car failed: %s', tostring(why))
                return 'failed', data
            end
            if why then NotifyPlayer(src, 'Your new car: ' .. why, 'warning') end
            -- Later cards still find it, and the run's end leaves it alone.
            ctx:remember(carW, { vehicleId = newId, claimed = true })
            local def = Vehicles.getDef(newId)
            Director.event(run, ctx.node.id, 'claimed', src, def and def.plate or tostring(newId))
            return 'claimed', data
        end)
        ctx:after(20000, 'timeout')
        return nil
    end,
})

local WHERE = { 'their garage', 'at a placed thing' }

define({
    type = 'vehicle.give', v = 1, category = 'player', title = 'Give Car', handsOut = true,
    desc = 'Gives the player a new car of their own: in their garage, or standing at a placed thing.',
    outputs = { 'given', 'failed', 'timeout' },
    latent = true, yields = true,
    check = fixedPlate,
    props = {
        { key = 'model', kind = 'text', label = 'Car model', required = true, maxLength = 60, check = modelCheck },
        { key = 'plate', kind = 'text', label = 'Plate (empty: a new one)', maxLength = 8, check = plateCheck },
        { key = 'where', kind = 'select', label = 'Where', options = WHERE, default = WHERE[1] },
        { key = 'at', kind = 'world', label = 'At (a placed thing)' },
        { key = 'key', kind = 'bool', label = 'Give the player its key', default = true },
    },
    run = function(ctx)
        local run = ctx.run
        local src = Director.playerOf(ctx)
        if not src then return 'failed' end
        local model = ctx:prop('model')
        local data = { source = src }
        if run.test then
            NotifyPlayer(src, ('Test: this would give you a %s'):format(tostring(model)), 'info')
            Director.event(run, ctx.node.id, 'gave a car (test)', src, model)
            return 'given', data
        end
        local spawnAt
        if ctx:prop('where') == WHERE[2] then
            local w = ctx:place(ctx.node.props.at)
            spawnAt = vec(type(w) == 'table' and type(w.def) == 'table' and w.def.coords or nil)
            if not spawnAt then
                ctx:log('Give Car: "at" has no spot')
                return 'failed', data
            end
        end
        local plate = ctx:prop('plate')
        local madeId = nil
        ctx:call(function()
            local id, why = Vehicles.createOwned(src, { model = model, plate = plate ~= '' and plate or nil },
                { spawnAt = spawnAt, giveKey = ctx:prop('key') ~= false })
            if not id then
                ctx:log('giving a %s failed: %s', tostring(model), tostring(why))
                return 'failed', data
            end
            madeId = id
            local def = Vehicles.getDef(id)
            Director.event(run, ctx.node.id, 'gave a car', src, ('%s %s'):format(tostring(model), def and def.plate or ''))
            return 'given', data
        end, {
            -- The car was made after the card timed out (slow database): it is still theirs, and logged.
            late = function()
                if not madeId then return end
                local def = Vehicles.getDef(madeId)
                print(('[spur_core:director] run %s: Give Car made a %s (%s) for %s after the card had given up: kept')
                    :format(tostring(run.id), tostring(model), def and def.plate or '?', tostring(src)))
                Director.event(run, ctx.node.id, 'gave a car (late)', src, ('%s %s'):format(tostring(model), def and def.plate or ''))
            end,
        })
        ctx:after(20000, 'timeout')
        return nil
    end,
})

local INTO = { 'trunk', 'glovebox' }

define({
    type = 'vehicle.putIn', v = 1, category = 'world', title = 'Put in Car', givesItems = true, giveUp = 15,
    desc = 'Puts an item in the scenario\'s car: its trunk or its glovebox (the package waiting in the getaway car).',
    outputs = { 'placed', 'failed', 'timeout' },
    latent = true, yields = true,
    props = {
        { key = 'car', kind = 'world', worldKind = 'vehicle', label = 'Car', required = true },
        { key = 'item', kind = 'item', label = 'Item', required = true },
        { key = 'amount', kind = 'number', label = 'How many', default = 1, min = 1, max = 100 },
        { key = 'into', kind = 'select', label = 'Into', options = INTO, default = INTO[1] },
    },
    run = function(ctx)
        local run, carW = ctx.run, ctx.node.props.car
        local id = runCar(ctx, carW)
        if not id then
            ctx:log('%s: no car of this run (Spawn Car first)', tostring(carW))
            return 'failed'
        end
        local item = ctx:prop('item')
        if not (type(Config) == 'table' and Config.Items and Config.Items[item]) then
            ctx:log('%s is not an item on this server', tostring(item))
            return 'failed'
        end
        local amount = math.max(1, math.min(100, math.floor(tonumber(ctx:prop('amount')) or 1)))
        local into = ctx:prop('into') or 'trunk'
        ctx:call(function()
            if not Vehicles.loadInventory(id) then
                ctx:log('the car\'s %s could not be read', into)
                return 'failed'
            end
            -- (The run's way: real in a live run, stamped and taken back from whoever carries it in a test: effects.lua.)
            local stamp = DirectorEffects.stamper(run, item, { dworld = carW })
            local ok, why = Stores.giveAt({ kind = 'vehicle', id = id, sub = into }, item, amount, stamp(nil),
                { reason = Director.reason(run) })
            if not ok then
                ctx:log('could not put %s in the %s: %s', item, into, tostring(why))
                return 'failed'
            end
            Director.event(run, ctx.node.id, 'put in the ' .. into, nil, ('%s x%d'):format(item, amount))
            return 'placed'
        end)        return nil
    end,
})

define({
    type = 'vehicle.plate', v = 1, category = 'world', title = 'Change Plate', giveUp = 15,
    desc = 'Puts another plate on the scenario\'s car (a scratched VIN, false plates).',
    outputs = { 'out', 'failed', 'timeout' },
    -- Waits: once claimed (Claim Car), the car is saved, and its plate with it.
    latent = true, yields = true,
    props = {
        { key = 'car', kind = 'world', worldKind = 'vehicle', label = 'Car', required = true },
        { key = 'plate', kind = 'text', label = 'New plate', required = true, maxLength = 8, check = plateCheck },
    },
    run = function(ctx)
        local id = runCar(ctx, ctx.node.props.car)
        if not id then return 'failed' end
        local plate = ctx:prop('plate')
        ctx:call(function()
            local ok, why = Vehicles.setPlate(id, plate)
            if not ok then
                ctx:log('the plate could not be changed: %s', tostring(why))
                return 'failed'
            end
            return 'out'
        end)        return nil
    end,
})
