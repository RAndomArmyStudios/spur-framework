-- ============================================
-- THE HANDS (server) — blocking a player's hands, and FreeHands(source)
-- ============================================
--
-- A server resource blocks a player's hands (jail, an arrest, a mission): the block is kept here, so the server's
-- own checks can ask AreHandsBlocked(source, what) (whip_gunny refuses a draw), and sent to the player's game, which
-- empties the hands and refuses there too (client/hands.lua). Gone at logout or a drop, or when its resource stops:
-- on the one registration rule (shared/registry.lua), keyed by the owner.

local blocks = {}   -- ['<resource>:<source>:<id>'] = { source, label, only }

--- The player's game is sent all of its blocks each time one changes.
local function send(source)
    local list = {}
    for key, b in pairs(blocks) do
        if b.source == source then list[key] = { label = b.label, only = b.only } end
    end
    TriggerClientEvent('spur_core:client:handsBlocks', source, list)
end

local blockReg = Registry.new('HandsBlockServer', {
    label    = 'hands block',
    store    = blocks,
    scoped   = true,
    onAdd    = function(_, b) send(b.source) end,
    onRemove = function(_, b) if Players[b.source] then send(b.source) end end,
})

--- An online player's server id, or nil and why.
local function online(source)
    local charId, src = WhoIs(source)   -- nil and why when there is no such player
    if not charId or not src then return nil, 'No player with that server id is online' end
    return src
end

--- Block a player's hands until UnblockHands(source, id), they log out, or this resource stops. `opts` as the
--- client's: { label?, only? = 'weapons' }. Answers true, or false and why.
---
---     exports.spur_core:BlockHands(source, 'cuffed', { label = 'You are handcuffed' })
exports('BlockHands', function(source, id, opts)
    local owner = Registry.caller()
    local src, why = online(source)
    if not src then return false, why end
    if (type(id) ~= 'string' and type(id) ~= 'number') or id == '' then return false, 'a hands block needs an id' end
    local b
    b, why = Hands.readBlock(opts)
    if not b then return false, why end
    b.source = src
    local ok, err = blockReg:add(owner, src .. ':' .. tostring(id), b)
    if not ok then return false, err end
    return true
end)

exports('UnblockHands', function(source, id)
    local owner = Registry.caller()
    local src = tonumber(source)
    if not src then return false, 'source is a server id' end
    local ok, why = blockReg:remove(owner, src .. ':' .. tostring(id))
    if not ok then return false, why end
    return true
end)

--- Are this player's hands blocked for `what` ('weapon', or nil for anything)? Answers true and the block's words,
--- or false. The server's own blocks only: a block a player's game made for itself is that game's to keep.
exports('AreHandsBlocked', function(source, what)
    local src = tonumber(source)
    for _, b in pairs(blocks) do
        if b.source == src and Hands.covers(b, what) then return true, b.label end
    end
    return false
end)

--- Have a player's game empty their hands now (the freeHands moment: a gun holstered, the nozzle dropped). Answers
--- true once asked, or false and why.
exports('FreeHands', function(source)
    local src, why = online(source)
    if not src then return false, why end
    TriggerClientEvent('spur_core:client:freeHands', src)
    return true
end)

-- At logout (and a drop) the player's blocks go: the next character on this game starts free.
Character.onLife('logout', function(e)
    local src = e and e.source
    if not src then return end
    local mine = {}
    for key, b in pairs(blocks) do
        if b.source == src then mine[#mine + 1] = key end
    end
    for _, key in ipairs(mine) do
        local owner = blockReg:ownerOf(key)
        if owner then blockReg:remove(owner, key:sub(#owner + 2)) end
    end
end)
