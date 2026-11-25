-- spur_gunny: RELOADING AND CHECKING THE AMMO (client)
--
-- R (B on a controller) loads loose cartridges from the pockets into the drawn gun, with the game's own reload. G
-- (LB + B) says how full it is.
--
-- RedM (spur_gunny, 24 Nov 2026): rewritten. There are no magazines. The server says how many cartridges may go in and
-- of which kind (spur_gunny:beginReload); the game's reload plays, a cartridge at a time or all at once as RDR2 does it
-- for that gun, and the player may stop it partway by firing; how many went in goes back as it ends
-- (spur_gunny:server:reloadEnded), and only those are taken from the pockets. RDR2 reloads in the saddle and on a wagon,
-- so R works there too. The last round fired reloads by itself (Config.Reload.autoWhenEmpty).
--
-- Firing stops the moment a reload is asked for and comes back as the game's reload begins: from then a shot stops the
-- reload, and is counted. From the press to the end (GunnyReloadUnderWay), an ordinary holster and a draw are refused (a
-- death or a block still puts the gun away at once).

local isReloading = false

--- From the press (GunnyStartReload) until the reload's thread ends.
local underWay = false

--- Is a reload under way, asked for or playing? (client/weapons.lua refuses an ordinary holster and a draw meanwhile.)
---@return boolean
function GunnyReloadUnderWay()
    return underWay or isReloading or GunnyAmmo.reloading()
end

