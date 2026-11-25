-- ============================================
-- Item: lockpick (Lockpicking Tools)
-- Non-usable — reusable tool for unlocking vehicles
-- ============================================

--- Returns true if the player has a lockpick in any inventory container
function Vehicles.playerHasLockpick(player)
    if not player or not player.inventory then return false end
    for _, container in pairs(PlayerContainers) do
        local slots = player.inventory[container]
        if slots then
            for _, slot in pairs(slots) do
                if slot and slot.item == 'lockpick' then
                    return true
                end
            end
        end
    end
    return false
end
