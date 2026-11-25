// RedM (spur_phone, 24 Nov 2026): new file, in place of whip_phone's duo.js (a 3D phone drawn with three.js). The
// pocket notebook is flat: the OS's displays (os.js View hosts) are placed on the screen with CSS, inside a leather
// cover drawn in CSS too. It keeps duo.js's interface, so main.js and os.js drive it the same way:
//
//   closed ('phone')   the small notebook, bottom right: the OS's phone display is its page
//   open ('tablet')    the two-page spread in the middle of the screen (the tablet display; tabletP on an upright screen)
//   peek               put away with notices waiting: the closed notebook's top edge shows at the bottom right
//   hidden             put away
//
// Mouse, keyboard and controller input are the OS's own (os.js); nothing here reads them.

import { SIZE } from './os.js';

const MOVE_MS = 320;                                  // a move between states
const EASE = 'cubic-bezier(.2,.9,.25,1)';
const COVER = { phone: { l: 16, t: 10, r: 10, b: 10 }, tablet: { l: 14, t: 12, r: 14, b: 12 } };   // cover past the page, px at k = 1

const FRAME_CSS = `
.nb-frame{position:absolute;left:0;top:0;transform-origin:0 0;pointer-events:none;opacity:0;visibility:hidden;
  border-radius:7px;background:var(--nb-cover,#6b4a2e);
  background-image:radial-gradient(circle at 30% 20%,rgba(255,255,255,.08),transparent 60%),
    repeating-linear-gradient(45deg,rgba(0,0,0,.035) 0 2px,transparent 2px 5px);
  box-shadow:0 18px 40px rgba(0,0,0,.55),0 3px 8px rgba(0,0,0,.45),inset 0 0 0 1px rgba(0,0,0,.35),inset 0 0 18px rgba(0,0,0,.35)}
.nb-frame::before{content:'';position:absolute;pointer-events:none}
.nb-frame.closed::before{left:7px;top:8px;bottom:8px;width:0;border-left:1.5px dashed rgba(255,240,210,.35)}
.nb-frame.open::before{left:50%;top:-6px;bottom:-6px;width:22px;margin-left:-11px;border-radius:5px;
  background:linear-gradient(90deg,rgba(0,0,0,.25),rgba(255,255,255,.07) 45%,rgba(0,0,0,.25));background-color:var(--nb-cover,#6b4a2e)}
.nb-frame .nb-ribbon{position:absolute;top:100%;width:12px;height:34px;margin-top:-6px;background:var(--nb-ribbon,#7a1f1f);
  clip-path:polygon(0 0,100% 0,100% 100%,50% 78%,0 100%);box-shadow:0 2px 3px rgba(0,0,0,.4)}
.nb-frame.closed .nb-ribbon{right:46px}
.nb-frame.open .nb-ribbon{left:calc(50% + 40px)}
@media (prefers-reduced-motion: reduce){.nb-frame,.os-host{transition-duration:1ms!important}}
`;

export class NotebookViewer {
  /**
   * { os, onChange(openness, state), onArea(area), hidden, phoneScale }. (`canvas`, `glb` and `topBar` were the 3D
   * phone's; they are ignored.)
   */
  constructor({ os, onChange = null, onArea = null, hidden = true, phoneScale = 0.5 } = {}) {
    this.os = os; this.onChange = onChange; this.onArea = onArea;
    this.phoneScale = phoneScale;
    this.wobble = 0; this.tiltAmount = 0;             // (the 3D phone's sway: kept so callers can still set them)
    this.mode = 'phone';                              // the display in use when shown: 'phone' (closed) or 'tablet' (open)
    this.hidden = !!hidden;
    this.peek = 0;                                    // notices peeking up while it is put away
    this.settled = true;
    this._timer = 0;
    if (!document.getElementById('nb-frame-css')) {
      document.head.appendChild(Object.assign(document.createElement('style'), { id: 'nb-frame-css', textContent: FRAME_CSS }));
    }
    const parent = os.views.phone.host.parentNode || document.body;
    const frame = (cls) => {
      const el = document.createElement('div');
      el.className = `nb-frame ${cls}`;
      el.innerHTML = '<i class="nb-ribbon"></i>';
      parent.insertBefore(el, parent.firstChild);   // under the pages
      return el;
    };
    this.frames = { phone: frame('closed'), tablet: frame('open') };
    for (const h of Object.values(os.hosts)) {
      h.style.transition = `transform ${MOVE_MS}ms ${EASE}, opacity ${MOVE_MS * 0.8}ms ease`;
    }
    for (const f of Object.values(this.frames)) {
      f.style.transition = `transform ${MOVE_MS}ms ${EASE}, opacity ${MOVE_MS * 0.8}ms ease`;
    }
    if (os.wp) this.setWallpaper(os.wp);             // the cover os.js started with (it tells us of later changes)
    addEventListener('resize', () => this.relayout());
    this.ready = Promise.resolve(true);
    this.os.setHidden(this.hidden);
    this.os.setMode(this.mode, 'phone');
    this.relayout(true);
  }

