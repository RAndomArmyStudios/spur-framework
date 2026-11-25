-- ============================================
-- /propcheck — does every catalog prop actually spawn?
-- ============================================
--
--   /propcheck           start, or carry on where the last one stopped
--   /propcheck           (again, while it runs) stop; it carries on from there next time
--   /propcheck restart   from the first prop again
--
-- Developer mode. Every prop the furnisher offers (Furnisher.catalog) is loaded and made once, out of
-- sight under the player, then deleted — the real test, where the login's check (property_furnish.lua)
-- only asks whether the game has the name. One that does not load, or does not come into being, is
-- binned: marked unavailable for everyone (the server's propCatalogBroken), as /prop remove does.
--
-- Thousands of props take minutes: the chat says how far it is every few hundred. PROGRESS IS KEPT
-- (this game's KVP), so a stop or a crash carries on from the last prop done; and the model being made
-- when the game went down is binned when it starts again, as the one that took it down.

local KVP_LAST    = 'whip:propcheck:last'      -- the last model checked (the list is in name order)
local KVP_TESTING = 'whip:propcheck:testing'   -- the model being made right now
local LOAD_MS     = 8000    -- the longest one may take to load before it counts as failed
local SAY_EVERY   = 500     -- a progress line every so many
local SEND_EVERY  = 100     -- failures sent to the server in batches this size (its limit is 200)

local running = false

local function say(text)
    print('[spur_core:propcheck] ' .. text)
    TriggerEvent('chat:addMessage', { args = { 'Prop check', text } })
end

--- Load it, make it 60 m under the player, delete it. True when it came into being.
local function spawns(model)
    local hash = LoadModel(model, LOAD_MS)
    if not hash then return false end
    local c = GetEntityCoords(PlayerPedId())
    local obj = CreateObjectNoOffset(hash, c.x, c.y, c.z - 60.0, false, false, false)
    local made = obj ~= 0 and DoesEntityExist(obj)
    if made then
        FreezeEntityPosition(obj, true)
        DeleteObject(obj)
    end
    SetModelAsNoLongerNeeded(hash)
    return made
end

local function send(list)
    if #list == 0 then return end
    TriggerServerEvent('spur_core:server:propCatalogBroken', list)
end

local function run(fromStart)
    running = true
    if fromStart then DeleteResourceKvp(KVP_LAST) end
    local failed = {}

    -- The game went down while making this one last time: that is a fail. (A spur_core restart or a logout mid-check
    -- lets go of the mark, below, so only the game itself going away leaves it: a crash, or the game closed.)
    local crashed = GetResourceKvpString(KVP_TESTING)
    if crashed and crashed ~= '' then
        failed[#failed + 1] = crashed
        say(('%s was being made when the game last went down: binned. If the game only closed then, that prop is fine: put it back in the prop catalog'):format(crashed))
        print(('^3[propcheck] BINNED %s: it was being made when the game last went down (a crash, or the game closed mid-check)^7'):format(crashed))
        DeleteResourceKvp(KVP_TESTING)
    end

    local models = {}
    for _, p in ipairs((Furnisher.catalog() or {}).props or {}) do
        if type(p.model) == 'string' then models[#models + 1] = p.model:lower() end
    end
    table.sort(models)
    local last = GetResourceKvpString(KVP_LAST)
    local todo = {}
    for _, m in ipairs(models) do
        if not last or m > last then todo[#todo + 1] = m end
    end
    if #todo == 0 then
        send(failed)
        say(('all %d props were checked already (/propcheck restart to go again)'):format(#models))
        running = false
        return
    end
    say(('%d of %d props to check%s — /propcheck again stops it'):format(#todo, #models,
        last and ' (carrying on)' or ''))

    local bad, done = #failed, 0
    for _, model in ipairs(todo) do
        if not running then break end
        SetResourceKvp(KVP_TESTING, model)
        if not spawns(model) then
            failed[#failed + 1] = model
            bad = bad + 1
        end
        DeleteResourceKvp(KVP_TESTING)
        SetResourceKvp(KVP_LAST, model)
        done = done + 1
        if #failed >= SEND_EVERY then send(failed); failed = {} end
        if done % SAY_EVERY == 0 then say(('%d / %d checked, %d binned'):format(done, #todo, bad)) end
        Wait(0)
    end
    send(failed)

    if running then
        say(('done: %d checked, %d did not spawn and are hidden now (the server console lists them)'):format(done, bad))
    else
        say(('stopped after %d (%d binned): /propcheck carries on from there'):format(done, bad))
    end
    running = false
end

RegisterCommand('propcheck', function(_, args)
    if not (DevToolsOn and DevToolsOn()) then
        say('developer mode only (/w)')
        return
    end
    if running then
        running = false   -- the loop sees it and stops after the prop it is on
        return
    end
    CreateThread(function() run(args[1] == 'restart') end)
end, false)

AddEventHandler('spur_core:player:loaded', function()
    TriggerEvent('chat:addSuggestion', '/propcheck', 'Spawn every catalog prop once and hide the ones that fail (developer mode)', {
        { name = 'restart', help = 'from the first prop again; left out, carries on' },
    })
end)

-- A check cut short by spur_core stopping (a restart, a sync) or a logout is not a crash: the prop it was on is let go
-- of, and the next run carries on from it. Left set, the next run binned that working prop for everyone (audit 20, DX-9).
local function cutShort()
    running = false
    DeleteResourceKvp(KVP_TESTING)
end
AddEventHandler('onResourceStop', function(res) if res == GetCurrentResourceName() then cutShort() end end)
AddEventHandler('spur_core:player:logout', cutShort)
