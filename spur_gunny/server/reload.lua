-- spur_gunny: RELOADING, UNLOADING, AND THE KIND OF CARTRIDGE (server)
--
-- RedM (spur_gunny, 24 Nov 2026): rewritten. There are no magazines: every gun holds loose cartridges of one kind (the
-- gun's `ammo` and `kind` metadata). R plays the game's own reload, a cartridge at a time or all at once as RDR2 does
-- it for that gun, and the player may stop partway. So nothing is taken when the reload starts: beginReload says how
-- many may go in and of which kind, and the client says how many did when it ends. Only those are taken, from the
-- pockets, never more than the gun has room for or than are still carried. A reload that never says (a death, a drop,
-- the gun put away) takes nothing, and the gun keeps what it had. (whip_gunny's shell-at-a-time reload, for every gun.)
--
-- A gun holds one kind at a time. Reloaded with some still in it, it takes more of the same kind; empty, it takes the
-- kind it is set for, or the first kind of its group carried. "Switch Cartridges" (the item's menu) unloads it and sets
-- it for the next kind carried. A bow's arrows are not loaded: Switch Arrows sets which kind it shoots.

local pending = {}   -- [source] = { item, serial, pocket, slot, room, kind, at }
local REPORT_MS = 30000

--- Is a reload under way on this player's gun in this slot? Unload and Switch wait for it: the client counts the
--- cartridges going in, and a change made meanwhile would not be in its count.
---@param source number
---@param slot number
---@param pocket string
---@return boolean
function GunnyReloadOpen(source, slot, pocket)
    local r = pending[source]
    return r ~= nil and r.slot == slot and r.pocket == (pocket or 'player') and GetGameTimer() - r.at <= REPORT_MS
end

--- The cartridges a gun holds, in force (the Items page may have changed it).
local function capacityOf(weaponConfig)
    return math.max(0, math.floor(tonumber(weaponConfig.capacity) or 0))
end

RegisterGunnyCallback('spur_gunny:beginReload', { params = { { 'weapon', 'slot', { item = GunnyWeaponItems } } } },
function(source, _, weapon)
    local weaponConfig = Config.GetWeapon(weapon.item)
    -- Only a modified client asks for anything but a gun: client/reload.lua stands down for the rest.
    if not Config.IsFirearm(weaponConfig) then return false, 'That weapon is not reloaded' end

    local meta = weapon.metadata or {}
    local loaded = tonumber(meta.ammo) or 0
    local room = capacityOf(weaponConfig) - loaded
    if room <= 0 then return false, 'Already fully loaded' end

    local kind, have
    if loaded > 0 then
        -- More of what is in it.
        kind = GunnyKindOf(weapon.item, meta)
        have = kind and (exports.spur_core:GetItemCount(source, kind) or 0) or 0
        if have <= 0 then
            return false, ('No %s on you'):format(kind and Config.AmmoLabel(kind) or 'cartridges for it')
        end
    else
        kind, have = GunnyCarriedKind(source, weapon.item, GunnyKindOf(weapon.item, meta))
        if not kind then return false, ('No %s cartridges on you'):format(Config.GroupLabel(weapon.item) or 'matching') end
    end
    room = math.min(room, have)

    pending[source] = { item = weapon.item, serial = meta.serial, pocket = weapon.addr.sub or 'player',
                        slot = weapon.addr.slot, room = room, kind = kind, at = GetGameTimer() }
    local a = Config.GetAmmo(kind)
    GunnyDebugPrint('Reload begins -', weapon.item, 'room for', room, kind)
    return true, { room = room, kind = kind, ammoType = a.type, kindLabel = a.label }
end)

-- The cartridges that went in. Taken now, as many as are still on the player (some may have left the pockets
-- mid-reload), and never more than the gun has room for.
RegisterGunnyEvent('spur_gunny:server:reloadEnded', {
    whileDead = true,   -- an end: a reload cut by a death still says what went in
    rateLimit = 200,
    burst     = 3,      -- an end: never refused for coming close behind the last
    params = { {'loaded', 'int', 0, 250} },
}, function(source, _, loaded)
    local r = pending[source]
    pending[source] = nil
    if not r or GetGameTimer() - r.at > REPORT_MS then return end
    loaded = math.min(loaded, r.room)
    if loaded <= 0 then return end

    local addr = GunnyPocket(source, r.pocket, r.slot)
    local sd = GunnyStillThere(addr, r.item, r.serial)
    if not sd then return end
    local weaponConfig = Config.GetWeapon(r.item)
    if not weaponConfig then return end
    local before = tonumber((sd.metadata or {}).ammo) or 0
    -- One kind at a time: rounds of another kind in it now (none should be: Unload and Switch wait for the reload).
    if before > 0 and GunnyKindOf(r.item, sd.metadata) ~= r.kind then
        TriggerClientEvent('spur_gunny:client:reloadShort', source, r.slot, r.pocket, before)
        return
    end
    local space = capacityOf(weaponConfig) - before
    local have = exports.spur_core:GetItemCount(source, r.kind) or 0
    local take = math.max(0, math.min(loaded, space, have))
    if take > 0 and not exports.spur_core:RemoveItem(source, r.kind, take, nil, { reason = 'loaded into a weapon' }) then
        take = 0
    end

    -- Read again after the take: the slot as it is now, never what was read before it (a shot counted since has lowered
    -- the count, and stays).
    sd = GunnyStillThere(addr, r.item, r.serial)
    if take > 0 and not sd then
        GunnyWarn('reload: the weapon moved during the take, so %d cartridges go back to the pockets', take)
        GunnyGiveBack(source, r.kind, take, nil, 'reload undone')
        return
    end
    local meta = sd and sd.metadata or {}
    local kindBefore = meta.kind
    if take > 0 then
        meta.ammo = (tonumber(meta.ammo) or 0) + take
        meta.kind = r.kind
        meta.kindLabel = Config.AmmoLabel(r.kind)
        local wrote, why = exports.spur_core:SetItemMetadata(addr, meta)
        if not wrote then
            if why == 'Too heavy' then
                exports.spur_core:NotifyPlayer(source, 'You are carrying too much to load it. Put something down first', 'error')
            else
                GunnyWarn('reload: the weapon could not be written, so %d cartridges go back to the pockets', take)
            end
            GunnyGiveBack(source, r.kind, take, nil, 'reload undone')
            meta.ammo = meta.ammo - take
            meta.kind = kindBefore
            take = 0
        end
    end
    if take < loaded and sd then
        TriggerClientEvent('spur_gunny:client:reloadShort', source, r.slot, r.pocket, tonumber(meta.ammo) or 0)
    end
    GunnyDebugPrint('Reload - loaded', take, 'of', loaded, r.kind, '- total:', meta.ammo)
    if take > 0 then
        GunnyLedgerGun(source, r.item, r.serial, 'reload', (meta.ammo or 0) - take, meta.ammo or 0, nil, r.kind)   -- server/ledger.lua
    end
end)

AddEventHandler('playerDropped', function() pending[source] = nil end)
AddEventHandler('spur_core:player:logout', function(e) pending[e.source] = nil end)
-- Put away mid-reload: the client reports nothing (the gun keeps what it had).
AddEventHandler('spur_gunny:weapon:holstered', function(e) pending[e.source] = nil end)

-- ============================================
-- UNLOAD AND SWITCH (the item's menu, server/items.lua)
-- ============================================

--- Empty a gun into the pockets. Answers true and how many came out, or false and why.
--- Take before give: the gun is written empty first, then its cartridges are handed back; when they land nowhere, the
--- gun takes them back.
---@param source number
---@param addr table      the gun's slot
---@param slotData table  spur_core's copy of it
---@return boolean ok
---@return string|number whyOrCount
function GunnyUnload(source, addr, slotData)
    local weaponConfig = Config.GetWeapon(slotData.item)
    if not Config.IsFirearm(weaponConfig) then return false, 'That is not a gun' end
    if GunnyReloadOpen(source, addr.slot, addr.sub) then return false, 'Finish reloading first' end
    local meta = slotData.metadata or {}
    local n = tonumber(meta.ammo) or 0
    if n <= 0 then return true, 0 end
    local kind = GunnyKindOf(slotData.item, meta)

    meta.ammo = 0
    if not exports.spur_core:SetItemMetadata(addr, meta) then return false, 'Could not unload it, try again' end
    local version = GunnyCountChanged(source, addr, meta.serial)

    local where = kind and Whip.core:AddItem(source, kind, n, nil, 'unloaded from a weapon')
    if not where then
        -- Nowhere at all: back into the gun, as it is now.
        local now = GunnyStillThere(addr, slotData.item, meta.serial)
        local nowMeta = now and now.metadata
        if nowMeta and (tonumber(nowMeta.ammo) or 0) == 0 then
            nowMeta.ammo = n
            if Whip.core:SetItemMetadata(addr, nowMeta) == true then
                if version then
                    local v = GunnyCountChanged(source, addr, meta.serial)
                    if v then TriggerClientEvent('spur_gunny:client:loadChanged', source, addr.slot, addr.sub or 'player', n, kind, v) end
                end
                return false, 'No room for the cartridges'
            end
        end
        GunnyWarn('unload: %d x %s LOST: nowhere to put them, and the gun could not take them back', n, tostring(kind))
        return false, 'No room for the cartridges'
    end
    if version then
        TriggerClientEvent('spur_gunny:client:loadChanged', source, addr.slot, addr.sub or 'player', 0, meta.kind or kind, version)
    end
    GunnyLedgerGun(source, slotData.item, meta.serial, 'unload', n, 0)   -- server/ledger.lua
    return true, n
end

--- The next kind after `current` in this weapon's group that the player carries, or nil.
local function nextCarried(source, weaponName, current)
    local kinds = Config.AmmoKindsFor(weaponName)
    local at = 0
    for i, k in ipairs(kinds) do if k == current then at = i end end
    for step = 1, #kinds do
        local k = kinds[(at + step - 1) % #kinds + 1]
        if k ~= current and (exports.spur_core:GetItemCount(source, k) or 0) > 0 then return k end
    end
    return nil
end

--- Set a gun or a bow for the next kind of cartridge (or arrow) the player carries. A gun is unloaded first. Answers
--- true and the kind's label, or false and why.
---@param source number
---@param addr table
---@param slotData table
---@return boolean ok
---@return string labelOrWhy
function GunnySwitchKind(source, addr, slotData)
    local weaponConfig = Config.GetWeapon(slotData.item)
    local bow = Config.IsBow(weaponConfig)
    if not (bow or Config.IsFirearm(weaponConfig)) then return false, 'That weapon takes no cartridges' end
    if GunnyReloadOpen(source, addr.slot, addr.sub) then return false, 'Finish reloading first' end
    local meta = slotData.metadata or {}
    local current = GunnyKindOf(slotData.item, meta)
    local nextKind = nextCarried(source, slotData.item, current)
    if not nextKind then
        return false, bow and 'You carry no other kind of arrow' or 'You carry no other kind of cartridge for it'
    end

    if not bow and (tonumber(meta.ammo) or 0) > 0 then
        local ok, why = GunnyUnload(source, addr, slotData)
        if not ok then return false, why end
        local now = GunnyStillThere(addr, slotData.item, meta.serial)
        if not now then return false, 'The gun moved' end
        meta = now.metadata or {}
    end
    meta.kind = nextKind
    meta.kindLabel = Config.AmmoLabel(nextKind)
    if not Whip.core:SetItemMetadata(addr, meta) then return false, 'Could not set it, try again' end

    local e = EquippedWeapons[source]
    local drawnHere = e and e.slot == addr.slot and e.pocket == (addr.sub or 'player') and e.serial == meta.serial
    if drawnHere and bow then
        -- The drawn bow shoots the new kind from now: its count is the new kind's.
        e.arrowItem = nextKind
        e.count = exports.spur_core:GetItemCount(source, nextKind) or 0
        TriggerClientEvent('spur_gunny:client:stackKind', source, Config.GetAmmo(nextKind).type, e.count, e.taken or 0)
    elseif drawnHere then
        local v = GunnyCountChanged(source, addr, meta.serial)
        if v then TriggerClientEvent('spur_gunny:client:loadChanged', source, addr.slot, addr.sub or 'player', 0, nextKind, v) end
    end
    return true, Config.AmmoLabel(nextKind)
end

-- What the player carries for a gun or a bow, for Gunny Debug (client/debug.lua): each kind and its count. Developer
-- mode only, as the overlay is. Answers true and { kinds = { { item, label, count } }, total }.
RegisterGunnyCallback('spur_gunny:countInventory', { ace = 'whip.devtools', params = { { 'weaponName', 'key', 64 } } },
function(source, _, weaponName)
    if not Config.GetWeapon(weaponName) then return false, 'Not one of gunny\'s weapons' end
    local list, total = {}, 0
    for _, kind in ipairs(Config.AmmoKindsFor(weaponName)) do
        local n = exports.spur_core:GetItemCount(source, kind) or 0
        list[#list + 1] = { item = kind, label = Config.AmmoLabel(kind), count = n }
        total = total + n
    end
    return true, { kinds = list, total = total }
end)
