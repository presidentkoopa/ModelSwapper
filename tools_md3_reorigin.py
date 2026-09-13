"""Move an MD3's origin onto the mesh, in place, touching nothing else.

    python tools_md3_reorigin.py MESH.md3 --rest N            # report only
    python tools_md3_reorigin.py MESH.md3 --rest N --apply    # write

WHAT IT DOES. Computes the centroid of every vertex at the rest frame --
skipping any surface collapsed onto a single point, which renders as
nothing (see visible_verts_at) -- rounds it to the MD3 grid (1/64 unit -- so the shift is exact and no
vertex moves by a rounding error), and subtracts it from:

  - every vertex of every surface at every frame   (int16 xyz, /64)
  - every frame's minBounds, maxBounds, localOrigin (float)
  - every tag's origin                             (float)

Radius is untouched: it is measured from localOrigin, and both moved.
Normals, triangles, texcoords, shaders and every header field are not
written at all -- the file is patched as a bytearray, so a byte-compare
against the original shows exactly and only the fields above changed.

WHY THE REST FRAME. A gun's centroid moves when its slide cycles or its
magazine drops. The pose that has to sit in the hand is the rest pose,
so that is the one whose centre goes to 0,0,0. Other frames keep their
motion relative to it, which is the point.

THE VERIFY STEP re-reads the written file and asserts the rest centroid
is within one grid step of zero, that every frame's bounds still contain
its vertices, and that the untouched byte ranges are identical to the
input. Prints the shift so the modeldef can be compensated.
"""
import struct, sys, os, math

GRID = 64.0


def read_all(b):
    nf, nt, ns, nsk, of, ot, osf, oe = struct.unpack_from("<8i", b, 76)
    surfs = []
    o = osf
    for _ in range(ns):
        nfr, nsh, nv, ntri, otri, osh, ost, oxyz, oend = struct.unpack_from("<9i", b, o + 72)
        surfs.append(dict(base=o, nv=nv, nfr=nfr, oxyz=oxyz, oend=oend,
                          name=b[o + 4:o + 68].split(b"\0")[0].decode("latin1")))
        o += oend
    return dict(nf=nf, nt=nt, ns=ns, of=of, ot=ot, osf=osf, oe=oe, surfs=surfs)


def verts_at(b, h, frame):
    pts = []
    for s in h["surfs"]:
        base = s["base"] + s["oxyz"] + frame * s["nv"] * 8
        for v in range(s["nv"]):
            x, y, z = struct.unpack_from("<hhh", b, base + v * 8)
            pts.append((x / GRID, y / GRID, z / GRID))
    return pts


def centroid(pts):
    n = float(len(pts))
    return (sum(p[0] for p in pts) / n, sum(p[1] for p in pts) / n, sum(p[2] for p in pts) / n)


# A surface whose vertices all sit within this of their own centre is parked,
# not geometry.
COLLAPSED = 0.5


