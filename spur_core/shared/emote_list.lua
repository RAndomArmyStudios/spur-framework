-- The emotes players can pick (/e and the emote menu on the F1 wheel). RedM version.
--
-- whip_core's original-game list (GPL 3.0, built from RPEmotes) does not carry over: every animation and scenario in it is the original game's.
-- This list replaces it. It is new, made for spur_core, and is under the LGPL 3.0 like the rest of spur_core.
--
-- Every emote here is an RDR2 *scenario*: the game brings its own props, loop and exit. Each name was checked
-- against femga/rdr3_discoveries (animations/scenarios/scenario_types_with_conditional_anims.lua). Add more from
-- that list; a scenario that does not exist simply never starts.
-- RedM (spur_core, 26 Nov 2026): each one was started on a ped in game. Four that started on no ped were taken out
-- (WORLD_HUMAN_GUARD_SCOUT, _GUARD_LAZY, _HAMMER_KNEEL, _GRAVEDIG). RDR2 plays the mirror, the fan and the window
-- only on women (the labels say so), checkpistol only with a revolver, and the lean and chair ones best at a wall,
-- rail, post or chair.
--
-- AN EMOTE is:
--   cmd       what players type: /e smoke. Lowercase letters, digits and _ only; "c" and "place" are taken.
--   label     what the menu shows
--   category  one of the category keys below
--   scenario  an RDR2 scenario name (client/rdr_compat.lua plays it with TASK_START_SCENARIO_IN_PLACE_HASH)
--
-- RDR2 animation dictionaries (dict/anim) also work in the same shape as whip_core's original-game ones, but none are listed
-- yet: add them once each is tested in game.
--
-- A WALK is { cmd, label, loco }: loco is an RDR2 loco motion type, put on with _SET_PED_DESIRED_LOCO_MOTION_TYPE
-- (0x89F5E7ADECCCB49C) after the stance is set to 'default' ('default_female' for women) with
-- _SET_PED_DESIRED_LOCO_FOR_MODEL (0x923583741DC87BCE): the motion type does nothing on the player's own stance.
-- The names are from the rdr2mods.com thread "Native for changing walk styles" (topic 812). NOT YET TRIED IN GAME
-- (27 Nov 2026): a name that turns out to show nothing should come out of the list, as the emotes did.
-- Moods (facial idles) are empty for now.

