// ============================================
// RADAR TUNER — the UI half of /radardebug
// ============================================
//
// Builds a slider + editable number for every value the minimap exposes, and posts each change
// straight at Lua. See client/radar_debug.lua for WHY this exists and what each component was
// found to actually control — the short version is that the names lie and the only way to tune
// them was to see them.

import { NuiRouter } from './router.js';
import { nuiCallback } from './utils.js';

const root = document.getElementById('radar-debug');
const bodyEl = document.getElementById('rd-body');
const optsEl = document.getElementById('rd-opts');

/** Live copy of what Lua sent, so a change can post the whole component rather than a diff. */
let state = { components: [], opts: {} };

/* RANGES ARE GENEROUS ON PURPOSE. The stock values all sit under 0.5, but the compass hunt
   already went outside what looked reasonable — a slider that cannot reach the answer is worse
   than no slider, because it reads as "I tried that" when you did not. */
const RANGE = {
    posX:  { min: -1.0, max: 1.0, step: 0.0005 },
    posY:  { min: -1.0, max: 1.0, step: 0.0005 },
    sizeX: { min:  0.0, max: 1.5, step: 0.0005 },
    sizeY: { min:  0.0, max: 1.5, step: 0.0005 },
    corner: { min: 0.0, max: 3.0, step: 0.01 },   // the black skin's frame corners: 1 = the mask's own
};

const ALIGN_X = ['L', 'R', 'C', 'I'];
const ALIGN_Y = ['T', 'B', 'C', 'I'];

function rgb(c) {
    return c ? `rgb(${c[0]},${c[1]},${c[2]})` : 'rgba(255,255,255,0.4)';
}

/** Post one component's current values. `rebuild:false` while dragging — Lua debounces the
 *  expensive radar rebuild, and saying so lets it skip even scheduling one mid-drag. */
function push(comp, rebuild) {
    nuiCallback('radarDebugSet', {
        key: comp.key,
        posX: comp.posX, posY: comp.posY, sizeX: comp.sizeX, sizeY: comp.sizeY,
        alignX: comp.alignX, alignY: comp.alignY, corner: comp.corner,
        rebuild: rebuild !== false,
    });
}

function fieldRow(comp, field) {
    const r = RANGE[field];

    const row = document.createElement('div');
    row.className = 'rd-row';

    const label = document.createElement('label');
    label.textContent = field;
    row.appendChild(label);

    const slider = document.createElement('input');
    slider.type = 'range';
    slider.min = r.min; slider.max = r.max; slider.step = r.step;
    slider.value = comp[field];
    row.appendChild(slider);

    const num = document.createElement('input');
    num.type = 'number';
    num.step = r.step;
    num.value = Number(comp[field]).toFixed(4);
    row.appendChild(num);

    // `input` fires continuously during a drag, `change` once it is released. The split is what
    // makes dragging smooth: values stream without a rebuild, and the rebuild lands on release.
    slider.addEventListener('input', () => {
        comp[field] = parseFloat(slider.value);
        num.value = comp[field].toFixed(4);
        push(comp, false);
    });
    slider.addEventListener('change', () => push(comp, true));

    num.addEventListener('change', () => {
        const v = parseFloat(num.value);
        if (Number.isNaN(v)) { num.value = Number(comp[field]).toFixed(4); return; }
        comp[field] = v;
        // A typed value can legitimately sit outside the slider's range; let the slider clamp
        // its own handle rather than clamping the value the user asked for.
        slider.value = v;
        push(comp, true);
    });

    return row;
}

function alignRow(comp) {
    const wrap = document.createElement('div');
    wrap.className = 'rd-aligns';

    [['alignX', ALIGN_X], ['alignY', ALIGN_Y]].forEach(([field, options]) => {
        const sel = document.createElement('select');
        options.forEach(o => {
            const opt = document.createElement('option');
            opt.value = o;
            opt.textContent = `${field === 'alignX' ? 'X' : 'Y'}: ${o}`;
            if (comp[field] === o) opt.selected = true;
            sel.appendChild(opt);
        });
        sel.addEventListener('change', () => { comp[field] = sel.value; push(comp, true); });
        wrap.appendChild(sel);
    });

    return wrap;
}

function componentCard(comp) {
    const card = document.createElement('div');
    card.className = 'rd-comp' + (comp.managed ? '' : ' rd-extra');

    const head = document.createElement('div');
    head.className = 'rd-comp-head';

    const swatch = document.createElement('span');
    swatch.className = 'rd-swatch';
    swatch.style.background = rgb(comp.colour);
    head.appendChild(swatch);

    const name = document.createElement('span');
    name.className = 'rd-comp-name';
    name.textContent = comp.label;
    head.appendChild(name);

    // Per-component outline toggle. Several can be on at once — seeing minimap and
    // minimap_blur together is what makes their relationship legible.
    const outline = document.createElement('button');
    outline.type = 'button';
    outline.className = 'rd-toggle' + (comp.outline ? ' on' : '');
    outline.textContent = 'box';
    outline.addEventListener('click', () => {
        comp.outline = !comp.outline;
        outline.classList.toggle('on', comp.outline);
        nuiCallback('radarDebugOutline', { key: comp.key, on: comp.outline });
    });
    head.appendChild(outline);

    card.appendChild(head);

    if (comp.note) {
        const note = document.createElement('p');
        note.className = 'rd-note';
        note.textContent = comp.note;
        card.appendChild(note);
    }

    // The black skin's frame brings a corner scale and has no anchors (client/radar_debug.lua).
    (comp.fields || ['posX', 'posY', 'sizeX', 'sizeY']).forEach(f => card.appendChild(fieldRow(comp, f)));
    if (!comp.noAlign) card.appendChild(alignRow(comp));

    return card;
}

