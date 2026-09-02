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
// The round.
//
// FastProjectile because it moves fast enough that ordinary projectile
// stepping would tunnel through thin geometry.
//
// NO TRAIL. FastProjectile will draw one for free -- set MissileType and
// Effect() spawns that actor at every movement substep -- and this used
// to. It is deliberately not set now: the point of the feature is that a
// shot takes time to arrive, not that it paints a line showing where it
// went. A streak reads as a tracer round, which is a different thing, and
// in a headset it is a bright object crossing your view every time you
// pull the trigger.
//
// The round itself is stock PUFF, so this ships no sprites of its own.
//
// Tick() survives in a much smaller form because the engine has no notion
// of a projectile that expires at a distance. A hitscan stops at
// AttackDistance; without this the round would fly until it hit
// something, which is a different weapon.
// ---------------------------------------------------------------------
class MS_Ballistic : FastProjectile
{
	// Their puff, kept so it can still be spawned at the point of impact.
	// The whole mod's premise is that their effects keep running; a
	// converted shot must still leave their decal, their spark, their
	// ricochet sound.
	Class<Actor> storedPuff;

	// A hitscan stops at AttackDistance. The round has to as well, or a
	// short-range shot turns into one that carries across the map.
	double maxRange;
	double travelled;
	Vector3 lastPos;
	bool    hasLastPos;

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
		Scale 0.4;
		Projectile;
		+THRUSPECIES
		+BRIGHT
		Species "Player";
		RenderStyle "Add";
		Alpha 0.9;
	}

	override void Tick()
	{
		Super.Tick();
		if (++age > MAX_LIFETIME) { Destroy(); return; }
		if (!hasLastPos) { lastPos = Pos; hasLastPos = true; return; }

		double d = (Pos - lastPos).Length();
		lastPos = Pos;
		if (d < 0.1) return;

		// Out of range. A hitscan that reaches its limit without hitting
		// anything spawns no puff, so neither do we -- just stop existing.
		travelled += d;
		if (maxRange > 0 && travelled > maxRange) Destroy();
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
		PUFF A 1 Bright;
		Loop;
	Death:
		TNT1 A 1 { SpawnStoredPuff(); }
		Stop;
	}

	// Which round class rs_fm_ballistic_type selects. Type 1 is this class;
	// Which round class rs_fm_ballistic_type selects. Type 1 is this class;
	// 2 to 5 are the four ported from Hideous Farrago below.
	static string TypeClass()
	{
		CVar c = CVar.FindCVar("rs_fm_ballistic_type");
		int t = c ? c.GetInt() : 1;
		switch (t)
		{
		case 2:  return "MS_Ballistic_ZDoom";
		case 3:  return "MS_Ballistic_LPUF";
		case 4:  return "MS_Ballistic_DPUF";
		case 5:  return "MS_Ballistic_Layered";
		default: return "MS_Ballistic";
		}
	}
}

// ---------------------------------------------------------------------
// THE OTHER FOUR ROUNDS -- ported from Hideous Farrago's
// hf_ballistic_fx.zs: VR_ZDoomBullet, VR_LPUFBullet, VR_DPUFBullet and
// HF_LayeredBullet, in that order. Scales, alphas, trail densities and
// timings are HF's, carried over rather than reinvented.
//
// WHAT CHANGED IN THE PORT, and only this:
//
//  - PARENT. HF's sit on VR_BaseBullet; ours sit on MS_Ballistic, so
//    each keeps the stored puff on impact, the range cutoff and the
//    lifetime backstop. HF hands its Death to its own VR_GlowPuff; ours
//    has to hand it back to whatever mod is loaded, so every Death here
//    calls SpawnStoredPuff() where HF called SpawnPuff.
//
//  - SPRITE. HF draws these on LPUF and DPUF. Its own
//    ASSET_PROVENANCE.md files both as rips -- LPUF from GunBonsai,
//    DPUF from Dakka -- marked RIP-UNTIL-CLEARED with a standing TODO to
//    replace them. They are not ours to ship, so all four draw on the
//    stock PUFF instead. Point these four letters at real art later and
//    it is one line each.
//
// Everything else -- damage, speed, range, the puff the mod gets back --
// is identical across all five types.
// ---------------------------------------------------------------------

