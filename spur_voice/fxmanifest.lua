fx_version 'cerulean'
-- RedM (spur_voice, 24 Nov 2026): RedM, not FiveM. A rebuild of whip_voice 1.0.0 for spur_core on RedM's own Mumble
-- voice (README.md, NOTICE.md): no LiveKit, no voice ports or downloads, nothing in a page.
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

name 'spur_voice'
description 'Proximity voice for spur_core on RedM, on its built-in Mumble voice: whisper, talk and shout ranges, the HUD mic, and voice lines (calls) for other resources.'
author 'Whippy and WLVF (whip_voice); RedM port, non-commercial'
version '1.0.0-redm.1'

-- HOW IT WORKS: RedM's own voice (Mumble) carries the audio. Each player sits alone in a voice channel of their own
-- (their server id) and talks into the channels of the players near them, as far as their range (Z: whisper, talk,
-- shout). A line (a call) adds the other members to who they talk to, and plays them at full volume wherever they
-- are. The server alone decides who is on a line.

shared_script '@spur_core/lib/satellite.lua'
shared_script 'config.lua'

client_scripts {
    'client/main.lua',    -- the channel, the range, who hears us, the HUD mic, /voicestatus
}

server_scripts {
    'server/main.lua',       -- the voice system spur_core knows, who is in voice, the convars
    'server/lines.lua',      -- voice lines: players who hear each other wherever they are
    'server/lines_api.lua',  -- OpenLine and the rest, for other resources (whip_voice's contract)
    'server/world.lua',      -- the world voices whip_voice's voice bot gave: none here, said politely
}

dependencies { 'spur_core' }
whip_requires '1.0'
