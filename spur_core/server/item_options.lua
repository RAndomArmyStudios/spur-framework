-- ============================================
-- Item options and pictures: what an item offers, and how it looks, as data
-- ============================================
--
-- An item's definition (config.lua, RegisterItem) may carry two lists, and another resource may add
-- options to an item it does not own (AddItemOption, server/inventory.lua):
--
--   contextOptions = {
--       { action  = 'whip_gunny:unload_mag',   -- what RegisterContextAction registered (32 letters at most)
--         label   = 'Unload',                  -- what the menu says
--         order   = 3,                         -- where it sits among the item's options: lowest first
--         when    = { ammo = { above = 0 } },  -- THE ITEM: only while its metadata says so
--         whyNot  = 'The magazine is empty',   -- what a player told no by `when` hears (a double-click)
--         require = { job = 'police', onDuty = true },     -- THE PLAYER: AddAction's words
--         anywhere = true },   -- on the menu where the item is not on you too: a boot, a glovebox, a stash,
--                              -- a bag or wallet, a resource's panel (not the ground). Its handler is handed
--                              -- that store's address. Without it, an option is offered in the pockets only.
--   }
--   images = {   -- the first that fits is the picture; none fits, or its file is missing: the item's own
--       { when = { slots = { empty = false } }, image = 'html/img/items/duffle_bag_full.webp' },
--       { image = 'html/img/items/keys/{make}.webp' },
--       { amount = { atLeast = 1000 }, image = 'html/img/items/cash_2_fan.webp' },   -- how many are in the slot
--   }
--   `amount` tests the slot's count with above / below / atLeast / atMost. Where there is no slot (a shop's list,
--   /whip → Items) there is no count, so no `amount` picture fits there and the item's own is drawn.
--
-- WHEN: one test per metadata field, and all of them must pass.
--   ammo = 0                       equal to this (a number, text, true or false)
--   model = { 'adder', 't20' }     one of these
--   ammo = { above = 0 }           a number above / below / atLeast / atMost (several: all of them)
--   slots = { empty = false }      has something in it. Empty is nothing, false, '', 0, or a table with
--                                  nothing in it.
--   ammo = { below = 12, default = 0 }   `default` beside a test: what the field counts as when the
--                                  item has none (a magazine with no ammo field is empty, so not full)
--
-- REQUIRE: the words AddAction's `require` uses (alive, vehicle, job, onDuty, jobPermission, item, held, zone,
-- charId, ace), checked by the same code: InteractSpec.checkRequire for the words,
-- Requirements.met (server/requirements.lua) for the answer.
--
-- AN IMAGE is a path inside the resource that owns the item, as `image` is. {field} is filled from
-- the item's metadata (lowercased, letters, digits, _ and - only), and {make} is the maker of the car
-- named by its `model` ('pegassi'), which only the game knows: the page asks it (client/inventory.lua).
-- A field it does not have skips that picture.
--
-- `when` is read in two places that must agree: here, on the server, before an option runs (the
-- answer that counts), and on the page, html/js/core/item-rules.js, deciding what to show.
-- dev/item_rules_test.js runs one list of cases through both.

ItemOptions = {}

local OPTION = { action = true, label = true, order = true, when = true, whyNot = true, require = true, icon = true,
                 anywhere = true }
local IMAGE  = { when = true, image = true, amount = true }
local AMOUNT_TESTS = { above = true, below = true, atLeast = true, atMost = true }
local TESTS  = { above = true, below = true, atLeast = true, atMost = true, empty = true, default = true }

local OPTION_HINT = {
    requires = "'require'", condition = "'when' (the item) or 'require' (the player)",
    conditions = "'when' (the item) or 'require' (the player)", canInteract = "'when' or 'require'",
    text = "'label'", name = "'label'", title = "'label'", event = "'action'", id = "'action'",
    priority = "'order'", sort = "'order'", position = "'order'",
}
local IMAGE_HINT = { img = "'image'", path = "'image'", picture = "'image'", icon = "'image'", condition = "'when'" }
local TEST_HINT = {
    gt = "'above'", greater = "'above'", more = "'above'", over = "'above'",
    lt = "'below'", less = "'below'", under = "'below'",
    gte = "'atLeast'", min = "'atLeast'", minimum = "'atLeast'",
    lte = "'atMost'", max = "'atMost'", maximum = "'atMost'",
    equals = 'the value itself (ammo = 0)', eq = 'the value itself (ammo = 0)',
    notEmpty = "'empty = false'", isEmpty = "'empty = true'", oneOf = 'a list ({ \'a\', \'b\' })',
}

