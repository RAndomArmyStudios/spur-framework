// ========================================
// /whip SECTION — UI Library (the component tester)
//
// Ported from ui-tester.js. The old bottom-left non-modal card died with this port:
// as a panel section, every demo borrows the ACTUAL game screen — and the whole UI
// layer stack (toasts at z 900, the drawtext band, the skill check, the wheel) renders
// BELOW the panel overlay — so the Lua half (tools/panel_sections/uitester.lua)
// suspends the panel around each run. The panel hides, the demo plays where it can be
// seen, the panel resumes, and the card's result line gets patched via
// onData('result', {demo, result}). The callbacks keep their old uitTest* names;
// only the choreography around them changed.
// ========================================

import { WhipPanel, WP } from '../whip-panel.js';
import { nuiCallback } from '../utils.js';

// Toast copy per notify type — carried over from the old tester unchanged.
const NOTIFY_MESSAGES = {
    success: 'Operation completed successfully!',
    error: 'Something went wrong. Please try again.',
    info: 'Server restart in 5 minutes.',
    warning: 'Low health! Find food or a medkit.',
};

// One entry per demo card — the old #ui-tester-overlay sections, re-expressed in the
// wp-* vocabulary. `key` is the name Lua reports results back under; `cols` picks the
// wp-cols-N grid for the buttons row.
const DEMOS = [
    {
        key: 'notify', label: 'Notifications', cols: 4,
        desc: 'Stackable toast notifications (top-right, max 5). The panel hides for the toast’s 3s life.',
        buttons: [
            { label: 'Success', action: 'uitTestNotify', arg: 'success' },
            { label: 'Error',   action: 'uitTestNotify', arg: 'error' },
            { label: 'Info',    action: 'uitTestNotify', arg: 'info' },
            { label: 'Warning', action: 'uitTestNotify', arg: 'warning' },
        ],
    },
    {
        key: 'progress', label: 'Progress Bar', cols: 2,
        desc: 'Bottom-center bar, fills over duration. Blocks movement.',
        buttons: [
            { label: 'Start 5s',              action: 'uitTestProgress', arg: 'false' },
            { label: 'Start 5s (Cancelable)', action: 'uitTestProgress', arg: 'true' },
        ],
    },
    {
        key: 'input', label: 'Input Dialog', cols: 2,
        desc: 'Modal with text, number, select, checkbox fields.',
        buttons: [
            { label: 'Open Sample Form', action: 'uitTestInput' },
        ],
    },
    {
        key: 'skillcheck', label: 'Skill Check', cols: 3,
        desc: 'The ring: push the dot onto the lit part and hold it. Mouse or right stick.',
        buttons: [
            { label: 'Easy',   action: 'uitTestSkillCheck', arg: 'easy' },
            { label: 'Medium', action: 'uitTestSkillCheck', arg: 'medium' },
            { label: 'Hard',   action: 'uitTestSkillCheck', arg: 'hard' },
        ],
    },
    {
        key: 'alert', label: 'Alert Dialog', cols: 2,
        desc: 'Simple OK modal.',
        buttons: [
            { label: 'Show Alert', action: 'uitTestAlert' },
        ],
    },
    {
        key: 'confirm', label: 'Confirm Dialog', cols: 2,
        desc: 'Yes/No modal. Returns true/false.',
        buttons: [
            { label: 'Show Confirm', action: 'uitTestConfirm' },
        ],
    },
    {
        key: 'drawtext', label: 'DrawText UI', cols: 3,
        desc: 'The band at the bottom (or top) of the screen, the same element the progress bar draws into. Each preview runs ~2.5s.',
        buttons: [
            { label: 'Show at Bottom', action: 'uitTestDrawtext' },
            { label: 'Show at Top',    action: 'uitTestDrawtextTop' },
            { label: 'Manual Fill',    action: 'uitTestDrawtextProgress' },
        ],
    },
    {
        key: 'radial', label: 'Radial Menu', cols: 2,
        desc: 'Registers three sample options, then opens the wheel. Real options come from AddAction with at = { radial = true }. Press F1 in a vehicle for the built-in ones.',
        buttons: [
            { label: 'Register + Open', action: 'uitTestRadial' },
            { label: 'Remove Samples',  action: 'uitTestRadialClear' },
        ],
    },
    {
        key: 'interact', label: '3D Interaction', cols: 2,
        desc: 'Spawns a temporary interact point 3m ahead, for 30s: close the panel and walk up to it.',
        buttons: [
            { label: 'Spawn Test Indicator', action: 'uitTestInteract' },
        ],
    },
];

