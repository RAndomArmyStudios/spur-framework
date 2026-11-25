-- spur_gunny: AMMUNITION, and the one place it is written
--
-- One number lives in three places: what the ped holds, CurrentWeapon.ammo, and the gun's metadata on the server (the
-- authoritative copy). Write the ped's ammunition only through this file, so they cannot disagree.
--
-- RedM (spur_gunny, 24 Nov 2026): rewritten for RDR2.
--   * RDR2 keeps ammunition in pools by kind (AMMO_REVOLVER, AMMO_ARROW...), not per weapon, and a gun has a clip. The
--     pool counts the rounds in the clip too (seen in game), so the ped's total is the pool. A pool goes down only by
--     _REMOVE_AMMO_FROM_PED_BY_TYPE with a reason the game accepts (setPool, below). Every write goes by the drawn
--     weapon's kind (CurrentWeapon.typeHash).
--   * No magazines. A reload puts the rounds that may go in into the pool as a reserve, plays the game's own reload,
--     and takes back what did not go in (startReload, reloadFrame). One model for every gun: the game loads a revolver
--     a cartridge at a time and a pump shotgun a shell at a time, and the player may stop partway.
--   * RDR2 hands out ammunition by itself: looted off bodies, picked up, from a kit, from a cheat. None of it is kept.
--     reconcile puts the pools back to what the items say after every shot, as every reload ends, on the guard's timer
--     (client/guard.lua) and as the weapon changes. A gain is clamped away, never turned into an item.

GunnyAmmo = {}

-- ============================================
-- READING THE PED
-- ============================================

--- [weapon hash] = the game's clip size for it (GetMaxAmmoInClip), once the game has answered one.
local maxClipOf = {}

local function whole(n)
    return math.max(0, math.floor(tonumber(n) or 0))
end

--- The rounds in the weapon's clip. (GetAmmoInClip answers (found, ammo): the count is the second value.)
local function clipOf(ped, hash)
    local _, n = GetAmmoInClip(ped, hash)
    return whole(n)
end

local function poolOf(ped, typeHash)
    return whole(GetPedAmmoByType(ped, typeHash))
end

-- RedM (spur_gunny, 24 Nov 2026): in game (/gunnyammolab), a Cattleman's AMMO_REVOLVER pool did not move for
-- SetPedAmmoByType (down or up), for _REMOVE_AMMO_FROM_PED_BY_TYPE with REMOVE_REASON_DEFAULT, or for SetPedAmmo on
-- the weapon; _ADD_AMMO_TO_PED_BY_TYPE added. Loading the clip left the pool as it was: the pool holds the clip. So a
-- pool is written one way after another, each read back, until one sticks, and the way that stuck is remembered per
-- kind and direction and tried first after. Down: the plain set, the remove with each reason RDR2's own scripts use,
-- the weapon's remove and set, and last every pool emptied (_REMOVE_ALL_PED_AMMO) and this one and the drawn kind's
-- added back (gunny keeps every other pool empty anyway). Up: the plain set, then the add.
local ADD_BY_TYPE, REMOVE_BY_TYPE = 0x106A811C6D3035F3, 0xB6CFEC32E3742779
local REMOVE_FROM_WEAPON, REMOVE_ALL = 0xF4823C813CB8277D, 0x1B83C0DEEBCBB214
local ADD_REASON, USED_REASON = GetHashKey('ADD_REASON_DEFAULT'), GetHashKey('REMOVE_REASON_USED')

local function add(ped, typeHash, k)
    if k > 0 then Citizen.InvokeNative(ADD_BY_TYPE, ped, typeHash, k, ADD_REASON) end
end

local function drawnOf(typeHash)
    local w = CurrentWeapon
    return w and w.typeHash == typeHash and w or nil
end

--- Each way: { name, fn(ped, typeHash, now, n) }, `now` the pool as read just before.
local DOWN = { { 'SetPedAmmoByType', function(ped, t, _, n) SetPedAmmoByType(ped, t, n) end } }
for _, reason in ipairs({ 'REMOVE_REASON_USED', 'REMOVE_REASON_DEFAULT', 'REMOVE_REASON_DEBUG', 'REMOVE_REASON_DROPPED',
                          'REMOVE_REASON_GIVEN' }) do
    local h = GetHashKey(reason)
    DOWN[#DOWN + 1] = { '_REMOVE_AMMO_FROM_PED_BY_TYPE ' .. reason, function(ped, t, now, n)
        Citizen.InvokeNative(REMOVE_BY_TYPE, ped, t, now - n, h)
    end }
