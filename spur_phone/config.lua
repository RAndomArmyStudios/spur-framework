Config = {}
-- RedM (spur_phone, 24 Nov 2026): the phone is a pocket notebook (1899). The keys, the pages it holds, the places
-- where an errand can be done (telegraph offices, telephones, bank counters), how it is held and how it sounds.

-- Open / close key. Players can rebind it in the game's key binding settings ("Notebook: open / close"). A new
-- default reaches only players who have not bound the key yet.
Config.OpenKey = 'F3'

-- Answer / decline a telephone call ringing in, with the notebook out or put away. Players can rebind them too
-- ("Notebook: answer a call", "Notebook: decline a call"). A new default reaches only players who have not bound
-- the key yet.
Config.AnswerKey = 'Y'
Config.DeclineKey = 'U'

-- The closed notebook's height as a share of the screen height (the open spread sizes itself to the screen).
Config.PhoneSize = 0.5

-- Built-in pages (modules), in html/modules/<id>/module.js. A module whose folder is deleted is simply skipped, and
-- with no modules at all the notebook still opens, empty. A new one also needs its own line in fxmanifest.lua's
-- files { } or players never receive it. Other resources add pages with exports.spur_phone:RegisterModule.
--   phone     Telephone       messages  Telegrams       bank      Passbook
--   business  Ledger          settings  Settings        skillcheck  the skill check games (hidden)
Config.Modules = { 'phone', 'messages', 'bank', 'business', 'settings', 'skillcheck' }

-- Built-in pages only developers see: players with dev tools who turned developer mode on in /w. They come and go
-- as it is switched. Each also needs its own line in fxmanifest.lua's files { }.
--   skilltest   Skill Check Tester: plays any skill check (the ring or a notebook game) at any level, with the
--               numbers changed for the test (they are never saved: config.lua stays as it is)
Config.DeveloperApps = { 'skilltest' }

