import { NuiRouter } from './router.js';

// ========================================
// THE AIM DOT: whip's crosshair (client/aim_dot.lua)
// ========================================
//
// One dot, made on first use. Lua sends where it goes (x, y: fractions of the screen) and `blocked` (the
// muzzle is against something: red), and only when one of them changes.

let dot = null;

function aimDot(d) {
    if (!dot) {
        dot = document.createElement('div');
        dot.id = 'aim-dot';
        document.body.appendChild(dot);
    }
    if (!d.on) {
        dot.classList.remove('on', 'blocked');
        dot.style.left = '50%';
        dot.style.top = '50%';
        return;
    }
    dot.style.left = (d.x * 100) + '%';
    dot.style.top = (d.y * 100) + '%';
    dot.classList.add('on');
    dot.classList.toggle('blocked', d.blocked === true);
}

NuiRouter.register('aimDot', aimDot);
