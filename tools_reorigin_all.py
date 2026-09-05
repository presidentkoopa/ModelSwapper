"""Re-origin every HUD donor mesh and compensate every modeldef block.

    python tools_reorigin_all.py --report             # what would change
    python tools_reorigin_all.py --apply              # do it
    python tools_reorigin_all.py --apply --only MS_X  # one donor
    python tools_reorigin_all.py --apply --known MS_Pistol 22.84375 0.109375 -3.09375

Per MESH (each file shifted exactly once, however many blocks use it):
  1. rest frame = the shelf's rest frame for the first donor using it
  2. tools_md3_reorigin moves the rest centroid to 0,0,0 and verifies
  3. before/after renders go to renders/<mesh>_{before,after}.png

Per HUD BLOCK using that mesh:
  4. its Scale / Offset / ZOffset / AngleOffset / PitchOffset / RollOffset are
     read, the compensating Offset computed by tools_md3_compensate's replica
     of the engine matrix, and the block rewritten with ONE unified
     `Offset x y z` line -- any ZOffset line is removed, because the engine
     takes whichever of Offset.z / ZOffset came last and that ambiguity is
     exactly the kind of thing being unified away.
  5. the block is stamped `// origin: centred` so a re-run cannot compensate
     it twice. --known supplies the shift for a mesh already centred by hand
     (the pistol, done first as the proof) whose blocks are still unstamped.

MS_PU_ blocks are NOT touched: tools_gen_pickups.ps1 regenerates them from
the mesh, and must be run once after this.
"""
import io, os, re, sys, subprocess

R = os.path.dirname(os.path.abspath(__file__))
STAMP = "// origin: centred by tools_reorigin_all.py -- Offset compensates the mesh shift"
sys.path.insert(0, R)
from tools_md3_compensate import compensate

args = sys.argv[1:]
APPLY = "--apply" in args
ONLY = args[args.index("--only") + 1] if "--only" in args else None
KNOWN = {}
if "--known" in args:
    i = args.index("--known")
    KNOWN[args[i + 1]] = tuple(float(args[i + k]) for k in (2, 3, 4))

md = io.open(os.path.join(R, "modeldef"), encoding="utf-8").read()
shelf = {m.group(2): int(m.group(5)) for m in re.finditer(
    r'"(\w+)\|(MS_\w+)\|(\w+)\|(-?\d+)\|(-?\d+)\|(-?\d+)"',
    io.open(os.path.join(R, "zscript", "RS_ForeignModels.zs"), encoding="utf-8").read())}

# ---- parse HUD blocks --------------------------------------------------
blocks = []   # (name, start, end, text)
for m in re.finditer(r"^Model (MS_\w+)\n\{\n(.*?)^\}\n", md, re.S | re.M):
    name = m.group(1)
    if name.startswith("MS_PU_"): continue
    blocks.append((name, m.start(), m.end(), m.group(0)))


def field(text, key, n):
    m = re.search(r"^\t%s\s+(.+)$" % key, text, re.M)
    if not m: return None
    v = m.group(1).split()
    return tuple(float(x) for x in v[:n]) if n > 1 else float(v[0])


def mesh_of(text):
    p = re.search(r'^\tPath\s+"([^"]+)"', text, re.M).group(1)
    f = re.search(r'^\tModel 0\s+"([^"]+)"', text, re.M).group(1)
    return os.path.join(R, p.replace("/", os.sep), f)


by_mesh = {}
for name, s, e, text in blocks:
    by_mesh.setdefault(mesh_of(text), []).append((name, s, e, text))

outdir = os.path.join(R, "renders"); os.makedirs(outdir, exist_ok=True)
edits = []   # (start, end, newtext)

