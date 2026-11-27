-- Rev range per vehicle model: { idle, limiter } in thousand rpm, keyed by spawn name, and a top per class.
-- GetVehicleCurrentRpm 0.2 = idle, 1.0 = limiter. A model not listed uses classMax.
-- RedM (spur_core, 26 Nov 2026): whip_core's per-model list was the original game's cars, and is gone; the
-- class tops stay (plain numbers). List a wagon's or a mod car's range under models to give it one.
return {
    classMax = {   -- top of the dial when the model isn't listed: class median limiter / 0.97, rounded up to 0.5k
        military = 2.5,   -- median of 9
        commercial = 2.5,   -- median of 6
        industrial = 3,   -- old-style trucks, buses, plant
        service = 3.5,   -- old-style trucks, buses, plant
        utility = 3.5,   -- old-style trucks, buses, plant
        vans = 5.5,   -- median of 40
        suvs = 6,   -- median of 45
        offroad = 6,   -- median of 67
        sportsclassics = 6.5,   -- median of 50
        muscle = 6.5,   -- median of 90
        emergency = 6.5,   -- median of 24
        compacts = 7,   -- median of 18
        sedans = 7,   -- median of 41
        sports = 7.5,   -- median of 113
        coupes = 7.5,   -- median of 20
        super = 8.5,   -- median of 51
        openwheel = 9,   -- median of 4
        motorcycles = 12,   -- sport and dirt bikes (their recordings read 5.5-8.5k)
    },
    models = {},
}
