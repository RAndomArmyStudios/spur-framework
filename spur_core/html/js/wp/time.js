// ========================================
// /whip SECTION — Time & Weather
//
// The pilot section, and the reference shape for every other port: build the skeleton
// once in render(), keep references to the elements that change, patch them in
// onData(), express every user action through the section's `actions` map (dispatched
// by the shell's ONE delegated listener — no addEventListener in sections), and let
// the shell own chrome, focus, Escape and zoom.
//
// Ported from time-manager.js. The single-column control form maps to the
// .wp-section-solo variant: no list column, just a toolbar-less stack of groups.
// ========================================

import { WhipPanel, WP } from '../whip-panel.js';
import { nuiCallback } from '../utils.js';

let state = { hour: 12, minute: 0, weather: 'CLEAR', frozen: false, blackout: false, timeScale: 1.0 };
let weatherTypes = [];

// live-patched elements
let els = {};

function cap(w) { return w.charAt(0) + w.slice(1).toLowerCase(); }

// The state as readouts, not boxes (boxes read as things to type in): the Item Log's number tiles,
// a value each.
function buildStatus(body) {
    const row = WP.el('div', 'wp-stats');
    const tile = (label, id) => {
        const t = WP.el('div', 'wp-stat');
        t.appendChild(WP.el('div', 'wp-stat-label', label));
        const v = WP.el('div', 'wp-stat-value', '—');
        els[id] = v;
        t.appendChild(v);
        return t;
    };
    row.appendChild(tile('Time', 'time'));
    row.appendChild(tile('Weather', 'weather'));
    row.appendChild(tile('Clock', 'frozen'));
    row.appendChild(tile('Speed', 'scale'));
    body.appendChild(row);
}

function buildTimeGroup(body) {
    // A flex row of content-sized capsules, not a wp-cols-3: a stretched grid gave a
    // two-digit hour a column's worth of input box. wp-input-short pins each box to
    // digit width and the row's own vertical padding keeps the presets off its heels.
    const row = WP.el('div', 'wp-actions-row');
    els.hour = WP.input({ type: 'number', id: 'wp-tw-hour' });
    els.hour.min = 0; els.hour.max = 23;
    els.hour.classList.add('wp-input-short');
    els.minute = WP.input({ type: 'number', id: 'wp-tw-minute' });
    els.minute.min = 0; els.minute.max = 59;
    els.minute.classList.add('wp-input-short');
    row.appendChild(WP.field('Hour', els.hour));
    row.appendChild(WP.field('Minute', els.minute));
    row.appendChild(WP.btn('Set Time', 'twSetTime', 'primary'));
    // On the grid the presets and weather buttons share: both edges line up with theirs.
    row.style.display = 'grid';
    row.style.gridTemplateColumns = 'minmax(0, 1fr) minmax(0, 1fr) auto';
    body.appendChild(row);

    // No 'Presets' heading — four buttons named Dawn/Noon/Sunset/Midnight explain
    // themselves better than a label above them could.
    const presets = WP.el('div', 'wp-cols-4');
    for (const [key, label] of [['dawn', 'Dawn 6:00'], ['noon', 'Noon 12:00'], ['sunset', 'Sunset 19:00'], ['midnight', 'Midnight 0:00']]) {
        presets.appendChild(WP.btn(label, 'twPreset', null, key));
    }
    body.appendChild(presets);
}

function buildWeatherGroup(body) {
    els.weatherGrid = WP.el('div', 'wp-cols-4');
    body.appendChild(els.weatherGrid);
    renderWeatherButtons();
}

function renderWeatherButtons() {
    if (!els.weatherGrid) return;
    els.weatherGrid.innerHTML = '';
    for (const w of weatherTypes) {
        const b = WP.btn(cap(w), 'twSetWeather', null, w);
        if (w === state.weather) b.classList.add('wp-btn-primary');
        els.weatherGrid.appendChild(b);
    }
}

