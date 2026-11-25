"""Collect dev/map_survey.lua's readings from the RedM logs into one survey file for dev/map3d_rdr.py.

RedM (spur_core, 25 Nov 2026): new. Part of spur_core (LGPL-3.0), the RedM port of whip_core by Whippy and WLVF;
non-commercial. The survey prints "MAPSV ..." lines to the game's console; RedM writes them to its log on this PC.

Run:  python -I dev/map_survey_read.py <survey.json> [log files or folders ...] [--since 2026-11-25T00:00]
With no logs named it reads every CitizenFX_log_*.log in %LOCALAPPDATA%/RedM/RedM.app/logs (oldest first, so a later
reading of a block wins).

What it decides:
- The ground at each point from its layers (the survey peels: roof, floor, ..., ground). The lowest layer, unless it
  sits far under its neighbours (a mine, a cellar, a cave): then the layer nearest the neighbours' median.
- The water at each point: the probe's surface where it answered; then spread to the neighbours inside a water zone
  whose ground lies under that surface (the probe reaches about 150 m from where the survey looked).
- The roads: each node joined to its nearest neighbours along its heading (both ways), the joins chained into lines
  between junctions and ends, simplified to 1 m; the width from the nodes' lanes.
"""
import glob
import json
import math
import os
import re
import sys
from collections import defaultdict

LINE = re.compile(r'MAPSV (\S+) (\d+) (.*?) (\d+)/(\d+) ?(.*)$')


def read_logs(files, since):
    """The survey's records, run by run: [{'H': header, 'recs': [(kind, head, body), ...]}]."""
    runs = []
    for f in files:
        if since and os.path.getmtime(f) < since:
            continue
        cur = None
        parts = {}
        with open(f, encoding='utf-8', errors='replace') as fh:
            for raw in fh:
                k = raw.find('MAPSV ')
                if k < 0:
                    continue
                m = LINE.match(raw[k:].rstrip('\r\n'))
                if not m:
                    continue
                kind, seq, head, p, n, body = m.group(1), int(m.group(2)), m.group(3), int(m.group(4)), int(m.group(5)), m.group(6).strip()
                if kind == 'H' and p == 1:
                    if cur is not None:
                        cur['bad'] += len(parts)
                    cur = {'H': None, 'recs': [], 'bad': 0}
                    runs.append(cur)
                    parts = {}
                if cur is None:
                    continue
                got = parts.setdefault(seq, {})
                got[p] = body
                if len(got) == n:
                    full = ''.join(got[q] for q in range(1, n + 1)) if all(q in got for q in range(1, n + 1)) else None
                    del parts[seq]
                    if full is None:
                        cur['bad'] += 1
                        continue
                    if kind == 'H':
                        cur['H'] = json.loads(full)
                    else:
                        cur['recs'].append((kind, head, full))
        if cur is not None:
            cur['bad'] += len(parts)   # a record cut off (the game closed in the middle of it)
    return [r for r in runs if r['H']]


