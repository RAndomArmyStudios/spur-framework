-- ============================================
-- WORLD QUAD — one textured rectangle in 3D space
-- ============================================
--
-- The single primitive every world-space overlay in whip is built from. It was a local inside
-- client/interact_world.lua, where it drew interaction badges and labels; it lives here now
-- because a SECOND thing needed it (the garage position helper) and copying it would have been
-- the StoreMove mistake again — one operation with two implementations only stays correct in the
-- one that gets exercised, and the one that rots is the one nobody is looking at.
--
-- WHAT IT IS. A rectangle placed by a CENTRE and two BASIS VECTORS, so the caller decides which
-- way it faces and this file never has to know:
--
--   right / up from the camera   -> a billboard that turns to face the player (interact prompts)
--   right / up in the XY plane   -> a decal lying flat on the ground (garage bays)
--
-- Both are the same two triangles. Only the vectors differ.
--
-- WHY POLYGONS RATHER THAN NUI. These depth-test. A quad behind a wall is hidden by the wall,
-- and the position comes from the same frame as the camera that renders it — neither of which a
-- browser composited onto the finished frame can ever do. The long version of that argument is at
-- the top of interact_world.lua, and it is the reason this primitive exists at all.
--
-- NO STATE, NO ALLOCATION, NO NATIVE CALLS BUT THE TWO DRAWS. It runs once per quad per frame.
--
-- A SATELLITE LOADS IT TOO ('@spur_core/client/world_quad.lua': whip_fuel's pump screens), so it reads nothing of
-- spur_core's but CleanScreen, and that only when it is there: a satellite's quads are part of the world.

WorldQuad = {}

--- One textured quad, as two triangles.
---
--- The winding below is the REVERSED order, which is the one that renders — confirmed in game.
--- Get it the other way round and backface culling makes the quad invisible from the side you are
--- standing on, which looks like nothing drew at all rather than like a winding mistake. The
--- third texture coordinate is 0: it is undocumented for a flat 2D texture and 0 is what works.
---
--- BOTH OF THOSE WERE FOUND BY TRIAL, in the whip_duitest sandbox, and neither is guessable from
--- the native's signature. That is the whole reason this is one function in one file.
---@param txd string  runtime texture dictionary name
---@param tex string  texture name within it
---@param cx number @param cy number @param cz number  centre, world space
---@param rx number @param ry number @param rz number  RIGHT basis vector, unit length
---@param ux number @param uy number @param uz number  UP basis vector, unit length
---@param w number  width in metres, along `right`
---@param h number  height in metres, along `up`
---@param u0 number @param v0 number @param u1 number @param v1 number  UV rect (atlas cell)
---@param a number   alpha 0-255
---@param tr number @param tg number @param tb number  tint, multiplied into the texture
function WorldQuad.draw(txd, tex, cx, cy, cz, rx, ry, rz, ux, uy, uz, w, h, u0, v0, u1, v1, a,
                        tr, tg, tb)
    -- A clean screen that hides the world (client/clean_screen.lua, a recording): no prompt, bubble or decal anywhere.
    if CleanScreen and CleanScreen.world then return end
    local hw, hh = w * 0.5, h * 0.5
    local hx, hy, hz = rx * hw, ry * hw, rz * hw
    local gx, gy, gz = ux * hh, uy * hh, uz * hh

    local tlx, tly, tlz = cx + gx - hx, cy + gy - hy, cz + gz - hz
    local trx, try_, trz = cx + gx + hx, cy + gy + hy, cz + gz + hz
    local blx, bly, blz = cx - gx - hx, cy - gy - hy, cz - gz - hz
    local brx, bry, brz = cx - gx + hx, cy - gy + hy, cz - gz + hz

    DrawTexturedPoly(
        tlx, tly, tlz,  blx, bly, blz,  trx, try_, trz,
        tr, tg, tb, a, txd, tex,
        u0, v0, 0.0,  u0, v1, 0.0,  u1, v0, 0.0
    )
    DrawTexturedPoly(
        trx, try_, trz,  blx, bly, blz,  brx, bry, brz,
        tr, tg, tb, a, txd, tex,
        u1, v0, 0.0,  u0, v1, 0.0,  u1, v1, 0.0
    )
end

--- One textured quad by its four corners, for a shape that is not flat: a decal laid over the ground in
--- patches, each corner at the ground's own height (the world builder's guard cone, client/vision.lua). The
--- same two triangles and winding as WorldQuad.draw; `tl` is the corner at (u0, v0), `br` the one at (u1, v1).
---@param tl table @param tr table @param bl table @param br table  { x, y, z } each
function WorldQuad.drawCorners(txd, tex, tl, tr, bl, br, u0, v0, u1, v1, a, cr, cg, cb)
    if CleanScreen and CleanScreen.world then return end
    DrawTexturedPoly(
        tl.x, tl.y, tl.z,  bl.x, bl.y, bl.z,  tr.x, tr.y, tr.z,
        cr, cg, cb, a, txd, tex,
        u0, v0, 0.0,  u0, v1, 0.0,  u1, v0, 0.0
    )
    DrawTexturedPoly(
        tr.x, tr.y, tr.z,  bl.x, bl.y, bl.z,  br.x, br.y, br.z,
        cr, cg, cb, a, txd, tex,
        u1, v0, 0.0,  u0, v1, 0.0,  u1, v1, 0.0
    )