// live-patched elements: one result line per demo key
let els = { results: {} };

function buildCard(demo) {
    // Closed by default — eight open demo cards made the section a wall; scan the
    // labels, open the one you're testing.
    const g = WP.group(demo.key, demo.label, false);
    g.body.appendChild(WP.el('div', 'wp-item-sub', demo.desc));
    const row = WP.el('div', 'wp-cols-' + demo.cols);
    for (const b of demo.buttons) {
        row.appendChild(WP.btn(b.label, b.action, null, b.arg));
    }
    g.body.appendChild(row);
    const result = WP.el('div', 'wp-info-value wp-info-value-mono', '—');
    els.results[demo.key] = result;
    g.body.appendChild(result);
    return g.root;
}

// ---- the panel's own widgets: WP.stepper, WP.tabs, WP.statusRow ----
//
// Unlike the demos above these never leave the panel, so they run right here, with no Lua half.
// A four-step wizard that uses all three: a step that refuses Next until it is filled in, a step
// of tabs, an optional step to Skip, and a review of status rows. Nothing is sent anywhere.

const wizDemo = { name: '', kind: 'house', garage: false };
let wiz = null;
let wizGroup = null;

function wizStep(key, _from, body) {
    if (key === 'name') {
        body.appendChild(WP.el('div', 'wp-hint', 'Next refuses until there is a name, and says why in the footer.'));
        const input = WP.input({ value: wizDemo.name, placeholder: 'e.g. Mega A 3-1', inputAction: 'uitWizName' });
        body.appendChild(WP.field('Name', input, true));
    } else if (key === 'kind') {
        body.appendChild(WP.el('div', 'wp-hint', 'WP.tabs, inline. The choice survives going Back.'));
        const tabs = WP.tabs({
            id: 'uit-wiz-kind', inline: true, active: wizDemo.kind,
            tabs: [{ key: 'house', label: 'House' }, { key: 'apartment', label: 'Apartment' }, { key: 'studio', label: 'Studio' }],
            onChange: (k) => { wizDemo.kind = k; },
        });
        body.appendChild(tabs.root);
    } else if (key === 'garage') {
        body.appendChild(WP.el('div', 'wp-hint', 'An optional step: Skip is offered, and skipping it is shown on the rail.'));
        body.appendChild(WP.btn('Garage: ' + (wizDemo.garage ? 'ON' : 'OFF'), 'uitWizGarage', wizDemo.garage ? 'primary' : 'ghost'));
    } else if (key === 'review') {
        body.appendChild(WP.statusRow({ label: 'Name', status: wizDemo.name ? 'ok' : 'err',
            detail: wizDemo.name || 'missing', action: 'uitWizEdit', arg: 'name' }));
        body.appendChild(WP.statusRow({ label: 'Kind', status: 'ok', detail: wizDemo.kind, action: 'uitWizEdit', arg: 'kind' }));
        body.appendChild(WP.statusRow({ label: 'Garage', status: wizDemo.garage ? 'ok' : 'off',
            detail: wizDemo.garage ? 'private, 2 bays' : 'none', action: 'uitWizEdit', arg: 'garage' }));
        body.appendChild(WP.statusRow({ label: 'Verify', status: 'warn', detail: 'not checked in the world yet' }));
        body.appendChild(WP.statusRow({ label: 'Furniture', status: 'todo', detail: 'nothing placed' }));
    }
}

