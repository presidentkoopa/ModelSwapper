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
| **Randomize — One-Handed** | Slaps a random pistol, revolver or smg model on every weapon in the list in one press — a varied loadout instead of dialling in each one by hand. |
| **Forget Learned Timing** | Clears measured animation timing. Use it if a mod update changed how a weapon moves. |
| **Forget Saved Models** | Clears saved model choices, back to auto-picked everywhere. |
| **List Unbound Weapons** | Shows weapons with no slot binding — normally the Heretic, Hexen, Strife and Chex arsenals the engine compiles into every session. |

Models swap in your hands as you cycle, so choosing is looking rather than guessing.

Set the family to **`any`** to pick from all fifty models regardless of archetype. A
chainsaw on a rocket launcher is a legitimate thing to want.

**Picks are remembered between sessions, per mod, with no profile system to manage.**
Every choice — yours or Randomize's — is saved keyed on the foreign weapon's class name.
Since only one mod's weapon classes exist in the world at a time, that name is already
scoped to whichever mod is loaded: load Ashes, pick models, quit; load Golden Souls, pick
different ones; go back to Ashes next week and its picks are still there, because Golden
Souls never wrote an entry under Ashes' class names. (Two different mods reusing an
identical class name would collide — the same tradeoff the learned-timing archive already
makes, and for the same reason: rare enough in practice that neither guards against it.)

---

## What's in it

**50 donor models across four sets**, and the picker names which set each came from
so cycling is a style choice rather than a shape hunt.

| Set | Models | Character |
|---|---|---|
| **VanAlek** | 14 | Doom's own arsenal, cleanly modelled |
| **Bv21** | 16 | BrutalDoomV21 — broader, includes railgun and flamethrower |
| **MeatG** | 9 | MeatGrinder — grittier, short meshes |
| **BWolf** | 11 | Brutal Wolfenstein — real WW2 small arms |

Thirteen families, four to six models each. Every family has options; nothing is
ever left unmodelled.

No donor ships a sprite. Every one anchors on a stock Doom sprite name that any IWAD
already has. The only sprite in the pk3 is `RSB0`, the ballistic round below — a name
that is ours and overrides nothing.

**Optional: bullets that travel.** Off by default, on its own menu page, and the only
thing here that changes how a mod *plays* rather than how it looks. See below.

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
| **Brutal Doom v22** | Heavy state machines, reload system | Under audit |
| **DoomRL Arsenal** | Assembly weapons, many variants per gun | Under audit |
| **Guncaster** | ZScript weapons rather than DECORATE | Under audit |
| **MetaDoom** | Weapons evolve and upgrade mid-game | Under audit |
| **Trailblazer** | Elaborate reload and alt-fire animations | Under audit |

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

**Reload timing is rate-scaled, not just fitted.** A single locked duration used to mean
a six-shell tube reload and a one-shell top-up — the same entry state, wildly different
real lengths — couldn't both look right off one number; whichever kind got observed
first is the one that matched. Reload durations now carry the ammo the locked run
actually restored alongside the tic count, so a future reload scales that duration by how
much *it* is missing rather than replaying a fixed length regardless.

Not every reload scales with how much ammo is gone. Most fixed-magazine weapons —
pistols, SMGs, rifles — eject whatever's left and load a fresh mag either way, same
motion, same duration, whether one round or the whole mag was missing. Scaling *those*
would predict a short partial reload from a long full one and rush the model through the
clip early, then leave it frozen for what's left — worse than not scaling at all. So the
rate is never assumed from one observed reload; it has to be **earned**, across the
learning window, by two runs that actually restored different amounts *and* took
different amounts of time to do it. No such evidence, on a fixed-mag weapon or a
shotgun-style one the player just always ran dry before reloading — and that entry keeps
flat-duration timing permanently, same as before rate scaling existed. This is derived
from behavior alone, never from what kind of weapon it is; nothing here knows or asks
whether something is a shotgun. Fire and altfire never scale this way regardless — ammo
drops there, it doesn't rise, so nothing about this touches them.

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

