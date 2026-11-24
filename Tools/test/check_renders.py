"""Checks the render matrix: heat image aligned with the chassis outline, nothing blank, no AppKit placeholders.
Usage: python3 Tools/test/check_renders.py <outdir>"""
import sys, os
from PIL import Image
out = sys.argv[1]
fails = 0
def sat(px):
    r, g, b = px[:3]; mx, mn = max(r, g, b), min(r, g, b)
    return 0 if mx == 0 else (mx - mn) / mx
for line in open(os.path.join(out, "index.txt")):
    name, *flags = line.split()
    im = Image.open(os.path.join(out, name + ".png")).convert("RGB")
    W, H = im.size; sc = 2
    size = next((f[7:] for f in flags if f.startswith("--size=")), None)
    w0, h0 = (map(float, size.split("x")) if size else (1440, 860))
    # geometry as in ContentView / ChassisView
    cw = w0 - 352.5; chh = h0 - 62 - 64
    s = min((cw - 100) / 304.1, (chh - 100) / 215)
    bw, bh = 304.1 * s, 215 * s
    ox, oy = (cw - bw) / 2, 62 + (chh - bh) / 2
    problems = []
    if name.startswith("align"):
        px = im.load()
        def at(x, y): return px[int(x * sc), int(y * sc)]
        inside = [(ox + 8, oy + bh / 2), (ox + bw - 8, oy + bh / 2), (ox + bw / 2, oy + bh - 8), (ox + 30, oy + bh - 30), (ox + bw - 30, oy + 30)]
        outside = [(ox - 6, oy + bh / 2), (ox + bw + 6, oy + bh / 2)]
        for p in inside:
            if sat(at(*p)) < 0.5: problems.append(f"no field at {tuple(int(v) for v in p)} {at(*p)}")
        for p in outside:
            if sat(at(*p)) > 0.35: problems.append(f"field outside chassis at {tuple(int(v) for v in p)} {at(*p)}")
    # blank check on the map area
    crop = im.crop((int(ox * sc), int(oy * sc), int((ox + bw) * sc), int((oy + bh) * sc))).resize((80, 56))
    vals = [sum(p) for p in crop.getdata()]
    if max(vals) - min(vals) < 60: problems.append("map area looks blank")
    # AppKit placeholder (pure yellow block) anywhere outside the map
    small = im.resize((W // 4, H // 4)); n = 0
    for i, p in enumerate(small.getdata()):
        x, y = (i % small.width) * 4 / sc, (i // small.width) * 4 / sc
        if ox <= x <= ox + bw and oy <= y <= oy + bh: continue
        if p[0] > 240 and p[1] > 185 and p[2] < 12: n += 1
    if n > 40: problems.append(f"placeholder-yellow pixels outside map: {n}")
    print(("FAIL  " if problems else "PASS  ") + name + ("  -- " + "; ".join(problems) if problems else ""))
    fails += bool(problems)
print("ALL PASS" if not fails else f"{fails} FAILED")
sys.exit(1 if fails else 0)
