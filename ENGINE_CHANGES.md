# Engine changes ModelSwapper needs

Everything required to run this on your own GZDoom build, in the order to apply it.
Five edits across six files, plus one signature thread. Nothing here changes how world
models render — it is all confined to the HUD/psprite path.

Written against **GZDoom 4.14**. Line numbers are approximate; the surrounding code is
quoted so you can find the spot regardless of version drift.

---

## Why any of this is necessary

A HUD model's frame arrives **through the sprite**. `psp->Frame` is a sprite letter
index, MODELDEF's `FrameIndex` maps that letter to a model frame, and `FindModelFrame`
looks the pair up.

That channel is one character wide. `MAX_SPRITE_FRAMES` is **29** — inherited from
Doom's 8-character lump names, where the frame is a single character and Boom pushed it
as far as `]`.

Meshes have no such limit. A typical weapon model here runs 30–75 frames; one is 97.
Everything past the 29th is **unaddressable** — not awkward, unnameable, because there
is no letter left to name it with.

Raising `MAX_SPRITE_FRAMES` does not fix it. Three more ASCII characters exist after
`]` and then it is lowercase, which lump names case-fold away — call it 32 against a
requirement of 97. It is also baked into `spriteframewithrotate sprtemp[...]` and the
lump-name scanner in `sprites.cpp`, so it changes how *every sprite in the game* parses
to buy something only the model path wants.

So these changes skip the encoding rather than stretching it.

---

## 1. Three fields on `DPSprite`

**`src/playsim/p_pspr.h`** — in the public block alongside `Sprite`, `Frame`, `ID`:

```cpp
int   ModelFrame     = -1;   // model frame to show, bypassing the sprite
int   ModelFrameNext = -1;   // frame to blend toward
float ModelFrameLerp = -1.f; // 0..1 blend factor; <0 = use stock timing
```

**Use in-class initialisers, not constructor-body assignments.** `DPSprite` has a
private argument-less constructor used only by savegame deserialisation, which runs
none of the public constructor's body — and the serialiser leaves unknown fields alone
when reading a save written before they existed. Set only in the constructor body,
these come back as garbage on load, and a garbage `ModelFrame` indexes a model's frame
array with a random int.

They live on the **psprite**, not the weapon actor, so the two hands animate
independently: mainhand and offhand are separate layers (`PSP_WEAPON` /
`PSP_OFFHANDWEAPON`) while `AActor::modelData` is per-actor.

---

## 2. Serialise and export them

**`src/playsim/p_pspr.cpp`** — in `DPSprite::Serialize`, add to the `arc(...)` chain:

```cpp
("modelframe", ModelFrame)
("modelframenext", ModelFrameNext)
("modelframelerp", ModelFrameLerp)
```

Same file, next to the other `DEFINE_FIELD(DPSprite, ...)` lines:

```cpp
DEFINE_FIELD(DPSprite, ModelFrame)
DEFINE_FIELD(DPSprite, ModelFrameNext)
DEFINE_FIELD(DPSprite, ModelFrameLerp)
```

**`wadsrc/static/zscript/actors/player/player.zs`** — in `class PSprite`, after
`native int Frame;`:

```
native int ModelFrame;
native int ModelFrameNext;
native float ModelFrameLerp;
```

---

## 3. Thread the psprite into the frame-selection path

This is the only structural part. `RenderHUDModel` has the `DPSprite` in hand and
passes only `psp->Caller`, so the psprite never reaches the code that picks a frame.

Add a trailing `const DPSprite* psp = nullptr` to three functions. World models pass
the default and are unaffected.

**`src/r_data/models.cpp`** — the forward declaration near the top:

```cpp
void RenderFrameModels(FModelRenderer* renderer, FLevelLocals* Level,
    const FSpriteModelFrame *smf, const FState* curState, const int curTics,
    FTranslationID translation, AActor* actor, const DPSprite* psp = nullptr);
```

…the definition (no default here — it belongs on the declaration only):

```cpp
void RenderFrameModels(..., AActor* actor, const DPSprite* psp)
```

…and in `RenderHUDModel`, pass it:

```cpp
RenderFrameModels(renderer, playermo->Level, smf, psp->GetState(),
                  psp->GetTics(), trans, psp->Caller, psp);
```

Inside `RenderFrameModels`, forward it to both callees:

```cpp
CalcModelFrameInfo frameinfo = CalcModelFrame(Level, smf, curState, curTics,
                                              modelData, actor, is_decoupled, tic, psp);
...
if (CalcModelOverrides(i, smf, modelData, frameinfo, drawinfo, is_decoupled, psp))
```

