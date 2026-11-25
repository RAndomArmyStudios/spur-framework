-- spur_gunny: RDR2'S WEAPON WHEEL (client)
--
-- RedM (spur_gunny, 25 Nov 2026): new; whip_gunny (by Whippy and WLVF) has nothing like it, GTA's wheel being switched
-- off there. On RedM the wheel (Tab) is the game's own way to pick a gun, and it shows what the ped carries. gunny
-- puts a gun on the ped only while it is drawn, so the wheel was empty. With Config.Wheel.enabled:
--
--   * every sidearm, bow and blade in the pockets, and the two long guns in the lowest pocket slots (RDR2 carries two,
--     on the back and the shoulder, and its wheel shows those), is carried on the body, holstered and EMPTY (its
--     rounds stay with its item, as ever: the guard keeps every pool but the drawn gun's at nothing);
--   * picking one on the wheel (or the game's own tap of Tab) draws it the way Equip does, through the server:
--     DrawWeapon on its pocket slot. A draw the server refuses puts the hands back to empty;
--   * picking the fists, or the game putting the gun away, holsters it the way Equip does.
--
-- So the wheel is a second way to press Equip, and nothing about who owns the rounds changes. Throwables are left to
-- their items (the game will not carry one with none to throw).

local cfg = Config.Wheel or {}
if cfg.enabled == false then return end

local UNARMED = Config.Hash('WEAPON_UNARMED')
local GIVE_WEAPON_TO_PED, ADD_REASON_DEFAULT = 0x5E3BDDBCB83F3D84, GetHashKey('ADD_REASON_DEFAULT')
local SYNC_MS, WATCH_MS = 1000, 150
local PICK_MS = 200         -- a wheel pick must stand this long before it is drawn
local AWAY_MS = 700         -- the drawn gun out of the hands this long: put away
local RETRY_MS = 2000       -- after a refused draw, that gun is not tried again for this long

local carried = {}          -- weapon hash -> true: on the ped by this file's doing
local carriedPed = 0
local want = {}             -- weapon hash -> { slot, pocket }: the pockets' guns as last read
local busy = false          -- a draw or holster this file asked for is under way
local refusedUntil = {}     -- weapon hash -> game time

local function loaded(hash)
    local r = HasWeaponAssetLoaded(hash)
    return r == true or (type(r) == 'number' and r ~= 0)
end

--- The pockets' weapons: hash -> the lowest slot holding one.
local LONG_SLOTS = 2   -- RDR2 carries two long guns (Longarm Back, Longarm Shoulder), and its wheel shows those two

local function isLong(w)
    return w.kind == 'gun' and w.group ~= 'revolver' and w.group ~= 'pistol'
end

local function readPockets()
    local out = {}
    local ok, inv = pcall(function() return exports.spur_core:GetInventory() end)
    if not ok or type(inv) ~= 'table' then return out end
    local pockets = inv.player
    if type(pockets) ~= 'table' then return out end
    for slot, data in pairs(pockets) do
        local w = data and Config.Weapons[data.item]
        local n = tonumber(slot)
        if w and w.hash and n and not Config.IsThrowable(w) then
            local h = Config.U32(w.hash)
            if not out[h] or n < out[h].slot then out[h] = { slot = n, pocket = 'player', long = isLong(w) } end
        end
    end
    -- Of the long guns, only the two in the lowest pocket slots are carried: given more, the game picks two of them
    -- itself, by no rule a player can see. The others are drawn from the inventory or a hotbar key, as ever.
    local longs = {}
    for h, spot in pairs(out) do
        if spot.long then longs[#longs + 1] = { h = h, slot = spot.slot } end
    end
    table.sort(longs, function(a, b) return a.slot < b.slot end)
    for i = LONG_SLOTS + 1, #longs do out[longs[i].h] = nil end
    return out
end

local function takeOff(ped, hash)
    carried[hash] = nil
    GunnyGuardHold[hash] = nil
    if not (CurrentWeapon and CurrentWeapon.hash == hash) then
        if HasPedGotWeapon(ped, hash, 0, false) then RemoveWeaponFromPed(ped, hash) end
        Whip.core:PermitNativeWeapon(hash, false)
    end
end

--- The ped's holsters brought in line with the pockets. Not while a gun is on its way in or out of the hands.
local function sync()
    local ped = PlayerPedId()
    if ped == 0 or not DoesEntityExist(ped) or busy or GunnyPuttingAway() then return end
    if ped ~= carriedPed then carried, carriedPed = {}, ped end   -- a new ped carries nothing
    want = readPockets()
    for hash in pairs(carried) do
        if not want[hash] then takeOff(ped, hash) end
    end
    if Whip.core:IsPlayerDead() == true then return end
    local gave = false
    for hash in pairs(want) do
        local drawn = CurrentWeapon and CurrentWeapon.hash == hash
        GunnyGuardHold[hash] = true                        -- gunny's guard leaves it (client/guard.lua)
        if not drawn and not HasPedGotWeapon(ped, hash, 0, false) and IsWeaponValid(hash) then
            if not loaded(hash) then
                RequestWeaponAsset(hash, 31, 0)            -- given at a later look, once it is in
            else
                Whip.core:PermitNativeWeapon(hash, true)   -- spur_core's guard leaves it too
                -- not into the hand, into its holster, unlocks ignored (client/weapons.lua says why)
                Citizen.InvokeNative(GIVE_WEAPON_TO_PED, ped, hash, 0, false, true, 0, false, 0.5, 1.0,
                    ADD_REASON_DEFAULT, true, 0.0, false)
                carried[hash] = true
                gave = true
            end
        else
            carried[hash] = true
        end
    end
    -- The game gives a gun with rounds in it whatever is asked: taken back at once (every pool but the drawn gun's).
    if gave then GunnyAmmo.reconcile(ped, true) end
end

-- A gun put away: the permit went with it (client/weapons.lua letGo), so it is carried again at once.
GunnyAfterHolster(function()
    CreateThread(function()
        Wait(0)
        pcall(sync)
    end)
end)

CreateThread(function()
    while true do
        Wait(SYNC_MS)
        local ok, err = pcall(sync)
        if not ok then print('[GUNNY] the wheel errored: ' .. tostring(err)) end
    end
end)

--- Empty hands, when a pick could not be drawn (so no empty, untracked gun is left out).
local function handsEmpty(ped)
    SetCurrentPedWeapon(ped, UNARMED, true, 0, false, false)
end

CreateThread(function()
    local seen, since = nil, 0
    while true do
        Wait(WATCH_MS)
        local ped = PlayerPedId()
        local now = GetGameTimer()
        local sel = ped ~= 0 and Config.U32(GetSelectedPedWeapon(ped)) or nil
        if sel ~= seen then seen, since = sel, now end
        local cur = CurrentWeapon
        if sel and not busy and not GunnyPuttingAway() and not GunnyReloadUnderWay() then
            local held = now - since
            if sel ~= UNARMED and want[sel] and (not cur or cur.hash ~= sel) then
                -- a carried gun came into the hand: the wheel's pick, or the game's own draw
                if held >= PICK_MS then
                    if now < (refusedUntil[sel] or 0) then
                        handsEmpty(ped)
                    else
                        busy = true
                        local spot = want[sel]
                        local ok, drew = pcall(DrawWeapon, spot.slot, spot.pocket)
                        if not ok or drew ~= true then
                            refusedUntil[sel] = GetGameTimer() + RETRY_MS
                            if not CurrentWeapon then handsEmpty(PlayerPedId()) end
                        end
                        busy = false
                        seen = nil
                    end
                end
            elseif cur and sel == UNARMED and held >= AWAY_MS and now - (cur.drawnAt or 0) >= 1500 then
                -- the drawn gun left the hands (the fists picked, a tap of Tab): put away as Equip does
                busy = true
                pcall(GunnyHolster)
                busy = false
                seen = nil
            end
        end
    end
end)

local function strip()
    local ped = PlayerPedId()
    for hash in pairs(carried) do takeOff(ped, hash) end
    want = {}
end
AddEventHandler('spur_core:player:logout', strip)
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then strip() end
end)
