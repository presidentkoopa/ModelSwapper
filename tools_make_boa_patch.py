"""Build boa-patch-quest.pk3: Wolfenstein: Blade of Agony (C3.1.4) on
QuestZDoom and UZDXREMA.

    python tools_make_boa_patch.py [boa.ipk3] [output.pk3]

Load order: boa.ipk3 as the IWAD, then this patch (then ModelSwapper).

WHY. Blade of Agony ships its own GZDoom and is written for it. Two of its
scripts fail to compile on QuestZDoom and UZDXREMA, four errors in all:

  scripts/actors/playerfollowers.zs, lines 501 and 1234
    "Cannot convert Pointer<Class<Actor>> to Pointer<Class<PathMarker>>".
    Markers is an Array<PathMarker> and currentGoal an Actor; this engine's
    Array.Find wants the element type exactly. Fixed with a PathMarker cast
    -- the same object, so the same answer.

  scripts/actors/skyboxview.zs, lines 86 and 87
    "Expression must be a modifiable value". SectorPortal.mSkybox and
    mDestination are `internal` here: only the engine's own scripts may
    write them. The two assignments are dropped. BoA's SkyViewPointStatic
    derives from the engine's SkyViewPoint, whose own BeginPlay already
    makes a tid-0 viewpoint the default skybox, so that case is unchanged;
    only BoA's forced override for a viewpoint with args[3] > 0 is lost.

HOW IT WORKS. The engine resolves an #include to the last loaded file with
that path, and only refuses overrides of its own core scripts. The patch
carries those two files, fixed, at their own paths.

WHY GENERATED, NOT COMMITTED. The files are Blade of Agony's code. This
script reads them from your own boa.ipk3 and edits them there, so none of
it lives in this repo. It refuses any file but C3.1.4's, by hash, and every
edit must match an exact number of times.
"""
import hashlib
import os
import sys
import zipfile

DEFAULT_BOA = r"C:\Users\Command\Downloads\boa_c31.4\boa.ipk3"
DEFAULT_OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "boa-patch-quest.pk3")

FILES = {
    "scripts/actors/playerfollowers.zs": (
        "df8282a0f68a06367f059b7a9e069a752a365592",
        [
            ("DestroyMarkers(Markers.Find(currentGoal));",
             "DestroyMarkers(Markers.Find(PathMarker(currentGoal)));", 1),
            ("index < follower.Markers.Find(follower.currentGoal)",
             "index < follower.Markers.Find(PathMarker(follower.currentGoal))", 1),
        ]),
    "scripts/actors/skyboxview.zs": (
        "f728803eeb727c6b0da06d6f3c64e083de6712c9",
        [
            ("level.sectorPortals[0].mSkybox = mo;",
             "// boa-patch-quest: mSkybox is internal on this engine; SkyViewPoint's own BeginPlay sets the tid-0 default", 1),
            ("level.sectorPortals[0].mDestination = mo.CurSector;",
             "// boa-patch-quest: mDestination is internal on this engine", 1),
        ]),
}

README = """boa-patch-quest
===============

Lets Wolfenstein: Blade of Agony C3.1.4 run on QuestZDoom and UZDXREMA.
Load boa.ipk3 as the IWAD, then this patch.

It replaces two Blade of Agony scripts that do not compile on those engines:
  - scripts/actors/playerfollowers.zs: two type casts
  - scripts/actors/skyboxview.zs: two skybox assignments this engine does
    not allow are dropped; a map's default skybox still works, but a forced
    skybox override (args[3] > 0) does not

Built by ModelSwapper's tools_make_boa_patch.py from your own copy of Blade
of Agony; for C3.1.4 only.
"""


def fail(msg):
    print("REFUSED: " + msg)
    sys.exit(1)


def main():
    args = sys.argv[1:]
    src = args[0] if len(args) > 0 else DEFAULT_BOA
    out = args[1] if len(args) > 1 else DEFAULT_OUT
    z = zipfile.ZipFile(src)
    names = {n.lower(): n for n in z.namelist()}
    patched = {}
    for path, (sha, edits) in FILES.items():
        if path not in names:
            fail("no %s in %s" % (path, src))
        raw = z.read(names[path])
        got = hashlib.sha1(raw).hexdigest()
        if got != sha:
            fail("%s is not Blade of Agony C3.1.4's (sha1 %s, expected %s)" % (path, got, sha))
        text = raw.decode("latin-1")
        for old, new, count in edits:
            n = text.count(old)
            if n != count:
                fail("%s: expected %d of %r, found %d" % (path, count, old, n))
            text = text.replace(old, new)
        patched[names[path]] = text.encode("latin-1")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as o:
        for n, data in patched.items():
            o.writestr(n, data)
        o.writestr("BOA-PATCH-QUEST.txt", README)
    print("wrote %s: %d Blade of Agony scripts fixed for QuestZDoom and UZDXREMA" % (out, len(patched)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