**`src/r_data/models.h`** — same trailing parameter, defaulted, on the declarations of
`CalcModelFrame` and `CalcModelOverrides`.

### ⚠ The landmine

**`src/common/rendering/hwrenderer/data/hw_vrwheel.cpp` carries its own forward
declaration of `RenderFrameModels`** and does not include `models.h`. It must be updated
to match:

```cpp
class DPSprite;
void RenderFrameModels(FModelRenderer* renderer, FLevelLocals* Level,
    const FSpriteModelFrame* smf, const FState* curState, const int curTics,
    FTranslationID translation, AActor* actor, const DPSprite* psp = nullptr);
```

Miss this and you get a **link error, not a compile error** — the signature silently
diverges. If your build doesn't have the VR weapon wheel, grep for other stray
declarations before assuming there are none.

---

## 4. Consume `ModelFrame` — the frame override

**`src/r_data/models.cpp`**, at the **end** of `CalcModelOverrides`, immediately before
its `return`:

```cpp
if (psp && psp->ModelFrame >= 0)
{
    out.modelframe     = psp->ModelFrame;
    out.modelframenext = (psp->ModelFrameNext >= 0) ? psp->ModelFrameNext
                                                    : psp->ModelFrame;
}
```

It must go **last**. That function resolves the frame in three separate branches — the
`modelFrameGenerators` path, the plain `data` path, and the no-`data` path — and the
override has to win over all of them.

Only the frame **number** is replaced. Scale, offsets, angle/pitch/roll, skins and flags
still come from the `FSpriteModelFrame` the sprite lookup returned, which is why
`FindModelFrame` must still succeed upstream. This is an override inside the model
system, not a bypass of it.

**Bounds are the caller's problem, deliberately.** `FMD3Model::RenderFrame` rejects
`(unsigned)frameno >= Frames.Size()` and draws nothing — a visible failure. Clamping to
the last frame here would hide the bug instead.

**Multi-model note.** `CalcModelOverrides` runs per model index in a loop. A single
`ModelFrame` applies the same frame to every model in the definition, which is correct
for a weapon showing frames of one animation. Per-index divergence would need an array.

---

## 5. Consume `ModelFrameLerp` — explicit interpolation

**`src/r_data/models.cpp`**, in `CalcModelFrame`, **after** the
`gl_interpolate_model_frames` / `MDL_NOINTERPOLATION` branch and before the
`modelsamount` calculation:

```cpp
if (psp && psp->ModelFrameLerp >= 0.f)
{
    float f = psp->ModelFrameLerp;
    if (f > 1.f) f = 1.f;
    inter   = f;
    smfNext = smf;
}
```

Three things make this work, and each was a bug before it did:

- **`smfNext = smf` is required.** `RenderModelFrame` discards `inter` unless
  `frameinfo.smfNext` is non-null. Same definition, different frame number, so `smf`
  itself is the correct "next" — every dereference reads valid memory.
- **It must sit after the CVar branch**, so an explicit blend is not silently dropped
  when a user turns `gl_interpolate_model_frames` off.
- **Don't use `clamp()`** unless that file already pulls it in; a manual upper bound
  avoids a header dependency. The lower bound is the `>= 0.f` test, which is also false
  for NaN.

Without this, stock `inter` is derived from state tics and only tweens across a state
*transition* — so an animation played across a foreign weapon's timings would restart
its blend on every state change and sit at zero between them, snapping pose to pose.

---

## 6. Export `AActor::hasmodel` (optional but recommended)

**`src/scripting/vmthunks_actors.cpp`**, next to `DEFINE_FIELD(AActor, sprite)`:

```cpp
DEFINE_FIELD(AActor, hasmodel)
```

**`wadsrc/static/zscript/actors/actor.zs`**, after `native uint8 frame;`:

```
native readonly bool hasmodel;
```

`hasmodel` is set on the **class defaults** by the MODELDEF parser and is the same flag
`FindModelFrameRaw` gates on, so it answers "does this class have a model at all" —
which is what a model-swapping mod needs in order not to paint over a mod that already
ships 3D weapons.

**Read it off `GetDefaultByType`, never off a live actor.** `EnsureModelData` sets it on
the *instance* as a side effect of `A_ChangeModel`, so an instance read reports true for
anything already swapped.

Without this the mod still works; it just cannot detect mods that ship their own models.

---

## 7. Suppress flat psprite overlays on a weapon drawn as a model (optional)

