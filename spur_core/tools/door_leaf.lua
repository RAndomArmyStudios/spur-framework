-- ============================================
-- DoorLeaf — a door lit up in the world
-- ============================================
--
-- THE DOOR ITSELF LIGHTS UP. One drawing for both tools/property_wizard.lua's door picker and tools/zones.lua's
-- Door Editor.
--
--   DoorLeaf.box(model)                       its model's box { mn, mx }, or nil while the game has none for it
--   DoorLeaf.body(model, x, y, z, heading)    its middle, top, bottom and width in the world
--   DoorLeaf.entity(slot, model, x, y, z)     its object, found by model where it stands and kept in `slot`
--                                             (slot.entity, slot.lookAt), or nil while it is not streamed in
--   DoorLeaf.draw(model, ent, x, y, z, heading, rgb, fill, edge)
--                                             a wash of `rgb` on each face, just off it (a wash inside the leaf is
--                                             hidden by it), and an edge round it: on the object as it stands
--                                             (open or shut), else where it was found
--   DoorLeaf.outliner()                       the white outline, on one object at a time: o.set(ent), o.set(nil)
--
-- Nothing here touches the door: it is drawn on, never opened, locked or moved.

DoorLeaf = {}

local DEFAULT_MN = { x = -0.5, y = -0.05, z = 0.0 }
local DEFAULT_MX = { x = 0.5, y = 0.05, z = 2.1 }
local BOX_RETRY_MS = 5000   -- a model with no box yet (not known to the game) is asked again after this

local boxOf = {}   -- model -> { mn, mx } | { missUntil }

function DoorLeaf.box(model)
    local b = boxOf[model]
    if b and b.mn then return b end
    local now = GetGameTimer()
    if b and b.missUntil > now then return nil end
    local mn, mx = GetModelDimensions(model)
    if mn and mx and (mx.x - mn.x) > 0.01 then
        b = { mn = mn, mx = mx }
        boxOf[model] = b
        return b
    end
    boxOf[model] = { missUntil = now + BOX_RETRY_MS }
    return nil
end

function DoorLeaf.body(model, x, y, z, heading)
    local b = DoorLeaf.box(model)
    if not b then
        return { x = x, y = y, z = z + 1.0, top = z + 2.1, bottom = z, width = 1.0 }
    end
    local mn, mx = b.mn, b.mx
    local cx, cy, cz = (mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5, (mn.z + mx.z) * 0.5
    local h = math.rad(heading or 0.0)
    local c, s = math.cos(h), math.sin(h)
    return {
        x = x + cx * c - cy * s, y = y + cx * s + cy * c, z = z + cz,
        top = z + mx.z, bottom = z + mn.z, width = mx.x - mn.x,
    }
end

--- Kept while it is that door; looked for again at most once a second while it is not there.
function DoorLeaf.entity(slot, model, x, y, z)
    local e = slot.entity
    if e and e ~= 0 and DoesEntityExist(e)
        and PropertyMath.signedHash(GetEntityModel(e)) == PropertyMath.signedHash(model) then
        return e
    end
    slot.entity = nil
    local now = GetGameTimer()
    if (slot.lookAt or 0) > now then return nil end
    slot.lookAt = now + 1000
    local obj = GetClosestObjectOfType(x + 0.0, y + 0.0, z + 0.0, 0.75, model, false, false, false)
    if obj and obj ~= 0 then slot.entity = obj return obj end
    return nil
end

function DoorLeaf.draw(model, ent, x, y, z, heading, rgb, fill, edge)
    local box = DoorLeaf.box(model)
    local mn = box and box.mn or DEFAULT_MN
    local mx = box and box.mx or DEFAULT_MX
    local h = math.rad(heading or 0.0)
    local cs, sn = math.cos(h), math.sin(h)
    local function at(px, py, pz)
        if ent then return GetOffsetFromEntityInWorldCoords(ent, px, py, pz) end
        return { x = x + px * cs - py * sn, y = y + px * sn + py * cs, z = z + pz }
    end
    local r, g, b = rgb[1], rgb[2], rgb[3]
    for _, fy in ipairs({ mx.y + 0.015, mn.y - 0.015 }) do
        local q1, q2, q3, q4 = at(mn.x, fy, mn.z), at(mx.x, fy, mn.z), at(mx.x, fy, mx.z), at(mn.x, fy, mx.z)
        -- Both windings: a poly is seen from one side only.
        DrawPoly(q1.x, q1.y, q1.z, q2.x, q2.y, q2.z, q3.x, q3.y, q3.z, r, g, b, fill)
        DrawPoly(q1.x, q1.y, q1.z, q3.x, q3.y, q3.z, q4.x, q4.y, q4.z, r, g, b, fill)
        DrawPoly(q3.x, q3.y, q3.z, q2.x, q2.y, q2.z, q1.x, q1.y, q1.z, r, g, b, fill)
        DrawPoly(q4.x, q4.y, q4.z, q3.x, q3.y, q3.z, q1.x, q1.y, q1.z, r, g, b, fill)
        if edge > 0 then
            DrawLine(q1.x, q1.y, q1.z, q2.x, q2.y, q2.z, r, g, b, edge)
            DrawLine(q2.x, q2.y, q2.z, q3.x, q3.y, q3.z, r, g, b, edge)
            DrawLine(q3.x, q3.y, q3.z, q4.x, q4.y, q4.z, r, g, b, edge)
            DrawLine(q4.x, q4.y, q4.z, q1.x, q1.y, q1.z, r, g, b, edge)
        end
    end
end

--- One door outlined white at a time; set(nil) takes it off. Through client/highlight.lua, the outline's one owner (its
--- colour is one setting for the whole game): each outliner is an owner of its own there, its door the 'hover'.
local outliners = 0
function DoorLeaf.outliner()
    outliners = outliners + 1
    local owner = 'doorLeaf:' .. outliners
    local current = nil
    local o = {}
    function o.set(ent)
        if ent == current then return end
        current = ent
        Highlight.set(owner, (ent and DoesEntityExist(ent)) and { hover = ent } or nil)
    end
    return o
end
