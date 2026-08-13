// =====================================================================
// RS_ForeignBulletTime -- BULLET TIME X COMPENSATION.
//
// A hook for one specific sideloaded mod, Bullet Time X. It does nothing
// at all unless that mod is loaded, and it detects it by its cvars rather
// than its classes -- we never name one of its types, never subclass it,
// never touch its handler. If it is absent, FindCVar returns null and
// every path here returns immediately.
//
// WHAT BULLET TIME X ACTUALLY DOES, because the naming is misleading.
// Every "multiplier" cvar in that mod is a DIVISOR:
//
//     monsters:  vel /= bt_multiplier                   (BulletTime.zs:840)
//     player:    speed /= bt_player_movement_multiplier (BulletTime.zs:985)
//
// So a HIGHER player multiplier means a SLOWER player, and the player's
// advantage during bullet time is however much smaller their divisor is
// than the world's. Setting the player's to 1 removes the slowdown from
// them entirely; setting it equal to the world's makes them exactly as
// slow as everything they are shooting at.
//
// THE SLIDER runs 0.0 to 1.0, both ends load-bearing, no dead zone:
//
//     0.0  player divisor = world divisor   -- as slow as the monsters
//     1.0  player divisor = 1               -- normal movement
//
// Linear in between. There used to be a third anchor at 1.0 for "the
// mod's own configured value, untouched" with a normal-speed anchor
// pushed out to 2.0 -- dropped, because Bullet Time X ships with both
// divisors at 4 (bt_multiplier and bt_player_movement_multiplier), so
// on a STOCK CONFIG that middle anchor and the 0.0 anchor were the same
// number and the entire bottom half of the slider did nothing. This
// version has no anchor that can degenerate like that: it only ever
// depends on the world's OWN divisor, read live, which is never 0 here
// (see below) and never equal to 1 -- their default is 4, and no target
// mod ships it at 1, because a world divisor of 1 is no slowdown at all.
//
// WORTH KNOWING: Bullet Time X clamps its own player divisor to 1..20
// (BulletTime.zs:359) -- 1 IS their fastest, "normal speed," there is no
// faster setting to reach for a true 2x. 1.0 on this slider is already
// the ceiling of what their own cvar can express, not a compromise.
//
// HOW IT APPLIES. Bullet Time X re-reads its cvars in initCvarVariables()
// every time bullet time starts (BulletTime.zs, doSlowTime). So the cvar
// only has to be correct before activation, not during -- writing it on a
// slow cadence is enough, and mid-activation writes would be ignored
// anyway.
// =====================================================================

class MS_BulletTime
{
	// Bullet Time X keeps four independent slowdown profiles -- normal,
	// dodge, berserk, and berserk-dodge -- each with its own world and
	// player divisor. Compensating only the first would leave a dodge
	// feeling nothing like the bullet time it interrupts, so all four
	// move together.
	const GROUPS = 4;

	static string WorldCVar(int i)
	{
		switch (i)
		{
		case 0:  return "bt_multiplier";
		case 1:  return "bt_dodge_multiplier";
		case 2:  return "bt_berserk_multiplier";
		default: return "bt_berserk_dodge_multiplier";
		}
	}

	static string PlayerCVar(int i)
	{
		switch (i)
		{
		case 0:  return "bt_player_movement_multiplier";
		case 1:  return "bt_dodge_player_movement_multiplier";
		case 2:  return "bt_berserk_player_movement_multiplier";
		default: return "bt_berserk_dodge_player_movement_multiplier";
		}
	}

	// s=0 -> world (as slow as everything else), s=1 -> 1 (normal speed).
	// Their own clamp range for a player divisor is 1..20 (BulletTime.zs:
	// 359); producing anything outside it would just be silently clamped
	// by them into a value we did not intend, so clamp it here too, where
	// it is visible.
	static int Target(double s, int world)
	{
		double v = world + (1.0 - world) * s;

		int r = int(round(v));
		if (r < 1)  r = 1;
		if (r > 20) r = 20;
		return r;
	}
}

