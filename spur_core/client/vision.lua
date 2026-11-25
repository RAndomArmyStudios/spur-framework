-- ============================================
-- VISION — what a guard sees (client): this player's half
-- ============================================
--
-- The server works out which guards have this player in their cone and range, and keeps the meter
-- (server/vision.lua). This game does two things for it:
--
--   LOOKING   for each guard on the list the server sends (spur_core:client:visionLook, numbered), is there
--             anything between its eyes and this player's head or chest: a wall, a car, a bush? Asked four
--             times a second while the list has anyone on it, two rays a guard (synchronous: a list is short,
--             24 at most). Said to the server (spur_core:server:visionSeen) as one bit a guard, with whether
--             this player is sneaking, on every change and once a second. A guard this game does not have
--             (too far to be streamed in) is not in sight.
--   MARKS     over each guard near this player that is noticing someone (spur_core:client:visionMarks): one
--             browser paints them all (html/vision3d/marks.html), one cell a guard, and each cell is drawn on
--             its guard's head by the engine every frame (WorldQuad), so it never lags and a wall hides it.
--             The browser is made the first time a mark shows, and given back a minute after the last one goes.
--
-- No Wait(0) unless a mark is up: the draw loop ends with the last one.

local HEAD, CHEST = 31086, 24818    -- SKEL_Head, SKEL_Spine3
local LOOK_MS     = 250
local SAY_MS      = 1000            -- the same answer is said again this often (the server forgets one after 1.5 s)
local CELLS       = 8
local CELL        = 256
local SIZE_M      = 0.50            -- a mark's size in the world
local ABOVE_M     = 0.64            -- how far over the guard's head (its centre: half its size clear of the head)
local TXD, TEX    = 'whip_vision_txd', 'marks'

