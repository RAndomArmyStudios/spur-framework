/* ========================================
   THE DIALOG ON THE SCREEN — RedM (spur_core, 24 Nov 2026)

   On GTA the dialog capsule (interact3d/dialog.html) is a DUI texture that client/conversations.lua draws beside the
   NPC. RDR2 has no DUI textures, so there it could not be drawn at all: a Director Dialog Line showed neither the
   NPC's line nor the answers. Then conversations.lua sends the capsule's messages here, and this shows that same
   page in a frame low on the screen, so it looks and lays out (grid, stack, team, haggle) as it does in the world.

   The page paints four cells of 1024 x 512, cell k with answer k selected; this shows one of them, as the quad's UV
   does in the world. Messages: convScreen { msg } (the page's own message, as sent to the DUI), convScreen { hide },
   and convScreenCell { cell } (1-4). Nothing here takes a key or the mouse: the answers are the prompt's (E, the
   wheel, the number keys), as in the world.
   ======================================== */

import { NuiRouter } from './router.js';

const CELL_W = 1024;
const CELL_H = 512;
const CELLS = 4;
const SCALE_AT_1080 = 0.55;   // the capsule's size on a 1080-line screen; it scales with the screen's height

let host = null;
let frame = null;
let ready = false;
let pending = null;   // the last message before the page loaded (each message is the whole capsule)
let cell = 1;

function scale() {
    return SCALE_AT_1080 * (window.innerHeight / 1080);
}

function place() {
    if (!host) return;
    const s = scale();
    host.style.width = `${Math.round(CELL_W * s)}px`;
    host.style.height = `${Math.round(CELL_H * s)}px`;
    frame.style.transform = `scale(${s}) translateY(${-(cell - 1) * CELL_H}px)`;
}

function ensure() {
    if (host) return;
    const style = document.createElement('style');
    style.textContent = `
#conv-screen {
    position: fixed; left: 50%; bottom: 9vh; transform: translateX(-50%);
    overflow: hidden; pointer-events: none; z-index: 40;
    opacity: 0; transition: opacity 0.15s ease;
}
#conv-screen.on { opacity: 1; }
#conv-screen iframe {
    position: absolute; left: 0; top: 0; width: ${CELL_W}px; height: ${CELL_H * CELLS}px;
    border: 0; background: transparent; transform-origin: 0 0; pointer-events: none;
}`;
    document.head.appendChild(style);
    host = document.createElement('div');
    host.id = 'conv-screen';
    frame = document.createElement('iframe');
    frame.setAttribute('scrolling', 'no');
    frame.setAttribute('allowtransparency', 'true');
    frame.tabIndex = -1;
    frame.addEventListener('load', () => {
        ready = true;
        if (pending) frame.contentWindow.postMessage(pending, '*');
        pending = null;
    });
    frame.src = 'interact3d/dialog.html';
    host.appendChild(frame);
    document.body.appendChild(host);
    window.addEventListener('resize', place);
    place();
}

function post(msg) {
    if (ready) frame.contentWindow.postMessage(msg, '*');
    else pending = msg;
}

NuiRouter.register('convScreen', (d) => {
    if (!d) return;
    if (d.hide) {
        if (host) host.classList.remove('on');
        return;
    }
    if (!d.msg || typeof d.msg !== 'object') return;
    ensure();
    post(d.msg);
    host.classList.add('on');
});

NuiRouter.register('convScreenCell', (d) => {
    const n = Math.floor(Number(d && d.cell) || 1);
    cell = Math.max(1, Math.min(CELLS, n));
    place();
});
