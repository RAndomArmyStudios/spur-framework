-- ============================================
-- TAKE TRACK — the maths of a recorded drive (a take), shared by recording, playback and the server's check
-- ============================================
--
-- A TAKE is a car's drive, recorded frame by frame in the Director (client/director_takes.lua) and played back
-- on the game that owns the car when a run plays it (client/actors.lua). Format 3: whip_scenes' takes' format 2,
-- but with each wheel's angle counted on through its turns (TakeTrack.unwrap); a format 2 take is read as format 3
-- (TakeTrack.upgrade). Plain Lua, no natives.
--
-- A take's samples are one flat list of numbers, STRIDE to a sample, in the order of TakeTrack.FIELDS:
--   t          ms from the take's start (0)
--   x y z      position (m)                         qx qy qz qw   rotation (GET_ENTITY_QUATERNION)
--   vx vy vz   velocity (m/s, world)                steer         steering angle (GET_VEHICLE_STEERING_ANGLE)
--   rpm        engine revs (0 to 1)                 flags         lights, horn and so on (TakeTrack.FLAG bits), and
--                                                                 the gear above them (TakeTrack.gearOf)
--   w0 .. w3   each wheel's angle (radians, counting whole turns). GET_VEHICLE_WHEEL_ROTATION_SPEED reads the angle
--              the game shows, -pi to pi, and SET_ that same angle back (TakeTrack.wheelAngle).
-- Between two samples the position follows a cubic Hermite curve through both positions with both velocities, the
-- rotation a slerp, velocity, steering, revs and wheels a straight line; flags keep the earlier sample's.
--
-- Recording keeps only the samples playback needs: TakeTrack.push drops every frame that the curve between its
-- neighbours already gives to within TOL, so a steady cruise is a few samples a second and a crash keeps every
-- frame. (Format 2 kept the game's wrapped angle: each wheel wrapping from pi to -pi broke the line, ten times a
-- second a wheel at speed, so nearly every frame was kept.)

TakeTrack = {}

local FIELDS = { 't', 'x', 'y', 'z', 'qx', 'qy', 'qz', 'qw', 'vx', 'vy', 'vz', 'steer', 'rpm', 'flags', 'w0', 'w1', 'w2', 'w3' }

TakeTrack.FORMAT = 3
TakeTrack.FIELDS = FIELDS
TakeTrack.STRIDE = #FIELDS
TakeTrack.WHEELS = 15                       -- where the wheel angles start in a sample
TakeTrack.FLAG = { brake = 1, horn = 2, siren = 4, lights = 8, fullbeam = 16, left = 32, right = 64, engine = 128,
                   handbrake = 256, burnout = 512 }

-- THE GEAR rides in the flags, above their bits, because flags already keep the earlier sample's between two samples
-- and a change in them always keeps a sample: a gear change lands on its frame. 1 and up; the car going backwards says
-- reverse by itself. None (0): a take recorded before takes kept it.
local GEAR_SHIFT, GEAR_MAX = 10, 31

--- A sample's flags with the gear the car is in (the game's 0, reverse or no gear yet, kept as 1).
function TakeTrack.withGear(flags, gear)
    return flags | (math.max(1, math.min(math.tointeger(gear) or 1, GEAR_MAX)) << GEAR_SHIFT)
end

--- The gear a sample's flags keep, or nil.
function TakeTrack.gearOf(flags)
    local g = ((math.tointeger(tonumber(flags) or 0) or 0) >> GEAR_SHIFT) & GEAR_MAX
    return g > 0 and g or nil
end

-- How far a dropped frame may be from what playback makes of it; gap = the longest stretch between two samples (ms).
-- Position also allows the distance covered in clock ms (the game timer counts whole milliseconds). A wheel's angle
-- may be off by `wheel` radians (about 6 degrees), or by `wheelPart` of it when that is more (none: the angle counts
-- on, so a part of it would grow with the drive).
TakeTrack.TOL = { pos = 0.01, clock = 1.5, rot = 0.25, vel = 0.1, steer = 1.0, rpm = 0.03, wheel = 0.1, wheelPart = 0,
                  gap = 500 }

local STRIDE = TakeTrack.STRIDE
local sqrt, abs, acos, sin, atan = math.sqrt, math.abs, math.acos, math.sin, math.atan
local TAU = 2 * math.pi

-- ---- wheels ----

--- A wheel's angle as the game shows it (-pi to pi), from a take's (which counts on through the turns).
function TakeTrack.wheelAngle(a)
    return (a + math.pi) % TAU - math.pi
end

