-- spur_gunny: THROWABLES AND ARROWS (server)
--
-- Each one thrown is taken from the drawn stack through spur_core, which logs it ("thrown"). Only ever taken, never
-- given: a client can lose its own dynamite by saying so, never gain one. Each report is bounded and capped at what
-- there is.
--
-- RedM (spur_gunny, 24 Nov 2026): a bow reports its arrows here too. Each arrow shot is taken from the arrows of its
-- kind in the pockets (an arrow lying in the world is the game's, and is not picked up as an item).

RegisterGunnyEvent('spur_gunny:server:thrown', {
    whileDead = true,   -- one thrown (or a lit stick dropped) as the player dies still leaves the stack
    sheet = 'light',    -- the handler never reads `player`
    -- A throw takes most of a second, an arrow a little less; the burst covers a few reported together after a hitch.
    rateLimit = 100,
    burst     = 5,
    params = {
        {'count', 'int', 1, 10, 1},
    },
}, function(source, _, count)
    local slotData, equipped = GunnyDrawnWeapon(source)
    if not equipped then GunnyNoDrawRecord(source) return end
    if not slotData then
        GunnyForceHolster(source)
        return
    end
    local weaponConfig = Config.GetWeapon(slotData.item)
    local bow = Config.IsBow(weaponConfig)
    if not (bow or Config.IsThrowable(weaponConfig)) then return end

    -- Every throw reported this draw, sent back with each stack count so the client takes off those still on their way
    equipped.taken = (equipped.taken or 0) + count

    local have
    if bow then
        have = equipped.arrowItem and (exports.spur_core:GetItemCount(source, equipped.arrowItem) or 0) or 0
    else
        have = tonumber(slotData.amount) or 0
    end
    count = math.min(count, have)
    if count < 1 then return end

    -- The count as the hand has it now, first: our own take must arrive as no change (server/weapons.lua).
    equipped.count = have - count
    local removed, why
    if bow then
        removed, why = exports.spur_core:RemoveItem(source, equipped.arrowItem, count, nil, { reason = 'shot from a bow' })
    else
        removed, why = exports.spur_core:StoreTake(GunnyPocket(source, equipped.pocket, equipped.slot), count, 'thrown')
    end
    if not removed then
        equipped.count = have
        GunnyWarn('a throw was not taken (%s): %s', bow and equipped.arrowItem or slotData.item, tostring(why))
        TriggerClientEvent('spur_gunny:client:syncThrown', source, have, equipped.taken)   -- the hand back to the count
        return
    end
    GunnyDebugPrint(bow and 'Arrow shot:' or 'Thrown:', count, bow and equipped.arrowItem or slotData.item, '-', equipped.count, 'left')
end)
