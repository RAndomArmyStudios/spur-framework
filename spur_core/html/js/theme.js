// ========================================
// THEME LOADER — the skin mechanism's NUI half
//
// A theme is a SEPARATE RESOURCE that ships a theme.css overriding base.css's tokens (and
// nothing else — see docs/nui-theming.md). Config.Theme names it; client/ready.lua sends
// that name here; this file injects <link href="https://cfx-nui-<resource>/theme.css">
// APPENDED LAST in <head>. Cascade order is document order at equal specificity, so a
// token the theme redeclares wins everywhere — that single link IS the entire skin system.
//
// FAILS SOFT, LOUDLY. A theme resource that is stopped, misnamed, or missing its files{}
// line 404s; onerror removes the link and the base look survives — the same philosophy as
// itemImageUrl's fallback chain. The console error names the resource so the fix is obvious.
//
// setTheme is re-runnable (the /whip_theme dev command re-sends it), replacing any previous
// theme link — live skin iteration without a restart.
// ========================================

import { NuiRouter } from './router.js';

const LINK_ID = 'whip-theme';

// A RESOURCE NAME, NOTHING ELSE — the name is concatenated into the stylesheet URL below, and a
// value carrying `.`, `/` or `#` pointed it at a host of the sender's choosing. See renderer-loader.js.
const RESOURCE_NAME = /^[A-Za-z0-9_-]{1,64}$/;

NuiRouter.register('setTheme', (d) => {
    const existing = document.getElementById(LINK_ID);
    if (existing) existing.remove();

    if (!d.resource) return;   // Config.Theme = nil → base look, and a way to clear live
    if (typeof d.resource !== 'string' || !RESOURCE_NAME.test(d.resource)) {
        console.error('[spur_core:theme] refusing theme resource name — not a plain resource name');
        return;
    }

    const link = document.createElement('link');
    link.id = LINK_ID;
    link.rel = 'stylesheet';
    link.href = 'https://cfx-nui-' + d.resource + '/theme.css';
    link.onerror = () => {
        console.error('[spur_core:theme] theme.css could not be loaded from resource "'
            + d.resource + '" — is it started, and is theme.css in its files{}? '
            + 'Falling back to the base look.');
        link.remove();
    };
    document.head.appendChild(link);
});
