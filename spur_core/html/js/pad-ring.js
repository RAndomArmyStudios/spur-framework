// ========================================
// PAD RING — a screen's highlight on a controller
//
// The white ring the D-pad moves over a screen's controls, for a screen that a pad drives control by
// control (the emote menu, the furnisher; the creator has its own copy, written first). It knows:
//   - which control is lit, as a KEY that outlives a redraw (the grids are rebuilt all the time)
//   - the nearest control that way: its distance that way, plus three times how far off to the side,
//     so a grid steps along its row or column; one too far off to the side is not "that way" at all
//   - to put its class back after a redraw (a MutationObserver), and to scroll a list to what it lit
//
//   const ring = createRing({ root: () => el, selector: '.a, .b', keyOf?: (el) => 'words' })
//   ring.set(el)  ring.step('down') -> the new one or null  ring.el()  ring.clear()
//
// The ring is drawn by the screen's CSS on `.pad-focus` under html[data-input="pad"], so a mouse never
// sees it.
// ========================================

const CLS = 'pad-focus';

function defaultKey(el) {
    if (el.id) return '#' + el.id;
    const d = el.dataset;
    return Object.keys(d).sort().map((k) => k + '=' + d[k]).join('|') || el.className;
}

function visible(el) {
    return !el.disabled && !el.hidden && el.getClientRects().length > 0;
}

function gap(a1, a2, b1, b2) { return Math.max(0, Math.max(a1, b1) - Math.min(a2, b2)); }

/** The nearest of `items` from `cur` in a direction (see the top), or null. */
export function nearestThatWay(cur, dir, items) {
    const a = cur.getBoundingClientRect();
    const ax = (a.left + a.right) / 2, ay = (a.top + a.bottom) / 2;
    let best = null, bestScore = Infinity;
    for (const el of items) {
        if (el === cur) continue;
        const b = el.getBoundingClientRect();
        const bx = (b.left + b.right) / 2, by = (b.top + b.bottom) / 2;
        let along, across, reach;
        if (dir === 'down' || dir === 'up') {
            if (dir === 'down' ? by <= ay + 1 : by >= ay - 1) continue;
            along = dir === 'down' ? b.top - a.bottom : a.top - b.bottom;
            across = gap(a.left, a.right, b.left, b.right);
            reach = 3 * Math.max(a.width, b.width);
        } else {
            // Left and right stay on the row: only what is beside it (the end of a row of cards does
            // not jump up to the chips over the list).
            if (dir === 'right' ? bx <= ax + 1 : bx >= ax - 1) continue;
            along = dir === 'right' ? b.left - a.right : a.left - b.right;
            across = gap(a.top, a.bottom, b.top, b.bottom);
            reach = 0.5 * Math.min(a.height, b.height);
        }
        if (across > reach) continue;
        const score = Math.max(0, along) + across * 3;
        if (score < bestScore) { bestScore = score; best = el; }
    }
    return best;
}

/** Scroll the list it is in (only that list) so the element can be seen. */
function reveal(el) {
    for (let n = el.parentElement; n && n !== document.body; n = n.parentElement) {
        const s = getComputedStyle(n);
        if ((s.overflowY === 'auto' || s.overflowY === 'scroll') && n.scrollHeight > n.clientHeight) {
            const er = el.getBoundingClientRect(), nr = n.getBoundingClientRect();
            if (er.top < nr.top + 4) n.scrollTop -= nr.top + 4 - er.top;
            else if (er.bottom > nr.bottom - 4) n.scrollTop += er.bottom - (nr.bottom - 4);
            return;
        }
    }
}

export function createRing(o) {
    const keyOf = o.keyOf || defaultKey;
    const ring = { key: null };
    let queued = false;

    ring.items = () => Array.from(o.root().querySelectorAll(o.selector)).filter(visible);
    ring.el = () => (ring.key ? ring.items().find((el) => keyOf(el) === ring.key) || null : null);

    ring.mark = () => {
        const el = ring.el();
        o.root().querySelectorAll('.' + CLS).forEach((x) => { if (x !== el) x.classList.remove(CLS); });
        if (el) el.classList.add(CLS);
    };

    ring.set = (el) => {
        if (!el) return;
        ring.key = keyOf(el);
        ring.mark();
        reveal(el);
    };

    ring.clear = () => {
        ring.key = null;
        ring.mark();
    };

    /** One step that way; the new control, or null when there is none. */
    ring.step = (dir) => {
        const cur = ring.el();
        if (!cur) return null;
        const next = nearestThatWay(cur, dir, ring.items());
        if (next) ring.set(next);
        return next;
    };

    // A redraw takes the class with the old element: put it back on the new one, once a frame.
    const watch = () => {
        const root = o.root();
        if (!root) return;
        new MutationObserver(() => {
            if (!ring.key || queued) return;
            queued = true;
            requestAnimationFrame(() => { queued = false; ring.mark(); });
        }).observe(root, { childList: true, subtree: true });
    };
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', watch); else watch();

    return ring;
}
