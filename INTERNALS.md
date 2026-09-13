# ModelSwapper internals

How the mod actually works: the binding and animation mechanism, the classifier, and
the repo layout. None of this is needed to *use* ModelSwapper —
see [README.md](README.md) for that. The engine-side fork work has its own document,
[ENGINE_CHANGES.md](ENGINE_CHANGES.md).

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

### Animation — their state machine is the clock

The weapon already broadcasts its complete animation state every tic: which state its
psprite is in. Everything else follows from reading it.

**At bind time, once per (weapon, donor):** walk the weapon's labeled state sequences —
`Ready`, `Fire`, `AltFire`, `Reload`, `Zoom`, `User1-4`, and the rest. Those labels are
engine-structural, not conventions: the engine's own button code jumps to them by name,
so any weapon that answers a button has them. Collect each sequence's states in order
with their tic durations (`Goto` is encoded in `NextState`, so the walk follows the real
authored flow), and distribute the donor clip's frames across that timeline
proportionally. The result is a lookup table: **their state → our mesh frame**.

**At runtime, per tic:** one table lookup. Their conditionals, branches, per-shell
loops, refires, and empty-mag auto-reloads all just happen — whatever state their logic
lands in, the mapped frame shows. Timing cannot drift from theirs because there is no
timing of ours. A partial reload displays fewer of their states than a full one, and the
mesh follows exactly. Nothing is learned, so nothing has a learning period: **the first
shot of the first session is already right.**

The recoil lands on the bang **statically**: their fire states carry `bFullbright`, our
clip knows which of its frames is the shot, and the walk pins those together at build
time — no observation needed.

Sequences claim states in priority order (Ready first, Reload before Fire), so shared
tails park on the rest pose and an empty-mag `Fire → Goto Reload` shows the reload
mapping the moment its states are entered. States reachable only through runtime
`A_Jump` side effects are absent from the table; the runtime holds the last mapped pose
until their logic returns to mapped territory — a pause, never garbage.

An earlier design predicted instead of reading: it learned durations by observation,
locked them, scaled them by ammo-rates, gated the rates on evidence, and glued idle gaps
to find sequence boundaries. Every mechanism in that list existed to reconstruct
information the state table already carries, and every one of them hosted bugs. The
remap replaced all of it and deleted more code than it added.

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
must not be narrowed. The **menu** then shows a row if *either* of two signals earns it:

- **Slot binding** — the weapon is bound to one of the player's weapon slots, which the
  loaded mod put there and the engine-compiled Heretic/Hexen/Strife/Chex arsenals never
  are.
- **Provenance** — the class name was read out of a sideloaded archive's own
  `DECORATE`/`ZSCRIPT` text. The engine can't be asked which archive defined a class, so
  the scanner reads the same text the engine compiled: every container's root
  script lump and its `#include` tree (quoted and unquoted forms both — Ashes includes
  without quotes), skipping container 0, which is the engine itself and the home of
  every stock arsenal. No game names, no IWAD lists, nothing to maintain.

Either alone has a known failure. Slot binding misses Golden Souls entirely (its slots
live on a player class that never spawns under RS_Main — the menu came up empty).
Provenance goes dark on packaging the text parser can't read. The union covers both, and
if the harvest fails completely the menu degrades to exactly the old slot-binding
behavior — never to empty-while-models-work.

Both filters live in the menu on purpose. Filtering inside the scan means a broken
filter takes your models down with it. The scan report also names the archive each
listed weapon came from.

### Classes nobody holds

Mods also declare Weapon subclasses that are not weapons. Brutal Doom v22 has vehicle
guns, seven meat shields, executions, a ledge grab and a repair tool, one tagged "Pistol"
and one "Chainsaw", so each was a junk row with a believable name. The menu drops a class
when either of two tests says nobody holds it (`EntryNeverHeld`):