function buildOptionsGroup(body) {
    const row = WP.el('div', 'wp-cols-2');
    // Both are toggles, and patch() lights them primary while active — the weather
    // buttons' idiom. Blackout loses its danger paint: red means destructive here,
    // and a blackout is undone with the same click that made it.
    els.freezeBtn = WP.btn('Freeze Time', 'twToggleFrozen');
    els.blackoutBtn = WP.btn('Enable Blackout', 'twToggleBlackout');
    row.appendChild(els.freezeBtn);
    row.appendChild(els.blackoutBtn);
    body.appendChild(row);

    body.appendChild(WP.el('div', 'wp-section-title', 'Time Scale'));
    // Same content-sized row as the hour/minute one — a 0.1–10 number never earned
    // half the pane's width.
    const scaleRow = WP.el('div', 'wp-actions-row');
    els.scaleInput = WP.input({ type: 'number', id: 'wp-tw-scale' });
    els.scaleInput.min = 0; els.scaleInput.max = 10; els.scaleInput.step = 0.1;
    els.scaleInput.classList.add('wp-input-short');
    scaleRow.appendChild(WP.field('Speed ×', els.scaleInput));
    scaleRow.appendChild(WP.btn('Set Scale', 'twSetScale'));
    scaleRow.style.display = 'grid';
    scaleRow.style.gridTemplateColumns = 'minmax(0, 1fr) auto';
    body.appendChild(scaleRow);
}

function patch() {
    const h = Math.floor(state.hour), m = Math.floor(state.minute);
    els.time.textContent = `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
    els.weather.textContent = cap(state.weather);
    els.frozen.textContent = state.frozen ? 'Frozen' : 'Running';
    els.scale.textContent = state.timeScale.toFixed(1) + '×';
    els.hour.value = h;
    els.minute.value = m;
    els.scaleInput.value = state.timeScale;
    els.freezeBtn.textContent = state.frozen ? 'Unfreeze Time' : 'Freeze Time';
    els.freezeBtn.classList.toggle('wp-btn-primary', state.frozen);
    els.blackoutBtn.textContent = state.blackout ? 'Disable Blackout' : 'Enable Blackout';
    els.blackoutBtn.classList.toggle('wp-btn-primary', state.blackout);
    renderWeatherButtons();
}

function adopt(data) {
    if (!data) return;
    if (data.hour !== undefined) state.hour = data.hour;
    if (data.minute !== undefined) state.minute = data.minute;
    if (data.weather) state.weather = data.weather;
    if (data.frozen !== undefined) state.frozen = data.frozen;
    if (data.blackout !== undefined) state.blackout = data.blackout;
    if (data.timeScale !== undefined) state.timeScale = data.timeScale;
    if (data.weatherTypes) weatherTypes = data.weatherTypes;
    patch();
}

WhipPanel.registerSection({
    id: 'time',
    group: 'world',
    label: 'Time & Weather',
    order: 40,

    render(root) {
        els = {};
        const solo = WP.el('div', 'wp-section-solo wp-section-center');

        const status = WP.group('status', 'Current State', true);
        buildStatus(status.body);
        solo.appendChild(status.root);

        const time = WP.group('time', 'Time', true);
        buildTimeGroup(time.body);
        solo.appendChild(time.root);

        const weather = WP.group('weather', 'Weather', true);
        buildWeatherGroup(weather.body);
        solo.appendChild(weather.root);

        const options = WP.group('options', 'Options', false);
        buildOptionsGroup(options.body);
        solo.appendChild(options.root);

        root.appendChild(solo);
    },

    onData(kind, payload) {
        // 'all' (section enter snapshot) and 'refresh' (server-side change while open)
        // carry the same flat shape.
        adopt(payload);
    },

    onEscape() { return false; },   // no drill-down state — Escape closes the panel

    actions: {
        twSetTime: () => {
            nuiCallback('twSetTime', {
                hour: parseInt(els.hour.value, 10) || 0,
                minute: parseInt(els.minute.value, 10) || 0,
            });
        },
        twPreset: (el) => nuiCallback('twSetPreset', { preset: el.dataset.arg }),
        twSetWeather: (el) => nuiCallback('twSetWeather', { weather: el.dataset.arg }),
        twToggleFrozen: () => nuiCallback('twSetFrozen', { frozen: !state.frozen }),
        twToggleBlackout: () => nuiCallback('twSetBlackout', { blackout: !state.blackout }),
        twSetScale: () => nuiCallback('twSetTimeScale', { scale: parseFloat(els.scaleInput.value) || 1.0 }),
    },
});
