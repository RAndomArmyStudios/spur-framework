-- spur_gunny: THE SERVER'S FOUNDATION
--
-- How gunny declares what the client may ask, the shapes every handler shares, and the drawn-weapon record. The
-- items themselves are registered in server/items.lua.
--
-- CALLING SPUR_CORE, on the server: exports.spur_core:X straight inside a handler spur_core runs (it is up then),
-- Whip.core outside one (a console command). Inside a handler too, a call that can wait (AddItem: full pockets drop
-- the item on the ground) and everything after such a wait (an undo: GunnyStillThere, below) go through Whip.core, so
-- a failure answers false and why instead of throwing, and the half-made change can be undone or said lost. (The
-- client's rule is at the top of client/main.lua.)
--
-- RedM (spur_gunny, 24 Nov 2026): whip_core -> spur_core, whip_gunny: -> spur_gunny:. No magazines: the helpers that
-- carried a magazine's record in and out of a gun are gone, and the slot lists are weapons, cartridges and parts.

--- Every declaration, kept to be made again when a weapon pack changes the item lists the schemas name (the bottom of
--- this file).
local declarations = {}

local function declare(fn)
    declarations[#declarations + 1] = fn
    Whip.register(fn)
end

--- Declare a callback by its full name ('spur_gunny:equipWeapon'), the name the client's GunnyCallback asks for.
---
--- Through SecureCallback: spur_core checks the params against the schema, rate-limits, and logs, before the handler
--- runs with (source, player, ...). Through Whip.register, so it is declared once spur_core is ready, and again when
--- a weapon pack changes the item lists (SecureCallback replaces its entry and binds the net handler once).
---@param name string
---@param schema table
---@param handler function
function RegisterGunnyCallback(name, schema, handler)
    if type(schema) ~= 'table' or type(handler) ~= 'function' then
        error(('RegisterGunnyCallback(%s): a schema and a handler are both required'):format(tostring(name)), 2)
    end
    -- A floor for callbacks that declare no rateLimit (a declared one wins), with a burst: a player's own quick
    -- presses (draw, holster, draw again) are not refused.
    if schema.rateLimit == nil then
        schema.rateLimit = 150
        schema.burst     = schema.burst or 8
    end
    declare(function()
        exports.spur_core:SecureCallback(name, schema, handler)
    end)
end

--- Declare a client -> server event by its full name ('spur_gunny:server:shotFired'), the same way.
---@param name string
---@param schema table
---@param handler function
function RegisterGunnyEvent(name, schema, handler)
    if type(schema) ~= 'table' or type(handler) ~= 'function' then
        error(('RegisterGunnyEvent(%s): a schema and a handler are both required'):format(tostring(name)), 2)
    end
    declare(function()
        exports.spur_core:SecureEvent(name, schema, handler)
    end)
end

--- A rollback that fired (an item handed back after a half-failed change) or a lost write: always printed, for the
--- server owner.
---@param fmt string
function GunnyWarn(fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    print(('[GUNNY] WARNING: %s'):format(ok and msg or fmt))
end

--- An undo: give back what a half-done change already took. Through Whip.core, as AddItem may wait (full pockets
--- drop it on the ground) and an answer must come even if spur_core stops meanwhile. Answers whether it landed; when
--- it did not, the item is lost, and that is said.
---@return boolean
function GunnyGiveBack(source, item, amount, metadata, reason)
    local where, why = Whip.core:AddItem(source, item, amount, metadata, reason)
    if where then return true end
    GunnyWarn('%d x %s LOST: %s, and it could not be given back (%s)', amount, item, reason, tostring(why))
    return false
end

--- Read a slot again after a wait (AddItem): what is in it, if it is still `item` with `serial`, or nil (moved,
--- replaced, or spur_core gone meanwhile). The read before an undo, so the undo lands on the thing it took from.
---@param addr table      the slot (GunnyPocket)
---@param item string     the item it held
---@param serial string|nil  the serial it had
---@return table|nil slotData  { item, amount, metadata }
function GunnyStillThere(addr, item, serial)
    local sd = Whip.core:GetItemAt(addr)
    if type(sd) == 'table' and sd.item == item and (sd.metadata or {}).serial == serial then return sd end
    return nil
end

--- [source] = true for each player with Gunny Debug on in /w (server/debug.lua).
GunnyDebugFor = {}

--- A debug line, printed while anyone has Gunny Debug on.
function GunnyDebugPrint(...)
    if next(GunnyDebugFor) then
        print('[GUNNY]', ...)
    end
end

--- The spur_core ADDRESS of one of a player's pocket slots, which its slot calls take (GetItemAt, SetItemMetadata,
--- StoreTake).
---@param source number
---@param pocket string  'player' or 'accessory'
---@param slot number
---@return table addr
function GunnyPocket(source, pocket, slot)
    return { kind = 'player', id = source, sub = pocket or 'player', slot = slot }
end

--- The items a handler's 'slot' param may name. A handler acting on a slot the client names declares
--- { 'weapon', 'slot', { item = GunnyWeaponItems } } and the client sends GunnySlot(slot, pocket): spur_core checks
--- the pocket is the player's, the slot is in range and not empty, and holds one of these, and the handler gets
--- { addr, item, amount, metadata } (a copy).
GunnyWeaponItems     = Config.GetAllWeaponNames()
GunnyAmmoItems       = Config.GetAllAmmoNames()
GunnyAttachmentItems = Config.GetAllAttachmentNames()

-- A weapon pack's item arrived or went (shared/packs.lua): the lists again, in place (the schemas hold these tables),
-- and every declaration made again with them, once for a burst of a pack's items.
local function refill(list, names)
    for i = #list, 1, -1 do list[i] = nil end
    for i, n in ipairs(names) do list[i] = n end
end
local redeclaring = false
GunnyPacks.onChange(function()
    if redeclaring then return end
    redeclaring = true
    SetTimeout(0, function()
        redeclaring = false
        refill(GunnyWeaponItems, Config.GetAllWeaponNames())
        refill(GunnyAmmoItems, Config.GetAllAmmoNames())
        if not Whip.isReady() then return end
        for _, fn in ipairs(declarations) do fn() end
    end)
end)

--- The weapon each player has drawn: [source] = { slot, pocket, weapon, serial, countVersion, count?, taken?,
--- arrowItem? } (server/weapons.lua).
EquippedWeapons = {}

--- The record of a gun just put away, kept LATE_COUNT_MS: a shot fired in the frame the holster read its count is sent
--- just behind the holster, and is still charged to that gun (GunnyDrawnWeapon's `lateToo`, server/shooting.lua).
local justHolstered = {}   -- [source] = { record, at }
local LATE_COUNT_MS = 2000

--- The record put away less than LATE_COUNT_MS ago, or nil.
---@param source number
---@return table|nil record
function GunnyJustHolstered(source)
    local j = justHolstered[source]
    if j and GetGameTimer() - j.at <= LATE_COUNT_MS then return j.record end
    return nil
end

--- The record ends, whichever way it went, and other resources hear it once: spur_gunny:weapon:holstered with
--- `reason` 'holstered' (put away), 'moved' (it left its slot), 'replaced', 'logout' or 'dropped'.
---@param source number
---@param reason string
function GunnyEndDrawn(source, reason)
    local e = EquippedWeapons[source]
    justHolstered[source] = nil   -- before the check: a new draw ends no record, and still forgets the last one
    if not e then return end
    EquippedWeapons[source] = nil
    if reason == 'holstered' then justHolstered[source] = { record = e, at = GetGameTimer() } end
    TriggerEvent('spur_gunny:weapon:holstered', { source = source, item = e.weapon, serial = e.serial,
        slot = e.slot, pocket = e.pocket, reason = reason })
end

AddEventHandler('playerDropped', function()
    GunnyEndDrawn(source, 'dropped')
end)

-- A logout keeps the connection (no playerDropped): cleared here, or the next character on this source inherits it.
AddEventHandler('spur_core:player:logout', function(e)
    GunnyEndDrawn(e.source, 'logout')
end)

math.randomseed(os.time())

--- A new weapon's serial: 12 letters and digits.
function GunnyNewSerial()
    local chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    local parts = {}
    for _ = 1, 12 do
        local idx = math.random(1, #chars)
        parts[#parts + 1] = chars:sub(idx, idx)
    end
    return table.concat(parts)
end

--- RedM (spur_gunny, 24 Nov 2026): the kind of cartridge a gun is loaded with, or set for. The gun's own `kind` if it
--- fits, else its group's first.
---@param weaponName string
---@param meta table|nil
---@return string|nil
function GunnyKindOf(weaponName, meta)
    local kind = type(meta) == 'table' and meta.kind or nil
    if kind and Config.AmmoFits(weaponName, kind) then return kind end
    return Config.DefaultKind(weaponName)
end

--- The first kind this gun or bow takes that the player carries, starting from `prefer`; nil when none.
---@param source number
---@param weaponName string
---@param prefer string|nil
---@return string|nil kind
---@return number have
function GunnyCarriedKind(source, weaponName, prefer)
    if prefer and Config.AmmoFits(weaponName, prefer) then
        local n = exports.spur_core:GetItemCount(source, prefer) or 0
        if n > 0 then return prefer, n end
    end
    for _, kind in ipairs(Config.AmmoKindsFor(weaponName)) do
        local n = exports.spur_core:GetItemCount(source, kind) or 0
        if n > 0 then return kind, n end
    end
    return nil, 0
end
