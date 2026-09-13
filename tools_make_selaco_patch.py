"""Build a patch that lets ModelSwapper's Quest build load in Selaco.

    python tools_make_selaco_patch.py [ModelSwapper-QUEST.pk3] [output.pk3]

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
Nothing else. Only files that needed a change are in the patch.

HOW IT WORKS. ModelSwapper's zscript.txt includes each script by full path,
and the engine resolves an #include to the last loaded file with that path.
The patch carries those paths, so loaded after ModelSwapper it replaces
them. It has no zscript.txt of its own. Nothing of Selaco's is copied or
edited: this is ModelSwapper's code, rewritten from the pk3 you load.

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
that use those names. It contains no Selaco code. Built by ModelSwapper's
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


def main():
    args = sys.argv[1:]
    src = args[0] if len(args) > 0 else DEFAULT_SRC
    out = args[1] if len(args) > 1 else DEFAULT_OUT
    z = zipfile.ZipFile(src)
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

    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as o:
        o.writestr("zscript.txt", names_zs)
        for n, t in sorted(patched.items()):
            o.writestr(n, t.encode("utf-8"))
        o.writestr("MODELSWAPPER-SELACO-PATCH.txt", README)
    print("wrote %s: %d of %d script files rewritten for Selaco" % (out, len(patched), len(scripts)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
