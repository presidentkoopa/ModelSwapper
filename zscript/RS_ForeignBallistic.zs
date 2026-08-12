// =====================================================================
// RS_ForeignBallistic -- HITSCAN BECOMES A TRAVELLING ROUND.
//
// Every other feature here replaces pixels and nothing else: their code,
// their damage, their projectiles, their sounds all run untouched. This
// one deliberately crosses that line, and it is the only thing in the mod
// that does. It is off by default and stays off unless asked for.
//
// WHAT IT ACTUALLY DOES. GZDoom funnels every hitscan in the game through
// P_LineAttack, and P_LineAttack asks WorldHitscanPreFired first --
// returning true makes it return nullptr and the shot never happens
// (p_map.cpp, P_LineAttack). The event carries the angle, pitch,
// distance, damage, damage type and puff of the shot that was about to
// be fired, which is everything needed to send a real projectile down
// the same line instead.
//
// So this is a genuine conversion, not a cosmetic tracer chasing an
// instant hit. The bullet has travel time, can be outrun at range, and
// arrives after the sound does.
//
// WHAT IT COSTS, stated plainly because it is a real cost. A mod's
// balance assumes its hitscan lands instantly and always. Travel time
// means shots miss movers that instant ones would have hit, and a
// weapon's feel changes at long range. That is the point of the feature
// and also its risk, which is why it is opt-in.
//
// The round and its trail are vendored from RS_Main's ballistic FX
// (RS_FX_BallisticFired.zs) rather than depended on, so this pk3 stays
// standalone.
// =====================================================================

// ---------------------------------------------------------------------
// The round. FastProjectile because it moves fast enough that ordinary
// projectile stepping would tunnel through thin geometry.
// ---------------------------------------------------------------------
class MS_Ballistic : FastProjectile
{
	// Map units between trail bits. Spacing rather than a per-tic count:
	// a fixed count leaves gaps that get worse the faster the round
	// travels, and these move 30-90 units a tic.
	const TRAIL_SPACING = 12.0;

	// One pathological step -- a teleport, a huge first frame -- must not
	// cost a frame's worth of spawns.
	const TRAIL_MAX_PER_TIC = 24;

	// Where the round was at the end of the previous tic. The trail fills
	// the segment between there and here, so it cannot leave a gap however
	// fast the round is moving.
	Vector3 prevPos;
	bool    hasPrevPos;

	// Set on rounds spawned past the per-tic trail budget. A 20-pellet
	// shotgun blast still converts every pellet -- half-travelling,
	// half-instant would be worse than either -- but only the first few
	// draw streaks.
	bool noTrail;

	// Their puff, kept so it can still be spawned at the point of impact.
	// The whole mod's premise is that their effects keep running; a
	// converted shot must still leave their decal, their spark, their
	// ricochet sound.
	Class<Actor> storedPuff;

	// A hitscan stops at AttackDistance. The round has to as well, or a
	// short-range shot turns into one that carries across the map.
	double maxRange;
	double travelled;

	// maxRange retires a round that keeps moving. A round that stops moving
	// -- wedged in geometry, velocity zeroed by something in the mod -- would
	// otherwise sit there forever, so age retires that one.
	int    age;
	const  MAX_LIFETIME = 350;

	Default
	{
		Radius 2;
		Height 2;
		Speed 100;   // overridden on spawn from the shot being replaced
		Damage 5;    // likewise
		Projectile;
		+THRUSPECIES
		Species "Player";
	}

	override void Tick()
	{
		Super.Tick();
		if (++age > MAX_LIFETIME) { Destroy(); return; }
		if (!hasPrevPos) { prevPos = Pos; hasPrevPos = true; return; }

		Vector3 here = Pos;
		Vector3 seg  = here - prevPos;
		double  dist = seg.Length();
		prevPos = here;
		if (dist < 0.1) return;

		// Out of range. A hitscan that reaches its limit without hitting
		// anything spawns no puff, so neither do we -- just stop existing.
		travelled += dist;
		if (maxRange > 0 && travelled > maxRange) { Destroy(); return; }

		if (noTrail) return;

		int bits = int(dist / TRAIL_SPACING);
		if (bits < 1) return;
		if (bits > TRAIL_MAX_PER_TIC) bits = TRAIL_MAX_PER_TIC;

		for (int i = 0; i < bits; ++i)
		{
			// f runs 0 at the tail of this tic's segment to 1 at the head.
			double f = double(i + 1) / double(bits);
			Vector3 p = prevPos - seg + seg * f;

			let t = Spawn("MS_BallisticTrail", p, ALLOW_REPLACE);
			if (!t) continue;

			// Newest bit is biggest and brightest, older ones dimmer and
			// smaller. That taper is what gives the streak a readable
			// direction instead of a uniform line of dots.
			t.A_SetScale(0.16 + 0.20 * f);
			t.alpha = 0.35 + 0.55 * f;
		}
	}

