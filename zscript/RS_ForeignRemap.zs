// =====================================================================
// RS_ForeignRemap -- THEIR STATE MACHINE IS THE CLOCK.
//
// The old animation engine watched behavior and predicted: learned
// durations, locked them, scaled them by ammo rates, guarded the rates
// with evidence gates, glued idle gaps, and detected boundaries. Every
// one of those mechanisms existed to reconstruct information the
// weapon already broadcasts every tic: WHICH STATE IT IS IN. This file
// replaces all of it with a lookup table.
//
// AT BIND TIME, ONCE PER (WEAPON CLASS, DONOR): walk the weapon's
// labeled state sequences -- Ready, Fire, AltFire, Reload, and the
// rest. Those labels are engine-structural, not conventions: the
// engine's own button code jumps to them by name (P_CheckWeaponButtons
// -> NAME_Reload etc.), so any weapon that responds to a button HAS
// them. Collect each sequence's states in order with their tic
// durations, and distribute the donor clip's per-tic frame list across
// that timeline proportionally. Store state -> (meshFrame, nextFrame).
//
// AT RUNTIME, PER TIC: psp.CurState -> one table lookup. Their
// conditionals, their branches, their per-shell loops, their refires
// all just happen -- whatever state their logic lands in, we show the
// frame mapped to it. Timing cannot drift from theirs because there is
// no timing of ours: a partial reload shows fewer of their states, a
// full one more, and the mesh follows. Nothing is learned, so nothing
// has to be learned three times, and the first shot of the first
// session is already right.
//
// THE KEY IS THE STATE POINTER, not (sprite, frame). Two sequences can
// share a sprite frame; they can never share a State. Pointers are
// stable for the session; the table is rebuilt lazily per session, so
// savegame restores across sessions just repopulate it.
//
// WHAT A WALK CAN'T SEE: states reached only through runtime A_Jump*
// side effects (a reload-done tail entered by an inventory check, a
// mod-custom combo label). Those are simply absent from the table, and
// the runtime holds the last mapped frame until their logic returns to
// mapped territory. Degrades to a pose, never to garbage.
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

	// -----------------------------------------------------------------
	// Labels in CLAIM ORDER, which is load-bearing. Sequences flow into
	// each other ("Goto Ready", fire falling into reload on empty), and
	// a state belongs to whichever sequence claimed it first. Ready
	// claims first so every transitional tail parks on the rest pose;
	// Reload claims before Fire so a Fire label that jumps straight to
	// reloading (the empty-mag auto-reload idiom) shows the reload
	// mapping the moment its states are entered.
	// -----------------------------------------------------------------
	static State RootFor(readonly<Weapon> def, int li)
	{
		switch (li)
		{
		case 0:  return def.FindState('Ready');
		case 1:  return def.FindState('Deselect');
		case 2:  return def.FindState('Select');
		case 3:  return def.FindState('Reload');
		case 4:  return def.FindState('Zoom');
		case 5:  return def.FindState('User1');
		case 6:  return def.FindState('User2');
		case 7:  return def.FindState('User3');
		case 8:  return def.FindState('User4');
		case 9:  return def.FindState('AltFire');
		case 10: return def.FindState('AltHold');
		case 11: return def.FindState('Fire');
		default: return def.FindState('Hold');
		}
	}

	static string ClipFor(int li)
	{
		switch (li)
		{
		case 3:  return "reload";
		case 9:  return "altfire";
		case 10: return "altfire";
		case 11: return "fire";
		case 12: return "fire";
		default: return "ready";
		}
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

		readonly<Weapon> def = GetDefaultByType(type);
		if (!def) return m;

		for (int li = 0; li <= 12; ++li)
		{
			State root = RootFor(def, li);
			if (root == null) continue;
			MapSequence(m, root, ClipFor(li), donorCls, clips, frameCount, restFrame);
		}
		return m;
	}

	static void MapSequence(RS_ForeignRemap m, State root, string seqName,
	                        string donorCls, RS_ForeignClip clips,
	                        int frameCount, int restFrame)
	{
		// 1. Collect the sequence: follow NextState until we revisit a
		// state (their loop), hit territory another sequence already
		// claimed, or run off the end. Goto is encoded as NextState, so
		// this follows the real authored flow, not a guess about it.
		Array<State> seq;
		Array<int>   dur;
		int total = 0;

		State s = root;
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
		if (seq.Size() == 0) return;

		// 2. The donor clip for this sequence, already expanded to a
		// per-tic frame list by RS_ForeignClip (authored pacing intact).
		Array<int> frames;
		int markFire;
		bool haveClip = clips.Get(donorCls, seqName, frameCount, frames, markFire)
		                && frames.Size() > 0;

		int rest = restFrame;
		if (frameCount > 0 && rest >= frameCount) rest = frameCount - 1;
		if (rest < 0) rest = 0;

		if (!haveClip || total <= 0)
		{
			// No clip on this donor for this sequence (or a sequence of
			// pure 0-tic states): every state parks on the rest pose.
			for (int k = 0; k < seq.Size(); ++k)
			{
				m.mStates.Push(seq[k]);
				m.mMesh.Push(rest);
				m.mMeshNext.Push(rest);
			}
			return;
		}

		int N = frames.Size();

		// 3. The shot anchor, now STATIC. Their bright frame is authored
		// into their states (bFullbright); our clip knows which of its
		// own frames is the shot (markFire). Pin those together and
		// interpolate on either side -- the recoil lands on the bang
		// without ever having observed a single shot.
		int brightAt = -1, cum = 0;
		for (int k = 0; k < seq.Size(); ++k)
		{
			if (dur[k] > 0 && seq[k].bFullbright) { brightAt = cum; break; }
			cum += dur[k];
		}
		bool anchored = (brightAt > 0 && brightAt < total
		              && markFire > 0 && markFire < N - 1);

		// 4. Distribute. Position t in their timeline -> index into our
		// per-tic frame list; each state stores its frame and the frame
		// its END lands on, so the runtime can lerp across multi-tic
		// states at display rate.
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
