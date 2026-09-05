"""Full per-donor inventory: mesh, frames, poses, clips, pitch.

tools_clip_audit answers "is anything neglected". This answers "what IS
this model" -- one block per donor listing every distinct pose, which
frames share it, what pitch it sits at, and which clip plays it.

Writes Markdown to stdout. Redirect it into the docs folder:

    python tools_model_inventory.py > "E:/DOOMWork/Engine docs/MODEL_INVENTORY.md"
"""
import io, os, re, sys, math

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tools_md3_pitch import read_md3, principal_pitch

R = os.path.dirname(os.path.abspath(__file__))
SAME = 0.05          # mean vertex delta below which two frames are one pose


def meshes():
    out, cur, path, skin = {}, None, None, None
    for ln in io.open(os.path.join(R, "modeldef"), encoding="utf-8"):
        m = re.match(r"^Model\s+(\S+)", ln)
        if m:
            cur, path, skin = m.group(1), None, None
            continue
        m = re.match(r'^\s*Path\s+"([^"]+)"', ln)
        if m:
            path = m.group(1); continue
        # Skin 0 is written AFTER Model 0 in these blocks, so the entry is
        # recorded on Model 0 and the skin patched in when it turns up.
        m = re.match(r'^\s*Skin\s+0\s+"([^"]+)"', ln)
        if m and cur in out and out[cur][2] == "-":
            out[cur] = (out[cur][0], out[cur][1], m.group(1))
            continue
        m = re.match(r'^\s*Model\s+0\s+"([^"]+)"', ln)
        if m and cur and path and cur not in out:
            out[cur] = (os.path.join(R, path.replace("/", os.sep), m.group(1)),
                        m.group(1), "-")
    return out


def geometry():
    """Scale / Offset / ZOffset per donor, straight from the modeldef."""
    out, cur, g = {}, None, {}
    for ln in io.open(os.path.join(R, "modeldef"), encoding="utf-8"):
        m = re.match(r"^Model\s+(\S+)", ln)
        if m:
            if cur and cur not in out:
                out[cur] = (g.get("s", "1 1 1"), g.get("o", "0 0 0"), g.get("z", "0"))
            cur, g = m.group(1), {}
            continue
        m = re.match(r"^\s*Scale\s+(.+)", ln)
        if m: g["s"] = m.group(1).strip(); continue
        m = re.match(r"^\s*Offset\s+(.+)", ln)
        if m: g["o"] = m.group(1).strip(); continue
        m = re.match(r"^\s*ZOffset\s+(.+)", ln)
        if m: g["z"] = m.group(1).strip(); continue
    if cur and cur not in out:
        out[cur] = (g.get("s", "1 1 1"), g.get("o", "0 0 0"), g.get("z", "0"))
    return out


def shelf():
    src = io.open(os.path.join(R, "zscript", "RS_ForeignModels.zs"), encoding="utf-8").read()
    fam, rest = {}, {}
    for m in re.finditer(r'"(\w+)\|(MS_\w+)\|(\w+)\|(-?\d+)\|(-?\d+)\|(-?\d+)"', src):
        fam.setdefault(m.group(2), []).append(m.group(1))
        rest[m.group(2)] = int(m.group(5))
    return fam, rest


def spec_frames(spec):
    out = []
    for part in spec.split(","):
        part = part.split("@")[0]
        if "-" in part:
            a, b = part.split("-"); out += list(range(int(a), int(b) + 1))
        elif part:
            out.append(int(part))
    return out


def clips():
    src = io.open(os.path.join(R, "zscript", "RS_ForeignAnim.zs"), encoding="utf-8").read()
    out = {}
    for m in re.finditer(r'"(MS_\w+)\|(\w+)\|([0-9,@\-]+)\|', src):
        out.setdefault(m.group(1), {})[m.group(2)] = spec_frames(m.group(3))
    return out


def runs(nums):
    """[1,2,3,7,8] -> '1-3,7-8'"""
    nums = sorted(nums)
    if not nums: return "-"
    out, a, b = [], nums[0], nums[0]
    for x in nums[1:]:
        if x == b + 1: b = x
        else:
            out.append(str(a) if a == b else "%d-%d" % (a, b)); a = b = x
    out.append(str(a) if a == b else "%d-%d" % (a, b))
    return ",".join(out)


MESH, (FAM, REST), CLIP, GEOM = meshes(), shelf(), clips(), geometry()

print("# Model inventory")
print()
print("Every donor mesh, pose by pose. Generated -- do not hand-edit:")
print()
print("```bash")
print('python tools_model_inventory.py > "E:/DOOMWork/Engine docs/MODEL_INVENTORY.md"')
print("```")
print()
print("**Poses, not frames.** Meshes store the same pose repeatedly -- the BFG")
print("holds its idle six times over. Frames sharing a pose are grouped, so a")
print("clip naming one of them has lost nothing. Pitch is the dominant axis")
print("against horizontal; compare each to the model's own REST row, not to")
print("zero, because plenty of weapons are authored nose-down or held high.")
print()

for donor in sorted(MESH):
    if donor.startswith("MS_PU_"): continue
    path, mfile, skin = MESH[donor]
    if not os.path.exists(path): continue
    frames = read_md3(path)
    n = len(frames)

    groups = []
    for i, f in enumerate(frames):
        for g in groups:
            if sum(math.dist(p, q) for p, q in zip(f, frames[g[0]])) / len(f) < SAME:
                g.append(i); break
        else:
            groups.append([i])

    byframe = {}
    for name, fr in CLIP.get(donor, {}).items():
        for x in fr:
            byframe.setdefault(x, []).append(name)

    rest = REST.get(donor, 0)
    fams = "/".join(sorted(set(FAM.get(donor, ["-"]))))
    kb = os.path.getsize(path) // 1024

    print("## `%s`" % donor)
    print()
    sc, of, zo = GEOM.get(donor, ("?", "?", "?"))

    # WHERE THE MESH SITS RELATIVE TO ITS OWN ORIGIN, at the rest pose.
    # A model authored around 0,0,0 has a small centroid; one exported
    # with the origin left at the world origin of whatever scene it came
    # from can be tens of units out, and every Offset in the modeldef is
    # then compensating for that rather than positioning the gun.
    rf = frames[rest] if rest < n else frames[0]
    cx = sum(q[0] for q in rf) / len(rf)
    cy = sum(q[1] for q in rf) / len(rf)
    cz = sum(q[2] for q in rf) / len(rf)
    ext = max(math.dist(q, (cx, cy, cz)) for q in rf)

    print("{} &middot; `{}` {} KB &middot; skin `{}` &middot; **{} frames, {} poses** &middot; rest frame **{}**".format(
        fams, mfile, kb, skin, n, len(groups), rest))
    print()
    print("Scale `{}` &middot; Offset `{}` &middot; ZOffset `{}` &middot; "
          "centroid `{:+.1f},{:+.1f},{:+.1f}` &middot; extent `{:.0f}`".format(
              sc, of, zo, cx, cy, cz, ext))
    print()
    print("| pose | frames | pitch | plays |")
    print("| --- | --- | --- | --- |")
    for g in groups:
        p, _ = principal_pitch(frames[g[0]])
        names = sorted({c for x in g for c in byframe.get(x, [])})
        mark = " **REST**" if rest in g else ""
        print("| %d | `%s` | %+.1f&deg; | %s%s |"
              % (groups.index(g) + 1, runs(g), p, ", ".join(names) or "&mdash;", mark))
    print()
