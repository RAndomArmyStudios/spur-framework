// ========================================
// NUI CAPS — the page's half of client/nui_caps.lua
//
// js/caps.js (a classic script in <head>) has already asked the browser what it can do. This
// module, on spur_core's own page only (never a DUI page), hands those answers to Lua once the page
// is up, so Lua and other resources can ask too, and runs /nuicaps gameview: Cfx.re's new game view
// live in a box for a few seconds, the test that it works on this build.
// ========================================

import { NuiRouter } from './router.js';
import { nuiCallback } from './utils.js';

const REPORT_TRIES = 10;
const REPORT_EVERY_MS = 2000;

// Lua registers its callback as spur_core starts, before the page has loaded, so the first try
// lands. A few more are cheap insurance: an unanswered callback answers {} here (utils.js).
async function report(tries) {
    const caps = window.WhipCaps;
    if (!caps) return;
    const answer = await nuiCallback('nuiCaps', caps.refresh());
    if (answer && answer.ok) return;
    if (tries > 1) setTimeout(() => report(tries - 1), REPORT_EVERY_MS);
}
report(REPORT_TRIES);

// ---- /nuicaps gameview ----
//
// Cfx.re's own CfxGameViewRenderer draws the game into a canvas through gl.CFX_BIND_GAME_VIEW. Its
// placeholder texture is solid blue, so a blue box means the binding did not take.
let testBox = null;
let testCanvas = null;
let testRenderer = null;
let testTimer = 0;

function endGameViewTest() {
    clearTimeout(testTimer);
    testTimer = 0;
    if (testRenderer) {
        try { testRenderer.destroy(); } catch (e) { /* already gone */ }
        testRenderer = null;
    }
    // destroy() only stops its drawing: the WebGL context (the same one getContext hands back) is let
    // go now, not whenever the browser collects the canvas. A page holds only so many at once.
    if (testCanvas) {
        try {
            const gl = testCanvas.getContext('webgl2');
            const lose = gl && gl.getExtension('WEBGL_lose_context');
            if (lose) lose.loseContext();
        } catch (e) { /* no context to let go */ }
        testCanvas = null;
    }
    if (testBox) {
        testBox.remove();
        testBox = null;
    }
}

function gameViewTest(data) {
    endGameViewTest();
    const caps = window.WhipCaps;
    if (!caps || !caps.gameView) return;
    const seconds = Math.max(2, Math.min(30, Number(data && data.seconds) || 8));

    testBox = document.createElement('div');
    testBox.id = 'caps-gameview-test';
    testBox.style.cssText = 'position:fixed;top:24px;right:24px;width:480px;padding:10px;'
        + 'background:var(--ui-surface, rgba(10,12,18,0.75));border:1px solid var(--ui-border, rgba(255,255,255,0.08));'
        + 'border-radius:12px;color:var(--ui-text, #fff);font:600 13px/1.4 var(--ui-font, sans-serif);'
        + 'pointer-events:none;z-index:2147483000';
    const label = document.createElement('div');
    label.textContent = 'Game view (Chrome ' + caps.chrome + '): the live game here means it works. Solid blue means it did not bind.';
    label.style.marginBottom = '8px';
    const canvas = document.createElement('canvas');
    canvas.width = 460;
    canvas.height = 259;
    canvas.style.cssText = 'display:block;width:460px;height:259px;border-radius:6px';
    testBox.appendChild(label);
    testBox.appendChild(canvas);
    document.body.appendChild(testBox);
    testCanvas = canvas;

    try {
        testRenderer = new window.CfxGameViewRenderer(canvas);
        testRenderer.resize(canvas.width, canvas.height);
    } catch (e) {
        label.textContent = 'Game view failed to start: ' + (e && e.message ? e.message : e);
    }
    testTimer = setTimeout(endGameViewTest, seconds * 1000);
}

NuiRouter.register('nuiCapsGameView', gameViewTest);
