// ========================================
// PAGE TOOLS — reading and pressing a page by its words, and its errors, for any whip page
// ========================================
//
// A plain script (not a module), so any resource's page can load it from spur_core:
//
//     <script src="https://cfx-nui-spur_core/html/js/page-tools.js"></script>
//
// window.WhipProbe = { read(opts), press(opts) }: what the page shows now, and pressing one of its controls as a mouse
// would. spur_core's own page uses it through js/screen-probe.js (ReadScreen / PressScreen, client/screen_probe.lua).
//
//   read  -> { view, focus, text: [lines], controls: [{ id, label, kind, near, state, rect }] }
//            The text in reading order, a line per block, and everything that can be pressed (buttons, fields, lists,
//            tabs, rows with a pointer cursor, anything marked data-act (whip's pages hand clicks out by it: the
//            phone's lock screen is one) and anything marked data-probe-press: a keyboard-only menu like /w's,
//            which takes no mouse but answers a press), numbered for press.
//   press -> one control: by `id` from the last read, or by `label` (exact, then starts with, then contains),
//            narrowed by `near` (the heading above it) and `kind`, or the `index`th of several. Pressed the way a
//            mouse would, at its middle, so the page's own handlers run; `text` types into a field, `choose` picks
//            from a list. Several matches and no index: the answer lists them instead of guessing.
//
// IN ANOTHER RESOURCE'S PAGE (the phone, Whiplash, the dealership) it also answers spur_core's asks, which that
// resource's lib/satellite.lua passes in as a `whipProbe` message, and sends the page's errors to the error tap (the
// same as js/error-tap.js does for spur_core's page): both through that resource's own NUI callbacks.

