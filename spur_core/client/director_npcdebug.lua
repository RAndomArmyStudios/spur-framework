-- Director NPC debug in a test (J): over each NPC, what it is doing and why. The server sends the lines once a
-- second while on (server/director/hub.lua, Npcs.explain); each is drawn when the tester is within NEAR_M of the
-- NPC or looks at it within LOOK_M. What only this game sees (GTA's AI fighting or running) overrides the server's
-- word. Text needs a per-frame loop, run only while on.

DirectorNpcDebug = {}

local NEAR_M, LOOK_M = 25.0, 90.0
local HEAD = 31086
local REACTING = 'Reacts to danger is on (the game\'s own reaction)'

local list = nil     -- the server's lines, while it is on
local wanted = false

--- J in a test (client/director.lua makeKeys): on, or off.
function DirectorNpcDebug.toggle()
    wanted = not wanted
    TriggerServerEvent('spur_core:server:directorNpcDebug', wanted)
    UI.Notify(wanted and 'NPC debug on: go near an NPC of the test, or look at one' or 'NPC debug off', 'info', 3000)
end

--- Is the camera looking at a point: within a cone that is wider the nearer it is (a body's width), and LOOK_M.
local function lookedAt(cam, fwd, at)
    local dx, dy, dz = at.x - cam.x, at.y - cam.y, at.z - cam.z
    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
    if d < 0.5 or d > LOOK_M then return false end
    local cone = math.max(math.rad(3.0), math.atan(1.2, d))
    return (dx * fwd.x + dy * fwd.y + dz * fwd.z) / d >= math.cos(cone)
end

--- The server's two lines, or this game's when GTA's own AI has taken it over.
local function linesFor(e, ped)
    local what, why = e.what, e.why
    if e.reacts and e.state ~= 'fighting' and e.state ~= 'fleeing' and e.state ~= 'dead' then
        if IsPedFleeing(ped) then
            what, why = 'Reacting to danger: running away', REACTING
        elseif IsPedInCombat(ped, 0) then
            what = IsPedInCombat(ped, PlayerPedId()) and 'Reacting to danger: fighting you' or 'Reacting to danger: fighting'
            why = REACTING
        end
    end
    return what, why
end

local function text(s, y, scale, r, g, b)
    SetTextScale(0.0, scale)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(r, g, b, 235)
    SetTextOutline()
    SetTextCentre(true)
    SetTextEntry('STRING')
    AddTextComponentString(s)
    DrawText(0.0, y)
end

local function draw(e, ped)
    local what, why = linesFor(e, ped)
    local head = GetPedBoneCoords(ped, HEAD, 0.0, 0.0, 0.0)
    SetDrawOrigin(head.x, head.y, head.z + 0.45, 0)
    text(e.name or '', -0.062, 0.26, 170, 178, 190)
    text(what or '', -0.044, 0.33, 255, 255, 255)
    text(why or '', -0.020, 0.28, 255, 214, 120)
    ClearDrawOrigin()
end

local function loop()
    CreateThread(function()
        while list do
            local me = GetEntityCoords(PlayerPedId())
            local cam = GetFinalRenderedCamCoord()
            local rot = GetFinalRenderedCamRot(2)
            local rx, rz = math.rad(rot.x), math.rad(rot.z)
            local fwd = { x = -math.sin(rz) * math.cos(rx), y = math.cos(rz) * math.cos(rx), z = math.sin(rx) }
            for _, e in ipairs(list) do
                local ped = DirectorKit.entityOfNet(e.net)
                if ped then
                    local c = GetEntityCoords(ped)
                    if #(c - me) <= NEAR_M or lookedAt(cam, fwd, c) then draw(e, ped) end
                end
            end
            Wait(0)
        end
    end)
end

RegisterNetEvent('spur_core:client:directorNpcDebug', function(l)
    if l == false then
        list, wanted = nil, false
        return
    end
    if type(l) ~= 'table' then return end
    local was = list ~= nil
    list = l
    if not was then loop() end
end)
