"""Build a patch that lets ModelSwapper's Quest build load in Selaco.

    python tools_make_selaco_patch.py [ModelSwapper-QUEST.pk3] [output.pk3] [Selaco.ipk3]

Load order: Selaco, then ModelSwapper-QUEST.pk3, then this patch.

WHY. Selaco runs on its own GZDoom 4.12 engine, and that engine renamed the
Weapon base class to WeaponBase. ZScript resolves class names when it
compiles, so every place ModelSwapper names Weapon is a load failure there
("Unable to resolve weapon as a type"). Selaco is also not a VR engine: it
has no off hand (OffhandWeapon, PSP_OFFHANDWEAPON) and no controller aim
(AttackPos and friends), which the Quest build reads.

WHAT IT CHANGES. Copies of ModelSwapper's own script files, with:
  - the class Weapon, as a type or as a class-name literal, spelled WeaponBase
  - the off hand read as always empty, and its sprite layer as a layer
    nothing uses
  - the effect relocator told there is no controller aim, so it stands down
    (on a flat screen the gun is drawn at the eye, where effects already are)
  - the menu's which-archive-is-this lookup spelled the way this older engine
    spells it (GetLumpWadNum and GetWadName)
  - the names of Heretic, Hexen and Strife weapon classes, which Selaco does
    not ship, replaced by a class no weapon descends from
And additions:
  - Selaco's own weapon pickup meshes as models (modeldef.selaco), each
    first in its families, pointed at where Selaco.ipk3 already has them
  - one never-spawned actor that makes our MODELDEF's sprite names known
  - our wireframe render of each Selaco gun (renders/, and renders/selaco/
    in the repo), for anyone who wants to look
Only script files that needed a change are in the patch.

HOW IT WORKS. ModelSwapper's zscript.txt includes each script by full path,
and the engine resolves an #include to the last loaded file with that path.
The patch carries those paths, so loaded after ModelSwapper it replaces
them. Its own zscript.txt only declares classes and includes nothing.
Nothing of Selaco's is copied or edited: this is ModelSwapper's code,
rewritten from the pk3 you load, plus names of files Selaco already loads.

Every edit must match an exact number of times, and the result is checked
for any surviving VR-only or Weapon name, so a changed ModelSwapper fails
here loudly instead of producing a patch that half-loads.
"""
import os
import re
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_SRC = os.path.join(HERE, "ModelSwapper-QUEST.pk3")
DEFAULT_OUT = os.path.join(HERE, "ModelSwapper-Selaco-Patch.pk3")

# A sprite layer id no engine or mod uses: comparisons against it never match.
NO_LAYER = "0x7FFFFFF0"

# (file, pattern on code, replacement, exact count). Patterns only ever see
# code: comments, strings and names are cut out first and handled below.
CODE_EDITS = [
    ("zscript/RS_ForeignModels.zs", r"\b\w+\.OffhandWeapon\b", "WeaponBase(null)", 6),
    ("zscript/RS_ForeignModels.zs", r"\bPSP_OFFHANDWEAPON\b", NO_LAYER, 4),
    ("zscript/RS_ForeignEffects.zs", r"\bpmo\.OverrideAttackPosDir\b", "false", 1),
    ("zscript/RS_ForeignEffects.zs", r"\bpmo\.AttackAngle\b", "pmo.Angle", 1),
    ("zscript/RS_ForeignEffects.zs", r"\bpmo\.AttackPitch\b", "pmo.Pitch", 1),
    ("zscript/RS_ForeignEffects.zs", r"\bpmo\.AttackPos\b", "pmo.Pos", 1),
    # Selaco's engine predates GZDoom's container rename: a lump's archive
    # index is GetLumpWadNum and its name GetWadName. Same meaning, and the
    # engine's own archive is still index 0.
    ("zscript/RS_ForeignModels.zs", r"\bWads\.GetLumpContainer\b", "Wads.GetLumpWadNum", 2),
    ("zscript/RS_ForeignModels.zs", r"\bWads\.GetContainerName\b", "Wads.GetWadName", 1),
]

