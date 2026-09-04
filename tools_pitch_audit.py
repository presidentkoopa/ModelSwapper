"""Audit every donor's SELECT and SPRINT clips for frames that point the
gun somewhere the player's hand is not.

The reference is each model's OWN rest frame, not level -- some meshes are
authored a few degrees nose-down and that is how they are meant to sit.
What matters is a clip frame that departs from the rest pose far enough to
read as the gun swinging on its own.
"""
import io, re, os, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tools_md3_pitch import read_md3, principal_pitch

# Follow the repo rather than a path baked in when this was written --
# the tree moved once already and this silently pointed at the old one.
R = os.path.dirname(os.path.abspath(__file__))
TOL = 12.0          # degrees away from the rest pose before it reads as a swing

# ---- donor -> mesh path, from MODELDEF -------------------------------
mesh = {}
cur = None; path = None
for ln in io.open(R + r"\modeldef", encoding="utf-8"):
    m = re.match(r'^Model\s+(\S+)', ln)
    if m: cur = m.group(1); path = None; continue
    m = re.match(r'^\s*Path\s+"([^"]+)"', ln)
    if m: path = m.group(1); continue
    m = re.match(r'^\s*Model\s+0\s+"([^"]+)"', ln)
    if m and cur and path and cur not in mesh:
        mesh[cur] = os.path.join(R, path.replace("/", os.sep), m.group(1))

# ---- donor -> rest frame, from the shelf -----------------------------
rest = {}
for m in re.finditer(r'"(\w+)\|(MS_\w+)\|(\w+)\|(-?\d+)\|(-?\d+)\|(-?\d+)"',
                     io.open(R + r"\zscript\RS_ForeignModels.zs", encoding="utf-8").read()):
    rest[m.group(2)] = int(m.group(5))

# ---- clip rows -------------------------------------------------------
def frames_of(spec):
    out = []
    for part in spec.split(","):
        part = part.split("@")[0]
        if "-" in part:
            a, b = part.split("-"); out += list(range(int(a), int(b) + 1))
        elif part:
            out.append(int(part))
    return out

clips = {}
for m in re.finditer(r'"(MS_\w+)\|(\w+)\|([0-9,@\-]+)\|',
                     io.open(R + r"\zscript\RS_ForeignAnim.zs", encoding="utf-8").read()):
    clips.setdefault(m.group(1), {})[m.group(2)] = frames_of(m.group(3))

# ---- measure ---------------------------------------------------------
cache = {}
def pitches(donor):
    if donor in cache: return cache[donor]
    p = mesh.get(donor)
    if not p or not os.path.exists(p):
        cache[donor] = None; return None
    out = [principal_pitch(f)[0] for f in read_md3(p)]
    cache[donor] = out
    return out

print("%-24s %-6s %-8s %s" % ("DONOR", "REST", "RESTPITCH", "SELECT / SPRINT frames (pitch)"))
bad = []
for donor in sorted(clips):
    ps = pitches(donor)
    if ps is None: continue
    rf = rest.get(donor, 0)
    if rf >= len(ps): continue
    rp = ps[rf]
    notes = []
    for clip in ("select", "sprint"):
        fr = clips[donor].get(clip)
        if not fr: continue
        shown = []
        worst = 0.0
        for f in fr:
            if f >= len(ps): continue
            d = ps[f] - rp
            shown.append("%d:%+.0f" % (f, d))
            worst = max(worst, abs(d))
        if worst > TOL:
            notes.append("%s[%s]" % (clip, " ".join(shown)))
            bad.append((donor, clip, fr, worst, rf, rp, ps))
    if notes:
        print("%-24s %-6d %+8.1f  %s" % (donor, rf, rp, "  ".join(notes)))

print()
print("%d donor/clip pairs swing more than %.0f deg off their own rest pose."
      % (len(bad), TOL))
