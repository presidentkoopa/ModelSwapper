# ModelSwapper

**3D weapon models for weapons that aren't yours.**

Load this next to any Doom mod and every weapon that mod adds wears one of our 3D
models — animated, in your hands, without that mod knowing anything about it. Its
own code, damage, projectiles, effects and sounds all run untouched. The only thing
replaced is the mesh.

```
gzdoom -file TheModYouWantToPlay.pk3 ModelSwapper.pk3
```

Load it **last**. Everything is configured from menus; there is nothing to type.

Built for VR, where a flat sprite welded to your view is the thing you notice most.

---

## Using it

**Options → Weapon Model Swap Program**

| | |
|---|---|
| **Enable** | Master switch. On by default. |
| **Choose Models** | One row per weapon in the loaded mod. Three fields: family, mainhand model, offhand model. Left/Right cycles the highlighted one, Enter moves the highlight. |
| **Scan Report** | Everything found, and why it was classified the way it was. |
| **Rescan Now** | Re-reads the loaded mod without a map reload. Your picks are kept. |
| **List Unbound Weapons** | Shows weapons with no slot binding — normally the Heretic, Hexen, Strife and Chex arsenals the engine compiles into every session. |

Models swap in your hands as you cycle, so choosing is looking rather than guessing.

Set the family to **`any`** to pick from all fifty models regardless of archetype. A
chainsaw on a rocket launcher is a legitimate thing to want.

---

## What's in it

**50 donor models across four sets**, and the picker names which set each came from
so cycling is a style choice rather than a shape hunt.

| Set | Models | Character |
|---|---|---|
| **VanAlek** | 14 | Doom's own arsenal, cleanly modelled |
| **Bv21** | 16 | GoldHunter — broader, includes railgun and flamethrower |
| **MeatG** | 9 | MeatGrinder — grittier, short meshes |
| **BWolf** | 11 | Brutal Wolfenstein — real WW2 small arms |

Thirteen families, four to six models each. Every family has options; nothing is
ever left unmodelled.

No sprites ship at all. Every donor anchors on a stock Doom sprite name that any
IWAD already has.

---

## How it works

### Binding — two runtime steps, no MODELDEF authoring

**1. Point the weapon at our model.** `A_ChangeModel(<donorClass>)` sets the foreign
weapon instance's `modelData->modelDef`. The HUD render path resolves models against
`psp->Caller`'s per-instance model data *before* falling back to its class
(`models.cpp`, `FindModelFrame(AActor*)`), so the lookup lands in our MODELDEF block —
carrying its `Path`, `Skin`, `Scale`, `Offset` and `ZOffset` with it.

**2. Pin the psprite.** Frame lookup still keys on sprite+frame, so each tick the
psprite is pinned to our donor's anchor sprite. That only has to *resolve*. Runs per
tick because the foreign weapon's own states re-set the sprite every frame.

**3. Drive the frame.** `psp.ModelFrame` picks which mesh frame actually draws,
bypassing the sprite encoding and its 29-frame ceiling, with `ModelFrameNext` and
`ModelFrameLerp` blending at display rate.

### Animation — identity without names

A sequence is **everything from leaving idle until returning to it** — not the gap
between two state changes. `WF_WEAPONREADY` marks that boundary exactly:
`A_WeaponReady` sets it and the engine clears it every tick, so it is true precisely
while a weapon is idle, in any mod, because calling `A_WeaponReady` is what makes a
weapon usable at all.

The state you land on when you leave idle *is* the sequence's identity —
`(weaponClass, entryState)`. It never has to be **named**, only recognised again.

Which clip to play is read from **behaviour, live**: ammo up is a reload, ammo down is
a shot, a bright frame on a short sequence is a shot. Names are never consulted,
because names are the one thing that doesn't generalise.

Playback is at natural rate — one clip tic per game tic, exactly as authored,
identical on every play. An animation that is right every time beats one that is
occasionally better timed and never predictable. `rs_foreignmodels_warp` enables
time-matching to the observed duration for anyone who wants it.

### Classification

Every weapon is sorted into a **family**, then wears a model off that family's shelf.
Evidence order:

1. Name and tag tokens
2. Melee flag — but only on a weapon carrying no ammo at all
3. Ammo class names, **both** slots (reload mods put a magazine pseudo-ammo in slot 1
   and the real pool in slot 2)
4. Parent weapon class, so tiered variants of one gun don't scatter
5. **Slot number** — the catch-all, so nothing is ever left unmodelled

