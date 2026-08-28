# ModelSwapper

**Their code, their damage, their sounds, their timing — these models.**

Real 3D weapons in any Doom mod. Load it alongside whatever weapon set you
already play, and the flat sprites in your hands become models. Nothing else
changes: the mod you loaded still does all the shooting.

![ModelSwapper](media/demo-1.gif)

## Any mod. Any weapon.

It knows nothing about any particular weapon set. It reads what's loaded at
runtime, sorts every weapon it finds into a family, and dresses it — so a mod
released tomorrow works the same as one from 2016, with no patch and no list to
maintain.

Guessed wrong? The menu lets you put any model on any weapon, and your choices
are remembered per weapon between sessions.

## Built for VR

Made for playing in a headset, where a flat sprite hanging in front of your face
is the one thing that breaks the illusion. Weapons animate against the mod's own
timing — fire, reload, raise, lower — because the mod's own state machine drives
the frames rather than anything guessing at them.

Optional: turn hitscan weapons into rounds that actually travel, so shots can be
led and dodged.

## Light

**31 models covering 20 weapon families, in about 28 MB** — 36 to pick from once
alternate finishes are counted. Deliberately small: one good model per shape
rather than everything that would fit, so it loads fast and stays out of the way.

It also leaves the world alone. Weapons lying on the ground keep the art their
own author drew.

![Assigning models](media/demo-2.gif)

## Does it work with my mod?

Tested against Ashes, Brutal Doom v21 and v22, Project Brutality, Golden Souls,
DoomRL Arsenal, Trailblazer, Combined Arms, DAKKA, Doomablo and Borderdoom,
among others. When one misbehaves, the menu's manual override is the escape
hatch.

## Which version?

| | |
| --- | --- |
| **`ModelSwapper.pk3`** | Desktop VR, on [UZDXREMA](https://github.com/presidentkoopa/UZDXREMA). **Animated**, reloads included. |
| **`ModelSwapper-QUEST.pk3`** | Standalone Quest, on [QuestZDoom](https://github.com/emawind84/QuestZDoom). Models are **static** — the animation needs engine features Quest doesn't have. |

Same models either way. Grab one, load it after your weapon mod, done.

---

- **[INTERNALS.md](INTERNALS.md)** — how it works, what it can't do, and why
- **[ENGINE_CHANGES.md](ENGINE_CHANGES.md)** — the engine-side changes animation needs
