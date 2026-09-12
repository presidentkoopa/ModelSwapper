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
// this mod replaces pixels and nothing else. This is the only thing that
// crosses that line, so it is opt-out and it says so in the menu.
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

	// WHAT WE MOVED AND WHAT WE LET PAST, one line per class, once each.
	//
	// The detector is deliberately mod-agnostic, so trying it against
	// another mod validates it but cannot discover the NEXT thing of this
	// shape. This can. Every actor that spawned next to the eye while the
	// weapon was working gets reported with the reason it was moved or
	// skipped, so simply playing anything produces the list -- including
	// the false positives, which are the dangerous half.
	//
	// The known gap it should surface first: a missile is skipped on
	// purpose, because a thrown grenade has to leave from where the mod
	// aimed it. A mod that draws its TRACER as a missile from the eye is
	// the same bug wearing a different flag, and there is no way to tell
	// those two apart from here. Seeing one named in this log is what
	// would justify doing something about it.
	Array<string> mReported;

	// WHY WE DID NOTHING. Every gate below can silently disable the whole
	// feature, and silence is indistinguishable from "there was nothing to
	// move" -- which is exactly how the first build of this shipped
	// looking like it worked. Each reason announces itself once.
	string mLastGate;

	void Gate(string why)
	{
		if (!RS_ForeignRemap.DebugOn()) return;
		if (mLastGate == why) return;
		mLastGate = why;
		Console.Printf("\c[Brick][RSFX] standing down: %s", why);
	}

	void Armed()
	{
		if (!RS_ForeignRemap.DebugOn()) return;
		if (mLastGate == "armed") return;
		mLastGate = "armed";
		Console.Printf("\c[Green][RSFX] armed -- shift is %.1f,%.1f,%.1f units from the eye",
			mShift.x, mShift.y, mShift.z);
	}

	void Report(Actor a, string what)
	{
		if (!RS_ForeignRemap.DebugOn()) return;
		string key = what .. ":" .. a.GetClassName();
		if (mReported.Find(key) != mReported.Size()) return;
		mReported.Push(key);
		Console.Printf("[RSFX] %-7s %-28s %.0f units from the eye",
			what, a.GetClassName(), (a.Pos - mEye).Length());
	}

	// -----------------------------------------------------------------
	// HOW FAR PAST THE HAND THE MUZZLE IS. Moved here when the hitscan
	// converter was removed; this is the only caller left.
	//
	// The engine has no muzzle: a weapon acts from the controller's own
	// transform, which is the grip. MD3 geometry is not reachable from
	// ZScript, and MODELDEF carries scale and offset but no extent, so
	// nothing exposes a real barrel length. What we do have is the
	// classifier -- barrel length tracks weapon family closely enough
	// that a per-family figure beats one global number, and the slider
	// trims what is left.
	//
	// switch() on a String won't compile -- ZScript's switch takes only
	// an int or a Name -- so this is a plain if/else chain.
	// -----------------------------------------------------------------
	static double FamilyMuzzle(string arch)
	{
		if (arch == "pistol")       return 13;
		if (arch == "revolver")     return 15;
		if (arch == "smg")          return 17;
		if (arch == "grenade")      return 20;
		if (arch == "supershotgun") return 21;
		if (arch == "flamethrower") return 22;
		if (arch == "plasma")       return 23;
		if (arch == "unmaker")      return 23;
		if (arch == "bfg")          return 24;
		if (arch == "shotgun")      return 25;
		if (arch == "rocket")       return 26;
		if (arch == "launcher")     return 26;
		if (arch == "machinegun")   return 26;
		if (arch == "chaingun")     return 27;
		if (arch == "rifle")        return 28;
		if (arch == "railgun")      return 30;
		if (arch == "sniper")       return 31;
		// melee, saw, axe, sword: a swing throws nothing, so the figure
		// only has to be harmless.
		return 20;
	}

	static double MuzzleTrim()
	{
		CVar c = CVar.FindCVar("rs_fm_muzzle");
		double t = c ? double(c.GetInt()) : 0.0;
		if (t < -20) t = -20;
		if (t >  80) t =  80;
		return t;
	}

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
		if (!pmo) return;
		if (multiplayer) { Gate("multiplayer"); return; }

		// If there is no controller transform there is no displacement to
		// correct either, so say so rather than disappearing silently.
		if (!pmo.OverrideAttackPosDir) { Gate("no controller transform (OverrideAttackPosDir false)"); return; }

		// ONLY FOR WEAPONS WE MOVED. If the player is holding something we
		// did not paint, its effects are where its own author put them and
		// nothing here has any business touching them. This is also what
		// keeps the feature honest: we compensate for our own displacement
		// and nothing else.
		let h = RS_ForeignModelHandler.Get();
		if (!h) { Gate("no model handler"); return; }
		if (h.mLastMain == null) { Gate("no weapon is wearing one of our models"); return; }

		Weapon w = pi.ReadyWeapon;
		if (!w) { Gate("no ready weapon"); return; }
		if (w != h.mLastMain) { Gate("ready weapon is not the one we painted"); return; }

		// The eye: exactly the origin a mod builds its offsets from.
		mEye = (pmo.pos.x, pmo.pos.y, pi.viewz);

		// The muzzle: the controller's own transform, walked forward to
		// roughly where the barrel ends -- the engine has no notion of a
		// muzzle, and the archetype is the best estimate there is.
		double ang = pmo.angle;
		double pit = pmo.pitch;
		Vector3 d  = pmo.AttackDir(pmo, ang, pit);
		ang = d.x;
		pit = d.y;

		double reach = FamilyMuzzle(
			h.ArchetypeForClass("" .. w.GetClassName())) + MuzzleTrim();

		Vector3 muzzle = pmo.AttackPos;
		if (reach > 0)
			muzzle += (cos(ang) * cos(pit), sin(ang) * cos(pit), -sin(pit)) * reach;

		mShift     = muzzle - mEye;
		mHaveFrame = true;
		Armed();
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
		if (a.player)     return;
		if (a.bIsMonster) return;

		// Distance first for anything we might REPORT, so the log is not
		// flooded by every gib in the level -- only things that were
		// plausibly built from the view origin are worth naming.
		if ((a.Pos - mEye).Length() > EYE_RADIUS) return;

		if (a.bShootable)     { Report(a, "shoot");  return; }
		if (a.bMissile)       { Report(a, "missile"); return; }
		if (a is 'Inventory') { Report(a, "invent"); return; }

		Report(a, "MOVED");

		// Translate. Not reposition -- the mod's own offsets and its
		// velocity are already correct RELATIVE to where it thought the
		// gun was, so shifting the whole thing preserves the arc it drew.
		a.SetOrigin(a.Pos + mShift, false);
	}
}