for mesh, users in by_mesh.items():
    names = [u[0] for u in users]
    if ONLY and ONLY not in names: continue
    first = names[0]
    rest = shelf.get(first, 0)
    tag = os.path.splitext(os.path.basename(mesh))[0] + "_" + os.path.basename(os.path.dirname(mesh))

    stamped = [u for u in users if STAMP in u[3]]
    if len(stamped) == len(users):
        print("%-22s already done" % first); continue

    # ---- the mesh --------------------------------------------------------
    if first in KNOWN:
        shift = KNOWN[first]
        print("%-22s mesh already centred; using known shift %s" % (first, shift))
    else:
        rep = subprocess.run([sys.executable, os.path.join(R, "tools_md3_reorigin.py"), mesh, "--rest", str(rest)],
                             capture_output=True, text=True).stdout
        m = re.search(r"shift applied \(grid\)\s+([-+0-9.]+)\s+([-+0-9.]+)\s+([-+0-9.]+)", rep)
        shift = tuple(float(x) for x in m.groups())
        if max(abs(x) for x in shift) < 1.0 / 64:
            print("%-22s mesh already centred, blocks unstamped -- pass --known" % first); continue
        print("%-22s rest %-3d shift %+8.3f %+8.3f %+8.3f  users %s" % (first, rest, *shift, ",".join(names)))
        if APPLY:
            subprocess.run([sys.executable, os.path.join(R, "tools_md3_render.py"), mesh,
                            os.path.join(outdir, tag + "_before.png"), "--frame", str(rest)], check=True)
            res = subprocess.run([sys.executable, os.path.join(R, "tools_md3_reorigin.py"), mesh, "--rest", str(rest), "--apply"],
                                 capture_output=True, text=True)
            # GATE ON THE EXIT CODE, not on a word in the text. The first
            # run of this looked only for "FAIL" and sailed past eight
            # meshes whose verify line read "bounds no longer contain their
            # verts: 1" -- a real failure, spelled without the magic word.
            # Those turned out to be pre-existing sloppy exporter bounds,
            # but the gate had no way of knowing that.
            if res.returncode != 0 or "ABORT" in res.stdout:
                print(res.stdout); print("STOPPING on %s" % first); sys.exit(1)
            subprocess.run([sys.executable, os.path.join(R, "tools_md3_render.py"), mesh,
                            os.path.join(outdir, tag + "_after.png"), "--frame", str(rest)], check=True)

    # ---- every block on that mesh ----------------------------------------
    for name, s, e, text in users:
        if STAMP in text: continue
        scale = field(text, "Scale", 3) or (1.0, 1.0, 1.0)
        off = list(field(text, "Offset", 3) or (0.0, 0.0, 0.0))
        zo = field(text, "ZOffset", 1)
        if zo is not None: off[2] = zo          # engine: last one wins; ours is always after Offset
        ang = field(text, "AngleOffset", 1) or 0.0
        pit = field(text, "PitchOffset", 1) or 0.0
        rol = field(text, "RollOffset", 1) or 0.0
        new, _ = compensate(shift, scale, tuple(off), ang, pit, rol)
        print("    %-22s Scale %s  Offset %s -> %.3f %.3f %.3f" % (
            name, " ".join("%g" % x for x in scale), " ".join("%g" % x for x in off), *new))

        t = re.sub(r"^\tZOffset\s+.+\n", "", text, flags=re.M)
        line = "\tOffset %.3f %.3f %.3f\n" % new
        if re.search(r"^\tOffset\s+.+\n", t, re.M):
            t = re.sub(r"^\tOffset\s+.+\n", line, t, count=1, flags=re.M)
        else:
            t = re.sub(r"(^\tScale\s+.+\n)", r"\1" + line, t, count=1, flags=re.M) if "\tScale" in t \
                else re.sub(r'(^\tSkin 0\s+.+\n)', r"\1" + line, t, count=1, flags=re.M)
        t = t.replace("\n{\n", "\n{\n\t" + STAMP + "\n", 1)
        edits.append((s, e, t))

if APPLY and edits:
    for s, e, t in sorted(edits, reverse=True):
        md = md[:s] + t + md[e:]
    io.open(os.path.join(R, "modeldef"), "w", encoding="utf-8", newline="\n").write(md)
    print("\nmodeldef: %d blocks rewritten. Renders in %s. Now run tools_gen_pickups.ps1 and build." % (len(edits), outdir))
elif not APPLY:
    print("\n(report only)")