Scored against Golden Souls and Ashes: roughly 62% clean, 76% acceptable. That is good
enough **only because the picker exists**. A trumpet that fires musical notes has no
Doom archetype and no heuristic will ever find one — it gets the launcher its slot
implies, and you change it if you disagree.

Rows the classifier had to guess from slot alone are marked `?` and sorted to the top.

### Which weapons are listed

The scan sees every class the engine compiled, because that is what binds models and it
must not be narrowed. The **menu** then shows only weapons bound to one of the player's
weapon slots — which the loaded mod put there, and which the Heretic, Hexen, Strife and
Chex arsenals are not.

That filter is in the menu on purpose. Filtering inside the scan means a broken filter
takes your models down with it.

---

## Known limits

**Timing is fixed, not fitted.** Clips play at their authored rate. If a weapon's reload
runs longer than ours, the model finishes and holds — a gun that has finished reloading
and is waiting.

**Eighteen of the fifty donors have no reload animation.** Knives, chainsaws, fists, the
shorter MeatGrinder meshes: the mesh has no such frames. Bound to a weapon that reloads
they hold the rest pose. The picker marks them `*`.

**Five reloads are inferred, not derived.** Only 18 of 43 source weapons declare a
`Reload:` state, so for the rocket launcher, plasma rifle, GH machinegun, MeatGrinder
SSG and BFG10k the range is read off the unused tail of the mesh's frame budget. They
are the one place in the clip table a range could be wrong.

**Requires the DoomXR fork for animation.** `psp.ModelFrame` and `Actor.hasmodel` are
fork exports. Binding, classification and the picker are all stock-GZDoom compatible;
animation is not, and referencing an unknown field is a compile error rather than a
graceful degrade.

**No offhand grip modelling.** The offhand binds and is pickable, but grip points and
two-handed placement are not modelled — every donor MD3 here has zero tags.

---

## Layout

```
zscript.txt                  donor stubs + includes
zscript/
  RS_ForeignModels.zs        scanner, classifier, binder, animation driver
  RS_ForeignAnim.zs          clip table, expansion, per-hand state
  RS_ForeignModelsMenu.zs    picker + scan report
modeldef                     49 donor blocks
models/                      the meshes and skins
MENUDEF  CVARINFO  MAPINFO  KEYCONF
```

Donor classes are bodyless `: Actor` stubs. A MODELDEF block is inert without a class
owning its name, and `A_ChangeModel` takes an actor class name — so they exist purely as
something to hang a model on. Never spawned, never picked up, never seen.

They're namespaced `MS_` so this can load alongside RS_Main without duplicate-class
errors.

**Never subclass a donor.** `FindModelFrameRaw` compares `smff->type == ti` as an exact
class-pointer test, so a subclass inherits no model.

### Building

```powershell
./build.ps1
```

Produces `ModelSwapper.pk3` and verifies it: forward-slash entries (a pk3 is a zip, and
`Compress-Archive` writes backslashes GZDoom can't read), every modeldef asset
resolving, no duplicate donor blocks, no donor without a stub.

---

## The engine change

Frame-accurate animation needed one thing stock GZDoom can't do.

A HUD model's frame arrives *through the sprite*: `psp->Frame` is a sprite letter index,
MODELDEF maps that letter to a model frame. That channel is one character wide —
`MAX_SPRITE_FRAMES` is **29**, inherited from Doom's 8-character lump names where Boom
pushed the frame char as far as `]`.

Meshes have no such limit. The fist here is 75 frames; the MG42 is 97. Everything past
the 29th was **unaddressable** — not awkward, unnameable. And raising the cap doesn't
help: three more ASCII characters exist after `]` and then it's lowercase, which lump
names case-fold away.

So the fork skips the encoding instead of stretching it: `int ModelFrame` on `DPSprite`,
read directly by the HUD path, with `ModelFrameNext` and `ModelFrameLerp` for sub-tic
blending. Documented as **§19** in `FORK_CHANGES.md`.

---

## Requirements

GZDoom 4.11+ for `A_ChangeModel`. The DoomXR fork for animation.

## Asset licensing

The code here is ours. **The models are not** — they come from several weapon packs
(a GoldHunter-derived set, a VR weapons set, models credited in the source modeldef to
`BR_VR_MeatGrinder`, and the Brutal Wolfenstein VR weapons). Their licenses have not
been established. Sort that out before making this repository public or redistributing
the pk3.
