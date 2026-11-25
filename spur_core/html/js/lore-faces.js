import { nuiCallback } from './utils.js';

// ========================================
// LORE FACES — lore characters' headshots, for every page that shows them
// ========================================
//
// A lore character whose look was made in the character editor has a HEADSHOT, taken as that look was saved
// (server/director/lore.lua). It is their face wherever they have no picture link: a link replaces it.
// The lists that name them carry only when it was taken (portraitAt); the picture itself is asked for here, a page
// at a time (tools/panel_sections/director.lua lorePortraits), and kept until it is taken again.
//
//   primeLorePortraits(list)  ask for the headshots of a list of lore characters ({ key, portraitAt }) not here
//                             yet, then set `portrait` (a data: URL) on each one in the list. Answers whether any
//                             changed, and 'whip:loreportraits' is sent on window when one did.
//   lorePortrait(c)           a lore character's headshot, if it is here (also sets c.portrait), else ''

const PAGE = 20;              // the server answers at most this many at once
const kept = new Map();       // key -> { at, url }
const flying = new Set();     // 'key@at' asked for and not answered: never asked twice

/** A lore character's headshot when it is here, else ''. */
export function lorePortrait(c) {
    if (!c || !c.key || !c.portraitAt) return '';
    const hit = kept.get(c.key);
    if (!hit || hit.at !== c.portraitAt) return '';
    c.portrait = hit.url;
    return hit.url;
}

/** Ask for the headshots this list needs, then put them on its characters. */
export async function primeLorePortraits(list) {
    const all = (Array.isArray(list) ? list : Object.values(list || {})).filter((c) => c && typeof c.key === 'string');
    let changed = false;
    // What is here already goes on at once.
    for (const c of all) {
        const before = c.portrait;
        const url = lorePortrait(c);
        if (!url && c.portrait) delete c.portrait;   // a new one taken, or none now: the old one goes
        if ((c.portrait || '') !== (before || '')) changed = true;
    }
    const want = all.filter((c) => c.portraitAt && !lorePortrait(c) && !flying.has(c.key + '@' + c.portraitAt));
    const at = new Map(want.map((c) => [c.key, c.portraitAt]));
    const keys = Array.from(at.keys());
    for (const k of keys) flying.add(k + '@' + at.get(k));
    for (let i = 0; i < keys.length; i += PAGE) {
        const page = keys.slice(i, i + PAGE);
        let res = null;
        try { res = await nuiCallback('lorePortraits', { keys: page }); } catch (e) { res = null; }
        const got = (res && res.ok && res.portraits) || {};
        for (const k of page) {
            flying.delete(k + '@' + at.get(k));
            const url = typeof got[k] === 'string' && got[k].indexOf('data:image/') === 0 ? got[k] : null;
            if (url) kept.set(k, { at: at.get(k), url });
        }
    }
    for (const c of all) {
        const before = c.portrait;
        lorePortrait(c);
        if ((c.portrait || '') !== (before || '')) changed = true;
    }
    if (changed) window.dispatchEvent(new CustomEvent('whip:loreportraits'));
    return changed;
}
