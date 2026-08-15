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

// One group's clip data, kept after build so self-healing can continue
// the right clip when an orphaned state is claimed mid-action.
class RS_RemapGroup
{
	string clipName;
	Array<int> frames;   // per-tic frame list, post-fallback
}

// play scope: HealFrom registers rows with the engine mid-game, which is
// a play-side write, and every caller of this class is the play-side
// handler anyway. (Data scope was the compile error the session log
// caught: "Can't call play function RegisterModelStateFrame".)
class RS_ForeignRemap play
{
	string clsName;
	string donor;

	// Parallel arrays; mStates is the key. Per row: the mesh frame shown
	// while the state displays, the frame its end lands on (for lerp),
	// WHICH GROUP the row belongs to, and how far through that group's
	// frame list the row's end sits. The last two exist for self-healing:
	// an orphaned state healed mid-action needs to know which clip was
	// playing and where it left off, so the heal can continue the clip
	// instead of freezing it. Lookups are hint-cached: states advance
	// sequentially, so the next lookup is almost always the same index or
	// the one after it.
	Array<State> mStates;
	Array<int>   mMesh;
	Array<int>   mMeshNext;
	Array<int>   mGroupId;   // index into mGroups
	Array<int>   mEndIdx;    // index into the group's frame list at state end
	Array<RS_RemapGroup> mGroups;
	int mHint;

	int LookupIndex(State s)
	{
		int n = mStates.Size();
		if (n == 0 || s == null) return -1;

		if (mHint >= 0 && mHint < n)
		{
			if (mStates[mHint] == s) return mHint;
			int nx = mHint + 1;
			if (nx < n && mStates[nx] == s) { mHint = nx; return nx; }
		}
		for (int i = 0; i < n; ++i)
		{
			if (mStates[i] == s) { mHint = i; return i; }
		}
		return -1;
	}

	bool Lookup(State s, out int meshFrame, out int meshNext)
	{
		int i = LookupIndex(s);
		if (i < 0) { meshFrame = -1; meshNext = -1; return false; }
		meshFrame = mMesh[i];
		meshNext  = mMeshNext[i];
		return true;
	}

	bool Claimed(State s)
	{
		for (int i = 0; i < mStates.Size(); ++i)
			if (mStates[i] == s) return true;
		return false;
	}

	// -----------------------------------------------------------------
	// SELF-HEALING. The walk cannot see a runtime jump whose target
	// label lives only in an action function's arguments -- that is an
	// information limit, not a code gap. But the MOMENT such a jump
	// lands, it identifies itself: the psprite was on a mapped row last
	// tic and is on an unmapped state now. That is unambiguous, so the
	// table repairs itself right there: walk the orphaned chain exactly
	// the way the builder walks a label chain, and distribute the
	// REMAINDER of the interrupted group's clip across it -- from the
	// frame index where the mapped portion left off to the clip's end.
	// The rows register with the engine the same tic, so the heal is
	// invisible: no pause, no snap, the clip just keeps playing across
	// states nobody could have predicted statically. Once healed, the
	// rows are permanent for the session and re-heal identically the
	// next session on first encounter.
	// -----------------------------------------------------------------
	// Which group plays a given clip. The healer needs this to answer
	// "the player pressed altfire, so the orphan chain they landed on is
	// the altfire animation" -- see ApplyHand.
	int FindGroupByClip(string clipName) const
	{
		for (int i = 0; i < mGroups.Size(); ++i)
			if (mGroups[i].clipName == clipName) return i;
		return -1;
	}

	string GroupClip(int gid) const
	{
		if (gid < 0 || gid >= mGroups.Size()) return "";
		return mGroups[gid].clipName;
	}

	int GroupIdOfRow(int row) const
	{
		if (row < 0 || row >= mGroupId.Size()) return -1;
		return mGroupId[row];
	}

	int EndIdxOfRow(int row) const
	{
		if (row < 0 || row >= mEndIdx.Size()) return 0;
		return mEndIdx[row];
	}

