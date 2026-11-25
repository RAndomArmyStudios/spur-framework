// ========================================
// DIRECTOR LOADER — the only Director file in whip's module graph
//
// The Director's screen (html/js/director/*.js) is imported the first time /director opens it, the
// renderer-loader.js way: a fault in any of those files fails the Director alone, never this page
// (plan §11, decision 1: the Director is inside spur_core, and must not be able to take its NUI
// down). This file stays tiny so there is nothing in it to break.
//
// A FAILED IMPORT GIVES THE MOUSE BACK. client/director.lua takes the NUI focus before the page is
// asked to draw anything; a screen that never appears would leave the player stuck behind an
// invisible page, so the loader tells Lua to close at once and says why in the F8 console.
// ========================================

import { NuiRouter } from './router.js';
import { nuiCallback } from './utils.js';

let app = null;
let loading = null;

/** The Director's world-builder side (director/app.js `builder`), or null before the Director has loaded:
 *  the world builder (js/furnisher.js) draws its pages and its grid with it. Always loaded when the builder
 *  was opened from the Director, the only time it asks. */
export function directorBuilder() {
    return app && app.builder ? app.builder : null;
}

function load() {
    if (app) return Promise.resolve(app);
    if (!loading) {
        loading = import('./director/app.js').then((m) => {
            app = m;
            return m;
        }).catch((err) => {
            loading = null;
            throw err;
        });
    }
    return loading;
}

NuiRouter.register('directorOpen', (d) => {
    load().then((m) => m.open(d)).catch((err) => {
        console.error('[spur_core:director] the editor could not load: ' + (err && err.message ? err.message : err));
        nuiCallback('directorClose');
    });
});

for (const action of ['directorClose', 'directorHide', 'directorShow', 'directorPlaceRefused', 'directorTestDone',
    // A live run of the open scenario going on (pulses)
    'directorPulse',
    // Another resource added or took away Director cards (the Director API, slice C4)
    'directorCardsChanged',
    // Done in the world builder: the scenario's things as it left them
    'directorBuilt',
    // A task's point just put down in the world builder, and one moved there (once it stops)
    'directorPointPlaced', 'directorPointMoved',
    // An emote clicked in the emote menu opened for a Play Emote step
    'directorEmotePicked',
    // A route put down in the world builder (it becomes its point 1), and a route's point or a group's spot removed there;
    // any other thing put down there (the scenario has it at once) and taken out again
    'directorRoutePlaced', 'directorPointRemoved', 'directorThingPlaced', 'directorThingRemoved',
    // The world builder's preview: playing, played, stopped (client/director_preview.lua)
    'directorPreviewState',
    // Recording a take: what is on screen meanwhile, and the take once saved (client/director_takes.lua)
    'directorRec', 'directorTakeSaved',
    // Isolate world went on or off on the server's side
    'directorIsolated',
    // Other resources' buttons on placed things: the list moved, and what one of them saved on a thing
    // (client/director_buttons.lua)
    'directorButtonsChanged', 'directorThingData',
    // A freemode NPC's look made in the character editor (client/director.lua directorEditLook)
    'directorLookMade',
    // The test window: on and off with a test, its mouse, the run's steps (client/director.lua, director/testwin.js)
    'directorTestWindow', 'directorTestFlow']) {
    NuiRouter.register(action, (d) => {
        if (app) app.message(d);
    });
}
