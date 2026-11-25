-- spur_gunny: THE ITEMS, REGISTERED WITH SPUR_CORE
--
-- Every weapon, cartridge and gunsmith part in items/*.lua becomes a spur_core item: its name, weight, card, menu and
-- settings, and the metadata a new one starts with. Through Whip.register, so all of it is declared once spur_core is
-- ready (it keeps items in memory). A spur_core restart stops gunny first and starts it again (its dependency).
--
-- RedM (spur_gunny, 24 Nov 2026): no magazines (no Load Bullets, no Open, no magazine slot), no jerry can. A gun's card
-- shows the cartridges loaded and their kind; its menu has Unload and Switch Cartridges. A bow's has Switch Arrows.
-- whip_core -> spur_core, whip_gunny: -> spur_gunny:.

-- Where gunny's options sit on an item's right-click menu (above spur_core's Give, Place and Split, lowest first).
local MENU_ORDER = { equip = 1, unload = 3, switch = 4 }

-- On the ground, a weapon's prompt offers Equip after Pick up: picked up as Pick up does, then drawn from the slot
-- it landed in.
local GROUND_EQUIP = { { action = 'spur_gunny:equip_weapon', label = 'Equip', icon = 'target' } }

-- A gun's settings on the Items page (shared/catalog.lua writes the value into its table): the cartridges it holds.
local function gunSettings(itemName)
    local capacity = Config.ItemSettingDefault(itemName, 'capacity')
    if not capacity then return nil end
    -- At most 250, or the gun's own size where that is more: spur_core refuses an item whose default is past its
    -- setting's limit.
    return {
        { key = 'capacity', type = 'int', min = 1, max = math.max(250, capacity), default = capacity,
          label = 'Rounds it holds',
          help = 'How many cartridges it takes. Lowered, a gun holding more gives the extra back to the pockets the next time it is drawn, but never goes below its standard size.' },
    }
end

--- A weapon pack's item (shared/packs.lua): its icon in the pack, html/img/items/<item>.webp or .png, as spur_core's
--- '@pack/path'. nil for gunny's own (spur_core finds those in gunny's folder) or a pack's with none.
---@param itemName string
---@return string|nil
local function packImage(itemName)
    local pack = GunnyPacks.owner[itemName]
    if not pack then return nil end
    for _, ext in ipairs({ 'webp', 'png' }) do
        local path = ('html/img/items/%s.%s'):format(itemName, ext)
        if LoadResourceFile(pack, path) then return ('@%s/%s'):format(pack, path) end
    end
    return nil
end

-- RedM (spur_gunny, 25 Nov 2026): whip_gunny's item pictures are GTA's guns, so this copy shipped none and every
-- gun showed spur_core's "no picture" glyph. Now each item has the picture of its class (a revolver, a repeater, a
-- box of cartridges...), drawn for this copy: html/img/items/class/<class>.png (painted, 25 Nov 2026; flat .svg drawings before that). A picture named after the item
-- itself (html/img/items/<item>.webp or .png, here or in a weapon pack) still comes first.
local CLASS_DIR = 'html/img/items/class/'
local WEAPON_CLASS = {   -- the first whose text the weapon's game name has
    { 'THROWING_KNIVES', 'throwing_knives' }, { 'REVOLVER', 'revolver' }, { 'PISTOL', 'pistol' },
    { 'REPEATER', 'repeater' }, { 'SHOTGUN', 'shotgun' }, { 'RIFLE', 'rifle' }, { 'BOW', 'bow' },
    { 'KNIFE', 'knife' }, { 'MACHETE', 'machete' }, { 'TORCH', 'torch' }, { 'LASSO', 'lasso' },
    { 'HATCHET', 'hatchet' }, { 'TOMAHAWK', 'tomahawk' }, { 'CLEAVER', 'cleaver' }, { 'DYNAMITE', 'dynamite' },
    { 'MOLOTOV', 'bottle_fire' }, { 'POISONBOTTLE', 'bottle_poison' }, { 'BOLAS', 'bolas' },
}

--- The picture an item shows: its own where there is one, else its class's, else nil (spur_core's glyph).
---@param itemName string
---@param class string|nil
---@return string|nil
local function itemImage(itemName, class)
    local own = packImage(itemName)
    if own then return own end
    for _, ext in ipairs({ 'webp', 'png' }) do
        if LoadResourceFile(GetCurrentResourceName(), ('html/img/items/%s.%s'):format(itemName, ext)) then return nil end
    end
    if class and LoadResourceFile(GetCurrentResourceName(), CLASS_DIR .. class .. '.png') then
        return CLASS_DIR .. class .. '.png'
    end
    return nil
end

local function weaponClass(w)
    local name = tostring(w.weapon or ''):upper()
    for _, row in ipairs(WEAPON_CLASS) do
        if name:find(row[1], 1, true) then return row[2] end
    end
    return nil
end

local function ammoClass(a)
    if a.group == 'shotgun' then return 'shells' end
    if a.group == 'arrow' then return 'arrow' end
    return 'cartridges'
end

--- A weapon's item, and the metadata a new one starts with (nil: none, so stacks of it merge).
---@param itemName string
---@param w table  its Config.Weapons entry
---@return table def
---@return function|nil newMeta
local function weaponDef(itemName, w)
    local def = {
        name     = w.label or itemName,
        desc     = w.description or w.label or itemName,
        type     = 'weapon',
        stack    = false,
        maxStack = 1,
        usable   = false,
        prop     = w.prop,
        image    = itemImage(itemName, weaponClass(w)),
        defaultAction  = 'spur_gunny:equip_weapon',
        contextOptions = { { action = 'spur_gunny:equip_weapon', label = 'Equip', order = MENU_ORDER.equip } },
        groundOptions  = GROUND_EQUIP,
    }
    if Config.IsThrowable(w) then
        -- A stack, with no metadata, so stacks merge; the drawn one is known by its slot and item.
        def.weight = w.weight or 0.5
        def.stack, def.maxStack = true, w.maxStack or 25
        return def, nil
    elseif Config.IsMelee(w) then
        -- No card rows. The serial is still stamped: it is how the drawn weapon is known (GunnyDrawnWeapon).
        def.weight = w.weight or 1.0
        return def, function() return { serial = GunnyNewSerial() } end
    elseif Config.IsBow(w) then
        -- Its arrows are carried, not loaded: the card says which kind it shoots.
        def.weight = w.weight or 1.0
        def.contextOptions[2] = { action = 'spur_gunny:switch_ammo', label = 'Switch Arrows', order = MENU_ORDER.switch }
        def.metaFields = { { key = 'serial', label = 'Serial' }, { key = 'kindLabel', label = 'Arrows' } }
        return def, function()
            local kind = Config.DefaultKind(itemName)
            return { serial = GunnyNewSerial(), kind = kind, kindLabel = kind and Config.AmmoLabel(kind) or nil }
        end
    end
    -- A gun: its card its serial, what is loaded and its caliber.
    def.desc = w.description or ''
    def.weight = w.weight or 2.0
    def.contextOptions[2] = { action = 'spur_gunny:unload', label = 'Unload', order = MENU_ORDER.unload,
                              when = { ammo = { above = 0 } }, whyNot = 'It is not loaded' }
    def.contextOptions[3] = { action = 'spur_gunny:switch_ammo', label = 'Switch Cartridges', order = MENU_ORDER.switch }
    def.metaFields = {
        { key = 'serial', label = 'Serial' },
        { key = 'ammo', label = 'Loaded' },
        { key = 'kindLabel', label = 'Cartridges' },
        { key = 'caliber', label = 'Caliber', value = Config.GroupLabel(itemName) },
    }
    def.settings = gunSettings(itemName)
    return def, function()
        local kind = Config.DefaultKind(itemName)
        return { serial = GunnyNewSerial(), ammo = 0, kind = kind, kindLabel = kind and Config.AmmoLabel(kind) or nil,
                 attachments = {} }
    end
end

--- A cartridge item: a stack, carried loose.
local function ammoDef(itemName, a)
    return {
        name     = a.label or itemName,
        desc     = a.description or ((Config.AmmoGroups[a.group] or {}).label or '') .. ' ammunition',
        weight   = a.weight or 0.01,
        type     = 'ammo',
        stack    = true,
        maxStack = a.maxStack or 999,
        usable   = false,
        prop     = a.prop,
        image    = itemImage(itemName, ammoClass(a)),
    }
end

--- RegisterItem answers (ok, err): a refusal is said. Answers whether it landed, and why not. A refused new-item
--- metadata (the serial a new one starts with) is said too, but the item stays: GiveWeapon sets its own, and a gun
--- without one still draws.
local function regItem(itemName, def, newMeta)
    local ok, err = exports.spur_core:RegisterItem(itemName, def)
    if not ok then
        Whip.startProblem('item "%s" refused: %s', tostring(itemName), tostring(err))
        return false, err
    end
    if newMeta then
        local metaOk, metaWhy = exports.spur_core:RegisterItemDefaultMetadata(itemName, newMeta)
        if not metaOk then Whip.startProblem('item "%s": its new-item metadata refused: %s', tostring(itemName), tostring(metaWhy)) end
    end
    return true
end

local function registerWeapon(itemName)
    return regItem(itemName, weaponDef(itemName, Config.Weapons[itemName]))
end

local function registerAmmo(itemName)
    return regItem(itemName, ammoDef(itemName, Config.Ammo[itemName]))
end

local function registerWithCore()
    -- A weapon pack's item spur_core refuses (its name is another resource's item) leaves gunny's tables, after the
    -- loops: nothing may draw or load it (shared/packs.lua).
    local refused = {}
    local function noteRefused(itemName, ok, why)
        if not ok and GunnyPacks.owner[itemName] then refused[itemName] = why end
    end

    for itemName in pairs(Config.Ammo) do noteRefused(itemName, registerAmmo(itemName)) end
    for itemName in pairs(Config.Weapons) do noteRefused(itemName, registerWeapon(itemName)) end
    for itemName, why in pairs(refused) do GunnyPacks.refused(itemName, why) end

    for itemName, attData in pairs(Config.Attachments or {}) do
        regItem(itemName, {
            name     = attData.label or itemName,
            desc     = attData.description or (attData.label .. ', fitted by a gunsmith'),
            weight   = attData.weight or 0.2,
            type     = 'weapon',
            stack    = false,
            maxStack = 1,
            prop     = attData.prop,
            -- RedM (spur_gunny, 25 Nov 2026): a part shows its kind's picture (class/scope, barrel, rifling.png).
            image    = itemImage(itemName, attData.category),
        })
    end

    -- The right-click actions. spur_core hands each the item's address (addr.sub is the pocket). Action names are
    -- server-wide, first come first served, so they carry this resource's name.
    local function action(name, fn)
        local ok, why = exports.spur_core:RegisterContextAction(name, fn)
        if not ok then Whip.startProblem('context action %s refused: %s', name, tostring(why)) end
    end

    -- From a pile's prompt (`how.from == 'ground'`): straight into the hand, no draw.
    action('spur_gunny:equip_weapon', function(source, _, _, addr, how)
        TriggerClientEvent('spur_gunny:client:useWeapon', source, addr.slot, addr.sub, type(how) == 'table' and how.from == 'ground')
    end)

    -- A refusal is answered `false, why`: spur_core shows the player why, and records it. Unload waits for AddItem
    -- (full pockets drop the cartridges on the ground): the action's handler is a thread of spur_core's.
    action('spur_gunny:unload', function(source, _, slotData, addr)
        if not Config.IsFirearm(Config.GetWeapon(slotData.item)) then return false, 'That is not a gun' end
        local ok, why = GunnyUnload(source, addr, slotData)   -- server/reload.lua
        if not ok then return false, why end
        exports.spur_core:NotifyPlayer(source, ('Unloaded %d %s'):format(why, Config.AmmoLabel(GunnyKindOf(slotData.item, slotData.metadata))), 'success')
    end)

    action('spur_gunny:switch_ammo', function(source, _, slotData, addr)
        local ok, why = GunnySwitchKind(source, addr, slotData)   -- server/reload.lua
        if not ok then return false, why end
        exports.spur_core:NotifyPlayer(source, ('Set for %s'):format(why), 'success')
    end)

    -- The sizes set on the Items page, into gunny's tables: now, and at each change.
    Config.FollowItemSettings()
end

Whip.register(registerWithCore)

-- One line in the console once everything has registered: started, or what went wrong.
Whip.sayStarted()

-- A weapon pack's item arriving while spur_core runs: registered now, with its settings. (Before spur_core is up,
-- registerWithCore takes it in with the rest. One that goes stays an item: players carry it.)
GunnyPacks.onChange(function(itemName, kind, gone)
    if gone or not Whip.isReady() then return end
    local ok, why
    if kind == 'ammo' then ok, why = registerAmmo(itemName) else ok, why = registerWeapon(itemName) end
    -- Refused (its name is another resource's item): out of gunny's tables, and the pack's export answers false.
    if not ok then GunnyPacks.refused(itemName, why) return end
    if kind == 'weapon' then Config.FollowItemSettings(nil, itemName) end
end)

-- ============================================
-- EXPORTS
-- ============================================

--- Give a player a weapon with fresh metadata. `reason` is for the activity log ('shop purchase', 'admin spawn').
--- spur_core's own AddItem gives the same weapon, empty: this is for the options.
---
--- `overrides`: `serial`, `attachments` ({ [category] = part item }), and by kind:
--- - a gun: `kind` (the cartridge item it is set for, one of its group's), and `ammo`, the cartridges in it, or
---   `loaded = true` to fill it;
--- - a bow: `kind`, the arrows it shoots;
--- - a throwable: `amount`, the stack (1 if none). A throwable carries no metadata.
--- Cartridges are held to what the gun holds. Answers true and where it went, as AddItem does: 'inventory', or
--- 'ground' at their feet when it did not fit; and its serial, to find it again with spur_core's
--- FindItemByMetadata('serial', serial) (a throwable has none: a stack is not one thing).
exports('GiveWeapon', function(source, weaponName, overrides, reason)
    local weaponConfig = Config.GetWeapon(weaponName)
    if not weaponConfig then return false, 'Unknown weapon: ' .. tostring(weaponName) end

    overrides = type(overrides) == 'table' and overrides or {}

    if Config.IsThrowable(weaponConfig) then
        local amount = math.max(1, math.floor(tonumber(overrides.amount) or 1))
        local where, err = Whip.core:AddItem(source, weaponName, amount, nil, reason)
        if not where then return false, err end
        return true, where
    end

    local serial = type(overrides.serial) == 'string' and overrides.serial ~= '' and overrides.serial or GunnyNewSerial()
    local meta
    if Config.IsMelee(weaponConfig) then
        meta = { serial = serial }
    else
        local kind = overrides.kind
        if kind ~= nil and not Config.AmmoFits(weaponName, kind) then
            return false, ('%s does not take %s'):format(weaponName, tostring(kind))
        end
        kind = kind or Config.DefaultKind(weaponName)
        meta = { serial = serial, kind = kind, kindLabel = kind and Config.AmmoLabel(kind) or nil }
        if Config.IsFirearm(weaponConfig) then
            local cap = math.max(0, math.floor(tonumber(weaponConfig.capacity) or 0))
            meta.ammo = overrides.loaded and cap or math.max(0, math.min(cap, math.floor(tonumber(overrides.ammo) or 0)))
            meta.attachments = {}
            -- Each part one this gun takes in that slot, as the gunsmith would fit it.
            for category, attName in pairs(type(overrides.attachments) == 'table' and overrides.attachments or {}) do
                local att = Config.GetAttachment(attName)
                if not (att and att.category == category and Config.GetWeaponAttachmentComponent(weaponName, category, att.tier)) then
                    return false, ('%s does not take %s in its %s slot'):format(weaponName, tostring(attName), tostring(category))
                end
                meta.attachments[category] = attName
            end
        end
    end

    -- AddItem answers where it went ('inventory' or 'ground'), or false and why. Through Whip.core, as it can wait
    -- (full pockets drop it on the ground; server/main.lua says when gunny calls spur_core which way).
    local where, err = Whip.core:AddItem(source, weaponName, 1, meta, reason)
    if not where then return false, err end
    return true, where, meta.serial
end)

--- Give a player cartridges (or arrows) of one kind: `amount` of `ammoItem`. RedM (spur_gunny, 24 Nov 2026): in place
--- of GiveMagazine. `reason` and the answer as GiveWeapon (no serial: a stack is not one thing).
exports('GiveAmmo', function(source, ammoItem, amount, reason)
    if not Config.GetAmmo(ammoItem) then return false, 'Unknown cartridges: ' .. tostring(ammoItem) end
    amount = math.floor(tonumber(amount) or 0)
    if amount < 1 then return false, 'Give at least one' end
    local where, err = Whip.core:AddItem(source, ammoItem, amount, nil, reason)
    if not where then return false, err end
    return true, where
end)
