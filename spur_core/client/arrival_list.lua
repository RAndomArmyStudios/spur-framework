-- ============================================
-- EVERY ARRIVAL SCENE — client/arrival_list.lua
-- ============================================
--
-- The scenes the settings page offers for the login's lists (/whip → Settings → Joining, sent by
-- tools/panel_sections/config.lua); the login takes a scene's prop from here when its Config.ArrivalScenes
-- line has none (client/arrival.lua).
--
-- RedM (spur_core, 26 Nov 2026): whip_core's list was the original game's story scenes (its three leads' switch scenes),
-- and is gone. Empty: add scenes to Config.ArrivalScenes yourself.
--
--   key     the scene's name (dictionary/clip)
--   cam     the camera move; none: it plays under the game camera
--   prop    { model, how = clip|drop|hide|set, clip?, bone?, pos?, rot?, at? } — client/arrival.lua
--   others  made with other people, who will not be there
--   car     made with a car or bike in it
--
-- The same shape as Config.ArrivalScenes' entries, so a line can be copied there as it is.

ArrivalSceneList = {}
