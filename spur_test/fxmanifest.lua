fx_version 'cerulean'
-- RedM (spur_test, 23 Nov 2026): RedM, not FiveM. whip_test 1.0.0 ported for spur_core (README.md, NOTICE.md).
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

name 'spur_test'
author 'Whippy and WLVF (whip_test); RedM port, non-commercial'
description 'Automated test suite for spur_core on RedM. For a test server only.'
version '1.0.0-redm.1'

dependency 'spur_core'
whip_requires '1.0'   -- the spur_core it is built for: the setup report flags an older one

-- A stand-in theme resource for module 69 (spur_core/server/property_themes.lua): its exports are in
-- server/tests/69_property_themes.lua, and it has no homes but while that module runs.
whip_interior_themes 'v1'

-- The /test menu's sections: which test modules each card runs. Both halves need it — the server
-- runs its modules by section, and so does the client.
shared_scripts {
    -- RedM (spur_test, 23 Nov 2026): spur_core's compat layer, first, so a test reads a native the way spur_core
    -- writes it (GetEntityProofs gives GTA's nine values from RDR2's bitset) and a GTA-only call is a quiet stub
    -- here as it is there, not a nil call. Only spur_core registers its commands.
    '@spur_core/shared/rdr_compat.lua',
    '@spur_core/shared/rdr_compat_stubs.lua',
    'shared/redm.lua',   -- RedM (spur_test, 23 Nov 2026): what the tests use on RedM
    'shared/sections.lua',
    -- whip's satellite helper (Whip.register / call / ready), included the way any resource
    -- includes it — module 46 tests it from here.
    '@spur_core/lib/satellite.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/runner.lua',
    -- What the Director modules (76 on) build and run their scenarios with: before them.
    'server/director_kit.lua',
    'server/tests/*.lua',
    -- Load test. Shares nothing with the suite above except the NUI page, and does nothing at all
    -- until /testload is typed.
    'server/loadtest.lua',
}

client_scripts {
    -- RedM (spur_test, 23 Nov 2026): spur_core's emote list (EmoteList), so module 16 tests the emotes, walks and
    -- moods spur_core actually has rather than GTA's.
    '@spur_core/shared/emote_list.lua',
    'client/runner.lua',
    -- What the Director modules ask this game: where things are, what they do.
    'client/director_kit.lua',
    'client/tests/*.lua',
    'client/loadtest.lua',
    -- The deliberate cheat: writes watched statebag keys the way a cheat menu would, so
    -- the Sentinel can be proven against a genuinely client-originated tamper. Gated by
    -- this resource not being ensured — it exists only while spur_test is manually started.
    'client/sn_tamper.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/report.css',
    'html/js/report.js',
    -- The /test menu: a card per section, and the full-suite button.
    'html/css/menu.css',
    'html/js/menu.js',
    -- Load-test panel. Its own stylesheet and script because it uses spur_core's overlay language
    -- rather than this resource's report styling.
    'html/css/load.css',
    'html/js/load.js',
}
