-- ============================================
-- PROPERTY VALIDATE — one checker for every way a property is described
-- ============================================
--
-- A MAP PACK (an MLO creator's whip_properties file, or RegisterPropertyPack) and, later, the
-- Configurator's drafts describe templates, units and properties in the same shape, so they are
-- checked by the same code. Whatever passes here is safe to store and to place in the world.
--
-- ATOMIC, AND IT SAYS WHERE. The first mistake refuses the whole pack, with the path to it:
--
--     templates[1].units[2].doors[1].model: a door needs a model (a name or a hash)
--
-- A pack that is half applied is worse than one that is refused: some flats appear, some do not,
-- and nothing says why. So nothing is written until all of it has passed.
--
-- WHAT COMES OUT IS A NEW TABLE, normalised: every position is { x, y, z }, every hash is signed,
-- every heading is 0..360, and anything this file does not know about is left behind.
--
-- LOCAL COORDINATES ARE BOUNDED: a unit's parts must be within 250 m of its interior's origin. A
-- flat is never that big, and a typo that puts a door 40 km away is caught here rather than on a
-- door list.

PropertyValidate = {}

PropertyValidate.FORMAT = 1

--- The most any one pack may carry.
PropertyValidate.LIMITS = {
    templates  = 256,
    units      = 64,    -- per template
    shapes     = 16,    -- per unit
    points     = 64,    -- per polygon
    doors      = 32,    -- per unit
    bays       = 8,     -- per garage
    rooms      = 64,    -- per template
    properties = 2000,
    reach      = 250.0, -- metres from the interior's origin, for anything in a unit
}

local LIMITS = PropertyValidate.LIMITS

local ROLES = { entrance = true, interior = true, garage = true }

-- ============================================
-- Failing, with a path
-- ============================================

--- Stop validating, and say where and why. Caught once, at the top.
local function fail(path, msg)
    error({ path = path, msg = msg }, 0)
end

local function at(path, key)
    if type(key) == 'number' then return ('%s[%d]'):format(path, key) end
    return path == '' and key or (path .. '.' .. key)
end

-- ============================================
-- Values
-- ============================================

local function finite(n)
    return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge
end

local function num(v, path, lo, hi, default)
    if v == nil and default ~= nil then return default end
    if not finite(v) then fail(path, 'must be a number') end
    if lo and v < lo then fail(path, ('must be at least %s'):format(lo)) end
    if hi and v > hi then fail(path, ('must be at most %s'):format(hi)) end
    return v
end

local function str(v, path, max, pattern, patternWhy)
    if type(v) ~= 'string' or v == '' then fail(path, 'must be text') end
    if #v > max then fail(path, ('must be %d characters or fewer'):format(max)) end
    if pattern and not v:match(pattern) then fail(path, patternWhy or 'has characters it cannot have') end
    return v
end

local function optStr(v, path, max)
    if v == nil then return nil end
    return str(v, path, max)
end

local function bool(v, path, default)
    if v == nil then return default end
    if type(v) ~= 'boolean' then fail(path, 'must be true or false') end
    return v
end

local function list(v, path, max, min)
    if v == nil then v = {} end
    if type(v) ~= 'table' then fail(path, 'must be a list') end
    local n = #v
    for k in pairs(v) do
        if type(k) ~= 'number' or k < 1 or k > n or k % 1 ~= 0 then fail(path, 'must be a list, not a table with names') end
    end
    if min and n < min then fail(path, ('needs at least %d'):format(min)) end
    if n > max then fail(path, ('can hold at most %d, this has %d'):format(max, n)) end
    return v
end

--- A position: { x, y, z }, { 1, 2, 3 } or a vector3 (which the pack sandbox hands over as a
--- table). `reach` bounds each component.
local function vec(v, path, reach)
    if type(v) ~= 'table' then fail(path, 'must be a position { x, y, z } or vec3(...)') end
    local x, y, z = v.x or v[1], v.y or v[2], v.z or v[3]
    num(x, at(path, 'x'), -reach, reach)
    num(y, at(path, 'y'), -reach, reach)
    num(z, at(path, 'z'), -reach, reach)
    return { x = x, y = y, z = z }
end

local function heading(v, path)
    return num(v, path, nil, nil, 0.0) % 360.0
end

--- A model or archetype: a name, or a hash either signed or unsigned. Signed out.
local function hash(v, path, what)
    if type(v) == 'string' and v ~= '' then
        if #v > 100 then fail(path, 'is too long') end
        return PropertyMath.signedHash(v), (not v:match('^%-?%d+$')) and v or nil
    end
    if finite(v) and v % 1 == 0 then return PropertyMath.signedHash(v), nil end
    fail(path, ('%s must be a name or a hash'):format(what))
end

local KEY_PATTERN = '^[%w_%-%.]+$'
local KEY_WHY = 'may only use letters, numbers, _ - and .'

-- ============================================
-- The parts of a unit
-- ============================================

local function shape(s, path)
    if type(s) ~= 'table' then fail(path, 'must be a shape') end
    local reach = LIMITS.reach
    if s.type == 'box' then
        local c = s.center or s.pos
        if c == nil then fail(at(path, 'center'), 'a box needs a center') end
        local size = s.size
        if type(size) ~= 'table' then fail(at(path, 'size'), 'a box needs a size { x, y, z }') end
        local sx, sy, sz = size.x or size[1], size.y or size[2], size.z or size[3]
        return {
            type = 'box',
            center = vec(c, at(path, 'center'), reach),
            size = { x = num(sx, at(at(path, 'size'), 'x'), 0.1, 500), y = num(sy, at(at(path, 'size'), 'y'), 0.1, 500),
                     z = num(sz, at(at(path, 'size'), 'z'), 0.1, 100) },
            heading = heading(s.heading, at(path, 'heading')),
        }
    elseif s.type == 'poly' then
        local pts = list(s.points, at(path, 'points'), LIMITS.points, 3)
        local out = {}
        for i, p in ipairs(pts) do
            local pp = at(at(path, 'points'), i)
            if type(p) ~= 'table' then fail(pp, 'must be a point { x, y }') end
            out[i] = { x = num(p.x or p[1], at(pp, 'x'), -reach, reach), y = num(p.y or p[2], at(pp, 'y'), -reach, reach) }
        end
        local minZ = num(s.minZ, at(path, 'minZ'), -reach, reach)
        local maxZ = num(s.maxZ, at(path, 'maxZ'), -reach, reach)
        if maxZ <= minZ then fail(at(path, 'maxZ'), 'must be above minZ') end
        return { type = 'poly', points = out, minZ = minZ, maxZ = maxZ }
    elseif s.type == 'interior' then
        return { type = 'interior' }
    elseif s.type == 'rooms' then
        local names = list(s.rooms, at(path, 'rooms'), 32, 1)
        local out = {}
        for i, n in ipairs(names) do out[i] = str(n, at(at(path, 'rooms'), i), 64) end
        return { type = 'rooms', rooms = out }
    end
    fail(at(path, 'type'), "must be 'box', 'poly', 'interior' or 'rooms'")
end

local function door(d, path)
    if type(d) ~= 'table' then fail(path, 'must be a door') end
    local role = d.role or 'interior'
    if not ROLES[role] then fail(at(path, 'role'), "must be 'entrance', 'interior' or 'garage'") end
    if d.model == nil then fail(at(path, 'model'), 'a door needs a model (a name or a hash)') end
    local model = hash(d.model, at(path, 'model'), 'a door model')
    if d.pos == nil then fail(at(path, 'pos'), 'a door needs a position') end
    return {
        key     = str(d.key, at(path, 'key'), 32, KEY_PATTERN, KEY_WHY),
        role    = role,
        lock    = bool(d.lock, at(path, 'lock'), false),
        pair    = d.pair ~= nil and str(d.pair, at(path, 'pair'), 32) or nil,
        model   = model,
        pos     = vec(d.pos, at(path, 'pos'), LIMITS.reach),
        heading = heading(d.heading, at(path, 'heading')),
    }
end

--- `withPost`: the outside sign, which may stand on a sign post (`post`, a prop's name: shared/property_math.lua,
--- Sign posts). Any name is kept, listed or not, so a post later taken out of Config.PropertySignPosts never fails a
--- saved property: it only loses its post. Where an admin picks one, the list is checked (property_admin.lua).
local function pointAndHeading(v, path, withPost)
    if type(v) ~= 'table' then fail(path, 'must be { pos = vec3(...), heading = n }') end
    if v.pos == nil then fail(at(path, 'pos'), 'needs a position') end
    local out = { pos = vec(v.pos, at(path, 'pos'), LIMITS.reach), heading = heading(v.heading, at(path, 'heading')) }
    if withPost and v.post ~= nil and v.post ~= false and v.post ~= '' then
        out.post = str(v.post, at(path, 'post'), 64, '^[%w_]+$', 'may only use letters, numbers and _')
    end
    return out
end

--- One unit, in its interior's own space.
---@return table
function PropertyValidate.unit(u, path)
    if type(u) ~= 'table' then fail(path, 'must be a unit') end
    local out = {
        key   = str(u.key, at(path, 'key'), 64, KEY_PATTERN, KEY_WHY),
        label = optStr(u.label, at(path, 'label'), 100),
    }

    out.space = {}
    for i, s in ipairs(list(u.space, at(path, 'space'), LIMITS.shapes, 1)) do
        out.space[i] = shape(s, at(at(path, 'space'), i))
    end

    out.doors = {}
    local keys = {}
    for i, d in ipairs(list(u.doors, at(path, 'doors'), LIMITS.doors)) do
        local dp = at(at(path, 'doors'), i)
        local nd = door(d, dp)
        if keys[nd.key] then fail(at(dp, 'key'), ('"%s" is used by two doors'):format(nd.key)) end
        keys[nd.key] = true
        out.doors[i] = nd
    end
    for i, d in ipairs(out.doors) do
        if d.pair and (not keys[d.pair] or d.pair == d.key) then
            fail(at(at(at(path, 'doors'), i), 'pair'), ('"%s" is not another door of this unit'):format(d.pair))
        end
    end

    -- The sign outside (for sale) and the manager inside (for the people who live there).
    if u.sign ~= nil then out.sign = pointAndHeading(u.sign, at(path, 'sign'), true) end
    if u.manager ~= nil then out.manager = pointAndHeading(u.manager, at(path, 'manager')) end
    if u.visit ~= nil then out.visit = vec(u.visit, at(path, 'visit'), LIMITS.reach) end

    if u.garage ~= nil then
        if type(u.garage) ~= 'table' then fail(at(path, 'garage'), 'must be { bays = { ... } }') end
        local bays = {}
        for i, b in ipairs(list(u.garage.bays, at(at(path, 'garage'), 'bays'), LIMITS.bays, 1)) do
            bays[i] = pointAndHeading(b, at(at(at(path, 'garage'), 'bays'), i))
        end
        out.garage = { bays = bays }
    end
    return out
end

--- What a unit stores as its base: its parts, without its key and label (those are columns).
function PropertyValidate.unitBase(u)
    return { space = u.space, doors = u.doors, sign = u.sign, manager = u.manager, visit = u.visit, garage = u.garage }
end

--- A whole unit from the Configurator's draft, checked by the same rules as a pack's.
---@return table|nil unit, string|nil err
function PropertyValidate.unitOf(u)
    local ok, res = pcall(PropertyValidate.unit, u, 'unit')
    if ok then return res end
    if type(res) == 'table' and res.msg then return nil, res.path .. ': ' .. res.msg end
    return nil, tostring(res)
end

--- One unit part on its own (space, doors, sign, manager, visit), for editing one part of a
--- property: checked by building a unit around it.
---@return table|nil value, string|nil err
function PropertyValidate.partOf(part, value)
    local u = { key = 'part', space = { { type = 'interior' } } }
    u[part] = value
    local unit, err = PropertyValidate.unitOf(u)
    if not unit then return nil, err end
    return unit[part]
end

--- A sign's spot (either sign), in its interior's own space, for the admin panel's placing. `withPost`: the
--- outside sign, which may name its post.
---@return table|nil part, string|nil err
function PropertyValidate.signOf(v, withPost)
    local ok, res = pcall(pointAndHeading, v, 'sign', withPost == true)
    if ok then return res end
    if type(res) == 'table' and res.msg then return nil, res.path .. ': ' .. res.msg end
    return nil, tostring(res)
end

-- ============================================
-- Templates, properties, packs
-- ============================================

local function settings(s, path)
    if s == nil then return nil end
    if type(s) ~= 'table' then fail(path, 'must be a table of settings') end
    local out = {}
    if s.price ~= nil then out.price = math.floor(num(s.price, at(path, 'price'), 0, 1e9)) end
    if s.maxObjects ~= nil then out.maxObjects = math.floor(num(s.maxObjects, at(path, 'maxObjects'), 0, 1000)) end
    if s.autolock ~= nil then out.autolock = bool(s.autolock, at(path, 'autolock')) end
    if s.autolockDelay ~= nil then out.autolockDelay = math.floor(num(s.autolockDelay, at(path, 'autolockDelay'), 1, 300)) end
    return out
end

local function rooms(v, path)
    if v == nil then return nil end
    local out = {}
    for i, r in ipairs(list(v, path, LIMITS.rooms)) do
        local rp = at(path, i)
        if type(r) ~= 'table' then fail(rp, 'must be a room { name, min, max }') end
        out[i] = {
            name = str(r.name, at(rp, 'name'), 64),
            min  = vec(r.min, at(rp, 'min'), LIMITS.reach),
            max  = vec(r.max, at(rp, 'max'), LIMITS.reach),
        }
    end
    return out
end

--- An interior's rooms as the Configurator read them.
---@return table|nil rooms, string|nil err
function PropertyValidate.roomsOf(v)
    local ok, res = pcall(rooms, v, 'rooms')
    if ok then return res end
    if type(res) == 'table' and res.msg then return nil, res.path .. ': ' .. res.msg end
    return nil, tostring(res)
end

local function template(t, path)
    if type(t) ~= 'table' then fail(path, 'must be a template') end
    local out = {
        key   = str(t.key, at(path, 'key'), 64, KEY_PATTERN, KEY_WHY),
        label = optStr(t.label, at(path, 'label'), 100),
        rooms = rooms(t.rooms, at(path, 'rooms')),
        settings = settings(t.settings, at(path, 'settings')),
    }
    -- `archetype = 0` (or false) is a property with no interior: its units are in world space
    -- around the placement, which is how a plain house on the map is described.
    if t.archetype == nil then
        fail(at(path, 'archetype'), 'needs the interior\'s archetype name or hash (0 for no interior)')
    elseif t.archetype == 0 or t.archetype == false then
        out.archetypeHash, out.archetype = 0, nil
    else
        out.archetypeHash, out.archetype = hash(t.archetype, at(path, 'archetype'), 'an archetype')
    end
    if t.fingerprint ~= nil then
        local f = t.fingerprint
        if type(f) ~= 'table' then fail(at(path, 'fingerprint'), 'must be a table') end
        out.fingerprint = {
            rooms   = f.rooms ~= nil and math.floor(num(f.rooms, at(at(path, 'fingerprint'), 'rooms'), 0, 1000)) or nil,
            portals = f.portals ~= nil and math.floor(num(f.portals, at(at(path, 'fingerprint'), 'portals'), 0, 5000)) or nil,
        }
    end

    out.units = {}
    local keys = {}
    for i, u in ipairs(list(t.units, at(path, 'units'), LIMITS.units, 1)) do
        local up = at(at(path, 'units'), i)
        local nu = PropertyValidate.unit(u, up)
        if keys[nu.key] then fail(at(up, 'key'), ('"%s" is used by two units'):format(nu.key)) end
        keys[nu.key] = true
        nu.sortOrder = i
        out.units[i] = nu
    end
    return out
end

local function property(p, path, templatesByKey)
    if type(p) ~= 'table' then fail(path, 'must be a property') end
    local out = {
        key      = str(p.key, at(path, 'key'), 64, KEY_PATTERN, KEY_WHY),
        template = str(p.template, at(path, 'template'), 64),
        unit     = str(p.unit, at(path, 'unit'), 64),
        name     = str(p.name, at(path, 'name'), 100),
        label    = optStr(p.label, at(path, 'label'), 60),
        building = optStr(p.building, at(path, 'building'), 100),
        settings = settings(p.settings, at(path, 'settings')),
    }
    local t = templatesByKey[out.template]
    if not t then fail(at(path, 'template'), ('there is no template "%s" in this pack'):format(out.template)) end
    local found = false
    for _, u in ipairs(t.units) do if u.key == out.unit then found = true break end end
    if not found then fail(at(path, 'unit'), ('template "%s" has no unit "%s"'):format(out.template, out.unit)) end

    local pl = p.placement
    if type(pl) ~= 'table' or pl.pos == nil then
        fail(at(path, 'placement'), 'needs { pos = vec3(...), heading = n } — where the interior stands')
    end
    local pos = vec(pl.pos, at(at(path, 'placement'), 'pos'), 100000.0)
    out.place = { x = pos.x, y = pos.y, z = pos.z, yaw = heading(pl.heading or pl.yaw, at(at(path, 'placement'), 'heading')) }
    return out
end

--- Check a property's own settings (the admin panel's Settings form uses the same rules as packs).
---@return table|nil settings, string|nil err
function PropertyValidate.settingsOf(s)
    local ok, res = pcall(settings, s, 'settings')
    if ok then return res or {} end
    if type(res) == 'table' and res.msg then return nil, res.path .. ': ' .. res.msg end
    return nil, tostring(res)
