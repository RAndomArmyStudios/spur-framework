---@meta
-- ============================================
-- spur_core — the Director API's shapes (LuaLS)
-- ============================================
--
-- What other resources get back from the Director's exports and events (types/server.lua has the
-- exports; types/events.lua the events). Every one is a COPY made when it was asked for: changing it
-- changes nothing in the run.

---@class DirectorRunPlayer
---@field source number
---@field charId number|nil
---@field name string|nil

---@class DirectorRunObjective
---@field source number          whose band
---@field text string            what it says ("Get to the docks")
---@field countdown number|nil   seconds left on its clock

---@class DirectorRunThing   what a run made for one of its placed things (by the thing's id)
---@field kind string|nil        'npc' | 'vehicle' | 'groundItem' | 'container' | 'door' | 'prop' | 'spot'
---@field netId number|nil
---@field npcId number|nil
---@field vehicleId number|nil
---@field containerId number|nil
---@field groundId number|nil
---@field doorId number|nil
---@field npcs number[]|nil      every npcId made for it (reinforcements: a second Spawn NPC)

---@class DirectorWhere
---@field world string           the placed thing's id
---@field label string
---@field coords { x: number, y: number, z: number }

---@class DirectorRunView
---@field id number
---@field tag string             give it to what you make for the run (ShowBlip, AddPoint ...): it goes with the run
---@field scenario string        the scenario's key
---@field name string
---@field rev number             its revision
---@field test boolean           a builder's Test (only when you asked for { tests = true })
---@field kinds string[]         its Kind (Settings): 'heist', 'job' ...
---@field where DirectorWhere|nil  where it happens (Settings), else where its runs start
---@field players DirectorRunPlayer[]
---@field starter number|nil
---@field startedAt number       epoch seconds
---@field seconds number         how long it has been going
---@field endsIn number|nil      seconds to its deadline (nil: none)
---@field vars table<string, string|number|boolean>
---@field objectives DirectorRunObjective[]
---@field things table<string, DirectorRunThing>

---@class DirectorScenarioView
---@field key string
---@field name string
---@field description string|nil
---@field kinds string[]
---@field where DirectorWhere|nil
---@field on boolean             switched on now
---@field rev number|nil         the revision that is on
---@field draftRev number|nil
---@field startMode string       'enabled' | 'interaction' | 'press' | 'area' | 'item' | 'timer' | 'script' | 'admin'
---@field source string          'db' (made here) | 'pack:<resource>' (shipped, read-only) | 'file'
---@field runs number            how many runs of it are going (tests left out)
---@field cards string[]|nil     the card types it uses (GetScenario only)
---@field world { id: string, kind: string, layer: string, label: string|nil, coords: table|nil }[]|nil  (GetScenario only)
---@field vars { id: string, type: string, default: any }[]|nil  (GetScenario only)

---@class DirectorStartOpts   StartScenarioRun's opts
---@field with (number|{ charId: number })[]|nil   more players in it from the start (crew; 16 at most)
---@field vars table<string, string|number|boolean>|nil   its variables, of the types the scenario declares
---@field places table<string, { x: number, y: number, z: number, heading: number|nil }>|nil   where this run's NPCs, car, items, containers and spots are (not a Standing thing, a door or a prop)

---@class DirectorRunStartedEvent
---@field run DirectorRunView
---@field startedBy { mode: string, by: string|nil }

---@class DirectorRunEndedEvent
---@field run DirectorRunView
---@field outcome 'succeeded'|'failed'|'calledOff'|'aborted'|'faulted'
---@field reason string|nil
---@field vars table<string, string|number|boolean>  its variables at the end
---@field payout number
---@field faultCard { id: string, type: string|nil }|nil
---@field stopping boolean       spur_core is stopping

---@class DirectorRunPlayerLeftEvent
---@field run DirectorRunView    without them
---@field source number
---@field charId number|nil
---@field why string             'logout' | 'left' | a script's reason ...
---@field by string|nil          the resource that took them out (RemovePlayerFromScenarioRun)
---@field runEnds boolean        it ends with them (its run:ended follows)

---@class DirectorRunPlayerJoinedEvent
---@field run DirectorRunView    with them
---@field source number
---@field charId number
---@field by string|nil          the resource that put them in (AddPlayerToScenarioRun)

---@class DirectorRunSignalledEvent   a Send Signal card
---@field run DirectorRunView
---@field name string            the signal ('alarm')
---@field data { value: any }    what the card said with it
---@field source number|nil      the player it is about
