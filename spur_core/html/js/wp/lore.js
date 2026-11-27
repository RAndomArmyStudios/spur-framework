// ========================================
// /whip GROUP — Director → Lore characters: each one's dashboard
//
// The story's named people (server/director/lore.lua). The list on the left; on the right, the one picked, as a
// profile: their picture large over their name, ped and notes, and three tabs beside it:
//
//   Details       name, bank name, ped, notes: typed straight in
//   Audio         their voice lines (server/director/lore_voice.lua): each line's variants (a recording's link and a
//                 subtitle), Play hears one at you
//   Interactions  what they are part of (spur_core:director:loreActivity): the scenarios that use them, their
//                 phone's texts and calls, what they have paid players
//
// Details and Audio are ONE DRAFT: the bar under them says when it differs from what is saved, and Save writes both.
// The picture saves on its own: Edit picture turns it into its frame (drag it, zoom with the slider) with Save under
// it. New lore character opens an empty one on Details, and Create makes it.
//
// THEIR LOOK: a GTA ped (its spawn name), or one MADE IN THE CHARACTER EDITOR: Male or Female puts the builder in
// the editor wearing a new look (a new one is made first), Edit look in the one they have, and Copy my look gives them
// the builder's own character as it is now, no editor. Either way a headshot of the look is kept with it, which is
// their face wherever they have no picture link (lore-faces.js).
// Requests go through tools/panel_sections/director.lua (wpDirector), as the rest of the Director's do.
// ========================================

import { WhipPanel, WP } from '../whip-panel.js';
import { nuiCallback, pedImageUrl } from '../utils.js';
import { lorePortrait, primeLorePortraits } from '../lore-faces.js';
import { dateTime, ago, money, plural, phoneNumber } from './format.js';

const SEC = 'directorLore';
const NEW = '\u0000new';   // st.sel while a new one is being made
const KEY_OK = /^[A-Za-z0-9_-]{2,64}$/;

/** Set by the Director's own pages (wp/director.js): show a scenario on its Scenarios page. */
export const loreLinks = { openScenario: null };

const st = {
    data: null,      // the 'lore' answer: { lore, ready, admin, pictureLinks, voice }
    search: '',
    sel: null,       // the key shown, NEW, or null
    draft: null,     // Details + Audio as typed: { isNew, key, name, model, bankName, notes, picture, frame, voice }
    tab: 'details',
    pic: null,       // the picture being edited: { url, frame }, else null
    acts: {},        // [key] = { data, why } once read: the Interactions tab's answer
    test: null,      // { key, endsAt } while this builder's test NPC is out (spur_core:director:loreTest)
    turn: {},        // [line] = the variant Say played last (they take turns, as in the world)
};
const els = {};
let tabs = null;

async function call(op, args) {
    const r = await nuiCallback('wpDirector', { op, args: args || {} });
    if (r && r.ok) return { ok: true, data: r.data || {} };
    return { ok: false, why: (r && r.why) || 'No answer from the server' };
}

const arr = (v) => (Array.isArray(v) ? v : (v && typeof v === 'object' ? Object.values(v) : []));
const slug = (text) => String(text || '').toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 40);
const clampN = (n, lo, hi) => Math.max(lo, Math.min(hi, n));
const trim = (s) => String(s || '').trim();

// Fixed icons (no data in them), one stroke.
const ICON = {
    play: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M8 5.6v12.8a1 1 0 0 0 1.53.85l10.2-6.4a1 1 0 0 0 0-1.7L9.53 4.75A1 1 0 0 0 8 5.6z"/></svg>',
    remove: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M7 7l10 10M17 7L7 17"/></svg>',
    camera: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M4 8.6A1.6 1.6 0 0 1 5.6 7h2.1l1.6-2.2h5.4L16.3 7h2.1A1.6 1.6 0 0 1 20 8.6v8.8a1.6 1.6 0 0 1-1.6 1.6H5.6A1.6 1.6 0 0 1 4 17.4z"/><circle cx="12" cy="12.8" r="3.4"/></svg>',
    minus: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M6 12h12"/></svg>',
    plus: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M12 6v12M6 12h12"/></svg>',
};

function icon(name) {
    const s = WP.el('span', 'wl-ico');
    s.innerHTML = ICON[name];
    return s;
}

/** A small button that is only an icon: its words are its label for a screen reader and its tooltip. */
function iconBtn(name, label, kind) {
    const b = WP.el('button', 'wp-btn wp-btn-sm wl-icon-btn' + (kind ? ' wp-btn-' + kind : ''));
    b.type = 'button';
    b.title = label;
    b.setAttribute('aria-label', label);
    b.appendChild(icon(name));
    return b;
}

// ============================================================
// Pictures: a link, framed
// ============================================================

/** A picture's FRAMING ({ x, y, z }: the point of it kept in view, 0-100 across and down, and the zoom, 1-3) as an
 *  img's style. The phone draws a contact's picture the same way (whip_phone kit.avatar), and the Scenarios map's
 *  mark card frames a lore NPC's with it (wp/director.js). */
export function frameStyle(img, fr) {
    const x = fr ? fr.x : 50, y = fr ? fr.y : 50, z = fr ? fr.z : 1;
    img.style.objectPosition = `${x}% ${y}%`;
    img.style.transformOrigin = `${x}% ${y}%`;
    img.style.transform = `scale(${z})`;
}
const frame0 = () => ({ x: 50, y: 50, z: 1 });
const frameCopy = (fr) => (fr ? { x: +fr.x, y: +fr.y, z: +fr.z } : frame0());

/** Why a picture link would be refused, or null (the server's DirectorLore.pictureProblem decides; this says it
 *  sooner): it starts with an accepted link and is a plain address after it. */
function pictureProblem(url) {
    url = trim(url);
    if (!url) return null;
    const starts = arr(st.data && st.data.pictureLinks);
    if (!starts.length) return 'Pictures are switched off (Config: Picture links accepted)';
    const start = starts.find((x) => url.startsWith(x));
    if (!start) return `Only links starting with ${starts.join(' or ')} are accepted`;
    const rest = url.slice(start.length);
    if (!rest || !/^[A-Za-z0-9\-._/]+$/.test(rest) || rest.includes('..')) return 'That link is not a picture\'s address';
    return null;
}

/** Their initials: the first and last word's first letters. */
function initials(name) {
    const words = trim(name || '?').split(/\s+/);
    return ((words[0] || '?')[0] + (words.length > 1 ? words[words.length - 1][0] : '')).toUpperCase();
}

/** Their face: their picture, framed, when they have one; else their headshot (a look made in the character
 *  editor); else their GTA ped's, closed in on the head; else their initials. `cls` sizes it (wl-face-xl: the
 *  profile's). */
function loreFace(c, cls) {
    const el = WP.el('span', 'wp-avatar wl-face' + (cls ? ' ' + cls : ''));
    el.appendChild(WP.el('span', 'wp-avatar-initials', initials(c.name)));
    const face = c.picture && !pictureProblem(c.picture);
    const shot = !face && (c.portrait || lorePortrait(c));
    const src = face ? c.picture : shot || (c.model && !c.hasLook ? pedImageUrl(c.model) : '');
    if (src) {
        const img = document.createElement('img');
        img.alt = '';
        img.draggable = false;
        if (face) frameStyle(img, c.pictureFrame); else if (!shot) el.classList.add('wl-ped');
        img.addEventListener('load', () => el.classList.add('has-portrait'));
        img.addEventListener('error', () => img.remove());
        img.src = src;
        el.appendChild(img);
    }
    return el;
}

// ============================================================
// Voice lines (server/director/lore_voice.lua)
// ============================================================

/** Why a voice line's link would be refused, or null (the server's LoreVoice.audioProblem decides; this says it
 *  sooner): an accepted start, a plain address, an .mp3, .ogg or .wav. */