EmoteList = {
    categories = {
        { key = 'general', label = 'General' },
        { key = 'poses', label = 'Idles & leaning' },
        { key = 'sit_lie', label = 'Sitting & lying' },
        { key = 'work', label = 'Work & chores' },
        { key = 'food_drink', label = 'Food, drink & smoke' },
        { key = 'music', label = 'Music' },
    },

    emotes = {
        -- general
        { cmd = 'inspect', label = 'Crouch & Inspect', category = 'general', scenario = 'WORLD_HUMAN_CROUCH_INSPECT' },
        { cmd = 'notebook', label = 'Write in Notebook', category = 'general', scenario = 'WORLD_HUMAN_WRITE_NOTEBOOK' },
        { cmd = 'mirror', label = 'Pocket Mirror (women)', category = 'general', scenario = 'WORLD_HUMAN_POCKET_MIRROR' },
        { cmd = 'fan', label = 'Fan Yourself (women)', category = 'general', scenario = 'WORLD_HUMAN_FAN' },
        { cmd = 'washface', label = 'Wash Face', category = 'general', scenario = 'WORLD_HUMAN_WASH_FACE_BUCKET_GROUND' },
        { cmd = 'pee', label = 'Relieve Yourself', category = 'general', scenario = 'WORLD_HUMAN_PEE' },
        { cmd = 'mourn', label = 'Mourn at a Grave', category = 'general', scenario = 'WORLD_HUMAN_GRAVE_MOURNING_KNEEL' },

        -- idles & leaning
        { cmd = 'stoic', label = 'Stand Stoic', category = 'poses', scenario = 'WORLD_HUMAN_STARE_STOIC' },
        { cmd = 'impatient', label = 'Wait Impatiently', category = 'poses', scenario = 'WORLD_HUMAN_WAITING_IMPATIENT' },
        { cmd = 'badass', label = 'Badass', category = 'poses', scenario = 'WORLD_HUMAN_BADASS' },
        { cmd = 'lean', label = 'Lean on Wall', category = 'poses', scenario = 'WORLD_HUMAN_LEAN_BACK_WALL' },
        { cmd = 'leanleft', label = 'Lean Left', category = 'poses', scenario = 'WORLD_HUMAN_LEAN_WALL_LEFT' },
        { cmd = 'leanright', label = 'Lean Right', category = 'poses', scenario = 'WORLD_HUMAN_LEAN_WALL_RIGHT' },
        { cmd = 'leanrail', label = 'Lean on Railing', category = 'poses', scenario = 'WORLD_HUMAN_LEAN_RAILING' },
        { cmd = 'leanpost', label = 'Lean on Post', category = 'poses', scenario = 'WORLD_HUMAN_LEAN_POST_RIGHT' },
        { cmd = 'whittle', label = 'Lean & Whittle', category = 'poses', scenario = 'WORLD_HUMAN_LEAN_BACK_WHITTLE' },
        { cmd = 'checkpistol', label = 'Lean & Check Pistol', category = 'poses', scenario = 'WORLD_HUMAN_LEAN_CHECK_PISTOL' },
        { cmd = 'newspaper', label = 'Read the Paper', category = 'poses', scenario = 'WORLD_HUMAN_LEAN_READ_PAPER' },

        -- sitting & lying
        { cmd = 'sit', label = 'Sit on the Ground', category = 'sit_lie', scenario = 'WORLD_HUMAN_SIT_GROUND' },
        { cmd = 'chair', label = 'Sit in a Chair', category = 'sit_lie', scenario = 'PROP_HUMAN_SEAT_CHAIR' },
        { cmd = 'sleep', label = 'Sleep on the Ground', category = 'sit_lie', scenario = 'WORLD_HUMAN_SLEEP_GROUND_ARM' },
        { cmd = 'passout', label = 'Passed Out', category = 'sit_lie', scenario = 'WORLD_HUMAN_DRUNK_PASSED_OUT_FLOOR' },
        { cmd = 'sitcoffee', label = 'Sit with Coffee', category = 'sit_lie', scenario = 'WORLD_HUMAN_SIT_GROUND_COFFEE_DRINK' },

        -- work & chores
        { cmd = 'broom', label = 'Sweep', category = 'work', scenario = 'WORLD_HUMAN_BROOM_WORKING' },
        { cmd = 'pushbroom', label = 'Push Broom', category = 'work', scenario = 'WORLD_HUMAN_PUSH_BROOM_WORKING' },
        { cmd = 'cleantable', label = 'Wipe the Table', category = 'work', scenario = 'WORLD_HUMAN_CLEAN_TABLE' },
        { cmd = 'cleanwindow', label = 'Clean a Window (women)', category = 'work', scenario = 'WORLD_HUMAN_CLEAN_WINDOW' },
        { cmd = 'cleanglass', label = 'Polish a Glass', category = 'work', scenario = 'WORLD_HUMAN_BARTENDER_CLEAN_GLASS' },
        { cmd = 'shopkeep', label = 'Mind the Shop', category = 'work', scenario = 'WORLD_HUMAN_SHOPKEEPER' },
        { cmd = 'rake', label = 'Rake', category = 'work', scenario = 'WORLD_HUMAN_FARMER_RAKE' },
        { cmd = 'hay', label = 'Pitch Hay', category = 'work', scenario = 'WORLD_HUMAN_PITCH_HAY_SCOOP' },
        { cmd = 'chickens', label = 'Feed Chickens', category = 'work', scenario = 'WORLD_HUMAN_FEED_CHICKEN' },
        { cmd = 'pigs', label = 'Feed Pigs', category = 'work', scenario = 'WORLD_HUMAN_FEED_PIGS' },
        { cmd = 'pickaxe', label = 'Pickaxe', category = 'work', scenario = 'WORLD_HUMAN_PICKAXE_WALL' },
        { cmd = 'fire', label = 'Tend a Fire', category = 'work', scenario = 'WORLD_HUMAN_FIRE_TEND_KNEEL' },
        { cmd = 'brushhorse', label = 'Brush Horse', category = 'work', scenario = 'WORLD_HUMAN_HORSE_TEND_BRUSH_LINK' },

        -- food, drink & smoke
        { cmd = 'smoke', label = 'Smoke', category = 'food_drink', scenario = 'WORLD_HUMAN_SMOKE' },
        { cmd = 'cigar', label = 'Cigar', category = 'food_drink', scenario = 'WORLD_HUMAN_SMOKE_CIGAR' },
        { cmd = 'drink', label = 'Drink', category = 'food_drink', scenario = 'WORLD_HUMAN_DRINKING' },
        { cmd = 'drunk', label = 'Drink (Drunk)', category = 'food_drink', scenario = 'WORLD_HUMAN_DRINKING_DRUNK' },
        { cmd = 'coffee', label = 'Coffee', category = 'food_drink', scenario = 'WORLD_HUMAN_COFFEE_DRINK' },
        { cmd = 'cook', label = 'Cook Canned Food', category = 'food_drink', scenario = 'WORLD_HUMAN_CANNED_FOOD_COOKING' },
        { cmd = 'bucketdrink', label = 'Drink from a Bucket', category = 'food_drink', scenario = 'WORLD_HUMAN_BUCKET_DRINK_GROUND' },

        -- music
        { cmd = 'trumpet', label = 'Trumpet', category = 'music', scenario = 'WORLD_HUMAN_TRUMPET' },
        { cmd = 'harmonica', label = 'Harmonica (Ledge)', category = 'music', scenario = 'WORLD_HUMAN_SEAT_LEDGE_HARMONICA' },
        { cmd = 'banjo', label = 'Banjo (Chair)', category = 'music', scenario = 'PROP_HUMAN_SEAT_CHAIR_BANJO' },
        { cmd = 'guitar', label = 'Guitar (Chair)', category = 'music', scenario = 'PROP_HUMAN_SEAT_CHAIR_GUITAR' },
    },

    walks = {
        { cmd = 'tipsy', label = 'Tipsy', loco = 'moderate_drunk' },
        { cmd = 'drunk', label = 'Drunk', loco = 'very_drunk' },
        { cmd = 'hurt', label = 'Hurt', loco = 'injured_general' },
        { cmd = 'limpleft', label = 'Limp (Left Leg)', loco = 'injured_left_leg' },
        { cmd = 'limpright', label = 'Limp (Right Leg)', loco = 'injured_right_leg' },
        { cmd = 'side', label = 'Hurt in the Side', loco = 'injured_torso' },
        { cmd = 'parched', label = 'Parched', loco = 'dehydrated_unarmed' },
        { cmd = 'cold', label = 'Cold', loco = 'snow' },
        { cmd = 'sad', label = 'Sad', loco = 'sad' },
        { cmd = 'downcast', label = 'Downcast', loco = 'depressed' },
        { cmd = 'angry', label = 'Angry', loco = 'angry' },
        { cmd = 'menacing', label = 'Menacing', loco = 'intimidate' },
        { cmd = 'brave', label = 'Brave', loco = 'default_brave' },
        { cmd = 'nervous', label = 'Nervous', loco = 'nervous' },
        { cmd = 'scared', label = 'Scared', loco = 'scared' },
        { cmd = 'cautious', label = 'Cautious', loco = 'cautious' },
        { cmd = 'sneak', label = 'Sneaking', loco = 'stealth' },
        { cmd = 'shackled', label = 'Shackled', loco = 'chain_gang_legs' },
    },
    moods = {},
}
