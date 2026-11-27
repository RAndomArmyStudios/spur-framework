-- Director editor, Lua half: opens and closes it (NUI focus, DirectorEditorOpen), forwards the page's
-- requests to server/director/hub.lua, places things through the world builder, and runs Test mode
-- (F5 resets, F9 back to the editor, G hides the test map).

DirectorEditorOpen = false

local hidden = false          -- open, but out of the way while placing
local building = false        -- the world builder (the furnisher) is open for this editor (below)
local uploadToken = 0
local uploadBps = 500000
local testing = nil           -- { name } while a test runs
local backToEditor            -- (Test mode, below)
local isolated = false        -- in a world of our own (Isolate world: server/director/hub.lua)

-- Open and close

--- The weapons an NPC can carry (shared/weapon_catalog.lua), only those this game build has. `from`: which resource
--- added it; `gun`: it has a world model (it can be a Fixed Weapon). Rebuilt when the catalog changes.
local weaponList, weaponListAt
local function weapons()
    if weaponList and weaponListAt == WeaponCatalog.version then return weaponList end
    weaponList, weaponListAt = {}, WeaponCatalog.version
    for _, w in ipairs(WeaponCatalog.list()) do
        if IsWeaponValid(GetHashKey(w.name)) then
            weaponList[#weaponList + 1] = { name = w.name, label = w.label, group = w.group, from = w.from,
                                            gun = WeaponCatalog.modelOf(w.name) ~= nil or nil }
        end
    end
    return weaponList
end

--- Tutorial (html/js/director/tutorial.js): stages finished on this PC, as bits. 0: never opened, so it starts itself.
local TUTORIAL_KVP = 'whip:director:tutorial'

--- The screen; `key` opens that scenario (the /whip Director section's Edit), and `world` goes straight into the
--- world builder on it, the page kept out of sight. None: the editor as it was left (back from a test).
local function open(key, world)
    if testing then backToEditor() return end
    if DirectorEditorOpen or not PlayerLoaded or PlayerIsDead then return end
    if (IsAnyUIOpen and IsAnyUIOpen()) or (FocusScreenUp and FocusScreenUp('none')) then
        UI.Notify('Close what is open first', 'error')
        return
    end
    DirectorEditorOpen, hidden = true, false
    Focus.take('director', { screen = true })
    SendNUIMessage({ action = 'directorOpen', weapons = weapons(), openKey = type(key) == 'string' and key or nil,
                     world = world == true, tutorial = GetResourceKvpInt(TUTORIAL_KVP) })
end

RegisterNUICallback('directorTutorial', function(d, cb)
    cb('ok')
    local n = math.tointeger(tonumber(type(d) == 'table' and d.done or nil))
    if n and n >= 0 and n < 256 then SetResourceKvpInt(TUTORIAL_KVP, n) end
end)

--- From the /whip panel: closes the panel and opens the Director in the world on that scenario.
function DirectorOpenAt(key)
    if WhipPanelIsOpen and WhipPanelIsOpen() then WhipPanelClose() end
    open(key, true)
end

local builderView = nil   -- where the world builder's camera was as Record a take or Fullscreen closed it: { pos, rot, fov }
--- Why the world builder is closing: 'page' (the page goes on), 'test', 'closing' (the Director is closing); nil: its Exit.
local leaving = nil

local closeHooks = {}   -- what else ends with the Director (DirectorScreen.onClose)

local function close()
    if not DirectorEditorOpen then return end
    if building and Furnisher and Furnisher.close then
        leaving = 'closing'
        Furnisher.close()
    end
    builderView = nil
    DirectorEditorOpen, hidden = false, false
    Focus.release('director')
    SendNUIMessage({ action = 'directorClose' })
    TriggerServerEvent('spur_core:server:directorClosed')
    for _, fn in ipairs(closeHooks) do
        local ok, err = pcall(fn)
        if not ok then print('[spur_core:director] something ending with the Director failed: ' .. tostring(err)) end
    end
end

--- Back from placing: the page again, with the mouse. `reopen`: a car's id the page reopens the builder on.
local function show(reopen)
    if not DirectorEditorOpen or not hidden then return end
    hidden = false
    Focus.take('director', { screen = true })
    SendNUIMessage({ action = 'directorShow', reopen = reopen })
end

RegisterNUICallback('directorClose', function(_, cb)
    cb('ok')
    close()
end)

AddEventHandler('spur_core:player:died', close)
AddEventHandler('spur_core:player:logout', close)
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then Focus.release('director') end
end)

-- The page's requests. Each op names its arguments in the order the server's callback takes them;
-- nothing else is forwarded. The page gets { ok = true, data } or { ok = false, why }.

local OPS = {
    list       = {},
    cards      = {},
    open       = { 'key', 'rev' },
    watch      = { 'key', 'rev' },
    history    = { 'key' },
    create     = { 'key', 'name', 'from' },
    activate   = { 'key', 'rev', 'endRuns' },
    deactivate = { 'key', 'endRuns' },
    delete     = { 'key' },
    startRun   = { 'key' },
    abort      = { 'runId' },
    isolate    = { 'on' },
    example    = { 'name' },
    lore       = {},
    loreSave   = { 'key', 'name', 'model', 'bankName', 'notes', 'picture', 'frameX', 'frameY', 'frameZ', 'voice' },
    loreRetire = { 'key' },
    loreVoiceTest = { 'key', 'url' },   -- a voice line played at the builder (server/director/lore_voice.lua)
    previewPlans = { 'things', 'world' },
    takePath   = { 'key', 'take' },   -- a car's take as a line, for the world builder's Map window (director/map.js)
}

local function answer(cb, res, why)
    if res == nil or res == false then
        cb({ ok = false, why = why or 'No answer from the server' })
    else
        if type(res) == 'table' and res.uploadBps then uploadBps = tonumber(res.uploadBps) or uploadBps end
        cb({ ok = true, data = res })
    end
end

