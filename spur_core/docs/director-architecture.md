# The Director: how it is built

For spur_core's own code. Every concept the Director has is said in **one place**, and the rest of the Director (Check, the runtime, the editor, the hub) reads it from there. A new card, task step, field kind or kind of placed thing is one entry in its registry, never edits spread across files. `dev/director/lint.lua` (run by `golden.lua`) fails when a file names a card type, a step or a kind its registry does not have.

| What | Where | Holds |
|---|---|---|
| Card types | `server/director/nodes.lua` (DirectorNodes) | Every card: its fields, outcomes and how it behaves (`latent`, `giveUp` its Took too long, `talks`, `saysAbove`, `makes`, `condition` with its `watch`, ...). The header lists each part. Shared card helpers (who a card is for, the run's car) are here too |
| Task steps | `shared/director/steps.lua` (DirectorSteps) | Every step and what it is: `moves`, `endsRide`, `faces`, `leftByDrives` (state a car keeps), preview and standing rules. Both sides read it |
| Field kinds | `server/director/fields.lua` (DirectorFields) | Every kind a card or step field can be: how it is checked, read, and which placed things it names (renames follow). The `when` language that hides fields and outcomes (its twin: `html/js/director/when.js`) |
| Placed things | `shared/director/things.lua` (DirectorThings) | Every kind of placed thing (NPC, car, prop, spot, ...): its label, what it needs, what its page has. `dev/director/export_data.lua` writes the editor's copy (`things-data.js`, `refs-data.js`): run it after a change |
| References | `server/director/refs.lua` (DirectorRefs) and `html/js/director/refs.js` | Every place a scenario names a placed thing or a variable, walked one way: renames, "used by", the map's names |
| What a run hands out | `server/director/effects.lua` (DirectorEffects) | Giving items, paying, charging, taking it all back at the run's end, where its items may go. A Test changes nothing that lasts, here, for every card |
| Conversations | `server/director/talk.lua` (DirectorTalk) | The one way a card talks with a player: the capsule, the Talk point, its talk mark, the parting line, No answer |
| A run | `server/director/runtime.lua` (DirectorRuntime) | Cards, waits and the scheduler. A card's `ctx`: `after`, `poll`, `on`, `call`, `hold`, `emit` (an outcome while it waits on), `broken` (a Fail Condition's rule), `own` (what its end gives back), `alive`. How a run ended is decided once (main.lua's end record) |
| Tasks on NPCs and cars | `server/task_seq.lua` (TaskSeq) | One sequencer for both: jobs, their owners, resuming. What lasts on the thing (an NPC's held weapon, a car's lights and siren) is kept on its record, so every game that takes it over sets it again |

A scenario is read one way (`server/director/doc.lua`): its format, renamed cards, and each card's `upgrade(props, fromV)` when its `v` goes up. Nothing else reads an old shape. `dev/director/golden.lua` runs every dev example, the harness modules and the whip_test Director tests offline, and says when anything differs from `golden_baseline.txt`.
