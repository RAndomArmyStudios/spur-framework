"""Make map/rdr-map3d.js, the 3D map's data for RDR2, from a survey of the game (dev/map_survey.lua, collected by dev/map_survey_read.py).

RedM (spur_core, 25 Nov 2026). whip's 3D map (html/js/map3d/map3d.js: the pause map, the minimap and the spawn
picker) draws one data file, a media pack's map/whip-map3d.js: the original game's 2D map shapes standing on heights read from
the game. RDR2 has no such file, and none can be taken from the original game's. This builds one in the same format (meta.v 3), from
what the survey read in RDR2 itself: the ground's height on a grid, the water's surface, and the roads. Nothing is
downloaded and none of the game's map art is used. The renderer and the format are whip's (whip_core by Whippy and
WLVF); spur_core is non-commercial.

Run:  python -I dev/map3d_rdr.py <survey.json> [--out map/rdr-map3d.js]

The survey file (JSON):
    grid   {x0, y0, step, nx, ny}  the terrain grid, metres; point (i, j) is at (x0 + i*step, y0 + j*step)
    h      [nx*ny]  the ground's height at each point (row by row from y0), or null where nothing answered
    wgrid  {x0, y0, step, nx, ny}  the water grid (finer, so rivers show)
    w      [nx*ny]  the water's surface height over each point, or null for none
    roads  [{w, pts: [[x, y], ...]}]  roads and trails as lines, w their width in metres
The output is a plain script, `window.WHIP_MAP3D = {meta, bin}`, as the pause map loads it (pause-map.js loadGl).
"""
import base64
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'map', 'rdr-map3d.js')

# The palette's source colours. The page maps each to whip's own colours (map3d.js whipColour) and its kind by
# brightness (kindOf): land up to 35, buildings 36-129, paths 130, roads 131-180, highways over 180; water has more
# blue than red + 6. A colour in the wrong band changes what the shape is drawn as.
TOP_SHADE = 1.0            # top-down, the terrain's slope shading at full (whip's original map: none)
LAND_RGB = [48, 54, 50]    # the land as drawn (whip's [17, 20, 25] left RDR2's hills almost black)
COLOURS = [
    [20, 20, 20],      # 0 land (the terrain)
    [120, 200, 255],   # 1 water: lakes, rivers and the sea, whip's shore blue
    [80, 80, 80],      # 2 buildings
    [130, 130, 130],   # 3 trails
    [160, 160, 160],   # 4 roads
    [200, 200, 200],   # 5 main roads
]
LAND, WATER, BUILD, PATH, ROAD, HWY = range(6)

F_OFF, F_LEVEL, F_MULTI, F_DRAPE = 1, 2, 4, 8


# ---- writing ----
class Bytes:
    def __init__(self):
        self.b = bytearray()

    def u8(self, v):
        self.b.append(v & 0xFF)

    def u16(self, v):
        v = max(0, min(65535, int(round(v))))
        self.b += v.to_bytes(2, 'little')

    def varint(self, v):
        v = int(v)
        assert v >= 0
        while True:
            c = v & 0x7F
            v >>= 7
            if v:
                self.b.append(c | 0x80)
            else:
                self.b.append(c)
                return

    def zz(self, v):
        self.varint(2 * v if v >= 0 else -2 * v - 1)


def put_ring(out, pts, x0, y0):
    """A ring as the page reads it (ring()): its count, then each point's step from the last in decimetres, the first
    from the grid's origin."""
    dm = []
    for x, y in pts:
        p = (int(round((x - x0) * 10)), int(round((y - y0) * 10)))
        if not dm or p != dm[-1]:
            dm.append(p)
    if len(dm) > 1 and dm[0] == dm[-1]:
        dm.pop()
    out.varint(len(dm))
    lx = ly = 0
    for x, y in dm:
        out.zz(x - lx)
        out.zz(y - ly)
        lx, ly = x, y
    return len(dm)


