-- ============================================
-- RedM COMPATIBILITY LAYER: whip_core's GTA V natives on RDR2
-- ============================================
--
-- spur_core is whip_core 1.3.0 (by Whippy, LGPL 3.0) ported to RedM. This file is new in the port
-- (added 23 Nov 2026) and is under the LGPL 3.0 like the rest of spur_core.
--
-- whip_core was written for GTA V, so its code calls about 300 natives that RDR2 does not have. Rather than
-- rewrite every call, this file (loaded before every other spur_core script, on both sides) gives each of
-- those names a body:
--
--   MAPPED   the RDR2 native that does the same job (blips, text, shape tests, load scenes, scenarios,
--            weather, clock, weapons, doors, screen maths). Written out below.
--   STUBBED  nothing in RDR2 does it (vehicles' tuning, GTA's pause menu, scaleform, ped headshots, freemode
--            clothing, interiors' room data...). The call does nothing and returns a safe value.
--            shared/rdr_compat_stubs.lua holds those, generated from the GTA V native list.
--
-- A name is only defined when RedM does not already have it (def), except where RedM has the same name with
-- different arguments and whip's call would go wrong (force): TaskStartScenarioInPlace, IsPedUsingScenario
-- and SetBlipSprite take a hash on RDR2 where GTA takes a name or a number.
--
-- The first time a stub is called it says so in the console (F8 / server console), once per name:
--     [spur_core] RedM: <Name> has no RDR2 equivalent: skipped
-- /spurcompat (F8) or spurcompat (server console) lists every one hit so far, with counts.
-- setr spur_compat_log 0 in server.cfg silences the first-call lines. CONVERSION.md says what each stub turns off.

RdrCompat = {
    hits = {},      -- name -> calls, for stubs
    kind = {},      -- name -> 'mapped' | 'stub'
}
local C = RdrCompat
local SERVER = IsDuplicityVersion()
local hash = joaat or GetHashKey
local logOn = GetConvar('spur_compat_log', '1') ~= '0'
-- Another resource may load this file too (spur_test does, so its tests read the natives as spur_core writes them):
-- it says whose calls it logs, and only spur_core registers the commands.
local RES = GetCurrentResourceName()
local OWN = RES == 'spur_core'

local function onSide(side)
    return side == 'both' or (side == 'server') == SERVER
end

-- RedM (spur_core, 23 Nov 2026): the coroutines that must never Wait, the Director's and the Systems Creator's card
-- runners (they mark theirs as they make them). Making a vehicle or a ped waits on RedM; RdrEntity.canWait
-- (server/rdr_entities.lua) reads this so that it never waits inside one.
RdrGuarded = RdrGuarded or setmetatable({}, { __mode = 'k' })

local function truthy(v)
    return v == true or (type(v) == 'number' and v ~= 0)
end
C.truthy = truthy

--- Defines `name` as `fn` unless RedM already has it.
function C.def(name, fn)
    if _G[name] ~= nil then return false end
    _G[name] = fn
    C.kind[name] = 'mapped'
    return true
end
local def = C.def

--- Defines `name` as `fn` even when RedM has it: RedM's version takes other arguments than whip passes.
function C.force(name, fn)
    _G[name] = fn
    C.kind[name] = 'mapped'
end
local force = C.force

local function noteHit(name)
    local n = (C.hits[name] or 0) + 1
    C.hits[name] = n
    if n == 1 and logOn then
        print(('^3[%s] RedM: %s has no RDR2 equivalent: skipped (see CONVERSION.md in spur_core)^7'):format(RES, name))
    end
end

--- A GTA V native RDR2 has no counterpart for: does nothing, returns `...` (the safe values for its GTA return
--- and out-parameters). `side` is 'client', 'server' or 'both'.
function C.stub(name, side, ...)
    if not onSide(side) or _G[name] ~= nil then return end
    local rets = table.pack(...)
    _G[name] = function()
        noteHit(name)
        return table.unpack(rets, 1, rets.n)
    end
    C.kind[name] = 'stub'
end

--- A stub that never logs: purely cosmetic calls made every frame (text outline, HUD component hiding...).
function C.quiet(name, side, ...)
    if not onSide(side) or _G[name] ~= nil then return end
    local rets = table.pack(...)
    _G[name] = function()
        C.hits[name] = (C.hits[name] or 0) + 1
        return table.unpack(rets, 1, rets.n)
    end
    C.kind[name] = 'stub'
end
local quiet = C.quiet

local function listHits()
    local names = {}
    for n in pairs(C.hits) do names[#names + 1] = n end
    table.sort(names, function(a, b) return C.hits[a] > C.hits[b] end)
    print(('[%s] RedM compat (%s): %d GTA-only natives called so far'):format(RES, SERVER and 'server' or 'client', #names))
    for _, n in ipairs(names) do print(('  %-44s %d'):format(n, C.hits[n])) end
end

-- ============================================================================================
-- PLATES AND DOOR LOCKS, kept on the vehicle (both sides)
-- ============================================================================================
-- RedM (spur_core, 24 Nov 2026): RDR2's vehicles have no number plates, and whip_core names its cars by plate on both
-- sides (the one name the server and every game agree on). RedM's server can't read a door lock back either (it
-- answers 0). So both are kept on the vehicle as state bags the server sets, spurPlate and spurLock, and these
-- natives read and write them. Each game applies spurLock with RDR2's own SetVehicleDoorsLocked (client side, below).
local PLATE_BAG, LOCK_BAG = 'spurPlate', 'spurLock'
C.PLATE_BAG, C.LOCK_BAG = PLATE_BAG, LOCK_BAG
-- RedM (spur_core, 24 Nov 2026): who sits where (SEATS, below). { net = vehicle netId, seat = -1.. } or nil.
local SEAT_BAG = 'spurSeat'
C.SEAT_BAG = SEAT_BAG

local function bagOf(veh)
    if type(veh) ~= 'number' or veh == 0 or not DoesEntityExist(veh) then return nil end
    local ok, st = pcall(function() return Entity(veh).state end)
    return ok and st or nil
end

force('GetVehicleNumberPlateText', function(veh)
    local st = bagOf(veh)
    local v = st and st[PLATE_BAG]
    return type(v) == 'string' and v or ''
end)

-- The server's is seen by every game; a game's own stays in that game.
force('SetVehicleNumberPlateText', function(veh, text)
    local st = bagOf(veh)
    if st then pcall(st.set, st, PLATE_BAG, tostring(text or ''), SERVER) end
end)

if SERVER then
    local rawLock, rawLockStatus = SetVehicleDoorsLocked, GetVehicleDoorLockStatus
    force('SetVehicleDoorsLocked', function(veh, status)
        if rawLock then pcall(rawLock, veh, status) end
        local st = bagOf(veh)
        if st then pcall(st.set, st, LOCK_BAG, math.tointeger(tonumber(status)) or 0, true) end
    end)
    force('GetVehicleDoorLockStatus', function(veh)
        local st = bagOf(veh)
        local v = st and st[LOCK_BAG]
        if type(v) == 'number' then return v end
        local ok, raw = pcall(rawLockStatus or function() return 0 end, veh)
        return ok and tonumber(raw) or 0
    end)
elseif OWN then
    -- A lock the server set, applied in this game. The bag can arrive a moment before the vehicle does.
    AddStateBagChangeHandler(LOCK_BAG, nil, function(bagName, _, value)
        if type(value) ~= 'number' then return end
        CreateThread(function()
            for _ = 1, 40 do
                local ent = GetEntityFromStateBagName(bagName)
                if ent ~= 0 then
                    SetVehicleDoorsLocked(ent, value)
                    return
                end
                Wait(50)
            end
        end)
    end)
end

-- RedM (spur_core, 24 Nov 2026): a script putting this game's player in a seat is noted, with the time, in the
-- player's own state bag (spurSeatedAt; not sent to the server, read by every resource here). client/vehicles.lua's
-- lock guard puts a player who has got onto a locked wagon without its key back down, and this tells it that the
-- player was put there (the Vehicle Manager, the seat page, a take, an arrival) rather than climbed on.
if not SERVER then
    for _, name in ipairs({ 'SetPedIntoVehicle', 'TaskWarpPedIntoVehicle' }) do
        local raw = _G[name]
        if raw then
            force(name, function(ped, ...)
                if ped == PlayerPedId() then LocalPlayer.state:set('spurSeatedAt', GetGameTimer(), false) end
                return raw(ped, ...)
            end)
        end
    end
end

-- ============================================================================================
-- SERVER
-- ============================================================================================
if SERVER then
    if OWN then
        RegisterCommand('spurcompat', function(source)
            if source ~= 0 then return end
            listHits()
        end, true)
    end

    -- server/object_viewer.lua repairs and damages vehicles through FiveM's server-side vehicle natives, and
    -- server/npcs.lua asks whether an NPC is frozen. RedM's server has none of them.
    def('IsEntityPositionFrozen', function() return false end)
    def('GetVehicleNumberOfWheels', function() return 4 end)
    C.stub('SetVehicleFixed', 'server')
    C.stub('SetVehicleDeformationFixed', 'server')
    C.stub('SetVehicleEngineHealth', 'server')
    C.stub('SetVehicleBodyHealth', 'server')
    C.stub('SetVehiclePetrolTankHealth', 'server')
    C.stub('SetVehicleDirtLevel', 'server')
    C.stub('SetVehicleTyreFixed', 'server')
    C.stub('SetVehicleTyreBurst', 'server')

    -- SEATS. RedM (spur_core, 24 Nov 2026): RedM's server sees a ped get into a vehicle but never sees it get out:
    -- GetVehiclePedIsIn(ped, false) still names the wagon after the player has climbed down and walked off, and
    -- GetPedInVehicleSeat never names anyone (seen in spur_test 05, "seat probe"). So each game says where its own
    -- player sits, and where the NPCs it runs sit (the spurSeat bag: client side, SEATS, below), and these two
    -- natives answer from that:
    --   * in: only a vehicle the server saw the ped get into, or one it is standing at (5 m), so no game can put its
    --     player in a car across the map;
    --   * out: as soon as the game says so.
    -- A ped no game speaks for (an ambient one) reads as in no vehicle, as the server can't tell.
    local rawPedIn, rawSeat = GetVehiclePedIsIn, GetPedInVehicleSeat
    local NEAR = 5.0
    local npcSeats = {}   -- ped entity -> its bag value (NPCs; players are read from their player bag)

    local function reportOf(ped)
        local owner = NetworkGetEntityOwner(ped)
        if owner and owner > 0 and GetPlayerPed(owner) == ped then
            return Player(owner).state[SEAT_BAG]
        end
        local ok, st = pcall(function() return Entity(ped).state end)
        return ok and st and st[SEAT_BAG] or nil
    end

    --- The vehicle a ped's report puts it in, if the server can believe it; else 0.
    local function seatedIn(ped, r)
        if type(r) ~= 'table' or type(r.net) ~= 'number' then return 0 end
        local veh = NetworkGetEntityFromNetworkId(r.net)
        if not veh or veh == 0 or not DoesEntityExist(veh) then return 0 end
        if rawPedIn and rawPedIn(ped, false) == veh then return veh end
        if #(GetEntityCoords(ped) - GetEntityCoords(veh)) <= NEAR then return veh end
        return 0
    end
    C.seatedIn = function(ped) return seatedIn(ped, reportOf(ped)) end

    force('GetVehiclePedIsIn', function(ped, lastVehicle)
        if lastVehicle then return rawPedIn and rawPedIn(ped, true) or 0 end
        if not ped or ped == 0 or not DoesEntityExist(ped) then return 0 end
        return seatedIn(ped, reportOf(ped))
    end)

    force('GetPedInVehicleSeat', function(veh, seat)
        if not veh or veh == 0 or not DoesEntityExist(veh) then return 0 end
        seat = math.tointeger(tonumber(seat)) or -1
        for _, id in ipairs(GetPlayers()) do
            local src = tonumber(id)
            local ped = GetPlayerPed(src)
            if ped and ped ~= 0 then
                local r = Player(src).state[SEAT_BAG]
                if type(r) == 'table' and r.seat == seat and seatedIn(ped, r) == veh then return ped end
            end
        end
        for ped, r in pairs(npcSeats) do
            if not DoesEntityExist(ped) then
                npcSeats[ped] = nil
            elseif r.seat == seat and seatedIn(ped, r) == veh then
                return ped
            end
        end
        -- The server's own answer, where it gives one, and only while that ped still reads as in this vehicle.
        local raw = rawSeat and rawSeat(veh, seat) or 0
        if raw ~= 0 and DoesEntityExist(raw) and seatedIn(raw, reportOf(raw)) == veh then return raw end
        return 0
    end)

    AddStateBagChangeHandler(SEAT_BAG, nil, function(bagName, _, value)
        if bagName:sub(1, 7) ~= 'entity:' then return end
        local ped = GetEntityFromStateBagName(bagName)
        if not ped or ped == 0 then return end
        npcSeats[ped] = type(value) == 'table' and value or nil
    end)
    return
end

-- ============================================================================================
-- CLIENT
-- ============================================================================================
if OWN then RegisterCommand('spurcompat', listHits, false) end

local N = Citizen.InvokeNative

-- ---- text --------------------------------------------------------------------------------
-- GTA: SetTextFont/Scale/Colour/Centre, SetTextEntry('STRING') or BeginTextCommandDisplayText, then the text
-- in components, then DrawText(x, y). RDR2: the same style setters, then DisplayText(VarString(text), x, y).
-- whip builds every label that way, so the components are kept here and drawn in one go.

local pending = {}           -- text components since the last SetTextEntry / Begin*
local function startText() pending = {} end
local function addText(s) pending[#pending + 1] = tostring(s) end
local function takeText()
    local s = table.concat(pending)
    pending = {}
    return s
end

local function varString(s)
    if CreateVarString then return CreateVarString(10, 'LITERAL_STRING', s) end
    return N(0xFA925AC00EB830B9, 10, 'LITERAL_STRING', s, Citizen.ResultAsLong())   -- VAR_STRING
end

local function drawPending(x, y)
    local s = takeText()
    if s == '' then return end
    -- RDR2's font 1 (the one RedM frameworks draw labels with); GTA's font numbers mean nothing here.
    if SetTextFontForCurrentCommand then SetTextFontForCurrentCommand(1) end
    N(0xD79334A4BB99BAD1, varString(s), x + 0.0, y + 0.0)                             -- _DISPLAY_TEXT
end

def('SetTextScale', function(scale, size) N(0x4170B650590B3B00, scale + 0.0, size + 0.0) end)
def('SetTextCentre', function(on) N(0xBE5261939FBECB8C, on == true) end)
def('SetTextColour', function(r, g, b, a) N(0x50A41AD966910F03, r, g, b, a) end)   -- _SET_TEXT_COLOR
quiet('SetTextFont', 'client')            -- applied at draw time (font 1)
quiet('SetTextProportional', 'client')
quiet('SetTextOutline', 'client')
def('SetTextEntry', function() startText() end)
def('BeginTextCommandDisplayText', function() startText() end)
def('AddTextComponentString', addText)
def('AddTextComponentSubstringPlayerName', addText)
def('DrawText', drawPending)
def('EndTextCommandDisplayText', drawPending)
--- GTA's text labels (GXT) do not exist: a label reads as itself, a missing one as GTA's 'NULL'.
--- Only where RedM lacks GetLabelText: RedM b1491 has its own, which reads RDR2's labels and gives nil (not 'NULL')
--- for one it lacks, so whip's callers treat nil and 'NULL' alike (seen in game, 23 Nov 2026: /spurzone).
def('GetLabelText', function(label)
    if label == nil or label == '' or label == 'CARNOTFOUND' then return 'NULL' end
    return label
end)

-- ---- zones -------------------------------------------------------------------------------
-- GTA: GetNameOfZone(x, y, z) gives the zone's GXT label ('VINE'), and GetLabelText its name. RDR2 has neither:
-- GET_MAP_ZONE_AT_COORDS gives the hash of the town (type 1), the district (10) or the state (0) at a point.
-- GetNameOfZone here asks for each in turn and hands back the first one's name, or '' in open water or anywhere
-- none of the names below is known. Callers use the name as it is: RedM's own GetLabelText would read it as a
-- text label and give 'NULL' (client/pause.lua).
local ZONE_NAMES = {
    -- towns and settlements (type 1)
    annesburg = 'Annesburg', armadillo = 'Armadillo', beechershope = "Beecher's Hope", blackwater = 'Blackwater',
    braithwaite = 'Braithwaite Manor', butcher = 'Butcher Creek', caliga = 'Caliga Hall',
    cornwall = 'Cornwall Kerosene & Tar', emerald = 'Emerald Ranch', lagras = 'Lagras', manzanita = 'Manzanita Post',
    rhodes = 'Rhodes', siska = 'Sisika Penitentiary', stdenis = 'Saint Denis', strawberry = 'Strawberry',
    tumbleweed = 'Tumbleweed', valentine = 'Valentine', vanhorn = 'Van Horn', wallace = 'Wallace Station',
    wapiti = 'Wapiti', aguasdulcesfarm = 'Aguasdulces', aguasdulcesruins = 'Aguasdulces',
    aguasdulcesvilla = 'Aguasdulces', manicato = 'Manicato',
    -- districts (type 10)
    bayou_nwa = 'Bayou Nwa', big_valley = 'Big Valley', bluewater_marsh = 'Bluewater Marsh',
    cholla_springs = 'Cholla Springs', cumberland = 'Cumberland Forest', diez_coronas = 'Diez Coronas',
    gaptooth_ridge = 'Gaptooth Ridge', great_plains = 'Great Plains', grizzlies_east = 'Grizzlies East',
    grizzlies_west = 'Grizzlies West', guarma_d = 'Guarma', heartlands = 'The Heartlands',
    hennigans_stead = "Hennigan's Stead", perdido = 'Perdido', punta_orgullo = 'Punta Orgullo',
    rio_bravo = 'Rio Bravo', roanoke = 'Roanoke Ridge', scarlett_meadows = 'Scarlett Meadows',
    tall_trees = 'Tall Trees',
    -- states (type 0)
    ambarino = 'Ambarino', lemoyne = 'Lemoyne', new_hanover = 'New Hanover', west_elizabeth = 'West Elizabeth',
    new_austin = 'New Austin', guarma = 'Guarma',
}

--- A hash as a signed 32-bit number, as natives hand them back, whichever way joaat gave it.
local function s32(h)
    h = math.tointeger(h)
    if not h then return nil end
    h = h & 0xFFFFFFFF
    if h >= 0x80000000 then h = h - 0x100000000 end
    return h
end

local ZONE_BY_HASH = {}
for key, label in pairs(ZONE_NAMES) do ZONE_BY_HASH[s32(hash(key))] = label end
local ZONE_TYPES = { 1, 10, 0 }   -- town, then district, then state

def('GetNameOfZone', function(x, y, z)
    for _, t in ipairs(ZONE_TYPES) do
        local h = s32(N(0x43AD8FC02B429D33, x + 0.0, y + 0.0, z + 0.0, t, Citizen.ResultAsInteger()))   -- GET_MAP_ZONE_AT_COORDS
        local name = h and h ~= 0 and ZONE_BY_HASH[h]
        if name then return name end
    end
    return ''
end)

--- /spurzone (F8): the zone hash at the player for every type GET_MAP_ZONE_AT_COORDS knows, and the name each
--- reads as. To name a place GetNameOfZone leaves blank, add its hash's name to ZONE_NAMES above.
if OWN then RegisterCommand('spurzone', function()
    local c = GetEntityCoords(PlayerPedId())
    for t = 0, 12 do
        local raw = N(0x43AD8FC02B429D33, c.x, c.y, c.z, t, Citizen.ResultAsInteger())
        print(('[spur_core] zone type %d: %s -> %s'):format(t, tostring(raw), tostring(ZONE_BY_HASH[s32(raw) or 0])))
    end
    local name = GetNameOfZone(c.x, c.y, c.z)
    print(('[spur_core] GetNameOfZone: "%s"; GetLabelText of it (%s): "%s"'):format(tostring(name),
        C.kind.GetLabelText == 'mapped' and "spur_core's" or "RedM's", tostring(GetLabelText(name))))
end, false) end

-- ---- blips -------------------------------------------------------------------------------
-- RDR2 blips are made from a style hash, take a sprite *hash*, and are coloured by modifiers.

local STYLE_POINT = 1664425300                   -- the map-point style RedM frameworks use
local STYLE_RADIUS = hash('BLIP_STYLE_RADIUS')
local STYLE_ENTITY = hash('BLIP_STYLE_FRIENDLY')

-- RedM (spur_core, 25 Nov 2026): the blip list. RDR2 cannot list its blips: GTA's GetFirstBlipInfoId / GetNextBlipInfoId,
-- through which whip's minimap and pause map find every blip, have no RDR2 counterpart, and as stubs they answered
-- none, so both maps showed no blips. spur_core's own blips are kept here as they are made (AddBlipFor*), with what
-- GTA would answer about each (sprite, colour, display, alpha, short range, flashing, what it is on), and those
-- lookups read this list (below, after the blip natives). Blips other resources or the game make are not in it.
local blipReg, blipBySprite, blipWalk = {}, {}, {}   -- [blip] = its facts; [GTA sprite] = { [blip] = true }; walks
local function blipSetSprite(b, sprite)
    local r = blipReg[b]
    if not r then return end
    if r.sprite and blipBySprite[r.sprite] then blipBySprite[r.sprite][b] = nil end
    r.sprite = sprite
    blipBySprite[sprite] = blipBySprite[sprite] or {}
    blipBySprite[sprite][b] = true
end
--- A blip just made: `sprite` GTA's first one for its kind (1 a point or a thing, 9 an area), `kind` GTA's blip type.
local function trackBlip(b, sprite, kind, entity)
    if math.type(b) ~= 'integer' or b == 0 then return b end
    local old = blipReg[b]   -- a handle used again
    if old and old.sprite and blipBySprite[old.sprite] then blipBySprite[old.sprite][b] = nil end
    blipReg[b] = { kind = kind, entity = entity or 0, display = 2, alpha = 255, colour = 0 }
    blipSetSprite(b, sprite)
    return b
end
local ENTITY_BLIP = { [1] = 2, [2] = 1, [3] = 3 }   -- GetEntityType (ped, vehicle, object) to GTA's blip type

def('AddBlipForCoord', function(x, y, z)
    return trackBlip(N(0x554D9D53F696D002, STYLE_POINT, x + 0.0, y + 0.0, (z or 0.0) + 0.0, Citizen.ResultAsInteger()), 1, 4)
end)
def('AddBlipForRadius', function(x, y, z, radius)
    return trackBlip(N(0x45F13B7E0A15C880, STYLE_RADIUS, x + 0.0, y + 0.0, (z or 0.0) + 0.0, radius + 0.0,
        Citizen.ResultAsInteger()), 9, 7)
end)
def('AddBlipForEntity', function(entity)
    return trackBlip(N(0x23F74C2FDA6E7C61, STYLE_ENTITY, entity, Citizen.ResultAsInteger()), 1,
        ENTITY_BLIP[GetEntityType(entity)] or 2, entity)
end)

-- GTA sprite numbers whip uses (config and code) -> RDR2 blip textures. A string is taken as an RDR2 sprite
-- name, a hash as an RDR2 sprite hash.
local SPRITE = {
    [1] = 'blip_poi', [9] = 'blip_ambient_npc', [40] = 'blip_proc_home', [52] = 'blip_shop_store',
    [51] = 'blip_shop_doctor', [61] = 'blip_shop_doctor', [71] = 'blip_shop_barber', [73] = 'blip_shop_tailor',
    [93] = 'blip_saloon', [108] = 'blip_proc_bank', [110] = 'blip_shop_gunsmith', [207] = 'blip_proc_bank',
    [225] = 'blip_ambient_coach', [326] = 'blip_ambient_coach', [350] = 'blip_proc_home', [357] = 'blip_player_coach',
    [374] = 'blip_proc_home', [375] = 'blip_proc_home', [411] = 'blip_proc_home', [492] = 'blip_proc_home',
    [500] = 'blip_proc_bank',
}
local function spriteHash(sprite)
    if type(sprite) == 'string' then return hash(sprite) end
    if math.type(sprite) == 'integer' and sprite >= 0 and sprite < 1000 then
        return hash(SPRITE[sprite] or 'blip_poi')
    end
    return sprite
end
C.spriteHash = spriteHash
force('SetBlipSprite', function(blip, sprite)
    N(0x74F74D3207ED525C, blip, spriteHash(sprite), true)
    if math.type(sprite) == 'integer' and sprite >= 0 and sprite < 1000 then blipSetSprite(blip, sprite) end   -- RedM (spur_core, 25 Nov 2026)
end)

-- GTA blip colour numbers -> the RDR2 modifiers that only set a colour. Colours with none (blues, greens,
-- purples, pinks) keep the style's own colour.
local MOD = {
    white = hash('BLIP_MODIFIER_PLAYER_HORSE_IN_RANGE'), red = hash('BLIP_MODIFIER_AREA_OUT_OF_BOUNDS'),
    orange = hash('BLIP_MODIFIER_RACE_CHECKPOINT_ALT'), yellow = hash('BLIP_MODIFIER_KEY_MISSION'),
    grey = hash('BLIP_MODIFIER_MP_PLAYER_NEUTRAL'),
}
local COLOUR = {
    [0] = 'white', [4] = 'white', [1] = 'red', [6] = 'red', [49] = 'red', [59] = 'red', [75] = 'red', [76] = 'red',
    [17] = 'orange', [44] = 'orange', [47] = 'orange', [81] = 'orange',
    [5] = 'yellow', [28] = 'yellow', [33] = 'yellow', [36] = 'yellow', [46] = 'yellow', [66] = 'yellow',
    [70] = 'yellow', [73] = 'yellow',
    [20] = 'grey', [39] = 'grey', [40] = 'grey', [55] = 'grey', [62] = 'grey', [72] = 'grey',
}
local blipMod = {}                                -- blip -> the colour modifier applied, so a new one replaces it
def('SetBlipColour', function(blip, colour)
    local m = MOD[COLOUR[colour] or '']
    if blipMod[blip] and blipMod[blip] ~= m then N(0xB059D7BD3D78C16F, blip, blipMod[blip]) end   -- BLIP_REMOVE_MODIFIER
    blipMod[blip] = m
    if m then N(0x662D364ABF16DE2F, blip, m) end                                                 -- BLIP_ADD_MODIFIER
    if blipReg[blip] then blipReg[blip].colour = colour end                                     -- RedM (spur_core, 25 Nov 2026)
end)
-- RedM's SetBlipFlashes reads pointers (it is another native under that name): flashing is a modifier in RDR2.
local FLASH = hash('BLIP_MODIFIER_FLASH_FOREVER')
force('SetBlipFlashes', function(blip, toggle)
    N(toggle and 0x662D364ABF16DE2F or 0xB059D7BD3D78C16F, blip, FLASH)                          -- BLIP_ADD/REMOVE_MODIFIER
    if blipReg[blip] then blipReg[blip].flash = toggle and true or nil end                      -- RedM (spur_core, 25 Nov 2026)
end)

-- Blip names: GTA spells them out as a text command; RDR2 takes the string.
def('BeginTextCommandSetBlipName', function() startText() end)
def('EndTextCommandSetBlipName', function(blip)
    N(0x9CB1A1623062F402, blip, takeText())                                                     -- _SET_BLIP_NAME
end)

def('GetBlipInfoIdCoord', function(blip) return N(0x201C319797BDA603, blip, Citizen.ResultAsVector()) end)   -- GET_BLIP_COORDS

-- RedM (spur_core, 25 Nov 2026): GTA's blip lookups, over the blip list (above). Settings RDR2 has no counterpart for (display,
-- alpha, short range) are only remembered, for whip's maps to read; they change nothing on RDR2's own map.
if not SERVER then
    def('GetFirstBlipInfoId', function(sprite)
        local set = blipBySprite[sprite]
        if not set or next(set) == nil then blipWalk[sprite] = nil return 0 end
        local w = blipWalk[sprite] or { list = {} }
        blipWalk[sprite] = w
        local list, n = w.list, 0
        for b in pairs(set) do
            if DoesBlipExist(b) then n = n + 1 list[n] = b else set[b] = nil blipReg[b] = nil end   -- removed since
        end
        for k = #list, n + 1, -1 do list[k] = nil end
        w.i = 1
        return list[1] or 0
    end)
    def('GetNextBlipInfoId', function(sprite)
        local w = blipWalk[sprite]
        if not w then return 0 end
        w.i = w.i + 1
        return w.list[w.i] or 0
    end)
    local function fact(b, key, none)
        local r = blipReg[b]
        if r == nil or r[key] == nil then return none end
        return r[key]
    end
    def('GetBlipInfoIdDisplay', function(b) return fact(b, 'display', 0) end)
    def('GetBlipAlpha', function(b) return fact(b, 'alpha', 0) end)
    def('IsBlipShortRange', function(b) return fact(b, 'short', false) end)
    def('IsBlipFlashing', function(b) return fact(b, 'flash', false) end)
    def('GetBlipInfoIdType', function(b) return fact(b, 'kind', 0) end)
    def('GetBlipInfoIdEntityIndex', function(b) return fact(b, 'entity', 0) end)
    def('SetBlipDisplay', function(b, d) if blipReg[b] then blipReg[b].display = d end end)
    def('SetBlipAlpha', function(b, a) if blipReg[b] then blipReg[b].alpha = a end end)
    def('SetBlipAsShortRange', function(b, on) if blipReg[b] then blipReg[b].short = on and true or false end end)
    -- A blip's colour on whip's maps: GTA answers a HUD colour, which GetHudColour turns into RGB. RDR2 has
    -- neither, so a blip answers 1000 + its GTA blip colour, and GetHudColour gives that colour's RGB (GTA's
    -- palette, near enough). Any other HUD colour stays white, as the stub was.
    local BLIP_RGB = {
        [0] = 0xfefefe, 0xe03232, 0x71cb71, 0x5db6e5, 0xfefefe, 0xeec64e, 0xc25050, 0x9c6eaf, 0xfe7ac3, 0xf59d79,
        0xb18f83, 0x8dcea7, 0x70a8ae, 0xd3d1e7, 0x8f7e98, 0x6ac4bf, 0xd5c398, 0xea8e50, 0x97cae9, 0xb26287,
        0x8f8d79, 0xa6755e, 0xafa8a8, 0xe78d9a, 0xbbd65b, 0x0c7b56, 0x7ac3fe, 0xab3ce6, 0xcda80c, 0x4561ab,
        0x29a5b8, 0xb89b7b, 0xc8e0fe, 0xf0f096, 0xed8ca1, 0xf98a8a, 0xfbeea5, 0xfefefe, 0x2c6db8, 0x9a9a9a,
        0x4c4c4c,
    }
    def('GetBlipHudColour', function(b) return 1000 + fact(b, 'colour', 0) end)
    def('GetHudColour', function(hud)
        local rgb = math.type(hud) == 'integer' and hud >= 1000 and BLIP_RGB[hud - 1000] or 0xfefefe
        return (rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255, 255
    end)
end

-- Waypoints. GTA finds the waypoint as the first blip with sprite 8; whip's four lookups go through
-- RdrCompat.waypoint() instead. SetNewWaypoint has no RDR2 counterpart: it draws a GPS route to the point and is
-- remembered as the waypoint until the player sets or clears one.
local setWaypoint
function C.waypoint()
    if truthy(N(0x202B1BBFC6AB5EE4, Citizen.ResultAsInteger())) then                           -- IS_WAYPOINT_ACTIVE
        local c = N(0x29B30D07C3F7873B, Citizen.ResultAsVector())                               -- _GET_WAYPOINT_COORDS
        setWaypoint = nil
        return c
    end
    return setWaypoint
end
def('SetNewWaypoint', function(x, y)
    setWaypoint = vector3(x + 0.0, y + 0.0, 0.0)
    N(0x9E0AB9AAEE87CE28)                                                                       -- CLEAR_GPS_MULTI_ROUTE
    N(0x3D3D15AF7BCAAF83, hash('COLOR_YELLOW'), true, true)                                     -- START_GPS_MULTI_ROUTE
    N(0x64C59DD6834FA942, x + 0.0, y + 0.0, 0.0, false)                                         -- ADD_POINT_TO_GPS_MULTI_ROUTE
    N(0x4426D65E029A4DC0, true)                                                                 -- SET_GPS_MULTI_ROUTE_RENDER
end)
local rdrWaypointOff = SetWaypointOff
force('SetWaypointOff', function()
    if setWaypoint then N(0x9E0AB9AAEE87CE28) end
    setWaypoint = nil
    if rdrWaypointOff then rdrWaypointOff() else N(0xFA8C41E8020D3439) end
end)

-- ---- world & screen ------------------------------------------------------------------------

-- GTA's StartShapeTestRay is the synchronous LOS probe (same hash on both games): the result is ready at once,
-- which is how whip reads it.
def('StartShapeTestRay', function(x1, y1, z1, x2, y2, z2, flags, ignore, p8)
    return N(0x377906D8A31E5586, x1 + 0.0, y1 + 0.0, z1 + 0.0, x2 + 0.0, y2 + 0.0, z2 + 0.0, flags or -1,
        ignore or 0, p8 or 0, Citizen.ResultAsInteger())
end)

def('NewLoadSceneStartSphere', function(x, y, z, radius, p4)
    return truthy(N(0x513F8AA5BF2F17CF, x + 0.0, y + 0.0, z + 0.0, radius + 0.0, p4 or 0, Citizen.ResultAsInteger()))
end)
def('NewLoadSceneStart', function(x, y, z, ox, oy, oz, radius, p7)
    return truthy(N(0x387AD749E3B69B70, x + 0.0, y + 0.0, z + 0.0, ox + 0.0, oy + 0.0, oz + 0.0, radius + 0.0,
        p7 or 0, Citizen.ResultAsInteger()))
end)
def('NewLoadSceneStop', function() N(0x5A8B01199C3E79C3) end)
def('IsNewLoadSceneLoaded', function() return truthy(N(0x0909F71B5C070797, Citizen.ResultAsInteger())) end)

-- RDR2 gives an interior's position but not its rotation: the offset is added unrotated (exact for interiors
-- placed square to the world, which the property tools should check in game).
def('GetOffsetFromInteriorInWorldCoords', function(interior, x, y, z)
    local o = N(0x2C9746D0CA15BE1C, interior, Citizen.ResultAsVector())                        -- _GET_INTERIOR_POSITION
    return vector3(o.x + x, o.y + y, o.z + z)
end)

def('World3dToScreen2d', function(x, y, z)
    if GetScreenCoordFromWorldCoord then return GetScreenCoordFromWorldCoord(x + 0.0, y + 0.0, z + 0.0) end
    local r, sx, sy = N(0xCB50D7AFCC8B0EC6, x + 0.0, y + 0.0, z + 0.0, Citizen.PointerValueFloat(),
        Citizen.PointerValueFloat(), Citizen.ResultAsInteger())
    return truthy(r), sx, sy
end)
def('GetActiveScreenResolution', function()
    if GetScreenResolution then return GetScreenResolution() end
    return N(0x66773C92835D0909, Citizen.PointerValueInt(), Citizen.PointerValueInt())
end)
quiet('GetSafeZoneSize', 'client', 1.0)

def('IsUsingKeyboard', function(c) return truthy(N(0xA571D46727E2B718, c or 0, Citizen.ResultAsInteger())) end)
-- GTA's IsInputDisabled(2) is "the player is on keyboard and mouse".
def('IsInputDisabled', function(c) return truthy(N(0xA571D46727E2B718, 0, Citizen.ResultAsInteger())) end)

-- GTA weather names -> RDR2's (RDR2 names pass through).
local WEATHER = {
    EXTRASUNNY = 'SUNNY', CLEAR = 'HIGHPRESSURE', NEUTRAL = 'SUNNY', SMOG = 'MISTY', FOGGY = 'FOG',
    CLOUDS = 'CLOUDS', OVERCAST = 'OVERCAST', RAIN = 'RAIN', THUNDER = 'THUNDERSTORM', CLEARING = 'DRIZZLE',
    SNOW = 'SNOW', BLIZZARD = 'BLIZZARD', SNOWLIGHT = 'SNOWLIGHT', XMAS = 'SNOW', HALLOWEEN = 'OVERCASTDARK',
}
function C.weatherHash(name)
    if type(name) ~= 'string' then return name end
    local up = name:upper()
    return hash(WEATHER[up] or up)
end
local function setWeather(name)
    N(0x59174F1AFE095B5A, C.weatherHash(name), true, true, true, 0.0, false)                     -- SET_WEATHER_TYPE
end
def('SetWeatherTypeNow', setWeather)
def('SetWeatherTypeNowPersist', function(name)
    setWeather(name)
    N(0xD74ACDF7DB8114AF, true)                                                                 -- _SET_WEATHER_TYPE_FROZEN
end)
def('NetworkOverrideClockTime', function(h, m, s)
    N(0x669E223E64B1903C, h, m, s or 0, 0, false)                                               -- _NETWORK_CLOCK_TIME_OVERRIDE
end)

-- Doors: RDR2 doors are the game's own, by door hash (no model or position). The hash has to be an RDR2 door
-- (CONVERSION.md: doors).
def('AddDoorToSystem', function(doorHash)
    N(0xD99229FE93B46286, doorHash, true, true, false, 0, 0, false)                             -- _ADD_DOOR_TO_SYSTEM_NEW
end)

-- ---- natives RedM has under the same name, with other arguments ------------------------------
-- whip passes GTA's arguments; these take them and call RDR2's version. Raw calls, so numbers are made floats
-- where RDR2 reads a float, and a string RDR2 reads as a hash is hashed.

local function f(v) return (tonumber(v) or 0) + 0.0 end
local function toHash(s) return type(s) == 'string' and hash(s) or s end

-- GTA: (pedType, model, ...). RDR2 has no ped type, and a ped it spawns has no outfit (it is invisible) until
-- one is put on: a random one here, which the appearance code replaces for the player's own peds.
-- (Client only: the server's CreatePed is FiveM's own and keeps GTA's arguments on RedM.)
force('CreatePed', function(_, model, x, y, z, heading, isNetwork, scriptHost)
    local ped = N(0xD49F9B0955C367DE, model, f(x), f(y), f(z), f(heading), isNetwork == true, scriptHost == true,
        false, false, Citizen.ResultAsInteger())                                                -- CREATE_PED
    if ped and ped ~= 0 then N(0x283978A15512B2FE, ped, true) end                               -- _SET_RANDOM_OUTFIT_VARIATION
    return ped
end)

-- GTA: eight booleans. RDR2: one bitset (femga AI/ENTITY_PROOFS): 1 bullet, 2 fire, 4 explosion, 8 collision,
-- 16 melee, 32 steam, 64 smoke, 128 headshot, 256 projectile. GTA's p7 reads as smoke; RDR2 has no drown proof.
local PROOF = { 1, 2, 4, 8, 16, 32, 64 }
force('SetEntityProofs', function(entity, ...)
    local on, bits = { ... }, 0
    for i, bit in ipairs(PROOF) do if on[i] then bits = bits | bit end end
    if on[1] then bits = bits | 128 | 256 end              -- GTA's bullet proof covers headshots and arrows too
    N(0xFAEE099C6F890BB8, entity, bits, false)                                                   -- SET_ENTITY_PROOFS
end)
force('GetEntityProofs', function(entity)
    local bits = N(0x6CF0DAD7FA1088EA, entity, Citizen.ResultAsInteger()) or 0                   -- _GET_ENTITY_PROOFS
    local r = { true }
    for i, bit in ipairs(PROOF) do r[i + 1] = bits & bit ~= 0 end
    r[9] = false
    return table.unpack(r, 1, 9)
end)

-- GTA: (soundId, name, soundset, p3); RDR2: (name, soundset, p2, p3), with its own sounds. The GTA sounds whip
-- plays -> RDR2 menu sounds (femga audio/frontend_soundsets); others are skipped.
local FRONTEND = {
    ['HUD_FRONTEND_DEFAULT_SOUNDSET/NAV_UP_DOWN'] = { 'NAV_DOWN', 'HUD_PLAYER_MENU' },
    ['HUD_FRONTEND_DEFAULT_SOUNDSET/NAV_LEFT_RIGHT'] = { 'NAV_RIGHT', 'HUD_PLAYER_MENU' },
    ['HUD_FRONTEND_DEFAULT_SOUNDSET/SELECT'] = { 'SELECT', 'HUD_PLAYER_MENU' },
    ['HUD_FRONTEND_DEFAULT_SOUNDSET/BACK'] = { 'BACK', 'HUD_PLAYER_MENU' },
    ['HUD_FRONTEND_DEFAULT_SOUNDSET/WAYPOINT_SET'] = { 'INFO_SHOW', 'Ledger_Sounds' },
    ['HUD_MINI_GAME_SOUNDSET/3_2_1'] = { 'round_start_countdown_tick', 'RDRO_Poker_Sounds' },
    ['HUD_MINI_GAME_SOUNDSET/GO'] = { 'CHECKPOINT_PERFECT', 'HUD_MINI_GAME_SOUNDSET' },
}
force('PlaySoundFrontend', function(a, b, c, d)
    if type(a) == 'string' then                             -- already RDR2's form
        return N(0x67C540AA08E4A6F5, a, b, c == true, d or 0)
    end
    local s = FRONTEND[tostring(c) .. '/' .. tostring(b)]
    if s then N(0x67C540AA08E4A6F5, s[1], s[2], true, 0) else noteHit('PlaySoundFrontend ' .. tostring(c) .. '/' .. tostring(b)) end
end)

-- RDR2's ambient speech takes a struct of speech parameters, not GTA's line name.
force('PlayPedAmbientSpeechNative', function() noteHit('PlayPedAmbientSpeechNative') end)

-- RDR2 reads a weapon's damage from a weapon object, not its hash: whip's director shows 0.
force('GetWeaponDamage', function() noteHit('GetWeaponDamage'); return 0.0 end)

-- GTA: (entity) -> fire id; RDR2: (entity, intensity, bone, flags).
force('StartEntityFire', function(entity)
    N(0xC4DC7418A44D6822, entity, 1.0, 0, 0)                                                     -- START_ENTITY_FIRE
    return 0
end)

-- GTA: (ped, weapon, ammo, isHidden, forceInHand); RDR2 adds holster, attach point, add reason and so on.
-- RedM (spur_core, 24 Nov 2026): bIgnoreUnlocks (the 11th) is on. With it off the weapon reached the ped's inventory
-- some time under 500 ms later (spur_gunny's /gunnygivelab), so the SetCurrentPedWeapon that follows a give failed:
-- Steal the Car's guards were given their card's gun but kept their model's own rifle in hand. With it on the
-- weapon is there at once. The server decides who carries what, not RDR2's unlocks.
local ADD_REASON, REMOVE_REASON = hash('ADD_REASON_DEFAULT'), hash('REMOVE_REASON_DEFAULT')
force('GiveWeaponToPed', function(ped, weapon, ammo, _, forceInHand)
    N(0x5E3BDDBCB83F3D84, ped, weapon, math.floor(tonumber(ammo) or 0), forceInHand == true, false, 0, false,
        0.5, 1.0, ADD_REASON, true, 0.0, false)                                                  -- GIVE_WEAPON_TO_PED
end)
force('RemoveWeaponFromPed', function(ped, weapon)
    N(0x4899CB088EDF59B8, ped, weapon, true, REMOVE_REASON)                                      -- REMOVE_WEAPON_FROM_PED
end)
-- RedM (spur_core, 24 Nov 2026): RedM's own IsWeaponValid answers a number (1 was printed for a real gun in
-- /gunnygivelab), and 0 is true in Lua, so every weapon read as valid. Read as a number here.
force('IsWeaponValid', function(weapon)
    return truthy(N(0x937C71165CF334B3, weapon, Citizen.ResultAsInteger()))                     -- IS_WEAPON_VALID
end)

-- GTA: (ped, from, distance, time, preferPavements, updateToNearest); RDR2: (..., fleeType, speed, targetPed).
force('TaskSmartFleePed', function(ped, from, distance, time)
    N(0x22B0D0E37CCB840D, ped, from, f(distance), math.floor(tonumber(time) or -1), 0, 3.0, 0)  -- TASK_SMART_FLEE_PED
end)

-- GTA's last three are lockX/Y/Z; RDR2's are p8, ik flags, p10, a task filter (a string) and p12, so they are
-- not passed on. The flag bits below 64 (loop, hold, upper body, secondary...) are the same in both games.
force('TaskPlayAnim', function(ped, dict, name, blendIn, blendOut, duration, flags, rate)
    N(0xEA47FE3719165B94, ped, dict, name, f(blendIn or 8.0), f(blendOut or -8.0), math.floor(tonumber(duration) or -1),
        math.floor(tonumber(flags) or 0), f(rate), false, 0, false, 0, false)                   -- TASK_PLAY_ANIM
end)

-- GTA's last one is a task message name in RDR2 (a string): not passed on.
force('SetPedToRagdoll', function(ped, t1, t2, kind, p4, p5)
    return truthy(N(0xAE99FB955581844A, ped, math.floor(tonumber(t1) or 0), math.floor(tonumber(t2) or 0),
        math.floor(tonumber(kind) or 0), p4 == true, p5 == true, 0, Citizen.ResultAsInteger()))  -- SET_PED_TO_RAGDOLL
end)

-- Named by GTA as strings, by RDR2 as hashes.
force('RequestNamedPtfxAsset', function(asset) N(0xF2B2353BBC0D4E8F, toHash(asset)) end)
force('HasNamedPtfxAssetLoaded', function(asset)
    return truthy(N(0x65BB72F29138F5D6, toHash(asset), Citizen.ResultAsInteger()))
end)
force('SetOverrideWeather', function(weather) N(0xBE83CAE8ED77A94F, C.weatherHash(weather)) end)   -- _SET_OVERRIDE_WEATHER
force('TaskStartScenarioAtPosition', function(ped, scenario, x, y, z, heading, duration, sitting, teleport)
    N(0x4D1F61FC34AF3CD1, ped, toHash(scenario), f(x), f(y), f(z), f(heading), math.floor(tonumber(duration) or -1),
        sitting == true, teleport == true, 0, -1.0, false)                                       -- TASK_START_SCENARIO_AT_POSITION
end)

-- RDR2 adds a second float (undocumented); 1.0 is passed.
force('SetGameplayCamRelativeHeading', function(heading) N(0x5D1EB123EAC5D071, f(heading), 1.0) end)

-- ---- peds ----------------------------------------------------------------------------------

-- Scenarios: GTA takes the name, RDR2 the hash. RedM's TaskStartScenarioInPlace takes the hash, so this replaces it.
function C.scenarioHash(s) return type(s) == 'string' and hash(s) or s end
force('TaskStartScenarioInPlace', function(ped, scenario, duration, playEnter)
    if not duration or duration == 0 then duration = -1 end      -- GTA's 0 is "no delay"; RDR2's -1 is "until stopped"
    N(0x524B54361229154F, ped, C.scenarioHash(scenario), duration, playEnter ~= false, 0, -1.0, false)
end)
force('IsPedUsingScenario', function(ped, scenario)
    return truthy(N(0x34D6AC1157C8226C, ped, C.scenarioHash(scenario), Citizen.ResultAsInteger()))
end)

def('GetSelectedPedWeapon', function(ped)
    local _, weapon = N(0x3A87E44BB9A01D54, ped, Citizen.PointerValueInt(), true, 0, true, Citizen.ReturnResultAnyway())
    return weapon or hash('WEAPON_UNARMED')
end)

-- RDR2 has no armour. Kept per ped so whip's UI reads back what it set; it stops no damage (CONVERSION.md).
local armour = {}
def('SetPedArmour', function(ped, amount) armour[ped] = math.max(0, math.min(100, tonumber(amount) or 0)) end)
def('GetPedArmour', function(ped) return armour[ped] or 0 end)

-- Clothing. RDR2 dresses a ped with metaped outfit presets, not GTA's numbered components, and a ped with none
-- is invisible. Slot 11 (Tops) stands for the preset: drawable N is preset N (wrapped to how many the model has),
-- so the creator's Tops cards pick a whole RDR2 outfit and a saved appearance keeps it. The other slots, props,
-- hair, face and overlays stay stubs (rdr_compat_stubs.lua).
if not SERVER then
    local OUTFIT_SLOT = 11
    local outfitOf = {}     -- [ped] = preset put on through here

    local function numOutfits(ped)
        return N(0x10C70A515BC03707, ped, Citizen.ResultAsInteger()) or 0                       -- GET_NUM_META_PED_OUTFITS
    end

    -- RedM (spur_core, 23 Nov 2026): THE BODY. A freemode ped (mp_male, mp_female) has no head, body, eyes or
    -- teeth until shop items for them are put on, and no outfit preset carries them: without these it is floating
    -- clothes. The items come from femga's rdr3_discoveries clothes list, and each item's hash is the joaat of its
    -- name, so the names are built here and hashed. whip's head blend stands for the body: the mother card picks the
    -- head, the father card the build (1-5) and the skin mix the skin tone (1-6). The eye colour picks the eyes.
    -- Hair style (slot 2) and colour pick an RDR2 hair, and the beard overlay (1) and its colour a beard (men only).
    -- An outfit preset replaces every item when it lands, so all of these go back on after one (settle).
    local HEADS = {     -- the head numbers each model has (every one in all six tones)
        M = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 18, 21, 22, 25, 28 },
        F = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 20, 22, 27, 28 },
    }
    local HAIRS = {     -- slot 2's drawable n (1 and up) is the nth of these; 0 is no hair
        M = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 28 },
        F = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28 },
    }
    local BEARDS = 24   -- men's beards 001-024; the beard overlay's index n is beard n + 1
    -- Every hair and beard comes in these 17 colours. The creator's palette index n is the (n + 1)th, and the RGB
    -- is an approximation for its swatches (GetPedHairRgbColor).
    local HAIR_COLOURS = {
        { 'JET_BLACK', 20, 18, 17 }, { 'DARKEST_BROWN', 40, 28, 22 }, { 'BROWN', 75, 50, 35 },
        { 'MEDIUM_BROWN', 95, 65, 45 }, { 'LIGHT_BROWN', 125, 90, 60 }, { 'DARK_BLONDE', 150, 115, 75 },
        { 'BLONDE', 185, 150, 100 }, { 'LIGHT_BLONDE', 215, 190, 140 }, { 'STRAWBERRY_BLONDE', 190, 130, 90 },
        { 'DARK_GINGER', 120, 55, 30 }, { 'GINGER', 160, 75, 40 }, { 'LIGHT_GINGER', 195, 110, 65 },
        { 'SALT_PEPPER', 110, 105, 100 }, { 'DARK_GREY', 80, 80, 80 }, { 'GREY', 130, 130, 128 },
        { 'LIGHT_GREY', 175, 175, 172 }, { 'UNCLE_GREY', 205, 205, 200 },
    }
    local CAT_HAIR, CAT_BEARD = hash('hair'), hash('beards_complete')     -- metaped categories (joaat of the name)
    local BUILDS, TONES, EYES = 5, 6, 14
    local DEFAULT_BODY = { head = 0, build = 0, tone = 4, eyes = 0, hair = 0, hairColour = 0, beard = -1, beardColour = 0 }
    local bodyOf = {}       -- [ped] = { head, build, tone, eyes } put on through here

    local function sexOf(ped)
        local m = GetEntityModel(ped)
        if m == hash('mp_male') then return 'M' end
        if m == hash('mp_female') then return 'F' end
        return nil
    end

    local function applyItem(ped, name)
        N(0xD3A7B003ED343FD9, ped, hash(name), true, true, true)                                -- _APPLY_SHOP_ITEM_TO_PED
    end

    local function refresh(ped)
        N(0xCC8CA3E88256E58F, ped, false, true, true, true, false)                              -- _UPDATE_PED_VARIATION
    end

    local function readyToRender(ped)
        local r = N(0xA0BC8FAED8CFEB3C, ped, Citizen.ResultAsInteger())                         -- _IS_PED_READY_TO_RENDER
        return math.type(r) == 'integer' and (r & 0xFF) ~= 0
    end

    --- Puts the body `b` on a freemode ped. False for any other model (an NPC model comes whole).
    local function putBody(ped, b)
        local g = sexOf(ped)
        if not g then return false end
        local heads = HEADS[g]
        local head, build, tone = heads[(b.head % #heads) + 1], (b.build % BUILDS) + 1, b.tone
        applyItem(ped, ('CLOTHING_ITEM_%s_HEAD_%03d_V_%03d'):format(g, head, tone))
        applyItem(ped, ('CLOTHING_ITEM_%s_BODIES_UPPER_%03d_V_%03d'):format(g, build, tone))
        applyItem(ped, ('CLOTHING_ITEM_%s_BODIES_LOWER_%03d_V_%03d'):format(g, build, tone))
        applyItem(ped, ('CLOTHING_ITEM_%s_EYES_001_TINT_%03d'):format(g, (b.eyes % EYES) + 1))
        applyItem(ped, ('CLOTHING_ITEM_%s_TEETH_000'):format(g))
        local hairs = HAIRS[g]
        if (b.hair or 0) > 0 then
            applyItem(ped, ('CLOTHING_ITEM_%s_HAIR_%03d_%s'):format(g, hairs[((b.hair - 1) % #hairs) + 1],
                HAIR_COLOURS[((b.hairColour or 0) % #HAIR_COLOURS) + 1][1]))
        else
            N(0xD710A5007C2AC539, ped, CAT_HAIR, 0)                                             -- _REMOVE_TAG_FROM_META_PED
        end
        if g == 'M' and (b.beard or -1) >= 0 then
            applyItem(ped, ('CLOTHING_ITEM_M_BEARD_%03d_%s'):format((b.beard % BEARDS) + 1,
                HAIR_COLOURS[((b.beardColour or 0) % #HAIR_COLOURS) + 1][1]))
        else
            N(0xD710A5007C2AC539, ped, CAT_BEARD, 0)
        end
        return true
    end
    C.putBody = putBody

    -- An outfit preset streams in and lands a moment after it is asked for, and when it lands it can replace every
    -- item on the ped, the body's too. A ped made a moment ago keeps the body only if it goes on with the preset, and
    -- the player's ped only if it goes on after the preset has landed. So it goes on with the preset (equipOutfit),
    -- once the ped is ready to render, and again a moment later. One job per ped: a newer one (another preset,
    -- another head) stands the older down.
    local settleGen = {}
    local settleBody = {}   -- [ped] = true while a job that puts the body on is pending: a newer job keeps that
    -- RedM (spur_core, 23 Nov 2026): a ped made a moment ago (the character screen's, the inventory's) drops an outfit
    -- preset asked for before it is ready to render, and can drop body items with it: the character screen showed the
    -- character shirtless, or bald, while the same character in the world was dressed. Asked for again once the ped is
    -- ready, the preset lands (tried in game). So the first preset put on a ped, and one asked for while the ped isn't
    -- ready, is asked for again on settle's first pass, and the body goes back on after it. Per ped, not per job: a
    -- newer job (a hair or eye change in the creator) carries it on, as it does the body.
    local pendingPreset = {}    -- [ped] = preset to ask for again once the ped is ready
    local bodyFor
    local function settle(ped, withBody)
        withBody = withBody or settleBody[ped] or false
        settleBody[ped] = withBody or nil
        local gen = (settleGen[ped] or 0) + 1
        settleGen[ped] = gen
        CreateThread(function()
            for pass = 1, 2 do
                Wait(pass == 1 and 0 or 300)
                local deadline = GetGameTimer() + 3000
                while not readyToRender(ped) and GetGameTimer() < deadline do Wait(0) end
                if settleGen[ped] ~= gen or not DoesEntityExist(ped) then return end
                local again = pendingPreset[ped]
                if again then
                    pendingPreset[ped] = nil
                    N(0x77FF8D35EEC6BBC4, ped, again, false)                                    -- _EQUIP_META_PED_OUTFIT_PRESET
                end
                if withBody or again then putBody(ped, bodyFor(ped)) end
                refresh(ped)
            end
            settleGen[ped] = nil
            settleBody[ped] = nil
        end)
    end

    bodyFor = function(ped)
        local b = bodyOf[ped]
        if not b then
            b = {}
            for k, v in pairs(DEFAULT_BODY) do b[k] = v end
            bodyOf[ped] = b
        end
        return b
    end

    -- GTA: (ped, shape mother, father, third, skin mother, father, third, shape mix, skin mix, third mix, isParent).
    force('SetPedHeadBlendData', function(ped, mom, dad, _, _, _, _, _, skinMix)
        if not ped or ped == 0 or not DoesEntityExist(ped) or not sexOf(ped) then return end
        local b = bodyFor(ped)
        b.head = math.max(0, math.floor(tonumber(mom) or 0))
        b.build = math.max(0, math.floor(tonumber(dad) or 0))
        b.tone = math.max(1, math.min(TONES, math.floor((tonumber(skinMix) or 0.5) * TONES) + 1))
        putBody(ped, b)
        refresh(ped)
        settle(ped, true)
    end)
    force('HasPedHeadBlendFinished', function() return true end)
    force('SetPedEyeColor', function(ped, index)
        if not ped or ped == 0 or not DoesEntityExist(ped) then return end
        local g = sexOf(ped)
        if not g then return end
        local b = bodyFor(ped)
        b.eyes = math.max(0, math.floor(tonumber(index) or 0))
        applyItem(ped, ('CLOTHING_ITEM_%s_EYES_001_TINT_%03d'):format(g, (b.eyes % EYES) + 1))
        refresh(ped)
        settle(ped, false)
    end)

    --- Puts outfit preset `preset` on `ped` (wrapped into range) and refreshes it. A model with no presets gets
    --- a random outfit variation instead. A freemode ped's body goes back on after it (putBody).
    function C.equipOutfit(ped, preset)
        if not ped or ped == 0 or not DoesEntityExist(ped) then return end
        local n = numOutfits(ped)
        local p = math.floor(tonumber(preset) or 0)
        if n > 0 then
            p = p % n
            -- RedM (spur_core, 23 Nov 2026): asked for again once the ped is ready (pendingPreset).
            if outfitOf[ped] == nil or not readyToRender(ped) then pendingPreset[ped] = p end
            N(0x77FF8D35EEC6BBC4, ped, p, false)                                                -- _EQUIP_META_PED_OUTFIT_PRESET
        else
            p = 0
            N(0x283978A15512B2FE, ped, true)                                                    -- _SET_RANDOM_OUTFIT_VARIATION
        end
        putBody(ped, bodyFor(ped))
        refresh(ped)
        settle(ped, true)     -- and again once the preset has landed
        outfitOf[ped] = p
    end

    -- Hair and beard: change one, put the body's items back on (the hair rides with the body, see putBody).
    local HAIR_SLOT, BEARD_OVERLAY = 2, 1
    local function rebody(ped)
        if not ped or ped == 0 or not DoesEntityExist(ped) or not sexOf(ped) then return nil end
        return bodyFor(ped)
    end
    local function rebodyDone(ped, b)
        putBody(ped, b)
        refresh(ped)
        settle(ped, true)
    end

    force('SetPedComponentVariation', function(ped, comp, drawable)
        if comp == OUTFIT_SLOT then return C.equipOutfit(ped, drawable) end
        if comp == HAIR_SLOT then
            local b = rebody(ped)
            if b then
                b.hair = math.max(0, math.floor(tonumber(drawable) or 0))
                rebodyDone(ped, b)
            end
            return
        end
        noteHit('SetPedComponentVariation')
    end)
    force('GetNumberOfPedDrawableVariations', function(ped, comp)
        if comp == OUTFIT_SLOT then return numOutfits(ped) end
        if comp == HAIR_SLOT then
            local g = sexOf(ped)
            return g and (#HAIRS[g] + 1) or 0
        end
        noteHit('GetNumberOfPedDrawableVariations')
        return 0
    end)
    force('GetNumberOfPedTextureVariations', function(ped, comp)
        if comp == OUTFIT_SLOT or comp == HAIR_SLOT then return 1 end
        noteHit('GetNumberOfPedTextureVariations')
        return 0
    end)
    force('GetPedDrawableVariation', function(ped, comp)
        if comp == OUTFIT_SLOT then return outfitOf[ped] or 0 end
        if comp == HAIR_SLOT then return (bodyOf[ped] and bodyOf[ped].hair) or 0 end
        noteHit('GetPedDrawableVariation')
        return 0
    end)
    force('GetNumHairColors', function() return #HAIR_COLOURS end)
    force('GetPedHairRgbColor', function(i)
        local c = HAIR_COLOURS[(math.floor(tonumber(i) or 0) % #HAIR_COLOURS) + 1]
        return c[2], c[3], c[4]
    end)
    force('SetPedHairColor', function(ped, colour)
        local b = rebody(ped)
        if not b then return end
        colour = math.max(0, math.floor(tonumber(colour) or 0))
        if colour == b.hairColour then return end
        b.hairColour = colour
        rebodyDone(ped, b)
    end)
    force('GetPedHairColor', function(ped) return (bodyOf[ped] and bodyOf[ped].hairColour) or 0 end)
    force('GetPedHairHighlightColor', function(ped) return (bodyOf[ped] and bodyOf[ped].hairColour) or 0 end)
    force('GetPedHeadOverlayNum', function(overlay)
        if overlay == BEARD_OVERLAY then return BEARDS end
        noteHit('GetPedHeadOverlayNum')
        return 0
    end)
    -- GTA: (ped, overlay, index, opacity); index 255 or opacity 0 is none.
    force('SetPedHeadOverlay', function(ped, overlay, index, opacity)
        if overlay ~= BEARD_OVERLAY then return noteHit('SetPedHeadOverlay') end
        local b = rebody(ped)
        if not b then return end
        index = math.floor(tonumber(index) or 255)
        local beard = (index >= 0 and index < 255 and (tonumber(opacity) or 1.0) > 0.0) and index or -1
        if beard == b.beard then return end
        b.beard = beard
        rebodyDone(ped, b)
    end)
    -- GTA: (ped, overlay, colour type, colour, second colour).
    force('SetPedHeadOverlayColor', function(ped, overlay, _, colour)
        if overlay ~= BEARD_OVERLAY then return noteHit('SetPedHeadOverlayColor') end
        local b = rebody(ped)
        if not b then return end
        colour = math.max(0, math.floor(tonumber(colour) or 0))
        if colour == b.beardColour then return end
        b.beardColour = colour
        rebodyDone(ped, b)
    end)
    -- "The game's own look for this model" (an admin's WearModel): its first preset.
    force('SetPedDefaultComponentVariation', function(ped) C.equipOutfit(ped, 0) end)
end

-- Health. GTA counts a ped's health from 100 (dead) to 200 (full), and whip does its sums on that scale (stats,
-- the HUD, NPCs, drowning, the death screen). An RDR2 ped dies at 0 and its full health differs by model. A ped's
-- health is moved between the scales here; a dead ped reads 0, as in GTA. Objects and wagons are left alone.
if not SERVER then
    local function isPed(e) return e and e ~= 0 and truthy(N(0xCF8176912DDA4EA5, e, Citizen.ResultAsInteger())) end  -- IS_ENTITY_A_PED
    local function rawMax(e) return N(0x15D757606D170C3C, e, false, Citizen.ResultAsInteger()) or 0 end  -- GET_ENTITY_MAX_HEALTH
    local function rawGet(e) return N(0x82368787EA73C0F7, e, Citizen.ResultAsInteger()) or 0 end         -- GET_ENTITY_HEALTH

    force('GetEntityHealth', function(e)
        local h = rawGet(e)
        if not isPed(e) or h <= 0 then return h end
        local max = rawMax(e)
        if max <= 0 then return h end
        return 100 + math.max(1, math.min(100, math.floor(h * 100 / max + 0.5)))
    end)
    force('GetEntityMaxHealth', function(e)
        if isPed(e) then return 200 end
        return rawMax(e)
    end)
    force('SetEntityHealth', function(e, value, killer)
        local v = math.floor(tonumber(value) or 0)
        if isPed(e) then
            local max = rawMax(e)
            if v <= 100 then v = 0
            elseif max > 0 then v = math.max(1, math.floor((math.min(v, 200) - 100) * max / 100 + 0.5)) end
        end
        N(0xAC2767ED8BDFAB15, e, v, killer or 0)                                                  -- SET_ENTITY_HEALTH
    end)
else
    -- The server reads the same scale (its death checks compare with 100). A max of 0 means the owner's game has
    -- not sent the ped's health yet (server/npcs.lua waits for that), so it stays 0.
    local rawGet, rawMax, typeOf = GetEntityHealth, GetEntityMaxHealth, GetEntityType
    force('GetEntityHealth', function(e)
        local h = rawGet(e)
        if typeOf(e) ~= 1 or h <= 0 then return h end
        local max = rawMax(e)
        if max <= 0 then return h end
        return 100 + math.max(1, math.min(100, math.floor(h * 100 / max + 0.5)))
    end)
    force('GetEntityMaxHealth', function(e)
        local max = rawMax(e)
        if typeOf(e) == 1 and max > 0 then return 200 end
        return max
    end)
end

-- GTA's "regenerate up to this fraction" -> RDR2's regeneration rate: 0 turns it off.
def('SetPlayerHealthRechargeLimit', function(player, limit)
    N(0x8899C244EBCF70DE, player, (tonumber(limit) or 0) <= 0 and 0.0 or 1.0)                  -- SET_PLAYER_HEALTH_RECHARGE_MULTIPLIER
end)

-- Moves the ped with what it is riding: a vehicle (wagon, coach, boat) or a horse.
def('SetPedCoordsKeepVehicle', function(ped, x, y, z)
    local target = GetVehiclePedIsIn(ped, false)
    if target == 0 and truthy(N(0x460BC76A0E10655E, ped, Citizen.ResultAsInteger())) then      -- IS_PED_ON_MOUNT
        target = N(0xE7E11B8DCBED1058, ped, Citizen.ResultAsInteger())                          -- GET_MOUNT
    end
    if not target or target == 0 then target = ped end
    SetEntityCoords(target, x + 0.0, y + 0.0, z + 0.0, false, false, false, false)
end)

def('IsEntityPositionFrozen', function(entity) return truthy(N(0x083D497D57B7400F, entity, Citizen.ResultAsInteger())) end)

-- GTA's movement clipsets are RDR2's clip sets.
def('RequestAnimSet', function(name) N(0xEF7611B57A820126, name) end)                              -- REQUEST_CLIP_SET
def('HasAnimSetLoaded', function(name) return truthy(N(0x1F23D6B6DA1CC3B2, name, Citizen.ResultAsInteger())) end)

-- From the entity's rotation (order 2: yaw, then pitch, then roll), for the few tools that want a quaternion.
def('GetEntityQuaternion', function(entity)
    local r = GetEntityRotation(entity, 2)
    local p, q, y = math.rad(r.x) / 2, math.rad(r.y) / 2, math.rad(r.z) / 2
    local cx, sx, cy, sy, cz, sz = math.cos(p), math.sin(p), math.cos(q), math.sin(q), math.cos(y), math.sin(y)
    -- q = qz(yaw) * qx(pitch) * qy(roll)
    return cz * sx * cy - sz * cx * sy,
        cz * cx * sy + sz * sx * cy,
        sz * cx * cy + cz * sx * sy,
        cz * cx * cy - sz * sx * sy
end)

-- ---- vehicles: RDR2's are wagons, coaches, carts and boats ------------------------------------

-- The RDR2 vehicle models whip's lists can offer; only those this game has are returned.
local VEHICLES = {
    'buggy01', 'buggy02', 'buggy03', 'cart01', 'cart02', 'cart03', 'cart04', 'cart05', 'cart06', 'cart07', 'cart08',
    'chuckwagon000x', 'chuckwagon002x', 'coach2', 'coach3', 'coach4', 'coach5', 'coach6', 'coal_wagon',
    'huntercart01', 'logwagon', 'logwagon2', 'oilwagon01x', 'oilwagon02x', 'policewagon01x', 'stagecoach001x',
    'stagecoach002x', 'stagecoach003x', 'stagecoach004x', 'stagecoach005x', 'stagecoach006x', 'supplywagon',
    'supplywagon2', 'utilliwag', 'wagon02x', 'wagon03x', 'wagon04x', 'wagon05x', 'wagon06x', 'wagonarmoured01x',
    'wagoncircus01x', 'wagoncircus02x', 'wagondairy01x', 'wagondoc01x', 'wagonprison01x', 'wagontraveller01x',
    'wagonwork01x', 'canoe', 'canoetreetrunk', 'pirogue', 'pirogue2', 'rowboat', 'rowboatswamp', 'rowboatswamp02',
    'keelboat', 'skiff', 'boatsteam02x',
}
local vehicleModels, vehicleName
local function loadVehicles()
    if vehicleModels then return end
    vehicleModels, vehicleName = {}, {}
    for _, m in ipairs(VEHICLES) do
        local h = hash(m)
        if IsModelInCdimage(h) and IsModelAVehicle(h) then
            vehicleModels[#vehicleModels + 1] = m
            vehicleName[h] = m:upper()
        end
    end
end
def('GetAllVehicleModels', function()
    loadVehicles()
    return { table.unpack(vehicleModels) }
end)
def('GetDisplayNameFromVehicleModel', function(model)
    loadVehicles()
    return vehicleName[model] or 'CARNOTFOUND'
end)

local function isBoat(m) return truthy(N(0x799CFC7C5B743B15, m, Citizen.ResultAsInteger())) end
local function isTrain(m) return truthy(N(0xFC08C8F8C1EDF174, m, Citizen.ResultAsInteger())) end
-- GTA's classes whip asks about: 14 boats, 21 trains; every wagon and coach reads as 0 (an ordinary car).
local function classOf(model)
    if isBoat(model) then return 14 end
    if isTrain(model) then return 21 end
    return 0
end
def('GetVehicleClass', function(veh) return classOf(GetEntityModel(veh)) end)
def('GetVehicleClassFromName', function(model) return classOf(type(model) == 'string' and hash(model) or model) end)
def('IsThisModelACar', function(m) return IsModelAVehicle(m) and not isBoat(m) and not isTrain(m) end)
def('GetVehicleNumberOfWheels', function() return 4 end)

-- ---- drawing ---------------------------------------------------------------------------------

-- RDR2 has DrawSprite but no UV crop: the whole texture is drawn.
def('DrawSpriteUv', function(dict, name, x, y, w, h, u1, v1, u2, v2, heading, r, g, b, a)
    DrawSprite(dict, name, x, y, w, h, heading or 0.0, r or 255, g or 255, b or 255, a or 255, false)
end)

-- ---- controls --------------------------------------------------------------------------------
-- GTA numbers its controls (0-360); RDR2 names them by hash. Every control native takes whip's GTA number and
-- reads the RDR2 control on the same key and pad button (femga rdr3_discoveries, Controls/README.md), or the one meant for the
-- same thing where the keys differ (noted). A number with no RDR2 control is passed on and reads as never
-- pressed; it is listed by /spurcompat. Hashes (RDR2 controls, key mappings) pass through.
local CONTROL = {
    [0] = 0x7F8D09B8,   -- NEXT_CAMERA            V / View
    [1] = 0xA987235F,   -- LOOK_LR
    [2] = 0xD2047988,   -- LOOK_UD
    [3] = 0xC0651D40, [4] = 0x8ED92E16, [5] = 0x08F8BC6D, [6] = 0xA1EB1353,   -- LOOK_UP/DOWN/LEFT/RIGHT_ONLY
    [14] = 0xFD0F0C2C,  -- WEAPON_WHEEL_NEXT      -> NEXT_WEAPON (wheel down)
    [15] = 0xCC1075A7,  -- WEAPON_WHEEL_PREV      -> PREV_WEAPON (wheel up)
    [16] = 0xD0842EDF,  -- SELECT_NEXT_WEAPON     wheel down
    [17] = 0xF78D7337,  -- SELECT_PREV_WEAPON     wheel up
    [18] = 0xCDC4E4E9,  -- SKIP_CUTSCENE          Enter / A
    [19] = 0x580C4473,  -- CHARACTER_WHEEL (Alt)  -> HUD_SPECIAL, Alt / D-pad down
    [21] = 0x8FFC75D6,  -- SPRINT                 Shift / A
    [22] = 0xD9D0E1C0,  -- JUMP                   Space / X
    [23] = 0xCEFD9220,  -- ENTER                  RDR2: E / Y
    [24] = 0x07CE1E61,  -- ATTACK                 LMB / RT
    [25] = 0xF84FA74F,  -- AIM                    RMB / LT
    [26] = 0x9959A6F0,  -- LOOK_BEHIND            C / R3
    [30] = 0x4D8FB4C1, [31] = 0xFDA83190,   -- MOVE_LR, MOVE_UD
    [32] = 0x8FD015D8, [33] = 0xD27782E3, [34] = 0x7065027D, [35] = 0xB4E465B4,   -- MOVE_UP/DOWN/LEFT/RIGHT_ONLY
    [36] = 0xDB096B85,  -- DUCK                   Ctrl / L3
    [37] = 0xAC4BD4F1,  -- SELECT_WEAPON (Tab)    -> OPEN_WHEEL_MENU, Tab / LB
    [38] = 0xCEFD9220,  -- PICKUP (E)             -> ENTER, E / Y: RDR2's E
    [44] = 0xDE794E3E,  -- COVER                  Q / RB
    [45] = 0xE30CD707,  -- RELOAD                 R / B
    [47] = 0xA1ABB953,  -- DETONATE (G)           -> INTERACT_ANIMAL, G
    [59] = 0xF1E2852C, [60] = 0x8A81C00C,   -- VEH_MOVE_LR, VEH_MOVE_UD
    [63] = 0x9DF54706, [64] = 0x97A8FD98,   -- VEH_MOVE_LEFT/RIGHT_ONLY
    [68] = 0xD7CAFCEF, [69] = 0xF4330038, [70] = 0xF1C341BA,   -- VEH_AIM, VEH_ATTACK, VEH_ATTACK2
    [71] = 0x5B9FD4E2,  -- VEH_ACCELERATE
    [72] = 0x6E1F639B,  -- VEH_BRAKE
    [73] = 0x4AF4D473,  -- VEH_DUCK (X)           -> FRONTEND_DELETE, Delete / X (whip: "remove")
    [74] = 0x24978A28,  -- VEH_HEADLIGHT (H)      -> WHISTLE, H (whip: the death screen's key)
    [75] = 0xFEFAB9B4,  -- VEH_EXIT               RDR2: E / Y
    [76] = 0x65D24C98,  -- VEH_HANDBRAKE
    [79] = 0xCAE9B017,  -- VEH_LOOK_BEHIND
    [80] = 0x620A6C5E,  -- VEH_CIN_CAM            -> CINEMATIC_CAM
    [86] = 0x63A0D258,  -- VEH_HORN
    [91] = 0xEE2804D0, [92] = 0x27AD4433,   -- VEH_PASSENGER_AIM, VEH_PASSENGER_ATTACK
    [99] = 0x889A626F, [100] = 0x0C97BAC7,  -- VEH_SELECT_NEXT/PREV_WEAPON
    [104] = 0xC7083798, -- VEH_SHUFFLE            RDR2: Z / X
    [106] = 0x39CCABD5, -- VEH_MOUSE_CONTROL_OVERRIDE
    [140] = 0xB2F377E8, [141] = 0x2277FAE9, [142] = 0xB2F377E8,   -- MELEE_ATTACK_LIGHT/HEAVY/ALTERNATE
    [143] = 0xB5EEEFB7, -- MELEE_BLOCK
    [157] = 0xE6F612E4, [158] = 0x1CE6D9EB, [160] = 0x4F49CC4C,   -- the 1, 2 and 3 keys
    [172] = 0x6319DB71, [173] = 0x05CA7C52, [174] = 0xA65EBAB4, [175] = 0xDEB34313,   -- CELLPHONE_ arrows -> FRONTEND_
    [177] = 0x156F7119, -- CELLPHONE_CANCEL       -> FRONTEND_CANCEL
    [180] = 0x8BDE7443, [181] = 0x62800C92,   -- CELLPHONE_SCROLL_FORWARD/BACKWARD -> CURSOR_SCROLL_DOWN/UP
    [182] = 0x80F28E95, -- CELLPHONE_CAMERA_FOCUS_LOCK (L) -> PLAYER_MENU, L
    [187] = 0x05CA7C52, [188] = 0x6319DB71, [189] = 0xA65EBAB4, [190] = 0xDEB34313,   -- FRONTEND_DOWN/UP/LEFT/RIGHT
    [195] = 0xFB56DD5B, [196] = 0x091178D0, [197] = 0x3D23549A, [198] = 0xEB4130DF,   -- FRONTEND_(RIGHT_)AXIS_X/Y
    [199] = 0xD82E0BD2, -- FRONTEND_PAUSE         P / Start
    [200] = 0x4A903C11, -- FRONTEND_PAUSE_ALTERNATE  Esc
    [201] = 0xC7B5340A, -- FRONTEND_ACCEPT        Enter / A
    [202] = 0x156F7119, -- FRONTEND_CANCEL        Backspace, Esc / B
    [203] = 0x6DB8C62F, -- FRONTEND_X             Space / X
    [204] = 0x7C0162C0, -- FRONTEND_Y             RDR2: Shift / Y
    [205] = 0xE885EF16, -- FRONTEND_LB            Q / LB
    [206] = 0x17BEC168, -- FRONTEND_RB            E / RB
    [207] = 0x51104035, -- FRONTEND_LT            PgDn / LT
    [208] = 0x6FED71BC, -- FRONTEND_RT            PgUp / RT
    [209] = 0x43CDA5B0, -- FRONTEND_LS            RDR2: Z / L3
    [210] = 0x7DA48D2A, -- FRONTEND_RS            RDR2: X / R3
    [217] = 0x171910DC, -- FRONTEND_SELECT        RDR2: Tab / View
    [237] = 0x9D2AEA88, [238] = 0x27568539,   -- CURSOR_ACCEPT, CURSOR_CANCEL
    [239] = 0xD6C4ECDC, [240] = 0xE4130778,   -- CURSOR_X, CURSOR_Y
    [241] = 0x62800C92, [242] = 0x8BDE7443,   -- CURSOR_SCROLL_UP, CURSOR_SCROLL_DOWN
    [249] = 0x4BC9DABB, -- PUSH_TO_TALK           N
    [257] = 0x0283C582, -- ATTACK2
    [329] = 0x6AA8A71B, -- (whip: middle mouse)   -> CURSOR_SCROLL_CLICK
    [330] = 0x27568539, -- (whip: right mouse)    -> CURSOR_CANCEL
}
local function control(c)
    if type(c) ~= 'number' or c < 0 or c >= 400 then return c end
    local h = CONTROL[c]
    if h then return h end
    noteHit('control ' .. c)
    return c
end
C.control = control
for _, name in ipairs({ 'IsControlPressed', 'IsControlJustPressed', 'IsControlJustReleased', 'IsControlReleased',
    'IsDisabledControlPressed', 'IsDisabledControlJustPressed', 'IsDisabledControlJustReleased',
    'IsDisabledControlReleased', 'DisableControlAction', 'EnableControlAction', 'IsControlEnabled',
    'GetControlNormal', 'GetDisabledControlNormal', 'GetControlUnboundNormal', 'GetDisabledControlUnboundNormal',
    'GetControlValue', 'GetDisabledControlValue', 'SetControlNormal' }) do
    local rdr = _G[name]
    if rdr then force(name, function(pad, c, ...) return rdr(pad, control(c), ...) end) end
end

-- ============================================================================================
-- PED FLAGS (client side). RedM (spur_core, 24 Nov 2026)
-- ============================================================================================
-- whip numbers ped config flags and ped reset flags as GTA V does. RDR2 numbers them its own way: GTA's config 48
-- (BlockWeaponSwitching) is RDR2's ShouldFixIfNoCollision, and GTA's reset 200 (DisableActionMode), which whip sets
-- every frame, is RDR2's EnableEagleEyeInVehicle. Each GTA number whip uses maps here to RDR2's own (femga's
-- rdr3_discoveries, AI/CPED_CONFIG_FLAGS and AI/CPED_RESET_FLAGS). One with no RDR2 counterpart (false) is not passed
-- on: its value is kept per ped, so a read gives back what was set. A number not listed is passed on as it is.
-- Only whip's GTA numbers are listed; a resource that loads this file and wants RDR2's own numbers calls
-- RdrCompat.rawPedConfigFlag / RdrCompat.rawPedResetFlag.
if not SERVER then
    local CONFIG_FLAG = {
        [2]   = 263,    -- NoCriticalHits
        [14]  = 'drop', -- DoesntDropWeaponsWhenDead: RDR2 has SET_PED_DROPS_WEAPONS_WHEN_DEAD instead
        [32]  = 5,      -- WillFlyThroughWindscreen
        [35]  = false,  -- PutOnMotorcycleHelmet (no motorbikes)
        -- BlockWeaponSwitching. Not passed on: whip keeps it on whenever the player isn't in a turret seat (client/
        -- inventory.lua's WeaponLock), and RDR2's own (249) on all that time could stop spur_gunny's equips and the
        -- holster. The weapon wheel is held off by whip's control blocks anyway. To try RDR2's, put 249 here.
        [48]  = false,
        [122] = 26,     -- DisableMelee
        [161] = false,  -- DontActivateRagdollFromMelee
        [166] = false,  -- IsInjured
        [170] = 55,     -- ForceDirectEntry
        [179] = 61,     -- PedIgnoresAnimInterruptEvents
        [184] = 65,     -- PreventAutoShuffleToDriversSeat
        [187] = false,  -- HasHurtStarted
        [188] = false,  -- DisableHurt
        [360] = 184,    -- PreventAutoShuffleToTurretSeat
        [404] = false,  -- suppress melee reactions when melee proof
    }
    local RESET_FLAG = {
        [200] = 41,     -- DisableActionMode
        [216] = false,  -- DisableSeatShuffleDueToInjuredDriver
        [274] = false,  -- BlockRagdollFromVehicleFallOff
    }
    -- [ped] = { [gta flag] = true }: the unmapped ones set on. Only "on" is kept (an NPC's flags are mostly switched
    -- off), and a ped's table goes with its last one.
    local kept = {}
    local function keep(ped, flag, on)
        local t = kept[ped]
        if on then
            if not t then t = {}; kept[ped] = t end
            t[flag] = true
        elseif t then
            t[flag] = nil
            if next(t) == nil then kept[ped] = nil end
        end
    end

    local setConfig, getConfig = _G.SetPedConfigFlag, _G.GetPedConfigFlag
    local setReset, getReset = _G.SetPedResetFlag, _G.GetPedResetFlag
    C.rawPedConfigFlag = { set = setConfig, get = getConfig }
    C.rawPedResetFlag = { set = setReset, get = getReset }

    if setConfig and getConfig then
        force('SetPedConfigFlag', function(ped, flag, value, ...)
            local to = CONFIG_FLAG[flag]
            if to == nil then return setConfig(ped, flag, value, ...) end
            local on = truthy(value)
            keep(ped, flag, on)
            if to == 'drop' then
                SetPedDropsWeaponsWhenDead(ped, not on)
            elseif to then
                setConfig(ped, to, on)
            end
        end)
        force('GetPedConfigFlag', function(ped, flag, p2)
            local to = CONFIG_FLAG[flag]
            if to == nil then return getConfig(ped, flag, p2) end
            if to and to ~= 'drop' then return truthy(getConfig(ped, to, p2)) end
            local t = kept[ped]
            return t ~= nil and t[flag] == true
        end)
    end
    if setReset then
        force('SetPedResetFlag', function(ped, flag, value)
            local to = RESET_FLAG[flag]
            if to == nil then return setReset(ped, flag, value) end
            if to then setReset(ped, to, truthy(value)) end
        end)
    end
    if getReset then
        force('GetPedResetFlag', function(ped, flag)
            local to = RESET_FLAG[flag]
            if to == nil then return getReset(ped, flag) end
            return to and truthy(getReset(ped, to)) or false
        end)
    end
end

-- ============================================================================================
-- PED BONES (client side). RedM (spur_core, 24 Nov 2026)
-- ============================================================================================
-- A ped bone tag is a hash of the bone's name, and GTA and RDR2 hash their skeletons' names differently: GTA's
-- PH_R_Hand is 28422, RDR2's is 7966. whip passes GTA's tags (held props, the head for prompts and bubbles, the
-- creator's camera), so each one whip uses maps here to RDR2's tag for the same bone (femga's rdr3_discoveries
-- boneNames/mp_male, the same names on mp_female). A tag not listed is passed on as it is.
if not SERVER then
    local BONE = {
        [11816] = 56200,   -- SKEL_Pelvis
        [23553] = 14410,   -- SKEL_Spine0
        [24816] = 14411,   -- SKEL_Spine1
        [24817] = 14412,   -- SKEL_Spine2
        [24818] = 14413,   -- SKEL_Spine3
        [39317] = 14284,   -- SKEL_Neck_1 (RDR2's SKEL_Neck1)
        [31086] = 21030,   -- SKEL_Head
        [12844] = 21030,   -- IK_Head (RDR2 has none: the head)
        [64729] = 30226,   -- SKEL_L_Clavicle
        [10706] = 54802,   -- SKEL_R_Clavicle
        [45509] = 37873,   -- SKEL_L_UpperArm
        [40269] = 46065,   -- SKEL_R_UpperArm
        [61163] = 53675,   -- SKEL_L_Forearm
        [28252] = 54187,   -- SKEL_R_Forearm
        [18905] = 34606,   -- SKEL_L_Hand
        [57005] = 22798,   -- SKEL_R_Hand
        [60309] = 37709,   -- PH_L_Hand
        [28422] = 7966,    -- PH_R_Hand
        [26610] = 41403,   -- SKEL_L_Finger00
        [58866] = 16827,   -- SKEL_R_Finger00
        [58271] = 65478,   -- SKEL_L_Thigh
        [51826] = 6884,    -- SKEL_R_Thigh
        [63931] = 55120,   -- SKEL_L_Calf
        [36864] = 43312,   -- SKEL_R_Calf
        [14201] = 45454,   -- SKEL_L_Foot
        [52301] = 33646,   -- SKEL_R_Foot
    }
    C.boneTag = function(tag) return BONE[tag] or tag end
    local boneIndex, boneCoords = _G.GetPedBoneIndex, _G.GetPedBoneCoords
    if boneIndex then
        force('GetPedBoneIndex', function(ped, tag) return boneIndex(ped, BONE[tag] or tag) end)
    end
    if boneCoords then
        force('GetPedBoneCoords', function(ped, tag, x, y, z)
            return boneCoords(ped, BONE[tag] or tag, x or 0.0, y or 0.0, z or 0.0)
        end)
    end
end

-- ============================================
-- HIDDEN ON THIS SCREEN ONLY (client side). RedM (spur_core, 24 Nov 2026)
-- ============================================
-- GTA's SET_ENTITY_LOCALLY_INVISIBLE (every frame: hidden for this game, seen by everyone else) isn't in RDR2.
-- RDR2 has it for players only: SET_LOCAL_PLAYER_INVISIBLE_LOCALLY for the player's own ped and
-- SET_PLAYER_INVISIBLE_LOCALLY for another player's, both every frame. The camera item hides the player's ped
-- with it while they look through the lens. Any other entity (a prop, a car, an NPC) stays seen, as the stub
-- left it (rdr_compat_stubs.lua's quiet one is now only for builds without these natives). The bool is GTA's
-- "and their vehicle too", or RDR2's "on" if nativedb's name for it is right: true is right either way, as
-- client/take_copies.lua hides a rider's real car as well and the camera ends in a vehicle.
if not SERVER then
    def('SetEntityLocallyInvisible', function(entity)
        if not entity or entity == 0 or not IsEntityAPed(entity) or not IsPedAPlayer(entity) then return end
        local player = NetworkGetPlayerIndexFromPed(entity)
        if player == PlayerId() then
            N(0xE5F773C1A1D9D168, true)            -- SET_LOCAL_PLAYER_INVISIBLE_LOCALLY
        elseif player and player ~= -1 then
            N(0x12B37D54667DB0B8, player, true)    -- SET_PLAYER_INVISIBLE_LOCALLY
        end
    end)
end

-- GTA's NETWORK_EXPLODE_VEHICLE(vehicle, audible, invisible, netId) isn't in RDR2; its EXPLODE_VEHICLE(vehicle,
-- audible, invisible, p3, p4) is. The Director's Blow Up step (client/actors.lua) and the object viewer's explode
-- (client/ov_effects.lua) use it on a wagon or coach they control. RedM (spur_core, 24 Nov 2026)
if not SERVER then
    def('NetworkExplodeVehicle', function(vehicle, audible, invisible)
        if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
        N(0x75DCED9EEC5769D7, vehicle, audible ~= false, invisible == true, 0, 0)   -- EXPLODE_VEHICLE
        return true
    end)
end

-- FiveM's key bindings (Settings > Key Bindings). Where this RedM build has none, whip's bound commands still
-- run from F8; the keys are not bound.
def('RegisterKeyMapping', function(command) noteHit('RegisterKeyMapping') end)

-- shared/rdr_compat_stubs.lua (next in the manifest) fills in every other GTA-only name whip calls.

-- ============================================================================================
-- SEATS (client side). RedM (spur_core, 24 Nov 2026)
-- ============================================================================================
-- RedM's server never sees a ped get out of a vehicle (server side, above). This game says where its player sits, in
-- the player's spurSeat bag, and where the script-made NPCs it runs sit, in theirs. The server believes an "in" only
-- for a vehicle it saw the ped get into or one the ped is standing at.
if OWN then
    local function seatOf(ped)
        local veh = GetVehiclePedIsIn(ped, false)
        if not veh or veh == 0 or not NetworkGetEntityIsNetworked(veh) then return nil end
        local net = NetworkGetNetworkIdFromEntity(veh)
        if not net or net == 0 then return nil end
        local max = GetVehicleMaxNumberOfPassengers and GetVehicleMaxNumberOfPassengers(veh) or 8
        for s = -1, math.max(max, 0) - 1 do
            if GetPedInVehicleSeat(veh, s) == ped then return { net = net, seat = s } end
        end
        return { net = net, seat = -2 }   -- aboard, seat unknown
    end

    local function same(a, b)
        if a == nil or b == nil then return a == b end
        return type(a) == 'table' and type(b) == 'table' and a.net == b.net and a.seat == b.seat
    end

    CreateThread(function()
        local tick = 0
        while true do
            Wait(150)
            tick = tick + 1
            local me = PlayerPedId()
            local mine = seatOf(me)
            if not same(LocalPlayer.state[SEAT_BAG], mine) then LocalPlayer.state:set(SEAT_BAG, mine, true) end

            if tick % 4 == 0 then
                for _, ped in ipairs(GetGamePool('CPed')) do
                    if ped ~= me and not IsPedAPlayer(ped) and NetworkGetEntityIsNetworked(ped)
                        and NetworkHasControlOfEntity(ped) and IsEntityAMissionEntity(ped) then
                        local st = Entity(ped).state
                        local now = seatOf(ped)
                        if not same(st[SEAT_BAG], now) then st:set(SEAT_BAG, now, true) end
                    end
                end
            end
        end
    end)
end
