// =====================================================================
// RS_ForeignAnim -- PLAYING OUR ANIMATION ON THEIR TIMING.
//
// Their weapon runs its own states at its own pace. We do not get to know
// what those states MEAN -- every structural way of asking was tried and
// each one broke on real mods:
//
//   * psprite y-kinematics: Offset(x,y) compiles to Misc1/Misc2 and
//     SetState writes `oldx = x` in one statement, so the delta is zero
//     on exactly the states the maths needed.
//   * the muzzle-flash layer: A_GunFlash appears ZERO times in either
//     Golden Souls or Ashes.
//   * state-chain membership: a walk from the Reload head reaches the
//     idle loop through NextState, so it labels Ready as Reload.
//   * summing state tics for a duration: Ashes' revolver reload hides
//     its whole body behind a 0-tic conditional jump. Predicts 1 tic,
//     actually runs 68.
//
// So identity is not a NAME here. It is the ENTRY STATE POINTER.
// (foreignClass, entryState) is stable, exact and mod-independent. We
// watch a sequence once to learn how long it really ran and where its
// bright frame fell, then replay our matching clip stretched across that
// learned duration. We never have to be RIGHT about whether it is called
// "Fire" -- only CONSISTENT.
//
// Which clip to play for a learned key is a PRIOR. It is allowed to be
// wrong, because the picker is the correction path.
// =====================================================================

// ---------------------------------------------------------------------
// One donor animation clip, expanded to one frame per tic.
//
// Table rows: donorClass|seq|steps|markFire|markEject|markFeed
//   steps -- comma separated; "f@t" holds frame f for t tics,
//            "a-b@t" runs a to b inclusive (either direction), t tics
//            PER FRAME.
//   marks -- clip-tic offsets of the shot / shell eject / magazine
//            seat. -1 = none. Used to anchor the warp so the recoil
//            lands on their shot rather than merely near it.
// ---------------------------------------------------------------------
class RS_ForeignClip
{
	Array<string> mRows;

