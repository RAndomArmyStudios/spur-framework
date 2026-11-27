-- ============================================
-- ThrowAim — how a throw is aimed
-- ============================================
--
-- One rule for every throw, so a script's (ThrowGroundItem, server/ground.lua) flies like a player's
-- (client/inventory.lua). A throw is aimed at a spot at a speed, on the low (flatter) arc that lands on it at
-- that speed. At something out of reach it goes straight along the aim with a little lift (LOFT) and falls
-- short. A harder throw is never aimed past the spot: it comes in flatter and faster, and bounces or skids on
-- further.
--
-- No natives: arithmetic only, and shared, so the server works out where a script's throw should come down
-- with the same numbers its game flies it with. Positions are anything with x, y, z; velocities come back as
-- three numbers.

ThrowAim = {}

ThrowAim.GRAVITY = 9.81   -- m/s², what the game pulls a thrown object down with
ThrowAim.LOFT    = 2.5    -- m/s up, added to a throw at something out of reach

local sqrt = math.sqrt

--- The velocity that carries a throw from `from` to land on `to` at `speed`, on the low arc. nil when `to` is
--- out of reach at that speed, or straight above or below.
---@param speed number  m/s
---@return number|nil vx, number|nil vy, number|nil vz
function ThrowAim.arc(from, to, speed)
    local dx, dy, dz = to.x - from.x, to.y - from.y, to.z - from.z
    local d = sqrt(dx * dx + dy * dy)
    if d < 0.05 or speed <= 0 then return nil end
    local v, g = speed, ThrowAim.GRAVITY
    local v2 = v * v
    local disc = v2 * v2 - g * (g * d * d + 2.0 * dz * v2)
    if disc < 0.0 then return nil end
    local tanA = (v2 - sqrt(disc)) / (g * d)
    local cosA = 1.0 / sqrt(1.0 + tanA * tanA)
    local h = v * cosA / d
    return dx * h, dy * h, v * tanA * cosA
end

--- Straight along the aim from `from` towards `to` at `speed`, with LOFT on top: a throw at something it
--- cannot reach. nil when the two are the same point.
---@param speed number  m/s
---@return number|nil vx, number|nil vy, number|nil vz
function ThrowAim.straight(from, to, speed)
    local dx, dy, dz = to.x - from.x, to.y - from.y, to.z - from.z
    local len = sqrt(dx * dx + dy * dy + dz * dz)
    if len < 0.001 then return nil end
    local k = speed / len
    return dx * k, dy * k, dz * k + ThrowAim.LOFT
end

--- The gentlest throw that lands on `to`: the slowest speed that reaches it, and its velocity (45° up on the
--- flat). Straight above, up just enough; straight below, let go.
---@return number speed, number vx, number vy, number vz
function ThrowAim.softest(from, to)
    local dx, dy, dz = to.x - from.x, to.y - from.y, to.z - from.z
    local d = sqrt(dx * dx + dy * dy)
    local g = ThrowAim.GRAVITY
    if d < 0.05 then
        local up = dz > 0 and sqrt(2.0 * g * dz) or 0.0
        return up, 0.0, 0.0, up
    end
    local v2 = g * (dz + sqrt(d * d + dz * dz))
    local v = sqrt(v2)
    local tanA = v2 / (g * d)
    local cosA = 1.0 / sqrt(1.0 + tanA * tanA)
    local h = v * cosA / d
    return v, dx * h, dy * h, v * tanA * cosA
end

--- Where a throw from `from` at (vx, vy, vz) comes back down to height `z`, or to `from`'s own height when it
--- never gets up to `z`.
---@return number x, number y, number z
function ThrowAim.landing(from, vx, vy, vz, z)
    local g = ThrowAim.GRAVITY
    local disc = vz * vz + 2.0 * g * (from.z - z)
    if disc < 0.0 then z, disc = from.z, vz * vz end
    local t = (vz + sqrt(disc)) / g
    return from.x + vx * t, from.y + vy * t, z
end

--- How high a throw from `from` rises: `from`'s height plus what its upward speed carries it.
---@return number z
function ThrowAim.apex(from, vz)
    return from.z + (vz > 0 and vz * vz / (2.0 * ThrowAim.GRAVITY) or 0.0)
end
