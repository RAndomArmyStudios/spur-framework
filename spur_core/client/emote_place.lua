-- ============================================
-- EMOTE PLACING — pose a see-through copy of yourself, then walk there and settle in
-- ============================================
--
-- /e place <emote>, or Place in the emote menu. A ghost of the player — their model, their clothes,
-- already doing the emote — stands where the camera points. The wheel turns it (Ctrl for fine), the
-- up and down arrows raise and lower it, E sends the player walking there, and on arrival they
-- settle into the emote at exactly the ghost's spot and heading (Emotes.play with `at`).
--
-- The item placer's pattern (client/placing.lua) with a ped for a prop, and two differences:
--   the thread is BORN WITH THE MODE AND ENDS WITH IT — nothing idles while nobody is placing;
--   the ghost is a local CreatePed built far below and then moved (the recipe of BuildMenuPed in
--   client/inventory.lua), not ClonePed — a ped created beside a parked car can make the game
--   reclaim the car.
--
-- NOT A WAY THROUGH WALLS. Other emote scripts let a player place an emote on the far side of a
-- wall or a window and be put there — straight into a locked interior. Here:
--   the spot must be in sight: nothing between the player's head and the ghost's chest;
--   there must be headroom above the spot (no burying a head in a ceiling);
--   the player WALKS there (TaskGoStraightToCoord, timeout -1: the navmesh task's timeout teleports
--   the ped to the target when it runs out), and any jump of more than 1.5 m on the way ends it;
--   on arrival the sight line is checked again, from where E was pressed and from where they
--   stand, and the final shift into the pose is at most 1.5 m across, 1.6 m up and 1 m down.
--
-- WHY NOT THE NAVMESH. Plenty of interiors have none, and a spot up on a bed or a table is off it.
-- The spot is in sight and at most placeRange away, so a straight walk is what gets there.

local placing = nil     -- the mode's state while it runs; nil otherwise

local ROTATE_STEP, ROTATE_FINE = 15.0, 2.0   -- degrees per wheel notch; with Ctrl held
-- On a pad the triggers turn it, the wheel being nothing there: LT left, RT right,
-- smoothly, faster the further they are pulled — the item placer's way (client/placing.lua). The D-pad's
-- up and down are the height on both (IsGameInputFree is false while placing: pad.lua leaves them be).
local PAD_TURN = 140.0                       -- degrees a second at a full pull
local PAD_DEAD = 0.08                        -- a trigger resting short of this is not pulled
local NUDGE_STEP = 0.05                      -- metres per arrow press
local NUDGE_MIN, NUDGE_MAX = -0.3, 1.0       -- below 0 only a little: a deep nudge sinks into a floor
local NORMAL_MIN_Z = 0.7                     -- the surface must face up: a floor, a seat, a bed
local MAX_RISE = 2.0                         -- the spot's floor at most this far above/below the player's
local SIGHT_SLACK = 0.15                     -- the sight ray may stop this short of the chest
local HEADROOM = 0.8                         -- clear space above the ghost's root
local CHEST = 0.35                           -- the chest, above the root
local RAY_MASK = 1 + 2 + 16 + 64             -- world, vehicles, objects, glass
local SIGHT_MASK = 1 + 16 + 64               -- what can hide a spot
local ARRIVE, ARRIVE_ENDED = 0.35, 1.5       -- close enough; close enough once the walk stopped
local SHIFT_SIDE, SHIFT_UP, SHIFT_DOWN = 1.5, 1.6, 1.0
local JUMP = 1.5                             -- metres in one 100 ms check: a teleport, not a walk
local ALPHA = 150

-- ---- small helpers ----

