-- Garage bay: is a car in this bay, by the bay's outline. One rule for the client's bay prompt
-- (client/garage_spots.lua) and the server's check before a car comes out (Vehicles.spotBlocked).
-- By outline, not radius, as bays are only ~3 m apart: a car takes a bay when its body overlaps the bay's rectangle
-- (Config.GaragePositionHelper length x width) less GIVE all round. Pure, no natives; the caller supplies the car's
-- size (the server uses CAR_HALF_LENGTH / CAR_HALF_WIDTH, a large car).

GarageBay = {}

local GIVE = 0.15               -- metres off the outline on every side: touching the line is not in
local HEIGHT = 2.5              -- metres above or below the bay: another floor of a car park is not in
GarageBay.CAR_HALF_LENGTH = 2.5 -- a car whose size is not known: 5.0 x 2.1 m, larger than most
GarageBay.CAR_HALF_WIDTH = 1.05

--- The bay's half length (along its heading) and half width, less the give.
---@return number halfLength, number halfWidth
function GarageBay.halfSize()
    local c = Config.GaragePositionHelper or {}
    local L, W = tonumber(c.length) or 5.2, tonumber(c.width) or 2.6
    return math.max(0.5, L * 0.5 - GIVE), math.max(0.3, W * 0.5 - GIVE)
end

--- Does a car (middle, heading, half size) overlap a bay (middle, heading)? Two ground rectangles, by the separating
--- axis test.
---@return boolean
function GarageBay.overlaps(bx, by, bz, bheading, cx, cy, cz, cheading, chl, chw)
    if math.abs((cz or bz) - bz) > HEIGHT then return false end
    local bhl, bhw = GarageBay.halfSize()
    chl, chw = chl or GarageBay.CAR_HALF_LENGTH, chw or GarageBay.CAR_HALF_WIDTH
    local bh, ch = math.rad(bheading or 0.0), math.rad(cheading or 0.0)
    local bfx, bfy, brx, bry = -math.sin(bh), math.cos(bh), math.cos(bh), math.sin(bh)
    local cfx, cfy, crx, cry = -math.sin(ch), math.cos(ch), math.cos(ch), math.sin(ch)
    local dx, dy = cx - bx, cy - by
    local axes = { { bfx, bfy }, { brx, bry }, { cfx, cfy }, { crx, cry } }
    for _, a in ipairs(axes) do
        local ax, ay = a[1], a[2]
        local dist = math.abs(dx * ax + dy * ay)
        local rb = bhl * math.abs(bfx * ax + bfy * ay) + bhw * math.abs(brx * ax + bry * ay)
        local rc = chl * math.abs(cfx * ax + cfy * ay) + chw * math.abs(crx * ax + cry * ay)
        if dist > rb + rc then return false end
    end
    return true
end
