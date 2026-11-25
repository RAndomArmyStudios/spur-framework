// ========================================
// THINGS-DATA, the kinds of placed thing — as shared/director/things.lua says it
// ========================================
// Written by dev/director/export_data.lua: never edit it here. Change the Lua, then run it.

export const THINGS = {
    "container": {
        "base": "container",
        "builder": true,
        "copy": true,
        "group": "Container",
        "label": "Container",
        "noun": "container",
        "runOnly": true,
        "spawn": "container",
        "title": "Container"
    },
    "door": {
        "base": "door",
        "builder": true,
        "group": "Door",
        "label": "Door",
        "noun": "door",
        "runOnly": true,
        "title": "Door"
    },
    "groundItem": {
        "base": "item",
        "builder": true,
        "copy": true,
        "group": "Item",
        "label": "Item spot",
        "needs": {
            "key": "item",
            "what": "item"
        },
        "noun": "item",
        "spawn": "item",
        "title": "Item spot"
    },
    "npc": {
        "base": "npc",
        "builder": true,
        "copy": true,
        "label": "New NPC",
        "needs": {
            "key": "model",
            "what": "ped model"
        },
        "noun": "NPC",
        "remodel": true,
        "spawn": "NPC",
        "tasks": true,
        "title": "NPC"
    },
    "prop": {
        "base": "prop",
        "builder": true,
        "copy": true,
        "group": "Prop",
        "label": "New prop",
        "needs": {
            "key": "model",
            "what": "prop model"
        },
        "noun": "prop",
        "remodel": true,
        "spawn": "prop",
        "tasks": true,
        "title": "Prop"
    },
    "route": {
        "base": "route",
        "builder": true,
        "label": "Route",
        "noun": "route",
        "place": true,
        "title": "Route",
        "unmarked": true
    },
    "spot": {
        "base": "spot",
        "builder": true,
        "copy": true,
        "label": "Spot",
        "noun": "spot",
        "place": true,
        "title": "Spot"
    },
    "vehicle": {
        "base": "car",
        "builder": true,
        "copy": true,
        "group": "Car",
        "label": "New car",
        "needs": {
            "key": "model",
            "what": "car model"
        },
        "notStanding": "\"%s\" is a car: cars are made by a run (Spawn Car), not standing",
        "noun": "car",
        "remodel": true,
        "runOnly": true,
        "spawn": "car",
        "tasks": true,
        "title": "Car"
    }
};

/** A part of a kind's (things.lua's list): its value, or false. */
export const thingIs = (kind, part) => !!THINGS[kind] && (THINGS[kind][part] || false);
