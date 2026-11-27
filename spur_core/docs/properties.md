# Properties: houses players can own

SPUR's housing, ported from WHIP by Whippy and WLVF. A **property** is something a player can own: a house, a
cabin, a room over a saloon. It has a space (where "inside" is), doors that lock for its owner, a for-sale sign,
a sign inside for the people who live there, furniture, stashes, and a yard for wagons if you give it one.

RedM (spur_core, 25 Nov 2026): set up and played through in game on a building in Valentine. Buying, the door
locks, the owner's sign, furniture, a stash and a garage bay all work. What differs from WHIP is marked **RedM**.

## What a player does

1. **Buys it.** Walk up to the sign by the front door. It shows the name, the garage bays and the price. Press E on
   the price, E again on "Purchase?", then pick Cash or a bank account.
2. **Locks and unlocks it.** Each door has a padlock at its handle. E locks or unlocks it. Anyone who is not the
   owner or a keyholder is refused.
3. **Uses the sign inside.** Only the owner, keyholders and admins see it. It has Furnish and Keys.
4. **Gives keys.** Keys, on the sign inside, lists the people standing within 5 m. A key opens the doors, the
   stashes and the garage. Only the owner can give or take back keys.
5. **Furnishes it.** Furnish (or `/furnish` inside) opens the furnisher: pick a prop from the catalog, put it down,
   Save. Up to 150 props a property (`Config.PropertyMaxObjects`).
6. **Stores things.** Some furniture is a stash when placed: search the catalog for `Chest 01`, `Armoire regal 01`,
   `Dresser 01` (the `p_dresser01x` one) or `Safe 01`. The list, with slots and weight, is
   `Config.PropertyStashProps`. Up to 6 a property. A stash with something in it cannot be removed.

## Setting one up in game

You need the admin panel (`/spur`, ACE `whip.devtools`). Go to **World > Properties > New property** and stand at
the house.

1. **Interior.** Press **No interior**. **RedM:** RDR2's houses are part of the world and the game has no room or
   portal natives, so the wizard cannot read an interior. The property is measured from where you stand.
2. **Space.** Press **Draw in the world**. Aim at the floor and press E at each corner. R changes the shape:
   a rectangle (two opposite corners), a rectangle along a wall (two corners on the wall, then how deep), or an
   outline (E at each corner, Enter to close it). The wheel sets the height: raise it to take in an upper floor.
   X undoes a corner, Enter finishes, C throws the drawing away. Draw as many shapes as the house needs.
3. **Doors.** Pick the doors near you. **RedM:** a door locks through the game's own hash for it, looked up by
   model and position (`client/rdr_door_hashes.lua`). A door that is not in that list (one added by a map mod)
   registers but does not hold its lock, and F8 says so once.
4. **Signs.** Place the for-sale sign outside by the front door and the manager sign inside. A sign is read from
   the side it faces. **RedM:** the sign is a floating prompt. WHIP's for-sale sign posts are props RDR2 doesn't have, so none
   are listed (`Config.PropertySignPosts`).
5. **Garage.** Optional. Aim at the ground where a wagon should stand and add a bay. Up to 8.
6. **Name & settings.** Name, number, building (a group in the admin list, such as the town), price, most
   furniture, and whether the doors lock themselves.
7. **Review**, then save. You must still be at the property.

Afterwards the same page lists it. From there you can go to it, show its space, move a sign, edit its space, doors
or garage, set or clear its owner, give or take back a key, clear its furniture, or delete it. Deleting releases
its doors: they go back to being ordinary unlocked doors.

Pick buildings nobody needs to walk into. A saloon or a shop turned into a property is locked to everyone else.

## Templates, units and properties

SPUR builds a property from three pieces:

| Piece | What it is | Example |
|---|---|---|
| **Template** | one per interior (MLO archetype), or one for a house with no interior | a boarding house MLO's floor |
| **Unit** | one home inside it, described in the interior's own space | room 3 of the four on that floor |
| **Property** | one unit, at one place in the world | Room 3, Valentine |

Everything inside a unit is measured from the **interior's origin, along its own axes** (for a house with no
interior, from the spot the admin stood on). That is why one template serves every copy of an MLO: describe a
floor's rooms once and every copy of that floor has them. For RDR2's own houses each one is its own template,
because no two are the same building.

