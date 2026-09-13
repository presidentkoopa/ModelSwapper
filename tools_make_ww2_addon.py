"""Build ModelSwapper-WW2Addon.pk3: WW2 small arms for ModelSwapper.

    python tools_make_ww2_addon.py [BW-VR-Weapons folder] [output.pk3]

Load it after ModelSwapper (either build). Its models go first in their
families, so WW2 guns become the default models while it is loaded.

WHAT. The ten weapon models of the Brutal Wolfenstein VR weapon pack --
Luger, Colt 1911, MP40, Thompson, M1 Garand, StG 44, Kar98k, MG42, Trench
Gun, Flammenwerfer -- as ModelSwapper donors. Scale and offset come from
each model's own MODELDEF in the pack, as its author set them for VR.

THE TREATMENT. Like every core donor: each mesh is centred on its
rest-frame centroid (a copy, in .gen/ww2 -- the pack is never written), the
Offset compensated so the gun stays where its author placed it, and
before/after renders written to renders/ww2.

ANIMATION. The clip rows below are the ones ModelSwapper shipped for these
same meshes in commits 88b872e..982389f, derived from each weapon's own
letter->frame table crossed with its state machine. Rest frames are not
zero on every gun: the MG42 idles at frame 12, the StG 44 and MP40 at 13.
The desktop build plays the clips; the Quest build shows the rest frame.

HOW IT PLUGS IN. The addon's msaddon.txt (lump MSADDON) adds shelf, name and
clip rows to ModelSwapper's own tables -- see RS_ForeignAddon in
RS_ForeignAnim.zs. Its zscript.txt declares the donor classes and its
modeldef.ww2 their model blocks.
"""
import os
import re
import shutil
import struct
import subprocess
import sys
import zipfile

from tools_md3_compensate import compensate

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_SRC = r"D:\SteamLibrary\steamapps\Common\DooM VR\__Games\BrutalWolfenstein3D\BW-VR-Weapons"
DEFAULT_OUT = os.path.join(HERE, "ModelSwapper-WW2Addon.pk3")
# Centred copies are built here (.gen/ is gitignored); the pack is never written.
BUILD = os.path.join(HERE, ".gen", "ww2")
RENDERS = os.path.join(HERE, "renders", "ww2")

# donor, menu name, pack folder, mesh, skin, anchor sprite, rest frame
GUNS = [
    ("MS_BW_Luger", "Luger P08", "Luger", "luger.md3", "luger.png", "PISG", 0),
    ("MS_BW_Colt", "Colt 1911", "1911", "1911.md3", "1911.png", "PISG", 1),
    ("MS_BW_MP40", "MP40", "MP40", "mp40.md3", "mp40.png", "CHGG", 13),
    ("MS_BW_Thompson", "Thompson M1A1", "Thompson", "m1a1.md3", "m1a1.png", "CHGG", 1),
    ("MS_BW_Garand", "M1 Garand", "Garand", "garand.md3", "garand.png", "CHGG", 1),
    ("MS_BW_STG44", "StG 44", "STG44", "stg44.md3", "stg44.png", "CHGG", 13),
    ("MS_BW_Kar98", "Kar98k", "Mauser", "kar98k.md3", "kar98k.png", "CHGG", 1),
    ("MS_BW_MG42", "MG42", "MG42", "mg42.md3", "mg42.png", "CHGG", 12),
    ("MS_BW_Trenchgun", "Trench Gun", "Trenchgun", "m12.md3", "m12.png", "SHTG", 1),
    ("MS_BW_Flamethrower", "Flammenwerfer", "Flammenwerfer", "flammenwerfer.md3", "flammenwerfer.png", "PLSG", 0),
]

# Shelf order is default order: the first row of a family is what a weapon
# in that family wears until the player picks otherwise.
SHELF = [
    ("pistol", "MS_BW_Luger"), ("pistol", "MS_BW_Colt"),
    ("smg", "MS_BW_MP40"), ("smg", "MS_BW_Thompson"),
    ("rifle", "MS_BW_Garand"), ("rifle", "MS_BW_STG44"), ("rifle", "MS_BW_Kar98"),
    ("sniper", "MS_BW_Kar98"), ("sniper", "MS_BW_Garand"), ("sniper", "MS_BW_STG44"),
    ("machinegun", "MS_BW_MG42"), ("chaingun", "MS_BW_MG42"),
    ("shotgun", "MS_BW_Trenchgun"),
    ("flamethrower", "MS_BW_Flamethrower"),
]

