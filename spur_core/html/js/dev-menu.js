import { NuiRouter } from './router.js';
import { nuiCallback } from './utils.js';

// ========================================
// DEV MENU — /w Tool Selector (NUI)
// Keyboard-only, no NUI focus — the Lua thread in tools/core.lua drives selection and
// this module only renders. Entries may be tools ({name, active, kind, desc}) or group
// headers ({sep = 'Label'}); headers are display-only and the Lua side never parks the
// selection index on one.
//
// THE HOUSE LOOK. A row ends in what the tool IS: a switch for one that
// stays on (kind 'toggle'), a run mark for a one-off ('run'), a chevron for one that
// opens a screen ('open', Admin Panel and every resource's page). Under the list, the picked
// tool's name and what it does.
//
// PAGES. A resource's page (RegisterDevPage, tools/core.lua) swaps in for the list inside the same
// panel: its title, the trail above it ("Dev Tools"), the way back as its first row (kind 'back'),
// and its rows, which may include notes (kind 'note': read, never picked). Each message names its
// view; a new view slides in from the side the message says (`dir`). A page's row may lead with a
// glyph (`icon`, a key of js/glyphs.js): an icon list, an objective's mark.
// ========================================

let devMenuOpen = false;
let _dmItems = [];    // cached per-entry: { el, active, isSep, isNote, sep, sw, name, desc }
let _dmDescName = null, _dmDescText = null;
let _dmList = null;   // the .dm-list of the panel on screen
let _dmMore = null;   // the rows under developer mode's switch, in one box that slides (_dmSlide)
let _dmView = '';     // which view is drawn: '' for the tool list, else the page's (tools/core.lua menuMessage)
let _dmTitle = null, _dmTitleName = null, _dmCrumb = null;

// How long the rows under the switch take to slide open or shut.
const DM_SLIDE_MS = 320;

// Fixed icons, no data.
const RUN_MARK = '<svg class="dm-mark" viewBox="0 0 18 18" fill="none" stroke="currentColor" stroke-width="2"'
    + ' stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M14.5 4v5.5a2 2 0 0 1-2 2H4"/>'
    + '<path d="M7 8.5L4 11.5l3 3"/></svg>';
const OPEN_MARK = '<svg class="dm-mark" viewBox="0 0 18 18" fill="none" stroke="currentColor" stroke-width="2.2"'
    + ' stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M7 4l5 5-5 5"/></svg>';
// The way back on a page leads with the open chevron turned round.
const BACK_MARK = '<svg class="dm-lead" viewBox="0 0 18 18" fill="none" stroke="currentColor" stroke-width="2.2"'
    + ' stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M11 4L6 9l5 5"/></svg>';
// DEVELOPER MODE'S SWITCH leads with the HUD mark's own glyph, the terminal prompt
// (server/stats.lua ICONS.developer), so the switch and the mark it puts on the HUD read as one thing.
const DEV_MARK = '<svg class="dm-devmark" viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor"'
    + ' d="M2.97 6.13 5.23 3.87 13.36 12l-8.13 8.13-2.26-2.26L8.84 12z M14.1 16.9h7v3.2h-7z"/></svg>';

function devMenuShow(data) {
    devMenuOpen = true;
    _dmItems = [];
    _dmView = data.view || '';
    const overlay = document.getElementById('dev-menu-overlay');
    overlay.innerHTML = '';
    overlay.style.display = 'block';
    _devMenuBuild(overlay, data);
    _dmEdgesSoon();
}

/** THE LIST'S EDGES: one with more past it fades out (css .dm-more-above / -below). Asked whenever the list
 *  may have moved or changed size: a scroll, a pick, rows come or gone, a slide ended. */
function _dmEdges() {
    const list = _dmList;
    if (!list) return;
    // (A scroll can stop a fraction of a pixel short of either end, zoomed.)
    const past = list.scrollHeight - list.clientHeight - list.scrollTop;
    list.classList.toggle('dm-more-above', list.scrollTop > 2);
    list.classList.toggle('dm-more-below', past > 2);
}
function _dmEdgesSoon() { requestAnimationFrame(_dmEdges); }

