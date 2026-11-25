-- spur_gunny: LOOKUPS into the items (items/*.lua), on both sides
--
-- RedM (spur_gunny, 24 Nov 2026): rewritten for RDR2's weapons and cartridges. GetWeapon and GetAmmo run on every
-- draw, shot and reload: table indexes, never a scan.

-- ============================================
-- HASHES
-- ============================================

--- A hash as one unsigned 32-bit number, however the game handed it over (a native can answer it signed).
---@param h number|nil
---@return integer
function Config.U32(h)
    return (math.tointeger(tonumber(h) or 0) or 0) & 0xFFFFFFFF
end

--- The game's hash of a name (WEAPON_..., AMMO_..., COMPONENT_...), unsigned.
---@param name string
---@return integer
function Config.Hash(name)
    return Config.U32(GetHashKey(name))
end

-- ============================================
-- WEAPONS
-- ============================================

function Config.GetWeapon(itemName)
    return Config.Weapons[itemName]
end

--- Is this entry a gun: fired, loaded with loose cartridges, reloaded?
---@param weapon table|nil  a Config.Weapons entry
function Config.IsFirearm(weapon)
    return type(weapon) == 'table' and weapon.kind == 'gun'
end

--- Is this entry a bow: its arrows are items carried, each one shot taken from the pockets?
function Config.IsBow(weapon)
    return type(weapon) == 'table' and weapon.kind == 'bow'
end

--- Is this entry swung (no rounds, no reload, no parts)?
function Config.IsMelee(weapon)
    return type(weapon) == 'table' and weapon.kind == 'melee'
end

--- Is this entry a throwable (a stack, and the stack is what the hand holds)?
function Config.IsThrowable(weapon)
    return type(weapon) == 'table' and weapon.kind == 'throwable'
end

--- What kind of weapon an entry is, as the exports and events name it: 'gun', 'bow', 'melee' or 'throwable'.
---@param weapon table
---@return string
function Config.KindOf(weapon)
    return type(weapon) == 'table' and weapon.kind or 'melee'
end

-- ============================================
-- CARTRIDGES
-- ============================================

function Config.GetAmmo(itemName)
    return Config.Ammo[itemName]
end

--- The kinds a gun or bow takes, in the order one with none loaded picks from. Empty for anything else.
---@param weaponName string
---@return string[]
function Config.AmmoKindsFor(weaponName)
    local w = Config.Weapons[weaponName]
    local g = w and w.group and Config.AmmoGroups[w.group]
    return g and g.kinds or {}
end

--- Does this cartridge item go in this gun (or this arrow on this bow)?
function Config.AmmoFits(weaponName, ammoName)
    local w, a = Config.Weapons[weaponName], Config.Ammo[ammoName]
    return w ~= nil and a ~= nil and w.group ~= nil and a.group == w.group
end

--- The kind a new gun is set for: its group's first.
function Config.DefaultKind(weaponName)
    return Config.AmmoKindsFor(weaponName)[1]
end

--- The label of a cartridge item, or its name.
function Config.AmmoLabel(ammoName)
    local a = Config.Ammo[ammoName]
    return a and a.label or tostring(ammoName)
end

--- A gun's group label ('Revolver'), for its card.
function Config.GroupLabel(weaponName)
    local w = Config.Weapons[weaponName]
    local g = w and w.group and Config.AmmoGroups[w.group]
    return g and g.label or nil
end

-- ============================================
-- THE GUNSMITH'S PARTS
-- ============================================

function Config.GetAttachment(itemName)
    return Config.Attachments[itemName]
end

--- The RDR2 component name for a gun's slot (category) and tier, or nil when it takes none.
function Config.GetWeaponAttachmentComponent(weaponName, category, tier)
    local slots = Config.WeaponAttachments[weaponName]
    local kinds = slots and slots[category]
    return kinds and kinds[tier]
end

--- The slots this gun has.
function Config.GetWeaponAttachmentCategories(weaponName)
    local categories = {}
    for category in pairs(Config.WeaponAttachments[weaponName] or {}) do categories[#categories + 1] = category end
    table.sort(categories)
    return categories
end

-- ============================================
-- WHAT EVERY ITEM MUST HAVE
-- ============================================
--
-- Checked as gunny starts, on both sides: an entry the code could not use is left out, and said. So the code reads
-- these fields without a fallback.

local KINDS = { gun = true, bow = true, melee = true, throwable = true }

--- Why this cartridge item cannot be used as written, or nil.
---@param a table  a Config.Ammo entry
---@return string|nil
function Config.AmmoProblem(a)
    if type(a) ~= 'table' then return 'it is not a table' end
    if type(a.type) ~= 'string' or not a.type:match('^AMMO_') then return 'it needs type, the game\'s AMMO_ name' end
    if not Config.AmmoGroups[a.group] then return ('its group %s is not in Config.AmmoGroups'):format(tostring(a.group)) end
    return nil
end

--- Why this weapon cannot be used as written, or nil. Gives it its hash.
---@param w table  a Config.Weapons entry
---@return string|nil
function Config.WeaponProblem(w)
    if type(w) ~= 'table' then return 'it is not a table' end
    if type(w.weapon) ~= 'string' or not w.weapon:match('^WEAPON_') then return 'it needs weapon, the game\'s WEAPON_ name' end
    if not KINDS[w.kind] then return 'its kind is gun, bow, melee or throwable' end
    w.hash = Config.Hash(w.weapon)
    if w.kind == 'gun' or w.kind == 'bow' then
        if not Config.AmmoGroups[w.group] then return ('its group %s is not in Config.AmmoGroups'):format(tostring(w.group)) end
    end
    if w.kind == 'gun' then
        local capacity = tonumber(w.capacity)
        if not capacity or capacity < 1 then return 'a gun needs capacity (the cartridges it holds)' end
    end
    return nil
end

for itemName, a in pairs(Config.Ammo) do
    local why = Config.AmmoProblem(a)
    if why then
        Whip.startProblem('cartridges %s left out: %s', itemName, why)
        Config.Ammo[itemName] = nil
    else
        a.typeHash = Config.Hash(a.type)
    end
end
-- A group's kinds are items that exist.
for _, g in pairs(Config.AmmoGroups) do
    for i = #g.kinds, 1, -1 do
        if not Config.Ammo[g.kinds[i]] then table.remove(g.kinds, i) end
    end
end
for itemName, w in pairs(Config.Weapons) do
    local why = Config.WeaponProblem(w)
    if why then
        Whip.startProblem('weapon %s left out: %s', itemName, why)
        Config.Weapons[itemName] = nil
    end
end

-- ============================================
-- NAME LISTS (sorted, so they read the same every time)
-- ============================================

local function sortedKeys(t)
    local names = {}
    for itemName in pairs(t or {}) do names[#names + 1] = itemName end
    table.sort(names)
    return names
end

function Config.GetAllWeaponNames() return sortedKeys(Config.Weapons) end
function Config.GetAllAmmoNames() return sortedKeys(Config.Ammo) end
function Config.GetAllAttachmentNames() return sortedKeys(Config.Attachments) end

-- ============================================
-- ITEM SETTINGS: the cartridges a gun holds
-- ============================================
--
-- A setting of the gun item itself (server/items.lua declares it), changed per item on /spur's Items page. spur_core
-- keeps the value in force on both sides; Config.FollowItemSettings writes it INTO Config.Weapons (`capacity`), so
-- everything that reads it sees the admin's value. RedM (spur_gunny, 24 Nov 2026): whip_gunny's reload time and
-- magazine sizes are gone (the game plays its own reload; there are no magazines).

local itemDefaults = {}   -- [item] = { [field] = number }

--- Keep an item's own values as its settings' defaults (a weapon pack's item as it registers, shared/packs.lua).
---@param itemName string
function Config.NoteItemDefaults(itemName)
    local gun = Config.Weapons[itemName]
    if Config.IsFirearm(gun) then
        itemDefaults[itemName] = { capacity = tonumber(gun.capacity) }
    else
        itemDefaults[itemName] = nil
    end
end

for itemName in pairs(Config.Weapons) do Config.NoteItemDefaults(itemName) end

--- The item file's value of one of an item's settings: its default on the Items page. nil when it has no such setting.
---@param itemName string
---@param field string  'capacity'
---@return number|nil
function Config.ItemSettingDefault(itemName, field)
    local d = itemDefaults[itemName]
    return d and d[field]
end

--- Follow spur_core's value of every item's settings: now, and whenever an admin changes one. Run from Whip.register
--- on both sides, once spur_core is ready; on the server AFTER the items are registered.
---@param onChange function|nil  fn(itemName, field, value) after a value in force changes here
---@param only string|nil  just this item's (a pack's, as it registers)
function Config.FollowItemSettings(onChange, only)
    for itemName, fields in pairs(itemDefaults) do
        local t = Config.Weapons[itemName]
        if t and (only == nil or only == itemName) then
            for field, default in pairs(fields) do
                local function put(value)
                    if value == nil then value = default end
                    if t[field] == value then return end
                    t[field] = value
                    if onChange then onChange(itemName, field, value) end
                end
                exports.spur_core:OnItemSettingChanged(itemName, field, put)
                put(exports.spur_core:GetItemSetting(itemName, field))
            end
        end
    end
end

-- A player's game follows them as spur_core is ready, and again after it restarts. (The server follows them at the
-- end of its own registration, server/items.lua.)
if not IsDuplicityVersion() then
    Whip.register(function() Config.FollowItemSettings() end)
end
