-- ============================================
-- Prices — what things cost, for working out what someone is worth
-- ============================================
--
-- AN ITEM costs what the shops ask: every shop that sells it, each counted once, averaged.
-- A VEHICLE costs what the resources selling cars ask (SetVehiclePrices), averaged the same way.
-- A PROPERTY costs its listed price.
--
-- Free is not a price (a shop handing something out says nothing about its worth), nor is a price in
-- something other than dollars (a shop whose settings.currency is not cash). Nobody selling it means
-- no price: the caller says so, it does not guess.

Prices = {}

-- [resource] = { prices = { [model] = price } }. Goes when the resource stops: it is no longer selling them.
local sellers = {}
local sellerReg = Registry.new('vehiclePrices', { label = 'vehicle price list', store = sellers })

--- What every shop asks for what it sells, averaged. A fresh table each call. Waits (a stocked shop's prices
--- may need reading).
---@return table<string, { price: number, shops: number }>
function Prices.items()
    -- Collected first: reading a shelf's prices waits, and the shops can change meanwhile.
    local shops = {}
    for _, def in pairs(Shops.cache) do
        if ((def.settings and def.settings.currency) or 'cash') == 'cash' then shops[#shops + 1] = def end
    end

    local sums = {}
    local function add(item, price)
        price = tonumber(price)
        if not price or price <= 0 then return end
        local s = sums[item]
        if not s then s = { total = 0, shops = 0 }; sums[item] = s end
        s.total, s.shops = s.total + price, s.shops + 1
    end
    for _, def in ipairs(shops) do
        if def.mode == 'stocked' then
            if def.containerId then
                Shops.loadPrices(def.containerId)
                for item, p in pairs(Shops.priceCache[def.containerId] or {}) do
                    if p.forSale then add(item, p.price) end
                end
            end
        else
            for item, price in pairs(def.catalog or {}) do add(item, price) end
        end
    end

    local out = {}
    for item, s in pairs(sums) do
        out[item] = { price = math.floor(s.total / s.shops + 0.5), shops = s.shops }
    end
    return out
end

--- What the sellers ask for a car model, averaged, and how many sell it. nil when none does.
---@param model string
---@return number|nil price
---@return number|nil sellers
function Prices.vehicle(model)
    if type(model) ~= 'string' then return nil end
    model = model:lower()
    local total, count = 0, 0
    for _, seller in pairs(sellers) do
        local price = seller.prices[model]
        if price then total, count = total + price, count + 1 end
    end
    if count == 0 then return nil end
    return math.floor(total / count + 0.5), count
end

--- A property's listed price, or nil when it has none.
---@param rec table  Properties.get's record
---@return number|nil
function Prices.property(rec)
    local price = math.floor(tonumber(rec and rec.effective and rec.effective.price) or 0)
    if price <= 0 then return nil end
    return price
end

--- What your resource charges for vehicles: { [model] = price }, whole dollars. Declared again, it replaces your list;
--- it goes when your resource stops. What the /whip Banks page values an owned car at.
exports('SetVehiclePrices', function(prices)
    local owner = Registry.caller()
    if type(prices) ~= 'table' then
        return false, 'prices must map a vehicle model to its price, e.g. { wagon05x = 450 }'
    end
    local clean = {}
    for model, price in pairs(prices) do
        price = tonumber(price)
        if type(model) ~= 'string' or not price or price ~= price or price <= 0 or price == math.huge then
            return false, ('invalid price for %s'):format(tostring(model))
        end
        clean[model:lower()] = math.floor(price)
    end
    return sellerReg:add(owner, owner, { prices = clean })
end)
