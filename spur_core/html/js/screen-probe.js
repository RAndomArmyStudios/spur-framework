// ========================================
// SCREEN PROBE — what spur_core's page shows, and pressing it by its words
//
// For tests and tools (whip_devlink's AI link, whip_test): client/screen_probe.lua's ReadScreen and PressScreen send
// `screenProbe` here and wait for the answer on the screenProbe callback. Lua lets it through only in developer mode.
// The reading and pressing are js/page-tools.js's (window.WhipProbe), a plain script index.html loads before this,
// so other resources' pages (the phone, Whiplash, the dealership) can load the same and be read the same way.
// ========================================

import { NuiRouter } from './router.js';
import { nuiCallback } from './utils.js';

NuiRouter.register('screenProbe', async (d) => {
    const answer = (ok, result, err) => nuiCallback('screenProbe', { token: d.token, ok, result, err });
    try {
        const probe = window.WhipProbe;
        if (!probe) throw new Error('js/page-tools.js did not load');
        const opts = d.opts || {};
        if (d.kind === 'read') answer(true, probe.read(opts));
        else if (d.kind === 'press') answer(true, await probe.press(opts));
        else answer(false, null, 'no such probe: ' + d.kind);
    } catch (e) {
        answer(false, null, String(e && e.message || e));
    }
});