class MS_BulletTimeHandler : StaticEventHandler
{
	// Cheap. The value only needs to be right at the moment bullet time
	// starts, and the player cannot move a menu slider between two tics.
	const REFRESH = 8;

	// Bullet Time X is present iff its cvars are. Testing for a cvar rather
	// than a class means this keeps working if the mod renames its types,
	// and means we never have to reference a symbol that might not exist.
	static bool Detected()
	{
		return CVar.FindCVar("bt_player_movement_multiplier") != null;
	}

	static bool CompEnabled()
	{
		CVar c = CVar.FindCVar("rs_fm_bt");
		return (c && c.GetBool());
	}

	static double Scale()
	{
		double s = 1.0;
		CVar c = CVar.FindCVar("rs_fm_bt_scale");
		if (c) s = c.GetFloat();
		if (s < 0.0) s = 0.0;
		if (s > 1.0) s = 1.0;
		return s;
	}

	override void WorldLoaded(WorldEvent e)
	{
		Apply();
	}

	override void WorldTick()
	{
		if (level.maptime % REFRESH != 0) return;
		Apply();
	}

	void Apply()
	{
		if (!Detected()) return;

		// These are server cvars. In a netgame only the arbitrator may move
		// them without the others disagreeing about how fast the world is.
		if (multiplayer && consoleplayer != Net_Arbitrator) return;

		if (!CompEnabled()) { Restore(); return; }

		// Captured only so Restore() has something to give back when this
		// is switched off -- the slider's own math (Target, below) depends
		// on nothing but the world's live divisor, not on what the player's
		// divisor used to be.
		Capture();

		double s = Scale();

		for (int i = 0; i < MS_BulletTime.GROUPS; ++i)
		{
			CVar wc = CVar.FindCVar(MS_BulletTime.WorldCVar(i));
			CVar pc = CVar.FindCVar(MS_BulletTime.PlayerCVar(i));
			if (!wc || !pc) continue;

			int world = wc.GetInt();

			// A world divisor of zero is their total-freeze mode, and their
			// player divisor cannot go to zero to match it. There is no
			// honest "as slow as the monsters" when the monsters are
			// stopped dead, so leave that profile alone entirely rather
			// than invent a number for it.
			if (world <= 0) continue;

			int want = MS_BulletTime.Target(s, world);
			if (pc.GetInt() != want) pc.SetInt(want);
		}
	}

	// Record what the mod was configured to before we ever wrote to it, and
	// keep it in a cvar rather than a field so it survives a restart. If it
	// lived only in memory, quitting with compensation on would leave their
	// settings permanently overwritten with no way back.
	void Capture()
	{
		CVar bc = CVar.FindCVar("rs_fm_bt_base");
		if (!bc || bc.GetString() != "") return;

		String packed = "";
		for (int i = 0; i < MS_BulletTime.GROUPS; ++i)
		{
			CVar pc = CVar.FindCVar(MS_BulletTime.PlayerCVar(i));
			int v = pc ? pc.GetInt() : 1;
			if (i > 0) packed = packed .. ":";
			packed = packed .. v;
		}
		bc.SetString(packed);
	}

	// Switched off: hand their settings back exactly as they were and
	// forget them, so the next capture reads a clean value rather than one
	// of ours.
	void Restore()
	{
		CVar bc = CVar.FindCVar("rs_fm_bt_base");
		if (!bc || bc.GetString() == "") return;

		Array<String> saved;
		String packed = bc.GetString();
		packed.Split(saved, ":");

		if (saved.Size() >= MS_BulletTime.GROUPS)
		{
			for (int i = 0; i < MS_BulletTime.GROUPS; ++i)
			{
				CVar pc = CVar.FindCVar(MS_BulletTime.PlayerCVar(i));
				if (pc) pc.SetInt(saved[i].ToInt());
			}
		}

		bc.SetString("");
	}
}