function voiceProblem(url) {
    url = trim(url);
    if (!url) return null;
    const starts = arr(st.data && st.data.voice && st.data.voice.links);
    if (!starts.length) return 'Voice lines are switched off (Config: Voice line links accepted)';
    const start = starts.find((x) => url.startsWith(x));
    if (!start) return `Only links starting with ${starts.join(' or ')} are accepted`;
    const rest = url.slice(start.length);
    if (!rest || !/^[A-Za-z0-9\-._/]+$/.test(rest) || rest.includes('..')) return 'That link is not a recording\'s address';
    if (!/\.(mp3|ogg|wav)$/i.test(rest)) return 'A recording is an .mp3, .ogg or .wav link';
    return null;
}

const voiceLines = () => arr(st.data && st.data.voice && st.data.voice.lines);

/** A character's voice lines as the draft edits them: { [line]: [{ url, text }] }, a copy (not `busy`: busyCopy). */
function voiceCopy(v) {
    const out = {};
    for (const [k, list] of Object.entries(v && typeof v === 'object' ? v : {})) {
        if (k === 'busy') continue;
        out[k] = arr(list).map((x) => ({ url: x.url || '', text: x.text || '' }));
    }
    return out;
}

/** What each line does when asked while they are already talking (server/director/lore_voice.lua, "One line at a
 *  time"): { [line]: 'queue' | 'cut' }; a line left out is skipped. */
const BUSY_CHOICES = [
    { value: 'skip', label: 'If talking: skip it' },
    { value: 'queue', label: 'If talking: say it after' },
    { value: 'cut', label: 'If talking: cut in' },
];
const busyCopy = (v) => Object.assign({}, v && v.busy && typeof v.busy === 'object' ? v.busy : {});

/** Voice lines as saved: per line, the variants with a link (trimmed), in the catalogue's order, and `busy`. */
function voiceClean(v, busy) {
    const out = {};
    for (const line of voiceLines()) {
        const clean = arr(v && v[line.key]).map((x) => ({ url: trim(x.url), text: trim(x.text) })).filter((x) => x.url);
        if (clean.length) out[line.key] = clean.map((x) => (x.text ? x : { url: x.url }));
    }
    const b = {};
    for (const line of voiceLines()) {
        const m = busy && busy[line.key];
        if (m === 'queue' || m === 'cut') b[line.key] = m;
    }
    if (Object.keys(b).length) out.busy = b;
    return out;
}

/** How many of the lines have a recording, and how many recordings in all. */
function voiceCount(v) {
    let lines = 0, variants = 0;
    const clean = voiceClean(v);
    for (const line of voiceLines()) {
        if (clean[line.key]) { lines++; variants += clean[line.key].length; }
    }
    return { lines, variants };
}

/** The voice lines to save: JSON text (the links checked, empty variants dropped; '{}' clears them), or '' to leave
 *  them as they are (voice lines off, or a server without them). { why } when one is refused. */
function voiceToSave(d) {
    const V = st.data && st.data.voice;
    if (!V || !V.on || !d.voice) return { text: '' };
    for (const line of voiceLines()) {
        const list = arr(d.voice[line.key]);
        for (let i = 0; i < list.length; i++) {
            const bad = voiceProblem(list[i].url);
            if (bad) return { why: `${line.label}, variant ${i + 1}: ${bad}` };
        }
    }
    const text = JSON.stringify(voiceClean(d.voice, d.busy));
    if (text.length > 48000) return { why: 'Too many voice lines to save at once' };
    return { text };
}

// ============================================================
// The list, and what is picked
// ============================================================

const loreList = () => (st.data ? arr(st.data.lore) : []);
const loreOf = (key) => loreList().find((c) => c.key === key) || null;

/** Their hat as the form types it: { hat: '' (none) or its number as text, hatTex: its texture as text }. */
function hatOf(c) {
    const p = arr(c && c.props).find((x) => Number(x.anchor) === 0);
    return p ? { hat: String(p.drawable), hatTex: String(p.texture || 0) } : { hat: '', hatTex: '0' };
}
/** The typed hat as numbers: { hat: -1 for none, tex } or { why }. */
function hatToSave(d) {
    const h = trim(d.hat), t = trim(d.hatTex) || '0';
    if (h === '') return { hat: -1, tex: 0 };
    if (!/^\d{1,3}$/.test(h) || +h > 255) return { why: 'A hat is its number, 0 to 255 (blank for none)' };
    if (!/^\d{1,2}$/.test(t) || +t > 63) return { why: 'A hat texture is a number, 0 to 63' };
    return { hat: +h, tex: +t };
}

const draftOf = (c) => ({ isNew: false, key: c.key, name: c.name || '', model: c.model || '', bankName: c.bankName || '',
    notes: c.notes || '', picture: c.picture || '', frame: frameCopy(c.pictureFrame), voice: voiceCopy(c.voice),
    busy: busyCopy(c.voice), ...hatOf(c) });
const blank = () => ({ isNew: true, key: '', name: '', model: '', bankName: '', notes: '', picture: '', frame: frame0(), voice: {},
    busy: {}, hat: '', hatTex: '0' });

/** Has the typed hat changed from what is saved? */
function hatChanged(d, c) {
    const now = hatToSave(d), was = hatOf(c);
    if (now.why) return true;
    const w = was.hat === '' ? { hat: -1, tex: 0 } : { hat: +was.hat, tex: +was.hatTex };
    return now.hat !== w.hat || (now.hat >= 0 && now.tex !== w.tex);
}

/** Does the draft differ from what is saved? A new one always does. */
function dirty() {
    const d = st.draft;
    if (!d) return false;
    if (d.isNew) return true;
    const c = loreOf(d.key);
    if (!c) return false;
    return trim(d.name) !== trim(c.name) || trim(d.model) !== trim(c.model) || trim(d.bankName) !== trim(c.bankName)
        || trim(d.notes) !== trim(c.notes)
        || JSON.stringify(voiceClean(d.voice, d.busy)) !== JSON.stringify(voiceClean(c.voice, c.voice && c.voice.busy))
        || hatChanged(d, c);
}

let loadDraw = 0;
async function load() {
    const draw = ++loadDraw;
    const r = await call('lore');
    if (draw !== loadDraw) return;
    if (!r.ok) { WP.result(r.why, 'err'); return; }
    st.data = r.data;
    if (st.sel && st.sel !== NEW && !loreOf(st.sel)) { st.sel = null; st.draft = null; st.pic = null; }
    // A look made in the character editor sets their ped: a draft with other changes takes it too.
    const cur = st.sel && st.sel !== NEW ? loreOf(st.sel) : null;
    if (cur && cur.hasLook && st.draft && !st.draft.isNew) st.draft.model = cur.model || '';
    // A draft with nothing changed follows what was saved (another builder may have changed it).
    if (st.sel && st.sel !== NEW && (!st.draft || !dirty())) st.draft = draftOf(loreOf(st.sel));
    renderList();
    renderDetail();
    // Their headshots, asked for once each: the faces drawn without them are drawn again with them.
    primeLorePortraits(loreList()).then((moved) => {
        if (!moved || draw !== loadDraw) return;
        renderList();
        redrawFace();
        if (st.tab === 'details' && els.lookCard && els.lookCard.isConnected) drawTab();
    });
}

/** The profile's face again (a headshot arrived, a name typed), unless its picture is being edited. */
function redrawFace() {
    if (!els.ring || !els.ring.isConnected || st.pic || !st.draft) return;
    const c = st.sel && st.sel !== NEW ? loreOf(st.sel) : null;
    els.ring.innerHTML = '';
    els.ring.appendChild(loreFace(shownOf(c), 'wl-face-xl'));
}

