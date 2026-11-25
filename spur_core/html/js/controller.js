// ============================================
// CONTROLLER BRIDGE — the NUI half
// ============================================
//
// A GAMEPAD IS INVISIBLE TO THIS PAGE. Nothing in whip's UI can read a controller directly, and
// that is not a gap to be worked around — it is the shape of the platform, twice over:
//
//   1. NUI resources are served as full-screen IFRAMES. The Gamepad API is gated behind a
//      Permissions-Policy the PARENT document must grant a frame (allow="gamepad"), and the
//      parent here belongs to FiveM, not to whip. There is no attribute we can add.
//   2. Even where the API exists, a pad stays hidden from a page until a button is pressed while
//      that page HAS FOCUS. A HUD overlay never has focus, so the list can legitimately stay
//      empty forever.
//
// So the pad is read where it can be read — by the game, in client/controller.lua, through GTA's
// own control layer — and arrives here as a message.
//
// IT SENDS INTENT, NOT KEYS. The payload says 'up', 'select', 'back'; it never says "the D-pad
// moved" and it never fakes an ArrowDown. Synthesising key events would have worked and would
// have been a trap: it hardcodes a keyboard model into the controller path, so the day a panel
// needs "next tab" as distinct from "next item" there is no way to express the difference — both
// are already spelled ArrowRight.
//
// THE ROUTER OWNS THE ROUTING. Nav goes through the same scope walk as keys (see router.js), so
// there is one answer to "which panel is on top" rather than two that drift apart.

import { NuiRouter } from './router.js';
import { nuiCallback } from './utils.js';
import { padGlyph } from './pad-glyphs.js';

/* ---- which panel, if any, can take a pad ----
   Reported up to Lua so the driver only runs when something is listening. Lua must NOT take the
   pad over for a panel with no onNav — see activeNavScope() in router.js for what that would do
   to a player. */
NuiRouter.onNavScopeChange((name, analog) => {
    nuiCallback('navScope', { scope: name, analog: !!analog });
});

/* ---- the hint strip ----
   On a controller, the menu holding the pad says which buttons do what: the B picture, "Close".
   Drawn from the top scope's `padHints` (router.js), bottom centre. A keyboard never sees it: the
   CSS shows it only under data-input="pad", so a device change needs no redraw. Redrawn when the
   hints change — on a scope change, after a nav press, and on the backstop tick below, which is
   what catches a dialog swapping its buttons inside one scope. */
const hintStrip = document.createElement('div');
hintStrip.id = 'pad-hints';
document.body.appendChild(hintStrip);
let shownHints = '';

function drawPadHints() {
    const hints = NuiRouter.activeNavHints() || [];
    // The look the screen asks for (router.js activeNavHintsLook): 'bare' is Whiplash's (css/ui.css).
    const look = NuiRouter.activeNavHintsLook() || '';
    const sig = look + '|' + JSON.stringify(hints);
    if (sig === shownHints) return;
    shownHints = sig;
    hintStrip.classList.toggle('pad-hints-bare', look === 'bare');
    hintStrip.textContent = '';
    // A hint's button may be a list, for a button held under another: [['rb', 'a'], 'Quick move'].
    for (const [button, label] of hints) {
        const imgs = (Array.isArray(button) ? button : [button])
            .map((name) => padGlyph(name, 'pad-hint-glyph')).filter(Boolean);
        if (!imgs.length) continue;
        const item = document.createElement('span');
        item.className = 'pad-hint';
        for (const img of imgs) item.appendChild(img);
        item.appendChild(document.createTextNode(label));
        hintStrip.appendChild(item);
    }
    hintStrip.classList.toggle('visible', hintStrip.childElementCount > 0);
    // Said on the page too, for what shares the bottom centre with the strip: the hint capsule
    // (css/ui.css §9) lifts above it while it is up — a dialog opened over a "[E] Search" hint.
    document.documentElement.classList.toggle('pad-hints-up', hintStrip.childElementCount > 0);
}

NuiRouter.onNavScopeChange(drawPadHints);
NuiRouter.onHintsChange(drawPadHints);   // a scope's hints changed with no press (the Director's circle)

/* A BACKSTOP, NOT THE MECHANISM — but a fast one, and the speed is a safety property rather than
   a nicety.

   Scope changes are reported the instant a message or a keypress causes one, which covers
   essentially every open and close. This catches the residue: a panel that closes itself on a
   timer, a scope whose isOpen() reads a DOM property something else wrote, any path that changes
   what is on screen without sending a message.

   WHY A MISS IS EXPENSIVE. While Lua believes a nav scope is open it holds the pad: gameplay
   controls disabled, NUI focus kept open. Miss a CLOSE and the player is standing in the world
   unable to move until this fires. 500ms bounds that to something a player reads as a hitch
   rather than as a freeze — and it is a walk of about six isOpen() calls twice a second, which
   is not a cost worth trading for that.

   If this interval is ever what makes the pad work at all, a change notification is missing
   somewhere and this is hiding it. */
setInterval(() => { NuiRouter.syncNavScope(true); drawPadHints(); }, 500);

/* ---- inbound ---- */

// One nav intent from the pad. Lua has already applied its own repeat timing, so each message is
// one deliberate press: do not de-bounce again here.
NuiRouter.register('navInput', (d) => {
    // rb: held under the press; held: a direction's ms down so far (0 the press, more on its repeats)
    if (d && d.nav) NuiRouter.handleNav(d.nav, { rb: d.rb === true, held: +d.held || 0 });
    drawPadHints();   // the press may have changed what the menu asks (a form opened, a confirm)
});

// The sticks and triggers as numbers, for a scope that asked (router.js activeNavAnalog): x/y the left
// stick past its dead zone (up is +y), rx/ry the right the same way, lt/rt the triggers 0-1. Sent when
// they change, and all 0 when let go, so the scope keeps moving at the last values between messages.
// `a` is whether A is held (never with LB): a press arrives as 'select' too, but only this says when
// it is let go — what a cursor that drags needs (the Director's).
NuiRouter.register('navAnalog', (d) => {
    if (d) {
        NuiRouter.handleAnalog({ x: +d.x || 0, y: +d.y || 0, lt: +d.lt || 0, rt: +d.rt || 0,
                                 rx: +d.rx || 0, ry: +d.ry || 0, a: d.a === true });
    }
});

/* WHICH DEVICE IS IN THE PLAYER'S HANDS, published as an attribute on <html>.
   `data-input="pad"` or `"kbm"`, so a stylesheet can swap a key hint for a button glyph with no
   JavaScript at all — `[data-input="pad"] .hint-key { display: none }` and its mirror. Lua settles
   the answer for 400 ms before sending it.

   NOT THE MOUSE CURSOR: CSS cannot hide it in FiveM (`cursor: none` gives no cursor handle, and
   FiveM's NUIClient::OnCursorChange swaps its default cursor in for that). The
   cursor goes with the focus instead: client/focus.lua, Focus.padInput. */
NuiRouter.register('controllerDevice', (d) => {
    document.documentElement.dataset.input = (d && d.pad) ? 'pad' : 'kbm';
});

/* Report once at load. Lua sends the real answer on ready, but a page that reloads mid-session
   would otherwise carry no attribute at all until the player next changed device. */
document.documentElement.dataset.input = 'kbm';
