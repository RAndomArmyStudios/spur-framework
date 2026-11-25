-- spur_gunny: THE GUNSMITH (client)
--
-- At the gunsmith's bench (Config.Gunsmith), with a gun drawn: fit a part you carry (a scope, a barrel, rifling) or
-- take one off. The server does the work (server/gunsmith.lua); this offers the choice and shows the drawn gun's parts.
--
-- RedM (spur_gunny, 24 Nov 2026): whip_gunny's weapon bench (client/attachments.lua and its page), renamed the
-- gunsmith. A spur_core action at a fixed place instead of a placed bench, and spur_core's Input in place of the page.
-- A part is RDR2's own weapon component (items/gunsmith.lua: UNTESTED names).

local ACTION_ID = 'gunsmith'
local benchProp = nil

-- ============================================
-- PARTS ON THE DRAWN GUN
-- ============================================

local componentRefusalSaid = {}

-- RedM (spur_gunny, 24 Nov 2026): RedM's Lua gives this native's answer as a number (0 or 1); true/false read too.
local function hasComponent(ped, comp, weaponHash)
    local r = HasPedGotWeaponComponent(ped, comp, weaponHash)
    return r == true or (type(r) == 'number' and r ~= 0)
end

--- Put one RDR2 weapon component on a weapon in the ped's hands. Its model loaded first, when it has one.
local function giveComponent(ped, weaponHash, componentName)
    local comp = Config.Hash(componentName)
    local model = GetWeaponComponentTypeModel(comp)
    if model and model ~= 0 then
        if not GunnyLoadModel(model) then return end
    end
    if not (CurrentWeapon and CurrentWeapon.hash == weaponHash) then return end   -- put away while it loaded
    GiveWeaponComponentToEntity(ped, comp, weaponHash, true)
    if model and model ~= 0 then SetModelAsNoLongerNeeded(model) end
    if not hasComponent(ped, comp, weaponHash) and not componentRefusalSaid[componentName] then
        componentRefusalSaid[componentName] = true
        print(('[GUNNY] WARNING: the game did not put %s on the gun (items/gunsmith.lua)'):format(componentName))
    end
end

