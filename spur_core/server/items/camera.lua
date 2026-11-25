-- ============================================
-- Item: camera
-- A tool, never used up: used, the player's game takes it out and up to the eye (client/items/camera.lua);
-- used again, it goes away.
-- ============================================
--
-- The camera in the hand is a held prop (server/held_props.lua), so everyone sees it, made here when the
-- player's game says the camera is coming out and only while they carry one. Anything else that takes the
-- hand (an emote, a bar, give mode) takes the camera away with it, and the player's game is told to put
-- the viewfinder away.

local CAMERA_PROPS = {
    -- On the right hand as the paparazzi clips hold it (shared/emote_list.lua's Camera 2).
    -- RedM (spur_core, 24 Nov 2026): RDR2's box camera; GTA's prop_pap_camera_01 doesn't exist in RDR2. The bone is
    -- GTA's PH_R_Hand, which shared/rdr_compat.lua turns into RDR2's when the player's game attaches it.
    { model = 'p_camera01x', bone = 28422, offset = { 0.0, 0.0, 0.0 }, rot = { 0.0, 0.0, 0.0 } },
}

-- false: done, and not used up (as the jerry can's equip).
Inventory.registerUseHandler('camera', function(source)
    TriggerClientEvent('spur_core:client:cameraUse', source)
    return false
end, GetCurrentResourceName())

--- The player's game took the camera out (true) or put it away (false).
SecureEvent('spur_core:server:cameraHold', {
    rateLimit = 250,
    burst     = 4,
    whileDead = true,   -- dying puts it away; its prop must still go
    params    = { {'on', 'bool'} },
}, function(source, player, on)
    if not on then
        HeldProps.drop(source, 'camera')
        return
    end
    if Inventory.getItemCountAcrossContainers(player.inventory, 'camera') < 1 then
        return false, 'You have no camera'
    end
    return HeldProps.give(source, CAMERA_PROPS, 'camera')
end)

AddEventHandler('spur_core:heldProps:lost', function(e)
    if type(e) == 'table' and e.tag == 'camera' and e.source then
        TriggerClientEvent('spur_core:client:cameraAway', e.source)
    end
end)
