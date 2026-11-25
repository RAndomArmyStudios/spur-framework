-- ============================================
-- ACTION MODE — kept off, every frame
-- ============================================
--
-- GTA's combat stance after firing or being shot at. Nothing switches it off for good: no ped config
-- flag does, the reset flag that does (200, PRF_DisableActionMode) clears every frame, and GTA forces
-- the stance back every frame for about 4 s after a punch.
--
-- Every frame (any slower lets it show), on whip's one per-frame loop (ControlBlocks, an empty spec: no
-- controls held) rather than a thread of its own: two natives a frame. After controls.lua in the
-- manifest, which defines it.
--
-- Not in a vehicle (the stance cannot happen there). Let go when client/vehicles.lua says the player got
-- in (spur_core:vehicle:entered, also fired for a car the player is already in when spur_core starts) and
-- taken again when it says they got out (…:exited). That edge is read every 200 ms, so the first moments
-- on foot can go up to that long without it.

local cfg = Config.ActionMode or {}
local seated = false   -- in a vehicle, as client/vehicles.lua last said

local function actionModeFrame()
    local ped = PlayerPedId()
    if ped == 0 then return end
    SetPedResetFlag(ped, 200, true)   -- PRF_DisableActionMode, for this frame
    if IsPedUsingActionMode(ped) then SetPedUsingActionMode(ped, false, -1, 'DEFAULT_ACTION') end
end

--- Held exactly while it is switched on (Config.ActionMode.Disable) and the player is on foot.
local function sync()
    if cfg.Disable ~= false and not seated then
        ControlBlocks.hold('actionMode', {}, actionModeFrame)
    else
        ControlBlocks.release('actionMode')
    end
end

sync()

AddEventHandler('spur_core:vehicle:entered', function() seated = true; sync() end)
AddEventHandler('spur_core:vehicle:exited', function() seated = false; sync() end)

-- Changed in /whip → Settings (in place, so `cfg` sees it): the per-frame hold taken or let go.
Settings.onChange('ActionMode.Disable', function()
    sync()
end)