--- RedM (spur_gunny, 24 Nov 2026): /gunnypartlab (client/debug.lua), in F8. First every part name of every gun
--- (items/gunsmith.lua) asked of the game: a name it does not know has no model. Then, with a gun drawn, each part that
--- gun takes put on, read back and taken off again; the gun's own parts are put back afterwards. Call from a thread.
---@return string[] lines
function GunsmithLab(ped)
    local lines = {}
    local function say(s) lines[#lines + 1] = s end
    local names, known, unknown = {}, 0, {}
    for gun, slots in pairs(Config.WeaponAttachments or {}) do
        for _, tiers in pairs(slots) do
            for _, name in pairs(tiers) do
                if not names[name] then
                    names[name] = true
                    local model = GetWeaponComponentTypeModel(Config.Hash(name))
                    if model and model ~= 0 and IsModelInCdimage(model) then
                        known = known + 1
                    else
                        unknown[#unknown + 1] = ('%s (%s, model %s)'):format(name, gun, tostring(model))
                    end
                end
            end
        end
    end
    table.sort(unknown)
    say(('part names: %d with a model in the game, %d without (a part may have none, as rifling may: putting it on a drawn gun below is the answer)')
        :format(known, #unknown))
    for _, u in ipairs(unknown) do say('  no model: ' .. u) end

    local w = CurrentWeapon
    if not (w and Config.IsFirearm(w.config)) then
        say('no gun drawn: nothing put on')
        return lines
    end
    say(('%s: HAS_PED_GOT_WEAPON_COMPONENT answers a %s'):format(w.name, type(HasPedGotWeaponComponent(ped, 0, w.hash))))
    for category, tiers in pairs(Config.WeaponAttachments[w.name] or {}) do
        for tier, name in pairs(tiers) do
            if CurrentWeapon ~= w then say('put away: stopped'); return lines end
            local comp = Config.Hash(name)
            local model = GetWeaponComponentTypeModel(comp)
            if model and model ~= 0 then GunnyLoadModel(model) end
            RemoveWeaponComponentFromPed(ped, comp, w.hash)
            Wait(0)
            local before = hasComponent(ped, comp, w.hash)
            GiveWeaponComponentToEntity(ped, comp, w.hash, true)
            local now = hasComponent(ped, comp, w.hash)
            Wait(500)
            local later = hasComponent(ped, comp, w.hash)
            RemoveWeaponComponentFromPed(ped, comp, w.hash)
            Wait(0)
            local off = hasComponent(ped, comp, w.hash)
            say(('  %s (%s %s): %s; before %s, put on %s, 500 ms on %s, taken off %s'):format(name, category, tier,
                (now and later and not off) and 'OK' or 'NO', tostring(before), tostring(now), tostring(later),
                tostring(off)))
            if model and model ~= 0 then SetModelAsNoLongerNeeded(model) end
        end
    end
    if CurrentWeapon == w then
        ApplyWeaponAttachments(ped, w.hash, w.name, w.metadata and w.metadata.attachments)
        say("the gun's own parts put back")
    end
    return lines
end

--- The drawn gun's fitted parts on the ped: { [category] = part item }. Call from a thread (models may load).
---@param ped number
---@param weaponHash integer
---@param weaponName string
---@param attachments table
function ApplyWeaponAttachments(ped, weaponHash, weaponName, attachments)
    for category, attName in pairs(attachments or {}) do
        local att = Config.GetAttachment(attName)
        local component = att and Config.GetWeaponAttachmentComponent(weaponName, category, att.tier)
        if component then giveComponent(ped, weaponHash, component) end
        if not (CurrentWeapon and CurrentWeapon.hash == weaponHash) then return end
    end
end

local function drawnAt(slot, pocket)
    local w = CurrentWeapon
    return w and w.slot == slot and w.pocket == (pocket or 'player') and w or nil
end

RegisterNetEvent('spur_gunny:client:attachmentInstalled', function(slot, pocket, category, attName, componentName)
    local w = drawnAt(slot, pocket)
    if not w then return end
    w.metadata.attachments = w.metadata.attachments or {}
    w.metadata.attachments[category] = attName
    if type(componentName) == 'string' then giveComponent(PlayerPedId(), w.hash, componentName) end
end)

RegisterNetEvent('spur_gunny:client:attachmentRemoved', function(slot, pocket, category, componentName)
    local w = drawnAt(slot, pocket)
    if not w then return end
    if w.metadata.attachments then w.metadata.attachments[category] = nil end
    if type(componentName) == 'string' then
        RemoveWeaponComponentFromPed(PlayerPedId(), Config.Hash(componentName), w.hash)
    end
end)

-- ============================================
-- THE BENCH
-- ============================================

local benchBusy = false

--- The choices at the bench for this gun: fit each part carried that it takes, or take off each one fitted.
local function choicesFor(data)
    local options = {}
    local fitted = data.weapon.attachments or {}
    local takes = {}
    for _, c in ipairs(data.weapon.categories or {}) do takes[c] = true end
    for category, attName in pairs(fitted) do
        local att = Config.GetAttachment(attName)
        options[#options + 1] = { value = 'off:' .. category,
            label = ('Take off the %s'):format(att and att.label or Config.AttachmentCategories[category] or category) }
    end
    for _, att in ipairs(data.attachments or {}) do
        if takes[att.category] and not fitted[att.category]
            and Config.GetWeaponAttachmentComponent(data.weapon.name, att.category, att.tier) then
            options[#options + 1] = { value = ('fit:%d:%s'):format(att.slot, att.pocket or 'player'),
                                      label = ('Fit the %s'):format(att.label or att.name) }
        end
    end
    return options
end

local function openBench()
    if benchBusy then return end
    local gun = CurrentWeapon
    if not (gun and Config.IsFirearm(gun.config)) then
        GunnyNotify('Draw the gun you want worked on first', 'info')
        return
    end
    benchBusy = true
    local ok, data = GunnyCallback('spur_gunny:getWorkbenchData', GunnySlot(gun.slot, gun.pocket))
    if not ok then
        GunnyNotify(type(data) == 'string' and data or 'The gunsmith cannot help with that', 'error')
        benchBusy = false
        return
    end
    local options = choicesFor(data)
    if #options == 0 then
        GunnyNotify('Nothing to fit: carry a part this gun takes', 'info')
        benchBusy = false
        return
    end
    local result = Whip.core:Input(Config.Gunsmith.name or 'Gunsmith', {
        { type = 'select', label = gun.config.label or gun.name, options = options, default = options[1].value },
    })
    local choice = type(result) == 'table' and result[1] or nil
    if type(choice) ~= 'string' or CurrentWeapon ~= gun then benchBusy = false; return end

    local done, why
    local category = choice:match('^off:(.+)$')
    if category then
        done, why = GunnyCallback('spur_gunny:removeAttachment', GunnySlot(gun.slot, gun.pocket), category)
        if done then GunnyNotify('Taken off', 'success') end
    else
        local slot, pocket = choice:match('^fit:(%d+):(.+)$')
        if slot then
            done, why = GunnyCallback('spur_gunny:installAttachment', GunnySlot(gun.slot, gun.pocket),
                GunnySlot(tonumber(slot), pocket))
            if done then GunnyNotify('Fitted', 'success') end
        end
    end
    if done == false then GunnyNotify(type(why) == 'string' and why or 'The gunsmith could not do that', 'error') end
    benchBusy = false
end

--- The gunsmith's own prop, when Config.Gunsmith.model names one: on this player's game only, never networked.
local function placeProp()
    local bench = Config.Gunsmith
    if not bench.model or benchProp then return end
    local model = Config.Hash(bench.model)
    if not GunnyLoadModel(model) then return end
    local p = bench.place
    benchProp = CreateObject(model, p.x, p.y, p.z, false, false, false, false, false)
    SetModelAsNoLongerNeeded(model)
    if not benchProp or benchProp == 0 then benchProp = nil; return end
    SetEntityHeading(benchProp, p.w or 0.0)
    PlaceObjectOnGroundProperly(benchProp, true)
    FreezeEntityPosition(benchProp, true)
end

local function removeProp()
    if benchProp and DoesEntityExist(benchProp) then DeleteObject(benchProp) end
    benchProp = nil
end

Whip.register(function()
    local bench = Config.Gunsmith
    if not bench or bench.enabled == false or not bench.place then return end
    local p = bench.place
    local id, why = exports.spur_core:AddAction({
        id      = ACTION_ID,
        at      = { coords = vector3(p.x, p.y, p.z) },
        label   = bench.name or 'Gunsmith',
        reach   = 2.5,
        onSelect = function() CreateThread(openBench) end,
    })
    if not id then print('[GUNNY] no gunsmith: ' .. tostring(why)) end
    CreateThread(placeProp)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    removeProp()
end)
