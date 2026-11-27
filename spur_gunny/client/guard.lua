-- spur_gunny: THE GUARD (client)
--
-- RedM (spur_gunny, 24 Nov 2026): new. RDR2 hands out weapons and ammunition by itself: a gun picked up off a body,
-- cartridges looted, arrows pulled out of a deer, a kit, a cheat. spur_core's weapon guard knows only the game's weapons,
-- so this one looks after RDR2's. Every Config.Guard.intervalMs, as the weapon in hand changes, and after every draw and
-- holster:
--   * a weapon from items/weapons.lua on the ped that was not drawn from the inventory is taken away
--     (Config.Guard.sweepWeapons; Config.Guard.keep leaves some alone);
--   * every ammunition pool gunny knows is put back to what the items say (GunnyAmmo.reconcile, client/ammo.lua):
--     the drawn weapon's never above its count, every other kind empty.
-- Also: no second gun in the other hand, no weapon dropped on death, and long guns not put on the horse at a dismount.

local WATCH_MS = 100   -- how often the weapon in hand is looked at

local catalogue, keep = nil, nil
GunnyPacks.onChange(function() catalogue = nil end)

--- Every weapon hash in the items, once each, and the ones to leave alone.
local function weaponHashes()
    if catalogue then return catalogue end
    local seen = {}
    catalogue = {}
    for _, w in pairs(Config.Weapons) do
        if w.hash and not seen[w.hash] then
            seen[w.hash] = true
            catalogue[#catalogue + 1] = w.hash
        end
    end
    keep = {}
    for _, name in ipairs(Config.Guard.keep or {}) do keep[Config.Hash(name)] = true end
    return catalogue
end

local lastPed = 0

-- RedM (spur_gunny, 24 Nov 2026): weapons left alone for a while by a dev tool (/gunnygivelab, client/debug.lua).
---@type table<integer, boolean>
GunnyGuardHold = {}

--- Look the ped over now. `why` is for the debug line.
---@param why string
function GunnyGuardSweep(why)
    local ped = PlayerPedId()
    if ped == 0 or not DoesEntityExist(ped) then return end
    if ped ~= lastPed then
        -- A new ped (spawn, a death, a model change): its weapon settings again.
        lastPed = ped
        SetAllowDualWield(ped, false)
        SetPedDropsWeaponsWhenDead(ped, false)
        Citizen.InvokeNative(0xB832F1A686B9B810, ped, false, 0)   -- _SET_INSTANTLY_STORE_LONGARMS_ON_DISMOUNT
    end

    if Config.Guard.sweepWeapons ~= false then
        local list = weaponHashes()
        local drawn = CurrentWeapon and CurrentWeapon.hash
        for i = 1, #list do
            local h = list[i]
            if h ~= drawn and not keep[h] and not GunnyGuardHold[h] and HasPedGotWeapon(ped, h, 0, false) then
                RemoveWeaponFromPed(ped, h)   -- rdr_compat: REMOVE_WEAPON_FROM_PED
                GunnyDebugCounts.sweptWeapons = GunnyDebugCounts.sweptWeapons + 1
                GunnyDebugPrint('Guard: took a weapon nothing drew', h, why)
            end
        end
    end

    GunnyAmmo.reconcile(ped, true)
end

GunnyAfterDraw(function() GunnyGuardSweep('drawn') end)
GunnyAfterHolster(function() GunnyGuardSweep('holstered') end)

CreateThread(function()
    local lastWeapon, nextSweep = nil, 0
    while true do
        Wait(WATCH_MS)
        local ped = PlayerPedId()
        local now = GetGameTimer()
        local inHand = ped ~= 0 and Config.U32(GetSelectedPedWeapon(ped)) or nil
        local interval = math.max(WATCH_MS, tonumber(Config.Guard.intervalMs) or 500)
        if inHand ~= lastWeapon or now >= nextSweep then
            local changed = inHand ~= lastWeapon
            lastWeapon = inHand
            nextSweep = now + interval
            -- A draw gives the weapon and names it CurrentWeapon with no wait between, so this never sees one half done.
            local ok, err = pcall(GunnyGuardSweep, changed and 'weapon changed' or 'timer')
            if not ok then print('[GUNNY] the guard errored: ' .. tostring(err)) end
        end
    end
end)