There are two ways to get properties onto a server:

- **An admin sets them up in game**, as above.
- **An MLO ships a pack:** one data file, and the homes exist the moment the resource is ensured. The rest of
  this page is about packs. It applies to MLOs made for RedM; the manifest key keeps WHIP's name so a pack
  written in WHIP's format reads the same.

In game, an admin sets up one home with New property; every other copy of that interior is then Register here;
Verify checks them in the world; and **Export pack** on the Templates & packs tab writes the file described
below.

---

## Shipping a pack with your MLO

Add one line to your resource's `fxmanifest.lua`:

```lua
whip_property_pack 'whip_properties.lua'   -- or 'whip_properties.json'
```

Put the file next to it. That is all: no script, no dependency, no load order. SPUR reads the file
when your resource starts, and on a server without SPUR the line does nothing.

A resource can instead pass the same table to `exports.spur_core:RegisterPropertyPack(pack)` from its
own server script. It answers `true, 'applied' | 'unchanged'` or `false, 'where: what is wrong'`.

### The file is data

A `.lua` pack is **plain data**: `return { ... }` of tables, text, numbers, `true` / `false`
and `vec3(x, y, z)`. SPUR reads that without running any of it, on every server.

A pack file that uses code (loops, local variables, `math`) is refused with a message saying so,
and never runs. The Configurator's Export writes plain data for you. To work a pack out with code
(a boarding house with many rooms), build the table in your resource's own server script and hand it to
`exports.spur_core:RegisterPropertyPack(pack)`.

A `.json` pack is the same table as JSON, with positions written as `{ "x": 1, "y": 2, "z": 3 }`.

### If something is wrong

The whole pack is refused, nothing is applied, and the server console says exactly where:

```
[spur_core:packs] REFUSED my_mlo/whip_properties.lua — templates[1].units[2].doors[1].model: a door needs a model (a name or a hash)
```

The same message shows in /spur → World → Properties → Templates & packs.

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

A pack with templates and no properties is useful too. It teaches SPUR your interior, and an admin
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
Admins can move either sign in game (/spur → World → Properties → Move), for one property or for every
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
  - `'interior'` is left alone unless you add `lock = true`. Every managed door is locked when the server
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
and `heading` is the way a parked wagon faces.

When somebody loses access (their key is taken back, or the home changes hands), any wagon of theirs
left in the garage is moved to the nearest public garage, and they are told where it went. Admins
place bays in game: /spur → World → Properties → Garage → Edit.

### Where the numbers come from

Stand inside your interior on a SPUR server and run `/propprobe your_mlo_name`. The report
(`spur_core/dev/probe/`) gives:

- the interior's origin and heading — that is `placement`;
- its rooms and doorways, where the game gives them. **RedM:** RDR2 has no room or portal natives, so the
  report has the origin and hash but 0 rooms and 0 doorways. Write `rooms` yourself or use box shapes.

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

A house with no interior, in the shape an admin's **Export pack** writes (the Valentine test building,
25 Nov 2026):

```lua
return {
    format = 1, id = 'yourname.valentine', version = '1.0.0', label = 'Valentine houses',
    templates = { {
        key = 'hillside', label = 'Hillside House', archetype = 0,
        settings = { price = 250, maxObjects = 150, autolock = false, autolockDelay = 10 },
        units = { {
            key = 'house', label = '1',
            space = { { type = 'box', center = vec3(0.0, 0.0, 2.9), size = vec3(7.9, 8.9, 6.2), heading = 19.1 } },
            doors = {
                { key = 'front', role = 'entrance', model = 'p_door04x', pos = vec3(-2.36, -4.82, 0.04), heading = 110 },
            },
            sign    = { pos = vec3(-3.5, -5.7, 1.4), heading = 110 },
            manager = { pos = vec3(0.0, 0.0, 1.4), heading = 110 },
            garage  = { bays = { { pos = vec3(-9.1, -1.9, -1.3), heading = 200 } } },
        } },
    } },
    properties = { {
        key = 'hillside_1', template = 'hillside', unit = 'house', name = 'Hillside House', building = 'Valentine',
        placement = { pos = vec3(-241.37, 769.86, 117.10), heading = 0 },
    } },
}
```

With `archetype = 0` the placement is the spot everything is measured from, and `heading = 0` keeps the unit's
numbers in world directions.
