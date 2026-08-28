// =====================================================================
// RS_ForeignWorldModels -- THE WORLD-ANCHORED HALF OF EVERY DONOR.
//
// These classes carry no behaviour. They exist so each donor has a
// MODELDEF block anchored on a sprite that works OUTSIDE the player's
// hands, sized for something seen at arm's length or further rather
// than filling the view.
//
// WHO ACTUALLY USES THEM. Not this mod. RS_Holsters displays a stored
// weapon by borrowing whatever model that weapon currently resolves to
// (level.GetActorModelClass), and for a ModelSwapper-swapped weapon that
// is one of our donors. But a donor's own MODELDEF is keyed to a HUD
// hand sprite -- PISG, CHGG, SHTG and the rest -- which a holster prop
// never wears, so every geometry query against it comes back not-found
// and nothing draws.
//
// RS_HolsterProp.ShowWeapon solves that by retrying against sprite SHOT
// frame 0, and it finds the right block by NAME: it takes the donor's
// class name, strips "MS_", and prepends "MS_PU_". That substitution is
// load-bearing and lives in someone else's file, so:
//
//     DO NOT RENAME THESE CLASSES. RS_Holsters derives the name.
//
// The floor-pickup binder these were originally built for is gone --
// ModelSwapper does not replace the weapon lying on the ground any more.
// The classes and their blocks stay because a second consumer turned up
// for them, which is also why the "PU" in the name now reads as archaic.
// It is kept anyway: the string substitution above is why.
//
// SAFE TO SUBCLASS, unlike the donor stubs in zscript.txt. Those must not
// be subclassed because FindModelFrameRaw's smff->type == ti is an exact
// class-pointer test, so a subclass inherits no model. The test still
// holds here -- it is just satisfied the other way round. This base owns
// NO modeldef block; each generated subclass owns its own, so each one
// matches itself exactly and the shared parent only carries the state and
// the inert flags.
// =====================================================================
class MS_PickupModel : Actor
{
	Default
	{
		+NOBLOCKMAP
		+NOGRAVITY
		+NOINTERACTION
		+DONTSPLASH
		+NOTONAUTOMAP
		Radius 1;
		Height 1;
	}

	States
	{
	Spawn:
		SHOT A -1;
		Stop;
	}
}