--- Wheel `i`'s angle as a take keeps it, from the game's (`raw`, -pi to pi) at `t` ms: the whole turns since the drive
--- began added on, the number of them the one that keeps the wheel turning as fast as it just did (so a wheel that
--- turns more than half a turn between two frames, fast or at a low frame rate, is still counted right). `rec` keeps
--- where each wheel got to: one per car per drive.
function TakeTrack.unwrap(rec, i, raw, t)
    local u = rec.wheel
    if not u then u = {}; rec.wheel = u end
    local w = u[i]
    if not w then
        u[i] = { acc = raw, t = t, rate = 0 }
        return raw
    end
    local dt = t - w.t
    local guess = w.acc + w.rate * dt
    local acc = raw + TAU * math.floor((guess - raw) / TAU + 0.5)
    if dt > 0 then w.rate = (acc - w.acc) / dt end
    w.acc, w.t = acc, t
    return acc
end

-- ---- rotations ----

--- The turn from rotation a to rotation b, world axes: axis times angle (radians), the short way round.
function TakeTrack.turn(ax, ay, az, aw, bx, by, bz, bw)
    local cx = aw * bx - ax * bw + ay * bz - az * by
    local cy = aw * by - ay * bw + az * bx - ax * bz
    local cz = aw * bz - az * bw + ax * by - ay * bx
    local cw = aw * bw + ax * bx + ay * by + az * bz
    if cw < 0 then cx, cy, cz, cw = -cx, -cy, -cz, -cw end
    local len = sqrt(cx * cx + cy * cy + cz * cz)
    if len < 1e-9 then return 0.0, 0.0, 0.0 end
    local k = 2 * atan(len, cw) / len
    return cx * k, cy * k, cz * k
end
local turn = TakeTrack.turn