function buildWizardDemo() {
    const g = WP.group('wizard', 'Wizard, tabs and status rows', false);
    wizGroup = g.root;
    g.body.appendChild(WP.el('div', 'wp-item-sub',
        'WP.stepper with WP.tabs and WP.statusRow inside it. Escape steps back while this card is open.'));
    wiz = WP.stepper({
        id: 'uit-wizard',
        steps: [
            { key: 'name', label: 'Name' },
            { key: 'kind', label: 'Kind' },
            { key: 'garage', label: 'Garage', optional: true },
            { key: 'review', label: 'Review' },
        ],
        onGo: wizStep,
        canLeave: (from) => (from === 'name' && !wizDemo.name.trim()) ? 'Give it a name first' : true,
        onFinish: () => {
            WP.result('Demo wizard finished. Nothing was saved', 'ok');
            wiz.say('Finished. Pick any step to look again.', 'ok');
        },
        finishLabel: 'Save',
    });
    g.body.appendChild(wiz.root);
    wiz.start();
    return g.root;
}

WhipPanel.registerSection({
    id: 'uitester',
    group: 'system',
    label: 'UI Library',
    order: 20,

    render(root) {
        els = { results: {} };
        const solo = WP.el('div', 'wp-section-solo wp-section-center');
        for (const demo of DEMOS) solo.appendChild(buildCard(demo));
        solo.appendChild(buildWizardDemo());
        root.appendChild(solo);
    },

    onData(kind, payload) {
        // 'ready' (access confirmed on enter) carries nothing — the cards are static.
        // 'result' patches the card of the demo that just finished.
        if (kind === 'result' && payload && els.results[payload.demo]) {
            els.results[payload.demo].textContent = 'Result: ' + JSON.stringify(payload.result);
        }
    },

    // The wizard demo, while its card is open, is the one drill-down: Escape steps it back.
    onEscape() {
        return !!(wiz && wizGroup && wizGroup.classList.contains('open') && wiz.escape());
    },

    actions: {
        uitWizName: (el) => { wizDemo.name = el.value; },
        uitWizGarage: () => { wizDemo.garage = !wizDemo.garage; wiz.go('garage'); },
        uitWizEdit: (el) => wiz.go(el.dataset.arg),
        uitTestNotify: (el) => nuiCallback('uitTestNotify', {
            type: el.dataset.arg,
            text: NOTIFY_MESSAGES[el.dataset.arg] || 'Test notification',
        }),
        uitTestProgress: (el) => {
            const canCancel = el.dataset.arg === 'true';
            nuiCallback('uitTestProgress', {
                duration: 5000,
                canCancel: canCancel,
                // The bar says its own cancel key (X, or A on a pad: ui.js), as a satellite's would
                label: canCancel ? 'Searching...' : 'Processing...',
            });
        },
        uitTestInput: () => nuiCallback('uitTestInput', {}),
        uitTestSkillCheck: (el) => nuiCallback('uitTestSkillCheck', { difficulty: el.dataset.arg }),
        uitTestAlert: () => nuiCallback('uitTestAlert', {}),
        uitTestConfirm: () => nuiCallback('uitTestConfirm', {}),
        uitTestDrawtext: () => nuiCallback('uitTestDrawtext', {}),
        uitTestDrawtextTop: () => nuiCallback('uitTestDrawtextTop', {}),
        uitTestDrawtextProgress: () => nuiCallback('uitTestDrawtextProgress', {}),
        uitTestRadial: () => nuiCallback('uitTestRadial', {}),
        uitTestRadialClear: () => nuiCallback('uitTestRadialClear', {}),
        uitTestInteract: () => nuiCallback('uitTestInteract', {}),
    },
});