CLIPS = [
    # Draw animations: the pack's Ready/Deselect sprite groups (ZLUS, Z19S,
    # ZMPS, ...), forward on select and reversed on deselect. Flammenwerfer's
    # IFLS 2-8 draw and FLMF 9-14 fire are read from sprite names, not states.
    "MS_BW_Luger|select|53-60@1|-1|-1|-1", "MS_BW_Luger|deselect|60-53@1|-1|-1|-1",
    "MS_BW_Colt|select|8-15@1|-1|-1|-1", "MS_BW_Colt|deselect|15-8@1|-1|-1|-1",
    "MS_BW_MP40|select|1-12@1|-1|-1|-1", "MS_BW_MP40|deselect|12-1@1|-1|-1|-1",
    "MS_BW_Thompson|select|40-52@1|-1|-1|-1", "MS_BW_Thompson|deselect|52-40@1|-1|-1|-1",
    "MS_BW_Garand|select|11-18@1|-1|-1|-1", "MS_BW_Garand|deselect|18-11@1|-1|-1|-1",
    "MS_BW_STG44|select|1-12@1|-1|-1|-1", "MS_BW_STG44|deselect|12-1@1|-1|-1|-1",
    "MS_BW_Kar98|select|35-43@1|-1|-1|-1", "MS_BW_Kar98|deselect|43-35@1|-1|-1|-1",
    "MS_BW_MG42|select|1-11@1|-1|-1|-1", "MS_BW_MG42|deselect|11-1@1|-1|-1|-1",
    "MS_BW_Trenchgun|select|8-22@1|-1|-1|-1", "MS_BW_Trenchgun|deselect|22-8@1|-1|-1|-1",
    "MS_BW_Flamethrower|select|2-8@1|-1|-1|-1", "MS_BW_Flamethrower|deselect|8-2@1|-1|-1|-1",
    "MS_BW_Luger|ready|0@1|-1|-1|-1",
    "MS_BW_Luger|fire|1@1,2@1,3-4@1,5@1|0|-1|-1",
    "MS_BW_Luger|reload|6-13@1,14-16@2,17-22@2,22-26@2,27-28@2,29-30@3,31-39@1,40-43@1,44-46@2,47-48@2,49@4,50-52@2,39-31@1|-1|0|24",
    "MS_BW_Colt|ready|1@1|-1|-1|-1",
    "MS_BW_Colt|fire|2@1,3@1,4-6@1|0|-1|-1",
    "MS_BW_Colt|reload|36-43@1,44-51@2,52-55@2,56-59@1,16-23@1,24-31@2,32-35@2,23-16@1|-1|0|20",
    "MS_BW_MP40|ready|13@1|-1|-1|-1",
    "MS_BW_MP40|fire|14@1,15-16@1,17-18@1|0|-1|-1",
    "MS_BW_MP40|reload|19-27@1,28-31@2,32-34@2,35-37@2,38@2,39@10,40-42@3,43-47@3,27-19@1|-1|0|26",
    "MS_BW_Thompson|ready|1@1|-1|-1|-1",
    "MS_BW_Thompson|fire|2@1,3@1,4@1|0|-1|-1",
    "MS_BW_Thompson|reload|6-13@1,14-17@2,18-27@2,28-30@2,31-32@3,33-35@1,35-37@1,32-28@1,13-6@1|-1|0|28",
    "MS_BW_Garand|ready|1@1|-1|-1|-1",
    "MS_BW_Garand|fire|2@1,3-5@1,6-9@1|0|-1|-1",
    "MS_BW_Garand|reload|19-24@1,25-30@2,31-35@1|-1|0|12",
    "MS_BW_STG44|ready|13@1|-1|-1|-1",
    "MS_BW_STG44|fire|14@1,15-17@1,18@1|0|-1|-1",
    "MS_BW_STG44|reload|19-24@1,25-27@1,28@2,29-37@2,42-44@1,45@3,46-50@1,24-19@1|-1|0|22",
    "MS_BW_Kar98|ready|1@1|-1|-1|-1",
    "MS_BW_Kar98|fire|2@1,3-6@1,6@3,7-10@2,11@6,10-7@2|0|-1|-1",
    "MS_BW_Kar98|reload|7-8@2,9-11@2,28-29@2,30-33@2,7-8@2,9-11@2,12-27@2,11-7@2|-1|0|18",
    "MS_BW_MG42|ready|12@1|-1|-1|-1",
    "MS_BW_MG42|fire|13@1,14@1,17@1|0|-1|-1",
    "MS_BW_MG42|reload|18-28@1,29@3,30-46@1,47-72@2,73-78@1,79@3,80@1,81@3,82-87@1,88@3,89-92@1,93@3,94-96@1|-1|0|60",
    "MS_BW_Trenchgun|ready|1@1|-1|-1|-1",
    "MS_BW_Trenchgun|fire|2@1,3-7@1,23@1,25@1,27@1,29@1,31@1,32@1,34@1,32@1,30@1,28@1,26@1,23@1|0|4|-1",
    "MS_BW_Trenchgun|reload|23-31@1,35-36@2,37-44@1,45@4,34-23@1|-1|0|14",
    "MS_BW_Flamethrower|ready|0@1|-1|-1|-1",
    "MS_BW_Flamethrower|fire|9-14@1|0|-1|-1",
]

