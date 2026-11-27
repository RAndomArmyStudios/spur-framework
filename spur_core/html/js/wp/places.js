// ========================================
// A SCENARIO'S THINGS ON THE MAP — the marks and a mark's card, for every map that shows them: /whip's Scenarios page
// (wp/director.js, from the server's `places` answer: server/director/hub.lua placeOf) and the world builder's Map
// window (director/map.js, from the scenario open in the editor). A place is
//   { id, kind, name, x, y, model, layer, facts, uses: [{ what, n }], tasks: { steps, loop }, takes: [{ id, label, ms }],
//     lore: { name, retired, picture, pictureFrame, key, portraitAt }, weapon, item: { key, name, img } }
// ========================================

import { WP } from '../whip-panel.js';
import { pedImageUrl, vehicleImageUrl, propImageUrl, itemImageUrl } from '../utils.js';
import { GLYPHS } from '../furnisher-data.js';
import { frameStyle } from './lore.js';
import { lorePortrait } from '../lore-faces.js';

const arr = (v) => (Array.isArray(v) ? v : (v && typeof v === 'object' ? Object.values(v) : []));

/** Label and value rows. */
export function info(pairs) {
    const g = WP.el('div', 'wp-info-grid');
    for (const [label, value] of pairs) {
        g.appendChild(WP.el('span', 'wp-info-label', label));
        g.appendChild(WP.el('span', 'wp-info-value', value === undefined || value === null || value === '' ? '—' : String(value)));
    }
    return g;
}

// A thing's mark on the map: its own picture where there is one (placePic), over the world builder's glyph for its
// kind (furnisher.js KIND_GLYPH). A car's glyph is the garage rows' car (js/glyphs.js).
const KIND_GLYPH = { prop: 'box', npc: 'person', vehicle: 'car', spot: 'pin', groundItem: 'box', container: 'chest', door: 'door', route: 'pin' };
// As the editor names the kinds (director/panels.js worldInfo).
const KIND_TEXT = { npc: 'NPC', vehicle: 'Car', prop: 'Prop', container: 'Container', door: 'Door', groundItem: 'Item spot',
                    spot: 'Spot', route: 'Route' };
const BEHAVIOUR_TEXT = { stand: 'Stands still', guard: 'Guards its spot' };

export function kindGlyph(kind) {
    const car = kind === 'vehicle' && window.WhipGlyphs && window.WhipGlyphs.glyphs && window.WhipGlyphs.glyphs.car;
    return car || GLYPHS[KIND_GLYPH[kind] || 'pin'] || GLYPHS.pin;
}

/** A thing's own picture and how it sits in a round frame ({ pic, fit, frame }), or {} for its glyph: a lore
 *  character's portrait, else an NPC's ped (the whole of them: 'face' closes in), a car's, a prop's (a container's
 *  prop), an item spot's item. A picture that does not load leaves the glyph showing. */
export function placePic(p) {
    const f = p.facts || {};
    const m = p.model && !/^-?\d+$/.test(p.model) ? p.model : null;
    if (p.kind === 'npc' && p.lore && p.lore.picture) return { pic: p.lore.picture, frame: p.lore.pictureFrame || { x: 50, y: 50, z: 1 } };
    // No picture link: the headshot of a look made in the character editor (lore-faces.js), when it is here.
    const shot = p.kind === 'npc' && p.lore ? p.lore.portrait || lorePortrait(p.lore) : '';
    if (shot) return { pic: shot, frame: { x: 50, y: 50, z: 1 } };
    if (p.kind === 'npc' && m) return { pic: pedImageUrl(m), fit: 'face' };
    if (p.kind === 'vehicle' && m) return { pic: vehicleImageUrl(m) };
    if (p.kind === 'prop' && m) return { pic: propImageUrl(m) };
    if (p.kind === 'container' && typeof f.prop === 'string' && f.prop) return { pic: propImageUrl(f.prop) };
    if (p.kind === 'groundItem' && p.item) {
        const url = itemImageUrl(p.item.key, p.item.img);
        return /missing\.png$/.test(url) ? {} : { pic: url };
    }
    return {};
}