# Class-name literals of games Selaco does not ship. They exist to keep other
# games' weapons out of the menu; in Selaco nothing descends from them, so
# each becomes a class that exists and that no weapon descends from.
NEVER_A_WEAPON = "'MS_Fist'"
NAME_EDITS = ("zscript/RS_ForeignModels.zs",
              ["'HereticWeapon'", "'FighterWeapon'", "'ClericWeapon'", "'MageWeapon'",
               "'StrifeWeapon'", "'Gauntlets'", "'PhoenixRod'", "'Sigil'"], 8)

# Names Selaco's engine does not have. None may survive in code.
FORBIDDEN = r"\b(Weapon|OffhandWeapon|bOffhandWeapon|PSP_OFFHANDWEAPON|OverrideAttackPosDir|AttackPos|AttackAngle|AttackPitch|AttackRoll|OffhandPos|OffhandAngle|OffhandPitch|OffhandRoll)\b"

TOKEN = re.compile(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\\n])*"|\'[^\'\n]*\'', re.S)

README = """ModelSwapper Selaco patch
=========================

Lets ModelSwapper's Quest build load in Selaco.
Load order: Selaco, then ModelSwapper-QUEST.pk3, then this patch.

Selaco's engine calls the weapon base class WeaponBase instead of Weapon and
has no VR hands. This patch replaces ModelSwapper's script files with copies
that use those names, and adds Selaco's own guns as in-hand models, read
from Selaco.ipk3 where they already are. It contains no Selaco code or
files. renders/ has a wireframe of each gun. Built by ModelSwapper's
tools_make_selaco_patch.py.
"""


def fail(msg):
    print("REFUSED: " + msg)
    sys.exit(1)


def split(text):
    """[(is_code, chunk)] -- comments, strings and names are not code."""
    out, pos = [], 0
    for m in TOKEN.finditer(text):
        out.append((True, text[pos:m.start()]))
        out.append((False, m.group(0)))
        pos = m.end()
    out.append((True, text[pos:]))
    return out


def rewrite(name, text):
    counts = {}
    parts = []
    for is_code, chunk in split(text):
        if is_code:
            for f, pat, rep, _ in CODE_EDITS:
                if f == name:
                    chunk, n = re.subn(pat, rep, chunk)
                    counts[pat] = counts.get(pat, 0) + n
            chunk, n = re.subn(r"\bWeapon\b", "WeaponBase", chunk, flags=re.I)
            counts["Weapon"] = counts.get("Weapon", 0) + n
        elif chunk in ('"Weapon"', "'Weapon'"):
            chunk = chunk[0] + "WeaponBase" + chunk[-1]
            counts["Weapon"] = counts.get("Weapon", 0) + 1
        elif name == NAME_EDITS[0] and chunk in NAME_EDITS[1]:
            chunk = NEVER_A_WEAPON
            counts["names"] = counts.get("names", 0) + 1
        parts.append((is_code, chunk))
    if name == NAME_EDITS[0] and counts.get("names", 0) != NAME_EDITS[2]:
        fail("%s: other games' class names expected %d, found %d -- ModelSwapper changed?" % (name, NAME_EDITS[2], counts.get("names", 0)))
    for f, pat, _, want in CODE_EDITS:
        if f == name and counts.get(pat, 0) != want:
            fail("%s: %s expected %d match(es), found %d -- ModelSwapper changed?" % (name, pat, want, counts.get(pat, 0)))
    code = "".join(c for is_code, c in parts if is_code)
    left = sorted(set(m.group(0) for m in re.finditer(FORBIDDEN, code)))
    if left:
        fail("%s: names Selaco lacks survived: %s" % (name, left))
    names = "".join(c for is_code, c in parts if not is_code)
    if re.search(r"['\"]Weapon['\"]", names):
        fail("%s: a Weapon class-name literal survived" % name)
    return "".join(c for _, c in parts), counts.get("Weapon", 0)


import math
import struct

DEFAULT_SELACO = "D:/SteamLibrary/steamapps/common/Selaco/Selaco.ipk3"

