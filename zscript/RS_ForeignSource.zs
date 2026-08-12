// =====================================================================
// RS_ForeignSource -- WHICH WEAPONS BELONG TO THE MOD WE ARE LOADED WITH.
//
// AllActorClasses is not the mod's arsenal. GZDoom compiles the Heretic,
// Hexen, Strife and Chex Quest weapons into EVERY session out of
// game_support.pk3 -- Timon's Axe, Quietus, Bloodscourge, the Sigil, the
// Calamity Blade -- and none of them are obtainable in a Doom game. Left
// in, they bury the twenty weapons the player actually has under four
// hundred rows of arsenal from games nobody is playing.
//
// Two filters were tried and both are wrong:
//
//   * By class NAME. There are hundreds and the list rots the moment
//     anything is added -- a seventy-name list was already missing most
//     of Hexen's and all of Chex 3's.
//   * By "can the player select it" (the weapon slot table). Answers a
//     different question, and comes back empty on mods that bind their
//     arsenal through their own player class.
//
// The right question is PROVENANCE: what did the mod we are loaded
// alongside actually declare? And the answer is readable without asking
// the engine for anything new. Every mod declares its actors in DECORATE
// or ZSCRIPT lumps; Wads.FindLump walks every copy of those across every
// loaded file, GetLumpContainer says which file each came from, and
// ReadLump hands over the text. Skip the engine's own files and our own,
// parse what is left, and that IS the mod's roster.
//
// Nothing here knows the name of any mod. It knows the names of the four
// files the ENGINE ships, which is a fixed list that does not rot.
// =====================================================================

class RS_ForeignSource
{
	// Class names declared by files that are neither the engine's nor ours.
	Array<string> mDeclared;
	bool mBuilt;

	// Containers the engine itself provides. Everything else in the load is
	// either the mod or us. Matched case-insensitively on a substring so
	// version suffixes and paths do not matter.
	static bool IsEngineContainer(string cname)
	{
		string n = cname; n = n.MakeLower();
		return (n.IndexOf("gzdoom.pk3")         >= 0
		     || n.IndexOf("doomxr.pk3")         >= 0
		     || n.IndexOf("game_support.pk3")   >= 0
		     || n.IndexOf("game_widescreen")    >= 0
		     || n.IndexOf("game_optional")      >= 0);
	}

	// Pull every "actor <Name>" / "class <Name>" declaration out of one lump
	// and follow its #includes. Depth-limited: a malformed or circular
	// include set must not hang the game.
	void Harvest(int lump, int depth)
	{
		if (lump < 0 || depth > 8) return;

		string text = Wads.ReadLump(lump);
		if (text.Length() == 0) return;

		Array<string> lines;
		text.Split(lines, "\n");

		for (int i = 0; i < lines.Size(); ++i)
		{
			string ln = lines[i];
			// strip a trailing comment and surrounding whitespace
			int c = ln.IndexOf("//");
			if (c >= 0) ln = ln.Left(c);
			ln = ln.Filter();                 // drop \r and other control chars

			string low = ln; low = low.MakeLower();
			int p = -1;

			// "#include "DEC_WEPS"" -- DECORATE and ZScript both use it.
			int inc = low.IndexOf("#include");
			if (inc >= 0)
			{
				int q1 = ln.IndexOf("\"", inc);
				if (q1 >= 0)
				{
					int q2 = ln.IndexOf("\"", q1 + 1);
					if (q2 > q1)
					{
						string inm = ln.Mid(q1 + 1, q2 - q1 - 1);
						int il = Wads.CheckNumForFullName(inm);
						if (il < 0) il = Wads.FindLumpFullName(inm, 0, true);
						if (il < 0) il = Wads.FindLump(inm, 0);
						Harvest(il, depth + 1);
					}
				}
				continue;
			}

			// A declaration has to START the line -- "actor" and "class" both
			// appear inside state code and comments constantly.
			if (low.IndexOf("actor ") == 0)      { p = 6; }
			else if (low.IndexOf("class ") == 0) { p = 6; }
			else continue;

			// take the identifier
			string rest = ln.Mid(p);
			string nm = "";
			for (int k = 0; k < rest.Length(); ++k)
			{
				string ch = rest.Mid(k, 1);
				if (ch == " " || ch == "\t" || ch == ":" || ch == "{") break;
				nm = nm .. ch;
			}
			if (nm.Length() > 0) mDeclared.Push(nm);
		}
	}

	void Build()
	{
		mDeclared.Clear();
		mBuilt = true;

		// Our own container, so we never treat our donor stubs as the mod's.
		int ourLump = Wads.CheckNumForFullName("zscript/RS_ForeignModels.zs");
		int ourFile = (ourLump >= 0) ? Wads.GetLumpContainer(ourLump) : -1;

		// Walk EVERY lump rather than asking for one by name. Mods spell the
		// entry point half a dozen ways -- DECORATE, DECORATE.TXT, ZScript.zsc,
		// zscript.txt -- and whether the extension survives into the lump name
		// is not something to bet the whole feature on. Ashes Afterglow ships
		// DECORATE.TXT; asking for "DECORATE" found nothing and the filter
		// silently did not apply.
		int total = Wads.GetNumLumps();
		for (int l = 0; l < total; ++l)
		{
			string nm = Wads.GetLumpName(l);
			nm = nm.MakeLower();

			// strip an extension if the lump name kept one
			int dotPos = nm.IndexOf(".");
			if (dotPos > 0) nm = nm.Left(dotPos);

			if (nm != "decorate" && nm != "zscript") continue;

			int f = Wads.GetLumpContainer(l);
			if (f == ourFile) continue;
			if (IsEngineContainer(Wads.GetContainerName(l))) continue;

			Harvest(l, 0);
		}
	}

	// Did the loaded mod declare this class?
	bool Declares(string cls) const
	{
		for (int i = 0; i < mDeclared.Size(); ++i)
			if (mDeclared[i] == cls) return true;
		return false;
	}

	int Count() const { return mDeclared.Size(); }

	// If we found no mod files at all -- someone is running us against a bare
	// IWAD, or a mod ships neither lump under a name we looked for -- then
	// filtering on this would hide everything. Callers check this and fall
	// back to scanning the lot rather than showing an empty list.
	bool Usable() const { return mBuilt && mDeclared.Size() > 0; }
}