end
DOWN[#DOWN + 1] = { '_REMOVE_AMMO_FROM_PED (the weapon)', function(ped, t, now, n)
    local w = drawnOf(t)
    if w then Citizen.InvokeNative(REMOVE_FROM_WEAPON, ped, w.hash, now - n, USED_REASON) end
end }
DOWN[#DOWN + 1] = { 'SetPedAmmo (the weapon)', function(ped, t, _, n)
    local w = drawnOf(t)
    if w then SetPedAmmo(ped, w.hash, n) end
end }
DOWN[#DOWN + 1] = { '_REMOVE_ALL_PED_AMMO, then added back', function(ped, t, _, n)
    local w = CurrentWeapon
    local other = w and w.typeHash and w.typeHash ~= t and w.typeHash or nil
    local keep = other and poolOf(ped, other) or 0
    Citizen.InvokeNative(REMOVE_ALL, ped)
    if other then add(ped, other, keep - poolOf(ped, other)) end
    add(ped, t, n - poolOf(ped, t))
end }
local UP = {
    { 'SetPedAmmoByType', function(ped, t, _, n) SetPedAmmoByType(ped, t, n) end },
    { '_ADD_AMMO_TO_PED_BY_TYPE', function(ped, t, now, n) add(ped, t, n - now) end },
}
GunnyAmmo.WAYS_DOWN, GunnyAmmo.WAYS_UP = DOWN, UP   -- for /gunnyammolab

local wayDown, wayUp = {}, {}   -- [kind] = the index of the way that last stuck
local cannotLower = {}          -- [kind] = true while no way down sticks (a reload then adds nothing: startReload)
local refusalSaid = {}          -- [kind] = true once F8 has been told no way stuck

--- Put `n` rounds in the pool of this kind. Answers whether the game holds `n` afterwards.
---@return boolean
local function setPool(ped, typeHash, n, again)
    n = whole(n)
    local now = poolOf(ped, typeHash)
    if now == n then return true end
    local down = now > n
    local ways, known = down and DOWN or UP, down and wayDown or wayUp
    local first = known[typeHash]
    local order = first and { first } or {}
    for i = 1, #ways do if i ~= first then order[#order + 1] = i end end
    for _, i in ipairs(order) do
        ways[i][2](ped, typeHash, now, n)
        now = poolOf(ped, typeHash)
        if now == n then
            if known[typeHash] ~= i then
                known[typeHash] = i
                GunnyDebugPrint('Pool', typeHash, down and 'lowered' or 'raised', 'by', ways[i][1])
            end
            if down then cannotLower[typeHash] = nil end
            return true
        end
        -- Overshot: once more from there, the other way.
        if (down and now < n) or (not down and now > n) then
            if not again then return setPool(ped, typeHash, n, true) end
            break
        end
    end
    if down then cannotLower[typeHash] = true end
    if not refusalSaid[typeHash] then
        refusalSaid[typeHash] = true
        print(('[GUNNY] WARNING: the game kept %d in ammunition pool %s after being set to %d (/gunnyammolab)')
            :format(now, tostring(typeHash), n))
    end
    return false
end
GunnyAmmo.setPool = setPool

--- The game's clip size for the drawn weapon; the item's capacity until the game answers one.
local function maxClip(ped, w)
    local m = maxClipOf[w.hash]
    if m then return m end
    m = whole(GetMaxAmmoInClip(ped, w.hash, true))
    if m > 0 then
        maxClipOf[w.hash] = m
        return m
    end
    return math.max(1, whole(w.config.capacity))
end

