-- Fire Weapon: a Fixed Weapon (a World-tab prop whose def.weapon names a gun, shared/weapon_catalog.lua) fires.
-- Only one game fires, so there is one shot, not one per player: the player who set the card off when near it,
-- else the run player nearest it (within FIRE_RANGE). The shot is real, in a Test too. That game reports back
-- through spur_core:server:directorFired.

local CORE = GetCurrentResourceName()

local define = DirectorKit.define

local FIRE_RANGE = 150.0   -- a game further than this from the gun may not have it made
local AT = { 'where it points', 'a placed thing' }
local fires = {}           -- [token] = { src, done, ok, why }
local serial = 0

local function worldOf(doc, id)
    for _, w in ipairs(type(doc) == 'table' and type(doc.world) == 'table' and doc.world or {}) do
        if type(w) == 'table' and w.id == id then return w end
    end
    return nil
end

--- Check: the placed thing is a Fixed Weapon (a prop with a gun).
local function isWeapon(v, doc)
    local w = worldOf(doc, v)
    if not w then return nil end
    if w.kind ~= 'prop' or type(w.def) ~= 'table' or not WeaponCatalog.modelOf(w.def.weapon) then
        return ('"%s" is not a Fixed Weapon (place one from the world builder\'s More, Weapons)'):format(tostring(w.label or w.id))
    end
    return nil
end

local vec = DirectorKit.vec3

--- Where a placed thing is now, and its network id (nodes.lua).
local whereNow = DirectorNodes.whereNow

--- The run player who fires it: the one who set the card off when near it, else the nearest within FIRE_RANGE.
local function shooterFor(ctx, at)
    local function near(s)
        local ped = GetPlayerPed(s)
        if not ped or ped == 0 then return nil end
        return #(GetEntityCoords(ped) - at)
    end
    local first = Director.playerOf(ctx)
    local d = first and near(first)
    if d and d <= FIRE_RANGE then return first end
    local best, bestD
    for _, s in ipairs(ctx:players()) do
        local ds = near(s)
        if ds and ds <= FIRE_RANGE and (not bestD or ds < bestD) then best, bestD = s, ds end
    end
    return best
end

define({
    type = 'weapon.fire', v = 1, category = 'world', title = 'Fire Weapon',
    desc = 'A Fixed Weapon fires where it points, or at a placed thing. The shots are real, in a Test too.',
    outputs = { 'fired', 'failed', 'timeout' },
    labels = { fired = 'Fired', failed = 'Could not', timeout = 'No answer' },
    latent = true, yields = true,
    props = {
        -- `weaponsOnly`: the picker lists only Fixed Weapons.
        { key = 'weapon', kind = 'world', worldKind = 'prop', weaponsOnly = true, label = 'Fixed Weapon', required = true, check = isWeapon },
        { key = 'shots', kind = 'number', label = 'Shots', default = 1, min = 1, max = 20 },
        { key = 'gap', kind = 'number', label = 'Between shots (seconds)', default = 0.5, min = 0.05, max = 5 },
        { key = 'at', kind = 'select', label = 'At', options = AT, default = AT[1] },
        { key = 'thing', kind = 'world', label = 'The placed thing (for "a placed thing")' },
    },
    check = function(props)
        if props.at == AT[2] and (type(props.thing) ~= 'string' or props.thing == '') then
            return 'Pick the placed thing it fires at'
        end
        return nil
    end,
    run = function(ctx)
        local run = ctx.run
        local wid = ctx.node.props.weapon
        local w = ctx:place(wid)
        local gun = type(w) == 'table' and type(w.def) == 'table' and WeaponCatalog.modelOf(w.def.weapon) and w.def.weapon:upper() or nil
        if not gun then
            ctx:log('%s is not a Fixed Weapon', tostring(wid))
            return 'failed'
        end
        -- Its prop set and slot: from Show Prop, or the scenario's standing one.
        local setId, index = DirectorTasks.propSlot(run, wid)
        if not setId then
            local h = Director.handleOf(run, wid)
            if type(h) == 'table' and h.propSet then setId, index = h.propSet, 1 end
        end
        local wire = setId and PropSets.wireOf(CORE, setId) or nil
        if not wire then
            ctx:log('%s is not shown (Show Prop first)', tostring(wid))
            return 'failed'
        end
        local attachTo = type(w.def.attach) == 'table' and w.def.attach.to or nil
        local at = (type(attachTo) == 'string' and whereNow(ctx, attachTo)) or vec(w.def.coords)
        if not at then return 'failed' end
        local src = shooterFor(ctx, at)
        if not src then
            ctx:log('nobody of the run is within %d m of %s to fire it', FIRE_RANGE, tostring(wid))
            return 'failed'
        end
        local target
        if ctx:prop('at') == AT[2] then
            local tid = ctx.node.props.thing
            local pos, net = whereNow(ctx, tid)
            if not pos then
                ctx:log('%s is not in the world to fire at', tostring(tid))
                return 'failed'
            end
            target = net and { net = net } or { x = pos.x, y = pos.y, z = pos.z }
        end
        local shots = math.max(1, math.min(20, math.floor(tonumber(ctx:prop('shots')) or 1)))
        local gapMs = math.floor(math.max(0.05, math.min(5, tonumber(ctx:prop('gap')) or 0.5)) * 1000)
        serial = serial + 1
        local token = ('%d:%d'):format(run.id, serial)
        -- The game's answer (directorFired) continues the card; "No answer" fires if it never comes.
        fires[token] = { src = src, hold = ctx:hold(), ctx = ctx, wid = wid }
        ctx:onEnd(function() fires[token] = nil end)
        -- Every game turns its copy of the gun; only the one firing fires.
        if target then TriggerClientEvent('spur_core:client:directorAim', -1, { wire = wire, i = index, at = target }) end
        TriggerClientEvent('spur_core:client:directorFire', src, { token = token, wire = wire, i = index, weapon = gun,
                                                                  shots = shots, gapMs = gapMs, at = target })
        Director.event(run, ctx.node.id, 'fired', src, ('%s x%d'):format(gun, shots))
        ctx:after(shots * gapMs + 10000, 'timeout')
        return nil
    end,
})

--- The firing game reports how it went (accepted only from the game given the shot).
SecureEvent('spur_core:server:directorFired', {
    whileDead = true, rateLimit = 100, burst = 10,
    params = { { 'token', 'string', 32 }, { 'ok', 'bool' }, { 'why', 'string', 120, '' } },
}, function(source, _, token, ok, why)
    local f = fires[token]
    if not f or f.src ~= source then return end
    fires[token] = nil
    if ok ~= true then f.ctx:log('%s could not fire: %s', tostring(f.wid), tostring(why)) end
    DirectorRuntime.answer(f.hold, ok == true and 'fired' or 'failed')
end)
