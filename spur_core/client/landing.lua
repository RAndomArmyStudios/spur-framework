-- The landing page: one camera shot with the whip logo and "Press any button to continue", shown between the
-- loading screen and character select (on joining and on a spur_core restart; /logout skips it). Settings:
-- Config.Landing. A plain game camera, since every fade is whip's curtain (client/curtain.lua):
--   arrives  the game's fade is down (spawn.lua)
--   build    TakeFromGame: the curtain holds the black while the shot is built and streamed
--   show     Uncover: the shot and the logo come up
--   press    Cover: the curtain falls and stays down; ShowCharacterSelect carries on from there
-- Input is the page's (html/js/landing.js): it holds NUI focus, and a pad reaches it through
-- client/controller.lua. Nothing here reads a control.

Landing = {}

local _cam     = nil
local _running = false   -- Landing.Run is between its start and its end
local _waiting = false   -- the shot is up and a press is awaited
-- Answered by the press (the page's landingContinue, or Landing.Continue); the landing waits on it.
local _press   = nil

-- How far ahead the view is loaded, in metres: a shot from the hills takes in the whole city.
local LOAD_RADIUS = 2000.0

-- How often focus is given back to the page while waiting (another resource could take it, and without
-- focus no key reaches the page).
local REFOCUS_MS = 1000

--- Put the camera up and move the game's streaming focus there (the game loads only around its focus).
---@param c table  Config.Landing.camera
local function startShot(c)
    local x, y, z = c.pos.x + 0.0, c.pos.y + 0.0, c.pos.z + 0.0
    _cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(_cam, x, y, z)
    SetCamRot(_cam, c.rot.x + 0.0, c.rot.y + 0.0, c.rot.z + 0.0, 2)
    SetCamFov(_cam, (c.fov or 50.0) + 0.0)
    SetCamActive(_cam, true)
    RenderScriptCams(true, false, 0, true, false)
    SetFocusPosAndVel(x, y, z, 0.0, 0.0, 0.0)
end

local function endShot()
    if _cam then
        RenderScriptCams(false, false, 0, true, false)
        DestroyCam(_cam, false)
        _cam = nil
    end
    ClearFocus()
end

--- Load what the camera looks at. Bounded: a view that never reports loaded is shown after `budget` ms.
---@param c table  Config.Landing.camera
---@param budget number  ms
local function streamView(c, budget)
    -- The way the camera faces, from pitch and yaw (rotation order 2, degrees).
    local pitch, yaw = math.rad(c.rot.x), math.rad(c.rot.z)
    local dx = -math.sin(yaw) * math.cos(pitch)
    local dy = math.cos(yaw) * math.cos(pitch)
    local dz = math.sin(pitch)

    local deadline = GetGameTimer() + budget
    if NewLoadSceneStart(c.pos.x + 0.0, c.pos.y + 0.0, c.pos.z + 0.0, dx, dy, dz, LOAD_RADIUS, 0) then
        while not IsNewLoadSceneLoaded() and GetGameTimer() < deadline do Wait(50) end
        NewLoadSceneStop()
    else
        -- No load scene started; the focus is already there, so wait a moment.
        Wait(math.min(budget, 1500))
    end
end

--- The landing itself: shot up, shown, a press, black again. See Landing.Run.
---@param cfg table  Config.Landing
local function run(cfg)
    -- The ped stays at the join spawn, hidden and held still (client/ped_hold.lua) until character select takes over.
    PedHold.set('charselect', { frozen = true, hidden = true })
    DisplayRadar(false)

    -- If the page never answered, go straight on; the game's fade still holds the black ShowCharacterSelect expects.
    if not Curtain.TakeFromGame() then return end

    if cfg.look and WeatherLayer then WeatherLayer.set('landing', cfg.look) end
    startShot(cfg.camera)
    streamView(cfg.camera, tonumber(cfg.streamMs) or 6000)

    _press = promise.new()
    _waiting = true
    SendNUIMessage({ action = 'landingShow', prompt = cfg.prompt })
    -- The spawn picker's map starts building now, so the character screen has less to wait for.
    if Config.CharSelect and SpurPickerOn() then SendNUIMessage({ action = 'spawnselWarm' }) end
    Focus.take('landing')

    -- One frame for the camera to arrive.
    Wait(0)
    Curtain.Uncover(cfg.fadeIn or 800)

    -- Focus back to the page once a second while it waits (REFOCUS_MS)
    local press = _press
    CreateThread(function()
        while _waiting and _press == press do
            Wait(REFOCUS_MS)
            if _waiting and _press == press then Focus.reassert() end
        end
    end)
    Citizen.Await(press)
    if not _waiting then return end   -- spur_core stopping: onResourceStop has tidied up
    _waiting = false
    _press = nil

    Focus.release('landing')
    Curtain.Cover(cfg.fadeOut or 500)

    -- Behind the black now. The logo goes first: the page draws over the game's fade, so it would show through.
    SendNUIMessage({ action = 'landingHide' })
    endShot()
    if WeatherLayer then WeatherLayer.set('landing', nil) end
end

--- Show the landing page and wait for a press. Returns with the screen black for ShowCharacterSelect; returns at
--- once if the page is switched off. Yields, so call from a thread.
function Landing.Run()
    local cfg = Config.Landing
    if type(cfg) ~= 'table' or cfg.enabled == false or type(cfg.camera) ~= 'table' then return end

    -- One landing at a time; a second caller waits for the first.
    if _running then
        while _running do Wait(100) end
        return
    end

    -- Protected, so an error cannot leave _running set or stop the character screen opening.
    _running = true
    local ok, err = pcall(run, cfg)
    _running = false
    if not ok then
        print(('[spur_core:landing] the landing page failed: %s'):format(tostring(err)))
        _waiting = false
        endShot()
        Focus.release('landing')
        SendNUIMessage({ action = 'landingHide' })
        if WeatherLayer then WeatherLayer.set('landing', nil) end
    end
end

--- Go on as a press would, from code (CharSelect.Enter: a game with nobody at it). False when no landing waits.
---@return boolean
function Landing.Continue()
    if not _waiting or not _press then return false end
    _press:resolve(true)
    return true
end

--- The page heard a key, a mouse button or a pad button.
RegisterNUICallback('landingContinue', function(_, cb)
    if _waiting and _press then _press:resolve(true) end
    cb({ ok = true })
end)

-- A stop mid-landing leaves a script camera rendering and focus held; clean both up.
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if not _waiting and not _cam then return end
    _waiting = false
    endShot()
    Focus.release('landing')
end)
