--[[
    spur_rope — HOW THE ROPE IS DRAWN, BEYOND A PROP PER NODE

    'segments': one rope piece per gap between two points (the nodes, or the spline's samples).
    The piece is spur_rope_seg (docs/spur_rope_seg.txt): a capsule SegmentLength (0.25 m) long on its
    own +Y, centred on its origin. Each frame SetEntityMatrix puts it
      * at the middle of the two points,
      * with +Y along the gap, scaled to the gap's length (a stretched rope stretches its pieces).
        With no overlap the rounded caps sit on the nodes, so neighbours meet and the strands line up;
        overlap puts lumps on bends,
      * with X and Z scaled by the thickness, both equally (unequal scaling breaks the lighting).

    The roll is carried from piece to piece (a rotation-minimising frame), so the strand twist runs
    across joints instead of jumping.

    RedM (spur_rope, 24 Nov 2026): 'segments' can't be drawn on RedM. spur_rope_seg is an original-game model (kept outside the
    resource) and RedM has no SetEntityMatrix to place and scale a piece. client/visuals.lua draws 'rdr' instead
    (RDR2's own rope, pinned along ours, below). The pieces' code stays for a game that has both.
]]

Rope.Mesh = {}

local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
local function cross(a, b)
    return vector3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
end

local WORLD_UP = vector3(0.0, 0.0, 1.0)
local WORLD_X = vector3(1.0, 0.0, 0.0)

--- A first "right" square to `t`: across it, level with the ground (or along X for a rope hanging
--- straight down).
local function startRight(t)
    local r = cross(t, WORLD_UP)
    local len = #r
    if len < 1e-4 then
        r = cross(t, WORLD_X)
        len = #r
    end
    return r / len
end

--- Every piece's matrix along `points` (vector3s, in order), into `out[k]` = { f, r, u, at } with the
--- scales applied: f along the gap, as (its length + overlap) / the model's own length; r and u the
--- thickness (the SAME on both, or the model's lighting bends). Pure: no natives.
---@param points vector3[]
---@param thickness number    scale on the model's own X and Z
---@param overlap number      metres added to each piece's length
---@param modelLength number  the model's own length along +Y (metres)
function Rope.Mesh.Frames(points, thickness, overlap, out, modelLength)
    out = out or {}
    modelLength = modelLength or 1.0
    local right, lastT = nil, vector3(0.0, 1.0, 0.0)
    for k = 1, #points - 1 do
        local a, b = points[k], points[k + 1]
        local d = b - a
        local len = #d
        -- Two points on top of each other: the piece keeps the last one's way
        local t = len > 1e-5 and d / len or lastT
        lastT = t
        -- Carry the last right on: take away its part along the new gap
        if right then
            local r = right - t * dot(right, t)
            local rl = #r
            right = rl > 1e-4 and r / rl or startRight(t)
        else
            right = startRight(t)
        end
        local up = cross(right, t)
        local f = out[k] or {}
        f.f = t * ((len + overlap) / modelLength)
        f.r = right * thickness
        f.u = up * thickness
        f.at = (a + b) * 0.5
        out[k] = f
    end
    for k = #points, #out do out[k] = nil end
    return out
end

-- ============================================================================
-- THE PIECES ON THIS GAME
-- ============================================================================

--- The pieces for a rope, of `model` (loaded already: client/visuals.lua's Rope.LoadLook).
function Rope.Mesh.Create(rope, pointCount, model)
    rope.segments = {}
    rope.segmentFrames = {}
    rope.segmentLast = nil
    rope.segmentModel = model
    local at = rope.nodes[1].position
    for _ = 1, pointCount - 1 do
        local prop = CreateObject(model, at.x, at.y, at.z, false, false, false)
        if DoesEntityExist(prop) then
            SetEntityCollision(prop, false, false)
            FreezeEntityPosition(prop, true)
            SetEntityLodDist(prop, 500)
            rope.segments[#rope.segments + 1] = prop
        end
    end
end

--- Deletes only our own pieces (checked by the model they were made with, which the shadows setting may
--- have changed since), never whatever a stale handle now names.
function Rope.Mesh.Delete(rope)
    local model = rope.segmentModel
    for _, prop in ipairs(rope.segments or {}) do
        if DoesEntityExist(prop) and GetEntityModel(prop) == model then DeleteEntity(prop) end
    end
    rope.segments = {}
    rope.segmentLast = nil
end

-- ============================================================================
-- RDR2'S OWN ROPE, PINNED ALONG OURS (Config.Visuals.Style = 'rdr')
-- ============================================================================
-- RedM (spur_rope, 24 Nov 2026): whip_rope pinned one of the original game's ropes along ours. RDR2 has ropes too (ADD_ROPE,
-- types 0-18 in ropedata.xml; 0, 15 and 18 hang like a rope), but no ROPE_LOAD_TEXTURES, no
-- ROPE_SET_UPDATE_PINVERTS and no named PIN_ROPE_VERTEX. 0xE54BF2CE6C7D23A9 is unnamed in RDR2's native list and has
-- PIN_ROPE_VERTEX's shape (rope, vertex, x, y, z), so it pins here. That is a guess, so the first rope checks it:
-- its end vertices read back (GET_ROPE_VERTEX_COORD) must sit on their pins, or ropes are drawn as props ('balls')
-- from then on, said once in the console. One continuous rope, no props or seams, and no physics of its own:
-- drawing only; our simulation and sync are unchanged.
-- Tested in game (24 Nov 2026): the pins hold (ends 0.00 m off), but RDR2 made rope type 0 with only 2 vertices, so one
-- rope draws as a straight line. A type with 2 vertices is drawn as a chain instead: short ropes end to end along ours,
-- each pinned at both ends (CHAIN_PIECE apart, at most CHAIN_MAX of them). /ropevertices (client/main.lua) prints how
-- many vertices RDR2 gives each type.

local PIN_ROPE_VERTEX = 0xE54BF2CE6C7D23A9
local PIN_MISS = 0.25        -- metres: an end vertex this far from its pin is a pin that did not hold
local CHECK_AT = { 20, 60 }  -- the updates (frames) a new rope's pins are read back at; failing both = dead
local CHAIN_PIECE = 0.4      -- metres: a chain's pieces are about this long...
local CHAIN_MAX = 16         -- ...and a rope has at most this many (each is one of RDR2's ropes)

Rope.Mesh.Rdr = { dead = false, verified = false, chainSaid = false }

--- Whether RDR2's rope may be used (not found wanting by an earlier rope's check).
function Rope.Mesh.RdrUsable()
    return not Rope.Mesh.Rdr.dead
end

--- The point `s` metres along `points` (cum: the running lengths), walking on from index `k`.
local function along(points, cum, s, k)
    local n = #points
    while k < n - 1 and cum[k + 1] < s do k = k + 1 end
    local seg = cum[k + 1] - cum[k]
    local t = seg > 1e-6 and (s - cum[k]) / seg or 0.0
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    return points[k] + (points[k + 1] - points[k]) * t, k
end
Rope.Mesh.Along = along

--- One of RDR2's ropes, `len` metres of `ropeType`, at `a`: its handle, or nil.
local function addRope(a, len, ropeType)
    len = len + 0.0
    -- RDR2's ADD_ROPE: the original game's arguments, its unkPtr filled in by RedM, and one more BOOL (p17) at the end
    local ok, handle = pcall(AddRope, a.x, a.y, a.z, 0.0, 0.0, 0.0, len, ropeType or 0,
        len, 0.5, 0.0, false, false, false, 1.0, false, false)
    if not ok or not handle or handle == 0 or not DoesRopeExist(handle) then
        Rope.Util.DebugPrint('RDR2 would not make a rope of type', ropeType, ok and '' or tostring(handle))
        return nil
    end
    return handle
end

--- RDR2's rope of `ropeType` for one of ours.
function Rope.Mesh.CreateRdr(rope, ropeType)
    if Rope.Mesh.Rdr.dead then return false end
    local len = (#rope.nodes - 1) * Rope.LinkLength(rope)
    local handle = addRope(rope.nodes[1].position, len, ropeType)
    if not handle then return false end
    rope.rdrRope = handle
    rope.rdrType = ropeType or 0
    rope.rdrChain = nil
    rope.rdrUpdates = 0
    rope.rdrMisses = 0
    return true
end

function Rope.Mesh.DeleteRdr(rope)
    local handle = rope.rdrRope
    rope.rdrRope = nil
    for i, h in ipairs(rope.rdrChain or {}) do
        if i > 1 and DoesRopeExist(h) then DeleteRope(h) end   -- [1] is rdrRope itself, below
    end
    rope.rdrChain = nil
    if handle and DoesRopeExist(handle) then DeleteRope(handle) end
end

--- The chain for a rope whose type RDR2 gives only 2 vertices: its first rope and more of the same type, one per
--- CHAIN_PIECE of `total`. Fewer if RDR2 will make no more.
local function startChain(rope, total)
    local want = math.max(2, math.min(CHAIN_MAX, math.floor(total / CHAIN_PIECE + 0.5)))
    local chain = { rope.rdrRope }
    local at = rope.nodes[1].position
    for _ = 2, want do
        local h = addRope(at, total / want, rope.rdrType)
        if not h then break end
        chain[#chain + 1] = h
    end
    rope.rdrChain = chain
    if not Rope.Mesh.Rdr.chainSaid then
        Rope.Mesh.Rdr.chainSaid = true
        print(('[spur_rope] RedM: RDR2 gives rope type %d 2 vertices: a rope is drawn as a chain of %d short ones')
            :format(rope.rdrType or 0, #chain))
    end
end

--- Reads back a new rope's end vertices once its pins have had time to hold (`h0`'s vertex 0 and `h1`'s vertex `last1`).
--- Two misses: RDR2's rope does not follow the pin native, so every rope is drawn as props from now on.
local function checkPins(rope, h0, h1, last1, first, last)
    local n = rope.rdrUpdates
    if Rope.Mesh.Rdr.verified or (n ~= CHECK_AT[1] and n ~= CHECK_AT[2]) then return end
    local v0 = GetRopeVertexCoord(h0, 0)
    local vn = GetRopeVertexCoord(h1, last1)
    local miss = math.max(v0 and #(v0 - first) or 999.0, vn and #(vn - last) or 999.0)
    if miss <= PIN_MISS then
        Rope.Mesh.Rdr.verified = true
        print(('[spur_rope] RedM: RDR2\'s rope follows its pins (%d vertices, %.2f m off at most)'):format(last1 + 1, miss))
        return
    end
    rope.rdrMisses = (rope.rdrMisses or 0) + 1
    if rope.rdrMisses < #CHECK_AT then return end
    Rope.Mesh.Rdr.dead = true
    print(('^3[spur_rope] RedM: RDR2\'s rope did not follow its pins (an end %.2f m off): ropes are drawn as props^7')
        :format(miss))
    -- Every rope again in the look there is now (not from inside the frame loop that called us)
    CreateThread(function() Rope.RedrawRopes() end)
end

--- Every frame: each of RDR2's rope vertices onto ours, spaced evenly along its length (or, for a chain, each piece's
--- two ends onto ours, the pieces end to end).
function Rope.Mesh.UpdateRdr(rope, points)
    local handle = rope.rdrRope
    if not handle or #points < 2 then return end
    local cum = rope.rdrCum or {}
    cum[1] = 0.0
    for k = 2, #points do cum[k] = cum[k - 1] + #(points[k] - points[k - 1]) end
    for k = #points + 1, #cum do cum[k] = nil end
    rope.rdrCum = cum
    local total = cum[#points]
    local N = Citizen.InvokeNative
    local chain = rope.rdrChain
    if not chain then
        local count = GetRopeVertexCount(handle)
        if not count or count < 2 then return end
        if count == 2 and #points > 2 then
            startChain(rope, total)
            chain = rope.rdrChain
        else
            local k = 1
            for v = 0, count - 1 do
                local p
                p, k = along(points, cum, total * v / (count - 1), k)
                N(PIN_ROPE_VERTEX, handle, v, p.x, p.y, p.z)
            end
            rope.rdrUpdates = (rope.rdrUpdates or 0) + 1
            checkPins(rope, handle, handle, count - 1, points[1], points[#points])
            return
        end
    end
    local pieces = #chain
    local prev, k = points[1], 1
    for i = 1, pieces do
        local p
        p, k = along(points, cum, total * i / pieces, k)
        local h = chain[i]
        N(PIN_ROPE_VERTEX, h, 0, prev.x, prev.y, prev.z)
        N(PIN_ROPE_VERTEX, h, 1, p.x, p.y, p.z)
        prev = p
    end
    rope.rdrUpdates = (rope.rdrUpdates or 0) + 1
    checkPins(rope, chain[1], chain[pieces], 1, points[1], points[#points])
end

--- spur_rope stopping: RDR2 loads no rope textures, so nothing to let go.
function Rope.Mesh.ReleaseRdr() end

local MOVE_EPS = 0.01   -- a piece whose two ends moved less than this keeps its matrix

--- Every frame: each piece onto its gap.
function Rope.Mesh.Update(rope, points)
    local segs = rope.segments
    if not segs or #segs == 0 then return end
    if not SetEntityMatrix then return end   -- RedM (spur_rope, 24 Nov 2026): no SetEntityMatrix (see the top)
    rope.segmentLast = rope.segmentLast or {}
    local last = rope.segmentLast
    -- A rope lying still: skip working out the frames at all
    local any = false
    for k = 1, math.min(#segs, #points - 1) do
        local l = last[k]
        if not l or #(l.a - points[k]) > MOVE_EPS or #(l.b - points[k + 1]) > MOVE_EPS then
            any = true
            break
        end
    end
    if not any then return end
    -- A rope with its own look keeps that look's thickness (its piece is made at its size: a pump's hose)
    local look = rope.opts and rope.opts.look
    local thickness = look and (look.thickness or 1.0) or Config.Visuals.SegmentThickness or 1.0
    local frames = Rope.Mesh.Frames(points, thickness,
        Config.Visuals.SegmentOverlap or 0.0, rope.segmentFrames, Config.Visuals.SegmentLength or 0.25)
    rope.segmentFrames = frames
    for k, prop in ipairs(segs) do
        local fr = frames[k]
        if fr then
            local a, b = points[k], points[k + 1]
            local l = last[k]
            if not l or #(l.a - a) > MOVE_EPS or #(l.b - b) > MOVE_EPS then
                SetEntityMatrix(prop, fr.f.x, fr.f.y, fr.f.z, fr.r.x, fr.r.y, fr.r.z,
                    fr.u.x, fr.u.y, fr.u.z, fr.at.x, fr.at.y, fr.at.z)
                if l then l.a, l.b = a, b else last[k] = { a = a, b = b } end
            end
        end
    end
end