-- The framework must answer the 'spur_phone:session' callback before the notebook opens (refuse it for "no notebook
-- / no address card"). false lets the notebook open without one (development).
Config.RequireSession = true

-- The clock on the page: true = in-game time, false = the player's real clock.
Config.GameClock = true

-- spur_core BlockControls groups held while the notebook has focus (walking stays free).
Config.BlockControls = { 'combat', 'look', 'vehicleCombat', 'weaponWheel' }

-- RedM (spur_phone, 24 Nov 2026): what the player holds while the notebook is out: an emote's /e name from
-- spur_core's emote list (spur_core/shared/emote_list.lua). '' (the default) holds nothing: whip_phone's were GTA
-- phone and tablet animations, and no RDR2 notebook animation has been tried in game yet. Name one here once it has.
-- A player already in an emote (sitting, leaning) is left as they are.
Config.Emotes = {
    phone  = '',   -- the notebook closed in one hand
    tablet = '',   -- the notebook open in both hands
}

-- RedM (spur_phone, 24 Nov 2026): look and sound on a fresh notebook; the player's own choices (Settings) come back
-- with the session.
--   wallpaper    the cover: tan, oxblood, bottle, navy, black, ledger, foolscap, onionskin (html/core/wallpaper.js)
--   ringtone     bell (an electric telephone bell), candlestick, handbell, chime, silent
--   messageTone  telegraph (a sounder's clicks), chime, bell, tap, none   (a telegram arriving)
--   notifyTone   the same list                                            (any other notice)
--   soundVolume  0 to 100 (Settings offers 25, 50, 75 and 100)
-- The sounds are made by the page itself (html/core/sounds.js), no files. Each address card keeps its own choices.
Config.Defaults = {
    wallpaper   = 'tan',
    ringtone    = 'bell',
    messageTone = 'telegraph',
    notifyTone  = 'chime',
    soundVolume = 75,
}

-- ---------------------------------------------------------------- where errands are done (RedM, 24 Nov 2026)
-- Telegrams are written anywhere and read anywhere, but SENT only at a telegraph office. A telephone call is
-- placed only at a telephone (answering one works anywhere: see README.md). Moving money (transfers, opening,
-- closing and sharing accounts) is done at a bank counter; balances and history read anywhere. The server checks
-- each one against the player's position; the page names the nearest one.
-- false lets everything be done anywhere (testing).
Config.PlaceChecks = true

-- Each place: label (what players read), coords, radius in metres.
-- RedM (spur_phone, 24 Nov 2026): each telegraph office is where a player stands at the telegraph window, taken in
-- game on 24 Nov 2026 (SPUR_PORTS.md lists them). A radius of 4 metres takes in the counter and a step back from it.
-- To add one, stand at the window, take the position (/vec4) and give it the same radius.
Config.TelegraphOffices = {
    { label = 'Valentine station',      coords = vector3(-178.9, 626.7, 114.1),     radius = 4.0 },
    { label = 'Rhodes station',         coords = vector3(1225.6, -1293.9, 76.9),    radius = 4.0 },
    { label = 'Saint Denis station',    coords = vector3(2747.1, -1396.7, 46.2),    radius = 4.0 },
    { label = 'Blackwater station',     coords = vector3(-875.2, -1328.9, 44.0),    radius = 4.0 },
    { label = 'Armadillo',              coords = vector3(-3733.9, -2597.6, -12.9),  radius = 4.0 },
    { label = 'Annesburg station',      coords = vector3(2938.6, 1286.5, 44.7),     radius = 4.0 },
    { label = 'Strawberry',             coords = vector3(-1765.1, -384.2, 157.7),   radius = 4.0 },
    { label = 'Emerald Ranch station',  coords = vector3(1521.2, 439.4, 90.7),      radius = 4.0 },
}

-- Telephones were rare in 1899: the station agent's telephone, at the telegraph window of the bigger towns.
Config.Telephones = {
    { label = 'Saint Denis station', coords = vector3(2747.1, -1396.7, 46.2),  radius = 4.0 },
    { label = 'Valentine station',   coords = vector3(-178.9, 626.7, 114.1),   radius = 4.0 },
    { label = 'Rhodes station',      coords = vector3(1225.6, -1293.9, 76.9),  radius = 4.0 },
    { label = 'Blackwater station',  coords = vector3(-875.2, -1328.9, 44.0),  radius = 4.0 },
    { label = 'Annesburg station',   coords = vector3(2938.6, 1286.5, 44.7),   radius = 4.0 },
}

-- The bank counters, as spur_core's Config.BankCounters has them (its own ATM check on RedM does not read those, so
-- the notebook keeps its own copy). RedM (spur_phone, 24 Nov 2026): all four walked in game with spur_core's; the
-- Valentine point moved with spur_core's from the teller's side of the counter to the lobby.
Config.BankSpots = {
    { label = 'Valentine',   coords = vector3(-308.72, 775.90, 118.70),  radius = 8.0 },
    { label = 'Blackwater',  coords = vector3(-813.18, -1277.60, 43.68), radius = 8.0 },
    { label = 'Saint Denis', coords = vector3(2644.08, -1292.21, 52.29), radius = 8.0 },
    { label = 'Rhodes',      coords = vector3(1294.14, -1303.06, 77.04), radius = 8.0 },
}

-- ---------------------------------------------------------------- addresses and address cards (Josh, 7 Oct 2026)
-- An address (a phone number in the database) belongs to a character. A telegraph address card carries one: keep
-- it in any notebook and you send telegrams and place calls as that address, with its contacts and telegrams. A
-- card bought in a shop gets a new address for its buyer; one made for nobody (a stash, a reward) gets one for
-- whoever first puts it in a notebook.

-- New addresses start with one of these, then 7 random digits.
Config.NumberPrefixes = { '689', '041', '227', '869', '915' }

-- Seconds an unanswered call rings before it is missed.
Config.RingSeconds = 30

-- How many of an address's telegrams and calls the notebook loads.
Config.MessageHistory = 300
Config.RecentCalls = 50

-- ---------------------------------------------------------------- the sound of a call (the voice system)
-- A call carries what each side says with their normal talk key; the people around them still hear them as usual.
-- The voice system plays it; the notebook only says how it should sound (a recipe of sound blocks). A voice system
-- whose `sounds` feature is 'basic' plays a plain telephone filter at most and may skip the rest.
Config.CallSound = {
    { 'band', low = 300, high = 3400 },          -- the telephone band: no lows, no highs
    { 'drive', k = 1.5 },                         -- a little line grit
    { 'compress', threshold = -24, ratio = 4 },   -- even, like a telephone line
    { 'noise', kind = 'pink', level = 0.008 },    -- a faint line hiss, only while they talk
    { 'gain', db = -2 },
}

-- How far a telephone call carries out loud, in metres (1-30), on a voice system with the `speaker` feature. With
-- none (spur_voice has none), there is no speaker: only the one holding the receiver hears the call.
Config.SpeakerRange = 8

-- RedM (spur_phone, 24 Nov 2026): what the Telephone page says while no voice system is running. Only telephone
-- calls need one: telegrams, the passbook and the ledger work without it.
Config.VoiceDownText = 'The telephone lines are down: no voice system is running.'

-- ---------------------------------------------------------------- skill check games in the notebook
-- spur_core's skill check can play one of these in the notebook instead of the ring: the notebook comes out open,
-- held to the game until it is over (no index, no closing, Back gives up). Pick one in the Director's Skill Check
-- card (Game), or from a script: exports.spur_core:SkillCheck(source, 'hard', { game = 'phone.reroute' }).
-- Every input is a single press, so a controller and a keyboard play the same game at the same difficulty.
--
-- A player with no notebook is told this, and nothing starts. It is not a fail: they can try again with one.
Config.SkillGameNoPhone = 'You need a notebook!'

-- Each game has three levels: easy, medium and hard. `seconds` is a level's clock (running out is a fail).
-- `enabled = false` takes a game out (the Director stops offering it). Times are in seconds unless they say Ms.
Config.SkillGames = {
    -- BRUTE FORCE: letters scroll through a reel; press as the reel's letter crosses the line to lock it.
    --   reels: how many · speed: letters a second · letters: on each reel · window: how close to the line counts
    --   (0.5 = half a letter) · missCost: seconds a miss costs · set: 'clear' (no lookalikes), 'mixed' or 'all' ·
    --   lookalikes: 8 and B, O and 0 right beside the real letter · bothWays: every other reel scrolls the other way
    bruteforce = {
        easy   = { reels = 4, speed = 3.2, letters = 12, window = 0.32, missCost = 2, set = 'clear', lookalikes = false, bothWays = false, seconds = 25 },
        medium = { reels = 6, speed = 4.4, letters = 16, window = 0.27, missCost = 3, set = 'mixed', lookalikes = false, bothWays = false, seconds = 32 },
        hard   = { reels = 8, speed = 5.6, letters = 20, window = 0.22, missCost = 4, set = 'all',   lookalikes = true,  bothWays = true,  seconds = 40 },
    },
    -- CODE RECALL: a code flashes one arrow at a time; enter it back. Each round is longer.
    --   rounds: the code's length each round · flashMs / gapMs: how long each arrow shows, and the pause after it ·
    --   mistakes: allowed (a mistake shows the code again) · newCode: a new code each round (otherwise it grows) ·
    --   lastBackwards: the last round is entered backwards
    coderecall = {
        easy   = { rounds = { 3, 4, 5 },    flashMs = 560, gapMs = 220, mistakes = 2, newCode = false, lastBackwards = false, seconds = 45 },
        medium = { rounds = { 4, 5, 6, 7 }, flashMs = 430, gapMs = 170, mistakes = 1, newCode = false, lastBackwards = false, seconds = 55 },
        hard   = { rounds = { 5, 6, 7, 8 }, flashMs = 330, gapMs = 130, mistakes = 0, newCode = true,  lastBackwards = true,  seconds = 60 },
    },
    -- FRAGMENT MATCH: slide each column until the middle line spells the code at the top, then check it.
    --   columns · letters: in each column · afterWrong: 'columns' (marks the wrong ones), 'count' (says how many) or
    --   'nothing' · lookalikes: beside the real one · wrongCost: seconds a wrong check costs
    fragmentmatch = {
        easy   = { columns = 4, letters = 6,  afterWrong = 'columns', lookalikes = false, wrongCost = 3, seconds = 40 },
        medium = { columns = 6, letters = 8,  afterWrong = 'count',   lookalikes = false, wrongCost = 4, seconds = 45 },
        hard   = { columns = 8, letters = 10, afterWrong = 'nothing', lookalikes = true,  wrongCost = 5, seconds = 50 },
    },
    -- OVERRIDE: arrows fall to a line; press each as it crosses. A press with nothing there is a miss too.
    --   lanes: 3 or 4 · arrows: how many · fallSeconds: top to line · windowMs: how early or late still counts ·
    --   gapMs: time between arrows, at least min and at most max · misses: allowed. Its clock is the track's length.
    override = {
        easy   = { lanes = 3, arrows = 14, fallSeconds = 1.9,  windowMs = 140, gapMs = { min = 620, max = 1000 }, misses = 4 },
        medium = { lanes = 4, arrows = 20, fallSeconds = 1.5,  windowMs = 110, gapMs = { min = 430, max = 760 },  misses = 3 },
        hard   = { lanes = 4, arrows = 26, fallSeconds = 1.15, windowMs = 85,  gapMs = { min = 300, max = 560 },  misses = 2 },
    },
    -- REROUTE: turn the tiles until a line of pipe runs from Power to Exit. Every grid can be solved.
    --   grid: 3 to 6 tiles a side · keepRight: share of the path's tiles already turned right (0-1) · decoys: how
    --   often each other tile is a straight, an elbow, a T or a dead end
    reroute = {
        easy   = { grid = 4, keepRight = 0.2,  decoys = { straight = 4, elbow = 5, tee = 1, dead = 0 }, seconds = 40 },
        medium = { grid = 5, keepRight = 0.15, decoys = { straight = 3, elbow = 5, tee = 2, dead = 1 }, seconds = 50 },
        hard   = { grid = 6, keepRight = 0.1,  decoys = { straight = 3, elbow = 4, tee = 3, dead = 2 }, seconds = 60 },
    },
    -- SAFE CRACK: turn the dial a notch at a time; the right number gives a heavy click. Set it, turn the other way.
    --   numbers: in the combination · hint: within how many notches the clicks get heavier (0 = the exact number
    --   only) · wrongCost: seconds a wrong number costs · wrongRestarts: a wrong number goes back to the first
    safecrack = {
        easy   = { numbers = 2, hint = 2, wrongCost = 3, wrongRestarts = false, seconds = 40 },
        medium = { numbers = 3, hint = 1, wrongCost = 4, wrongRestarts = false, seconds = 50 },
        hard   = { numbers = 4, hint = 0, wrongCost = 4, wrongRestarts = true,  seconds = 60 },
    },
    -- STABILISE: hold to push the needle up, let go and it falls; keep it in the band while the drill works.
    --   band: its size (share of the gauge) · bandSpeed: how fast it moves · drillSeconds: time in the band needed ·
    --   leaving: how fast the drill loses progress outside the band (0 = it only pauses) · overheatSeconds: in the red
    stabilise = {
        easy   = { band = 0.26, bandSpeed = 0.07, drillSeconds = 7,  leaving = 0,    overheatSeconds = 1.6, seconds = 25 },
        medium = { band = 0.2,  bandSpeed = 0.11, drillSeconds = 9,  leaving = 0.25, overheatSeconds = 1.3, seconds = 30 },
        hard   = { band = 0.14, bandSpeed = 0.16, drillSeconds = 11, leaving = 0.5,  overheatSeconds = 1.0, seconds = 36 },
    },
}

Config.Debug = false
