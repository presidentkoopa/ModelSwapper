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
psprite is pinned to our donor's anchor sprite. That only has to *resolve* — every
donor anchors on a stock Doom sprite name, which is why this ships no sprite lumps.
Runs per tick because the foreign weapon's own states re-set the sprite every frame.

**3. Drive the frame.** `psp.ModelFrame` picks which mesh frame actually draws,
bypassing the sprite encoding and its 29-frame ceiling, with `ModelFrameNext` and
`ModelFrameLerp` blending between frames at display rate.

### Animation

A sequence is **everything from leaving idle until returning to it** — not the gap
between two state changes. `WF_WEAPONREADY` marks the boundary exactly: `A_WeaponReady`
sets it and the engine clears it every tick, so it is true precisely while a weapon is
idle, in any mod, because calling `A_WeaponReady` is what makes a weapon usable at all.

The state you land on when you leave idle is the sequence's identity —
`(foreignClass, entryState)` — and it never has to be *named*, only recognised again.
Watch it once to learn how long it really ran and where its bright frame fell, then
play our matching clip across that duration on later runs.

Which clip to play is a **prior**, read from behaviour rather than names: ammo down
means they fired, clip up means they reloaded, a bright frame on a short sequence means
they fired. It is allowed to be wrong, because the picker is the correction path.

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

**Animation timing converges rather than being right immediately.** The models do
animate — fire and reload both play, driven by the foreign weapon's own timing. But a
sequence's real duration cannot be predicted from its state machine (a weapon's reload
can hide its entire body behind a zero-tic conditional jump: one tic predicted, sixty-
eight actual). So the first play of each sequence runs at our clip's natural rate, and
subsequent plays fit the shortest run observed. Expect the first shot and first reload
of each weapon to be approximate.

**Eighteen of the fifty donors have no reload animation.** Knives, chainsaws, fists,
the shorter MeatGrinder meshes — the mesh simply has no such frames. Bound to a weapon
that reloads, they hold the rest pose while the ammo count changes. The picker marks
them with `*`, and every family has other donors that do reload.

**Five reloads are inferred rather than derived.** Only 18 of the 43 source weapons
have a `Reload:` state, so for the rocket launcher, plasma rifle, GH machinegun,
MeatGrinder SSG and BFG10k the reload range is read off the unused tail of the mesh's
frame budget instead of off a state machine. They are the one place in the clip table
a range could be wrong.

**Frame-accurate animation requires the fork.** `psp.Frame` is a sprite *letter* index
and `MAX_SPRITE_FRAMES` is 29 — inherited from Doom's 8-character lump names. Every
donor here has more frames than that (the fist has 75, the MG42 has 97), so most
animation is unaddressable through the sprite path. The fork adds `int ModelFrame` on
`DPSprite`, read directly by the HUD path, which skips the encoding entirely. On stock
GZDoom the binding still works but the animation is limited to what 29 letters reach.

**Mods that already ship 3D weapons get painted over.** The engine's own test is
`actorDefaults->hasmodel`, which stock GZDoom does not export to ZScript. The fork
exports it; on stock it can't be detected.

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
