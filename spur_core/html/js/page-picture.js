// ========================================
// PAGE PICTURE — whip's page drawn over a game picture (js/screenshot.js, a shot with `ui`)
// ========================================
//
// A shot reads the game's picture alone: whip's page is laid over the game by Cfx.re afterwards, and nothing hands a
// script the two together. This draws the page as it looks right now into the picture. It copies every element shown
// into an SVG image, each carrying its own computed style (what differs from the browser's default for it or from its
// parent's), its ::before / ::after, the fonts it uses and its pictures and canvases as data, every scrolled box at its
// scroll. The game picture goes in underneath inside the same image, so frosted panels blur the game as on screen.
// Nothing runs between shots: it is built when a shot asks, and let go after.
//
// Not in it: other resources' pages (the phone, Whiplash, the dealership: frames of their own); a WebGL canvas with
// nothing drawn in the frame it is read (a map that draws only when it changes); a moving element, caught where it is.

const XHTML = 'http://www.w3.org/1999/xhtml';
const SKIP_TAGS = new Set(['SCRIPT', 'STYLE', 'LINK', 'META', 'NOSCRIPT', 'TEMPLATE', 'IFRAME', 'BASE', 'TITLE', 'HEAD']);
// A still has no use for these, and an animation or transition left in it would start again from its beginning.
// The block / inline properties are the left / right / top / bottom ones again under other names (whip is written
// left to right, top to bottom), so the copy says each once.
const SKIP_PROP = /^(--|animation|transition)|(^|-)(block|inline)(-|$)/;
// What an SVG icon's own shapes take from the page's stylesheets.
const SVG_PROPS = ['fill', 'fill-opacity', 'fill-rule', 'stroke', 'stroke-width', 'stroke-opacity', 'stroke-linecap',
    'stroke-linejoin', 'stroke-dasharray', 'stroke-dashoffset', 'opacity', 'color', 'display', 'visibility',
    'transform', 'transform-origin'];
const PSEUDOS = ['::before', '::after'];

// url -> Promise<data URL | null>, kept between shots (fonts and pictures do not change). One that failed is not kept
// (asked again next shot), and the oldest go once there are DATA_URLS_MAX: a page that draws many pictures over a
// session must not keep a copy of every one.
const dataUrls = new Map();
const DATA_URLS_MAX = 300;
const defaults = {};          // tag -> { prop: the browser's own value }, the same in every shot

function dataUrl(url) {
    if (!dataUrls.has(url)) {
        const p = fetch(url).then((r) => (r.ok ? r.blob() : null)).then((b) => b && new Promise((res) => {
            const fr = new FileReader();
            fr.onload = () => res(fr.result);
            fr.onerror = () => res(null);
            fr.readAsDataURL(b);
        })).catch(() => null).then((v) => {
            if (v == null && dataUrls.get(url) === p) dataUrls.delete(url);
            return v;
        });
        dataUrls.set(url, p);
        while (dataUrls.size > DATA_URLS_MAX) dataUrls.delete(dataUrls.keys().next().value);
    }
    return dataUrls.get(url);
}

/** A page with no stylesheet of its own: what the browser gives each tag before any of whip's CSS. */
async function sandbox() {
    const f = document.createElement('iframe');
    f.setAttribute('aria-hidden', 'true');
    f.style.cssText = 'position:fixed;left:-10000px;top:0;width:64px;height:64px;border:0;visibility:hidden';
    f.srcdoc = '<!DOCTYPE html><html><head></head><body></body></html>';
    const loaded = new Promise((r) => { f.onload = r; });
    document.documentElement.appendChild(f);
    await loaded;
    return f;
}

function defaultsFor(box, tag, svg) {
    const key = svg ? 'svg:' + tag : tag;
    let d = defaults[key];
    if (d) return d;
    const doc = box.contentDocument;
    const el = svg ? doc.createElementNS('http://www.w3.org/2000/svg', tag) : doc.createElement(tag);
    doc.body.appendChild(el);
    const cs = box.contentWindow.getComputedStyle(el);
    d = {};
    for (let i = 0; i < cs.length; i++) d[cs[i]] = cs.getPropertyValue(cs[i]);
    el.remove();
    defaults[key] = d;
    return d;
}

/**
 * A style attribute's text: each property written unless it is both the browser's default for this tag and what the
 * parent has (then the copy gets the same value either way, inherited or not). `shift`: the parent's scroll, put back
 * as a move.
 */
