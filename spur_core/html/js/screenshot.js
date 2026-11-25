import { NuiRouter } from './router.js';
import { nuiCallback } from './utils.js';
import { pagePicture } from './page-picture.js';

// ========================================
// SCREENSHOTS — the game's picture, read once, when asked (client/screenshot.lua)
// ========================================
//
// whip's own screenshots, in place of screenshot-basic: that one's page drew the whole game picture into a texture
// every frame whether or not anybody wanted a shot, and halved the frame rate on GTA V Enhanced (Josh, 31 Oct). This
// draws nothing until asked, reads what it was asked for, and lets everything go again: between shots it costs nothing.
//
// The game's picture, without whip's interface (the page sits over it, not in it), unless the shot says `ui`: then
// js/page-picture.js draws this page over it as it looks at that moment (not other resources' pages). Two ways into
// the game's picture, whichever this game has (js/caps.js gameView):
//   CfxGameViewRenderer   FiveM's own game view on new builds: it draws the game into a canvas; its placeholder is
//                         solid blue, so a shot waits until that is gone
//   the game-view texture the older builds' way (screenshot-basic's; GTA V Enhanced's Chrome 103): a WebGL texture
//                         given three wrap modes in a row is bound to the game's picture, drawn through a quad flipped
//                         the right way up. Drawn a frame at a time until the game's picture is in it: the first draws
//                         come out black (Josh, 3 Nov: Player Manager pictures black under the HUD on Enhanced)
// RedM (spur_core, 24 Nov 2026): RedM's pages get no game picture either way (CEF 144 has CfxGameViewRenderer, but it
// and the texture both stayed blue for 240 frames), so on RedM a shot ends "the game view never showed the game". The
// MCP server (dev/mcp/spur_mcp.mjs) reads the game window from Windows instead.
// Either way a frame is looked at in five places before it is taken: still the placeholder's blue, or black all over,
// is not the game yet. Neither gone in BIND_FRAMES: no picture, and why. A BURST takes black (it is there to watch a
// fade): only the blue is waited out, and on the texture way black too for its first BURST_BLACK_FRAMES (the texture
// filling), so a burst's first frame is the first after the bind.
//
// `frames` (2 to 24) and `every` (ms, 33 or more): a BURST, frames read one after another into one picture, a grid
// left to right then down, each with its number and when it was read. For what a still cannot show: a camera move,
// a fade, an animation. 640 wide a frame unless asked; no `ui` in a burst (drawing the page takes longer than a frame).
//
// Message `screenshot` { id, format: 'jpg'|'png'|'webp', quality 0-1, width, height, ui, frames, every,
// upload: { url, field } }: the picture at that size (the screen's by default), as a data URL, or posted to
// upload.url as a file in a form (a helper on this PC) and that answer's text. Answered by the NUI callback
// `screenshotTaken` { id, ok, data | why }. One shot at a time; the next waits its turn.

