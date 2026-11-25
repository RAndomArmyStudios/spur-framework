-- spur_gunny: GUNNY DEBUG, the drawn weapon's numbers on screen
--
-- Switched from /w (Debug -> Gunny Debug, developer mode). While it is on, this game and the server print gunny's
-- GunnyDebugPrint lines too.
--
-- Three counts of the same rounds, side by side: the GAME's (the clip and the pool, read every frame), the CLIENT's
-- (gunny's own count), and the SERVER's (pushed after every shot, spur_gunny:client:syncAmmo). What the player carries
-- for the weapon needs a round trip, so it is asked every 100 frames and its age is shown. Shots sent against shots
-- confirmed is what shows a shot lost on the way.
--
-- RedM (spur_gunny, 24 Nov 2026): RDR2's text natives; the pool shown beside the clip, the rounds the game handed out
-- and gunny took back, and the weapons the guard swept; cartridges carried in place of magazines. /gunnyammoprobe
-- prints what the game says about the drawn weapon's ammunition.

local overlayOn = false

local invData, invPolledAt = {}, 0
local isPolling = false

local ammoHistory, AMMO_HISTORY_MAX = {}, 12
local lastRecordedServerAmmo = nil

local function devOnly()
    if Whip.core:HasDevTools() ~= true then
        GunnyNotify('That needs developer mode on (/w)', 'error')
        return false
    end
    return true
end

local function zeroCounts(dbg)
    dbg.sent, dbg.confirmed, dbg.staleIgnored, dbg.ammoJumps, dbg.lastJump = 0, 0, 0, 0, nil
    dbg.clipShots, dbg.edgeShots, dbg.chargedRounds, dbg.clampedClip, dbg.clampedPool = 0, 0, 0, 0, 0
    dbg.reloadLowered, dbg.sweptWeapons = 0, 0
end

RegisterCommand('gunnydebugreset', function()
    if not devOnly() then return end
    zeroCounts(GunnyDebugCounts)
    lastRecordedServerAmmo = nil
    ammoHistory = {}
    GunnyNotify('Debug counters reset', 'info')
end, false)

-- /ammoledger: this game's half in F8, then the server's ledger (server/ledger.lua). /ammoledger reset starts both.
RegisterCommand('ammoledger', function(_, args)
    if not devOnly() then return end
    local dbg = GunnyDebugCounts
    local reset = args[1] == 'reset'
    if reset then
        zeroCounts(dbg)
    else
        print('[GUNNY AMMO] this game:')
        print(('  rounds off the ped %d, plus %d charged for a shot with none off it; charged %d in all')
            :format(dbg.clipShots, dbg.edgeShots, dbg.chargedRounds))
        print(('  shot reports sent %d, answered %d; answers during a reload took %d off its count')
            :format(dbg.sent, dbg.confirmed, dbg.reloadLowered))
        print(('  the game handed out %d of the drawn kind and %d of others, all taken back; %d weapons swept')
            :format(dbg.clampedClip, dbg.clampedPool, dbg.sweptWeapons))
        if not GunnyDebugOn then print('  (Gunny Debug is off in /w: the server keeps no ledger)') end
    end
    TriggerServerEvent('spur_gunny:server:ammoLedger', reset)
end, false)

RegisterNetEvent('spur_gunny:client:ammoLedger', function(lines)
    if type(lines) ~= 'table' then return end
    print('[GUNNY AMMO] the server:')
    for _, line in ipairs(lines) do print('  ' .. tostring(line)) end
    GunnyNotify('Ammo ledger printed in F8', 'info')
end)

-- /gunnyammoprobe: what the game says about the drawn weapon's ammunition, in F8.
RegisterCommand('gunnyammoprobe', function()
    if not devOnly() then return end
    local p = GunnyAmmo.probe(PlayerPedId())
    if not p then
        GunnyNotify('Draw a weapon first', 'info')
        return
    end
    print('[GUNNY PROBE] ' .. tostring(p.name))
    print(('  ammo name %s (%s), valid for it: %s; the game\'s own kind for it now: %s')
        :format(tostring(p.ammoType), tostring(p.typeHash), tostring(p.valid), tostring(p.gameType)))
    print(('  the pool holds the clip: %s; clip %s of %s; pool %s; in the weapon %s')
        :format(tostring(p.poolHoldsClip), tostring(p.clip), tostring(p.maxClip), tostring(p.pool), tostring(p.inWeapon)))
    GunnyNotify('Ammo probe printed in F8', 'info')
end, false)

-- RedM (spur_gunny, 24 Nov 2026): /gunnyammolab: each way of writing the drawn gun's ammunition pool, tried in turn and
-- read back, in F8 (GunnyAmmo.lab, client/ammo.lua). The gun is put back to its count afterwards.
RegisterCommand('gunnyammolab', function()
    if not devOnly() then return end
    CreateThread(function()
        local lines = GunnyAmmo.lab(PlayerPedId())
        if not lines then
            GunnyNotify('Draw a gun first (not mid-reload)', 'info')
            return
        end
        print('[GUNNY LAB] ' .. tostring(CurrentWeapon and CurrentWeapon.name))
        for _, l in ipairs(lines) do print('  ' .. l) end
        GunnyNotify('Ammo lab printed in F8', 'info')
    end)
end, false)

-- RedM (spur_gunny, 24 Nov 2026): /gunnypartlab: every gunsmith part name asked of the game, then each part the drawn
-- gun takes put on and read back, in F8 (GunsmithLab, client/gunsmith.lua).
RegisterCommand('gunnypartlab', function()
    if not devOnly() then return end
    CreateThread(function()
        local lines = GunsmithLab(PlayerPedId())
        print('[GUNNY PARTS] ' .. tostring(CurrentWeapon and CurrentWeapon.name or 'no gun drawn'))
        for _, l in ipairs(lines) do print('  ' .. l) end
        GunnyNotify('Part lab printed in F8', 'info')
    end)
end, false)

-- RedM (spur_gunny, 24 Nov 2026): /gunnygivelab <weapon item>: with nothing drawn, the weapon given to the ped in a few
-- ways, and what the game then says it has, in F8: in the player's own inventory (HAS_PED_GOT_WEAPON, inventory only:
-- what a draw looks at), anywhere on the ped, and in the hand. Taken away after each; the guard leaves it alone
-- meanwhile (GunnyGuardHold, client/guard.lua).
local GIVE_WEAPON_TO_PED, ADD_REASON = 0x5E3BDDBCB83F3D84, GetHashKey('ADD_REASON_DEFAULT')
local function yes(r) return r == true or (type(r) == 'number' and r ~= 0) end

