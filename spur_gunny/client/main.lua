-- spur_gunny: THE CLIENT'S FOUNDATION
--
-- Asking the server, the drawn weapon, debug lines, and the one per-frame thread every gun-in-hand job runs on.
--
-- Calling spur_core, the one rule in every client file:
--   inside Whip.register (registrations) its exports are called straight: those run only while it is up;
--   so is the per-frame tick, for speed: it runs only with a weapon drawn, and gunny stops with spur_core (its
--   dependency), so the tick never outlives it;
--   so is a call behind Whip.isReady() that answers at once, with no wait between the two (a weapon pack's item
--   settings, below);
--   everything else goes through Whip.core, which answers `false, why` instead of throwing when spur_core is down,
--   and answers a wait even if spur_core stops meanwhile.
--
-- RedM (spur_gunny, 24 Nov 2026): whip_core -> spur_core, whip_gunny: -> spur_gunny:. The drawn gun carries its kind
-- of cartridge (`kind`, `ammoType`) instead of a magazine; GetDrawnWeapon answers `ammoKind` in place of `magazine`.

--- Ask one of this resource's server callbacks by its full name ('spur_gunny:equipWeapon', server/main.lua), so the
--- name searched for here is the one on the server. Answers what the handler answered, or `false, why` when spur_core
--- refused the call (too far away, asked too often, no answer).
function GunnyCallback(name, ...)
    return Whip.core:Callback(name, ...)
end

--- A pocket slot as one value, for a server handler with spur_core's 'slot' param: spur_core checks the pocket is the
--- player's, the slot is in range, and what is in it, before the handler runs.
---@param slot number
---@param pocket string|nil  'player' (default) or 'accessory'
---@return table
function GunnySlot(slot, pocket)
    return { sub = pocket or 'player', slot = slot }
end

--- The drawn weapon, nil when none: { slot, pocket, name, hash, serial, config, ammo, kind, ammoType, typeHash,
--- metadata, shotsInFlight, countVersion, pedClip } (client/weapons.lua).
CurrentWeapon = nil

--- Gunny Debug is on in /w (client/debug.lua).
GunnyDebugOn = false

--- Gunny Debug's numbers, written where they happen and only read by the overlay (client/debug.lua): shot reports sent
--- and answered, the server's last count and when, answers ignored as stale, counts that went up, the last shot and
--- reload, and the game's own gains that were clamped away. /gunnydebugreset zeroes them.
---@class GunnyDebugCounts
GunnyDebugCounts = { sent = 0, confirmed = 0, staleIgnored = 0, ammoJumps = 0, lastJump = nil,
                     serverAmmo = nil, serverAmmoAt = nil, lastShotAt = nil, lastReloadAt = nil,
                     clipShots = 0, edgeShots = 0, chargedRounds = 0, clampedClip = 0, clampedPool = 0,
                     reloadLowered = 0, sweptWeapons = 0 }

--- A debug line, printed while Gunny Debug is on.
function GunnyDebugPrint(...)
    if GunnyDebugOn then
        print('[GUNNY]', ...)
    end
end

--- Load a model with spur_core's loader (call from a thread): true once it is in, or false, said. Release it with
--- SetModelAsNoLongerNeeded once what needs it is made.
---@return boolean
function GunnyLoadModel(model)
    if HasModelLoaded(model) then return true end
    if type(Whip.core:LoadModel(model, 5000)) == 'number' then return true end
    print('[GUNNY] WARNING: a model did not load: ' .. tostring(model))
    return false
end

--- A notification to this player: 'error' unless said.
function GunnyNotify(msg, kind)
    Whip.core:Notify(msg, kind or 'error')
end

-- A weapon pack's item arriving while spur_core runs: its Items page settings followed here too (shared/catalog.lua
-- follows the rest as spur_core is ready).
GunnyPacks.onChange(function(itemName, _, gone)
    if not gone and Whip.isReady() then Config.FollowItemSettings(nil, itemName) end
end)

