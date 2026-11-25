-- The body, as the player's game sees it. BodyState.of(ped): under water, swimming, falling, or nothing
-- (see shared/body_state.lua). Asked by a bar's `notWhile` (client/ui.lua), the breath (client/stats.lua)
-- and the GetBodyState export. Natives in, answers out.

local SUNK_LEVEL = 0.85   -- how far under water (0 to 1) a car is sunk: client/vehicle_damage.lua's wreck rule
local BOATS = 14          -- the vehicle class of boats and submarines, built to sit in water

--- Is the player under water? Swimming under, or in a car that has gone under (the car's water level, not the
--- ped's). Not a boat or submarine, nor a car in submarine mode (IS_VEHICLE_IN_SUBMARINE_MODE).
---@param ped number
---@return boolean
function BodyState.underwater(ped)
    if IsPedSwimmingUnderWater(ped) then return true end
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 or GetVehicleClass(veh) == BOATS then return false end
    if (tonumber(GetEntitySubmergedLevel(veh)) or 0.0) < SUNK_LEVEL then return false end
    -- By hash, in a pcall: a game build without the native must not stop the breath's loop.
    local ok, sub = pcall(Citizen.InvokeNative, 0xA77DC70BD689A1E5, veh, Citizen.ResultAsInteger())
    return not (ok and sub ~= nil and sub ~= 0)
end

-- Faster than this downwards, in the air, is a fall (a jump is slower). A long fall ragdolls the ped and ends GTA's
-- own falling state, so speed is what still says it.
local FALL_SPEED = -6.0   -- metres a second

--- Is the player falling? GTA's fall or a skydive, or a body in the air coming down fast. Not in a seat.
---@param ped number
---@return boolean
function BodyState.falling(ped)
    if IsPedFalling(ped) or IsPedInParachuteFreeFall(ped) then return true end
    if not IsEntityInAir(ped) or IsPedInAnyVehicle(ped, false) then return false end
    return GetEntityVelocity(ped).z < FALL_SPEED
end

--- What the body is doing, the first that applies: 'underwater', 'swimming', 'falling', or nil.
---@param ped number|nil  the player's own by default
---@return string|nil state
function BodyState.of(ped)
    ped = ped or PlayerPedId()
    if BodyState.underwater(ped) then return 'underwater' end
    if IsPedSwimming(ped) then return 'swimming' end
    if BodyState.falling(ped) then return 'falling' end
    return nil
end

--- Why a ragdolled player's work stopped, in their words (a long fall ragdolls too, and is said as falling).
---@param ped number
---@return string
function BodyState.ragdollWhy(ped)
    if BodyState.falling(ped) then return BodyState.WORDS.falling end
    return 'You were knocked down'
end

--- What the player's body is doing that work in the hands cannot be done in, and the words for it:
--- 'underwater' | 'swimming' | 'falling', or false.
---
--- ```lua
--- local state, words = exports.spur_core:GetBodyState()
--- if state then return Notify(words, 'error') end   -- 'You cannot do that while swimming'
--- ```
exports('GetBodyState', function()
    local state = BodyState.of(PlayerPedId())
    if not state then return false end
    return state, BodyState.WORDS[state]
end)
