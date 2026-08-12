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
// THE SLIDER maps onto that, with three anchors:
//
//     0.0  player divisor = world divisor   -- as slow as the monsters
//     1.0  player divisor = the mod's own   -- untouched, whatever it is
//     2.0  player divisor = 1               -- normal movement
//
// 1.0 passes their configuration through unchanged, so the default
// setting of this feature is "change nothing" even while it is switched
// on. Between anchors it interpolates linearly.
//
// WORTH KNOWING: Bullet Time X ships with bt_multiplier = 4 and
// bt_player_movement_multiplier = 4 -- the player is already exactly as
// slow as the monsters out of the box. On a stock config 0.0 and 1.0 are
// therefore the same value and the bottom half of the slider does
// nothing. The half above 1.0 is where the range lives. The lower half
// only opens up if the mod's own player-speed setting has been changed
// away from matching the world.
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

	// Their clamp range for a player divisor is 1..20 (BulletTime.zs:359).
	// Producing anything outside it would just be silently clamped by them
	// into a value we did not intend, so clamp it here where it is visible.
	static int Target(double s, int base, int world)
	{
		double v;
		if (s <= 1.0) v = world + (base - world) * s;
		else          v = base  + (1.0  - base)  * (s - 1.0);

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
		if (s > 2.0) s = 2.0;
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

		Capture();

		CVar bc = CVar.FindCVar("rs_fm_bt_base");
		if (!bc) return;

		Array<String> saved;
		String packed = bc.GetString();
		packed.Split(saved, ":");
		if (saved.Size() < MS_BulletTime.GROUPS) return;

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

			int want = MS_BulletTime.Target(s, saved[i].ToInt(), world);
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