	void Build()
	{
		static const string CLIP[] = {
			"MS_AE_Pistol|ready|0@1|-1|-1|-1",
			"MS_AE_Pistol|fire|1@2,2@2,3@2,4@2,5@2|0|-1|-1",
			"MS_AE_Pistol|reload|6-19@2|-1|0|10",
			"MS_AE_Shotgun|ready|0@1|-1|-1|-1",
			"MS_AE_Shotgun|fire|0@1,1@1,1@2,2@2,0@1,3@1,3@1,4@1,4@1,5@1,5@1,4@1,4@1,3@1,3@1,0@2|1|-1|-1",
			"MS_AE_Shotgun|reload|14-28@2|-1|0|12",
			"MS_AE_Flamer|ready|0@1|-1|-1|-1",
			"MS_AE_Flamer|fire|0@2,1@2,1@2,2@2,3@2,0@2,1@2,1@2,1@1,0@1|0|-1|-1",
			"MS_RC_Auto9|ready|0@1|-1|-1|-1",
			"MS_RC_Auto9|fire|1@2,1@2,1@2,2@8|0|-1|-1",
			"MS_Cola_Revolver|ready|0@1|-1|-1|-1",
			"MS_Cola_Revolver|fire|1-6@1|0|-1|-1",
			"MS_Cola_Revolver|reload|7-30@2|-1|0|20",
			"MS_RC_Chainsaw|ready|0-10@1|-1|-1|-1",
			"MS_RC_Chainsaw|fire|11-24@1|0|-1|-1",
			"MS_Jackhammer|ready|0@1|-1|-1|-1",
			"MS_Jackhammer|fire|1@1,2@1,3@1,4@1,5@1|0|-1|-1",
			"MS_RC_M32|ready|0@1|-1|-1|-1",
			"MS_RC_M32|fire|1@3,2@3,3@3,4@3,5@3,6@3|0|-1|-1",
			"MS_RC_M32|reload|7-36@2|-1|0|24",
			"MS_Rifle2|fire|1-10@1|0|-1|-1",
			"MS_Rifle2|ready|0@1|-1|-1|-1",
			"MS_Rifle2|reload|11-13@2,14-25@1,26-34@2,35-37@1,38-40@2,0@1|-1|-1|-1",
			"MS_Shotgun2|fire|1-4@1,5@1,6@1,7@1,8-12@1,13@1,14-19@1,0@1|0|-1|-1",
			"MS_Shotgun2|ready|0@1|-1|-1|-1",
			"MS_Shotgun2|reload|5@2,6@2,19@1,18@1,17@1,16@1,15@1,14@1,13@1,12@1,11@1,10@1,9@1,8@1,7@1,6@1,5@1|0|-1|-1",
			"MS_SuperShotgun2|fire|0@2,1-7@2|0|-1|-1",
			"MS_SuperShotgun2|ready|0@1|-1|-1|-1",
			"MS_SuperShotgun2|reload|8@2,9-17@3,18@2,19-21@3,23@2,24@2,24@1|0|-1|-1",
			"MS_BD_Boot|fire|5@1,6@1,7@1,8@1,9@1,10@1,11@1,12@1,13@1,14@1,15@1,16@1,17@1,18@1,19@1,20@1,21@1,22@1,23@1,24@1,25@1,26@1,27@1,28@1,29@1,30@1,31@1,32@1,33@1,34@1,35@1,36@1,37@1,38@1,39@1,40@1,53@1,54@1,55@1,56@1,57@1|0|-1|-1",
			"MS_BD_BrutalAxe|fire|5@1,6@1,7@1,8@1,9@1,10@1,11@1,12@1,13@1,14@1|0|-1|-1",
			"MS_BD_BrutalAxe|ready|5@1|-1|-1|-1",
			"MS_BD_BrutalAxe|select|0@1,1@1,2@1,3@1|-1|-1|-1",
			"MS_BD_BrutalAxe|sprint|3@1|-1|-1|-1",
			"MS_BD_BrutalPistol|fire|2@1,3@1,4@1,5@1,6@1,7@1|0|-1|-1",
			"MS_BD_BrutalPistol|ready|3@1|-1|-1|-1",
			"MS_BD_BrutalPistol|reload|8@1,9@1,10@1,11@1,12@1,13@1,14@1,15@1,16@1,17@1,18@1,19@1,20@1,21@1,22@1,23@1,24@1,25@1|-1|-1|-1",
			"MS_BD_BrutalPistol|sprint|27@1,28@1,29@1,30@1,31@1,32@1,33@1,34@1,35@1,36@1,37@1|-1|-1|-1",
			"MS_BD_BrutalSMG|ads|2@1,3@1,4@1,5@1,6@1|-1|-1|-1",
			"MS_BD_BrutalSMG|fire|3@1,4@1,5@1,6@1|0|-1|-1",
			"MS_BD_BrutalSMG|ready|3@1|-1|-1|-1",
			"MS_BD_BrutalSMG|reload|7@1,8@1,9@1,10@1,11@1,12@1,13@1,14@1,15@1,16@1,17@1,18@1,19@1,20@1,21@1,22@1,23@1,24@1,25@1,26@1|-1|-1|-1",
			"MS_BD_BrutalSMG|select|0@1,1@1,2@1|-1|-1|-1",
			"MS_BD_BrutalSMG|sprint|2@1|-1|-1|-1",
			"MS_BD_Flamethrower2|fire|0@1,1@1,2@1,3@1,4@1|0|-1|-1",
			"MS_BD_M79|fire|3@1,4@1,5@1,6@1|0|-1|-1",
			"MS_BD_M79|ready|3@1|-1|-1|-1",
			"MS_BD_M79|reload|7@1,8@1,9@1,10@1,11@1,12@1,13@1,14@1,15@1,16@1,17@1,18@1,19@1,20@1,21@1,22@1,23@1,24@1,25@1,26@1,27@1,28@1,29@1,30@1,31@1,32@1|-1|-1|-1",
			"MS_BD_M79|select|0@1,1@1,2@1|-1|-1|-1",
			"MS_BD_M79|sprint|2@1|-1|-1|-1",
			"MS_BD_Machinegun|fire|4@1,5@1,7@1,8@1,9@1,10@1|0|-1|-1",
			"MS_BD_Machinegun|altfire|11-17@1|0|-1|-1",
			"MS_BD_Machinegun|ready|10@1|-1|-1|-1",
			"MS_BD_Machinegun|reload|18@1,19@1,20@1,21@1,22@1,23@1,24@1,25@1,26@1,27@1,28@1,29@1,30@1,31@1,32@1,33@1,34@1,35@1|-1|-1|-1",
			"MS_BD_Machinegun|select|0@1,1@1,2@1,3@1|-1|-1|-1",
			"MS_BD_Machinegun|sprint|3@1|-1|-1|-1",
			"MS_BD_nade|fire|3@1,4@1,5@1,6@1,7@1,8@1,9@1,10@1,11@1,12@1,13@1,14@1,15@1|0|-1|-1",
			"MS_BD_nade|reload|16@1,17@1,18@1,19@1,20@1,21@1,22@1,23@1,24@1,25@1,26@1|-1|-1|-1",
			"MS_BD_RailGun|ads|3@1,36@1|-1|-1|-1",
			"MS_BD_RailGun|fire|3@1,4@1,5@1,6@1,7@1,8@1,9@1,10@1|0|-1|-1",
			"MS_BD_RailGun|ready|3@1|-1|-1|-1",
			"MS_BD_RailGun|reload|11@1,12@1,13@1,14@1,15@1,16@1,17@1,18@1,19@1,20@1,21@1,22@1,23@1,24@1,25@1,26@1,27@1,28@1,29@1,30@1,31@1,32@1,33@1,34@1|-1|-1|-1",
			"MS_BD_RailGun|select|0@1,1@1,2@1|-1|-1|-1",
			"MS_BD_RailGun|sprint|2@1|-1|-1|-1",
			"MS_BD_Unmaker|ready|4@1|-1|-1|-1",
			"MS_BD_Unmaker|reload|5@1,6@1,7@1,8@1,9@1,10@1,11@1,12@1,13@1,14@1,15@1|-1|-1|-1",
			"MS_Chaingun|fire|4@2,10@2|0|-1|-1",
			"MS_Chaingun|ready|4@1|-1|-1|-1",
			"MS_Chainsaw|deselect|11@1|-1|-1|-1",
			"MS_Chainsaw|fire|6@1,7@1,8@1,9@1,10@1,11@1,12@1,7@1|0|-1|-1",
			"MS_Chainsaw|ready|13@4,14@4|-1|-1|-1",
			"MS_Chainsaw|select|0@1,1@1,2@1,3@1,4@1,5@1|-1|-1|-1",
			"MS_MG_Bolter|ready|0@1|-1|-1|-1",
			"MS_MG_Tec9|ready|0@1|-1|-1|-1",
			"MS_MG_Bolter|fire|3@1,1@1,1@1,2@1|0|-1|-1",
			"MS_MG_Tec9|fire|4@1,1@1,2@1,0@1|0|-1|-1",
			"MS_Pistol|fire|1@2,2@2,0@1|0|-1|-1",
			"MS_MG_Bolter|ready|0@1|-1|-1|-1",
			"MS_MG_Tec9|ready|0@1|-1|-1|-1",
			"MS_MG_Bolter|fire|3@1,1@1,1@1,2@1|0|-1|-1",
			"MS_MG_Tec9|fire|4@1,1@1,2@1,0@1|0|-1|-1",
			"MS_Pistol|ready|0@1|-1|-1|-1",
			"MS_MG_Bolter|ready|0@1|-1|-1|-1",
			"MS_MG_Tec9|ready|0@1|-1|-1|-1",
			"MS_MG_Bolter|fire|3@1,1@1,1@1,2@1|0|-1|-1",
			"MS_MG_Tec9|fire|4@1,1@1,2@1,0@1|0|-1|-1",
			"MS_Pistol|reload|5-17@1,18-22@1,23-24@1|0|-1|-1",
			"MS_Pistol2|fire|1@2,2@2,0@1|0|-1|-1",
			"MS_Pistol2|ready|0@1|-1|-1|-1",
			"MS_Pistol2|reload|5-17@1,18-22@1,23-24@1|0|-1|-1",
			"MS_PlasmaRifle|fire|4@1,5@1,6@1,7@1,8@1,9@1,10@1,11@1,12@1,13@1,14@1,15@1,16@1,17@1|0|-1|-1",
			"MS_PlasmaRifle|ready|4@1|-1|-1|-1",
			"MS_PlasmaRifle|reload|18@1,19@1,20@1,21@1,22@1,23@1,24@1,25@1,26@1,27@1,28@1,29@1|-1|-1|-1",
			"MS_PlasmaRifle|select|0@1,1@1,2@1,3@1|-1|-1|-1",
			"MS_PlasmaRifle|sprint|3@1|-1|-1|-1",
			"MS_Revolver|fire|1-3@1,4-5@2,6-15@1|0|-1|-1",
			"MS_Revolver|ready|0@1|-1|-1|-1",
			"MS_Revolver|reload|16-25@2,26@1,27-33@2,34-37@1,0@1|0|-1|-1",
			"MS_Revolver2|fire|1-3@1,4-5@2,6-15@1|0|-1|-1",
			"MS_Revolver2|ready|0@1|-1|-1|-1",
			"MS_Revolver2|reload|16-25@2,26@1,27-33@2,34-37@1,0@1|0|-1|-1",
			"MS_Rifle|fire|1-10@1|0|-1|-1",
			"MS_Rifle|ready|0@1|-1|-1|-1",
			"MS_Rifle|reload|11-13@2,14-25@1,26-34@2,35-37@1,38-40@2,0@1|-1|-1|-1",
			"MS_RocketLauncher|fire|10@6,10@4,5@1|0|-1|-1",
			"MS_RocketLauncher|ready|5@1|-1|-1|-1",
			"MS_RocketLauncher|reload|11-38@1|-1|0|14",
			"MS_Shotgun|fire|1-4@1,5@1,6@1,7@1,8-12@1,13@1,14-19@1,0@1|0|-1|-1",
			"MS_Shotgun|ready|0@1|-1|-1|-1",
			"MS_Shotgun|reload|5@2,6@2,19@1,18@1,17@1,16@1,15@1,14@1,13@1,12@1,11@1,10@1,9@1,8@1,7@1,6@1,5@1|0|-1|-1",
			"MS_SuperShotgun|fire|0@2,1-7@2|0|-1|-1",
			"MS_SuperShotgun|ready|0@1|-1|-1|-1",
			"MS_SuperShotgun|reload|8@2,9-17@3,18@2,19-21@3,23@2,24@2,24@1|0|-1|-1",
			"MS_VR_BFG9000|fire|7@3,8@3,9@3,6@1|0|-1|-1",
			"MS_VR_BFG9000|ready|6@1|-1|-1|-1"
		};
		mRows.Clear();
		for (int i = 0; i < CLIP.Size(); ++i) mRows.Push(CLIP[i]);
	}

