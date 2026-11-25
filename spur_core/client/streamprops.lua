-- Shared prop streaming: one 500 ms thread spawns and despawns world props by distance for every registered
-- stream (containers.lua, shops.lua, the furniture). A stream can ask for an immediate pass (passNow).
-- Not grid-backed: a pass is a few arithmetic ops per def and defs number in the dozens.

StreamProps = {}

local streams = {}   -- [name] = descriptor, see addStream

--- Register a streamed prop set. The thread below decides spawn/despawn; the caller keeps its defs table and
--- prop lifecycle functions. defs and isSpawned are closures because callers rebind their locals on full sync.
---
---@param opts table {
---   name      string    unique stream name (re-registering replaces)
---   defs      function  () → live defs table ([id] = data with .x/.y/.z, and .reach: how far the thing
---                        spreads from that point, added to the range)
---   range     function  () → stream-in distance in metres
---   isSpawned function  (id) → is this prop currently in the world
---   spawn     function  (data) puts the prop in the world
---   despawn   function  (id) removes it
---   beforePass function|nil  () run at the start of each of its passes (prop sets look at the player's interior)
--- }
function StreamProps.addStream(opts)
    streams[opts.name] = opts
end

--- One stream's pass, separate so it can be pcall'd.
local function passStream(s, px, py, pz)
    if s.beforePass then s.beforePass() end
    local range = s.range()
    local rangeSq = range * range
    for id, data in pairs(s.defs()) do
        local dx = px - data.x
        local dy = py - data.y
        local dz = pz - data.z
        -- A def with a reach is measured to its edge, not its centre.
        local limitSq = rangeSq
        local reach = data.reach
        if reach and reach > 0 then limitSq = (range + reach) * (range + reach) end
        if (dx * dx + dy * dy + dz * dz) <= limitSq then
            if not s.isSpawned(id) then s.spawn(data) end
        elseif s.isSpawned(id) then
            s.despawn(id)
        end
    end
end

--- Where streaming is measured from: the player, or the camera while a free camera is on (the Director's placing
--- leaves the player behind with pedFollows = false; other free cameras keep the ped with them).
local function centre()
    if FreeCam and FreeCam.isActive() then
        local c = FreeCam.getCoord()
        if c then return c.x, c.y, c.z end
    end
    local p = GetEntityCoords(PlayerPedId())
    return p.x, p.y, p.z
end

local queued = {}   -- [name] = true: a passNow waiting for its thread

--- One stream's pass now, in its own thread (a spawn can wait on its model). Asked many times in one tick, it is
--- one pass.
---@param name string
function StreamProps.passNow(name)
    local s = streams[name]
    if not s or queued[name] then return end
    queued[name] = true
    CreateThread(function()
        queued[name] = nil
        local px, py, pz = centre()
        local ok, err = pcall(passStream, s, px, py, pz)
        if not ok then print(('[spur_core:streamprops] stream "%s" failed a pass: %s'):format(tostring(name), tostring(err))) end
    end)
end

CreateThread(function()
    while true do
        local px, py, pz = centre()

        -- Each stream in its own pcall so one bad def cannot end the shared loop.
        for name, s in pairs(streams) do
            local cost = WhipCost.start()
            local ok, err = pcall(passStream, s, px, py, pz)
            if cost then WhipCost.stop('streamed props: ' .. tostring(name), cost) end
            if not ok then
                print(('[spur_core:streamprops] stream "%s" failed a pass: %s'):format(tostring(name), tostring(err)))
            end
        end

        Wait(500)
    end
end)