// ===================================================================
// TYPE 2 -- ZDOOM BULLET. HF's VR_ZDoomBullet: a small clean round with
// nothing trailing it.
// ===================================================================
class MS_Ballistic_ZDoom : MS_Ballistic
{
	Default
	{
		Scale 0.08;
		Alpha 0.95;
		RenderStyle "Add";
	}
	States
	{
	Spawn:
		PUFF A 1 Bright;
		Loop;
	Death:
		TNT1 A 0 { SpawnStoredPuff(); }
		PUFF ABCD 2 Bright A_FadeOut(0.2);
		Stop;
	}
}

// ===================================================================
// TYPE 3 -- LPUF BULLET. HF's VR_LPUFBullet: a glowing streak, drawn by
// the engine. MissileType is FastProjectile's own trail hook -- Effect()
// spawns one of these at every movement substep, so the line is
// continuous however fast the round is travelling.
// ===================================================================
class MS_Ballistic_LPUF : MS_Ballistic
{
	Default
	{
		MissileType "MS_LPUFTrail";
		MissileHeight 8;
		RenderStyle "Add";
		Scale 0.4;
		Alpha 0.9;
	}
	States
	{
	Spawn:
		PUFF A 1 Bright;
		Loop;
	Death:
		TNT1 A 0 { SpawnStoredPuff(); }
		PUFF ABCD 2 Bright;
		Stop;
	}
}

class MS_LPUFTrail : Actor
{
	Default
	{
		Speed 0;
		Scale 0.4;
		Alpha 0.75;
		RenderStyle "Add";
		+NOBLOCKMAP +NOGRAVITY +NOTELEPORT +CANNOTPUSH +NODAMAGETHRUST
	}
	States
	{
	Spawn:
		// Shrink AND fade together, so the streak tapers as it dies
		// rather than blinking out at a uniform width.
		PUFF A 1 Bright
		{
			A_SetScale(scale.x - 0.04, scale.y - 0.04);
			A_FadeOut(0.12);
			if (scale.x <= 0.05) Destroy();
		}
		Loop;
	}
}

// ===================================================================
// TYPE 4 -- DPUF BULLET. HF's VR_DPUFBullet: two-frame round in flight,
// and four bouncing sparks thrown backwards where it lands.
// ===================================================================
class MS_Ballistic_DPUF : MS_Ballistic
{
	Default
	{
		RenderStyle "Add";
		Scale 0.4;
		Alpha 0.9;
	}
	States
	{
	Spawn:
		PUFF A 0 NoDelay;
		PUFF A 1 Bright;
		PUFF B 1 Bright;
		Loop;
	Death:
		TNT1 A 0
		{
			for (int i = 0; i < 4; i++)
				A_SpawnItemEx("MS_DakkaSpark", 0, 0, 0,
					frandom(3.0, 12.0), frandom(-4.0, 4.0), frandom(0.5, 8.0),
					180 + frandom(-30, 30), SXF_CLIENTSIDE);
			SpawnStoredPuff();
		}
		Stop;
	}
}

class MS_DakkaSpark : Actor
{
	Default
	{
		+CLIENTSIDEONLY
		+THRUACTORS
		+BOUNCEONWALLS
		+FORCEXYBILLBOARD
		+DONTSPLASH
		+NOTRIGGER
		Projectile;
		-NOGRAVITY
		Radius 1; Height 1;
		Gravity 0.5;
		BounceFactor 0.1;
		RenderStyle "Add";
		Scale 0.25;
	}
	States
	{
	Spawn:
		PUFF A 105 Bright;
		Stop;
	}
}

