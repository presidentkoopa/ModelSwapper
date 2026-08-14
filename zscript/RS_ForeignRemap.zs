// =====================================================================
// RS_ForeignRemap -- THEIR STATE MACHINE IS THE CLOCK.
//
// Build a table mapping every state a weapon can display to a frame of
// our donor mesh, register it with the engine once at bind, and the
// renderer resolves each frame against the psprite's actual current
// state natively. No learning, no timing of ours, no per-tick script.
//
// V2, after the Ashes session log proved v1's blind spot: DECORATE-era
// mods put their REAL animations behind runtime conditional jumps into
// mod-custom labels -- RealFire, Work1, ReloadChamber, ReloadDone --
// which a NextState walk from the standard labels can never reach (the
// log: revolver Reload mapped 4 states out of a 60-tic animation; Fire
// mapped 2). ZScript could not even see those labels: FindState probes
// names known in advance. The fork now enumerates the class's ENTIRE
// label table (Actor.CountStateLabels / GetStateLabelAt), sorted by
// state address -- which is source declaration order -- so every custom
// label can be attributed to the standard label it was written under:
//
//   Fire:            <- opens the "fire" group
//   RealFire: ...    <- custom, joins fire
//   Fire2: ...       <- custom, joins fire
//   Reload:          <- opens the "reload" group
//   Work1: ...       <- custom, joins reload
//   ReloadDone: ...  <- custom, joins reload
//   Spawn:           <- non-psprite label, closes any open group
//
// Each group's states -- all its labels' chains, concatenated in source
// order -- get the group's donor clip distributed across them by tic
// weight. Their per-shell loops replay mapped states; their branches
// select between mapped states; timing is theirs because no other
// timing exists.
// =====================================================================

class RS_ForeignRemap
{
	string clsName;
	string donor;

	// Parallel arrays; mStates is the key. Lookups are hint-cached:
	// states advance sequentially, so the next lookup is almost always
	// the same index or the one after it.
	Array<State> mStates;
	Array<int>   mMesh;
	Array<int>   mMeshNext;
	int mHint;

	bool Lookup(State s, out int meshFrame, out int meshNext)
	{
		meshFrame = -1; meshNext = -1;
		int n = mStates.Size();
		if (n == 0 || s == null) return false;

		if (mHint >= 0 && mHint < n)
		{
			if (mStates[mHint] == s) { meshFrame = mMesh[mHint]; meshNext = mMeshNext[mHint]; return true; }
			int nx = mHint + 1;
			if (nx < n && mStates[nx] == s) { mHint = nx; meshFrame = mMesh[nx]; meshNext = mMeshNext[nx]; return true; }
		}
		for (int i = 0; i < n; ++i)
		{
			if (mStates[i] == s) { mHint = i; meshFrame = mMesh[i]; meshNext = mMeshNext[i]; return true; }
		}
		return false;
	}

	bool Claimed(State s)
	{
		for (int i = 0; i < mStates.Size(); ++i)
			if (mStates[i] == s) return true;
		return false;
	}

	static bool DebugOn()
	{
		// Always on, by request. The build/bind trace IS the debugging story
		// for the remap -- a handful of console lines per weapon, printed
		// once per bind, and the whole reason nobody ever has to relaunch
		// the game just to find out what the table thinks it did.
		return true;
	}

	// Which of our clips a STANDARD psprite label plays. "" = not a
	// psprite standard (so it cannot open a group).
	static string PspriteClip(string lname)
	{
		if (lname == "fire"    || lname == "hold"    || lname == "flash")    return "fire";
		if (lname == "altfire" || lname == "althold" || lname == "altflash") return "altfire";
		if (lname == "reload") return "reload";
		if (lname == "ready"  || lname == "deselect" || lname == "select"
		 || lname == "zoom"   || lname == "user1"    || lname == "user2"
		 || lname == "user3"  || lname == "user4") return "ready";
		return "";
	}

	// Labels that mean "whatever follows is NOT part of a psprite
	// sequence" -- world-actor and inventory labels. A custom label that
	// follows one of these in source order belongs to it, not to us.
	static bool ClosesGroup(string lname)
	{
		return lname == "spawn"  || lname == "see"    || lname == "idle"
		    || lname == "melee"  || lname == "missile"|| lname == "pain"
		    || lname == "death"  || lname == "xdeath" || lname == "raise"
		    || lname == "crash"  || lname == "wound"  || lname == "heal"
		    || lname == "pickup" || lname == "use"    || lname == "drop"
		    || lname == "lightdone" || lname == "cache" || lname == "bounce"
		    || lname == "burn"   || lname == "ice"    || lname == "disintegrate"
		    || lname == "brainexplode" || lname == "genericfreezedeath"
		    || lname == "gibbed" || lname == "genericcrush";
	}

