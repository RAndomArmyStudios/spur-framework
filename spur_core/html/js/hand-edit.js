// ========================================
// The hand position editor's item list (tools/hand_edit.lua)
//
// Down the left while the editor is up: every item with its picture, name, key and resource, found by name or key,
// filtered by resource and by whether it has a hand position of its own. A pick goes to the editor, which asks
// first (handEditAsk) when the item on screen has changes not saved: Cancel, Save & swap, Disregard & swap. Over the
// list, the item's "Allow player walk animation" (handEditWalk), shown by the walking poses, and "Picked up with
// both hands" (handEditGrab): both saved with its hands.
//
// Typing in the search box takes the game's keys away (handEditTyping) and gives them back when it lets go, so an
// H or an Esc typed there is a letter, not the next pose or the way out.
// ========================================

import { NuiRouter } from './router.js';
import { nuiCallback, itemImageUrl, escapeHtml as e } from './utils.js';

const SEARCH_ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/></svg>';
const SETS = [{ value: '', label: 'All' }, { value: 'set', label: 'Set' }, { value: 'unset', label: 'Not set' }];

const root = document.createElement('div');
root.id = 'hand-edit';
root.innerHTML = `
  <aside class="he-col">
    <div class="he-head">
      <small>Hand position</small>
      <div class="he-title"><b>Items</b><span class="he-count"></span></div>
    </div>
    <button class="he-walk" data-toggle="walk" type="button" role="switch" aria-checked="false">
      <span class="he-walk-text"><b>Allow player walk animation</b><small></small></span>
      <span class="he-switch" aria-hidden="true"></span>
    </button>
    <button class="he-walk he-grab" data-toggle="grab" type="button" role="switch" aria-checked="false">
      <span class="he-walk-text"><b>Picked up with both hands</b><small></small></span>
      <span class="he-switch" aria-hidden="true"></span>
    </button>
    <div class="dr-search-box">${SEARCH_ICON}<input class="dr-field he-search" type="text" placeholder="Name, key or resource" spellcheck="false" aria-label="Search items"></div>
    <select class="dr-field he-res" aria-label="Resource"></select>
    <div class="dr-seg he-set" role="group" aria-label="Hand position">
      ${SETS.map((s) => `<button class="dr-seg-key" type="button" data-set="${s.value}">${s.label}</button>`).join('')}
    </div>
    <div class="he-list" role="listbox" aria-label="Items"></div>
  </aside>
  <div class="he-ask" hidden>
    <div class="he-ask-card" role="alertdialog" aria-modal="true" aria-labelledby="he-ask-title">
      <b id="he-ask-title">Swap and disregard changes?</b>
      <p class="he-ask-text"></p>
      <div class="he-ask-btns">
        <button class="dr-btn ghost" type="button" data-answer="cancel">Cancel</button>
        <button class="dr-btn" type="button" data-answer="save">Save &amp; swap</button>
        <button class="dr-btn danger" type="button" data-answer="discard">Disregard &amp; swap</button>
      </div>
    </div>
  </div>`;
document.body.appendChild(root);

const els = {
    walk: root.querySelector('[data-toggle="walk"]'),
    walkNote: root.querySelector('[data-toggle="walk"] small'),
    grab: root.querySelector('[data-toggle="grab"]'),
    grabNote: root.querySelector('[data-toggle="grab"] small'),
    count: root.querySelector('.he-count'),
    search: root.querySelector('.he-search'),
    res: root.querySelector('.he-res'),
    set: root.querySelector('.he-set'),
    list: root.querySelector('.he-list'),
    ask: root.querySelector('.he-ask'),
    askText: root.querySelector('.he-ask-text'),
};

let items = [];        // [{ key, name, resource, img, set }], by name (server/item_holds.lua)
let current = null;    // the item on screen
let waiting = null;    // the item picked, until the editor says which is on screen
let query = '';
let resFilter = '';    // kept between openings: going through one resource's items is the usual way
let setFilter = '';

function shown() {
    return items.filter((it) => {
        if (resFilter && it.resource !== resFilter) return false;
        if (setFilter === 'set' && !it.set) return false;
        if (setFilter === 'unset' && it.set) return false;
        if (!query) return true;
        return it.name.toLowerCase().includes(query) || it.key.toLowerCase().includes(query)
            || it.resource.toLowerCase().includes(query);
    });
}

function renderList() {
    const list = shown();
    els.count.textContent = list.length === items.length ? String(items.length) : `${list.length} of ${items.length}`;
    els.list.innerHTML = list.length
        ? list.map((it) => {
            const on = it.key === current ? ' on' : it.key === waiting ? ' waiting' : '';
            return `<button class="he-row${on}" type="button" role="option" aria-selected="${it.key === current}" data-key="${e(it.key)}">`
                + `<img alt="" data-item-img="" data-item-key="${e(it.key)}" src="${e(itemImageUrl(it.key, it.img))}">`
                + `<span class="he-row-text"><b>${e(it.name)}</b><small>${e(it.key)} · ${e(it.resource)}</small></span>`
                + (it.set ? '<span class="he-row-set">Set</span>' : '')
                + '</button>';
        }).join('')
        : `<div class="he-empty">${query || resFilter || setFilter ? 'No item matches' : 'No items'}</div>`;
}

function renderFilters() {
    const resources = [...new Set(items.map((it) => it.resource))].sort();
    if (resFilter && !resources.includes(resFilter)) resFilter = '';
    els.res.innerHTML = '<option value="">Every resource</option>'
        + resources.map((r) => `<option value="${e(r)}">${e(r)}</option>`).join('');
    els.res.value = resFilter;
    for (const b of els.set.children) b.classList.toggle('on', b.dataset.set === setFilter);
}

