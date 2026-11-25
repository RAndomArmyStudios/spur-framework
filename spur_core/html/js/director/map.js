// ========================================
// THE WORLD BUILDER'S MAP — the scenario's things on whip's GTA map, in a window over the world (js/furnisher.js
// #fz-map, opened by its Map button), as /whip's Scenarios page shows them (wp/places.js: each thing's own picture,
// a mark's card, a car's takes as lines). Read from the scenario open here, saved or not, at where the builder has
// each thing now (client/property_furnish.lua furnishWhere, asked twice a second while the window is open; one put
// down and not given to the scenario yet is there too). The camera is the arrow. A mark's card has Go to (the camera
// in front of it, it selected) and Configure (its page on the right).
// ========================================

import { WP } from '../whip-panel.js';
import { nuiCallback } from '../utils.js';
import { getItemDefs } from '../core/item-defs.js';
import { placeMarks, placeCard, takeLines } from '../wp/places.js';
import { thingIs } from './things-data.js';
import { eachRef, namerText } from './refs.js';
import { listOf as list } from './doc.js';

const POLL_MS = 500;

// As the server's card says them (server/director/hub.lua placeOf): these settings, plain values only. (The kinds a
// run's cards make whatever their layer says: their runOnly, things-data.js.)
const PLACE_DEF = ['behaviour', 'armour', 'fightBack', 'plate', 'locked', 'secure', 'group', 'collision', 'slots',
                   'maxWeight', 'prop', 'amount'];
// What the builder holds that is not a thing of the map's: a task's point (its thing is the mark), a kind with no
// mark of its own (a route: its unmarked).
const notMark = (kind) => kind === 'point' || thingIs(kind, 'unmarked');

/** Who names each thing (refs.js: cards, task steps, other things' settings, the Settings), as hub.lua namersOf
 *  says it. { [id]: [{ what, n }] }, first met first. */
function namersOf(ed) {
    const out = {}, at = {};
    eachRef(ed.doc, ed.cards, ed.tasks && ed.tasks.types, (r) => {
        if (r.kind !== 'world') return;
        const what = namerText(r, ed.cards);
        const l = out[r.id] || (out[r.id] = []);
        const k = r.id + '\u0000' + what;
        if (k in at) { l[at[k]].n += 1; return; }
        at[k] = l.length;
        l.push({ what, n: 1 });
    });
    return out;
}

/** One thing as a place for the map's mark and card, at (x, y): what the server's placeOf says of it, from the
 *  scenario as it is here. */
function placeOf(ed, w, x, y, namers) {
    const d = w.def || {};
    const kind = String(w.kind || '');
    const p = { id: w.id, kind, name: String(w.label || w.id || ''), x, y, uses: namers[w.id] || [] };
    if (typeof d.model === 'string' && d.model) p.model = d.model;
    if (kind !== 'spot') p.layer = thingIs(kind, 'runOnly') || w.layer !== 'standing' ? 'run' : 'standing';
    const facts = {};
    for (const k of PLACE_DEF) {
        const v = d[k];
        if (typeof v === 'string' || typeof v === 'number' || typeof v === 'boolean') facts[k] = v;
    }
    const cond = d.conditions || {};
    if (typeof cond.invincible === 'boolean') facts.invincible = cond.invincible;
    if (typeof cond.canMove === 'boolean') facts.canMove = cond.canMove;
    p.facts = facts;
    if (kind === 'vehicle') {
        const takes = list(d.takes).filter((t) => t && Number.isInteger(Number(t.id)))
            .map((t) => ({ id: Number(t.id), label: typeof t.label === 'string' ? t.label : 'Driving event ' + t.id, ms: Number(t.ms) || undefined }));
        if (takes.length) p.takes = takes;
    }
    if (kind === 'npc') {
        const wn = d.weapon && typeof d.weapon === 'object' ? d.weapon.name : d.weapon;
        if (typeof wn === 'string' && wn) {
            const g = (ed.weapons || []).find((x) => x.name === wn.toUpperCase());
            // (As the server's hub.lua names it: whose, for one another resource adds.)
            p.weapon = g ? (g.from ? `${g.label} (${g.from})` : g.label) : wn;
        }
        const c = d.lore ? (ed.lore || []).find((x) => x.key === d.lore) : null;
        if (c) {
            // (key, portraitAt: their headshot where they have no picture link, wp/places.js placePic)
            p.lore = { name: c.name, retired: c.retired || undefined, picture: c.picture || undefined, pictureFrame: c.pictureFrame || undefined,
                       key: c.key, portraitAt: c.portraitAt || undefined, portrait: c.portrait || undefined };
            if (c.model) p.model = c.model;   // (their ped as it is now: Npcs.spawn wears it)
        }
    } else if (kind === 'groundItem' && typeof d.item === 'string' && d.item) {
        const idef = (getItemDefs() || {})[d.item];
        p.item = { key: d.item, name: idef && idef.name };
    }
    const t = d.tasks;
    if (t && Array.isArray(t.list) && t.list.length) {
        const types = ed.tasks && ed.tasks.types;
        const steps = t.list.map((s) => { const td = types && s && types.get(s.t); return td ? td.label : null; }).filter(Boolean);
        if (steps.length) p.tasks = { steps, loop: t.after === 'loop' };
    }
    return p;
}

