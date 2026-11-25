// ============================================
// LABEL WIDTHS — how wide a 3D prompt's words are, for client/interact_world.lua
// ============================================
//
// The world prompts' words are painted by another browser (html/interact3d/label.html, a DUI), and a
// DUI is one-way: nothing it measures can come back. A prompt CENTRED on its point (a stash's 'Faces
// towards you' sign) needs to know how wide its words are, so this page — which can answer — measures them
// the way the label page sets them: the same faces (css/fonts.css, which both pages load), at the
// row's type size, with its weight, letter-spacing and case. The answer is in the label row's pixels;
// Lua turns it into metres.

import { NuiRouter } from './router.js';
import { nuiCallback } from './utils.js';

const FAMILY = 'Barlow';             // label.html's face (css/fonts.css): one file per weight
const ROW_TEXT_MAX = 1008;           // label.html: a 1024 px row less its 8 px padding each side

/** The face at this weight, loaded before measuring. Each weight is its own file. */
async function fontReady(weight) {
    try {
        await document.fonts.load(`${weight} 54px "${FAMILY}"`);
    } catch (e) {
        // Measured in the fallback face then: near enough, and the prompt still centres.
    }
}

const ctx = document.createElement('canvas').getContext('2d');

async function measure(d) {
    const upper = d.case === 'upper';
    const text = upper ? String(d.text || '').toUpperCase() : String(d.text || '');
    const weight = Number(d.weight) || 700;
    const px = Number(d.px) || 54;
    await fontReady(weight);
    ctx.font = `${weight} ${px}px "${FAMILY}", "Segoe UI", sans-serif`;
    // label.html's letter-spacing: 0.5px, or 2px for upper case (applyFmt).
    const spacing = upper ? 2 : 0.5;
    const width = ctx.measureText(text).width + spacing * Array.from(text).length;
    // A label too wide for its row is set smaller until it fits (label.html fit()), so never more than the row.
    nuiCallback('i3dMeasured', { key: d.key, px: Math.min(ROW_TEXT_MAX, Math.round(width)) });
}

NuiRouter.register('i3dMeasure', (d) => { if (d && typeof d.key === 'string') measure(d); });