	int HealInto(int gid, int startIdx, State missed, Actor w)
	{
		if (gid < 0 || gid >= mGroups.Size()) return 0;
		if (missed == null || w == null) return 0;

		let grp = mGroups[gid];
		int N = grp.frames.Size();
		if (N == 0) return 0;

		if (startIdx < 0) startIdx = 0;
		if (startIdx > N - 1) startIdx = N - 1;

		// Walk the orphan chain: same rules as the builder -- stop on
		// claimed territory (the chain rejoining mapped states is its
		// natural end), on a revisit (their loop), or at the cap.
		Array<State> seq;
		Array<int>   dur;
		int total = 0;
		State s = missed;
		for (int guard = 0; guard < 512; ++guard)
		{
			if (s == null) break;
			if (Claimed(s)) break;
			bool seen = false;
			for (int k = 0; k < seq.Size(); ++k)
				if (seq[k] == s) { seen = true; break; }
			if (seen) break;

			int d = s.Tics;
			if (d < 0) d = 1;
			seq.Push(s);
			dur.Push(d);
			total += d;
			s = s.NextState;
		}
		if (seq.Size() == 0) return 0;

		// Distribute the clip's tail across the chain by tic weight.
		int span = (N - 1) - startIdx;
		int cum = 0;
		for (int k = 0; k < seq.Size(); ++k)
		{
			int a = startIdx + ((total > 0) ? cum * span / total : 0);
			int b = startIdx + ((total > 0) ? (cum + dur[k]) * span / total : 0);
			if (a > N - 1) a = N - 1;
			if (b > N - 1) b = N - 1;

			mStates.Push(seq[k]);
			mMesh.Push(grp.frames[a]);
			mMeshNext.Push(grp.frames[b]);
			mGroupId.Push(gid);
			mEndIdx.Push(b);
			RS_Fork.RegisterRow(w, seq[k], grp.frames[a], grp.frames[b]);
			cum += dur[k];
		}

		if (DebugOn()) Console.Printf("[RSRM] healed %d states into clip '%s' for %s (%d tics of chain)",
			seq.Size(), grp.clipName, clsName, total);
		return seq.Size();
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
		// Zero on a stock engine -- the static build produces an empty
		// table and the binder never consults it. See RS_Fork.
		int n = RS_Fork.CountLabels(ac);
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
				[nm, st] = RS_Fork.LabelAt(ac, i);
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

		// The group is recorded either way -- a no-clip group holds one
		// rest frame -- because self-healing needs every row to know its
		// group and every group to have a frame list to continue.
		let grp = new("RS_RemapGroup");
		grp.clipName = clipName;
		int gid = m.mGroups.Size();

		if (!haveClip || total <= 0)
		{
			grp.frames.Push(rest);
			m.mGroups.Push(grp);
			for (int k = 0; k < seq.Size(); ++k)
			{
				m.mStates.Push(seq[k]);
				m.mMesh.Push(rest);
				m.mMeshNext.Push(rest);
				m.mGroupId.Push(gid);
				m.mEndIdx.Push(0);
			}
			if (DebugOn()) Console.Printf("[RSRM]   group [%s] -> %d states at rest (no '%s' clip)",
				groupNames, seq.Size(), clipName);
			return;
		}

		int N = frames.Size();
		for (int k = 0; k < N; ++k) grp.frames.Push(frames[k]);
		m.mGroups.Push(grp);

		// 3. Shot anchor, static: their first bright displaying state pinned
		// to our clip's marked shot frame, interpolated on both sides.
		int brightAt = -1, cum = 0;
		for (int k = 0; k < seq.Size(); ++k)
		{
			if (dur[k] > 0 && seq[k].bFullbright) { brightAt = cum; break; }
			cum += dur[k];
		}
		// markFire >= 0, NOT > 0. Index 0 is a valid shot marker and is what
		// 49 of the 50 fire clips actually use -- the clip's first frame IS
		// the muzzle flash. Requiring > 0 silently disabled the shot anchor
		// for every one of them, so the recoil was only ever landing near
		// the bang by proportion, never pinned to it. brightAt > 0 still
		// guards the division below; markFire == 0 just means the whole
		// run-up sits on frame 0, which is the correct pre-shot pose.
		bool anchored = (brightAt > 0 && brightAt < total
		              && markFire >= 0 && markFire < N - 1);

		// 4. Distribute across the whole group span.
		cum = 0;
		for (int k = 0; k < seq.Size(); ++k)
		{
			int a = RemapPos(cum,          total, N, anchored, brightAt, markFire);
			int b = RemapPos(cum + dur[k], total, N, anchored, brightAt, markFire);
			m.mStates.Push(seq[k]);
			m.mMesh.Push(frames[a]);
			m.mMeshNext.Push(frames[b]);
			m.mGroupId.Push(gid);
			m.mEndIdx.Push(b);
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
