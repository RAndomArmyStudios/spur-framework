// ========================================
// DIRECTOR — the card search (right-click the grid; drop a wire on empty ground) and small menus
//
// A floating box at the cursor: type to filter, arrows to move, Enter or a click to pick, Esc to
// leave. Opened from a wire it lists only cards that wire can go to (from an output: cards with an
// input; from an input: cards with an output). The positioned element is never zoomed; the box
// inside is the surface root and wears --ui-scale (DESIGN.md, the One-Zoom Rule), so the box lands
// at the cursor whatever the scale.
// ========================================

import { escapeHtml } from '../utils.js';

export const CATEGORY_ORDER = ['events', 'goals', 'fail', 'dialog', 'world', 'player', 'lore', 'flow', 'scenario'];
export const CATEGORY_TITLE = {
    events: 'Events', goals: 'Goals', fail: 'Fail Conditions', dialog: 'Dialog', world: 'World', player: 'Player', lore: 'Lore',
    flow: 'Flow', scenario: 'Scenario',
};

let open = null;   // { el, close }

export function isSearchOpen() { return open !== null; }
export function closeSearch() { if (open) open.close(); }

function place(el, at) {
    document.body.appendChild(el);
    const box = el.firstElementChild.getBoundingClientRect();
    const x = Math.min(at.x, window.innerWidth - box.width - 8);
    const y = Math.min(at.y, window.innerHeight - box.height - 8);
    el.style.left = Math.max(8, x) + 'px';
    el.style.top = Math.max(8, y) + 'px';
}

/** Cards grouped in palette order, filtered by text. `order` and `titles` are another editor's own
 *  categories (the Systems Creator's); the Director's when left out. */
export function groupCards(cards, text, accept, order, titles) {
    const ORDER = order || CATEGORY_ORDER, TITLE = titles || CATEGORY_TITLE;
    const q = String(text || '').trim().toLowerCase();
    const groups = new Map();
    for (const def of cards.values()) {
        if (accept && !accept(def)) continue;
        if (q && !(def.title.toLowerCase().includes(q) || (def.desc || '').toLowerCase().includes(q)
            || def.type.toLowerCase().includes(q))) continue;
        const cat = def.category || 'scenario';
        if (!groups.has(cat)) groups.set(cat, []);
        groups.get(cat).push(def);
    }
    const all = [...ORDER, ...[...groups.keys()].filter((c) => !ORDER.includes(c))];
    const out = [];
    for (const cat of all) {
        const list = groups.get(cat);
        if (!list) continue;
        list.sort((a, b) => a.title.localeCompare(b.title));
        // A group of another resource's cards: the title it gives (categoryTitle), its colour (def.tint).
        const own = !TITLE[cat] && list[0];
        out.push({ cat, title: TITLE[cat] || (own && own.categoryTitle) || cat, tint: own ? own.tint : undefined, cards: list });
    }
    return out;
}

/**
 * @param {object} o  { at: {x, y}, cards: Map, accept?: fn(def), onPick: fn(def), title?, order?, titles? }
 */
export function openSearch(o) {
    closeSearch();
    const el = document.createElement('div');
    el.className = 'dr-float';
    el.innerHTML = '<div class="dr-search">'
        + `<div class="dr-search-title">${escapeHtml(o.title || 'Add a card')}</div>`
        + '<input class="dr-field dr-search-input" type="text" placeholder="Search cards" spellcheck="false">'
        + '<div class="dr-search-list"></div></div>';
    const input = el.querySelector('input');
    const listEl = el.querySelector('.dr-search-list');
    let flat = [], at = 0;

    const draw = () => {
        const groups = groupCards(o.cards, input.value, o.accept, o.order, o.titles);
        flat = [];
        const html = [];
        for (const g of groups) {
            html.push(`<div class="dr-search-cat kind-${escapeHtml(g.tint || g.cat)}">${escapeHtml(g.title)}</div>`);
            for (const def of g.cards) {
                html.push(`<div class="dr-search-row" data-i="${flat.length}"><b>${escapeHtml(def.title)}</b>`
                    + (def.desc ? `<span>${escapeHtml(def.desc)}</span>` : '') + '</div>');
                flat.push(def);
            }
        }
        if (!flat.length) html.push('<div class="dr-search-none">No card matches</div>');
        listEl.innerHTML = html.join('');
        at = Math.min(at, Math.max(0, flat.length - 1));
        mark();
    };
    const mark = () => {
        listEl.querySelectorAll('.dr-search-row').forEach((r) => r.classList.toggle('on', Number(r.dataset.i) === at));
        const on = listEl.querySelector('.dr-search-row.on');
        if (on) on.scrollIntoView({ block: 'nearest' });
    };
    const pick = (i) => {
        const def = flat[i];
        close();
        if (def) o.onPick(def);
    };
    const close = () => {
        if (!open || open.el !== el) return;
        open = null;
        document.removeEventListener('mousedown', outside, true);
        el.remove();
        if (o.onClose) o.onClose();
    };
    const outside = (e) => { if (!el.contains(e.target)) close(); };

    input.addEventListener('input', () => { at = 0; draw(); });
    input.addEventListener('keydown', (e) => {
        if (e.key === 'ArrowDown') { at = Math.min(flat.length - 1, at + 1); mark(); e.preventDefault(); }
        else if (e.key === 'ArrowUp') { at = Math.max(0, at - 1); mark(); e.preventDefault(); }
        else if (e.key === 'Enter') { pick(at); e.preventDefault(); }
        else if (e.key === 'Escape') { close(); e.preventDefault(); }
        e.stopPropagation();
    });
    listEl.addEventListener('mousedown', (e) => {
        const row = e.target.closest('.dr-search-row');
        if (row) { e.preventDefault(); pick(Number(row.dataset.i)); }
    });
    listEl.addEventListener('mousemove', (e) => {
        const row = e.target.closest('.dr-search-row');
        if (row && Number(row.dataset.i) !== at) { at = Number(row.dataset.i); mark(); }
    });

    open = { el, close };
    draw();
    place(el, o.at);
    document.addEventListener('mousedown', outside, true);
    input.focus();
}

/**
 * A small menu of actions at the cursor.
 * @param {object} o  { at: {x, y}, items: [{ label, danger?, run: fn }] }
 */
export function openMenu(o) {
    closeSearch();
    const el = document.createElement('div');
    el.className = 'dr-float';
    el.innerHTML = '<div class="dr-menu">' + o.items.map((it, i) =>
        `<div class="dr-menu-row${it.danger ? ' danger' : ''}" data-i="${i}">${escapeHtml(it.label)}</div>`).join('') + '</div>';
    const close = () => {
        if (!open || open.el !== el) return;
        open = null;
        document.removeEventListener('mousedown', outside, true);
        el.remove();
    };
    const outside = (e) => { if (!el.contains(e.target)) close(); };
    el.addEventListener('mousedown', (e) => {
        const row = e.target.closest('.dr-menu-row');
        if (!row) return;
        e.preventDefault();
        const it = o.items[Number(row.dataset.i)];
        close();
        if (it) it.run();
    });
    open = { el, close };
    place(el, o.at);
    document.addEventListener('mousedown', outside, true);
}
