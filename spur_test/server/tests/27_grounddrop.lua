-- ============================================
-- CreateGroundItem — both call shapes
--
-- WHY THIS MODULE EXISTS
--
-- This one signature has been called wrongly by TWO independent authors, both passing a
-- vector where the metadata argument goes:
--
--   shops.lua        a purchase that overflowed the buyer's inventory destroyed the item
--                    after payment had been taken
--   spur_gunny       an ejected magazine is destroyed instead of dropped
--
-- Both failed the same way: x/y/z are NOT NULL, so the INSERT threw, a pcall swallowed it,
-- and the caller discarded the return. Nothing anywhere said an item had just ceased to
-- exist.
--
-- When two separate developers make the identical mistake against one signature, the
-- signature is the defect — so both shapes are now accepted. These tests pin that, and pin
-- the refusal path, so a future tidy-up cannot quietly restore silent destruction.
--
-- RedM (spur_test, 23 Nov 2026): spur_core settled it the other way since: CreateGroundItem takes
-- ONE table, { item, amount?, coords, metadata?, heading?, reason? }, and nothing else. So these
-- tests pin that form, its coords as a vector or a plain table, and both refusals: no coords, and
-- the old positional call, which is refused with a reason instead of destroying the item.
-- ============================================

local ITEM = '_test_grounddrop'

--- Ground rows for our fixture item, read straight from the database.
local function droppedRows()
    return DbQuery(
        'SELECT `id`, `x`, `y`, `z`, `metadata` FROM `ground_items` WHERE `item` = ?', { ITEM })
end

--- Remove every fixture row — THROUGH spur_core, so the cache and the grid go with it.
---
--- This used to be a bare SQL DELETE, which emptied the half of a ground item nothing reads. The
--- cache and the spatial grid kept every row, so each one went on rendering at the tester's feet
--- and could still be PICKED UP — GroundItems.delete answers yes for a cached row whether or not
--- the database still has it, so every pickup handed over an item that no longer existed
--- anywhere. The suite was minting fixture items into the world on every run.
---
--- Three passes, because there are three places a row can be:
---   1. rows on disk: deleted through the export (row, cache, grid, clients),
---   2. cache-only ghosts an OLDER run's SQL cleanup left behind near the tester: found through the
---      same cache the pickup reads, and deleted through the export,
---   3. disk rows the cache never knew (the export refuses an id it cannot find): SQL, which is
---      now safe because there is no cache entry to strand.
---@param ctx table|nil  for the tester's position; the ghost sweep is skipped without it
local function clearDropped(ctx)
    for _, row in ipairs(droppedRows()) do
        pcall(exports.spur_core.DeleteGroundItem, exports.spur_core, row.id)
    end
    if ctx and ctx.x then
        local ok, nearby = pcall(exports.spur_core.GetGroundItemsNearby, exports.spur_core,
            ctx.x, ctx.y, ctx.z, 50.0)
        for _, row in ipairs(ok and nearby or {}) do
            if row.item == ITEM then
                pcall(exports.spur_core.DeleteGroundItem, exports.spur_core, row.id)
            end
        end
    end
    pcall(MySQL.query.await, 'DELETE FROM `ground_items` WHERE `item` = ?', { ITEM })
end

