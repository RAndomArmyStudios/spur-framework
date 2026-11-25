-- ============================================
-- Item: lockpick — Client Logic
-- The item flag the lockpick prompts read. The
-- prompts themselves are on the car's doors
-- (client/vehicle_prompts.lua) and on doors
-- (client/doors.lua).
-- ============================================
--
-- spur_core's functions, not its exports: an export called from inside spur_core is a full
-- round trip. A satellite writes the same with RegisterItemFlag and the other exports.

local CORE = GetCurrentResourceName()

-- The item flag: "is the player carrying a lockpick", kept fresh by spur_core. Read by the
-- vehicle and door lockpick prompts (client/vehicles.lua, client/doors.lua).
Inventory.registerItemFlagFor(CORE, 'lockpick')

-- The skill check itself is SERVER-RUN now (server/events_vehicles.lua attemptLockpick →
-- Skill.run): the server sends spur_core:client:serverSkillCheck, client/ui.lua plays it and
-- answers with the token. The old lockpickSkillCheck / lockpickResult pair — where this file
-- reported its own success and the server believed it — is gone.

-- (spur_core:client:lockpickUnlockNPC is gone: nothing sent it. A picked lock is applied by the
-- server now, on the vehicle whip tracks.)
