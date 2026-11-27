fx_version 'cerulean'
-- RedM (spur_loadingscreen, 23 Nov 2026): A port of whip_loadingscreen 1.6.2 for spur_core (README.md,
-- NOTICE.md): the SPUR wordmark in place of WHIP's logo, and an 1899 backdrop in CSS in place of the three.js blueprint.
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

name 'spur_loadingscreen'
author 'Whippy and WLVF (whip_loadingscreen); RedM port, non-commercial'
description 'Loading screen for spur_core on RedM: the SPUR wordmark on an 1899 backdrop, the circles in its bar the loading light.'
version '1.6.2-redm.1'

-- `loadscreen`, not `ui_page`. The game shows this page from the moment the player connects until
-- something calls ShutdownLoadingScreen.
loadscreen 'html/index.html'

-- NO `loadscreen_manual_shutdown`. That key hands responsibility for dismissing the screen to this
-- resource, and nothing here is in a position to know when the world is ready. spur_core's own
-- spawn flow calls ShutdownLoadingScreen once the player is in the world (client/spawn.lua) —
-- spawnmanager is not used — so the default is both correct and already wired.

-- This resource has NO Lua at all. A loading screen is pure NUI, and this one needs nothing from the
-- game: the logo's light and the backdrop run on their own until the screen is taken away.

-- RedM (spur_loadingscreen, 23 Nov 2026): whip_loadingscreen's blueprint (html/bp: three.js, a scene and its
-- picture atlas) and the dev/ tools that made it are not in this copy, nor its browser preview page. The backdrop is
-- CSS (html/css/loading.css). To look at the screen in a browser, open html/index.html.
files {
    'html/index.html',
    'html/css/loading.css',
    'html/js/icons.js',
    'html/js/logo.js',
}