def visible_verts_at(b, h, frame):
    """The vertices that are actually geometry at `frame`, and what was skipped.

    Modellers hide an unused sub-mesh by welding every vertex of it onto one
    point. It draws nothing, but it still counts in an average. VanAlek's fist
    carries a whole duplicate glove collapsed to a point -- half the mesh's
    vertices -- and centring on every vertex left the visible hand 16 units
    off the origin; the revolver was 24 off, the super shotgun 4. So collapsed
    surfaces are skipped. If every surface is collapsed, all vertices are used.
    """
    keep, ignored = [], []
    for s in h["surfs"]:
        base = s["base"] + s["oxyz"] + frame * s["nv"] * 8
        pts = [tuple(c / GRID for c in struct.unpack_from("<hhh", b, base + v * 8)) for v in range(s["nv"])]
        if not pts:
            continue
        c = centroid(pts)
        if max(math.dist(p, c) for p in pts) < COLLAPSED:
            ignored.append((s["name"], len(pts)))
        else:
            keep.extend(pts)
    return (keep if keep else verts_at(b, h, frame)), ignored


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__); return 2
    path = args[0]
    rest = int(args[args.index("--rest") + 1]) if "--rest" in args else 0
    apply = "--apply" in args

    src = open(path, "rb").read()
    b = bytearray(src)
    h = read_all(b)
    assert b[:4] == b"IDP3", "not an MD3"
    assert 0 <= rest < h["nf"], "rest frame out of range"

    vis, ignored = visible_verts_at(b, h, rest)
    c = centroid(vis)
    # Snap to the vertex grid so subtraction is exact in int16.
    ci = tuple(int(round(x * GRID)) for x in c)
    cf = tuple(x / GRID for x in ci)
    print("%-40s frames %d tags %d surfaces %d" % (os.path.basename(path), h["nf"], h["nt"], h["ns"]))
    for name, n in ignored:
        print("ignored collapsed surface %-24s %d verts, parked on one point" % (name, n))
    print("rest frame %d centroid  %+8.3f %+8.3f %+8.3f" % (rest, c[0], c[1], c[2]))
    print("shift applied (grid)    %+8.3f %+8.3f %+8.3f" % cf)

    # Range check before touching anything.
    lo = hi = None
    for f in range(h["nf"]):
        for s in h["surfs"]:
            base = s["base"] + s["oxyz"] + f * s["nv"] * 8
            for v in range(s["nv"]):
                x, y, z = struct.unpack_from("<hhh", b, base + v * 8)
                for val in (x - ci[0], y - ci[1], z - ci[2]):
                    if not -32768 <= val <= 32767:
                        print("ABORT: vertex leaves int16 range after shift"); return 1

    if not apply:
        print("(report only -- pass --apply to write)")
        return 0

    # 1. vertices
    for f in range(h["nf"]):
        for s in h["surfs"]:
            base = s["base"] + s["oxyz"] + f * s["nv"] * 8
            for v in range(s["nv"]):
                p = base + v * 8
                x, y, z = struct.unpack_from("<hhh", b, p)
                struct.pack_into("<hhh", b, p, x - ci[0], y - ci[1], z - ci[2])

    # 2. frame headers: min, max, localOrigin. radius untouched.
    for f in range(h["nf"]):
        o = h["of"] + f * 56
        for k in range(3):
            for fld in (0, 12, 24):
                val = struct.unpack_from("<f", b, o + fld + k * 4)[0]
                struct.pack_into("<f", b, o + fld + k * 4, val - cf[k])

    # 3. tag origins (112 bytes each: name 64, origin 12, axis 36)
    for t in range(h["nt"]):
        o = h["ot"] + t * 112 + 64
        for k in range(3):
            val = struct.unpack_from("<f", b, o + k * 4)[0]
            struct.pack_into("<f", b, o + k * 4, val - cf[k])

    open(path, "wb").write(bytes(b))

    # ---- VERIFY against the file actually on disk ------------------------
    b2 = open(path, "rb").read()
    h2 = read_all(b2)
    c2 = centroid(visible_verts_at(b2, h2, rest)[0])
    ok = all(abs(x) <= 1.0 / GRID + 1e-6 for x in c2)
    print("verify: rest centroid   %+8.3f %+8.3f %+8.3f  %s" % (c2[0], c2[1], c2[2], "OK" if ok else "FAIL"))

    # bounds still contain their vertices
    bad = 0
    for f in range(h2["nf"]):
        o = h2["of"] + f * 56
        mn = struct.unpack_from("<3f", b2, o); mx = struct.unpack_from("<3f", b2, o + 12)
        for p in verts_at(b2, h2, f):
            if any(p[k] < mn[k] - 0.02 or p[k] > mx[k] + 0.02 for k in range(3)):
                bad += 1; break
    print("verify: frames whose bounds no longer contain their verts: %d" % bad)

    # untouched ranges byte-identical
    touched = set()
    for f in range(h["nf"]):
        o = h["of"] + f * 56
        touched.update(range(o, o + 36))
        for s in h["surfs"]:
            base = s["base"] + s["oxyz"] + f * s["nv"] * 8
            for v in range(s["nv"]):
                touched.update(range(base + v * 8, base + v * 8 + 6))
    for t in range(h["nt"]):
        o = h["ot"] + t * 112 + 64
        touched.update(range(o, o + 12))
    diff = sum(1 for i in range(len(src)) if src[i] != b2[i] and i not in touched)
    print("verify: bytes changed outside vertex/bounds/tag fields: %d  %s" % (diff, "OK" if diff == 0 else "FAIL"))
    print("SHIFT %+.6f %+.6f %+.6f" % cf)
    return 0 if ok and bad == 0 and diff == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
