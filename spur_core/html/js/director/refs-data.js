// ========================================
// REFS-DATA, where references live — as server/director/fields.lua (kinds) and shared/director/things.lua (named in) says it
// ========================================
// Written by dev/director/export_data.lua: never edit it here. Change the Lua, then run it.

/** What each field kind names: { names, refs, sibling } (fields.lua's header). */
export const FIELD_REFS = {
    "card": {
        "names": "card"
    },
    "rule": {
        "refs": {
            "var": [
                "onlyVar"
            ]
        }
    },
    "target": {
        "sibling": {
            "key": "thing",
            "names": "world",
            "when": "thing"
        }
    },
    "var": {
        "names": "var"
    },
    "world": {
        "names": "world"
    },
    "worlds": {
        "names": "worlds"
    }
};

/** Where a placed thing is named in another's settings: { kind, path } (things.lua NAMED_IN). */
export const NAMED_IN = [
    {
        "kind": "vehicle",
        "path": "tow",
        "says": "its trailer"
    },
    {
        "kind": "vehicle",
        "path": "key.spot",
        "says": "its key's spot"
    },
    {
        "kind": "vehicle",
        "path": "riders[].npc",
        "says": "rides in it"
    },
    {
        "kind": "vehicle",
        "path": "takes[].tow.tracks{}",
        "says": "a trailer its driving event hitched"
    },
    {
        "kind": "vehicle",
        "path": "takes[].tow.events[].w",
        "says": "a trailer its driving event hitched"
    },
    {
        "kind": "groundItem",
        "path": "keyOf",
        "says": "the car it is the key spot of"
    },
    {
        "kind": "spot",
        "path": "marker.thing",
        "says": "sets its marker off"
    },
    {
        "kind": "prop",
        "path": "attach.to",
        "says": "what it is attached to"
    }
];

/** Where it is named in the scenario's Settings. */
export const SETTINGS_NAMED = [
    {
        "path": "start.world",
        "says": "Starts the scenario"
    },
    {
        "path": "where",
        "says": "Where it happens"
    }
];