function styleText(cs, parent, dflt, shift, urls) {
    let s = '';
    for (let i = 0; i < cs.length; i++) {
        const p = cs[i];
        if (SKIP_PROP.test(p)) continue;
        let v = cs.getPropertyValue(p);
        if (p === 'transform' && shift) {
            v = `translate(${-shift.x}px, ${-shift.y}px)` + (v && v !== 'none' ? ' ' + v : '');
        } else if (v === dflt[p] && (!parent || v === parent.getPropertyValue(p))) {
            continue;
        }
        if (v.includes('url(')) {
            for (const m of v.matchAll(/url\("?([^")]+)"?\)/g)) if (!m[1].startsWith('data:')) urls.add(m[1]);
        }
        s += p + ':' + v + ';';
    }
    if (shift && !s.includes('transform:')) s += `transform:translate(${-shift.x}px, ${-shift.y}px);`;
    return s;
}

function copySvg(el) {
    const clone = el.cloneNode(true);
    const live = [el, ...el.querySelectorAll('*')];
    const copies = [clone, ...clone.querySelectorAll('*')];
    for (let i = 1; i < live.length; i++) {
        const cs = getComputedStyle(live[i]);
        let s = '';
        for (const p of SVG_PROPS) s += p + ':' + cs.getPropertyValue(p) + ';';
        copies[i].setAttribute('style', s);
    }
    return clone;
}

/** The copy of one element and everything under it, or null for what is not shown. */
function copy(node, parent, shift, k) {
    if (node.nodeType === 3) return document.createTextNode(node.nodeValue);
    if (node.nodeType !== 1 || SKIP_TAGS.has(node.tagName)) return null;
    const cs = getComputedStyle(node);
    if (cs.display === 'none') return null;
    const svg = node instanceof SVGElement;
    const tag = node === document.body ? 'div' : node.localName;
    let el;
    if (svg) {
        el = copySvg(node);
    } else if (node.tagName === 'CANVAS' || node.tagName === 'VIDEO') {
        el = document.createElementNS(XHTML, 'img');
        const shot = k.canvases.get(node);
        if (shot) el.setAttribute('src', shot);
    } else {
        el = document.createElementNS(XHTML, tag);
    }
    k.fonts.add(cs.fontFamily);
    let style = styleText(cs, parent, defaultsFor(k.box, el.localName, svg), shift, k.urls);
    if (node === document.body && cs.position === 'static') style += 'position:absolute;left:0;top:0;';
    el.setAttribute('style', style);
    if (svg) return el;

    switch (node.tagName) {
        case 'IMG': {
            const src = node.currentSrc || node.src;
            if (src) { el.setAttribute('src', src); if (!src.startsWith('data:')) k.urls.add(src); }
            return el;
        }
        case 'INPUT':
            el.setAttribute('type', node.type);
            if (node.type === 'checkbox' || node.type === 'radio') { if (node.checked) el.setAttribute('checked', ''); }
            else { el.setAttribute('value', node.value); if (node.placeholder) el.setAttribute('placeholder', node.placeholder); }
            return el;
        case 'TEXTAREA':
            el.textContent = node.value;
            return el;
        case 'SELECT': {
            const o = document.createElementNS(XHTML, 'option');
            o.textContent = node.selectedOptions[0] ? node.selectedOptions[0].text : '';
            el.appendChild(o);
            return el;
        }
        case 'CANVAS': case 'VIDEO':
            return el;
    }

    // ::before and ::after, as rules on a class of the copy's own
    const classes = [];
    for (const which of PSEUDOS) {
        const ps = getComputedStyle(node, which);
        if (!ps.content || ps.content === 'none' || ps.content === 'normal') continue;
        const name = 'p' + (++k.n);
        classes.push(name);
        k.fonts.add(ps.fontFamily);
        k.rules.push(`.${name}${which}{content:${ps.content};${styleText(ps, cs, defaultsFor(k.box, 'span'), null, k.urls)}}`);
    }
    if (classes.length) el.setAttribute('class', classes.join(' '));

    const scrolled = (node.scrollLeft || node.scrollTop) ? { x: node.scrollLeft, y: node.scrollTop } : null;
    for (const child of node.childNodes) {
        const c = copy(child, cs, child.nodeType === 1 ? scrolled : null, k);
        if (c) el.appendChild(c);
    }
    return el;
}