function renderList() {
    if (!els.list) return;
    els.list.innerHTML = '';
    const q = st.search.toLowerCase();
    const all = loreList();
    // The ones still in use first, the retired after them.
    const list = all.filter((c) => !q || `${c.name} ${c.key} ${c.model || ''}`.toLowerCase().includes(q))
        .sort((a, b) => (a.retired === b.retired ? String(a.name).localeCompare(String(b.name)) : a.retired ? 1 : -1));
    for (const c of list) {
        const item = WP.listItem({ title: c.name || c.key,
            sub: c.key + (c.hasLook ? ' · made in the editor' : c.model ? ' · ' + c.model : ''),
            pill: c.retired ? 'Retired' : null, id: c.key, action: 'wlSelect' });
        item.classList.add('wp-has-icon');
        item.prepend(loreFace(c));
        if (st.sel === c.key) item.classList.add('active');
        els.list.appendChild(item);
    }
    if (!st.data) els.list.appendChild(WP.empty('Loading…'));
    else if (!list.length) els.list.appendChild(WP.empty(q ? `No lore characters match "${st.search}"` : 'No lore characters yet'));
    els.count.textContent = st.data ? `${list.length} of ${all.length}` : '';
}

// ============================================================
// The dashboard
// ============================================================

function renderDetail() {
    const d = els.detail;
    if (!d) return;
    d.innerHTML = '';
    const L = st.data;
    if (L && !L.ready) { d.appendChild(WP.empty('Lore characters are unavailable: see the server console')); return; }
    const c = st.sel && st.sel !== NEW ? loreOf(st.sel) : null;
    if (!st.draft || (!c && st.sel !== NEW)) {
        d.appendChild(WP.empty(loreList().length ? 'Pick a lore character on the left' : 'No lore characters yet: New lore character makes one'));
        return;
    }
    const dash = WP.el('div', 'wl-dash');
    dash.appendChild(profile(c));
    const main = WP.el('div', 'wl-main');
    const count = voiceCount(st.draft.voice);
    const list = [
        { key: 'details', label: 'Details' },
        ...(L && L.voice ? [{ key: 'audio', label: 'Audio', badge: count.variants || null }] : []),
        ...(st.draft.isNew ? [] : [{ key: 'interactions', label: 'Interactions' }]),
    ];
    if (!list.some((t) => t.key === st.tab)) st.tab = 'details';
    tabs = WP.tabs({ id: 'wl-tabs', inline: true, active: st.tab, tabs: list,
        onChange: (key) => { st.tab = key; drawTab(); } });
    main.appendChild(tabs.root);
    els.body = WP.el('div', 'wl-body');
    main.appendChild(els.body);
    els.bar = saveBar();
    main.appendChild(els.bar);
    dash.appendChild(main);
    d.appendChild(dash);
    drawTab();
    updateBar();
}

function drawTab() {
    const b = els.body;
    if (!b) return;
    b.innerHTML = '';
    b.scrollTop = 0;
    if (st.tab === 'audio') audioTab(b);
    else if (st.tab === 'interactions') interactionsTab(b);
    else detailsTab(b);
}

// ---- the profile: picture, name, who they are ----

/** What the profile shows of the draft: its name, key and ped as typed, the picture as saved (a new one's, as
 *  framed so far). */
function shownOf(c) {
    const d = st.draft;
    return { name: trim(d.name) || (d.isNew ? 'New lore character' : d.key),
             key: d.isNew ? (trim(d.key) || slug(d.name) || 'their key') : d.key, model: trim(d.model),
             picture: c ? c.picture : d.picture, pictureFrame: c ? c.pictureFrame : d.frame,
             hasLook: !!(c && c.hasLook), portrait: c ? lorePortrait(c) : '' };
}

function profile(c) {
    const d = st.draft;
    const col = WP.el('aside', 'wl-profile');
    const shown = shownOf(c);

    if (st.pic) col.appendChild(pictureEditor(c));
    else {
        els.ring = WP.el('div', 'wl-portrait');
        els.ring.appendChild(loreFace(shown, 'wl-face-xl'));
        col.appendChild(els.ring);
        const edit = WP.btn(shown.picture ? 'Edit picture' : 'Add picture', 'wlPicEdit');
        edit.classList.add('wp-btn-sm', 'wl-pic-btn');
        edit.prepend(icon('camera'));
        col.appendChild(edit);
    }

    const who = WP.el('div', 'wl-who');
    els.pName = WP.el('div', 'wl-name', shown.name);
    who.appendChild(els.pName);
    els.pHandle = WP.el('div', 'wl-handle');
    who.appendChild(els.pHandle);
    if (c && c.retired) who.appendChild(WP.el('span', 'wp-pill wp-pill-warn', 'Retired'));
    col.appendChild(who);
    els.pBio = WP.el('p', 'wl-bio');
    col.appendChild(els.pBio);
    profileWords(c);

    if (c) {
        const facts = WP.el('dl', 'wl-facts');
        const fact = (label, value) => {
            facts.appendChild(WP.el('dt', null, label));
            facts.appendChild(WP.el('dd', null, value));
        };
        fact('Payments from', c.payName || c.name);
        if (st.data && st.data.voice) {
            const n = voiceCount(c.voice);
            fact('Voice lines', n.lines ? `${n.lines} of ${voiceLines().length} lines` : 'none yet');
        }
        fact('Changed', `${ago(c.updatedAt)} by ${c.updatedBy || 'the server'}`);
        col.appendChild(facts);
        // The house order: the destructive one apart, at the foot (retiring is a Director admin's; the server
        // refuses anyone else regardless).
        const foot = WP.el('div', 'wl-profile-foot');
        if (c.retired) foot.appendChild(WP.btn('Bring back', 'wlBack', 'primary', c.key));
        else if (st.data && st.data.admin) foot.appendChild(WP.btn('Retire', 'wlRetire', 'danger', c.key));
        if (foot.childElementCount) col.appendChild(foot);
    }
    return col;
}

/** The profile's words, from the draft as typed: the name, "key · ped" and the notes as their bio. */
function profileWords(c) {
    const s = shownOf(c);
    els.pName.textContent = s.name;
    els.pHandle.innerHTML = '';
    els.pHandle.appendChild(WP.el('span', null, s.key));
    if (s.hasLook) els.pHandle.appendChild(WP.el('span', null, 'made in the character editor'));
    else if (s.model) els.pHandle.appendChild(WP.el('span', null, s.model));
    els.pBio.textContent = trim(st.draft.notes);
    els.pBio.hidden = !trim(st.draft.notes);
}

/** Edit picture: the portrait becomes its frame (dragged to move it, the slider or the wheel zooms), with the link,
 *  Remove, Cancel and Save under it. A new one's picture goes in its draft, saved with Create. */
