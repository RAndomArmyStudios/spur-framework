// ============================================
// PAD OVERLAY — the UI half of /paddebug
// ============================================
//
// Draws every controller input whip watches, which physical button each one is, what whip has
// claimed it for, and a live tail of the actions that actually fired. See
// client/controller_debug.lua for WHY — the short version is that input in whip crosses four
// layers and every one of them fails the same way, silently.
//
// IT RECEIVES AND NEVER SENDS. No nuiCallback, no NUI focus, no listeners. The overlay has to be
// watchable while the game is still fully playable, because the inputs worth debugging only
// happen while driving, fighting or standing at a prompt — so anything that took focus would
// destroy the thing it exists to measure.
//
// THE LAYOUT IS BUILT ONCE. Lua sends the group/row table on open and then only what changes, so
// the per-frame path writes classes and text into nodes that already exist. Rebuilding the list
// on every state message would be a full reflow sixty times a second, and worse, it would make
// the rows move — which is unreadable while pressing things.

import { NuiRouter } from './router.js';

const root     = document.getElementById('pad-debug');
const deviceEl = document.getElementById('pd-device');
const statusEl = document.getElementById('pd-status');
const groupsEl = document.getElementById('pd-groups');
const logEl    = document.getElementById('pd-log');

/** control id -> its row element, so a state message is a map lookup per pressed control. */
const rowByControl = new Map();
/** control id -> { fill, val } for the axis bars. */
const axisByControl = new Map();
/** Which controls were down last paint, so only the difference is written. */
let lastDown = new Set();

function el(tag, cls, text) {
    const n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text !== undefined) n.textContent = text;
    return n;
}

// ============================================
// Layout — built once, on open
// ============================================

function buildLayout(groups, axisGroups) {
    rowByControl.clear();
    axisByControl.clear();
    lastDown = new Set();
    groupsEl.innerHTML = '';

    (groups || []).forEach((g) => {
        const wrap = el('div', 'pd-group');
        wrap.appendChild(el('div', 'pd-gtitle', g.title));

        (g.rows || []).forEach((r) => {
            const row = el('div', 'pd-row');

            row.appendChild(el('span', 'pd-cid', String(r.control)));

            // BOTH DEVICES, SIDE BY SIDE. A control is one action wired to a key AND a button,
            // and every hard input bug here came from only ever seeing one of them. An EMPTY pad
            // cell is the most informative thing in the table: it means no controller input can
            // reach that control, which is exactly what a replacement for 14/15 has to be.
            row.appendChild(el('span', 'pd-pad' + (r.pad ? '' : ' empty'), r.pad || '—'));
            row.appendChild(el('span', 'pd-kb'  + (r.kb  ? '' : ' empty'), r.kb  || '—'));

            // A control whip does not read still gets a row — confirming a press did NOTHING is
            // half of debugging input, and an absent row cannot say that.
            row.appendChild(el('span', 'pd-claim' + (r.claim ? '' : ' none'),
                r.claim || 'not read by whip'));

            wrap.appendChild(row);
            rowByControl.set(r.control, row);
        });

        groupsEl.appendChild(wrap);
    });

    // ONE FLAT INDEX ACROSS ALL AXIS GROUPS, matching AXIS_ORDER in the Lua. The per-frame
    // message is a bare array of numbers, so the two sides agree by position and nothing has to
    // carry a control id sixty times a second.
    let axisIndex = 0;

    (axisGroups || []).forEach((g) => {
        const wrap = el('div', 'pd-group');
        wrap.appendChild(el('div', 'pd-gtitle', g.title));

        // Sticks rest at centre and swing both ways; triggers rest at zero and only climb. Same
        // element, two readings — so the track is told which it is rather than guessing from the
        // sign of a value that happens to be negative at the time.
        const bipolar = g.range !== 'unipolar';

        (g.rows || []).forEach((a) => {
            const row = el('div', 'pd-axis');
            row.appendChild(el('span', 'pd-axis-label', a.label));

            const track = el('div', 'pd-axis-track' + (bipolar ? ' bipolar' : ''));
            const fill  = el('div', 'pd-axis-fill');
            track.appendChild(fill);

            // The half-travel line. This is where GTA starts calling a trigger "pressed", and
            // drawing it is what turns "my half-pull did something odd" into a visible boundary.
            if (typeof g.mark === 'number') {
                const mark = el('div', 'pd-axis-mark');
                mark.style.left = (g.mark * 100) + '%';
                track.appendChild(mark);
            }

            row.appendChild(track);
            row.appendChild(el('span', 'pd-axis-val', '0.00'));

            wrap.appendChild(row);
            axisByControl.set(a.control, {
                fill,
                val: row.lastChild,
                index: axisIndex++,
                bipolar,
            });
        });

        groupsEl.appendChild(wrap);
    });
}

// ============================================
// State — the per-change path
// ============================================

