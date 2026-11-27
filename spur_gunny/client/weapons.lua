-- spur_gunny: DRAWING AND PUTTING AWAY (client)
--
-- The server says what is drawn (server/weapons.lua); this puts it in the hands, with its cartridges and its parts, and
-- takes it out again. CurrentWeapon (client/main.lua) is the drawn weapon, nil when none.
--
-- RedM (spur_gunny, 24 Nov 2026): RDR2's weapons, given and taken with RDR2's natives. The gun comes straight into
-- the hand (no game draw animation) and goes back with the game's own holster. No magazines and no jerry can: a gun
-- carries its kind of cartridge (`kind`, `ammoType`), and a bow the kind of arrow it shoots. whip_core -> spur_core,
-- whip_gunny: -> spur_gunny:.

local UNARMED = Config.Hash('WEAPON_UNARMED')

--- Weapon hash -> item key, built on first use, and again after a weapon pack's item arrives or goes.
local _hashToName = nil
GunnyPacks.onChange(function() _hashToName = nil end)

local function weaponByHash(hash)
    if not _hashToName then
        _hashToName = {}
        for name, cfg in pairs(Config.Weapons or {}) do
            if cfg.hash then _hashToName[cfg.hash] = name end
        end
    end
    return _hashToName[Config.U32(hash)]
end

--- spur_core's weapon guard takes away native weapons nothing permits: on before the give, off after the removal. A
--- refused permit is said, once per weapon.
local permitRefusalSaid = {}
local function permitGun(hash, on)
    if not hash then return end
    local ok = Whip.core:PermitNativeWeapon(hash, on)
    if on and ok ~= true and not permitRefusalSaid[hash] then
        permitRefusalSaid[hash] = true
        print(('[GUNNY] WARNING: spur_core\'s weapon guard did not permit weapon %s, so it may take it away'):format(tostring(hash)))
    end
end

--- Is this pocket slot the drawn weapon's?
local function isDrawn(slot, pocket)
    return CurrentWeapon ~= nil and CurrentWeapon.slot == slot and CurrentWeapon.pocket == pocket
end

-- ============================================
-- AFTER A DRAW OR A HOLSTER: gunny's own steps, then everyone's event
-- ============================================
--
-- gunny's other files react through these (its key blocks, the ammo sync, the guard), in order, before
-- spur_gunny:weapon:drawn / :holstered tell other resources.

local afterDraw, afterHolster = {}, {}