  /** what the player sees: 'hidden' | 'peek' | 'phone' | 'tablet', or null while it moves */
  get state() {
    if (!this.settled) return null;
    if (this.hidden) return this.peek > 0 ? 'peek' : 'hidden';
    return this.mode;
  }

  // ---------------------------------------------------------------- what callers ask
  /** closed <-> open (Y, the ribbon's button) */
  toggle() { if (!this.hidden) this.goTo(this.mode === 'phone' ? 'tablet' : 'phone'); }
  hide() { this.goTo('hidden'); }
  show(mode = 'phone') { this.goTo(mode === 'tablet' ? 'tablet' : 'phone'); }
  /** n notices waiting while it is put away: that much of the closed notebook peeks up */
  setPeek(n) {
    n = Math.max(0, n | 0);
    if (n === this.peek) return;
    this.peek = n;
    if (this.hidden) this.relayout();
  }
  goTo(target) {
    if (target === 'hidden') {
      if (this.hidden) return;
      this.hidden = true;
    } else {
      const was = this.hidden ? 'hidden' : this.mode;
      if (was === target) return;
      this.hidden = false;
      this.mode = target === 'tablet' ? 'tablet' : 'phone';
    }
    this.os.activeKey = null;                         // moving: no display takes input until it settles
    this.settled = false;
    this.os.setHidden(this.hidden);
    this.relayout();
    clearTimeout(this._timer);
    this._timer = setTimeout(() => this.settle(), MOVE_MS + 20);
  }
  settle() {
    this.settled = true;
    const key = this.mode === 'phone' ? 'phone' : this.innerKey();
    this.os.setMode(this.hidden ? 'phone' : this.mode, this.hidden ? 'phone' : key);
    this.os.endBoot();
    this.os.renderNow();
    this.relayout(true);
    this.report();
  }
  setWallpaper(wp) {
    // the cover's leather and the ribbon follow the chosen cover (wallpaper.js)
    const c = wp && wp.cover, r = wp && wp.ribbon;
    for (const f of Object.values(this.frames)) {
      if (c) f.style.setProperty('--nb-cover', c);
      if (r) f.style.setProperty('--nb-ribbon', r);
    }
  }
  pointer() {}
  pointerLeave() {}

  // ---------------------------------------------------------------- placing
  /** the open notebook's display: the upright one on a screen taller than wide */
  innerKey() { return innerWidth < innerHeight * 0.85 ? 'tabletP' : 'tablet'; }

