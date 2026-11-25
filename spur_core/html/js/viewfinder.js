import { NuiRouter } from './router.js';

// ========================================
// VIEWFINDER — the camera item's overlay
//
// Lua shows it while the player looks through a camera (client/items/camera.lua) and hides it when the
// camera comes down. The look is css/viewfinder.css; this only turns it on and off and runs the
// timecode, hours:minutes:seconds:frames at 30 frames a second from the moment it shows. Only the look:
// the camera takes nothing yet.
// ========================================

const el = document.getElementById('viewfinder');
const clock = el.querySelector('.vf-time');

let shownAt = 0;
let raf = 0;
let last = '';

const two = (n) => String(n).padStart(2, '0');

function tick(now) {
    const f = Math.floor(Math.max(0, now - shownAt) / (1000 / 30));
    const s = Math.floor(f / 30);
    const text = two(Math.floor(s / 3600)) + ':' + two(Math.floor(s / 60) % 60) + ':' + two(s % 60) + ':' + two(f % 30);
    if (text !== last) { clock.textContent = text; last = text; }   // only where the page has a timecode (see below)
    raf = requestAnimationFrame(tick);
}

NuiRouter.register('viewfinder', (d) => {
    const on = !!(d && d.on);
    cancelAnimationFrame(raf);
    el.classList.toggle('on', on);
    // RedM (spur_core, 25 Nov 2026): the page has no timecode any more (a plate camera of 1899), so nothing runs.
    if (!on || !clock) return;
    shownAt = performance.now();
    last = '';
    raf = requestAnimationFrame(tick);
});
