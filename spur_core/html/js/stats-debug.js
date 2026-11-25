import { NuiRouter } from './router.js';
import { DebugPanel, num, dur, caption, empty, chip, statRow, changeRow, lineRow } from './debug-panel.js';

/* ========================================
   PLAYER STATS DEBUG — a section of the debug panel

   Your stats as the server holds them, five times a second (server/stats.lua Stats.getDebugData):
   each stat's value and bar in its HUD colour, the ped's own reading beside a vital (amber when they
   disagree), how long ago it was set, a need's decay; then the effects on you, and the last changes
   with what made them. Everything is set as text, never as markup: a change source can carry
   another player's name.
   ======================================== */

const sec = DebugPanel.section('player', { title: 'Player stats', order: 1 });

const NAMES = { health: 'Health', armour: 'Armour', hunger: 'Hunger', thirst: 'Thirst', developer: 'Developer' };
const label = (n) => NAMES[n] || (String(n).charAt(0).toUpperCase() + String(n).slice(1).replace(/_/g, ' '));

/** How full a stat is, as the HUD draws it: health counts from 100 (GTA's dead) to 200. */
function pctOf(s) {
    const v = Number(s.value) || 0, max = Number(s.max) || 100;
    if (s.type === 'vital' && max === 200) return (v - 100);
    return (v / max) * 100;
}

function render(data) {
    if (!sec.visible || !data) return;
    sec.setMeta(data.who || '');
    const frag = document.createDocumentFragment();

    for (const s of data.stats || []) {
        const extra = [];
        if (s.ped !== undefined && s.ped !== null) {
            extra.push(chip('ped ' + s.ped, Math.abs((Number(s.value) || 0) - s.ped) >= 1 ? 'warn' : ''));
        }
        if (typeof s.setAgo === 'number' && s.setAgo < 5) extra.push(chip('set ' + num(s.setAgo) + 's ago'));
        if (s.decay) extra.push(chip((s.decay > 0 ? '+' : '') + num(s.decay, 2) + ' / ' + (s.decayInterval || 10) + 's'));
        frag.appendChild(statRow({
            name: label(s.name), color: s.color, pct: pctOf(s),
            value: num(Number(s.value), 0) + ' / ' + (s.max ?? '?'), extra,
        }));
    }

    const effects = Object.entries(data.effects || {});
    if (effects.length) {
        frag.appendChild(caption('Effects · ' + effects.length));
        for (const [name, e] of effects) {
            const extra = [chip(e.remaining !== null && e.remaining !== undefined ? dur(e.remaining) + ' left' : 'permanent')];
            if (e.magnitude) extra.push(chip((e.magnitude > 0 ? '+' : '') + e.magnitude + (e.tickRate ? ' / ' + e.tickRate + 's' : '')));
            if (e.resource) extra.push(chip(e.resource));
            frag.appendChild(lineRow(label(name), extra));
        }
    }

    frag.appendChild(caption('Changes'));
    if (data.changes && data.changes.length) {
        for (const c of data.changes) {
            frag.appendChild(changeRow({ delta: c.delta, stat: label(c.stat), source: c.source, ago: c.ago }));
        }
    } else {
        frag.appendChild(empty('Nothing yet'));
    }

    sec.body.replaceChildren(frag);
}

// ROUTER REGISTRATION — see router.js's header.
NuiRouter.register('statsDebug', (d) => render(d.data));
NuiRouter.register('statsDebugShow', () => sec.show());
NuiRouter.register('statsDebugHide', () => sec.hide());
