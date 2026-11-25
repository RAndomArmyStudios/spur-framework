-- ============================================
-- Director — the band: what a run tells each of its players on screen
-- ============================================
--
-- One objective card per player per run, at the top right of their screen (PlayerText.objective,
-- server/player_text.lua: separate from the instruction band at the bottom, which other things
-- take). A run puts two things on it:
--   * its OBJECTIVE: "Get to the docks" (Show Objective, a Goal card while it waits)
--   * its CLOCKS: a Countdown, a Goal's time limit
-- The card shows the objective with the clock that ends first counting down under it, the job's name
-- beside the clock. A clock with no objective shows its own words ("Time left"). Each card puts up and
-- takes down only ITS part, by a key: a Goal that ends does
-- not wipe an objective a later card showed, and a Countdown stopping leaves a Goal's clock alone.
-- Objectives are kept by key in the order they were put up, and the newest still up is the one shown,
-- so two goals at once (Survive while Kill Them All) fall back to each other as they end.
--
-- Kept on the run (run.band), so it goes with the run; what is on screen goes with the run's tag
-- (the card carries it). A player leaving the run is taken off it (main.lua's leave).

DirectorBand = {}

local CORE = GetCurrentResourceName()

local function slot(run, src)
    run.band = run.band or {}
    local b = run.band[src]
    if not b then
        b = { objectives = {}, clocks = {} }   -- objectives: { { key, text } } oldest first
        run.band[src] = b
    end
    return b
end

local function find(b, key)
    for i, o in ipairs(b.objectives) do if o.key == key then return i end end
    return nil
end

--- The run's card's name: one card per run, so two runs are two cards.
local function cardOf(run)
    return run.tag or ('run:' .. tostring(run.id))
end

--- What one player's band says for this run now: its text (nil: nothing), the clock beside it, and the icon
--- and subtext its objective asked for (Show Objective's; nil: the flag, and the scenario's name).
---@return string|nil text
---@return table|nil clock  { endsAt, total }, the one that ends first
---@return string|nil icon
---@return string|false|nil sub  its own words, false for none, nil for the scenario's name
local function shown(run, src)
    local b = run.band and run.band[src]
    if not b then return nil end
    local first
    for _, c in pairs(b.clocks) do
        if not first or c.endsAt < first.endsAt or (c.endsAt == first.endsAt and c.key < first.key) then first = c end
    end
    local newest = b.objectives[#b.objectives]
    local text = (newest and newest.text) or (first and first.label) or nil
    if type(text) ~= 'string' or text == '' then return nil, nil end
    return text, first, newest and newest.icon or nil, newest and newest.sub
end

--- For other resources (the Director API): what a player's band shows, how many seconds its clock has
--- left (nil when there is none), and when that clock ends (GetGameTimer ms: the same clock, the same
--- number, whenever it is asked).
---@return string|nil text
---@return number|nil countdown
---@return number|nil endsAt
function DirectorBand.current(run, src)
    local text, clock = shown(run, src)
    if not text then return nil, nil, nil end
    if not clock then return text, nil, nil end
    return text, math.max(0, math.floor((clock.endsAt - GetGameTimer()) / 1000)), clock.endsAt
end

--- Put one player's band up as it now stands for this run, or take it down when it says nothing.
local function draw(run, src)
    local b = run.band and run.band[src]
    if not b or run.status ~= 'running' or not run.players[src] then return end
    local text, first, icon, sub = shown(run, src)
    -- The player's own game hears what their band says (a phone's job screen, a HUD): api.lua.
    Director.tellPlayer(run, src, 'updated')
    if not text then
        PlayerText.clearObjective(CORE, src, cardOf(run))
        return
    end
    local name = run.scenario and run.scenario.name or run.scenarioId
    if sub == false then name = nil elseif type(sub) == 'string' then name = sub end
    local opts = { tag = run.tag, name = name, icon = icon }
    if first then
        opts.countdown = math.max(0, (first.endsAt - GetGameTimer()) / 1000)
        opts.countdownTotal = first.total
    end
    local ok, why = PlayerText.objective(CORE, src, cardOf(run), text, opts)
    if not ok then print(('[spur_core:director] run %d: the objective for %s: %s'):format(run.id, tostring(src), tostring(why))) end
end

--- Show `text` as the objective for one player, under `key` (whose it is): the newest, so the one shown.
--- `icon`: the card's disc, a glyph's key (html/js/glyphs.js); nil, the flag. `sub`: the line under it, its own words,
--- false for none; nil, the scenario's name.
function DirectorBand.objective(run, src, text, key, icon, sub)
    local b = slot(run, src)
    local i = find(b, key)
    if i then table.remove(b.objectives, i) end
    b.objectives[#b.objectives + 1] = { key = key, text = text, icon = icon, sub = sub }
    draw(run, src)
end

--- Change the words of `key`'s objective where it stands (a goal's count: "(2 left)"), not putting it
--- above a newer one. Nothing when it is not up.
function DirectorBand.reword(run, src, key, text)
    local b = run.band and run.band[src]
    local i = b and find(b, key)
    if not i then return end
    b.objectives[i].text = text
    draw(run, src)
end

--- Take `key`'s objective down; the newest one left (if any) is shown.
function DirectorBand.clearObjective(run, src, key)
    local b = run.band and run.band[src]
    local i = b and find(b, key)
    if not i then return end
    table.remove(b.objectives, i)
    draw(run, src)
end

--- Start a clock for one player: `seconds` from now, under `key`; `label` is said when there is no
--- objective ("Time left").
function DirectorBand.clock(run, src, key, seconds, label)
    local b = slot(run, src)
    local s = math.max(0, tonumber(seconds) or 0)
    b.clocks[key] = { key = key, label = label, endsAt = GetGameTimer() + math.floor(s * 1000), total = s }
    draw(run, src)
end

--- Stop one of the clocks.
function DirectorBand.stopClock(run, src, key)
    local b = run.band and run.band[src]
    if not b or not b.clocks[key] then return end
    b.clocks[key] = nil
    draw(run, src)
end

--- A player is out of the run: their card for it goes.
function DirectorBand.drop(run, src)
    if not (run.band and run.band[src]) then return end
    run.band[src] = nil
    PlayerText.clearObjective(CORE, src, cardOf(run))
end
