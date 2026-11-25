# Properties — making an MLO a home in whip

A **property** is something a player can own: a house, a flat, a studio. whip builds one from three
pieces:

| Piece | What it is | Example |
|---|---|---|
| **Template** | one per interior (MLO archetype) | `mega_b1_floor`, one half-floor of Mega Tower B |
| **Unit** | one home inside that interior, described in the interior's own space | flat 5 of the four on that half-floor |
| **Property** | one unit, at one place the interior stands in the world | B805 |

Everything inside a unit is measured from the **interior's origin, along its own axes**. That is why
one template serves every copy of an interior: describe a tower floor's four flats once, and all 36
floors have them.

There are two ways to get properties onto a server:

- **An admin sets them up in game:** /whip → Properties (the Configurator).
- **The MLO ships a pack:** one data file, and the homes exist the moment the resource is ensured. This
  page is about packs.

(Written 24 Sep 2026. In game, an admin sets up one home with New property; every other copy of that
interior is then Register here, or Stamp mode for a whole tower; Verify checks them in the world;
and **Export pack** on the Templates & packs tab writes the file this page describes.)

---

## Shipping a pack with your MLO

Add one line to your resource's `fxmanifest.lua`:

```lua
whip_property_pack 'whip_properties.lua'   -- or 'whip_properties.json'
```

Put the file next to it. That is all: no script, no dependency, no load order. whip reads the file
when your resource starts, and on a server without whip the line does nothing.

A resource can instead pass the same table to `exports.spur_core:RegisterPropertyPack(pack)` from its
own server script. It answers `true, 'applied' | 'unchanged'` or `false, 'where: what is wrong'`.

### The file is data

A `.lua` pack is **plain data**: `return { ... }` of tables, text, numbers, `true` / `false`
and `vec3(x, y, z)`. whip reads that without running any of it, on every server.

A pack file that uses code (loops, local variables, `math`) is refused with a message saying so,
and never runs. The Configurator's Export writes plain data for you. To work a pack out with code
(a tower with 36 floors), build the table in your resource's own server script and hand it to
`exports.spur_core:RegisterPropertyPack(pack)`.

A `.json` pack is the same table as JSON, with positions written as `{ "x": 1, "y": 2, "z": 3 }`.

### If something is wrong

The whole pack is refused, nothing is applied, and the server console says exactly where:

```
[spur_core:packs] REFUSED my_mlo/whip_properties.lua — templates[1].units[2].doors[1].model: a door needs a model (a name or a hash)
```

The same message shows in /whip → Properties → Templates & packs.

---

## The format

```lua
return {
    format  = 1,                   -- always 1 for now
    id      = 'yourname.mlo',      -- unique: lower case, numbers, . _ -   (3-48 characters)
    version = '1.0.0',             -- your version; shown to admins
    label   = 'Your MLO',

    templates = {                  -- one per interior archetype
        {
            key       = 'house',           -- your name for it, unique in this pack
            label     = 'Two-bedroom house',
            archetype = 'your_mlo_name',   -- the archetype name (or its hash); 0 = no interior
            rooms     = { ... },           -- optional: the interior's rooms (see below)
            settings  = { price = 0, maxObjects = 150, autolock = false, autolockDelay = 10 },  -- optional defaults

            units = {
                {
                    key   = 'flat_1',
                    label = 'Flat 1',
                    space = { ... },       -- where the home is (required)
                    doors = { ... },       -- its doors
                    sign    = { pos = vec3(...), heading = 0 },   -- OUTSIDE, by the front door: shown while it is for sale
                    manager = { pos = vec3(...), heading = 0 },   -- INSIDE: shown to the owner and keyholders once it is owned
                    visit = vec3(...),     -- somewhere to stand inside it (optional)
                    garage = { bays = { { pos = vec3(...), heading = 0 } } },  -- optional: a private garage
                },
            },
        },
    },

    properties = {                 -- optional: where the interior stands, if you know
        {
            key       = 'flat_1',          -- unique in this pack
            template  = 'house',
            unit      = 'flat_1',
            name      = 'Flat 1',          -- what players see
            label     = '1',               -- optional: the unit number
            building  = 'Your Building',   -- optional: groups them in the admin panel
            placement = { pos = vec3(x, y, z), heading = h },  -- the interior's origin and turn in the world
        },
    },
}
```

A pack with templates and no properties is useful too. It teaches whip your interior, and an admin
standing in any copy of it presses **Register here** to make the homes.

### Space

The home's floor area and height, as a list of shapes. Use one of these:

