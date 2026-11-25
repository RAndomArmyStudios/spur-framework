-- ============================================
-- SHAPES — Shared containment maths
-- ============================================
--
-- "Is this point inside that box or polygon", once, for both sides. Properties use it for their
-- spaces: the server to bound furniture and to answer "which property is this", the client to tell
-- a player they have walked into one.
--
-- THE ZONE SYSTEM'S CONVENTIONS, EXACTLY, so a shape here is a shape the zone renderer can draw
-- (see ZonePreview in client/zones.lua) without translation:
--
--   box    { type = 'box',  pos = {x,y,z}, size = {x,y,z}, heading = degrees }
--          pos is the CENTRE, height included: the box runs pos.z - size.z/2 .. pos.z + size.z/2.
--          The box's own X axis points along world (cos h, sin h) — the same way round as a
--          property placement's yaw (shared/property_math.lua), which is what lets a unit's local
--          box become a world box by adding the placement's yaw to its heading.
--   poly   { type = 'poly', points = { {x,y}, ... }, minZ, maxZ }
--          winding-number containment on the points, between minZ and maxZ.
--
-- WHY NOT JUST USE ZONES. A zone registered on a client is reported to the server, which caps a
-- player at 500 of them (server/zones.lua) — a tower of properties would be partly dropped and would
-- flood the server at every login — and the zone editor draws every zone it can find. Properties
-- need the maths, not the registry. The zone system still carries its own copy of these two tests
-- (client/zones.lua, server/zones.lua); moving it onto this file is a separate change.

Shapes = {}

local sqrt, abs, huge = math.sqrt, math.abs, math.huge
local rad, cos, sin = math.rad, math.cos, math.sin

--- Winding number: non-zero means inside. The same algorithm, and the same edge rules, as the
--- zone system's, so a polygon drawn in the zone editor contains exactly the same points here.
local function windingNumber(points, px, py)
    local wn = 0
    local n = #points
    for i = 1, n do
        local a, b = points[i], points[(i % n) + 1]
        local x1, y1, x2, y2 = a.x, a.y, b.x, b.y
        if y1 <= py then
            if y2 > py and (x2 - x1) * (py - y1) - (px - x1) * (y2 - y1) > 0 then wn = wn + 1 end
        elseif y2 <= py and (x2 - x1) * (py - y1) - (px - x1) * (y2 - y1) < 0 then
            wn = wn - 1
        end
    end
    return wn
end