const TYPES = { jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', webp: 'image/webp' };
const BIND_FRAMES = 30;      // the most frames a new game view gets to show the game instead of its blue
const BURST_BLACK_FRAMES = 6;   // a burst on the texture way: black this many frames in is taken as the screen's
const BURST_MAX = 24;
const BURST_WIDTH = 640;

const frame = () => new Promise((r) => requestAnimationFrame(r));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function sizeOf(d) {
    const sw = Math.max(1, Math.round(window.innerWidth * (window.devicePixelRatio || 1)));
    const sh = Math.max(1, Math.round(window.innerHeight * (window.devicePixelRatio || 1)));
    let w = Math.round(Number(d.width) || 0), h = Math.round(Number(d.height) || 0);
    if (w > 0 && h <= 0) h = Math.round(w * sh / sw);
    if (h > 0 && w <= 0) w = Math.round(h * sw / sh);
    if (w <= 0 || h <= 0) { w = sw; h = sh; }
    return { w: Math.min(w, 7680), h: Math.min(h, 4320) };
}

// Where a frame is looked at: the middle and four points around it, as fractions of the width and height.
const SPOTS = [[0.5, 0.5], [0.25, 0.25], [0.75, 0.25], [0.25, 0.75], [0.75, 0.75]];

/** What a frame shows, from its colours at SPOTS (r, g, b, a in a row): 'blue' (the placeholder), 'black' (nothing yet,
 *  or a screen faded out) or 'game'. */
function seen(px) {
    let blue = true, black = true;
    for (let i = 0; i < px.length; i += 4) {
        const r = px[i], g = px[i + 1], b = px[i + 2];
        if (!(r < 8 && g < 8 && b > 247)) blue = false;
        if (!(r < 2 && g < 2 && b < 2)) black = false;
    }
    return blue ? 'blue' : (black ? 'black' : 'game');
}

/** Why a view showed no game in BIND_FRAMES, from what it showed last. */
function noGame(last) {
    return new Error(last === 'blue' ? 'the game view never showed the game'
        : 'the game\'s picture stayed black: the screen is faded out, or this game hands the page no picture');
}

function letGo(canvas) {
    try {
        const gl = canvas.getContext('webgl2') || canvas.getContext('webgl');
        const lose = gl && gl.getExtension('WEBGL_lose_context');
        if (lose) lose.loseContext();
    } catch (e) { /* no context to let go */ }
}

/** New builds: FiveM's game view. Its WebGL2 context is made here first, keeping its drawing buffer (the renderer is
 *  handed the same one by getContext), so a copy holds the frame whenever it is taken. Answers { grab, close }:
 *  grab(ctx, x, y) copies the frame showing now. `blackOk` (a burst): a black frame is taken too. */
async function openGameView(w, h, blackOk) {
    const gl = document.createElement('canvas');
    gl.width = w; gl.height = h;
    gl.getContext('webgl2', { preserveDrawingBuffer: true, antialias: false, depth: false, alpha: false });
    const probe = document.createElement('canvas');
    probe.width = SPOTS.length; probe.height = 1;
    const pctx = probe.getContext('2d', { willReadFrequently: true });
    let renderer = null;
    const close = () => {
        if (renderer) { try { renderer.destroy(); } catch (e) { /* gone */ } renderer = null; }
        letGo(gl);
    };
    try {
        renderer = new window.CfxGameViewRenderer(gl);
        renderer.resize(w, h);
        let last = 'blue';
        for (let i = 0; i < BIND_FRAMES; i++) {
            await frame();
            SPOTS.forEach(([fx, fy], s) => pctx.drawImage(gl, Math.floor(w * fx), Math.floor(h * fy), 1, 1, s, 0, 1, 1));
            last = seen(pctx.getImageData(0, 0, SPOTS.length, 1).data);
            const shows = last === 'game' || (blackOk && last === 'black');
            if (shows && i >= 1) return { grab: (ctx, x, y) => ctx.drawImage(gl, x, y, w, h), close };
        }
        throw noGame(last);
    } catch (e) {
        close();
        throw e;
    }
}

/** Older builds: the game-view texture (three wrap modes in a row bind it), drawn flipped into a framebuffer and read
 *  back bottom-up, which puts it the right way up (as screenshot-basic does). Answers { grab, close }.
 *  Drawn once a frame until the game's picture is in it, as screenshot-basic and ScreenCapture do (they draw every
 *  frame): one draw read straight away came out black. Its placeholder is blue, as the game view's: still blue = the
 *  texture never bound. `blackOk` (a burst): black is taken once BURST_BLACK_FRAMES have gone by. */
async function openTexture(w, h, blackOk) {
    const c = document.createElement('canvas');
    c.width = w; c.height = h;
    const gl = c.getContext('webgl', { preserveDrawingBuffer: true, antialias: false, depth: false, alpha: false });
    if (!gl) throw new Error('no WebGL');
    const tex = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array([0, 0, 255, 255]));
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.MIRRORED_REPEAT);
    gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);

    const sh = (type, src) => {
        const s = gl.createShader(type);
        gl.shaderSource(s, src);
        gl.compileShader(s);
        return s;
    };
    const prog = gl.createProgram();
    gl.attachShader(prog, sh(gl.VERTEX_SHADER,
        'attribute vec2 p; varying vec2 uv; void main() { uv = vec2((p.x + 1.0) * 0.5, 1.0 - (p.y + 1.0) * 0.5); gl_Position = vec4(p, 0.0, 1.0); }'));
    gl.attachShader(prog, sh(gl.FRAGMENT_SHADER,
        'precision mediump float; varying vec2 uv; uniform sampler2D t; void main() { gl_FragColor = vec4(texture2D(t, uv).rgb, 1.0); }'));
    gl.linkProgram(prog);
    gl.useProgram(prog);
    const buf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
    const at = gl.getAttribLocation(prog, 'p');
    gl.enableVertexAttribArray(at);
    gl.vertexAttribPointer(at, 2, gl.FLOAT, false, 0, 0);
    gl.uniform1i(gl.getUniformLocation(prog, 't'), 0);
    gl.viewport(0, 0, w, h);

    // Drawn a frame at a time until the game's picture is in it.
    const spot = new Uint8Array(4), spots = new Uint8Array(SPOTS.length * 4);
    let last = 'blue', bound = false;
    for (let i = 0; i < BIND_FRAMES && !bound; i++) {
        await frame();
        gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
        SPOTS.forEach(([fx, fy], s) => {
            gl.readPixels(Math.floor(w * fx), Math.floor(h * fy), 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, spot);
            spots.set(spot, s * 4);
        });
        last = seen(spots);
        bound = i >= 2 && (last === 'game' || (blackOk && last === 'black' && i >= BURST_BLACK_FRAMES));
    }
    if (!bound) { letGo(c); throw noGame(last); }
    const px = new Uint8Array(w * h * 4);
    const img = new ImageData(new Uint8ClampedArray(px.buffer), w, h);
    const tmp = document.createElement('canvas');
    tmp.width = w; tmp.height = h;
    const tctx = tmp.getContext('2d');
    return {
        grab: (ctx, x, y) => {
            gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
            gl.readPixels(0, 0, w, h, gl.RGBA, gl.UNSIGNED_BYTE, px);
            tctx.putImageData(img, 0, 0);
            ctx.drawImage(tmp, x, y);
        },
        close: () => letGo(c),
    };
}