--- fn(gun) once a weapon is drawn: gun is CurrentWeapon.
function GunnyAfterDraw(fn) afterDraw[#afterDraw + 1] = fn end

--- fn(gun) once it is put away, however it went: gun is the record it was.
function GunnyAfterHolster(fn) afterHolster[#afterHolster + 1] = fn end

local function runSteps(steps, gun)
    for _, fn in ipairs(steps) do
        local ok, err = pcall(fn, gun)
        if not ok then print(('[GUNNY] a step after a draw or holster errored: %s'):format(tostring(err))) end
    end
end

-- One equip at a time. The latch has a deadline, so a server that never answers cannot block equipping for good.
local isEquipping = false
local equipStartedAt = 0
local EQUIP_TIMEOUT = 10000

--- The draw in flight, from asking the server until the weapon is in the hand. What the server says meanwhile is kept
--- and applied as the draw ends: `holster` (it took the weapon back) and `count` (a drawn stack or arrows changed).
local drawing = nil

--- Keep the server's word for the draw in flight. false: none in flight.
---@param what 'holster'|'count'
---@param value number|nil  the count, for 'count'
---@return boolean
function GunnyDrawNote(what, value)
    if not drawing then return false end
    if what == 'holster' then drawing.holster = true else drawing.count = value end
    return true
end

local function equipInProgress()
    if not isEquipping then return false end
    if GetGameTimer() - equipStartedAt > EQUIP_TIMEOUT then
        print('[GUNNY] equip lock expired after ' .. EQUIP_TIMEOUT .. 'ms: the server never answered. Releasing.')
        isEquipping = false
        return false
    end
    return true
end

--- Put the drawn weapon back on the server: its count, and it is no longer in the hand. Waits. The count goes with
--- its version: one from before the server's last change to the gun is ignored there (GunnyCountChanged).
---@return boolean ok
local function tellHolstered(ammo, countVersion)
    return GunnyCallback('spur_gunny:holsterWeapon', ammo or 0, countVersion or 0) == true
end

-- RedM (spur_gunny, 24 Nov 2026): the gun's asset is loaded before it is given (femga's notes: load it when the ped has
-- not had that gun out yet). RedM's Lua gives _HAS_WEAPON_ASSET_LOADED's answer as a number, and 0 is true in Lua:
-- compared here.
local ASSET_WAIT_MS = 3000
local function assetLoaded(hash)
    local r = HasWeaponAssetLoaded(hash)
    return r == true or (type(r) == 'number' and r ~= 0)
end
local function loadWeaponAsset(hash)
    if assetLoaded(hash) then return true end
    RequestWeaponAsset(hash, 31, 0)
    local deadline = GetGameTimer() + ASSET_WAIT_MS
    while not assetLoaded(hash) do
        if GetGameTimer() > deadline then return false end
        Wait(0)
    end
    return true
end

-- RedM (spur_gunny, 24 Nov 2026): GIVE_WEAPON_TO_PED called here with bIgnoreUnlocks on (rdr_compat's GiveWeaponToPed
-- has it off). With it off, /gunnygivelab showed an Elephant Rifle in the hand at once but in the player's own
-- inventory (HAS_PED_GOT_WEAPON, inventory only) only some time under 500 ms later. A draw looked at in between was
-- read as taken away (weaponGone, below), which is what put a Carcano, a Springfield and an Elephant Rifle straight
-- back. With it on, the gun is in the inventory at once. The inventory decides who may carry what, not RDR2's unlocks.
local GIVE_WEAPON_TO_PED, ADD_REASON_DEFAULT = 0x5E3BDDBCB83F3D84, GetHashKey('ADD_REASON_DEFAULT')

--- Give the weapon to the ped and put it in the hand at once.
local function giveToHand(ped, hash, ammo)
    Citizen.InvokeNative(GIVE_WEAPON_TO_PED, ped, hash, math.floor(tonumber(ammo) or 0), true, false, 0, false, 0.5, 1.0,
        ADD_REASON_DEFAULT, true, 0.0, false)                   -- forced into the hand, unlocks ignored
    SetCurrentPedWeapon(ped, hash, true, 0, false, false)       -- equipNow: no draw to wait out
    SetPedInfiniteAmmo(ped, false, hash)
    SetPedInfiniteAmmoClip(ped, false)
    SetPedCurrentWeaponVisible(ped, true, false, false, false)
end

--- Draw the weapon in this pocket slot. Waits; answers true (drawn, or already was) or false and why.
---@return boolean ok
---@return string|nil why
function DrawWeapon(slot, pocket)
    pocket = pocket or 'player'
    if isDrawn(slot, pocket) then return true end
    if equipInProgress() then return false, 'Already drawing a weapon' end
    if GunnyReloadUnderWay() then   -- client/reload.lua: the gun in hand is not put away for it
        GunnyNotify('Finish reloading first', 'error')
        return false, 'Finish reloading first'
    end
    -- A resource has blocked the hands, or weapons (spur_core's BlockHands): a no-weapons zone, a restraint.
    local blocked, why = Whip.core:AreHandsBlocked('weapon')
    if blocked == true then
        GunnyNotify(why, 'error')
        return false, why
    end

    -- Another weapon out: away first (waits out the game's holster). The latch goes on before, so nothing starts
    -- between.
    isEquipping, equipStartedAt = true, GetGameTimer()
    if CurrentWeapon then GunnyHolster() end
    if CurrentWeapon then isEquipping = false; return false, 'The weapon in hand did not go away' end

    local draw = {}
    drawing = draw
    local success, drawn = GunnyCallback('spur_gunny:equipWeapon', GunnySlot(slot, pocket))
    -- RedM (spur_gunny, 24 Nov 2026): the gun's asset loaded before it is given (loadWeaponAsset), while the server's
    -- word on this draw is still kept. Not loaded in time: given anyway, and said.
    if success and type(drawn) == 'table' and drawn.hash and not loadWeaponAsset(Config.U32(drawn.hash)) then
        GunnyDebugPrint('Equip: the weapon asset did not load in time', drawn.hash)
    end
    drawing = nil
    if not success then
        local refused = type(drawn) == 'string' and drawn or 'Cannot equip weapon'
        GunnyNotify(refused, 'error')
        isEquipping = false
        return false, refused
    end
    local hash, ammo = Config.U32(drawn.hash), math.max(0, math.floor(tonumber(drawn.ammo) or 0))
    GunnyDebugPrint('Equip', slot, pocket, '- server:', hash, ammo, drawn.kind)

    local weaponName = weaponByHash(hash)
    local weaponConfig = weaponName and Config.Weapons[weaponName] or nil
    if not weaponConfig then
        -- The server has it drawn: it goes back there too, or the record and the held item would stay.
        tellHolstered(ammo, drawn.countVersion)
        GunnyNotify('Unknown weapon', 'error')
        isEquipping = false
        return false, 'Unknown weapon'
    end

    -- Died, or the server took it back, during the round trip: put away there too, and nothing is given.
    if Whip.core:IsPlayerDead() == true or draw.holster then
        if not tellHolstered(ammo, drawn.countVersion) then
            GunnyDebugPrint('Holster after a called-off draw: the server had no record')
        end
        isEquipping = false
        return false, draw.holster and 'The weapon left its slot' or 'Dead'
    end
    local ped = PlayerPedId()

    if not IsWeaponValid(hash) then
        tellHolstered(ammo, drawn.countVersion)
        local missing = ('This server\'s game has no %s'):format(weaponConfig.label or weaponName)
        GunnyNotify(missing, 'error')
        isEquipping = false
        return false, missing
    end

    local throwable = Config.IsThrowable(weaponConfig)
    local bow = Config.IsBow(weaponConfig)
    -- A stack or the arrows changed during the draw: the server's newer count (a stack's never above the equip's).
    if draw.count then ammo = throwable and math.min(ammo, draw.count) or (bow and draw.count or ammo) end

    -- The game will not hand over a throwable with none, so a stack is given with its count.
    permitGun(hash, true)
    giveToHand(ped, hash, throwable and ammo or 0)

    local attachments = type(drawn.attachments) == 'table' and drawn.attachments or {}
    CurrentWeapon = {
        slot = slot,
        pocket = pocket,
        name = weaponName,
        hash = hash,
        serial = drawn.serial,
        config = weaponConfig,
        ammo = 0,
        kind = drawn.kind,           -- the cartridge (or arrow) item it is loaded with or set for
        ammoType = drawn.ammoType,   -- that item's game ammunition name
        typeHash = nil,              -- set by GunnyAmmo.setKind
        metadata = { attachments = attachments },
        shotsInFlight = 0,           -- shots sent and not yet answered (client/shooting.lua)
        countVersion = drawn.countVersion or 1,
        drawnAt = GetGameTimer(),    -- RedM (spur_gunny, 24 Nov 2026): weaponGone gives a new draw GONE_GRACE_MS
    }
    GunnyStartTick()   -- the weapon can fire from now: its shots are counted from the next frame (client/main.lua)

    -- Its rounds, through client/ammo.lua, the one writer of a ped's ammunition.
    if throwable then
        CurrentWeapon.stackType = Config.U32(GetAmmoTypeForWeapon(hash))
        GunnyAmmo.setStack(ammo)
    elseif Config.IsFirearm(weaponConfig) or bow then
        GunnyAmmo.setKind(drawn.ammoType and Config.Hash(drawn.ammoType) or nil)
        GunnyAmmo.set(ammo, true)
    end
    if Config.IsFirearm(weaponConfig) and GunnyDebugOn then
        local gameClip = GetMaxAmmoInClip(ped, hash, true)
        if gameClip ~= tonumber(weaponConfig.capacity) then
            GunnyDebugPrint(('%s: the item holds %s, the game\'s clip %s'):format(weaponName,
                tostring(weaponConfig.capacity), tostring(gameClip)))
        end
    end
    GunnyDebugPrint('Equipped', weaponName, 'with', ammo, drawn.kind or '')

    isEquipping = false
    runSteps(afterDraw, CurrentWeapon)
    TriggerEvent('spur_gunny:weapon:drawn', GetDrawnWeapon())

    -- Its parts last: a part's model may take a moment to load, and the weapon is gunny's by then.
    if next(attachments) then ApplyWeaponAttachments(ped, hash, weaponName, attachments) end
    return true
end

--- The drawn weapon out of the hands and forgotten here (`remove` false: the game already took it). Its kind's pool
--- is emptied too: a pool belongs to the kind, not the weapon. Answers the record it was.
---@param ped number
---@param remove boolean
---@return table gun
local function letGo(ped, remove)
    local gun = CurrentWeapon
    ---@cast gun -nil   -- called only with a weapon drawn
    GunnyAmmo.dropReload()
    if remove then RemoveWeaponFromPed(ped, gun.hash) end   -- rdr_compat: REMOVE_WEAPON_FROM_PED
    local pool = gun.typeHash or gun.stackType
    if pool then GunnyAmmo.setPool(ped, pool, 0) end   -- RedM (spur_gunny, 24 Nov 2026): the way that sticks (client/ammo.lua)
    permitGun(gun.hash, false)
    CurrentWeapon = nil
    runSteps(afterHolster, gun)
    TriggerEvent('spur_gunny:weapon:holstered', { item = gun.name, slot = gun.slot, pocket = gun.pocket })
    return gun
end

--- Firing held off while a weapon goes away, on foot, in the saddle and in a seat (spur_core's control blocks). The
--- server is told the count as the holster starts, and a shot after that would have no draw to be charged to.
local AWAY_BLOCK = 'gunGoingAway'
local fireHeld = false
local function holdFire(on)
    if on == fireHeld then return end
    fireHeld = on
    local ok, why
    if on then ok, why = Whip.core:BlockControls(AWAY_BLOCK, { groups = { 'combat', 'vehicleCombat' } })
    else ok, why = Whip.core:UnblockControls(AWAY_BLOCK) end
    if ok ~= true then GunnyDebugPrint('Holster: the fire keys could not be', on and 'held' or 'let go', why) end
end

--- The last shots and throws before the count is read.
local function settle(ped)
    GunnyThrowSettle(ped)   -- client/throwables.lua
    GunnyShotSettle(ped)    -- client/shooting.lua
end

-- The game's holster: at least this long, and no longer than the most, while the weapon is on its way.
local HOLSTER_MIN_MS, HOLSTER_MAX_MS = 100, 1500

--- Holster: the body, run one at a time by GunnyHolster.
---@param serverDropped boolean|nil  the server has already put it away (spur_gunny:client:forceHolster)
---@param now boolean|nil  out of the hands at once, even mid-reload: dying, or the hands blocked
local function holsterInner(serverDropped, now)
    if not CurrentWeapon then return end
    local ped = PlayerPedId()

    if serverDropped then
        letGo(ped, true)
        return
    end

    if now then
        settle(ped)
        if not CurrentWeapon then return end
        local ammo, countVersion = CurrentWeapon.ammo, CurrentWeapon.countVersion
        letGo(ped, true)
        if not tellHolstered(ammo, countVersion) then
            print('[GUNNY] WARNING: the server refused the holster, ammo may not have saved')
        end
        return
    end

    if GunnyReloadUnderWay() then
        GunnyNotify('Finish reloading first', 'error')
        return
    end

    -- Nothing fires from here on, so the count read next is the last one.
    holdFire(true)
    settle(ped)
    if not CurrentWeapon then return end
    local ammo = CurrentWeapon.ammo

    -- The game's own holster, and the server told while it plays. Refused, it is put away anyway (a weapon left out is
    -- worse), and said.
    local startedAt = GetGameTimer()
    SetCurrentPedWeapon(ped, UNARMED, false, 0, false, false)
    if not tellHolstered(ammo, CurrentWeapon and CurrentWeapon.countVersion or 0) then
        print('[GUNNY] WARNING: server refused the holster, putting the weapon away anyway; ammo may not have saved')
    end
    while GetGameTimer() - startedAt < HOLSTER_MIN_MS
        or (IsWeaponHolsterStateChanging(ped) and GetGameTimer() - startedAt < HOLSTER_MAX_MS) do
        Wait(0)
    end

    if not CurrentWeapon then return end
    letGo(ped, true)
    GunnyDebugPrint('Holstered weapon')
end

--- One holster at a time (two can arrive together: a forceHolster as the player dies). The one under way, as a
--- promise a second caller waits on.
local holstering = nil

--- Is the drawn weapon on its way out of the hands? R does nothing meanwhile (client/reload.lua).
---@return boolean
function GunnyPuttingAway()
    return holstering ~= nil
end

---@param serverDropped boolean|nil
---@param now boolean|nil
function GunnyHolster(serverDropped, now)
    if holstering then
        Citizen.Await(holstering)
        return
    end
    local done = promise.new()
    holstering = done
    local ok, err = pcall(holsterInner, serverDropped, now)
    holdFire(false)   -- every way out, an error too
    holstering = nil
    done:resolve(true)
    if not ok then print('[GUNNY] holster failed: ' .. tostring(err)) end
end

--- The inventory's Equip: draw it, or put it away if it is the one drawn.
local function toggleDraw(slot, pocket)
    pocket = pocket or 'player'
    if isDrawn(slot, pocket) then
        GunnyHolster()
    else
        DrawWeapon(slot, pocket)
    end
end

exports('DrawWeapon', function(slot, pocket) return DrawWeapon(slot, pocket) end)

-- The drawn weapon left the slot it was drawn from (dragged away, stashed, handed over): the server has let it go.
RegisterNetEvent('spur_gunny:client:forceHolster', function()
    if CurrentWeapon then GunnyHolster(true) else GunnyDrawNote('holster') end
end)

-- A logout puts it away, so the next character does not start with this one's weapon. The server already let it go.
AddEventHandler('spur_core:player:logout', function()
    if CurrentWeapon then GunnyHolster(true) else GunnyDrawNote('holster') end
end)
AddEventHandler('spur_core:player:died', function()
    if CurrentWeapon then GunnyHolster(false, true) end
end)
-- The hands were blocked with a weapon out: put away with the game's holster, or at once when a reload is under way.
AddEventHandler('spur_core:hands:blocked', function()
    if CurrentWeapon then
        CreateThread(function() GunnyHolster(false, GunnyReloadUnderWay()) end)
    else
        GunnyDrawNote('holster')
    end
end)

-- Equip from the inventory (the context action, server/items.lua). The third value (picked up off the ground) means
-- nothing here: every draw is straight into the hand.
RegisterNetEvent('spur_gunny:client:useWeapon', function(slot, pocket)
    toggleDraw(slot, pocket)
end)

-- ============================================
-- THE SERVER CHANGED THE DRAWN GUN'S LOAD (server/reload.lua: Unload, Switch Cartridges, an undone unload)
-- ============================================

RegisterNetEvent('spur_gunny:client:loadChanged', function(slot, pocket, ammo, kind, countVersion)
    local w = CurrentWeapon
    if not w or w.slot ~= slot or w.pocket ~= (pocket or 'player') then return end
    if not Config.IsFirearm(w.config) then return end
    -- A shot since the last frame is counted first, against the old count and kind; then the server's word stands.
    -- (It does nothing while a reload plays.)
    GunnyShotSettle(PlayerPedId(), GetGameTimer())
    if CurrentWeapon ~= w then return end
    w.countVersion = tonumber(countVersion) or w.countVersion
    ammo = math.max(0, math.floor(tonumber(ammo) or 0))
    local a = kind and Config.GetAmmo(kind)
    local newKind = a and kind ~= w.kind
    if a then w.kind, w.ammoType = kind, a.type end
    -- A reload playing: the count only (Unload and Switch wait for one, so this is rare); it ends from this count.
    if GunnyAmmo.reloading() then
        w.ammo = ammo
        return
    end
    if newKind then GunnyAmmo.setKind(Config.Hash(a.type)) end
    GunnyAmmo.set(ammo, newKind)
end)

-- ============================================
-- TAKEN OUT OF THE HANDS BY SOMETHING ELSE
-- ============================================
--
-- Another script, or the game with a throwable's last one thrown: put away here and on the server, with the count
-- kept. Looked at once a second, on the tick. Leaving its slot is the server's to see (server/weapons.lua).

local GONE_CHECK_MS = 1000
-- RedM (spur_gunny, 24 Nov 2026): not looked at in a draw's first moments, while the game may still be filing the gun
-- in the player's inventory (giveToHand, above).
local GONE_GRACE_MS = 1500
local goneCheckAt = 0

RegisterGunnyTick('weaponGone', function(ped, now)
    if now < goneCheckAt then return end
    if now - (CurrentWeapon.drawnAt or 0) < GONE_GRACE_MS then return end
    goneCheckAt = now + GONE_CHECK_MS
    if HasPedGotWeapon(ped, CurrentWeapon.hash, 0, true) then return end
    GunnyDebugPrint('Weapon removed from ped - force holstering')
    settle(ped)
    if not CurrentWeapon then return end
    local gun = letGo(ped, false)
    CreateThread(function() tellHolstered(gun.ammo, gun.countVersion) end)   -- its own thread: the call waits
end)

-- Stopping: the weapon goes too, so it does not stay in the hand with nothing tracking it.
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    local w = CurrentWeapon
    if w and w.hash then
        local ped = PlayerPedId()
        RemoveWeaponFromPed(ped, w.hash)
        local pool = w.typeHash or w.stackType
        if pool then GunnyAmmo.setPool(ped, pool, 0) end   -- RedM (spur_gunny, 24 Nov 2026): the way that sticks
    end
    CurrentWeapon = nil
end)