# ---- the ground ----
def fill_holes(h):
    """Points nothing answered for take the mean of their answered neighbours, spreading inwards."""
    h = h.copy()
    known = ~np.isnan(h)
    if not known.any():
        raise SystemExit('the survey has no heights')
    for _ in range(max(h.shape)):
        if known.all():
            break
        acc = np.zeros_like(h)
        cnt = np.zeros_like(h)
        for dj, di in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)):
            sh = np.roll(np.roll(np.where(known, h, 0.0), dj, 0), di, 1)
            sk = np.roll(np.roll(known, dj, 0), di, 1)
            # no wrapping round the edges
            if dj == 1: sh[0, :] = 0; sk[0, :] = False
            if dj == -1: sh[-1, :] = 0; sk[-1, :] = False
            if di == 1: sh[:, 0] = 0; sk[:, 0] = False
            if di == -1: sh[:, -1] = 0; sk[:, -1] = False
            acc += sh
            cnt += sk
        new = (~known) & (cnt > 0)
        h[new] = acc[new] / cnt[new]
        known |= new
    return h


def _grow(m):
    """m with every point's 8 neighbours switched on too."""
    p = np.pad(m, 1)
    o = m.copy()
    for dj in (0, 1, 2):
        for di in (0, 1, 2):
            o |= p[dj:dj + m.shape[0], di:di + m.shape[1]]
    return o


def close_gaps(a, pocket=400):
    """RedM (spur_core, 25 Nov 2026): the answered points with the survey's gaps closed. The game gives no ground along
    the seams of its own map sections (x and y = 0, +-2560, -5120 ...: lines one point wide, 40 m of hole on the map),
    nor at odd single points. Closed: gaps up to two points wide (grow twice, shrink twice), and unanswered pockets of
    up to `pocket` points that answered ground surrounds. Their heights are fill_holes' (the neighbours' mean)."""
    g = _grow(_grow(a))
    g = ~_grow(_grow(np.pad(~g, 2, constant_values=True)))[2:-2, 2:-2]   # shrink; the edge counts as unanswered
    out = a | g
    # pockets: unanswered regions that don't reach the grid's edge
    ny, nx = out.shape
    seen = out.copy()
    for j0 in range(ny):
        for i0 in range(nx):
            if seen[j0, i0]:
                continue
            seen[j0, i0] = True
            reg, stack, open_ = [], [(j0, i0)], False
            while stack:
                j, i = stack.pop()
                reg.append((j, i))
                for jj, ii in ((j + 1, i), (j - 1, i), (j, i + 1), (j, i - 1)):
                    if jj < 0 or ii < 0 or jj >= ny or ii >= nx:
                        open_ = True
                    elif not seen[jj, ii]:
                        seen[jj, ii] = True
                        stack.append((jj, ii))
            if not open_ and len(reg) <= pocket:
                for j, i in reg:
                    out[j, i] = True
    return out


# ---- water outlines ----
def trace(mask):
    """The outlines of a mask's cells (True = water), in corner coordinates: corner (i, j) is the lower left of cell
    (i, j). Each ring has the water on its left: an outline goes anticlockwise, a hole (an island) clockwise."""
    ny, nx = mask.shape
    m = np.zeros((ny + 2, nx + 2), bool)
    m[1:-1, 1:-1] = mask
    out = {}   # corner -> [next corners]

    def edge(a, b):
        out.setdefault(a, []).append(b)

    for j in range(ny):
        row, below, above = m[j + 1], m[j], m[j + 2]
        for i in np.nonzero(mask[j])[0]:
            i = int(i)
            ci = i + 1
            if not below[ci]:
                edge((i, j), (i + 1, j))
            if not row[ci + 1]:
                edge((i + 1, j), (i + 1, j + 1))
            if not above[ci]:
                edge((i + 1, j + 1), (i, j + 1))
            if not row[ci - 1]:
                edge((i, j + 1), (i, j))
    rings = []
    while out:
        start = next(iter(out))
        ring = [start]
        prev, cur = None, start
        while True:
            nexts = out[cur]
            if len(nexts) == 1:
                nxt = nexts.pop()
            else:
                # two ways on (cells touching at a corner): the left turn, so the two stay separate rings
                dx, dy = (cur[0] - prev[0], cur[1] - prev[1]) if prev else (1, 0)
                left = (-dy, dx)
                pick = next((n for n in nexts if (n[0] - cur[0], n[1] - cur[1]) == left), nexts[0])
                nexts.remove(pick)
                nxt = pick
            if not nexts:
                del out[cur]
            if nxt == start:
                break
            ring.append(nxt)
            prev, cur = cur, nxt
        rings.append(ring)
    return rings


