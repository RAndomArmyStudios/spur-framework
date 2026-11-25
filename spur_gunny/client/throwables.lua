-- spur_gunny: THROWABLES AND ARROWS (client)
--
-- A throwable is a stack, and the hand holds the whole stack. The game throws them; gunny only counts: a throw shows as
-- the game's count going down, and how many left the hand goes to the server, which takes them from the stack
-- (server/throwables.lua). Looked at every frame one is drawn, and once more as it is put away, so a throw just before a
-- holster or a death still counts.
--
-- RedM (spur_gunny, 24 Nov 2026): RDR2's throwables. Dynamite and fire bottles are lit and thrown, and go off by their
-- own fuse: there is nothing to set off by hand, so G only checks a gun's ammo. Throwing knives, tomahawks, hatchets and
-- bolas are thrown the same way. A bow's arrows are counted here too: each arrow shot is taken from the arrows of its
-- kind in the pockets. One picked up again in the world (an arrow out of a deer, a tomahawk off the ground) is the
-- game's, and is taken back off the ped, as looted ammunition is.

--- Is the drawn weapon a throwable?
---@return boolean
function GunnyThrowableDrawn()
    return CurrentWeapon ~= nil and Config.IsThrowable(CurrentWeapon.config)
end

--- Report `n` thrown or shot, at most 10 a report (the server's schema).
local function report(n)
    while n > 0 do
        local part = math.min(n, 10)
        TriggerServerEvent('spur_gunny:server:thrown', part)
        CurrentWeapon.thrownSent = (CurrentWeapon.thrownSent or 0) + part   -- every one reported this draw
        n = n - part
    end
end

--- A bow: arrows off the ped since the last look, told to the server; arrows onto it, taken back.
local function arrowSettle(ped)
    local w = CurrentWeapon
    if not w.typeHash then return end
    local total = GunnyAmmo.total(ped)
    local known = w.pedTotal or total
    if total < known then
        local n = known - total
        w.pedTotal = total
        w.ammo = math.max(0, (w.ammo or 0) - n)
        report(n)
        GunnyDebugPrint('Shot', n, w.kind or 'arrows', '-', w.ammo, 'left')
    elseif total > known then
        GunnyAmmo.reconcile(ped)
    end
end

--- What left the hand since the last look, told to the server. A count that went up is not believed: it is taken back
--- off the ped, and the server's count comes back as spur_gunny:client:syncThrown.
---
--- The game takes the weapon away with the last one thrown: gone with one left, it was thrown; gone with more,
--- something else took it, and nothing was thrown.
---@param ped number
function GunnyThrowSettle(ped)
    local w = CurrentWeapon
    if not w then return end
    if Config.IsBow(w.config) then return arrowSettle(ped) end
    if not Config.IsThrowable(w.config) then return end
    local known = w.ammo or 0
    local left
    if HasPedGotWeapon(ped, w.hash, 0, true) then
        left = math.max(0, GetAmmoInPedWeapon(ped, w.hash) or 0)
    elseif known == 1 then
        left = 0
    else
        return
    end
    if left > known then
        GunnyDebugCounts.clampedClip = GunnyDebugCounts.clampedClip + (left - known)
        GunnyAmmo.setStack(known)
        return
    end
    if left == known then return end
    w.ammo = left
    w.pedTotal = left
    report(known - left)
    GunnyDebugPrint('Threw', known - left, w.name, '-', left, 'left')
end

-- The drawn stack's count (or the drawn bow's arrows) from the server: it changed in the inventory while drawn, or a
-- throw could not be taken. `taken` is how many of this draw's the server has had; the ones reported and not had yet
-- are still in its count, so they come off it here instead of coming back to the hand.
RegisterNetEvent('spur_gunny:client:syncThrown', function(count, taken)
    count = math.max(0, math.floor(tonumber(count) or 0))
    local w = CurrentWeapon
    if not (w and (Config.IsThrowable(w.config) or Config.IsBow(w.config))) then
        GunnyDrawNote('count', count)   -- during a draw: kept, and applied as it ends (client/weapons.lua)
        return
    end
    GunnyThrowSettle(PlayerPedId())
    if CurrentWeapon ~= w then return end
    local inFlight = math.max(0, (w.thrownSent or 0) - math.floor(tonumber(taken) or 0))
    if Config.IsBow(w.config) then
        GunnyAmmo.set(count - inFlight)
    else
        GunnyAmmo.setStack(count - inFlight)
    end
end)

-- The drawn bow set for another kind of arrow (Switch Arrows, server/reload.lua): it shoots that kind from now, and
-- holds what is carried of it.
RegisterNetEvent('spur_gunny:client:stackKind', function(ammoType, count, taken)
    local w = CurrentWeapon
    if not (w and Config.IsBow(w.config)) or type(ammoType) ~= 'string' then return end
    GunnyThrowSettle(PlayerPedId())   -- arrows shot of the old kind told first
    if CurrentWeapon ~= w then return end
    for _, kind in ipairs(Config.AmmoKindsFor(w.name)) do
        local a = Config.GetAmmo(kind)
        if a and a.type == ammoType then w.kind = kind end
    end
    w.ammoType = ammoType
    GunnyAmmo.setKind(Config.Hash(ammoType))
    local inFlight = math.max(0, (w.thrownSent or 0) - math.floor(tonumber(taken) or 0))
    GunnyAmmo.set(math.max(0, math.floor(tonumber(count) or 0)) - inFlight, true)
end)