	// Expand a step list into one frame per tic. Clamped to the donor's
	// real frame count -- an out-of-range ModelFrame draws NOTHING, so a
	// bad row would make the weapon vanish rather than look wrong.
	static void Expand(string steps, int frameCount, out Array<int> frames)
	{
		frames.Clear();
		Array<string> parts;
		steps.Split(parts, ",");

		for (int p = 0; p < parts.Size(); ++p)
		{
			string s = parts[p];
			int at = s.IndexOf("@");
			if (at < 0) continue;

			string range = s.Left(at);
			int tics = s.Mid(at + 1).ToInt();
			if (tics < 1) tics = 1;

			int dash = range.IndexOf("-", 1);   // from 1: allow a leading sign
			int a, b;
			if (dash > 0)
			{
				a = range.Left(dash).ToInt();
				b = range.Mid(dash + 1).ToInt();
			}
			else { a = range.ToInt(); b = a; }

			int step = (b >= a) ? 1 : -1;
			for (int f = a; ; f += step)
			{
				int cf = f;
				if (frameCount > 0 && cf >= frameCount) cf = frameCount - 1;
				if (cf < 0) cf = 0;
				for (int t = 0; t < tics; ++t) frames.Push(cf);
				if (f == b) break;
			}
		}
	}

	// donorClass + seq -> expanded frame list and its fire mark.
	bool Get(string donor, string seq, int frameCount, out Array<int> frames, out int markFire) const
	{
		frames.Clear(); markFire = -1;
		string key = donor .. "|" .. seq .. "|";
		for (int i = 0; i < mRows.Size(); ++i)
		{
			if (mRows[i].IndexOf(key) != 0) continue;
			Array<string> f;
			mRows[i].Split(f, "|");
			if (f.Size() < 4) return false;
			Expand(f[2], frameCount, frames);
			markFire = f[3].ToInt();
			return (frames.Size() > 0);
		}
		return false;
	}