RegisterTestModule({
    order    = 27,
    category = 'Ground Drop',

    setup = function(source, ctx)
        exports.spur_core:RegisterItem(ITEM, {
            name = 'Ground Drop Fixture', desc = 'ground drop fixture',
            weight = 0.1, type = 'misc', stack = true, maxStack = 10,
        })

        local ped = GetPlayerPed(source)
        local pos = GetEntityCoords(ped)
        ctx.x, ctx.y, ctx.z = pos.x, pos.y, pos.z

        clearDropped(ctx)
    end,

    teardown = function(ctx, source)
        clearDropped(ctx)
        if source then RemoveAllOf(source, ITEM) end
    end,

    tests = {
        {
            name = 'The one table (item, amount, metadata, coords) creates the row',
            fn = function(source, ctx)
                clearDropped(ctx)
                local data, why = exports.spur_core:CreateGroundItem({
                    item = ITEM, amount = 2, metadata = { tag = 'onetable' },
                    coords = vector3(ctx.x, ctx.y, ctx.z), heading = 0.0,
                })

                -- assertOk, not assertNotNil: a refusal is `false, reason`, and false is not nil.
                assertOk(data, why, 'CreateGroundItem returned a row')
                local rows = droppedRows()
                assertEqual(#rows, 1, 'exactly one ground row exists')
                assertTrue(math.abs(rows[1].x - ctx.x) < 0.5, 'x came from coords')
                assertTrue(rows[1].metadata:find('onetable', 1, true) ~= nil,
                    'metadata was stored, not swallowed as a coordinate')
            end,
        },
        {
            name = 'Coords as a vector: the metadata beside it is kept',
            fn = function(source, ctx)
                -- The shape spur_gunny's ejected magazine needs: its rounds are in the metadata.
                clearDropped(ctx)
                local data, why = exports.spur_core:CreateGroundItem({
                    item = ITEM, amount = 1, coords = vector3(ctx.x, ctx.y, ctx.z),
                    metadata = { tag = 'coords', ammo = 27 },
                })

                assertOk(data, why, 'CreateGroundItem accepted a vector3')
                local rows = droppedRows()
                assertEqual(#rows, 1, 'exactly one ground row exists')
                assertTrue(math.abs(rows[1].x - ctx.x) < 0.5, 'x was taken from the vector')
                assertTrue(math.abs(rows[1].z - ctx.z) < 0.5, 'z was taken from the vector')
                assertTrue(rows[1].metadata:find('27', 1, true) ~= nil,
                    'the metadata beside the vector was stored — a magazine keeps its rounds')
            end,
        },
        {
            name = 'A plain table of coordinates is accepted too',
            fn = function(source, ctx)
                -- Not every caller has a real vector3 to hand; some build {x=,y=,z=}.
                clearDropped(ctx)
                local data, why = exports.spur_core:CreateGroundItem({
                    item = ITEM, amount = 1, coords = { x = ctx.x, y = ctx.y, z = ctx.z },
                    metadata = { tag = 'table' },
                })

                assertOk(data, why, 'a table with x/y/z was read as coordinates')
                local rows = droppedRows()
                assertEqual(#rows, 1, 'row created')
                assertTrue(math.abs(rows[1].x - ctx.x) < 0.5, 'x was taken from the table')
                assertTrue(math.abs(rows[1].z - ctx.z) < 0.5, 'z was taken from the table')
                assertTrue(rows[1].metadata:find('table', 1, true) ~= nil,
                    'the metadata beside the table was stored as metadata')
            end,
        },
        {
            name = 'Metadata carrying x/y/z is still metadata, not coordinates',
            fn = function(source, ctx)
                -- An item whose METADATA records a position — a map marker, a saved waypoint —
                -- must not be mistaken for the position to drop it at.
                clearDropped(ctx)
                local data, why = exports.spur_core:CreateGroundItem({
                    item = ITEM, amount = 1, metadata = { x = 111.0, y = 222.0, z = 333.0, tag = 'marker' },
                    coords = vector3(ctx.x, ctx.y, ctx.z),
                })

                assertOk(data, why, 'created')
                local rows = droppedRows()
                assertEqual(#rows, 1, 'row created')
                assertTrue(math.abs(rows[1].x - ctx.x) < 0.5,
                    'dropped at the REAL coordinates, not at the ones inside the metadata')
                assertTrue(rows[1].metadata:find('marker', 1, true) ~= nil,
                    'the metadata survived intact')
            end,
        },
        {
            name = 'Missing coordinates are REFUSED, not silently swallowed',
            fn = function(source, ctx)
                -- The original bug: no usable coordinates meant a NOT NULL violation inside a
                -- pcall, and the item vanished with no error anyone would see. It must come back
                -- as a clear failure so the caller can keep the item. THE REASON IS THE ASSERTION:
                -- a swallowed INSERT failure is falsy too, and only the reason tells them apart.
                -- (An export's return list is cut at its first nil, so the refusal is
                -- `false, reason`, never `nil, reason`.)
                clearDropped(ctx)
                local data, why = exports.spur_core:CreateGroundItem({ item = ITEM, amount = 1, metadata = { tag = 'nowhere' } })
                assertFalse(data, 'no row was created without coords')
                assertEqual(why, 'CreateGroundItem needs coords', 'refused for the RIGHT reason')

                data, why = exports.spur_core:CreateGroundItem({ item = ITEM, amount = 1, coords = { tag = 'nowhere' } })
                assertFalse(data, 'no row was created for coords with no numbers')
                assertEqual(why, 'Invalid coordinates',
                    'refused for the RIGHT reason, not a swallowed NOT NULL violation')
                assertEqual(#droppedRows(), 0, 'nothing reached the database')
            end,
        },
        {
            name = 'The old positional call is refused with a reason, not destroyed',
            fn = function(source, ctx)
                -- A satellite written for the old signature must hear why, and keep its item.
                clearDropped(ctx)
                local data, why = exports.spur_core:CreateGroundItem(ITEM, 1, { tag = 'old' }, ctx.x, ctx.y, ctx.z, 0.0, nil)
                assertFalse(data, 'no row was created')
                assertTrue(type(why) == 'string' and why:find('one table', 1, true) ~= nil,
                    'the reason says it takes one table')
                assertEqual(#droppedRows(), 0, 'nothing reached the database')
            end,
        },
    },
})
