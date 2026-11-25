import { NuiRouter } from './router.js';
import { padGlyph } from './pad-glyphs.js';

// ========================================
// OBJECT VIEWER — NUI
//
// Draws a name tag on every entity the Lua side is tracking, and expands the one you are
// looking at into a full detail card. Screen positions arrive already projected from
// tools/objectviewer.lua, exactly like the 3D interaction layer does it.
//
// One element per entity, and the SAME element is the tag and the card — .focused just
// expands it. Keeping them as one element is what makes the card appear at the entity rather
// than beside it, and means there is no second thing to keep in sync with the tag's position.
//
// THE HOUSE CARD: every part of the open card is built with the tag and only
// opened by .focused (css/object-viewer.css says how it looks) — the disc with the kind's glyph,
// the name as the title, the readings, the copy key — so focusing is a class
// change and the card animates open rather than being made on the spot.
//
// WHAT GOES IN THE CARD IS DECIDED IN LUA. The rows arrive as a list of {k, v} pairs and are
// rendered as given. That keeps every judgement about what is worth showing — and which rows
// only sometimes apply, like the whip one — in the file that has the entity in front of it,
// rather than split across two languages.
// ========================================

(function() {
    const layer = document.getElementById('ov-layer');

    let tags = {};       // [entity] = { el, nameEl, rowsEl, disc, actText, kind, copiedTimer }
    let focusedId = null;

    // Kind -> class. Object blue, ped green, vehicle red; the colours live in the CSS.
    const KIND_CLASS = {
        object:  'ov-kind-object',
        ped:     'ov-kind-ped',
        vehicle: 'ov-kind-vehicle',
    };

    // Kind -> the disc's glyph (js/glyphs.js).
    const KIND_GLYPH = { object: 'object', ped: 'ped', vehicle: 'car' };
    const GLYPHS = () => (window.WhipGlyphs && window.WhipGlyphs.glyphs) || {};

    // What the copy key does (tools/objectviewer.lua: the name, the hash, and a vector4 of where it is),
    // and how long the card says it did.
    const COPY_TEXT = 'Copy name, hash and spot';
    const COPIED_MS = 1400;

    // textContent throughout, never innerHTML: a model name is game data. (The glyphs are whip's own.)
    function el(tag, cls, text) {
        const node = document.createElement(tag);
        if (cls) node.className = cls;
        if (text !== undefined && text !== null) node.textContent = String(text);
        return node;
    }

    function createTag(id, name, kind) {
        const tag = el('div', 'ov-tag ' + (KIND_CLASS[kind] || KIND_CLASS.object));
        tag.appendChild(el('div', 'ov-dot'));

        const card = el('div', 'ov-card');
        const head = el('div', 'ov-head');
        const disc = el('div', 'ov-disc');
        disc.innerHTML = GLYPHS()[KIND_GLYPH[kind] || 'object'] || '';
        const text = el('div', 'ov-head-text');
        // The kind is the disc's glyph and colour only — no chip naming it.
        const nameEl = el('div', 'ov-name', name);
        text.append(nameEl);
        head.append(disc, text);

        const more = el('div', 'ov-more');
        const rowsEl = el('div', 'ov-readings');
        // The copy key: G on a keyboard; on a pad the same control is D-pad left (its picture).
        const act = el('div', 'ov-act');
        const kbm = el('span', 'ov-keys ov-k-kbm');
        kbm.appendChild(el('span', 'ov-key', 'G'));
        const pad = el('span', 'ov-keys ov-k-pad');
        const img = padGlyph('dpad_left', 'ov-pad');
        if (img) pad.appendChild(img);
        const actText = el('span', 'ov-act-text', COPY_TEXT);
        act.append(kbm, pad, actText);
        more.append(rowsEl, act);

        card.append(head, more);
        tag.appendChild(card);
        layer.appendChild(tag);

        // Fade in on the next frame — the element needs to exist at opacity 0 for one frame
        // or there is no start value to transition from.
        requestAnimationFrame(function() { tag.classList.add('visible'); });

        tags[id] = { el: tag, nameEl, rowsEl, disc, actText, kind, copiedTimer: 0 };
        return tags[id];
    }

    function removeTag(id) {
        const t = tags[id];
        if (!t) return;
        clearTimeout(t.copiedTimer);
        if (t.el.parentNode) t.el.parentNode.removeChild(t.el);
        delete tags[id];
        if (focusedId === id) focusedId = null;
    }

    function fillDetail(id, d) {
        const t = tags[id];
        if (!t) return;

        // Rebuilt rather than patched in place. This only runs when the focused entity changes,
        // which is the same moment the card is expanding anyway, so nothing visibly redraws —
        // and the row LIST varies between entities, so there is no stable set to patch.
        t.rowsEl.textContent = '';
        const rows = d.rows || [];
        for (let i = 0; i < rows.length; i++) {
            t.rowsEl.appendChild(el('span', 'ov-r-label', rows[i].k));
            t.rowsEl.appendChild(el('span', 'ov-r-value', rows[i].v));
        }

        // The name is resolved on the Lua side and sent with the label, but an entity whose
        // name arrived as a bare hash gets a second chance here — by the time it is focused
        // the model may have finished streaming in.
        if (d.name && d.name !== 'unknown' && t.nameEl.textContent !== d.name) {
            t.nameEl.textContent = d.name;
        }
    }

    function setFocus(id) {
        if (focusedId === id) return;
        if (focusedId != null && tags[focusedId]) {
            tags[focusedId].el.classList.remove('focused');
        }
        focusedId = id;
        if (id != null && tags[id]) {
            tags[id].el.classList.add('focused');
        }
    }

    // --- Message handlers, called from main.js ---

    window.ovShow = function() {
        layer.style.display = 'block';
        // Anything left over belongs to the previous session — the pools will re-announce
        // everything currently in range within one scan.
        for (const id in tags) removeTag(id);
        tags = {};
        focusedId = null;
    };

    window.ovHide = function() {
        for (const id in tags) removeTag(id);
        tags = {};
        focusedId = null;
        layer.style.display = 'none';
    };

    window.ovLabels = function(msg) {
        if (msg.removed) {
            for (let i = 0; i < msg.removed.length; i++) removeTag(msg.removed[i]);
        }
        if (msg.labels) {
            for (let i = 0; i < msg.labels.length; i++) {
                const l = msg.labels[i];
                if (!tags[l.id]) createTag(l.id, l.name, l.kind);
            }
        }
    };

    window.ovFrame = function(msg) {
        layer.style.display = 'block';

        const positions = msg.positions;
        if (positions) {
            const w = window.innerWidth;
            const h = window.innerHeight;
            // Everything not named in this frame is off screen or behind us. Hiding rather
            // than removing keeps the element (and its detail rows) alive for when it comes
            // back into view a frame later.
            const seen = {};
            for (let i = 0; i < positions.length; i += 3) {
                const id = positions[i];
                const t = tags[id];
                seen[id] = true;
                if (t) {
                    t.el.style.left = (positions[i + 1] * w) + 'px';
                    t.el.style.top  = (positions[i + 2] * h) + 'px';
                    t.el.classList.remove('offscreen');
                }
            }
            for (const id in tags) {
                if (!seen[id]) tags[id].el.classList.add('offscreen');
            }
        }

        if (msg.detail !== undefined && msg.detail !== false && msg.focus) {
            fillDetail(msg.focus, msg.detail);
        }

        setFocus(msg.focus ? msg.focus : null);
    };

    // Copied: the ring turns green round a tick and the key's words say so, then the card is itself
    // again (the coords readout's way). A second copy while it shows starts the time again.
    window.ovCopied = function() {
        const t = focusedId != null ? tags[focusedId] : null;
        if (!t) return;
        t.el.classList.add('copied');
        t.disc.innerHTML = GLYPHS().success || '';
        t.actText.textContent = 'Copied';
        clearTimeout(t.copiedTimer);
        t.copiedTimer = setTimeout(function() {
            t.el.classList.remove('copied');
            t.disc.innerHTML = GLYPHS()[KIND_GLYPH[t.kind] || 'object'] || '';
            t.actText.textContent = COPY_TEXT;
        }, COPIED_MS);
    };
})();


// ROUTER REGISTRATION — see router.js's header. IIFE file; functions resolved via window.
NuiRouter.register('ovShow', () => ovShow());
NuiRouter.register('ovHide', () => ovHide());
NuiRouter.register('ovLabels', (d) => ovLabels(d));
NuiRouter.register('ovFrame', (d) => ovFrame(d));
NuiRouter.register('ovCopied', () => ovCopied());