-- ============================================
-- Systems — Registers: things a system makes for the server, for good
-- ============================================
--
-- The fourth power, "make" (a systems admin ticks it, as the others): the system adds its own thing
-- to whip. An ITEM cannot be taken away again once it is in people's pockets, so it stays registered
-- while spur_core runs (switching the system off leaves it; at the next start the system registers
-- it again when it switches on). So each is capped: 10 items a system. Named by the system
-- (C.name: `s_<short id>_<name>`), so no two systems, and no resource, share one.
--
-- An editor's Test registers its item under the Test's own name and tag: it goes when the Test ends,
-- and a Test never hands one out (Give Item's dry run).
--
-- Not yet: a system's own stats (the builder needs its full name shown to read it),
-- shops and jobs (rows the system's delete must take away), zones (zones.lua's register is a local).

local C = SystemCards
local CORE = 'spur_core'
--- At most this many items per system (they are never taken away while spur_core runs).
local MAX_ITEMS = 10

local function define(def)
    def.side = 'server'
    local ok, why = C.define(def)
    if not ok then print('^1[spur_core:systems] card type refused: ' .. tostring(why) .. '^0') end
end

--- How many items carry this system's names already: the switched-on system's (`s_<short>_<name>`,
--- never a "-"), or one tester's (`s_<short>_t<tester>-<name>`). Each is held to MAX_ITEMS on its own,
--- so a Test's items never count against the live system's.
local function itemsOf(short, tester)
    local prefix = tester and ('s_%s_t%s-'):format(short, tostring(tester)) or ('s_%s_'):format(short)
    local n = 0
    for key in pairs(Config.Items) do
        if type(key) == 'string' and key:sub(1, #prefix) == prefix and (tester or not key:find('-', #prefix + 1, true)) then
            n = n + 1
        end
    end
    return n
end

define({
    type = 'make.item', category = 'items', kind = 'trigger', title = 'This System\'s Item', power = 'make',
    api = { 'RegisterItem', 'RegisterUseHandler' },
    desc = 'An item of this system\'s own (a car wash token, a ticket), made for the server when the system is switched on, and kept for good. Usable, this card starts when a player uses one: it is not taken unless the system takes it (Take Item).',
    props = { { key = 'name', kind = 'text', label = 'Name (this system\'s own)', required = true, default = 'token', maxLength = 24 },
              { key = 'label', kind = 'text', label = 'What players see', required = true, default = 'Token', maxLength = 40 },
              { key = 'description', kind = 'text', label = 'Description', maxLength = 120 },
              { key = 'weight', kind = 'number', label = 'Weight (kg)', default = 0.1, min = 0, max = 100 },
              { key = 'stack', kind = 'bool', label = 'Stacks', default = true },
              { key = 'usable', kind = 'bool', label = 'Can be used', default = true } },
    standing = function(api)
        local short = api.meta and api.meta.shortId
        if not short then error('the system has no short id', 0) end
        local tester = api.test and api.tester or nil
        local key = C.name(short, tester, api.props.name)
        if not Config.Items[key] and itemsOf(short, tester) >= MAX_ITEMS then
            error(('this system has %d items already, the most it may'):format(MAX_ITEMS), 0)
        end
        local label = type(api.props.label) == 'string' and api.props.label:match('%S') and api.props.label:sub(1, 40) or 'Item'
        local desc = type(api.props.description) == 'string' and api.props.description:sub(1, 120) or nil
        local usable = api.props.usable ~= false
        local ok, why = Inventory.registerItem(key, {
            name = api.test and ('Test: ' .. label) or label, desc = desc,
            weight = tonumber(api.props.weight) or 0.1, stack = api.props.stack ~= false, usable = usable,
            type = 'item',
        }, CORE, api.test and { tag = api.tag } or nil)
        if not ok then error(tostring(why), 0) end
        if usable then
            -- The use is the system's: it keeps the item (false) and starts this card's pulse. While
            -- the system is off, a use is said to do nothing, rather than nothing at all.
            local function onUse(source)
                if not api.listening() then return false, 'That does nothing right now' end
                if not api.test and api.isTesting(source) then return false, 'You are testing a draft of this system' end
                local pv = Systems.playerValue(source)
                if pv then api.emit('item.used', { player = pv, item = key }) end
                return false
            end
            -- A Test's use goes with its tag, as its item does.
            local uok, uwhy
            if api.test then uok, uwhy = Inventory.registerTaggedUseHandler(key, onUse, api.tag)
            else uok, uwhy = Inventory.registerUseHandler(key, onUse, CORE) end
            if not uok then error(tostring(uwhy), 0) end
        end
    end,
    trigger = { name = 'item.used', match = function(ctx, p)
        -- Only this instance's own card's item (another system's, or the live copy's, is not ours).
        if type(p) ~= 'table' or p.inst ~= ctx:instanceId() or p.node ~= ctx:nodeId() or not p.player then return nil end
        return { player = p.player, item = p.item }, { player = p.player }
    end },
    values = { outputs = { { key = 'player', type = 'player', label = 'Used by' }, { key = 'item', type = 'item', label = 'Item' } } },
})
