fx_version 'cerulean'
-- RedM (spur_phone, 24 Nov 2026): RedM, not FiveM. A port of whip_phone 1.1.0 for spur_core, reworked for 1899: the
-- phone is a pocket notebook (README.md, NOTICE.md).
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

name 'spur_phone'
description 'A pocket notebook for spur_core on RedM (F3): telegrams sent from a telegraph office, telephone calls from a telephone, a bank passbook, a business ledger. Every page is a module (html/modules or another resource).'
author 'Whippy and WLVF (whip_phone); RedM port, non-commercial'
version '1.1.0-redm.1'
-- RedM (spur_phone, 24 Nov 2026): no whip_updates line (it would offer WHIP's releases).

shared_scripts {
    '@spur_core/lib/satellite.lua',   -- first: Whip.register / Whip.core
    -- RedM (spur_phone, 24 Nov 2026): spur_core's names for the GTA natives RDR2 lacks (control ids, key mappings),
    -- loaded into this resource as spur_rope loads them. Only spur_core runs their threads and commands.
    '@spur_core/shared/rdr_compat.lua',
    '@spur_core/shared/rdr_compat_stubs.lua',
    'config.lua',
    'shared/places.lua',              -- RedM (spur_phone, 24 Nov 2026): telegraph offices, telephones, bank counters
    'shared/skillgames.lua',          -- the skill check games: which, their levels and timings (both sides)
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua', -- spur_phone keeps its own tables (Josh, 7 Oct 2026)
    -- spur_core's guard on that MySQL (audit 10, INV-8): a database that does not answer becomes an error after a
    -- limit instead of a wait for ever. Right after MySQL.lua, before anything uses it.
    '@spur_core/server/db_guard.lua',
    'server/numbers.lua',     -- telegraph addresses (phone numbers): owners and locks, kept in memory
    'server/schema.lua',      -- the tables, made and brought up to date on start
    'server/sim.lua',         -- which notebook and which address card a player is using
    'server/items.lua',       -- the notebook (with its card pocket) and the telegraph address card
    'server/main.lua',        -- exports: Notify, Push, Open, Close, SetSession, ReloadCache (the admin Phones panel)
    'server/contract.lua',    -- the notebook's data: session, settings, contacts, telegrams, the address card page
    'server/calls.lua',       -- telephone calls and Recents
    'server/blocks.lua',      -- the block list: addresses a card gets no telegrams or calls from
    'server/lore.lua',        -- lore characters' addresses (spur_core's Director) and the Lore cards
    'server/card.lua',        -- a player's own contact card: their name and picture (Settings > My card)
    'server/people.lua',      -- who is on and who is near (picking a person: sharing, hiring)
    'server/bank.lua',        -- the Passbook: spur_core's bank, asked as the player
    'server/business.lua',    -- the Ledger: spur_core's jobs, with the player as `by`
    'server/skillgames.lua',  -- the skill check games, given to spur_core (they need a notebook)
    'server/skilltest.lua',   -- the Skill Check Tester's requests (developers only)
}

ui_page 'html/index.html'
nui_callback_strict_mode 'true'

-- RedM (spur_phone, 24 Nov 2026): no 3D phone, so no three.js and no phone model. The notebook is drawn in CSS
-- (html/core/notebook.js). Nothing for the browser preview is shipped.
files {
    'html/index.html',
    'html/core/*.js',
    -- The built-in pages (Config.Modules): ONE LINE PER APP FOLDER. A `*` in a folder name matches nothing
    -- here: 'html/modules/*/module.js' shipped no app at all. A new app folder needs its own line.
    'html/modules/phone/module.js',        -- Telephone
    'html/modules/messages/module.js',     -- Telegrams
    'html/modules/bank/module.js',         -- Passbook
    'html/modules/business/module.js',     -- Ledger
    'html/modules/settings/module.js',     -- Settings
    'html/modules/skillcheck/module.js',   -- hidden: the skill check games (shared/skillgames.lua)
    'html/modules/skilltest/module.js',    -- a developer app (Config.DeveloperApps): the Skill Check Tester
    'html/img/items/*.webp',  -- the notebook and the address card in the inventory
}

dependency 'spur_core'
whip_requires '1.0'   -- the spur_core it is built for: the setup report flags an older one
dependency 'oxmysql'