RegisterCommand('gunnygivelab', function(_, args)
    if not devOnly() then return end
    local name = args[1] or 'gunny_elephant'
    local w = Config.Weapons[name]
    if not (w and w.hash) then GunnyNotify('No weapon item ' .. tostring(name), 'error'); return end
    if CurrentWeapon then GunnyNotify('Put the drawn weapon away first', 'info'); return end
    CreateThread(function()
        local ped, hash = PlayerPedId(), Config.U32(w.hash)
        RequestWeaponAsset(hash, 31, 0)
        local deadline = GetGameTimer() + 3000
        while not yes(HasWeaponAssetLoaded(hash)) and GetGameTimer() < deadline do Wait(0) end
        local lines = { ('%s (%s): valid %s, asset loaded %s'):format(name, tostring(hash), tostring(IsWeaponValid(hash)),
            tostring(yes(HasWeaponAssetLoaded(hash)))) }
        GunnyGuardHold[hash] = true
        Whip.core:PermitNativeWeapon(hash, true)
        local ways = {   -- { label, forced into the hand, unlocks ignored }
            { 'in hand, unlocks kept (gunny now)', true, false },
            { 'in hand, unlocks ignored', true, true },
            { 'not in hand, unlocks ignored, then selected', false, true },
        }
        for _, way in ipairs(ways) do
            RemoveWeaponFromPed(ped, hash)
            Wait(300)
            Citizen.InvokeNative(GIVE_WEAPON_TO_PED, ped, hash, 0, way[2], false, 0, false, 0.5, 1.0, ADD_REASON, way[3],
                0.0, false)
            if not way[2] then SetCurrentPedWeapon(ped, hash, true, 0, false, false) end
            local reads = {}
            for _, ms in ipairs({ 0, 500, 1500 }) do
                if ms > 0 then Wait(ms - (ms == 1500 and 500 or 0)) end
                reads[#reads + 1] = ('%d ms: inventory %s, on ped %s, in hand %s'):format(ms,
                    tostring(yes(HasPedGotWeapon(ped, hash, 0, true))), tostring(yes(HasPedGotWeapon(ped, hash, 0, false))),
                    tostring(Config.U32(GetSelectedPedWeapon(ped)) == hash))
            end
            lines[#lines + 1] = way[1] .. ': ' .. table.concat(reads, '; ')
        end
        RemoveWeaponFromPed(ped, hash)
        Wait(300)
        GunnyGuardHold[hash] = nil
        Whip.core:PermitNativeWeapon(hash, false)
        RemoveWeaponAsset(hash)
        GunnyGuardSweep('give lab')
        print('[GUNNY GIVE]')
        for _, l in ipairs(lines) do print('  ' .. l) end
        GunnyNotify('Give lab printed in F8', 'info')
    end)
end, false)

--- One line of white text, RDR2's way: the style, then the text as a literal string.
local function drawText(x, y, text, scale)
    scale = scale or 0.30
    SetTextScale(scale, scale)
    SetTextColor(255, 255, 255, 255)
    SetTextCentre(false)
    SetTextDropshadow(1, 0, 0, 0, 255)
    SetTextFontForCurrentCommand(1)
    DisplayText(VarString(10, 'LITERAL_STRING', text), x, y)
end

local function pollInventory()
    if isPolling or not CurrentWeapon then return end
    if not (Config.IsFirearm(CurrentWeapon.config) or Config.IsBow(CurrentWeapon.config)) then
        invData, invPolledAt = {}, GetGameTimer()
        return
    end
    isPolling = true
    local name = CurrentWeapon.name
    CreateThread(function()
        local ok, carried = GunnyCallback('spur_gunny:countInventory', name)
        if ok and type(carried) == 'table' then invData = carried end
        invPolledAt = GetGameTimer()
        isPolling = false
    end)
end

local function mark(same) return same and '' or '  <<' end

local function drawFrame(now)
    local dbg = GunnyDebugCounts
    local ped = PlayerPedId()
    local w = CurrentWeapon

    if dbg.serverAmmo and dbg.serverAmmo ~= lastRecordedServerAmmo then
        lastRecordedServerAmmo = dbg.serverAmmo
        ammoHistory[#ammoHistory + 1] = dbg.serverAmmo
        while #ammoHistory > AMMO_HISTORY_MAX do table.remove(ammoHistory, 1) end
    end

    local x, y, lh = 0.008, 0.26, 0.022
    local function line(text, scale) drawText(x, y, text, scale); y = y + lh end

    line('GUNNY DEBUG: /gunnydebugreset zeroes the counters', 0.34)
    if not w then
        line('No weapon drawn')
        return
    end
    line(('%s  [%s]  slot %s (%s)  %s'):format(w.name, Config.KindOf(w.config), tostring(w.slot), tostring(w.pocket),
        w.serial or ''))
    if w.kind then line(('  loaded with %s'):format(Config.AmmoLabel(w.kind)), 0.26) end

    -- The three counts. The game apart from the client is a different fault from the server apart from it.
    y = y + lh * 0.4
    line('ROUNDS')
    local tracked = w.ammo or 0
    local clip, pool = GunnyAmmo.peek(ped)
    local gameTotal = Config.IsThrowable(w.config) and (pool or 0) or GunnyAmmo.total(ped)
    line(('  game     clip %d   pool %s   total %d%s'):format(clip, pool and tostring(pool) or '-', gameTotal,
        mark(gameTotal == tracked or GunnyAmmo.reloading())))
    line(('  client   %d%s'):format(tracked, GunnyAmmo.reloading() and '   (reloading)' or ''))
    if dbg.serverAmmo then
        local age = now - (dbg.serverAmmoAt or now)
        line(('  server   %d   %d ms ago%s'):format(dbg.serverAmmo, age,
            dbg.serverAmmo == tracked and '' or ('  << ' .. (dbg.serverAmmo - tracked))))
    else
        line('  server   no answer yet')
    end
    if #ammoHistory > 0 then line('  history  ' .. table.concat(ammoHistory, ' '), 0.26) end

    y = y + lh * 0.4
    line('SHOTS')
    local inFlight = w.shotsInFlight or 0
    line(('  sent %d   confirmed %d   in flight %d%s'):format(dbg.sent, dbg.confirmed, inFlight, mark(inFlight < 4)))
    line(('  off the ped %d   charged with none off it %d   stale answers %d')
        :format(dbg.clipShots, dbg.edgeShots, dbg.staleIgnored), 0.26)
    if dbg.lastShotAt then line(('  last shot %d ms ago'):format(now - dbg.lastShotAt), 0.26) end

    y = y + lh * 0.4
    line(('TAKEN BACK   drawn kind %d   other kinds %d   weapons %d')
        :format(dbg.clampedClip, dbg.clampedPool, dbg.sweptWeapons), 0.28)
    if dbg.ammoJumps > 0 and dbg.lastJump then
        line(('COUNT WENT UP x%d   last %d to %d, %d s ago'):format(dbg.ammoJumps, dbg.lastJump.from, dbg.lastJump.to,
            math.floor((now - dbg.lastJump.at) / 1000)), 0.28)
    else
        line('no count went up', 0.28)
    end

    y = y + lh * 0.4
    local pollAge = invPolledAt > 0 and math.floor((now - invPolledAt) / 1000) or -1
    line(('CARRIED, asked %s'):format(pollAge >= 0 and (pollAge .. ' s ago') or 'never'), 0.28)
    for _, k in ipairs(invData.kinds or {}) do
        line(('  %s   %d'):format(tostring(k.label), tonumber(k.count) or 0), 0.26)
    end
end

--- On or off: the overlay, and gunny's debug prints here and on the server.
local function setOverlay(on)
    on = on == true
    if on == overlayOn then return end
    overlayOn = on
    GunnyDebugOn = on
    TriggerServerEvent('spur_gunny:server:debug', on)
    if not on then return end
    CreateThread(function()
        local frames = 0
        while overlayOn do
            frames = frames + 1
            if frames >= 100 then frames = 0; pollInventory() end
            local ok, err = pcall(drawFrame, GetGameTimer())
            if not ok then
                print('[GUNNY] the debug overlay errored: ' .. tostring(err))
                overlayOn, GunnyDebugOn = false, false
                break
            end
            Wait(0)
        end
    end)
end

Whip.register(function()
    local ok, why = exports.spur_core:RegisterDebugTool('gunny', {
        label    = 'Gunny Debug',
        desc     = 'The drawn weapon\'s rounds as the game, gunny and the server count them, the shots sent and confirmed, what the game handed out and gunny took back, and the cartridges carried. Also prints gunny\'s debug lines.',
        onToggle = setOverlay,
    })
    if not ok then print('[GUNNY] no Gunny Debug in /w: ' .. tostring(why)) end
end)