	bool Has(string donor, string seq) const
	{
		string key = donor .. "|" .. seq .. "|";
		for (int i = 0; i < mRows.Size(); ++i)
			if (mRows[i].IndexOf(key) == 0) return true;
		return false;
	}
}

// ---------------------------------------------------------------------
// Display state for ONE hand. This used to be fifteen fields of watched
// behavior -- entry states, elapsed tics, ammo baselines, idle glue,
// live sequence proofs. The remap engine (RS_ForeignRemap) reads the
// weapon's own state machine every tic instead, so all that survives is
// who we're painting and where the mesh parked.
// ---------------------------------------------------------------------
class RS_ForeignHand
{
	Actor lastCaller;
	int   lastMesh;    // last mapped mesh frame; held on unmapped states

	// Heal context: the table and row of the last HIT, so a miss knows
	// which group's clip was interrupted and where it left off. The map
	// reference guards against a stale row after a donor change rebuilds
	// the table.
	RS_ForeignRemap lastMap;
	int lastHitRow;

	// Health telemetry: tics this hand spent on states the table resolved
	// vs. missed, printed and reset periodically by the handler so every
	// session's log answers "did it animate, and where are the holes"
	// without anyone being asked anything. The last missed state's
	// sprite/frame is kept so a hole names itself; healed counts states
	// the table repaired into itself this interval.
	int hits, misses, healed;
	int missSprite, missFrame, missTics;

	void Reset()
	{
		lastCaller = null;
		lastMesh   = -1;
		lastMap    = null;
		lastHitRow = -1;
		hits = 0; misses = 0; healed = 0;
		missSprite = -1; missFrame = -1; missTics = -1;
	}
}
