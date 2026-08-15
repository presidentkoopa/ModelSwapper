# ModelSwapper

**3D weapon models for weapons that aren't yours.**

Load this next to any Doom mod and every weapon that mod adds wears one of our 3D models
— in your hands, animated, without that mod knowing anything about it. Its own code,
damage, projectiles, effects and sounds run untouched. Only the mesh is replaced.

Built for VR, where a flat sprite welded to your view is the thing you notice most.

PKs Note: Confirmed working for Ashes, Golden Souls, DAKKA, ... I'm workin on brutaldoomv22 and I'm almost there.

---

## Download

| Your engine | File |
|---|---|
| **UZDXREMA / DoomXR** (PC VR) | `ModelSwapper.pk3` — models animate |
| **QuestZDoom** (Emawind's DoomVR), or stock GZDoom 4.11+ | `ModelSwapper-QUEST.pk3` — models held at rest pose |

Same 42 models and the same menus in both. The difference is animation, and only
animation. **Don't load both** — they're the same mod and will collide.

## Run it

```
gzdoom -file TheModYouWantToPlay.pk3 ModelSwapper.pk3
```

**Load it last.** That's the only rule. Everything else is menus.

---

## Using it

**Options → Weapon Model Swap Program**

| | |
|---|---|
| **Choose Models** | One row per weapon in the loaded mod. Left/Right cycles, Enter moves down. Models swap in your hands as you cycle, so you're looking rather than guessing. |
| **Assign All** — VanAlek / Bv21 / MeatG / BWolf | Dresses the whole arsenal in one set, keeping each weapon's kind: a shotgun gets that set's shotgun. |
| **Randomize — One-Handed** | Random pistol, revolver or SMG on everything, one press. |
| **Rescan Now** | Re-reads the loaded mod without reloading the map. Your picks survive. |
| **Scan Report** | What it found and why it guessed the way it did. |
| **Forget Saved Models** | Back to auto-picked everywhere. |

Set a weapon's family to **`any`** to pick from all 42 models regardless of type. A
chainsaw on a rocket launcher is a legitimate thing to want.

**Your picks are remembered per mod, with no profiles to manage.** Choices are saved
against the weapon's own class name, so Ashes and Golden Souls never tread on each
other — come back next week and each still has what you gave it.

**One model per weapon, not per hand.** Whichever hand holds a gun, it wears the same
model.

Weapons you never look at don't all end up identical: an auto-picked model is chosen by
hashing the weapon's name, so two pistols in one mod differ — and the same weapon gets
the same model every session.

---

## The models

**42 models across four sets**, and the picker names the set each came from so cycling
is a style choice rather than a shape hunt.

| Set | Models | Character |
|---|---|---|
| **Bv21** | 18 | Brutal Doom v21 — the broadest set |
| **VanAlek** | 9 | Doom's own arsenal, cleanly modelled |
| **BWolf** | 8 | Brutal Wolfenstein — real WW2 small arms |
| **MeatG** | 7 | MeatGrinder — grittier, shorter meshes |

21 weapon families, from pistol and shotgun through railgun, flamethrower, sniper and
kick. Every family has options; nothing is left unmodelled.

No model ships a sprite — each anchors on a stock Doom sprite name every IWAD already
has.

**Optional: bullets that travel.** Off by default, its own menu page, and the only thing
here that changes how a mod *plays* rather than how it looks. Details in
[INTERNALS.md](INTERNALS.md).

---

## Known limits

- **Some models have no reload animation** — knives, saws, fists, the shorter meshes.
  The mesh simply has no such frames; bound to a weapon that reloads, they hold their
  rest pose. The picker marks them `*`.
- **A few reload ranges are inferred**, read off the unused tail of a mesh's frames
  rather than derived from the source weapon. They're the one place a range could be
  wrong — if one looks off, pick another model.
- **The Quest build doesn't animate.** Models bind and orient correctly and hold their
  rest pose.
- **Overlay actions are PCVR only** — a mod's kick, run on its own psprite layer, wears
  a model on the full build but not the Quest one.
- **No offhand grip modelling.** The offhand binds and is pickable, but two-handed grip
  points aren't modelled.

Longer list, with the reasons, in [INTERNALS.md](INTERNALS.md).

---

## Requirements

GZDoom **4.11+** for the static build. The **DoomXR / UZDXREMA** fork for animation.

## Building

```
./build.ps1           # ModelSwapper.pk3        -- PCVR, full animation
./build.ps1 -Static   # ModelSwapper-QUEST.pk3  -- stock-safe, no animation
```

One source tree; the script swaps a single file between the two.

## Asset licensing

The code here is ours. **The models are not** — they come from Brutal Doom v21,
MeatGrinder, Alek's Doom Guns, Ermac's Vanilla Doom Guns, and the Brutal Wolfenstein VR
weapons. Their licenses have not been established. Sort that out before redistributing.

## More

- **[INTERNALS.md](INTERNALS.md)** — how binding, animation and classification work
- **[ENGINE_CHANGES.md](ENGINE_CHANGES.md)** — the engine-side changes animation needs