--- Distance from a point to a segment, on the ground plane. Only used for a polygon's slack.
local function segmentDistance(px, py, x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    local len2 = dx * dx + dy * dy
    local t = 0.0
    if len2 > 0 then
        t = ((px - x1) * dx + (py - y1) * dy) / len2
        if t < 0 then t = 0 elseif t > 1 then t = 1 end
    end
    local cx, cy = x1 + dx * t - px, y1 + dy * t - py
    return sqrt(cx * cx + cy * cy)
end

--- The four ground-plane corners of a box, in order round it.
---@return table corners  { {x,y}, {x,y}, {x,y}, {x,y} }
function Shapes.boxCorners(box)
    local h = rad(box.heading or 0.0)
    local c, s = cos(h), sin(h)
    local hx, hy = box.size.x * 0.5, box.size.y * 0.5
    local px, py = box.pos.x, box.pos.y
    local out = {}
    for i, sgn in ipairs({ { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } }) do
        local lx, ly = hx * sgn[1], hy * sgn[2]
        out[i] = { x = px + lx * c - ly * s, y = py + lx * s + ly * c }
    end
    return out
end

--- A world-space shape made ready for containment: trig and bounds worked out once.
---
--- RETURNS A NEW TABLE and leaves the input alone, because the input is usually a stored record,
--- and caches written onto it would travel wherever that record is sent next.
---@param shape table  a world box or poly
---@return table|nil prepared, string|nil err
function Shapes.prepare(shape)
    if type(shape) ~= 'table' then return nil, 'not a shape' end

    if shape.type == 'box' then
        local p, s = shape.pos, shape.size
        if not (p and s) then return nil, 'box needs pos and size' end
        local out = {
            type = 'box',
            pos = { x = p.x, y = p.y, z = p.z },
            size = { x = s.x, y = s.y, z = s.z },
            heading = shape.heading or 0.0,
        }
        local h = rad(out.heading)
        out._cosH, out._sinH = cos(h), sin(h)
        local minX, minY, maxX, maxY = huge, huge, -huge, -huge
        for _, c in ipairs(Shapes.boxCorners(out)) do
            if c.x < minX then minX = c.x end
            if c.x > maxX then maxX = c.x end
            if c.y < minY then minY = c.y end
            if c.y > maxY then maxY = c.y end
        end
        out._bbox = { minX = minX, minY = minY, maxX = maxX, maxY = maxY,
                      minZ = p.z - s.z * 0.5, maxZ = p.z + s.z * 0.5 }
        return out
    end

    if shape.type == 'poly' then
        local pts = shape.points
        if type(pts) ~= 'table' or #pts < 3 then return nil, 'poly needs at least 3 points' end
        if not (shape.minZ and shape.maxZ) then return nil, 'poly needs minZ and maxZ' end
        local out = { type = 'poly', points = {}, minZ = shape.minZ, maxZ = shape.maxZ }
        local minX, minY, maxX, maxY = huge, huge, -huge, -huge
        for i = 1, #pts do
            local x, y = pts[i].x or pts[i][1], pts[i].y or pts[i][2]
            out.points[i] = { x = x, y = y }
            if x < minX then minX = x end
            if x > maxX then maxX = x end
            if y < minY then minY = y end
            if y > maxY then maxY = y end
        end
        out._bbox = { minX = minX, minY = minY, maxX = maxX, maxY = maxY,
                      minZ = shape.minZ, maxZ = shape.maxZ }
        return out
    end

    return nil, 'unknown shape type ' .. tostring(shape.type)
end

--- Is the point inside this PREPARED shape?
---
--- `slack` widens the shape by that many metres on every side, vertically as well, for the
--- places a hard edge would be wrong — a chair whose origin sits a few centimetres past a wall it is
--- pushed up against is still in the room.
---@param s table   prepared shape
---@param slack number|nil  metres, default 0
---@return boolean
function Shapes.contains(s, x, y, z, slack)
    slack = slack or 0.0
    local b = s._bbox
    if x < b.minX - slack or x > b.maxX + slack or y < b.minY - slack or y > b.maxY + slack
        or z < b.minZ - slack or z > b.maxZ + slack then
        return false
    end

    if s.type == 'box' then
        local dx, dy = x - s.pos.x, y - s.pos.y
        local lx = dx * s._cosH + dy * s._sinH
        local ly = -dx * s._sinH + dy * s._cosH
        return abs(lx) <= s.size.x * 0.5 + slack and abs(ly) <= s.size.y * 0.5 + slack
    end

    -- A polygon: inside by winding, or within `slack` of one of its edges.
    if windingNumber(s.points, x, y) ~= 0 then return true end
    if slack <= 0 then return false end
    local pts, n = s.points, #s.points
    for i = 1, n do
        local a, c = pts[i], pts[(i % n) + 1]
        if segmentDistance(x, y, a.x, a.y, c.x, c.y) <= slack then return true end
    end
    return false
end

--- Inside any of a list of prepared shapes?
---@return boolean, number|nil index
function Shapes.containsAny(list, x, y, z, slack)
    for i = 1, #list do
        if Shapes.contains(list[i], x, y, z, slack) then return true, i end
    end
    return false, nil
end

--- The bounds of a list of prepared shapes.
---@return table|nil { minX, minY, minZ, maxX, maxY, maxZ }
function Shapes.bbox(list)
    if #list == 0 then return nil end
    local out = { minX = huge, minY = huge, minZ = huge, maxX = -huge, maxY = -huge, maxZ = -huge }
    for i = 1, #list do
        local b = list[i]._bbox
        if b.minX < out.minX then out.minX = b.minX end
        if b.minY < out.minY then out.minY = b.minY end
        if b.minZ < out.minZ then out.minZ = b.minZ end
        if b.maxX > out.maxX then out.maxX = b.maxX end
        if b.maxY > out.maxY then out.maxY = b.maxY end
        if b.maxZ > out.maxZ then out.maxZ = b.maxZ end
    end
    return out
end

--- Floor area in square metres, for the Configurator's readout. Works on any box or poly, local or
--- world — area does not change with a rotation.
---@return number
function Shapes.area(shape)
    if shape.type == 'box' then return shape.size.x * shape.size.y end
    if shape.type == 'poly' then
        local pts, n, sum = shape.points, #shape.points, 0.0
        for i = 1, n do
            local a, b = pts[i], pts[(i % n) + 1]
            sum = sum + (a.x or a[1]) * (b.y or b[2]) - (b.x or b[1]) * (a.y or a[2])
        end
        return abs(sum) * 0.5
    end
    return 0.0
end
