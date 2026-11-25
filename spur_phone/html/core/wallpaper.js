// RedM (spur_phone, 24 Nov 2026): rewritten. whip_phone's wallpapers were colourful gradients behind a 3D phone's
// screens; the pocket notebook has a COVER (its leather, its ribbon) and PAPER (its colour, ruled or plain) instead.
// A "wallpaper" here is one of those pairs: Settings → Cover and paper. The exports keep whip_phone's names, so os.js
// and Settings read them as they did:
//   PALETTES             the choices, each { label, cover, ribbon, paper, rule, margin, css (Settings' swatch) }
//   DEFAULT_WALLPAPER    a fresh notebook's (Config.Defaults.wallpaper on the server says which; it wins)
//   resolveWallpaper     an id as one of these, or null (an address card saved with whip_phone's gradients shows
//                        the default)
//   makeWallpaper        -> { name, sky, mountain, dune, vars }: `sky` is the paper (drawn into each page by
//                        paintPanel), the other two are left empty; `vars` the CSS colours of the cover (os.js puts
//                        them on each page, notebook.js on the leather round it)
//   paintPanel           draws the paper into a page's canvas
// No 3D, no parallax, no fold: the paper is flat.

export const PALETTES = {
  tan:       { label: 'Tan calf',     cover: '#8a5a32', ribbon: '#6e1b1b', paper: '#efe4cc', rule: null,                    margin: null },
  oxblood:   { label: 'Oxblood',      cover: '#5a1a17', ribbon: '#c9a548', paper: '#f1e6cf', rule: null,                    margin: null },
  bottle:    { label: 'Bottle green', cover: '#23402d', ribbon: '#7a1f1f', paper: '#ede3c8', rule: null,                    margin: null },
  navy:      { label: 'Navy cloth',   cover: '#1f2a44', ribbon: '#8b1e1e', paper: '#efe6d2', rule: null,                    margin: null },
  black:     { label: 'Black morocco', cover: '#1d1a17', ribbon: '#7a1f1f', paper: '#eee5cf', rule: null,                   margin: null },
  ledger:    { label: 'Ledger',       cover: '#4a3626', ribbon: '#2f5a3a', paper: '#eef0de', rule: 'rgba(60,120,80,.28)',   margin: 'rgba(170,40,40,.35)' },
  foolscap:  { label: 'Foolscap',     cover: '#2b2622', ribbon: '#7a1f1f', paper: '#f3ecd8', rule: 'rgba(70,100,160,.25)',  margin: 'rgba(170,40,40,.35)' },
  onionskin: { label: 'Onionskin',    cover: '#3a3f4a', ribbon: '#6e1b1b', paper: '#f5f1e6', rule: 'rgba(90,90,90,.12)',    margin: null },
};

/** What a notebook shows when it has none. */
export const DEFAULT_WALLPAPER = 'tan';

/** A cover's id as one of these, or null for one there is not (whip_phone's gradients included). */
export function resolveWallpaper(name) {
  return typeof name === 'string' && PALETTES[name] ? name : null;
}

const RULE_PX = 26;          // the ruled lines' pitch, in page px
const MARGIN_PX = 38;        // the margin line, from the left edge, in page px

/** a faint paper grain, made once (the same speckle on every page) */
let grain = null;
function grainPattern(g) {
  if (!grain) {
    grain = document.createElement('canvas'); grain.width = grain.height = 192;
    const ng = grain.getContext('2d'), id = ng.createImageData(192, 192);
    let s = 1899;
    const rand = () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; };
    for (let i = 0; i < id.data.length; i += 4) {
      const v = rand() < 0.55 ? 90 : 255;
      id.data[i] = v; id.data[i + 1] = Math.round(v * 0.92); id.data[i + 2] = Math.round(v * 0.8);
      id.data[i + 3] = Math.floor(rand() * 16);
    }
    ng.putImageData(id, 0, 0);
  }
  return g.createPattern(grain, 'repeat');
}

/** -> { name, sky, mountain, dune, vars }. sky: the palette itself (paintPanel draws it at each page's size). */
export function makeWallpaper(name = DEFAULT_WALLPAPER) {
  const id = resolveWallpaper(name) || DEFAULT_WALLPAPER;
  const pal = PALETTES[id];
  return {
    name: id, sky: pal, mountain: null, dune: null,
    cover: pal.cover, ribbon: pal.ribbon, paper: pal.paper,
    vars: { '--cover': pal.cover, '--ribbon': pal.ribbon, '--paper': pal.paper },
  };
}

/**
 * Draw the paper into a page's canvas (the canvas is the page's size, twice over). which: ['sky'] draws the paper;
 * anything else (the old near layers) leaves the canvas clear. panel / openness are kept for os.js's call.
 */
export function paintPanel(ctx, wp, panel, openness, which) {
  const { width: W, height: H } = ctx.canvas;
  ctx.clearRect(0, 0, W, H);
  if (!which.includes('sky') || !wp || !wp.sky) return;
  const pal = wp.sky, k = 2;                         // canvas px per page px (os.js View: w * 2)
  ctx.fillStyle = pal.paper; ctx.fillRect(0, 0, W, H);
  // the edges a shade darker: old paper
  const edge = ctx.createRadialGradient(W / 2, H / 2, Math.min(W, H) * 0.35, W / 2, H / 2, Math.max(W, H) * 0.75);
  edge.addColorStop(0, 'rgba(120,80,30,0)'); edge.addColorStop(1, 'rgba(120,80,30,.16)');
  ctx.fillStyle = edge; ctx.fillRect(0, 0, W, H);
  ctx.fillStyle = grainPattern(ctx); ctx.fillRect(0, 0, W, H);
  if (pal.rule) {
    ctx.strokeStyle = pal.rule; ctx.lineWidth = 1 * k;
    for (let y = 92 * k; y < H; y += RULE_PX * k) { ctx.beginPath(); ctx.moveTo(0, y + 0.5); ctx.lineTo(W, y + 0.5); ctx.stroke(); }
  }
  if (pal.margin) {
    ctx.strokeStyle = pal.margin; ctx.lineWidth = 1.2 * k;
    ctx.beginPath(); ctx.moveTo(MARGIN_PX * k, 0); ctx.lineTo(MARGIN_PX * k, H); ctx.stroke();
  }
}

/** Settings' swatch: the cover, the ribbon across it and the paper's edge showing. */
function cssOf(pal) {
  const lines = pal.rule ? `, repeating-linear-gradient(180deg, transparent 0 9px, ${pal.rule} 9px 10px)` : '';
  return `linear-gradient(90deg, transparent 0 62%, ${pal.ribbon} 62% 70%, transparent 70%), ` +
    `linear-gradient(90deg, ${pal.cover} 0 84%, rgba(0,0,0,.35) 84% 85%, transparent 85%)${lines}, ` +
    `linear-gradient(${pal.paper}, ${pal.paper})`;
}
for (const pal of Object.values(PALETTES)) pal.css = cssOf(pal);
