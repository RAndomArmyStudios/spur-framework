-- ============================================
-- Systems — what an editor's Test hands out, taken back
-- ============================================
--
-- Tests take the items back when they restart or end, as the Director's tests do. A Test's Give
-- Item, Sell and Drop Item hand out REAL items,
-- stamped with the Test: metadata.systest = its tag, a new one at every start, so F5 (a restart) is an
-- end like any other. Money still never moves in a Test.
--
--   * Its END takes every stamped stack back from the tester and removes every stamped pile on the
--     ground: stopped, F5, a new Test, a fault, 30 minutes, losing systems.build (main.lua's onStop).
--   * A tester who logged out or left, or a restart under a Test, leaves them in pockets: taken at that
--     character's next load (no Test survives a relog), and the ground's piles at the next start.
--   * WHILE IT RUNS its items stay where its end finds them: only the tester's pockets (stores.lua's
--     stamp vetoes, the gate the Director's run stamps use). Not a stash, a boot, a bag, a shop or
--     another player. Once over, only pockets, where the next load takes them.

SystemsTestItems = {}
local T = SystemsTestItems

local REASON = 'systems test (taken back: the test ended)'
local handed = {}   -- [tag] = { [itemKey] = true }: what a Test handed out, so its end knows what to look for

--- The metadata a Test's item carries, and a note of what it handed out. Cards call this in a Test.
---@param tag string  the Test's tag (ctx:tag())
---@param item string
---@return table metadata
function T.stamp(tag, item)
    local h = handed[tag]
    if not h then h = {}; handed[tag] = h end
    h[item] = true
    return { systest = tag }
end

--- The tester whose Test has this tag, while it is still going (nil once it ended).
local function testerOf(tag)
    for src, t in pairs(Systems.tests or {}) do
        if t.inst and t.inst.tag == tag and t.inst.status == 'on' then return src end
    end
    return nil
end

--- What is inside an item, as whip reads it for weight (inventory.lua's readContents; the Director
--- keeps the same copy).
local function contentsOf(itemKey, metadata)
    if type(metadata) ~= 'table' then return nil end
    local cfg = Panels and Panels.itemConfigs and Panels.itemConfigs[itemKey]
    if not cfg then return nil end
    if cfg.read then
        local ok, projected = pcall(cfg.read, { item = itemKey, metadata = metadata })
        return (ok and type(projected) == 'table') and projected or nil
    end
    local stored = metadata[cfg.storageKey or 'slots']
    return type(stored) == 'table' and stored or nil
end

--- The tester's own things inside a Test's stack (a Test's bag holding their gun): everything not
--- stamped as a Test's, and inside what is, its contents too. Three levels at most, as whip nests.
local function ownInside(itemKey, metadata, out, depth)
    depth = (depth or 0) + 1
    if depth > 3 then return out end
    for _, e in pairs(contentsOf(itemKey, metadata) or {}) do
        if type(e) == 'table' and type(e.item) == 'string' then
            if type(e.metadata) == 'table' and e.metadata.systest ~= nil then
                ownInside(e.item, e.metadata, out, depth)
            else
                out[#out + 1] = e
            end
        end
    end
    return out
end

--- Take every stack stamped `match(stamp)` out of src's pockets, giving them back what of theirs is
--- inside it (their pockets, or the ground at their feet): the items it took, and their names.
local function takeFrom(src, keys, match, reason)
    local n, names = 0, {}
    for key in pairs(keys) do
        for _, f in ipairs(Inventory.findAll(src, key) or {}) do
            local md = f.metadata
            if type(md) == 'table' and md.systest ~= nil and match(md.systest) then
                local own = ownInside(key, md, {})
                if Stores.takeAt(f.addr, f.amount, { reason = reason }) then
                    for _, e in ipairs(own) do
                        Inventory.give(src, e.item, tonumber(e.amount) or 1, e.metadata, reason .. ' (theirs, from inside it)')
                    end
                    n = n + (tonumber(f.amount) or 1)
                    local def = Config.Items and Config.Items[key]
                    names[def and def.name or key] = true
                end
            end
        end
    end
    local list = {}
    for name in pairs(names) do list[#list + 1] = name end
    table.sort(list)
    return n, list
end

--- The ground's piles stamped `match(stamp)`, removed (each removal waits on the database).
local function clearGround(match)
    local ids = {}
    for id, row in pairs(GroundItems and GroundItems.cache or {}) do
        local md = type(row) == 'table' and row.metadata or nil
        if type(md) == 'table' and md.systest ~= nil and match(md.systest) then ids[#ids + 1] = id end
    end
    for _, id in ipairs(ids) do
        if GroundItems.getById(id) then GroundItems.deleteItem(id) end
    end
    return #ids
end

--- A Test ended: what it handed out goes back. In a thread of its own (taking and clearing wait).
---@param tag string
---@param src number|nil  its tester
---@param only table|nil  [itemKey] = true: just these (T.late), leaving the record alone
function T.testEnded(tag, src, only)
    local keys = only or handed[tag] or {}
    if not only then handed[tag] = nil end
    CreateThread(function()
        local is = function(s) return s == tag end
        local p = src and Players[src]
        -- A tester on their way out keeps them until their next load (the logout is saving pockets).
        if p and not p.closing and next(keys) then
            local ok, n, names = pcall(takeFrom, src, keys, is, REASON)
            if not ok then
                print(('^1[spur_core:systems] taking a test\'s items back from %s failed: %s^0'):format(tostring(src), tostring(n)))
            elseif n > 0 then
                NotifyPlayer(src, ('Test: %s taken back'):format(table.concat(names, ', ')), 'info')
            end
        end
        local ok, err = pcall(clearGround, is)
        if not ok then print(('^1[spur_core:systems] clearing a test\'s ground items failed: %s^0'):format(tostring(err))) end
    end)
end

--- A give or a drop that finished after its pulse was over (ctx:call's `late`): if the Test itself is
--- over, its end's take-back ran before this landed (a drop's row waits on the database), so it goes
--- back now. A pulse called off while the Test runs keeps it: the end takes it.
---@param tag string
---@param src number|nil
---@param item string
function T.late(tag, src, item)
    if testerOf(tag) then return end
    T.testEnded(tag, src, { [item] = true })
end

--- WHERE A TEST'S ITEMS MAY GO: its tester's pockets while it runs; once it is over, pockets only
--- (the next load takes them back). Anywhere else is refused.
Stores.stampVetoes.systest = function(kindId, h, _, md)
    local tester = testerOf(md.systest)
    if kindId ~= 'player' then return true end
    if not tester then return false end
    local src = type(h) == 'table' and type(h.player) == 'table' and h.player.source or nil
    return src ~= tester
end

-- A CHARACTER COMING ON holds no Test's items: a Test ends at its tester's logout, so a stamped stack
-- in their pockets is from one that is over (they left mid-test, or spur_core stopped under it).
Character.onLife('loaded', function(e)
    local src = e and e.source
    if not src then return end
    CreateThread(function()
        local keys = {}
        for _, slots in pairs(Inventory.pocketsCopy(src) or {}) do
            for _, d in pairs(type(slots) == 'table' and slots or {}) do
                if type(d) == 'table' and type(d.item) == 'string' and type(d.metadata) == 'table' and d.metadata.systest ~= nil then
                    keys[d.item] = true
                end
            end
        end
        if not next(keys) then return end
        local ok, n, names = pcall(takeFrom, src, keys, function(s) return testerOf(s) ~= src end,
            'systems test (taken back: the test is over)')
        if ok and n > 0 then NotifyPlayer(src, ('%s taken back: a test is over'):format(table.concat(names, ', ')), 'info') end
    end)
end)

-- AT THE START, a Test's piles left on the ground by a stop under it: no Test of this start has made any.
CoreStart.add('clearing Systems tests\' ground items', function()
    local ok, n = pcall(clearGround, function() return true end)
    if ok and n > 0 then print(('[spur_core:systems] removed %d ground item(s) a test left behind'):format(n)) end
end)