function srow(key, value, tone) {
    const r = el('div', 'pd-srow');
    r.appendChild(el('span', 'pd-skey', key));
    r.appendChild(el('span', 'pd-sval' + (tone ? ' ' + tone : ''), value));
    return r;
}

function paintStatus(st) {
    statusEl.innerHTML = '';

    // The detector is the one thing that can be outright BROKEN rather than merely off, so it
    // gets the loud treatment: a missing native means the whole bridge is disabled and every
    // other line below it is meaningless.
    statusEl.appendChild(st.detector
        ? srow('detector', st.detector, 'good')
        : srow('detector', 'MISSING — bridge off', 'bad'));

    statusEl.appendChild(srow('pad active', st.padActive ? 'yes' : 'no',
        st.padActive ? 'good' : null));
    statusEl.appendChild(srow('nav scope', st.navScope || 'none',
        st.navScope ? 'good' : null));
    statusEl.appendChild(srow('keep-input', st.holding ? 'held' : 'released',
        st.holding ? 'warn' : null));
}

function paintDown(down) {
    const now = new Set(down || []);

    // Only the difference. Walking every row on every message would touch ~20 elements a frame
    // to change two of them.
    lastDown.forEach((c) => {
        if (!now.has(c)) {
            const r = rowByControl.get(c);
            if (r) r.classList.remove('down');
        }
    });
    now.forEach((c) => {
        if (!lastDown.has(c)) {
            const r = rowByControl.get(c);
            if (r) r.classList.add('down');
        }
    });

    lastDown = now;
}

function paintAxes(values) {
    if (!values) return;
    axisByControl.forEach((a) => {
        const v = values[a.index];
        if (typeof v !== 'number') return;

        if (a.bipolar) {
            // A stick rests at centre, so the reading is DEFLECTION — the bar grows out of the
            // middle in whichever direction the stick went. Growing from the left would put a
            // resting stick at half full, which reads as "half pressed".
            const mag = Math.min(1, Math.abs(v)) * 50;
            a.fill.style.left  = (v < 0 ? 50 - mag : 50) + '%';
            a.fill.style.width = mag + '%';
        } else {
            // A trigger rests at zero and only climbs, so it fills from the left like a gauge.
            // Clamped at both ends: some of these controls report a signed value on a pad that
            // has never been touched, and a negative width is a silently invisible bar.
            a.fill.style.left  = '0%';
            a.fill.style.width = (Math.max(0, Math.min(1, v)) * 100) + '%';
        }

        a.val.textContent = v.toFixed(2);
    });
}

/* Sequence of the newest line already drawn. The state message carries the whole log every time
   it is sent, and it is sent on ANY change — so nudging a stick would otherwise rebuild fourteen
   elements every frame to redraw text that had not moved. */
let lastLogSeq = -1;

function paintLog(lines) {
    const newest = (lines && lines.length) ? lines[lines.length - 1].seq : 0;
    if (newest === lastLogSeq) return;
    lastLogSeq = newest;

    logEl.innerHTML = '';

    if (!lines || !lines.length) {
        logEl.appendChild(el('div', 'pd-empty', 'nothing fired yet'));
        return;
    }

    // Newest LAST, reading downward like a console. Newest-first would put the line you are
    // waiting for at the top while your eye is at the bottom where the last one appeared.
    lines.forEach((l, i) => {
        const line = el('div', 'pd-line' + (i === lines.length - 1 ? ' fresh' : ''));
        line.appendChild(el('span', 'pd-src ' + (l.source || ''), l.source || ''));

        const what = el('span', 'pd-what');
        what.textContent = l.label || '';
        if (l.detail) {
            const d = el('span', 'pd-detail', '  ' + l.detail);
            what.appendChild(d);
        }
        line.appendChild(what);

        logEl.appendChild(line);
    });
}

// ============================================
// Messages
// ============================================

NuiRouter.register('padDebugOpen', (d) => {
    buildLayout(d.groups, d.axisGroups);
    // -1 so the empty state always draws: Lua resets its counter to 0 on open, and a stale -1
    // from a previous session would otherwise match and leave the last run's lines on screen.
    lastLogSeq = -1;
    paintLog(null);
    root.classList.remove('pd-hidden');
});

NuiRouter.register('padDebugClose', () => {
    root.classList.add('pd-hidden');
});

NuiRouter.register('padDebugState', (d) => {
    if (root.classList.contains('pd-hidden')) return;
    if (d.status) paintStatus(d.status);
    paintDown(d.down);
    paintAxes(d.axes);
    paintLog(d.log);
});

/* The device chip rides the same message the rest of whip uses for this, rather than Lua sending
   it twice — controller.js already turns it into an attribute on <html>, and this is a second
   subscriber on the same action. */
NuiRouter.register('controllerDevice', (d) => {
    const pad = !!(d && d.pad);
    deviceEl.textContent = pad ? 'pad' : 'kbm';
    deviceEl.classList.toggle('on', pad);
});
