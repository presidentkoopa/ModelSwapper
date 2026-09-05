"""Which frames of each donor mesh the clip table actually uses.

The chaingun was the case that prompted this: its mesh carries 16 frames
and its clips referenced two of them, because the source modeldef it was
transcribed from was written for vanilla Doom's two-frame chaingun
psprite. Faithful to the source, and nearly empty on a mod with a real
animation.

That is not visible by reading either file alone -- you have to hold the
mesh and the clip table up against each other. So:

  COVERAGE   how many of the mesh's frames any clip names
  CLIPS      which animations exist, and which standard ones do not
  DEAD       frames the mesh has that nothing plays
  BROKEN     frames whose geometry is degenerate, so they must not be used

Run it after adding a donor or editing clips. It reports, never edits.
"""
import io, os, re, sys, math

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tools_md3_pitch import read_md3, principal_pitch

R = os.path.dirname(os.path.abspath(__file__))

# Clips a fully-authored donor would have. Not every weapon earns all of
# them -- a chainsaw has no reload and a fist has no ads -- so a missing
# one is a question, not a verdict.
STANDARD = ["ready", "fire", "altfire", "reload", "select", "sprint", "ads"]

# A frame is degenerate when its verts sprawl far beyond the model's real
# extent. Every set has a few: an unbuilt bind pose left in the export.
#
# MEASURED AT THE MEDIAN VERTEX, and it took three tries to get here.
# Max condemned a frame for one stray vertex, which flagged twenty donors
# whose frame 0 merely parks a collapsed surface at the origin -- a casing,
# a shell -- while the gun renders perfectly. The 95th percentile was no
# better: a collapsed surface of 37 verts in a 800-vert pistol IS the top
# 5%, so it sat exactly on the boundary and still fired.
#
# The median cannot be moved by any minority of the geometry. A frame is
# only unusable when MOST of it has left the model, which is what actually
# happened to the Beretta's frame 0 and what "degenerate" should mean. The
# pickup fitter already reports collapsed surfaces separately and ignores
# them; this must not duplicate that with a worse test.
BROKEN_RATIO = 4.0
BROKEN_PCTL  = 0.50


def mesh_paths():
    out, cur, path = {}, None, None
    for ln in io.open(os.path.join(R, "modeldef"), encoding="utf-8"):
        m = re.match(r"^Model\s+(\S+)", ln)
        if m:
            cur, path = m.group(1), None
            continue
        m = re.match(r'^\s*Path\s+"([^"]+)"', ln)
        if m:
            path = m.group(1)
            continue
        m = re.match(r'^\s*Model\s+0\s+"([^"]+)"', ln)
        if m and cur and path and cur not in out:
            out[cur] = os.path.join(R, path.replace("/", os.sep), m.group(1))
    return out


def shelf_rest():
    src = io.open(os.path.join(R, "zscript", "RS_ForeignModels.zs"), encoding="utf-8").read()
    return {m.group(2): int(m.group(5)) for m in
            re.finditer(r'"(\w+)\|(MS_\w+)\|(\w+)\|(-?\d+)\|(-?\d+)\|(-?\d+)"', src)}


def frames_of(spec):
    out = []
    for part in spec.split(","):
        part = part.split("@")[0]
        if "-" in part:
            a, b = part.split("-")
            out += list(range(int(a), int(b) + 1))
        elif part:
            out.append(int(part))
    return out


def clip_table():
    src = io.open(os.path.join(R, "zscript", "RS_ForeignAnim.zs"), encoding="utf-8").read()
    out = {}
    for m in re.finditer(r'"(MS_\w+)\|(\w+)\|([0-9,@\-]+)\|', src):
        out.setdefault(m.group(1), {})[m.group(2)] = frames_of(m.group(3))
    return out


mesh, rest, clips = mesh_paths(), shelf_rest(), clip_table()

rows = []
for donor in sorted(set(clips) | set(rest)):
    p = mesh.get(donor)
    if not p or not os.path.exists(p):
        continue
    frames = read_md3(p)
    n = len(frames)

    lens = []
    for f in frames:
        cx = sum(q[0] for q in f) / len(f)
        cy = sum(q[1] for q in f) / len(f)
        cz = sum(q[2] for q in f) / len(f)
        d = sorted(math.dist(q, (cx, cy, cz)) for q in f)
        lens.append(d[int(len(d) * BROKEN_PCTL)])
    med = sorted(lens)[len(lens) // 2] or 1.0
    broken = [i for i, L in enumerate(lens) if L > med * BROKEN_RATIO]

    # DUPLICATE FRAMES ARE NOT MISSED FRAMES.
    #
    # Raw coverage lies. The BFG stores its idle pose six times over
    # (frames 6-11) and the Jackhammer stores its idle six times and every
    # stroke pose twice; a clip naming one of each has lost nothing, but
    # counted raw it reads as 44% and looks like neglect. What matters is
    # how many DISTINCT poses the mesh holds and how many of those any clip
    # reaches.
    groups = []
    for i, f in enumerate(frames):
        for g in groups:
            j = g[0]
            if sum(math.dist(p2, q) for p2, q in zip(f, frames[j])) / len(f) < 0.05:
                g.append(i)
                break
        else:
            groups.append([i])
    poses = len(groups)

    used = set()
    for fr in clips.get(donor, {}).values():
        used.update(f for f in fr if f < n)
    used.add(rest.get(donor, 0))

    reached = sum(1 for g in groups if any(x in used for x in g))
    dead = [i for i in range(n) if i not in used and i not in broken
            and not any(x in used for g in groups if i in g for x in g)]
    missing = [c for c in STANDARD if c not in clips.get(donor, {})]
    used_broken = sorted(used & set(broken))

    rows.append((donor, poses, reached, dead, missing, used_broken))

rows.sort(key=lambda r: r[2] / max(1, r[1]))

print("%-24s %-11s %-8s %s" % ("DONOR", "POSES SEEN", "COVER", "MISSING CLIPS"))
for donor, n, u, dead, missing, ub in rows:
    pct = 100.0 * u / max(1, n)
    flag = "  <-- thin" if pct < 40 and n >= 8 else ""
    print("%-24s %2d/%-8d %5.0f%%   %s%s" % (donor, u, n, pct, ",".join(missing) or "-", flag))

print()
for donor, n, u, dead, missing, ub in rows:
    if ub:
        print("BROKEN  %-22s clips use degenerate frame(s): %s" %
              (donor, ",".join(str(x) for x in ub)))
for donor, n, u, dead, missing, ub in rows:
    if len(dead) >= 5:
        rng = "%d-%d" % (dead[0], dead[-1]) if dead == list(range(dead[0], dead[-1] + 1)) else ",".join(str(x) for x in dead[:12])
        print("DEAD    %-22s %2d frames nothing plays: %s" % (donor, len(dead), rng))