- **No Ready state.** A weapon is raised into Ready, so a class without one cannot be
  held. This catches abstract bases, and MetaDoom's rocket, a projectile declared
  `: Weapon`.
- **No slot, and flagged `+WEAPON.CHEATNOTWEAPON`.** The mod itself says "not a weapon"
  and no number key reaches it. Nearly every mod flags real guns too, but those sit in
  slots. Upgraded forms (`+WEAPON.POWERED_UP`) are exempt. So is any archive that brings
  its own player class while you are playing a different one: its slot table is not in
  play, so "no slot" means nothing there.

Checked against the source of about twenty mods before shipping. The only rows it
removes are abstract bases, helpers and that rocket. List Unbound Weapons shows them all
again.

### Project Brutality in the off hand

A VR engine can move any weapon between hands, and ModelSwapper never stops it. Project
Brutality's weapon code, though, asks for the main-hand sprite layer everywhere. While a
gun moves to the off hand the main hand is briefly empty, the engine answers null, and
eleven of PB's lookups use that answer unchecked, so a move occasionally crashes the game.

`tools_make_pb_offhand_patch.py` fixes that at the source without touching either engine.
From your own copy of Project Brutality 0.4.1 it rewrites those lookups to ask for the
hand the gun is actually in and to check for null, and writes
`PB-0.4.1-VR-Offhand-Patch.pk3`. Load it after PB. A later archive replaces an included
script by carrying the same path, so it works on Quest too. No PB code is committed here:
the script edits your copy, refuses any file but 0.4.1's by hash, and fails if an edit
does not match exactly.
---

## Compatibility targets

These are the mods this is meant to work with. They were chosen because between
them they cover the ways a Doom weapon can be built — vanilla-ish arsenals,
magazine reloads, scavenged small arms, whimsical weapons with no archetype at
all, assembly systems, and ZScript weapons rather than DECORATE ones.

| Mod | Style | Status |
|---|---|---|
| **Golden Souls 2 / Remastered** | Whimsical, custom ammo, weapons with no Doom archetype | Tested — binds, classifies, animates |
| **Ashes 2063 / Afterglow** | Post-apocalyptic, magazine reloads, realistic small arms | Tested — binds, classifies, animates |
| **Brutal Doom v22** | Heavy state machines, reload system | Tested — binds, classifies, animates |
| **Project Brutality** | One gun composed across several psprite layers; models its floor pickup but not its first-person view | Tested — binds, classifies, animates |
| **DoomRL Arsenal** | Assembly weapons, many variants per gun | Tested — binds, classifies, animates |
| **Guncaster** | ZScript weapons rather than DECORATE | Under audit |
| **MetaDoom** | Weapons evolve and upgrade mid-game | Under audit |
| **Trailblazer** | Elaborate reload and alt-fire animations | Tested — binds, classifies, animates |

"Binds" means the models attach and are pickable. "Animates" means fire and
reload play against that weapon's own timing.

The audit is reading each mod's weapon definitions to test the five assumptions
the animation rests on: that idle calls `A_WeaponReady`, that it isn't called
mid-action, that ammo changes observably during a reload, that fire uses bright
frames, and that one action is one sequence. Any mod that breaks the third one
breaks silently — the reload plays as an idle pose and nothing errors.

Results and per-mod fixes will be recorded here as they land.

---

## Known limits

**States reached only by runtime jumps are unmapped.** The sequence walk follows
`NextState` (which encodes `Goto`), but a state entered *only* through an `A_Jump*`
side effect — a reload-done tail behind an inventory check, a mod-custom combo label —
is invisible to it. The model holds its last mapped pose through such states and resumes
the moment their logic returns to mapped territory. In practice these are short tails;
a held pose reads as a pause.

**Some models have no reload animation.** Knives, chainsaws, fists, the
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
## Layout