function devMenuUpdate(data) {
    if (!devMenuOpen) return;
    _dmEdgesSoon();
    const tools = data.tools;
    // ANOTHER VIEW: a page opened, a level of one, or back to the list. Swapped in inside the panel.
    const view = data.view || '';
    if (view !== _dmView) {
        _dmView = view;
        _dmSwap(data, data.dir);
        return;
    }
    // Fast path: just update classes on existing items (the same rows, each still the same kind of row)
    if (_dmItems.length === tools.length && _dmSameKinds(tools)) {
        _devMenuPatch(tools, data.index);
        return;
    }
    // THE ROWS CHANGED: developer mode went on (the switch and every tool) or off (the switch alone).
    // ONE MENU, NOT A NEW ONE: the switch stays where it is, and what is under it slides open or shut.
    // Rebuilding the panel replayed its entrance, and the menu looked like it closed and opened again.
    const keep = _dmSameRows(tools);
    if (keep === _dmItems.length && tools.length > keep) {
        _dmItems.length = keep;
        _dmReveal(tools, keep, data.index);
        _devMenuPatch(tools, data.index);
    } else if (keep === 1 && tools.length === 1 && tools[0].dev && _dmMore) {
        _dmItems.length = keep;
        const going = _dmMore;
        _dmMore = null;
        _devMenuPatch(tools, data.index);
        _dmSlide(going, false, () => going.remove());
    } else {
        // Any other change (a page came or went, a page's rows grew or shrank): the list drawn again in
        // place, the panel kept, so it does not look like the menu closed and opened again.
        _dmSwap(data, null);
    }
}

function devMenuHide() {
    devMenuOpen = false;
    document.getElementById('dev-menu-overlay').style.display = 'none';
}

/** What a row is drawn as: its end mark (or none), its glyph, and whether it can be picked. */
function _dmKindOf(tool) {
    if (tool.sep !== undefined) return 'sep';
    return (tool.dev ? 'dev:' : '') + (tool.icon ? 'icon=' + tool.icon + ':' : '') + (tool.kind || 'toggle');
}

/** A row's glyph (`icon`, a key of js/glyphs.js) as markup, or '' when it names none the table has. Only
 *  the table's own markup goes in, never the key. */
function _dmGlyph(tool) {
    const glyphs = (window.WhipGlyphs && window.WhipGlyphs.glyphs) || {};
    if (typeof tool.icon !== 'string' || !Object.prototype.hasOwnProperty.call(glyphs, tool.icon)) return '';
    return '<span class="dm-glyph" aria-hidden="true">' + glyphs[tool.icon] + '</span>';
}

/** Is every row still drawn as the same kind of row? A page may turn a row into another kind (a note
 *  into a button) without the count changing; patching would leave the old look. */
function _dmSameKinds(tools) {
    for (let i = 0; i < tools.length; i++) {
        if (!_dmItems[i] || _dmItems[i].kind !== _dmKindOf(tools[i])) return false;
    }
    return true;
}

/** How many rows from the top are the same rows as before (the same switch, the same header). */
function _dmSameRows(tools) {
    let n = 0;
    while (n < tools.length && n < _dmItems.length) {
        const was = _dmItems[n], now = tools[n];
        if (was.isSep !== (now.sep !== undefined)) break;
        if (was.isSep ? was.sep !== now.sep : was.name !== now.name) break;
        n++;
    }
    return n;
}

/** The rows from `from` on, in a box under the switch that slides open. They come in one after another
 *  from the top of the box, as the menu's rows do when it opens. */
function _dmReveal(tools, from, index) {
    const more = document.createElement('div');
    more.className = 'dm-more';
    for (let i = from; i < tools.length; i++) more.appendChild(_dmRow(tools[i], i, index, i - from));
    // Everything under the switch stays in one box (the one that slides shut): new rows under rows
    // already there go inside it.
    if (_dmMore) {
        _dmMore.appendChild(more);
    } else {
        _dmList.appendChild(more);
        _dmMore = more;
    }
    _dmSlide(more, true);
}

/** Slide a box open to its rows' height, or shut to nothing. From whatever height it has now, so a
 *  switch flipped back mid-slide turns round where it is. Measured, not a grid-row transition: CEF 103
 *  cannot animate those. Open, it is left to its rows' own height (the list's height cap still holds). */
function _dmSlide(el, open, done) {
    const token = (el._dmSlide || 0) + 1;
    el._dmSlide = token;
    const finish = () => {
        if (el._dmSlide !== token) return;
        el.classList.remove('dm-sliding');
        if (open) el.style.height = '';
        if (done) done();
        _dmEdgesSoon();
    };
    if (window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
        if (!open) el.style.height = '0px';
        finish();
        return;
    }
    el.style.height = (open && !el.classList.contains('dm-sliding') ? 0 : el.offsetHeight) + 'px';
    el.classList.add('dm-sliding');
    void el.offsetHeight;   // the start height drawn, so the change below is a transition
    el.style.height = (open ? el.scrollHeight : 0) + 'px';
    setTimeout(finish, DM_SLIDE_MS + 40);
}

