-- ============================================
-- PROPERTIES — The furnisher's view of the screen
-- ============================================
--
-- Where a point on the screen points into the room, and where a point in the room lands on the
-- screen. The furnisher's X / Y / Z markers are drawn by the page (html/js/furnisher-gizmo.js) and
-- its clicks start there, so the page and this file must agree exactly on how the camera maps the
-- room onto the screen. This is the Lua half of that agreement; the page's half is `basis`,
-- `project` and `rayAt` in furnisher-gizmo.js — the same basis and the same two numbers.
--
-- THE TWO NUMBERS (kx, ky): how far the screen reaches across and up at one metre in front of the
-- camera, i.e. tan of half the field of view each way. The camera's FOV is taken as the vertical
-- one, times the screen's aspect for across — but that is an assumption about the engine, so it is
-- checked against the engine (FurnishView.calibrate): one point is put through
-- GetScreenCoordFromWorldCoord and the numbers are read back off where it landed. Only while the
-- camera holds still, because the engine projects with the frame it last drew and a moving camera
-- would read its own motion as a wrong field of view.
--
-- Pure: no natives are called here. The caller passes GetScreenCoordFromWorldCoord in, which is
-- what lets scratch tests run this file outside the game.

FurnishView = {}

--- The camera's forward, right and up from its rotation: pitch (x) and yaw (z) in degrees, rotation
--- order 2, no roll — FreeCam never rolls. The same basis client/freecam.lua flies with.
---@return table f, table r, table u   each { x, y, z }
function FurnishView.basis(pitch, yaw)
    local p, y = math.rad(pitch), math.rad(yaw)
    local cp, sp, cy, sy = math.cos(p), math.sin(p), math.cos(y), math.sin(y)
    local f = { -sy * cp, cy * cp, sp }
    local r = { cy, sy, 0.0 }
    -- up = right x forward, which comes out as (sin yaw sin pitch, -cos yaw sin pitch, cos pitch)
    local u = { sy * sp, -cy * sp, cp }
    return f, r, u
end

--- The two numbers from the camera's own field of view: the answer until the engine has been asked.
---@param fovDeg number  the cam's FOV (GetCamFov), taken as vertical
---@param aspect number  width / height (GetAspectRatio)
---@return number kx, number ky
function FurnishView.kFromFov(fovDeg, aspect)
    local ky = math.tan(math.rad(fovDeg or 60.0) / 2)
    return ky * (aspect or (16 / 9)), ky
end

--- Which way a point on the screen looks into the room: a unit direction from the camera.
---@param nx number  0 left edge .. 1 right edge
---@param ny number  0 top edge .. 1 bottom edge
---@return number dx, number dy, number dz
function FurnishView.rayAt(nx, ny, pitch, yaw, kx, ky)
    local f, r, u = FurnishView.basis(pitch, yaw)
    local a, b = (nx - 0.5) * 2 * kx, (0.5 - ny) * 2 * ky
    local dx = f[1] + r[1] * a + u[1] * b
    local dy = f[2] + r[2] * a + u[2] * b
    local dz = f[3] + r[3] * a + u[3] * b
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    return dx / len, dy / len, dz / len
end

--- Where a point in the room lands on the screen (0-1 across, 0-1 down), or nil when it is behind
--- the camera. The page's `project`, written out here so the two can be checked against each other.
---@return number|nil nx, number|nil ny
function FurnishView.project(px, py, pz, cx, cy, cz, pitch, yaw, kx, ky)
    local f, r, u = FurnishView.basis(pitch, yaw)
    local dx, dy, dz = px - cx, py - cy, pz - cz
    local depth = dx * f[1] + dy * f[2] + dz * f[3]
    if depth < 0.05 then return nil end
    local across = dx * r[1] + dy * r[2] + dz * r[3]
    local up = dx * u[1] + dy * u[2] + dz * u[3]
    return 0.5 + 0.5 * (across / depth) / kx, 0.5 - 0.5 * (up / depth) / ky
end

--- Read the two numbers back off the engine.
---
--- A point ten metres ahead and three across and up — inside the view at any field of view the
--- furnisher uses — is handed to `toScreen` (GetScreenCoordFromWorldCoord), and where it landed
--- says how wide and tall the view really is. Nil when the engine did not put it on screen.
---@param toScreen function  (x, y, z) -> onScreen, nx, ny
---@return number|nil kx, number|nil ky
function FurnishView.calibrate(cx, cy, cz, pitch, yaw, toScreen)
    local f, r, u = FurnishView.basis(pitch, yaw)
    local D, A = 10.0, 3.0
    local wx = cx + f[1] * D + r[1] * A + u[1] * A
    local wy = cy + f[2] * D + r[2] * A + u[2] * A
    local wz = cz + f[3] * D + r[3] * A + u[3] * A
    local on, sx, sy = toScreen(wx, wy, wz)
    if not on or type(sx) ~= 'number' or type(sy) ~= 'number' then return nil end
    local ax, ay = sx - 0.5, 0.5 - sy
    if ax < 1e-3 or ay < 1e-3 then return nil end
    return 0.5 * (A / D) / ax, 0.5 * (A / D) / ay
end