README = """ModelSwapper WW2 Addon
======================

WW2 small arms for ModelSwapper: Luger P08, Colt 1911, MP40, Thompson M1A1,
M1 Garand, StG 44, Kar98k, MG42, Trench Gun and Flammenwerfer.

Load it after ModelSwapper (desktop or Quest build). While it is loaded the
WW2 guns are the default model in their families; the model menu still
lists everything. Animated on the desktop build, static on Quest.

Weapon models and textures: the Brutal Wolfenstein VR weapon pack.
Built by ModelSwapper's tools_make_ww2_addon.py.
"""


def fail(msg):
    print("REFUSED: " + msg)
    sys.exit(1)


def frame_count(path):
    d = open(path, "rb").read(96)
    if d[:4] != b"IDP3":
        fail("%s is not an MD3" % path)
    return struct.unpack_from("<i", d, 76)[0]


def pack_block(src, mesh):
    """Scale and offset from the pack's own MODELDEF block for this mesh."""
    for fn in sorted(os.listdir(src)):
        if not fn.lower().startswith("modeldef"):
            continue
        text = open(os.path.join(src, fn), encoding="latin-1").read()
        for m in re.finditer(r"\bModel\s+\w+\s*\{(.*?)\}", text, re.S | re.I):
            body = m.group(1)
            if re.search(r'\bModel\s+0\s+"%s"' % re.escape(mesh), body, re.I):
                sc = re.search(r"^\s*Scale\s+(\S+)\s+(\S+)\s+(\S+)", body, re.M | re.I)
                of = re.search(r"^\s*Offset\s+(\S+)\s+(\S+)\s+(\S+)", body, re.M | re.I)
                zo = re.search(r"^\s*ZOffset\s+(\S+)", body, re.M | re.I)
                scale = [float(x) for x in sc.groups()] if sc else [1.0, 1.0, 1.0]
                off = [float(x) for x in of.groups()] if of else [0.0, 0.0, 0.0]
                if zo:
                    off[2] = float(zo.group(1))  # ZOffset and Offset's z are one field
                return scale, off
    fail("no MODELDEF block in %s uses %s" % (src, mesh))


def treat(donor, mpath, folder, mesh, rest, scale, off):
    """THE TREATMENT, as every core donor got it (tools_reorigin_all.py):
    centre a copy of the mesh on its rest-frame centroid with
    tools_md3_reorigin.py (which verifies centroid, bounds and untouched
    bytes), compensate Offset with tools_md3_compensate's replica of the
    engine matrix so the gun stays exactly where its author put it, and
    render before and after."""
    os.makedirs(os.path.join(BUILD, folder), exist_ok=True)
    os.makedirs(RENDERS, exist_ok=True)
    cpath = os.path.join(BUILD, folder, mesh)
    shutil.copyfile(mpath, cpath)
    r = subprocess.run([sys.executable, os.path.join(HERE, "tools_md3_reorigin.py"), cpath,
                        "--rest", str(rest), "--apply"], capture_output=True, text=True)
    shift = re.search(r"shift applied \(grid\)\s+(\S+)\s+(\S+)\s+(\S+)", r.stdout)
    if r.returncode != 0 or not shift or "FAIL" in r.stdout or "ABORT" in r.stdout:
        fail("%s: re-origin failed:\n%s%s" % (donor, r.stdout, r.stderr))
    shift = tuple(float(x) for x in shift.groups())
    new_off, _ = compensate(shift, tuple(scale), tuple(off))
    stem = os.path.splitext(mesh)[0]
    for which, path in (("before", mpath), ("after", cpath)):
        png = os.path.join(RENDERS, "%s_%s.png" % (stem, which))
        rr = subprocess.run([sys.executable, os.path.join(HERE, "tools_md3_render.py"), path, png,
                             "--frame", str(rest)], capture_output=True, text=True)
        if rr.returncode != 0:
            fail("%s: render failed: %s" % (donor, (rr.stderr or rr.stdout)[-300:]))
    print("  %-20s shift %+8.3f %+8.3f %+8.3f  Offset %.3f %.3f %.3f -> %.3f %.3f %.3f"
          % ((donor,) + shift + tuple(off) + tuple(new_off)))
    return cpath, list(new_off)


