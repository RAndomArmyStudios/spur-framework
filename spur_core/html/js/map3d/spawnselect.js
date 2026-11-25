// whip's spawn picker: what follows choosing a character. The character screen's camera pans up, and the 3D map comes
// down over the picture with it: a tall soft gradient from the game to the map, its edge locked to the world as if it
// hung above the shot. The map's own camera carries the look up on: looking straight down, the map slides down the
// screen in step with the game's pan while any of the game shows, then tilts up onto the place picked by default (where
// they last were), easing to a stop from the pan's speed. On the left, the list: their last
// place, the properties they own or hold a key to, the server's spawn points, each an icon and a name. The map flies to
// each, a beacon of light standing on it. Picking one clears the list away and starts the game's load behind the map, which
// waits straight over the spot. The game holds its arrival scene on its first frame and sends that camera; the map
// lands exactly on it, so the map and the game are the same picture, still, for a moment (the buildings seem to swap
// from the map's to the game's); then the scene plays and the map fades out following its camera.
//
//   import { SpawnSelect } from './map3d/spawnselect.js';
//   const ss = new SpawnSelect(document.getElementById('spawnsel'), { map, nui: (name, data) => ... });
//   ss.open(d); ss.ready(d); ss.started(d); ss.cam(d); ss.closing(d); ss.abort();   // the game's messages
//   ss.key(e); ss.nav('up' | 'down' | 'select' | 'back'); ss.padHints();   // input, through the page's key scope
//
// THE CONTRACT (game -> page: the methods above; page -> game: opts.nui(name, data))
//   open    { spawns: [{ id, kind: 'last' | 'property' | 'preset', label, x, y, z, heading }], defaultId,
//             pan: { ms, fromPitch, toPitch, fov, ease: 'inQuad' } }, in the frame the game's pan starts:
//             pitch(t) = fromPitch + (toPitch - fromPitch) * ease(t / ms), fov fixed (vertical degrees). The map's edge
//             is a fixed elevation in that camera's world, so it comes down exactly as fast as the camera pans up.
//   choose  -> 'spawnsel:choose' { id }. No way back after it.
//   back    -> 'spawnsel:back' {} (Escape, pad B; before choose only). The game answers closing.
//   closing { pan } in the frame the game pans back down: the open pan played backwards,
//             pitch(t) = fromPitch + (toPitch - fromPitch) * ease(1 - t / ms). The map's edge rises with it.
//   (after choose the list goes; the map waits straight over the place; the game shows its own loading logo over it)
//   ready   { cam: { x, y, z, rotX, rotY, rotZ, fov } }: the arrival scene is started and held on its first frame, its
//             camera on screen behind the map. cam is that camera (GetFinalRenderedCamCoord / GetFinalRenderedCamRot(2)
//             / GetFinalRenderedCamFov): still and exact. The map moves from the wait onto it in zoomMs, lands exactly on
//             it, then
//   go      -> 'spawnsel:go' {}: the map is exactly on cam and still (nothing more is drawn until started). The game
//             holds both still for a moment, then releases the scene and, in that frame, sends
//   started { cam }: the scene is playing. The map fades out at once (fadeMs), following the game's camera.
//   cam     { x, y, z, rotX, rotY, rotZ, fov } every game frame after started: the same reading. The scene's camera
//             moves: this is the live target, carried on from its last two readings to the moment drawn.
//   done    -> 'spawnsel:done' {}: the map is off the page again (the page's other maps can have it back).
//   abort   {}: the load failed. The picker fades out at once, then done.
//
// Drawing is on demand: no frames while nothing moves (the list sitting still, the wait over the spot).

