-- Voice lines: a line is a set of players who hear each other wherever they are. The resource that opens one owns it:
-- a telephone call is a line its resource opens.
--
--   track      'voice' or 'radio': both are what the player says (RedM: there is no radio key in 1899)
--   sameWorld  only members in the same routing bucket hear each other; a call: anywhere
--   members    [src] = { speaker, muted }: muted, the line does not hear them (the people near still do)
--
-- Membership is not presence: a member stays a member by server id until they leave, log out or disconnect, and is
-- linked once their game is in voice. `minMembers` counts members, never presence.
--
-- Privacy: the server alone decides who is on a line; each member's game is told exactly whom to talk to and whom to
-- hear (Lines.push). Leaving and muting take effect at once.
--
-- RedM (spur_voice, 24 Nov 2026): whip_voice's lines, kept as they were, but heard through Mumble: each member's game
-- adds the others to its voice target and plays them at full volume (client/main.lua). No voice bots, no own shared
-- lines (the radio), no recipes built: a line sounds like the voice it carries.

Lines = {
    byId = {},       -- [lineId] = line
    ofPlayer = {},   -- [src] = { [lineId] = true }
}

local startTag = nil   -- per start of spur_voice: a line id from before a restart never matches a new one
local count = 0

local function newId()
    if not startTag then startTag = ('%x'):format(math.random(0x10000000, 0x7fffffff)) end
    count = count + 1
    return ('%s-%d'):format(startTag, count)
end

local function clamp(v, lo, hi, def)
    v = tonumber(v)
    if not v or v ~= v then return def end
    return math.max(lo, math.min(hi, v))
end

local function memberCount(line)
    local n = 0
    for _ in pairs(line.members) do n = n + 1 end
    return n
end

--- A callback, a tick later and never inside our own work: a resource's onEnd may open another line.
local function later(fn, ...)
    if not fn then return end
    local args = table.pack(...)
    SetTimeout(0, function()
        local ok, err = pcall(fn, table.unpack(args, 1, args.n))
        if not ok then print(('[spur_voice] a line callback failed: %s'):format(tostring(err))) end
    end)
end

