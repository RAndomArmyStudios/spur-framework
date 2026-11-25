-- spur_gunny: WEAPON PACKS: weapons and cartridges from another resource
--
-- A pack is a resource of its own. It ships its items' icons (html/img/items/<item>.webp, in its `files`) and tells
-- gunny about each item on both sides, in the shape items/weapons.lua and items/ammo.lua use, cartridges first:
--
--     shared_script '@spur_gunny/lib/pack.lua'
--     shared_script 'gunny.lua'   -- Gunny.register(function() exports.spur_gunny:RegisterAmmo(...) ... end)
--
-- Gunny.register runs it whenever gunny is up, and again each time gunny starts. A weapon names one of RDR2's own
-- WEAPON_ hashes (RedM streams no new weapons); it may bring its gunsmith parts as `attachments` (items/gunsmith.lua's
-- Config.WeaponAttachments shape: component names or hashes). When the pack stops, its items leave gunny's tables;
-- players keep them, and they work again when it is back.
--
-- RedM (spur_gunny, 24 Nov 2026): RegisterMagazine is gone (no magazines); RegisterAmmo takes a cartridge item of one
-- of RDR2's AMMO_ types, in one of the groups of items/ammo.lua or a new one the pack names (`groupLabel`).

GunnyPacks = { owner = {} }   -- owner[item] = the pack resource that registered it
local ownGroup = {}            -- ownGroup[group] = the pack that made this group

local listeners = {}

--- fn(itemName, kind, gone) after a pack's item arrives or changes, or goes (gone = true): kind 'weapon' or 'ammo'.
function GunnyPacks.onChange(fn)
    listeners[#listeners + 1] = fn
end

local function changed(itemName, kind, gone)
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, itemName, kind, gone)
        if not ok then Whip.startProblem('taking in pack item %s errored: %s', itemName, tostring(err)) end
    end
end

--- May `owner` register `itemName` as `kind`? Not one of gunny's own, another running pack's, or another kind's.
local function claim(itemName, owner, kind)
    if type(itemName) ~= 'string' or #itemName > 50 or not itemName:match('^[%w_%-]+$') then
        return false, 'an item name is letters, digits, _ and -, 50 at most'
    end
    local holder = GunnyPacks.owner[itemName]
    if holder and holder ~= owner then return false, ('%s belongs to %s'):format(itemName, holder) end
    local other = kind == 'weapon' and Config.Ammo or Config.Weapons
    local own = kind == 'weapon' and Config.Weapons or Config.Ammo
    if other[itemName] or Config.Attachments[itemName] then return false, ('%s is already another kind of item'):format(itemName) end
    if own[itemName] and not holder then return false, ('%s is one of spur_gunny\'s own'):format(itemName) end
    return true
end

--- Why a weapon's gunsmith parts cannot be used, or nil: { [category] = { [tier] = component name or hash } }.
local function attachmentsProblem(att)
    if type(att) ~= 'table' then return 'attachments is { [category] = { [tier] = component } }' end
    for category, kinds in pairs(att) do
        if not Config.AttachmentCategories[category] then return ('attachments: %s is not a slot in items/gunsmith.lua'):format(tostring(category)) end
        if type(kinds) ~= 'table' then return ('attachments.%s is { [tier] = component }'):format(category) end
        for tier, component in pairs(kinds) do
            local t = type(component)
            if t ~= 'number' and not (t == 'string' and component:match('^COMPONENT_')) then
                return ('attachments.%s.%s is a COMPONENT_ name or a component hash'):format(category, tostring(tier))
            end
        end
    end
    return nil
end

--- A tier no part item has can never be fitted: said, as it is most likely a typing slip. The weapon still registers.
local function warnUnknownTiers(itemName, att, owner)
    for category, kinds in pairs(att) do
        for tier in pairs(kinds) do
            local known = false
            for _, a in pairs(Config.Attachments) do
                if a.category == category and a.tier == tier then known = true break end
            end
            if not known then
                Whip.startProblem('%s\'s weapon %s: no part in items/gunsmith.lua is a %s %s, so that one never fits',
                    owner, itemName, tostring(tier), category)
            end
        end
    end
end

--- Take a cartridge item off its group's list (and drop a pack's group left with none).
local function offGroup(itemName, group)
    local g = group and Config.AmmoGroups[group]
    if not g then return end
    for i = #g.kinds, 1, -1 do
        if g.kinds[i] == itemName then table.remove(g.kinds, i) end
    end
    if #g.kinds == 0 and ownGroup[group] then
        Config.AmmoGroups[group] = nil
        ownGroup[group] = nil
    end
end

--- A pack's item out of gunny's tables: its pack stopped, or spur_core refused it.
local function forget(itemName)
    local kind = Config.Weapons[itemName] and 'weapon' or 'ammo'
    local a = Config.Ammo[itemName]
    if a then offGroup(itemName, a.group) end
    Config.Weapons[itemName] = nil
    Config.Ammo[itemName] = nil
    Config.WeaponAttachments[itemName] = nil
    GunnyPacks.owner[itemName] = nil
    Config.NoteItemDefaults(itemName)
    changed(itemName, kind, true)
end

local refusals = {}   -- [item] = why spur_core refused it, for the export's answer