# SELACO'S OWN GUNS. Selaco draws its weapon pickups with MD3 meshes. The
# patch points ModelSwapper donor classes at those meshes, where Selaco.ipk3
# already has them loaded -- nothing is copied -- and lists each first in its
# families, so a weapon in that family wears it unless the player picks
# otherwise. (donor class, menu name, families, Selaco's MODELDEF block)
SELACO_GUNS = [
    ("MS_SEL_Cricket", "Roaring Cricket", ["pistol"], "ROARINGCRICKET_PICKUP"),
    ("MS_SEL_UC36", "UC-36 Rifle", ["rifle"], "RIFLE_PICKUP"),
    ("MS_SEL_Shotgun", "Selaco Shotgun", ["shotgun"], "SHOTGUN_PICKUP"),
    ("MS_SEL_SMG", "Selaco SMG", ["smg"], "SMG_PICKUP"),
    ("MS_SEL_DMR", "Marksman Rifle", ["sniper"], "MARKSMANRIFLE_PICKUP"),
    ("MS_SEL_Nailgun", "Nailgun", ["chaingun", "machinegun"], "NAILGUN_PICKUP"),
    ("MS_SEL_Railgun", "Selaco Railgun", ["railgun"], "RAILGUN_PICKUP"),
    ("MS_SEL_Plasma", "Selaco Plasma Rifle", ["plasma"], "PLASMARIFLE_PICKUP"),
    ("MS_SEL_GrenadeLauncher", "Selaco Grenade Launcher", ["launcher", "rocket"], "GRENADELAUNCHER_PICKUP"),
    ("MS_SEL_Grenade", "Selaco Grenade", ["grenade"], "HandGrenade"),
]


def md3_verts(data, frame=0):
    """Vertices of one frame, skipping surfaces collapsed onto one point."""
    nf, nt, ns, nsk, ofr, otg, osf = struct.unpack_from("<iiiiiii", data, 76)
    frame = frame if 0 <= frame < nf else 0
    p, out = osf, []
    for _ in range(ns):
        sf, ssh, sv, stri = struct.unpack_from("<iiii", data, p + 72)
        oxyz, oend = struct.unpack_from("<ii", data, p + 100)
        base = p + oxyz + frame * sv * 8
        vs = [tuple(c / 64.0 for c in struct.unpack_from("<hhh", data, base + v * 8)) for v in range(sv)]
        if vs:
            c = [sum(v[k] for v in vs) / len(vs) for k in range(3)]
            if max(math.dist(v, c) for v in vs) >= 0.5:
                out += vs
        p += oend
    return out


def render(data, donor):
    """Three-view wireframe of one Selaco mesh (tools_md3_render.py) into renders/selaco/."""
    import subprocess
    import tempfile
    folder = os.path.join(HERE, "renders", "selaco")
    os.makedirs(folder, exist_ok=True)
    png = os.path.join(folder, donor + ".png")
    with tempfile.TemporaryDirectory() as td:
        mesh = os.path.join(td, "mesh.md3")
        with open(mesh, "wb") as f:
            f.write(data)
        r = subprocess.run([sys.executable, os.path.join(HERE, "tools_md3_render.py"), mesh, png],
                           capture_output=True, text=True)
    if r.returncode != 0 or not os.path.isfile(png):
        fail("render of %s failed: %s" % (donor, (r.stderr or r.stdout).strip()[-300:]))
    return png


