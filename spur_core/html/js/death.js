import { NuiRouter } from './router.js';

// ========================================
// DEATH SCREEN — Cinematic Blackout & Wake
// ========================================

const deathOverlay = document.getElementById('death-overlay');

/** Snap to black — visceral impact (called on health=0). */
function deathFadeOut() {
    deathOverlay.className = 'death-active';
}

/** Eye-flutter wake-up (called after death state is set up). */
function deathFadeIn() {
    deathOverlay.className = 'death-fadein';
}

/** Instant cleanup — resets all animation state. The death screen goes too. */
function deathHide() {
    deathOverlay.className = '';
    screenOff();
}


// ========================================
// THE DEATH SCREEN — css/death.css has the look
// ========================================
//
// client/death.lua's RunRespawnFlow drives it with `deathScreen` messages:
//   { state: 'count', left, total, hidden }   each second of the countdown
//   { state: 'ready', progress, key }         the hold: 0-100, sent when it changes; key: the Interact key's name
//   { state: 'held', label }                  a resource holds the respawn (HoldRespawn): its words, no hold
//   { hidden }                                the hide key (H / Y), bottom right
//   { state: 'off' }                          the respawn's fade; deathHide does the same
// Lua owns `hidden` (the hold does nothing while the screen is hidden); the page only shows it.

const screen    = document.getElementById('death-screen');
const leftEl    = screen.querySelector('.ds-left');
const unitEl    = screen.querySelector('.ds-unit');
const fillEl    = screen.querySelector('.ds-fill');
const holdLabel = screen.querySelector('.ds-hold-label');
const holdKey   = screen.querySelector('.ds-hold .ds-kbm');   // the keyboard's key: the Interact binding's
const keyLabel  = screen.querySelector('.ds-toggle-label');
const heldEl    = screen.querySelector('.ds-held');

const clampPct = (n) => Math.max(0, Math.min(100, Number(n) || 0));

function screenOff() {
    screen.classList.remove('on', 'ds-ready', 'ds-holding', 'ds-held-on', 'ds-hidden');
}

function deathScreen(d) {
    if (!d) return;
    if (d.state === 'off') { screenOff(); return; }

    if (d.hidden != null) screen.classList.toggle('ds-hidden', d.hidden === true);

    if (d.state === 'held') {
        screen.classList.remove('ds-ready', 'ds-holding');
        screen.classList.add('on', 'ds-held-on');
        heldEl.textContent = typeof d.label === 'string' ? d.label.slice(0, 80) : '';
        fillEl.style.width = '0%';
    } else if (d.state === 'count') {
        const left = Math.max(0, Math.floor(Number(d.left) || 0));
        screen.classList.remove('ds-ready', 'ds-holding', 'ds-held-on');
        screen.classList.add('on');
        leftEl.textContent = String(left);
        unitEl.textContent = left === 1 ? 'second' : 'seconds';
        fillEl.style.width = (d.total > 0 ? clampPct(left / d.total * 100) : 0) + '%';
    } else if (d.state === 'ready') {
        const p = clampPct(d.progress);
        screen.classList.remove('ds-held-on');
        screen.classList.add('on', 'ds-ready');
        screen.classList.toggle('ds-holding', p > 0);
        holdLabel.textContent = p > 0 ? 'Keep holding' : 'Hold to respawn';
        if (typeof d.key === 'string' && d.key) holdKey.textContent = d.key.slice(0, 6);
        fillEl.style.width = p + '%';
    }

    keyLabel.textContent = screen.classList.contains('ds-hidden') ? 'Show' : 'Hide';
}


// ROUTER REGISTRATION — see router.js's header.
NuiRouter.register('deathFadeOut', () => deathFadeOut());
NuiRouter.register('deathFadeIn', () => deathFadeIn());
NuiRouter.register('deathHide', () => deathHide());
NuiRouter.register('deathScreen', (d) => deathScreen(d));