--- spur_core refused a pack's item (server/items.lua): most likely its name is another resource's item. Left out of
--- gunny's tables, so nothing draws or loads it, and said. A pack's gun whose group is left with no cartridges goes too.
---@param itemName string
---@param why string|nil
function GunnyPacks.refused(itemName, why)
    local owner = GunnyPacks.owner[itemName]
    if not owner then return end
    refusals[itemName] = tostring(why or 'refused')
    Whip.startProblem('%s\'s item %s left out: spur_core refused it (%s)', owner, itemName, refusals[itemName])
    local group = Config.Ammo[itemName] and Config.Ammo[itemName].group
    forget(itemName)
    if not group or Config.AmmoGroups[group] then return end
    for name, w in pairs(Config.Weapons) do
        if GunnyPacks.owner[name] and w.group == group then
            GunnyPacks.refused(name, ('its cartridges %s were refused'):format(itemName))
        end
    end
end

--- The export's answer once the item has been taken in: spur_core may have refused it meanwhile.
local function answer(itemName)
    local why = refusals[itemName]
    if why then return false, ('%s: spur_core refused it (%s)'):format(itemName, why) end
    return true
end

--- The pack calling, or nil and why.
local function packCaller(what)
    local owner = GetInvokingResource()
    if not owner or owner == GetCurrentResourceName() then
        return nil, what .. ' is for other resources: spur_gunny\'s own items are in items/'
    end
    return owner
end

--- A pack's cartridge (or arrow) item: { label, type = 'AMMO_...', group, weight, description }. `group` is one of
--- items/ammo.lua's (revolver, pistol, repeater, rifle, elephant, varmint, shotgun, arrow) or a new one, made with
--- `groupLabel`. Answers true, or false and why.
exports('RegisterAmmo', function(itemName, def)
    local owner, why = packCaller('RegisterAmmo')
    if not owner then return false, why end
    local ok
    ok, why = claim(itemName, owner, 'ammo')
    if not ok then return false, why end
    if type(def) == 'table' and type(def.group) == 'string' and not Config.AmmoGroups[def.group] then
        if type(def.groupLabel) ~= 'string' then
            return false, ('ammo %s: group %s is not one of items/ammo.lua\'s; name it with groupLabel to make it'):format(itemName, def.group)
        end
        Config.AmmoGroups[def.group] = { label = def.groupLabel, kinds = {} }
        ownGroup[def.group] = owner
    end
    why = Config.AmmoProblem(def)
    if why then return false, ('ammo %s: %s'):format(itemName, why) end
    local before = Config.Ammo[itemName]
    if before and before.group ~= def.group then offGroup(itemName, before.group) end
    def.typeHash = Config.Hash(def.type)
    Config.Ammo[itemName] = def
    local kinds = Config.AmmoGroups[def.group].kinds
    local listed = false
    for _, k in ipairs(kinds) do if k == itemName then listed = true end end
    if not listed then kinds[#kinds + 1] = itemName end
    GunnyPacks.owner[itemName] = owner
    refusals[itemName] = nil
    changed(itemName, 'ammo')
    return answer(itemName)
end)

--- A pack's weapon: one of RDR2's WEAPON_ names, in items/weapons.lua's shape. Its cartridges (its group's) must be
--- registered first. Answers true, or false and why.
exports('RegisterWeapon', function(itemName, def)
    local owner, why = packCaller('RegisterWeapon')
    if not owner then return false, why end
    local ok
    ok, why = claim(itemName, owner, 'weapon')
    if not ok then return false, why end
    why = Config.WeaponProblem(def)
    if why then return false, ('weapon %s: %s'):format(itemName, why) end
    if (def.kind == 'gun' or def.kind == 'bow') and #Config.AmmoGroups[def.group].kinds == 0 then
        return false, ('weapon %s: its group %s has no cartridges'):format(itemName, def.group)
    end
    local attachments = def.attachments
    if attachments ~= nil then
        why = attachmentsProblem(attachments)
        if why then return false, ('weapon %s: %s'):format(itemName, why) end
        warnUnknownTiers(itemName, attachments, owner)
        def.attachments = nil
    end
    Config.Weapons[itemName] = def
    Config.WeaponAttachments[itemName] = attachments
    GunnyPacks.owner[itemName] = owner
    refusals[itemName] = nil
    Config.NoteItemDefaults(itemName)
    changed(itemName, 'weapon')
    return answer(itemName)
end)

-- A pack stopping: its items leave the tables.
AddEventHandler('onResourceStop', function(res)
    local gone = {}
    for itemName, owner in pairs(GunnyPacks.owner) do
        if owner == res then gone[#gone + 1] = itemName end
    end
    -- Weapons first: a cartridge leaving may drop its pack's group.
    table.sort(gone, function(a, b)
        local wa, wb = Config.Weapons[a] ~= nil, Config.Weapons[b] ~= nil
        if wa ~= wb then return wa end
        return a < b
    end)
    for _, itemName in ipairs(gone) do forget(itemName) end
end)

-- Packs register once every file of gunny has loaded, and again each time it starts: lib/pack.lua hears this.
CreateThread(function() TriggerEvent('spur_gunny:packs:ready', {}) end)