**Independent of everything above.** Nothing else in this document depends on it, and
animation works fine without it — this fixes a *visual* artifact that only appears once
weapons render as models, which is to say once any of this works at all.

### The problem

A muzzle flash is its own psprite layer, drawn by the same weapon on top of itself. VR
runs two passes over the same psprite list:

```cpp
PreparePlayerSprites3D:   if (!smf) continue;   // keeps layers WITH a model
PreparePlayerSprites2D:   if (smf)  continue;   // keeps layers WITHOUT one
```

The gun has a model, so the 3D pass draws it. The flash has none, so the 2D pass draws
it flat. Both run every frame, and the result is a billboard hanging in front of a 3D
weapon — the single artifact that gives the whole illusion away.

### Why it cannot be done from ZScript

Two reasons, either one sufficient:

1. `DPSprite::GetRenderStyle` **discards `psp->alpha`** unless the layer carries
   `PSPF_ALPHA` or `PSPF_FORCEALPHA`. A plain `A_GunFlash` overlay sets neither, so it
   returns the *owner's* alpha and a script's write is thrown away. Setting the flag
   means `A_OverlayFlags`, an action function on the weapon — not reachable for someone
   else's weapon from an event handler.
2. The decision is a `continue` in a render loop. No script participates.

### The change

One cvar:

```cpp
// rendering/r_utility.cpp
CVAR(Float, r_hudflatoverlay, 1.0f, CVAR_ARCHIVE);
```

and one block in `PreparePlayerSprites2D` (`rendering/hwrenderer/scene/hw_weapon.cpp`),
immediately after that pass's `if (smf) continue;`. It walks the psprite list for a
`PSP_WEAPON`/`PSP_OFFHANDWEAPON` layer with the **same `Caller`** and tests whether that
layer resolves a model. If it does, this flat layer belongs to a weapon being drawn as a
mesh, and the cvar decides its fate: `<= 0` skips it outright, anything between scales
`hudsprite.alpha` after `GetWeaponRenderStyle` has run.

### Why it is safe

Scoped to *"the weapon owning this layer is drawn as a model"*, not to *"hide flashes"*.
Three consequences worth stating, because they are the whole argument:

- **Vanilla play is untouched.** A sprite pistol's weapon layer resolves no model, the
  test is false, and the flash draws exactly as always — even with the cvar at 0.
- **A mod's own sprite weapons keep their flashes** in the same session where a modelled
  weapon loses one. The distinction is per weapon, per frame, and always current.
- **The default is 1.0**, which suppresses nothing. Someone has to opt in.

The one cost: it is a *fork* feature. Stock GZDoom and QuestZDoom have no such cvar, so
the flash stays there. Setting a cvar that does not exist is harmless, so nothing needs
guarding on the script side.

## What is *not* needed

**`A_ChangeModel` is stock** as of GZDoom 4.11 and unchanged through 4.14. The binding
half of this mod — per-instance `modelDef` override, classification, the picker — runs on
an unmodified engine. Only the animation needs the above.

**No MODELDEF format change.** Donor blocks are ordinary MODELDEF.

**No new CVars, no renderer state, no shader work.**

**The ballistics option needs nothing either.** Converting the player's hitscans into
travelling projectiles sounds like it would need a hook, and it does — but the hook is
already stock. `WorldHitscanPreFired` returns `bool`, and `P_LineAttack` returns
`nullptr` when a handler returns `true`, which is complete cancellation at the one
function every hitscan in the game funnels through. The `WorldEvent` it hands over
already carries the angle, pitch, distance, damage, damage type, puff and offsets of the
shot that was about to happen — everything needed to rebuild it as a projectile. Nothing
in `RS_ForeignBallistic.zs` touches the engine.

---

## Verifying it

1. **It compiles and links.** The link step is where a missed `hw_vrwheel.cpp` shows up.
2. **Load a save written before the change.** `ModelFrame` must read back as `-1`, not
   garbage. This is what the in-class initialisers are for.
3. **World models are unchanged.** They pass `psp == nullptr` and take none of the new
   branches.
4. **Set `psp.ModelFrame` from ZScript and watch the mesh change frame.** If the weapon
   vanishes instead, the frame is out of range for that mesh — which is the intended
   failure mode.

---

## Upstreaming

Nothing here is specific to this mod. `int ModelFrame` on a psprite is the general fix
for "a HUD model cannot reach past 29 frames", which affects any mod shipping detailed
weapon models regardless of whether anything is being swapped. If you are carrying these
patches, they are small enough and self-contained enough to be worth proposing upstream.
