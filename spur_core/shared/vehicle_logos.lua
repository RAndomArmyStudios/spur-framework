-- Manufacturer logos that ship, as a set the client tests before asking the badge atlas to draw one (otherwise a model
-- without a logo would paint an empty disc instead of the generic car icon). Keys are lowercase makers, as named in
-- html/img/manufacturers/.
-- RedM (spur_core, 26 Nov 2026): whip_core's set was the original game's car makers, and is gone. SPUR ships no
-- logos, so the set is empty and every vehicle shows the generic icon.

VehicleLogos = {}

--- Is there a logo for this manufacturer key?
---@param key string|nil  lowercase brand, as it appears in html/img/manufacturers/
---@return boolean
function HasVehicleLogo(key)
    return key ~= nil and VehicleLogos[key] == true
end
