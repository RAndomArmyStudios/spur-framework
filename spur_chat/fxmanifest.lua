fx_version 'cerulean'
-- RedM (spur_chat, 23 Nov 2026): RedM, not FiveM. A port of whip_chat 1.2.0 for spur_core (README.md, NOTICE.md).
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

name 'spur_chat'
author 'Whippy and WLVF (whip_chat); RedM port, non-commercial'
description 'Chat for spur_core on RedM. Stands in for the stock cfx `chat` resource.'
version '1.2.0-redm.1'

-- It answers stock chat's events and exports, so it stands in for it: a resource with `dependency 'chat'` starts, and
-- `exports.chat:addMessage(...)` reaches spur_chat (shared/stock_exports.lua), with no change to that resource.
provide 'chat'

-- The inbound message event is a spur_core SecureEvent.
dependency 'spur_core'
whip_requires '1.3'   -- the spur_core it is built for: the setup report flags an older one

-- Whip.register re-declares the events after a spur_core restart; Whip.core doesn't error while it's down.
shared_scripts {
    '@spur_core/lib/satellite.lua',
    'shared/stock_exports.lua',   -- stock chat's exports answered as exports.chat too
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    'server/main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    -- Copied from spur_core/html/css/ui.css. Loaded first so chat.css can use the tokens.
    'html/css/tokens.css',
    'html/css/chat.css',
    'html/js/chat.js',
    -- Barlow, the chat's face, its own copy (tokens.css): nothing is fetched from the internet.
    'html/fonts/*.woff2',
}

-- Only this resource's own page may call its NUI callbacks.
nui_callback_strict_mode 'true'
