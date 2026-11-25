// ========================================
// LOGO LIGHT — the logo with its loading light, for any page that shows it
// RedM (spur_core, 23 Nov 2026): the logo is a SPUR wordmark now (logoMarkup), not WHIP's.
//
// The light is the loading screen's (spur_loadingscreen/html/js/logo.js): the four circles in the bar
// under the letters light one at a time, left to right, each at once and with a random interaction
// icon on it, and fade as the light moves on. The icons come from js/glyphs.js: the actions only,
// and only those that fit 1899, as in the loading screen's copy (NOT_LIT).
//
// Shared by the landing page (landing.js, which builds it with logoMarkup), the pause menu
// (pause.js, which builds it with logoMarkup) and the logo over a load's black (curtain.js) — one
// copy of the light, not three that drift.
// Styled by the page that shows it: .ld-letters, .ld-ring, .ld-disc, .ld-hole, .ld-icon, and
// .ld-dot.lit for the lit circle (landing.css has the look).
// ========================================

/** How long each circle stays lit before the next takes over — the loading screen's pace. */
const STEP_MS = 450;

/** How wide an icon is against its disc: the 3D badge's share. The car slices fill the disc. */
const ICON_SHARE = 0.46 / 0.78;

const shared = window.WhipGlyphs || { glyphs: {}, fullBleed: {} };

/** The marks that are not actions: a menu arrow (`back`), an objective card's (a tick or a cross lit
 *  over a load would read as a verdict on it), the notifications', and the dev tools' own. */
const NOT_LIT = new Set(['back', 'objective', 'target', 'pin', 'star', 'timer',
    'fail', 'success', 'info', 'warning', 'object', 'ped', 'camera',
    // RedM (spur_core, 23 Nov 2026): and the ones with no place in 1899, as the loading screen leaves out
    // (spur_loadingscreen/html/js/logo.js, NOT_1899): cars and their parts, fuel, a phone, a power switch.
    'hood_closed', 'hood_open', 'trunk_closed', 'trunk_open', 'trunk_lid', 'garage', 'car', 'turbo',
    'fuel', 'nozzle', 'headlights', 'phone', 'power', 'devtools', 'theme']);
const names = Object.keys(shared.glyphs).filter((n) => !NOT_LIT.has(n));

/** The logo's markup with clip ids under `prefix`, so two copies on one page do not share them.
 *  RedM (spur_core, 23 Nov 2026): a SPUR wordmark in place of WHIP's logo (a fork may not use WHIP's name or
 *  mark: NOTICE.md). The light runs along the four circles in the bar under the letters. */
export function logoMarkup(prefix) {
    const DOTS = [468, 532, 596, 660];   // the four circles' x, along the bar (cy 332)
    const CY = 332;
    const circle = (cx, cy) => '<circle cx="' + cx + '" cy="' + cy + '" r="20.5"/>';
    const light = (cx, cy, clip) => '<g class="ld-light"><circle class="ld-ring" cx="' + cx + '" cy="' + cy + '" r="26.5"/>'
        + '<circle class="ld-disc" cx="' + cx + '" cy="' + cy + '" r="20.5"/>'
        + '<g class="ld-icon" clip-path="url(#' + prefix + '-' + clip + ')"></g></g>';
    const dot = (cx, i) => '<g class="ld-dot"><circle class="ld-hole" cx="' + cx + '" cy="' + CY + '" r="20"/>' + light(cx, CY, i) + '</g>';
    return '<svg viewBox="52 40 1024 329" xmlns="http://www.w3.org/2000/svg"><defs>'
        + DOTS.map((cx, i) => '<clipPath id="' + prefix + '-' + i + '">' + circle(cx, CY) + '</clipPath>').join('')
        + '</defs><g class="ld-letters">'
        // S
        + '<path d="M292 50 V96 H124 V140.5 H252 A40 40 0 0 1 292 180.5 V237 A40 40 0 0 1 252 277 H62 V231 H230 V186.5 H102 A40 40 0 0 1 62 146.5 V90 A40 40 0 0 1 102 50 Z"/>'
        // P
        + '<path fill-rule="evenodd" d="M320 50 H510 A40 40 0 0 1 550 90 V160 A40 40 0 0 1 510 200 H382 V277 H320 Z M382 96 V154 H488 V96 Z"/>'
        // U
        + '<path d="M578 50 H640 V178 A53 53 0 0 0 746 178 V50 H808 V162 A115 115 0 0 1 578 162 Z"/>'
        // R
        + '<path fill-rule="evenodd" d="M836 50 H1026 A40 40 0 0 1 1066 90 V160 A40 40 0 0 1 1026 200 L1066 277 H1000 L960 200 H898 V277 H836 Z M898 96 V154 H1004 V96 Z"/>'
        // the bar the light runs along
        + '<rect x="422" y="305" width="284" height="54" rx="27"/>'
        + '</g>'
        + DOTS.map(dot).join('')
        + '</svg>';
}

/** The light on a logo inside `root`: { start, stop }. Paints the fixed W and P icons at once. */
export function logoLight(root) {
    const dots = root ? Array.from(root.querySelectorAll('.ld-dot')) : [];
    let bag = [], last = null, timer = null, at = -1;

    function shuffle(list) {
        for (let i = list.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            const t = list[i]; list[i] = list[j]; list[j] = t;
        }
        return list;
    }

    /** A random icon: shuffled in rounds, never the same one twice running. */
    function nextIcon() {
        if (!names.length) return null;
        if (!bag.length) {
            bag = shuffle(names.slice());
            // The round is dealt from the end: do not start it with the one just shown.
            if (bag.length > 1 && bag[bag.length - 1] === last) {
                const t = bag[0]; bag[0] = bag[bag.length - 1]; bag[bag.length - 1] = t;
            }
        }
        last = bag.pop();
        return last;
    }

    /** Put an icon on a circle's disc, sized in the logo's own coordinates. */
    function paint(group, name) {
        const slot = group.querySelector('.ld-icon');
        const disc = group.querySelector('.ld-disc');
        if (!slot || !disc) return;
        if (!name || !shared.glyphs[name]) { slot.innerHTML = ''; return; }
        const cx = +disc.getAttribute('cx'), cy = +disc.getAttribute('cy'), r = +disc.getAttribute('r');
        const size = shared.fullBleed[name] ? r * 2 : r * 2 * ICON_SHARE;
        slot.innerHTML = shared.glyphs[name];
        const svg = slot.firstElementChild;
        if (!svg) return;
        svg.setAttribute('x', cx - size / 2);
        svg.setAttribute('y', cy - size / 2);
        svg.setAttribute('width', size);
        svg.setAttribute('height', size);
    }

    if (root) root.querySelectorAll('[data-icon]').forEach((g) => paint(g, g.getAttribute('data-icon')));

    function step() {
        if (at >= 0) dots[at].classList.remove('lit');   // fades (the page's CSS), its icon with it
        at = (at + 1) % dots.length;
        paint(dots[at], nextIcon());
        dots[at].classList.add('lit');                   // lights at once
    }

    return {
        start() {
            if (timer || !dots.length) return;
            at = -1;
            step();
            timer = setInterval(step, STEP_MS);
        },
        stop() {
            if (timer) clearInterval(timer);
            timer = null;
            dots.forEach((d) => d.classList.remove('lit'));
            at = -1;
        },
    };
}
