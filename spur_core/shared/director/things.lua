-- Every kind of placed thing in a scenario's World tab, as data read on both sides.
-- The editor reads html/js/director/things-data.js, generated from this file by dev/director/export_data.lua.
-- Each kind, every part optional:
--   label     a new one's name ("New NPC")        base     a new one's id before its number ("car3")
--   title     the kind's name in the World list   noun     what one is called in a sentence
--   place     only a place: nothing exists there  group    the heading over its own fields on its page
--   needs     { key, what }: a def field it must have besides where it is
--   runOnly   only a run makes it, never standing; notStanding is Check's message for one set to stand
--   tasks     may have a task list                builder  the world builder places it
--   copy      the world builder can copy it       remodel  its model may be changed there
--   spawn     a standing one "exists at all times", by this noun
--   unmarked  the map shows no mark for it

DirectorThings = {}
local T = DirectorThings

T.KINDS = {
    npc = { label = 'New NPC', base = 'npc', title = 'NPC', noun = 'NPC', needs = { key = 'model', what = 'ped model' },
            tasks = true, builder = true, copy = true, remodel = true, spawn = 'NPC' },
    vehicle = { label = 'New car', base = 'car', title = 'Car', noun = 'car', group = 'Car', needs = { key = 'model', what = 'car model' },
                runOnly = true, notStanding = '"%s" is a car: cars are made by a run (Spawn Car), not standing',
                tasks = true, builder = true, copy = true, remodel = true, spawn = 'car' },
    prop = { label = 'New prop', base = 'prop', title = 'Prop', noun = 'prop', group = 'Prop', needs = { key = 'model', what = 'prop model' },
             tasks = true, builder = true, copy = true, remodel = true, spawn = 'prop' },
    spot = { label = 'Spot', base = 'spot', title = 'Spot', noun = 'spot', place = true, builder = true, copy = true },
    groundItem = { label = 'Item spot', base = 'item', title = 'Item spot', noun = 'item', group = 'Item',
                   needs = { key = 'item', what = 'item' }, builder = true, copy = true, spawn = 'item' },
    container = { label = 'Container', base = 'container', title = 'Container', noun = 'container', group = 'Container', runOnly = true,
                  builder = true, copy = true, spawn = 'container' },
    door = { label = 'Door', base = 'door', title = 'Door', noun = 'door', group = 'Door', runOnly = true, builder = true },
    route = { label = 'Route', base = 'route', title = 'Route', noun = 'route', place = true, builder = true, unmarked = true },
}

-- Where a placed thing is named besides card and step fields: in another thing's settings and in the scenario's
-- Settings, with the text a "who names it" list shows (`says`). Walked by refs.lua and refs.js.
-- A path is dotted keys; [] is each of a list, {} each key of a table.
T.NAMED_IN = {
    { kind = 'vehicle', path = 'tow', says = 'its trailer' },
    { kind = 'vehicle', path = 'key.spot', says = 'its key\'s spot' },
    { kind = 'vehicle', path = 'riders[].npc', says = 'rides in it' },
    { kind = 'vehicle', path = 'takes[].tow.tracks{}', says = 'a trailer its driving event hitched' },
    { kind = 'vehicle', path = 'takes[].tow.events[].w', says = 'a trailer its driving event hitched' },
    { kind = 'groundItem', path = 'keyOf', says = 'the car it is the key spot of' },
    { kind = 'spot', path = 'marker.thing', says = 'sets its marker off' },
    { kind = 'prop', path = 'attach.to', says = 'what it is attached to' },
}
T.SETTINGS_NAMED = {
    { path = 'start.world', says = 'Starts the scenario' },
    { path = 'where', says = 'Where it happens' },
}

--- A kind by its name, or nil.
function T.get(kind) return T.KINDS[kind] end

--- A part of a kind's (the header's list): its value, or false for a kind without it (or no such kind).
function T.is(kind, part)
    local d = T.KINDS[kind]
    return d ~= nil and d[part] or false
end

--- The kinds with this part, as a set: { [kind] = true }.
function T.with(part)
    local out = {}
    for k, d in pairs(T.KINDS) do if d[part] then out[k] = true end end
    return out
end
