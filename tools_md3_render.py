"""Render an MD3 frame to PNG: three orthographic wireframe views.

    python tools_md3_render.py MESH.md3 OUT.png [--frame N] [--frame2 M]

Panels: TOP (X right, Y up), SIDE (X right, Z up), FRONT (Y right, Z up).
Axes through the origin in grey. The frame's OWN header bounding box in
red. If the mesh does not sit inside its red box, the projection is
wrong -- that is the self-check, and it cannot be fooled by a pretty
picture. --frame2 overlays a second frame in blue to show motion.
"""
import struct, sys
from PIL import Image, ImageDraw

GRID = 64.0


def load(path, frame):
    b = open(path, "rb").read()
    nf, nt, ns, nsk, of, ot, osf, oe = struct.unpack_from("<8i", b, 76)
    assert 0 <= frame < nf
    o = of + frame * 56
    mn = struct.unpack_from("<3f", b, o); mx = struct.unpack_from("<3f", b, o + 12)
    pts, tris = [], []
    o = osf
    for _ in range(ns):
        nfr, nsh, nv, ntri, otri, osh, ost, oxyz, oend = struct.unpack_from("<9i", b, o + 72)
        base = len(pts)
        vb = o + oxyz + frame * nv * 8
        for v in range(nv):
            x, y, z = struct.unpack_from("<hhh", b, vb + v * 8)
            pts.append((x / GRID, y / GRID, z / GRID))
        tb = o + otri
        for t in range(ntri):
            a, bb, c = struct.unpack_from("<3i", b, tb + t * 12)
            tris.append((base + a, base + bb, base + c))
        o += oend
    return pts, tris, mn, mx


def panel(draw, ox, oy, size, pts, tris, mn, mx, ax, ay, colour, scale, centre):
    def P(p):
        return (ox + size / 2 + (p[ax] - centre[ax]) * scale,
                oy + size / 2 - (p[ay] - centre[ay]) * scale)
    for a, b, c in tris:
        pa, pb, pc = P(pts[a]), P(pts[b]), P(pts[c])
        draw.line([pa, pb, pc, pa], fill=colour, width=1)
    # header bounds
    bx0, by0 = P((mn[0], mn[1], mn[2]))
    bx1, by1 = P((mx[0], mx[1], mx[2]))
    draw.rectangle([min(bx0, bx1), min(by0, by1), max(bx0, bx1), max(by0, by1)], outline=(220, 40, 40), width=1)
    # origin axes
    o = P((0, 0, 0))
    draw.line([(ox, o[1]), (ox + size, o[1])], fill=(150, 150, 150), width=1)
    draw.line([(o[0], oy), (o[0], oy + size)], fill=(150, 150, 150), width=1)
    draw.ellipse([o[0] - 4, o[1] - 4, o[0] + 4, o[1] + 4], outline=(0, 160, 0), width=2)


def main():
    a = sys.argv[1:]
    path, out = a[0], a[1]
    f1 = int(a[a.index("--frame") + 1]) if "--frame" in a else 0
    f2 = int(a[a.index("--frame2") + 1]) if "--frame2" in a else None

    pts, tris, mn, mx = load(path, f1)
    ext = max(max(abs(v) for v in p) for p in pts) * 1.15 + 5
    size = 380
    scale = (size / 2) / ext
    centre = (0.0, 0.0, 0.0)          # keep the ORIGIN at panel centre on purpose

    img = Image.new("RGB", (size * 3 + 40, size + 60), (255, 255, 255))
    d = ImageDraw.Draw(img)
    views = [("TOP  x->  y^", 0, 1), ("SIDE  x->  z^", 0, 2), ("FRONT  y->  z^", 1, 2)]
    for i, (label, ax, ay) in enumerate(views):
        ox = 10 + i * (size + 10)
        d.rectangle([ox, 30, ox + size, 30 + size], outline=(0, 0, 0))
        d.text((ox + 4, 8), label, fill=(0, 0, 0))
        panel(d, ox, 30, size, pts, tris, mn, mx, ax, ay, (30, 30, 30), scale, centre)
        if f2 is not None:
            p2, t2, mn2, mx2 = load(path, f2)
            panel(d, ox, 30, size, p2, t2, mn2, mx2, ax, ay, (60, 90, 230), scale, centre)
    d.text((10, size + 40), "%s  frame %d%s   red = header bounds   green ring = origin   scale %.2f px/unit"
           % (path.replace("\\", "/").split("/")[-1], f1, ("  + frame %d in blue" % f2) if f2 is not None else "", scale),
           fill=(0, 0, 0))
    img.save(out)
    inside = all(mn[k] - 0.05 <= p[k] <= mx[k] + 0.05 for p in pts for k in range(3))
    print("wrote %s   verts %d tris %d   mesh inside header bounds: %s" % (out, len(pts), len(tris), "YES" if inside else "NO"))


if __name__ == "__main__":
    main()
