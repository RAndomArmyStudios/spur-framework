-- ============================================
-- THE VEHICLE LIST — server/vehicle_catalog_list.lua
-- ============================================
--
-- The vehicles whip knows by name: what the dealership sells and the vehicle wizard offers. At each start spur_core adds
-- any of them its vehicle catalog does not have yet (server/vehicle_catalog.lua); a vehicle it already has keeps its
-- name and class.
--
-- RedM (spur_core, 24 Nov 2026): RDR2's wagons, coaches, carts and boats. whip_core's list was GTA V's 700 cars, none
-- of which RDR2 has; migration 049_redm_gta_vehicle_catalog takes them out of a database seeded with them. RDR2 has
-- no motorbikes, cars or aircraft. The classes are GTA's numbers (GetVehicleClass's), as the catalog keeps them, and
-- the pickers show the ones used here under 1899 names (Compacts reads "Buggies & carts", Sedans "Coaches", Vans
-- "Wagons", Emergency "Law", Trains "Rail"). A model this game does not have is never offered (each player's game
-- checks the list when it joins), so a line here that is wrong costs nothing but its line.
--
-- ADD A VEHICLE: add a line here, and restart spur_core. A line is { model, class, name }, and the class is one of:
--   compacts  sedans  suvs  coupes  muscle  sportsclassics  sports  super  motorcycles  offroad  industrial  utility
--   vans  cycles  boats  helicopters  planes  service  emergency  military  commercial  trains  openwheel
-- A vehicle with no picture (img/vehicles/<model>.webp in a media pack) is left out of the dealership.

local list = {
    -- Buggies and carts: one horse or two, a driver and a passenger or a small load.
    { 'buggy01', 'compacts', 'Buggy' },
    { 'buggy02', 'compacts', 'Buggy II' },
    { 'buggy03', 'compacts', 'Buggy III' },
    { 'cart01', 'compacts', 'Cart' },
    { 'cart02', 'compacts', 'Cart II' },
    { 'cart03', 'compacts', 'Cart III' },
    { 'cart04', 'compacts', 'Cart IV' },
    { 'cart05', 'compacts', 'Cart V' },
    { 'cart06', 'compacts', 'Cart VI' },
    { 'cart07', 'compacts', 'Cart VII' },
    { 'cart08', 'compacts', 'Cart VIII' },
    { 'huntercart01', 'compacts', 'Hunting Cart' },

    -- Coaches and stagecoaches: passengers.
    { 'coach2', 'sedans', 'Coach II' },
    { 'coach3', 'sedans', 'Coach III' },
    { 'coach4', 'sedans', 'Coach IV' },
    { 'coach5', 'sedans', 'Coach V' },
    { 'coach6', 'sedans', 'Coach VI' },
    { 'stagecoach001x', 'sedans', 'Stagecoach' },
    { 'stagecoach002x', 'sedans', 'Stagecoach II' },
    { 'stagecoach003x', 'sedans', 'Stagecoach III' },
    { 'stagecoach004x', 'sedans', 'Stagecoach IV' },
    { 'stagecoach005x', 'sedans', 'Stagecoach V' },
    { 'stagecoach006x', 'sedans', 'Stagecoach VI' },

    -- Wagons: loads and travel.
    { 'wagon02x', 'vans', 'Wagon II' },
    { 'wagon03x', 'vans', 'Wagon III' },
    { 'wagon04x', 'vans', 'Wagon IV' },
    { 'wagon05x', 'vans', 'Wagon V' },
    { 'wagon06x', 'vans', 'Wagon VI' },
    { 'wagontraveller01x', 'vans', 'Traveller\'s Wagon' },
    { 'wagonwork01x', 'vans', 'Work Wagon' },
    { 'chuckwagon000x', 'vans', 'Chuck Wagon' },
    { 'chuckwagon002x', 'vans', 'Chuck Wagon II' },
    { 'utilliwag', 'utility', 'Utility Wagon' },
    { 'supplywagon', 'utility', 'Supply Wagon' },
    { 'supplywagon2', 'utility', 'Supply Wagon II' },

    -- Industry.
    { 'logwagon', 'industrial', 'Log Wagon' },
    { 'oilwagon01x', 'industrial', 'Oil Wagon' },
    { 'oilwagon02x', 'industrial', 'Oil Wagon II' },
    { 'coal_wagon', 'industrial', 'Coal Wagon' },

    -- Trades and shows.
    { 'wagondairy01x', 'commercial', 'Dairy Wagon' },
    { 'wagondoc01x', 'commercial', 'Doctor\'s Wagon' },
    { 'wagoncircus01x', 'commercial', 'Circus Wagon' },
    { 'wagoncircus02x', 'commercial', 'Circus Wagon II' },

    -- The law.
    { 'policewagon01x', 'emergency', 'Police Wagon' },
    { 'policewagongatling01x', 'emergency', 'Police Gatling Wagon' },
    { 'wagonprison01x', 'emergency', 'Prison Wagon' },
    { 'wagonarmoured01x', 'emergency', 'Armoured Wagon' },

    -- The army.
    { 'armysupplywagon', 'military', 'Army Supply Wagon' },
    { 'warwagon2', 'military', 'War Wagon' },
    { 'gatchuck', 'military', 'Gatling Chuck Wagon' },
    { 'gatchuck_2', 'military', 'Gatling Chuck Wagon II' },
    { 'gatling_gun', 'military', 'Gatling Gun' },
    { 'gatlingmaxim02', 'military', 'Maxim Gun' },
    { 'breach_cannon', 'military', 'Breach Cannon' },
    { 'hotchkiss_cannon', 'military', 'Hotchkiss Cannon' },

    -- Boats.
    { 'canoe', 'boats', 'Canoe' },
    { 'canoetreetrunk', 'boats', 'Dugout Canoe' },
    { 'pirogue', 'boats', 'Pirogue' },
    { 'pirogue2', 'boats', 'Pirogue II' },
    { 'rowboat', 'boats', 'Rowboat' },
    { 'rowboatswamp', 'boats', 'Swamp Rowboat' },
    { 'rowboatswamp02', 'boats', 'Swamp Rowboat II' },
    { 'skiff', 'boats', 'Skiff' },
    { 'keelboat', 'boats', 'Keelboat' },
    { 'boatsteam02x', 'boats', 'Steam Launch' },
    { 'tugboat2', 'boats', 'Tugboat' },

    -- Rail.
    { 'handcart', 'trains', 'Handcart' },
}

for i = 1, #list do VehicleCatalog.seed[#VehicleCatalog.seed + 1] = list[i] end
