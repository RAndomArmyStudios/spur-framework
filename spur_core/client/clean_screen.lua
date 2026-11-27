-- ============================================
-- CLEAN SCREEN — nothing on screen but the game's picture, for recording
-- ============================================
--
-- The Camera Creator's play mode holds it while a shot rolls (and the whole time, if the player chose
-- that), so a recording (OBS, ShadowPlay) has the picture alone. While anything holds it:
--
--   The game's own    HUD and radar, every frame (HideHudAndRadarThisFrame)
--   whip's page  every layer of it hidden (html.whip-clean, css/ui.css) but what the holder shows itself
--   the world    3D prompts, /me bubbles, bay decals: WorldQuad.draw draws nothing (client/world_quad.lua) while
--                any hold hides the world (CleanScreen.world), as every hold does but one that keeps it (the
--                camera item's, unless Config.CameraHidesDui); the black skin's map frame goes with the HUD
--                (client/hud_skin.lua)
--   others       told by the event 'spur_core:ui:cleanScreen' ({ on, world }), to put their own away
--
-- Hidden, not closed: a screen opened meanwhile still works, it just cannot be seen — so a holder lets go
-- as soon as its reason has passed.
--
--     CleanScreen.hold('cameraLive')
--     CleanScreen.hold('cameraItem', { keepWorld = true })   -- the HUD and the page go; the world's things stay
--     CleanScreen.release('cameraLive')
--     if CleanScreen.on then ... end      -- cheap enough for a frame loop

CleanScreen = { on = false, world = false }

local holds = {}       -- [id] = { world = true when it hides the world's things too }
local hiding = false   -- the HUD-hiding loop is running: an off and an on in one frame must not start a second

local function refresh()
    local want, world = next(holds) ~= nil, false
    for _, h in pairs(holds) do if h.world then world = true end end
    if want == CleanScreen.on and world == CleanScreen.world then return end
    local was = CleanScreen.on
    CleanScreen.on, CleanScreen.world = want, world
    WhipEmit('spur_core:ui:cleanScreen', { on = want, world = world })
    if want == was then return end
    SendNUIMessage({ action = 'cleanScreen', on = want })
    if want and not hiding then
        hiding = true
        CreateThread(function()
            while CleanScreen.on do
                HideHudAndRadarThisFrame()
                Wait(0)
            end
            hiding = false
        end)
    end
end

---@param id string  who holds it (released by the same id)
---@param opts table|nil  { keepWorld = true }: whip's things in the world (prompts, /me bubbles, decals) stay drawn
function CleanScreen.hold(id, opts)
    holds[id] = { world = not (type(opts) == 'table' and opts.keepWorld == true) }
    refresh()
end

---@param id string
function CleanScreen.release(id)
    holds[id] = nil
    refresh()
end

-- ---- For other resources (whip_scenes' cutscenes, Josh 22 Oct 2026) ----
--
--     exports.spur_core:HoldCleanScreen('take')      -- everything above goes; true
--     exports.spur_core:ReleaseCleanScreen('take')   -- back, once nothing else holds it
--
-- Held under '<resource>:<id>', so one resource cannot let go of another's, and let go of when that
-- resource stops: a crash mid-take never leaves the player with no HUD. Chat is whip_chat's own frame,
-- so it stays (its F6 hides it). On whip's registry (shared/registry.lua), its owners and its sweep, not a
-- hand-rolled copy of them (audit 20, CLI-4).

local holdsByResource = Registry.new('cleanScreen', {
    label    = 'clean screen hold',
    scoped   = true,   -- '<resource>:<id>'
    onAdd    = function(key) CleanScreen.hold(key) end,
    onRemove = function(key) CleanScreen.release(key) end,
})

exports('HoldCleanScreen', function(id)
    if not GetInvokingResource() then return false end
    return holdsByResource:add(Registry.caller(), tostring(id or 'default'), true)
end)

exports('ReleaseCleanScreen', function(id)
    if not GetInvokingResource() then return false end
    local owner, key = Registry.caller(), tostring(id or 'default')
    holdsByResource:remove(owner, key)
    return true
end)
