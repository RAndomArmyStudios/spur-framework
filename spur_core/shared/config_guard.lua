-- ============================================
-- CONFIG GUARD — shared/config_guard.lua (straight after config.lua; works on the server)
-- ============================================
--
-- config.lua is the file owners edit by hand. One slip in it (a missing comma, bracket or quote) stops it partway:
-- Config is missing or half made, and the files after it error as they load, a wall of red that never names the
-- cause. This file runs config.lua again on its own to find the slip, names the line in one plain message, and
-- stops spur_core's start: server/player_lifecycle.lua halts on ConfigGuard.problem, and nobody can join until the
-- file is fixed. The message prints again once the start is over, below the errors it caused.
--
-- Running it again is safe: config.lua only fills in Config (its one call is GetConvar), and here it fills a table
-- of its own.

if not IsDuplicityVersion() then return end

ConfigGuard = { problem = nil }

local SELF = GetCurrentResourceName()

--- The error config.lua stops on, with its line ('config.lua:812: ...'), or nil when it runs to the end.
local function findSlip()
    local text = LoadResourceFile(SELF, 'config.lua')
    if not text then
        return type(Config) ~= 'table' and 'config.lua could not be read' or nil
    end
    local env = setmetatable({}, { __index = _G })
    local chunk, parseErr = load(text, '@config.lua', 't', env)
    if not chunk then return parseErr end
    local ok, runErr = pcall(chunk)
    if not ok then return tostring(runErr) end
    if type(rawget(env, 'Config')) ~= 'table' then return 'config.lua no longer makes Config (its "Config = {}" line)' end
    return nil
end

ConfigGuard.problem = findSlip()

-- SETTINGS WHIP NO LONGER READS. An owner who kept an older config.lua across an update has keys whip ignores without a
-- word: each one still there is named, once, with what took its place. (Add a key here when a release drops it.)
local RETIRED = {
    FuelStations = 'fuel moved to whip_fuel: set it in whip_fuel/config.lua',
    FuelPumpProps = 'fuel moved to whip_fuel: set it in whip_fuel/config.lua',
    FuelStationBlipColor = 'fuel moved to whip_fuel: set it in whip_fuel/config.lua',
    FuelStationBlipSprite = 'fuel moved to whip_fuel: set it in whip_fuel/config.lua',
    RefuelLeashRange = 'fuel moved to whip_fuel: set it in whip_fuel/config.lua',
    RefuelPumpRange = 'fuel moved to whip_fuel: set it in whip_fuel/config.lua',
    RefuelVehicleRange = 'fuel moved to whip_fuel: set it in whip_fuel/config.lua',
    VehicleFuelDrainRate = 'fuel moved to whip_fuel: set it in whip_fuel/config.lua',
    VehicleFuelRefillRate = 'fuel moved to whip_fuel: set it in whip_fuel/config.lua',
    VehicleFuelReportInterval = 'fuel moved to whip_fuel: set it in whip_fuel/config.lua',
    VehicleRefuelCostPerUnit = 'fuel moved to whip_fuel: set it in whip_fuel/config.lua',
    GarageEditorReach = 'now GarageWizardReach',
    HousingEntryPlaceRange = 'housing became Properties: see the Property settings',
    HousingInsideRange = 'housing became Properties: see the Property settings',
    HousingKeyGrantRange = 'housing became Properties: now PropertyKeyGrantRange',
    HousingMaxObjects = 'housing became Properties: see the Property settings',
    HousingStreamRange = 'housing became Properties: see the Property settings',
    PropSnapImageW = '/propsnap is gone',
    PropSnapImageH = '/propsnap is gone',
    MenuPedEnabled = 'the menu ped is gone', MenuPedLighting = 'the menu ped is gone',
    MenuPedOffset = 'the menu ped is gone', MenuPedTimecycle = 'the menu ped is gone',
    AccessorySlots = 'the containers are code now (shared/inventory_shape.lua), not a setting',
    PlayerContainers = 'the containers are code now (shared/inventory_shape.lua), not a setting',
    IgnitionKeyItems = 'no longer a setting', VehicleModSlots = 'no longer a setting',
    DefaultAccountType = 'no longer a setting', DefaultStatuses = 'stats are registered by the resources that use them',
}
if type(Config) == 'table' then
    local stale = {}
    for key, instead in pairs(RETIRED) do
        if rawget(Config, key) ~= nil then stale[#stale + 1] = ('%s (%s)'):format(key, instead) end
    end
    if #stale > 0 then
        table.sort(stale)
        print(('^3[spur_core] config.lua has %d setting%s whip no longer reads, from an older whip: %s. Delete them, or move them where it says.^7')
            :format(#stale, #stale == 1 and '' or 's', table.concat(stale, '; ')))
    end
end

if not ConfigGuard.problem then return end

local function say()
    local atLine = ConfigGuard.problem:match('^config%.lua:%d+:') ~= nil
    local lines = {
        '==================================================================',
        'spur_core cannot start: config.lua has a mistake.',
        '  ' .. ConfigGuard.problem,
        atLine and 'Open spur_core/config.lua at that line. The slip is often on the line just above it: a missing'
            or 'Put spur_core/config.lua back (a fresh copy comes with whip, then make your changes again).',
        atLine and 'comma, bracket or quote. Save the file, then run: ensure spur_core'
            or 'Then run: ensure spur_core',
        'Until then players cannot join, and the other spur_core errors you see come from this one.',
        '==================================================================',
    }
    for _, line in ipairs(lines) do print('^1[spur_core] ' .. line .. '^0') end
end

say()

AddEventHandler('onResourceStart', function(name)
    if name == SELF then SetTimeout(1000, say) end
end)

-- player_lifecycle.lua refuses joins once it has halted (BootHalted). This covers the case where config.lua broke
-- that file too, so a player is never let into a spur_core that did not start.
AddEventHandler('playerConnecting', function(_, _, deferrals)
    if BootHalted then return end
    deferrals.defer()
    Wait(0)
    deferrals.done('[spur_core] The server could not start: its config.lua has a mistake. An admin needs to check the server console.')
end)