--- A heading (degrees, the game's: 0 north) from a quaternion.
function TakeTrack.heading(qx, qy, qz, qw)
    local yaw = math.atan(2 * (qw * qz + qx * qy), 1 - 2 * (qy * qy + qz * qz))
    return math.deg(yaw) % 360.0
end

-- ---- between two samples ----

--- The sample at time t between sample a (A[ia+1 .. ia+K]) and sample b (B[ib+1 ..]), into out[1 .. K]; out.sx, sy,
--- sz is the spin (rad/s, world) that turns a into b.
local function interp(A, ia, B, ib, t, out, K)
    K = K or STRIDE
    local ta, tb = A[ia + 1], B[ib + 1]
    local dt = (tb - ta) / 1000
    local s = dt > 0 and (t - ta) / (tb - ta) or 0
    if s < 0 then s = 0 elseif s > 1 then s = 1 end
    local s2 = s * s
    local s3 = s2 * s
    local h00, h10, h01, h11 = 2 * s3 - 3 * s2 + 1, s3 - 2 * s2 + s, -2 * s3 + 3 * s2, s3 - s2
    out[1] = t
    for k = 0, 2 do
        local v0, v1 = A[ia + 9 + k], B[ib + 9 + k]
        out[2 + k] = h00 * A[ia + 2 + k] + h10 * v0 * dt + h01 * B[ib + 2 + k] + h11 * v1 * dt
        -- the recorded speeds in a straight line (the curve's own slope would carry the clock's ms jitter)
        out[9 + k] = v0 + (v1 - v0) * s
    end
    local ax, ay, az, aw = A[ia + 5], A[ia + 6], A[ia + 7], A[ia + 8]
    local bx, by, bz, bw = B[ib + 5], B[ib + 6], B[ib + 7], B[ib + 8]
    local dot = ax * bx + ay * by + az * bz + aw * bw
    if dot < 0 then bx, by, bz, bw, dot = -bx, -by, -bz, -bw, -dot end
    local wa, wb
    if dot > 0.9995 then
        wa, wb = 1 - s, s
    else
        local th = acos(dot)
        local sn = sin(th)
        wa, wb = sin((1 - s) * th) / sn, sin(s * th) / sn
    end
    local qx, qy, qz, qw = wa * ax + wb * bx, wa * ay + wb * by, wa * az + wb * bz, wa * aw + wb * bw
    local n = sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
    if n > 0 then qx, qy, qz, qw = qx / n, qy / n, qz / n, qw / n end
    out[5], out[6], out[7], out[8] = qx, qy, qz, qw
    if dt > 0 then
        local rx, ry, rz = turn(ax, ay, az, aw, bx, by, bz, bw)
        out.sx, out.sy, out.sz = rx / dt, ry / dt, rz / dt
    else
        out.sx, out.sy, out.sz = 0.0, 0.0, 0.0
    end
    out[12] = A[ia + 12] + (B[ib + 12] - A[ia + 12]) * s
    out[13] = A[ia + 13] + (B[ib + 13] - A[ia + 13]) * s
    out[14] = A[ia + 14]
    for k = 15, K do out[k] = A[ia + k] + (B[ib + k] - A[ia + k]) * s end
    return out
end

local function copy(A, ia, out, K)
    for k = 1, K do out[k] = A[ia + k] end
    out.sx, out.sy, out.sz = 0.0, 0.0, 0.0
    return out
end

--- The take at time t (ms) into out (interp's layout). keys = the flat samples, n = how many, cur = the sample the
--- last call ended on (playback moves forward, so the search starts there). Returns the sample index for next time;
--- past the end, the last sample.
function TakeTrack.at(keys, n, t, cur, out, K)
    K = K or STRIDE
    if n < 2 or t <= keys[1] then copy(keys, 0, out, K); return 0 end
    local last = (n - 1) * K
    if t >= keys[last + 1] then copy(keys, last, out, K); return n - 1 end
    local i = cur or 0
    if i < 0 or i > n - 2 or keys[i * K + 1] > t then
        local lo, hi = 0, n - 2
        while lo < hi do
            local mid = (lo + hi + 1) // 2
            if keys[mid * K + 1] <= t then lo = mid else hi = mid - 1 end
        end
        i = lo
    end
    while keys[(i + 1) * K + 1] <= t do i = i + 1 end
    interp(keys, i * K, keys, (i + 1) * K, t, out, K)
    return i
end

--- A take's length (ms): its last sample's time.
function TakeTrack.length(samples)
    return samples[#samples - STRIDE + 1]
end

-- ---- recording ----

local function round(v, m) return math.floor(v * m + 0.5) / m end

--- A sample as it is stored (mm, 1e-5 of a quaternion, ...), so what recording checks is what playback gets.
function TakeTrack.quantize(s)
    local K = #s
    for k = 1, K do
        local v = s[k]
        if type(v) ~= 'number' or v ~= v or v == math.huge or v == -math.huge then s[k] = 0 end
    end
    s[1] = math.floor(s[1] + 0.5)
    local n = sqrt(s[5] * s[5] + s[6] * s[6] + s[7] * s[7] + s[8] * s[8])
    if n < 1e-6 then s[5], s[6], s[7], s[8], n = 0, 0, 0, 1, 1 end
    for k = 2, 4 do s[k] = round(s[k], 1000) end
    for k = 5, 8 do s[k] = round(s[k] / n, 100000) end
    for k = 9, 11 do s[k] = round(s[k], 1000) end
    s[12] = round(s[12], 100)
    s[13] = round(s[13], 1000)
    s[14] = math.tointeger(s[14]) or 0
    for k = 15, K do s[k] = round(s[k], 100) end
    return s
end

function TakeTrack.recorder()
    return { keys = {}, n = 0, anchor = nil, pending = {}, tmp = {}, K = STRIDE }
end

local COS_ROT = math.cos(math.rad(TakeTrack.TOL.rot) / 2)

local function emit(rec, s)
    local K = rec.K
    local keys, base = rec.keys, rec.n * K
    for k = 1, K do keys[base + k] = s[k] end
    rec.n = rec.n + 1
end

local function fits(rec, a, c)
    local tol, K = TakeTrack.TOL, rec.K
    if c[1] - a[1] > tol.gap then return false end
    local tmp, vel2 = rec.tmp, tol.vel * tol.vel
    for _, p in ipairs(rec.pending) do
        if p[14] ~= a[14] then return false end
        interp(a, 0, c, 0, p[1], tmp, K)
        local dx, dy, dz = tmp[2] - p[2], tmp[3] - p[3], tmp[4] - p[4]
        local reach = tol.pos + sqrt(p[9] * p[9] + p[10] * p[10] + p[11] * p[11]) * tol.clock / 1000
        if dx * dx + dy * dy + dz * dz > reach * reach then return false end
        local pn = sqrt(p[5] * p[5] + p[6] * p[6] + p[7] * p[7] + p[8] * p[8])
        if abs(tmp[5] * p[5] + tmp[6] * p[6] + tmp[7] * p[7] + tmp[8] * p[8]) < COS_ROT * pn then return false end
        local ex, ey, ez = tmp[9] - p[9], tmp[10] - p[10], tmp[11] - p[11]
        if ex * ex + ey * ey + ez * ez > vel2 then return false end
        if abs(tmp[12] - p[12]) > tol.steer or abs(tmp[13] - p[13]) > tol.rpm then return false end
        for k = 15, K do
            if abs(tmp[k] - p[k]) > math.max(tol.wheel, abs(p[k]) * tol.wheelPart) then return false end
        end
    end
    return true
end

--- Add a frame (a quantized sample). Frames must come in time order; one at the same time as the last is skipped.
function TakeTrack.push(rec, s)
    local a = rec.anchor
    if not a then rec.anchor = s; emit(rec, s); return end
    local pend = rec.pending
    local latest = pend[#pend] or a
    if s[1] <= latest[1] then return end
    if #pend > 0 and not fits(rec, a, s) then
        local last = pend[#pend]
        emit(rec, last)
        rec.anchor = last
        rec.pending = { s }
        return
    end
    pend[#pend + 1] = s
end

--- The samples so far, ending on the latest frame: keys (flat), n.
function TakeTrack.finish(rec)
    local pend = rec.pending
    if #pend > 0 then
        local last = pend[#pend]
        emit(rec, last)
        rec.anchor = last
        rec.pending = {}
    end
    return rec.keys, rec.n
end

-- ---- an older take ----

--- A take's samples as this format keeps them, from the format it was saved in. Format 2 kept each wheel's angle as the
--- game shows it, so every wrap kept a frame: its wheels are counted on (TakeTrack.unwrap) and the drive thinned again
--- by today's TOL, about a third of the samples for the same drive. `pause()`, when given, is called every few hundred
--- samples (a long take is seconds of work: the server's Wait(0)). The same table when there is nothing to do.
function TakeTrack.upgrade(samples, format, pause)
    if (tonumber(format) or 2) >= 3 then return samples end
    local n = #samples // STRIDE
    local rec, wheels = TakeTrack.recorder(), {}
    local W = TakeTrack.WHEELS
    for j = 0, n - 1 do
        local b = j * STRIDE
        local s = {}
        for k = 1, STRIDE do s[k] = samples[b + k] end
        for i = 0, 3 do s[W + i] = round(TakeTrack.unwrap(wheels, i, s[W + i], s[1]), 100) end
        TakeTrack.push(rec, s)
        if pause and j % 250 == 249 then pause() end
    end
    return (TakeTrack.finish(rec))
end

-- ---- on the wire ----
--
-- A take crosses the network (saved from the builder's game, sent to the game that plays it) as whole numbers: each
-- value at the precision quantize keeps it to (mm, 1e-5 of a quaternion...), as the change from the sample before.
-- A drive changes little from one frame to the next, so most values are one to three bytes in the event's msgpack
-- instead of nine: a three-minute drive is about a quarter of the size, so it arrives that much sooner on a slow
-- connection. unpack gives back exactly the samples that were packed (the same division quantize made). Kept in the
-- database as samples, as before.

local SCALE = { 1, 1000, 1000, 1000, 100000, 100000, 100000, 100000, 1000, 1000, 1000, 100, 1000, 1, 100, 100, 100, 100 }
TakeTrack.WIRE = 1

--- Samples as they cross the network: { w = WIRE, d = { whole numbers } }.
function TakeTrack.pack(samples)
    local d, prev = {}, {}
    for i = 1, #samples do
        local k = (i - 1) % STRIDE + 1
        local v = math.floor(samples[i] * SCALE[k] + 0.5)
        d[i] = v - (prev[k] or 0)
        prev[k] = v
    end
    return { w = TakeTrack.WIRE, d = d }
end

--- Samples back from pack's table, or nil for anything else.
function TakeTrack.unpack(p)
    if type(p) ~= 'table' or p.w ~= TakeTrack.WIRE or type(p.d) ~= 'table' then return nil end
    local d, out, acc = p.d, {}, {}
    for i = 1, #d do
        local v = math.tointeger(d[i])
        if not v then return nil end
        local k = (i - 1) % STRIDE + 1
        local a = (acc[k] or 0) + v
        acc[k] = a
        out[i] = SCALE[k] == 1 and a or a / SCALE[k]
    end
    return out
end

-- ---- checking a take (the server, and a take read back) ----

local function finite(v) return type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge end

--- Are these a take's samples playback can use? true, or false and why. maxKeys caps how many there are.
function TakeTrack.check(samples, maxKeys)
    if type(samples) ~= 'table' then return false, 'no samples' end
    local len = #samples
    if len < 2 * STRIDE or len % STRIDE ~= 0 then return false, 'too few samples, or a broken one' end
    if maxKeys and len > maxKeys * STRIDE then return false, ('more than %d samples'):format(maxKeys) end
    for i = 1, len do
        if not finite(samples[i]) then return false, 'a sample value is not a number' end
    end
    if samples[1] < 0 then return false, 'it starts before its start' end
    for i = STRIDE + 1, len, STRIDE do
        if samples[i] <= samples[i - STRIDE] then return false, 'its samples are not in time order' end
    end
    return true
end
