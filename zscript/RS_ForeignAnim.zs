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
			// ---- standalone donors (same meshes as the VR_ set) ----
			"MS_Pistol|ready|0@1|-1|-1|-1",
			"MS_Pistol|fire|1@2,2@2,0@1|0|-1|-1",
			"MS_Pistol|reload|5-17@1,18-22@1,23-24@1|-1|0|13",

			"MS_Revolver|ready|0@1|-1|-1|-1",
			"MS_Revolver|fire|1@1,2@2,3@2,0@1|0|-1|-1",
			"MS_Revolver|reload|4-25@1,26-40@1|-1|0|22",

			"MS_Rifle|ready|0@1|-1|-1|-1",
			"MS_Rifle|fire|1@1,2@1,0@1|0|-1|-1",
			"MS_Rifle|reload|11-13@2,14-24@1,25-34@2,35-37@1,38-40@2|-1|0|24",

			"MS_Shotgun|ready|0@1|-1|-1|-1",
			"MS_Shotgun|fire|1-19@1,0@1|0|4|12",
			"MS_Shotgun|reload|5@2,6@2,19@1,18-6@1,5@1|-1|0|8",

			"MS_SuperShotgun|ready|0@1|-1|-1|-1",
			"MS_SuperShotgun|fire|0@2,1-7@2|0|-1|-1",
			"MS_SuperShotgun|reload|8@2,9-17@3,18@2,19-22@3,23@2,24@3|-1|0|31",

			"MS_Chaingun|ready|4@1|-1|-1|-1",
			"MS_Chaingun|fire|5@1,6@1,4@1|0|-1|-1",
			"MS_Chaingun|reload|7-15@1|-1|0|-1",

			"MS_RocketLauncher|ready|5@1|-1|-1|-1",
			"MS_RocketLauncher|fire|6@2,7@2,8@2,5@1|0|-1|-1",
			"MS_RocketLauncher|reload|11-34@1|-1|0|17",

			"MS_PlasmaRifle|ready|4@1|-1|-1|-1",
			"MS_PlasmaRifle|fire|5@1,6@1,4@1|0|-1|-1",
			"MS_PlasmaRifle|reload|13-29@1|-1|0|8",

			"MS_BFG9000|ready|6@1|-1|-1|-1",
			"MS_BFG9000|fire|7@3,8@3,9@3,6@1|0|-1|-1",
			"MS_BFG9000|reload|10-15@2|-1|0|-1",

			"MS_BFG10k|ready|6@1|-1|-1|-1",
			"MS_BFG10k|fire|7@3,8@3,9@3,6@1|0|-1|-1",
			"MS_BFG10k|reload|10-20@2|-1|0|-1",

			"MS_Flamethrower|ready|0@1|-1|-1|-1",
			"MS_Flamethrower|fire|1@1,2@1,3@1,0@1|0|-1|-1",

			"MS_Fist|ready|0@1|-1|-1|-1",
			"MS_Fist|fire|1-18@1,0@1|8|-1|-1",

			"MS_Chainsaw|ready|0@1|-1|-1|-1",
			"MS_Chainsaw|fire|1@1,2@1,3@1,0@1|0|-1|-1",
			"MS_Chainsaw|altfire|4@1,5@1,6@1,7@1,0@1|0|-1|-1",

			// ---- RS_Main donors (present when RS_Main is loaded) ----
			"VR_Pistol|ready|0@1|-1|-1|-1",
			"VR_Pistol|fire|1@2,2@2,0@1|0|-1|-1",
			"VR_Pistol|reload|5-17@1,18-22@1,23-24@1|-1|0|13",

			"VR_Rifle|ready|0@1|-1|-1|-1",
			"VR_Rifle|fire|1@1,2@1,0@1|0|-1|-1",
			"VR_Rifle|reload|11-13@2,14-24@1,25-34@2,35-37@1,38-40@2|-1|0|24",

			"VR_Shotgun|ready|0@1|-1|-1|-1",
			"VR_Shotgun|fire|1-19@1,0@1|0|4|12",
			"VR_Shotgun|reload|5@2,6@2,19@1,18-6@1,5@1|-1|0|8",

			"VR_SuperShotgun|ready|0@1|-1|-1|-1",
			"VR_SuperShotgun|fire|0@2,1-7@2|0|-1|-1",
			"VR_SuperShotgun|reload|8@2,9-17@3,18@2,19-22@3,23@2,24@3|-1|0|31",

			"VR_Revolver|ready|0@1|-1|-1|-1",
			"VR_Revolver|fire|1@1,2@2,3@2,0@1|0|-1|-1",
			"VR_Revolver|reload|4-25@1,26-40@1|-1|0|22",

			"VR_SMG|ready|3@1|-1|-1|-1",
			"VR_SMG|fire|4@1,5@1,6@1,3@1|0|-1|-1",
			"VR_SMG|reload|7-26@1|-1|0|10",

			"VR_Chaingun|ready|4@1|-1|-1|-1",
			"VR_Chaingun|fire|5@1,6@1,4@1|0|-1|-1",
			"VR_Chaingun|reload|7-15@1|-1|0|-1",

			"VR_RocketLauncher|ready|5@1|-1|-1|-1",
			"VR_RocketLauncher|fire|6@2,7@2,8@2,5@1|0|-1|-1",
			"VR_RocketLauncher|reload|11-34@1|-1|0|17",

			"VR_PlasmaRifle|ready|4@1|-1|-1|-1",
			"VR_PlasmaRifle|fire|5@1,6@1,4@1|0|-1|-1",
			"VR_PlasmaRifle|reload|13-29@1|-1|0|8",

			"VR_BFG9000|ready|6@1|-1|-1|-1",
			"VR_BFG9000|fire|7@3,8@3,9@3,6@1|0|-1|-1",
			"VR_BFG9000|reload|10-15@2|-1|0|-1",

			"VR_Chainsaw|ready|0@1|-1|-1|-1",
			"VR_Chainsaw|fire|1@1,2@1,3@1,0@1|0|-1|-1",
			"VR_Chainsaw|altfire|4@1,5@1,6@1,7@1,0@1|0|-1|-1",

			"RS_GH_Pistol|ready|2@1|-1|-1|-1",
			"RS_GH_Pistol|fire|3@1,4@2,5@2,2@1|0|-1|-1",
			"RS_GH_Pistol|altfire|3@1,4@1,3@1,4@1,3@1,4@3,2@1|0|-1|-1",
			"RS_GH_Pistol|reload|8-25@1|-1|0|10",

			"RS_GH_Revolver|ready|0@1|-1|-1|-1",
			"RS_GH_Revolver|fire|1@1,2@2,3@2,0@1|0|-1|-1",
			"RS_GH_Revolver|reload|18-30@2|-1|0|13",

			"RS_GH_SMG|ready|3@1|-1|-1|-1",
			"RS_GH_SMG|fire|4@1,5@1,6@1,3@1|0|-1|-1",
			"RS_GH_SMG|reload|7-26@1|-1|0|10",

			"RS_GH_MP40|ready|2@1|-1|-1|-1",
			"RS_GH_MP40|fire|3@1,4@1,5@1,2@1|0|-1|-1",
			"RS_GH_MP40|reload|7-13@2|-1|0|7",

			"RS_GH_Rifle|ready|3@1|-1|-1|-1",
			"RS_GH_Rifle|fire|4@1,5@1,6@1,3@1|0|-1|-1",
			"RS_GH_Rifle|reload|7-26@1|-1|0|10",

			"RS_GH_PumpShotgun|ready|4@1|-1|-1|-1",
			"RS_GH_PumpShotgun|fire|5-21@1,4@1|0|3|11",
			"RS_GH_PumpShotgun|reload|23-31@2|-1|0|9",

			"RS_GH_AssaultShotgun|ready|4@1|-1|-1|-1",
			"RS_GH_AssaultShotgun|fire|5@1,6@1,7@1,4@1|0|-1|-1",
			"RS_GH_AssaultShotgun|reload|11-31@1|-1|0|11",

			"RS_GH_SSG|ready|1@1|-1|-1|-1",
			"RS_GH_SSG|fire|2@1,3@2,4@2,1@1|0|-1|-1",
			"RS_GH_SSG|altfire|2@1,3@2,1@1|0|-1|-1",
			"RS_GH_SSG|reload|12-37@1|-1|0|14",

			"RS_GH_Machinegun|ready|4@1|-1|-1|-1",
			"RS_GH_Machinegun|fire|5@1,6@1,7@1,4@1|0|-1|-1",
			"RS_GH_Machinegun|reload|8-35@1|-1|0|14",

			"RS_GH_Minigun|ready|4@1|-1|-1|-1",
			"RS_GH_Minigun|fire|5@1,6@1,7@1,4@1|0|-1|-1",
			"RS_GH_Minigun|reload|11-15@2|-1|0|-1",

			"RS_GH_RocketLauncher|ready|5@1|-1|-1|-1",
			"RS_GH_RocketLauncher|fire|6@1,7@2,8@2,5@1|0|-1|-1",
			"RS_GH_RocketLauncher|reload|17-34@1|-1|0|9",

			"RS_GH_GrenadeLauncher|ready|3@1|-1|-1|-1",
			"RS_GH_GrenadeLauncher|fire|4@1,5@2,6@2,3@1|0|-1|-1",
			"RS_GH_GrenadeLauncher|reload|7-32@1|-1|0|13",

			"RS_GH_Plasma|ready|4@1|-1|-1|-1",
			"RS_GH_Plasma|fire|5@1,6@1,7@1,4@1|0|-1|-1",

			"RS_GH_Railgun|ready|3@1|-1|-1|-1",
			"RS_GH_Railgun|fire|4@1,5@2,6@2,3@1|0|-1|-1",

			"RS_GH_BFG9000|ready|6@1|-1|-1|-1",
			"RS_GH_BFG9000|fire|7@3,8@3,9@3,6@1|0|-1|-1",

			"RS_GH_BFG10k|ready|6@1|-1|-1|-1",
			"RS_GH_BFG10k|fire|7@3,8@3,9@3,6@1|0|-1|-1",

			"RS_GH_Flamethrower|ready|0@1|-1|-1|-1",
			"RS_GH_Flamethrower|fire|1@1,2@1,3@1,0@1|0|-1|-1",

			"RS_GH_Fist|ready|0@1|-1|-1|-1",
			"RS_GH_Fist|fire|1-18@1,0@1|8|-1|-1",

			"RS_GH_Chainsaw|ready|27@1|-1|-1|-1",
			"RS_GH_Chainsaw|fire|28-40@1,27@1|0|-1|-1"
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
// What we have learned about one (foreign weapon, entry state) pair by
// watching it run. Duration is OBSERVED, never predicted -- a foreign
// sequence's real length is not derivable from its state tics.
// ---------------------------------------------------------------------
class RS_ForeignLearned
{
	string clsName;
	State  entry;
	string seq;          // the prior: which of our clips to play
	int    observedTics; // <=0 until it has run once
	int    brightTic;    // when bFullbright first appeared, -1 = never
	int    plays;
}

// ---------------------------------------------------------------------
// Live animation state for ONE hand.
// ---------------------------------------------------------------------
class RS_ForeignHand
{
	Actor  lastCaller;
	State  lastState;
	State  predictedNext;
	State  entry;
	int    lastTics;
	int    elapsed;
	int    sawBrightAt;
	int    ammoAtEntry;
	int    ammo2AtEntry;

	void Reset()
	{
		lastCaller = null; lastState = null; predictedNext = null;
		entry = null; lastTics = 0; elapsed = 0; sawBrightAt = -1;
		ammoAtEntry = -1; ammo2AtEntry = -1;
	}
}
