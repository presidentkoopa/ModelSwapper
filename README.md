# ModelSwapper

**Their code, their damage, their sounds, their timing — these models.**

Real 3D weapons in any Doom mod. Load it alongside whatever weapon set you
already play, and the flat sprites in your hands become models. Nothing else
changes: the mod you loaded still does all the shooting.

![ModelSwapper](media/demo-1.gif)

---

## What you get

**44 models**, from Ermac's VanillaVR Plus, Alek's DoomGuns, Brutal Wolfenstein
5.0 and Brutal Doom v21.

**It guesses for you.** Load a mod and every weapon gets a sensible model
straight away, worked out from its name, its ammo and its slot. Nothing is left
as a bare sprite.

**Then you overrule it.** Any model on any weapon. If it guessed your shotgun is
a rifle, fix it in two clicks. Want a pistol on the BFG for some John Wick
nonsense? Also two clicks.

**Your choices stick** — per weapon, between sessions.

**The guns on the floor match.** A weapon lying in the level wears the model
you'll be holding once you pick it up, sized from the mesh rather than guessed.
Off by default; some mods have pickup art worth keeping.

![Assigning models](media/demo-2.gif)

### Or do it without a menu

Load [RS_WeaponWheel](https://github.com/presidentkoopa/RS_WeaponWheel) and
assignment moves into the world. Open the wheel and the ring fills with the
models for the gun in your hand — the one you're wearing highlighted, the rest a
trigger pull away. Point, pull, it's on.

No menu, no pausing, no taking the headset off. Desktop VR only.

---

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
