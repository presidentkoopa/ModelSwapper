# ModelSwapper

**Their code, their damage, their sounds, their timing — these models.**

Real 3D weapons in any Doom mod. Load it alongside whatever weapon set you
already play, and the flat sprites in your hands become models. Nothing else
changes: the mod you loaded still does all the shooting.

![ModelSwapper](media/demo-1.gif)

## Does it work with my mod?

Probably. It knows nothing about any particular weapon set — it reads what's
loaded at runtime, so a mod released tomorrow works the same as one from 2016.

Tested against Ashes, Brutal Doom v21 and v22, Project Brutality, Golden Souls,
DoomRL Arsenal, Trailblazer, Combined Arms, DAKKA, Doomablo and Borderdoom,
among others. When one misbehaves, the menu's manual override is the escape
hatch.

---

## Which version?

| | |
| --- | --- |
| **`ModelSwapper.pk3`** | Desktop VR, on [UZDXREMA](https://github.com/presidentkoopa/UZDXREMA). **Animated**, reloads included. |
| **`ModelSwapper-QUEST.pk3`** | Standalone Quest, on [QuestZDoom](https://github.com/emawind84/QuestZDoom). Models are **static** — the animation needs engine features Quest doesn't have. |

Same models either way. Grab one, load it after your weapon mod, done.

---

- **[INTERNALS.md](INTERNALS.md)** — how it works, what it can't do, and why
- **[ENGINE_CHANGES.md](ENGINE_CHANGES.md)** — the engine-side changes animation needs