/* ---- the global switches ---- */

function optToggle(labelText, name, isOn, valueWhenOn, valueWhenOff) {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'rd-toggle' + (isOn ? ' on' : '');
    b.textContent = labelText;
    b.addEventListener('click', () => {
        const nowOn = !b.classList.contains('on');
        b.classList.toggle('on', nowOn);
        nuiCallback('radarDebugOpt', { name, value: nowOn ? valueWhenOn : valueWhenOff });
    });
    return b;
}

function buildOpts(o) {
    optsEl.innerHTML = '';

    optsEl.appendChild(optToggle('outlines', 'showOutlines', o.showOutlines !== false, true, false));
    optsEl.appendChild(optToggle('bigmap',   'bigmapOn',     !!o.bigmapOn,             true, false));
    optsEl.appendChild(optToggle('hide bars', 'hideBars',    o.hideBars !== false,     true, false));
    // The black skin's frame on top of the game's HUD, for if the radar is drawn before it and hidden.
    optsEl.appendChild(optToggle('frame over the HUD', 'frameOver', !!o.frameOver, true, false));

    // Mask shape cycles rather than using a dropdown: four states, and the point is flicking
    // between them while watching, not picking one from a list.
    const SHAPES = ['rounded', 'square', 'circle', false];
    const shapeBtn = document.createElement('button');
    shapeBtn.type = 'button';
    shapeBtn.className = 'rd-toggle on';
    const shapeLabel = v => 'mask: ' + (v ? v : 'game');
    shapeBtn.textContent = shapeLabel(o.maskShape);
    shapeBtn.addEventListener('click', () => {
        const i = SHAPES.indexOf(state.opts.maskShape);
        const next = SHAPES[(i + 1) % SHAPES.length];
        state.opts.maskShape = next;
        shapeBtn.textContent = shapeLabel(next);
        nuiCallback('radarDebugOpt', { name: 'maskShape', value: next });
    });
    optsEl.appendChild(shapeBtn);

    // Zoom and clip type are numeric and rarely touched, so they get compact rows rather than
    // pills. 0 / -1 mean "do not call the native at all", which is not the same as calling it
    // with zero — and is why they default there.
    [['radarZoom', 'zoom', 0, 1400, 10], ['clipType', 'clip', -1, 3, 1]].forEach(
        ([name, label, min, max, step]) => {
            const row = document.createElement('div');
            row.className = 'rd-row';
            row.style.gridColumn = '1 / -1';
            row.style.width = '100%';

            const l = document.createElement('label');
            l.textContent = label;
            row.appendChild(l);

            const s = document.createElement('input');
            s.type = 'range'; s.min = min; s.max = max; s.step = step;
            s.value = o[name] !== undefined ? o[name] : min;
            row.appendChild(s);

            const n = document.createElement('input');
            n.type = 'number'; n.step = step;
            n.value = s.value;
            row.appendChild(n);

            const send = v => {
                state.opts[name] = v;
                nuiCallback('radarDebugOpt', { name, value: v });
            };
            s.addEventListener('input', () => { n.value = s.value; });
            s.addEventListener('change', () => send(parseFloat(s.value)));
            n.addEventListener('change', () => { s.value = n.value; send(parseFloat(n.value)); });

            optsEl.appendChild(row);
        });
}

function render(data) {
    state = data;
    buildOpts(data.opts || {});
    bodyEl.innerHTML = '';
    (data.components || []).forEach(c => bodyEl.appendChild(componentCard(c)));
}

/* ---- open / close ---- */

function open(data) {
    render(data);
    root.classList.remove('rd-hidden');
}

function close() {
    root.classList.add('rd-hidden');
}

document.getElementById('rd-close').addEventListener('click', () => {
    close();
    nuiCallback('radarDebugClose', {});
});

document.getElementById('rd-print').addEventListener('click', () => {
    nuiCallback('radarDebugPrint', {});
});

// Back to whip's shipped values — the point this session started from.
document.getElementById('rd-reset').addEventListener('click', () => {
    nuiCallback('radarDebugReset', { mode: 'config' });
});

// The game's own frontend.xml values. Kept as a diagnostic rather than a convenience: if the
// compass aligns here and nowhere else, the scaleform is ignoring the overrides entirely.
document.getElementById('rd-vanilla').addEventListener('click', () => {
    nuiCallback('radarDebugReset', { mode: 'stock' });
});

// ESC closes, like every other whip panel. Bound on the document because the panel does not
// hold focus while a slider is being dragged.
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !root.classList.contains('rd-hidden')) {
        close();
        nuiCallback('radarDebugClose', {});
    }
});

NuiRouter.register('radarDebugOpen', (d) => open(d.data || { components: [], opts: {} }));
NuiRouter.register('radarDebugClose', () => close());