| Shape | Written as | Use when |
|---|---|---|
| The whole interior | `{ type = 'interior' }` | the interior is exactly one home and its rooms fit its walls |
| Some rooms | `{ type = 'rooms', rooms = { 'living', 'bed1' } }` | a home is some of the interior's rooms |
| A box | `{ type = 'box', center = vec3(...), size = vec3(w, d, h), heading = 0 }` | anything else — the usual choice |
| A polygon | `{ type = 'poly', points = { {x=..,y=..}, ... }, minZ = 0, maxZ = 3 }` | an L-shaped or angled flat |

`'interior'` and `'rooms'` need the interior's rooms, either in `rooms = { ... }` on the template:

```lua
rooms = { { name = 'living', min = vec3(-8.7, -2.1, 0.4), max = vec3(-0.6, 4.6, 3.1) }, ... },
```

or found later by an admin's Verify.

Room boxes are only as good as the MLO. They run along the interior's own axes, so a flat built at an
angle inside its interior gets a loose box. For those, draw boxes that fit. Everything in a unit must
be within 250 m of the interior's origin.

### The two signs

A home has two signs, and players see one at a time:

- **`sign`, outside by the front door.** It shows while nobody owns the home: its name, that it is
  for sale, and its price.
- **`manager`, inside.** It shows once the home is owned, and only to its owner, its keyholders and
  admins. It is where they give keys and furnish, and it will carry more as homes gain features.

A `heading` faces the reader: a sign is read by someone looking at it from its heading's direction.
Admins can move either sign in game (/whip → Properties → Move), for one property or for every
property on the unit. Their spot is kept over the pack's. A home with no `manager` uses its `sign`
spot for the manager once it is owned.

### Doors

```lua
doors = {
    { key = 'front', role = 'entrance', model = 'your_door', pos = vec3(...), heading = 90 },
    { key = 'left',  role = 'entrance', model = 'your_door', pos = vec3(...), heading = 90, pair = 'right' },
    { key = 'right', role = 'entrance', model = 'your_door', pos = vec3(...), heading = 270, pair = 'left' },
    { key = 'bed',   role = 'interior', model = 'your_bedroom_door', pos = vec3(...) },
}
```

- **`pos`** is the door object's own position (its hinge), and **`model`** its model name or hash.
- **`role`:**
  - `'entrance'` locks for the owner and their keyholders.
  - `'garage'` locks the same way.
  - `'interior'` is left alone unless you add `lock = true`. Every whip door is locked when the server
    starts, and a bedroom door that did that would annoy everyone.
- **`pair`** links the two leaves of a double door, so they lock together.

### Garage

```lua
garage = { bays = {
    { pos = vec3(2.0, -9.5, 0.0), heading = 90 },
    { pos = vec3(5.0, -9.5, 0.0), heading = 90 },
} },
```

A home with bays gets a **private garage** of its own. Only its owner and keyholders can use its bays,
and it has no map blip. Up to 8 bays. Each bay is a parking space on the ground: `pos` is its middle,
and `heading` is the way a parked car faces.

When somebody loses access (their key is taken back, or the home changes hands), any car of theirs
left in the garage is moved to the nearest public garage, and they are told where it went. Admins
place bays in game: /whip → Properties → Garage → Edit.

### Where the numbers come from

Stand inside your interior on a whip server and run `/propprobe your_mlo_name`. The report
(`spur_core/dev/probe/`) gives:

- the interior's origin and heading — that is `placement`;
- its rooms, with their local boxes;
- every door attached to a doorway, with its local position.

An object's local heading is its world heading minus the placement's heading.

Better still, set the interior up once with the Configurator and press **Export pack**. You get this
file, filled in.

---

## What happens when you update your pack

A server applies your pack at every start. What it may change and what it never touches:

| | |
|---|---|
| **Your pack changes** | the templates, the units, and each property's template, unit and placement |
| **Only if an admin has not changed it since** | a property's name, label and building |
| **Never** | a property's owner, its keys, its furniture, an admin's settings or their own edits to a unit |

- **Unchanged pack:** a pack identical to the last one applied writes nothing.
- **A property you remove from the pack** stays, flagged for the admin to keep or delete. It is not
  deleted from under its owner.
- **A property the admin deleted** is never made again by your pack.
- **A part both of you changed** (you changed the space in an update, the admin had also changed it)
  keeps the admin's, and the admin is asked to choose.
- **An admin's existing home at the same spot** is taken over by your property, with its owner, keys
  and furniture.
- **When your resource stops,** its properties stay, owned, but show as closed.
- **Your pack id is yours.** Another resource sending the same id while yours runs is refused.

---

## A worked example

`whippy_test_bungalow/whip_properties.lua` is a complete pack for a one-home MLO: a template with its
rooms, one unit with the whole interior as its space, two entrance doors, four interior doors left
alone, an entry sign, and the one place the bungalow stands.