(function () {
    const CONTROL = 'button, a[href], input, select, textarea, summary, [role=button], [role=tab], [role=menuitem], '
        + '[role=option], [role=checkbox], [role=radio], [role=switch], [role=slider], [onclick], [contenteditable=true], '
        + '[data-probe-press], [data-act]:not([data-act=noop])';
    const HEADING = 'h1, h2, h3, h4, h5, h6, [role=heading], legend';
    const HEADING_CLASS = /(^|[-_\s])(title|header|heading|caption)($|[-_\s])/i;
    const SKIP = new Set(['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEMPLATE', 'svg', 'CANVAS', 'VIDEO', 'IFRAME']);

    const MAX_LINES = 400, MAX_LINE = 200, MAX_TEXT = 12000, MAX_CONTROLS = 300, MAX_LABEL = 80;

    let lastControls = [];   // [element]; a control's id is its place here + 1

    const squash = (s) => String(s || '').replace(/\s+/g, ' ').trim();
    const clip = (s, n) => (s.length > n ? s.slice(0, n - 1) + '…' : s);
    const cut = (a, b) => a.left < b.right && a.right > b.left && a.top < b.bottom && a.bottom > b.top;
    const meet = (a, b) => ({ left: Math.max(a.left, b.left), right: Math.min(a.right, b.right),
        top: Math.max(a.top, b.top), bottom: Math.min(a.bottom, b.bottom) });

    // CEF 103 measures a box inside a `zoom` UNZOOMED: a 100px probe in the box says which (as js/pad-cursor.js).
    const zoomFix = new WeakMap();
    function rectScale(node) {
        let k = 1, host = null;
        for (let n = node; n && n !== document.documentElement; n = n.parentElement) {
            const z = parseFloat(getComputedStyle(n).zoom);
            if (z > 0 && Math.abs(z - 1) > 0.001) { k *= z; if (!host) host = n; }
        }
        if (!host || Math.abs(k - 1) < 0.01) return 1;
        if (zoomFix.has(host)) return zoomFix.get(host);
        const probe = document.createElement('div');
        probe.style.cssText = 'position:absolute;left:0;top:0;width:100px;height:1px;visibility:hidden;pointer-events:none';
        host.appendChild(probe);
        const w = probe.getBoundingClientRect().width;
        probe.remove();
        const fix = Math.abs(w - 100 * k) < Math.abs(w - 100) ? 1 : k;
        zoomFix.set(host, fix);
        return fix;
    }
    function screenRect(node) {
        const r = node.getBoundingClientRect(), k = rectScale(node);
        return { left: r.left * k, right: r.right * k, top: r.top * k, bottom: r.bottom * k,
                 width: r.width * k, height: r.height * k };
    }

    function kindOf(el) {
        const role = el.getAttribute('role');
        if (role) return role === 'menuitem' || role === 'option' ? 'choice' : role;
        const t = el.tagName;
        if (t === 'BUTTON' || t === 'SUMMARY') return 'button';
        if (t === 'A') return 'link';
        if (t === 'SELECT') return 'list';
        if (t === 'TEXTAREA' || el.isContentEditable) return 'field';
        if (t === 'INPUT') {
            const ty = (el.type || 'text').toLowerCase();
            if (ty === 'checkbox' || ty === 'radio') return ty === 'radio' ? 'radio' : 'checkbox';
            if (ty === 'range') return 'slider';
            if (ty === 'button' || ty === 'submit' || ty === 'reset') return 'button';
            return 'field';
        }
        return 'row';
    }

    function labelOf(el) {
        const aria = el.getAttribute('aria-label');
        if (aria) return squash(aria);
        if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.tagName === 'SELECT') {
            if (el.labels && el.labels[0]) { const l = squash(el.labels[0].innerText); if (l) return l; }
            const p = el.getAttribute('placeholder') || el.getAttribute('title') || el.name;
            if (p) return squash(p);
            if (el.type === 'button' || el.type === 'submit') return squash(el.value);
        }
        const words = squash(el.innerText);
        if (words) return words;
        const img = el.querySelector('img[alt]');
        return squash(el.getAttribute('title') || (img && img.alt) || el.dataset.action || el.dataset.act || '');
    }

    /** For a control with few words ("Change", "×"): the words of the row it sits in, which tell five of them apart. */
    function rowOf(el, label) {
        if (label.length > 24) return '';
        let n = el.parentElement;
        for (let up = 0; n && n !== document.body && up < 4; up++, n = n.parentElement) {
            const all = squash(n.innerText);
            if (all.length > label.length + 2) return clip(squash(all.replace(label, ' ')), 60);
        }
        return '';
    }

    function stateOf(el) {
        const s = {};
        if (el.disabled || el.getAttribute('aria-disabled') === 'true' || el.classList.contains('disabled')) s.disabled = true;
        if (el.checked || el.getAttribute('aria-checked') === 'true' || el.getAttribute('aria-pressed') === 'true') s.on = true;
        if (el.getAttribute('aria-selected') === 'true' || el.classList.contains('active') || el.classList.contains('selected')) s.selected = true;
        if (el.tagName === 'SELECT') s.value = clip(squash(el.options[el.selectedIndex]?.text), 60);
        else if ((el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') && kindOf(el) !== 'checkbox') {
            s.value = el.type === 'password' ? (el.value ? '••••' : '') : clip(String(el.value ?? ''), 60);
        }
        return s;
    }

    /**
     * One walk of the page in reading order: the visible text a line per block, every control, and the heading each
     * control sits under. Hidden boxes (display none, opacity 0, scrolled out of their box) are left out.
     */
    function scan() {
        const view = { left: 0, top: 0, right: window.innerWidth, bottom: window.innerHeight };
        const lines = [], controls = [], blocks = new Map();
        const styles = new Map();
        const style = (el) => { let s = styles.get(el); if (!s) { s = getComputedStyle(el); styles.set(el, s); } return s; };
        let near = '', textLen = 0;

        const blockOf = (el) => {
            for (let n = el; n && n !== document.body; n = n.parentElement) {
                const d = style(n).display;
                if (d !== 'inline' && d !== 'contents') return n;
            }
            return document.body;
        };

        // visibility is inherited, so a child's own style already says whether a hidden box above it hides it too
        function walk(el, box, inControl) {
            if (SKIP.has(el.tagName)) return;
            const s = style(el);
            if (s.display === 'none' || parseFloat(s.opacity) === 0) return;
            const shown = s.visibility === 'visible';
            const r = el.getBoundingClientRect();
            const onScreen = (r.width > 0 || r.height > 0) && cut(r, box);

            if (shown && onScreen) {
                // a row's own title is part of the row, not a heading over what follows
                const heading = !inControl && (el.matches(HEADING)
                    || (HEADING_CLASS.test(el.className || '') && el.children.length < 4));
                if (heading) { const h = squash(el.innerText); if (h && h.length <= 60) near = h; }
                const pointer = s.cursor === 'pointer' && !inControl && el.parentElement && style(el.parentElement).cursor !== 'pointer';
                // pointer-events none takes no mouse, so it is no control, unless it says it answers a press
                const pressable = s.pointerEvents !== 'none' || el.hasAttribute('data-probe-press');
                if ((el.matches(CONTROL) || pointer) && controls.length < MAX_CONTROLS && pressable) {
                    controls.push({ el, near });
                    inControl = true;
                }
                for (const n of el.childNodes) {
                    if (n.nodeType !== 3 || textLen >= MAX_TEXT) continue;
                    const t = squash(n.nodeValue);
                    if (!t) continue;
                    const b = blockOf(el);
                    let line = blocks.get(b);
                    if (!line) {
                        if (lines.length >= MAX_LINES) continue;
                        line = { parts: [] };
                        blocks.set(b, line);
                        lines.push(line);
                    }
                    line.parts.push(t);
                    textLen += t.length;
                }
            }
            let inner = box;
            if (s.overflowX !== 'visible' || s.overflowY !== 'visible') inner = meet(box, r);
            for (const c of el.children) walk(c, inner, inControl);
        }
        walk(document.body, view, false);
        return {
            lines: lines.map((l) => clip(l.parts.join(' '), MAX_LINE)),
            controls,
        };
    }

    function read(opts) {
        opts = opts || {};
        const { lines, controls } = scan();
        lastControls = controls.map((c) => c.el);
        const under = opts.under ? squash(opts.under).toLowerCase() : null;
        const out = {
            view: { width: window.innerWidth, height: window.innerHeight },
            focus: document.activeElement && document.activeElement !== document.body
                ? clip(labelOf(document.activeElement), MAX_LABEL) : null,
        };
        if (opts.text !== false) out.text = lines;
        if (opts.controls !== false) {
            out.controls = [];
            controls.forEach((c, i) => {
                if (under && !c.near.toLowerCase().includes(under)) return;
                const r = screenRect(c.el);
                const state = stateOf(c.el);
                const label = labelOf(c.el);
                out.controls.push({
                    id: i + 1, label: clip(label, MAX_LABEL) || '(no words)', kind: kindOf(c.el),
                    near: c.near || undefined, row: rowOf(c.el, label) || undefined,
                    state: Object.keys(state).length ? state : undefined,
                    rect: [Math.round(r.left), Math.round(r.top), Math.round(r.width), Math.round(r.height)],
                });
            });
        }
        return out;
    }

    /** The one control `t` means, or { err } / { ambiguous }. */
    function find(t) {
        if (t.id != null) {
            const el = lastControls[t.id - 1];
            if (!el) return { err: `no control ${t.id} in the last read` };
            if (!el.isConnected) return { err: `control ${t.id} is gone (the screen changed): read again` };
            return { el };
        }
        const want = squash(t.label).toLowerCase();
        if (!want) return { err: 'give an id or a label' };
        const { controls } = scan();
        lastControls = controls.map((c) => c.el);
        let pool = controls.map((c, i) => ({ ...c, id: i + 1, label: labelOf(c.el).toLowerCase() }));
        // near: the heading above it, or the row it sits in
        if (t.near) {
            const n = squash(t.near).toLowerCase();
            pool = pool.filter((c) => c.near.toLowerCase().includes(n) || rowOf(c.el, labelOf(c.el)).toLowerCase().includes(n));
        }
        if (t.kind) pool = pool.filter((c) => kindOf(c.el) === t.kind);
        let hits = pool.filter((c) => c.label === want);
        if (!hits.length) hits = pool.filter((c) => c.label.startsWith(want));
        if (!hits.length) hits = pool.filter((c) => c.label.includes(want));
        if (!hits.length) return { err: `nothing on screen called "${t.label}"` + (t.near ? ` under "${t.near}"` : '') };
        if (t.index) {
            const h = hits[t.index - 1];
            return h ? { el: h.el } : { err: `only ${hits.length} called "${t.label}"` };
        }
        if (hits.length > 1) {
            return { ambiguous: hits.slice(0, 20).map((c) => {
                const label = labelOf(c.el);
                return { id: c.id, label: clip(label, MAX_LABEL), kind: kindOf(c.el), near: c.near || undefined,
                    row: rowOf(c.el, label) || undefined };
            }) };
        }
        return { el: hits[0].el };
    }

    const frames = (n) => new Promise((res) => { const step = () => (n-- > 0 ? requestAnimationFrame(step) : res()); step(); });

    function fire(target, type, x, y, button = 0, buttons = 0) {
        const Ctor = type.startsWith('pointer') ? PointerEvent : MouseEvent;
        target.dispatchEvent(new Ctor(type, { bubbles: true, cancelable: true, view: window, clientX: x, clientY: y,
            button, buttons, pointerType: 'mouse', isPrimary: true }));
    }

    async function press(opts) {
        opts = opts || {};
        const f = find(opts.target || {});
        if (!f.el) {
            if (f.ambiguous) return { ambiguous: f.ambiguous };
            throw new Error(f.err);
        }
        const el = f.el;
        const label = clip(labelOf(el), MAX_LABEL);
        if (stateOf(el).disabled) throw new Error(`"${label}" is disabled`);

        let r = screenRect(el);
        if (r.bottom < 0 || r.top > window.innerHeight || r.right < 0 || r.left > window.innerWidth) {
            el.scrollIntoView({ block: 'nearest', inline: 'nearest' });
            await frames(2);
            r = screenRect(el);
        }
        const x = r.left + r.width / 2, y = r.top + r.height / 2;
        const top = document.elementFromPoint(x, y);
        const target = top && (top === el || el.contains(top)) ? top : el;
        const covered = target === el && top && top !== el && !el.contains(top) && !el.hasAttribute('data-probe-press')
            ? clip(labelOf(top), MAX_LABEL) || top.tagName : undefined;

        if (opts.choose != null) {
            if (el.tagName !== 'SELECT') throw new Error(`"${label}" is not a list`);
            const want = squash(opts.choose).toLowerCase();
            const opt = [...el.options].find((o) => squash(o.text).toLowerCase() === want)
                || [...el.options].find((o) => squash(o.text).toLowerCase().includes(want));
            if (!opt) throw new Error(`"${label}" has no choice "${opts.choose}"`);
            el.value = opt.value;
            el.dispatchEvent(new Event('input', { bubbles: true }));
            el.dispatchEvent(new Event('change', { bubbles: true }));
            await frames(2);
            return { pressed: label, chose: squash(opt.text), covered };
        }
        if (opts.text != null) {
            if (kindOf(el) !== 'field') throw new Error(`"${label}" is not a text field`);
            el.focus();
            if (el.isContentEditable) el.textContent = String(opts.text);
            else el.value = String(opts.text);
            el.dispatchEvent(new Event('input', { bubbles: true }));
            el.dispatchEvent(new Event('change', { bubbles: true }));
            if (opts.enter) {
                for (const type of ['keydown', 'keyup']) {
                    el.dispatchEvent(new KeyboardEvent(type, { key: 'Enter', code: 'Enter', keyCode: 13, bubbles: true, cancelable: true }));
                }
            }
            await frames(2);
            return { pressed: label, typed: String(opts.text).length, covered };
        }

        const right = opts.button === 'right';
        const b = right ? 2 : 0, bs = right ? 2 : 1;
        fire(target, 'pointerover', x, y); fire(target, 'mouseover', x, y); fire(target, 'mousemove', x, y);
        const once = () => {
            fire(target, 'pointerdown', x, y, b, bs); fire(target, 'mousedown', x, y, b, bs);
            if (!right && typeof el.focus === 'function') el.focus({ preventScroll: true });
            fire(target, 'pointerup', x, y, b, 0); fire(target, 'mouseup', x, y, b, 0);
            fire(target, right ? 'contextmenu' : 'click', x, y, b, 0);
        };
        once();
        if (opts.button === 'double') { once(); fire(target, 'dblclick', x, y); }
        await frames(2);
        return { pressed: label, kind: kindOf(el), covered };
    }

    window.WhipProbe = { read, press };

    // ---- In another resource's page: spur_core's asks, and the page's errors ----
    const res = typeof GetParentResourceName === 'function' ? GetParentResourceName() : null;
    if (!res || res === 'spur_core') return;
    const post = (name, body) => fetch(`https://${res}/${name}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
    }).catch(() => {});

    // ONLY WHAT FIVEM SENDS (main.js's fromFiveM): another resource's frame can postMessage straight into this page and
    // press its buttons, outside developer mode (audit 20, CLI-3). This page's own SendNUIMessage has no source, or the
    // root page's; a sibling frame is neither, and the browser sets `source`.
    const fromFiveM = (ev) => { const s = ev.source; return s === null || s === window || s === window.parent || s === window.top; };
    window.addEventListener('message', async (ev) => {
        if (!fromFiveM(ev)) return;
        const d = ev.data;
        if (!d || d.action !== 'whipProbe') return;
        try {
            const result = d.kind === 'press' ? await press(d.opts) : read(d.opts);
            post('whipProbe', { token: d.token, ok: true, result });
        } catch (e) {
            post('whipProbe', { token: d.token, ok: false, err: String(e && e.message || e) });
        }
    });

    const say = (v) => (v instanceof Error ? v.stack || v.message
        : typeof v === 'object' && v !== null ? (() => { try { return JSON.stringify(v); } catch (e) { return String(v); } })() : String(v));
    let windowStart = 0, inWindow = 0;
    const tap = (text) => {
        const now = Date.now();
        if (now - windowStart > 1000) { windowStart = now; inWindow = 0; }
        if (++inWindow > 20) return;
        post('whipErrorTap', { text: String(text).slice(0, 2000) });
    };
    window.addEventListener('error', (ev) => tap(`${ev.message}${ev.filename ? ` (${ev.filename.replace(/^.*\/html\//, '')}:${ev.lineno})` : ''}`));
    window.addEventListener('unhandledrejection', (ev) => tap('a promise failed with nobody to catch it: ' + say(ev.reason)));
    const consoleError = console.error.bind(console);
    console.error = (...args) => { consoleError(...args); tap(args.map(say).join(' ')); };
})();
