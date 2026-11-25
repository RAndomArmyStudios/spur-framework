-- spur_gunny: SHOTS (client)
--
-- The client counts shots; the server decides the round count. Both client corrections (the periodic sync here and the
-- holster's count) are accepted only when lower: firing only lowers a count, so a higher claim would be a free reload.
--
-- RedM (spur_gunny, 24 Nov 2026): a shot is what left the ped. Every frame the drawn gun's total (its pool, and the clip
-- when the pool is apart from it: client/ammo.lua) is read against the last; a drop is rounds fired, and each is
-- reported (spur_gunny:server:shotFired, at most 10 a report). A rise outside a reload is the game handing out rounds
-- (looted, picked up) and is taken back off the ped. Should the game fire with no drop (IsPedShooting, and nothing off
-- the ped within EDGE_MS), one round is charged. The same on foot, in the saddle and on a wagon. No jerry can.

local SYNC_INTERVAL = 5000
local lastSyncedAmmo = -1
local lastSyncTime = 0

-- IsPedShooting with no round off the ped by then: one round charged (GunnyDebugCounts.edgeShots).
local EDGE_MS = 400
local lastDropAt = 0
local shotSeenAt = nil

--- Report rounds fired, at most 10 a report (the server's schema), each answered by spur_gunny:client:syncAmmo.
local function report(rounds, now)
    local dbg = GunnyDebugCounts
    while rounds > 0 do
        local part = math.min(rounds, 10)
        TriggerServerEvent('spur_gunny:server:shotFired', part)
        CurrentWeapon.shotsInFlight = CurrentWeapon.shotsInFlight + 1
        dbg.sent = dbg.sent + 1
        dbg.chargedRounds = dbg.chargedRounds + part
        rounds = rounds - part
    end
    dbg.lastShotAt = now
end

--- The last round left: the gun reloads by itself if the server says it may (quietly: the gun clicking empty says
--- it), on foot, in the saddle and in a seat.
local function emptied()
    if Config.Reload and Config.Reload.autoWhenEmpty then GunnyStartReload(true) end
end

--- Count what left the drawn gun since the last look. Called every frame, and once more before anything else
--- writes the ped's ammunition (a holster, an answer from the server), so a shot in between is never written over.
---@param ped number
---@param now number|nil
function GunnyShotSettle(ped, now)
    local w = CurrentWeapon
    if not w or not Config.IsFirearm(w.config) or not w.typeHash then return end
    if GunnyAmmo.reloading() then return end   -- its rounds are counted as it ends (client/ammo.lua)
    now = now or GetGameTimer()
    local total = GunnyAmmo.total(ped)
    local known = w.pedTotal or total
    if total < known then
        local spent = known - total
        w.pedTotal = total
        local charged = math.min(spent, w.ammo or 0)
        w.ammo = math.max(0, (w.ammo or 0) - spent)
        lastDropAt, shotSeenAt = now, nil
        GunnyDebugCounts.clipShots = GunnyDebugCounts.clipShots + spent
        if charged > 0 then report(charged, now) end
        GunnyDebugPrint('Fired', spent, '- Ammo left:', w.ammo)
        GunnyAmmo.reconcile(ped)   -- more on the ped than the count, or a kind the game switched to
        if w.ammo == 0 and CurrentWeapon == w then emptied() end
    elseif total > known then
        GunnyAmmo.reconcile(ped)   -- the game handed out rounds: not kept
    end
end

RegisterGunnyTick('shooting', function(ped, now)
    local w = CurrentWeapon
    local cfg = w.config
    if Config.IsMelee(cfg) then return end
    -- A throwable is thrown and an arrow shot: counted off the game's own count (client/throwables.lua).
    if Config.IsThrowable(cfg) or Config.IsBow(cfg) then return GunnyThrowSettle(ped) end

    -- A reload ends in the frame it ends: what went in is told before the shot that stopped it (client/reload.lua).
    GunnyReloadTick(ped, now)
    if CurrentWeapon ~= w then return end

    GunnyShotSettle(ped, now)
    if CurrentWeapon ~= w then return end

    if not GunnyAmmo.reloading() then
        -- The game fired and nothing came off the ped: one round charged, and the ped set to the count.
        if IsPedShooting(ped) and (w.ammo or 0) > 0 and now - lastDropAt > EDGE_MS and not shotSeenAt then
            shotSeenAt = now
        end
        if shotSeenAt and now - shotSeenAt >= EDGE_MS then
            shotSeenAt = nil
            if (w.ammo or 0) > 0 then
                GunnyDebugCounts.edgeShots = GunnyDebugCounts.edgeShots + 1
                GunnyAmmo.set(w.ammo - 1)
                report(1, now)
                GunnyDebugPrint('A shot with no round off the ped: charged one - Ammo left:', w.ammo)
                if w.ammo == 0 then emptied() end
            end
        end
    end

    -- The periodic sync: a backup, only when the count changed.
    if now - lastSyncTime >= SYNC_INTERVAL then
        lastSyncTime = now
        if not GunnyAmmo.reloading() and w.ammo ~= lastSyncedAmmo then
            lastSyncedAmmo = w.ammo
            local said = GunnyDebugCounts.serverAmmo
            if said and w.ammo < said then
                GunnyDebugPrint('5 s sync sends', w.ammo, 'below the server\'s last', said, 'with',
                    w.shotsInFlight, 'shots unanswered')
            end
            TriggerServerEvent('spur_gunny:server:syncAmmo', w.ammo, w.countVersion)
        end
    end
end)

-- The server's count after each shot it took (server/shooting.lua), one answer per report sent.
RegisterNetEvent('spur_gunny:client:syncAmmo', function(ammo, countVersion)
    local dbg = GunnyDebugCounts
    ammo = math.max(0, math.floor(tonumber(ammo) or 0))
    dbg.serverAmmo, dbg.serverAmmoAt, dbg.confirmed = ammo, GetGameTimer(), dbg.confirmed + 1

    local w = CurrentWeapon
    if not w or not Config.IsFirearm(w.config) then return end
    w.shotsInFlight = math.max(0, w.shotsInFlight - 1)
    -- An answer for a count before the server's last change to the gun: about another load.
    if countVersion and tonumber(countVersion) ~= w.countVersion then return end

    -- A shot since the last frame is counted first, so the answer is not written over it.
    GunnyShotSettle(PlayerPedId())
    local current = w.ammo or 0

    -- During fast fire each answer describes the gun some shots ago: a higher count while shots are still unanswered is
    -- old, and ignored. A lower one always applies: the server is the authority.
    if ammo > current and w.shotsInFlight > 0 then
        dbg.staleIgnored = dbg.staleIgnored + 1
        return
    end
    if ammo == current then return end

    if ammo > current then
        local reloadRecently = GunnyAmmo.reloading()
            or (dbg.lastReloadAt and (GetGameTimer() - dbg.lastReloadAt) < 1500)
        if not reloadRecently then
            dbg.ammoJumps = dbg.ammoJumps + 1
            dbg.lastJump = { from = current, to = ammo, at = GetGameTimer() }
        end
    end

    -- A reload playing: the count only; it ends from this count (client/ammo.lua).
    if GunnyAmmo.reloading() then
        if ammo < current then dbg.reloadLowered = dbg.reloadLowered + (current - ammo) end
        w.ammo = ammo
        return
    end
    GunnyAmmo.set(ammo)
end)

-- A new weapon in the hand, or none: the sync starts over.
GunnyAfterDraw(function()
    lastSyncTime = GetGameTimer()
    lastSyncedAmmo = -1
    lastDropAt, shotSeenAt = 0, nil
end)

GunnyAfterHolster(function()
    lastSyncedAmmo = -1
    shotSeenAt = nil
end)