function pictureEditor(c) {
    const p = st.pic;
    const wrap = WP.el('div', 'wl-pic-edit');
    const box = WP.el('div', 'wl-portrait wl-frame');
    const img = document.createElement('img');
    img.alt = '';
    img.draggable = false;
    box.appendChild(img);
    const none = WP.el('span', 'wl-frame-none', c && lorePortrait(c)
        ? 'Paste a picture\'s link below: it shows instead of their portrait' : 'Paste the picture\'s link below');
    box.appendChild(none);
    wrap.appendChild(box);

    const zoomRow = WP.el('div', 'wl-zoom-row');
    const zoom = WP.el('input', 'wl-zoom');
    zoom.type = 'range';
    zoom.min = '1'; zoom.max = '3'; zoom.step = '0.01';
    zoom.setAttribute('aria-label', 'Zoom');
    zoomRow.appendChild(icon('minus'));
    zoomRow.appendChild(zoom);
    zoomRow.appendChild(icon('plus'));
    wrap.appendChild(zoomRow);

    const starts = arr(st.data && st.data.pictureLinks);
    const site = starts.length ? starts[0].replace(/^https:\/\//, '').split('/')[0].replace(/^r2\./, '') : '';
    const url = WP.input({ value: p.url, placeholder: site ? `Link from ${site}` : 'Pictures are switched off' });
    url.classList.add('wl-input');
    url.maxLength = 255;
    url.spellcheck = false;
    url.setAttribute('aria-label', 'Picture link');
    wrap.appendChild(url);
    const why = WP.el('div', 'wl-why');
    wrap.appendChild(why);

    const row = WP.el('div', 'wl-pic-actions');
    const rm = WP.btn('Remove', 'wlPicClear', 'ghost');
    rm.classList.add('wp-btn-sm');
    row.appendChild(rm);
    row.appendChild(WP.el('span', 'wp-actions-split'));
    const cancel = WP.btn('Cancel', 'wlPicCancel', 'ghost');
    const save = WP.btn(st.draft.isNew ? 'Done' : 'Save', 'wlPicSave', 'primary');
    cancel.classList.add('wp-btn-sm');
    save.classList.add('wp-btn-sm');
    row.appendChild(cancel);
    row.appendChild(save);
    wrap.appendChild(row);

    const show = () => {
        const u = trim(p.url), bad = pictureProblem(u);
        const ok = !!u && !bad;
        rm.hidden = !u;
        box.classList.toggle('wl-frame-on', ok);
        zoom.disabled = !ok;
        why.textContent = bad || (ok ? 'Drag it to move it. Phones show it like this.' : '');
        why.classList.toggle('wl-why-bad', !!bad);
        save.disabled = !!bad;
        if (ok && img.getAttribute('src') !== u) img.src = u;
        frameStyle(img, p.frame);
        if (document.activeElement !== zoom) zoom.value = p.frame.z;
    };
    img.addEventListener('error', () => {
        box.classList.remove('wl-frame-on');
        why.textContent = 'That picture would not load: check the link';
        why.classList.add('wl-why-bad');
    });
    url.addEventListener('input', () => { p.url = url.value; show(); });
    zoom.addEventListener('input', () => { p.frame.z = Math.round(clampN(+zoom.value || 1, 1, 3) * 100) / 100; show(); });
    box.addEventListener('pointerdown', (ev) => {
        if (ev.button !== 0 || !box.classList.contains('wl-frame-on')) return;
        ev.preventDefault();
        const r = box.getBoundingClientRect(), start = frameCopy(p.frame), x0 = ev.clientX, y0 = ev.clientY;
        const move = (m) => {
            const per = 100 / (r.width * p.frame.z);
            p.frame.x = Math.round(clampN(start.x - (m.clientX - x0) * per, 0, 100) * 10) / 10;
            p.frame.y = Math.round(clampN(start.y - (m.clientY - y0) * per, 0, 100) * 10) / 10;
            show();
        };
        const up = () => { window.removeEventListener('pointermove', move); window.removeEventListener('pointerup', up); };
        window.addEventListener('pointermove', move);
        window.addEventListener('pointerup', up);
    });
    box.addEventListener('wheel', (ev) => {
        if (!box.classList.contains('wl-frame-on')) return;
        ev.preventDefault();
        p.frame.z = Math.round(clampN(p.frame.z + (ev.deltaY < 0 ? 0.1 : -0.1), 1, 3) * 100) / 100;
        show();
    }, { passive: false });
    show();
    // The link box takes the keyboard once, when Edit picture opens on no picture (not on every redraw).
    if (p.focus) { p.focus = false; if (!trim(p.url)) setTimeout(() => url.focus(), 0); }
    return wrap;
}

// ---- Details ----

/** A look made in the character editor, in words: which ped it is on. */
const lookWords = (c) => (c.model === 'mp_female' ? 'Made in the editor (female)' : 'Made in the editor (male)');

function detailsTab(b) {
    const d = st.draft;
    const c = d.isNew ? null : loreOf(d.key);
    const isLook = !!(c && c.hasLook);
    const grid = WP.el('div', 'wl-details');
    const fields = WP.el('div', 'wl-fields');
    const input = (k, max, ph) => {
        const i = WP.input({ value: d[k] || '', placeholder: ph || '' });
        i.maxLength = max;
        i.spellcheck = false;
        i.addEventListener('input', () => { d[k] = i.value; changed(k); });
        return i;
    };
    const name = input('name', 80, 'Their full name');
    const two = WP.el('div', 'wp-cols-2');
    two.appendChild(WP.field('Name', name));
    two.appendChild(WP.field('Bank name', input('bankName', 50, 'Same as their name')));
    fields.appendChild(two);
    const two2 = WP.el('div', 'wp-cols-2');
    // A look made in the character editor is its own ped: nothing to type (Use a GTA ped, beside, goes back to one).
    let model = null;
    if (isLook) {
        const ped = WP.el('div', 'wl-key');
        ped.appendChild(WP.el('span', 'wp-field-label', 'Ped'));
        ped.appendChild(WP.el('span', 'wl-key-value', lookWords(c)));
        two2.appendChild(ped);
    } else {
        model = input('model', 64, 'Spawn name');
        two2.appendChild(WP.field('Ped', model));
    }
    if (d.isNew) {
        // A new one's key: typed, or made from the name (the box shows which it will be).
        const key = input('key', 64, slug(d.name) || 'Made from the name');
        name.addEventListener('input', () => { key.placeholder = slug(d.name) || 'Made from the name'; });
        two2.appendChild(WP.field('Key', key));
    } else {
        const key = WP.el('div', 'wl-key');
        key.appendChild(WP.el('span', 'wp-field-label', 'Key'));
        key.appendChild(WP.el('span', 'wl-key-value', d.key));
        two2.appendChild(key);
    }
    fields.appendChild(two2);
    // Their hat: GTA puts none on by itself, so whip puts this one on every NPC that is them. (A look made in the
    // character editor has its own.)
    if (!isLook && (!st.data || st.data.props !== false)) {
        const two3 = WP.el('div', 'wp-cols-2');
        const hat = input('hat', 3, 'None');
        hat.inputMode = 'numeric';
        const tex = input('hatTex', 2, '0');
        tex.inputMode = 'numeric';
        two3.appendChild(WP.field('Hat', hat));
        two3.appendChild(WP.field('Hat texture', tex));
        fields.appendChild(two3);
    }
    fields.appendChild(WP.el('div', 'wl-help', 'Bank name is who their payments say they are from (their name when empty). '
        + (isLook
            ? 'Their look was made in the character editor: Edit look puts you back in it (you wear it while you edit), '
              + 'and its Save takes a new portrait. Copy my look gives them your character\'s look instead, as you are now. '
              + 'The portrait is their face wherever they have no picture of their own.'
            : 'The ped is the spawn name their NPC wears. Hat is the number of the ped\'s hat (blank for none) and Hat texture '
              + 'its colour: every NPC that is them wears it. Dundee\'s is hat 0, texture 0.'
              + ' Male or Female makes them a look of their own in the character editor instead, and Copy my look '
              + 'gives them your character\'s, as you are now: either way with a portrait.')));

    const notes = WP.el('textarea', 'wp-input wl-notes');
    notes.rows = 6;
    notes.maxLength = 2000;
    notes.spellcheck = false;
    notes.placeholder = 'Who they are, how they talk, what they want: for whoever writes their lines and texts';
    notes.value = d.notes || '';
    notes.addEventListener('input', () => { d.notes = notes.value; changed('notes'); });
    const notesField = WP.field('Notes', notes);
    notesField.classList.add('wl-field-col');
    fields.appendChild(notesField);

    if (c) {
        fields.appendChild(WP.el('div', 'wl-meta',
            `Made by ${c.createdBy || 'the server'} · changed by ${c.updatedBy || 'the server'}, ${dateTime(c.updatedAt)}`));
    }
    grid.appendChild(fields);

    // Their look beside the fields: the GTA ped standing, or the portrait of the look made in the character editor,
    // and under it the character editor's way in.
    const side = WP.el('div', 'wl-look');
    const card = WP.el('figure', 'wl-ped-card' + (isLook ? ' wl-look-card' : ''));
    els.lookCard = card;
    const pic = document.createElement('img');
    pic.alt = '';
    pic.draggable = false;
    const empty = WP.el('span', 'wl-ped-none', isLook ? 'No portrait yet' : 'No ped yet');
    card.appendChild(pic);
    card.appendChild(empty);
    const cap = WP.el('figcaption', null, isLook ? lookWords(c) : trim(d.model) || 'Ped');
    card.appendChild(cap);
    pic.addEventListener('load', () => card.classList.add('wl-ped-on'));
    if (isLook) {
        const shot = lorePortrait(c);
        if (shot) pic.src = shot;
        side.appendChild(card);
        side.appendChild(WP.btn('Edit look', 'wlLookEdit', 'primary'));
        side.appendChild(WP.btn('Copy my look', 'wlLookCopy'));
        const gta = WP.btn('Use a game ped', 'wlLookClear', 'ghost');
        gta.classList.add('wp-btn-sm');
        side.appendChild(gta);
    } else {
        const showPed = () => {
            const m = trim(d.model);
            cap.textContent = m || 'Ped';
            card.classList.remove('wl-ped-on');
            if (m) pic.src = pedImageUrl(m); else pic.removeAttribute('src');
        };
        pic.addEventListener('error', () => { card.classList.remove('wl-ped-on'); empty.textContent = 'No picture of that ped'; });
        // Asked once typing stops: each half-typed name would be a missing picture (an F8 line each).
        let pedTimer = 0;
        model.addEventListener('input', () => {
            empty.textContent = 'No ped yet';
            cap.textContent = trim(d.model) || 'Ped';
            clearTimeout(pedTimer);
            pedTimer = setTimeout(showPed, 450);
        });
        showPed();
        side.appendChild(card);
        side.appendChild(WP.el('div', 'wl-look-or', 'Or give them a look of their own'));
        const pair = WP.el('div', 'wl-look-pair');
        pair.appendChild(WP.btn('Male', 'wlLookMake', null, 'male'));
        pair.appendChild(WP.btn('Female', 'wlLookMake', null, 'female'));
        side.appendChild(pair);
        side.appendChild(WP.btn('Copy my look', 'wlLookCopy'));
    }
    grid.appendChild(side);
    b.appendChild(grid);
    if (d.isNew && !trim(d.name) && !st.pic) setTimeout(() => name.focus(), 0);
}

/** Something in the draft was typed: the profile's words follow (its face too, when it is their ped's), and the
 *  bar says it is not saved. */
let faceTimer = 0;
function changed(k) {
    const c = st.sel && st.sel !== NEW ? loreOf(st.sel) : null;
    if ((k === 'name' || k === 'model' || k === 'key' || k === 'notes') && els.pName) profileWords(c);
    if ((k === 'model' || k === 'name') && els.ring && !st.pic && !shownOf(c).picture) {
        clearTimeout(faceTimer);
        faceTimer = setTimeout(() => {
            if (!els.ring || !els.ring.isConnected) return;
            els.ring.innerHTML = '';
            els.ring.appendChild(loreFace(shownOf(c), 'wl-face-xl'));
        }, 350);
    }
    if (k === 'voice' && tabs) {
        const n = voiceCount(st.draft.voice).variants;
        const btn = tabs.root.querySelector('[data-arg="audio"]');
        if (btn) {
            let badge = btn.querySelector('.wp-pill');
            if (n && !badge) { badge = WP.el('span', 'wp-pill'); btn.appendChild(badge); }
            if (badge) { if (n) badge.textContent = String(n); else badge.remove(); }
        }
    }
    updateBar();
}

// ---- Audio ----

/** Is this one's test NPC out (Spawn to test), so Say and Play speak from it? */
const testing = () => !!(st.test && st.draft && !st.draft.isNew && st.test.key === st.draft.key && Date.now() < st.test.endsAt);

function setTest(d) {
    st.test = d && d.on ? { key: d.key, endsAt: Date.now() + (Number(d.left) || 0) * 1000 } : null;
    if (st.tab === 'audio' && els.body) {
        const top = els.body.scrollTop;
        drawTab();
        els.body.scrollTop = top;
    }
}

async function loadTest() {
    const r = await call('loreTest', { key: 'none', mode: 'ask' });
    if (r.ok) setTest(r.data);
}

const clock = (ms) => { const t = new Date(ms); return String(t.getHours()).padStart(2, '0') + ':' + String(t.getMinutes()).padStart(2, '0'); };

/** TEST IN THE WORLD: their NPC in front of you for ten minutes. Say plays a line from it, and it greets and reacts
 *  by itself (with the saved lines), as in a scenario. */
function testStrip() {
    const d = st.draft;
    const c = d.isNew ? null : loreOf(d.key);
    const strip = WP.el('div', 'wl-test' + (testing() ? ' wl-test-on' : ''));
    const words = WP.el('div', 'wl-test-words');
    const name = trim(d.name) || d.key;
    const other = st.test && Date.now() < st.test.endsAt && !testing() ? loreOf(st.test.key) : null;
    if (testing()) {
        const head = WP.el('div', 'wl-test-title');
        head.appendChild(WP.el('span', 'wp-dot wp-dot-ok'));
        head.appendChild(WP.el('span', null, `${name} is standing in front of you until ${clock(st.test.endsAt)}`));
        words.appendChild(head);
        words.appendChild(WP.el('div', 'wl-test-help',
            'Say plays a line from them, and Play a single variant. Close the panel to walk up to them, bump into them or aim at them: they react with their saved lines.'));
        strip.appendChild(words);
        strip.appendChild(WP.btn('Remove', 'wlTestOff'));
        return strip;
    }
    words.appendChild(WP.el('div', 'wl-test-title', 'Test in the world'));
    let why = null;
    if (!c) why = 'Create them first.';
    else if (c.retired) why = 'Bring them back first.';
    else if (!c.model) why = 'Give them a ped (Details) and save first.';
    words.appendChild(WP.el('div', 'wl-test-help', why || (other
        ? `You are testing ${other.name} until ${clock(st.test.endsAt)}. Spawning ${name} takes them away.`
        : `Spawns ${name} in front of you for 10 minutes, to hear their lines from them and try their reactions.`)));
    strip.appendChild(words);
    const go = WP.btn('Spawn to test', 'wlTestOn', 'primary');
    go.disabled = !!why;
    strip.appendChild(go);
    return strip;
}

/** A recording said by the test NPC (when it is out), else heard at you. */
async function playOne(d, url, text) {
    if (testing()) {
        const r = await call('loreTestSay', { url: trim(url), text: trim(text) });
        if (!r.ok && /has gone/.test(r.why)) setTest(null);
        WP.result(r.ok ? `Said by ${trim(d.name) || d.key}` : r.why, r.ok ? 'ok' : 'err');
        return;
    }
    const k = d.key || slug(d.name);
    const r = await call('loreVoiceTest', { key: KEY_OK.test(k) ? k : 'test', url: trim(url) });
    WP.result(r.ok ? 'Playing it at you, as it sounds from their NPC' : r.why, r.ok ? 'ok' : 'err');
}

function audioTab(b) {
    const V = st.data && st.data.voice;
    if (!V) return;
    if (!V.on) {
        b.appendChild(WP.el('div', 'wl-lead', 'Voice lines are off: Config, "Lore characters speak" (or see the server console).'));
        return;
    }
    b.appendChild(WP.el('div', 'wl-lead',
        'Said out loud from their NPC, heard like a player\'s voice by the players near it. Give a line as many variants as you like: they are said in turn. '
        + 'One line at a time: if they are already talking, a line is skipped, unless you set it to be said after or to cut in. '
        + (testing() ? 'Play says one from your test NPC.' : 'Play hears one at you.')));
    b.appendChild(testStrip());
    const d = st.draft;
    d.voice = d.voice || {};
    let group = null, box = null;
    for (const line of voiceLines()) {
        if (line.group !== group) {
            group = line.group;
            b.appendChild(WP.el('div', 'wp-section-title', group));
            box = WP.el('div', 'wl-lines');
            b.appendChild(box);
        }
        box.appendChild(voiceLine(d, line, V));
    }
}

function voiceLine(d, line, V) {
    const list = d.voice[line.key] || (d.voice[line.key] = []);
    const box = WP.el('div', 'wl-line');
    const head = WP.el('div', 'wl-line-head');
    const words = WP.el('div', 'wl-line-words');
    const top = WP.el('div', 'wl-line-top');
    top.appendChild(WP.el('span', 'wl-line-name', line.label));
    const count = WP.el('span', 'wl-line-count');
    top.appendChild(count);
    words.appendChild(top);
    words.appendChild(WP.el('div', 'wl-line-help', line.help));
    head.appendChild(words);
    // Testing: Say plays this line from the test NPC, its variants in turn (as typed here, saved or not).
    let sayBtn = null;
    if (testing()) {
        sayBtn = WP.btn('Say', null);
        sayBtn.type = 'button';
        sayBtn.classList.add('wp-btn-sm', 'wl-add');
        sayBtn.prepend(icon('play'));
        sayBtn.addEventListener('click', async () => {
            const ready = list.filter((x) => trim(x.url) && !voiceProblem(x.url));
            if (!ready.length) { WP.result(`No ${line.label} recording to say yet`, 'err'); return; }
            const i = ((st.turn[line.key] ?? -1) + 1) % ready.length;
            st.turn[line.key] = i;
            sayBtn.disabled = true;
            await playOne(d, ready[i].url, ready[i].text);
            sayBtn.disabled = false;
        });
        head.appendChild(sayBtn);
    }
    // While they are already saying another line: this one is skipped (the default), said after it, or cuts in.
    d.busy = d.busy || {};
    const busy = WP.select(BUSY_CHOICES);
    busy.classList.add('wl-busy');
    busy.value = d.busy[line.key] || 'skip';
    busy.title = 'What this line does when they are already saying another: ignored, said once it ends, or cuts it off';
    busy.setAttribute('aria-label', `${line.label}: if they are already talking`);
    busy.addEventListener('change', () => {
        if (busy.value === 'skip') delete d.busy[line.key]; else d.busy[line.key] = busy.value;
        changed('voice');
    });
    head.appendChild(busy);
    const add = WP.btn('Variant', null, 'ghost');
    add.type = 'button';
    add.classList.add('wp-btn-sm', 'wl-add');
    add.prepend(icon('plus'));
    head.appendChild(add);
    box.appendChild(head);
    const rows = WP.el('div', 'wl-variants');
    box.appendChild(rows);
    const draw = () => {
        rows.innerHTML = '';
        count.textContent = list.length ? plural(list.length, 'variant') : 'none';
        box.classList.toggle('wl-line-empty', !list.length);
        add.disabled = list.length >= (V.maxVariants || 50);
        if (sayBtn) sayBtn.disabled = !list.length;
        list.forEach((v, i) => rows.appendChild(variantRow(d, list, i, V, draw)));
    };
    add.addEventListener('click', () => {
        list.push({ url: '', text: '' });
        draw();
        changed('voice');
        const urls = rows.querySelectorAll('.wl-variant-url');
        if (urls.length) urls[urls.length - 1].focus();
    });
    draw();
    return box;
}

function variantRow(d, list, i, V, redraw) {
    const v = list[i];
    const row = WP.el('div', 'wl-variant');
    row.appendChild(WP.el('span', 'wl-variant-n', String(i + 1)));
    const starts = arr(V.links);
    const url = WP.input({ value: v.url || '', placeholder: starts.length ? `${starts[0]}…/line.mp3` : 'switched off' });
    url.classList.add('wl-input', 'wl-variant-url');
    url.maxLength = 255;
    url.spellcheck = false;
    url.setAttribute('aria-label', `Variant ${i + 1}'s recording link`);
    const text = WP.input({ value: v.text || '', placeholder: 'Subtitle (optional)' });
    text.classList.add('wl-input');
    text.maxLength = V.maxText || 160;
    text.setAttribute('aria-label', `Variant ${i + 1}'s subtitle`);
    const play = iconBtn('play', testing() ? 'Play it from your test NPC' : 'Play it at you');
    const del = iconBtn('remove', 'Remove this variant', 'ghost');
    const why = WP.el('div', 'wl-why wl-why-bad');
    const check = () => {
        const bad = voiceProblem(url.value);
        why.textContent = bad || '';
        row.classList.toggle('bad', !!bad);
        play.disabled = !trim(url.value) || !!bad;
    };
    url.addEventListener('input', () => { v.url = url.value; check(); changed('voice'); });
    text.addEventListener('input', () => { v.text = text.value; changed('voice'); });
    play.addEventListener('click', async () => {
        play.disabled = true;
        await playOne(d, url.value, text.value);
        check();
    });
    del.addEventListener('click', () => { list.splice(i, 1); redraw(); changed('voice'); });
    row.appendChild(url);
    row.appendChild(text);
    row.appendChild(play);
    row.appendChild(del);
    row.appendChild(why);
    check();
    return row;
}

// ---- Interactions ----

async function loadActivity(key) {
    const r = await call('loreActivity', { key });
    st.acts[key] = r.ok ? { data: r.data } : { why: r.why };
    if (st.sel === key && st.tab === 'interactions') drawTab();
}

function interactionsTab(b) {
    const key = st.draft.key;
    let a = st.acts[key];
    if (!a) {
        a = st.acts[key] = { loading: true };
        loadActivity(key);
    }
    if (a.loading) { b.appendChild(WP.empty('Reading what they are part of…')); return; }
    if (a.why) { b.appendChild(WP.empty(a.why)); return; }
    const A = a.data;
    const scen = arr(A.scenarios), phone = A.phone, pay = A.payments;
    const texts = phone && phone.texts, calls = phone && phone.calls;

    const stats = WP.el('div', 'wp-stats');
    const on = scen.filter((s) => s.on).length;
    stats.appendChild(WP.stat('Scenarios', String(scen.length), scen.length ? `${on} switched on` : 'in none yet'));
    stats.appendChild(WP.stat('Texts', texts ? String(texts.sent + texts.received) : '—',
        !phone ? 'no phone number' : texts ? (texts.people ? `with ${plural(texts.people, 'person', 'people')}` : 'none yet') : 'not read'));
    stats.appendChild(WP.stat('Calls', calls ? String(calls.made + calls.received) : '—',
        !phone ? 'no phone number' : calls ? `${calls.made} made, ${calls.received} to them` : 'not read'));
    stats.appendChild(WP.stat('Paid out', pay ? money(pay.total) : '$0',
        pay && pay.n ? `${plural(pay.n, 'payment')} to ${plural(pay.people, 'person', 'people')}` : 'nothing yet'));
    b.appendChild(stats);

    // The scenarios that use them: a row each, what in it names them; a row opens it on the Scenarios page.
    b.appendChild(WP.el('div', 'wp-section-title', 'In scenarios'));
    if (A.scenariosWhy) b.appendChild(WP.el('div', 'wl-help', A.scenariosWhy));
    else if (!scen.length) {
        b.appendChild(WP.el('div', 'wl-help', 'No scenario uses them yet. Make an NPC this lore character in the world builder, or pick them in a card\'s From.'));
    } else {
        const rows = WP.el('div', 'wl-rows');
        for (const s of scen) {
            const row = WP.el('button', 'wl-row');
            row.type = 'button';
            row.dataset.action = 'wlOpenScenario';
            row.dataset.arg = s.key;
            const words = WP.el('span', 'wl-row-words');
            words.appendChild(WP.el('span', 'wl-row-title', s.name || s.key));
            words.appendChild(WP.el('span', 'wl-row-sub',
                arr(s.uses).map((u) => (u.n > 1 ? `${u.what} ×${u.n}` : u.what)).join(' · ')));
            row.appendChild(words);
            row.appendChild(WP.el('span', 'wp-pill' + (s.on ? ' wp-pill-ok' : ''), s.on ? 'On' : 'Off'));
            rows.appendChild(row);
        }
        b.appendChild(rows);
    }

    // Their phone: spur_phone gives each lore character a number (a telegraph address). RedM (spur_core, 24 Nov 2026).
    b.appendChild(WP.el('div', 'wp-section-title', 'Telegraph address'));
    if (!phone) b.appendChild(WP.el('div', 'wl-help', 'No telegraph address. spur_phone gives each lore character one while it runs.'));
    else {
        const box = WP.el('div', 'wl-phone');
        box.appendChild(WP.el('div', 'wl-phone-number', phoneNumber(phone.number)));
        const facts = WP.el('dl', 'wl-facts wl-facts-wide');
        const fact = (label, value) => {
            facts.appendChild(WP.el('dt', null, label));
            facts.appendChild(WP.el('dd', null, value));
        };
        if (texts) fact('Texts', `${texts.sent} sent, ${texts.received} received${texts.lastAt ? ' · last ' + ago(texts.lastAt) : ''}`);
        if (calls) fact('Calls', `${calls.made} made, ${calls.received} to them (${calls.answered} answered)${calls.lastAt ? ' · last ' + ago(calls.lastAt) : ''}`);
        box.appendChild(facts);
        b.appendChild(box);
    }

    // What they have paid players (Send Money, PayAsLore), newest first.
    b.appendChild(WP.el('div', 'wp-section-title', 'Payments'));
    if (!pay || !pay.n) b.appendChild(WP.el('div', 'wl-help', 'They have paid nobody yet. The Send Money card pays from their account.'));
    else {
        const wrap = WP.el('div', 'wp-table-wrap');
        const t = WP.el('table', 'wp-table');
        const head = WP.el('tr');
        for (const h of ['To', 'Amount', 'Message', 'When']) head.appendChild(WP.el('th', null, h));
        const thead = WP.el('thead');
        thead.appendChild(head);
        t.appendChild(thead);
        const body = WP.el('tbody');
        for (const p of arr(pay.recent)) {
            const tr = WP.el('tr');
            tr.appendChild(WP.el('td', null, p.to || '—'));
            tr.appendChild(WP.el('td', 'wl-num', money(p.amount)));
            tr.appendChild(WP.el('td', null, p.message || '—'));
            tr.appendChild(WP.el('td', null, dateTime(p.at)));
            body.appendChild(tr);
        }
        t.appendChild(body);
        wrap.appendChild(t);
        b.appendChild(wrap);
        if (pay.n > arr(pay.recent).length) b.appendChild(WP.el('div', 'wl-help', `The newest ${arr(pay.recent).length} of ${pay.n}.`));
    }
}

// ---- the bar: what is not saved yet ----

function saveBar() {
    const bar = WP.el('div', 'wl-bar');
    els.barText = WP.el('span', 'wl-bar-text');
    bar.appendChild(els.barText);
    bar.appendChild(WP.el('span', 'wp-actions-split'));
    els.barUndo = WP.btn('Discard', 'wlDiscard', 'ghost');
    els.barSave = WP.btn('Save', 'wlSave', 'primary');
    bar.appendChild(els.barUndo);
    bar.appendChild(els.barSave);
    return bar;
}

function updateBar() {
    if (!els.bar) return;
    const d = st.draft;
    const show = !!d && dirty();
    els.bar.hidden = !show;
    if (!show) return;
    els.barText.textContent = d.isNew ? 'A new lore character: name them, then Create' : 'Changes not saved yet';
    els.barUndo.textContent = d.isNew ? 'Cancel' : 'Discard';
    els.barSave.textContent = d.isNew ? 'Create' : 'Save';
}

// ============================================================
// Saving
// ============================================================

/** Details and Audio, as the draft has them. A saved one keeps its picture as saved (it saves on its own). Answers
 *  whether it was saved. */
async function save() {
    const d = st.draft;
    if (!d) return false;
    const name = trim(d.name);
    if (!name) { WP.result('Give them a name', 'err'); goTab('details'); return false; }
    const key = d.isNew ? (trim(d.key) || slug(name)) : d.key;
    if (!KEY_OK.test(key)) { WP.result('A key is 2-64 letters, digits, _ and -', 'err'); goTab('details'); return false; }
    const taken = d.isNew ? loreOf(key) : null;
    if (taken) {
        WP.result(taken.retired ? `${key} is a retired lore character's: pick them and Bring back` : `${key} is taken`, 'err');
        goTab('details');
        return false;
    }
    const voice = voiceToSave(d);
    if (voice.why) { WP.result(voice.why, 'err'); goTab('audio'); return false; }
    const hat = hatToSave(d);
    if (hat.why) { WP.result(hat.why, 'err'); goTab('details'); return false; }
    const c = d.isNew ? null : loreOf(key);
    const hatMoved = d.isNew ? hat.hat >= 0 : hatChanged(d, c);
    const picture = c ? c.picture || '' : trim(d.picture);
    const bad = pictureProblem(picture);
    if (bad) { WP.result(bad, 'err'); return false; }
    const fr = frameCopy(c ? c.pictureFrame : d.frame);
    if (els.barSave) els.barSave.disabled = true;
    const r = await call('loreSave', { key, name, model: trim(d.model), bankName: trim(d.bankName), notes: trim(d.notes),
        picture, frameX: fr.x, frameY: fr.y, frameZ: fr.z, voice: voice.text });
    if (!r.ok) { if (els.barSave) els.barSave.disabled = false; WP.result(r.why, 'err'); return false; }
    // The hat saves on its own (spur_core:director:loreProps), once the character exists.
    if (hatMoved) {
        const h = await call('loreProps', { key, hat: hat.hat, hatTexture: hat.tex });
        if (!h.ok) {
            if (els.barSave) els.barSave.disabled = false;
            WP.result(`Saved, but not the hat: ${h.why}`, 'err');
            st.sel = key;
            if (d.isNew) { d.isNew = false; d.key = key; }
            await load();
            return true;
        }
    }
    if (els.barSave) els.barSave.disabled = false;
    WP.result(d.isNew ? `${name} made` : 'Saved', 'ok');
    st.sel = key;
    st.draft = null;
    st.pic = null;
    await load();
    return true;
}

/** Into the character editor on their look: a new one on the ped `gender` names, else the one they have. The panel
 *  closes; it opens on this page again once the editor closes (tools/panel_sections/director.lua wpLoreLook). */
async function editLook(c, gender) {
    const r = await nuiCallback('wpLoreLook', { key: c.key, name: c.name || c.key, gender: gender || '' });
    if (!r || !r.ok) WP.result((r && r.why) || 'The character editor did not open', 'err');
}

/** Copy my look: the builder's character as they are now becomes theirs, with a headshot of it (the panel stays
 *  open: tools/panel_sections/director.lua wpLoreCopyLook). */
async function copyLook(c) {
    const r = await nuiCallback('wpLoreCopyLook', { key: c.key });
    if (!r || !r.ok) { WP.result((r && r.why) || 'Your look was not copied', 'err'); return; }
    WP.result(r.portrait ? `${c.name || c.key} looks like you now, portrait and all`
        : `${c.name || c.key} looks like you now, but the portrait could not be taken`, r.portrait ? 'ok' : 'err');
    await load();
}

/** The picture alone: a saved one is written now (everything else as saved); a new one's goes in its draft. */
async function savePicture() {
    const p = st.pic, d = st.draft;
    if (!p || !d) return;
    const url = trim(p.url);
    const bad = pictureProblem(url);
    if (bad) { WP.result(bad, 'err'); return; }
    if (d.isNew) {
        d.picture = url;
        d.frame = frameCopy(p.frame);
        st.pic = null;
        renderDetail();
        return;
    }
    const c = loreOf(d.key);
    if (!c) return;
    const fr = frameCopy(p.frame);
    const r = await call('loreSave', { key: c.key, name: c.name, model: c.model || '', bankName: c.bankName || '',
        notes: c.notes || '', picture: url, frameX: fr.x, frameY: fr.y, frameZ: fr.z, voice: '' });
    if (!r.ok) { WP.result(r.why, 'err'); return; }
    WP.result(url ? 'Picture saved' : 'Picture removed', 'ok');
    st.pic = null;
    await load();
}

function goTab(key) {
    if (st.tab === key || !tabs) return;
    st.tab = key;
    tabs.set(key);
    drawTab();
}

/** Go on only when nothing typed would be lost, or the builder says to drop it. */
async function leaveDraft() {
    if (!dirty() && !st.pic) return true;
    const isNew = st.draft && st.draft.isNew;
    return WP.confirm({ title: isNew ? 'Drop this new lore character?' : 'Drop your changes?', danger: true,
        confirmLabel: isNew ? 'Drop it' : 'Drop them',
        body: isNew ? 'They have not been made yet: nothing typed is kept.' : 'What you changed here has not been saved.' });
}

// ============================================================
// Actions and the section
// ============================================================

const actions = {
    wlSearch: (el) => { st.search = el.value || ''; renderList(); },
    wlRefresh: () => { st.acts = {}; load().then(() => WP.result('Up to date', 'ok')); },
    wlSelect: async (el) => {
        const key = el.dataset.id;
        if (key === st.sel) return;
        if (!(await leaveDraft())) return;
        const c = loreOf(key);
        if (!c) return;
        st.sel = key;
        st.draft = draftOf(c);
        st.pic = null;
        delete st.acts[key];   // what they are part of is read fresh each time one is picked
        renderList();
        renderDetail();
    },
    wlNew: async () => {
        if (st.draft && st.draft.isNew) return;
        if (!(await leaveDraft())) return;
        st.sel = NEW;
        st.draft = blank();
        st.pic = null;
        st.tab = 'details';
        renderList();
        renderDetail();
    },
    wlSave: () => save(),
    wlDiscard: () => {
        const d = st.draft;
        if (!d) return;
        if (d.isNew) { st.sel = null; st.draft = null; st.pic = null; renderList(); renderDetail(); return; }
        const c = loreOf(d.key);
        st.draft = c ? draftOf(c) : null;
        renderDetail();
    },
    wlPicEdit: () => {
        const d = st.draft;
        if (!d) return;
        const c = d.isNew ? null : loreOf(d.key);
        st.pic = { url: c ? c.picture || '' : d.picture, frame: frameCopy(c ? c.pictureFrame : d.frame), focus: true };
        renderDetail();
    },
    wlPicClear: () => {
        if (!st.pic) return;
        st.pic.url = '';
        st.pic.frame = frame0();
        st.pic.focus = true;
        renderDetail();
    },
    wlPicCancel: () => { st.pic = null; renderDetail(); },
    wlPicSave: () => savePicture(),
    // Male or Female: a new look in the character editor. A new one is made first (its look is kept on it), and
    // one already made keeps any changes typed here in its draft meanwhile.
    wlLookMake: async (el) => {
        const d = st.draft;
        if (!d || el.disabled) return;
        const gender = el.dataset.arg === 'female' ? 'female' : 'male';
        el.disabled = true;
        const made = d.isNew ? await save() : true;
        el.disabled = false;
        const c = made && st.sel && st.sel !== NEW ? loreOf(st.sel) : null;
        if (c) await editLook(c, gender);
    },
    // Copy my look: a new one is made first; a look made already is replaced only once the builder says so.
    wlLookCopy: async (el) => {
        const d = st.draft;
        if (!d || el.disabled) return;
        const had = d.isNew ? null : loreOf(d.key);
        if (had && had.hasLook && !(await WP.confirm({ title: `Give ${had.name} your look?`, danger: true, confirmLabel: 'Copy my look',
            body: 'The look they have now is replaced by your character\'s as you are now, clothes and all, with a new portrait.' }))) return;
        el.disabled = true;
        el.textContent = 'Copying…';
        const made = d.isNew ? await save() : true;
        const c = made && st.sel && st.sel !== NEW ? loreOf(st.sel) : null;
        if (c) await copyLook(c);
        el.disabled = false;
        el.textContent = 'Copy my look';
    },
    wlLookEdit: async () => {
        const c = st.draft && !st.draft.isNew ? loreOf(st.draft.key) : null;
        if (c && c.hasLook) await editLook(c);
    },
    wlLookClear: async () => {
        const c = st.draft && !st.draft.isNew ? loreOf(st.draft.key) : null;
        if (!c || !c.hasLook) return;
        const ok = await WP.confirm({ title: `Make ${c.name} a game ped?`, danger: true, confirmLabel: 'Use a game ped',
            body: 'Their look made in the character editor and its portrait are taken away. Type the game ped they wear in Ped, and Save.' });
        if (!ok) return;
        const r = await call('loreLook', { key: c.key, look: 'none', image: '' });
        if (!r.ok) { WP.result(r.why, 'err'); return; }
        WP.result('Their look is gone: give them a ped', 'ok');
        await load();
    },
    wlTestOn: async (el) => {
        const d = st.draft;
        if (!d || d.isNew) return;
        el.disabled = true;
        const r = await call('loreTest', { key: d.key, mode: 'on' });
        el.disabled = false;
        if (!r.ok) { WP.result(r.why, 'err'); return; }
        st.turn = {};
        setTest(r.data);
        WP.result(`${trim(d.name) || d.key} is in front of you for 10 minutes`, 'ok');
    },
    wlTestOff: async () => {
        const r = await call('loreTest', { key: 'none', mode: 'off' });
        if (!r.ok) { WP.result(r.why, 'err'); return; }
        setTest(r.data);
        WP.result('Your test NPC is gone', 'ok');
    },
    wlOpenScenario: (el) => {
        if (loreLinks.openScenario) loreLinks.openScenario(el.dataset.arg);
    },
    wlBack: async (el) => {
        const c = loreOf(el.dataset.arg);
        if (!c) return;
        const r = await call('loreSave', { key: c.key, name: c.name, model: c.model || '', bankName: c.bankName || '',
            notes: c.notes || '', picture: c.picture || '', frameX: frameCopy(c.pictureFrame).x,
            frameY: frameCopy(c.pictureFrame).y, frameZ: frameCopy(c.pictureFrame).z, voice: '' });
        if (!r.ok) { WP.result(r.why, 'err'); return; }
        WP.result(`${c.name} is back`, 'ok');
        await load();
    },
    wlRetire: async (el) => {
        const key = el.dataset.arg;
        const c = loreOf(key);
        const ok = await WP.confirm({ title: `Retire ${c ? c.name : key}?`, danger: true, confirmLabel: 'Retire',
            body: 'They leave the pickers, and cards that name them stop working. Their texts, calls and bank records are kept, and Bring back returns them.' });
        if (!ok) return;
        const r = await call('loreRetire', { key });
        if (!r.ok) { WP.result(r.why, 'err'); return; }
        WP.result('Retired', 'ok');
        await load();
    },
};

WhipPanel.registerSection({
    id: SEC,
    group: 'director',
    label: 'Lore characters',
    order: 30,
    render(root) {
        root.appendChild(WP.toolbar({
            left: [WP.btn('New lore character', 'wlNew', 'primary'), WP.btn('Refresh', 'wlRefresh', 'ghost')],
            search: { inputAction: 'wlSearch', placeholder: 'Search lore characters…' },
        }));
        const split = WP.el('div', 'wp-split');
        const col = WP.el('div', 'wp-list-col');
        els.count = WP.el('div', 'wp-list-count', '');
        els.list = WP.el('div', 'wp-list');
        col.appendChild(els.count);
        col.appendChild(els.list);
        split.appendChild(col);
        els.detail = WP.el('div', 'wp-detail wl-detail');
        split.appendChild(els.detail);
        root.appendChild(split);
        renderList();
        renderDetail();
    },
    onEnter() { renderList(); renderDetail(); load(); loadTest(); },
    onEscape() {
        if (WP.dismissDialog()) return true;
        if (st.pic) { actions.wlPicCancel(); return true; }
        if (st.draft && st.draft.isNew) { actions.wlDiscard(); return true; }
        return false;
    },
    actions,
});