def main():
    args = sys.argv[1:]
    src = args[0] if len(args) > 0 else DEFAULT_SRC
    out = args[1] if len(args) > 1 else DEFAULT_OUT
    selaco = args[2] if len(args) > 2 else DEFAULT_SELACO
    z = zipfile.ZipFile(src)
    zlow = {n.lower(): n for n in z.namelist()}
    scripts = [n for n in z.namelist() if n.lower().startswith("zscript/") and n.lower().endswith(".zs")]
    if not scripts:
        fail("no zscript/*.zs in %s" % src)
    for f in set(f for f, _, _, _ in CODE_EDITS):
        if f not in scripts:
            fail("%s is not in %s" % (f, src))
    patched = {}
    for n in scripts:
        old = z.read(n).decode("utf-8")
        new, renamed = rewrite(n, old)
        if new != old:
            patched[n] = new
            print("  %-40s %3d Weapon names" % (n, renamed))
    # SPRITE NAMES. Every model block is keyed to a Doom sprite name (PISG,
    # SHTG, ...), and MODELDEF refuses a name the engine has never heard of --
    # "Unknown sprite PISG in model definition for MS_Pistol", a load failure.
    # Selaco ships none of Doom's sprites. A name becomes known when any
    # actor's states use it, lump or no lump, so one never-spawned actor of
    # ours lists them all. Its own zscript.txt compiles beside ModelSwapper's.
    md = z.read("modeldef").decode("utf-8")
    sprites = sorted(set(s.upper() for s in re.findall(r"^\s*FrameIndex\s+(\S{4})\s", md, re.M | re.I)))
    if not sprites:
        fail("no FrameIndex sprite names in %s's modeldef" % src)
    known = "\n".join("\t\t%s A -1;" % s for s in sprites)
    names_zs = ('version "4.12"\n\n'
                "// ModelSwapper Selaco patch: makes the sprite names ModelSwapper's\n"
                "// MODELDEF is keyed to known to the engine. Never spawned.\n"
                "class MS_SelacoSpriteNames : Actor\n{\n\tStates\n\t{\n\tSpawn:\n%s\n\t\tStop;\n\t}\n}\n" % known)
    print("  zscript.txt: %d sprite names made known (%s)" % (len(sprites), " ".join(sprites)))

    # Selaco's guns. Each is sized to the length of ModelSwapper's first model
    # in the same family, placed where that model sits, and centred by Offset
    # (Selaco's files are not ours to re-origin). The HUD transform is
    # v' = s * Ry(90 - AngleOffset) * v + Offset, in matrix axes (x, up, z)
    # = MD3 (x, z, y) with forward = -z; so ModelSwapper's meshes lead with
    # +X. Selaco's pickups lie along Y with the muzzle at -Y (AngleOffset 90)
    # or along X with it at +X (AngleOffset 0).
    sz = zipfile.ZipFile(selaco)
    slow = {re.sub(r"/+", "/", n.replace("\\", "/")).lower(): n for n in sz.namelist()}
    smd = "\n".join(sz.read(n).decode("latin-1") for n in sz.namelist() if n.lower().split("/")[-1].startswith("modeldef"))
    ms_src = z.read("zscript/RS_ForeignModels.zs").decode("utf-8")
    ms_shelf = re.search(r"static const string SHELF\[\]\s*=\s*\{(.*?)\};", ms_src, re.S).group(1)
    ms_rows = re.findall(r'"(\w+)\|(MS_\w+)\|(\w+)\|(-?\d+)\|(-?\d+)\|(-?\d+)"', ms_shelf)
    shelf_rows, name_rows, blocks, stubs, pngs = [], [], [], [], []
    for donor, label, families, pickup in SELACO_GUNS:
        m = re.search(r"^\s*Model\s+%s\s*\{(.*?)\}" % pickup, smd, re.S | re.M | re.I)
        if not m:
            fail("Selaco has no MODELDEF block %s" % pickup)
        body = m.group(1)
        path = re.search(r'\bPath\s+"([^"]+)"', body, re.I).group(1)
        mesh = re.search(r'\bModel\s+0\s+"([^"]+)"', body, re.I).group(1)
        skin = re.search(r'\bSkin\s+0\s+"([^"]+)"', body, re.I).group(1)
        key = re.sub(r"/+", "/", path.replace("\\", "/").strip("/") + "/" + mesh).lower()
        if key not in slow:
            fail("%s: %s is not in %s" % (pickup, key, selaco))
        mesh_bytes = sz.read(slow[key])
        vs = md3_verts(mesh_bytes)
        pngs.append((donor, render(mesh_bytes, donor)))
        c = [sum(v[k] for v in vs) / len(vs) for k in range(3)]
        ext = [max(v[k] for v in vs) - min(v[k] for v in vs) for k in range(3)]
        angle = 90.0 if ext[1] > ext[0] else 0.0

        fam = families[0]
        ref = next((r for r in ms_rows if r[0] == fam), None)
        if not ref:
            fail("ModelSwapper has no %s model to size %s against" % (fam, donor))
        rb = re.search(r"^Model %s\n\{\n(.*?)^\}" % ref[1], md, re.S | re.M).group(1)
        rpath = re.search(r'Path "([^"]+)"', rb).group(1)
        rmesh = re.search(r'Model 0 "([^"]+)"', rb).group(1)
        rscale = max(abs(float(x)) for x in re.search(r"^\s*Scale\s+(\S+)\s+(\S+)\s+(\S+)", rb, re.M).groups())
        ro = re.search(r"^\s*Offset\s+(\S+)\s+(\S+)\s+(\S+)", rb, re.M)
        place = [float(x) for x in ro.groups()] if ro else [0.0, 0.0, 0.0]
        rvs = md3_verts(z.read(zlow[(rpath + "/" + rmesh).lower()]), int(ref[4]))
        rlen = max(max(v[k] for v in rvs) - min(v[k] for v in rvs) for k in range(3))
        s = rlen * rscale / max(ext[0], ext[1])
        phi = math.radians(90.0 - angle)
        off = (place[0] - s * (c[0] * math.cos(phi) + c[1] * math.sin(phi)),
               place[1] - s * (-c[0] * math.sin(phi) + c[1] * math.cos(phi)),
               place[2] - s * c[2])
        anchor = ref[2]

        blocks.append(
            "Model %s\n{\n"
            "\t// Selaco's own %s mesh, read from Selaco.ipk3 -- not copied. Sized to\n"
            "\t// ModelSwapper's %s model %s, muzzle forward, centred by Offset.\n"
            "\tPath \"%s\"\n\tModel 0 \"%s\"\n\tSkin 0 \"%s\"\n"
            "\tScale %.3f %.3f %.3f\n\tAngleOffset %.0f\n\tOffset %.3f %.3f %.3f\n"
            "\tFrameIndex %s A 0 0\n\tFrameIndex %s B 0 9999\n}\n"
            % (donor, pickup, fam, ref[1], path, mesh, skin, s, s, s, angle, off[0], off[1], off[2], anchor, anchor))
        stubs.append("class %s : Actor {}" % donor)
        for f in families:
            shelf_rows.append('\t\t\t"%s|%s|%s|0|0|1",' % (f, donor, anchor))
        name_rows.append('\t\t\t"%s|%s",' % (donor, label))
        print("  %-24s %-18s scale %.3f  angle %3.0f  offset %7.2f %7.2f %7.2f" % (donor, "/".join(families), s, angle, off[0], off[1], off[2]))

    mt = patched["zscript/RS_ForeignModels.zs"]
    mt, n1 = re.subn(r"(static const string SHELF\[\]\s*=\s*\{\n)", lambda g: g.group(1) + "\n".join(shelf_rows) + "\n", mt)
    mt, n2 = re.subn(r"(static const string NAMES\[\]\s*=\s*\{\n)", lambda g: g.group(1) + "\n".join(name_rows) + "\n", mt)
    if n1 != 1 or n2 != 1:
        fail("could not find ModelSwapper's SHELF and NAMES tables (%d, %d)" % (n1, n2))
    patched["zscript/RS_ForeignModels.zs"] = mt
    names_zs += ("\n// Selaco's own guns: the classes that own the blocks in modeldef.selaco.\n"
                 "// Never subclass them (FindModelFrameRaw is an exact class test).\n" + "\n".join(stubs) + "\n")
    selaco_md = "// ModelSwapper Selaco patch: Selaco's own guns as in-hand models.\n\n" + "\n".join(blocks)

    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as o:
        o.writestr("zscript.txt", names_zs)
        o.writestr("modeldef.selaco", selaco_md)
        # Renders for people who want to see the guns. Distinct names, outside
        # every folder the engine reads textures or sprites from.
        for donor, png in pngs:
            o.write(png, "renders/msselaco_%s.png" % donor.lower())
        for n, t in sorted(patched.items()):
            o.writestr(n, t.encode("utf-8"))
        o.writestr("MODELSWAPPER-SELACO-PATCH.txt", README)
    print("wrote %s: %d of %d script files rewritten for Selaco" % (out, len(patched), len(scripts)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
