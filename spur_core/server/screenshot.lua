-- ============================================
-- SCREENSHOTS — server/screenshot.lua
-- ============================================
--
-- A player's game picture, from their own game (client/screenshot.lua takes it, once, when asked):
--
--   local data, why = exports.spur_core:RequestScreenshot(source, { format = 'jpg', quality = 0.8 })  -- yields
--
-- A data URL, or false + why. opts as TakeScreenshot's (ui = true: with whip's interface; frames + every: a burst in
-- one picture), without upload. Only an
-- answer to an ask made here is taken:
-- each ask has its own number, per player, and anything else that arrives is refused. A player's game can always send
-- a picture it made up; this is for tools (the AI dev link), not for catching cheats.

Screenshot = {}   -- spur_core's own files: Screenshot.request(source, opts) (the export is for other resources)

local REPLY_WAIT_MS = 30000              -- for the shot to come back (it travels slowly: a latent event)
local MAX_CHARS = 16 * 1024 * 1024       -- the biggest data URL taken (a 4K PNG is about 10 MB)

local _next = 0
local _asked = {}   -- [source] = { [reqId] = { done, data, why } }

local function request(source, opts)
    source = tonumber(source)
    if not source or not GetPlayerName(source) then return false, 'no such player' end
    opts = type(opts) == 'table' and opts or {}
    _next = _next + 1
    local reqId = _next
    _asked[source] = _asked[source] or {}
    local slot = {}
    _asked[source][reqId] = slot
    local frames = math.max(1, math.min(24, math.floor(tonumber(opts.frames) or 1)))
    local every = math.max(33, math.min(1000, math.floor(tonumber(opts.every) or 100)))
    TriggerClientEvent('spur_core:client:screenshot', source, reqId, {
        format = opts.format, quality = opts.quality, width = opts.width, height = opts.height, ui = opts.ui == true,
        frames = frames, every = every,
    })
    local by = GetGameTimer() + REPLY_WAIT_MS + (frames > 1 and frames * every or 0)
    while not slot.done and GetGameTimer() < by do Wait(50) end
    if _asked[source] then _asked[source][reqId] = nil end
    if not slot.done then return false, 'their game did not send the shot back' end
    if not slot.data then return false, slot.why or 'the shot failed' end
    return slot.data
end

---@param source number
---@param opts table|nil
---@return string|false data, string|nil why
function Screenshot.request(source, opts) return request(source, opts) end

exports('RequestScreenshot', function(source, opts) return request(source, opts) end)

-- `data` is 'any', looked at only once the ask is found: base64 has no control characters to strip, and a string
-- sanitiser would scan up to 16 MB from any game on the server's thread before knowing nobody asked.
SecureEvent('spur_core:server:screenshot', {
    rateLimit = 250, burst = 4, requirePlayer = false, whileDead = true,
    params = { {'reqId', 'id'}, {'data', 'any'}, {'why', 'string', 200, ''} },
}, function(source, _, reqId, data, why)
    local slot = _asked[source] and _asked[source][reqId]
    if not slot or slot.done then return end   -- not a shot this server asked for (or one already answered)
    slot.done = true
    if type(data) ~= 'string' or data == '' then
        slot.why = why ~= '' and why or 'the shot failed'
    elseif #data > MAX_CHARS then
        slot.why = 'the shot was too big'
    elseif not data:match('^data:image/') then
        slot.why = 'that was not a picture'
    else
        slot.data = data
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local asked = _asked[src]
    _asked[src] = nil
    for _, slot in pairs(asked or {}) do
        slot.done = true
        slot.why = 'they left'
    end
end)