def main():
    args = sys.argv[1:]
    src = args[0] if len(args) > 0 else DEFAULT_SRC
    out = args[1] if len(args) > 1 else DEFAULT_OUT
    donors = {g[0]: g for g in GUNS}
    for fam, d in SHELF:
        if d not in donors:
            fail("shelf row names unknown donor %s" % d)

    blocks, stubs, files, counts = [], [], [], {}
    for donor, label, folder, mesh, skin, anchor, rest in GUNS:
        mpath = os.path.join(src, "Models", folder, mesh)
        spath = os.path.join(src, "Models", folder, skin)
        for p in (mpath, spath):
            if not os.path.isfile(p):
                fail("missing %s" % p)
        nf = frame_count(mpath)
        if not 0 <= rest < nf:
            fail("%s rest frame %d outside its %d frames" % (donor, rest, nf))
        counts[donor] = nf
        scale, off = pack_block(src, mesh)
        cpath, off = treat(donor, mpath, folder, mesh, rest, scale, off)
        blocks.append(
            "Model %s\n{\n"
            "\t// Brutal Wolfenstein VR weapon pack, %s. Scale as its author set it.\n"
            "\t// origin: centred by tools_md3_reorigin.py -- Offset compensates the mesh shift\n"
            "\tPath \"models/ww2/%s\"\n\tModel 0 \"%s\"\n\tSkin 0 \"%s\"\n"
            "\tScale %.3f %.3f %.3f\n\tOffset %.3f %.3f %.3f\n"
            "\tFrameIndex %s A 0 %d\n\tFrameIndex %s B 0 9999\n}\n"
            % (donor, mesh, folder, mesh, skin, scale[0], scale[1], scale[2], off[0], off[1], off[2], anchor, rest, anchor))
        stubs.append("class %s : Actor {}" % donor)
        files += [(cpath, "models/ww2/%s/%s" % (folder, mesh)), (spath, "models/ww2/%s/%s" % (folder, skin))]

    for row in CLIPS:
        f = row.split("|")
        if f[0] not in donors:
            fail("clip row names unknown donor %s" % f[0])
        # frame numbers are the ones before "@" or around "-"; after "@" are tics
        top = max(int(n) for n in re.findall(r"\d+(?=[-@])|(?<=-)\d+", f[2]))
        if top >= counts[f[0]]:
            fail("%s %s clip reaches frame %d of %d" % (f[0], f[1], top, counts[f[0]]))

    anchor_of = {g[0]: g[5] for g in GUNS}
    rest_of = {g[0]: g[6] for g in GUNS}
    lines = ["// ModelSwapper addon rows -- see RS_ForeignAddon in ModelSwapper's RS_ForeignAnim.zs.", ""]
    lines += ["shelf %s|%s|%s|0|%d|%d" % (fam, d, anchor_of[d], rest_of[d], counts[d]) for fam, d in SHELF]
    lines += [""] + ["name %s|%s" % (g[0], g[1]) for g in GUNS]
    lines += [""] + ["clip " + r for r in CLIPS]
    zs = ('version "4.10"\n\n'
          "// ModelSwapper WW2 Addon: the donor classes that own the blocks in\n"
          "// modeldef.ww2. Never subclass them (FindModelFrameRaw is an exact class test).\n"
          + "\n".join(stubs) + "\n")

    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as o:
        o.writestr("zscript.txt", zs)
        o.writestr("modeldef.ww2", "// ModelSwapper WW2 Addon\n\n" + "\n".join(blocks))
        o.writestr("msaddon.txt", "\n".join(lines) + "\n")
        o.writestr("MODELSWAPPER-WW2ADDON.txt", README)
        for disk, arc in files:
            o.write(disk, arc)
    print("wrote %s: %d guns, %d shelf rows, %d clips (%.1f MB)"
          % (out, len(GUNS), len(SHELF), len(CLIPS), os.path.getsize(out) / 1048576.0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
