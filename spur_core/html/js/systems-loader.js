// ========================================
// SYSTEMS LOADER — the only Systems Creator file in whip's module graph
//
// director-loader.js's twin. The Systems Creator's screen (html/js/systems/*.js) is imported the
// first time /systems opens it: a fault in any of those files fails the Systems Creator alone, never
// this page. Tiny, so there is nothing in it to break.
//
// A FAILED IMPORT GIVES THE MOUSE BACK. client/systems_editor.lua takes the NUI focus before the page
// is asked to draw anything; a screen that never appears would leave the player stuck behind an
// invisible page, so the loader tells Lua to close at once and says why in the F8 console.
// ========================================

import { NuiRouter } from './router.js';
import { nuiCallback } from './utils.js';

let app = null;
let loading = null;

function load() {
    if (app) return Promise.resolve(app);
    if (!loading) {
        loading = import('./systems/app.js').then((m) => {
            app = m;
            return m;
        }).catch((err) => {
            loading = null;
            throw err;
        });
    }
    return loading;
}

NuiRouter.register('systemsOpen', (d) => {
    load().then((m) => m.open(d)).catch((err) => {
        console.error('[spur_core:systems] the editor could not load: ' + (err && err.message ? err.message : err));
        nuiCallback('systemsClose');
    });
});

for (const action of ['systemsClose', 'systemsHide', 'systemsShow', 'systemsPlaced',
    // A test going (its steps, its end, a restart) and a live system's pulses
    'systemsTestSteps', 'systemsTestEnded', 'systemsTestRestarted', 'systemsPulse']) {
    NuiRouter.register(action, (d) => {
        if (app) app.message(d);
    });
}