// Full build — only on first show
function _devMenuBuild(overlay, data) {
    const panel = document.createElement('div');
    panel.className = 'dm-panel';

    // Title block — the name alone on the tool list. A subtitle was tried here (a live tool count)
    // and removed: the list already shows what is running, beside the thing running it. On a page,
    // the trail above the name says where it is ("Dev Tools").
    _dmTitle = document.createElement('div');
    _dmTitle.className = 'dm-title';

    _dmCrumb = document.createElement('div');
    _dmCrumb.className = 'dm-crumb';
    _dmTitle.appendChild(_dmCrumb);

    _dmTitleName = document.createElement('div');
    _dmTitleName.className = 'dm-title-name';
    _dmTitle.appendChild(_dmTitleName);
    _dmSetTitle(data);

    panel.appendChild(_dmTitle);

    const list = document.createElement('div');
    list.className = 'dm-list';
    _dmList = list;
    list.addEventListener('scroll', _dmEdges);
    _dmFill(list, data);

    panel.appendChild(list);

    // What the picked tool does.
    const desc = document.createElement('div');
    desc.className = 'dm-desc';
    _dmDescName = document.createElement('div');
    _dmDescName.className = 'dm-desc-name';
    _dmDescText = document.createElement('div');
    _dmDescText.className = 'dm-desc-text';
    desc.appendChild(_dmDescName);
    desc.appendChild(_dmDescText);
    panel.appendChild(desc);
    _devMenuDescribe(data.index);

    // No keyboard hint footer — removed by request. It was the only thing on screen
    // naming the controls (arrows, Enter, Esc); this overlay takes no NUI focus, so
    // there is no cursor or click target advertising them either.

    overlay.appendChild(panel);
}

/** The title block for this view: the name, and on a page the trail above it. */
function _dmSetTitle(data) {
    _dmTitleName.textContent = data.title || 'Dev Tools';
    const crumb = data.crumb || '';
    _dmCrumb.textContent = crumb;
    _dmCrumb.style.display = crumb ? '' : 'none';
}

/** The rows of a view into the list (emptied first by the caller). */
function _dmFill(list, data) {
    const tools = data.tools, index = data.index;

    // The tool list's first group gets a header too, so every tool sits under a name. Drawn here,
    // not sent from Lua: a header there would be entry 1, where the menu opens. Not over developer
    // mode's switch, which stands alone at the top (its "Tools" header comes from Lua, under it), and
    // not on a page, which opens on its way back.
    if (!(data.view || '') && tools.length && tools[0].sep === undefined && !tools[0].dev) {
        const first = document.createElement('div');
        first.className = 'dm-sep';
        first.textContent = 'Tools';
        list.appendChild(first);
    }

    _dmItems = [];
    _dmMore = null;
    // Under developer mode's switch, every other row goes in the box that slides shut when it goes off.
    let into = list;
    for (let i = 0; i < tools.length; i++) {
        if (i === 1 && tools[0].dev) {
            _dmMore = document.createElement('div');
            _dmMore.className = 'dm-more';
            list.appendChild(_dmMore);
            into = _dmMore;
        }
        into.appendChild(_dmRow(tools[i], i, index, i));
    }
}

/** ANOTHER VIEW IN THE SAME PANEL: the title and the rows swapped, sliding in from the right going
 *  into something (`dir` 'fwd'), from the left coming back ('back'), or simply there (null: the same
 *  view with rows come or gone). The panel stays, so nothing looks like it closed. */
function _dmSwap(data, dir) {
    if (!_dmList) return;
    _dmSetTitle(data);
    const list = _dmList;
    list.innerHTML = '';
    list.classList.remove('dm-in-fwd', 'dm-in-back', 'dm-still');
    _dmTitle.classList.remove('dm-in-fwd', 'dm-in-back');
    void list.offsetWidth;   // the classes off for a frame, so the entrance plays again
    if (dir === 'fwd' || dir === 'back') {
        list.classList.add('dm-in-' + dir);
        _dmTitle.classList.add('dm-in-' + dir);
    } else {
        list.classList.add('dm-still');
    }
    _dmFill(list, data);
    list.scrollTop = 0;
    const picked = _dmItems[data.index];
    if (picked && picked.el) picked.el.scrollIntoView({ block: 'nearest' });
    _devMenuDescribe(data.index);
}

/** One row (a tool, a page's row or note, or a group header), cached in _dmItems at `i`. `stagger` is
 *  its place in the entrance: one row after another from the top of what is coming in. */
