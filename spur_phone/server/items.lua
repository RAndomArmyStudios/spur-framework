-- The phone and the SIM card (Josh, 7 Oct 2026: a phone item is needed, and a phone takes any SIM).
--
--   phone     Use: takes the phone out. Right-click > SIM tray: a one-slot panel that takes a SIM card
--             (spur_core's RegisterPanelItem; the card is kept in the phone's metadata, `sim`). The
--             phone's own look (Do Not Disturb, and its wallpaper while it has no SIM) is on it too,
--             `settings`, so a phone handed over keeps its look.
--   sim_card  metadata { phoneNumber, owner }. Made for whoever receives it (spur_core hands the item's
--             generator who it is for): given or bought, it is a new number of theirs; bought off a
--             shop's shelf it is made again for the buyer (forBuyer). Made for nobody (into a stash, a
--             Director reward) it is blank, and gets a number when first put in a phone (server/sim.lua).
-- RedM (spur_phone, 24 Nov 2026): the item keys stay 'phone' and 'sim_card' (spur_core's Phone slot, the admin pages and saved
-- inventories read them); what players read is a pocket notebook and a telegraph address card. The pictures
-- (html/img/items/<key>.webp, 512x512 WebP with alpha) are new, drawn for this copy; whip_phone's were renders of its
-- smartphone and SIM. No dropped-item model is named: spur_core puts its own ground prop down (no RDR2 notebook
-- model has been tried in game yet). An item's picture lives with whoever registers it.

local PHONE, CARD = 'phone', 'sim_card'

--- A SIM card's metadata for whoever it is made for (spur_core's ctx), or blank for nobody.
local function newCard(_, ctx)
    local charId = type(ctx) == 'table' and tonumber(ctx.charId) or nil
    if not charId then return {} end
    local number = Numbers.mint()
    if not number then return {} end
    return { phoneNumber = number, owner = charId }
end

--- The holder of a phone whose SIM changed: an open phone is told at once (a new session), and a call on the
--- number that left it ends (server/calls.lua).
local function simChanged(ctx)
    local src = ctx and ctx.source
    if src then
        TriggerClientEvent('spur_phone:client:refresh', src)
        if Calls then Calls.recheck(src) end
    end
end

Whip.register(function()
    local ok, why = exports.spur_core:RegisterItem(PHONE, {
        name = 'Pocket Notebook', desc = 'Telegrams, telephone calls, your passbook and ledger. Keeps a telegraph address card.',
        weight = 0.2, type = 'electronics', stack = false, usable = true, image = 'html/img/items/phone.webp',
        contextOptions = { { action = 'phone_sim_tray', label = 'Address card pocket' } },
    })
    if not ok then print('[spur_phone] could not register the notebook item: ' .. tostring(why)) end

    ok, why = exports.spur_core:RegisterItem(CARD, {
        name = 'Telegraph Address Card', desc = 'Your telegraph and telephone number. Keep it in a notebook.', weight = 0.01,
        type = 'electronics', stack = false, image = 'html/img/items/sim_card.webp',
        metaFields = { { key = 'phoneNumber', label = 'Number', format = 'phone' } },
    })
    if not ok then print('[spur_phone] could not register the address card item: ' .. tostring(why)) end

    ok, why = exports.spur_core:RegisterItemDefaultMetadata(CARD, newCard, { forBuyer = true })
    if not ok then print('[spur_phone] address cards will be blank: ' .. tostring(why)) end

    ok, why = exports.spur_core:RegisterPanelItem(PHONE, {
        action = 'phone_sim_tray', label = 'Address card pocket', slots = 1, storageKey = 'sim', allowedItems = { CARD },
        onChange = simChanged,
    })
    if not ok then print('[spur_phone] no address card pocket in notebooks: ' .. tostring(why)) end

    -- The strip's first slot is its Phone slot, where a phone is looked for first (server/sim.lua): while this runs it
    -- takes phones only, and spur_core puts its own slot back when this stops. No strip, nothing to make.
    local strip = exports.spur_core:GetAccessorySlots()
    if type(strip) == 'table' and strip[1] then
        ok, why = exports.spur_core:RegisterAccessorySlot({ slot = 1, label = 'Notebook', accepts = PHONE, icon = 'phone' })
        if not ok then print('[spur_phone] the strip\'s first slot takes anything, not only notebooks: ' .. tostring(why)) end
    end

    -- `false`: used, and KEPT. A use handler that answers nothing has its item consumed (spur_core's useItem: true or
    -- nothing = eaten, false = kept, false + why = refused), and "Use" on the phone ate it — the phone then opened, found
    -- no phone, and said so (Josh, 8 Oct 2026).
    -- THIS phone (Josh, 10 Oct 2026): Use on a phone opens that one, by its uid, while it is carried (Sim.choose);
    -- the open says it came from the item, so the session keeps the choice (the hotkey's forgets it).
    exports.spur_core:RegisterUseHandler(PHONE, function(source, _, slotData)
        local uid = type(slotData) == 'table' and type(slotData.metadata) == 'table' and slotData.metadata.uid or nil
        Sim.choose(source, uid)
        TriggerClientEvent('spur_phone:client:open', source, 'phone', true)
        return false
    end)
end)
