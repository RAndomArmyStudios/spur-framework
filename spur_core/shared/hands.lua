-- ============================================
-- THE HANDS — what a block is, on both sides
-- ============================================
--
-- A resource can say the player's hands may not be used for now, with the words the player is shown:
--   everything (tied up, a cutscene): the hands are emptied at once, and FreeHands answers false while it lasts;
--   weapons only (`only = 'weapons'`: a hospital, a police station): a weapon is put away, and none can be drawn.
-- client/hands.lua holds a game's own blocks, server/hands.lua the server's (sent to that player's game too).

Hands = {}

--- A block as kept: { label, only }, or nil and why.
---@param opts table|nil  { label?, only? = 'weapons' }
---@return table|nil block
---@return string|nil why
function Hands.readBlock(opts)
    if opts ~= nil and type(opts) ~= 'table' then return nil, 'opts is a table: { label?, only? }' end
    opts = opts or {}
    if opts.only ~= nil and opts.only ~= 'weapons' then return nil, "only is 'weapons', or nothing for everything" end
    if opts.label ~= nil and (type(opts.label) ~= 'string' or opts.label == '') then
        return nil, 'label is the words the player is shown'
    end
    return { label = opts.label or (opts.only and 'You cannot use a weapon here' or 'Your hands are busy'), only = opts.only }
end

--- Does this block stop `what`: 'weapon' (drawing one: every block does), or nil (anything in the hands: only a
--- block of everything)?
---@param block table
---@param what string|nil
---@return boolean
function Hands.covers(block, what)
    return what == 'weapon' or block.only == nil
end
