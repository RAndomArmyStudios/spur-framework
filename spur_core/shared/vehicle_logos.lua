-- Manufacturer logos that ship, as a set the client tests before asking the badge atlas to draw one (otherwise a model
-- without a logo would paint an empty disc instead of the generic car icon). Generated from html/img/manufacturers/;
-- names are the game's spellings, including "emporer". Regenerate by listing that directory.

VehicleLogos = {
    ['albany'] = true,        ['annis'] = true,         ['banshee'] = true,       ['benefactor'] = true,
    ['bf'] = true,            ['bollokan'] = true,      ['bravado'] = true,       ['brute'] = true,
    ['buckingham'] = true,    ['canis'] = true,         ['chariot'] = true,       ['cheval'] = true,
    ['city'] = true,          ['classique'] = true,     ['coil'] = true,          ['declasse'] = true,
    ['dewbauchee'] = true,    ['dilettante'] = true,    ['dinka'] = true,         ['dundreary'] = true,
    ['emporer'] = true,       ['enus'] = true,          ['fathom'] = true,        ['galivanter'] = true,
    ['grotti'] = true,        ['grotti_2'] = true,      ['hijak'] = true,         ['hvy'] = true,
    ['imponte'] = true,       ['invetero'] = true,      ['jacksheepe'] = true,    ['jobuilt'] = true,
    ['karin'] = true,         ['lampadati'] = true,     ['lcc'] = true,           ['maibatsu'] = true,
    ['mammoth'] = true,       ['maxwell'] = true,       ['mtl'] = true,           ['nagasaki'] = true,
    ['obey'] = true,          ['ocelot'] = true,        ['overflod'] = true,      ['ped'] = true,
    ['pegassi'] = true,       ['penaud'] = true,        ['pfister'] = true,       ['principe'] = true,
    ['progen'] = true,        ['rune'] = true,          ['schyster'] = true,      ['shitzu'] = true,
    ['speedophile'] = true,   ['stanley'] = true,       ['toundra'] = true,       ['tricycles'] = true,
    ['truffade'] = true,      ['ubermacht'] = true,     ['vapid'] = true,         ['vulcar'] = true,
    ['vysser'] = true,        ['weeny'] = true,         ['western'] = true,       ['westernmotorcycle'] = true,
    ['willard'] = true,       ['zirconium'] = true,
}

--- Is there a logo for this manufacturer key?
---@param key string|nil  lowercase brand, as it appears in html/img/manufacturers/
---@return boolean
function HasVehicleLogo(key)
    return key ~= nil and VehicleLogos[key] == true
end