local function dist2(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

--- A ray, answered now: hit (bool), where, the surface normal, the entity.
local function ray(a, b, mask, ignore)
    local h = StartShapeTestRay(a.x, a.y, a.z, b.x, b.y, b.z, mask, ignore or 0, 0)
    local _, hit, coords, normal, entity = GetShapeTestResult(h)
    return hit == 1, coords, normal, entity
end

--- Is the point in sight from `from`? Nothing in the way, or the first thing hit is within
--- SIGHT_SLACK of the point itself.
local function inSight(from, to)
    local hit, coords = ray(from, to, SIGHT_MASK, PlayerPedId())
    return not hit or #(coords - to) <= SIGHT_SLACK
end

local function headOf(ped)
    return GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
end

-- ---- the bottom-of-screen text, change-detected (placing.lua's pattern) ----

local shownText = nil
--- The hint capsule, its disc the emote glyph; `warn` rings it amber — nowhere to stand.
local function say(text, warn)
    if text == shownText then return end
    shownText = text
    UI.ShowText(text, { position = 'bottom', icon = 'emote', tone = warn and 'warn' or nil })
end
local function unsay()
    if shownText == nil then return end
    shownText = nil
    UI.HideText()
end

-- ---- the ghost ----

local function deleteGhost(st)
    for _, obj in ipairs(st.ghostProps or {}) do
        if DoesEntityExist(obj) then DeleteEntity(obj) end
    end
    st.ghostProps = {}
    if st.ghost and DoesEntityExist(st.ghost) then DeleteEntity(st.ghost) end
    st.ghost = nil
    st.ghostReady = false
end

local function ghostAnim(st)
    local g = st.ghost
    if g and DoesEntityExist(g) then
        TaskPlayAnim(g, st.def.dict, st.def.anim, 8.0, -8.0, -1, st.def.loop and 1 or 2, 0.0, false, false, false)
    end
end

--- Build the ghost: a local ped of the player's model in their clothes, doing the emote, holding
--- local copies of its props. Runs in its own thread; the mode goes on without it until it is up.
local function buildGhost(st)
    local ped = PlayerPedId()
    local model = GetEntityModel(ped)
    if not LoadModel(model) or placing ~= st then return end
    local c = GetEntityCoords(ped)
    local g = CreatePed(4, model, c.x, c.y, c.z - 100.0, 0.0, false, false)
    SetModelAsNoLongerNeeded(model)
    if not g or g == 0 then return end
    if placing ~= st then DeleteEntity(g) return end

    SetEntityVisible(g, false, false)          -- hidden until it is dressed and there is a good spot
    FreezeEntityPosition(g, true)
    SetEntityCollision(g, false, false)        -- also keeps it out of the aim ray
    SetEntityInvincible(g, true)
    SetBlockingOfNonTemporaryEvents(g, true)
    SetPedCanRagdoll(g, false)
    SetEntityAsMissionEntity(g, true, true)
    -- Recorded at once, so finish() deletes it however far this has got. It is not SHOWN until
    -- st.ghostReady, at the end: a half-built ghost is a full-opacity stranger in default clothes.
    st.ghost = g

    -- Every wait below may outlive the mode; finish() has cleaned up by then, so just stop.
    local meta = PlayerData and PlayerData.metadata
    if meta and meta.appearance and ApplyAppearance then ApplyAppearance(g, meta.appearance) end
    if placing ~= st then return end
    SetEntityAlpha(g, ALPHA, false)

    for _, p in ipairs(st.def.props or {}) do
        local hash = GetHashKey(p.model)
        -- No wait between this check and the append, so a prop is either listed for finish() or
        -- never made.
        if LoadModel(hash) and placing == st and DoesEntityExist(g) then
            local obj = CreateObject(hash, c.x, c.y, c.z - 100.0, false, false, false)
            SetModelAsNoLongerNeeded(hash)
            SetEntityCollision(obj, false, false)
            local o, r = p.offset or {}, p.rot or {}
            AttachEntityToEntity(obj, g, GetPedBoneIndex(g, p.bone or 18905),
                (o[1] or 0.0) + 0.0, (o[2] or 0.0) + 0.0, (o[3] or 0.0) + 0.0,
                (r[1] or 0.0) + 0.0, (r[2] or 0.0) + 0.0, (r[3] or 0.0) + 0.0,
                true, true, false, false, 1, true)
            SetEntityAlpha(obj, ALPHA, false)
            st.ghostProps[#st.ghostProps + 1] = obj
        end
    end
    if placing ~= st then return end

    if not LoadAnimDict(st.def.dict, 2000) or placing ~= st then return end
    -- A ped made this frame can refuse its first task; the aim loop asks again if it did (aimFrame).
    ghostAnim(st)
    st.ghostReady = true
end

-- ---- the one way out ----

--- What an end that was not the player's choice says, on the capsule (UI.ShowInterrupted). The rest say nothing: a cancel or taking the controls back was theirs, and a
--- refusal was said by Emotes.play already.
local STOPPED = {
    dead        = 'You went down',
    unreachable = "Couldn't get there",
    blocked     = "Can't reach that spot from here",
}

--- End placing, whatever stage it is in. `reason` picks what is said (see STOPPED).
local function finish(st, reason)
    if placing ~= st then return end
    placing = nil
    ControlBlocks.release('emoteAim')
    ControlBlocks.release('emoteWalk')
    deleteGhost(st)
    -- Said before the mode's own text goes, which then does not cut it short.
    local why = STOPPED[reason]
    if why then UI.ShowInterrupted(why, 'Placing ' .. tostring(st.def and st.def.label or 'the emote')) end
    unsay()
    -- A walk that did not arrive is ours to stop.
    if st.stage == 'walk' and reason ~= 'arrived' then ClearPedTasks(PlayerPedId()) end
end

function Emotes.isPlacing() return placing ~= nil end

function Emotes.cancelPlace()
    if placing then finish(placing, 'cancel') end
end

-- ---- aiming ----

--- Held off while aiming: fighting (the pad's triggers too, which turn it), the weapon wheel (the wheel is
--- the turn dial, read with the disabled readers), cover, duck (Ctrl is the fine-turn key), the arrows
--- (height, not the phone), reload (45: B on a pad, which cancels) and C (26), the cancel, so it does not
--- swing the camera round as well.
local AIM_BLOCK = { groups = { 'combat', 'weaponWheel' }, controls = { 26, 36, 44, 45, 172, 173 } }

--- Held off while walking there (the walk moves on its own; moving the stick ends it): only what B is
--- besides cancel on a pad — the light melee and reload — so cancelling never punches; and C (26).
local WALK_BLOCK = { controls = { 26, 45, 140, 141, 142 } }

--- Where the ghost would stand for this frame's aim, or nil and why.
local function aim(st)
    local ped = PlayerPedId()
    local cam = GetFinalRenderedCamCoord()
    local fx, fy, fz = InteractGetCameraForward()
    local me = GetEntityCoords(ped)
    local range = (Config.Emotes and Config.Emotes.placeRange) or 6.0
    -- Long enough to reach `range` from the player with the camera behind them.
    local reach = range + #(cam - me)
    local hit, coords, normal, entity = ray(cam, vector3(cam.x + fx * reach, cam.y + fy * reach, cam.z + fz * reach),
        RAY_MASK, ped)

    if not hit then return nil, 'Aim at the floor within reach' end
    if entity and entity ~= 0 and GetEntityType(entity) == 2 then return nil, "Not on a vehicle" end
    if not normal or normal.z < NORMAL_MIN_Z then return nil, 'Aim at the floor within reach' end
    if dist2(coords.x, coords.y, me.x, me.y) > range then return nil, 'Too far away' end
    local myFloor = me.z - st.rootH
    if math.abs(coords.z - myFloor) > MAX_RISE then return nil, 'Too far above or below you' end

    local root = vector3(coords.x, coords.y, coords.z + st.rootH + st.nudge)
    if not inSight(headOf(ped), root + vector3(0.0, 0.0, CHEST)) then return nil, "You can't see that spot" end
    local up = ray(vector3(coords.x, coords.y, coords.z + 0.05), root + vector3(0.0, 0.0, HEADROOM), SIGHT_MASK, ped)
    if up then return nil, 'No room there' end

    return { root = root, floor = coords }
end

local function aimFrame(st)
    local fine = IsDisabledControlPressed(0, 36)
    if IsDisabledControlJustPressed(0, 17) then          -- wheel up: turn left
        st.heading = (st.heading + (fine and ROTATE_FINE or ROTATE_STEP)) % 360.0
    elseif IsDisabledControlJustPressed(0, 16) then      -- wheel down: turn right
        st.heading = (st.heading - (fine and ROTATE_FINE or ROTATE_STEP)) % 360.0
    end
    if WhipPadActive then                                 -- LT → left, RT → right
        local pull = WhipPadTrigger('lt', PAD_DEAD) - WhipPadTrigger('rt', PAD_DEAD)
        if pull ~= 0.0 then
            st.heading = (st.heading + PAD_TURN * pull * math.abs(pull) * GetFrameTime()) % 360.0   -- squared: a light pull is fine
        end
    end
    if IsDisabledControlJustPressed(0, 172) then           -- up arrow / D-pad up
        st.nudge = math.min(NUDGE_MAX, st.nudge + NUDGE_STEP)
    elseif IsDisabledControlJustPressed(0, 173) then       -- down arrow / D-pad down
        st.nudge = math.max(NUDGE_MIN, st.nudge - NUDGE_STEP)
    end

    local spot, why = aim(st)
    st.spot = spot
    local g = st.ghostReady and st.ghost or nil

    if spot then
        if g and DoesEntityExist(g) then
            -- Moved only when the target changes: a still aim costs nothing.
            local r = spot.root
            local last = st.shown
            if not last or last.x ~= r.x or last.y ~= r.y or last.z ~= r.z or last.h ~= st.heading then
                SetEntityCoordsNoOffset(g, r.x, r.y, r.z, false, false, false)
                SetEntityHeading(g, st.heading)
                st.shown = { x = r.x, y = r.y, z = r.z, h = st.heading }
            end
            if not IsEntityVisible(g) then SetEntityVisible(g, true, false) SetEntityAlpha(g, ALPHA, false) end
            -- A ped sometimes drops its first task; ask again, twice a second at most.
            if GetGameTimer() > (st.nextAnimCheck or 0) then
                st.nextAnimCheck = GetGameTimer() + 500
                if not IsEntityPlayingAnim(g, st.def.dict, st.def.anim, 3) then ghostAnim(st) end
            end
        end
        say(WhipPadActive
            and (WhipAcceptHint() .. ' Go there  |  {pad:lt}{pad:rt} Turn  |  {pad:dpad_up}{pad:dpad_down} Height  |  '
                 .. WhipCancelHint() .. ' Cancel')
            or (WhipAcceptHint() .. ' Go there  |  [Scroll] Turn (Ctrl: fine)  |  [Up/Down] Height  |  [C] Cancel'))
    else
        if g and DoesEntityExist(g) and IsEntityVisible(g) then SetEntityVisible(g, false, false) end
        say(why .. '  |  ' .. WhipCancelHint() .. ' Cancel', true)
    end

    -- Disabled readers: C and E still count while another block holds them. E is A on a pad, never
    -- LB + A (controller.lua, WhipAcceptJustPressed); C is B on a pad (WhipCancelJustPressed).
    if WhipCancelJustPressed() then                              -- C / B
        finish(st, 'cancel')
    elseif spot and WhipAcceptJustPressed() then                 -- E / A
        st.target = { root = spot.root, floor = spot.floor, heading = st.heading }
        st.pressedFrom = headOf(PlayerPedId())
        st.stage = 'walk'
        ControlBlocks.release('emoteAim')
        ControlBlocks.hold('emoteWalk', WALK_BLOCK)   -- B cancels the walk: never a punch as well
    end
end

-- ---- walking there ----

local function walk(st)
    local ped = PlayerPedId()
    local t = st.target
    local here = GetEntityCoords(ped)
    local metres = dist2(here.x, here.y, t.floor.x, t.floor.y)
    TaskGoStraightToCoord(ped, t.floor.x, t.floor.y, t.floor.z, 1.0, -1, t.heading, 0.0)
    say('Walking there  |  ' .. WhipCancelHint() .. ' Cancel')

    local started = GetGameTimer()
    local deadline = started + math.min(3000 + metres * 1500, 15000)
    local last = here
    local stillSince = nil

    while placing == st do
        Wait(0)
        if PlayerIsDead then return finish(st, 'dead') end
        if WhipCancelJustPressed() then return finish(st, 'cancel') end   -- C / B
        if Emotes.wantsToMove() and GetGameTimer() - started > 300 then return finish(st, 'moved') end

        local now = GetGameTimer()
        if now - (st.lastCheck or 0) >= 100 then
            st.lastCheck = now
            ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            if #(pos - last) > JUMP then return finish(st, 'unreachable') end
            last = pos

            local d = dist2(pos.x, pos.y, t.floor.x, t.floor.y)
            if d <= ARRIVE then return 'arrived' end

            -- Stopped walking: close enough (a bed or table edge is reached from beside it), or not.
            if now - started > 700 and GetEntitySpeed(ped) < 0.05 then
                stillSince = stillSince or now
                if now - stillSince > 500 then
                    if d <= ARRIVE_ENDED then return 'arrived' end
                    return finish(st, 'unreachable')
                end
            else
                stillSince = nil
            end
            if now > deadline then return finish(st, 'unreachable') end
        end
    end
end

--- On arrival: the last checks, then the emote at the ghost's exact spot.
local function settle(st)
    local ped = PlayerPedId()
    local t = st.target
    local pos = GetEntityCoords(ped)
    local chest = t.root + vector3(0.0, 0.0, CHEST)

    if not inSight(st.pressedFrom, chest) or not inSight(headOf(ped), chest) then
        return finish(st, 'blocked')
    end
    local rise = t.root.z - pos.z
    if dist2(pos.x, pos.y, t.root.x, t.root.y) > SHIFT_SIDE or rise > SHIFT_UP or rise < -SHIFT_DOWN then
        return finish(st, 'blocked')
    end

    local cmd = st.def.cmd
    finish(st, 'arrived')
    local ok, why = Emotes.play(cmd, { x = t.root.x, y = t.root.y, z = t.root.z, heading = t.heading })
    if not ok and why then UI.Notify(why, 'error') end
end

-- ---- entry ----

--- Start placing an emote by its /e name. Answers true, or false and why.
---@param cmd string
---@return boolean ok
---@return string|nil why
function Emotes.place(cmd)
    local def = Emotes.get(cmd)
    if not def then return false, ('There is no emote called "%s"'):format(tostring(cmd)) end
    if not def.dict or not (def.loop or def.freeze) then
        return false, "That emote plays where you stand — it can't be placed"
    end
    local why = Emotes.blockedBy()
    if why then return false, why end

    if placing then finish(placing, 'cancel') end
    -- The same moment item placing announces: holster, drop what is carried — and it ends any
    -- emote playing now (client/emotes.lua listens).
    RunClientHook('beforePlaceMode')

    local ped = PlayerPedId()
    local me = GetEntityCoords(ped)
    -- How high a standing root sits above the floor, measured rather than assumed: a ped's
    -- bounding box is not its capsule.
    local rootH = 1.0
    local down, under = ray(me, me - vector3(0.0, 0.0, 3.0), 1, ped)
    if down then rootH = math.max(0.9, math.min(1.1, me.z - under.z)) end

    local st = { def = def, heading = GetEntityHeading(ped), nudge = 0.0, rootH = rootH,
                 stage = 'aim', ghostProps = {} }
    placing = st
    ControlBlocks.hold('emoteAim', AIM_BLOCK)

    CreateThread(function() buildGhost(st) end)
    CreateThread(function()
        while placing == st and st.stage == 'aim' do
            if PlayerIsDead then return finish(st, 'dead') end
            aimFrame(st)
            Wait(0)
        end
        if placing ~= st then return end
        if walk(st) == 'arrived' and placing == st then settle(st) end
    end)
    return true
end

-- Death and logout end it; a restart must not leave a ghost standing in the world.
AddEventHandler('spur_core:player:died', function() Emotes.cancelPlace() end)
AddEventHandler('spur_core:player:logout', function() Emotes.cancelPlace() end)
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and placing then deleteGhost(placing) end
end)
