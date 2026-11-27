fx_version 'cerulean'
-- RedM (spur_rope, 24 Nov 2026): A port of whip_rope 1.0.0 for spur_core (README.md, NOTICE.md).
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

name 'spur_rope'
description 'A physics rope for spur_core on RedM: carry it as an item, tie it to wagons, props and the map where you aim, tow with it, hang off it.'
author 'Whippy and WLVF (whip_rope); RedM port, non-commercial'
version '1.0.0-redm.1'

-- Whip.register re-runs our registrations whenever spur_core starts; Whip.core is safe while it's down;
-- Whip.configPage puts config.lua in /spur.
shared_script '@spur_core/lib/satellite.lua'
-- RedM (spur_rope, 24 Nov 2026): spur_core's names for the original-game natives RDR2 lacks (text, visibility and the rest), loaded
-- into this resource as spur_test loads them. Only spur_core runs their threads and commands.
shared_script '@spur_core/shared/rdr_compat.lua'
shared_script '@spur_core/shared/rdr_compat_stubs.lua'
shared_script 'config.lua'
shared_script 'shared/settings.lua'   -- the pulling and item settings as a page in /spur → Settings

client_scripts {
    '@spur_core/lib/cost.lua', -- WhipCost timers, read by spur_core's /whipcost
    'client/state.lua',        -- the Rope namespace every client file shares
    'client/physics.lua',      -- Verlet nodes, constraints, the ends, the pull on what it is tied to
    'client/collision.lua',    -- the ground, walls, people walking through it, explosions
    'client/contact.lua',      -- ropes against each other
    'client/mesh.lua',         -- RDR2's own rope, pinned along ours (RedM: no rope-piece model)
    'client/visuals.lua',      -- which look; a prop per node; someone hanging off it
    'client/hang_ragdoll.lua', -- someone hanging off it as the game's ragdoll, held by the hand (Config.PlayerHang.Style)
    'client/interaction.lua',  -- making, grabbing, tying, untying and hanging
    'client/sync.lua',         -- server state, and keeping every game's rope alike
    'client/drag.lua',         -- a held end pulled: dragged along behind a car, or out of your hands
    'client/keep.lua',         -- what this game's player pulls, taken and kept (server/keep.lua names it)
    'client/ui.lua',           -- spur_core's prompts and wheel entries, the hint capsule
    'client/main.lua',         -- the loops, the commands, cleaning up
    'client/api.lua',          -- a resource's rope here: its look, its held end, the watch (server/api.lua)
}

server_scripts {
    'server/state.lua',   -- every rope's ends, who holds what, the checks
    'server/keep.lua',    -- who keeps what a rope pulls: the player pulling it (client/keep.lua takes it)
    'server/item.lua',    -- the rope as an inventory item: using it, getting it back
    'server/main.lua',    -- the events, each through spur_core's SecureEvent
    'server/api.lua',     -- ropes for every resource (a pump's hose): CreateRope / SetRopeEnd / RemoveRope / GetRope
    'server/director.lua', -- the Director's rope cards: Make a Rope, Goal: Tie a Rope, Goal: Hang on a Rope...
}

-- The item's picture.
files {
    'html/img/items/*.webp',
}

-- RedM (spur_rope, 24 Nov 2026): no streamed rope piece. whip_rope's (whip_rope_seg, by 3D Clanker) is an original-game model
-- RDR2 can't load, placed with SetEntityMatrix, which RedM lacks; it is kept outside the resource. client/mesh.lua
-- draws RDR2's own rope instead.

dependencies { 'spur_core' }
whip_requires '1.0'   -- the spur_core it is built for: the setup report flags an older one
