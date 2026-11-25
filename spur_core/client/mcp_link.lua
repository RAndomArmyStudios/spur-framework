-- ============================================
-- MCP link: an MCP client on this PC (Claude Code) testing the game without the mouse or keyboard
-- ============================================
-- RedM (spur_core, 24 Nov 2026): new. whip_core by Whippy and WLVF had the pieces for this (the screen probe, the
-- screenshot, the error log: made for their whip_devlink "AI link", which is not in the repo); this is the link.
--
-- OFF unless this PC turned it on for this server (/mcplink on, or the server console's spur_mcplink: kept in this
-- PC's KVP, so it stays on across launches) AND the player holds whip.devtools. Then spur_core's page
-- (html/js/mcp-link.js) asks the MCP server on this PC (dev/mcp/spur_mcp.mjs, http://127.0.0.1 only) for the next
-- thing to do, hands it here on the mcpLink callback, and posts the answer back. Nothing listens on the network: the
-- page only goes out, to this PC, and only the MCP server's own client (its stdin) can give it anything to do.
--
-- What it does (each refused while the player lacks whip.devtools; screen, press, command and lua also need
-- developer mode on, as /w's tools do): status, devmode, screen (ReadScreen), press (PressScreen), command
-- (ExecuteCommand, as F8 would), lua (a chunk run here, its results back), shot (TakeScreenshot), errors (GetErrorLog).

local KVP = 'spur:mcplink'
local KVP_PORT = 'spur:mcplink:port'
local DEFAULT_PORT = 47130
local RES = GetCurrentResourceName()

local eligible = false     -- whip.devtools, as the server last said (spur_core:devtools:access)
local askedAt = -60000
local loaded = false       -- a character is in the world

local function wanted() return GetResourceKvpString(KVP) == 'on' end
local function port()
    local p = tonumber(GetResourceKvpString(KVP_PORT) or '')
    return (p and p >= 1024 and p <= 65535) and math.floor(p) or DEFAULT_PORT
end

--- Ask the server again (at most every 20 s unless forced). Yields.
local function refreshAccess(force)
    if not force and GetGameTimer() - askedAt < 20000 then return eligible end
    askedAt = GetGameTimer()
    local ok, access = pcall(Callback, 'spur_core:devtools:access')
    if ok and type(access) == 'table' then eligible = access.eligible == true end
    return eligible
end

local function tellPage()
    SendNUIMessage({ action = 'mcpLink', on = wanted() and eligible, port = port() })
end

-- ---- Answers in plain data (vectors as { x, y, z }, no functions, no cycles) ----

local function plain(v, depth, seen)
    local t = type(v)
    if t == 'nil' or t == 'boolean' or t == 'string' then return v end
    if t == 'number' then
        if v ~= v or v == math.huge or v == -math.huge then return tostring(v) end
        return v
    end
    if t == 'vector2' then return { x = v.x, y = v.y } end
    if t == 'vector3' then return { x = v.x, y = v.y, z = v.z } end
    if t == 'vector4' or t == 'quat' then return { x = v.x, y = v.y, z = v.z, w = v.w } end
    if t ~= 'table' then return tostring(v) end
    depth, seen = depth or 0, seen or {}
    if depth >= 6 then return '<table>' end
    if seen[v] then return '<cycle>' end
    seen[v] = true
    local n, count, array = #v, 0, true
    for k in pairs(v) do
        count = count + 1
        if math.type(k) ~= 'integer' or k < 1 or k > n then array = false end
    end
    local out = {}
    if array then
        for i = 1, math.min(n, 1000) do out[i] = plain(v[i], depth + 1, seen) end
    else
        local i = 0
        for k, x in pairs(v) do
            i = i + 1
            if i > 1000 then out['...'] = ('%d more'):format(count - 1000) break end
            out[tostring(k)] = plain(x, depth + 1, seen)
        end
    end
    seen[v] = nil
    return out
end

local function round(x) return math.floor(x * 100 + 0.5) / 100 end
-- RedM's BOOL natives can answer 1 or 0 (and 0 is true in Lua): status answers true or false.
local function yes(v) return v == true or (type(v) == 'number' and v ~= 0) end

local function status()
    local ped = PlayerPedId()
    local s = {
        resource = RES, serverId = GetPlayerServerId(PlayerId()), character = loaded,
        devMode = DevToolsOn and DevToolsOn() or false, eligible = eligible,
        nuiFocus = yes(IsNuiFocused()), gameTimer = GetGameTimer(),
    }
    pcall(function()
        local c = GetEntityCoords(ped)
        s.coords = { x = round(c.x), y = round(c.y), z = round(c.z) }
        s.heading = round(GetEntityHeading(ped))
        s.health = GetEntityHealth(ped)
        s.dead = yes(IsEntityDead(ped))
        s.pedModel = GetEntityModel(ped)
        s.inVehicle = GetVehiclePedIsIn(ped, false) ~= 0
        s.mounted = yes(IsPedOnMount(ped))
    end)
    return s
end

--- A chunk of Lua run here: `return <it>` first (an expression), else as statements. Its print() lines come back
--- with its results; globals it sets stay (the resource's own), so a later chunk can read them.
local function runLua(code)
    if type(code) ~= 'string' or code == '' or #code > 20000 then return false, nil, 'code: Lua, 20,000 characters at most' end
    local printed = {}
    local env = setmetatable({
        print = function(...)
            local parts = table.pack(...)
            for i = 1, parts.n do parts[i] = tostring(parts[i]) end
            if #printed < 200 then printed[#printed + 1] = table.concat(parts, '\t', 1, parts.n) end
        end,
    }, { __index = _G, __newindex = _G })
    local fn, err = load('return ' .. code, '=mcp', 't', env)
    if not fn then fn, err = load(code, '=mcp', 't', env) end
    if not fn then return false, nil, 'does not compile: ' .. tostring(err) end
    local r = table.pack(pcall(fn))
    if not r[1] then return false, { printed = printed }, tostring(r[2]) end
    local results = {}
    for i = 2, r.n do results[i - 1] = plain(r[i]) end
    return true, { results = results, count = r.n - 1, printed = printed }
end

local function needDev()
    if not (DevToolsOn and DevToolsOn()) then return 'developer mode is off (devmode on first)' end
end

local handlers = {}

handlers.status = function() return true, status() end

handlers.devmode = function(a)
    local on = a.on == true
    local ok, res, why = pcall(Callback, 'spur_core:devtools:setMode', on)
    if not ok then return false, nil, tostring(res) end
    if res ~= true then return false, nil, why or 'refused' end
    local by = GetGameTimer() + 4000   -- the server's spur_core:client:devMode lands separately
    while DevToolsOn() ~= on and GetGameTimer() < by do Wait(50) end
    return true, { devMode = DevToolsOn() }
end

handlers.screen = function(a)
    local why = needDev() if why then return false, nil, why end
    local r, err = exports[RES]:ReadScreen(type(a.opts) == 'table' and a.opts or {})
    if not r then return false, nil, err or 'refused' end
    return true, plain(r)
end

handlers.press = function(a)
    local why = needDev() if why then return false, nil, why end
    local r, err = exports[RES]:PressScreen(a.target, type(a.opts) == 'table' and a.opts or {})
    if not r then return false, nil, err or 'refused' end
    return true, plain(r)
end

handlers.command = function(a)
    local why = needDev() if why then return false, nil, why end
    if type(a.command) ~= 'string' or a.command == '' or #a.command > 500 then return false, nil, 'command: text' end
    ExecuteCommand(a.command)
    return true, { ran = a.command }
end

handlers.lua = function(a)
    local why = needDev() if why then return false, nil, why end
    return runLua(a.code)
end

handlers.shot = function(a)
    local data, err = Screenshot.take({
        format = 'jpg', quality = tonumber(a.quality) or 0.8, width = tonumber(a.width) or 1280, ui = a.ui == true,
    })
    if not data then return false, nil, err or 'no picture' end
    return true, data
end

handlers.errors = function(a)
    return true, plain(exports[RES]:GetErrorLog({ since = tonumber(a.since), max = tonumber(a.max) or 50 }))
end

RegisterNUICallback('mcpLink', function(data, cb)
    CreateThread(function()
        local cmd = type(data) == 'table' and data.cmd or nil
        local h = type(cmd) == 'string' and handlers[cmd] or nil
        if not wanted() then return cb({ ok = false, err = 'the link is off on this PC (/mcplink on)' }) end
        if not refreshAccess(false) then   -- a revoke is pushed (devtoolsRevoked, below); the ask is a second net
            tellPage()
            return cb({ ok = false, err = 'this account does not have dev tools (whip.devtools)' })
        end
        if not h then return cb({ ok = false, err = 'no such thing to do: ' .. tostring(cmd) }) end
        local ok, okay, result, err = pcall(h, type(data.args) == 'table' and data.args or {})
        if not ok then return cb({ ok = false, err = tostring(okay) }) end
        cb({ ok = okay == true, result = result, err = err })
    end)
end)

-- ---- Turning it on and off ----

local function set(on, p)
    if on then
        if not refreshAccess(true) then
            print('^1[spur_core:mcp] the MCP link needs dev tools (whip.devtools)^0')
            return
        end
        SetResourceKvp(KVP, 'on')
        if p then SetResourceKvp(KVP_PORT, tostring(math.floor(p))) end
    else
        DeleteResourceKvp(KVP)
    end
    tellPage()
    print(('[spur_core:mcp] MCP link %s on this PC (127.0.0.1:%d)'):format(wanted() and 'ON' or 'OFF', port()))
end

RegisterCommand('mcplink', function(_, args)
    local what, p = args[1], tonumber(args[2])
    if what == 'on' or what == 'off' then
        CreateThread(function() set(what == 'on', p) end)
    else
        print(('[spur_core:mcp] MCP link is %s on this PC (127.0.0.1:%d). /mcplink on [port] | off')
            :format(wanted() and 'ON' or 'OFF', port()))
    end
end, false)

-- The server console's spur_mcplink (server/mcp_link.lua): only the server can send this.
RegisterNetEvent('spur_core:client:mcpLink', function(on, p)
    CreateThread(function() set(on == true, tonumber(p)) end)
end)

RegisterNetEvent('spur_core:client:devtoolsGranted', function()
    CreateThread(function() refreshAccess(true) tellPage() end)
end)
RegisterNetEvent('spur_core:client:devtoolsRevoked', function()
    eligible = false
    tellPage()
end)
AddEventHandler('spur_core:player:loaded', function() loaded = true end)

-- The page may load after this runs, and reloads with spur_core: say it again now and then (the page ignores a
-- repeat). Nothing at all while the link is off on this PC.
CreateThread(function()
    while true do
        if wanted() then
            refreshAccess(false)
            tellPage()
            Wait(10000)
        else
            Wait(5000)
        end
    end
end)