-- ============================================
-- THE TICK: one thread for every per-frame job while a weapon is drawn
-- ============================================

local tickFunctions = {}
local tickOrder = {}

--- Run `fn(ped, now)` every frame while a weapon is drawn; `ped` and `now` are read once a frame for all of them.
--- Jobs run in the order they were registered (the files' order in fxmanifest.lua).
---@param name string
---@param fn fun(ped: number, now: number)
function RegisterGunnyTick(name, fn)
    if not tickFunctions[name] then tickOrder[#tickOrder + 1] = name end
    tickFunctions[name] = fn
end

-- Each job in its own pcall, so one error cannot stop shot counting or the control blocks. Said once per job.
local tickFailed = {}
local ticking = false

--- Start the tick: called the moment a weapon is in the hand (DrawWeapon, client/weapons.lua), so its first frame is
--- counted. It ends by itself once nothing is drawn, and the next draw starts it again.
function GunnyStartTick()
    if ticking then return end
    ticking = true
    CreateThread(function()
        while CurrentWeapon do
            local ped, now = PlayerPedId(), GetGameTimer()
            for _, name in ipairs(tickOrder) do
                local ok, err = pcall(tickFunctions[name], ped, now)
                if not ok and not tickFailed[name] then
                    tickFailed[name] = true
                    print(('[spur_gunny] tick "%s" errored: %s'):format(tostring(name), tostring(err)))
                end
                if not CurrentWeapon then break end
            end
            Wait(0)
        end
        ticking = false
    end)
end

-- ============================================
-- EXPORTS
-- ============================================

function IsWeaponDrawn()
    return CurrentWeapon ~= nil
end

--- The drawn weapon as other resources see it, a copy: { item, label, kind, serial, slot, pocket, ammo, capacity,
--- ammoKind, attachments }, or nil. `ammoKind` is the cartridge (or arrow) item it is loaded with or set for;
--- `capacity` the most a gun holds, nil for anything else. A bow's and a throwable's `ammo` is what is carried.
function GetDrawnWeapon()
    local w = CurrentWeapon
    if not w then return nil end
    local attachments = {}
    for category, item in pairs(w.metadata and w.metadata.attachments or {}) do attachments[category] = item end
    return {
        item        = w.name,
        label       = w.config.label,
        kind        = Config.KindOf(w.config),
        serial      = w.serial,
        slot        = w.slot,
        pocket      = w.pocket,
        ammo        = w.ammo or 0,
        capacity    = Config.IsFirearm(w.config) and tonumber(w.config.capacity) or nil,
        ammoKind    = w.kind,
        attachments = attachments,
    }
end

exports('IsWeaponDrawn', IsWeaponDrawn)
exports('GetDrawnWeapon', GetDrawnWeapon)

-- ============================================
-- SPUR_CORE'S MOMENTS
-- ============================================
--
-- spur_core names moments (give mode, something needing the hands) and gunny answers them, so spur_core never needs
-- to know gunny exists. Through Whip.register: spur_core forgets them when it restarts.

local function RegisterClientWithCore()
    -- Mid-reload an ordinary holster is refused ('Finish reloading first'). With the hands blocked (cuffs) the gun goes
    -- at once, as spur_core:hands:blocked puts it away in client/weapons.lua, with nothing said.
    local function holsterFirst()
        if not IsWeaponDrawn() then return end
        GunnyHolster(false, GunnyReloadUnderWay() and Whip.core:AreHandsBlocked() == true)
    end

    local ok, why = exports.spur_core:RegisterClientHook('beforeGiveMode', holsterFirst)
    if not ok then print('[GUNNY] could not register the beforeGiveMode hook: ' .. tostring(why)) end

    -- Something else needs the hands (spur_core's FreeHands).
    ok, why = exports.spur_core:RegisterClientHook('freeHands', holsterFirst)
    if not ok then print('[GUNNY] could not register the freeHands hook: ' .. tostring(why)) end
end

Whip.register(RegisterClientWithCore)
