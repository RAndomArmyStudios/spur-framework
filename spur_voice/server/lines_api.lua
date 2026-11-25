-- Voice lines for other resources (the exports). Any resource can use spur_voice without any of its code: a telephone
-- call is a line it opens. The resource owns its lines and spur_voice closes them when it stops. Server side only:
-- only a server decides who is on a line. The contract is whip_voice's (its docs/LINES.md), so a resource written for
-- whip_voice works unchanged; spur_core's Whip.voice calls these through whichever voice system runs.
--
--   local lineId = exports.spur_voice:OpenLine({
--       members  = { callerSrc, calleeSrc },
--       track    = 'voice',              -- 'voice' or 'radio' (the same on Mumble: what the player says)
--       recipe   = mySound,              -- taken and kept, not played (sounds 'basic': see below)
--       sameWorld = false,               -- only members in the same routing bucket hear each other
--       minMembers = 2,                  -- fewer members than this and the line closes by itself
--       onEnd    = function(lineId, why) end,         -- closed by spur_voice ('empty')
--       onLeave  = function(lineId, src, why) end,    -- a member gone ('left', 'logout', 'removed')
--   })
--   CloseLine(lineId)   AddLineMember(lineId, src)   RemoveLineMember(lineId, src)
--   SetLineSpeaker(lineId, src, on)   SetLineMuted(lineId, src, on)   SetLineRecipe(lineId, recipe)
--   GetLine(lineId)   RegisterSound(name, recipe)   IsVoiceReady(src)
--
-- Every export answers its value (or true), or false and why. A member is a player with a character loaded; not being
-- in voice yet is fine, they are linked once they are.
--
-- RedM (spur_voice, 24 Nov 2026): what Mumble can't do, spur_voice says (spur_core's features: speaker, pickup and
-- quality false, sounds 'basic'). SetLineSpeaker answers false and why; a recipe is checked for its shape and kept,
-- but a line sounds like the voice it carries (no phone filter).

local RESOURCE = GetCurrentResourceName()
local MAX_MEMBERS = 32       -- on one line
local MAX_LINES = 500        -- open at once, per resource
local MAX_BLOCKS = 16        -- in one recipe
local sounds = {}            -- ['<owner>:<name>'] = a recipe

local function isFuncRef(v) return type(v) == 'table' and rawget(v, '__cfx_functionReference') ~= nil end
local function callable(v) return type(v) == 'function' or isFuncRef(v) end

--- A recipe's shape: a list of blocks, each a table with a type. Its settings are not read (nothing is built from it).
local function checkRecipe(recipe)
    if type(recipe) ~= 'table' or isFuncRef(recipe) then return nil, 'a recipe is a list of blocks' end
    local n = #recipe
    if n > MAX_BLOCKS then return nil, ('at most %d blocks'):format(MAX_BLOCKS) end
    for i = 1, n do
        local b = rawget(recipe, i)
        if type(b) ~= 'table' or isFuncRef(b) then return nil, ('block %d is not a table'):format(i) end
        local name = rawget(b, 'type')
        if name == nil then name = rawget(b, 1) end
        if type(name) ~= 'string' then return nil, ('block %d has no type'):format(i) end
    end
    return recipe
end

--- A recipe, or a sound's name: the owner's own ('ring' = '<owner>:ring'), or another's in full.
local function recipeOf(owner, r)
    if type(r) == 'string' then
        local s = sounds[r] or sounds[owner .. ':' .. r]
        if not s then return nil, 'there is no sound called ' .. r end
        return s
    end
    if r == nil then return {} end
    return checkRecipe(r)
end

--- A player spur_core has a character loaded for (its own record: spur_voice may have just started).
local function loaded(src)
    src = tonumber(src)
    if not src or GetPlayerName(src) == nil then return false end
    local ok, p = pcall(function() return exports.spur_core:GetPlayer(src) end)
    return ok and p ~= nil and p ~= false
end

--- The owner's line, or false and why.
local function mine(owner, lineId)
    local line = type(lineId) == 'string' and Lines.byId[lineId] or nil
    if not line then return false, 'no such line (closed?)' end
    if line.owner ~= owner then return false, 'that line is not yours' end
    return line
end

--- A callback from another resource, run only while that resource still runs.
local function ownerCallback(owner, fn)
    if fn == nil then return nil end
    return function(...)
        if GetResourceState(owner) ~= 'started' then return end
        fn(...)
    end
end

local function owned(owner)
    local n = 0
    for _, line in pairs(Lines.byId) do if line.owner == owner then n = n + 1 end end
    return n
end

-- ---- The exports (each reads its caller first, before anything else) -----------------------------