def area(r):
    s = 0.0
    for k in range(len(r)):
        x1, y1 = r[k]
        x2, y2 = r[(k + 1) % len(r)]
        s += x1 * y2 - x2 * y1
    return s / 2


def inside(pt, r):
    x, y = pt
    c = False
    for k in range(len(r)):
        x1, y1 = r[k]
        x2, y2 = r[k - 1]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            c = not c
    return c


def straighten(r):
    """Drop the points in the middle of straight runs."""
    out = []
    n = len(r)
    for k in range(n):
        a, b, c = r[k - 1], r[k], r[(k + 1) % n]
        if (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0]) != 0:
            out.append(b)
    return out


def chaikin(r, times=2):
    for _ in range(times):
        n = len(r)
        nr = []
        for k in range(n):
            (x1, y1), (x2, y2) = r[k], r[(k + 1) % n]
            nr.append((0.75 * x1 + 0.25 * x2, 0.75 * y1 + 0.25 * y2))
            nr.append((0.25 * x1 + 0.75 * x2, 0.25 * y1 + 0.75 * y2))
        r = nr
    return r


def water_polys(mask, wg):
    """The water as polygons [[outline, hole, ...], ...] in metres, smoothed."""
    s, x0, y0 = wg['step'], wg['x0'], wg['y0']
    rings = [straighten(r) for r in trace(mask)]
    rings = [r for r in rings if len(r) >= 3]
    to_m = lambda r: [(x0 + (ci - 0.5) * s, y0 + (cj - 0.5) * s) for ci, cj in r]
    outers = [r for r in rings if area(r) > 0]
    holes = [r for r in rings if area(r) < 0]
    polys = [[r] for r in outers]
    oa = [area(r) for r in outers]
    for hole in holes:
        # the point just inside the hole's first edge (on the water's side, the left)
        (ax, ay), (bx, by) = hole[0], hole[1]
        mx, my = (ax + bx) / 2, (ay + by) / 2
        p = (mx - (by - ay) * 0.25, my + (bx - ax) * 0.25)
        best = None
        for k, o in enumerate(outers):
            if (best is None or oa[k] < oa[best]) and inside(p, o):
                best = k
        if best is not None:
            polys[best].append(hole)
    return [[to_m(chaikin(r)) for r in pg] for pg in polys]


# ---- roads ----
def road_rings(pts, w):
    """A road as pieces: a quad per segment and a small octagon at each bend, so the bends have no gaps."""
    half = w / 2
    rings = []
    for k in range(len(pts) - 1):
        (x1, y1), (x2, y2) = pts[k], pts[k + 1]
        dx, dy = x2 - x1, y2 - y1
        L = math.hypot(dx, dy)
        if L < 0.1:
            continue
        nx, ny = -dy / L * half, dx / L * half
        # either way round: the page's triangulator (three's ShapeUtils) turns a ring the way it needs
        rings.append([(x1 - nx, y1 - ny), (x2 - nx, y2 - ny), (x2 + nx, y2 + ny), (x1 + nx, y1 + ny)])
    for k in range(1, len(pts) - 1):
        x, y = pts[k]
        rings.append([(x + half * math.cos(a), y + half * math.sin(a)) for a in (t * math.pi / 4 for t in range(8))])
    return rings