end

--- The basis for a quad lying FLAT ON THE GROUND, rotated to a world heading.
---
--- Both vectors stay in the XY plane, which is the entire difference between a decal on the
--- tarmac and a billboard that turns to face you. `heading` is GTA's: degrees, 0 = north (+Y),
--- increasing anticlockwise — the same figure `garage_spots` stores and `GetEntityHeading`
--- returns, so a caller never has to convert.
---
--- `right` runs across the rectangle's width and `up` along its length, so a bay drawn with
--- (width, length) points the long axis the way the car should face.
---@param heading number  degrees
---@return number rx, number ry, number rz, number ux, number uy, number uz
function WorldQuad.groundBasis(heading)
    local rad = math.rad(heading or 0.0)
    local s, c = math.sin(rad), math.cos(rad)

    -- GTA headings turn anticlockwise from +Y, so forward is (-sin, cos) and right is its
    -- clockwise perpendicular, (cos, sin). Getting these the wrong way round does not fail
    -- visibly — it draws a rectangle of the right size lying at ninety degrees to the bay.
    return c, s, 0.0,   -s, c, 0.0
end

--- The basis for a BILLBOARD: parallel to the screen, never rolling. Shared by interact_world.lua
--- and the /me bubbles.
---
--- It faces the camera's PLANE, not its position: aiming each quad at the camera tilted the ones
--- near the screen edges. Right is taken against world-up, so it stays level; up follows from right
--- and forward, so the quad pitches as you look up or down but never leans with the camera.
--- Compute it once per frame and share it between every quad drawn that frame. The camera's forward may be
--- handed in when the caller read it this frame already (InteractGetCameraForward's three numbers).
---@param fx number|nil @param fy number|nil @param fz number|nil
---@return number rx, number ry, number rz, number ux, number uy, number uz
function WorldQuad.billboardBasis(fx, fy, fz)
    if not fx then fx, fy, fz = InteractGetCameraForward() end

    -- right = forward x world-up
    local rx, ry, rz = fy, -fx, 0.0
    local len = math.sqrt(rx * rx + ry * ry)
    if len < 0.001 then
        -- Looking straight up or down: no horizontal right exists, so use the camera's yaw.
        local h = math.rad(GetFinalRenderedCamRot(2).z)
        rx, ry = math.cos(h), math.sin(h)
    else
        rx, ry = rx / len, ry / len
    end

    -- up = right x forward
    local ux, uy, uz = ry * fz - rz * fy, rz * fx - rx * fz, rx * fy - ry * fx
    local ulen = math.sqrt(ux * ux + uy * uy + uz * uz)
    if ulen < 0.00001 then return rx, ry, rz, 0.0, 0.0, 0.0 end
    return rx, ry, rz, ux / ulen, uy / ulen, uz / ulen
end