--- What the ped holds of the drawn weapon's kind, clip and all. RedM (spur_gunny, 24 Nov 2026): in RDR2 the pool is that
--- total: in game the pool stayed the same while the game's own reload filled the clip (/gunnyammolab). (whip_gunny's
--- GTA build learned this per weapon; RDR2 answered the same for the revolver, so it is taken as the rule.)
---@param ped number
---@return integer
function GunnyAmmo.total(ped)
    local w = CurrentWeapon
    if not (w and w.typeHash) then return 0 end
    return poolOf(ped, w.typeHash)
end

--- Rounds on the ped beyond the clip: the game's reserve. A gun whose item holds more than the game's clip keeps the
--- rest here, and the game's own reload moves them in (client/reload.lua).
---@param ped number
---@return integer
function GunnyAmmo.reserve(ped)
    local w = CurrentWeapon
    if not (w and w.typeHash) then return 0 end
    return math.max(0, GunnyAmmo.total(ped) - clipOf(ped, w.hash))
end

--- `total` rounds on the ped, `clip` of them in the clip. RedM (spur_gunny, 24 Nov 2026): SetAmmoInClip does not take
--- the clip out of the pool. Filling it adds to the pool (0 to 2 put the pool up by 2), and emptying it puts its rounds
--- back in the pool (/gunnyammolab). So the clip is emptied into the pool, the pool set to what stays out of the clip,
--- the clip filled (which adds it), and the pool put right if the game did otherwise.
local function write(ped, w, total, clip)
    clip = math.max(0, math.min(clip, total))
    if clipOf(ped, w.hash) > 0 then SetAmmoInClip(ped, w.hash, 0) end
    setPool(ped, w.typeHash, total - clip)
    if clip > 0 then SetAmmoInClip(ped, w.hash, clip) end
    if poolOf(ped, w.typeHash) ~= total then setPool(ped, w.typeHash, total) end
end

-- ============================================
-- WRITING IT
-- ============================================

--- Set what the drawn gun or bow holds, on the ped and in the tracked count. `fill`: the clip as full as the rounds
--- allow (a draw, a new kind); otherwise the clip is kept as it is unless it holds more than the rounds.
---@param rounds number
---@param fill boolean|nil
function GunnyAmmo.set(rounds, fill)
    local w = CurrentWeapon
    if not w then return end
    rounds = whole(rounds)
    w.ammo = rounds
    if not w.typeHash then return end
    local ped = PlayerPedId()
    local clip = clipOf(ped, w.hash)
    if fill or clip > rounds then clip = math.min(rounds, maxClip(ped, w)) end
    write(ped, w, rounds, clip)
    -- What the ped holds now, as the game took it: shots are counted from this (client/shooting.lua).
    w.pedTotal = GunnyAmmo.total(ped)
    if w.pedTotal ~= rounds then
        GunnyDebugPrint('The game holds', w.pedTotal, 'of', w.name, 'after being set to', rounds)
    end
end

--- What gunny believes the drawn weapon holds.
---@return number
function GunnyAmmo.count()
    return CurrentWeapon and CurrentWeapon.ammo or 0
end

--- A drawn throwable's stack: the ped's count of it, and the tracked one. A stack has no clip.
---@param count number
function GunnyAmmo.setStack(count)
    local w = CurrentWeapon
    if not w then return end
    count = whole(count)
    local ped = PlayerPedId()
    SetPedAmmo(ped, w.hash, count)
    w.ammo = count
    w.pedTotal = whole(GetAmmoInPedWeapon(ped, w.hash))
end

