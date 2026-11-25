-- Highlight: the one owner of the game's entity outline. Tools that pick things tell it what is under the pointer
-- (`hover`), what is picked (`selected`) and what a card names (`lit`):
--
--   Highlight.set('furnish', { hover = ent, selected = ent, lit = { ent, ... } })   -- the world builder, Dungeon Mode
--   Highlight.set('furnish', { selected = { ent, ... } })                           -- several picked (Ctrl+click)
--   Highlight.set('objectViewer', { hover = ent, selected = ent })                  -- the /w object viewer
--   Highlight.set('ovPanel', { selected = ent })                                    -- its options, open on one
--   Highlight.set('furnish', nil)                                                   -- let go
--
-- White is under the pointer, blue is picked, green is named by a card.
--
-- An outline goes only on an object: SetEntityDrawOutline on a ped crashes the game, so peds and cars wear corners
-- drawn round their model's box every frame. The outline colour is one setting for all outlines, so only one of the
-- three can be an outline at a time (green over blue over white); an object that loses wears corners in its own
-- colour. A build without the outline natives gets corners for everything.
--
-- A frame thread runs from the first highlight to the last.

Highlight = {}

local owners = {}            -- [owner] = { hover = ent|nil, selected = { [ent] = true }|nil, lit = { [ent] = true }|nil }

local COLOUR = {
    hover    = { 255, 255, 255, 235 },
    selected = { 96, 165, 250, 255 },
    lit      = { 74, 222, 128, 255 },
}

local outlineOk = nil        -- does this build have the outline natives? (asked once, on first use)
local outlined = {}          -- [entity] = true: which carry the outline now
local outlineColour = nil    -- 'hover' | 'selected' | 'lit': the one colour set now
local corners = {}           -- [entity] = 'hover' | 'selected' | 'lit': drawn every frame
local running = false

--- Is it an object (the only kind an outline may go on)?
local function isObject(ent) return GetEntityType(ent) == 3 end

local function hasOutline()
    if outlineOk == nil then
        outlineOk = pcall(SetEntityDrawOutlineColor, COLOUR.selected[1], COLOUR.selected[2], COLOUR.selected[3], 255)
        outlineColour = 'selected'
    end
    return outlineOk
end

--- All owners' entities that are lit, picked and under the pointer (picked wins over hover).
local function wanted()
    local lit, selected, hover = {}, {}, {}
    for _, o in pairs(owners) do
        for ent in pairs(o.lit or {}) do lit[ent] = true end
        for ent in pairs(o.selected or {}) do selected[ent] = true end
        if o.hover then hover[o.hover] = true end
    end
    for ent in pairs(selected) do hover[ent] = nil end
    for ent in pairs(lit) do selected[ent], hover[ent] = nil, nil end
    return lit, selected, hover
end

--- Recompute the outline and corners; called only when what is wanted changes.
local function refresh()
    local lit, selected, hover = wanted()
    local sets = { lit = lit, selected = selected, hover = hover }
    -- The outline colour: the first of green, blue and white that has an object.
    local colour = nil
    if hasOutline() then
        for _, c in ipairs({ 'lit', 'selected', 'hover' }) do
            for ent in pairs(sets[c]) do
                if DoesEntityExist(ent) and isObject(ent) then colour = c break end
            end
            if colour then break end
        end
    end
    local want = {}
    corners = {}
    for _, c in ipairs({ 'lit', 'selected', 'hover' }) do
        for ent in pairs(sets[c]) do
            if DoesEntityExist(ent) then
                if c == colour and isObject(ent) then
                    want[ent] = true
                elseif c ~= 'lit' or isObject(ent) then
                    corners[ent] = c
                end
            end
        end
    end
    if colour and colour ~= outlineColour then
        local k = COLOUR[colour]
        pcall(SetEntityDrawOutlineColor, k[1], k[2], k[3], k[4])
    end
    outlineColour = colour
    for ent in pairs(outlined) do
        if not want[ent] then
            if DoesEntityExist(ent) then pcall(SetEntityDrawOutline, ent, false) end
            outlined[ent] = nil
        end
    end
    for ent in pairs(want) do
        if not outlined[ent] then
            pcall(SetEntityDrawOutline, ent, true)
            outlined[ent] = true
        end
    end
end

-- Corners