RegisterNUICallback('directorCall', function(d, cb)
    local op = type(d) == 'table' and d.op or nil
    local names = type(op) == 'string' and OPS[op] or nil
    if not names then cb({ ok = false, why = 'unknown request' }) return end
    local args = type(d.args) == 'table' and d.args or {}
    local list = {}
    for i, name in ipairs(names) do list[i] = args[name] end
    answer(cb, Callback('spur_core:director:' .. op, table.unpack(list, 1, #names)))
end)

--- How far a model's origin is over its bottom (wheels, a ped's feet), in metres; nil when the game does not know the
--- model. Loads the model briefly to size it (waits) unless `noLoad`. Cached per model.
local lifts = {}
local function liftOf(model, noLoad)
    local hash = type(model) == 'number' and model or (type(model) == 'string' and model ~= '' and GetHashKey(model))
    if not hash then return nil end
    if lifts[hash] ~= nil then return lifts[hash] or nil end
    if not IsModelInCdimage(hash) then return nil end
    local function read()
        local mn, mx = GetModelDimensions(hash)
        if not mn or (mn.z == 0.0 and mx.z == 0.0) then return nil end
        return -mn.z
    end
    local lift = read()
    if not lift then
        if noLoad then return nil end
        if LoadModel(hash, 1500) then
            lift = read()
            SetModelAsNoLongerNeeded(hash)
        end
    end
    lifts[hash] = lift or false
    return lift
end

--- Gives each placed car with a ground spot the height over its wheels (def.lifts) of every model it may be made as.
--- The server cannot read model sizes (nodes_world.lua spawnOne uses these to put the wheels on the ground).
local function carLifts(doc)
    local function each(world)
        for _, w in ipairs(type(world) == 'table' and world or {}) do
            local def = type(w) == 'table' and w.kind == 'vehicle' and type(w.def) == 'table' and w.def or nil
            if def and type(def.coords) == 'table' and tonumber(def.coords.ground) then
                local out = {}
                local function add(m)
                    local name = type(m) == 'table' and m.model or m
                    local lift = type(name) == 'string' and name ~= '' and liftOf(name) or nil
                    if lift then out[name] = math.floor(lift * 1000 + 0.5) / 1000 end
                end
                add(def.model)
                for _, m in ipairs(type(def.models) == 'table' and def.models or {}) do add(m) end
                def.lifts = next(out) and out or nil
            end
        end
    end
    each(doc.world)
    for _, v in ipairs(type(doc.variants) == 'table' and doc.variants or {}) do
        if type(v) == 'table' then each(v.world) end
    end
end

--- Sends a document up as a latent event (big documents get lost as plain events); returns its token.
local function upload(doc)
    carLifts(doc)
    uploadToken = uploadToken + 1
    TriggerLatentServerEvent('spur_core:server:directorDoc', uploadBps, uploadToken, doc)
    return uploadToken
end

RegisterNUICallback('directorSave', function(d, cb)
    if type(d) ~= 'table' or type(d.doc) ~= 'table' then cb({ ok = false, why = 'nothing to save' }) return end
    local token = upload(d.doc)
    answer(cb, Callback('spur_core:director:save', d.key, d.baseRev, token, type(d.note) == 'string' and d.note or ''))
end)

RegisterNUICallback('directorCheck', function(d, cb)
    if type(d) ~= 'table' or type(d.doc) ~= 'table' then cb({ ok = false, why = 'nothing to check' }) return end
    local token = upload(d.doc)
    answer(cb, Callback('spur_core:director:check', token))
end)

-- Test mode. The keys are made the first time someone tests, and do nothing unless a test is running.

local keysMade = false

-- A card of another resource in a test (cards_api.lua) does not run: the test map says what it would do and offers its
-- outcomes (Page Up moves through them, Page Down takes one; the first goes by itself after 15 seconds).
local testCard = nil   -- the one shown: { callId, node, title, owner, says, outcomes = { { pin, label } }, at, seconds }
local testCards = {}   -- every one waiting, oldest first; testCard is the first

-- Test window (html/js/director/testwin.js): the blueprint over the game while a test runs. H gives it the mouse,
-- G hides it and shows it again; the test and its keys go on.
local testMouse = false
local testHidden = false

local function testWindowHide(on)
    on = on == true and testing ~= nil
    if on == testHidden then return end
    testHidden = on
    SendNUIMessage({ action = 'directorTestWindow', hidden = on })
end

local function testWindowMouse(on)
    on = on == true and testing ~= nil
    if on == testMouse then return end
    if on then testWindowHide(false) end
    testMouse = on
    if on then Focus.take('directorTest') else Focus.release('directorTest') end
    SendNUIMessage({ action = 'directorTestWindow', mouse = on })
end

-- The test window's Free camera: a spectator camera to watch the run from; the ped stays put, hidden and held.
local testCam = false

--- Stops the free camera and leaves the player exactly where they are (`stay`; moving them back could pull a seated
--- tester out of their car). Waits.
local function stopTestCam()
    if not testCam then return end
    testCam = false
    if FreeCam.isActive() then FreeCam.stop({ stay = true }) end
    SendNUIMessage({ action = 'directorTestWindow', freecam = false })
end

local function testWindow(on)
    if not on then testWindowMouse(false) end
    testHidden = false
    SendNUIMessage({ action = 'directorTestWindow', on = on == true, own = isolated == true })
end

--- A status line in the test window ("Started again", "Took: Yes").
local function testSay(text)
    SendNUIMessage({ action = 'directorTestWindow', say = tostring(text or '') })
end

--- Shows the waiting card in the test window: what it would do, and the outcome Page Up is on.
local function testPick()
    local c = testCard
    SendNUIMessage({ action = 'directorTestWindow', pick = c and { node = c.node, owner = c.owner, says = c.says, at = c.at,
                                                                     outcomes = c.outcomes, seconds = c.seconds } or false })
end

local function resetTest()
    if not testing then return end
    testCards, testCard = {}, nil
    TriggerServerEvent('spur_core:server:directorTestReset')
    testPick()
    testSay('Starting again…')
end

--- Page Up: the waiting card's next outcome. Page Down (takeOutcome): take it.
local function nextOutcome()
    if not testing or not testCard then return end
    testCard.at = testCard.at % #testCard.outcomes + 1
    testPick()
end

local function takeOutcome()
    if not testing or not testCard then return end
    local o = testCard.outcomes[testCard.at]
    TriggerServerEvent('spur_core:server:directorTestPick', testCard.callId, tostring(o and o.pin or ''))
    table.remove(testCards, 1)
    testCard = testCards[1]
    testPick()
    testSay('Took: ' .. tostring(o and o.label or '?'))
end

backToEditor = function()
    if not testing then return end
    testWindow(false)
    testing = nil
    testCards, testCard = {}, nil
    CreateThread(function()
        stopTestCam()
        local res = Callback('spur_core:director:testStop')
        res = type(res) == 'table' and res or {}
        open()
        SendNUIMessage({ action = 'directorTestDone', trace = res.trace or {}, outcome = res.outcome, reason = res.reason,
                         faultNode = res.faultNode })
        -- The editor refused to open: tell the server now so an isolated tester returns to the shared world.
        if not DirectorEditorOpen then
            TriggerServerEvent('spur_core:server:directorClosed')
            UI.Notify('Test stopped. You are back in the shared world: /spur, Director, opens it again', 'info', 6000)
        end
    end)
end

local function makeKeys()
    if keysMade then return end
    keysMade = true
    RegisterCommand('director_test_reset', resetTest, false)
    RegisterCommand('director_test_back', function() backToEditor() end, false)
    RegisterKeyMapping('director_test_reset', 'Director: reset the test', 'keyboard', 'F5')
    RegisterKeyMapping('director_test_back', 'Director: back to the editor', 'keyboard', 'F9')
    RegisterCommand('director_test_next', nextOutcome, false)
    RegisterCommand('director_test_take', takeOutcome, false)
    RegisterKeyMapping('director_test_next', 'Director: a test card\'s next outcome', 'keyboard', 'PAGEUP')
    RegisterKeyMapping('director_test_take', 'Director: take a test card\'s outcome', 'keyboard', 'PAGEDOWN')
    RegisterCommand('director_test_mouse', function() if testing then testWindowMouse(not testMouse) end end, false)
    RegisterKeyMapping('director_test_mouse', 'Director: the test map\'s mouse (on, or off)', 'keyboard', 'H')
    RegisterCommand('director_test_hide', function()
        if not testing then return end
        if testMouse then testWindowMouse(false) end
        testWindowHide(not testHidden)
    end, false)
    RegisterKeyMapping('director_test_hide', 'Director: hide the test map (or show it again)', 'keyboard', 'G')
    RegisterCommand('director_test_npcdebug', function() if testing then DirectorNpcDebug.toggle() end end, false)
    RegisterKeyMapping('director_test_npcdebug', 'Director: NPC debug in a test (what each NPC is doing, and why)', 'keyboard', 'J')
end

-- The test window's own requests: mouse release, a card's outcome taken, rewind.
RegisterNUICallback('directorTestMouse', function(d, cb)
    cb('ok')
    testWindowMouse(type(d) == 'table' and d.on == true)
end)

-- The test window's Free camera on (mouse back to the game) or off.
RegisterNUICallback('directorTestFreecam', function(_, cb)
    cb('ok')
    if not testing then return end
    if testCam then stopTestCam() return end
    if FreeCam.isActive() then UI.Notify('Another free camera is on (noclip?): turn it off first', 'error') return end
    testWindowMouse(false)
    FreeCam.start({ pad = 'auto', pedFollows = false })
    testCam = true
    SendNUIMessage({ action = 'directorTestWindow', freecam = true })
end)

RegisterNUICallback('directorTestTake', function(d, cb)
    cb('ok')
    if not testing or type(d) ~= 'table' or type(d.node) ~= 'string' or type(d.pin) ~= 'string' then return end
    TriggerServerEvent('spur_core:server:directorTestTake', d.node, d.pin)
end)

RegisterNUICallback('directorTestRewind', function(d, cb)
    if not testing or type(d) ~= 'table' then cb({ ok = false, why = 'No test is running' }) return end
    answer(cb, Callback('spur_core:director:testRewind', math.tointeger(tonumber(d.seq)) or 0, tostring(d.node or ''), tostring(d.pin or '')))
end)

--- Every step of the test's run, which cards wait and which are queued (hub.lua beginTest).
RegisterNetEvent('spur_core:client:directorTestFlow', function(f)
    if not testing or type(f) ~= 'table' then return end
    SendNUIMessage({ action = 'directorTestFlow', steps = f.steps or {}, dropped = f.dropped, waiting = f.waiting or {},
                     queued = f.queued or {}, status = f.status, runId = f.runId })
end)

RegisterNUICallback('directorTest', function(d, cb)
    if type(d) ~= 'table' or type(d.doc) ~= 'table' or type(d.key) ~= 'string' then
        cb({ ok = false, why = 'nothing to test' })
        return
    end
    local token = upload(d.doc)
    local variant = type(d.variant) == 'string' and d.variant:match('^v%d+$') and d.variant or ''
    local res, why = Callback('spur_core:director:test', d.key, token, variant)
    if type(res) ~= 'table' then cb({ ok = false, why = why or 'No answer from the server' }) return end
    cb({ ok = true, data = res })
    if res.ok == false then return end   -- it did not pass its check: the page shows why
    -- The page is only hidden and the server is not told the editor closed: the scenario is still open.
    makeKeys()
    testing = { name = res.name or d.key }
    -- Close the world builder, or the test would play on its camera.
    if building and Furnisher and Furnisher.close then
        leaving = 'test'
        Furnisher.close()
    end
    DirectorEditorOpen, hidden = false, false
    Focus.release('director')
    SendNUIMessage({ action = 'directorClose' })
    testWindow(true)
end)

--- A live run of the open scenario went on: its cards light on the page (not while the page is hidden or closed).
RegisterNetEvent('spur_core:client:directorPulse', function(key, steps)
    if not DirectorEditorOpen or hidden or type(key) ~= 'string' or type(steps) ~= 'table' then return end
    SendNUIMessage({ action = 'directorPulse', key = key, steps = steps })
end)

--- Another resource's card in this test waits for the tester's outcome (cards_api.lua).
RegisterNetEvent('spur_core:client:directorTestCard', function(c)
    if not testing or type(c) ~= 'table' or type(c.callId) ~= 'string' or type(c.outcomes) ~= 'table' or #c.outcomes == 0 then return end
    for _, w in ipairs(testCards) do if w.callId == c.callId then return end end
    testCards[#testCards + 1] = { callId = c.callId, node = type(c.node) == 'string' and c.node or nil, title = c.title, owner = c.owner,
                                  says = c.says, outcomes = c.outcomes, at = 1, seconds = tonumber(c.seconds) }
    testCard = testCards[1]
    testPick()
end)

--- The card went on (outcome taken, or its first went by itself): off the list, the next shown.
RegisterNetEvent('spur_core:client:directorTestCardDone', function(callId)
    for i, w in ipairs(testCards) do
        if w.callId == callId then
            table.remove(testCards, i)
            testCard = testCards[1]
            testPick()
            return
        end
    end
end)

--- Another resource added or removed cards: the open page asks again.
RegisterNetEvent('spur_core:client:directorCardsChanged', function(rev)
    if DirectorEditorOpen then SendNUIMessage({ action = 'directorCardsChanged', rev = rev }) end
end)

RegisterNetEvent('spur_core:client:directorTestEnded', function(e)
    if not testing or type(e) ~= 'table' then return end
    testCards, testCard = {}, nil
    testPick()
    SendNUIMessage({ action = 'directorTestFlow', ended = { outcome = e.outcome, reason = e.reason, node = e.node } })
end)

RegisterNetEvent('spur_core:client:directorTestReset', function(ok, why)
    if not testing then return end
    testCards, testCard = {}, nil
    if ok then
        SendNUIMessage({ action = 'directorTestFlow', reset = true })
        testPick()
        testSay('Started again')
    else
        testWindow(false)
        testing = nil
        stopTestCam()
        UI.Notify('The test could not start again: ' .. tostring(why or '?'), 'error')
        -- No editor comes back: the server forgets what it had open and Isolate world ends.
        TriggerServerEvent('spur_core:server:directorClosed')
    end
end)

--- Isolate world went on or off (the editor's button, or the server).
RegisterNetEvent('spur_core:client:directorIsolated', function(on)
    on = on == true
    if on == isolated then return end
    isolated = on
    if testing then SendNUIMessage({ action = 'directorTestWindow', own = on }) end
    if DirectorEditorOpen then
        SendNUIMessage({ action = 'directorIsolated', on = on })
    elseif not on then
        UI.Notify('You are back in the shared world', 'info')
    end
end)

AddEventHandler('spur_core:player:logout', function()
    testCards, testCard = {}, nil
    if testing then
        testWindow(false)
        testing = nil
        stopTestCam()
    end
end)

-- The world builder (the World tab): the furnisher (client/property_furnish.lua) opened on the scenario's things,
-- working anywhere. Done sends the whole set back to the page; Exit throws the changes away. A switched-on scenario's
-- live props are hidden while it builds (client/prop_sets.lua), so each shows once.

--- Inside an MLO or not, asked a metre above the stored spot.
local function interiorAt(x, y, z) return GetInteriorAtCoords(x, y, z + 1.0) ~= 0 end

--- An angle in -180..180, one decimal (a prop's tilt).
local function tilt(v) v = tonumber(v) or 0.0 return math.floor(((v + 180.0) % 360.0 - 180.0) * 10 + 0.5) / 10 end

-- The peds a look from the character editor is made on.
local FREEMODE = { mp_male = true, mp_female = true }

-- The kinds the world builder places: every World-tab kind, and a task's point.
local BUILD_KINDS = DirectorThings.with('builder')
BUILD_KINDS.point = true

--- A thing's model for the builder: a name, a door's number, a container's prop; '' for markers; nil when it has none.
local function modelOf(t)
    if t.kind == 'door' then return tonumber(t.model) end
    if t.kind == 'container' then return type(t.model) == 'string' and t.model or '' end
    if t.kind == 'spot' or t.kind == 'groundItem' or t.kind == 'point' or t.kind == 'route' then return '' end
    if t.kind == 'vehicle' and t.random == true and (type(t.model) ~= 'string' or t.model == '') then return '' end
    -- A Fixed Weapon is its gun's own model, whatever the page last saved.
    if t.kind == 'prop' and WeaponCatalog.modelOf(t.weapon) then return WeaponCatalog.modelOf(t.weapon) end
    return type(t.model) == 'string' and t.model ~= '' and t.model or nil
end

--- The prompt a run puts on a thing, cleaned: { label, icon, reach, ride 'entity'|'coords', lift, options }; nil when none.
local function promptOf(p)
    if type(p) ~= 'table' then return nil end
    local function text(v, max) return (type(v) == 'string' and v ~= '') and v:sub(1, max) or nil end
    local reach, lift = tonumber(p.reach), tonumber(p.lift)
    local out = {
        label = text(p.label, 40) or 'Use',
        icon  = text(p.icon, 32),
        reach = reach and math.max(0.5, math.min(10.0, reach)) or nil,
        ride  = p.ride == 'entity' and 'entity' or 'coords',
        lift  = lift and math.max(-2.0, math.min(3.0, lift)) or 0.0,
    }
    if type(p.options) == 'table' then
        local opts = {}
        for i = 1, math.min(#p.options, 8) do
            local t = text(p.options[i], 44)
            if t then opts[#opts + 1] = t end
        end
        if #opts > 0 then out.options = opts end
    end
    return out
end

--- What the thing's mark in the builder says: { name, detail, pic }. `pic` is a path under html/ or a resource's own
--- https://cfx-nui- or nui:// file. nil when none.
local function markOf(m)
    if type(m) ~= 'table' then return nil end
    local function text(v, max) return (type(v) == 'string' and v ~= '') and v:sub(1, max) or nil end
    local pic = text(m.pic, 200)
    if pic and (pic:find('..', 1, true) or not (pic:match('^img/items/[%w_%-]+%.%a+$')
            or pic:match('^https://cfx%-nui%-[%w_%-]+/[%w_%-%./]+$') or pic:match('^nui://[%w_%-]+/[%w_%-%./]+$'))) then
        pic = nil
    end
    return { name = text(m.name, 60), detail = text(m.detail, 80), pic = pic }
end

--- What the builder keeps with a thing: its id, prompt and mark, plus kind-specific data (a point's `of`, `list`, `n`;
--- a route's `loops`; a guard's cone).
local function extraOf(t)
    local x = { id = t.id, kind = t.kind, label = t.label, uses = t.uses, prompt = promptOf(t.prompt), mark = markOf(t.mark) }
    -- Other resources' data ({ [resource] = data }), handed to them when the copy is made so they can dress it.
    if (t.kind == 'vehicle' or t.kind == 'npc' or t.kind == 'prop') and type(t.ext) == 'table' and next(t.ext) then x.ext = t.ext end
    -- A Fixed Weapon is a prop that is a gun; one saved without its gun is known by its model.
    if t.kind == 'prop' then
        local wpn = WeaponCatalog.modelOf(t.weapon) and t.weapon:upper() or WeaponCatalog.weaponOf(t.model)
        if wpn then x.weapon = wpn end
    end
    -- An NPC's lore character, weapon and outfit (furnish_builder.lua dressNpc).
    if t.kind == 'npc' then
        x.lore = type(t.lore) == 'string' and #t.lore <= 64 and t.lore:match('^[%w_%-]+$') and t.lore or nil
        x.weapon = type(t.weapon) == 'string' and #t.weapon <= 64 and t.weapon:match('^[%w_]+$') and t.weapon:upper() or nil
        x.look = not x.lore and type(t.look) == 'table' and FREEMODE[t.look.model] and t.look or nil
        x.outfit = not x.lore and not x.look and PedOutfit.clean(t.outfit) or nil
    end
    if t.kind == 'point' then
        x.of = type(t.of) == 'string' and t.of:sub(1, 64) or nil
        x.n = math.tointeger(tonumber(t.n)) or 1
        x.glyph = tostring(math.max(1, math.min(99, x.n)))
        x.list = t.list == 'points' and 'points' or 'tasks'
        x.loops = x.list == 'points' and t.loops == true or nil   -- a route's: round to point 1 again
    elseif t.kind == 'route' then
        x.loops = t.loops == true
    elseif t.kind == 'vehicle' and t.random == true then
        -- The models its copy cycles through.
        x.random = true
        local models = {}
        for i = 1, math.min(type(t.models) == 'table' and #t.models or 0, 8) do
            local m = t.models[i]
            if type(m) == 'string' and m ~= '' and #m <= 64 then models[#models + 1] = m end
        end
        x.models = models
    elseif t.kind == 'npc' and type(t.vision) == 'table' then
        local v = t.vision
        local range, cone = tonumber(v.range), tonumber(v.cone)
        if range and cone then
            local spotS = math.max(1.0, math.min(10.0, tonumber(v.spotS) or 2.0))
            x.vision = { range = math.max(3.0, math.min(80.0, range)), cone = math.max(20.0, math.min(360.0, cone)),
                         spotS = spotS, farS = math.max(spotS, math.min(30.0, tonumber(v.farS) or 8.0)), sneak = v.sneak ~= false }
        end
    elseif t.kind == 'spot' and type(t.zone) == 'table' then
        -- Its marker's shape (client/director_spots.lua).
        local z = t.zone
        if z.look == 'circle' or z.look == 'square' or z.look == 'garage' then
            local w = math.max(1.0, math.min(30.0, tonumber(z.w) or 4.0))
            x.zone = { look = z.look, w = w, l = math.max(1.0, math.min(30.0, tonumber(z.l) or w)),
                       icon = SpotShape.icon(z.icon, z.look) }
        end
    end
    return x
end

--- A thing the page sent as the furnisher's row { model, x, y, z, rx, ry, rz, extra }; nil when not placed or no model.
local function rowOf(t)
    if type(t) ~= 'table' or not BUILD_KINDS[t.kind] then return nil end
    local model = modelOf(t)
    if model == nil then return nil end
    local c = t.coords
    if type(c) ~= 'table' or not (tonumber(c.x) and tonumber(c.y) and tonumber(c.z)) then return nil end
    local r = t.kind == 'prop' and type(t.rot) == 'table' and t.rot or {}
    return { model = model, x = tonumber(c.x), y = tonumber(c.y), z = tonumber(c.z),
             rx = tonumber(r.x) or 0.0, ry = tonumber(r.y) or 0.0, rz = tonumber(c.heading) or 0.0,
             extra = extraOf(t) }
end

-- Vehicles tab: every vehicle this game has (add-ons too), by the game's class.

local VEHICLE_CLASS = { [0] = 'compacts', 'sedans', 'suvs', 'coupes', 'muscle', 'classics', 'sports', 'super', 'motorcycles',
    'offroad', 'industrial', 'utility', 'vans', 'cycles', 'boats', 'helicopters', 'planes', 'service', 'emergency', 'military',
    'commercial', 'trains', 'openwheel' }
-- `model`: the vehicle pictured on the group's card.
local VEHICLE_CLUSTERS = {
    { key = 'cars', label = 'Wagons', glyph = 'car', model = 'wagon05x' }, { key = 'boats', label = 'Boats', glyph = 'car', model = 'rowboat' },
    { key = 'bikes', label = 'Bikes', glyph = 'car', model = 'cliffhanger' }, { key = 'air', label = 'Air', glyph = 'car', model = 'havok' },
}
-- RedM (spur_core, 24 Nov 2026): the classes RDR2's vehicles are filed under read as 1899 names, and the Wagons and
-- Boats tiles show RDR2 models (server/vehicle_catalog_list.lua). RDR2 has no bikes or aircraft: those stay empty.
local VEHICLE_CATEGORIES = {
    { key = 'compacts', label = 'Buggies & carts', cluster = 'cars' }, { key = 'sedans', label = 'Coaches', cluster = 'cars' },
    { key = 'suvs', label = 'SUVs', cluster = 'cars' }, { key = 'coupes', label = 'Coupes', cluster = 'cars' },
    { key = 'muscle', label = 'Muscle', cluster = 'cars' }, { key = 'classics', label = 'Sports classics', cluster = 'cars' },
    { key = 'sports', label = 'Sports', cluster = 'cars' }, { key = 'super', label = 'Super', cluster = 'cars' },
    { key = 'offroad', label = 'Off-road', cluster = 'cars' }, { key = 'openwheel', label = 'Open wheel', cluster = 'cars' },
    { key = 'vans', label = 'Wagons', cluster = 'cars' }, { key = 'industrial', label = 'Industrial', cluster = 'cars' },
    { key = 'utility', label = 'Utility', cluster = 'cars' }, { key = 'service', label = 'Service', cluster = 'cars' },
    { key = 'emergency', label = 'Law', cluster = 'cars' }, { key = 'military', label = 'Military', cluster = 'cars' },
    { key = 'commercial', label = 'Commercial', cluster = 'cars' }, { key = 'trains', label = 'Rail', cluster = 'cars' },
    { key = 'boats', label = 'Boats', cluster = 'boats' },
    { key = 'motorcycles', label = 'Motorcycles', cluster = 'bikes' }, { key = 'cycles', label = 'Cycles', cluster = 'bikes' },
    { key = 'helicopters', label = 'Helicopters', cluster = 'air' }, { key = 'planes', label = 'Planes', cluster = 'air' },
}
for _, c in ipairs(VEHICLE_CATEGORIES) do c.glyph = 'car' end

--- The list, built once: each model the game has with its class and display name.
local vehicleList
local function vehicles()
    if vehicleList then return vehicleList end
    local props, seen = {}, {}
    for _, raw in ipairs(GetAllVehicleModels and GetAllVehicleModels() or {}) do
        local m = tostring(raw):lower()
        -- A numeric name is a hash, not a model.
        if m ~= '' and not seen[m] and not m:match('^%-?%d+$') then
            seen[m] = true
            local hash = GetHashKey(m)
            local label = GetLabelText(GetDisplayNameFromVehicleModel(hash))
            if type(label) ~= 'string' or label == '' or label == 'NULL' then label = m end
            props[#props + 1] = { model = m, category = VEHICLE_CLASS[GetVehicleClassFromName(hash)] or 'compacts', name = label }
        end
    end
    table.sort(props, function(a, b) return a.name < b.name end)
    vehicleList = { clusters = VEHICLE_CLUSTERS, categories = VEHICLE_CATEGORIES, props = props }
    return vehicleList
end

-- More, Weapons: a Fixed Weapon, each firearm this game has, by group.

-- RedM (spur_core, 24 Nov 2026): RDR2's firearm groups (shared/rdr_weapons.lua), in place of the original game's.
local WEAPON_GROUP_LABEL = { revolver = 'Revolvers', pistol = 'Pistols', repeater = 'Repeaters', rifle = 'Rifles',
                             sniper = 'Sniper rifles', shotgun = 'Shotguns' }

--- The tiles: { categories, props }, each prop { model, kind = 'prop', weapon, category, name }; rebuilt when the catalog changes.
local weaponTileList, weaponTilesAt
local function weaponTiles()
    if weaponTileList and weaponTilesAt == WeaponCatalog.version then return weaponTileList end
    local categories, props = {}, {}
    for _, g in ipairs(GameWeaponModels.groups) do
        categories[#categories + 1] = { key = 'weapons_' .. g:gsub(' ', '_'), label = WEAPON_GROUP_LABEL[g] or g, cluster = 'weapons', glyph = 'gun' }
    end
    for _, w in ipairs(WeaponCatalog.list()) do
        local model = WeaponCatalog.modelOf(w.name)
        if model and IsWeaponValid(GetHashKey(w.name)) and IsModelInCdimage(GetHashKey(model)) then
            props[#props + 1] = { model = model, kind = 'prop', weapon = w.name, category = 'weapons_' .. w.group:gsub(' ', '_'),
                                  name = WeaponCatalog.title(w), glyph = 'gun' }
        end
    end
    table.sort(props, function(a, b) return a.name < b.name end)
    weaponTileList, weaponTilesAt = { categories = categories, props = props }, WeaponCatalog.version
    return weaponTileList
end

--- Where a car's wheels touch, from where the builder's copy stands as the model it shows now.
local function groundOf(p)
    local lift = liftOf(p.model, true)
    return lift and p.z - lift or nil
end

--- The builder's set as the page takes it (directorBuilt). `was`: where each stood when last handed over, so only a moved
--- or new one is asked whether it is inside an interior (a far one in an unloaded interior would read as outside).
--- `index`: its row in the builder.
local function builtRows(payload, was)
    local out = {}
    for i, p in ipairs(type(payload) == 'table' and payload or {}) do
        local x = type(p.extra) == 'table' and p.extra or {}
        local kind = BUILD_KINDS[x.kind] and x.kind or 'prop'
        local isProp = kind == 'prop'
        local w0 = x.id ~= nil and was[x.id] or nil
        local moved = not w0 or math.abs(w0[1] - p.x) > 0.001 or math.abs(w0[2] - p.y) > 0.001 or math.abs(w0[3] - p.z) > 0.001
        local inside = nil   -- set for one moved or new; nil: as it was
        if moved then inside = interiorAt(p.x, p.y, p.z) end
        out[#out + 1] = {
            id = x.id, kind = kind, model = p.model, index = i,
            label = x.label or (isProp and Furnisher.nameOf and Furnisher.nameOf(p.model)) or (type(p.model) == 'string' and p.model ~= '' and p.model) or nil,
            lore = kind == 'npc' and type(x.lore) == 'string' and x.lore or nil,
            random = kind == 'vehicle' and x.random == true or nil,
            weapon = isProp and type(x.weapon) == 'string' and x.weapon or nil,
            coords = { x = p.x, y = p.y, z = p.z, heading = (tonumber(p.rz) or 0.0) % 360.0,
                       ground = kind == 'vehicle' and groundOf(p) or nil },
            rot = isProp and { x = tilt(p.rx), y = tilt(p.ry) } or nil,
            interior = inside,
            light = isProp and Furnisher.isLight and Furnisher.isLight(p.model) or nil,
        }
    end
    return out
end

--- The builder open now: `took` (the scenario's things it was handed; Done removes only those it does not hand back)
--- and `was` (where each stood when last handed over).
local held = nil   -- { took = { id, ... }, was = { [id] = { x, y, z } } }

RegisterNUICallback('directorBuild', function(d, cb)
    cb('ok')
    if not DirectorEditorOpen or hidden or building or type(d) ~= 'table' then return end
    if not Furnisher or not Furnisher.open then return end
    local rows, unplaced, adopt, took, was = {}, nil, nil, {}, {}
    for _, t in ipairs(type(d.things) == 'table' and d.things or {}) do
        local row = rowOf(t)
        if row then
            rows[#rows + 1] = row
            took[#took + 1] = t.id
            was[t.id] = { row.x, row.y, row.z }
        elseif type(t) == 'table' and t.id == d.focus and BUILD_KINDS[t.kind] then
            local extra = extraOf(t)
            if t.kind ~= 'door' and modelOf(t) ~= nil then
                -- Not placed yet: put in front of the camera.
                unplaced = { model = modelOf(t), extra = extra }
            else
                -- Nothing to make yet (no door or model picked): its first pick is it.
                adopt = extra
            end
        end
    end
    -- Noclip still on: off first, as the builder will not open over another free camera. The camera stops without
    -- setting the ped down (movePed = false), or the builder's camera would drop the ped from that height.
    if DevToolActive('Noclip') then
        if FreeCam.isActive() then FreeCam.stop({ movePed = false }) end
        DeactivateTool('Noclip')
    end
    -- `back`: from a recorded take, so the camera returns where it was.
    local view = d.back == true and builderView or nil
    builderView = nil
    hidden = true
    Focus.release('director')   -- the furnisher takes the focus
    SendNUIMessage({ action = 'directorHide' })
    building = true
    if PropSets and PropSets.hideLike then PropSets.hideLike(rows) end
    local name = type(d.name) == 'string' and d.name ~= '' and d.name or 'Scenario'
    -- On close: the page goes on when asked (leaving 'page'); its Exit leaves the Director.
    leaving = nil
    local function back()
        building = false
        held = nil
        if PropSets and PropSets.showHidden then PropSets.showHidden() end
        local how = leaving
        leaving = nil
        if how == 'page' then show()
        elseif how == nil then close() end
    end
    held = { took = took, was = was }
    local ok, why = Furnisher.open({
        title = 'World: ' .. name,
        rows = rows,
        focus = d.focus,
        camera = view,
        pick = unplaced,
        adopt = adopt,
        -- `director`: the page's Configure and Blueprint window. `autosave`: the page saves every five minutes
        -- while there is something to save. `configure`: the thing whose Configure opens first.
        page = { tabs = { 'catalog', 'npcs', 'vehicles', 'more', 'placed' }, done = 'Save', byName = true, vehicles = vehicles(),
                 weapons = weaponTiles(),
                 director = true, autosave = d.autosave ~= false, configure = view and d.focus or nil },
        onDone = function(payload)
            SendNUIMessage({ action = 'directorBuilt', things = builtRows(payload, held and held.was or was), took = held and held.took or took })
        end,
        -- Save with the builder open: the page writes the set into the scenario, then reports (directorBuilderSaved).
        onSave = function(payload, auto)
            local h = held
            if not h then return end
            SendNUIMessage({ action = 'directorBuilt', things = builtRows(payload, h.was), took = h.took, stay = true, auto = auto == true })
            local nowTook, nowWas = {}, {}
            for _, p in ipairs(type(payload) == 'table' and payload or {}) do
                local id = type(p.extra) == 'table' and p.extra.id or nil
                if id ~= nil then
                    nowTook[#nowTook + 1] = id
                    nowWas[id] = { p.x, p.y, p.z }
                end
            end
            h.took, h.was = nowTook, nowWas
        end,
        onClose = function() back() end,
    })
    if not ok then
        leaving = 'page'
        back()
        SendNUIMessage({ action = 'directorPlaceRefused', why = why or 'The world builder could not open' })
    end
end)

-- The Director inside the world builder: its Configure panel and Blueprint window change the scenario while the builder
-- is open, and the builder's copies follow (Furnisher.setExtra).

RegisterNUICallback('directorBuilderSync', function(d, cb)
    cb('ok')
    if not building or type(d) ~= 'table' or type(d.things) ~= 'table' or not Furnisher.setExtra then return end
    local keep = {}
    for i = 1, math.min(#d.things, 500) do
        local t = d.things[i]
        if type(t) == 'table' and BUILD_KINDS[t.kind] and type(t.id) == 'string' then
            Furnisher.setExtra(t.id, extraOf(t), modelOf(t))
            if t.kind == 'point' then
                keep[t.id] = true
                local row = d.all == true and FurnishBuilder and FurnishBuilder.addPoint and rowOf(t)
                if row then FurnishBuilder.addPoint(row) end
            end
        end
    end
    -- `all`: a point the scenario no longer has goes too. `points` names every point it has now; without it, `things` is all.
    if d.all == true and Furnisher.prunePoints then
        if type(d.points) == 'table' then
            if #d.points <= 2000 then
                local all = {}
                for _, id in ipairs(d.points) do if type(id) == 'string' then all[id] = true end end
                Furnisher.prunePoints(all)
            end
        elseif #d.things <= 500 then
            Furnisher.prunePoints(keep)
        end
    end
end)

--- Duplicate: the page made the copy in the scenario; here it is carried on the pointer, turned as the original.
RegisterNUICallback('directorBuilderCopy', function(d, cb)
    cb('ok')
    local t = type(d) == 'table' and d.thing or nil
    if not building or type(t) ~= 'table' or type(t.id) ~= 'string' or #t.id > 64 then return end
    if t.kind == 'door' or t.kind == 'point' or t.kind == 'route' then return end
    local row = rowOf(t)
    if not row or not (FurnishBuilder and FurnishBuilder.carryCopy) then return end
    if FurnishBuilder.carryCopy(row) and held then held.took[#held.took + 1] = t.id end
end)

--- One of the scenario's things (Place it in the world): selected and looked at where it is, or carried in front of
--- the camera if not placed yet. It is already the scenario's, so it is not reported as placed.
RegisterNUICallback('directorBuilderPut', function(d, cb)
    cb('ok')
    local t = type(d) == 'table' and d.thing or nil
    if not building or type(t) ~= 'table' or type(t.id) ~= 'string' or #t.id > 64 or not BUILD_KINDS[t.kind] then return end
    if t.kind == 'door' or t.kind == 'point' or t.kind == 'route' then return end
    if FurnishBuilder and FurnishBuilder.lookAt and FurnishBuilder.lookAt(t.id) then return end
    local model = modelOf(t)
    if model == nil or not (FurnishBuilder and FurnishBuilder.carryCopy) then return end
    FurnishBuilder.carryCopy({ model = model, extra = extraOf(t) })
end)

--- A task's point (Place it in the world): selected where it is, or put down in front of the camera; the page hears
--- where (directorPointPlaced). `carry`: it then rides the pointer until a left click (directorPointMoved).
RegisterNUICallback('directorBuilderPoint', function(d, cb)
    cb('ok')
    local t = type(d) == 'table' and d.thing or nil
    if not building or type(t) ~= 'table' or t.kind ~= 'point' or type(t.id) ~= 'string' or #t.id > 140 then return end
    if not FurnishBuilder or not FurnishBuilder.placePoint then return end
    local at = FurnishBuilder.placePoint(extraOf(t))
    if at then SendNUIMessage({ action = 'directorPointPlaced', id = t.id, coords = at }) end
    if d.carry == true and Furnisher.carry then Furnisher.carry() end
end)

--- A prop's Turn To heading as its slider moves: a see-through copy turned that way (FurnishBuilder.turnGhost).
RegisterNUICallback('directorTurnGhost', function(d, cb)
    cb('ok')
    if not building or type(d) ~= 'table' or type(d.id) ~= 'string' or #d.id > 140 then return end
    local h = tonumber(d.heading)
    if not h or h ~= h or not (FurnishBuilder and FurnishBuilder.turnGhost) then return end
    FurnishBuilder.turnGhost(d.id, h % 360.0, d.done == true)
end)

--- A Play Emote step's Choose: the emote menu in pick mode (client/emotes.lua pickFor); each emote clicked is sent
--- as directorEmotePicked and the menu stays open.
RegisterNUICallback('directorPickEmote', function(d, cb)
    cb('ok')
    if not DirectorEditorOpen or not (Emotes and Emotes.pickFor) then return end
    local current = type(d) == 'table' and type(d.current) == 'string' and d.current or nil
    local ok = Emotes.pickFor(function(cmd)
        if type(cmd) == 'string' then SendNUIMessage({ action = 'directorEmotePicked', cmd = cmd }) end
    end, { current = current })
    if not ok then UI.Notify('The emote menu is already open', 'error', 3000) end
end)

--- A card's Look at it: the thing selected, the camera in front of it.
RegisterNUICallback('directorBuilderLook', function(d, cb)
    cb('ok')
    if not building or type(d) ~= 'table' or type(d.id) ~= 'string' or #d.id > 140 then return end
    if not (FurnishBuilder and FurnishBuilder.lookAt) then return end
    if not FurnishBuilder.lookAt(d.id) then UI.Notify('It is not placed in the world yet', 'error', 3000) end
end)

--- The skill check ring's settings at a difficulty (shared/skillcheck.lua), for the page to play itself.
RegisterNUICallback('directorSkillLevel', function(d, cb)
    if not DirectorEditorOpen then cb({ ok = false, why = 'The Director is not open' }) return end
    local level, why = SkillCheckLevel(type(d) == 'table' and d.difficulty or nil)
    if not level then cb({ ok = false, why = why }) return end
    cb({ ok = true, level = level })
end)

--- A Speech step's Preview: the line said in that voice (none: its own) by the NPC's builder copy, else by the
--- player. A voice without the line says nothing.
RegisterNUICallback('directorSpeechHear', function(d, cb)
    cb('ok')
    if not DirectorEditorOpen or type(d) ~= 'table' then return end
    local line, voice = d.line, d.voice
    if type(line) ~= 'string' or not line:match('^[%w_]+$') or #line > 64 then return end
    if voice ~= nil and (type(voice) ~= 'string' or not voice:match('^[%w_]*$') or #voice > 64) then return end
    local ped
    if building and FurnishBuilder and type(d.id) == 'string' then
        local it = FurnishBuilder.itemOf(d.id)
        if it and it.obj and DoesEntityExist(it.obj) and GetEntityType(it.obj) == 1 then ped = it.obj end
    end
    if not ped then
        if building then UI.Notify('Place the NPC first to hear it here', 'warning', 3000) return end
        ped = PlayerPedId()
    end
    StopCurrentPlayingAmbientSpeech(ped)
    if voice and voice ~= '' then
        PlayPedAmbientSpeechWithVoiceNative(ped, line, voice, 'SPEECH_PARAMS_FORCE_NORMAL', false)
    else
        PlayPedAmbientSpeechNative(ped, line, 'SPEECH_PARAMS_FORCE_NORMAL')
    end
end)

--- What an NPC's ped can wear, for its page's Outfit (PedOutfit.options).
RegisterNUICallback('directorPedOptions', function(d, cb)
    local model = type(d) == 'table' and type(d.model) == 'string' and d.model or nil
    CreateThread(function()
        local o, why = PedOutfit.options(model)
        if o then cb({ ok = true, c = o.c, p = o.p }) else cb({ ok = false, why = why or 'it could not be read' }) end
    end)
end)

--- A freemode NPC's look in the character editor (EditLook): the Director steps aside, Save hands the look to the page
--- (directorLookMade), then the Director returns (`builder`: in the world builder on the NPC). Answers { ok } at once,
--- or { ok = false, why } when the editor cannot open now (a gun drawn, in a car).
RegisterNUICallback('directorEditLook', function(d, cb)
    d = type(d) == 'table' and d or {}
    local id = type(d.id) == 'string' and #d.id <= 64 and d.id or nil
    if not id then cb({ ok = false, why = 'Which NPC?' }) return end
    local why = LookEditProblem and LookEditProblem() or (not EditLook and 'The character editor is not here') or nil
    if why then cb({ ok = false, why = why }) return end
    local asideN = DirectorScreen.aside()
    if not asideN then cb({ ok = false, why = 'The Director cannot step aside now' }) return end
    cb({ ok = true })
    local look = type(d.look) == 'table' and FREEMODE[d.look.model] and d.look or nil
    local reopen = d.builder == true and id or nil
    local title = type(d.label) == 'string' and d.label ~= '' and DirectorKit.cut(d.label, 60) or id
    CreateThread(function()
        local ok, ewhy = EditLook({ appearance = look, gender = d.model == 'mp_female' and 'female' or 'male',
            title = title, sub = 'Director NPC',
            done = function(made)
                if made then SendNUIMessage({ action = 'directorLookMade', id = id, look = made }) end
                -- Wait out a death so the Director does not return over the death screen.
                CreateThread(function()
                    while PlayerIsDead do Wait(500) end
                    DirectorScreen.back(reopen, asideN)
                end)
            end })
        if not ok then
            SendNUIMessage({ action = 'directorLookMade', id = id, why = ewhy })
            DirectorScreen.back(reopen, asideN)
        end
    end)
end)

--- Checks a typed random-vehicle model is a vehicle this game has. { ok, model } (lower case), or { ok = false, why }.
RegisterNUICallback('directorVehicleModel', function(d, cb)
    local name = type(d) == 'table' and type(d.model) == 'string' and d.model:lower():match('^%s*([%w_]+)%s*$') or nil
    if not name or #name > 64 then cb({ ok = false, why = 'A model name is letters, digits and _ (wagon02x)' }) return end
    local hash = GetHashKey(name)
    if not IsModelInCdimage(hash) then cb({ ok = false, why = name .. ' is not a model this game has: check the spelling' }) return end
    if not IsModelAVehicle(hash) then cb({ ok = false, why = name .. ' is not a vehicle' }) return end
    cb({ ok = true, model = name })
end)

--- A thing the builder placed that the scenario did not have gets its id; the builder's copy is that thing from now on.
RegisterNUICallback('directorBuilderId', function(d, cb)
    cb('ok')
    if not building or type(d) ~= 'table' or not Furnisher.setId then return end
    local index, id = math.tointeger(tonumber(d.index)), d.id
    if index and type(id) == 'string' and id ~= '' and #id <= 64 then
        Furnisher.setId(index, id)
        if held then held.took[#held.took + 1] = id end
    end
end)

--- A route just put down (directorRoutePlaced): its marker becomes point 1.
RegisterNUICallback('directorBuilderConvert', function(d, cb)
    cb('ok')
    local t = type(d) == 'table' and d.thing or nil
    local index = type(d) == 'table' and math.tointeger(tonumber(d.index)) or nil
    if not building or not index or type(t) ~= 'table' or t.kind ~= 'point' or type(t.id) ~= 'string' or #t.id > 140 then return end
    if FurnishBuilder and FurnishBuilder.convert then FurnishBuilder.convert(index, extraOf(t)) end
end)

--- Done: the set is handed back and the builder closes, the page goes on. `record` / `full` / `aside` (a button that
--- takes over: client/director_buttons.lua) keep the camera so the builder reopens there.
RegisterNUICallback('directorBuilderDone', function(d, cb)
    cb('ok')
    if not building or not Furnisher.finish then return end
    builderView = nil
    if type(d) == 'table' and (d.record == true or d.full == true or d.aside == true) and FreeCam.isActive() then
        builderView = { pos = FreeCam.getCoord(), rot = FreeCam.getRot(), fov = (FreeCam.getFov()) }
    end
    leaving = 'page'
    Furnisher.finish()
end)

--- How a Save went: the builder is marked saved, or says why not.
RegisterNUICallback('directorBuilderSaved', function(d, cb)
    cb('ok')
    if not building or type(d) ~= 'table' or not Furnisher.markSaved then return end
    Furnisher.markSaved(d.ok == true, type(d.text) == 'string' and d.text or nil)
end)

-- Out of the way for a while (recording a take: client/director_takes.lua)

DirectorScreen = {}

local asideAt = 0   -- each step aside has its own number: a back() for an older one does nothing

--- Hides the editor (still open, mouse released). Returns this step aside's number for back(), or false when it is
--- not open or already out of the way.
function DirectorScreen.aside()
    if not DirectorEditorOpen or hidden or building or testing then return false end
    hidden = true
    asideAt = asideAt + 1
    Focus.release('director')
    SendNUIMessage({ action = 'directorHide' })
    return asideAt
end

--- Shows the editor again (`reopen`: a car's id to reopen the builder on). `n`: the step aside it ends; a newer one is left.
function DirectorScreen.back(reopen, n)
    if n ~= nil and n ~= asideAt then return end
    show(type(reopen) == 'string' and reopen or nil)
end

--- Calls fn() when the Director closes.
function DirectorScreen.onClose(fn) closeHooks[#closeHooks + 1] = fn end

--- The builder's Vehicles and Weapons lists (also used by client/director_live.lua).
function DirectorScreen.lists() return vehicles(), weaponTiles() end

--- A take from the world builder that could not start: reopens the builder on the car.
function DirectorScreen.reopen(car)
    if not DirectorEditorOpen or hidden or building or type(car) ~= 'string' then return end
    SendNUIMessage({ action = 'directorShow', reopen = car })
end