	// -----------------------------------------------------------------
	// Build the whole table for one weapon wearing one donor.
	// -----------------------------------------------------------------
	static RS_ForeignRemap Build(class<Weapon> type, string donorCls,
	                             RS_ForeignClip clips, int frameCount, int restFrame)
	{
		let m = new("RS_ForeignRemap");
		m.clsName = type.GetClassName();
		m.donor   = donorCls;
		m.mHint   = 0;

		class<Actor> ac = (class<Actor>)(type);
		int n = Actor.CountStateLabels(ac);
		if (DebugOn()) Console.Printf("[RSRM] %s/%s: %d labels total", m.clsName, donorCls, n);

		// One pass in source order. A psprite standard opens a group (and
		// closes the previous one); a world/inventory label closes without
		// opening; a custom label joins whatever group is open.
		string groupClip  = "";
		string groupNames = "";
		Array<State> roots;

		for (int i = 0; i <= n; ++i)   // one extra pass flushes the last group
		{
			string lname = "";
			State  lst   = null;
			if (i < n)
			{
				Name nm; State st;
				[nm, st] = Actor.GetStateLabelAt(ac, i);
				lname = "" .. nm; lname = lname.MakeLower();
				lst = st;
			}

			string std = (i < n) ? PspriteClip(lname) : "";
			bool closer = (i >= n) || (std.Length() > 0) || ClosesGroup(lname);

			if (closer)
			{
				if (groupClip.Length() > 0 && roots.Size() > 0)
					MapGroup(m, roots, groupClip, groupNames, donorCls, clips, frameCount, restFrame);
				roots.Clear();
				groupNames = "";
				groupClip  = std;   // "" when a world label or the end closed it
			}

			if (i < n && groupClip.Length() > 0 && lst != null)
			{
				roots.Push(lst);
				if (groupNames.Length() > 0) groupNames = groupNames .. "+";
				groupNames = groupNames .. lname;
			}
		}
		if (DebugOn()) Console.Printf("[RSRM] %s/%s: TABLE COMPLETE, %d states total",
			m.clsName, donorCls, m.mStates.Size());
		return m;
	}

	// -----------------------------------------------------------------
	// One GROUP: every label chain it owns, concatenated in source order,
	// wearing one clip distributed across the whole span by tic weight.
	// -----------------------------------------------------------------
	static void MapGroup(RS_ForeignRemap m, Array<State> roots, string clipName,
	                     string groupNames, string donorCls, RS_ForeignClip clips,
	                     int frameCount, int restFrame)
	{
		// 1. Collect. Each root's NextState chain (Goto is encoded there),
		// stopping at states already claimed -- by an earlier group or
		// earlier in THIS group -- or revisited (their loops).
		Array<State> seq;
		Array<int>   dur;
		int total = 0;

		for (int r = 0; r < roots.Size(); ++r)
		{
			State s = roots[r];
			for (int guard = 0; guard < 512; ++guard)
			{
				if (s == null) break;
				if (m.Claimed(s)) break;
				bool seen = false;
				for (int k = 0; k < seq.Size(); ++k)
					if (seq[k] == s) { seen = true; break; }
				if (seen) break;

				int d = s.Tics;
				if (d < 0) d = 1;          // -1 = infinite; it displays, count it once
				seq.Push(s);
				dur.Push(d);
				total += d;
				s = s.NextState;
			}
		}
		if (seq.Size() == 0) return;

		// 2. The donor clip, already expanded to a per-tic frame list.
		// A donor without an altfire clip plays its FIRE clip for altfire
		// -- a kick or grenade toss wearing the fire animation reads far
		// better than a weapon frozen at rest. (No such fallback for
		// reload: a fire animation during a reload reads as a bug, and
		// rest is the honest pose for a mesh with no reload frames.)
		Array<int> frames;
		int markFire;
		bool haveClip = clips.Get(donorCls, clipName, frameCount, frames, markFire)
		                && frames.Size() > 0;
		if (!haveClip && clipName == "altfire")
			haveClip = clips.Get(donorCls, "fire", frameCount, frames, markFire)
			           && frames.Size() > 0;

		int rest = restFrame;
		if (frameCount > 0 && rest >= frameCount) rest = frameCount - 1;
		if (rest < 0) rest = 0;

		if (!haveClip || total <= 0)
		{
			for (int k = 0; k < seq.Size(); ++k)
			{
				m.mStates.Push(seq[k]);
				m.mMesh.Push(rest);
				m.mMeshNext.Push(rest);
			}
			if (DebugOn()) Console.Printf("[RSRM]   group [%s] -> %d states at rest (no '%s' clip)",
				groupNames, seq.Size(), clipName);
			return;
		}

		int N = frames.Size();

		// 3. Shot anchor, static: their first bright displaying state pinned
		// to our clip's marked shot frame, interpolated on both sides.
		int brightAt = -1, cum = 0;
		for (int k = 0; k < seq.Size(); ++k)
		{
			if (dur[k] > 0 && seq[k].bFullbright) { brightAt = cum; break; }
			cum += dur[k];
		}
		bool anchored = (brightAt > 0 && brightAt < total
		              && markFire > 0 && markFire < N - 1);

		// 4. Distribute across the whole group span.
		cum = 0;
		for (int k = 0; k < seq.Size(); ++k)
		{
			int a = RemapPos(cum,          total, N, anchored, brightAt, markFire);
			int b = RemapPos(cum + dur[k], total, N, anchored, brightAt, markFire);
			m.mStates.Push(seq[k]);
			m.mMesh.Push(frames[a]);
			m.mMeshNext.Push(frames[b]);
			cum += dur[k];
		}
		if (DebugOn()) Console.Printf("[RSRM]   group [%s] -> %d states / %d tics on clip '%s'%s",
			groupNames, seq.Size(), total, clipName, anchored ? " (shot-anchored)" : "");
	}

	// Their tic position -> our frame-list index, piecewise-linear
	// around the shot anchor when there is one.
	static int RemapPos(int t, int total, int N, bool anchored, int brightAt, int markFire)
	{
		if (t < 0) t = 0;
		if (t > total) t = total;

		int idx;
		if (anchored)
		{
			if (t <= brightAt) idx = t * markFire / brightAt;
			else               idx = markFire + (t - brightAt) * (N - 1 - markFire) / (total - brightAt);
		}
		else
		{
			idx = (total > 0) ? t * (N - 1) / total : 0;
		}
		if (idx < 0) idx = 0;
		if (idx > N - 1) idx = N - 1;
		return idx;
	}
}