/** Every mark: each of the builder's things where it is now (by its id the scenario's thing, or one not given to the
 *  scenario yet as the builder has it), then the scenario's placed things the builder has not got. */
function placesOf(ed, live) {
    const namers = namersOf(ed);
    const out = [], seen = new Set();
    for (const it of list(live)) {
        if (!it || notMark(it.kind) || typeof it.x !== 'number' || typeof it.y !== 'number') continue;
        const w = it.id ? ed.doc.world.find((x) => x.id === it.id) : null;
        if (w) {
            seen.add(w.id);
            out.push({ ...placeOf(ed, w, it.x, it.y, namers), index: it.index });
        } else {
            // Put down here, not the scenario's yet (its Configure, or Save, makes it so).
            out.push({ id: 'new:' + it.index, kind: it.kind || 'prop', name: it.label || it.model || 'New', x: it.x, y: it.y,
                       model: it.model || undefined, facts: {}, uses: [], fresh: true, index: it.index });
        }
    }
    for (const w of ed.doc.world) {
        const c = w.def && w.def.coords;
        if (seen.has(w.id) || notMark(w.kind) || !c || typeof c.x !== 'number' || typeof c.y !== 'number') continue;
        out.push(placeOf(ed, w, c.x, c.y, namers));
    }
    return out;
}

/**
 * The map in the window's body `el`. ctx: { ed, call (the Director's server calls), configure(id) (its page on the
 * right) }. Answers { resized(), stop() }.
 */
export function mountMap(el, ctx) {
    const { ed } = ctx;
    let area = null, timer = 0, stopped = false, sig = '', live = [];
    const paths = {};   // [take id] = a promise of its drive, read once (the server's takePath)

    const card = (m) => {
        const p = m.place;
        const box = placeCard(p);
        // Go to and Configure right under its name (what it says can run long: they are not scrolled to).
        const head = box.firstChild;
        if (p.fresh) head.after(WP.el('div', 'wp-hint', 'Put down here and not in the scenario yet: Configure or Save makes it one of its things.'));
        const row = WP.el('div', 'wp-actions-row wd-pc-acts');
        if (typeof p.index === 'number') {
            const go = WP.btn('Go to', null, 'primary');
            go.type = 'button';
            go.title = 'The camera in front of it, and it selected';
            go.addEventListener('click', () => nuiCallback('furnishSelectIndex', { index: p.index, goTo: true }));
            row.appendChild(go);
        }
        if (!p.fresh && ctx.configure) {
            const cfg = WP.btn('Configure', null, null);
            cfg.type = 'button';
            cfg.addEventListener('click', () => ctx.configure(p.id));
            row.appendChild(cfg);
        }
        if (row.childElementCount) head.after(row);
        return box;
    };
    const linesFor = (m) => takeLines(m.place, (t) => {
        if (!paths[t.id]) paths[t.id] = ctx.call('takePath', { key: ed.key, take: t.id }).then((r) => (r.ok ? list(r.data.points) : null));
        return paths[t.id];
    });

    async function tick() {
        if (stopped) return;
        const r = await nuiCallback('furnishWhere', {});
        if (stopped) return;
        if (r && Array.isArray(r.items)) live = r.items;
        else if (r && r.items && typeof r.items === 'object') live = Object.values(r.items);
        if (ed.doc) {
            const places = placesOf(ed, live);
            const marks = placeMarks(places);
            const now = JSON.stringify(places);
            if (!area) {
                const cam = r && r.cam;
                area = WP.placeArea(el, { name: ed.doc.name || 'The scenario', marks, card, linesFor, x: cam && cam.x, y: cam && cam.y });
                el.classList.toggle('fz-map-empty', !marks.length);
            } else if (now !== sig) {
                area.update(marks);
                el.classList.toggle('fz-map-empty', !marks.length);
            }
            sig = now;
            if (r && r.cam && typeof r.cam.x === 'number') area.player({ x: r.cam.x, y: r.cam.y, heading: Number(r.cam.heading) || 0 });
        }
        timer = setTimeout(tick, POLL_MS);
    }
    tick();

    return {
        resized() { if (area) area.map.render(); },
        stop() {
            stopped = true;
            clearTimeout(timer);
            el.innerHTML = '';
        },
    };
}
