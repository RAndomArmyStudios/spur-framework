-- ============================================
-- DIRECTOR TALK MARKS — over the head of an NPC a card waits for this player to talk to
-- ============================================
--
-- The server says which NPCs (server/director/main.lua Director.speak: one with each Talk point a speaking card puts
-- up for this player), and how:
--   'new'      a card wants them to talk to this NPC to go on: the "!" and the talk sign in turn
--   'resume'   they started talking and walked off, and it waits for them: the talk sign alone
-- Drawn over the NPC's head, facing the camera, from up to MARK_FAR metres; close enough for its E prompt
-- (MARK_NEAR), the prompt says it instead. One browser (html/interact3d/talkmark.html), made when first needed and
-- given back after a minute with nothing to draw. The loop waits half a second while there is nothing.

local PAGE, TXD, TEX = 'talkmark', 'whip_dtalk', 'talk'
local DUI_W, DUI_H = 256, 128
local CELL_TALK = { 0.0, 0.0, 0.5, 1.0 }
local CELL_ATTENTION = { 0.5, 0.0, 1.0, 1.0 }
local FLIP_MS = 700        -- 'new': each sign this long in turn
local MARK_FAR = 40.0      -- metres: further, none
local MARK_NEAR = 2.5      -- metres: nearer, its E prompt says it
local SIZE = 0.32          -- metres across, up close
local GROW_FROM = 6.0      -- further than this it grows, so it never looks smaller than from here...
local GROW_MOST = 3.0      -- ...up to this many times its size
local LIFT = 0.42          -- metres over the head bone
local IDLE_MS = 60000
local HEAD_BONE = 31086    -- SKEL_Head

local runs = {}            -- [runId] = { { netId, state }, ... }

local page = DuiPage.new({
    name = 'directortalk', url = ('interact3d/%s.html'):format(PAGE), width = DUI_W, height = DUI_H,
    txd = TXD, tex = TEX, idleMs = IDLE_MS, without = 'talk marks will not draw',
})

RegisterNetEvent('spur_core:client:directorTalkMarks', function(runId, list)
    if type(runId) ~= 'number' then return end
    local out = {}
    for _, m in ipairs(type(list) == 'table' and list or {}) do
        if type(m) == 'table' and tonumber(m.netId) and (m.state == 'new' or m.state == 'resume') then
            out[#out + 1] = { netId = math.tointeger(tonumber(m.netId)), state = m.state }
        end
    end
    runs[runId] = #out > 0 and out or nil
end)

--- Where a mark goes this frame, or nil (too far, or near enough for its E prompt): { x, y, z, d, dx, dy, dz }.
local function placeOf(ent, cam, me)
    if #(me - GetEntityCoords(ent)) < MARK_NEAR then return nil end
    local head = GetPedBoneCoords(ent, HEAD_BONE, 0.0, 0.0, 0.0)
    local x, y, z = head.x, head.y, head.z + LIFT
    local dx, dy, dz = x - cam.x, y - cam.y, z - cam.z
    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
    if d > MARK_FAR or d < 0.01 then return nil end
    return { x = x, y = y, z = z, d = d, dx = dx / d, dy = dy / d, dz = dz / d }
end

local function drawMark(p, state, now)
    local cell = CELL_TALK
    if state == 'new' and (now // FLIP_MS) % 2 == 0 then cell = CELL_ATTENTION end
    local s = SIZE * (p.d > GROW_FROM and math.min(GROW_MOST, p.d / GROW_FROM) or 1.0)
    local rx, ry, rz, ux, uy, uz = WorldQuad.billboardBasis(p.dx, p.dy, p.dz)
    WorldQuad.draw(TXD, TEX, p.x, p.y, p.z, rx, ry, rz, ux, uy, uz, s, s, cell[1], cell[2], cell[3], cell[4], 255, 255, 255, 255)
end

CreateThread(function()
    while true do
        local drew, near = false, false
        if next(runs) then
            local cost = WhipCost.start()
            local cam = GetFinalRenderedCamCoord()
            local me = GetEntityCoords(PlayerPedId())
            local now = GetGameTimer()
            local shown = {}
            for _, list in pairs(runs) do
                for _, m in ipairs(list) do
                    local ent = DirectorKit.entityOfNet(m.netId)
                    local p = ent and placeOf(ent, cam, me) or nil
                    if p then shown[#shown + 1] = { p = p, state = m.state } end
                end
            end
            -- (The browser only while one is near enough to draw; DuiPage gives it back IDLE_MS after.)
            near = #shown > 0
            if near and page:ensure() and page:up() then
                for _, s in ipairs(shown) do drawMark(s.p, s.state, now) end
                drew = true
            end
            WhipCost.stop(drew and 'director talk marks: drawing (every frame near one)' or 'director talk marks: none near', cost)
        end
        -- (Near one but its browser still coming up: nothing to draw with yet, so not every frame.)
        Wait(drew and 0 or near and 100 or (next(runs) and 250 or 500))
    end
end)
