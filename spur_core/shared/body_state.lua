-- Body states (swimming, under water, falling) that work in the hands cannot be done in. A progress bar names the
-- ones it refuses (`notWhile`): it does not start in one, and one that begins while it runs ends it, with these
-- words. The server only checks the list; the player's game reads the body (client/body_state.lua).

BodyState = {}

--- The words the player is shown, by state. Under water counts as swimming too, with its own words.
BodyState.WORDS = {
    underwater = 'You cannot do that while underwater',
    swimming   = 'You cannot do that while swimming',
    falling    = 'You cannot do that while falling',
}

--- A `notWhile` list, checked: the set it names ({ swimming = true, ... }), or nil and why. nil names none.
---@param list table|nil  any of 'swimming', 'underwater', 'falling'
---@return table|nil set
---@return string|nil why
function BodyState.readList(list)
    if list == nil then return {} end
    if type(list) ~= 'table' then return nil, "notWhile is a list: { 'swimming', 'underwater', 'falling' }" end
    local set = {}
    for _, name in ipairs(list) do
        if not BodyState.WORDS[name] then
            return nil, ("notWhile: no state '%s' (swimming, underwater, falling)"):format(tostring(name))
        end
        set[name] = true
    end
    return set
end

--- The words for a body in `state` that `set` refuses, or nil when it may go on.
---@param set table        BodyState.readList's answer
---@param state string|nil BodyState.of's answer (client)
---@return string|nil words
function BodyState.refuses(set, state)
    if not state then return nil end
    if set[state] or (state == 'underwater' and set.swimming) then return BodyState.WORDS[state] end
    return nil
end
