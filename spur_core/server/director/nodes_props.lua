-- ============================================
-- Director — props: Show Prop and Hide Prop
-- ============================================
--
-- A PROP is a placed thing of the World tab: a model where it was put and turned as it was turned,
-- made by every player's own game (a prop set: server/prop_sets.lua), never networked. A STANDING
-- prop is there whenever the scenario is on (dressing: crates in the warehouse). A RUN prop is made by
-- Show Prop when the run gets there (the drill appearing on the vault door), and goes with the run.
-- A prop's GROUP (World tab) lets one Show Prop bring a whole scene in: "and its group too".
--
-- PHYSICS (its page's switch, on unless switched to static): a prop that falls, rolls and is knocked about, a run's or
-- a standing one (main.lua makeStanding), is one networked object instead (PHYSICS, below), moved by one player's game.

local CORE = GetCurrentResourceName()

local define = DirectorKit.define

--- The prop set id a run's props are shown under: the run's own, so its end takes it.
local function setId(ctx, worldId) return ctx:tag() .. ':prop:' .. worldId end

-- ============================================
-- PHYSICS
-- ============================================
--
-- One object the server makes (networked): FiveM gives it to one player's game, the nearest, which moves it, and the
-- others follow what that game says. Background physics, so nothing more is sent for it than FiveM sends. It is held
-- still until a ped or a car in its world is within PHYS_NEAR (with nothing there, the ground under it may not be
-- loaded on the game moving it, and it would fall through), and held again once none is, where it got to. A run's goes with its run (its tag),
-- with Hide Prop or Remove, or when a test goes back to before it was shown; a standing one with its scenario's
-- standing layer (switched off, a test over), and is back where it was placed when that is made again.
--
-- Static whatever the switch says (physicsOff): one with tasks (its timeline moves it), a Fixed Weapon, one attached to
-- something, one inside an interior (each game files its own copy in its room: prop_sets), one that is not solid.

local PHYS_NEAR = 100.0
local PHYS_CHECK_MS = 1000

local physLive = {}   -- [key] = { ent, bucket, frozen } while it is up

local function dropPhys(rec)
    if not rec then return end
    rec.dropped = true
    -- RedM (spur_core, 23 Nov 2026): one still on its way (makePhysical) is deleted when it comes.
    if rec.arriving then RdrEntity.litter(rec.ent) return end
    if rec.ent and DoesEntityExist(rec.ent) then DeleteEntity(rec.ent) end
end

local physReg = Registry.new('directorPhysicsProp', {
    label = 'physics prop',
    scoped = true,
    same = false,
    releaseOrder = 30,   -- with the props
    onAdd = function(key, rec, _, old)
        if old and old ~= rec then dropPhys(old) end
        physLive[key] = rec
    end,
    onRemove = function(key, rec)
        physLive[key] = nil
        dropPhys(rec)
    end,
})

--- Why this prop of a run stays where it is placed, its Physics switch aside or because of it (nil: it moves). On
--- DirectorNodes, which loads before this file (Director is main.lua's, after it).
---@param w table    the placed thing
---@param piece table  Director.propPiece's
---@return string|nil
function DirectorNodes.physicsOff(w, piece)
    local d = type(w) == 'table' and type(w.def) == 'table' and w.def or {}
    if d.physics == false then return 'switched to static' end
    if piece.weapon then return 'a Fixed Weapon' end
    if piece.attachTo then return 'attached to something' end
    if piece.interior then return 'inside an interior' end
    if not piece.collision then return 'not solid' end
    if DirectorTasks.has(w) then return 'its tasks move it' end
    return nil
end

-- Once a second while any is up: still, or free to move, by whether anything in its world that moves is near. What
-- can knock one about is every ped (the players' too) and car the server has, in its world: not only a player (a take's
-- car, an NPC or traffic, with no player near, must still bump it). The props up mark the PHYS_NEAR cells round them
-- (their own and the eight about it); a ped or car is looked at closer (its world, how far) only when it stands in one
-- of those, and nothing is kept of the rest. Nothing up: the pass is nothing.
local function cellOf(at) return math.floor(at.x / PHYS_NEAR) * 65536 + math.floor(at.y / PHYS_NEAR) end
Every('director physics props', PHYS_CHECK_MS, function()
    if not next(physLive) then return nil end
    local round = {}   -- [cell] = { rec, ... }: the props whose nine cells take it in
    local any = false
    for _, rec in pairs(physLive) do
        rec.near = nil
        if DoesEntityExist(rec.ent) then
            local at = GetEntityCoords(rec.ent)
            rec.at, rec.near, any = at, false, true
            local c = cellOf(at)
            for dx = -1, 1 do
                for dy = -1, 1 do
                    local k = c + dx * 65536 + dy
                    local list = round[k]
                    if not list then list = {}; round[k] = list end
                    list[#list + 1] = rec
                end
            end
        end
    end
    if not any then return nil end
    for _, list in ipairs({ GetAllPeds(), GetAllVehicles() }) do
        for _, e in ipairs(list) do
            local at = GetEntityCoords(e)
            local recs = round[cellOf(at)]
            if recs then
                local bucket = GetEntityRoutingBucket(e)
                for _, rec in ipairs(recs) do
                    if not rec.near and rec.bucket == bucket and #(at - rec.at) < PHYS_NEAR then rec.near = true end
                end
            end
        end
    end
    for _, rec in pairs(physLive) do
        if rec.near ~= nil and rec.near == rec.frozen then
            rec.frozen = not rec.near
            FreezeEntityPosition(rec.ent, rec.frozen)
        end
    end
    return nil
end)

--- Make a prop as its physics object, under `tag` (a run's, or a scenario's standing layer's: main.lua makeStanding)
--- in routing bucket `bucket` (nil: the shared world). `id`: what it is kept as, the same again replacing it. Answers
--- its handle ({ physProp = id, netId }), or nil and why.
function DirectorNodes.makePhysical(tag, bucket, id, piece)
    local c, r = piece.coords, piece.rot
    local ent = CreateObjectNoOffset(GetHashKey(piece.model), c.x + 0.0, c.y + 0.0, c.z + 0.0, true, true, false)
    if not ent or ent == 0 then return nil, 'its object could not be made' end
    bucket = bucket or 0
    -- RedM (spur_core, 23 Nov 2026): a player's game makes the object, a moment after this (server/rdr_entities.lua),
    -- and nothing can be done to it before. Its handle is answered now and gets its netId when the object comes;
    -- until then the watcher above leaves it be (it is not there to look at).
    local rec = { ent = ent, bucket = bucket, frozen = true, arriving = true }
    local ok, why = physReg:add(CORE, id, rec, { tag = tag })
    if not ok then
        RdrEntity.litter(ent)
        return nil, why
    end
    local handle = { physProp = id }
    local function arrived()
        rec.arriving = nil
        if rec.dropped then DeleteEntity(ent) return end
        SetEntityRoutingBucket(ent, bucket)   -- an isolated tester's own world
        SetEntityOrphanMode(ent, 2)           -- KeepEntity: its tag decides when it goes
        SetEntityRotation(ent, r.x + 0.0, r.y + 0.0, r.z + 0.0, 2, false)
        FreezeEntityPosition(ent, true)       -- (until something is near: the watcher above, from its next pass)
        handle.netId = NetworkGetNetworkIdFromEntity(ent)
    end
    if RdrEntity.ready(ent) or RdrEntity.await(ent) then
        arrived()
    else
        RdrEntity.whenReady(ent, function(ready)
            if ready then arrived() return end
            rec.arriving = nil
            RdrEntity.litter(ent)
            if not rec.dropped then physReg:remove(CORE, id) end
        end)
    end
    return handle
end

-- One set for what one Show Prop brings in (every set is sent to every player): its props go in one set, and the run keeps which prop is in which (run.propSets: [setId] = { [worldId] = piece }),
-- so one of them can still be taken away (Hide Prop; Remove, nodes_basics.lua) and the rest put up
-- again without it. A placed thing's handle names its set ({ propSet = id }), as before.

local function setsOf(run)
    local s = run.propSets
    if not s then s = {}; run.propSets = s end
    return s
end

--- What a prop is ATTACHED to as its set goes up (its page: Attached to): the run's car or NPC by its netId, or another
--- of the run's props (in this set, or by its set), and where it sits on it: the offset and turn between where both
--- were placed, read by the parent's heading (a tilted prop under it counts as level). Nil while its parent is not in
--- the world (made later, or gone): it stands where it was placed.
local function attachOf(ctx, piece, sameSet)
    local pid = piece.attachTo
    local pw = ctx:place(pid)
    if type(pw) ~= 'table' or type(pw.def) ~= 'table' or type(pw.def.coords) ~= 'table' then return nil end
    local spec
    if pw.kind == 'npc' or pw.kind == 'vehicle' then
        local h = Director.handleOf(ctx.run, pid)
        local net = type(h) == 'table' and h.netId or nil
        if not net then return nil end
        spec = { net = net }
    elseif pw.kind == 'prop' then
        local ph = Director.handleOf(ctx.run, pid)
        if type(ph) == 'table' and ph.physProp and ph.netId then
            spec = { net = ph.netId }   -- (a physics prop: the one object, wherever it has got to)
        elseif sameSet[pid] then
            spec = { index = sameSet[pid] }
        else
            local sid, i = DirectorTasks.propSlot(ctx.run, pid)
            if not sid then return nil end
            spec = { set = sid, index = i }
        end
    else
        return nil
    end
    local pc, cc = pw.def.coords, piece.coords
    local ph = tonumber(pc.heading) or 0.0
    local dx, dy, dz = cc.x - (tonumber(pc.x) or 0), cc.y - (tonumber(pc.y) or 0), cc.z - (tonumber(pc.z) or 0)
    local c, s = math.cos(math.rad(-ph)), math.sin(math.rad(-ph))
    local offset = { x = dx * c - dy * s, y = dx * s + dy * c, z = dz }
    local rot = { x = piece.rot.x or 0.0, y = piece.rot.y or 0.0, z = ((piece.rot.z or 0.0) - ph) % 360.0 }
    return spec, offset, rot
end

--- Put a set up as it now is (its props in a fixed order), or take it down when nothing is left in it.
---@return boolean ok
---@return string|nil why
local function sendSet(ctx, id)
    local sets = setsOf(ctx.run)
    local pieces = sets[id]
    local wids = {}
    for wid in pairs(pieces or {}) do wids[#wids + 1] = wid end
    if #wids == 0 then
        sets[id] = nil
        PropSets.hide(CORE, id)
        return true
    end
    table.sort(wids)
    local sameSet = {}
    for i, wid in ipairs(wids) do sameSet[wid] = i end
    local list = {}
    for i, wid in ipairs(wids) do
        local p = pieces[wid]
        if p.attachTo then
            local spec, offset, rot = attachOf(ctx, p, sameSet)
            if spec then
                local c = {}
                for k, v in pairs(p) do c[k] = v end
                c.attach, c.attachOffset, c.attachRot = spec, offset, rot
                p = c
            else
                ctx:log('%s: what it is attached to (%s) is not in the world yet: it stands where it was placed', wid, tostring(p.attachTo))
            end
        end
        list[i] = p
    end
    -- An isolated tester's props are theirs alone (main.lua startRun); everyone's otherwise.
    local ok, why = PropSets.show(CORE, id, { props = list, tag = ctx:tag(), audience = ctx.run.propAudience })
    -- The set is sent as a new one: the props playing tasks in it go on where their timelines are.
    local moving = ctx.run.propMotions
    if ok and moving then
        for i, wid in ipairs(wids) do
            if moving[wid] then PropSets.move(CORE, id, i, moving[wid]) end
        end
    end
    return ok, why
end

--- Where a run's prop is: its set's id and its place in the set's list (as sendSet sends it), or nil.
--- On DirectorTasks (server/director/tasks.lua, loaded before this file): a prop's tasks move it there.
function DirectorTasks.propSlot(run, worldId)
    local h = run.world[worldId]
    local id = type(h) == 'table' and h.propSet or nil
    local pieces = id and run.propSets and run.propSets[id]
    if not pieces or not pieces[worldId] then return nil end
    local wids = {}
    for wid in pairs(pieces) do wids[#wids + 1] = wid end
    table.sort(wids)
    for i, wid in ipairs(wids) do
        if wid == worldId then return id, i end
    end
    return nil
end

--- Take these placed things' props out of the sets that show them (not sent yet). Answers the sets it
--- changed, to be sent once each. `handles`: [worldId] = its handle, when the caller has it already.
local function takeOut(ctx, wids, handles, touched)
    touched = touched or {}
    local sets = setsOf(ctx.run)
    for _, wid in ipairs(wids) do
        local h = handles and handles[wid] or ctx:handle(wid)
        if type(h) == 'table' and h.physProp then
            ctx:remember(wid, nil)
            physReg:remove(CORE, h.physProp)
        elseif type(h) == 'table' and h.propSet then
            ctx:remember(wid, nil)
            if ctx.run.propMotions then ctx.run.propMotions[wid] = nil end   -- (its tasks go with it)
            local pieces = sets[h.propSet]
            if pieces then
                pieces[wid] = nil
                touched[h.propSet] = true
            else
                PropSets.hide(CORE, h.propSet)   -- a set the run does not keep: its own, whole
            end
        end
    end
    return touched
end

--- Take one of the run's props away: out of its set, the rest of the set staying up (Remove,
--- nodes_basics.lua). On DirectorNodes, which loads before this file (Director is main.lua's, after it).
---@param h table|nil  its handle, when the caller has forgotten it already
function DirectorNodes.takeRunProp(ctx, worldId, h)
    for sid in pairs(takeOut(ctx, { worldId }, { [worldId] = h })) do sendSet(ctx, sid) end
end

--- This prop and, when asked, every run prop of its group. `world`: [id] = placed thing.
local function propsFor(world, worldId, withGroup)
    local ids = { worldId }
    local w = world[worldId]
    local g = w and type(w.def) == 'table' and w.def.group
    if withGroup and type(g) == 'string' and g ~= '' then
        local others = {}
        for wid, o in pairs(world) do
            if wid ~= worldId and o.kind == 'prop' and o.layer ~= 'standing' and type(o.def) == 'table' and o.def.group == g then
                others[#others + 1] = wid
            end
        end
        table.sort(others)
        for _, wid in ipairs(others) do ids[#ids + 1] = wid end
    end
    return ids
end

--- The props a Show Prop or Hide Prop card names, each once: each prop picked, a group's members (only those a card
--- shows: an Always present one is there already), and with Its group too every run prop of each one's group.
--- `world`: [id] = placed thing.
local function cardProps(world, props)
    local out, seen = {}, {}
    for _, x in ipairs(type(props.prop) == 'table' and props.prop or { props.prop }) do
        local g = DirectorNodes.groupName(x)
        for _, wid in ipairs(DirectorNodes.expandThings(world, { x }, 'prop')) do
            local w = world[wid]
            if w and not (g and w.layer == 'standing') then
                for _, id in ipairs(propsFor(world, wid, props.withGroup == true)) do
                    if not seen[id] then seen[id] = true; out[#out + 1] = id end
                end
            end
        end
    end
    return out
end

--- A document's things by id.
local function byId(doc)
    local out = {}
    for _, w in ipairs(type(doc) == 'table' and type(doc.world) == 'table' and doc.world or {}) do
        if type(w) == 'table' and type(w.id) == 'string' then out[w.id] = w end
    end
    return out
end
--- The props a Show Prop card shows, of a document (Check: graph.lua shownProps).
function DirectorNodes.showPropsOf(doc, props) return cardProps(byId(doc), props) end

--- Check: a prop these cards change is the run's (a standing one is the scenario's, there already). Only those picked
--- one by one: a group's Always present ones are passed over.
local function runProp(v, doc)
    local picked = {}
    for _, x in ipairs(type(v) == 'table' and v or { v }) do
        if not DirectorNodes.groupName(x) then picked[x] = true end
    end
    for _, w in ipairs(type(doc) == 'table' and type(doc.world) == 'table' and doc.world or {}) do
        if type(w) == 'table' and picked[w.id] and w.layer == 'standing' then
            return ('"%s" is Always present: it is there whenever the scenario is on (make it Only activates via card for a card to show it)')
                :format(tostring(w.label or w.id))
        end
    end
    return nil
end

define({
    type = 'prop.show', v = 2, category = 'world', title = 'Show Prop',
    desc = 'Puts the props (or groups) picked from the World tab where they were placed. With Physics on, they fall and get knocked about. Gone when the scenario ends.',
    outputs = { 'out' },
    heavy = true,   -- a set sent to every player: the pass checks its time after it
    upgrade = function(props) return DirectorNodes.toList(props, 'prop') end,
    -- What it makes (its props, and with Its group too every prop of each one's group), and that it starts their tasks
    -- itself (Check, Start Tasks: nodes.lua `makes`).
    makes = function(props, doc) return DirectorKit.idSet(DirectorNodes.showPropsOf(doc, props)) end,
    startsTasks = function(props) return props.tasks ~= false end,
    props = {
        DirectorNodes.thingsField('prop', 'prop', 'Props (the scenario\'s, or groups)', { check = runProp }),
        { key = 'withGroup', kind = 'bool', label = 'Their groups too', default = false },
        { key = 'tasks', kind = 'bool', label = 'Start their tasks', default = true, hint = 'Each with a list on its page' },
    },
    run = function(ctx)
        local wids = cardProps(ctx.run.graph.world, ctx.node.props)
        local pieces, shown = {}, {}
        for _, wid in ipairs(wids) do
            local w = ctx:place(wid)
            local piece = type(w) == 'table' and Director.propPiece(w.def) or nil
            if not piece then
                ctx:log('%s has no model or no spot', tostring(wid))
            else
                pieces[wid] = piece
                shown[#shown + 1] = wid
            end
        end
        if #shown == 0 then return 'out' end
        -- Shown already (by an earlier card, alone or with its group): out of that set first, so it is
        -- never there twice; every set changed is sent once.
        local touched = takeOut(ctx, shown)
        -- A physics one: its object, made now (PHYSICS). One that cannot be made stands still in the set instead.
        local still = {}
        for _, wid in ipairs(shown) do
            local h, why = nil, nil
            if not DirectorNodes.physicsOff(ctx:place(wid), pieces[wid]) then
                h, why = DirectorNodes.makePhysical(ctx:tag(), ctx.run.bucket, setId(ctx, wid), pieces[wid])
            end
            if h then
                ctx:remember(wid, h)
            else
                if why then ctx:log('%s: physics: %s (it stands still)', tostring(wid), tostring(why)) end
                still[#still + 1] = wid
            end
        end
        local id = setId(ctx, wids[1])
        local again = touched[id]   -- (its set, changed by takeOut: sent again even with none still)
        touched[id] = nil
        for sid in pairs(touched) do sendSet(ctx, sid) end
        if #still > 0 or again then
            local sets = setsOf(ctx.run)
            local set = sets[id] or {}
            sets[id] = set
            for _, wid in ipairs(still) do set[wid] = pieces[wid] end
            local ok, why = sendSet(ctx, id)
            if ok then
                for _, wid in ipairs(still) do ctx:remember(wid, { propSet = id }) end
            else
                ctx:log('props: %s', tostring(why))
                for _, wid in ipairs(still) do set[wid] = nil end
                if next(set) == nil then sets[id] = nil end
                still = {}
            end
        end
        -- (A physics one never has tasks: physicsOff. Started for the ones shown still.)
        if ctx:prop('tasks') ~= false then
            for _, wid in ipairs(still) do DirectorTasks.startFor(ctx, wid) end
        end
        return 'out'
    end,
})

define({
    type = 'prop.hide', v = 2, category = 'world', title = 'Hide Prop',
    desc = 'Takes away the props (or groups) Show Prop put up (and, if asked, every prop of their groups).',
    outputs = { 'out' },
    upgrade = function(props) return DirectorNodes.toList(props, 'prop') end,
    props = {
        DirectorNodes.thingsField('prop', 'prop', 'Props (the scenario\'s, or groups)', { check = runProp }),
        { key = 'withGroup', kind = 'bool', label = 'Their groups too', default = false },
    },
    run = function(ctx)
        -- Each taken out of its set; a set with others still in it is sent again without them.
        for sid in pairs(takeOut(ctx, cardProps(ctx.run.graph.world, ctx.node.props))) do
            sendSet(ctx, sid)
        end
        return 'out'
    end,
})

-- Ready before it is shown (a model loading when the card shows it takes a moment). When a run starts, every prop its Show Prop cards can bring in is sent as a READY
-- set (PropSets.ready): each game near one loads its model and keeps an eye on its interior, so the card's
-- prop is made the moment it comes. It goes with the run (its tag). At most a set's size (PropSets.maxProps,
-- Props per scene set): past that, a prop is made as before, its model loading when it comes.

--- Send a run's props as one ready set (main.lua startRun), when it has any.
function DirectorNodes.readyRunProps(run)
    local wids, seen = {}, {}
    for _, node in pairs(run.graph.nodes) do
        if node.type == 'prop.show' and node.props.prop ~= nil then
            for _, wid in ipairs(cardProps(run.graph.world, node.props)) do
                if not seen[wid] then seen[wid] = true; wids[#wids + 1] = wid end
            end
        end
    end
    if #wids == 0 then return end
    table.sort(wids)
    local list, models, max = {}, {}, PropSets.maxProps()
    for _, wid in ipairs(wids) do
        local w = DirectorRuntime.place(run, wid)
        local piece = type(w) == 'table' and Director.propPiece(w.def) or nil
        -- One a model is enough to load it; each inside an MLO is kept for its interior.
        if piece and #list < max and (piece.interior or not models[piece.model]) then
            models[piece.model] = true
            list[#list + 1] = piece
        end
    end
    if #list == 0 then return end
    local ok, why = PropSets.ready(CORE, run.tag .. ':ready', { props = list, tag = run.tag, audience = run.propAudience })
    if not ok then print(('[spur_core:director] run %s: its props could not be readied: %s'):format(tostring(run.id), tostring(why))) end
end