const openGame = (w, h, blackOk) => (typeof window.CfxGameViewRenderer === 'function'
    ? openGameView(w, h, blackOk) : openTexture(w, h, blackOk));

/** One frame of the game, as a canvas w x h. */
async function still(w, h) {
    const game = await openGame(w, h);
    try {
        const out = document.createElement('canvas');
        out.width = w; out.height = h;
        game.grab(out.getContext('2d'), 0, 0);
        return out;
    } finally {
        game.close();
    }
}

/** `count` frames `every` ms apart, in one picture: a grid, each frame marked with its number and when it was read. */
async function burst(w, h, count, every) {
    const cols = Math.ceil(Math.sqrt(count));
    const rows = Math.ceil(count / cols);
    const sheet = document.createElement('canvas');
    sheet.width = cols * w; sheet.height = rows * h;
    const ctx = sheet.getContext('2d');
    ctx.fillStyle = '#000';
    ctx.fillRect(0, 0, sheet.width, sheet.height);
    const game = await openGame(w, h, true);
    try {
        const t0 = performance.now();
        for (let i = 0; i < count; i++) {
            if (i > 0) {
                const due = t0 + i * every;
                if (due > performance.now()) await sleep(due - performance.now());
                await frame();
            }
            const x = (i % cols) * w, y = Math.floor(i / cols) * h;
            const at = Math.round(performance.now() - t0);
            game.grab(ctx, x, y);
            const label = `#${i + 1}  +${at} ms`;
            ctx.font = `bold ${Math.max(12, Math.round(h / 18))}px sans-serif`;
            const pad = 6, tw = ctx.measureText(label).width;
            ctx.fillStyle = 'rgba(0,0,0,0.65)';
            ctx.fillRect(x, y, tw + pad * 2, Math.round(h / 18) + pad * 2);
            ctx.fillStyle = '#fff';
            ctx.textBaseline = 'top';
            ctx.fillText(label, x + pad, y + pad);
        }
    } finally {
        game.close();
    }
    return sheet;
}

function blobOf(dataUrl) {
    const [head, body] = dataUrl.split(',');
    const type = head.split(':')[1].split(';')[0];
    const bin = atob(body);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return new Blob([bytes], { type });
}

async function take(d) {
    const fmt = String(d.format || 'jpg').toLowerCase();
    const type = TYPES[fmt] || TYPES.jpg;
    const q = Math.max(0.1, Math.min(1, Number(d.quality) || 0.92));
    const count = Math.min(BURST_MAX, Math.round(Number(d.frames) || 1));
    let canvas;
    if (count >= 2) {
        const { w, h } = sizeOf(d.width || d.height ? d : { width: BURST_WIDTH });
        canvas = await burst(w, h, count, Math.max(33, Number(d.every) || 100));
    } else {
        const { w, h } = sizeOf(d);
        canvas = await still(w, h);
        if (d.ui) canvas = await pagePicture(canvas, w, h, { type });
    }
    const data = canvas.toDataURL(type, q);
    const up = d.upload;
    if (up && typeof up.url === 'string' && up.url !== '') {
        const form = new FormData();
        form.append(String(up.field || 'file'), blobOf(data), 'screenshot.' + (fmt === 'jpeg' ? 'jpg' : fmt));
        // A helper that takes the connection and never answers must not hold every later shot up: given up on in time
        const stop = new AbortController();
        const timer = setTimeout(() => stop.abort(), UPLOAD_MS);
        try {
            const res = await fetch(up.url, { method: 'POST', mode: 'cors', body: form, signal: stop.signal });
            return await res.text();
        } catch (e) {
            throw new Error(stop.signal.aborted ? 'the upload got no answer in time' : String(e && e.message || e));
        } finally {
            clearTimeout(timer);
        }
    }
    return data;
}

const UPLOAD_MS = 10000;

// One shot at a time. One Lua has given up on (screenshotCancel, its wait over) while it was still queued is skipped,
// and one still queued past its own wait is too: nobody would read it.
let queue = Promise.resolve();
const cancelled = new Set();

NuiRouter.register('screenshotCancel', (d) => { if (d && d.id != null) cancelled.add(d.id); });

NuiRouter.register('screenshot', (d) => {
    const id = d && d.id;
    const until = Date.now() + (Number(d && d.waitMs) || 15000);
    queue = queue.then(() => {
        if (cancelled.has(id) || Date.now() > until) { cancelled.delete(id); return null; }
        return take(d || {})
            .then((data) => nuiCallback('screenshotTaken', { id, ok: true, data }))
            .catch((e) => nuiCallback('screenshotTaken', { id, ok: false, why: String(e && e.message || e) }));
    }).finally(() => cancelled.delete(id));
});
