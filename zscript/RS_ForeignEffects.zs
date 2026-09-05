// =====================================================================
// RS_ForeignEffects -- THEIR CASINGS COME OUT OF YOUR FACE. MOVE THEM.
//
// THE PROBLEM, and it is not a bug in anybody's mod. A weapon mod spawns
// its casings, smoke and ejection effects relative to the PLAYER, because
// on a monitor the player and the gun are the same place: the psprite is
// painted over the view, so "22 units forward and 20 up from the eye" IS
// the ejection port. Project Brutality's PB_SpawnCasing is the textbook
// version of it --
//
//     vertOfs -= (self.player.viewz - self.pos.z) / self.player.CrouchFactor;
//     Vector3 spos = PB_Math.RelativeToGlobalCoords(
//         (self.pos.xy, self.player.viewz),        // the EYE
//         (self.angle, self.pitch, self.roll),     // the HEAD
//         (xOfs, horOfs, vertOfs), true);
//
// -- and every mod that ejects brass does some version of the same thing.
//
// In a headset the two come apart. The gun is in a tracked hand and the
// eye is your face, so the brass leaves your cheekbone. Rotating the
// whole offset by head pitch is what makes it swing around as you look
// up and down, which reads as effects appearing at random heights.
//
// WHY THIS IS OURS TO FIX EVEN THOUGH IT IS NOT OUR CODE. The rest of
// this mod replaces pixels and nothing else. This crosses that line, and
// it is the second thing that does (the ballistic converter is the
// first), so it is opt-out and it says so in the menu.
//
// The justification is that we are the reason the gun moved. A flat
// sprite mod in VR draws the weapon at the eye too, so its effects line
// up with its own gun and nobody notices. The moment a model is placed
// in a tracked hand, the mod's own effects are left behind at the eye --
// by us. Putting them back on the gun restores what the author drew.
//
// HOW IT WORKS, and the one idea that makes it safe: TRANSLATE, NEVER
// REPOSITION. The mod worked out a position relative to the eye, with
// its own forward/side/up offsets and its own velocity arc. We do not
// recompute any of that. We add a single vector -- from the eye to the
// muzzle -- to whatever it decided. Every offset it authored survives,
// the velocity is untouched, and the ejection arc is identical to the
// one it drew, just starting from the gun. A casing that tumbled up and
// to the right still tumbles up and to the right.
//
// NO PER-MOD KNOWLEDGE. Nothing here names a mod, a class, or a sprite.
// The rule is positional and temporal: something small and non-solid
// appeared next to the player's eye within a few tics of the player
// working the weapon. That describes a casing in any mod ever written,
// and describes almost nothing else.
// =====================================================================
class MS_EffectRelocator : StaticEventHandler
{
	// The eye-to-muzzle vector, recomputed once a tic rather than once
	// per spawned actor. A firefight in a gore-heavy mod spawns hundreds
	// of actors a tic and WorldThingSpawned sees every one of them, so
	// everything expensive lives here and the spawn hook does distance
	// arithmetic and nothing else.
	Vector3 mEye;
	Vector3 mShift;
	bool    mHaveFrame;

	// Last tic the player was working the weapon -- trigger, alt trigger
	// or reload, either hand. Casings and smoke come out during the
	// animation, which outlives the button, so the window below is
	// generous.
	int mActionTic;

	// How long after the button a spawn still counts. Twelve tics is
	// about a third of a second: long enough for a slow bolt cycle or a
	// magazine change to finish ejecting, short enough that it has closed
	// again before anything unrelated happens.
	const ACTION_WINDOW = 12;

	// How close to the eye a spawn has to be. Mods offset their ejection
	// port a couple of feet from the view origin -- PB uses 22 forward and
	// 20 up -- so this has to clear that comfortably while still being
	// nowhere near arm's length. Anything further away was not computed
	// from the eye and is not ours.
	const EYE_RADIUS = 56.0;

	static bool Enabled()
	{
		CVar c = CVar.FindCVar("rs_fm_effects");
		return (c && c.GetBool());
	}

