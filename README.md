# ModelSwapper

**3D weapon models for weapons that aren't yours.**

Load this next to any Doom mod and every weapon that mod adds gets one of our 3D
HUD models painted over it. The mod's own code, damage, projectiles, effects and
sounds all run untouched underneath — the only thing replaced is the mesh in your
hands.

Built for VR, where a flat sprite welded to the view is the thing you notice most.

```
gzdoom -file TheModYouWantToPlay.pk3 ModelSwapper.pk3
```

Load it **last**. Everything is configured from menus; there is nothing you need
to type.

---

## Using it

**Radiant Silvergun Options → Weapon Model Swap Program**, or plain
**Options → Weapon Model Swap Program** when RS_Main isn't loaded.

| | |
|---|---|
| **Enable** | Master switch. On by default. |
| **Choose Models** | One row per foreign weapon. Three fields: family, mainhand model, offhand model. Left/Right cycles the highlighted field, Enter moves the highlight. |
| **Scan Report** | Everything the scanner found, why it guessed what it guessed. |
| **Rescan Now** | Re-reads the loaded mod without a map reload. Models you picked by hand are kept. |
| **List Unbound Weapons** | Turn on if the weapon list comes up empty. |

Models swap in your hands as you cycle, so picking is looking rather than guessing.

### If the weapon list is empty

Some mods (Golden Souls among them) assign weapon slots on their own player class
rather than on the weapons. The scanner hides weapons you have no slot binding for,
because otherwise the list fills with Heretic, Hexen and Strife weapons that GZDoom
compiles into every session and you can never hold. Switch **List Unbound Weapons**
on and hit **Rescan Now**.

---

## How it works

Two steps, both at runtime. No MODELDEF authoring, no restart.

**1. Point the weapon at our model.** `A_ChangeModel(<donorClass>)` sets the foreign
weapon instance's `modelData->modelDef`. The HUD render path resolves models against
`psp->Caller`'s per-instance model data *before* falling back to its class
(`models.cpp`, `FindModelFrame(AActor*)`), so the lookup lands in our MODELDEF block
— carrying its `Path`, `Skin`, `Scale`, `Offset` and `ZOffset` along with it.

**2. Pin the psprite.** Frame lookup still keys on sprite+frame, so each tick the
psprite is pinned to our donor's anchor sprite at its resting letter. This has to run
per tick because the foreign weapon's own states re-set the sprite every frame.

### Classification

Every foreign weapon is sorted into a **family**, then wears a model off that family's
shelf. Evidence order:

1. Name and tag tokens
2. Melee flag — but only on a weapon carrying no ammo at all
3. Ammo class names, **both** slots (reload mods put a magazine pseudo-ammo in slot 1
   and the real pool in slot 2)
4. Parent weapon class, so tiered variants of one gun don't scatter
5. **Slot number** — the catch-all, so nothing is ever left unmodelled

Scored against Golden Souls 2 and Ashes 2063: roughly 62% clean, 76% acceptable.
That is good enough *only because the picker exists*. A trumpet that fires musical
notes has no Doom archetype, and no heuristic will ever find one — it gets the
rocket launcher its slot implies, and you change it if you disagree.

Rows the classifier had to guess from slot alone are marked `?` and sorted to the top.
They are the only ones worth your attention.

---

## Known limits

**Static pose.** The model holds one resting frame. It does not animate on fire or
reload yet.

This is not a bug, it's a wall: `psp.Frame` is a sprite *letter* index, and
`MAX_SPRITE_FRAMES` is **29** — a limit inherited from Doom's 8-character lump names,
where the frame is a single character and Boom pushed it as far as `]`. Every donor
model here has more frames than that (the fist has 75), so most of the animation is
literally unaddressable through the sprite path.

The fix is an engine change: an `int ModelFrame` on `DPSprite` that the HUD path reads
directly, skipping the sprite encoding entirely. Then 75 is no different from 5.
Frame-accurate animation — mapping our sequences onto the foreign weapon's own
Raise/Ready/Lower/Fire/AltFire/Reload timings — depends on it.

**Mods that already ship 3D weapons get painted over.** The engine's own test is
`actorDefaults->hasmodel`, which isn't exported to ZScript. Two lines in a fork fixes
it; on stock GZDoom it can't be detected.

**No offhand-specific tuning.** The offhand is bound and pickable, but grip points and
two-handed placement are not modelled — every donor MD3 here has zero tags.

---

## Layout

```
zscript.txt              donor stubs + includes
zscript/
  RS_ForeignModels.zs    scanner, classifier, binder
  RS_ForeignModelsMenu.zs  picker + scan report
modeldef                 donor MODELDEF blocks
models/                  the meshes and skins
sprites/                 the five non-IWAD anchor sprites
MENUDEF  CVARINFO  MAPINFO  KEYCONF
```

The donor classes are bodyless `: Actor` stubs. A MODELDEF block is inert without a
real actor class owning its name, and `A_ChangeModel` takes an actor class name — so
they exist purely as something to hang a model on. They are never spawned, never
picked up, never seen.

They are namespaced `MS_` so this can load alongside RS_Main without duplicate-class
errors on `VR_*` / `RS_GH_*`. The shelf table lists both name sets and drops any row
whose donor class isn't loaded, so one build works either way.

**Never subclass a donor.** `FindModelFrameRaw` compares `smff->type == ti` as an exact
class-pointer test with no walk up the hierarchy, so a subclass inherits no model.

### Building

```powershell
./build.ps1
```

Produces `ModelSwapper.pk3`. A pk3 is a zip; entries must use forward slashes, which
`Compress-Archive` on Windows PowerShell does *not* do — hence the script.

---

## Requirements

GZDoom 4.11+ for `A_ChangeModel`. Verified against a 4.14 fork.

## Asset licensing

The code here is ours. **The models are not** — they came from several weapon packs
(a GoldHunter-derived set, a VR weapons set, and models credited in the source
modeldef to `BR_VR_MeatGrinder`). Their licenses have not been established. Sort that
out before making this repository public or redistributing the pk3.
