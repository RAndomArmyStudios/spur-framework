import { NuiRouter } from './router.js';
import { DebugPanel, num, caption, empty, chip, statRow, changeRow, kvRow } from './debug-panel.js';

/* ========================================
   VEHICLE STATS DEBUG — a section of the debug panel

   What the car you are in is carrying, and what is moving it (client/vehicle_stats.lua, 20 times a
   second, read off the car's own statebag): every registered stat, what this car stores first, each
   bar in the stat's own HUD colour, its rate and the source of its last change; then the data
   resources have attached to the car, and the recent changes.

   EVERY REGISTERED STAT IS LISTED. "Absent, so it reads as its default" is a fact a debug panel
   should show, so a stat the car does not carry is drawn quiet AND says "not fitted" in words.
   Everything is set as text, never markup: a satellite's vehicle data reaches this panel.
   ======================================== */

const sec = DebugPanel.section('vehicle', { title: 'Vehicle stats', order: 2 });

function render(data) {
    if (!sec.visible || !data) return;

    if (!data.vehicle) {
        sec.setMeta('');
        sec.body.replaceChildren(empty('Not in a vehicle. The whip cars near you show theirs over them.'));
        return;
    }

    const v = data.vehicle;
    sec.setMeta(String(v.plate || '???').trim() + '  ·  #' + (v.id ?? '—') + '  ·  ' + (v.seat || ''));
    const frag = document.createDocumentFragment();

    if (!data.stats || !data.stats.length) frag.appendChild(empty('No stats registered'));
    for (const s of data.stats || []) {
        const extra = [];
        // The key you type into an export, when the label is more than the key with a capital.
        if (s.label && s.label.toLowerCase() !== String(s.name).toLowerCase()) extra.push(chip(s.name));
        if (!s.stored) extra.push(chip('not fitted'));
        if (!s.gauged) extra.push(chip('no gauge'));
        if (s.rate) extra.push(chip((s.rate > 0 ? '+' : '') + s.rate.toFixed(2) + '/s', s.rate < 0 ? 'down' : 'up'));
        else if (s.consumes && s.stored) extra.push(chip('idle'));
        if (s.source) extra.push(chip(s.source));
        frag.appendChild(statRow({
            name: s.label || s.name, color: s.stored ? s.color : null, dim: !s.stored,
            pct: s.pct, value: num(s.value) + ' · ' + num(s.pct, 0) + '%', extra,
        }));
    }

    if (data.attached && data.attached.length) {
        frag.appendChild(caption('Attached data'));
        for (const a of data.attached) frag.appendChild(kvRow(a.key, a.text));
    }

    frag.appendChild(caption('Changes'));
    if (data.changes && data.changes.length) {
        for (const c of data.changes) {
            frag.appendChild(changeRow({ delta: c.delta, stat: c.stat, source: c.source || '?', ago: c.ago,
                                         cleared: c.cleared, dp: 2 }));
        }
    } else {
        frag.appendChild(empty('Nothing yet'));
    }

    sec.body.replaceChildren(frag);
}

// ROUTER REGISTRATION — see router.js's header.
NuiRouter.register('vehStatDebug', (d) => render(d.data));
NuiRouter.register('vehStatDebugShow', () => sec.show());
NuiRouter.register('vehStatDebugHide', () => sec.hide());