// the list's icons (24 box, drawn in currentColor)
const svg = (d) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${d}</svg>`;
const ICON = {
    last: svg('<path d="M3.6 12a8.4 8.4 0 1 0 2.5-6"/><path d="M3.4 4.4v4.2h4.2"/><path d="M12 7.6V12l3 2"/>'),
    home: svg('<path d="M3.8 10.6 12 4l8.2 6.6"/><path d="M6 9.2v10.3h12V9.2"/><path d="M10 19.5v-5h4v5"/>'),
    place: svg('<path d="M6.2 21V4"/><path d="M6.2 4.6h11.3l-2.3 4.1 2.3 4.1H6.2"/>'),
};

const ease = {
    linear: (t) => t,
    inQuad: (t) => t * t,
    outCubic: (t) => 1 - (1 - t) ** 3,
    inOutCubic: (t) => (t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2),
    inOutSine: (t) => -(Math.cos(Math.PI * t) - 1) / 2,
};
const clamp01 = (t) => Math.max(0, Math.min(1, t));
const rad = (d) => d * Math.PI / 180;
const wrap180 = (d) => ((d % 360) + 540) % 360 - 180;
const easeOf = (name, fallback) => ease[name] || fallback;

// ---- tuning ----
export const SPAWNSEL_TUNING = {
    fade: 0.42,          // the map's edge: a gradient from the game to the map this tall, as a share of the screen's height
    coverAt: 0.9,        // the map covers the whole screen this far through the pan's angle (the rest is behind it)
    msgLag: 16,          // ms a game message takes to reach the page: the map's edge and the live camera run this far ahead
    settleMs: 1600,      // after the pan: the map's camera tilting up onto the place, easing out from the pan's speed
    settleMaxMs: 3200,   // ... the longest, for a pan too slow to carry the tilt in settleMs
    listAfter: 300,      // ms after the map covers the screen, the list comes in
    dist: 950, pitch: -90, heading: 0, fov: 50,   // looking at a place in the list (RedM (spur_core, 25 Nov 2026): straight down,
                                                  // the map is kept flat; whip's -50 tilted onto the place)
    shift: 0.14,         // ... the picture's centre moved right by this share of the width (the list is on the left)
    waitDist: 700, arriveMs: 1500,                // picked: straight over it, this high
    zoomMs: 1000,        // ready: from the wait onto the game's held first frame ("a second at most")
    fadeMs: 600,         // started: the fade to the game as its scene begins to play, following its camera
    abortMs: 400,
    pinDropMs: 620, pinOutMs: 170,
    strikeMs: 170,       // the beacon's column coming down from the sky (then its flash at the foot, the ring, the specks)
    pinIdleMs: 33,       // the standing beacon's light moves on at most this often (a copy of the map + the beacon: ~30 fps)
};

const KIND = {
    last: { order: 0, icon: 'last' },
    property: { order: 1, icon: 'home' },
    preset: { order: 2, icon: 'place' },
};

/** a GTA camera pose from an orbit rig: a target, the distance to it, pitch (degrees, -90 down) and heading */
function rigPose(r, W) {
    const p = rad(r.pitch), h = rad(r.heading);
    const fx = -Math.sin(h) * Math.cos(p), fy = Math.cos(h) * Math.cos(p), fz = Math.sin(p);
    return { x: r.tx - fx * r.d, y: r.ty - fy * r.d, z: r.tz - fz * r.d, rotX: r.pitch, rotY: 0, rotZ: r.heading, fov: r.fov,
        shiftX: (r.shift || 0) * W, shiftY: 0 };
}

/** the rig that gives a pose, its target on the level tz */
function poseRig(c, tz) {
    const p = rad(c.rotX), h = rad(c.rotZ);
    const fx = -Math.sin(h) * Math.cos(p), fy = Math.cos(h) * Math.cos(p), fz = Math.sin(p);
    const d = fz < -0.05 ? (c.z - tz) / -fz : 100;
    return { tx: c.x + fx * d, ty: c.y + fy * d, tz: c.z + fz * d, d: Math.max(1, d), pitch: c.rotX, heading: c.rotZ, fov: c.fov, shift: 0 };
}

/** a GTA camera pose's look direction */
function fwdOf(c) {
    const p = rad(c.rotX), h = rad(c.rotZ);
    return [-Math.sin(h) * Math.cos(p), Math.cos(h) * Math.cos(p), Math.sin(p)];
}

/** Between two camera poses at e (eased), the character (focus) kept in the middle the whole way. Across in plan;
 *  the height on a log scale over a floor under both, so a dive from high up spends its time like a zoom instead of
 *  rushing the last metres; heading the short way; roll and fov lerp; the pitch looks at a point sliding from what a
 *  looks at to what b looks at, each as far out as the focus (so it is exactly a's pitch at 0 and b's at 1). */
export function zoomPose(a, b, focus, e) {
    if (e >= 1) return { ...b, shiftX: 0, shiftY: 0 };
    const l = (k) => (a[k] ?? 0) + ((b[k] ?? 0) - (a[k] ?? 0)) * e;
    const out = (c) => {
        const f = fwdOf(c), d = Math.hypot(focus.x - c.x, focus.y - c.y, focus.z - c.z);
        return [c.x + f[0] * d, c.y + f[1] * d, c.z + f[2] * d];
    };
    const ta = out(a), tb = out(b), T = ta.map((v, i) => v + (tb[i] - v) * e);
    const base = Math.min(a.z, b.z, focus.z) - 2;
    const z = base + Math.exp(Math.log(a.z - base) + (Math.log(b.z - base) - Math.log(a.z - base)) * e);
    const p = { x: l('x'), y: l('y'), z, rotY: l('rotY'), rotZ: a.rotZ + wrap180(b.rotZ - a.rotZ) * e, fov: l('fov'),
        shiftX: (a.shiftX || 0) * (1 - e), shiftY: 0 };
    const h = rad(p.rotZ), along = (T[0] - p.x) * -Math.sin(h) + (T[1] - p.y) * Math.cos(h);
    p.rotX = Math.max(-90, Math.min(89, Math.atan2(T[2] - p.z, along) * 180 / Math.PI));
    return p;
}

const num = (v, d) => (Number.isFinite(+v) ? +v : d);

export class SpawnSelect {
    /** @param root an empty element (the picker's own layer); opts.map the page's WhipMap3D (built), or setMap later;
     *  opts.nui(name, data) the page's callback to the game; opts.tuning overrides SPAWNSEL_TUNING; opts.now a clock in
     *  ms (performance.now by default); opts.raf a frame scheduler (requestAnimationFrame by default) */
    constructor(root, opts = {}) {
        this.root = root;
        this.map = opts.map || null;
        this.nui = opts.nui || (() => {});
        this.o = Object.assign({}, SPAWNSEL_TUNING, opts.tuning);
        this.state = 'idle';
        this.spawns = []; this.sel = 0;
        this.raf = 0; this.tw = null; this.pinA = null; this.rig = null; this.pose = null;
        this.frames = 0;                 // whole map frames drawn (tests: none while still)
        this.pinFrames = 0;              // beacon-only frames (the map copied, the light drawn over it)
        this.pinIdle = false; this.pinT = -Infinity;
        this.now = opts.now || (() => performance.now());   // the clock (tests: a virtual one)
        // the frame scheduler (tests: none, and _frame stepped by hand)
        this.rafFn = opts.raf || ((fn) => requestAnimationFrame(fn));
        this.cafFn = opts.raf ? () => {} : (id) => cancelAnimationFrame(id);
        this.W = 1; this.H = 1;
        this._dom();
        window.addEventListener('resize', () => { if (this.state !== 'idle') this._resize(); });
    }

    setMap(map) { this.map = map; }
    isOpen() { return this.state !== 'idle'; }

    // ---- the layer ----

    _dom() {
        const r = this.root;
        r.classList.add('ss');
        r.hidden = true;
        r.innerHTML = `
            <div class="ss-mapclip"><div class="ss-mapin"></div></div>
            <div class="ss-scrim"></div>
            <div class="ss-panel"><div class="ss-scale">
                <div class="ss-list" role="listbox" aria-label="Where to arrive"></div>
                <div class="ss-foot"><button class="ss-go" type="button"><span class="ss-go-txt">Spawn here</span></button></div>
            </div></div>`;
        const q = (c) => r.querySelector(c);
        this.el = { clip: q('.ss-mapclip'), mapIn: q('.ss-mapin'), panel: q('.ss-panel'), list: q('.ss-list'), go: q('.ss-go'),
            goTxt: q('.ss-go-txt') };
        this.el.go.addEventListener('click', () => this._choose());
        this.el.list.addEventListener('click', (e) => {
            const row = e.target.closest('.ss-row');
            if (!row) return;
            const i = +row.dataset.i;
            if (i === this.sel) this._choose(); else this._select(i);
        });
    }

    _resize() {
        this._size();
        if (this.map && this.attached) this.map.resize(this.W, this.H, window.devicePixelRatio || 1);
        if (this.pan) this._curtainSetup();
        this._edges(this.edgeY ?? -1);
        this._kick();
    }

    /** the screen's size, and the edge's gradient from it (CSS px, in --ss-fade for the stylesheet) */
    _size() {
        this.W = Math.max(1, window.innerWidth); this.H = Math.max(1, window.innerHeight);
        this.G = Math.round(this.o.fade * this.H);
        this.root.style.setProperty('--ss-fade', this.G + 'px');
    }

    _attach() {
        const c = this.map.canvas;
        if (c.parentNode === this.el.mapIn) return;
        this.savedCss = c.style.cssText;
        c.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;display:block';
        this.el.mapIn.appendChild(c);
        this.attached = true;
        this.map.resize(this.W, this.H, window.devicePixelRatio || 1);
    }

    _detach() {
        if (!this.attached) return;
        const c = this.map.canvas;
        if (c.parentNode === this.el.mapIn) c.remove();
        c.style.cssText = this.savedCss || '';
        this.attached = false;
    }

    /** the map's edge at edgeY (CSS px from the top): the map shows above it, through a gradient G tall that ends
     *  there (the stylesheet's mask on the map's box), and the game below. Transforms only. */
    _edges(edgeY) {
        this.edgeY = edgeY;
        const H = this.H, G = this.G;
        // the map's box ends at edgeY; the map inside stays put. Whole pixels, so the two opposite moves cancel exactly
        const y = Math.round(Math.min(H + G, edgeY));
        this.el.clip.style.transform = `translate3d(0, ${y - H - G}px, 0)`;
        this.el.mapIn.style.transform = `translate3d(0, ${H + G - y}px, 0)`;
    }

    // ---- the game's messages ----

    open(d) {
        if (!this.map || this.map.failed || !this.map.ground) { this.nui('spawnsel:done', { failed: true }); return false; }
        const list = (d && Array.isArray(d.spawns) ? d.spawns : []).filter((s) => s && s.id != null && Number.isFinite(+s.x) && Number.isFinite(+s.y));
        if (!list.length) { this.nui('spawnsel:done', { failed: true }); return false; }
        this._stop();
        const opt = (v) => (v != null && v !== '' && Number.isFinite(+v) ? +v : null);       // (+null is 0: not a height)
        this.spawns = list.map((s, i) => ({ ...s, x: +s.x, y: +s.y, z: opt(s.z), heading: opt(s.heading),
            kind: KIND[s.kind] ? s.kind : 'preset', n: i }))
            .sort((a, b) => KIND[a.kind].order - KIND[b.kind].order || a.n - b.n);
        this.sel = Math.max(0, this.spawns.findIndex((s) => String(s.id) === String(d.defaultId)));
        this.pan = this._pan(d.pan);
        this.chosen = null; this.zoom = null; this.live = null;
        this._list();
        this.root.hidden = false;
        this.root.style.opacity = '';
        this.root.className = 'ss ss-on';
        this._size();
        this._attach();
        this._curtainSetup();
        this._edges(-1);
        this.map.setPin(null);
        this.state = 'opening';
        this.t0 = this.now() - this.o.msgLag;   // (the game started its pan as it sent this)
        this.listShown = false;
        // the map's camera: the slide and settle onto the place, on the pan's clock (_arrival)
        this.rig = this._selRig(this.spawns[this.sel]);
        this._arrival();
        this._kick();
        return true;
    }

    closing(d) {
        if (this.state === 'idle') return;
        this._stop();
        if (d && d.pan) this.pan = this._pan(d.pan);
        this._curtainSetup();
        this.root.classList.add('ss-leaving');
        this.state = 'closing';
        this.t0 = this.now() - this.o.msgLag;
        this._kick();
    }

    /** the arrival scene is held on its first frame: move from wherever the map is (the wait, or still on its way there)
     *  onto that camera, land exactly on it, hold still and send go. No camera: just fade out. */
    ready(d) {
        if (this.state !== 'arriving' && this.state !== 'waiting') return;
        const c = this._camOf(d && d.cam);
        if (!c) { this.abort(); return; }
        this.tw = null;
        this._endArr();
        const s = this.chosen || this.spawns[this.sel];
        this.zoom = { from: { ...(this.pose || rigPose(this.rig, this.W)) }, to: c, t0: this.now(), focus: { x: s.x, y: s.y, z: this._spotZ(s) + 1 } };
        this.state = 'zooming';
        this.root.classList.add('ss-going');
        this._kick();
    }

    /** the scene is playing (released in this frame): fade out at once, following its camera */
    started(d) {
        if (this.state !== 'holding' && this.state !== 'zooming') return;
        const c = this._camOf(d && d.cam) || (this.zoom && this.zoom.to);
        if (!c) { this.abort(); return; }
        this.live = [{ c, t: this.now() }];
        this.tf = this.now() - this.o.msgLag;        // (released as the message was sent)
        this.state = 'fading';
        this._kick();
    }

    /** the game's camera this frame, after started (the live target) */
    cam(d) {
        if (this.state !== 'fading') return;
        const c = this._camOf(d);
        if (!c) return;
        this.live.push({ c, t: this.now() });
        if (this.live.length > 2) this.live.shift();
    }

    _camOf(c) {
        if (!c || !Number.isFinite(+c.x) || !Number.isFinite(+c.y) || !Number.isFinite(+c.z)) return null;
        return { x: +c.x, y: +c.y, z: +c.z, rotX: num(c.rotX, 0), rotY: num(c.rotY, 0), rotZ: num(c.rotZ, 0), fov: num(c.fov, 50) };
    }

    /** the live camera at now: its last reading, carried on along the last two (a reading is about a message late when
     *  it lands, and older still by the time it is drawn), at most 66 ms ahead */
    _livePose(now) {
        const L = this.live, b = L[L.length - 1];
        if (L.length < 2) return b.c;
        const a = L[0], dt = b.t - a.t;
        if (dt < 4) return b.c;
        const k = Math.min(66, now - b.t + this.o.msgLag) / dt, p = a.c, q = b.c;
        const x = (key) => q[key] + (q[key] - p[key]) * k;
        return { x: x('x'), y: x('y'), z: x('z'), rotX: x('rotX'), rotY: x('rotY'), rotZ: q.rotZ + wrap180(q.rotZ - p.rotZ) * k, fov: x('fov') };
    }

    abort() {
        if (this.state === 'idle' || this.state === 'aborting') return;
        this.tw = null;
        this.state = 'aborting';
        this.ta = this.now();
        this._kick();
    }

    // ---- input ----

    key(e) {
        const k = e.key;
        if (k === 'ArrowUp' || k === 'ArrowDown') { e.preventDefault(); this._step(k === 'ArrowDown' ? 1 : -1); }
        else if (k === 'Enter') { e.preventDefault(); this._choose(); }
        else if (k === 'Escape' || k === 'Backspace') { e.preventDefault(); this._back(); }
    }

    nav(nav) {
        if (nav === 'up' || nav === 'left') this._step(-1);
        else if (nav === 'down' || nav === 'right') this._step(1);
        else if (nav === 'select') this._choose();
        else if (nav === 'back') this._back();
    }

    padHints() {
        return this.state === 'choosing' ? [['dpad', 'Choose'], ['a', 'Spawn'], ['b', 'Back']] : [];
    }

    _step(delta) {
        if (this.state !== 'choosing') return;
        this._select((this.sel + delta + this.spawns.length) % this.spawns.length);
    }

    _back() {
        if (this.state !== 'choosing') return;
        this.state = 'leaving';
        this.root.classList.add('ss-leaving');
        this.nui('spawnsel:back', {});
    }

    _choose() {
        if (this.state !== 'choosing') return;
        this._endArr();
        const s = this.spawns[this.sel];
        this.chosen = s;
        this.state = 'arriving';
        this.root.classList.add('ss-chosen', 'ss-going');           // the list and its dark go: the full map

        this.nui('spawnsel:choose', { id: s.id });
        if (!this.pinA || this.pinA.s !== s) this._pinDrop(s);
        const r = this.rig, o = this.o;
        this._tween({ ...this._selRig(s), d: o.waitDist, pitch: -90, heading: r.heading, shift: 0 }, o.arriveMs, {
            win: { angle: [0, 0.8] },
            done: () => { this.state = 'waiting'; },
        });
    }

    // ---- the list ----

    _list() {
        // each place: its kind's icon and its name, nothing else
        const L = this.el.list;
        L.textContent = '';
        this.spawns.forEach((s, i) => {
            const b = document.createElement('button');
            b.type = 'button';
            b.className = 'ss-row';
            b.dataset.i = i;
            b.setAttribute('role', 'option');
            b.innerHTML = `<span class="ss-ico">${ICON[KIND[s.kind].icon]}</span><span class="ss-label"></span>`;
            b.querySelector('.ss-label').textContent = s.label || 'Somewhere';
            L.appendChild(b);
        });
        this._mark();
    }

    _mark() {
        const L = this.el.list, rows = L.querySelectorAll('.ss-row');
        if (this.listShown) L.classList.toggle('ss-scroll', L.scrollHeight > L.clientHeight + 1);
        rows.forEach((b) => {
            const on = +b.dataset.i === this.sel;
            b.classList.toggle('selected', on);
            b.setAttribute('aria-selected', on ? 'true' : 'false');
            // kept in view (clear of the faded ends) by scrolling the list itself: scrollIntoView could move the page's
            // other boxes too
            if (on && this.listShown) {
                const top = b.offsetTop, bottom = top + b.offsetHeight, pad = 56;
                if (top - pad < L.scrollTop) L.scrollTop = Math.max(0, top - pad);
                else if (bottom + pad > L.scrollTop + L.clientHeight) L.scrollTop = bottom + pad - L.clientHeight;
            }
        });
    }

    _select(i) {
        if (i === this.sel) return;
        this._endArr();
        this.sel = i;
        this._mark();
        const s = this.spawns[i], r = this.rig, to = this._selRig(s);
        const dist = Math.hypot(to.tx - r.tx, to.ty - r.ty), far = Math.max(r.d, to.d);
        const hop = Math.max(0, Math.min(6, (dist * 0.9) / far - 1));
        const ms = Math.min(2400, 900 + 380 * Math.log2(1 + dist / 700));
        if (this.pinA && this.pinA.mode !== 'out') this.pinA = { ...this.pinA, mode: 'out', t0: this.now() };
        this._tween(to, ms, { hop, done: () => this._pinDrop(s) });
    }

    _selRig(s) {
        const o = this.o, z = this._spotZ(s);
        return { tx: s.x, ty: s.y, tz: z, d: o.dist, pitch: o.pitch, heading: o.heading, fov: o.fov, shift: o.shift };
    }

    /** where a spawn's feet are: its z is a standing ped's (about 1 m over the floor) */
    _spotZ(s) {
        // last and preset: a standing ped's position (about 1 m over the floor); property: its inside visit point, about
        // the floor (maybe up a tower: never snapped to the map's ground); none: the map's ground
        if (s.z == null) return this.map.heightAt(s.x, s.y);
        return s.kind === 'property' ? s.z : s.z - 1;
    }

    // ---- the map's edge, locked to the game's pan ----

    _pan(p) {
        p = p || {};
        const from = num(p.fromPitch, 0), to = num(p.toPitch, from + 70);
        return { ms: Math.max(1, num(p.ms, 1500)), from, to: to > from + 1 ? to : from + 70, fov: Math.min(120, Math.max(5, num(p.fov, 40))),
            ease: easeOf(p.ease, ease.inQuad) };
    }

    /** The map's edge (where its gradient has faded to nothing) is a fixed elevation in the game camera's world, chosen
     *  so the whole gradient has passed the screen's bottom (the map covers it all) when the pan is coverAt through its
     *  angle. A pan too short for its field of view gets an edge faster than the world. */
    _curtainSetup() {
        const p = this.pan, span = p.to - p.from, dc = this.o.coverAt * span, f = (this.H / 2) / Math.tan(rad(p.fov / 2));
        // the angle under the screen's middle where the edge is when the gradient's top reaches the bottom
        const below = Math.atan((this.H / 2 + this.G) / f) * 180 / Math.PI, need = p.fov / 2 + below;
        const m = dc < need + 6 ? (need + 6) / Math.max(1, dc) : 1;
        this.cur = { span, m, ac: m * dc - below };
        // when the edge enters at the top and when the map covers the screen (the pan's ease need not be invertible)
        const at = (y) => { let a = 0, b = p.ms; for (let i = 0; i < 30; i++) { const t = (a + b) / 2; if (this._hemAt(t, false) < y) a = t; else b = t; } return b; };
        this.cur.enterT = at(0);
        this.cur.coverT = at(this.H + this.G);
    }

    /** the game pan's speed at pan time t, as the screen moves at its middle: px per ms */
    _panPxPerMs(t) {
        const p = this.pan, u = clamp01(t / p.ms), du = 1e-3;
        const dDelta = this.cur.span * (p.ease(Math.min(1, u + du)) - p.ease(Math.max(0, u - du))) / (Math.min(1, u + du) - Math.max(0, u - du));
        return (dDelta / p.ms) * (Math.PI / 180) * (this.H / 2) / Math.tan(rad(p.fov / 2));
    }

    /** the map's edge (CSS px) at pan time t: the camera pitches up under it (closing: back down) */
    _hemAt(t, closing) {
        const p = this.pan, c = this.cur, u = clamp01(t / p.ms);
        const delta = c.span * p.ease(closing ? 1 - u : u);
        const a = Math.max(-89, Math.min(89, c.ac - c.m * delta));
        const f = (this.H / 2) / Math.tan(rad(p.fov / 2));
        return this.H / 2 - f * Math.tan(rad(a));
    }

    // ---- the pin ----

    _pinDrop(s) {
        this.pinA = { s, mode: 'drop', t0: this.now() };
        this._kick();
    }

    /** the beacon for this frame; true while it is landing or leaving. Standing, pinIdle says only its light moves on */
    _pinFrame(now) {
        const a = this.pinA;
        this.pinIdle = false;
        if (!a) { this.map.setPin(null); return false; }
        const s = a.s, base = { x: s.x, y: s.y, z: this._spotZ(s), heading: s.heading, t: now };
        if (a.mode === 'drop') {
            // the column strikes down from the sky, flashes at its foot and settles; the ring fades in, the specks start
            const o = this.o, t = now - a.t0, k = o.strikeMs;
            this.map.setPin({ ...base, strike: clamp01(t / k) ** 2, flash: t < k ? 0 : Math.max(0, 1 - (t - k) / 430) ** 2 * 1.3,
                glow: t >= k * 0.88 ? 1 : 0, ring: clamp01((t - 200) / 300), motes: clamp01((t - 220) / 400) });
            if (t < o.pinDropMs) return true;
            a.mode = 'on';                 // landed: standing from this frame, its light moving on by itself
            this.pinIdle = true;
            return false;
        }
        if (a.mode === 'out') {
            const u = clamp01((now - a.t0) / this.o.pinOutMs);
            this.map.setPin({ ...base, alpha: 1 - u, scale: 1 - 0.35 * u, ring: 1 - u });
            if (u >= 1) { this.pinA = null; this.map.setPin(null); }
            return u < 1;
        }
        // standing; while the map zooms onto the game's camera it fades away (pinFade, set by the zoom)
        const k = this.zoom ? this.pinFade ?? 1 : 1;
        this.map.setPin(k > 0 ? { ...base, alpha: k, ring: k } : null);
        this.pinIdle = k > 0;
        return false;
    }

    // ---- the camera ----

    /** a flight from where the camera is to rig `to`: the target slides in plan, the distance changes on a log scale
     *  (rising in the middle by `hop` for a long trip, so both ends stay in sight), the angles turn the short way. Each
     *  channel (move, dist, angle, heading) can have its own window, as shares of ms. */
    _tween(to, ms, opts = {}) {
        this.tw = { a: { ...this.rig }, b: to, ms, t0: this.now(), ease: opts.ease || ease.inOutCubic, hop: opts.hop || 0,
            win: opts.win || {}, done: opts.done };
        this._kick();
    }

    _tweenFrame(now) {
        const w = this.tw, u = clamp01((now - w.t0) / w.ms), a = w.a, b = w.b;
        const ch = (k, dflt) => { const r = w.win[k] || w.win[dflt] || [0, 1]; return w.ease(clamp01((u - r[0]) / Math.max(1e-6, r[1] - r[0]))); };
        const em = ch('move'), ed = ch('dist', 'move'), ea = ch('angle'), eh = ch('heading', 'angle');
        const l = (k, e) => (a[k] ?? 0) + ((b[k] ?? 0) - (a[k] ?? 0)) * e;
        this.rig = {
            tx: l('tx', em), ty: l('ty', em), tz: l('tz', em),
            d: Math.exp(Math.log(a.d) + (Math.log(b.d) - Math.log(a.d)) * ed) * (1 + w.hop * Math.sin(Math.PI * em)),
            pitch: l('pitch', ea), heading: a.heading + wrap180(b.heading - a.heading) * eh, fov: l('fov', ea), shift: l('shift', ea),
        };
        if (u < 1) return true;
        this.tw = null;
        if (w.done) w.done();
        return !!this.tw;
    }

    // ---- frames ----

    _kick() { if (!this.raf && this.state !== 'idle') this.raf = this.rafFn(() => this._frame()); }

    _stop() {
        if (this.raf) this.cafFn(this.raf);
        this.raf = 0;
        this.tw = null;
    }

    // ---- the map's camera carrying the game's look up on ----

    /** The map's camera keeps pace with the game while any of the game is on screen, then settles onto the place.
     *  SLIDE (the edge entering -> the pan's end): looking straight down from the list view's height, it moves forward
     *  along its heading, so the ground slides down the screen exactly as fast as the game's pan moves the world (px at
     *  the middle), speeding up with it. A tilt has only 40 degrees of room; a slide has as much as the pan needs.
     *  SETTLE (then, settleMs): it tilts up onto the place (-90 -> the list's pitch) while the slide runs on into the list
     *  view's position, both easing out together (cubic) from the slide's last speed, so nothing jumps. */
    _arrival() {
        const o = this.o, p = this.pan, c = this.cur, to = this._selRig(this.spawns[this.sel]);
        const end = rigPose(to, this.W);                                   // the list's view: where it all ends
        const fMap = (this.H / 2) / Math.tan(rad(to.fov / 2)), fGame = (this.H / 2) / Math.tan(rad(p.fov / 2));
        const deg = (t) => c.span * p.ease(clamp01(t / p.ms));             // the game's pitch over where it started
        const dx = -Math.sin(rad(to.heading)), dy = Math.cos(rad(to.heading));
        // the slide: metres along the heading per degree of the game's pitch (its px at the middle = the map's), from the
        // camera's height over the ground it passes (the map's own ground along the way, not the place's level)
        const kOf = (h) => (Math.max(50, h) / fMap) * fGame * Math.PI / 180;
        let h = end.z - to.tz, k = kOf(h), slide = k * (deg(p.ms) - deg(c.enterT));
        let g = 0;
        for (let i = 0; i < 16; i++) { const b = slide * (i + 0.5) / 16; g += this.map.heightAt(end.x - dx * b, end.y - dy * b) / 16; }
        h = Math.max(50, end.z - g); k = kOf(h); slide = k * (deg(p.ms) - deg(c.enterT));
        // the settle: from the slide's last speed (px per ms at the middle) to nothing over T. The tilt gives fMap * room
        // px of it, the rest is more slide; a slow pan with too little speed for the tilt settles longer instead
        const u = this._panPxPerMs(p.ms - 1), room = rad(to.pitch + 90);
        let T = o.settleMs, more = h * (u * T / (3 * fMap) - room);
        if (more < 0) { more = 0; T = Math.min(o.settleMaxMs, 3 * fMap * room / Math.max(u, 1e-6)); }
        this.arr = { to, end, k, slide, more, T, deg, t0: this.t0, dx, dy };
    }

    /** the arrival's pose at now; done (the place in view, the pin dropping) once it has settled */
    _arrFrame(now) {
        const a = this.arr, p = this.pan, t = now - a.t0;
        let s, pitch, done = false;
        if (t <= p.ms) {
            s = Math.max(0, a.k * (a.deg(t) - a.deg(this.cur.enterT)));
            pitch = -90;
        } else {
            const v = clamp01((t - p.ms) / a.T), e = 1 - (1 - v) ** 3;
            s = a.slide + a.more * e;
            pitch = -90 + (a.to.pitch + 90) * e;
            done = v >= 1;
        }
        const back = a.slide + a.more - s;                                 // metres still to go to the list's view
        this.pose = { ...a.end, x: a.end.x - a.dx * back, y: a.end.y - a.dy * back, rotX: pitch };
        if (!done) return true;
        this.arr = null;
        this.rig = a.to;
        this._pinDrop(this.spawns[this.sel]);
        return true;
    }

    /** an arrival cut short (a place picked while it runs): the camera's rig from where it is */
    _endArr() {
        if (!this.arr) return;
        if (this.pose) this.rig = { ...poseRig(this.pose, this.arr.to.tz), shift: this.o.shift };
        this.arr = null;
    }

    // ---- the frame ----

    /** one frame: the map's edge, the camera, the pin, the fade; draw false = the state moves on but the map is not
     *  drawn (tests stepping a virtual clock) */
    _frame(draw = true) {
        let now;
        this.raf = 0;
        if (this.state === 'idle') return;
        now = this.now();                  // (not rAF's time, the frame's start: the messages are stamped with this clock)
        let more = false, show = true, landed = false;
        const o = this.o, p = this.pan;
        if (this.state === 'opening' || this.state === 'choosing' && this.edgeY < this.H + this.G) {
            const t = now - this.t0, edge = this._hemAt(t, false);
            this._edges(edge);
            show = edge > 0;
            if (!this.listShown && t >= this.cur.coverT + o.listAfter) {
                this.listShown = true;
                this.root.classList.add('ss-list-in');
                this.state = 'choosing';
                this._mark();
            }
            more = t < p.ms || !this.listShown;
        } else if (this.state === 'closing') {
            const t = now - this.t0, edge = this._hemAt(t, true);
            this._edges(edge);
            show = edge > 0;
            if (t >= p.ms) { this._finish(); return; }
            more = true;
        }
        if (this.tw) more = this._tweenFrame(now) || more;
        if (this.state === 'zooming') {
            // onto the game's held first frame in zoomMs, landing exactly on it; then still, and go
            const z = this.zoom, t = now - z.t0, e = ease.inOutCubic(clamp01(t / o.zoomMs));
            this.pose = zoomPose(z.from, z.to, z.focus, e);
            this.pinFade = 1 - clamp01((e - 0.15) / 0.4);             // the pin gives way to the character itself
            if (t >= o.zoomMs) { this.state = 'holding'; this.pose = { ...z.to, shiftX: 0, shiftY: 0 }; landed = true; }
            else more = true;
        } else if (this.state === 'holding') {
            this.pose = { ...this.zoom.to, shiftX: 0, shiftY: 0 };     // (only drawn again for a resize)
        } else if (this.state === 'fading') {
            // the scene is playing: fade out at once, the map on its camera all the way
            const t = now - this.tf;
            this.pose = this._livePose(now);
            this.root.style.opacity = String(1 - ease.inOutSine(clamp01(t / o.fadeMs)));
            if (t >= o.fadeMs) { this._finish(); return; }
            more = true;
        } else if (this.state === 'aborting') {
            const u = clamp01((now - this.ta) / o.abortMs);
            this.root.style.opacity = String(1 - u);
            if (u >= 1) { this._finish(); return; }
            more = true;
        } else if (this.arr) {
            more = this._arrFrame(now) || more;
        } else {
            this.pose = rigPose(this.rig, this.W);
        }
        more = this._pinFrame(now) || more;
        // nothing moving but the standing beacon's light: the map's last frame copied out with the beacon over it, at
        // most every pinIdleMs (renderPin draws the whole map itself if anything else did change)
        const lightOnly = !more && this.pinIdle;
        if (show && this.pose && draw) {
            this.map.setCamera(this.pose);
            if (!lightOnly) { this.map.render(); this.frames++; this.pinT = now; }
            else if (now - this.pinT >= this.o.pinIdleMs) {
                if (this.map.renderPin()) this.frames++; else this.pinFrames++;
                this.pinT = now;
            }
        }
        // landed: this frame was drawn exactly on the game's held camera, and nothing moves until started
        if (landed) this.nui('spawnsel:go', {});
        if (more || lightOnly && show) this._kick();
    }

    _finish() {
        this._stop();
        this.pinA = null; this.arr = null; this.zoom = null; this.live = null;
        if (this.map) { this.map.setPin(null); this._detach(); }
        this.root.hidden = true;
        this.root.className = 'ss';
        this.root.style.opacity = '';
        this.el.goTxt.textContent = 'Spawn here';
        this.state = 'idle';
        this.nui('spawnsel:done', {});
    }
}
