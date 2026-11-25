-- ============================================
-- SPOT SHAPE — is a point inside a Director spot's marker
-- ============================================
--
-- ONE RULE FOR BOTH SIDES: the server's cards that wait at a spot (server/director/spots.lua) and the
-- client's marker, which lights while you are in it (client/director_spots.lua).
--
-- A spot's marker (its page: w.def.marker) is a circle (w across), a square (w across the way the spot
-- faces, l along it) or a garage bay (the garages' own size, Config.GaragePositionHelper). Flat on the
-- ground: anything more than HEIGHT above or below it is not in it (another floor of a car park).
--
-- Pure: no natives.

SpotShape = {}

local HEIGHT = 2.5   -- metres above or below the spot
SpotShape.MIN, SpotShape.MAX = 1, 30   -- a circle's or a square's side, in metres

--- A marker's symbol, as it keeps it: an icon's key (html/js/glyphs.js), or nil. A garage bay's 'garage' is nil (its
--- own, drawn anyway); a circle's or a square's 'garage' is that symbol, picked.
---@param v any
---@param look? string
---@return string|nil
function SpotShape.icon(v, look)
    if type(v) ~= 'string' or v == '' or #v > 24 or not v:match('^[%w_%-]+$') then return nil end
    if v == 'garage' and (look == nil or look == 'garage') then return nil end
    return v
end

--- The garage bay's size: Config.GaragePositionHelper's (width across, length along).
---@return number w, number l
function SpotShape.garageSize()
    local c = Config.GaragePositionHelper or {}
    return tonumber(c.width) or 2.6, tonumber(c.length) or 5.2
end

--- Is (x, y, z) inside? r = { look = 'circle'|'square'|'garage', x, y, z, heading, w, l }.
---@return boolean
function SpotShape.inside(r, x, y, z)
    if math.abs(z - r.z) > HEIGHT then return false end
    local dx, dy = x - r.x, y - r.y
    if r.look == 'circle' then
        local half = r.w * 0.5
        return dx * dx + dy * dy <= half * half
    end
    -- Along the spot's heading (GTA's: 0 faces north, turning left), and across it.
    local h = math.rad(r.heading or 0.0)
    local fx, fy = -math.sin(h), math.cos(h)
    local along, across = dx * fx + dy * fy, dx * fy - dy * fx
    return math.abs(across) <= r.w * 0.5 and math.abs(along) <= r.l * 0.5
end

--- Is a car's heading square to the spot's, either way round (nose in or reversed in), within `tol` degrees?
--- The garage helper's own rule (GarageHelperAligned).
---@return boolean
function SpotShape.aligned(a, b, tol)
    local d = math.abs(((a or 0.0) - (b or 0.0) + 180.0) % 360.0 - 180.0)
    tol = tol or 25.0
    return d <= tol or d >= 180.0 - tol
end