	// Hand the impact back to whatever the mod was going to spawn. Pulled
	// back along the direction of travel so a wall hit does not bury the
	// puff inside the surface.
	void SpawnStoredPuff()
	{
		if (!storedPuff) return;
		Vector3 p = Pos;
		if (Vel.Length() > 0.01) p -= Vel.Unit() * 2.0;
		Spawn(storedPuff, p, ALLOW_REPLACE);
	}

	States
	{
	Spawn:
		RSB0 A 2 Bright;
		RSB0 B 2 Bright;
		RSB0 C 2 Bright;
		RSB0 D 2 Bright;
		RSB0 E 2 Bright;
		Loop;
	Death:
		TNT1 A 1 { SpawnStoredPuff(); }
		Stop;
	}
}

// ---------------------------------------------------------------------
// One bit of the trail. Additive so light stacks rather than blending --
// that is what makes it read as glowing instead of merely translucent.
// ---------------------------------------------------------------------
class MS_BallisticTrail : Actor
{
	Default
	{
		+NOINTERACTION +CLIENTSIDEONLY +FORCEXYBILLBOARD +NOGRAVITY +NOTIMEFREEZE
		RenderStyle "Add";
		Scale 0.30;
		Alpha 0.85;
	}
	States
	{
	Spawn:
		RSB0 B 2 Bright A_FadeOut(0.22);
		RSB0 C 2 Bright A_FadeOut(0.28);
		Stop;
	}
}

// ---------------------------------------------------------------------
// The interception. Deliberately its own handler and not folded into
// RS_ForeignModelHandler: the model binder is the mod's core and must
// keep working whatever this does, so nothing here can reach its state.
// ---------------------------------------------------------------------
class MS_HitscanHandler : StaticEventHandler
{
	// Below this, a "hitscan" is a punch, a kick, a bite, a chainsaw --
	// LAF_ISMELEEATTACK catches most of them, but plenty of mods swing a
	// fist with a plain short-range LineAttack and no flag. Sending a
	// flying round out of a melee weapon would be absurd, so range is the
	// backstop the flag misses.
	const MELEE_CUTOFF = 96.0;

	// How many rounds per tic may draw a trail. A shotgun firing twenty
	// pellets converts all twenty -- see MS_Ballistic.noTrail -- but only
	// the first few streak, which is all the eye reads anyway.
	const TRAIL_BUDGET = 8;

	int mTrailsThisTic;

	// ---------------------------------------------------------------------
	// MUZZLE OFFSET.
	//
	// The engine has no concept of a muzzle. AttackPos is the raw controller
	// transform origin (hw_vrmodes.cpp, GetWeaponTransform) -- the grip, in
	// your fist. Every hitscan in the game has always started there; it just
	// never showed, because an instant shot has no visible origin. Give the
	// shot a travelling round and suddenly it is obviously coming out of the
	// handle.
	//
	// There is nothing to read the real barrel length from. The MD3 geometry
	// is not reachable from ZScript, and MODELDEF carries scale and offset
	// but no extent. What we do have is the classifier: every bound weapon
	// already has an archetype, and barrel length tracks family closely
	// enough that a per-family figure lands far better than one global
	// number. The slider trims whatever is left.
	// ---------------------------------------------------------------------
	static double FamilyMuzzle(string arch)
	{
		switch (arch)
		{
		case "pistol":       return 13;
		case "revolver":     return 15;
		case "smg":          return 17;
		case "grenade":      return 20;
		case "supershotgun": return 21;
		case "flamethrower": return 22;
		case "plasma":       return 23;
		case "unmaker":      return 23;
		case "bfg":          return 24;
		case "shotgun":      return 25;
		case "rocket":       return 26;
		case "launcher":     return 26;
		case "machinegun":   return 26;
		case "chaingun":     return 27;
		case "rifle":        return 28;
		case "railgun":      return 30;
		case "sniper":       return 31;
		// melee, saw, axe never reach here -- melee shots are not converted.
		default:             return 20;
		}
	}

	static double MuzzleTrim()
	{
		CVar c = CVar.FindCVar("rs_fm_muzzle");
		double t = c ? double(c.GetInt()) : 0.0;
		if (t < -20) t = -20;
		if (t >  80) t =  80;
		return t;
	}

	override void WorldTick()
	{
		mTrailsThisTic = 0;
	}

	static bool Enabled()
	{
		CVar c = CVar.FindCVar("rs_fm_ballistic");
		return (c && c.GetBool());
	}

