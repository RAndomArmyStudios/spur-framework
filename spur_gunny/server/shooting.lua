-- spur_gunny: SHOTS (server)
--
-- The client counts shots (it sees the cartridges in the gun frame by frame); the server holds the number. Each shot
-- takes a cartridge from the drawn gun, and the client's own count is only ever believed when it is lower.
--
-- A shot fired in the frame the gun is put away can be counted after the holster read its count, so it arrives just
-- behind the holster. It is still charged to that gun, as long as it sits where it was drawn from (GunnyDrawnWeapon's
-- `lateToo`): dropped, the round would come back with the next draw. Nothing is sent back for it: the hand holds
-- nothing now, or the next gun.
--
-- RedM (spur_gunny, 24 Nov 2026): no magazines and no jerry can. Every gun holds its own cartridges (meta.ammo).
-- Shooting from the saddle or a wagon is counted the same way (client/shooting.lua). A bow's arrows are taken as
-- thrown (server/throwables.lua).

--- Rounds this player's drawn gun spent, for other resources: spur_gunny:weapon:fired, once per batch the server
--- took (a burst arrives as a few, a missed shot with the next sync).
local function fired(source, slotData, equipped, shots, ammo)
    local ped = GetPlayerPed(source)
    TriggerEvent('spur_gunny:weapon:fired', { source = source, item = slotData.item, serial = equipped.serial,
        shots = shots, ammo = ammo, kind = (slotData.metadata or {}).kind,
        coords = ped ~= 0 and GetEntityCoords(ped) or nil })
end

--- A shot left the barrel.
RegisterGunnyEvent('spur_gunny:server:shotFired', {
    whileDead = true,   -- a round fired just before dying is still spent
    -- The light player sheet: the handler never reads `player`, and this fires a few times a second per shooter.
    sheet = 'light',
    -- Above any of RDR2's fire rates, but not unlimited: each shot is a metadata write. 15 ms, burst 30.
    -- A dropped shot is never charged.
    rateLimit = 15,
    burst     = 30,
    params = {
        -- Bounded: one report cannot claim to have emptied a gun of 26.
        {'shotsFired', 'int', 1, 10, 1},
    },
}, function(source, _, shotsFired)
    -- The server's own record of the drawn gun (or the one just put away: the top of this file), still in the slot it
    -- was drawn from: one moved away is put away rather than fired for free.
    local slotData, equipped, late = GunnyDrawnWeapon(source, true)
    if not equipped then
        GunnyDebugPrint('Shot fired event but weapon not tracked as equipped')
        GunnyNoDrawRecord(source)
        return
    end
    if not slotData then
        if not late then GunnyForceHolster(source) end
        return
    end
    local addr = GunnyPocket(source, equipped.pocket, equipped.slot)

    local weaponConfig = Config.GetWeapon(slotData.item)
    if not Config.IsFirearm(weaponConfig) then return end

    local meta = slotData.metadata or {}
    local before = tonumber(meta.ammo) or 0
    local newAmmo = math.max(0, before - shotsFired)
    meta.ammo = newAmmo

    -- A failed write: the round was never spent. `quiet`: no whole-inventory push every shot (the count goes back as
    -- syncAmmo); the pockets are saved about once a second, so a burst is one write.
    if not exports.spur_core:SetItemMetadata(addr, meta, { quiet = true }) then
        GunnyWarn('shot fired but metadata write FAILED - ammo not synced to client')
        return
    end

    GunnyDebugPrint(late and 'Shot fired as the gun went away - Ammo:' or 'Shot fired - Ammo:', newAmmo)
    GunnyLedgerGun(source, slotData.item, equipped.serial, 'shot', before, newAmmo, shotsFired)   -- server/ledger.lua
    if not late then TriggerClientEvent('spur_gunny:client:syncAmmo', source, newAmmo, equipped.countVersion) end
    -- Only rounds there were: a claim past an empty gun spent nothing.
    if before > newAmmo then fired(source, slotData, equipped, before - newAmmo, newAmmo) end
end)

--- The client's own count, every few seconds and as it reconciles: taken only when lower (a shot the server missed).
--- Higher would be a free reload. One from before the server's last change to the gun (GunnyCountChanged) is ignored:
--- it was counted for the cartridges that were in it then. One sent as the gun went away counts for it, as a shot does
--- (the top of this file).
RegisterGunnyEvent('spur_gunny:server:syncAmmo', {
    whileDead = true,
    -- About once a second at most, with a burst: one arriving a few ms early over a jittery connection is still taken.
    rateLimit = 1000,
    burst     = 3,
    params = {
        {'ammoCount',    'int', 0, 9999},
        {'countVersion', 'int', 0, 2147483647, 0},
    },
}, function(source, _, ammoCount, countVersion)
    local slotData, equipped, late = GunnyDrawnWeapon(source, true)
    if not equipped then GunnyNoDrawRecord(source) return end
    if not slotData then
        if not late then GunnyForceHolster(source) end
        return
    end
    if countVersion ~= equipped.countVersion then
        GunnyDebugPrint('Ammo sync from before the last change ignored', source, countVersion, equipped.countVersion)
        return
    end
    local addr = GunnyPocket(source, equipped.pocket, equipped.slot)

    local weaponConfig = Config.GetWeapon(slotData.item)
    if not Config.IsFirearm(weaponConfig) then return end

    local meta = slotData.metadata or {}
    local before = tonumber(meta.ammo) or 0
    if ammoCount >= before then return end
    meta.ammo = ammoCount

    if not exports.spur_core:SetItemMetadata(addr, meta, { quiet = true }) then
        GunnyWarn('ammo sync metadata write FAILED')
        return
    end
    GunnyDebugPrint('Synced ammo from client:', ammoCount)
    GunnyLedgerGun(source, slotData.item, equipped.serial, 'sync', before, ammoCount)   -- server/ledger.lua
    fired(source, slotData, equipped, before - ammoCount, ammoCount)
end)