local LABEL_MAX  = 40
local ACTION_MAX = 32    -- the wire carries at most 32 letters (customContextAction's 'action' param)
local LIST_MAX   = 50    -- a `{ 'a', 'b' }` test's entries
local IMAGES_MAX = 20
local PATH_MAX   = 200

local function literal(v)
    return type(v) == 'string' or type(v) == 'boolean' or (type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge)
end

local function finite(v) return type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge end

local function unknownField(where, k, fields, hints)
    local meant = InteractSpec.didYouMean(k, fields, hints)
    if meant then return ('%s.%s is not a field: use %s'):format(where, tostring(k), meant) end
    return ('%s.%s is not a field'):format(where, tostring(k))
end

--- Is this a `when` table whip can read? nil when it is, or why not.
---@param when any
---@param where string  how the message names it: 'item "x" option "unload" when'
---@return string|nil why
function ItemOptions.checkWhen(when, where)
    if when == nil then return nil end
    if type(when) ~= 'table' then return where .. ' must be a table of metadata fields' end
    if next(when) == nil then return where .. ' has no tests in it' end
    for field, test in pairs(when) do
        if type(field) ~= 'string' or not field:match('^[%w_]+$') or #field > 50 then
            return ('%s: %s is not a metadata field name (letters, digits and _)'):format(where, tostring(field))
        end
        local at = where .. '.' .. field
        if type(test) == 'table' then
            if test[1] ~= nil then
                if #test > LIST_MAX then return ('%s: a list of at most %d'):format(at, LIST_MAX) end
                for k, v in pairs(test) do
                    if type(k) ~= 'number' then return at .. ' is a list or a table of tests, not both' end
                    if not literal(v) then return at .. ' lists text, numbers, true or false' end
                end
            else
                if next(test) == nil then return at .. ' is an empty table' end
                for k, v in pairs(test) do
                    if not TESTS[k] then
                        local meant = InteractSpec.didYouMean(k, TESTS, TEST_HINT)
                        return ('%s.%s is not a test (above, below, atLeast, atMost, empty, default)%s')
                            :format(at, tostring(k), meant and (': use ' .. meant) or '')
                    end
                    if k == 'empty' then
                        if type(v) ~= 'boolean' then return at .. '.empty is true or false' end
                    elseif k == 'default' then
                        if not literal(v) then return at .. '.default is a value: a number, text, true or false' end
                    elseif not finite(v) then
                        return ('%s.%s is a number'):format(at, k)
                    end
                end
                if test.default ~= nil then
                    local alone = true
                    for k in pairs(test) do if k ~= 'default' then alone = false break end end
                    if alone then return at .. '.default goes beside a test (below = 12, default = 0)' end
                end
            end
        elseif not literal(test) then
            return at .. ' is a value, a list, or a table of tests'
        end
    end
    return nil
end

--- Nothing, false, '', 0, or a table with nothing in it.
local function isEmpty(v)
    if v == nil or v == false or v == '' or v == 0 then return true end
    if type(v) == 'table' then return next(v) == nil end
    return false
end

--- One field's test against its value. Only a number is a number: '5' is text.
local function passes(test, v)
    if type(test) ~= 'table' then return v == test end
    if test[1] ~= nil then
        for _, x in ipairs(test) do
            if v == x then return true end
        end
        return false
    end
    if v == nil and test.default ~= nil then v = test.default end
    if test.empty ~= nil and isEmpty(v) ~= test.empty then return false end
    local n = finite(v) and v or nil
    if test.above ~= nil and not (n and n > test.above) then return false end
    if test.below ~= nil and not (n and n < test.below) then return false end
    if test.atLeast ~= nil and not (n and n >= test.atLeast) then return false end
    if test.atMost ~= nil and not (n and n <= test.atMost) then return false end
    return true
end

--- Does an item's metadata pass a `when`? No `when` passes.
---@param when table|nil  checked with checkWhen
---@param meta table|nil  the item's metadata
---@return boolean
function ItemOptions.whenMet(when, meta)
    if when == nil then return true end
    if type(meta) ~= 'table' then meta = {} end
    for field, test in pairs(when) do
        if not passes(test, meta[field]) then return false end
    end
    return true
end

--- One option, checked and copied: { action, label, order?, when?, require? }. `icon` is accepted
--- and dropped (the menu draws words only).
---@param opt any
---@param where string
---@return table|nil option
---@return string|nil why
function ItemOptions.cleanOption(opt, where)
    if type(opt) ~= 'table' then return nil, where .. ' must be a table: { action = ..., label = ... }' end
    for k in pairs(opt) do
        if not OPTION[k] then return nil, unknownField(where, k, OPTION, OPTION_HINT) end
    end
    if type(opt.action) ~= 'string' or opt.action == '' then
        return nil, where .. ' needs an action (the name RegisterContextAction registered)'
    end
    if #opt.action > ACTION_MAX then
        return nil, ('%s: action "%s" is longer than %d letters'):format(where, opt.action, ACTION_MAX)
    end
    if type(opt.label) ~= 'string' or opt.label == '' then return nil, where .. ' needs a label (what the menu says)' end
    if #opt.label > LABEL_MAX then return nil, ('%s: a label is %d letters at most'):format(where, LABEL_MAX) end
    if opt.order ~= nil and not finite(opt.order) then return nil, where .. '.order is a number' end
    if opt.whyNot ~= nil and (type(opt.whyNot) ~= 'string' or opt.whyNot == '' or #opt.whyNot > 80) then
        return nil, where .. '.whyNot is what the player is told, 80 letters at most'
    end
    if opt.anywhere ~= nil and type(opt.anywhere) ~= 'boolean' then
        return nil, where .. '.anywhere is true or false'
    end
    local why = ItemOptions.checkWhen(opt.when, where .. '.when')
        or InteractSpec.checkRequire(opt.require, where .. '.require')
    if why then return nil, why end
    -- Read as the server will read it before the option runs (Requirements): a word it could not read would be no
    -- requirement there while the menu still hid the option, and a zone only this game knows the server never sees.
    -- (config.lua's items are read before requirements.lua and the saved zones load: those two checks wait for a
    -- resource's RegisterItem / AddItemOption, and the server refuses at the click either way.)
    if type(opt.require) == 'table' and Requirements then
        local clean = Requirements.clean(opt.require)
        local lost = Requirements.lost(opt.require, clean)
        if lost then return nil, ('%s.require.%s could not be read (see AddAction\'s require)'):format(where, lost) end
        if clean and clean.zone and Zones and Zones.loaded then
            for _, z in ipairs(clean.zone) do
                if not Zones.isSaved(z) then
                    return nil, ('%s.require: zone "%s" is not a saved zone: an item option can only require one of those'):format(where, z)
                end
            end
        end
    end
    return { action = opt.action, label = opt.label, order = opt.order, when = opt.when, whyNot = opt.whyNot,
             require = opt.require, anywhere = opt.anywhere == true or nil }
end

--- An item's contextOptions, checked and copied. nil for none; a list with two options of the same
--- action is refused (the menu could not tell them apart).
---@param list any
---@param where string  'item "x" contextOptions'
---@return table|nil options
---@return string|nil why
function ItemOptions.cleanOptions(list, where)
    if list == nil then return nil end
    if type(list) ~= 'table' then return nil, where .. ' must be a list of options' end
    local out, seen = {}, {}
    for i, opt in ipairs(list) do
        local at = ('%s[%d]'):format(where, i)
        local clean, why = ItemOptions.cleanOption(opt, at)
        if not clean then return nil, why end
        if seen[clean.action] then return nil, ('%s: two options are "%s"'):format(where, clean.action) end
        seen[clean.action] = true
        out[#out + 1] = clean
    end
    if #out == 0 then return nil end
    return out
end

--- GROUND OPTIONS (Josh, 1 Nov): what the 3D prompt on a pile of this item offers after Pick up. Each names one of the
--- item's own options (a contextOptions action, or its defaultAction): choosing it picks the item up exactly as Pick
--- up does and, only once it is in the pockets, runs that option on the slot it landed in, as the inventory would.
---
---   groundOptions = { { action = 'whip_gunny:equip_weapon', label = 'Equip', icon = 'target' } }
---
--- label: what the prompt says (the item's name follows it: "Equip Pump Shotgun"); icon: a glyph's name
--- (html/js/glyphs.js), Pick up's arrow when none. At most 3.
local GROUND = { action = true, label = true, icon = true }
local GROUND_MAX = 3

--- An item's groundOptions, checked and copied. nil for none.
---@param list any
---@param where string  'item "x" groundOptions'
---@return table|nil options
---@return string|nil why
function ItemOptions.cleanGroundOptions(list, where)
    if list == nil then return nil end
    if type(list) ~= 'table' then return nil, where .. ' must be a list of options' end
    local out, seen = {}, {}
    for i, o in ipairs(list) do
        local at = ('%s[%d]'):format(where, i)
        if type(o) ~= 'table' then return nil, at .. ' must be a table: { action, label, icon? }' end
        for k in pairs(o) do
            if not GROUND[k] then return nil, ('%s: "%s" is not a field (action, label, icon)'):format(at, tostring(k)) end
        end
        if type(o.action) ~= 'string' or o.action == '' or #o.action > 32 then
            return nil, at .. ".action names one of the item's own options (32 letters at most)"
        end
        if type(o.label) ~= 'string' or o.label == '' or #o.label > 24 then
            return nil, at .. '.label is what the prompt says (24 letters at most)'
        end
        if o.icon ~= nil and (type(o.icon) ~= 'string' or #o.icon > 32 or not o.icon:match('^[%w_]+$')) then
            return nil, at .. ".icon is a glyph's name (html/js/glyphs.js)"
        end
        if seen[o.action] then return nil, ('%s: two are "%s"'):format(where, o.action) end
        seen[o.action] = true
        out[#out + 1] = { action = o.action, label = o.label, icon = o.icon }
    end
    if #out > GROUND_MAX then return nil, ('%s: %d at most'):format(where, GROUND_MAX) end
    if #out == 0 then return nil end
    return out
end

--- An image path: inside a resource, a picture file, and {field} parts that name a metadata field.
local function checkPath(path, where)
    if type(path) ~= 'string' or path == '' then return where .. '.image is a path (html/img/items/x.webp)' end
    if #path > PATH_MAX then return ('%s.image is %d letters at most'):format(where, PATH_MAX) end
    if path:find('..', 1, true) or path:sub(1, 1) == '/' or path:find(':', 1, true) or path:find('\\', 1, true) then
        return where .. ".image is a path inside the item's resource (no '..', no leading /, no drive or https:)"
    end
    if not path:match('^[%w_%-%./{}]+$') then
        return where .. '.image is letters, digits, _ - . / and {field} parts only'
    end
    local bare = path:gsub('{[%w_]+}', '')
    if bare:find('[{}]') then return where .. '.image: a {part} names a metadata field, letters, digits and _' end
    local ext = path:match('%.(%w+)$')
    ext = ext and ext:lower()
    if ext ~= 'png' and ext ~= 'webp' and ext ~= 'jpg' and ext ~= 'jpeg' then
        return where .. '.image ends .png, .webp or .jpg'
    end
    return nil
end

--- An item's images, checked and copied. nil for none.
---@param list any
---@param where string  'item "x" images'
---@return table|nil images
---@return string|nil why
function ItemOptions.cleanImages(list, where)
    if list == nil then return nil end
    if type(list) ~= 'table' then return nil, where .. ' must be a list: { { when = ..., image = ... } }' end
    if #list > IMAGES_MAX then return nil, ('%s: %d pictures at most'):format(where, IMAGES_MAX) end
    local out = {}
    for i, v in ipairs(list) do
        local at = ('%s[%d]'):format(where, i)
        if type(v) ~= 'table' then return nil, at .. ' must be a table: { when = ..., image = ... }' end
        for k in pairs(v) do
            if not IMAGE[k] then return nil, unknownField(at, k, IMAGE, IMAGE_HINT) end
        end
        local why = checkPath(v.image, at) or ItemOptions.checkWhen(v.when, at .. '.when')
        if why then return nil, why end
        -- The slot's count: number tests only (an amount is always a whole number of the item).
        if v.amount ~= nil then
            if type(v.amount) ~= 'table' or next(v.amount) == nil then
                return nil, at .. '.amount is a table of tests: { atLeast = 100, below = 1000 }'
            end
            for k, n in pairs(v.amount) do
                if not AMOUNT_TESTS[k] then
                    local meant = InteractSpec.didYouMean(k, AMOUNT_TESTS, TEST_HINT)
                    return nil, ('%s.amount.%s is not a test (above, below, atLeast, atMost)%s')
                        :format(at, tostring(k), meant and (': use ' .. meant) or '')
                end
                if not finite(n) then return nil, ('%s.amount.%s is a number'):format(at, k) end
            end
        end
        out[#out + 1] = { when = v.when, image = v.image, amount = v.amount }
    end
    if #out == 0 then return nil end
    return out
end
