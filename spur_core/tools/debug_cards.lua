-- ============================================
-- Debug cards — stats over nearby players and whip cars
-- ============================================
--
-- Player Stats Debug and Vehicle Stats Debug put a card over every player and whip car near you: not
-- over you, and not over the car you are in, whose stats are in the debug panel. One browser (DUI)
-- paints every card into its own cell of one texture (html/debug3d/cards.html), the /me bubbles' way;
-- each frame a cell is drawn as a SCREEN sprite at its entity's root (SetDrawOrigin + DrawSpriteUv),
-- so it faces the camera and shows through walls and bodywork.
--
--   DebugCards.set(key, entity, card)   card = { title, sub, rows = { { n, p, v, c, d } }, note }
--                                       `entity` may be a vector3 instead: a card at a place (the Ground
--                                       page's grid cells)
--                                       n name, p percent, v value text, c colour, d dim
--   DebugCards.remove(key)
--   DebugCards.keep(prefix, keys)       every card under `prefix` not in `keys` goes
--
-- Callers pass the nearest first: when every cell is taken, the rest are not shown.
--
-- Per frame only while a card is up; the browser goes 15 s after the last card does.

DebugCards = {}

local CELL_W, CELL_H, COLS, CELLS = 512, 512, 2, 8
local ROWS = math.ceil(CELLS / COLS)
local TXD, TEX = 'whip_debugcards_txd', 'cards'

local SEND_MS   = 250     -- a card's words go to the page at most four times a second
local WIDTH     = 0.15    -- a card's width close up, in screen widths
local NEAR, FAR = 6.0, 60.0
local MIN_SCALE = 0.55    -- how small it gets at FAR and beyond
local IDLE_MS   = 15000   -- the browser is kept this long after the last card, for the next one

local cards = {}     -- [key] = { cell, entity, json, pending, sentAt }
local cellKey = {}   -- [cell] = key
local looping = false

--- The browser: made with the first card (messages wait until it is up), kept while any card is up (the draw loop
--- uses it every frame), and given back IDLE_MS after the last one, for the next card.
local page = DuiPage.new({
    name = 'debugcards', url = ('debug3d/cards.html?w=%d&h=%d&cols=%d&cells=%d'):format(CELL_W, CELL_H, COLS, CELLS),
    width = CELL_W * COLS, height = CELL_H * ROWS, txd = TXD, tex = TEX, idleMs = IDLE_MS,
    without = 'the debug cards will not draw',
})

local function send(msg)
    page:send(msg)
end

--- How big a card is drawn at `dist` metres: full size close up, shrinking to MIN_SCALE by FAR.
local function scaleAt(dist)
    if dist <= NEAR then return 1.0 end
    if dist >= FAR then return MIN_SCALE end
    return 1.0 - (1.0 - MIN_SCALE) * ((dist - NEAR) / (FAR - NEAR))
end

--- Every frame while a card is up.
local function drawLoop()
    looping = true
    while next(cards) do
        local now = GetGameTimer()
        page:used()
        if page:up() then
            local cam = GetFinalRenderedCamCoord()
            local aspect = GetAspectRatio(false)
            for _, c in pairs(cards) do
                if c.pending and now - c.sentAt >= SEND_MS then
                    send({ cell = c.cell - 1, card = c.pending })
                    c.pending, c.sentAt = nil, now
                end
                local ent = c.entity
                local p = type(ent) == 'vector3' and ent
                    or (ent and DoesEntityExist(ent) and GetEntityCoords(ent)) or nil
                if p then
                    local dx, dy, dz = p.x - cam.x, p.y - cam.y, p.z - cam.z
                    local w = WIDTH * scaleAt(math.sqrt(dx * dx + dy * dy + dz * dz))
                    local h = w * (CELL_H / CELL_W) * aspect
                    local col, row = (c.cell - 1) % COLS, (c.cell - 1) // COLS
                    local u0, v0 = col / COLS, row / ROWS
                    SetDrawOrigin(p.x, p.y, p.z, 0)
                    DrawSpriteUv(TXD, TEX, 0.0, 0.0, w, h, u0, v0, u0 + 1 / COLS, v0 + 1 / ROWS,
                        0.0, 255, 255, 255, 255)
                    ClearDrawOrigin()
                end
            end
        end
        Wait(0)
    end
    looping = false
end

local function freeCell()
    for i = 1, CELLS do
        if not cellKey[i] then return i end
    end
    return nil
end

--- Show (or update) a card over `entity`. A card whose words have not changed sends nothing.
---@param key string     'p:<serverId>', 'v:<vehicleId>'
---@param entity number
---@param card table
function DebugCards.set(key, entity, card)
    local c = cards[key]
    if not c then
        local cell = freeCell()
        if not cell then return end   -- every cell taken by a nearer one
        if not page:ensure() then return end
        c = { cell = cell, sentAt = 0 }
        cards[key] = c
        cellKey[cell] = key
    end
    c.entity = entity
    local j = json.encode(card)
    if j ~= c.json then
        c.json, c.pending = j, card
    end
    -- Marked here, not in the loop: a thread first runs on the next tick, so a second set in the same frame started a
    -- second loop (as client/property_listing.lua learnt; audit 20, ARC-2)
    if not looping then looping = true; CreateThread(drawLoop) end
end

---@param key string
function DebugCards.remove(key)
    local c = cards[key]
    if not c then return end
    cards[key] = nil
    cellKey[c.cell] = nil
    send({ cell = c.cell - 1, clear = true })
end

--- Every card under `prefix` that is not in `keys` ({ [key] = true }) goes. `{}` takes them all.
---@param prefix string
---@param keys table
function DebugCards.keep(prefix, keys)
    for key in pairs(cards) do
        if key:sub(1, #prefix) == prefix and not keys[key] then DebugCards.remove(key) end
    end
end
