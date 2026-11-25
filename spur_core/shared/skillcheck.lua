-- ============================================
-- SKILL CHECK DIFFICULTIES — one reading of the settings, for both sides
-- ============================================
--
-- The client draws the ring from a difficulty and the server times the answer from the same one
-- (server/skillcheck.lua), so both read it here: a name the server accepts is always one the
-- client can draw, and a setting the ring cannot be drawn from is refused on both with the same
-- sentence.
--
-- The settings are Config.SkillCheckDifficulty and Config.SkillCheckHoldMs (config.lua, section 10).
-- A caller can also bring its own numbers instead of a name (`{ level = { ... } }`): read the same way.

local DEFAULT = 'medium'

-- One difficulty's numbers (Config.SkillCheckDifficulty), as GetSkillCheckSettings hands them out.
local LEVEL_KEYS = { 'pieces', 'parts', 'widest', 'narrowest', 'msPerPart' }

--- A positive number, or the default.
local function positive(v, default)
    v = tonumber(v)
    if not v or not (v > 0) or v == math.huge then return default end
    return v
end

--- A whole number, also when it travelled as 4.0 (through JSON), or nil.
local function whole(v)
    return type(v) == 'number' and math.tointeger(v) or nil
end

--- One difficulty's numbers, read and checked. `where` names them in a refusal (a setting the ring cannot be drawn
--- from is the server owner's to fix: said with where it is). `own`: a caller's own numbers, which may carry their
--- own holdMs and mouseSpeed, and are kept on the level (level.own) so the server can hand them to the client.
local function readLevel(name, def, where, own)
    local pieces, parts = whole(def.pieces), whole(def.parts)
    if not pieces or pieces < 1 or not parts or parts < 1 then
        return nil, ('%s needs a whole number of pieces and of parts'):format(where)
    end
    local widest, narrowest = def.widest, def.narrowest
    local function isWidth(w) return type(w) == 'number' and w > 0 and w <= pieces end
    if not isWidth(widest) or not isWidth(narrowest) or narrowest > widest then
        return nil, ('%s: widest and narrowest must be numbers of pieces above 0, up to %d, widest the bigger')
            :format(where, pieces)
    end

    -- Each part narrower than the one before, evenly from widest to narrowest. The page reads one width
    -- per part.
    local widths = {}
    for i = 1, parts do
        local t = parts > 1 and (i - 1) / (parts - 1) or 0
        widths[i] = widest - (widest - narrowest) * t
    end

    -- The clock is per difficulty: msPerPart × parts. A difficulty added without msPerPart gets 600.
    local msPerPart = def.msPerPart
    if msPerPart == nil then msPerPart = 600 end
    if type(msPerPart) ~= 'number' or not (msPerPart > 0) or msPerPart == math.huge then
        return nil, ('%s: msPerPart must be a number of milliseconds above 0'):format(where)
    end

    local holdMs = positive(Config.SkillCheckHoldMs, 196)
    local mouseSpeed = positive(Config.SkillCheckMouseSpeed, 1.0)
    if own then
        holdMs = positive(def.holdMs, holdMs)
        mouseSpeed = positive(def.mouseSpeed, mouseSpeed)
    end

    return {
        name        = name,
        pieces      = pieces,
        rounds      = widths,
        holdMs      = holdMs,
        timeLimitMs = math.floor(msPerPart * #widths),
        mouseSpeed  = mouseSpeed,
        own         = own and { pieces = pieces, parts = parts, widest = widest, narrowest = narrowest,
            msPerPart = msPerPart, holdMs = holdMs, mouseSpeed = mouseSpeed } or nil,
    }
end

--- The skill check a caller asked for, read and checked.
---
--- `difficulty` is a name from Config.SkillCheckDifficulty ('easy', 'medium', 'hard', or one the
--- server owner added), nil for 'medium', or `{ difficulty = name }` (the one-table form every UI
--- component takes).
---
--- Or `{ level = { pieces, parts, widest, narrowest, msPerPart, holdMs?, mouseSpeed? } }`: the ring with the
--- caller's own numbers instead of a named difficulty (a tester, a check of its own). Each means what it means in
--- Config.SkillCheckDifficulty; holdMs and mouseSpeed default to config.lua's.
---@param difficulty string|table|nil
---@return table|nil level  { name, pieces, rounds (one width per part), holdMs, timeLimitMs, mouseSpeed, own? } — what the page draws
---@return string|nil why   a sentence naming the problem, when there is no level
function SkillCheckLevel(difficulty)
    if type(difficulty) == 'table' then
        if difficulty.level ~= nil then
            if type(difficulty.level) ~= 'table' then
                return nil, 'SkillCheck { level } takes a table of the ring\'s numbers (pieces, parts, widest, narrowest, msPerPart)'
            end
            return readLevel('own', difficulty.level, "The skill check's own level", true)
        end
        -- A non-empty table with no `difficulty` is refused (e.g. an old `{ checks = ... }` list), not
        -- quietly read as the default. Only an empty table means "the default".
        if difficulty.difficulty == nil and next(difficulty) ~= nil then
            return nil, "SkillCheck takes a difficulty now ('easy', 'medium' or 'hard'), not a list of checks"
        end
        difficulty = difficulty.difficulty
    end
    if difficulty == nil then difficulty = DEFAULT end

    local levels = type(Config.SkillCheckDifficulty) == 'table' and Config.SkillCheckDifficulty or {}
    local def = type(difficulty) == 'string' and levels[difficulty] or nil
    if type(def) ~= 'table' then
        return nil, ("no skill check difficulty called '%s' (Config.SkillCheckDifficulty has easy, medium and hard)")
            :format(tostring(difficulty))
    end
    return readLevel(difficulty, def, 'Config.SkillCheckDifficulty.' .. difficulty, false)
end

--- Level names easiest first, as a list shows them: easy, medium, hard, then any other A to Z. Sorts `names` in place.
local LADDER = { easy = 1, medium = 2, hard = 3 }
---@param names string[]
---@return string[] names
function SortSkillLevels(names)
    table.sort(names, function(a, b)
        local x, y = LADDER[a] or 4, LADDER[b] or 4
        if x ~= y then return x < y end
        return a < b
    end)
    return names
end

--- The ring's settings as they are now (config.lua's, or what an admin changed in /whip Config), for a tool that
--- shows them: { holdMs, mouseSpeed, difficulties = { easy = { pieces, parts, widest, narrowest, msPerPart }, ... } }.
--- A copy: changing it changes nothing.
exports('GetSkillCheckSettings', function()
    local out = {
        holdMs = positive(Config.SkillCheckHoldMs, 196),
        mouseSpeed = positive(Config.SkillCheckMouseSpeed, 1.0),
        difficulties = {},
    }
    for name, def in pairs(type(Config.SkillCheckDifficulty) == 'table' and Config.SkillCheckDifficulty or {}) do
        if type(name) == 'string' and type(def) == 'table' then
            local d = {}
            for _, k in ipairs(LEVEL_KEYS) do
                if type(def[k]) == 'number' then d[k] = def[k] end
            end
            out.difficulties[name] = d
        end
    end
    return out
end)
