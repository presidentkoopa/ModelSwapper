// =====================================================================
// RS_ForeignPersist -- REMEMBERING WHAT WAS LEARNED, BETWEEN SESSIONS.
//
// Two archives live in this file, both for the same reason: something
// was worked out once -- by watching, or by the player's own hand -- and
// re-deriving it from nothing every session would waste either CPU or
// patience. Both key on the weapon's CLASS NAME rather than anything
// mod-specific, which is what makes them work as de facto per-mod
// profiles without either archive ever having to know what a "mod" is:
// only one mod's weapon classes exist in the world at a time, so a class
// name is already scoped to whichever mod is loaded. Load Ashes, pick
// models, quit; load Golden Souls, pick different ones; go back to Ashes
// next week and its picks are still there, because Golden Souls never
// wrote an entry under Ashes' class names. Two different mods reusing an
// identical class name would collide -- unlikely enough in practice that
// neither archive guards against it, same tradeoff either has always
// made.
//
// THE TIMING ARCHIVE. The animation learns how long a weapon's sequences
// actually take by watching them. At runtime a sequence is identified by
// the State POINTER it enters on, which is exact and needs no names --
// and which is a memory address, meaningless the moment the game
// restarts. So a saved entry is keyed by (weaponClass, sequenceName)
// instead: stable across sessions, stable across a mod being reloaded,
// and unique enough in practice because a weapon has one fire and one
// reload. The pointer stays the runtime key; this is only the archive.
//
// Duration alone was never enough for a reload: a six-shell tube reload
// and a one-shell top-up can be the same entry state and wildly different
// lengths, and locking one fixed number meant every reload but the kind
// that got observed first looked compressed or smeared. restoreUnits is
// how much ammo the SAME locked run actually restored, saved alongside
// the duration it took -- together they're a rate (tics per unit), so a
// future reload can be timed to how much IT is short, not to whatever the
// first three runs happened to be.
//
// THE PICK ARCHIVE. `pinned` -- a player's manual model choice -- used to
// survive a map change (RS_ForeignModelHandler.Rescan carries it in
// memory) but not a restart: quit and relaunch the same mod and every
// hand-picked model was gone, re-guessed from scratch. Keyed the same
// way, by class name, so it needs nothing the timing archive doesn't
// already have.
//
// WHERE IT LIVES. ZScript cannot write files and cannot create cvars at
// runtime, so each archive packs into one archived string cvar:
//
//     timing:  class:seq:duration:brightTic;class:seq:duration:brightTic;...
//     picks:   class:archetype:pick1:pick2;class:archetype:pick1:pick2;...
//
// A mod of twenty weapons produces maybe sixty timing entries, a couple
// of kilobytes -- and at most twenty pick entries, one per weapon. Timing
// is written only when a sequence LOCKS, once per sequence ever; a pick
// is written only when the player changes it. Neither is a per-tick cost.
// =====================================================================

class RS_ForeignPersist
{
	Array<string> mKeys;    // "WeaponClass|seq"
	Array<int>    mDur;
	Array<int>    mBright;
	Array<int>    mRestore; // ammo restored during the SAME run mDur was taken from; 0 = no rate
	bool          mDirty;

	static string MakeKey(string cls, string seq)
	{
		return cls .. "|" .. seq;
	}

	void Load()
	{
		mKeys.Clear(); mDur.Clear(); mBright.Clear(); mRestore.Clear();
		mDirty = false;

		CVar c = CVar.FindCVar("rs_fm_learned");
		if (!c) return;
		string blob = c.GetString();
		if (blob.Length() == 0) return;

		Array<string> recs;
		blob.Split(recs, ";");
		for (int i = 0; i < recs.Size(); ++i)
		{
			if (recs[i].Length() == 0) continue;
			Array<string> f;
			recs[i].Split(f, ":");
			if (f.Size() < 4) continue;
			mKeys.Push(MakeKey(f[0], f[1]));
			mDur.Push(f[2].ToInt());
			mBright.Push(f[3].ToInt());
			// 5th field is newer than the format's first release -- a record
			// saved before rate-learning existed simply has none, and reads
			// back as 0 ("no rate known"), same as if it had never applied.
			mRestore.Push((f.Size() >= 5) ? f[4].ToInt() : 0);
		}
	}

	void Save()
	{
		if (!mDirty) return;
		CVar c = CVar.FindCVar("rs_fm_learned");
		if (!c) return;

		string blob = "";
		for (int i = 0; i < mKeys.Size(); ++i)
		{
			Array<string> k;
			mKeys[i].Split(k, "|");
			if (k.Size() < 2) continue;
			blob = blob .. k[0] .. ":" .. k[1] .. ":"
			            .. mDur[i] .. ":" .. mBright[i] .. ":" .. mRestore[i] .. ";";
		}
		c.SetString(blob);
		mDirty = false;
	}

