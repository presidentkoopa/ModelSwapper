// =====================================================================
// RS_ForeignPersist -- REMEMBERING THE PLAYER'S CHOICES, BETWEEN
// SESSIONS.
//
// One archive lives here now: model picks. It keys on the weapon's
// CLASS NAME rather than anything mod-specific, which is what makes it
// work as a de facto per-mod profile without ever having to know what a
// "mod" is: only one mod's weapon classes exist in the world at a time,
// so a class name is already scoped to whichever mod is loaded. Load
// Ashes, pick models, quit; load Golden Souls, pick different ones; go
// back to Ashes next week and its picks are still there, because Golden
// Souls never wrote an entry under Ashes' class names. (Two different
// mods reusing an identical class name would collide -- rare enough
// that this does not guard against it.)
//
// There used to be a second archive here: learned sequence timings.
// The remap engine (RS_ForeignRemap) made it meaningless -- timing now
// comes from the weapon's own state table, read fresh each session in
// milliseconds, so there is nothing to remember.
//
// WHERE IT LIVES. ZScript cannot write files and cannot create cvars at
// runtime, so the archive packs into one archived string cvar:
//
//     picks: class:archetype:pick1:pick2;class:archetype:pick1:pick2;...
//
// At most one entry per weapon, written only when the player changes a
// pick. Not a per-tick cost.
// =====================================================================

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

	// Written every time the player changes a pick -- a few times a session
	// by hand, so the immediate Save costs nothing. Batch writers (the
	// random-assign button) pass save=false per row and call Save() ONCE
	// after: per-row saving rebuilds the whole growing blob every call,
	// which at hundreds of rows is quadratic string churn measured in the
	// hundreds of megabytes -- a multi-second main-thread stall that killed
	// a VR session outright before this parameter existed.
	void Store(string cls, string arch, int p1, int p2, bool save = true)
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
		if (save) Save();
	}

	void Forget()
	{
		mCls.Clear(); mArch.Clear(); mPick1.Clear(); mPick2.Clear();
		Save();
	}

	int Count() const { return mCls.Size(); }
}
