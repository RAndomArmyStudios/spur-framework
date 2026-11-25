import { NuiRouter } from './router.js';

// ============================================
// Door Editor HUD — the in-world door registration overlay
//
// Extracted verbatim from the old doors.js when the Door Manager became a /whip
// section (html/js/wp/doors.js). Same split as zone-editor.js: the HUD shows while
// the panel is suspended, keeps its #door-editor-hud root in index.html, and is
// driven by tools/zones.lua (deShow on editor enter, deHide + WhipPanelResume on
// exit).
// ============================================

function deShow() { document.getElementById('door-editor-hud').style.display = 'block'; }
function deHide() { document.getElementById('door-editor-hud').style.display = 'none'; }

function deUpdate(data) {
    document.getElementById('de-target').textContent = data.targetModel || 'None';
    document.getElementById('de-target-hash').textContent = data.targetHash || '—';
    document.getElementById('de-target-pos').textContent = data.targetPos || '—';
    document.getElementById('de-target-saved').textContent = data.targetSaved ? 'YES' : 'No';
    document.getElementById('de-linking').textContent = data.linkingDoorId ? ('Door #' + data.linkingDoorId + ' → press E on second') : '—';
    document.getElementById('de-count').textContent = data.doorCount || 0;
}

function deStatus(text) {
    const el = document.getElementById('de-status');
    el.textContent = text;
    el.style.display = 'block';
    setTimeout(function() { el.style.display = 'none'; }, 3000);
}

// ROUTER REGISTRATION — see router.js's header. No key scope; the editor's game-side
// key thread owns the keyboard while the HUD shows.
NuiRouter.register('deShow', () => deShow());
NuiRouter.register('deHide', () => deHide());
NuiRouter.register('deUpdate', (d) => deUpdate(d));
NuiRouter.register('deStatus', (d) => deStatus(d.text));