/** Every font the copy uses, as @font-face rules carrying the font itself. */
async function fontRules(families) {
    const used = new Set();
    for (const f of families) for (const name of f.split(',')) used.add(name.trim().replace(/^["']|["']$/g, '').toLowerCase());
    const out = [];
    const walk = async (rules, base) => {
        for (const r of rules) {
            if (r.styleSheet) { await walkSheet(r.styleSheet); continue; }
            if (r.cssRules && !(r instanceof CSSFontFaceRule)) { await walk(r.cssRules, base); continue; }
            if (!(r instanceof CSSFontFaceRule)) continue;
            const family = r.style.getPropertyValue('font-family').trim().replace(/^["']|["']$/g, '').toLowerCase();
            if (!used.has(family)) continue;
            let text = r.cssText;
            for (const m of [...text.matchAll(/url\("?([^")]+)"?\)/g)]) {
                if (m[1].startsWith('data:')) continue;
                const data = await dataUrl(new URL(m[1], base).href);
                if (data) text = text.split(m[0]).join(`url("${data}")`);
            }
            out.push(text);
        }
    };
    const walkSheet = async (sheet) => {
        let rules;
        try { rules = sheet.cssRules; } catch (e) { return; }   // another origin's: not readable
        await walk(rules, sheet.href || location.href);
    };
    for (const sheet of document.styleSheets) await walkSheet(sheet);
    return out;
}

/** Each canvas and video as a picture, read in a frame just after the page has drawn into it. */
async function readCanvases() {
    const shots = new Map();
    await new Promise((r) => requestAnimationFrame(() => {
        for (const c of document.querySelectorAll('canvas, video')) {
            if (!c.getClientRects().length) continue;   // not shown: not copied either
            try {
                if (c.tagName === 'CANVAS') {
                    if (c.width && c.height) shots.set(c, c.toDataURL('image/png'));
                } else if (c.videoWidth) {
                    const t = document.createElement('canvas');
                    t.width = c.videoWidth; t.height = c.videoHeight;
                    t.getContext('2d').drawImage(c, 0, 0);
                    shots.set(c, t.toDataURL('image/png'));
                }
            } catch (e) { /* another origin's picture: left out */ }
        }
        r();
    }));
    return shots;
}

/**
 * The page as it looks now, over `game` (a canvas of the game's picture), as a new canvas `w` x `h`.
 * @param {HTMLCanvasElement} game
 * @param {{ type?: string, quality?: number }} [enc] how the game picture is kept inside the image
 */
export async function pagePicture(game, w, h, enc = {}) {
    const vw = window.innerWidth, vh = window.innerHeight;
    const box = await sandbox();
    let svg;
    try {
        const k = { box, canvases: await readCanvases(), fonts: new Set(), urls: new Set(), rules: [], n: 0 };
        const page = copy(document.body, null, null, k);

        const root = document.createElementNS(XHTML, 'div');
        root.setAttribute('style', `position:relative;width:${vw}px;height:${vh}px;overflow:hidden;margin:0`);
        const css = document.createElementNS(XHTML, 'style');
        css.textContent = (await fontRules(k.fonts)).join('\n') + '\n' + k.rules.join('\n')
            + '\n*::-webkit-scrollbar{display:none}';
        root.appendChild(css);
        const under = document.createElementNS(XHTML, 'img');
        under.setAttribute('src', game.toDataURL(enc.type === 'image/png' ? 'image/png' : 'image/jpeg', 0.95));
        under.setAttribute('style', 'position:absolute;left:0;top:0;width:100%;height:100%;display:block');
        root.appendChild(under);
        if (page) root.appendChild(page);

        svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${vw} ${vh}">`
            + `<foreignObject x="0" y="0" width="${vw}" height="${vh}">${new XMLSerializer().serializeToString(root)}`
            + '</foreignObject></svg>';
        const found = await Promise.all([...k.urls].map(async (u) => [u, await dataUrl(new URL(u, location.href).href)]));
        for (const [u, data] of found) {
            if (!data) continue;
            svg = svg.split(u).join(data);
            if (u.includes('&')) svg = svg.split(u.replace(/&/g, '&amp;')).join(data);
        }
    } finally {
        box.remove();
    }

    const img = new Image();
    img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg);
    try { await img.decode(); } catch (e) { throw new Error('the page could not be drawn as a picture'); }
    const out = document.createElement('canvas');
    out.width = w; out.height = h;
    out.getContext('2d').drawImage(img, 0, 0, w, h);
    return out;
}