-- Firing held off while the server answers (spur_core's control blocks): on foot, and from the saddle or a seat.
local FIRE_BLOCK = 'gunReloading'
local FIRE_CONTROLS = { 24, 257, 69, 70, 92 }   -- attack and attack 2; a driver's two; a passenger's
local fireHeld = false

local function holdFire(on)
    if on == fireHeld then return end
    fireHeld = on
    local ok, why
    if on then ok, why = Whip.core:BlockControls(FIRE_BLOCK, { controls = FIRE_CONTROLS })
    else ok, why = Whip.core:UnblockControls(FIRE_BLOCK) end
    if ok ~= true then GunnyDebugPrint('Reload: the fire keys could not be', on and 'held' or 'let go', why) end
end

--- Start a reload: R, B on a controller, the last round fired, an empty gun's trigger in the saddle. Firing stops
--- here, before the reload's own thread runs, so no shot from after the press reaches the server after the ask.
---@param quiet boolean|nil  a refusal is not said (the automatic reload: the gun clicking empty says it)
function GunnyStartReload(quiet)
    if isReloading or underWay then return end
    if GunnyPuttingAway() then return end   -- the gun is going away: it is not reloaded on its way out
    if not (CurrentWeapon and Config.IsFirearm(CurrentWeapon.config)) then return end
    underWay = true
    holdFire(true)
    CreateThread(function() GunnyReload(quiet) end)
end

-- How the last one ended, and the promise reloadNow waits on while one plays.
local reloadEnd = nil
local reloadWait = nil

local function endReloadWait()
    local p = reloadWait
    reloadWait = nil
    if p then p:resolve(true) end
end

local function say(quiet, text, kind)
    if not quiet then GunnyNotify(text, kind or 'error') end
end

local function reloadNow(quiet)
    local gun = CurrentWeapon
    if not gun or not Config.IsFirearm(gun.config) then return end
    if isReloading then return end
    isReloading = true

    local capacity = math.max(0, math.floor(tonumber(gun.config.capacity) or 0))
    local ped = PlayerPedId()
    if (gun.ammo or 0) >= capacity then
        -- Full. Rounds kept beyond the game's clip (an item that holds more than it) go in with the game's own reload,
        -- with nothing asked of the server: they are the gun's already.
        if GunnyAmmo.reserve(ped) > 0 then MakePedReload(ped) else say(quiet, 'Already fully loaded', 'info') end
        isReloading = false
        return
    end

    local ok, result = GunnyCallback('spur_gunny:beginReload', GunnySlot(gun.slot, gun.pocket))
    if not ok then
        say(quiet, type(result) == 'string' and result or 'Cannot reload')
        isReloading = false
        return
    end
    -- Put away, or another drawn, while the server answered: nothing is reported, and the server takes nothing.
    if CurrentWeapon ~= gun then isReloading = false; return end

    -- An empty gun takes the kind the server picked (the first of its group carried).
    local a = Config.GetAmmo(result.kind)
    if a and result.kind ~= gun.kind then
        gun.kind, gun.ammoType = result.kind, a.type
        GunnyAmmo.setKind(Config.Hash(a.type))
        GunnyAmmo.set(gun.ammo, true)
    end

    -- Shots taken meanwhile make more room, never more than the server allowed.
    local room = math.min(math.floor(tonumber(result.room) or 0), capacity - GunnyAmmo.count())
    if room <= 0 then
        TriggerServerEvent('spur_gunny:server:reloadEnded', 0)
        isReloading = false
        return
    end

    reloadEnd = nil
    reloadWait = promise.new()
    local waiting = reloadWait
    if not GunnyAmmo.startReload(room) then
        TriggerServerEvent('spur_gunny:server:reloadEnded', 0)
        endReloadWait()
        isReloading = false
        return
    end
    GunnyDebugPrint('Reload begins - room for', room, result.kind)
    Citizen.Await(waiting)

    GunnyDebugCounts.lastReloadAt = GetGameTimer()
    if CurrentWeapon ~= gun then
        -- Put away mid-reload (dying): the gun keeps what it had, and nothing is taken.
        GunnyAmmo.dropReload()
        isReloading = false
        return
    end
    -- Ended or stopped, the ped is left as it is: clearing its tasks would cut the aim or the run it was stopped for.
    -- Only one stuck past the time out is ended.
    if reloadEnd and reloadEnd.timedOut then GunnyAmmo.endAnimation(PlayerPedId()) end
    GunnyDebugPrint('Reload ended -', reloadEnd and reloadEnd.loaded or 0, 'in,', GunnyAmmo.count(), 'rounds')
    isReloading = false
end

--- Every frame, from the shooting tick before it counts a shot: a reload ends in the frame it ends, so the server hears
--- what went in before the shot that stopped it.
function GunnyReloadTick(ped, now)
    if not GunnyAmmo.reloading() then
        if reloadWait then endReloadWait() end   -- ended without a word (the gun changed under it)
        return
    end
    if fireHeld and GunnyAmmo.reloadSeen() then holdFire(false) end   -- from here a shot stops it
    -- Its own pcall: a failure here must not leave a reload open, which would stop shots being counted.
    local ok, loaded, cutShort, timedOut = pcall(GunnyAmmo.reloadFrame, ped, now)
    if not ok then
        print(('[GUNNY] reload failed: %s'):format(tostring(loaded)))
        GunnyAmmo.dropReload()
        GunnyAmmo.set(GunnyAmmo.count())   -- the reserve goes; the gun keeps what it had
        TriggerServerEvent('spur_gunny:server:reloadEnded', 0)
        endReloadWait()
        return
    end
    if not loaded then return end
    reloadEnd = { loaded = loaded, cutShort = cutShort, timedOut = timedOut }
    TriggerServerEvent('spur_gunny:server:reloadEnded', loaded)
    GunnyAmmo.reconcile(ped)
    endReloadWait()
end

-- The gun put away mid-reload: whoever waits on it is told.
GunnyAfterHolster(endReloadWait)

--- The reload's thread (GunnyStartReload). Under a pcall: an error part way must not leave the latches on. Firing comes
--- back once it is over, however it ended.
function GunnyReload(quiet)
    local ok, err = pcall(reloadNow, quiet)
    if not ok then
        print(('[GUNNY] reload failed: %s'):format(tostring(err)))
        if GunnyAmmo.reloading() then
            GunnyAmmo.dropReload()
            TriggerServerEvent('spur_gunny:server:reloadEnded', 0)
        end
        endReloadWait()
        isReloading = false
        if CurrentWeapon then GunnyAmmo.set(GunnyAmmo.count()) end   -- the ped as the count says, no reserve left
    end
    underWay = false
    if not isReloading then holdFire(false) end
end

-- The server took fewer cartridges than went in (they left the pockets mid-reload): the gun holds what was paid for.
RegisterNetEvent('spur_gunny:client:reloadShort', function(slot, pocket, ammo)
    if not CurrentWeapon or CurrentWeapon.slot ~= slot or CurrentWeapon.pocket ~= (pocket or 'player') then return end
    ammo = math.max(0, math.floor(tonumber(ammo) or 0))
    if ammo >= GunnyAmmo.count() then return end
    if GunnyAmmo.reloading() then CurrentWeapon.ammo = ammo return end
    GunnyShotSettle(PlayerPedId())   -- a shot since the last frame is counted from the old count first
    if ammo < GunnyAmmo.count() then GunnyAmmo.set(ammo) end
end)

RegisterCommand('+gunny_reload', function()
    if not CurrentWeapon then return end
    -- Guns only, silently: with a bow or a knife R is the game's own.
    if not Config.IsFirearm(CurrentWeapon.config) then return end
    if isReloading then return end
    -- Not while a bar, a screen or anything else owns the keys.
    if Whip.core:IsGameInputFree() ~= true then return end
    GunnyStartReload()
end, false)
RegisterCommand('-gunny_reload', function() end, false)
RegisterKeyMapping('+gunny_reload', 'Reload Weapon', 'keyboard', 'r')

-- ============================================
-- THE GAME'S OWN RELOAD AND MELEE, HELD OFF WITH A GUN IN HAND
-- ============================================
--
-- The game's R would reload from a pool gunny keeps empty, and its melee would pistol-whip. Held through spur_core's
-- control blocks. E is not: prompts read it.

local GUN_BLOCK = 'gunInHand'
local GUN_CONTROLS = { 45, 140, 141, 142, 143 }   -- reload, melee light / heavy / alternate, melee block
local gunKeysHeld = false
local blockRefusalSaid = false

local function holdGunKeys(on)
    on = on == true
    if on == gunKeysHeld then return end
    local ok, why
    if on then ok, why = Whip.core:BlockControls(GUN_BLOCK, { controls = GUN_CONTROLS })
    else ok, why = Whip.core:UnblockControls(GUN_BLOCK) end
    if ok == true or not on then
        gunKeysHeld = on
    elseif not blockRefusalSaid then
        blockRefusalSaid = true
        print('[GUNNY] the reload and pistol-whip keys could not be held off: ' .. tostring(why))
    end
end

RegisterGunnyTick('controlBlock', function(ped)
    local inHand = Config.U32(GetSelectedPedWeapon(ped)) == CurrentWeapon.hash
    holdGunKeys(inHand and Config.IsFirearm(CurrentWeapon.config))
end)

-- Put away mid-reload (a death, a forced holster): firing comes back now.
GunnyAfterHolster(function() holdGunKeys(false); holdFire(false) end)

-- On a controller, B on foot reloads: a pad action of spur_core's, which presses +gunny_reload as R does. Ready only
-- while a gun is drawn.
local function gunDrawn() return CurrentWeapon ~= nil and Config.IsFirearm(CurrentWeapon.config) == true end
Whip.register(function()
    local ok, why = exports.spur_core:RegisterPadAction('gunny_reload', {
        label = 'Reload', command = '+gunny_reload', slot = 'foot_b', where = 'foot', ready = gunDrawn(),
    })
    if not ok then print('[GUNNY] no reload on the controller: ' .. tostring(why)) end
end)
GunnyAfterDraw(function() Whip.core:SetPadActionReady('gunny_reload', gunDrawn()) end)
GunnyAfterHolster(function() Whip.core:SetPadActionReady('gunny_reload', false) end)

-- ============================================
-- G: CHECKING THE AMMO
-- ============================================
--
-- RedM (spur_gunny, 24 Nov 2026): a reading only. No borrowed reload animation (the game's reload would load from the
-- pool), and nothing to set off: dynamite and fire bottles are lit and thrown, not detonated.

local function ammoDescription(current, capacity)
    if capacity <= 0 then return 'It holds nothing.' end
    local percent = (current / capacity) * 100
    if percent >= 100 then return 'Full.'
    elseif percent >= 80 then return 'Almost full...'
    elseif percent >= 60 then return 'More than half...'
    elseif percent >= 40 then return 'Roughly half...'
    elseif percent >= 20 then return 'Less than half...'
    elseif percent >= 10 then return 'Looking low...'
    elseif percent >= 1 then return 'Basically empty...'
    else return 'Empty.' end
end

local function checkAmmo()
    local gun = CurrentWeapon
    if not gun or not Config.IsFirearm(gun.config) then return end
    local capacity = math.max(0, math.floor(tonumber(gun.config.capacity) or 0))
    local current = gun.ammo or 0
    local text = ammoDescription(current, capacity)
    if current > 0 and gun.kind then text = ('%s (%s)'):format(text, Config.AmmoLabel(gun.kind)) end
    GunnyNotify(text, 'info')
    GunnyDebugPrint('Ammo check:', current, '/', capacity, gun.kind or '')
end

RegisterCommand('+gunny_check_ammo', function()
    if Whip.core:IsGameInputFree() ~= true then return end
    if isReloading then return end
    checkAmmo()
end, false)
RegisterCommand('-gunny_check_ammo', function() end, false)
RegisterKeyMapping('+gunny_check_ammo', 'Check Ammo', 'keyboard', 'g')

-- On a controller: LB + B, unless the player moved it.
Whip.register(function()
    local ok, why = exports.spur_core:RegisterPadAction('gunny_check_ammo', {
        label = 'Check ammo', command = '+gunny_check_ammo', slot = 'lb_b',
    })
    if not ok then print('[GUNNY] no check ammo on the controller: ' .. tostring(why)) end
end)
