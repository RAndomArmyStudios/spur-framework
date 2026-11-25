# Exported property packs

/whip → Properties → Templates & packs → **Export** writes a template here as a pack file, named
after its pack id (for example `export.mega_b1_floor.lua`).

To ship it with the MLO:

1. Copy the file into the MLO's resource and rename it `whip_properties.lua`.
2. Add one line to that resource's `fxmanifest.lua`:

   ```lua
   whip_property_pack 'whip_properties.lua'
   ```

3. Change `id` at the top of the file to your own (`yourname.mlo`), and bump `version` when you
   change it.

Every server that ensures the MLO then gets its homes, with no admin steps. The format is described
in `spur_core/docs/properties.md`. Files here are not loaded by anything: this folder is only where
exports land.
