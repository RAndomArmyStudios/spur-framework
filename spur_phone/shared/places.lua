-- RedM (spur_phone, 24 Nov 2026): new file. Where the notebook's errands are done, on both sides.
--
--   telegraph   sending a telegram          (Config.TelegraphOffices)
--   telephone   placing a telephone call    (Config.Telephones)
--   bank        moving money                (Config.BankSpots)
--
-- The server decides (Places.check, from the player's ped where the server sees it). The client only works out the
-- same answer for the page's buttons and hints (client/main.lua), so nothing is polled from the server.

Places = {}

local LISTS = { telegraph = 'TelegraphOffices', telephone = 'Telephones', bank = 'BankSpots' }

-- What a refused errand says. The page shows the same words on its buttons.
Places.NEED = {
    telegraph = 'Telegrams are sent from a telegraph office. Your telegram is kept until you get there.',
    telephone = "Calls are placed from a telephone. A big town's station has one at the telegraph window.",
    bank      = 'Money is moved at a bank counter. Your passbook still shows your balances anywhere.',
}

--- Places are checked at all (Config.PlaceChecks; false = everything anywhere).
function Places.on()
    return Config.PlaceChecks ~= false
end

local function list(kind)
    local l = LISTS[kind] and Config[LISTS[kind]]
    return type(l) == 'table' and l or {}
end

local function xyz(v)
    if type(v) ~= 'vector3' and type(v) ~= 'vector4' and type(v) ~= 'table' then return nil end
    local x, y, z = tonumber(v.x), tonumber(v.y), tonumber(v.z)
    if not x or not y or not z then return nil end
    return x, y, z
end

--- The nearest place of this kind to `coords`, and how far it is (metres), or nil.
---@param kind string  'telegraph' | 'telephone' | 'bank'
function Places.nearest(kind, coords)
    local px, py, pz = xyz(coords)
    if not px then return nil end
    local best, bestD
    for _, p in ipairs(list(kind)) do
        local x, y, z = xyz(type(p) == 'table' and p.coords)
        if x then
            local d = math.sqrt((x - px) ^ 2 + (y - py) ^ 2 + (z - pz) ^ 2)
            if not bestD or d < bestD then best, bestD = p, d end
        end
    end
    return best, bestD
end

--- The place of this kind `coords` stands at (inside its radius), or nil. With Config.PlaceChecks off, always one.
function Places.at(kind, coords)
    if not Places.on() then return { label = 'anywhere', anywhere = true } end
    local p, d = Places.nearest(kind, coords)
    if p and d <= (tonumber(p.radius) or 4.0) then return p end
    return nil
end

if IsDuplicityVersion() then
    --- Server: may `src` do this errand where they stand? The place, or nil and what to tell them.
    function Places.check(src, kind)
        if not Places.on() then return { label = 'anywhere', anywhere = true } end
        local ped = GetPlayerPed(src)
        if not ped or ped == 0 then return nil, Places.NEED[kind] end
        local p = Places.at(kind, GetEntityCoords(ped))
        if p then return p end
        return nil, Places.NEED[kind]
    end
end
-- The client's side (what the page shows: client/main.lua, placeStatus) uses Places.nearest and Places.at.
