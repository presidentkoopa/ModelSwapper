# The model shelf: what's in it, what's wrong with it

A standing audit of the 38 donor meshes. Everything here is **measured**,
not read off anyone's modeldef — two tools produce it and both re-run in
seconds:

```bash
python tools_clip_audit.py    # frames used vs frames present, missing clips
python tools_pitch_audit.py   # clips that swing the gun off its rest pose
```

---

## Read this first: the numbers were wrong until 2026-09-04

Every frame measurement taken before that date was **shifted by one
frame**, and several decisions were made on it.

In an MD3 surface header, offset 96 is `ofsST` — texture coordinates —
and offset 100 is `ofsXYZNormal`. The reader used 96. Two consequences,
neither of which announced itself:

- **"Frame 0" was texture-coordinate bytes read as geometry.** It looked
  like a scattered mesh, so 24 of 38 donors appeared to have a broken
  first frame. None of them did.
- **Every real frame was reported one index low**, because the ST array
  is exactly `numVerts * 8` bytes — the same stride as one frame of
  vertices.

The tell was a model reading 424 units across at frame 0 and 5.9 at frame
1. A model that broken would have been obvious in a headset, and none of
them were. When a measurement disagrees this hard with what the game
plainly shows, distrust the measurement.

Three donors had been changed on the bad data and are now corrected:
`MS_Beretta` (rest frame), `MS_BD_AssaultShotgun` (select), `MS_Chaingun`
(spin range).

---

## Coverage: how many distinct poses are ever seen

A donor's clips name specific mesh frames. Frames no clip names are dead
weight -- shipped, loaded, never drawn.

**Counted in distinct POSES, not raw frames.** Raw coverage lies: the BFG
stores its idle six times over (frames 6-11) and the Jackhammer stores
every stroke pose twice and its idle six times. A clip naming one of each
has lost nothing, but counted raw the BFG reads 44% and looks neglected.

```
DONOR                    POSES SEEN  COVER    MISSING CLIPS
MS_Cola_Revolver         30/52          58%   altfire,select,sprint,ads
MS_RC_Chainsaw           25/43          58%   altfire,reload,select,sprint,ads
MS_VR_BFG9000             7/11          64%   altfire,reload,sprint,ads
MS_BD_BrutalAxe          10/15          67%   altfire,reload,ads
MS_MG_Tec9                2/3           67%   altfire,reload,select,sprint,ads
MS_Chaingun               7/10          70%   reload,ads
MS_Beretta                8/11          73%   altfire,sprint,ads
   ... 19 donors above 80% ...
```

Nothing is flagged thin. The four that were are resolved:

| donor | was | now | how |
| --- | --- | --- | --- |
| `MS_Chaingun` | 2 frames of 16 | 7 poses of 10 | twelve frames of barrel spin nobody played |
| `MS_AE_Flamer` | 4 of 20 | 18 poses of 19 | source's own `//Reloading` sections, 14 frames |
| `MS_Jackhammer` | 6 of 20 | 6 poses of 6 | full reciprocating stroke |
| `MS_VR_BFG9000` | 4 of 16 | 7 poses of 11 | four-frame shot, not the single frame the source named |
| `MS_Beretta` | 9 of 24 | 8 poses of 11 | frames 10-21 are a second cycle the source never used -- **left alone**, see below |

**Why this happens, and it is nobody's fault.** A donor's clips were
transcribed from the source mod's own MODELDEF. `MS_Chaingun` is the
clearest case: VanAlek's file declares `CHGG A -> 4` and `CHGG B -> 10`
and stops, because vanilla Doom's chaingun psprite alternates exactly two
frames. Faithful to the source, and nearly empty the moment a mod with a
real chaingun animation loads.

**Where the source was silent, the mesh was measured instead.** The BFG
has no documented frame map anywhere -- RS_Main's modeldef names three
frames. Distinct-pose analysis gave the real shape: 0-5 a raise, 6-11 one
idle repeated, 12-15 the shot. So its fire clip is four frames, not one.

**`MS_Beretta` is deliberately left thin.** Frames 10-21 are a genuine
second animation cycle -- vertex deltas up to 6.4 units on a 29-unit gun,
so not duplicates -- but the source modeldef never references them on the
gun mesh, and nothing says whether they are a slide-lock variant, an
alternate fire, or an unshipped idea. Assigning them to `altfire` would be
inventing an animation. Left until something authoritative says what they
are.

## Pitch: clips that swing the gun in your hand

Measured against each model's **own** rest pose, not against level — the
Brutal Axe rests 38° up and that is correct for an axe.

Two tolerances, because the clips mean different things:

- **select, 12°** — the gun is settling into your hand and you are about
  to aim. Anything past a slight settle reads as the gun rotating on its
  own, because your hand is not moving.
- **sprint, 25°** — you are running, not aiming. A carried weapon bobbing
  is the animation working.

One outstanding: `MS_BD_BrutalPistol` sprint reaches −16°, inside the
sprint tolerance. Nothing else.

**What this cost.** Brutal Doom draws a raise by swinging the gun up from
below the view. Right for a flat sprite; impossible to keep for a model in
a tracked hand. Five donors had no select frame within tolerance, so they
now snap into your hand rather than being raised: `MS_BD_BrutalSMG`,
`MS_BD_M79`, `MS_BD_RailGun`, `MS_PlasmaRifle`, `MS_BD_Rifle`. A snap is
worse than a raise and much better than the gun pointing at the floor
every time you draw it.

---

## Collapsed surfaces are not broken frames

`tools_gen_pickups.ps1` reports things like:

```
MS_Revolver -- ignored 7 collapsed surface(s) at frame 0: python.008(18) ...
```

That is one sub-mesh — a casing, a shell, a cylinder chamber — parked at
the origin while it is not in use. The gun renders perfectly. The fitter
already ignores them.

Worth stating because a naive check flags all of these as broken models.
The clip audit's degeneracy test measures the **median** vertex, which no
minority of the geometry can move. A max or even a 95th percentile
condemns a frame for a single stray vertex, and a 37-vertex collapsed
surface in an 800-vertex pistol *is* the top 5 %.

---

## What is actually wrong, in priority order

1. **`altfire` is missing nearly everywhere.** 30-odd donors have no
   altfire clip, so a mod's alt attack borrows whatever the healer decides.
   Some weapons genuinely have no second mode; most of these just were
   never authored.
2. **No `ads` clip on anything.** Aiming down sights falls back. Only
   matters for mods that have real ADS.
3. **`MS_BD_Boot` has no `ready`.** A kick has no idle, so it may be
   correct — worth an eyeball rather than a change.
4. **`MS_BD_Boot`'s fitted axis is weak** (l1/l2 = 2.36). A boot is not
   barrel-shaped, so the holster fit is a guess. Cosmetic, holsters only.

## What is fine and should be left alone

Nineteen donors sit above 80 % pose coverage, and no donor is thin. `MS_Rifle`, `MS_RC_M32`,
`MS_AE_Pistol` and `MS_RC_Auto9` use every frame they ship. The pitch pass
is clean. No clip anywhere plays a degenerate frame.
