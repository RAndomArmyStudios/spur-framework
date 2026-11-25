// ========================================
// DIRECTOR — on a controller
//
// The editor is a mouse's: cards dragged, wires pulled from pin to pin, menus on a right click, a grid
// panned and zoomed. So on a pad it gets a mouse: the shared circle (../pad-cursor.js), which presses
// the mouse's own buttons where it is, so the page's own handlers do the rest:
//   A   the left button. Hold it to drag a card, pull a wire from a pin or draw a box; a tap is a click
//       (on a card, its page), two quick taps a double click (a comment's name, a reroute on a wire).
//   X   a right click: a card's menu (only: not its page too), a pin's wires broken, Add a card on the grid.
//   D-pad   jumps the circle to the nearest thing that way it can press (fields, buttons, rows, cards, pins)
//   a text field or a number: A opens the pad keyboard; a list: a menu of its choices (the search's own)
// This file is what is the Director's about it:
//   B   Esc: shuts a menu, the search or a question, clears the selection, leaves the scenario, closes
//   LB / RB  the column's tabs     RS  pans the grid, or scrolls the list under the circle
//   LT / RT  zoom out / in at the circle      Y  fits the cards on the screen (the search up: types its filter)
// The scope takes the sticks as numbers, and A's hold with them (client/controller.lua, navAnalog `a`).
// ========================================

import { createPadCursor } from '../pad-cursor.js';
import { openMenu, isSearchOpen } from './search.js';

/** What the circle can press: it slows over these, rings them, and the D-pad jumps between them. */
const TARGETS = 'button, [data-act], [data-tab], [data-type], [data-t], .dr-card, .dr-pin, .dr-note-head, .dr-note-grip,'
    + ' .dr-search-row, .dr-menu-row, input, textarea, select';

let api = null;
let cur = null;

/** app.js lends: root(), shown(), escape(), fit(), tab(step), pan(dx, dy), zoomAt(x, y, k), onGrid(node). */
export function initPad(a) {
    api = a;
    cur = createPadCursor({
        name: 'director',
        root: a.root,
        shown: a.shown,
        targets: TARGETS,
        floats: '.dr-float',
        // A menu, the card search or a question up: the D-pad stays in it.
        modal: () => document.querySelector('.dr-float') || (a.root() && a.root().querySelector('.dr-modal')),
        menu: openMenu,
        // The card search: A anywhere on its box but a row picks the row lit, as Enter does.
        press: (n) => {
            const search = n.closest('.dr-search');
            if (!search || !isSearchOpen() || n.closest('.dr-search-row')) return false;
            const input = search.querySelector('.dr-search-input');
            if (input) input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
            return true;
        },
        label: (field) => {
            const row = field.closest('.dr-row');
            const lab = row && row.querySelector('.dr-label');
            const text = lab && lab.firstChild && lab.firstChild.textContent;
            return text && text.trim();
        },
        // A comment's name is kept with Enter, as it is typed.
        afterType: (field) => {
            if (field.classList.contains('dr-note-input')) {
                field.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
            }
        },
        onGrid: a.onGrid,
        pan: a.pan,
        zoomAt: a.zoomAt,
    });
}

/** The screen closed or went away: let go of anything held, hide the circle. */
export function padHide() {
    if (cur) cur.hide();
}

export function padAnalog(a) {
    if (cur) cur.analog(a);
}

export function padNav(nav) {
    if (!api || !cur || !api.shown()) return;
    if (cur.nav(nav)) return;
    if (nav === 'back') { cur.letGo(); api.escape(); }
    else if (nav === 'buttonY') {
        const input = isSearchOpen() && document.querySelector('.dr-float .dr-search-input');
        if (input) cur.typeInto(input); else api.fit();
    }
    else if (nav === 'tabPrev') api.tab(-1);
    else if (nav === 'tabNext') api.tab(1);
    // 'select' is A's press, which padAnalog has from `a` with its release: nothing more here.
}

/** The hint strip: what each button does where the circle is. */
export function padHints() {
    const on = !!(cur && cur.on());
    const t = cur && cur.over();
    const n = cur && cur.at();
    const grid = !!(n && api && api.onGrid(n));
    const pin = t && t.closest('.dr-pin'), card = t && t.closest('.dr-card');
    const a = !on ? 'Click'
        : t && t.matches('input, textarea') ? 'Type'
        : t && t.matches('select') ? 'Choose'
        : pin ? 'Hold: wire'
        : card ? 'Open · hold: move'
        : t ? 'Press'
        : grid ? 'Hold: box' : 'Click';
    const x = pin ? 'Break wires' : card ? 'Card menu' : grid ? 'Add card' : null;
    const out = [['ls', 'Move'], ['a', a]];
    if (x) out.push(['x', x]);
    out.push(['rs', grid || !on ? 'Pan' : 'Scroll'], [['lt', 'rt'], 'Zoom'], ['y', isSearchOpen() ? 'Type' : 'Fit'],
        [['lb', 'rb'], 'Tabs'], ['b', 'Back']);
    return out;
}