	// -----------------------------------------------------------------
	// ONCE A TIC: where is the eye, and how far is it to the muzzle.
	// -----------------------------------------------------------------
	override void WorldTick()
	{
		mHaveFrame = false;
		if (!Enabled()) return;

		PlayerInfo pi = players[consolePlayer];
		if (!pi || !pi.mo) return;

		// Note the button BEFORE the early-outs below, so a weapon we do
		// not paint still refreshes the window -- switching mid-burst
		// should not strand a stale action tic.
		int btn = pi.cmd.buttons;
		if (btn & (BT_ATTACK | BT_ALTATTACK | BT_RELOAD))
			mActionTic = level.maptime;

		let pmo = pi.mo;
		if (!pmo || !pmo.OverrideAttackPosDir || multiplayer) return;

		// ONLY FOR WEAPONS WE MOVED. If the player is holding something we
		// did not paint, its effects are where its own author put them and
		// nothing here has any business touching them. This is also what
		// keeps the feature honest: we compensate for our own displacement
		// and nothing else.
		let h = RS_ForeignModelHandler.Get();
		if (!h || h.mLastMain == null) return;

		Weapon w = pi.ReadyWeapon;
		if (!w || w != h.mLastMain) return;

		// The eye: exactly the origin a mod builds its offsets from.
		mEye = (pmo.pos.x, pmo.pos.y, pi.viewz);

		// The muzzle: the controller's own transform, walked forward to
		// roughly where the barrel ends. Same figures the ballistic
		// converter uses, for the same reason -- the engine has no notion
		// of a muzzle and the archetype is the best estimate there is.
		double ang = pmo.angle;
		double pit = pmo.pitch;
		Vector3 d  = pmo.AttackDir(pmo, ang, pit);
		ang = d.x;
		pit = d.y;

		double reach = MS_HitscanHandler.FamilyMuzzle(
			h.ArchetypeForClass("" .. w.GetClassName())) + MS_HitscanHandler.MuzzleTrim();

		Vector3 muzzle = pmo.AttackPos;
		if (reach > 0)
			muzzle += (cos(ang) * cos(pit), sin(ang) * cos(pit), -sin(pit)) * reach;

		mShift     = muzzle - mEye;
		mHaveFrame = true;
	}

	// -----------------------------------------------------------------
	// PER SPAWN: is this one of theirs, and is it next to my face.
	// -----------------------------------------------------------------
	override void WorldThingSpawned(WorldEvent e)
	{
		if (!mHaveFrame) return;
		if (level.maptime - mActionTic > ACTION_WINDOW) return;

		Actor a = e.Thing;
		if (!a) return;

		// WHAT WE WILL NOT MOVE, in cheapest-test-first order. Each of
		// these is something that legitimately appears near the player and
		// whose position means something to the game rather than to the
		// eye.
		//
		//   players and monsters -- obvious, and a spawned-in monster
		//     standing on you is not a casing
		//   anything shootable  -- it is a participant, not decoration
		//   inventory           -- a dropped weapon or a spawned pickup
		//                          belongs on the floor where it landed
		//   missiles            -- their trajectory is the gameplay; a
		//                          thrown grenade or a fired projectile
		//                          must leave from where the mod aimed it
		//   corpses and gibs    -- bIsMonster covers the actor, and gore
		//                          spawned by a kill next to you is not
		//                          ours even inside the window
		if (a.player)      return;
		if (a.bIsMonster)  return;
		if (a.bShootable)  return;
		if (a.bMissile)    return;
		if (a is 'Inventory') return;

		// Was it built from the eye? Everything a mod offsets off the view
		// origin lands within arm's reach of it. Compare in 3D: a casing
		// is above and in front, and the vertical part is most of what
		// separates it from something standing on the floor beside you.
		if ((a.Pos - mEye).Length() > EYE_RADIUS) return;

		// Translate. Not reposition -- the mod's own offsets and its
		// velocity are already correct RELATIVE to where it thought the
		// gun was, so shifting the whole thing preserves the arc it drew.
		a.SetOrigin(a.Pos + mShift, false);
	}
}