/** The places as marks for WP.place / WP.placeArea, each keeping its place (`place`) and its id. */
export function placeMarks(places) {
    return arr(places).map((p) => ({ id: p.id, x: p.x, y: p.y, name: p.name, glyph: kindGlyph(p.kind), ...placePic(p), place: p }));
}

const yesNo = (v) => (v === undefined ? undefined : v ? 'Yes' : 'No');

// A car's takes on the map: each drive its own colour, the first the game's route purple.
export const TAKE_COLOURS = ['#a44cf2', '#38bdf8', '#fbbf24', '#f472b6', '#34d399', '#f97316'];
const clock = (ms) => { const sec = Math.round(ms / 1000); return Math.floor(sec / 60) + ':' + String(sec % 60).padStart(2, '0'); };

/** What a mark's card says: the thing's picture, name and kind, what it does (its task steps, the cards and other
 *  things' tasks that name it) and its settings. */
export function placeCard(p) {
    const f = p.facts || {};
    const el = WP.el('div', 'wd-pc');
    const head = WP.el('div', 'wd-pc-head');
    const art = WP.el('span', 'wd-pc-art');
    art.innerHTML = kindGlyph(p.kind);   // one of whip's own glyphs, never data
    const pic = placePic(p);
    if (pic.pic) {
        const img = document.createElement('img');
        img.alt = '';
        img.draggable = false;
        if (pic.frame) frameStyle(img, pic.frame);
        else if (pic.fit === 'face') art.classList.add('wd-pc-ped');
        img.addEventListener('load', () => art.classList.add('wd-pc-has'));
        img.addEventListener('error', () => img.remove());
        img.src = pic.pic;
        art.appendChild(img);
        if (pic.frame) art.classList.add('wd-pc-face');
    }
    head.appendChild(art);
    const words = WP.el('div', 'wd-pc-words');
    words.appendChild(WP.el('span', 'wp-item-title', p.name || p.id || 'Unnamed'));
    const layer = p.layer === 'standing' ? 'Standing' : p.layer === 'run' ? 'Each run' : null;
    words.appendChild(WP.el('span', 'wp-item-sub', [KIND_TEXT[p.kind] || p.kind, layer].filter(Boolean).join(' · ')));
    if (p.lore) words.appendChild(WP.el('span', 'wp-item-sub', 'Lore character: ' + p.lore.name + (p.lore.retired ? ' (retired)' : '')));
    head.appendChild(words);
    el.appendChild(head);

    // WHAT IT DOES: its own steps, then who makes it or uses it.
    el.appendChild(WP.el('div', 'wp-section-title', 'What it does'));
    const does = WP.el('div', 'wd-pc-does');
    if (p.layer === 'standing') does.appendChild(WP.el('div', 'wp-hint', 'There whenever the scenario is on'));
    else if (p.kind === 'door') does.appendChild(WP.el('div', 'wp-hint', 'Locked or unlocked by the run\'s cards, and given back as it was when the run ends'));
    else if (p.layer === 'run') does.appendChild(WP.el('div', 'wp-hint', 'Made by the run\'s cards, and gone when the run ends'));
    else if (p.kind === 'spot') does.appendChild(WP.el('div', 'wp-hint', 'A place: for a blip, a waypoint, a drop-off or an area'));
    const steps = p.tasks ? arr(p.tasks.steps) : [];
    if (steps.length) {
        const ol = WP.el('ol', 'wd-pc-steps');
        for (const s of steps) ol.appendChild(WP.el('li', null, s));
        does.appendChild(ol);
        does.appendChild(WP.el('div', 'wp-hint', p.tasks.loop ? 'Then again from the top' : 'Then it stops'));
    } else if (p.kind === 'npc') {
        does.appendChild(WP.el('div', 'wd-pc-line', BEHAVIOUR_TEXT[f.behaviour] || BEHAVIOUR_TEXT.stand));
    }
    const uses = arr(p.uses);
    if (uses.length) {
        does.appendChild(WP.el('div', 'wd-pc-sub', 'Named by'));
        const ul = WP.el('ul', 'wd-pc-uses');
        for (const u of uses) ul.appendChild(WP.el('li', null, u.what + (u.n > 1 ? ' ×' + u.n : '')));
        does.appendChild(ul);
    } else if (p.kind !== 'spot') {
        does.appendChild(WP.el('div', 'wp-hint', 'No card names it'));
    }
    el.appendChild(does);

    // ITS SETTINGS, as the World tab has them.
    const rows = [];
    if (p.kind === 'npc') {
        rows.push(['Ped', p.model], ['Weapon', p.weapon || 'None']);
        if (f.armour) rows.push(['Armour', f.armour]);
        rows.push(['Fights back', yesNo(!!f.fightBack)], ['Cannot be hurt', yesNo(!!f.invincible)]);
        if (f.canMove === false) rows.push(['Can move', 'No']);
    } else if (p.kind === 'vehicle') {
        rows.push(['Car', p.model], ['Plate', f.plate || 'A new one each run'],
            ['Locked', yesNo(f.locked !== false)], ['Only its key opens it', yesNo(f.secure !== false)]);
    } else if (p.kind === 'prop') {
        rows.push(['Prop', p.model], ['Solid', yesNo(f.collision !== false)]);
        if (f.group) rows.push(['Group', f.group]);
    } else if (p.kind === 'container') {
        rows.push(['Prop', f.prop || 'None: only a prompt'], ['Slots', f.slots || 10], ['Holds', (f.maxWeight || 100) + ' kg']);
    } else if (p.kind === 'groundItem' && p.item) {
        rows.push(['Item', (p.item.name || p.item.key) + ' ×' + (f.amount || 1)]);
    }
    if (rows.length) {
        el.appendChild(WP.el('div', 'wp-section-title', 'Settings'));
        el.appendChild(info(rows));
    }
    // A car's takes: each drive's colour, as its line on the map (takeLines), its name and how long it lasts.
    const takes = arr(p.takes);
    if (takes.length) {
        el.appendChild(WP.el('div', 'wp-section-title', takes.length === 1 ? 'Its Scripted Driving Event' : 'Its Scripted Driving Events'));
        const ul = WP.el('ul', 'wd-pc-takes');
        takes.forEach((t, i) => {
            const li = WP.el('li');
            const sw = WP.el('span', 'wd-pc-take-swatch');
            sw.style.background = TAKE_COLOURS[i % TAKE_COLOURS.length];
            li.appendChild(sw);
            li.appendChild(WP.el('span', null, (t.label || 'Driving event ' + t.id) + (t.ms ? ' · ' + clock(t.ms) : '')));
            ul.appendChild(li);
        });
        el.appendChild(ul);
        el.appendChild(WP.el('div', 'wp-hint', takes.length === 1 ? 'Its line on the map is where it drives.' : 'Each line on the map is where it drives in that driving event.'));
    }
    return el;
}

/** A car's takes as lines for the map (WP.place's linesFor), or null for anything else. `pathOf(take)` answers a promise
 *  of the drive as { x1, y1, x2, y2, ... } (the server's takePath), null when it cannot be read: that take is left out. */
export function takeLines(p, pathOf) {
    const takes = p && p.kind === 'vehicle' ? arr(p.takes) : [];
    if (!takes.length) return Promise.resolve(null);
    return Promise.all(takes.map(async (t, i) => {
        const flat = await pathOf(t);
        if (!flat || flat.length < 4) return null;
        const points = [];
        for (let j = 0; j + 1 < flat.length; j += 2) points.push([flat[j], flat[j + 1]]);
        return { points, colour: TAKE_COLOURS[i % TAKE_COLOURS.length] };
    })).then((lines) => lines.filter(Boolean));
}
