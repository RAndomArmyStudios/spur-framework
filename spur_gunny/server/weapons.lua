-- spur_gunny: DRAWING AND PUTTING AWAY (server)
--
-- The server's record of the drawn weapon (EquippedWeapons, server/main.lua): where it was drawn from, and its serial.
-- Everything a drawn weapon does afterwards (shots, throws, the holster) goes by this record, never by a slot the client
-- names.
--
-- RedM (spur_gunny, 24 Nov 2026): no jerry can and no magazines. A gun answers its loaded cartridges and their kind;
-- a bow answers the arrows of its kind the player carries (each one shot is taken from the pockets).

--- The weapon this player has drawn, read fresh, or nil if it is no longer where it was drawn from.
---
--- The inventory stays usable while a weapon is out (dragged, stashed, handed over), so the item in that slot must
--- still be the same item with the same serial: the slot number alone would charge shots to whatever sits there now.
---
--- `lateToo`: with nothing drawn now, the gun put away a moment ago (GunnyJustHolstered, server/main.lua), for a count
--- that was on its way as it went. The third answer says it is that one.
---@param source number
---@param lateToo boolean|nil
---@return table|nil slotData  the drawn weapon, still in place
---@return table|nil equipped  the record, whether or not the weapon is still there
---@return boolean late        the record is the one just put away
function GunnyDrawnWeapon(source, lateToo)
    local equipped, late = EquippedWeapons[source], false
    if not equipped and lateToo then equipped, late = GunnyJustHolstered(source), true end
    if not equipped then return nil, nil, false end
    local sd = exports.spur_core:GetItemAt(GunnyPocket(source, equipped.pocket, equipped.slot))
    if sd and sd.item == equipped.weapon and (sd.metadata or {}).serial == equipped.serial then
        return sd, equipped, late
    end
    return nil, equipped, late
end

--- Tell spur_core what is in the hand: the drawn weapon is the player's held item, so spur_core can act on it.
---@param source number
---@param addr table|nil  the drawn weapon's slot, or nil
local function setHeld(source, addr)
    local ok, why = exports.spur_core:SetHeldItem(source, addr)
    if not ok then GunnyDebugPrint('SetHeldItem refused:', why) end
end

--- The drawn weapon left the slot it was drawn from: put it away on both sides.
---@param source number
function GunnyForceHolster(source)
    GunnyEndDrawn(source, 'moved')
    setHeld(source, nil)
    TriggerClientEvent('spur_gunny:client:forceHolster', source)
end

--- The server changed the drawn gun's rounds itself (an unload, a kind switched): the count's version goes up, and the
--- client is told it with the new count. A count the client sends with an older version was counted before that change
--- and is ignored. Answers the new version, or nil when this is not the drawn gun.
---@param source number
---@param addr table          the gun's slot
---@param serial string|nil   the gun's serial
---@return number|nil countVersion
function GunnyCountChanged(source, addr, serial)
    local e = EquippedWeapons[source]
    if not (e and e.slot == addr.slot and e.pocket == (addr.sub or 'player') and e.serial == serial) then return nil end
    e.countVersion = e.countVersion + 1
    return e.countVersion
end

--- A shot, throw or count for a draw this server has no record of: the hand holds something nothing counts (a
--- forceHolster lost on its way). Put it away there, at most once a second per player.
local noRecordAt = {}
---@param source number
function GunnyNoDrawRecord(source)
    local now = GetGameTimer()
    if noRecordAt[source] and now - noRecordAt[source] < 1000 then return end
    noRecordAt[source] = now
    TriggerClientEvent('spur_gunny:client:forceHolster', source)
end
AddEventHandler('playerDropped', function() noRecordAt[source] = nil end)