**Converted shots have no fire haptic.** `P_LineAttack`'s controller vibration
(`vrmode->Vibrate`, `VR_HapticEvent`) runs *after* the `WorldHitscanPreFired` hook this
mod cancels on, so a shot rebuilt as a projectile skips the rumble a normal hitscan gets.
Fixing it means reordering two blocks in `p_map.cpp` — an engine change, not a pk3 one —
so it's left as a known gap rather than worked around here.

---

## Ballistics — the one feature that isn't cosmetic

*Options → Weapon Model Swap Program → Ballistics.* Off by default.

Turn it on and every hitscan the **player** fires becomes a real projectile: a glowing
round that leaves the muzzle, streaks downrange, and arrives after the sound does. It can
be led, it can be dodged, and at long range it can be outrun.

Damage, damage type, range and impact are untouched. The shot carries the mod's own
damage value, and on impact it spawns **the mod's own puff** — so their decals, sparks
and ricochet sounds all still happen. Only the instantaneous part is gone.

**What it deliberately leaves alone:**

| | Why |
|---|---|
| Monster hitscans | Converting those would make every enemy in the game dodgeable. Players only. |
| Melee | `LAF_ISMELEEATTACK`, plus a 96-unit range floor for the many mods that punch with a plain short-range `LineAttack` and no flag. |
| Zero-damage traces | `P_LineAttack` is also how the engine and half of ZScript answer *"what am I pointing at"* — autoaim, target readouts, tracer setup. Cancelling one of those returns `nullptr` and the caller silently loses its answer. |

In VR the round is spawned from `AttackPos`/`AttackDir` — the controller, not the eye —
rather than from your face.

**The muzzle.** The engine has no concept of one. `AttackPos` is the raw controller
transform origin (`hw_vrmodes.cpp`, `GetWeaponTransform`) — the grip, in your fist.
Every hitscan in the game has always started there; it just never showed,
because an instant shot has no visible origin. Give the shot a travelling round and it is
suddenly, obviously coming out of the handle.

Nothing exposes the real barrel length — MD3 geometry isn't reachable from ZScript, and
MODELDEF carries scale and offset but no extent. What *is* available is the classifier:
every bound weapon already has an archetype, and barrel length tracks family closely
enough that a per-family figure lands far better than one global number. **Muzzle Trim**
adjusts whatever's left.

The offset is walked forward along the *aim*, not along facing, so it stays right with the
gun pointed up or down — and it's traced first, so standing against a wall or with a
Pinky's face in the barrel clips it short instead of spawning the round on the far side of
what you're shooting at.

**The honest cost:** a mod's balance assumes its hitscan lands instantly and always.
Travel time means shots miss movers that instant ones would have hit, and a weapon's feel
changes at range. That is the point of the feature and also its risk, which is why it is
opt-in and why the speed is a slider.

A twenty-pellet shotgun blast converts all twenty pellets — half-travelling and
half-instant would be worse than either — but only the first eight per tic draw a trail.

**No dynamic lights.** `RSB0`, vendored from RS_Main, is a genuinely tiny source image —
5×5 to 15×15px, no soft radial falloff baked in — which reads fine at ordinary Doom
viewing distance but can read as a small hard-edged square up close in VR. A `PointLight`
attached to the round was tried as a fix and pulled: this mod doesn't carry dynamic
lights.

The fix that stayed is texture-only: `MS_BallisticGlow`, a second, much bigger (`1.1`),
much fainter (`0.22` alpha) copy of the same sprite, additively stacked directly behind
the sharp one — one riding along with the round for its whole flight, one paired with
every trail bit. A single hard-edged texture still has a hard edge; several overlapping
copies at different sizes and low alpha blur that edge out through sheer accumulation —
the trick behind most halo/flare sprites that predate dynamic lighting entirely. No
lighting engine involvement, no cost to nearby geometry, nothing added to GLDEFS.

