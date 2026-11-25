"""RedM (spur_core, 25 Nov 2026): new. How the item pictures in html/img/items were made.

An image model painted nine objects on one see-through sheet, three by three. This cuts each object out by its own
outline (one may lean out of its cell), drops the soft glow round it and saves it as a square 256 px PNG.
Needs Pillow.   usage: python cut_sheet.py sheet.png outdir name1,...,name9   (names in reading order)
"""
import sys
from collections import deque
from PIL import Image, ImageFilter
src, out, names = sys.argv[1], sys.argv[2], sys.argv[3].split(',')
im = Image.open(src).convert('RGBA')
W, H = im.size
LO, HI = 150, 235          # the glow round each object is half see-through: drop it, keep the object solid
lut = [0 if v <= LO else 255 if v >= HI else int((v - LO) * 255 / (HI - LO)) for v in range(256)]
im.putalpha(im.getchannel('A').point(lut))
K = 4
small = im.getchannel('A').resize((W // K, H // K), Image.BOX).point(lambda v: 255 if v > 40 else 0).filter(ImageFilter.MaxFilter(5))
w, h = small.size
px = small.load()
lab = [[0] * w for _ in range(h)]
comps = []
for y in range(h):
    for x in range(w):
        if px[x, y] and not lab[y][x]:
            n = len(comps) + 1
            q = deque([(x, y)]); lab[y][x] = n
            sx = sy = cnt = 0
            while q:
                a, b = q.popleft(); sx += a; sy += b; cnt += 1
                for c, d in ((a + 1, b), (a - 1, b), (a, b + 1), (a, b - 1)):
                    if 0 <= c < w and 0 <= d < h and px[c, d] and not lab[d][c]:
                        lab[d][c] = n; q.append((c, d))
            comps.append((n, cnt, sx / cnt, sy / cnt))
cell = {}
for n, cnt, cx, cy in comps:
    if cnt < w * h * 0.0015:
        continue
    cell.setdefault((int(cy * 3 / h), int(cx * 3 / w)), set()).add(n)
for i, name in enumerate(names):
    ids = cell.get(divmod(i, 3))
    assert ids, name
    m = Image.new('L', (w, h), 0)
    mp = m.load()
    for y in range(h):
        row = lab[y]
        for x in range(w):
            if row[x] in ids:
                mp[x, y] = 255
    m = m.resize((W, H), Image.NEAREST)
    obj = im.copy()
    from PIL import ImageChops
    obj.putalpha(ImageChops.multiply(obj.getchannel('A'), m))
    bb = obj.getchannel('A').point(lambda v: 255 if v > 40 else 0).getbbox()
    obj = obj.crop(bb)
    s = max(obj.size)
    sq = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    sq.paste(obj, ((s - obj.width) // 2, (s - obj.height) // 2))
    pad = Image.new('RGBA', (256, 256), (0, 0, 0, 0))
    pad.paste(sq.resize((232, 232), Image.LANCZOS), (12, 12))
    pad.save(f'{out}/{name}.png')
    print(name, bb, len(ids))