local PAD = 0.04            -- metres out from the model's box, so the lines stand clear of it
local ARM = 0.28            -- a corner's arms: this share of its edge, at most ARM_MAX
local ARM_MAX = 0.6

--- [model] = { mn, mx }, read once per model.
local boxes = {}

local function boxOf(ent)
    local model = GetEntityModel(ent)
    local b = boxes[model]
    if b == nil then
        local mn, mx = GetModelDimensions(model)
        b = (mn and mx) and { mn = mn, mx = mx } or false
        boxes[model] = b
    end
    return b or nil
end

--- The eight corners of its box, each with arms along the three edges that meet there.
local function drawCorners(ent, c)
    local b = boxOf(ent)
    if not b then return end
    local k = COLOUR[c]
    local x0, y0, z0 = b.mn.x - PAD, b.mn.y - PAD, b.mn.z - PAD
    local x1, y1, z1 = b.mx.x + PAD, b.mx.y + PAD, b.mx.z + PAD
    local ax = math.min((x1 - x0) * ARM, ARM_MAX)
    local ay = math.min((y1 - y0) * ARM, ARM_MAX)
    local az = math.min((z1 - z0) * ARM, ARM_MAX)
    for _, px in ipairs({ x0, x1 }) do
        local sx = px == x0 and ax or -ax
        for _, py in ipairs({ y0, y1 }) do
            local sy = py == y0 and ay or -ay
            for _, pz in ipairs({ z0, z1 }) do
                local sz = pz == z0 and az or -az
                local p = GetOffsetFromEntityInWorldCoords(ent, px, py, pz)
                local ex = GetOffsetFromEntityInWorldCoords(ent, px + sx, py, pz)
                local ey = GetOffsetFromEntityInWorldCoords(ent, px, py + sy, pz)
                local ez = GetOffsetFromEntityInWorldCoords(ent, px, py, pz + sz)
                DrawLine(p.x, p.y, p.z, ex.x, ex.y, ex.z, k[1], k[2], k[3], k[4])
                DrawLine(p.x, p.y, p.z, ey.x, ey.y, ey.z, k[1], k[2], k[3], k[4])
                DrawLine(p.x, p.y, p.z, ez.x, ez.y, ez.z, k[1], k[2], k[3], k[4])
            end
        end
    end
end

--- Every frame while there are corners to draw (an outline alone needs no thread).
local function loop()
    while next(corners) do
        local gone = false
        for ent, c in pairs(corners) do
            if DoesEntityExist(ent) then drawCorners(ent, c) else gone = true end
        end
        if gone then refresh() end
        Wait(0)
    end
    running = false
end

local function sameSet(a, b)
    a, b = a or {}, b or {}
    for ent in pairs(a) do if not b[ent] then return false end end
    for ent in pairs(b) do if not a[ent] then return false end end
    return true
end

local function same(a, b)
    if a == b then return true end
    if not a or not b then return false end
    if a.hover ~= b.hover then return false end
    return sameSet(a.selected, b.selected) and sameSet(a.lit, b.lit)
end

--- What `owner` highlights now: { hover, selected, lit = { ent, ... } } (`selected` one entity or a list), or nil.
---@param owner string
---@param spec table|nil
function Highlight.set(owner, spec)
    local o = nil
    if type(spec) == 'table' then
        local function ent(v) return type(v) == 'number' and v ~= 0 and DoesEntityExist(v) and v or nil end
        local function setOf(list)
            local out = nil
            for _, e in ipairs(list) do
                if ent(e) then out = out or {} out[e] = true end
            end
            return out
        end
        local sel = spec.selected
        o = { hover = ent(spec.hover), selected = setOf(type(sel) == 'table' and sel or { sel }),
              lit = setOf(type(spec.lit) == 'table' and spec.lit or {}) }
        if not (o.hover or o.selected or o.lit) then o = nil end
    end
    if same(owners[owner], o) then return end
    owners[owner] = o
    refresh()
    if next(corners) and not running then
        running = true
        CreateThread(loop)
    end
end

--- Does this build put outlines on objects? (The furnisher's chevron stands in where it does not.)
function Highlight.outlines() return hasOutline() end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    owners = {}
    for ent in pairs(outlined) do
        if DoesEntityExist(ent) then pcall(SetEntityDrawOutline, ent, false) end
    end
    outlined, corners = {}, {}
end)
