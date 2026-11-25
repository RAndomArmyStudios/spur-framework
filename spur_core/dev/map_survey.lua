-- RedM (spur_core, 25 Nov 2026): new. Reads RDR2's ground, water and roads for the 3D map (dev/map3d_rdr.py makes
-- map/rdr-map3d.js from it). Part of spur_core (LGPL-3.0), the RedM port of whip_core by Whippy and WLVF; non-commercial.
--
-- A dev tool, not in the manifest: run in the game as one game_lua chunk (this file's text), in developer mode. It
-- starts a thread and returns at once. MapSurvey.status() says how far it is, MapSurvey.stop() ends it. It writes
-- what it reads to the game's console as "MAPSV ..." lines, which land in the RedM log on this PC
-- (%LOCALAPPDATA%/RedM/RedM.app/logs); dev/map_survey_read.py collects them. Nothing goes to the server.
--
-- How (natives probed in game, 25 Nov 2026): zone natives answer anywhere, so a fast pass marks the map (a district
-- or a water zone, Guarma left out). Road nodes load anywhere for a box requested every frame. Collision streams
-- round the camera focus with no teleport (about 2.5 s for 300 x 200 m), so the ground is read block by block with
-- the player frozen where they stand. A downward probe stops at the topmost thing (roofs, trees, rocks), so each
-- point is peeled: ground Z again from 0.3 m under each hit, every layer kept; the reader picks the terrain.
--
-- MapSurvey.start{ phases = 'mbr', from = 1, box = {x0, y0, x1, y1} }: m the mask, b the ground blocks, r the roads
-- (in that order: a node query is made at the ground's height); `from` restarts the blocks at that number
-- (status().block); `box` limits it all (a test).

MapSurvey = MapSurvey or {}
local S = MapSurvey
local out = rawget(_G, 'print')   -- the console's own print (a game_lua chunk's print only goes back to the caller)
local N = Citizen.InvokeNative
local RI, PF, PV, PI = Citizen.ResultAsInteger, Citizen.PointerValueFloat, Citizen.PointerValueVector, Citizen.PointerValueInt
local floor, sqrt, abs = math.floor, math.sqrt, math.abs

local X0, Y0, STEP, NX, NY = -7000.0, -5600.0, 20.0, 551, 456   -- x -7000..4000, y -5600..3500
local B = 12                                                     -- a block is 12 x 12 points (240 m)
local TOP = 1500.0                                               -- probes start here, over every peak

local function px(i) return X0 + i * STEP end
local function py(j) return Y0 + j * STEP end
local function guarma(x, y) return x >= -600 and y <= -3600 end

local function now() return GetGameTimer() end

-- ---- what goes out: one line of at most 900 characters each, numbered parts ----
local seq = 0
local function emit(kind, head, body)
    seq = seq + 1
    local n = math.max(1, math.ceil(#body / 900))
    for p = 1, n do
        out(('MAPSV %s %d %s %d/%d %s'):format(kind, seq, head, p, n, body:sub((p - 1) * 900 + 1, p * 900)))
    end
end

-- ---- natives ----
local function groundZ(x, y, z)
    local ok, gz = N(0x24FA4267BB8D2431, x, y, z, PF(), false, RI())   -- GET_GROUND_Z_FOR_3D_COORD
    if ok == 1 then return gz end
end
local function layers(x, y)
    local z = groundZ(x, y, TOP)
    if not z then return nil end
    local t = { floor(z * 10 + 0.5) }
    for _ = 1, 7 do
        z = groundZ(x, y, z - 0.3)
        if not z then break end
        t[#t + 1] = floor(z * 10 + 0.5)
    end
    return t
end
local function water(x, y, z)
    local hit, h = N(0x2B3451FA1E3142E2, x, y, z, 1, PF(), RI())      -- TEST_VERTICAL_PROBE_AGAINST_ALL_WATER
    if hit == 1 and h then return floor(h * 10 + 0.5) end
end
local function district(x, y) return N(0x43AD8FC02B429D33, x, y, 100.0, 10, RI()) end   -- _GET_MAP_ZONE_AT_COORDS
local function waterZone(x, y) return N(0x5BA7A68A346A5A91, x, y, 100.0, RI()) end        -- _GET_WATER_MAP_ZONE_AT_COORDS
local function focus(x, y, z)
    N(0x25F6EF88664540E2, x, y, z, 0.0, 0.0, 0.0)   -- SET_FOCUS_POS_AND_VEL
    N(0x0A3720F162A033C9, x, y, z)                  -- REQUEST_COLLISION_AT_COORD
end

-- ---- state ----
S.mask = S.mask or nil      -- [j*NX + i + 1] = 0 none, 1 district, 2 water zone
S.hz = S.hz or {}           -- [j*NX + i + 1] = the lowest layer read there (the road queries' height)
S.state = S.state or { phase = 'idle' }   -- kept when this chunk runs again, so a second start sees the first
local st = S.state

local function inBox(x, y)
    local b = st.box
    return not b or (x >= b[1] and y >= b[2] and x <= b[3] and y <= b[4])
end

-- ---- m: the mask ----
local function maskPass()
    st.phase = 'mask'
    local m, rows = {}, 0
    for j = 0, NY - 1 do
        local y, row, last, run = py(j), {}, -1, 0
        for i = 0, NX - 1 do
            local x, c = px(i), 0
            if inBox(x, y) and not guarma(x, y) then
                if waterZone(x, y) ~= 0 then c = 2 elseif district(x, y) ~= 0 then c = 1 end
            end
            m[j * NX + i + 1] = c
            if c == last then run = run + 1 else
                if run > 0 then row[#row + 1] = last .. 'x' .. run end
                last, run = c, 1
            end
        end
        row[#row + 1] = last .. 'x' .. run
        emit('M', tostring(j), table.concat(row, ','))
        rows = rows + 1
        if rows % 8 == 0 then Wait(0) end
        if st.stop then return end
    end
    -- Districts leave seams (no district answers along some edges, as at Valentine's south-west), so the points
    -- within 3 of a marked one are surveyed too (3, not printed: the reader needs only the water zone).
    local R = 3
    for j = 0, NY - 1 do
        local y = py(j)
        for i = 0, NX - 1 do
            local k = j * NX + i + 1
            if m[k] == 0 and inBox(px(i), y) and not guarma(px(i), y) then
                local near = false
                for jj = math.max(0, j - R), math.min(NY - 1, j + R) do
                    for ii = math.max(0, i - R), math.min(NX - 1, i + R) do
                        local c = m[jj * NX + ii + 1]
                        if c == 1 or c == 2 then near = true break end
                    end
                    if near then break end
                end
                if near then m[k] = 3 end
            end
        end
        if j % 16 == 0 then Wait(0) end
        if st.stop then return end
    end
    S.mask = m
end

-- ---- r: the roads ----
local function roadPass()
    st.phase = 'roads'
    local seen, buf, nodes = {}, {}, 0
    local function flush()
        if #buf > 0 then emit('N', '-', table.concat(buf, ';')) buf = {} end
    end
    local T = 2000.0
    for ty = Y0, py(NY - 1), T do
        for tx = X0, px(NX - 1), T do
            if st.stop then return end
            -- the tile's 40 m points on the map
            local pts = {}
            for j = floor((ty - Y0) / STEP), math.min(NY - 1, floor((ty + T - Y0) / STEP) - 1), 2 do
                for i = floor((tx - X0) / STEP), math.min(NX - 1, floor((tx + T - X0) / STEP) - 1), 2 do
                    if S.mask[j * NX + i + 1] ~= 0 then
                        pts[#pts + 1] = { px(i), py(j), (S.hz[j * NX + i + 1] or st.lastZ or 150.0) + 1.0 }
                    end
                end
            end
            if #pts > 0 then
                local x1, y1, x2, y2 = tx - 500, ty - 500, tx + T + 500, ty + T + 500
                local by = now() + 1500
                repeat
                    N(0x07FB139B592FA687, x1, y1, x2, y2)   -- REQUEST_PATH_NODES_IN_AREA_THIS_FRAME
                    Wait(0)
                until N(0xF7B79A50B905A30D, tx, ty, tx + T, ty + T, RI()) == 1 or now() > by   -- ARE_NODES_LOADED_FOR_AREA
                local k = 1
                while k <= #pts do
                    N(0x07FB139B592FA687, x1, y1, x2, y2)
                    for _ = 1, 60 do
                        local p = pts[k]
                        if not p then break end
                        for n = 1, 24 do
                            local ok, pos, hd, lanes = N(0x591B40D4390DB54A, p[1], p[2], p[3], n, PV(), PF(), PI(), 1, 3.0, 0.0, RI())
                            if ok ~= 1 or not pos then break end
                            local dx, dy = pos.x - p[1], pos.y - p[2]
                            if dx * dx + dy * dy > 34 * 34 then break end
                            local key = floor(pos.x * 2 + 0.5) .. ',' .. floor(pos.y * 2 + 0.5)
                            if not seen[key] then
                                seen[key] = true
                                nodes = nodes + 1
                                buf[#buf + 1] = ('%d,%d,%d,%d,%d'):format(floor(pos.x * 10 + 0.5), floor(pos.y * 10 + 0.5),
                                    floor(pos.z * 10 + 0.5), floor((hd or 0) + 0.5), tonumber(lanes) or 0)
                                if #buf >= 40 then flush() end
                            end
                        end
                        k = k + 1
                    end
                    st.nodes = nodes
                    Wait(0)
                end
            end
        end
    end
    flush()
end

-- ---- b: the ground, block by block ----
local function blockList()
    local list = {}
    for bj = 0, math.ceil(NY / B) - 1 do
        for bi = 0, math.ceil(NX / B) - 1 do
            local any = false
            for j = bj * B, math.min(NY - 1, bj * B + B - 1) do
                for i = bi * B, math.min(NX - 1, bi * B + B - 1) do
                    if S.mask[j * NX + i + 1] ~= 0 then any = true break end
                end
                if any then break end
            end
            if any then list[#list + 1] = { bi, bj } end
        end
    end
    return list
end

local guess = {}   -- a block's mean ground height, for the next block's focus height

local function readBlock(bi, bj)
    local pts, need = {}, 0
    for j = bj * B, math.min(NY - 1, bj * B + B - 1) do
        for i = bi * B, math.min(NX - 1, bi * B + B - 1) do
            local mv = S.mask[j * NX + i + 1]
            local m = mv == 1 or mv == 2   -- waited for and looked for again; a seam point (3) is taken if it answers
            pts[#pts + 1] = { i = i, j = j, x = px(i), y = py(j), m = m, s = mv == 3 }
            if m then need = need + 1 end
        end
    end
    local cz = guess[(bj - 1) .. ',' .. bi] or guess[bj .. ',' .. (bi - 1)] or st.lastZ or 150.0
    local cx, cy = px(bi * B + B / 2 - 0.5), py(bj * B + B / 2 - 0.5)
    for try = 1, 3 do
        local t0, lastNew = now(), now()
        while true do
            focus(cx, cy, cz)
            local missing, seam, sumZ, nZ = 0, 0, 0, 0
            for _, p in ipairs(pts) do
                if not p.l then
                    p.l = layers(p.x, p.y)
                    if p.l then lastNew = now() end
                end
                if p.l then sumZ, nZ = sumZ + p.l[#p.l] / 10, nZ + 1
                elseif p.m then missing = missing + 1 elseif p.s then seam = seam + 1 end
            end
            if nZ > 0 then cz = sumZ / nZ + 2.0 end
            local t = now() - t0
            if missing == 0 and t > 300 and (seam == 0 or t > 1500) then break end
            if t > 4500 or (t > 1500 and now() - lastNew > 800) then break end
            Wait(0)
            if st.stop then return end
        end
        -- peel again now it has all streamed (a roof can come in before the ground under it), keeping the deeper
        for _, p in ipairs(pts) do
            if p.l then
                local again = layers(p.x, p.y)
                if again and again[#again] < p.l[#p.l] then p.l = again end
            end
        end
        -- water: once the ground is in (the probe's reach is about 150 m round the focus)
        for _, p in ipairs(pts) do
            if not p.w then p.w = water(p.x, p.y, p.l and (p.l[1] / 10 + 30.0) or 600.0) end
        end
        -- another look from the middle of what did not answer; if nothing did, higher, then lower
        local mx, my, mn, any = 0, 0, 0, false
        for _, p in ipairs(pts) do
            if p.l then any = true elseif p.m then mx, my, mn = mx + p.x, my + p.y, mn + 1 end
        end
        if mn == 0 or try == 3 then break end
        if any then cx, cy = mx / mn, my / mn else cz = cz + (try == 1 and 300.0 or -450.0) end
        st.retries = (st.retries or 0) + 1
    end
    local body, sum, n = {}, 0, 0
    for k, p in ipairs(pts) do
        body[k] = (p.l and table.concat(p.l, '/') or '') .. (p.w and ('~' .. p.w) or '')
        if p.l then
            sum, n = sum + p.l[#p.l] / 10, n + 1
            S.hz[p.j * NX + p.i + 1] = p.l[#p.l] / 10
        elseif p.m then st.missed = (st.missed or 0) + 1 end
    end
    if n > 0 then guess[bj .. ',' .. bi] = sum / n + 2.0 st.lastZ = sum / n + 2.0 end
    emit('B', bi .. ' ' .. bj, table.concat(body, ';'))
end

local function blockPass(from)
    st.phase = 'blocks'
    local list = blockList()
    st.blocks = #list
    local ped = PlayerPedId()
    st.home = GetEntityCoords(ped)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    local t0 = now()
    for k = from or 1, #list do
        st.block = k
        readBlock(list[k][1], list[k][2])
        if st.stop then break end
        local done = k - (from or 1) + 1
        st.eta_min = floor((now() - t0) / done * (#list - k) / 60000 + 0.5)
    end
end

local function finish()
    N(0x86CCAF7CE493EFBE)   -- CLEAR_FOCUS
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)
    st.phase = st.stop and 'stopped' or 'done'
    emit('E', st.phase, ('%d lines'):format(seq))
end

function S.start(o)
    if st.running then return 'already running: MapSurvey.status()' end
    o = o or {}
    for k in pairs(st) do st[k] = nil end
    st.running, st.box, st.started = true, o.box, now()
    local phases = o.phases or 'mbr'
    CreateThread(function()
        local ok, err = pcall(function()
            emit('H', '-', json.encode({ v = 1, x0 = X0, y0 = Y0, step = STEP, nx = NX, ny = NY, b = B, top = TOP,
                phases = phases, from = o.from, box = o.box }))
            if phases:find('m') or not S.mask then maskPass() end
            if not st.stop and phases:find('b') then blockPass(o.from) end
            if not st.stop and phases:find('r') then roadPass() end   -- after the ground: a node query wants its height
        end)
        if not ok then st.err = tostring(err) out('MAPSV X ' .. tostring(err)) end
        finish()
        st.running = false
    end)
    return 'started'
end

function S.stop() st.stop = true return 'stopping' end

function S.status()
    return { phase = st.phase, running = st.running == true, block = st.block, blocks = st.blocks, eta_min = st.eta_min,
        nodes = st.nodes, retries = st.retries, missed = st.missed, lines = seq, err = st.err,
        minutes = st.started and floor((now() - st.started) / 6000) / 10 }
end

return 'MapSurvey ready: MapSurvey.start{ phases = "mbr" } (m mask, b ground, r roads); status(), stop()'
