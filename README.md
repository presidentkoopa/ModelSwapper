# ModelSwapper

**A universal 3D weapon mod for Doom.**

Load it alongside whatever weapon set you already play and the flat sprites in
your hands become models. Nothing else changes: their code, their damage, their
sounds, their timing. The mod you loaded still does all the shooting.

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
led and dodged. Five looks to pick from, and it only ever touches your own
hitscan — projectiles, melee and monsters are left alone.

Ships with a compensator for **Bullet Time X**, so you can slow the world down
and still move at full speed while you dodge the rounds coming back. One slider,
inert unless that mod is loaded.

## Light

**32 models covering 20 weapon families, in about 29 MB** — 37 to pick from once
alternate finishes are counted. Deliberately small: one good model per shape
rather than everything that would fit, so it loads fast and stays out of the way.

It also leaves the world alone. Weapons lying on the ground keep the art their
own author drew.

## Does it work with my mod?

Tested against Dakka, vanilla Doom, Brutal Doom v21 and v22, Project Brutality
0.4.1, Ashes (all episodes), Combined Arms, Final Doomer, LegenDoom, Doomablo,
BorderDoom, Complex Doom, Trailblazer, Guncaster, DoomRL Arsenal, MetaDoom, and
Golden Souls 1 and 2, among others.

When one misbehaves, the menu's manual override is the escape hatch.

## Which version?

| | |
| --- | --- |
| **`ModelSwapper.pk3`** | Desktop VR, on [UZDXREMA](https://github.com/presidentkoopa/UZDXREMA). **Animated**, reloads included. |
| **`ModelSwapper-QUEST.pk3`** | Standalone Quest, on [QuestZDoom](https://github.com/emawind84/QuestZDoom). Models are **static** — the animation needs engine features Quest doesn't have. |

Same models either way. No dependencies, nothing to patch. Grab one, load it
after your weapon mod, done.

---

- **[INTERNALS.md](INTERNALS.md)** — how it works, what it can't do, and why
- **[ENGINE_CHANGES.md](ENGINE_CHANGES.md)** — the engine-side changes animation needs