--- The drawn gun or bow takes this kind from now (an ammo name's hash). The old kind's pool is emptied first. A kind
--- the game says the weapon cannot take is said in F8, once each.
local kindRefusalSaid = {}
---@param typeHash integer|nil
function GunnyAmmo.setKind(typeHash)
    local w = CurrentWeapon
    if not w then return end
    local ped = PlayerPedId()
    if w.typeHash and w.typeHash ~= typeHash then setPool(ped, w.typeHash, 0) end
    w.typeHash = typeHash
    if not typeHash then return end
    EnableAmmoTypeForPedWeapon(ped, w.hash, typeHash)
    SetAmmoTypeForPedWeapon(ped, w.hash, typeHash)
    if IsAmmoTypeValidForWeapon(w.hash, typeHash) == 0 then
        local key = w.hash .. ':' .. typeHash
        if not kindRefusalSaid[key] then
            kindRefusalSaid[key] = true
            print(('[GUNNY] WARNING: the game says %s cannot take %s (items/ammo.lua, items/weapons.lua)')
                :format(tostring(w.name), tostring(w.ammoType)))
        end
    end
end

-- ============================================
-- PUTTING THE POOLS BACK
-- ============================================

local allTypes, groupTypes = nil, {}
GunnyPacks.onChange(function() allTypes, groupTypes = nil, {} end)

--- Every pool gunny looks after: each cartridge item's kind, Config.Guard.alsoZero, and each throwable's own.
local function everyType()
    if allTypes then return allTypes end
    local seen, list = {}, {}
    local function add(h)
        h = Config.U32(h)
        if h ~= 0 and not seen[h] then seen[h] = true; list[#list + 1] = h end
    end
    for _, a in pairs(Config.Ammo) do add(a.typeHash or Config.Hash(a.type)) end
    for _, name in ipairs(Config.Guard.alsoZero or {}) do add(Config.Hash(name)) end
    for _, w in pairs(Config.Weapons) do
        if Config.IsThrowable(w) and w.hash then add(GetAmmoTypeForWeapon(w.hash)) end
    end
    allTypes = list
    return list
end

--- The pools of a gun's or bow's group: the kinds it could be switched to by the game.
local function typesOfGroup(group)
    if not group then return {} end
    if groupTypes[group] then return groupTypes[group] end
    local list = {}
    for _, kind in ipairs((Config.AmmoGroups[group] or {}).kinds or {}) do
        local a = Config.GetAmmo(kind)
        if a then list[#list + 1] = a.typeHash or Config.Hash(a.type) end
    end
    groupTypes[group] = list
    return list
end

-- A reload under way: its reserve is on the ped on purpose (startReload, below).
local reload = nil

-- /gunnyammolab running (GunnyAmmo.lab, below): the pools are being tried on purpose, so nothing puts them back and
-- no drop counts as a shot until it ends.
local labRunning = false

--- Put the ped's pools back to what the items say: the drawn weapon's own never above its count, every other kind
--- empty. `everything`: every pool gunny knows (the guard's timer, client/guard.lua); otherwise the drawn weapon's group.
---@param ped number
---@param everything boolean|nil
function GunnyAmmo.reconcile(ped, everything)
    if labRunning then return end
    local dbg = GunnyDebugCounts
    local w = CurrentWeapon
    local own = w and (w.typeHash or w.stackType) or nil
    if w and not reload then
        if Config.IsThrowable(w.config) then
            local has = whole(GetAmmoInPedWeapon(ped, w.hash))
            if has > (w.ammo or 0) then
                dbg.clampedClip = dbg.clampedClip + (has - w.ammo)
                GunnyAmmo.setStack(w.ammo)
            end
        elseif w.typeHash then
            local has = GunnyAmmo.total(ped)
            if has > (w.ammo or 0) then
                dbg.clampedClip = dbg.clampedClip + (has - w.ammo)
                GunnyDebugPrint('The game gave', has - w.ammo, 'rounds of', w.name, '- taken back')
                GunnyAmmo.set(w.ammo)
            end
        end
    end
    local list = (everything or not w) and everyType() or typesOfGroup(w.config.group)
    for i = 1, #list do
        local t = list[i]
        if t ~= own then
            local n = poolOf(ped, t)
            if n > 0 then
                setPool(ped, t, 0)
                dbg.clampedPool = dbg.clampedPool + n
            end
        end
    end
end

-- ============================================
-- THE RELOAD
-- ============================================
--
-- The game reloads from the reserve, and gunny keeps none of its own beyond the clip (only a gun whose item holds
-- more than the game's clip has one: `legit`). So a reload adds the rounds that may go in to the pool, asks the game to
-- reload, and watches. When it ends (the game's reload over, a shot that cut it short, a stall, the time out), what is
-- still in the reserve beyond `legit` did not go in, and is taken back off the ped. A shot in the meantime came out of
-- the clip, not the reserve, so the count holds either way; it is counted on the next frame (client/shooting.lua).

local function reloadCfg()
    local c = Config.Reload or {}
    return tonumber(c.settleMs) or 1000, tonumber(c.stallMs) or 4000, tonumber(c.timeoutMs) or 15000
end

--- Start one: up to `room` cartridges on top of what the gun holds now. False when there is nothing to load into.
---@param room number
---@return boolean
function GunnyAmmo.startReload(room)
    local w = CurrentWeapon
    if not (w and w.typeHash) or room <= 0 then return false end
    -- RedM (spur_gunny, 24 Nov 2026): rounds put in for a reload that could not be taken back would be free rounds.
    if cannotLower[w.typeHash] then
        GunnyDebugPrint('No reload: the game will not lower pool', w.typeHash)
        return false
    end
    local ped = PlayerPedId()
    local now = GetGameTimer()
    local clip = clipOf(ped, w.hash)
    reload = { hash = w.hash, room = room, legit = math.max(0, GunnyAmmo.total(ped) - clip),
               clip = clip, at = now, seen = false, movedAt = now }
    setPool(ped, w.typeHash, poolOf(ped, w.typeHash) + room)
    MakePedReload(ped)
    return true
end

--- Is one playing?
---@return boolean
function GunnyAmmo.reloading()
    return reload ~= nil or labRunning   -- the lab too: no drop counts as a shot while it runs (client/shooting.lua)
end

--- Has the game's reload begun? (Firing comes back then: client/reload.lua.)
---@return boolean
function GunnyAmmo.reloadSeen()
    return reload ~= nil and reload.seen
end

--- Every frame while one plays (client/reload.lua). In the frame it ends, the cartridges that did not go in come off
--- the ped, and the count takes the ones that did.
---@return number|nil loaded  cartridges that went in, in the frame it ended
---@return boolean|nil cutShort  fewer than room
---@return boolean|nil timedOut
function GunnyAmmo.reloadFrame(ped, now)
    local r = reload
    if not r then return nil end
    local w = CurrentWeapon
    if not w or w.hash ~= r.hash or not w.typeHash then reload = nil; return nil end
    local settleMs, stallMs, timeoutMs = reloadCfg()
    local reloading = IsPedReloading(ped)
    local clipNow = clipOf(ped, r.hash)
    if reloading then r.seen = true end
    if clipNow ~= r.clip then r.clip, r.movedAt = clipNow, now end
    local waited = now - r.at
    local timedOut = waited >= timeoutMs or (reloading and now - r.movedAt >= stallMs)
    local shooting = IsPedShooting(ped)
    if not timedOut and not shooting and (reloading or (not r.seen and waited < settleMs)) then
        return nil
    end
    reload = nil

    local loaded
    if not r.seen and not shooting then
        -- The game played no reload (some seats and saddles): filled at once. The rounds are on the ped already; they
        -- only move into the clip.
        loaded = r.room
        local total = GunnyAmmo.total(ped)
        write(ped, w, total, math.min(total, maxClip(ped, w)))
    else
        local unused = math.max(0, math.min(GunnyAmmo.reserve(ped) - r.legit, r.room))
        loaded = r.room - unused
        if unused > 0 then setPool(ped, w.typeHash, math.max(0, poolOf(ped, w.typeHash) - unused)) end
    end
    -- From the count before the reload: a shot fired during it shows as a drop on the next frame, and is counted then.
    w.ammo = (w.ammo or 0) + loaded
    w.pedTotal = (w.pedTotal or 0) + loaded
    return loaded, loaded < r.room, timedOut
end

--- Stop following one (the gun went, or it failed). The reserve it put on the ped goes with the next set or holster.
function GunnyAmmo.dropReload()
    reload = nil
end

--- End a stuck reload and put the gun back in the hand. Seated, mounted or getting into a seat, no task is cleared: the
--- seat is the ped's task, and clearing it would stop them getting in.
---@param ped number
function GunnyAmmo.endAnimation(ped)
    if not CurrentWeapon then return end
    if not IsPedInAnyVehicle(ped, false) and not IsPedGettingIntoAVehicle(ped) and not IsPedOnMount(ped) then
        if IsPedInCover(ped, false, false) then ClearPedSecondaryTask(ped) else ClearPedTasks(ped, true, true) end
    end
    SetCurrentPedWeapon(ped, CurrentWeapon.hash, true, 0, false, false)
end

-- Gunny Debug's probe (client/debug.lua): what the game says about the drawn weapon's ammunition.
---@return table|nil
function GunnyAmmo.probe(ped)
    local w = CurrentWeapon
    if not w then return nil end
    return {
        name = w.name, hash = w.hash, ammoType = w.ammoType, typeHash = w.typeHash,
        poolHoldsClip = true,   -- RedM (spur_gunny, 24 Nov 2026): in RDR2 it always does (GunnyAmmo.total)
        valid = w.typeHash and IsAmmoTypeValidForWeapon(w.hash, w.typeHash) or nil,
        gameType = Config.U32(GetPedAmmoTypeFromWeapon(ped, w.hash)),
        maxClip = GetMaxAmmoInClip(ped, w.hash, true),
        clip = clipOf(ped, w.hash),
        pool = w.typeHash and poolOf(ped, w.typeHash) or nil,
        inWeapon = GetAmmoInPedWeapon(ped, w.hash),
    }
end

-- RedM (spur_gunny, 24 Nov 2026): /gunnyammolab (client/debug.lua). Each way setPool knows, tried alone: a round
-- added first where needed (the add works), then the way asked to lower the pool by one (or raise it by one), read back
-- at once and a frame later. Then the clip loaded and emptied, to see whether the pool holds it. Then the gun is put
-- back to its count. Run in a thread (it waits).
---@return string[]|nil lines
function GunnyAmmo.lab(ped)
    local w = CurrentWeapon
    if not (w and w.typeHash) or reload or labRunning then return nil end
    labRunning = true
    local t, out = w.typeHash, {}
    local function state()
        return ('pool %3d  clip %d  in the weapon %3d%s'):format(poolOf(ped, t), clipOf(ped, w.hash),
            whole(GetAmmoInPedWeapon(ped, w.hash)), IsPedReloading(ped) and '  (reloading)' or '')
    end
    local function try(label, way, delta)
        if poolOf(ped, t) < 3 then add(ped, t, 3) end
        local before = poolOf(ped, t)
        way(ped, t, before, before + delta)
        local at = poolOf(ped, t)
        Wait(0)
        local later = poolOf(ped, t)
        local okNow = at == before + delta
        out[#out + 1] = ('%-4s %-46s %d -> %d, a frame later %d'):format(okNow and later == at and 'YES' or 'no',
            label, before, at, later)
    end
    local ok, err = pcall(function()
        out[#out + 1] = 'start: ' .. state()
        for _, way in ipairs(DOWN) do try('down 1: ' .. way[1], way[2], -1) end
        for _, way in ipairs(UP) do try('up 1: ' .. way[1], way[2], 1) end
        SetAmmoInClip(ped, w.hash, 0)
        out[#out + 1] = 'clip emptied: ' .. state()
        SetAmmoInClip(ped, w.hash, 2)
        out[#out + 1] = 'clip set to 2: ' .. state()
        SetAmmoInClip(ped, w.hash, 0)
        out[#out + 1] = 'clip emptied: ' .. state()
        local cleared = setPool(ped, t, 0)
        out[#out + 1] = ('setPool 0: %s, by %s: %s'):format(tostring(cleared),
            tostring(wayDown[t] and DOWN[wayDown[t]][1]), state())
    end)
    if not ok then out[#out + 1] = 'ERROR: ' .. tostring(err) end
    labRunning = false
    if CurrentWeapon == w then
        GunnyAmmo.set(w.ammo, true)
        out[#out + 1] = ('put back to the count %d: %s'):format(w.ammo or 0, state())
    end
    return out
end

--- The clip and the pool as the game holds them now, for the overlay (client/debug.lua).
---@return integer clip
---@return integer|nil pool
function GunnyAmmo.peek(ped)
    local w = CurrentWeapon
    if not w then return 0, nil end
    if Config.IsThrowable(w.config) then return 0, whole(GetAmmoInPedWeapon(ped, w.hash)) end
    return clipOf(ped, w.hash), w.typeHash and poolOf(ped, w.typeHash) or nil
end