end

--- Check a whole pack.
---@param data table
---@return table|nil pack  normalised
---@return string|nil err  'path: why'
function PropertyValidate.pack(data)
    local ok, res = pcall(function()
        if type(data) ~= 'table' then fail('', 'a pack must be a table') end
        if data.format ~= PropertyValidate.FORMAT then
            fail('format', ('must be %d (the pack format this whip reads)'):format(PropertyValidate.FORMAT))
        end
        local out = {
            format  = data.format,
            id      = str(data.id, 'id', 48, '^[a-z0-9_.-]+$', 'may only use lower-case letters, numbers, _ - and .'),
            label   = optStr(data.label, 'label', 100),
            version = data.version ~= nil and tostring(data.version):sub(1, 32) or '1',
        }
        if #out.id < 3 then fail('id', 'must be at least 3 characters') end

        out.templates = {}
        local byKey = {}
        for i, t in ipairs(list(data.templates, 'templates', LIMITS.templates, 1)) do
            local nt = template(t, at('templates', i))
            if byKey[nt.key] then fail(at(at('templates', i), 'key'), ('"%s" is used by two templates'):format(nt.key)) end
            byKey[nt.key] = nt
            out.templates[i] = nt
        end

        out.properties = {}
        local pkeys = {}
        for i, p in ipairs(list(data.properties, 'properties', LIMITS.properties)) do
            local np = property(p, at('properties', i), byKey)
            if pkeys[np.key] then fail(at(at('properties', i), 'key'), ('"%s" is used by two properties'):format(np.key)) end
            pkeys[np.key] = true
            out.properties[i] = np
        end
        return out
    end)
    if ok then return res end
    if type(res) == 'table' and res.msg then
        return nil, (res.path ~= '' and (res.path .. ': ') or '') .. res.msg
    end
    return nil, 'the pack could not be read: ' .. tostring(res)
end