**No engine change is needed for this.** `WorldHitscanPreFired` is stock, it is
cancellable, and `P_LineAttack` is the single funnel every hitscan in the game passes
through.

### Bullet Time X compensation

On the same page, and inert unless [Bullet Time X](https://www.moddb.com/mods/bullet-time-x)
is loaded alongside. Detection is by cvar, not by class — we never name one of its types.

Every "multiplier" in that mod is a **divisor**: monsters get `vel /= bt_multiplier`, the
player gets `speed /= bt_player_movement_multiplier`. A higher player multiplier means a
*slower* player, and the player's advantage is however much smaller their divisor is than
the world's. The slider runs edge to edge, no dead zone:

| | |
|---|---|
| **0.0** | player divisor = world divisor — as slow as the monsters |
| **1.0** | player divisor = `1` — normal movement while the world crawls |

Linear in between, and both ends load-bearing. There used to be a third anchor at `1.0`
for "the mod's own configured value, untouched," with the normal-speed anchor pushed out
to `2.0` — dropped, because Bullet Time X ships with both divisors at `4`
(`bt_multiplier` and `bt_player_movement_multiplier`), so on a stock config that middle
anchor and the `0.0` anchor were the same number and the *entire bottom half of the
slider did nothing.* This version only ever depends on the world's own divisor, read
live, which never degenerates that way.

**`1.0` is already the fastest their own cvar can express** — Bullet Time X clamps its
player divisor to `1..20`, and `1` *is* normal speed, there's no faster setting to reach
for a true double-speed player. This isn't a compromise; it's their own ceiling.

**The slider defaults to `0.0`** — Bullet Time X's own out-of-the-box behavior, since
their shipped defaults already put the player divisor equal to the world divisor. That
means flipping **Enable** on by itself changes nothing; the slider has to actually move
above `0.0` before this does anything different from what Bullet Time X would have done
anyway.

All four of its slowdown profiles move together — normal, dodge, berserk, berserk-dodge —
since compensating only the first would leave a dodge feeling nothing like the bullet time
it interrupts. A profile whose world divisor is `0` (total freeze) is skipped: there is no
honest "as slow as the monsters" when the monsters are stopped dead.

The originals are captured into a cvar before anything is written, so quitting with
compensation on can't strand their settings overwritten. Turn it off before editing Bullet
Time X's own player-speed options, or this will overwrite them.

---

## Layout

```
zscript.txt                  donor stubs + includes
zscript/
  RS_ForeignModels.zs        scanner, classifier, binder, animation driver
  RS_ForeignAnim.zs          clip table, expansion, per-hand state
  RS_ForeignModelsMenu.zs    picker + scan report
  RS_ForeignBallistic.zs     hitscan -> projectile, and the round itself
  RS_ForeignBulletTime.zs    Bullet Time X compensation (inert without it)
modeldef                     51 donor blocks
models/                      the meshes and skins
sprites/                     RSB0 — the ballistic round, and nothing else
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
blending.

**[`ENGINE_CHANGES.md`](ENGINE_CHANGES.md) is the full patch** — every file, every
function, the exact code, and the one signature change that fails as a *link* error
rather than a compile error if you miss it. Five edits across six files, all confined to
the HUD path; world models are untouched. It's written so someone can apply it to their
own GZDoom build without reading this mod's source.

---

## Requirements

GZDoom 4.11+ for `A_ChangeModel`. The DoomXR fork for animation.

## Asset licensing

The code here is ours. **The models are not** — they come from several weapon packs:
Brutal Doom v21 (the Bv21/`MS_GH_` set), MeatGrinder (credited in the source modeldef to
`BR_VR_MeatGrinder`), Alek's Doom Guns and Ermac's Vanilla Doom Guns (together, the
VanAlek set), and the Brutal Wolfenstein VR weapons. Their licenses have not been
established. Sort that out before making this repository public or redistributing the
pk3.