  /** place every display and its cover for the state it is going to. now: no transition (a resize, a settle). */
  relayout(now = false) {
    const W = innerWidth, H = innerHeight, os = this.os;
    const inner = this.innerKey();
    os.inner = inner;
    const place = {};
    // closed: Config.PhoneSize of the screen's height, bottom right
    {
      const [w, h] = SIZE.phone;
      const k = Math.max(0.2, (H * this.phoneScale) / h);
      const c = COVER.phone;
      const x = W - w * k - c.r * k - Math.max(16, W * 0.025);
      let y = H - h * k - c.b * k - Math.max(16, H * 0.03);
      let shown = !this.hidden && this.mode === 'phone';
      if (this.hidden) {
        // put away: below the screen, or with notices waiting, its top edge up far enough to show them
        y = this.peek > 0 ? H - Math.min(h, os.peekHeight(this.peek)) * k : H + 40;
        shown = this.peek > 0;
      }
      place.phone = { k, x, y, shown, c };
    }
    // open: as big as fits, in the middle
    for (const key of ['tablet', 'tabletP']) {
      const [w, h] = SIZE[key];
      const c = COVER.tablet;
      const k = Math.min((W * 0.9) / (w + c.l + c.r), (H * 0.86) / (h + c.t + c.b));
      const x = (W - w * k) / 2, y = (H - h * k) / 2 + H * 0.01;
      const shown = !this.hidden && this.mode === 'tablet' && key === inner;
      place[key] = { k, x, y, shown, c };
    }
    for (const [key, p] of Object.entries(place)) this.put(key, p, now);
    this.putFrame(this.frames.phone, place.phone, SIZE.phone, now);
    this.putFrame(this.frames.tablet, place[inner], SIZE[inner], now);
    this._place = place;
    this.onChange?.(this.mode === 'tablet' && !this.hidden ? 1 : 0, this.state);
    if (now) this.report();
  }
  put(key, p, now) {
    const v = this.os.views[key], host = v.host;
    // the display is drawn at its size on screen (crisp text), not stretched
    v.setScale(Math.round(p.k * 1000) / 1000);
    const lift = p.shown ? 0 : (key === 'phone' ? 0 : 14);
    host.style.transition = now ? 'none' : `transform ${MOVE_MS}ms ${EASE}, opacity ${MOVE_MS * 0.8}ms ease`;
    host.style.transform = `translate(${p.x.toFixed(1)}px, ${(p.y + lift).toFixed(1)}px)`;
    if (p.shown) {
      host.style.visibility = 'visible';
      host.style.opacity = '1';
      host.style.pointerEvents = 'auto';
    } else {
      host.style.opacity = '0';
      host.style.pointerEvents = 'none';
      if (now) host.style.visibility = 'hidden';
      else setTimeout(() => { if (host.style.opacity === '0') host.style.visibility = 'hidden'; }, MOVE_MS);
    }
  }
  putFrame(f, p, size, now) {
    const [w, h] = size, c = p.c, k = p.k;
    f.style.width = (w + c.l + c.r) + 'px';
    f.style.height = (h + c.t + c.b) + 'px';
    f.style.transition = now ? 'none' : `transform ${MOVE_MS}ms ${EASE}, opacity ${MOVE_MS * 0.8}ms ease`;
    f.style.transform = `translate(${(p.x - c.l * k).toFixed(1)}px, ${(p.y - c.t * k).toFixed(1)}px) scale(${k.toFixed(4)})`;
    if (p.shown) { f.style.visibility = 'visible'; f.style.opacity = '1'; }
    else {
      f.style.opacity = '0';
      if (now) f.style.visibility = 'hidden';
      else setTimeout(() => { if (f.style.opacity === '0') f.style.visibility = 'hidden'; }, MOVE_MS);
    }
  }

  /** where the notebook sits, as shares of the screen, for spur_core's HUD to make room (null: nothing shown) */
  report() {
    if (!this.onArea || !this._place) return;
    const W = innerWidth, H = innerHeight;
    let p = null, size = null;
    if (!this.hidden) { const key = this.mode === 'phone' ? 'phone' : this.innerKey(); p = this._place[key]; size = SIZE[key]; }
    else if (this.peek > 0) { p = this._place.phone; size = SIZE.phone; }
    if (!p) { this.onArea(null); return; }
    const c = p.c, k = p.k;
    const left = (p.x - c.l * k) / W, top = Math.max(0, (p.y - c.t * k) / H);
    const right = (p.x + (size[0] + c.r) * k) / W, bottom = Math.min(1, (p.y + (size[1] + c.b) * k) / H);
    const r = (n) => Math.round(Math.max(0, Math.min(1, n)) * 1000) / 1000;
    this.onArea({ left: r(left), top: r(top), right: r(right), bottom: r(bottom) });
  }
}
