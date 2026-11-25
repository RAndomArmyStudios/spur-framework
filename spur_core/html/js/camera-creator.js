import { NuiRouter } from './router.js';

// ========================================
// CAMERA CREATOR HUD — NUI Display
// ========================================

let ccVisible = false;
let _ccEls = null;
let _ccStatusTimeout = null;

function ccShow(data) {
    ccVisible = true;
    const overlay = document.getElementById('camera-creator-overlay');
    overlay.style.display = 'block';
    overlay.innerHTML = '';
    _ccBuildHUD(overlay, data.mode || 'single');
}

function ccHide() {
    ccVisible = false;
    const overlay = document.getElementById('camera-creator-overlay');
    overlay.style.display = 'none';
    overlay.innerHTML = '';
    _ccEls = null;
    if (_ccStatusTimeout) { clearTimeout(_ccStatusTimeout); _ccStatusTimeout = null; }
}

function _ccBuildHUD(overlay, mode) {
    _ccEls = {};

    const panel = document.createElement('div');
    panel.className = 'cc-panel';

    // ---- Header ----
    const header = document.createElement('div');
    header.className = 'cc-header';

    const title = document.createElement('div');
    title.className = 'cc-title';
    title.textContent = 'Camera';
    header.appendChild(title);

    const headerRight = document.createElement('div');
    headerRight.className = 'cc-header-right';

    const filterVal = document.createElement('div');
    filterVal.className = 'cc-filter-badge';
    filterVal.textContent = 'No Filter Applied';
    _ccEls.filter = filterVal;
    headerRight.appendChild(filterVal);

    const modeLabel = document.createElement('div');
    modeLabel.className = 'cc-mode';
    modeLabel.textContent = mode === 'single' ? 'SINGLE' : 'PATH';
    _ccEls.mode = modeLabel;
    headerRight.appendChild(modeLabel);

    header.appendChild(headerRight);
    panel.appendChild(header);

    // ---- Hero Metrics (FOV + Speed) ----
    const hero = document.createElement('div');
    hero.className = 'cc-hero';

    const fovItem = document.createElement('div');
    fovItem.className = 'cc-hero-item';
    const fovLabel = document.createElement('div');
    fovLabel.className = 'cc-hero-label';
    fovLabel.textContent = 'FOV';
    fovItem.appendChild(fovLabel);
    const fovVal = document.createElement('div');
    fovVal.className = 'cc-hero-val';
    fovVal.textContent = '60.0';
    _ccEls.fov = fovVal;
    fovItem.appendChild(fovVal);
    hero.appendChild(fovItem);

    const spdItem = document.createElement('div');
    spdItem.className = 'cc-hero-item';
    const spdLabel = document.createElement('div');
    spdLabel.className = 'cc-hero-label';
    spdLabel.textContent = 'Speed';
    spdItem.appendChild(spdLabel);
    const spdVal = document.createElement('div');
    spdVal.className = 'cc-hero-val';
    spdVal.textContent = '1.0';
    _ccEls.speed = spdVal;
    spdItem.appendChild(spdVal);
    hero.appendChild(spdItem);

    panel.appendChild(hero);

    // ---- Coordinates ----
    const coords = document.createElement('div');
    coords.className = 'cc-coords';
    _ccEls.posX = _ccCoord(coords, 'X', '0.000');
    _ccEls.posY = _ccCoord(coords, 'Y', '0.000');
    _ccEls.posZ = _ccCoord(coords, 'Z', '0.000');
    panel.appendChild(coords);

    // ---- Rotation + Waypoints ----
    const rotWp = document.createElement('div');
    rotWp.className = 'cc-rot-row';

    const rot = document.createElement('div');
    rot.className = 'cc-rot';
    _ccEls.rotX = _ccRotItem(rot, 'RX', '0.00');
    _ccEls.rotY = _ccRotItem(rot, 'RY', '0.00');
    _ccEls.rotZ = _ccRotItem(rot, 'RZ', '0.00');
    rotWp.appendChild(rot);

    const wpItem = document.createElement('div');
    wpItem.className = 'cc-wp-inline';
    wpItem.style.display = mode === 'multi' ? 'flex' : 'none';
    const wpLabel = document.createElement('span');
    wpLabel.className = 'cc-meta-label';
    wpLabel.textContent = 'WP';
    wpItem.appendChild(wpLabel);
    const wpVal = document.createElement('span');
    wpVal.className = 'cc-meta-val cc-wp';
    wpVal.textContent = '0';
    _ccEls.wpCount = wpVal;
    _ccEls.wpRow = wpItem;
    wpItem.appendChild(wpVal);
    rotWp.appendChild(wpItem);

    panel.appendChild(rotWp);

    // ---- Hints ----
    const hints = document.createElement('div');
    hints.className = 'cc-hints';
    const gLabel = mode === 'single' ? 'Place Camera' : 'Place Waypoint';
    const hintData = [
        ['G', gLabel], ['Tab', 'Filter'], ['H', 'Export'], ['M', 'Mode'],
        ['\u2190\u2192', 'Select'], ['E', 'Edit'], ['R', 'Delete'],
        ['F', 'Preview'], ['F5', 'HUD'], ['F6', 'Markers'], ['Esc', 'Exit']
    ];
    for (let i = 0; i < hintData.length; i++) {
        const h = document.createElement('div');
        h.className = 'cc-hint';
        const hSpan = document.createElement('span');
        hSpan.textContent = hintData[i][1];
        h.innerHTML = '<kbd>' + hintData[i][0] + '</kbd>';
        h.appendChild(hSpan);
        if (i === 0) _ccEls.gHintLabel = hSpan;
        hints.appendChild(h);
    }
    panel.appendChild(hints);

    // ---- Status ----
    const status = document.createElement('div');
    status.className = 'cc-status';
    status.style.display = 'none';
    _ccEls.status = status;
    panel.appendChild(status);

    overlay.appendChild(panel);
}

