-- ============================================
-- Director — what an NPC does: says, runs away, plays an emote, walks, follows
-- ============================================
--
-- The cards that move an NPC change its brain (server/npcs.lua: SetNpcState), so whichever player's
-- game runs the ped carries on with it, a new owner too. They change only NPCs a run made (Spawn NPC):
-- a standing one is every run's, and no run's end would put it back. For a thing made more than once,
-- every one of them does it. NPC /me only shows a line, so a standing NPC can say one too.
--
--   NPC /me            lines above its head for everyone near: what it does or says, a line picked from up
--                      to four (no answers: Dialog Line)
--   NPC Runs Away      runs from the player (or the nearest of the run's players), and fights nobody
--   NPC Plays Emote    an emote's animation where it stands (/e names); empty stops it
--   NPC Walks To       walks or runs to a placed thing and stays there: Arrived, Did not get there
--   NPC Follows Player walks after the player (an escort); "stop" leaves it where it is
--
-- Not built: NPC Drives Off (NPC drivers are on the plan's "later" list, plan section 9).

local CORE = GetCurrentResourceName()

local define = DirectorKit.define
local vec = DirectorKit.place

--- The NPCs THIS run made for a placed thing (never the standing one).
local function runNpcsOf(ctx, worldId) return DirectorNodes.npcIds(ctx:handle(worldId)) end

--- Check: a card that changes an NPC is given a standing one.
local function notStanding(v, doc)
    local world = type(doc) == 'table' and type(doc.world) == 'table' and doc.world or {}
    -- (The NPCs picked one by one: a group's standing ones are passed over, as the card only changes what a run made.)
    local named = {}
    for _, x in ipairs(type(v) == 'table' and v or { v }) do
        if not DirectorNodes.groupName(x) then named[x] = true end
    end
    for _, w in ipairs(world) do
        if type(w) == 'table' and named[w.id] and w.layer == 'standing' then
            return ('"%s" is Always present (shared by everyone): this card changes only NPCs the scenario makes (Spawn NPC)')
                :format(tostring(w.label or w.id))
        end
    end
    return nil
end

--- The NPCs this run made for every placed thing (and group) the card's field `key` names, each once.
local function runNpcsOfAll(ctx, key)
    local out, seen = {}, {}
    for _, wid in ipairs(DirectorNodes.things(ctx, key)) do
        for _, id in ipairs(runNpcsOf(ctx, wid)) do
            if not seen[id] then seen[id] = true; out[#out + 1] = id end
        end
    end
    return out
end

--- Change every NPC the run made for the placed things (and groups) the card's field `key` names. Answers how many
--- took it.
local function setAll(ctx, key, patchFor)
    local n = 0
    local ids = runNpcsOfAll(ctx, key)
    if #ids == 0 then ctx:log('%s: this run made none of them', table.concat(DirectorNodes.things(ctx, key), ', ')) end
    for i, id in ipairs(ids) do
        local info = Npcs.get(id)
        if info and info.alive then
            local ok, why = Npcs.setState(CORE, id, patchFor(id, info, i), ctx.node.def.title)
            if ok then n = n + 1 else ctx:log('NPC %s: %s', tostring(id), tostring(why)) end
        end
    end
    return n
end

--- An emote's animation: { dict, clip } or { scenario }, or nil (as Progress reads one: nodes.lua).
local emoteAnim = DirectorNodes.emoteAnim

local function flatDistance(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

-- ============================================
-- NPC /me: lines above an NPC
-- ============================================
--
-- What an NPC does or says ("hands over a package", "Hands up!"), above its head as a /me is above a player's, for everyone near: the run's players too, and it is
-- not part of anyone's dialog capsule. It goes on at once. (A Dialog Line's own line is shown this way
-- to the players watching, without a card: server/conversations.lua.)
--
-- ITS LINE, and up to three alternatives (the page adds one at a time). How they play: ONE AT RANDOM (How many of
-- them, each once, Between them apart) or IN ORDER (every one, Between them apart). It goes on at once; the later
-- lines show on their own time while the run lasts. For a thing made more than once: above each of them still up,
-- each with its own pick. A standing NPC works too.

local LINES = { 'text', 'text2', 'text3', 'text4' }
local PICK = { 'random', 'order' }
local PICK_LABELS = { random = 'One at random', order = 'In order' }

-- How they play, only once there are alternatives: How many of them at random, and Between them for more than one.
local ALTS = { any = { { key = 'text2', set = true }, { key = 'text3', set = true }, { key = 'text4', set = true } } }

--- Its fields; `first` is its line's label.
local function lineProps(first)
    return {
        DirectorNodes.thingsField('npc', 'npc', 'Who (NPCs or groups)'),
        { key = 'text', kind = 'text', label = first, required = true, maxLength = 120 },
        { key = 'text2', kind = 'text', label = 'Alternative dialog 1', maxLength = 120 },
        { key = 'text3', kind = 'text', label = 'Alternative dialog 2', maxLength = 120 },
        { key = 'text4', kind = 'text', label = 'Alternative dialog 3', maxLength = 120 },
        { key = 'pick', kind = 'select', label = 'How does dialog play?', options = PICK, optionLabels = PICK_LABELS, default = PICK[1],
          when = ALTS },
        { key = 'count', kind = 'number', label = 'How many play', hint = 'at random, each once', default = 1, min = 1, max = 4,
          when = { all = { ALTS, { key = 'pick', isnt = 'order' } } } },
        { key = 'gap', kind = 'duration', label = 'Between them (seconds)', default = 4, min = 1, max = 30,
          when = { all = { ALTS, { any = { { key = 'pick', is = 'order' }, { key = 'count', above = 1 } } } } } },
        -- (Left alone, a /me's own range, Config.Bubbles.range. Set, its size stays the same out to it: Bubbles.show `range`.)
        { key = 'range', kind = 'number', label = 'Seen from', min = 5, max = 250, step = 5, unit = ' m', slider = true,
          default = math.floor((Config.Bubbles and Config.Bubbles.range) or 20),
          hint = 'How far away players see it. It keeps its size, as the NPC does: through a camera zoomed in on them it is as big as they are' },
    }
end

--- The netIds of the NPCs the card's line goes above: every one still up of every placed thing (and group) it names,
--- each once.
local function speakersOf(ctx)
    local out, seen = {}, {}
    for _, wid in ipairs(DirectorNodes.things(ctx, 'npc')) do
        for _, id in ipairs(DirectorNodes.npcIds(Director.handleOf(ctx.run, wid))) do
            local info = Npcs.get(id)
            if info and info.alive and info.netId and not seen[info.netId] then
                seen[info.netId] = true
                out[#out + 1] = info.netId
            end
        end
    end
    return out
end

--- Show the card's lines above its NPCs.
local function sayAbove(ctx)
    local nets = speakersOf(ctx)
    if #nets == 0 then
        ctx:log('%s: none of them is in the world (or up): nobody to show it above', table.concat(DirectorNodes.things(ctx, 'npc'), ', '))
        return
    end
    local lines = {}
    for _, k in ipairs(LINES) do
        local v = ctx:prop(k)
        if type(v) == 'string' and v ~= '' then lines[#lines + 1] = v end
    end
    if #lines == 0 then return end
    local inOrder = ctx:prop('pick') == PICK[2]
    local count = math.max(1, math.min(#lines, math.floor(tonumber(ctx:prop('count')) or 1)))
    local gap = math.max(1, math.min(30, tonumber(ctx:prop('gap')) or 4))
    -- Its Seen from, only when the card sets one (unset: a /me's own range, whatever it is now).
    local seen = tonumber(ctx.node.props.range)
    local opts = seen and { range = seen } or nil
    -- What each NPC plays, in its order: every line (In order), or How many of them at random, each once.
    local function playList()
        if #lines == 1 or inOrder then return lines end
        local pool, out = { table.unpack(lines) }, {}
        for _ = 1, count do out[#out + 1] = table.remove(pool, math.random(#pool)) end
        return out
    end
    local plays, most = {}, 0
    for _, net in ipairs(nets) do
        plays[net] = playList()
        most = math.max(most, #plays[net])
    end
    -- Line i above each of them still up (one down since says nothing more), all in one go (Bubbles.showMany: the
    -- players are looked at once, not once per NPC).
    local function show(i)
        local said = {}
        for _, net in ipairs(i == 1 and nets or speakersOf(ctx)) do
            local line = plays[net] and plays[net][i]
            if line then said[#said + 1] = { { netId = net }, line, opts } end
        end
        if #said > 0 then Bubbles.showMany(said) end
    end
    show(1)
    for i = 2, most do
        SetTimeout(math.floor((i - 1) * gap * 1000), function()
            if ctx.run.status == 'running' then show(i) end
        end)
    end
end

define({
    type = 'npc.me', v = 2, category = 'dialog', title = 'NPC /me',
    desc = 'A line above an NPC\'s head for everyone nearby, like a /me. Add alternatives to pick one at random or in order.',
    outputs = { 'out' },
    upgrade = function(props) return DirectorNodes.toList(props, 'npc') end,
    heavy = true,   -- every player is looked at (who is near): the pass checks its time after it
    -- A line above its `npc` field's NPC: a talking card's outcome wired straight to it says this, not its own parting
    -- line (talk.lua).
    saysAbove = true,
    props = lineProps('What they say'),
    -- (The editor shows the alternatives written, and Add alternative dialog for the next.)
    repeats = { { keys = { 'text%d' }, from = 2, to = 4, min = 0, add = 'Add alternative dialog' } },
    run = function(ctx)
        sayAbove(ctx)
        return 'out'
    end,
})

-- ============================================
-- NPC Runs Away
-- ============================================

local FROM = { 'this player', 'the nearest of the run\'s players' }

define({
    type = 'npc.flee', v = 2, category = 'world', title = 'NPC Runs Away',
    desc = 'The NPCs (or groups) picked run from the player and stop fighting: a witness, a dealer who bolts.',
    outputs = { 'out' },
    upgrade = function(props) return DirectorNodes.toList(props, 'npc') end,
    props = {
        DirectorNodes.thingsField('npc', 'npc', 'NPCs (ones this scenario made)', { check = notStanding }),
        { key = 'from', kind = 'select', label = 'Runs from', options = FROM, default = FROM[1],
          optionLabels = { [FROM[2]] = 'the nearest of the scenario\'s players' } },
    },
    run = function(ctx)
        local nearest = ctx:prop('from') == FROM[2]
        local me = Director.playerOf(ctx)
        setAll(ctx, 'npc', function(_, info)
            local from = me
            if nearest or not from then
                local best, bestD
                for _, s in ipairs(ctx:players()) do
                    local ped = GetPlayerPed(s)
                    local c = ped and ped ~= 0 and GetEntityCoords(ped) or nil
                    if c and info.coords then
                        local d = flatDistance(c, info.coords)
                        if not bestD or d < bestD then best, bestD = s, d end
                    end
                end
                from = best or from
            end
            return { flee = from or false, hostileTo = false, follow = false }
        end)
        -- Calmed for good: Spawn NPC and NPC Attacks keep a hostile
        -- NPC's targets as the crew changes (Director.followCrew, 'npc:<id>'). Left in place, a crew
        -- change set it hostile again, and once a later card ended the flee it fought them.
        for _, id in ipairs(runNpcsOfAll(ctx, 'npc')) do
            Director.followCrew(ctx.run, 'npc:' .. tostring(id), nil)
        end
        return 'out'
    end,
})

-- ============================================
-- NPC Plays Emote
-- ============================================

define({
    type = 'npc.emote', v = 2, category = 'world', title = 'NPC Plays Emote',
    desc = 'The NPCs (or groups) picked play an emote where they stand, over and over: smoking, leaning, on the phone. Leave it empty to stop.',
    outputs = { 'out' },
    upgrade = function(props) return DirectorNodes.toList(props, 'npc') end,
    props = {
        DirectorNodes.thingsField('npc', 'npc', 'NPCs (ones this scenario made)', { check = notStanding }),
        { key = 'emote', kind = 'text', label = 'Emote (/e name; empty: stop)', maxLength = 40,
          check = function(v)
              if v == '' or emoteAnim(v) then return nil end
              return ('"%s" is not an emote with an animation (see /e)'):format(tostring(v))
          end },
    },
    run = function(ctx)
        local cmd = ctx:prop('emote')
        local anim = emoteAnim(cmd)
        if cmd ~= nil and cmd ~= '' and not anim then ctx:log('"%s" is not an emote with an animation', tostring(cmd)) end
        setAll(ctx, 'npc', function() return { anim = anim or false } end)
        return 'out'
    end,
})

-- ============================================
-- NPC Walks To
-- ============================================

local PACES = { 'walk', 'run' }
local ARRIVED_WITHIN = 3.0   -- metres from its new spot (flat): there

define({
    type = 'npc.walkTo', v = 2, category = 'world', title = 'NPC Walks To',
    desc = 'The NPCs (or groups) picked walk or run to a placed thing and stay there, spread round it. Did not get there: they died or are gone.',
    outputs = { 'arrived', 'failed', 'timeout' },
    labels = { arrived = 'Arrived', failed = 'Did not get there', timeout = 'Too late' },
    latent = true,
    pinWhen = DirectorFields.TIMES_OUT,
    upgrade = function(props) return DirectorNodes.toList(props, 'npc') end,
    props = {
        DirectorNodes.thingsField('npc', 'npc', 'NPCs (ones this scenario made)', { check = notStanding }),
        { key = 'at', kind = 'world', label = 'To (a placed thing)', required = true },
        { key = 'pace', kind = 'select', label = 'Pace', options = PACES, default = 'walk' },
        { key = 'seconds', kind = 'duration', label = 'Gives up after (seconds; empty: never)', min = 5, max = 3600 },
    },
    run = function(ctx)
        local atW = ctx.node.props.at
        local w = ctx:place(atW)
        local at = vec(type(w) == 'table' and type(w.def) == 'table' and w.def.coords or nil)
        if not at then
            ctx:log('%s has no spot', tostring(atW))
            return 'failed'
        end
        local ids = runNpcsOfAll(ctx, 'npc')
        local count = #ids
        local inside = type(w.def) == 'table' and w.def.interior == true
        -- Several spread round the spot, the first on it.
        local moved = setAll(ctx, 'npc', function(_, _, i)
            local a = (i - 1) * (2.0 * math.pi / math.max(1, count))
            local r = (count <= 1 or i == 1) and 0.0 or 1.5
            -- Inside an MLO, each looks for it at the spot itself, not on its own spot round it.
            return { post = { x = at.x + math.cos(a) * r, y = at.y + math.sin(a) * r, z = at.z, heading = at.heading },
                      gateAt = inside and { x = at.x, y = at.y, z = at.z } or nil,
                      interior = inside, pace = ctx:prop('pace') or 'walk', follow = false, flee = false }
        end)
        if moved == 0 then return 'failed' end
        ctx:poll(1000, function()
            -- There once every one still up is within reach of its spot; none left: did not get there.
            local up, there = 0, 0
            for _, id in ipairs(runNpcsOfAll(ctx, 'npc')) do
                local info = Npcs.get(id)
                if info and info.alive then
                    up = up + 1
                    if info.post and info.coords and flatDistance(info.coords, info.post) <= ARRIVED_WITHIN then there = there + 1 end
                end
            end
            if up == 0 then return 'failed' end
            if there < up then return nil end
            Director.event(ctx.run, ctx.node.id, 'arrived', nil, tostring(atW))
            return 'arrived'
        end)
        local seconds = tonumber(ctx:prop('seconds'))
        if seconds then ctx:after(seconds * 1000, 'timeout') end
        return nil
    end,
})

-- ============================================
-- NPC Follows Player
-- ============================================

local DO_FOLLOW = { 'follow the player', 'stop following' }
local IN_HOUSE = 20.0   -- metres from an MLO NPC's post that are still that house (client/npcs.lua's GATE_NEAR)

define({
    type = 'npc.follow', v = 2, category = 'world', title = 'NPC Follows Player',
    desc = 'The NPCs (or groups) picked walk after the player: someone to escort. "Stop following" leaves them standing where they are.',
    outputs = { 'out' },
    upgrade = function(props) return DirectorNodes.toList(props, 'npc') end,
    props = {
        DirectorNodes.thingsField('npc', 'npc', 'NPCs (ones this scenario made)', { check = notStanding }),
        { key = 'do', kind = 'select', label = 'Do', options = DO_FOLLOW, default = DO_FOLLOW[1] },
        { key = 'pace', kind = 'select', label = 'Pace', options = PACES, default = 'walk' },
    },
    run = function(ctx)
        if ctx:prop('do') == DO_FOLLOW[2] then
            -- Its post becomes where it is now, so it does not walk back to where it was made. An NPC
            -- made inside an MLO stays held by it only while it still stands in that house (near its
            -- old post): led out into the street, the house's interior is nothing to wait for there.
            setAll(ctx, 'npc', function(_, info)
                local c = info.coords
                if not c then return { follow = false } end
                local inside = info.interior == true and info.post ~= nil and flatDistance(c, info.post) <= IN_HOUSE
                return { follow = false, post = { x = c.x, y = c.y, z = c.z, heading = info.post and info.post.heading or 0.0 },
                         interior = inside }
            end)
            return 'out'
        end
        local src = Director.playerOf(ctx)
        if not src then
            ctx:log('nobody to follow')
            return 'out'
        end
        setAll(ctx, 'npc', function() return { follow = src, flee = false, pace = ctx:prop('pace') or 'walk' } end)
        Director.event(ctx.run, ctx.node.id, 'following', src)
        return 'out'
    end,
})