def median(v):
    v = sorted(v)
    n = len(v)
    return v[n // 2] if n % 2 else (v[n // 2 - 1] + v[n // 2]) / 2


def choose_ground(layers, nx, ny):
    """Each point's ground from its layers (decimetres, top first)."""
    g = [None] * (nx * ny)
    for k, ls in layers.items():
        g[k] = ls[-1] / 10
    for _ in range(2):
        new = list(g)
        for k, ls in layers.items():
            if len(ls) < 2:
                continue
            j, i = divmod(k, nx)
            near = [g[jj * nx + ii] for jj in range(max(0, j - 2), min(ny, j + 3)) for ii in range(max(0, i - 2), min(nx, i + 3))
                    if (jj, ii) != (j, i) and g[jj * nx + ii] is not None]
            if len(near) < 4:
                continue
            med = median(near)
            if g[k] < med - 6:
                new[k] = min((l / 10 for l in ls), key=lambda z: abs(z - med))
        g = new
    return g


def spread_water(w, ground, wzone, nx, ny):
    """Water from where the probe answered on to the neighbours in a water zone whose ground is under it."""
    w = list(w)
    front = [k for k in range(nx * ny) if w[k] is not None]
    while front:
        nxt = []
        for k in front:
            j, i = divmod(k, nx)
            for jj, ii in ((j + 1, i), (j - 1, i), (j, i + 1), (j, i - 1)):
                if 0 <= jj < ny and 0 <= ii < nx:
                    q = jj * nx + ii
                    if w[q] is None and wzone[q] and ground[q] is not None and ground[q] < w[k] - 0.2:
                        w[q] = w[k]
                        nxt.append(q)
        front = nxt
    return w


def roads_from(nodes):
    """Nodes (x, y, z, heading, lanes) to lines [{'w', 'pts'}]."""
    cell = defaultdict(list)
    for k, (x, y, z, hd, ln) in enumerate(nodes):
        cell[(int(x // 12), int(y // 12))].append(k)
    edges = set()
    cos30 = math.cos(math.radians(30))
    for k, (x, y, z, hd, ln) in enumerate(nodes):
        dx, dy = -math.sin(math.radians(hd)), math.cos(math.radians(hd))   # 0 = north, counter-clockwise
        best = {1: None, -1: None}
        cx, cy = int(x // 12), int(y // 12)
        for a in (cx - 1, cx, cx + 1):
            for b in (cy - 1, cy, cy + 1):
                for q in cell.get((a, b), ()):
                    if q == k:
                        continue
                    qx, qy = nodes[q][0] - x, nodes[q][1] - y
                    d = math.hypot(qx, qy)
                    if d < 0.5 or d > 11 or abs(nodes[q][2] - z) > 4:
                        continue
                    c = (qx * dx + qy * dy) / d
                    if abs(c) < cos30:
                        continue
                    side = 1 if c > 0 else -1
                    if best[side] is None or d < best[side][0]:
                        best[side] = (d, q)
        for side in (1, -1):
            if best[side]:
                q = best[side][1]
                edges.add((min(k, q), max(k, q)))
    adj = defaultdict(list)
    for a, b in edges:
        adj[a].append(b)
        adj[b].append(a)
    used = set()
    lines = []

    def walk(a, b):
        line = [a, b]
        used.add((min(a, b), max(a, b)))
        prev, cur = a, b
        while len(adj[cur]) == 2:
            nxt = adj[cur][0] if adj[cur][1] == prev else adj[cur][1]
            e = (min(cur, nxt), max(cur, nxt))
            if e in used:
                break
            used.add(e)
            line.append(nxt)
            prev, cur = cur, nxt
        return line

    for a in list(adj):
        if len(adj[a]) != 2:
            for b in adj[a]:
                if (min(a, b), max(a, b)) not in used:
                    lines.append(walk(a, b))
    for a in list(adj):   # loops with no junction or end
        for b in adj[a]:
            if (min(a, b), max(a, b)) not in used:
                lines.append(walk(a, b))
    out = []
    for ln in lines:
        pts = simplify([(nodes[k][0], nodes[k][1]) for k in ln], 1.0)
        lanes = median([nodes[k][4] for k in ln])
        w = 4.0 if lanes <= 1 else 7.0 if lanes <= 2 else 10.0
        out.append({'w': w, 'pts': [[round(x, 1), round(y, 1)] for x, y in pts]})
    return out, len(edges)


def simplify(pts, tol):
    if len(pts) < 3:
        return pts
    (ax, ay), (bx, by) = pts[0], pts[-1]
    L = math.hypot(bx - ax, by - ay)
    far, fk = -1, 0
    for k in range(1, len(pts) - 1):
        px, py = pts[k]
        d = abs((bx - ax) * (ay - py) - (ax - px) * (by - ay)) / L if L > 1e-6 else math.hypot(px - ax, py - ay)
        if d > far:
            far, fk = d, k
    if far <= tol:
        return [pts[0], pts[-1]]
    return simplify(pts[:fk + 1], tol)[:-1] + simplify(pts[fk:], tol)


def main():
    args = sys.argv[1:]
    since = None
    if '--since' in args:
        k = args.index('--since')
        from datetime import datetime
        since = datetime.fromisoformat(args[k + 1]).timestamp()
        del args[k:k + 2]
    if not args:
        sys.exit(__doc__)
    out_path, srcs = args[0], args[1:]
    if not srcs:
        srcs = [os.path.join(os.environ.get('LOCALAPPDATA', ''), 'RedM', 'RedM.app', 'logs')]
    files = []
    for s in srcs:
        files += sorted(glob.glob(os.path.join(s, 'CitizenFX_log_*.log'))) if os.path.isdir(s) else [s]
    files.sort(key=os.path.getmtime)
    runs = read_logs(files, since)
    if not runs:
        sys.exit('no survey in ' + ', '.join(srcs))
    H = runs[-1]['H']
    nx, ny, step, x0, y0, B = H['nx'], H['ny'], H['step'], H['x0'], H['y0'], H['b']
    mask = [0] * (nx * ny)
    layers, water = {}, [None] * (nx * ny)
    nodes, seen = [], set()
    blocks = 0
    for run in runs:
        h = run['H']
        if (h['nx'], h['ny'], h['step'], h['x0'], h['y0'], h['b']) != (nx, ny, step, x0, y0, B):
            print('skipping a run on another grid')
            continue
        for kind, head, body in run['recs']:
            if kind == 'M':
                j, i = int(head), 0
                for runlen in body.split(','):
                    c, n = runlen.split('x')
                    for _ in range(int(n)):
                        if int(c):
                            mask[j * nx + i] = int(c)
                        i += 1
            elif kind == 'B':
                bi, bj = map(int, head.split())
                blocks += 1
                k, ents = 0, body.split(';')
                for j in range(bj * B, min(ny, bj * B + B)):
                    for i in range(bi * B, min(nx, bi * B + B)):
                        e = ents[k] if k < len(ents) else ''
                        k += 1
                        q = j * nx + i
                        ls, _, wv = e.partition('~')
                        if ls:
                            layers[q] = [int(v) for v in ls.split('/')]
                        if wv:
                            water[q] = int(wv) / 10
            elif kind == 'N':
                for e in body.split(';'):
                    x, y, z, hd, ln = (int(v) for v in e.split(','))
                    key = (x // 5, y // 5)
                    if key not in seen:
                        seen.add(key)
                        nodes.append((x / 10, y / 10, z / 10, hd, ln))
    bad = sum(r['bad'] for r in runs)
    ground = choose_ground(layers, nx, ny)
    wzone = [m == 2 for m in mask]
    w = spread_water(water, ground, wzone, nx, ny)
    roads, nedges = roads_from(nodes)
    sv = {'grid': {'x0': x0, 'y0': y0, 'step': step, 'nx': nx, 'ny': ny}, 'h': [None if v is None else round(v, 2) for v in ground],
          'wgrid': {'x0': x0, 'y0': y0, 'step': step, 'nx': nx, 'ny': ny}, 'w': w, 'roads': roads}
    with open(out_path, 'w', encoding='utf-8') as f:
        json.dump(sv, f, separators=(',', ':'))
    print('%d runs, %d records lost; mask %d points (%d water zone); %d blocks, %d points with ground (%d moved off the lowest '
          'layer); %d probe water, %d with spread; %d nodes, %d joins, %d lines -> %s'
          % (len(runs), bad, sum(1 for m in mask if m), sum(wzone), blocks, sum(1 for v in ground if v is not None),
             sum(1 for k, ls in layers.items() if ground[k] is not None and abs(ground[k] - ls[-1] / 10) > 0.01),
             sum(1 for v in water if v is not None), sum(1 for v in w if v is not None), len(nodes), nedges, len(roads), out_path))


if __name__ == '__main__':
    main()