function _ccCoord(parent, label, defaultVal) {
    const item = document.createElement('div');
    item.className = 'cc-coord';
    const lbl = document.createElement('span');
    lbl.className = 'cc-coord-label';
    lbl.textContent = label;
    item.appendChild(lbl);
    const val = document.createElement('span');
    val.className = 'cc-coord-val';
    val.textContent = defaultVal;
    item.appendChild(val);
    parent.appendChild(item);
    return val;
}

function _ccRotItem(parent, label, defaultVal) {
    const item = document.createElement('div');
    item.className = 'cc-rot-item';
    const lbl = document.createElement('span');
    lbl.className = 'cc-rot-label';
    lbl.textContent = label;
    item.appendChild(lbl);
    const val = document.createElement('span');
    val.className = 'cc-rot-val';
    val.textContent = defaultVal;
    item.appendChild(val);
    parent.appendChild(item);
    return val;
}

function ccUpdate(data) {
    if (!ccVisible || !_ccEls) return;
    _ccEls.posX.textContent = data.x.toFixed(3);
    _ccEls.posY.textContent = data.y.toFixed(3);
    _ccEls.posZ.textContent = data.z.toFixed(3);
    _ccEls.rotX.textContent = data.rx.toFixed(2);
    _ccEls.rotY.textContent = data.ry.toFixed(2);
    _ccEls.rotZ.textContent = data.rz.toFixed(2);
    _ccEls.fov.textContent = data.fov.toFixed(1);
    _ccEls.speed.textContent = data.speed.toFixed(1);
    _ccEls.filter.textContent = (!data.filter || data.filter === 'none') ? 'No Filter Applied' : 'Filter: ' + data.filter;
    if (_ccEls.wpCount) {
        const total = data.waypointCount || 0;
        if (data.selectedIdx && total > 0) {
            _ccEls.wpCount.textContent = data.selectedIdx + '/' + total;
        } else {
            _ccEls.wpCount.textContent = total;
        }
    }
}

function ccModeChanged(data) {
    if (!ccVisible || !_ccEls) return;
    _ccEls.mode.textContent = data.mode === 'single' ? 'SINGLE' : 'PATH';
    if (_ccEls.wpRow) {
        _ccEls.wpRow.style.display = data.mode === 'multi' ? 'flex' : 'none';
    }
    if (_ccEls.gHintLabel) {
        _ccEls.gHintLabel.textContent = data.mode === 'single' ? 'Place Camera' : 'Place Waypoint';
    }
}

function ccFilterChanged(data) {
    if (!ccVisible || !_ccEls) return;
    _ccEls.filter.textContent = (!data.filter || data.filter === 'none') ? 'No Filter Applied' : 'Filter: ' + data.filter;
}

function ccPointSaved(data) {
    _ccShowStatus(data.mode === 'single' ? 'Point saved!' : 'Waypoint #' + data.count + ' added');
}

function ccCopied() {
    _ccShowStatus('Copied to clipboard!');
}

function ccPreviewStart() {
    _ccShowStatus('Previewing path...');
}

function ccPreviewEnd() {
    _ccShowStatus('Preview complete');
}

function ccSelectChanged(data) {
    if (!ccVisible || !_ccEls) return;
    if (_ccEls.wpCount) {
        const total = data.total || 0;
        if (data.selectedIdx && total > 0) {
            _ccEls.wpCount.textContent = data.selectedIdx + '/' + total;
        } else {
            _ccEls.wpCount.textContent = total;
        }
    }
}

function _ccShowStatus(text) {
    if (!ccVisible || !_ccEls || !_ccEls.status) return;
    _ccEls.status.textContent = text;
    _ccEls.status.style.display = 'block';
    _ccEls.status.style.animation = 'none';
    void _ccEls.status.offsetWidth;
    _ccEls.status.style.animation = 'ccStatusFade 2s var(--ui-ease) both';
    if (_ccStatusTimeout) clearTimeout(_ccStatusTimeout);
    _ccStatusTimeout = setTimeout(function() {
        if (_ccEls && _ccEls.status) _ccEls.status.style.display = 'none';
        _ccStatusTimeout = null;
    }, 2000);
}


// ROUTER REGISTRATION — see router.js's header.
NuiRouter.register('ccShow', (d) => ccShow(d));
NuiRouter.register('ccHide', () => ccHide());
NuiRouter.register('ccUpdate', (d) => ccUpdate(d));
NuiRouter.register('ccModeChanged', (d) => ccModeChanged(d));
NuiRouter.register('ccFilterChanged', (d) => ccFilterChanged(d));
NuiRouter.register('ccPointSaved', (d) => ccPointSaved(d));
NuiRouter.register('ccCopied', () => ccCopied());
NuiRouter.register('ccPreviewStart', () => ccPreviewStart());
NuiRouter.register('ccPreviewEnd', () => ccPreviewEnd());
NuiRouter.register('ccSelectChanged', (d) => ccSelectChanged(d));