exports('OpenLine', function(spec)
    local owner = GetInvokingResource()
    if not owner or owner == RESOURCE then return false, 'call it from another resource' end
    if type(spec) ~= 'table' or isFuncRef(spec) then return false, 'a line is a table: { members, recipe, ... }' end
    local track = rawget(spec, 'track')
    if track ~= nil and track ~= 'voice' and track ~= 'radio' then return false, "track is 'voice' or 'radio'" end
    local recipe, why = recipeOf(owner, rawget(spec, 'recipe'))
    if not recipe then return false, 'recipe: ' .. why end
    local onEnd, onLeave = rawget(spec, 'onEnd'), rawget(spec, 'onLeave')
    if onEnd ~= nil and not callable(onEnd) then return false, 'onEnd is a function' end
    if onLeave ~= nil and not callable(onLeave) then return false, 'onLeave is a function' end
    local list = rawget(spec, 'members')
    if list ~= nil and (type(list) ~= 'table' or isFuncRef(list)) then return false, 'members is a list of server ids' end
    local members = {}
    for i = 1, list and #list or 0 do
        local src = tonumber(rawget(list, i))
        if not loaded(src) then return false, ('member %s is not a player with a character loaded'):format(tostring(rawget(list, i))) end
        members[#members + 1] = src
    end
    if #members > MAX_MEMBERS then return false, ('at most %d members'):format(MAX_MEMBERS) end
    if owned(owner) >= MAX_LINES then return false, ('at most %d lines open at once'):format(MAX_LINES) end
    local Q = rawget(spec, 'quality')
    if Q ~= nil and (type(Q) ~= 'table' or isFuncRef(Q) or not tonumber(rawget(Q, 'clear')) or not tonumber(rawget(Q, 'range'))) then
        return false, 'quality is { clear = metres, range = metres }'
    end
    return Lines.open(owner, {
        members = members, track = track or 'voice',
        sameWorld = rawget(spec, 'sameWorld') == true, pickup = rawget(spec, 'pickup') == true,
        speakerRange = tonumber(rawget(spec, 'speakerRange')) or 8,
        minMembers = tonumber(rawget(spec, 'minMembers')) or 2,
        onEnd = ownerCallback(owner, onEnd), onLeave = ownerCallback(owner, onLeave),
    })
end)

exports('CloseLine', function(lineId)
    local owner = GetInvokingResource()
    if not owner then return false, 'call it from another resource' end
    if type(lineId) == 'string' and not Lines.byId[lineId] then return true end   -- closed already: nothing to do
    local line, why = mine(owner, lineId)
    if not line then return false, why end
    return Lines.close(lineId, 'closed', true)
end)

exports('AddLineMember', function(lineId, src)
    local owner = GetInvokingResource()
    if not owner then return false, 'call it from another resource' end
    local line, why = mine(owner, lineId)
    if not line then return false, why end
    src = tonumber(src)
    if not loaded(src) then return false, 'not a player with a character loaded' end
    if not line.members[src] then
        local n = 0
        for _ in pairs(line.members) do n = n + 1 end
        if n >= MAX_MEMBERS then return false, ('at most %d members'):format(MAX_MEMBERS) end
    end
    return Lines.join(lineId, src)
end)

exports('RemoveLineMember', function(lineId, src)
    local owner = GetInvokingResource()
    if not owner then return false, 'call it from another resource' end
    local line, why = mine(owner, lineId)
    if not line then return false, why end
    src = tonumber(src)
    if not (src and line.members[src]) then return true end   -- not on it: nothing to do
    return Lines.leave(lineId, src, 'removed')
end)

-- RedM (spur_voice, 24 Nov 2026): Mumble can't play a line out of one player's device to the people around them.
exports('SetLineSpeaker', function(lineId, src, on)
    local owner = GetInvokingResource()
    if not owner then return false, 'call it from another resource' end
    local line, why = mine(owner, lineId)
    if not line then return false, why end
    if not line.members[tonumber(src) or -1] then return false, 'not on that line' end
    if on ~= true then return true end   -- off is how it always is
    return false, 'spur_voice (Mumble) has no speaker: only the members hear a line'
end)

exports('SetLineMuted', function(lineId, src, on)
    local owner = GetInvokingResource()
    if not owner then return false, 'call it from another resource' end
    local line, why = mine(owner, lineId)
    if not line then return false, why end
    return Lines.setMuted(lineId, tonumber(src), on == true)
end)

exports('SetLineRecipe', function(lineId, recipe)
    local owner = GetInvokingResource()
    if not owner then return false, 'call it from another resource' end
    local line, why = mine(owner, lineId)
    if not line then return false, why end
    local r, rwhy = recipeOf(owner, recipe)
    if not r then return false, 'recipe: ' .. rwhy end
    return true
end)

exports('GetLine', function(lineId)
    local owner = GetInvokingResource()
    if not owner then return false, 'call it from another resource' end
    local line, why = mine(owner, lineId)
    if not line then return false, why end
    local members = {}
    for src, m in pairs(line.members) do members[src] = { speaker = m.speaker, muted = m.muted } end
    return { id = line.id, track = line.track, members = members, pickup = line.pickup, sameWorld = line.sameWorld,
             speakerRange = line.speakerRange, minMembers = line.minMembers }
end)

exports('RegisterSound', function(name, recipe)
    local owner = GetInvokingResource()
    if not owner then return false, 'call it from another resource' end
    if type(name) ~= 'string' or not name:match('^[%w_%-]+$') or #name > 32 then return false, 'a sound\'s name is letters, digits, - and _' end
    local r, why = checkRecipe(recipe)
    if not r then return false, 'recipe: ' .. why end
    sounds[owner .. ':' .. name] = r
    return owner .. ':' .. name
end)

exports('IsVoiceReady', function(src)
    src = tonumber(src)
    if not src or GetPlayerName(src) == nil then return false, 'not a player' end
    if not Voice.inVoice[src] then return false, 'not connected to voice' end
    return true
end)

-- A resource stopping: its lines close (no callbacks: its functions are gone), its sounds go.
AddEventHandler('onResourceStop', function(res)
    if res == RESOURCE then return end
    for _, id in ipairs(Lines.ownedBy(res)) do Lines.close(id, 'ownerStopped', true) end
    for key in pairs(sounds) do
        if key:sub(1, #res + 1) == res .. ':' then sounds[key] = nil end
    end
end)
