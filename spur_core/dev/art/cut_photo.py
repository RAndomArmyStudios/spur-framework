"""Cut a museum photo's object from its plain backdrop: fit a smooth backdrop, keep what differs."""
import sys
import numpy as np
from PIL import Image, ImageFilter
src, dst, T = sys.argv[1], sys.argv[2], float(sys.argv[3]) if len(sys.argv) > 3 else 22
im = Image.open(src).convert('RGB')
a = np.asarray(im).astype(np.float32)
H, W, _ = a.shape
yy, xx = np.mgrid[0:H, 0:W]
x = xx / W - 0.5; y = yy / H - 0.5
B = np.stack([np.ones_like(x), x, y, x * x, y * y, x * y, x ** 3, y ** 3, x * x * y, x * y * y], -1).reshape(-1, 10)
bgmask = np.zeros((H, W), bool)
m = max(4, W // 30)
bgmask[:m] = bgmask[-m:] = True; bgmask[:, :m] = bgmask[:, -m:] = True
for it in range(6):
    idx = bgmask.reshape(-1)
    model = np.zeros_like(a)
    for c in range(3):
        co, *_ = np.linalg.lstsq(B[idx], a[..., c].reshape(-1)[idx], rcond=None)
        model[..., c] = (B @ co).reshape(H, W)
    diff = np.abs(a - model).max(-1)
    bgmask = diff < T * 0.6
lum = a.mean(-1); mlum = model.mean(-1)
sat = a.max(-1) - a.min(-1)
shadow = (lum > mlum * 0.52) & (sat < 26) & (lum < mlum + 6)      # the backdrop, only darker: a cast shadow
if len(sys.argv) > 4: shadow[:] = False      # a black-and-white photo: grey is the gun too
fg = Image.fromarray((((diff > T) & ~shadow) * 255).astype(np.uint8))
fg = fg.filter(ImageFilter.MaxFilter(7)).filter(ImageFilter.MinFilter(7))       # close small gaps
# keep the big connected piece(s)
from scipy import ndimage as ndi
lab, n = ndi.label(np.asarray(fg) > 0)
sizes = ndi.sum(np.ones_like(lab), lab, range(1, n + 1))
keep = np.isin(lab, [i + 1 for i, s in enumerate(sizes) if s > sizes.max() * 0.08])
keep = ndi.binary_erosion(keep, iterations=1)
al = Image.fromarray((keep * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))
out = im.convert('RGBA'); out.putalpha(al)
out = out.crop(out.getchannel('A').point(lambda v: 255 if v > 30 else 0).getbbox())
out.save(dst); print(dst, out.size)
