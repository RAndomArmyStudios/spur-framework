import { NuiRouter } from './router.js';

// ============================================
// Zone Editor HUD — the in-world editing overlay
//
// Extracted verbatim from the old zones.js when the Zone Manager became a /whip
// section (html/js/wp/zones.js). The HUD is NOT part of the panel: it shows while the
// panel is suspended and the player flies the editor camera, so it keeps its own
// #zone-editor-hud root in index.html and its own router actions. tools/zones.lua
// drives it (zeShow on editor enter, zeHide + WhipPanelResume on exit).
// ============================================

let _zeStatusTimeout = null;

function zeShow() {
    document.getElementById('zone-editor-hud').style.display = 'block';
}

function zeHide() {
    document.getElementById('zone-editor-hud').style.display = 'none';
    zeHints(false);
    if (_zeStatusTimeout) { clearTimeout(_zeStatusTimeout); _zeStatusTimeout = null; }
}

// MOVE CORNERS (tools/zones.lua zwAdjust) has keys of its own: they stand in for the
// editor's while it runs, and the editor's come back after.
const ADJUST_HINTS = ['[E] Pick up / put down a corner', '[F] Add a corner', '[R] Take a corner off',
    '[Scroll] Ceiling', '[Ctrl+Scroll] Floor', '[Shift+Scroll] Speed', '[G] Done', '[Esc] Back'];
let _zeDefaultHints = null;

function zeHints(adjusting) {
    const box = document.querySelector('#zone-editor-hud .ze-hints');
    if (!box) return;
    if (_zeDefaultHints === null) _zeDefaultHints = box.innerHTML;   // index.html's own, fixed markup
    if (adjusting === (box.dataset.adjust === '1')) return;
    box.dataset.adjust = adjusting ? '1' : '';
    if (!adjusting) { box.innerHTML = _zeDefaultHints; return; }
    box.innerHTML = '';
    for (const h of ADJUST_HINTS) {
        const s = document.createElement('span');
        s.textContent = h;
        box.appendChild(s);
    }
}

function zeUpdate(data) {
    const adjusting = data.mode === 'adjust';
    zeHints(adjusting);
    let modeText = adjusting ? 'Moving corners'
        : data.mode === 'none' ? 'None' : data.mode.charAt(0).toUpperCase() + data.mode.slice(1);
    if (data.creating && !adjusting) modeText += ' (placing)';
    document.getElementById('ze-mode').textContent = modeText;

    if (data.pos) {
        document.getElementById('ze-pos').textContent = data.pos.x + ', ' + data.pos.y + ', ' + data.pos.z;
    }

    const sizeRow = document.getElementById('ze-size-row');
    const radiusRow = document.getElementById('ze-radius-row');
    const polyRow = document.getElementById('ze-poly-row');
    const scanRow = document.getElementById('ze-scan-row');
    sizeRow.style.display = 'none';
    radiusRow.style.display = 'none';
    polyRow.style.display = 'none';
    scanRow.style.display = 'none';

    if (data.mode === 'box' && data.creating) {
        sizeRow.style.display = 'flex';
        document.getElementById('ze-size').textContent = data.sizeX + ' × ' + data.sizeY + ' × ' + data.sizeZ;
    }
    if (data.mode === 'sphere' && data.creating) {
        radiusRow.style.display = 'flex';
        document.getElementById('ze-radius').textContent = data.radius + 'm';
    }
    if ((data.mode === 'poly' || adjusting) && data.creating) {
        polyRow.style.display = 'flex';
        document.getElementById('ze-poly').textContent = data.polyPts + (data.polyClosed ? ' (closed)' : '');
    }
    if (data.scanActive) {
        scanRow.style.display = 'flex';
        const phase = data.scanScanning ? 'Scanning' : (data.scanPreview ? 'Preview' : 'Idle');
        let info = data.scanHits + ' hits → ' + data.scanPoints + ' pts';
        if (data.scanMinZ != null && data.scanMaxZ != null) {
            info += ' | Z: ' + data.scanMinZ + ' → ' + data.scanMaxZ;
        }
        document.getElementById('ze-scan').textContent = phase + ' — ' + info;
    }

    document.getElementById('ze-selected').textContent = data.selected || 'None';
    document.getElementById('ze-count').textContent = data.zoneCount || 0;
    document.getElementById('ze-speed').textContent = data.speed || '1.0';
}

function zeStatus(text) {
    const el = document.getElementById('ze-status');
    el.textContent = text;
    el.classList.remove('ze-status-fade');
    void el.offsetWidth; // force reflow
    el.classList.add('ze-status-fade');
    if (_zeStatusTimeout) clearTimeout(_zeStatusTimeout);
    _zeStatusTimeout = setTimeout(function() { el.textContent = ''; }, 3000);
}

// ROUTER REGISTRATION — see router.js's header. The HUD has no key scope: while it
// shows, NUI focus is off and the editor's game-side key thread owns the keyboard.
NuiRouter.register('zeShow', () => zeShow());
NuiRouter.register('zeHide', () => zeHide());
NuiRouter.register('zeUpdate', (d) => zeUpdate(d));
NuiRouter.register('zeStatus', (d) => zeStatus(d.text));
