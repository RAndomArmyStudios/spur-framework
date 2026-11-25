-- ============================================
-- THE HANDS (client) — FreeHands, and blocking them
-- ============================================
--
-- FreeHands: a resource about to put something in the player's hands (the phone, a tool) asks first, and whatever
-- holds them puts it away: the 'freeHands' moment (RunClientHook), which whip_gunny answers by holstering and
-- whip_fuel by dropping the nozzle.
--
-- Blocks (shared/hands.lua says what one is): this game's own, from BlockHands here, and the server's, sent by
-- server/hands.lua. A new block is told to everyone as spur_core:hands:blocked { label, only }, and one of everything
-- also runs the freeHands moment; spur_core:hands:unblocked {} when none is left. On the one registration rule
-- (shared/registry.lua): keyed by the owner, swept when it stops.

local blocks = {}        -- ['<resource>:<id>'] = { label, only }
local serverBlocks = {}  -- [key] = { label, only }: the server's for this player
local wasBlocked = false

--- The block in force for `what` (Hands.covers), the server's first, or nil.
local function blockFor(what)
    for _, set in ipairs({ serverBlocks, blocks }) do
        for _, b in pairs(set) do
            if Hands.covers(b, what) then return b end
        end
    end
    return nil
end

--- A block began, or became one of everything.
local function began(b)
    wasBlocked = true
    WhipEmit('spur_core:hands:blocked', { label = b.label, only = b.only })
    if b.only == nil then CreateThread(function() RunClientHook('freeHands') end) end
end

--- After any block went: unblocked, once, when none is left.
local function settle()
    local any = next(blocks) ~= nil or next(serverBlocks) ~= nil
    if wasBlocked and not any then WhipEmit('spur_core:hands:unblocked', {}) end
    wasBlocked = any
end

local blockReg = Registry.new('HandsBlock', {
    label    = 'hands block',
    store    = blocks,
    scoped   = true,
    onAdd    = function(_, b, _, old) if not old or old.only ~= b.only then began(b) end end,
    onRemove = function() settle() end,
})

--- Something else needs the hands. Waits (call from a thread). Answers true when they are free after it (no weapon
--- in them), false when one still is, or false and the block's words while the hands are blocked.
---@return boolean free
---@return string|nil why
local function FreeHands()
    RunClientHook('freeHands')
    local b = blockFor(nil)
    if b then return false, b.label end
    return GetSelectedPedWeapon(PlayerPedId()) == `WEAPON_UNARMED`
end
Inventory.freeHands = FreeHands   -- spur_core's own callers (the camera item), never the export
exports('FreeHands', FreeHands)

--- Are the hands blocked for `what` ('weapon', or nil for anything)? Answers true and the block's words, or false.
---@return boolean blocked
---@return string|nil label
local function handsBlocked(what)
    local b = blockFor(what)
    if b then return true, b.label end
    return false
end
Inventory.handsBlocked = handsBlocked   -- give mode (client/inventory.lua)
exports('AreHandsBlocked', handsBlocked)

--- Block this player's hands until UnblockHands(id), or this resource stops. Answers true, or false and why.
---
---     exports.spur_core:BlockHands('hospital', { only = 'weapons', label = 'No weapons in the hospital' })
---@param id string
---@param opts table|nil  { label?, only? = 'weapons' }
exports('BlockHands', function(id, opts)
    local owner = Registry.caller()
    local b, why = Hands.readBlock(opts)
    if not b then return false, why end
    local ok, err = blockReg:add(owner, id, b)
    if not ok then return false, err end
    return true
end)

exports('UnblockHands', function(id)
    local owner = Registry.caller()
    local ok, why = blockReg:remove(owner, id)
    if not ok then return false, why end
    return true
end)

-- The server's blocks for this player, all of them each time one changes (server/hands.lua).
RegisterNetEvent('spur_core:client:handsBlocks', function(list)
    local before = serverBlocks
    serverBlocks = {}
    for key, raw in pairs(type(list) == 'table' and list or {}) do
        local b = Hands.readBlock(raw)
        if b then
            serverBlocks[key] = b
            local old = before[key]
            if not old or old.only ~= b.only then began(b) end
        end
    end
    settle()
end)

-- The server's FreeHands(source).
RegisterNetEvent('spur_core:client:freeHands', function()
    CreateThread(FreeHands)
end)