```
zscript.txt                  donor stubs + includes
zscript/
  RS_ForeignModels.zs        scanner, classifier, binder, telemetry
  RS_ForeignRemap.zs         label walk, group mapping, self-healing table
  RS_ForeignAnim.zs          clip table, expansion, per-hand state
  RS_ForeignPersist.zs       the picks archive
  RS_ForeignModelsMenu.zs    picker + scan report
modeldef                     32 donor blocks, one per model
models/                      the meshes and skins
tools_gen_bd21.ps1           generates the BD21 shelf from BD's own MODELDEFs
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

Frame-accurate animation needs things stock GZDoom can't do. There are **three**
additions, and they build on each other.

### 1. Direct model frame addressing (`ModelFrame`)

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
blending.

### 2. Native state remap — the animation clock

Writing a frame number every tic from script makes the *script* the animation clock, with
everything that implies: tick ordering, event timing, and silent failure when any link
breaks. Instead the engine owns a per-instance table.

- **`DActorModelData` gains `TMap<intptr_t, int64_t> stateRemap`** — `FState*` keyed,
  mapping to two packed non-negative int32s, `(frame << 32) | next`. Not serialized;
  binds re-register it.
- **Two ZScript natives on `Actor`:** `RegisterModelStateFrame(State, int, int)` and
  `ClearModelStateFrames()`. Registration requires `modelData`, so `A_ChangeModel` must
  run first.
- **Two consult points in `models.cpp`,** both shared by VR and flat, mainhand and
  offhand. `CalcModelFrame` derives interpolation from the state's own tic countdown plus
  the renderer's frame fraction — display rate, not 35Hz. `CalcModelOverrides` resolves
  the frame numbers from the table, placed *after* the §1 fields so a live table beats
  stale serialized values.
- **`rs_remap_dump` ccmd** — per hand: weapon class, table size, and whether the state in
  the psprite *right now* resolves.

### 3. Full state-label enumeration

`FindState` can only probe label names known in advance, which makes every mod-custom
label invisible to a script-side walk — and DECORATE-era mods keep their real animations
behind exactly those. The class's own label table has all of them:

```
clearscope native static int CountStateLabels(class<Actor> cls);
clearscope native static Name, State GetStateLabelAt(class<Actor> cls, int index);
```

Returned **sorted by state address**, which is source declaration order. That ordering is
the whole point: it lets the walker attribute each custom label to the standard label it
was written under, with no name heuristics. `clearscope` because these are pure reads of
static class data — play scope fails to compile from the builder's data context.

**[`ENGINE_CHANGES.md`](ENGINE_CHANGES.md) is the full patch** for §1 — every file, every
function, the exact code, and the one signature change that fails as a *link* error
rather than a compile error if you miss it. §2 and §3 are documented in the fork's own
`FORK_CHANGES.md` under "Native state remap".

---

## Running on stock GZDoom or QuestZDoom — the static-model port

None of the above is needed if you don't need *animation*. The binding half — putting the
right 3D model in your hands on any mod's weapons — is **stock-compatible**, and that's
the whole feature for a Quest build where a static model beats a flat sprite regardless.

`A_ChangeModel` is stock as of GZDoom 4.11, so the parts that already work anywhere are:
the scanner, the archetype classifier, provenance filtering, the picker menu, pick
persistence, Assign All / Randomize, and the per-instance model bind itself.

The psprite pin (`psp.Sprite`/`psp.Frame` set to the donor's anchor) is stock behaviour
and stays: it's what makes `FindModelFrame` resolve. Each model then renders at its
anchored rest frame permanently — a correct, well-oriented 3D weapon that doesn't move.

### What it loses

Animation, and the overlay painting that depends on the same frame table. A weapon
reloads with the sound and the timing and the ammo, wearing a model that holds still.

### Size

Both pk3s are the same ~27 MB, because the models are the whole budget and they are
identical. If a phone-class build ever needs to be smaller, the lever is the shelf table
in `RS_ForeignModels.zs` — fewer rows per family means fewer meshes to ship, and nothing
else in the mod has to change.

---