// ===================================================================
// TYPE 5 -- LAYERED. HF's HF_LayeredBullet: six particles strung out
// behind the round every tic, plus a faint cloud on top of it. Stays
// continuous at speeds that would otherwise strobe, and the densest of
// the four.
//
// THE ONE THING THAT IS NOT HF'S. HF spaces the six by VELOCITY --
// pos - vel * (i * 0.14), so the tail reaches 0.84 of a tic's travel
// behind the round. That is fine in HF, which flies these at Speed 160
// from the player's eye. It is not fine here. We default to 300 units
// per tic, so the same fractions reach 252 units back; and our round is
// spawned at the muzzle of a tracked controller, not inside the
// player's head. On the round's very FIRST tic it has not travelled
// yet, so all six land 252 units behind a gun held at arm's length --
// which is to say through the player's face and out behind them.
//
// So the tail is strung along the gap the round has ACTUALLY flown,
// pos back to lastPos, which the range counter already tracks. Before
// the round has moved that gap is zero and the six stack at the muzzle,
// invisible. After it has moved they fill exactly the space it crossed,
// which is what a wake is for. Identical to HF wherever HF's own
// assumption held, and it can no longer paint anything behind the gun.
// ===================================================================
class MS_Ballistic_Layered : MS_Ballistic
{
	Default
	{
		RenderStyle "Add";
		Scale 0.5;
		Alpha 0.95;
		+BRIGHT
	}
	States
	{
	Spawn:
		PUFF A 1 Bright
		{
			// The gap the round actually crossed since the last tic.
			// Zero on the first one, which is the whole point.
			Vector3 back = hasLastPos ? (lastPos - pos) : (0, 0, 0);
			for (int i = 1; i <= 6; i++)
			{
				double f = i / 7.0;
				Actor p = Spawn("MS_LayerTrailParticle",
					pos + back * f, ALLOW_REPLACE);
				if (p)
				{
					p.scale = (0.42 - i * 0.05, 0.42 - i * 0.05);
					p.A_SetRenderStyle(0.9 - i * 0.1, STYLE_Add);
				}
			}
			Spawn("MS_LayerCloud", pos, ALLOW_REPLACE);
		}
		Loop;
	Death:
		TNT1 A 0 { SpawnStoredPuff(); }
		PUFF ABCD 2 Bright;
		Stop;
	}
}

class MS_LayerTrailParticle : Actor
{
	Default
	{
		+NOINTERACTION +CLIENTSIDEONLY +FORCEXYBILLBOARD +NOGRAVITY
		RenderStyle "Add";
		Scale 0.3;
	}
	States
	{
	Spawn:
		PUFF B 3 Bright A_FadeOut(0.2);
		Loop;
	}
}

class MS_LayerCloud : Actor
{
	Default
	{
		+NOINTERACTION +CLIENTSIDEONLY +FORCEXYBILLBOARD +NOGRAVITY
		RenderStyle "Add";
		Scale 0.6;
		Alpha 0.06;
	}
	States
	{
	Spawn:
		PUFF C 4 Bright A_FadeOut(0.015);
		Loop;
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
	// switch() on a String won't compile -- ZScript's switch takes only an
	// int or a Name (FxSwitchStatement::Resolve casts anything else through
	// FxIntCast, which rejects a String with "Numeric type expected"). A
	// plain if/else chain on String == String works fine.
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
		// melee, saw, axe never reach here -- melee shots are not converted.
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

		let b = MS_Ballistic(Actor.Spawn(MS_Ballistic.TypeClass(), origin, ALLOW_REPLACE));
		if (!b) return false;   // could not spawn -- let the hitscan happen

		b.target      = shooter;
		b.angle       = ang;
		b.pitch       = pit;
		b.storedPuff  = e.AttackPuffType;
		b.maxRange    = e.AttackDistance;
		b.DamageType  = e.DamageType;
		b.SetDamage(e.Damage);

		// Seed the range counter at the muzzle. Without this the
		// round's first Tick has nothing to interpolate from and the streak
		// begins a whole tic downrange -- up to ninety units of gap between
		// the gun and its own tracer, which in VR reads as the two being
		// unrelated.
		b.lastPos    = origin;
		b.hasLastPos = true;

		double spd = MS_Speed();
		b.speed = spd;
		b.Vel = (cos(ang) * cos(pit), sin(ang) * cos(pit), -sin(pit)) * spd;

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
