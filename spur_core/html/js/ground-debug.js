import { NuiRouter } from './router.js';
import { DebugPanel, dur, caption, empty, chip, kvRow, lineRow } from './debug-panel.js';

/* ========================================
   GROUND ITEMS DEBUG — a section of the debug panel

   The ground items in your cell of the ground grid and the eight around it (tools/ground_debug.lua,
   from server/dev_ground.lua once a second): how many piles and items, the most common, who dropped
   the most, the oldest and newest; then the pile you are looking at — what it is, who dropped it,
   how long it has lain there, where. Everything as text: item labels and names are other people's.
   ======================================== */

const sec = DebugPanel.section('ground', { title: 'Ground items', order: 3 });

const n = (v) => Number(v || 0).toLocaleString('en-US');

function render(d) {
    if (!sec.visible || !d) return;
    sec.setMeta(d.cell ? 'cell ' + d.cell + (d.span ? '  ·  ' + d.span + ' m square' : '') : '');
    const frag = document.createDocumentFragment();

    // What is beamed and on the map: the nearest piles within the far range (tools/ground_debug.lua),
    // said with how many there are in reach when the list stops short of them all.
    if (typeof d.range === 'number') {
        const km = (d.range / 1000).toFixed(d.range % 1000 ? 1 : 0);
        let text = n(d.marked) + (d.marked === 1 ? ' pile' : ' piles') + ' within ' + km + ' km';
        if (typeof d.beyond === 'number' && d.beyond > d.marked) text += '  ·  nearest of ' + n(d.beyond);
        frag.appendChild(kvRow('Marked', text));
    }

    if (!d.piles) {
        frag.appendChild(empty('Nothing on the ground around you'));
    } else {
        frag.appendChild(kvRow('Here', n(d.piles) + (d.piles === 1 ? ' pile' : ' piles') + '  ·  '
            + n(d.total) + ' items  ·  ' + n(d.kinds) + (d.kinds === 1 ? ' kind' : ' kinds')));
        if (d.oldest) frag.appendChild(kvRow('Oldest', d.oldest.label + '  ·  ' + dur(d.oldest.age)));
        if (d.newest) frag.appendChild(kvRow('Newest', d.newest.label + '  ·  ' + dur(d.newest.age)));

        frag.appendChild(caption('Most common'));
        for (const k of d.common || []) {
            frag.appendChild(lineRow(String(k.label || '?'),
                [chip(n(k.piles) + (k.piles === 1 ? ' pile' : ' piles')), chip('×' + n(k.amount))]));
        }

        frag.appendChild(caption('Dropping the most'));
        for (const w of d.droppers || []) {
            const name = w.charId ? String(w.name || 'Unknown character') : 'Nobody (placed by the server)';
            const extra = [chip(n(w.piles) + (w.piles === 1 ? ' pile' : ' piles'))];
            if (w.charId) extra.unshift(chip('#' + w.charId));
            frag.appendChild(lineRow(name, extra));
        }
    }

    frag.appendChild(caption('Looking at'));
    const a = d.aimed;
    if (a) {
        frag.appendChild(kvRow('What', String(a.label || a.key) + '  ×' + n(a.amount)));
        frag.appendChild(kvRow('Item', String(a.key)));
        frag.appendChild(kvRow('Dropped by', a.by ? String(a.byName || 'Unknown character') + '  #' + a.by
                                                  : 'Nobody (placed by the server)'));
        frag.appendChild(kvRow('Lying here', dur(a.age)));
        frag.appendChild(kvRow('Where', [a.x, a.y, a.z].map((v) => Number(v).toFixed(1)).join(', ')));
        frag.appendChild(kvRow('Pile', '#' + a.id));
    } else {
        frag.appendChild(empty('Look at an item to see it'));
    }

    sec.body.replaceChildren(frag);
}

// ROUTER REGISTRATION — see router.js's header.
NuiRouter.register('groundDebug', (d) => render(d.data));
NuiRouter.register('groundDebugShow', () => sec.show());
NuiRouter.register('groundDebugHide', () => sec.hide());
