// =====================================================================
// RS_ForeignPersist -- REMEMBERING WHAT WAS LEARNED, BETWEEN SESSIONS.
//
// The animation learns how long a weapon's sequences actually take by
// watching them. That knowledge is worth keeping: without it every new
// session spends the first few reloads of every weapon at natural rate
// while it works the same facts out again.
//
// THE KEY HAD TO CHANGE TO SAVE IT. At runtime a sequence is identified
// by the State POINTER it enters on, which is exact and needs no names --
// and which is a memory address, meaningless the moment the game
// restarts. So a saved entry is keyed by (weaponClass, sequenceName)
// instead: stable across sessions, stable across a mod being reloaded,
// and unique enough in practice because a weapon has one fire and one
// reload. The pointer stays the runtime key; this is only the archive.
//
// WHERE IT LIVES. ZScript cannot write files and cannot create cvars at
// runtime, so everything packs into one archived string cvar:
//
//     class:seq:duration:brightTic;class:seq:duration:brightTic;...
//
// A mod of twenty weapons produces maybe sixty entries, a couple of
// kilobytes. It is written only when a sequence LOCKS, which happens
// once per sequence ever, so this is not a per-tick cost.
// =====================================================================

class RS_ForeignPersist
{
	Array<string> mKeys;    // "WeaponClass|seq"
	Array<int>    mDur;
	Array<int>    mBright;
	bool          mDirty;

	static string MakeKey(string cls, string seq)
	{
		return cls .. "|" .. seq;
	}

	void Load()
	{
		mKeys.Clear(); mDur.Clear(); mBright.Clear();
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
			            .. mDur[i] .. ":" .. mBright[i] .. ";";
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

	bool Get(string cls, string seq, out int dur, out int bright) const
	{
		dur = 0; bright = -1;
		int i = Find(cls, seq);
		if (i < 0) return false;
		dur = mDur[i]; bright = mBright[i];
		return (dur > 0);
	}

	void Store(string cls, string seq, int dur, int bright)
	{
		if (dur <= 0) return;
		int i = Find(cls, seq);
		if (i < 0)
		{
			mKeys.Push(MakeKey(cls, seq));
			mDur.Push(dur);
			mBright.Push(bright);
		}
		else
		{
			if (mDur[i] == dur && mBright[i] == bright) return;   // no change
			mDur[i]    = dur;
			mBright[i] = bright;
		}
		mDirty = true;
		Save();
	}

	void Forget()
	{
		mKeys.Clear(); mDur.Clear(); mBright.Clear();
		mDirty = true;
		Save();
	}

	int Count() const { return mKeys.Size(); }
}
