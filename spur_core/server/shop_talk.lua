-- ============================================
-- Shop talk — what a shopper says at the counter, and the keeper's answer
-- ============================================
--
-- A /me bubble above the shopper that everyone
-- nearby sees (Bubbles.show, server/bubbles.lua), then the shopkeeper's answer above the shopkeeper:
--
--   opening the shop        "What do you got?"                  keeper: "Welcome in."
--   into the basket         "I'll take x3 Water"                keeper: "Coming right up."
--   a new amount of it      "Actually, I want x5 Water instead" keeper: "No problem, changed."
--   out of the basket       "I changed my mind on x3 Water"     keeper: "No worries."
--   paying                  "Got it, thanks"                    keeper: "Thanks, come again!"
--   closing, bought nothing "Nevermind, I'll shop elsewhere"    keeper: "Suit yourself."
--
-- The basket's + and - go one unit at a time, so its changes are GATHERED until the basket has been
-- left alone for Config.ShopTalk.batchSeconds (1; every change starts the wait again), then each item
-- is said once — x1, x1, x1 is one "I'll take x3". An item already in the basket says its NEW AMOUNT ("Actually,
-- I want x5 instead"); one taken out altogether says how many it had. Up
-- and back down to where it was says nothing. Paying says what is still gathered first, so the order
-- reads right.
--
-- The lines are Config.ShopTalk's lists (config.lua §9), {n} the quantity and {item} the item's name.
-- Only a shop with a keeper standing near the shopper answers (a prop shop's counter is silent).
-- Nothing is said by a player who is down or in the character creator, and nothing when the shop is
-- shut by a death, a logout, a disconnect, a restart or walking away: only the player's own close says
-- goodbye. Called from server/shops.lua (the basket, the till, the session's end) and
-- server/events_misc.lua (Shops.openFor, the closeShop event).

local KEEPER_NEAR = 10.0       -- metres: a keeper further from the shopper than this does not answer
local REOPEN_QUIET_MS = 15000  -- the same shop opened again this soon: no second hello
local LEAVE_SETTLE_MS = 750    -- the goodbye waits this long, then asks again whether they are down
local BROKE_QUIET_MS = 8000    -- a refused Buy pressed again this soon: no second round of it

-- [source] = { shopId, bought, quiet, pending = { [itemKey] = { from, to } }, order = { itemKey... }, window }
-- One per open shop session: made by Shops.talkOpened, forgotten by Shops.talkEnded.
local talks = {}
-- [source] = { shopId, at }: the last shop each player opened, and when (REOPEN_QUIET_MS).
local lastOpen = {}

local function cfg()
    return type(Config.ShopTalk) == 'table' and Config.ShopTalk or {}
end

local function enabled()
    return cfg().enabled ~= false
end

--- A line from one of Config.ShopTalk's lists, at random, or nil when the list is empty or missing.
---@param key string
---@return string|nil
local function pick(key)
    local list = cfg()[key]
    if type(list) ~= 'table' or #list == 0 then return nil end
    local line = list[math.random(#list)]
    return type(line) == 'string' and line or nil
end

--- A line's {words} filled in from `vals` ({ n, item, total, items }); one it does not have is left as
--- it is. A function, not a replacement string: a name with a % in it would be read as a capture by gsub.
local function fill(line, vals)
    if not vals then return line end
    return (line:gsub('{(%a+)}', function(k)
        local v = vals[k]
        if v ~= nil then return tostring(v) end
    end))
end

--- An item's name as a player reads it.
local function itemName(itemKey)
    local def = Config.Items[itemKey]
    return (def and def.name) or tostring(itemKey)
end

--- A whole number with its thousands marked: 1170 -> "1,170".
local function thousands(n)
    local s = tostring(math.floor(math.abs(tonumber(n) or 0)))
    return (s:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', ''))
end

--- A sale's {total} and {items}, from the till's receipt (Shops.purchase: the delivered lines and what
--- they came to). {total} is in what the shop takes — "$1,170", or "12 Gold Bar" at a shop that prices in
--- an item. {items} names the first two things bought and counts the rest: "x10 Burger and x1 Phone",
--- "x2 Water, x1 Burger and 3 more".
local function paidVals(shopId, receipt)
    receipt = type(receipt) == 'table' and receipt or {}
    local def = Shops.getDef(shopId)
    local currency = def and type(def.settings) == 'table' and def.settings.currency or 'cash'
    local total = tonumber(receipt.total) or 0
    local totalText = currency == 'cash' and ('$' .. thousands(total))
        or (thousands(total) .. ' ' .. itemName(currency))

    local count, order = {}, {}
    for _, l in ipairs(type(receipt.items) == 'table' and receipt.items or {}) do
        local k = l.itemKey
        if type(k) == 'string' then
            if not count[k] then count[k] = 0; order[#order + 1] = k end
            count[k] = count[k] + (tonumber(l.amount) or 1)
        end
    end
    local function one(i) return ('x%s %s'):format(thousands(count[order[i]]), itemName(order[i])) end
    local itemsText = #order == 0 and 'everything'
        or #order == 1 and one(1)
        or #order == 2 and (one(1) .. ' and ' .. one(2))
        or ('%s, %s and %d more'):format(one(1), one(2), #order - 2)
    return { total = totalText, items = itemsText }
end

--- Up to talking: loaded, not down, not in the character creator. Down is the server's word for it
--- (MarkPlayerDead) OR a ped at the game's dying health: the death report waits for the server to see the
--- ped fall before marking it (server/events_misc.lua, playerDied), and the shop's close can arrive in
--- that wait.
local function canTalk(source)
    local p = Players[source]
    if not p or p.isDead == true or p._inCreator then return false end
    local ped = GetPlayerPed(source)
    return ped ~= 0 and GetEntityHealth(ped) > 100
end

--- The shop's keeper, if it has one standing near this shopper: its network id, or nil.
local function keeperNear(source, shopId)
    local netId = Shops.keeperOf(shopId)
    if not netId then return nil end
    local ent = NetworkGetEntityFromNetworkId(netId)
    local ped = GetPlayerPed(source)
    if not ent or ent == 0 or not DoesEntityExist(ent) or ped == 0 then return nil end
    if #(GetEntityCoords(ent) - GetEntityCoords(ped)) > KEEPER_NEAR then return nil end
    return netId
end

--- The line on the shopper's own shop screen as well: the screen covers the world
--- and the bubbles in it, so its header shows the visit's lines (html/js/shop-talk.js). `who` is 'me'
--- or 'keeper'. Cleaned as Bubbles.show cleans it, so the two say the same words. `kind` marks a line the
--- screen colours: 'sale' (it went through) or 'refused' (not enough money).
local function toScreen(source, who, line, kind)
    local text = BubbleText.clean(line, math.max((Config.Bubbles or {}).maxLength or 120, 120))
    if text ~= '' then TriggerClientEvent('spur_core:client:shopTalk', source, who, text, kind) end
end

--- The shopper says `line` (nothing for nil).
local function say(source, line, kind)
    if not line then return end
    Bubbles.show({ source = source }, line)
    toScreen(source, 'me', line, kind)
end

--- The keeper answers with a line from list `key` (its {words} from `vals`), after Config.ShopTalk.keeperDelay.
local function keeperSays(source, shopId, key, vals, kind)
    local netId = keeperNear(source, shopId)
    local line = netId and pick(key)
    if not line then return end
    line = fill(line, vals)
    local ms = math.floor((tonumber(cfg().keeperDelay) or 1.2) * 1000)
    SetTimeout(math.max(0, ms), function()
        Bubbles.show({ netId = netId }, line)
        toScreen(source, 'keeper', line, kind)
    end)
end

--- Is shop talk on? For the shop screen, which shows its capsule only then (Shops.buildShopPayload).
---@return boolean
function Shops.talkEnabled()
    return enabled()
end

--- Say what the window gathered: one line per item whose count moved, then one answer from the keeper
--- (not when `paying`: the keeper's thanks follows, and one answer is enough).
---@param source number
---@param t table  talks[source]
---@param paying boolean|nil
local function flush(source, t, paying)
    t.window = nil
    local order, pending = t.order, t.pending
    t.order, t.pending = {}, {}
    if not canTalk(source) then return end

    local added, changed, removed = false, false, false
    for _, key in ipairs(order) do
        local p = pending[key]
        local line, n
        if p.to == p.from then
            line = nil                                          -- up and back down: nothing happened
        elseif p.from == 0 then
            line, n, added = pick('add'), p.to, true            -- into the basket: "I'll take x3 Water"
        elseif p.to == 0 then
            line, n, removed = pick('remove'), p.from, true     -- out altogether: "I changed my mind on x3 Water"
        else
            line, n, changed = pick('change'), p.to, true       -- a new amount: "Actually, I want x5 Water instead"
        end
        if line then say(source, fill(line, { n = n, item = itemName(key) })) end
    end
    if paying then
        return
    elseif added then
        keeperSays(source, t.shopId, 'keeperAdd')
    elseif changed then
        keeperSays(source, t.shopId, 'keeperChange')
    elseif removed then
        keeperSays(source, t.shopId, 'keeperRemove')
    end
end

--- A player has opened a shop (Shops.openFor): they say hello, and the keeper answers.
---@param source number
---@param shopId number
function Shops.talkOpened(source, shopId)
    local t = { shopId = shopId, bought = false, pending = {}, order = {} }
    talks[source] = t
    if not enabled() or not canTalk(source) then return end
    -- Open, shut, open again: one hello (and one goodbye), not one a press.
    local now, last = GetGameTimer(), lastOpen[source]
    lastOpen[source] = { shopId = shopId, at = now }
    if last and last.shopId == shopId and now - last.at < REOPEN_QUIET_MS then
        t.quiet = true
        return
    end
    say(source, pick('open'))
    keeperSays(source, shopId, 'keeperOpen')
end

--- The basket's count of one item went from `before` to `after` (Shops.addToBasket, Shops.setLine).
--- Gathered, and said once the basket has been left alone for batchSeconds.
---@param source number
---@param itemKey string
---@param before number
---@param after number
function Shops.talkBasket(source, itemKey, before, after)
    local t = talks[source]
    if not t or before == after or not enabled() then return end
    local p = t.pending[itemKey]
    if p then
        p.to = after
    else
        t.pending[itemKey] = { from = before, to = after }
        t.order[#t.order + 1] = itemKey
    end
    -- From the last change, not the first: every change starts the wait again; the timers it replaces find another token and do nothing.
    local token = {}
    t.window = token
    local ms = math.floor((tonumber(cfg().batchSeconds) or 1) * 1000)
    SetTimeout(math.max(0, ms), function()
        -- Still the latest change of this visit: no click since, not paid for (which says it early),
        -- not a closed shop.
        local now = talks[source]
        if now and now.window == token then flush(source, now) end
    end)
end

--- The player has paid (Shops.purchase): what is still gathered first, then thanks, and the keeper's.
---@param source number
function Shops.talkPaid(source, receipt)
    local t = talks[source]
    if not t then return end
    t.bought = true
    if not enabled() then return end
    if t.window then flush(source, t, true) end
    if not canTalk(source) then return end
    -- A sale, said as one: the lines name what was paid and what for.
    local vals = paidVals(t.shopId, receipt)
    local line = pick('paid')
    if line then say(source, fill(line, vals), 'sale') end
    keeperSays(source, t.shopId, 'keeperPaid', vals, 'sale')
end

--- The till turned them down for want of money (Shops.purchase): they fumble, and the keeper lets them
--- have it.
--- Once in BROKE_QUIET_MS, however often Buy is pressed.
---@param source number
function Shops.talkBroke(source)
    local t = talks[source]
    if not t or not enabled() then return end
    local now = GetGameTimer()
    if t.brokeAt and now - t.brokeAt < BROKE_QUIET_MS then return end
    t.brokeAt = now
    if t.window then flush(source, t, true) end
    if not canTalk(source) then return end
    say(source, pick('broke'), 'refused')
    keeperSays(source, t.shopId, 'keeperBroke', nil, 'refused')
end

--- The player closed the shop themselves (the closeShop event), before Shops.endSession forgets the
--- visit. Bought nothing: a goodbye. What is still gathered is not said — it all goes back on the shelf.
---@param source number
function Shops.talkLeft(source)
    local t = talks[source]
    if not t or t.bought or t.quiet or not enabled() then return end
    local shopId = t.shopId
    -- A dying player's screen closes on the death (client/inventory.lua), and the server may not have
    -- seen the ped fall yet: asked again once it has had a moment.
    SetTimeout(LEAVE_SETTLE_MS, function()
        if not canTalk(source) then return end
        say(source, pick('leave'))
        keeperSays(source, shopId, 'keeperLeave')
    end)
end

--- The visit is over, however it ended (Shops.endSession): its gathered lines are dropped.
---@param source number
function Shops.talkEnded(source)
    talks[source] = nil
end

AddEventHandler('playerDropped', function()
    talks[source] = nil
    lastOpen[source] = nil
end)