function scrollToCurrent() {
    const row = els.list.querySelector('.he-row.on');
    if (row) row.scrollIntoView({ block: 'center' });
}

function closeAsk() {
    els.ask.hidden = true;
}

/** The item on screen's "Allow player walk animation": off, the give walk (the trash bag) while it is held out. */
let walkOn = false;
function renderWalk() {
    els.walk.classList.toggle('on', walkOn);
    els.walk.setAttribute('aria-checked', String(walkOn));
    els.walkNote.textContent = walkOn ? 'Held out with their own walk' : 'Held out with the trash-bag walk';
}

/** The item on screen's grab: off, picked up off the ground with the hand on its side. */
let grabOn = false;
function renderGrab() {
    els.grab.classList.toggle('on', grabOn);
    els.grab.setAttribute('aria-checked', String(grabOn));
    els.grabNote.textContent = grabOn ? 'For something big' : 'One hand, the side it is on';
}

// ---- the editor's side ----

NuiRouter.register('handEditOpen', (d) => {
    items = (Array.isArray(d.items) ? d.items : []).map((it) => ({
        key: String(it.key), name: String(it.name || it.key), resource: String(it.resource || 'spur_core'),
        img: it.img || null, set: it.set === true,
    }));
    current = d.current || null;
    waiting = null;
    query = '';
    els.search.value = '';
    walkOn = d.walk === true;
    renderWalk();
    grabOn = d.grab === true;
    renderGrab();
    closeAsk();
    renderFilters();
    renderList();
    root.classList.add('open');
    scrollToCurrent();
});

NuiRouter.register('handEditClose', () => {
    root.classList.remove('open');
    closeAsk();
    if (document.activeElement === els.search) els.search.blur();
    items = [];
    els.list.innerHTML = '';
});

// Which item is on screen now: the one picked, or the one kept (the swap refused or stopped).
NuiRouter.register('handEditCurrent', (d) => {
    current = d.key || current;
    waiting = null;
    renderList();
});

NuiRouter.register('handEditSaved', (d) => {
    const it = items.find((x) => x.key === d.key);
    if (it) it.set = true;
    renderList();
});

// The toggle as the editor has it: the item swapped, or a change it took (or kept back while busy).
NuiRouter.register('handEditWalk', (d) => {
    walkOn = d.on === true;
    renderWalk();
});
NuiRouter.register('handEditGrab', (d) => {
    grabOn = d.on === true;
    renderGrab();
});

NuiRouter.register('handEditAsk', (d) => {
    els.askText.textContent = `${d.from || 'This item'} has changes that are not saved. Swap to ${d.to || 'the next item'} anyway?`;
    els.ask.hidden = false;
    els.ask.querySelector('[data-answer="save"]').focus();
});

// ---- the page's side ----

els.list.addEventListener('click', (ev) => {
    const row = ev.target.closest('.he-row');
    if (!row || !els.ask.hidden) return;
    const key = row.dataset.key;
    if (key === current) return;
    const it = items.find((x) => x.key === key);
    waiting = key;
    renderList();
    nuiCallback('handEditPick', { itemKey: key, name: it ? it.name : key });
});

els.ask.addEventListener('click', (ev) => {
    const b = ev.target.closest('[data-answer]');
    if (!b) return;
    closeAsk();
    if (b.dataset.answer === 'cancel') { waiting = null; renderList(); }
    nuiCallback('handEditAnswer', { choice: b.dataset.answer });
});

els.walk.addEventListener('click', () => {
    if (!els.ask.hidden) return;
    walkOn = !walkOn;
    renderWalk();
    els.walk.blur();
    nuiCallback('handEditWalk', { on: walkOn });
});
els.grab.addEventListener('click', () => {
    if (!els.ask.hidden) return;
    grabOn = !grabOn;
    renderGrab();
    els.grab.blur();
    nuiCallback('handEditGrab', { on: grabOn });
});

els.search.addEventListener('input', () => {
    query = els.search.value.trim().toLowerCase();
    renderList();
});
els.search.addEventListener('focus', () => nuiCallback('handEditTyping', { on: true }));
els.search.addEventListener('blur', () => nuiCallback('handEditTyping', { on: false }));

// Let go of the dropdown once chosen: focused, it would keep the arrow keys and R from the editor.
els.res.addEventListener('change', () => { resFilter = els.res.value; els.res.blur(); renderList(); });

els.set.addEventListener('click', (ev) => {
    const b = ev.target.closest('[data-set]');
    if (!b) return;
    setFilter = b.dataset.set;
    for (const x of els.set.children) x.classList.toggle('on', x === b);
    renderList();
});

// Before Move's own keys (js/ov-panel.js, on the window too): Esc with the question up is Cancel, not the way out of
// the editor, and Esc in the search box lets go of it (the next Esc is the way out).
window.addEventListener('keydown', (ev) => {
    if (!root.classList.contains('open')) return;
    if (!els.ask.hidden) {
        if (ev.key === 'Escape' || ev.key === 'Backspace') {
            ev.preventDefault();
            ev.stopImmediatePropagation();
            closeAsk();
            waiting = null;
            renderList();
            nuiCallback('handEditAnswer', { choice: 'cancel' });
        }
        return;
    }
    if (document.activeElement === els.search && ev.key === 'Escape') {
        ev.preventDefault();
        ev.stopImmediatePropagation();
        els.search.blur();
    }
}, true);