	override bool WorldHitscanPreFired(WorldEvent e)
	{
		if (!Enabled()) return false;

		Actor shooter = e.Thing;
		if (!shooter || !shooter.player) return false;   // players only

		// damage == 0 is a probe, not a shot. P_LineAttack is how the
		// engine and half of ZScript answer "what am I pointing at" --
		// autoaim, target readouts, tracer setup. Cancelling one returns
		// nullptr and the caller silently loses its answer, which breaks
		// mods in ways that look nothing like this feature.
		if (e.Damage <= 0) return false;
		if (e.AttackLineFlags & LAF_NOINTERACT) return false;

		// Melee stays melee.
		if (e.AttackLineFlags & LAF_ISMELEEATTACK) return false;
		if (e.AttackDistance <= MELEE_CUTOFF) return false;

		// Reproduce the origin and direction the hitscan itself would
		// have used. In VR the shot leaves the controller, not the eye,
		// so reading AttackPos/AttackDir is what makes the round come out
		// of the model's muzzle instead of the player's face.
		bool offhand = (e.AttackLineFlags & LAF_ISOFFHAND) != 0;
		double ang = e.AttackAngle;
		double pit = e.AttackPitch;
		Vector3 origin;

		let pmo = shooter.player.mo;
		if (pmo && pmo.OverrideAttackPosDir && !multiplayer)
		{
			Vector3 d;
			if (offhand)
			{
				origin = pmo.OffhandPos;
				d = pmo.OffhandDir(shooter, ang, pit);
			}
			else
			{
				origin = pmo.AttackPos;
				d = pmo.AttackDir(shooter, ang, pit);
			}
			// AttackDir returns the resolved aim as (angle, pitch),
			// not a direction vector.
			ang = d.x;
			pit = d.y;
		}
		else
		{
			// Same height the engine computes: centre, minus floorclip,
			// plus the pawn's attack offset scaled by crouch, plus the
			// caller's own z nudge.
			double shootz = shooter.pos.z + shooter.height * 0.5 - shooter.Floorclip;
			if (e.AttackLineFlags & LAF_OVERRIDEZ)
				shootz = shooter.pos.z;
			else
				shootz += MS_AttackZ(shooter);
			shootz += e.AttackZ;

			origin = (shooter.pos.x, shooter.pos.y, shootz);
			origin.xy += (cos(ang), sin(ang)) * e.AttackOffsetForward;
			origin.xy += (cos(ang - 90), sin(ang - 90)) * e.AttackOffsetSide;
		}

		// Walk the spawn point forward from the grip to roughly where the
		// barrel ends, along the aim rather than along facing, so it stays
		// right when the gun is pointed up or down.
		double reach = 0;
		Weapon fired = offhand ? shooter.player.OffhandWeapon : shooter.player.ReadyWeapon;
		if (fired)
		{
			let h = RS_ForeignModelHandler.Get();
			if (h) reach = FamilyMuzzle(h.ArchetypeForClass("" .. fired.GetClassName()));
		}
		reach += MuzzleTrim();

		if (reach > 0)
		{
			// Standing against a wall, or with a Pinky's face in the muzzle,
			// the offset would otherwise put the round on the far side of
			// what you are shooting at and the shot would simply miss. Trace
			// the gap first and stop short of whatever is in it. Absolute
			// start position, because the grip is nowhere near the player's
			// centre in VR.
			FLineTraceData d;
			bool blocked = shooter.LineTrace(ang, reach, pit,
				TRF_ABSPOSITION | TRF_SOLIDACTORS,
				origin.z, origin.x, origin.y, d);
			if (blocked) reach = max(0.0, d.Distance - 2.0);

			origin += (cos(ang) * cos(pit), sin(ang) * cos(pit), -sin(pit)) * reach;
		}

		let b = MS_Ballistic(Actor.Spawn("MS_Ballistic", origin, ALLOW_REPLACE));
		if (!b) return false;   // could not spawn -- let the hitscan happen

		b.target      = shooter;
		b.angle       = ang;
		b.pitch       = pit;
		b.storedPuff  = e.AttackPuffType;
		b.maxRange    = e.AttackDistance;
		b.DamageType  = e.DamageType;
		b.SetDamage(e.Damage);

		// Seed the trail's previous position at the muzzle. Without this the
		// round's first Tick has nothing to interpolate from and the streak
		// begins a whole tic downrange -- up to ninety units of gap between
		// the gun and its own tracer, which in VR reads as the two being
		// unrelated.
		b.prevPos    = origin;
		b.hasPrevPos = true;

		double spd = MS_Speed();
		b.speed = spd;
		b.Vel = (cos(ang) * cos(pit), sin(ang) * cos(pit), -sin(pit)) * spd;

		if (mTrailsThisTic >= TRAIL_BUDGET) b.noTrail = true;
		else ++mTrailsThisTic;

		return true;   // P_LineAttack returns nullptr; the shot is ours now
	}

	// AttackZOffset lives on PlayerPawn and is scaled by crouch, matching
	// AActor::AttackOffset in the engine.
	static double MS_AttackZ(Actor shooter)
	{
		let pp = PlayerPawn(shooter);
		if (!pp) return 8.0;
		return pp.AttackZOffset * shooter.player.crouchfactor;
	}

	static double MS_Speed()
	{
		double s = 90.0;
		CVar c = CVar.FindCVar("rs_fm_ballistic_speed");
		if (c) s = c.GetInt();
		if (s < 10)  s = 10;
		if (s > 400) s = 400;
		return s;
	}
}
