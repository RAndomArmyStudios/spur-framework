import { NuiRouter } from './router.js';

// ========================================
// COORDS — the /w Coords readout (tools/coords.lua)
// ========================================
//
// The house capsule, as the hint capsule and the objective cards are (css/coords.css has the look):
// a disc whose needle points the way you face, the position as the title, the heading and the copy
// key under it. Built once when the tool opens; an update only writes four numbers and a rotation.
//
// THE NUMBERS ARE WHAT GETS COPIED: two places, as tools/coords.lua formats the vector4 it puts on
// the clipboard, so the screen and the paste agree in the last digit.

let coordsVisible = false;
let _els = null;
let _copiedTimer = null;
let _rot = 0;     // where the needle is going, in degrees — kept running so it never spins the long way
let _shown = 0;   // where it is drawn now, easing toward _rot
let _turnFrame = 0;
let _turnLast = 0;

/** How quickly the needle catches up with a new heading: the time to close most of the gap. The
 *  page is told ten times a second, so this is a little under one update's worth. */
const TURN_TAU_MS = 60;

/** The needle: the way you face (house glyph rules, 24 x 24, solid like the HUD's own icons). */
const NEEDLE = '<svg class="co-needle" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">'
    + '<path d="M12 2.6 18.6 20.4 12 16.6 5.4 20.4Z" stroke="currentColor" stroke-width="1.2" stroke-linejoin="round"/></svg>';

/** The tick a copy shows for a moment. */
const TICK = '<svg class="co-tick" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6"'
    + ' stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12.5 10 17.5 19 7"/></svg>';

function el(tag, cls, text) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
}

/** One "X  -360.96" pair; returns the pair and the number's element. */
function pair(axis, extraCls) {
    const p = el('span', 'co-pair' + (extraCls ? ' ' + extraCls : ''));
    p.appendChild(el('span', 'co-axis', axis));
    const n = el('span', 'co-num', '0.00');
    p.appendChild(n);
    return { p, n };
}

/** Lua opens the tool: { key } — the key the copy binding is on, 'G' unless it was moved. */
function coordsShow(data) {
    coordsVisible = true;
    const overlay = document.getElementById('coords-overlay');
    overlay.innerHTML = '';
    overlay.style.display = 'block';
    if (_turnFrame) { cancelAnimationFrame(_turnFrame); _turnFrame = 0; }
    _rot = 0;
    _shown = 0;

    const card = el('div', 'sh-capsule co-card');

    const disc = el('div', 'sh-stat dt-disc');
    const core = el('div', 'sh-disc');
    core.appendChild(el('div', 'sh-fill'));
    disc.appendChild(core);
    const icon = el('div', 'sh-icon');
    icon.innerHTML = NEEDLE + TICK;   // fixed markup, no data
    disc.appendChild(icon);
    card.appendChild(disc);

    const body = el('div', 'dt-body');
    const title = el('div', 'dt-title co-xyz');
    const x = pair('X'), y = pair('Y'), z = pair('Z');
    title.appendChild(x.p);
    title.appendChild(y.p);
    title.appendChild(z.p);
    body.appendChild(title);

    const row = el('div', 'dt-row');
    const h = pair('H', 'dt-item co-head');
    row.appendChild(h.p);
    const copy = el('span', 'dt-item');
    copy.appendChild(el('kbd', 'dt-key', (data && typeof data.key === 'string' && data.key) || 'G'));
    const copyText = el('span', 'co-copy', 'Copy vector4');
    copy.appendChild(copyText);
    row.appendChild(copy);
    body.appendChild(row);
    card.appendChild(body);

    overlay.appendChild(card);
    _els = { card, needlePath: icon.querySelector('.co-needle path'), x: x.n, y: y.n, z: z.n, h: h.n, copyText };
    requestAnimationFrame(function() { card.classList.add('visible'); });
}

function coordsHide() {
    coordsVisible = false;
    if (_copiedTimer) { clearTimeout(_copiedTimer); _copiedTimer = null; }
    if (_turnFrame) { cancelAnimationFrame(_turnFrame); _turnFrame = 0; }
    const overlay = document.getElementById('coords-overlay');
    overlay.style.display = 'none';
    overlay.innerHTML = '';
    _els = null;
}

/** Lua, when a number the display shows has moved: { x, y, z, h }. */
function coordsUpdate(data) {
    if (!coordsVisible || !_els) return;
    _els.x.textContent = data.x.toFixed(2);
    _els.y.textContent = data.y.toFixed(2);
    _els.z.textContent = data.z.toFixed(2);
    _els.h.textContent = data.h.toFixed(2) + '°';

    // The game's heading turns ANTICLOCKWISE from north, and CSS rotates clockwise: the needle on a
    // north-up dial is at -h. Taken the short way from where it is, so 359° to 1° is a nudge, not a
    // turn the whole way round.
    const delta = ((-data.h - _rot) % 360 + 540) % 360 - 180;
    _rot += delta;
    if (!_turnFrame && Math.abs(_rot - _shown) > 0.05) {
        _turnLast = performance.now();
        _turnFrame = requestAnimationFrame(turnStep);
    }
}

/** One frame of the needle turning.
 *
 *  THE PATH IS TURNED, NOT THE ELEMENT. A CSS transition on transform hands the turn to the
 *  compositor, which spins a bitmap of the needle taken before it moved — and under the overlay's
 *  zoom that bitmap is soft, so the needle would go blurry for every turn. An SVG
 *  transform on the path is drawn as a shape every frame, so it is as sharp turning as standing
 *  still. It costs a repaint of one small icon per frame, and only while the needle is moving. */
function turnStep(now) {
    _turnFrame = 0;
    if (!_els) return;
    const dt = Math.max(0, now - _turnLast);
    _turnLast = now;
    _shown += (_rot - _shown) * (1 - Math.exp(-dt / TURN_TAU_MS));
    if (Math.abs(_rot - _shown) <= 0.05) _shown = _rot;
    _els.needlePath.setAttribute('transform', 'rotate(' + _shown.toFixed(2) + ' 12 12)');
    if (_shown !== _rot) _turnFrame = requestAnimationFrame(turnStep);
}

/** tools/core.lua finished putting the vector4 on the clipboard. */
function coordsCopied() {
    if (!coordsVisible || !_els) return;
    const c = _els;
    c.card.classList.add('copied');
    c.copyText.textContent = 'Copied';
    if (_copiedTimer) clearTimeout(_copiedTimer);
    _copiedTimer = setTimeout(function() {
        _copiedTimer = null;
        if (_els !== c) return;   // closed or reopened meanwhile
        c.card.classList.remove('copied');
        c.copyText.textContent = 'Copy vector4';
    }, 1400);
}


// ROUTER REGISTRATION — see router.js's header.
NuiRouter.register('coordsShow', (d) => coordsShow(d));
NuiRouter.register('coordsHide', () => coordsHide());
NuiRouter.register('coordsUpdate', (d) => coordsUpdate(d));
NuiRouter.register('coordsCopied', () => coordsCopied());