-- Any pocket change (spur_core:inventory:changed): the drawn weapon is looked at right then. Gone from its slot
-- (moved, dropped, stashed, handed over), it is put away.
AddEventHandler('spur_core:inventory:changed', function(e)
    local src = type(e) == 'table' and e.source or nil
    if not src or not EquippedWeapons[src] then return end
    local slotData, equipped = GunnyDrawnWeapon(src)
    if not equipped then return end
    if not slotData then
        GunnyDebugPrint('Drawn weapon left its slot - holstering', src)
        GunnyForceHolster(src)
        return
    end
    -- A throwable in hand whose stack changed (more dragged onto it, some split off), or a bow whose arrows changed in
    -- the pockets: the new count, with the throws or shots taken so far (client/throwables.lua). Our own takes note the
    -- count first, so they arrive as no change.
    if equipped.count ~= nil then
        local n
        if equipped.arrowItem then
            n = exports.spur_core:GetItemCount(src, equipped.arrowItem) or 0
        else
            n = tonumber(slotData.amount) or 0
        end
        if n ~= equipped.count then
            equipped.count = n
            TriggerClientEvent('spur_gunny:client:syncThrown', src, n, equipped.taken or 0)
        end
    end
end)

--- The game's ammunition name for a cartridge item, or nil.
local function ammoTypeOf(kind)
    local a = kind and Config.GetAmmo(kind)
    return a and a.type or nil
end

-- Draw: the weapon arrives as spur_core's 'slot' param (this player's own pocket, holding one of gunny's weapons).
-- Answers true and { hash, ammo, kind, ammoType, attachments, serial, countVersion }, or false and why.
RegisterGunnyCallback('spur_gunny:equipWeapon', { params = { { 'weapon', 'slot', { item = GunnyWeaponItems } } } },
function(source, _, weapon)
    local slotData = weapon   -- spur_core's copy of the slot: { addr, item, amount, metadata }

    local weaponConfig = Config.GetWeapon(slotData.item)
    if not weaponConfig then return false, 'Invalid weapon' end

    -- The server's own blocks (spur_core's BlockHands(source, ...)): jail, an arrest. The game checks its own.
    local blocked, why = exports.spur_core:AreHandsBlocked(source, 'weapon')
    if blocked then return false, why end

    local meta = slotData.metadata or {}
    local throwable = Config.IsThrowable(weaponConfig)

    -- A weapon with no serial (given by a script that set no metadata) gets one, once: the serial is how a drawn
    -- weapon is known to be still in its slot. A throwable is a stack, known by its slot and item.
    if not throwable and not meta.serial then
        meta.serial = GunnyNewSerial()
        if not exports.spur_core:SetItemMetadata(weapon.addr, meta) then return false, 'Could not get the weapon ready' end
    end

    -- A gun holding more than it holds now ("Cartridges it holds" lowered on the Items page): trimmed to that size as it
    -- is drawn, and the extra cartridges go back to the pockets. Never below the item file's own size.
    if Config.IsFirearm(weaponConfig) then
        local setting = tonumber(weaponConfig.capacity)
        local builtIn = tonumber(Config.ItemSettingDefault(slotData.item, 'capacity'))
        local cap = setting and math.max(setting, builtIn or setting)
        local held = tonumber(meta.ammo) or 0
        if cap and held > cap then
            meta.ammo = cap
            if exports.spur_core:SetItemMetadata(weapon.addr, meta) then
                local kind = GunnyKindOf(slotData.item, meta)
                local back = kind and Whip.core:AddItem(source, kind, held - cap, nil, 'more than the gun holds now')
                if not back then
                    local now = GunnyStillThere(weapon.addr, slotData.item, meta.serial)
                    local nowMeta = now and now.metadata or {}
                    nowMeta.ammo = (tonumber(nowMeta.ammo) or 0) + (held - cap)
                    if now and Whip.core:SetItemMetadata(weapon.addr, nowMeta) == true then
                        meta.ammo = nowMeta.ammo
                    else
                        GunnyWarn('%d cartridges of %s LOST: nowhere to put them, and the gun could not keep them', held - cap, slotData.item)
                    end
                end
            else
                meta.ammo = held
            end
        end
    end

    -- The client puts one away before drawing another, so a record still here is a stale one.
    GunnyEndDrawn(source, 'replaced')
    local record = {
        slot = weapon.addr.slot,
        pocket = weapon.addr.sub,
        weapon = slotData.item,
        serial = meta.serial,   -- its identity (GunnyDrawnWeapon); a throwable has none: its slot and item
        countVersion = 1,       -- GunnyCountChanged
    }

    local ammo, kind = 0, nil
    if throwable then
        ammo = tonumber(slotData.amount) or 0   -- the hand holds the whole stack
        record.count = ammo
        GunnyDebugPrint('Player', source, 'took out', ammo, slotData.item)
    elseif Config.IsBow(weaponConfig) then
        -- The arrows of its kind carried, or of the first kind carried; none: drawn empty, set for its kind.
        local have
        kind, have = GunnyCarriedKind(source, slotData.item, GunnyKindOf(slotData.item, meta))
        kind = kind or GunnyKindOf(slotData.item, meta)
        ammo = have
        record.count, record.arrowItem = have, kind
        GunnyDebugPrint('Player', source, 'took out a bow with', have, kind)
    elseif Config.IsFirearm(weaponConfig) then
        ammo = tonumber(meta.ammo) or 0
        kind = GunnyKindOf(slotData.item, meta)
        GunnyDebugPrint('Player', source, 'drew', slotData.item, 'with', ammo, kind)
        GunnyLedgerDrawn(source, slotData.item, meta.serial, kind, ammo)   -- server/ledger.lua
    end

    EquippedWeapons[source] = record
    setHeld(source, weapon.addr)
    TriggerEvent('spur_gunny:weapon:drawn', { source = source, item = slotData.item, kind = Config.KindOf(weaponConfig),
        serial = meta.serial, slot = weapon.addr.slot, pocket = weapon.addr.sub })

    return true, { hash = weaponConfig.hash, ammo = ammo, kind = kind, ammoType = ammoTypeOf(kind),
                   attachments = meta.attachments or {}, serial = meta.serial, countVersion = 1 }
