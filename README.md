# ModelSwapper

3D weapons for any Doom mod, made for playing in VR.

Load ModelSwapper after the weapon mod you already play, and the flat sprite guns in your hands become 3D models. Nothing else about the mod changes: its damage, sounds, timing and reloads all stay its own. The mod you loaded still does all the shooting. ModelSwapper only changes what you're holding.

## Why it matters in VR

In a headset, a sprite weapon is a flat picture hanging in front of your face. Everything around you has depth except the one thing you look at most. A 3D gun you can turn over in your hand is a large part of what makes Doom in VR feel real.

The usual way to get one is for someone to hand-author a model set for a specific mod: every weapon modelled, fitted to the hand and animated to that mod's timing. That is a lot of work for a single mod, and the Doom VR community is small. Most weapon mods will never get a set of their own, including ones people love.

ModelSwapper doesn't wait for that. It carries one shelf of models and fits it to whatever you load.

## How it works

ModelSwapper reads every weapon the loaded mods define and sorts each one into a family, such as pistol, shotgun, rifle or launcher. It goes by the weapon's name, its ammo and its parent class, and finally by the weapon slot it sits in, so nothing is left without a model. Each weapon then wears a model from its family.

The animation is driven by the weapon's own code. Every Doom weapon already reports what it is doing each tic through its states: ready, fire, reload, raise, lower. When a model is attached, ModelSwapper maps those states onto the model's frames, and from then on the model plays whatever the weapon is doing. A reload lasts exactly as long on the model as it does in the mod, a partial reload plays short, and the very first shot is already in time, with nothing to learn or calibrate.

Nothing in it is written for a particular mod, so a pack released tomorrow works the same way as one from 2016. It has been tested with vanilla Doom, Brutal Doom v21 and v22, Project Brutality 0.4.1, Ashes (all episodes), Golden Souls 1 and 2, DoomRL Arsenal, Trailblazer, Dakka, Combined Arms, Final Doomer, LegenDoom, Doomablo, BorderDoom, Complex Doom, Guncaster and MetaDoom, among others.

## Making it yours

The automatic pick is a starting point. Most weapons land in the right family, but some have no real-world counterpart. A trumpet that fires musical notes has no Doom archetype, so it gets whatever its slot suggests.

Options > Weapon Model Swap Program > Choose Models lists every weapon the mod gives you, with the ones the classifier had to guess sorted to the top. Put any model on any weapon. Your choices are saved per weapon and kept between sessions, in one archive shared by every mod you load, so a gun you set up once stays set up. For mods that ship the same gun many times over, one row per family keeps the list short, and Randomize puts a random pistol, revolver or SMG model on everything for a mixed loadout.

Fit In Hand moves and sizes every model at once, with separate position and angle adjustments for each hand. Muzzle flashes, which mods draw as flat sprites, can be faded out so they don't hang in the air beside a 3D gun. Brass and smoke can be moved onto the gun, because mods spawn them from the player's position, which in a headset means your face. There is also an optional ballistics mode that turns your hitscan weapons into rounds that travel and can be led and dodged, with damage, range and impact left as the mod made them.

## The models

38 models across 20 weapon families, built from 33 meshes (the rest are alternate finishes), about 29 MB in all. It is one good model per shape rather than everything that would fit, so it loads fast.

The meshes come from different authors and different mods, and none of them were made to sit in a tracked hand. Each was measured with the scripts in this repo and corrected where the measurements showed a problem.

The biggest fix was where each model sits. 25 of the 38 sat further from their own origin than the gun is long, each by a different amount, and each model's position setting was cancelling that out rather than placing the gun. It looked right until you adjusted something. Size and hand angles work around the model's origin, so scaling or tilting a gun swung it around a point that could be a gun-length away from your hand. Every mesh is now centred on its own origin, and every position was recalculated with a copy of the engine's own transform, so nothing moved on screen. Size and angle changes now act on the gun where it sits.

These are the renders the tools produced along the way. Each one shows top, side and front views. The green ring is the model's origin and the red box is the bounds stored in the file.

The Bolter, before and after:

![Bolter before centring](renders/Bolter_Bolter_before.png)
![Bolter after centring](renders/Bolter_Bolter_after.png)

The BFG, before and after:

![BFG before centring](renders/BFG_BFG9000_before.png)
![BFG after centring](renders/BFG_BFG9000_after.png)

All 33 are in renders/, and renders/sheets/ lays the before and after views side by side.

The same measuring turned up animation that was sitting unused in the meshes. The chaingun carries twelve frames of barrel spin that nothing played, because the model definition it came from was written for vanilla Doom's two-frame chaingun. The AE flamer had fourteen frames of reload, the Jackhammer a full reciprocating stroke, and the BFG a four-frame shot where only one frame had been used. All of them play now.

It also caught guns that pointed at the floor every time you drew them. Brutal Doom animates a weapon raise by swinging the gun up from below the screen, which works for a sprite but not for a model in your hand. Five models had no raise frame close to how you actually hold them, so they now snap straight into your hand.

## Tools

Everything used on the models is in this repo. The scripts need Python 3, and the renderer also needs Pillow.

- tools_md3_pitch.py reads an MD3 mesh and measures the angle of every frame.
- tools_md3_reorigin.py centres a mesh on its origin and verifies the result byte by byte.
- tools_md3_compensate.py works out the position setting that keeps a centred gun exactly where it was, using a copy of the engine's own transform.
- tools_reorigin_all.py runs both over every model and stamps each model definition so a block can never be adjusted twice.
- tools_md3_render.py draws the wireframe renders shown above.
- tools_clip_audit.py shows which frames each animation uses and which frames nothing plays.
- tools_pitch_audit.py finds raise and sprint frames that swing the gun away from its resting angle.
- tools_model_inventory.py writes a full inventory of every model: frames, poses, angles and animations.
- tools_gen_pickups.ps1 generates the pickup model definitions from the meshes.
- tools_gen_bd21.ps1 generates the Brutal Doom v21 shelf from Brutal Doom's own model definitions.
- tools_zs_lint.py checks the ZScript for syntax errors before build.ps1 packs anything.

## Which build

ModelSwapper.pk3 is the desktop VR build, for [UZDXREMA](https://github.com/presidentkoopa/UZDXREMA). Models are animated, reloads included.

ModelSwapper-QUEST.pk3 is for standalone Quest, on [QuestZDoom](https://github.com/emawind84/QuestZDoom). Same models and the same picker, but the models hold still, because animation needs engine features Quest doesn't have. Fit In Hand and the muzzle flash setting are engine features too, so they do nothing there.

Load either one after your weapon mod. To build them from source, run ./build.ps1, or ./build.ps1 -Static for the Quest build.

INTERNALS.md explains the binding, classification and animation in detail, along with what they can't do. ENGINE_CHANGES.md covers the engine changes the animation needs.
