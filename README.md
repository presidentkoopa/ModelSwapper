# ModelSwapper

**Every weapon, in every mod, in 3D, in your hands.**

Load it last after any Doom mod and that mod's guns stop being flat sprites. Ashes,
Golden Souls, DAKKA, Brutal Doom — it doesn't matter which, and none of them need to
know ModelSwapper exists. Their code, their damage, their sounds, their timing: all of
it untouched. We replace the mesh and nothing else, then drive it off the mod's *own*
state machine — so when you reload, it looks like that mod's reload, because it **is**
that mod's reload, playing on a real 3D gun instead of a picture of one.

Pick your models from a menu while you're holding them, or press one button and dress
the whole arsenal at once. 42 models across 21 weapon families — pistols, shotguns,
railguns, flamethrowers, a chainsaw, a greatsword — remembered per mod, with no config
files and nothing to type. Built for VR, where a flat sprite welded to your face is the
first thing you notice and the last thing you forgive.

*PK's note: confirmed working for Ashes, Golden Souls, DAKKA. I'm working on Brutal Doom
v22 and I'm almost there.*

---

## Get it

| Your engine | Download |
|---|---|
| **UZDXREMA / DoomXR** (PC VR) | **`ModelSwapper.pk3`** — models animate |
| **QuestZDoom** (Emawind's DoomVR), or stock GZDoom 4.13+ | **`ModelSwapper-QUEST.pk3`** — models held at rest pose |

Same 42 models and the same menus in both; the difference is animation. **Don't load
both.**

```
gzdoom -file TheModYouWantToPlay.pk3 ModelSwapper.pk3
```

Load it **last**. That's the only rule. Everything else lives in
*Options → Weapon Model Swap Program*.

---

## On the model count

42 is what survived. The set started considerably larger and was cut to one model per
silhouette -- duplicates, dual-wield meshes that fight per-hand assignment in VR, and
anything that lost a straight comparison against the model kept for its family. Expect
it to shrink further: every model is still being evaluated against how cleanly it maps
onto real mods' animation states, and one gun that reloads correctly everywhere is worth
more than three that hold a pose.

---

## Asset licensing

The code here is ours. **The models are not** — they come from Brutal Doom v21,
MeatGrinder, Alek's Doom Guns, Ermac's Vanilla Doom Guns, and the Brutal Wolfenstein VR
weapons. Their licenses have not been established. Sort that out before redistributing.

## More

- **[INTERNALS.md](INTERNALS.md)** — how it works, what it can't do, and why
- **[ENGINE_CHANGES.md](ENGINE_CHANGES.md)** — the engine-side changes animation needs