end)

--- Put away: the cartridges left as the client counts them, written to the gun in its slot, only when lower (firing
--- only lowers a count), as the ammo sync is (server/shooting.lua).
local function keepCount(source, slotData, equipped, rounds)
    local weaponConfig = Config.GetWeapon(slotData.item)
    -- A throwable or a bow: nothing to write, each one thrown or shot was taken as it went (server/throwables.lua).
    if not Config.IsFirearm(weaponConfig) then return end
    local meta = slotData.metadata or {}
    local before = tonumber(meta.ammo) or 0
    -- RedM (spur_gunny, 25 Nov 2026): written even when it is no lower. Each shot writes its count quietly (server/shooting.lua),
    -- so the player's own copy of the pockets kept the count from before the shots until the inventory was next
    -- opened; this one write, not quiet, sends the pockets with the true count.
    local lower = rounds < before
    if lower then meta.ammo = rounds end
    if not exports.spur_core:SetItemMetadata(GunnyPocket(source, equipped.pocket, equipped.slot), meta) then
        GunnyWarn('holster: the count of %s could not be written', slotData.item)
    elseif lower then
        GunnyLedgerGun(source, slotData.item, equipped.serial, 'holster', before, rounds)   -- server/ledger.lua
    end
end

RegisterGunnyCallback('spur_gunny:holsterWeapon', {
    whileDead = true,   -- dying puts the gun away
    -- A release: a burst, so one is never refused for coming close behind another (a forced holster as the player
    -- dies), which would leave the gun drawn here.
    rateLimit = 200,
    burst     = 3,
    params = {
        {'remainingAmmo', 'int', 0, 9999},
        {'countVersion',  'int', 0, 2147483647, 0},   -- GunnyCountChanged
    },
}, function(source, _, remainingAmmo, countVersion)
    local slotData, equipped = GunnyDrawnWeapon(source)
    if not equipped then return false, 'No weapon drawn' end
    if slotData and countVersion == equipped.countVersion then
        keepCount(source, slotData, equipped, remainingAmmo)
    elseif slotData then
        GunnyDebugPrint('Holster count from before the last change ignored', source, countVersion, equipped.countVersion)
    end

    GunnyEndDrawn(source, 'holstered')
    setHeld(source, nil)
    GunnyDebugPrint('Player', source, 'holstered weapon')

    return true
end)