	int Find(string cls, string seq) const
	{
		string k = MakeKey(cls, seq);
		for (int i = 0; i < mKeys.Size(); ++i)
			if (mKeys[i] == k) return i;
		return -1;
	}

	bool Get(string cls, string seq, out int dur, out int bright, out int restoreUnits) const
	{
		dur = 0; bright = -1; restoreUnits = 0;
		int i = Find(cls, seq);
		if (i < 0) return false;
		dur = mDur[i]; bright = mBright[i]; restoreUnits = mRestore[i];
		return (dur > 0);
	}

	void Store(string cls, string seq, int dur, int bright, int restoreUnits)
	{
		if (dur <= 0) return;
		int i = Find(cls, seq);
		if (i < 0)
		{
			mKeys.Push(MakeKey(cls, seq));
			mDur.Push(dur);
			mBright.Push(bright);
			mRestore.Push(restoreUnits);
		}
		else
		{
			if (mDur[i] == dur && mBright[i] == bright
			 && mRestore[i] == restoreUnits) return;   // no change
			mDur[i]     = dur;
			mBright[i]  = bright;
			mRestore[i] = restoreUnits;
		}
		mDirty = true;
		Save();
	}

	void Forget()
	{
		mKeys.Clear(); mDur.Clear(); mBright.Clear(); mRestore.Clear();
		mDirty = true;
		Save();
	}

	int Count() const { return mKeys.Size(); }
}

// ---------------------------------------------------------------------
// The pick archive. See the file header -- keyed on class name only, no
// notion of "which mod" anywhere, which is what makes this a de facto
// per-mod profile without ever having to track one.
// ---------------------------------------------------------------------
class RS_ForeignPickPersist
{
	Array<string> mCls;
	Array<string> mArch;
	Array<int>    mPick1;
	Array<int>    mPick2;

	void Load()
	{
		mCls.Clear(); mArch.Clear(); mPick1.Clear(); mPick2.Clear();

		CVar c = CVar.FindCVar("rs_fm_picks");
		if (!c) return;
		string blob = c.GetString();
		if (blob.Length() == 0) return;

		Array<string> recs;
		blob.Split(recs, ";");
		for (int i = 0; i < recs.Size(); ++i)
		{
			if (recs[i].Length() == 0) continue;
			Array<string> f;
			recs[i].Split(f, ":");
			if (f.Size() < 4) continue;
			mCls.Push(f[0]);
			mArch.Push(f[1]);
			mPick1.Push(f[2].ToInt());
			mPick2.Push(f[3].ToInt());
		}
	}

	void Save()
	{
		CVar c = CVar.FindCVar("rs_fm_picks");
		if (!c) return;

		string blob = "";
		for (int i = 0; i < mCls.Size(); ++i)
			blob = blob .. mCls[i] .. ":" .. mArch[i] .. ":"
			            .. mPick1[i] .. ":" .. mPick2[i] .. ";";
		c.SetString(blob);
	}

	int Find(string cls) const
	{
		for (int i = 0; i < mCls.Size(); ++i)
			if (mCls[i] == cls) return i;
		return -1;
	}

	// Returns false (leaving arch/p1/p2 untouched) if this class has never
	// been saved -- the caller's own guessed defaults stand in that case.
	bool Get(string cls, out string arch, out int p1, out int p2) const
	{
		int i = Find(cls);
		if (i < 0) return false;
		arch = mArch[i]; p1 = mPick1[i]; p2 = mPick2[i];
		return true;
	}

	// Written every time the player changes a pick. That is at most a few
	// times a session by hand -- or up to one row per weapon in one shot
	// from the random-assign button -- so, unlike the timing archive, this
	// does not bother batching: correctness (never losing a pick to a
	// crash) is worth more than the write count here.
	void Store(string cls, string arch, int p1, int p2)
	{
		int i = Find(cls);
		if (i < 0)
		{
			mCls.Push(cls); mArch.Push(arch); mPick1.Push(p1); mPick2.Push(p2);
		}
		else
		{
			mArch[i] = arch; mPick1[i] = p1; mPick2[i] = p2;
		}
		Save();
	}

	void Forget()
	{
		mCls.Clear(); mArch.Clear(); mPick1.Clear(); mPick2.Clear();
		Save();
	}

	int Count() const { return mCls.Size(); }
}
