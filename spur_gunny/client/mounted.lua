-- spur_gunny: SHOOTING FROM THE SADDLE AND FROM A WAGON (client)
--
-- The game does the shooting; the shots are counted as on foot (client/shooting.lua), and R reloads as on foot
-- (client/reload.lua). Here: pulling the trigger on an empty gun in the saddle or in a seat reloads it, as the last
-- round fired does.
--
-- RedM (spur_gunny, 24 Nov 2026): whip_gunny's client/vehicle.lua, cut down. RDR2 aims from the saddle and a seat with
-- the aim button as on foot, so the GTA double tap on RB that turned aiming on is gone, with its pad blocks. Horses
-- count as a seat here (IsPedOnMount).

-- The fire buttons: on foot and in the saddle, a driver's, a passenger's (rdr_compat maps them to RDR2's).
local FIRE = { 24, 69, 92 }

local function triggerPulled()
    for i = 1, #FIRE do
        if IsDisabledControlJustPressed(0, FIRE[i]) then return true end
    end
    return false
end

RegisterGunnyTick('mounted', function(ped)
    local w = CurrentWeapon
    if not Config.IsFirearm(w.config) then return end
    if (w.ammo or 0) > 0 or GunnyReloadUnderWay() then return end
    if not (IsPedOnMount(ped) or IsPedInAnyVehicle(ped, false)) then return end
    if triggerPulled() then GunnyStartReload() end
end)