function _dmRow(tool, i, index, stagger) {
    if (tool.sep !== undefined) {
        const sep = document.createElement('div');
        sep.className = 'dm-sep';
        sep.textContent = tool.sep;
        sep.style.setProperty('--dm-i', stagger);
        _dmItems[i] = { el: sep, active: false, isSep: true, sep: tool.sep, kind: 'sep' };
        return sep;
    }

    // A NOTE: a line of a page's to read (what is loaded, what state it is in). The selection never
    // lands on one (tools/core.lua skips them), so it looks like nothing that can be picked.
    if (tool.kind === 'note') {
        const note = document.createElement('div');
        note.className = 'dm-note';
        note.style.setProperty('--dm-i', stagger);
        note.insertAdjacentHTML('beforeend', _dmGlyph(tool));
        const text = document.createElement('span');
        text.className = 'dm-name';
        text.textContent = tool.name;
        note.appendChild(text);
        _dmItems[i] = { el: note, active: false, isSep: false, isNote: true, sw: null, nameEl: text,
                        name: tool.name, title: '', desc: tool.desc || '', kind: 'note' };
        return note;
    }

    const item = document.createElement('div');
    item.className = 'dm-item' + (i === index ? ' dm-selected' : '')
        + (tool.dev ? ' dm-devrow' + (tool.active ? ' dm-dev-on' : '') : '')
        + (tool.kind === 'back' ? ' dm-back' : '');
    // The staggered entrance delay — one CSS rule reads this var, replacing the
    // forty hand-written nth-child rules the old stylesheet carried.
    item.style.setProperty('--dm-i', stagger);
    // No mouse reaches the menu (no NUI focus), but a tool pressing it by its words does (js/page-tools.js reads
    // data-probe-press rows): the press picks the row as Enter would (tools/core.lua, devMenuPick). The view goes
    // with it, so a press on a list that has since changed is ignored.
    item.setAttribute('role', 'menuitem');
    item.dataset.probePress = '1';
    item.addEventListener('click', () => nuiCallback('devMenuPick', { index: i + 1, view: _dmView }));
    if (tool.dev) item.insertAdjacentHTML('beforeend', DEV_MARK);
    if (tool.kind === 'back') item.insertAdjacentHTML('beforeend', BACK_MARK);
    item.insertAdjacentHTML('beforeend', _dmGlyph(tool));

    const name = document.createElement('span');
    name.className = 'dm-name';
    name.textContent = tool.name;
    item.appendChild(name);

    let sw = null;
    if (tool.kind === 'run') {
        item.insertAdjacentHTML('beforeend', RUN_MARK);
    } else if (tool.kind === 'open') {
        item.insertAdjacentHTML('beforeend', OPEN_MARK);
    } else if (tool.kind !== 'back') {
        sw = document.createElement('span');
        sw.className = 'dm-switch' + (tool.active ? ' on' : '');
        item.appendChild(sw);
    }

    _dmItems[i] = { el: item, active: tool.active, isSep: false, sw, nameEl: name, name: tool.name,
                    title: tool.title || '', desc: tool.desc || '', kind: _dmKindOf(tool) };
    return item;
}

/** The line under the list: the picked tool and what it does. */
function _devMenuDescribe(index) {
    const cached = _dmItems[index];
    if (!_dmDescName || !cached || cached.isSep) return;
    // A row may head its line with a question of its own (developer mode: "Enable developer mode?").
    _dmDescName.textContent = cached.title || cached.name;
    _dmDescText.textContent = cached.desc;
}

// Patch — update selection + switches without rebuilding DOM
function _devMenuPatch(tools, index) {
    for (let i = 0; i < tools.length; i++) {
        const cached = _dmItems[i];
        const tool = tools[i];
        if (cached.isSep) continue;

        // Update selected class; keep the selection visible inside the scroll cap.
        const shouldSelect = (i === index);
        const isSelected = cached.el.classList.contains('dm-selected');
        if (shouldSelect && !isSelected) {
            cached.el.classList.add('dm-selected');
            cached.el.scrollIntoView({ block: 'nearest' });
            _devMenuDescribe(i);
        } else if (!shouldSelect && isSelected) {
            cached.el.classList.remove('dm-selected');
        }

        // A switch follows its tool (a run or open row has none to light).
        if (tool.active !== cached.active) {
            cached.active = tool.active;
            if (cached.sw) cached.sw.classList.toggle('on', !!tool.active);
            if (tool.dev) cached.el.classList.toggle('dm-dev-on', !!tool.active);
        }
        // A row's words can change in place (developer mode's line reads differently on and off).
        if (tool.name !== cached.name || (tool.title || '') !== cached.title || (tool.desc || '') !== cached.desc) {
            cached.name = tool.name;
            cached.title = tool.title || '';
            cached.desc = tool.desc || '';
            cached.nameEl.textContent = tool.name;
            if (shouldSelect) _devMenuDescribe(i);
        }
    }
}


// ROUTER REGISTRATION — see router.js's header.
NuiRouter.register('devMenuShow', (d) => devMenuShow(d));
NuiRouter.register('devMenuUpdate', (d) => devMenuUpdate(d));
NuiRouter.register('devMenuHide', () => devMenuHide());