--- Tell one player's game whom to talk to on its lines, and whom to hear at full volume.
function Lines.push(src)
    if GetPlayerName(src) == nil then return end
    local talk, hear, seenT, seenH = {}, {}, {}, {}
    for id in pairs(Lines.ofPlayer[src] or {}) do
        local line = Lines.byId[id]
        local me = line and line.members[src]
        if me then
            local bucket = line.sameWorld and GetPlayerRoutingBucket(src)
            for other, m in pairs(line.members) do
                if other ~= src and GetPlayerName(other) ~= nil
                    and (not line.sameWorld or GetPlayerRoutingBucket(other) == bucket) then
                    if not me.muted and not seenT[other] then seenT[other] = true; talk[#talk + 1] = other end
                    if not m.muted and not seenH[other] then seenH[other] = true; hear[#hear + 1] = other end
                end
            end
        end
    end
    TriggerClientEvent('spur_voice:client:lines', src, talk, hear)
end

--- Everyone on a line told again (after it changed). `extra`: a player who just left it, told too.
local function pushLine(line, extra)
    for src in pairs(line.members) do Lines.push(src) end
    if extra then Lines.push(extra) end
end

--- Open a line. Answers its id, or false and why. (The exports, server/lines_api.lua, check what another resource
--- sends before it gets here.)
---@param owner string   the resource it belongs to
---@param spec table     { members?, track, sameWorld?, speakerRange?, pickup?, minMembers?, onEnd?, onLeave? }
function Lines.open(owner, spec)
    if type(spec) ~= 'table' then return false, 'a line is a table' end
    local id = newId()
    local line = {
        id = id, owner = owner,
        track = spec.track == 'radio' and 'radio' or 'voice',
        sameWorld = spec.sameWorld == true,
        speakerRange = clamp(spec.speakerRange, 1, 30, 8),
        pickup = spec.pickup == true,
        minMembers = math.floor(clamp(spec.minMembers, 1, 64, 2)),
        members = {},
        onEnd = spec.onEnd, onLeave = spec.onLeave,
    }
    Lines.byId[id] = line
    for _, src in ipairs(type(spec.members) == 'table' and spec.members or {}) do
        src = tonumber(src)
        if src and not line.members[src] then
            line.members[src] = { speaker = false, muted = false }
            Lines.ofPlayer[src] = Lines.ofPlayer[src] or {}
            Lines.ofPlayer[src][id] = true
        end
    end
    pushLine(line)
    Voice.debug('line %s opened by %s (%d members)', id, owner, memberCount(line))
    return id
end

--- Close a line: everyone on it lets go at once. `why` reaches its onEnd (not when its owner stopped: `quiet`).
function Lines.close(id, why, quiet)
    local line = Lines.byId[id]
    if not line then return false, 'no such line' end
    Lines.byId[id] = nil
    local was = {}
    for src in pairs(line.members) do
        was[#was + 1] = src
        local mine = Lines.ofPlayer[src]
        if mine then mine[id] = nil; if not next(mine) then Lines.ofPlayer[src] = nil end end
    end
    line.members = {}
    for _, src in ipairs(was) do Lines.push(src) end
    Voice.debug('line %s closed (%s)', id, tostring(why or 'closed'))
    if not quiet then later(line.onEnd, id, why or 'closed') end
    return true
end

--- Put a player on a line.
function Lines.join(id, src)
    local line = Lines.byId[id]
    if not line then return false, 'no such line' end
    src = tonumber(src)
    if not src then return false, 'not a player' end
    if not line.members[src] then
        line.members[src] = { speaker = false, muted = false }
        Lines.ofPlayer[src] = Lines.ofPlayer[src] or {}
        Lines.ofPlayer[src][id] = true
        pushLine(line)
    end
    return true
end

--- Take a player off a line (at once). Fewer than its minMembers left: the line closes.
function Lines.leave(id, src, why)
    local line = Lines.byId[id]
    if not line or not line.members[src] then return false, 'not on that line' end
    line.members[src] = nil
    local mine = Lines.ofPlayer[src]
    if mine then mine[id] = nil; if not next(mine) then Lines.ofPlayer[src] = nil end end
    later(line.onLeave, id, src, why or 'removed')
    if memberCount(line) < line.minMembers then
        Lines.push(src)
        Lines.close(id, 'empty')
    else
        pushLine(line, src)
    end
    return true
end

--- A member muted on a line (the line does not hear them; the people near still do), or not.
function Lines.setMuted(id, src, on)
    local line = Lines.byId[id]
    local m = line and line.members[src]
    if not m then return false, 'not on that line' end
    on = on == true
    if m.muted == on then return true end
    m.muted = on
    pushLine(line)
    return true
end

--- Off every line (they left, logged out, or spur_core was lost).
function Lines.leaveAll(src, why)
    local mine = Lines.ofPlayer[src]
    if not mine then return end
    local ids = {}
    for id in pairs(mine) do ids[#ids + 1] = id end   -- (leaving changes the table being walked)
    for _, id in ipairs(ids) do Lines.leave(id, src, why) end
end

--- The lines a resource owns (for its stop).
function Lines.ownedBy(owner)
    local ids = {}
    for id, line in pairs(Lines.byId) do if line.owner == owner then ids[#ids + 1] = id end end
    return ids
end

-- ---- Leaving, as players do --------------------------------------------------------------------

AddEventHandler('playerDropped', function()
    Lines.leaveAll(source, 'left')
end)

-- Logging out takes a player off every line: the next character must not inherit the last one's call.
AddEventHandler('spur_core:player:logout', function(e)
    if type(e) == 'table' and e.source then Lines.leaveAll(e.source, 'logout') end
end)