def main():
    args = sys.argv[1:]
    out_path = OUT
    if '--out' in args:
        k = args.index('--out')
        out_path = args[k + 1]
        del args[k:k + 2]
    if len(args) != 1:
        sys.exit('usage: python -I dev/map3d_rdr.py <survey.json> [--out map/rdr-map3d.js]')
    sv = json.load(open(args[0], encoding='utf-8'))

    g = sv['grid']
    nx, ny, step, x0, y0 = int(g['nx']), int(g['ny']), float(g['step']), float(g['x0']), float(g['y0'])
    h = np.array([np.nan if v is None else float(v) for v in sv['h']], float).reshape(ny, nx)
    answered = ~np.isnan(h)
    seams = int(answered.sum())
    answered = close_gaps(answered)
    print('gaps closed: %d points' % (int(answered.sum()) - seams))
    h = fill_holes(h)

    wg = sv.get('wgrid')
    shapes = []   # (colour, flags, polys)
    if wg and sv.get('w'):
        wnx, wny = int(wg['nx']), int(wg['ny'])
        wv = np.array([np.nan if v is None else float(v) for v in sv['w']], float).reshape(wny, wnx)
        wmask = ~np.isnan(wv)
        # the terrain at the water's surface where the water covers it (the probes find the bed), so the water,
        # laid on the terrain, lies at its own height
        for j in range(ny):
            for i in range(nx):
                wi = int(round((x0 + i * step - wg['x0']) / wg['step']))
                wj = int(round((y0 + j * step - wg['y0']) / wg['step']))
                if 0 <= wi < wnx and 0 <= wj < wny and wmask[wj, wi]:
                    h[j, i] = max(h[j, i], wv[wj, wi])
        polys = water_polys(wmask, wg)
        if polys:
            shapes.append((WATER, F_MULTI | F_DRAPE, polys))
    for kind, lo, hi in ((PATH, 0, 5.5), (ROAD, 5.5, 9), (HWY, 9, 99)):
        rings = []
        for rd in sv.get('roads', []):
            if lo <= rd['w'] < hi and len(rd['pts']) >= 2:
                rings += road_rings([tuple(p) for p in rd['pts']], rd['w'])
        if rings:
            shapes.append((kind, F_MULTI, [[r] for r in rings]))

    # land: every cell whose four corners the survey answered for (past them, the page shows its deep sea)
    cnx, cny = nx - 1, ny - 1
    land = answered[:-1, :-1] & answered[1:, :-1] & answered[:-1, 1:] & answered[1:, 1:]

    out = Bytes()
    terrain = 0
    for v in h.reshape(-1):
        t = max(-32768, min(32767, int(round(v * 10))))
        out.b += t.to_bytes(2, 'little', signed=True)
    landcells = len(out.b)
    lb = bytearray((cnx * cny + 7) // 8)
    flat = land.reshape(-1)
    for k in np.nonzero(flat)[0]:
        k = int(k)
        lb[k >> 3] |= 1 << (k & 7)
    out.b += lb
    shapes_at = len(out.b)
    for col, flags, polys in shapes:
        out.u8(col)
        out.u8(flags)
        assert flags & F_MULTI
        out.varint(len(polys))
        for pg in polys:
            out.varint(len(pg))
            for r in pg:
                put_ring(out, r, x0, y0)
    tops = len(out.b)
    for col, flags, polys in shapes:
        if col == BUILD:
            out.u16(0)
    assert terrain % 2 == 0

    meta = {
        'v': 3, 'grid': {'x0': x0, 'y0': y0, 'step': step, 'nx': nx, 'ny': ny},
        'sections': {'terrain': terrain, 'landcells': landcells, 'shapes': shapes_at, 'tops': tops},
        'colours': COLOURS, 'shapes': len(shapes), 'drape': 1, 'landColour': LAND,
        # the land is the map here (no building shapes): shaded by its slopes top-down too, in a lighter, earthier grey
        # than whip's near-black, so the hills read (map3d.js: topShade, landRgb)
        'topShade': TOP_SHADE, 'landRgb': LAND_RGB,
        'source': 'RDR2, surveyed in game by spur_core (dev/map_survey.lua); whip_core\'s 3D map format',
    }
    js = ('// RedM (spur_core): the 3D map\'s data for RDR2, made by dev/map3d_rdr.py from a survey of the game. Don\'t\n'
          '// edit by hand. The format and the renderer are whip\'s (whip_core by Whippy and WLVF); non-commercial.\n'
          'window.WHIP_MAP3D = ' + json.dumps({'meta': meta}, separators=(',', ':'))[:-1]
          + ',"bin":"' + base64.b64encode(bytes(out.b)).decode('ascii') + '"};\n')
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    with open(out_path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(js)
    nring = sum(len(pg) for _, _, polys in shapes for pg in polys)
    print('%d x %d grid at %g m, %d land cells, %d shapes (%d rings), %d bytes -> %s'
          % (nx, ny, step, int(land.sum()), len(shapes), nring, len(js), os.path.normpath(out_path)))


if __name__ == '__main__':
    main()