-- What a ray stops at: the map, objects and bushes, and cars (not this player's own: they look out of it).
-- Passed over (the options): glass, what can be seen through (a wire fence) and what has no collision, so a
-- guard sees through a window.
local SIGHT_WORLD   = 1 | 16 | 256
local SIGHT_CARS    = 2
local SIGHT_OPTIONS = 1 | 2 | 4

local list = { ver = 0, nets = {} }
local looking = false
local said = { mask = -1, sneak = nil, at = 0, ver = -1 }

--- Is the line from `a` to `b` clear (nothing it stops at in between)?
local function clear(a, b, flags, ignore)
    local h = StartExpensiveSynchronousShapeTestLosProbe(a.x, a.y, a.z, b.x, b.y, b.z, flags, ignore, SIGHT_OPTIONS)
    local _, hit = GetShapeTestResult(h)
    return not (hit == 1 or hit == true)
end

local function lookLoop()
    if looking then return end
    looking = true
    CreateThread(function()
        while #list.nets > 0 do
            local me = PlayerPedId()
            local head = GetPedBoneCoords(me, HEAD, 0.0, 0.0, 0.0)
            local chest = GetPedBoneCoords(me, CHEST, 0.0, 0.0, 0.0)
            local flags = IsPedInAnyVehicle(me, false) and SIGHT_WORLD or (SIGHT_WORLD | SIGHT_CARS)
            local mask = 0
            for i, net in ipairs(list.nets) do
                if NetworkDoesNetworkIdExist(net) then
                    local ped = NetworkGetEntityFromNetworkId(net)
                    if ped ~= 0 and DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
                        local eye = GetPedBoneCoords(ped, HEAD, 0.0, 0.0, 0.0)
                        if clear(eye, head, flags, ped) or clear(eye, chest, flags, ped) then
                            mask = mask | (1 << (i - 1))
                        end
                    end
                end
            end
            local st = GetPedStealthMovement(me)
            local sneak = st == true or st == 1
            local now = GetGameTimer()
            if mask ~= said.mask or sneak ~= said.sneak or list.ver ~= said.ver or now - said.at >= SAY_MS then
                said.mask, said.sneak, said.ver, said.at = mask, sneak, list.ver, now
                TriggerServerEvent('spur_core:server:visionSeen', list.ver, mask, sneak)
            end
            Wait(LOOK_MS)
        end
        looking = false
    end)
end

RegisterNetEvent('spur_core:client:visionLook', function(ver, nets)
    if type(ver) ~= 'number' or type(nets) ~= 'table' then return end
    local out = {}
    for _, n in ipairs(nets) do if type(n) == 'number' then out[#out + 1] = n end end
    list = { ver = ver, nets = out }
    if #out > 0 then lookLoop() end
end)

-- ============================================
-- The marks
-- ============================================

local FADE_MS = 350   -- a mark going away is drawn this long more: the page shrinks it (marks.html)
local IDLE_MS = 60000 -- the marks' and the cone's browsers given back this long after they were last drawn

local marks = {}      -- [netId] = { cell, m, o, s, untilMs = while it fades }
local cellOf = {}     -- [cell] = netId
local drawing = false

local marksPage = DuiPage.new({
    name = 'vision', url = ('vision3d/marks.html?s=%d&cells=%d'):format(CELL, CELLS), width = CELL, height = CELL * CELLS,
    txd = TXD, tex = TEX, idleMs = IDLE_MS, without = 'guard marks will not draw',
    -- (Given back only once no mark is left; a mark still listed is painted again on the next push.)
    onGone = function()
        for _, mk in pairs(marks) do mk.m, mk.o, mk.s = nil, nil, nil end
    end,
})

local function freeCell()
    for c = 1, CELLS do if not cellOf[c] then return c end end
    return nil
end

local function drawLoop()
    if drawing then return end
    drawing = true
    CreateThread(function()
        while next(marks) do
            local now = GetGameTimer()
            for net, mk in pairs(marks) do
                if mk.untilMs and now >= mk.untilMs then
                    marks[net] = nil
                    cellOf[mk.cell] = nil
                end
            end
            -- Kept while any mark is listed; given back IDLE_MS after the last one.
            marksPage:used()
            if marksPage:up() then
                local rx, ry, rz, ux, uy, uz = WorldQuad.billboardBasis()
                for net, mk in pairs(marks) do
                    if NetworkDoesNetworkIdExist(net) then
                        local ped = NetworkGetEntityFromNetworkId(net)
                        if ped ~= 0 and DoesEntityExist(ped) then
                            local head = GetPedBoneCoords(ped, HEAD, 0.0, 0.0, 0.0)
                            WorldQuad.draw(TXD, TEX, head.x, head.y, head.z + ABOVE_M,
                                rx, ry, rz, ux, uy, uz, SIZE_M, SIZE_M,
                                0.0, (mk.cell - 1) / CELLS, 1.0, mk.cell / CELLS,
                                255, 255, 255, 255)
                        end
                    end
                end
            end
            Wait(0)
        end
        drawing = false
    end)
end

-- Every guard near this player that is noticing someone: { [netId as text] = { m, o, s } }. One left out is calm again.
RegisterNetEvent('spur_core:client:visionMarks', function(got)
    if type(got) ~= 'table' then return end
    local keep = {}
    for k, e in pairs(got) do
        local net = tonumber(k)
        if net and type(e) == 'table' then
            keep[net] = true
            local mk = marks[net]
            if mk and mk.untilMs then mk.untilMs, mk.m = nil, nil end   -- (back while it faded: shown again)
            if not mk then
                local c = freeCell()
                if c then
                    marksPage:ensure()
                    mk = { cell = c }
                    marks[net] = mk
                    cellOf[c] = net
                end
            end
            if mk then
                local m, o = tonumber(e.m) or 0, tonumber(e.o) or 0
                local s = type(e.s) == 'string' and e.s or ''
                if mk.m ~= m or mk.o ~= o or mk.s ~= s then
                    mk.m, mk.o, mk.s = m, o, s
                    marksPage:send({ cell = mk.cell - 1, m = m, o = o, s = s })
                end
            end
        end
    end
    local now = GetGameTimer()
    for net, mk in pairs(marks) do
        if not keep[net] and not mk.untilMs then
            mk.untilMs = now + FADE_MS   -- (the draw loop frees its cell after)
            marksPage:send({ cell = mk.cell - 1, off = true })
        end
    end
    if next(marks) then drawLoop() end
end)

-- ============================================
-- A guard's cone in the world builder
-- ============================================
--
-- The selected guard's Sees players, laid on the ground round it (client/furnish_builder.lua calls VisionCone.draw
-- every frame while one is selected). One more browser paints it (html/vision3d/cone.html), again only when a
-- setting changes, and is given back a minute after the last cone; the engine lays it over the ground in a grid of
-- patches, each corner at the ground's own
-- height, so it follows a slope or a kerb instead of cutting into it. The heights are looked up again when the
-- guard moves, turns or its range changes, at most every 150 ms.

VisionCone = {}

local CONE_PX    = 1024
local CONE_TXD, CONE_TEX = 'whip_vision_cone_txd', 'cone'
local GRID       = 6          -- patches a side
local NEAR_M     = 2.5        -- server/vision.lua's: it notices you this close whichever way it faces
local LIFT_M     = 0.06       -- over the ground, so it is not lost in it
local GROUND_MS  = 150

-- What the page was last told (range, cone, sneak, spotS, farS), nil before it was; and where the ground was last read
-- for (x, y, z, heading, range). Numbers compared as they are, never written out: this runs every frame.
local coneSent = nil
local heights = { kx = nil, ky = 0.0, kz = 0.0, kh = 0.0, kr = 0.0, at = -1e9, dz = {} }   -- each corner's ground, over or under the guard's
local corners = {}                                  -- [index] = { x, y, z }, reused frame to frame
for n = 0, (GRID + 1) * (GRID + 1) - 1 do corners[n] = { x = 0.0, y = 0.0, z = 0.0 } end

local conePage = DuiPage.new({
    name = 'vision', url = ('vision3d/cone.html?s=%d'):format(CONE_PX), width = CONE_PX, height = CONE_PX,
    txd = CONE_TXD, tex = CONE_TEX, idleMs = IDLE_MS, without = 'the guard cone will not draw',
    -- A new browser is told the settings again.
    onGone = function() coneSent = nil end,
})

--- The ground's height at (x, y), looked for from a little over `refZ` (under a ceiling, not on its roof).
local function groundAt(x, y, refZ)
    local found, z = GetGroundZFor_3dCoord(x, y, refZ + 1.5, false)
    if found and z > refZ - 6.0 then return z end
    return refZ
end

--- Draw a guard's cone this frame: round (x, y, z), facing `heading` (GTA's degrees). `v` is its extra.vision:
--- { range, cone, spotS, farS, sneak } (client/director.lua extraOf).
function VisionCone.draw(x, y, z, heading, v)
    if type(v) ~= 'table' then return end
    if not conePage:ensure() then return end
    local range = tonumber(v.range) or 20.0
    local cone, sneak, spotS, farS = tonumber(v.cone) or 100, v.sneak ~= false, tonumber(v.spotS) or 2, tonumber(v.farS) or 8
    local s = coneSent
    if not s or s[1] ~= range or s[2] ~= cone or s[3] ~= sneak or s[4] ~= spotS or s[5] ~= farS then
        coneSent = { range, cone, sneak, spotS, farS }
        conePage:send({ range = range, cone = cone, near = NEAR_M, sneak = sneak, spotS = spotS, farS = farS }, 'settings')
    end
    if not conePage:up() then return end

    -- The patches' corners: across (i) from its left to its right, along (j) from ahead of it to behind. Where
    -- they are follows the guard every frame; the ground's heights under them at most every GROUND_MS (in
    -- between, the last ones, carried with it while it is dragged or turned).
    local h = math.rad(heading or 0.0)
    local rx, ry = math.cos(h), math.sin(h)       -- its right
    local fx, fy = -math.sin(h), math.cos(h)      -- the way it faces
    local refZ = groundAt(x, y, z - 1.0)
    local now = GetGameTimer()
    -- (Moved: a tenth of a metre, half a degree, as the ground was read for.)
    local hd = heading or 0.0
    local moved = heights.kx == nil or math.abs(x - heights.kx) >= 0.05 or math.abs(y - heights.ky) >= 0.05
        or math.abs(z - heights.kz) >= 0.05 or math.abs(hd - heights.kh) >= 0.5 or math.abs(range - heights.kr) >= 0.05
    local look = moved and now - heights.at >= GROUND_MS
    if look then heights.kx, heights.ky, heights.kz, heights.kh, heights.kr, heights.at = x, y, z, hd, range, now end
    for j = 0, GRID do
        for i = 0, GRID do
            local n = j * (GRID + 1) + i
            local a, b = -range + 2 * range * i / GRID, range - 2 * range * j / GRID
            local c = corners[n]
            c.x, c.y = x + rx * a + fx * b, y + ry * a + fy * b
            if look then heights.dz[n] = groundAt(c.x, c.y, refZ) - refZ end
            c.z = refZ + (heights.dz[n] or 0.0) + LIFT_M
        end
    end
    for j = 0, GRID - 1 do
        for i = 0, GRID - 1 do
            local tl, tr = corners[j * (GRID + 1) + i], corners[j * (GRID + 1) + i + 1]
            local bl, br = corners[(j + 1) * (GRID + 1) + i], corners[(j + 1) * (GRID + 1) + i + 1]
            WorldQuad.drawCorners(CONE_TXD, CONE_TEX, tl, tr, bl, br,
                i / GRID, j / GRID, (i + 1) / GRID, (j + 1) / GRID, 255, 255, 255, 255)
        end
    end
end
