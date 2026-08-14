// =====================================================================
// RS_ForeignModels -- OUR MODELS ON THEIR WEAPONS.
//
// Scans every weapon class loaded alongside us (any wad/pk3), guesses an
// archetype, and paints one of OUR HUD models over it. Their code, their
// damage, their projectiles, their effects, their sounds all run
// untouched underneath -- the ONLY thing we replace is the mesh in the
// player's hands.
//
// HOW THE BIND WORKS (two steps, both runtime, no MODELDEF authoring):
//   1. A_ChangeModel(<ourClass>) sets the foreign weapon's per-instance
//      modelData->modelDef. The HUD render path resolves models against
//      psp->Caller's model data before falling back to its class
//      (models.cpp FindModelFrame(AActor*)), so lookup now lands in OUR
//      modeldef block -- carrying its Path/Skin/Scale/Offset/ZOffset.
//   2. Frame lookup still keys on sprite+frame, so the psprite is pinned
//      to our anchor sprite at the archetype's RESTING LETTER. That is a
//      sprite letter index (A=0), NOT a model frame -- the donor's own
//      MODELDEF does letter -> model frame, and rides along with step 1.
//
// Step 1 runs once per weapon INSTANCE. Step 2 has to run per tick because
// the foreign weapon's own states re-set the psprite sprite every frame.
//
// CLASSIFICATION is a guess and is MEANT to be overridden. Order:
//   name/tag tokens -> melee flag (only if no ammo) -> ammo-class tokens
//   -> parent class -> SLOT NUMBER.
// The slot fallback means nothing is ever left without a model: a weapon
// we can't read at all still gets the Doom-default gun for its slot.
// A trumpet in slot 5 gets a rocket launcher, and that is correct
// behaviour -- the player retunes it from the picker.
//
// Archetype vocabulary is RS_Weapon.GetPaletteArchetype()'s, not a new
// one. Model shelves mirror RSWFAM.txt (authoring source; kept in sync
// by hand for now).
//
// GATED behind cvar `rs_foreignmodels`. Off = nothing here runs.
// =====================================================================

class RS_ForeignEntry
{
	string clsName;       // the foreign weapon's class name
	string tag;           // display tag (falls back to class name)
	int    slot;          // runtime slot, -1 = none
	string archetype;     // guessed archetype (our vocabulary)
	bool   guessedBySlot; // true = name/ammo told us nothing
	bool   located;       // player has a slot binding for it (see Scan)
	bool   modDefined;    // class name found in a sideloaded archive's own
	                      // DECORATE/ZSCRIPT text (see HarvestModClasses) --
	                      // false for everything the engine compiles in
	string srcContainer;  // archive that defined it, when modDefined
	int    modelPick1;    // MAINHAND  model: index into the archetype's shelf
	int    modelPick2;    // OFFHAND   model: independent pick, same shelf
	bool   pinned;        // player chose this; don't re-guess
	// (no "applied" flag -- binding is tracked per-instance on the handler)
}

// ---------------------------------------------------------------------
// The shelves. One archetype -> N of our models. Mirrors RSWFAM.txt.
// Encoded "archetype|modeldefClass|anchorSprite|heldFrame".
// ---------------------------------------------------------------------
class RS_ForeignShelf
{
	// Built ONCE at world-load. Get() runs per player per hand per tick, so
	// re-parsing 40 rows and re-resolving every donor class on each call was
	// pure waste.
	Array<string> mRows;

	void Build()
	{
		// The 4th field is a SPRITE LETTER INDEX (A=0, B=1, C=2 ...) -- it is
		// what psp.Frame takes. It is NOT the model frame; the donor class's
		// own MODELDEF maps letter -> model frame (e.g. HBPS A -> model frame
		// 2), and that mapping comes along for free with the modelDef
		// override. Verified against every RS_ weapon's Ready: state: they
		// all rest on letter A except RS_PS_Chainsaw, which rests on SAWG C.
		// FIELDS: archetype | donorClass | anchorSprite | restLetter | restFrame | frameCount
		//
		//   restLetter -- sprite letter index for psp.Frame (A=0). Only has to
		//                 resolve so FindModelFrame returns an smf; everything
		//                 geometric (scale, offsets, skin, flags) comes from it.
		//   restFrame  -- the MODEL frame of the resting pose, for psp.ModelFrame.
		//                 Extracted from each donor's own MODELDEF FrameIndex
		//                 table. This is where the numbers that took two builds
		//                 to find by noticing tilted guns actually live:
		//                 chainsaw 27, BFG 6, rocket 5, SSG 1.
		//   frameCount -- MD3 header frame count. The engine deliberately does
		//                 NOT clamp an out-of-range ModelFrame -- RenderFrame
		//                 rejects it and the weapon becomes INVISIBLE -- so the
		//                 bound is ours to enforce. It is also the ceiling for
		//                 every animation clip on this donor.
		static const string SHELF[] = {
			"pistol|RS_GH_Pistol|HBPS|0|2|38",
			"pistol|VR_Pistol|PISG|0|0|32",
			"revolver|RS_GH_Revolver|HBRV|0|0|33",
			"revolver|VR_Revolver|REVL|0|0|41",
			"smg|RS_GH_SMG|HBSM|0|3|27",
			"smg|RS_GH_MP40|HBMP|0|2|14",
			"smg|VR_SMG|SMGG|0|3|27",
			"smg|RS_PS_Machinegun|MGNG|0|0|6",
			"rifle|RS_GH_Rifle|HBRI|0|3|32",
			"rifle|VR_Rifle|RIFL|0|0|41",
			"shotgun|RS_GH_PumpShotgun|HBSG|0|4|36",
			"shotgun|VR_Shotgun|SHTG|0|0|32",
			"shotgun|RS_GH_AssaultShotgun|HBAG|0|4|32",
			"shotgun|RS_PS_AutoShotgun|SHTG|0|0|4",
			"supershotgun|RS_GH_SSG|HBSS|0|1|52",
			"supershotgun|VR_SuperShotgun|SHT2|0|0|26",
			"supershotgun|RS_PS_SSG|SSGG|0|0|12",
			"machinegun|RS_GH_Machinegun|HBMG|0|4|36",
			"chaingun|RS_GH_Minigun|HBMN|0|4|16",
			"chaingun|VR_Chaingun|CHGG|0|4|16",
			"chaingun|RS_PS_Chaingun|MGUG|0|0|6",
			"rocket|RS_GH_RocketLauncher|HBRL|0|5|39",
			"rocket|VR_RocketLauncher|MISG|0|5|39",
			"rocket|RS_GH_GrenadeLauncher|HBGL|0|3|33",
			"rocket|RS_PS_RocketLauncher|RLNC|0|0|7",
			"plasma|RS_GH_Plasma|HBPL|0|4|30",
			"plasma|VR_PlasmaRifle|PLSG|0|4|30",
			"plasma|RS_PS_Plasma|PLSC|0|0|5",
			"railgun|RS_GH_Railgun|HBRA|0|3|37",
			"flamethrower|RS_GH_Flamethrower|HBFT|0|0|6",
			"bfg|RS_GH_BFG9000|HBBF|0|6|16",
			"bfg|VR_BFG9000|BFGG|0|6|16",
			"bfg|RS_GH_BFG10k|HBBT|0|6|21",
			"bfg|RS_PS_BFG|BFGN|0|0|11",
			"melee|RS_GH_Fist|HBFS|0|0|75",
			"melee|RS_PS_Fist|FSTZ|0|0|9",

			// ---- standalone ModelSwapper.pk3 donors (MS_ namespace) ----
			// Present only when the standalone asset pk3 is loaded; dropped
			// automatically otherwise. Listing both sets means ONE build of
			// this file works whether the donors come from RS_Main or from
			// the standalone pk3.
			"pistol|MS_Pistol|PISG|0|0|32",
			"revolver|MS_Revolver|PISG|0|0|41",
			"rifle|MS_Rifle|CHGG|0|0|41",
			"shotgun|MS_Shotgun|SHTG|0|0|32",
			"supershotgun|MS_SuperShotgun|SHT2|0|0|26",
			"chaingun|MS_Chaingun|CHGG|0|4|16",
			"rocket|MS_RocketLauncher|MISG|0|5|39",
			"plasma|MS_PlasmaRifle|PLSG|0|4|30",
			"flamethrower|MS_Flamethrower|PLSG|0|0|6",
			"bfg|MS_BFG9000|BFGG|0|6|16",
			"bfg|MS_VR_BFG9000|BFGG|0|6|16",
			"bfg|MS_BFG10k|BFGG|0|6|21",
			"melee|MS_Fist|PUNG|0|0|57",

			// ---- GoldHunter set. Fills the two families the VR set has no
			// model for at all (smg, railgun) and gives every other family a
			// second and third option.
			"pistol|MS_GH_Pistol|PISG|0|2|38",
			"revolver|MS_GH_Revolver|PISG|0|0|33",
			"rifle|MS_GH_Rifle|CHGG|0|3|32",
			"smg|MS_GH_SMG|CHGG|0|3|27",
			"smg|MS_GH_MP40|CHGG|0|2|14",
			"chaingun|MS_GH_Minigun|CHGG|0|4|16",
			"shotgun|MS_GH_AutoShotgun|SHTG|0|4|32",
			"launcher|MS_GH_GrenadeLauncher|MISG|0|3|33",
			"plasma|MS_GH_Plasma|PLSG|0|4|30",
			"railgun|MS_GH_Railgun|PLSG|0|3|37",
			"melee|MS_GH_Fist|PUNG|0|0|75",

			// ---- MeatGrinder set. Nine models in 6MB, and a grittier look
			// than either of the others -- the cheapest breadth on offer.
			"melee|MS_MG_Knife|PUNG|0|0|9",

			// ---- axe/blade: a held edge, not a bare hand ----
			"axe|MS_MG_Knife|PUNG|0|0|9",

			// ---- thrown explosives ----
			// A hand grenade is not a rocket launcher. Every mod with a frag
			// or a pipe bomb was getting an RPG welded to its hand.
			"grenade|MS_GH_Grenade|MISG|0|2|27",

			// ---- saws, on their own shelf ----
			"saw|MS_Chainsaw|SAWG|0|0|8",
			"saw|MS_GH_Chainsaw|SAWG|0|27|65",
			"saw|MS_MG_Saw|SAWG|0|2|6",
			"saw|VR_Chainsaw|SAWG|0|0|8",
			"saw|RS_GH_Chainsaw|HBCS|0|27|65",
			"saw|RS_PS_Chainsaw|SAWG|2|2|6",
			"smg|MS_MG_Tec9|CHGG|0|0|6",
			"shotgun|MS_MG_Shotgun|SHTG|0|0|4",
			"supershotgun|MS_MG_SSG|SHT2|0|0|12",
			"chaingun|MS_MG_Chaingun|CHGG|0|0|6",
			"rocket|MS_MG_RPG|MISG|0|0|7",
			"plasma|MS_MG_Bolter|PLSG|0|0|5",
			"bfg|MS_MG_BFG|BFGG|0|0|11",

			// The Bolter is a handheld -- it reads as a high-power sidearm or
			// a compact rifle just as well as an energy weapon, so it sits on
			// three shelves. Nothing stops a donor appearing under more than
			// one archetype; the row is the same, only the shelf differs.
			"pistol|MS_MG_Bolter|PLSG|0|0|5",
			"rifle|MS_MG_Bolter|PLSG|0|0|5",

			// ---- Brutal Wolfenstein set. Real WW2 weapons, which is what a
			// post-apocalyptic or contemporary mod actually wants -- Ashes'
			// arsenal is scavenged small arms, not Doom's science fiction.
			//
			// Note the idle frames. These are NOT 0: the MG42 rests at 12 of
			// 97, the STG44 and MP40 at 13. Under the old sprite-letter route
			// most of these meshes were unreachable AND would have rested in
			// the wrong pose. Read out of each weapon's own state that calls
			// A_WeaponReady, which is the idle by definition -- the label
			// "Ready:" is the DEPLOY animation in this mod and would have put
			// the Luger at frame 53.
			"pistol|MS_BW_Colt|PISG|0|1|60",
			"pistol|MS_BW_Luger|PISG|0|0|61",
			"rifle|MS_BW_Kar98|CHGG|0|1|44",
			"rifle|MS_BW_Garand|CHGG|0|1|36",
			"rifle|MS_BW_STG44|CHGG|0|13|51",
			"smg|MS_BW_MP40|CHGG|0|13|48",
			"smg|MS_BW_Thompson|CHGG|0|1|53",
			"machinegun|MS_BW_MG42|CHGG|0|12|97",
			"shotgun|MS_BW_Trenchgun|SHTG|0|1|47",
			"flamethrower|MS_BW_Flamethrower|PLSG|0|0|15",

			// The Kar98 is a bolt-action rifle -- it reads as a marksman
			// weapon as well as a battle rifle, so it also sits on railgun,
			// which otherwise has one model.
			"railgun|MS_BW_Kar98|CHGG|0|1|44",

			// ---- sniper ----
			// The Kar98 is a bolt-action: one shot, work the bolt, shoot
			// again. It reads as a marksman weapon far better than as a
			// battle rifle, and it is the only mesh here with that
			// silhouette. The Garand backs it up, and the Railgun is the
			// long scoped-looking option for a sci-fi mod.
			"sniper|MS_BW_Kar98|CHGG|0|1|44",
			"sniper|MS_BW_Garand|CHGG|0|1|36",
			"sniper|MS_GH_Railgun|PLSG|0|3|37",

			// ---- the rest of the GoldHunter set, and the VR SMG. All four
			// donor sets are now complete: VR, GoldHunter, MeatGrinder and
			// Brutal Wolfenstein.
			"supershotgun|MS_GH_SSG|SHT2|0|1|52",
			"shotgun|MS_GH_PumpShotgun|SHTG|0|4|36",
			"machinegun|MS_GH_Machinegun|CHGG|0|4|36",
			"unmaker|MS_GH_Unmaker|BFGG|0|0|16",
			"smg|MS_SMG|CHGG|0|3|27"
		};
		mRows.Clear();
		for (int i = 0; i < SHELF.Size(); ++i)
		{
			// Drop any row whose donor class is not loaded. A MODELDEF block
			// is inert without a real actor class owning its name, and
			// A_ChangeModel would print "invalid modeldef name" on every
			// weapon select if pointed at nothing.
			Array<string> f;
			SHELF[i].Split(f, "|");
			if (f.Size() < 6) continue;
			if (!DonorExists(f[1])) continue;
			mRows.Push(SHELF[i]);
		}
	}

	// Is this donor class actually present in the current load?
	static bool DonorExists(string cls)
	{
		return ((class<Actor>)(cls) != null);
	}

	// Nearest neighbour when an archetype has no models in this load. One hop
	// only -- if the fallback is also empty the weapon keeps its own sprite,
	// which is honest, rather than chaining to something absurd.
	static string FallbackArchetype(string a)
	{
		if (a == "saw")          return "melee";
		if (a == "axe")          return "melee";
		if (a == "grenade")      return "rocket";
		if (a == "sniper")       return "rifle";
		if (a == "machinegun")  return "chaingun";
		if (a == "launcher")    return "rocket";
		if (a == "unmaker")     return "bfg";
		if (a == "smg")          return "pistol";
		if (a == "railgun")      return "rifle";
		if (a == "revolver")     return "pistol";
		if (a == "supershotgun") return "shotgun";
		if (a == "flamethrower") return "plasma";
		return "";
	}

	// Is this row's donor the first occurrence of that donor in the table?
	// A donor can sit on several shelves -- the Bolter is a sidearm, a rifle
	// and an energy weapon -- and the "any" shelf must list it once.
	bool FirstOf(int row) const
	{
		Array<string> f;
		mRows[row].Split(f, "|");
		if (f.Size() < 2) return false;
		for (int i = 0; i < row; ++i)
		{
			Array<string> g;
			mRows[i].Split(g, "|");
			if (g.Size() >= 2 && g[1] == f[1]) return false;
		}
		return true;
	}

	// how many models sit on this archetype's shelf
	int Count(string arche) const
	{
		// "any" is every model we have, deduped -- the escape hatch for
		// putting a specific mesh on a specific weapon regardless of what the
		// classifier thinks it is. A chainsaw on a rocket launcher is a
		// legitimate thing to want and nothing should be in the way of it.
		if (arche == "any")
		{
			int t = 0;
			for (int i = 0; i < mRows.Size(); ++i)
				if (FirstOf(i)) t++;
			return t;
		}

		string pfx = arche .. "|";
		int n = 0;
		for (int i = 0; i < mRows.Size(); ++i)
			if (mRows[i].IndexOf(pfx) == 0) n++;
		return n;
	}

	// pick N off the shelf -> donor class, anchor sprite, rest letter,
	// rest MODEL frame, and the donor's total frame count.
	bool Get(string arche, int pick, out string cls, out string anchor,
	         out int frame, out int restFrame, out int frameCount) const
	{
		cls = ""; anchor = ""; frame = 0; restFrame = 0; frameCount = 0;

		// Wrap the pick into what this shelf actually HAS. Rows are dropped at
		// build time when their donor class is absent, so a shelf is shorter in
		// a standalone load than in a full RS_Main one -- and the slot-8
		// fallback asks for index 2 of the bfg shelf, which only has two
		// entries standalone. Without this every slot-8 weapon silently got no
		// model at all.
		int have = Count(arche);

		// "any" walks the whole table, one entry per donor.
		if (arche == "any")
		{
			if (have <= 0) return false;
			if (pick < 0 || pick >= have) pick = ((pick % have) + have) % have;

			int seen2 = 0;
			for (int i = 0; i < mRows.Size(); ++i)
			{
				if (!FirstOf(i)) continue;
				if (seen2 == pick)
				{
					Array<string> f;
					mRows[i].Split(f, "|");
					if (f.Size() < 6) return false;
					cls        = f[1];
					anchor     = f[2];
					frame      = f[3].ToInt();
					restFrame  = f[4].ToInt();
					frameCount = f[5].ToInt();
					return true;
				}
				seen2++;
			}
			return false;
		}

		// An archetype with no shelf at all in this load falls back one hop to
		// the nearest thing we do have. The standalone pk3 ships 13 donors and
		// has no SMG and no railgun -- so every Ashes Ingram, the entire reason
		// the smg token block exists, would have got nothing.
		if (have <= 0)
		{
			string alt = FallbackArchetype(arche);
			if (alt.Length() == 0) return false;
			arche = alt;
			have  = Count(arche);
		}
		if (have <= 0) return false;
		if (pick < 0 || pick >= have) pick = ((pick % have) + have) % have;

		string pfx = arche .. "|";
		int seen = 0;
		for (int i = 0; i < mRows.Size(); ++i)
		{
			if (mRows[i].IndexOf(pfx) != 0) continue;
			if (seen == pick)
			{
				Array<string> f;
				mRows[i].Split(f, "|");
				if (f.Size() < 6) return false;
				cls        = f[1];
				anchor     = f[2];
				frame      = f[3].ToInt();
				restFrame  = f[4].ToInt();
				frameCount = f[5].ToInt();
				return true;
			}
			seen++;
		}
		return false;
	}
}

class RS_ForeignScanner
{
	// -----------------------------------------------------------------
	// Guess an archetype. Never returns "" -- slot fallback catches all.
	// -----------------------------------------------------------------
	static string Classify(class<Weapon> type, string clsName, string tag,
	                       int slot, string ammo1, string ammo2,
	                       out bool bySlot, out int pick)
	{
		bySlot = false;
		pick   = 0;

		readonly<Weapon> def = GetDefaultByType(type);

		// 1. NAME + TAG tokens run FIRST -- ahead of the melee flag.
		//    Mods set +MELEEWEAPON for autoaim/alert behaviour on things
		//    that are not melee weapons at all: Ashes flags its SawedOff
		//    double-barrel, which used to come out as bare fists. A
		//    positive weapon token beats the flag.
		string hay = clsName; hay = hay.MakeLower();
		string lt  = tag;     lt  = lt.MakeLower();
		hay = hay .. " " .. lt;

		string a = TokenArchetype(hay);
		if (a.Length() > 0) return a;

		// 2. melee flag, but ONLY on a weapon that carries no ammo at all.
		//    A gun with a magazine is not a fist no matter what it flags.
		if (def && def.bMeleeWeapon && ammo1.Length() == 0 && ammo2.Length() == 0)
			return "melee";

		// 3. ammo class names -- BOTH slots. Reload-based mods put a
		//    magazine pseudo-ammo in slot 1 ("GlockLoaded", "musketloaded")
		//    and the REAL pool in slot 2 ("fortyfiveammo", "shotgunammo").
		//    Reading only slot 1 made this rule dead code on every Ashes
		//    weapon.
		a = AmmoArchetype(ammo1);
		if (a.Length() > 0) return a;
		a = AmmoArchetype(ammo2);
		if (a.Length() > 0) return a;

		// 4. INHERIT from the parent weapon class. Tiered variants of one
		//    gun (Ingram / Ingram2 / Ingram3) share a parent whose name
		//    still carries the token, so they stop scattering across three
		//    different archetypes.
		class<Object> par = type.GetParentClass();
		while (par != null && par != "Weapon")
		{
			a = TokenArchetype(("" .. par.GetClassName()).MakeLower());
			if (a.Length() > 0) return a;
			par = par.GetParentClass();
		}

		// 5. SLOT FALLBACK -- the "nothing goes unmodelled" rule.
		bySlot = true;
		return SlotArchetype(slot, pick);
	}

	// Archetype from an ammo class name, tokens first then the vanilla pools.
	static string AmmoArchetype(string ammo)
	{
		if (ammo.Length() == 0) return "";
		string la = ammo; la = la.MakeLower();

		string a = TokenArchetype(la);
		if (a.Length() > 0) return a;

		if (la.IndexOf("shell") >= 0)  return "shotgun";
		if (la.IndexOf("rocket") >= 0) return "rocket";
		if (la.IndexOf("cell") >= 0)   return "plasma";
		if (la.IndexOf("clip") >= 0)   return "pistol";
		return "";
	}

	// contains-match archetype words, ordered so the specific wins
	static string TokenArchetype(string hay)
	{
		// SUPERSHOTGUN before SHOTGUN, and both before the SMG/pistol
		// checks -- "sawedoff" must not fall through to melee.
		if (hay.IndexOf("supershot") >= 0 || hay.IndexOf("ssg") >= 0
		 || hay.IndexOf("doublebarrel") >= 0 || hay.IndexOf("double barrel") >= 0
		 || hay.IndexOf("sawedoff") >= 0 || hay.IndexOf("sawed-off") >= 0
		 || hay.IndexOf("sawed off") >= 0 || hay.IndexOf("coachgun") >= 0) return "supershotgun";
		if (hay.IndexOf("shotgun") >= 0 || hay.IndexOf("shotty") >= 0
		 || hay.IndexOf("trenchgun") >= 0 || hay.IndexOf("boomstick") >= 0
		 || hay.IndexOf("pumpaction") >= 0) return "shotgun";
		if (hay.IndexOf("revolver") >= 0 || hay.IndexOf("magnum") >= 0) return "revolver";
		// SMG before PISTOL: "Machine Pistol" is an SMG, and the space
		// variant is why the old machinepistol token missed Ashes' Ingram.
		if (hay.IndexOf("smg") >= 0 || hay.IndexOf("machinepistol") >= 0
		 || hay.IndexOf("machine pistol") >= 0 || hay.IndexOf("ingram") >= 0
		 || hay.IndexOf("mac10") >= 0 || hay.IndexOf("mac-10") >= 0
		 || hay.IndexOf("uzi") >= 0 || hay.IndexOf("mp40") >= 0
		 || hay.IndexOf("tec9") >= 0 || hay.IndexOf("sten") >= 0) return "smg";
		// PLASMA before every generic shape word below it. id Software's own
		// canonical weapon name is "Plasma Rifle" -- it contains "rifle", and
		// the rifle check used to run first, so the single most standard
		// energy weapon in the genre was coming out as an assault rifle.
		// "plasma" is specific enough that it should win over any of the
		// generic shape tokens (rifle, launcher, rocket...) it might
		// legitimately co-occur with, the same reasoning as SNIPER before
		// RIFLE below -- just generalised, since rifle isn't the only word
		// a plasma weapon could be named alongside.
		if (hay.IndexOf("plasma") >= 0 || hay.IndexOf("energy") >= 0
		 || hay.IndexOf("beam") >= 0) return "plasma";
		// MACHINEGUN before CHAINGUN. A fixed single barrel on a bipod (an
		// MG42, a GH machinegun) is a different weapon from a rotating
		// barrel cluster (a minigun, a Vulcan/gatling chaingun) -- neither
		// looks nor handles like the other, and "machinegun" was folding
		// into "chaingun" and getting a rotary barrel welded onto a fixed one.
		if (hay.IndexOf("machinegun") >= 0 || hay.IndexOf("machine gun") >= 0
		 || hay.IndexOf("mg42") >= 0 || hay.IndexOf("lmg") >= 0
		 || hay.IndexOf("bipod") >= 0
		 || hay.IndexOf("m249") >= 0 || hay.IndexOf("m60") >= 0) return "machinegun";

		if (hay.IndexOf("chaingun") >= 0 || hay.IndexOf("minigun") >= 0
		 || hay.IndexOf("gatling") >= 0 || hay.IndexOf("vulcan") >= 0
		 || hay.IndexOf("rotary") >= 0) return "chaingun";
		// SNIPER before RIFLE -- a scoped bolt-action reads nothing like an
		// assault rifle, and "sniper rifle" contains "rifle".
		if (hay.IndexOf("sniper") >= 0 || hay.IndexOf("marksman") >= 0
		 || hay.IndexOf("scoped") >= 0 || hay.IndexOf("boltaction") >= 0
		 || hay.IndexOf("bolt action") >= 0 || hay.IndexOf("kar98") >= 0
		 || hay.IndexOf("mosin") >= 0 || hay.IndexOf("springfield") >= 0
		 || hay.IndexOf("musket") >= 0 || hay.IndexOf("dmr") >= 0) return "sniper";

		if (hay.IndexOf("rifle") >= 0 || hay.IndexOf("assault") >= 0
		 || hay.IndexOf("ar15") >= 0 || hay.IndexOf("m16") >= 0
		 || hay.IndexOf("ak47") >= 0 || hay.IndexOf("carbine") >= 0
		 || hay.IndexOf("garand") >= 0) return "rifle";
		// pipebomb/dynamite before any "pipe" melee token.
		// BFG and RAILGUN must be tested BEFORE the rocket line, because
		// "launcher" lives there and would eat BFGLauncher / RailLauncher.
		// UNMAKER before BFG/PLASMA. Doom 64's Unmaker and Brutal Doom v22's
		// own version of it are a named, specific superweapon -- not "a BFG"
		// and not "a plasma gun", a thing modders who include one clearly
		// mean deliberately. It deserves to be recognised as itself rather
		// than folded into whichever energy-weapon shelf it resembled least
		// badly.
		if (hay.IndexOf("unmaker") >= 0) return "unmaker";
		if (hay.IndexOf("bfg") >= 0) return "bfg";
		// "rail" alone false-positives on guardrail/trail/derail.
		if (hay.IndexOf("railgun") >= 0 || hay.IndexOf("rail gun") >= 0
		 || hay.IndexOf("railrifle") >= 0) return "railgun";
		if (hay.IndexOf("flame") >= 0 || hay.IndexOf("thrower") >= 0) return "flamethrower";
		// LAUNCHED-GRENADE before ROCKET before THROWN. Three weapons share
		// the word "grenade" and none of them look alike: a break-action
		// tube fired from the shoulder (an M79) is not a rocket launcher and
		// is not a hand-thrown frag. The specific combination has to be
		// tested first or "launcher" alone eats it into rocket.
		if (hay.IndexOf("grenadelauncher") >= 0 || hay.IndexOf("grenade launcher") >= 0
		 || hay.IndexOf("m79") >= 0 || hay.IndexOf("40mm") >= 0
		 || hay.IndexOf("underslung") >= 0 || hay.IndexOf("underbarrel") >= 0
		 || hay.IndexOf("m203") >= 0) return "launcher";

		if (hay.IndexOf("rocket") >= 0 || hay.IndexOf("launcher") >= 0
		 || hay.IndexOf("bazooka") >= 0 || hay.IndexOf("mortar") >= 0
		 || hay.IndexOf("napalm") >= 0) return "rocket";

		// THROWN. A grenade held for the throw is nothing like a tube on the
		// shoulder, and until now everything that was not a launcher got one.
		if (hay.IndexOf("grenade") >= 0 || hay.IndexOf("frag") >= 0
		 || hay.IndexOf("pipebomb") >= 0 || hay.IndexOf("pipe bomb") >= 0
		 || hay.IndexOf("dynamite") >= 0 || hay.IndexOf("molotov") >= 0
		 || hay.IndexOf("satchel") >= 0 || hay.IndexOf("throwable") >= 0
		 || hay.IndexOf("cocktail") >= 0) return "grenade";
		if (hay.IndexOf("pistol") >= 0 || hay.IndexOf("handgun") >= 0
		 || hay.IndexOf("glock") >= 0 || hay.IndexOf("autoloader") >= 0
		 || hay.IndexOf("9mm") >= 0 || hay.IndexOf("luger") >= 0
		 || hay.IndexOf("beretta") >= 0 || hay.IndexOf("deagle") >= 0
		 || hay.IndexOf("desert eagle") >= 0 || hay.IndexOf("sidearm") >= 0) return "pistol";
		// SAWS ARE NOT FISTS. Both are melee, and a shared melee shelf leads
		// with a fist, so every chainsaw in every mod came out as knuckles.
		// A powered saw is as distinct from a punch as a shotgun is from a
		// pistol and deserves its own shelf.
		//
		// Bare "saw" is deliberately not a token -- "sawed-off" would eat it,
		// and that is a supershotgun. It is matched earlier anyway.
		if (hay.IndexOf("chainsaw") >= 0 || hay.IndexOf("chain saw") >= 0
		 || hay.IndexOf("buzzsaw")  >= 0 || hay.IndexOf("sawblade") >= 0
		 || hay.IndexOf("ripper")   >= 0) return "saw";
		// AXE/BLADE before bare-hand melee. A hatchet, machete or combat knife
		// is a held edge with reach and a swing arc -- nothing like a fist,
		// and it was defaulting to one.
		if (hay.IndexOf("axe") >= 0 || hay.IndexOf("hatchet") >= 0
		 || hay.IndexOf("tomahawk") >= 0 || hay.IndexOf("machete") >= 0
		 || hay.IndexOf("knife") >= 0 || hay.IndexOf("dagger") >= 0
		 || hay.IndexOf("blade") >= 0) return "axe";

		if (hay.IndexOf("fist") >= 0
		 || hay.IndexOf("punch") >= 0 || hay.IndexOf("knuckle") >= 0
		 || hay.IndexOf("crowbar") >= 0 || hay.IndexOf("whip") >= 0
		 || hay.IndexOf("jackhammer") >= 0 || hay.IndexOf("wrench") >= 0
		 || hay.IndexOf("shovel") >= 0) return "melee";
		return "";
	}

	// Doom's own slot layout, extended past 7 with what the GH set has
	// spare: slot 8 takes the second BFG, slot 9 the flamethrower. Mods
	// that use the high slots get a distinct heavy instead of everything
	// above 7 collapsing onto one gun.
	//
	// `pick` is the default index on that archetype's shelf -- it lets
	// slots 7 and 8 both land on "bfg" while showing different models.
	static string SlotArchetype(int slot, out int pick)
	{
		pick = 0;
		// Slot 0 is where mods park utility items -- Ashes puts its Lantern
		// there. Melee is the least wrong thing to hand someone holding a
		// light source; pistol was actively silly.
		if (slot == 0) return "melee";
		if (slot == 1) return "melee";
		if (slot == 2) return "pistol";
		if (slot == 3) return "shotgun";
		if (slot == 4) return "chaingun";
		if (slot == 5) return "rocket";
		if (slot == 6) return "plasma";
		if (slot == 7) return "bfg";                    // RS_GH_BFG9000
		if (slot == 8) { pick = 2; return "bfg"; }      // RS_GH_BFG10k
		if (slot == 9) return "flamethrower";
		return "pistol";
	}

	// Is this one of OURS?
	static bool IsOurs(string cn)
	{
		return (cn.IndexOf("MS_") == 0 || cn.IndexOf("RS_") == 0
		     || cn.IndexOf("VR_") == 0 || cn.IndexOf("Vanilla_") == 0);
	}


	// Does this class already carry a HUD model of its own? Never paint over a
	// mod that shipped 3D weapons.
	//
	// hasmodel is set on the CLASS DEFAULTS by the MODELDEF parser and is the
	// same flag FindModelFrameRaw gates on, so it answers exactly the right
	// question. It is an RS-fork export (FORK_CHANGES.md §15); on stock GZDoom
	// this is not answerable from ZScript at all.
	//
	// READ IT OFF THE DEFAULTS, NEVER OFF A LIVE ACTOR. A_ChangeModel sets
	// hasmodel on the instance as a side effect, so an instance read reports
	// true for every weapon we already painted -- and the second scan would
	// skip everything the first one bound.
	static bool HasOwnModel(class<Weapon> type)
	{
		readonly<Actor> def = GetDefaultByType(type);
		return (def && def.hasmodel);
	}

	// -----------------------------------------------------------------
	// WHICH ARCHIVE DEFINED A CLASS. The engine cannot be asked -- it
	// knows, but exports nothing -- so the only route is reading the same
	// text it compiled: every sideloaded archive's root DECORATE/ZSCRIPT
	// lump and the include tree under it, harvesting declared class names.
	//
	// Container 0 is the engine's own resource archive, and every stock
	// arsenal -- Doom, Heretic, Hexen, Strife, Chex -- compiles from ITS
	// root zscript. Skipping it is the entire filter: no game names, no
	// IWAD lists, nothing to maintain. (game_support.pk3 only carries
	// filter/-scoped scripts, which are not root-level lumps, so the
	// root-only rule below skips those on its own.)
	//
	// THE API TRAP, learned the hard way: GetContainerName takes a
	// CONTAINER INDEX. Feeding it a lump number silently returns wrong
	// names and made this filter pass everything. The correct chain is
	// GetContainerName(GetLumpContainer(lump)).
	//
	// This is INFORMATION for the menu, never a scan gate. If every part
	// of it fails, modDefined is simply false everywhere and the menu
	// falls back to the slot-binding filter -- the models cannot be taken
	// down by a parsing bug here. That rule is load-bearing; see Scan().
	// -----------------------------------------------------------------
	static void HarvestModClasses(out Array<string> outNames, out Array<string> outFrom)
	{
		outNames.Clear();
		outFrom.Clear();

		Array<int> visited;
		int n = Wads.GetNumLumps();
		for (int i = 0; i < n; ++i)
		{
			if (Wads.GetLumpContainer(i) == 0) continue;   // the engine itself

			// Roots live at archive top level: "DECORATE", "decorate.txt",
			// "zscript.zsc", "ZSCRIPT" -- any extension, no directory.
			string fn = Wads.GetLumpFullName(i);
			fn = fn.MakeLower();
			if (fn.IndexOf("/") >= 0) continue;
			int dp = fn.IndexOf(".");
			string stem = (dp >= 0) ? fn.Left(dp) : fn;
			if (stem != "decorate" && stem != "zscript") continue;

			string from = Wads.GetContainerName(Wads.GetLumpContainer(i));
			ParseLump(i, from, outNames, outFrom, visited, 0);
		}
	}

	// One lump: harvest "class X" / "actor X" declarations, recurse into
	// #include lines. Text-level, deliberately dumb -- it only has to agree
	// with the compiler about NAMES, not semantics.
	static void ParseLump(int lump, string from,
	                      in out Array<string> outNames, in out Array<string> outFrom,
	                      in out Array<int> visited, int depth)
	{
		if (depth > 8) return;                 // include cycles / silly nesting
		if (visited.Size() > 500) return;      // runaway safety
		for (int i = 0; i < visited.Size(); ++i)
			if (visited[i] == lump) return;
		visited.Push(lump);

		string text = Wads.ReadLump(lump);
		Array<string> lines;
		text.Split(lines, "\n");

		for (int i = 0; i < lines.Size(); ++i)
		{
			string ln = lines[i];
			int cm = ln.IndexOf("//");
			if (cm >= 0) ln = ln.Left(cm);
			string low = ln.MakeLower();

			// #include -- and DECORATE includes are often UNQUOTED
			// ("#Include Actors/Weapons/Crowbar.txt", Ashes does exactly
			// this), so both forms have to parse.
			int inc = low.IndexOf("#include");
			if (inc >= 0)
			{
				int p = inc + 8;
				while (p < ln.Length() && (ln.ByteAt(p) == 32 || ln.ByteAt(p) == 9)) p++;
				string path = "";
				if (p < ln.Length() && ln.ByteAt(p) == 34)   // opening quote
				{
					int q2 = ln.IndexOf("\"", p + 1);
					if (q2 > p) path = ln.Mid(p + 1, q2 - p - 1);
				}
				else
				{
					int s0 = p;
					while (p < ln.Length() && ln.ByteAt(p) > 32) p++;
					path = ln.Mid(s0, p - s0);
				}
				if (path.Length() > 0)
				{
					int il = Wads.CheckNumForFullName(path);
					if (il < 0) { string lp = path.MakeLower(); il = Wads.CheckNumForFullName(lp); }
					if (il >= 0) ParseLump(il, from, outNames, outFrom, visited, depth + 1);
				}
				continue;
			}

			// Declarations only: the FIRST token on the line must be the
			// keyword. That skips "extend class" (defines nothing new) and
			// incidental uses of the words mid-line.
			int p = 0;
			while (p < low.Length() && (low.ByteAt(p) == 32 || low.ByteAt(p) == 9)) p++;
			bool isDecl = false;
			if (low.Mid(p, 6) == "class " || low.Mid(p, 6) == "class\t") { p += 6; isDecl = true; }
			else if (low.Mid(p, 6) == "actor " || low.Mid(p, 6) == "actor\t") { p += 6; isDecl = true; }
			if (!isDecl) continue;

			while (p < low.Length() && (low.ByteAt(p) == 32 || low.ByteAt(p) == 9)) p++;
			int s0 = p;
			while (p < low.Length())
			{
				int ch = low.ByteAt(p);
				bool idc = (ch >= 97 && ch <= 122) || (ch >= 48 && ch <= 57) || ch == 95;
				if (!idc) break;
				p++;
			}
			if (p > s0)
			{
				outNames.Push(low.Mid(s0, p - s0));
				outFrom.Push(from);
			}
		}
	}

	// -----------------------------------------------------------------
	static void Scan(in out Array<RS_ForeignEntry> outList)
	{
		outList.Clear();

		// Once per scan, not per class. See HarvestModClasses for why a
		// total failure here is safe: modDefined false everywhere degrades
		// to exactly the pre-harvest menu behavior.
		Array<string> harvestNames, harvestFrom;
		HarvestModClasses(harvestNames, harvestFrom);

		int n = AllActorClasses.Size();
		for (int i = 0; i < n; ++i)
		{
			let type = (class<Weapon>)(AllActorClasses[i]);
			if (type == null || type == "Weapon") continue;

			readonly<Weapon> def = GetDefaultByType(type);
			if (!def) continue;

			string cn = type.GetClassName();
			if (IsOurs(cn)) continue;

			string lcn = cn; lcn = lcn.MakeLower();
			if (lcn.IndexOf("random") == 0) continue;   // RandomSpawner-style

			// A mod that already ships its own 3D weapon models is not asking
			// for ours. Leave it alone.
			if (RS_ForeignScanner.HasOwnModel(type)) continue;

			RS_ForeignEntry e = new("RS_ForeignEntry");
			e.clsName = cn;
			e.tag     = def.GetTag(cn);

			// SlotNumber is -1 for weapons that get their slot from
			// KEYCONF/MAPINFO instead of the actor property. Read the
			// player's REAL runtime slot when we can.
			e.slot = def.SlotNumber;
			bool located = false;
			PlayerInfo pl = players[consolePlayer];
			if (pl && pl.mo)
			{
				int sl; int prio;
				[located, sl, prio] = pl.weapons.LocateWeapon(type);
				if (located) e.slot = sl;
			}

			// DO NOT REJECT ON !located. It looks like a clean way to keep the
			// Heretic/Hexen/Strife weapons GZDoom compiles into every session
			// out of the picker -- and it silently returns an EMPTY LIST on
			// Golden Souls.
			//
			// GS binds its whole arsenal through Player.WeaponSlot on its own
			// player class and sets no Weapon.SlotNumber anywhere. Load RS_Main
			// too and its MAPINFO PlayerClasses key CLEARS the class list
			// before adding its own, so GS's player class never spawns, the
			// slot table is read from RS_GH_Weaponset instead, AddExtraWeapons
			// never picks the GS weapons up either, and LocateWeapon comes back
			// false for every single one. Every weapon gets skipped and the
			// feature does nothing at all, with no error.
			//
			// So keep it as INFORMATION, not a filter: the picker dims unbound
			// rows and sorts them last. (Ashes is unaffected either way -- it
			// puts weapon.slotnumber on each weapon.)
			e.located = located;

			// Same rule for provenance: information, filled here, filtered in
			// the MENU. The union of located and modDefined is what the menu
			// shows by default -- located alone missed Golden Souls entirely
			// (see above), modDefined alone would go dark if the harvest hit
			// a packaging it can't parse. Either signal earns a row.
			e.modDefined   = false;
			e.srcContainer = "";
			for (int hj = 0; hj < harvestNames.Size(); ++hj)
			{
				if (harvestNames[hj] == lcn)
				{
					e.modDefined   = true;
					e.srcContainer = harvestFrom[hj];
					break;
				}
			}

			string ammo1 = "", ammo2 = "";
			if (def.AmmoType1 != null) ammo1 = "" .. def.AmmoType1.GetClassName();
			if (def.AmmoType2 != null) ammo2 = "" .. def.AmmoType2.GetClassName();

			bool bySlot; int pick;
			e.archetype     = RS_ForeignScanner.Classify(type, e.clsName, e.tag, e.slot, ammo1, ammo2, bySlot, pick);
			e.guessedBySlot = bySlot;
			e.modelPick1    = pick;
			e.modelPick2    = pick;
			e.pinned        = false;
			outList.Push(e);
		}
	}
}

// STATIC, not per-map. A plain EventHandler is destroyed and re-created on
// every level change, so every model the player picked died at the exit of
// every map -- and `pinned` was written in three places and read in none.
// StaticEventHandler still gets WorldLoaded and WorldTick, survives map
// changes, and additionally fires WorldLoaded on savegame restore.
class RS_ForeignModelHandler : StaticEventHandler
{
	Array<RS_ForeignEntry> mEntries;
	bool mScanned;

	// Track the ACTOR, not the class name. A_ChangeModel writes modelData on
	// one specific instance, so if the player drops and re-picks the same
	// weapon class the new instance never gets bound -- while step 2 still
	// pins its psprite to our anchor, leaving a raw sprite in their hands.
	Weapon mLastMain;
	Weapon mLastOff;
	bool   mBound;        // something is currently wearing one of our models
	bool   mLocatedDone;  // slot flags refreshed after the level settled

	RS_ForeignShelf mShelf;   // built once at world-load
	RS_ForeignClip  mClips;   // our animation clips, per donor
	RS_ForeignPersist mPersist; // learned timings that survive a restart
	RS_ForeignPickPersist mPicks; // player's model choices, keyed by class -- de facto per-mod profiles

	// Live per-hand animation state, and what watching has taught us.
	RS_ForeignHand  mHandMain;
	RS_ForeignHand  mHandOff;
	Array<RS_ForeignLearned> mLearned;

	// Plays before a sequence's timing locks. Shared by Commit (which
	// counts against it) and Animate (which must not trust a rate that
	// has not survived it -- see the rate block there).
	const LOCK_AFTER = 3;

	static bool Enabled()
	{
		CVar c = CVar.FindCVar("rs_foreignmodels");
		return (c && c.GetBool());
	}

	static RS_ForeignModelHandler Get()
	{
		return RS_ForeignModelHandler(StaticEventHandler.Find("RS_ForeignModelHandler"));
	}

	override void WorldLoaded(WorldEvent e)
	{
		if (!Enabled()) return;
		Rescan();

		CVar d = CVar.FindCVar("rs_foreignmodels_dump");
		if (d && d.GetBool()) Dump();
	}

	// Re-scan, carrying the player's choices across. This is the ONLY place
	// the entry list is built -- world load, savegame restore and the menu's
	// Rescan button all come through here, so a hand-picked model survives a
	// map change instead of being re-guessed from scratch.
	//
	// `pinned` is the whole point of the merge and was, until now, written in
	// three places and read in none.
	void Rescan()
	{
		if (!mShelf)
		{
			mShelf = new("RS_ForeignShelf");
			mShelf.Build();
		}
		if (!mClips)
		{
			mClips = new("RS_ForeignClip");
			mClips.Build();
		}
		if (!mPersist) { mPersist = new("RS_ForeignPersist"); mPersist.Load(); }
		if (!mPicks)   { mPicks   = new("RS_ForeignPickPersist"); mPicks.Load(); }
		if (!mHandMain) mHandMain = new("RS_ForeignHand");
		if (!mHandOff)  mHandOff  = new("RS_ForeignHand");
		mHandMain.Reset();
		mHandOff.Reset();

		Array<RS_ForeignEntry> keep;
		for (int i = 0; i < mEntries.Size(); ++i)
			if (mEntries[i].pinned) keep.Push(mEntries[i]);

		RS_ForeignScanner.Scan(mEntries);

		for (int k = 0; k < keep.Size(); ++k)
		{
			int idx = FindEntry(keep[k].clsName);
			if (idx < 0) continue;
			mEntries[idx].archetype     = keep[k].archetype;
			mEntries[idx].modelPick1    = keep[k].modelPick1;
			mEntries[idx].modelPick2    = keep[k].modelPick2;
			mEntries[idx].guessedBySlot = keep[k].guessedBySlot;
			mEntries[idx].pinned        = true;
		}

		// Anything still unpinned after the in-session carry is either the
		// very first scan this session, or a weapon the player never
		// touched -- either way, check the archive before settling for the
		// auto-guess. This is the only place a saved pick is ever applied,
		// same as `keep` is the only place a live one is.
		for (int i = 0; i < mEntries.Size(); ++i)
		{
			if (mEntries[i].pinned) continue;
			string arch; int p1, p2;
			if (!mPicks.Get(mEntries[i].clsName, arch, p1, p2)) continue;
			mEntries[i].archetype  = arch;
			mEntries[i].modelPick1 = p1;
			mEntries[i].modelPick2 = p2;
			mEntries[i].pinned     = true;
		}

		mScanned  = true;
		mLastMain = null; mLastOff = null;
	}

	int FindEntry(string cls)
	{
		for (int i = 0; i < mEntries.Size(); ++i)
			if (mEntries[i].clsName == cls) return i;
		return -1;
	}

	// Paint ONE hand. `pick` selects which of the entry's two model slots
	// to use -- mainhand reads modelPick1, offhand reads modelPick2, so the
	// same weapon class can wear a different model in each hand.
	// Returns the bound class name (or "") so the caller can track whether
	// a re-bind is needed.
	Weapon ApplyHand(PlayerInfo pi, Weapon w, int layer, int pick, Weapon lastBound, RS_ForeignHand hs)
	{
		if (!w) return null;

		int idx = FindEntry(w.GetClassName());
		if (idx < 0) return null;
		let en = mEntries[idx];

		string mcls, anchor; int heldFrame, restFrame, frameCount;
		if (!mShelf.Get(en.archetype, pick, mcls, anchor, heldFrame, restFrame, frameCount))
			return null;

		// STEP 1 -- once per INSTANCE: point this actor's model lookup at
		// our class. Brings its Path/Skin/Scale/Offset along with it.
		if (lastBound != w)
			w.A_ChangeModel(mcls);

		// STEP 2 -- every tick: their states re-set the psprite each frame,
		// so re-pin it to our anchor at the resting pose.
		let psp = pi.FindPSprite(layer);
		if (psp)
		{
			// GetSpriteIndex returns -1 for a name that was never registered,
			// and FindModelFrameRaw indexes sprites[] with it unchecked --
			// (unsigned)-1 is an out-of-bounds read, not a missing model.
			int si = Actor.GetSpriteIndex(anchor);
			if (si < 0) return w;
			psp.Sprite = si;
			psp.Frame  = heldFrame;

			// STEP 3 -- address the model frame DIRECTLY. The sprite pin above
			// only has to make FindModelFrame resolve; which frame actually
			// draws is this. That is what lifts the 29-frame ceiling and makes
			// a 75-frame reload reachable at all.
			Animate(hs, pi, w, psp, mcls, restFrame, frameCount,
				layer == PSP_OFFHANDWEAPON ? WF_OFFHANDREADY : WF_WEAPONREADY);
		}
		return w;
	}

	override void WorldTick()
	{
		// Row indices are per-client -- the entry list is built against the
		// console player -- and NetworkProcess applies `row` verbatim, so a
		// cycle on one machine would retune a different weapon on another.
		// Single-player only until the list is made identical everywhere.
		if (multiplayer) return;

		// Turning the switch OFF has to actually undo the bind. Step 2 stops
		// on its own, but modelData->modelDef stays attached to the weapon and
		// DActorModelData::Serialize writes it into the savegame -- so without
		// this the setting looks like it did nothing and the model comes back
		// on load.
		if (!Enabled())
		{
			if (mBound) Unbind();
			return;
		}

		// Lazy init, so switching the feature on mid-game works without
		// waiting for the next map.
		if (!mScanned || !mShelf) Rescan();
		if (!mScanned || !mShelf) return;

		// psprites are local-view state; v1 paints the console player only.
		if (!playeringame[consolePlayer] || !players[consolePlayer].mo) return;
		let pi = players[consolePlayer];

		// GetClassName() is a Name, not a String, and ?: will not unify the
		// two arms -- so the null test has to be outside the call.
		int mi = pi.ReadyWeapon   ? FindEntry("" .. pi.ReadyWeapon.GetClassName())   : -1;
		int oi = pi.OffhandWeapon ? FindEntry("" .. pi.OffhandWeapon.GetClassName()) : -1;

		mLastMain = ApplyHand(pi, pi.ReadyWeapon, PSP_WEAPON,
			mi >= 0 ? mEntries[mi].modelPick1 : 0, mLastMain, mHandMain);

		// SAME ACTOR IN BOTH HANDS: A_ChangeModel writes modelData on the
		// actor, not the psprite, so binding the offhand would overwrite the
		// mainhand's modelDef while the mainhand psprite is still pinned to
		// modelPick1's anchor -- lookup misses and a raw sprite appears. One
		// actor gets one model; the mainhand wins.
		if (pi.OffhandWeapon && pi.OffhandWeapon != pi.ReadyWeapon)
			mLastOff = ApplyHand(pi, pi.OffhandWeapon, PSP_OFFHANDWEAPON,
				oi >= 0 ? mEntries[oi].modelPick2 : 0, mLastOff, mHandOff);
		else
			mLastOff = null;

		mBound = (mLastMain != null || mLastOff != null);

		// REFRESH THE SLOT FLAGS, LATE.
		//
		// Scan runs at WorldLoaded, before the player's weapon slot table is
		// populated -- so LocateWeapon came back false for EVERY weapon,
		// including the mod's own, and the scan report showed "(no slot)" on
		// all 117 rows. Any filter built on that was doomed.
		//
		// A few tics in the table is real. Redo it once and the flag finally
		// means what it says: this weapon is bound to one of the player's
		// slots, i.e. the mod put it there, i.e. it is the mod's.
		//
		// Deliberately does not touch binding -- only the flag the menus read.
		if (!mLocatedDone && level.maptime > 8)
		{
			mLocatedDone = true;
			for (int i = 0; i < mEntries.Size(); ++i)
			{
				class<Weapon> t = mEntries[i].clsName;
				if (!t) continue;
				bool loc; int sl; int prio;
				[loc, sl, prio] = pi.weapons.LocateWeapon(t);
				mEntries[i].located = loc;
				if (loc) mEntries[i].slot = sl;
			}
		}
	}

	// Is `to` on `parked`'s natural path? Natural progression -- including
	// Goto loops, which the state table encodes as NextState -- is a walk;
	// a button-initiated jump is not on it. Bounded: a parked ready-ish
	// state reaches its successors within a few hops or not at all.
	static bool ReachableFrom(State parked, State to, int cap)
	{
		State s = parked;
		for (int i = 0; i <= cap && s != null; ++i)
		{
			if (s == to) return true;
			State nxt = s.NextState;
			if (nxt == s) return false;   // self-loop (Ready's Loop) ends the walk
			s = nxt;
		}
		return false;
	}

	// -----------------------------------------------------------------
	// THE ANIMATION. Watch their sequence, learn its real length, replay
	// ours across it.
	// -----------------------------------------------------------------
	void Animate(RS_ForeignHand hs, PlayerInfo pi, Weapon w, PSprite psp, string donor,
	             int restFrame, int frameCount, int readyMask)
	{
		State cur = psp.CurState;

		// A SEQUENCE IS "LEFT IDLE UNTIL BACK TO IDLE" -- not the gap between
		// two state changes.
		//
		// Treating every unpredicted state change as a boundary looks right
		// and is badly wrong on real mods. Ashes' revolver reload runs through
		// 0-tic conditional jumps, so a single 68-tic reload shattered into a
		// dozen 2-tic "sequences", each learned separately, each restarting
		// the clip. The reload happened; the cylinder never swung out, because
		// the clip never got past its first two frames before being reset.
		//
		// WF_WEAPONREADY is the exact signal. A_WeaponReady SETS it, and the
		// engine clears it every tick before psprite processing -- so it is
		// true exactly while the weapon is idle, in any mod, because calling
		// A_WeaponReady is what makes a weapon usable at all. No naming, no
		// state walking, no assumptions about how their reload is written.
		bool idle = (pi.WeaponState & readyMask) != 0;

		// A RELOAD PROVING ITSELF THROUGH A STALE FIRE SEQUENCE.
		//
		// The gap glue below exists to bridge SHORT idle blips inside ONE
		// continuing action -- but on its own it cannot tell "still the
		// same action" apart from "a different action started right after
		// this one, close enough in time to land inside the glue window."
		// A voluntary reload pressed within a few tics of the last shot is
		// exactly that: hs.entry is still the FIRE sequence's, un-reset (it
		// only resets when hs.entry is already null), so the reload runs
		// entirely under a stale liveSeq=="fire" -- elapsed and ammoAtEntry
		// both still belong to the shot that already happened. The model
		// sits wherever the fire clip's last frame was while the mod's own
		// reload timer and sound run underneath it, which is indistinguishable
		// from no animation at all. Reloading from empty dodges this only by
		// accident: there is naturally more than a glue window's worth of
		// pause between running dry and pressing reload.
		//
		// Ammo direction is the tell, and it needs no state-walking to read.
		// A continuing fire session can only hold ammoAtEntry's baseline or
		// fall further below it -- every shot is a decrement, and
		// ammoAtEntry is fixed at whatever the count was BEFORE the first
		// shot of the session, refires included. Ammo rising back above
		// that baseline is proof a reload started, on whatever tic that
		// happens to be, glue window or not.
		if (hs.entry && (hs.liveSeq == "fire" || hs.liveSeq == "altfire"))
		{
			int a1n = (w.Ammo1 ? w.Ammo1.Amount : -1);
			int a2n = (w.Ammo2 ? w.Ammo2.Amount : -1);
			if ((hs.ammoAtEntry  >= 0 && a1n > hs.ammoAtEntry)
			 || (hs.ammo2AtEntry >= 0 && a2n > hs.ammo2AtEntry))
			{
				Commit(hs, w);
				hs.entry = null;
			}
		}

		// A JUMP OUT OF GLUE IS A NEW ACTION, and the glue must not eat it.
		//
		// The glue exists to bridge idle blips INSIDE one action. But any
		// button pressed within the glue window landed in the same bridge:
		// fire, then reload half a second later, and the reload ran as a
		// continuation of the dead fire sequence -- its animation never
		// selected, the model parked on the fire clip's last frame. Hence
		// "I have to wait a beat and press deliberately or nothing plays":
		// waiting let the glue expire; fight-paced input never did. Running
		// dry made it a certainty, because an empty-mag reload is always
		// pressed tics after the shot that emptied it.
		//
		// The state table itself is the tell. Natural progression --
		// including Goto loops, which are encoded as NextState -- walks
		// forward from the parked state. A button-initiated action is a
		// JUMP the table does not predict: the engine sets the psprite to
		// the Fire/Reload/Zoom label directly. So on the tic the weapon
		// leaves idle-glue, walk the parked state's NextState chain; if the
		// current state is not on it, something redirected the weapon --
		// that is a boundary, on exactly the tic it happened. The old
		// sequence commits, and the fresh one lands on its own (usually
		// already-learned) entry, so the right clip plays from tic one.
		//
		// Runtime A_Jump* side-effects are also invisible to NextState, but
		// they cannot false-positive here: this test only runs on the
		// glue-exit tic, and a state parked in glue is parked precisely
		// because it is calling A_WeaponReady and waiting -- the jumps such
		// states take are button-driven by design. (BD's fire-to-cancel
		// mid-reload is a jump AND a genuinely new action: ending the
		// sequence there is correct, not collateral.)
		if (hs.entry && !idle && hs.idleRun > 0 && cur != null && hs.lastState != null
		 && !ReachableFrom(hs.lastState, cur, 24))
		{
			Commit(hs, w);
			hs.entry = null;
		}

		if (psp.Caller != hs.lastCaller)
		{
			// Different weapon entirely; whatever was running is not ours.
			hs.Reset();
			hs.lastCaller = psp.Caller;
		}
		else if (idle && hs.entry)
		{
			// GAP GLUE -- do not end a sequence on the first idle tic.
			//
			// Brutal Doom's shotgun calls A_WeaponReady for five tics inside
			// EVERY shell insertion. Treating that as the end meant an
			// eight-shell reload was eight sequences: the model replayed the
			// first fifth of the reload clip eight times and snapped back to
			// rest between each. Trailblazer's ChromeJustice does it ten
			// times. A brief idle gap is part of the action, not the end of
			// it.
			//
			// The cost is that a real return to idle is noticed six tics
			// late, so the ready pose starts a fifth of a second after the
			// action finishes. Invisible next to an eightfold stutter.
			hs.idleRun++;
			hs.elapsed++;
			if (hs.idleRun >= 6)
			{
				Commit(hs, w);
				hs.entry = null;
			}
		}
		else if (!idle && !hs.entry)
		{
			// Left idle: a sequence begins here, and THIS state identifies it
			// for as long as the mod exists.
			hs.entry         = cur;
			hs.elapsed       = 0;
			hs.sawBrightAt   = -1;
			hs.liveSeq       = "";
			hs.idleRun       = 0;
			hs.ammoAtEntry   = (w.Ammo1 ? w.Ammo1.Amount : -1);
			hs.ammo2AtEntry  = (w.Ammo2 ? w.Ammo2.Amount : -1);
			hs.ammoMark      = hs.ammoAtEntry;

			// Cleared, not carried over. liveSeq takes a few tics to resolve,
			// and until it does, a stale expectedUnits left over from the
			// PREVIOUS reload (a full reload's "8", say) would rate-scale
			// this new sequence's duration before its own amount is known --
			// wrong for exactly the tics it takes liveSeq to catch up.
			hs.expectedUnits = 0;

			// Alt-fire held at the start is the only thing that separates an
			// alt-fire from a primary when both leave idle identically. The
			// clip table already carries eleven altfire rows that nothing
			// could reach until now.
			hs.altHeld = (pi.cmd.buttons & BT_ALTATTACK) != 0;
		}
		else if (!idle && hs.entry)
		{
			hs.idleRun = 0;   // still going; any glue accrued was a gap
		}

		if (hs.entry && !idle)
		{
			hs.elapsed++;
			if (cur && cur.bFullbright && hs.sawBrightAt < 0) hs.sawBrightAt = hs.elapsed;

			// RE-TRIGGER, DO NOT SMEAR.
			//
			// Held fire never returns to idle: A_Refire and its hand-rolled
			// equivalents keep one sequence running for as long as the trigger
			// is down. Stretching one clip across that ran an eight-frame
			// recoil over five seconds -- the chaingun kicking in visible slow
			// motion, once, while the real weapon cycled ten times a second.
			//
			// A fresh ammo decrement is a fresh shot. Restart the clip on it
			// and held fire becomes a repeating cycle at the mod's own
			// cadence, which is what it looks like.
			int nowAmmo = (w.Ammo1 ? w.Ammo1.Amount : -1);
			if (hs.liveSeq == "fire" && nowAmmo >= 0 && hs.ammoMark >= 0
			 && nowAmmo < hs.ammoMark && hs.elapsed > 2)
			{
				hs.elapsed     = 1;
				hs.sawBrightAt = -1;
			}
			if (nowAmmo >= 0) hs.ammoMark = nowAmmo;

			// SETTLE THE SEQUENCE WHILE IT IS STILL RUNNING.
			//
			// The prior used to be read only at the END, which meant the very
			// FIRST reload of every weapon played the fire animation -- there
			// was nothing learned yet, so it fell back to a guess, and by the
			// time we knew better the reload was over.
			//
			// Ammo rising is a reload no matter what the sequence is called,
			// and it is observable the tic it happens. Reading it live means
			// the first reload looks right too.
			if (hs.liveSeq.Length() == 0)
			{
				int a1 = (w.Ammo1 ? w.Ammo1.Amount : -1);
				int a2 = (w.Ammo2 ? w.Ammo2.Amount : -1);
				if ((hs.ammoAtEntry  >= 0 && a1 > hs.ammoAtEntry)
				 || (hs.ammo2AtEntry >= 0 && a2 > hs.ammo2AtEntry))
				{
					hs.liveSeq = "reload";

					// Predict THIS run's total restore now, while it is still
					// knowable -- capacity minus what the weapon had when the
					// reload began. Ammo1 preferred, matching the precedence
					// the rest of the classifier already uses; falls back to
					// Ammo2 only when Ammo1 is the one that did not rise.
					if (hs.ammoAtEntry >= 0 && a1 > hs.ammoAtEntry && w.Ammo1)
						hs.expectedUnits = w.Ammo1.MaxAmount - hs.ammoAtEntry;
					else if (hs.ammo2AtEntry >= 0 && a2 > hs.ammo2AtEntry && w.Ammo2)
						hs.expectedUnits = w.Ammo2.MaxAmount - hs.ammo2AtEntry;
					if (hs.expectedUnits < 1) hs.expectedUnits = 1;
				}
				else if ((hs.ammoAtEntry  >= 0 && a1 < hs.ammoAtEntry)
				      || (hs.ammo2AtEntry >= 0 && a2 < hs.ammo2AtEntry))
					hs.liveSeq = hs.altHeld ? "altfire" : "fire";
			}
		}
		hs.lastState  = cur;
		hs.lastTics   = psp.Tics;
		hs.lastCaller = psp.Caller;

		// ---- pick the clip ----
		string seq = "ready";
		int D = 0;
		int shotTic = -1;
		int restoreUnits = 0;   // paired with D -- see rate scaling, below

		// The rate is EVIDENCE-GATED, and the gate runs at lock -- so a
		// rate read off an entry that has not locked yet is an unproven
		// guess, and applying it was the bug that looked like "it has to
		// learn every fill level separately": play 1 records duration and
		// restored-amount, plays 2 and 3 scaled by that ratio before the
		// gate ever ran, so a fixed-length mag swap at any OTHER fill got
		// stretched or crushed by a correlation nobody had checked.
		// Trust the rate only from a locked entry (the gate has run) or
		// from the archive (only ever written at lock).
		bool rateTrusted = false;

		if (hs.entry)
		{
			int li = FindLearned(w.GetClassName(), hs.entry);
			if (li >= 0)
			{
				seq = mLearned[li].seq; D = mLearned[li].observedTics;
				shotTic = mLearned[li].brightTic; restoreUnits = mLearned[li].restoreUnits;
				rateTrusted = (mLearned[li].plays >= LOCK_AFTER);
			}
			else
			{
				// UNLEARNED AND NOTHING PROVEN YET -- hold the rest pose.
				//
				// This used to default to "fire", which meant every melee
				// swing, kick, taunt, scope-in and mode toggle played the
				// firing animation the first time it was ever seen -- and
				// then Commit() learned "fire" for it permanently. Brutal
				// Doom alone inherits kick, slide attack, taunt and execution
				// onto all 37 of its weapons.
				//
				// A weapon at rest during an action we cannot identify is
				// wrong quietly. A weapon miming a gunshot while you kick
				// something is wrong loudly, and then stays wrong.
				seq = "ready";
			}

			// FIRST RUN OF A SESSION, ON A WEAPON WE ALREADY KNOW.
			//
			// The runtime entry does not exist until this sequence has
			// finished once, so without this the very first reload after
			// loading the game plays at natural rate even though the timing
			// was worked out days ago. The archive is keyed by name rather
			// than by pointer precisely so it can be consulted here, before
			// any pointer has been associated with anything.
			if (li < 0 && D <= 0 && mPersist && hs.liveSeq.Length() > 0)
			{
				int pd, pb, pr;
				if (mPersist.Get(w.GetClassName(), hs.liveSeq, pd, pb, pr))
				{
					seq = hs.liveSeq; D = pd; shotTic = pb; restoreUnits = pr;
					rateTrusted = true;   // archive rows are written at lock, post-gate
				}
			}

			// What the weapon has actually DONE this run outranks anything
			// remembered from a previous one. A weapon whose fire and reload
			// share an entry state -- common where reload is reached by a
			// conditional jump out of Fire -- would otherwise be stuck with
			// whichever one it did first, forever.
			if (hs.liveSeq.Length() > 0 && hs.liveSeq != seq)
			{
				seq          = hs.liveSeq;
				D            = 0;           // learned duration was for the other sequence
				shotTic      = -1;
				restoreUnits = 0;
				rateTrusted  = false;
				int lj = FindLearned(w.GetClassName(), hs.entry);
				if (lj >= 0 && mLearned[lj].seq == seq)
				{
					D            = mLearned[lj].observedTics;
					shotTic      = mLearned[lj].brightTic;
					restoreUnits = mLearned[lj].restoreUnits;
					rateTrusted  = (mLearned[lj].plays >= LOCK_AFTER);
				}
			}

			// RATE-SCALE A RELOAD TO HOW MUCH IT IS ACTUALLY RESTORING.
			//
			// D above is a duration measured on ONE past run. Locking that
			// number for every future reload of the weapon was the original
			// design and it is exactly what makes reload timing inconsistent:
			// a six-shell tube reload and a one-shell top-up can share an
			// entry state and be wildly different lengths, and only one of
			// them can match a fixed D. The other either finishes early and
			// holds, or overruns into the 1.15x stretch below.
			//
			// restoreUnits is how much ammo THAT locked run restored --
			// paired with D, that is a rate (tics per unit). hs.expectedUnits
			// is how much THIS run is predicted to restore, known from the
			// moment liveSeq resolves to "reload" (see Animate(), above).
			// D * expectedUnits / restoreUnits times the duration to how much
			// THIS reload is actually missing, instead of to whatever the
			// first three observed runs happened to be.
			//
			// restoreUnits <= 0 means no rate was ever learned for this
			// entry -- predates rate learning, or it is not a reload at all
			// (fire's ammo delta is a decrease) -- and D is used exactly as
			// measured, same as before this existed.
			if (D > 0 && rateTrusted && restoreUnits > 0 && hs.expectedUnits > 0)
				D = max(1, D * hs.expectedUnits / restoreUnits);
		}

		Array<int> frames; int markFire;
		if (!mClips.Get(donor, seq, frameCount, frames, markFire)
		 || frames.Size() == 0)
		{
			// No clip for this sequence on this donor: hold the rest pose.
			int rf = restFrame;
			if (frameCount > 0 && rf >= frameCount) rf = frameCount - 1;
			if (rf < 0) rf = 0;
			psp.ModelFrame     = rf;
			psp.ModelFrameNext = rf;
			psp.ModelFrameLerp = 0;
			return;
		}

		int N = frames.Size();
		double ct;

		// TIME-MATCHED AND DETERMINISTIC -- these were never in conflict.
		//
		// The warp is a pure function of elapsed tics and the learned
		// duration: the same tick of the same sequence yields the same frame,
		// every time. What made the animation vary was the DURATION moving
		// underneath it, refitted on every play. Commit() locks it after a
		// few observations, so from then on this is fixed.
		//
		// Until it locks, natural rate -- honest about not knowing yet, rather
		// than guessing at a fit that will change.
		//
		// rs_foreignmodels_natural forces natural rate permanently for anyone
		// who prefers the authored pacing to a matched one.
		bool natural = false;
		{
			CVar nc = CVar.FindCVar("rs_foreignmodels_natural");
			natural = (nc && nc.GetBool());
		}

		if (natural || D <= 0)
		{
			// Natural rate: one clip tic per game tic, exactly as authored.
			// Identical on every play, on every weapon, forever.
			ct = hs.elapsed - 1;
		}
		else
		{
			// Stretch or compress our clip across the duration they took.
			//
			// RUNNING LONGER THAN EXPECTED IS NORMAL, NOT AN ERROR. A reload
			// takes longer when more rounds are missing -- a six-shell tube
			// reload can be several times a one-shell top-up, off the same
			// entry state. Fitting a fixed duration meant the animation
			// finished in a fraction of the time and then FROZE, in full view,
			// for the rest of it. That is the "off" reload.
			//
			// D has already been rate-scaled to how much THIS reload is
			// predicted to restore, above -- that is the primary fix for the
			// six-shell-vs-one-shell case, not this. What is left here is the
			// residual: a prediction that undershoots (ammo capacity read
			// wrong, a top-up that keeps going further than expected) or a
			// weapon with no rate learned yet. So the target still stretches
			// as the run outlives the estimate, same as before rate-scaling
			// existed -- a safety net now, not the whole mechanism.
			double dEff = D;
			if (hs.elapsed > D) dEff = double(hs.elapsed) * 1.15;

			double e  = double(hs.elapsed - 1);
			double bt = double(shotTic - 1);          // sawBrightAt counts from 1
			double mf = double(markFire);

			// ANCHOR THE RECOIL TO THEIR SHOT.
			//
			// A proportional warp puts our animation in roughly the right
			// place; it does not put the KICK on the bang. Our clip knows
			// which of its own frames is the shot (markFire, authored from
			// the donor's own states) and watching taught us which tic of
			// their sequence the muzzle flash landed on. Pin those two
			// together and interpolate on either side, and the recoil hits
			// the frame the round leaves the barrel rather than merely near
			// it.
			//
			// Two segments: run-up compressed or stretched to reach the kick
			// exactly on time, then the recovery spread across whatever is
			// left. Falls back to the straight proportional warp when either
			// anchor is missing -- no flash seen, or a clip with no marked
			// shot, which is every reload.
			if (bt > 0 && mf > 0 && bt < dEff - 1 && mf < N - 1)
			{
				if (e <= bt) ct = e * mf / bt;
				else         ct = mf + (e - bt) * (double(N - 1) - mf) / (dEff - bt);
			}
			else
			{
				ct = e * double(N) / dEff;
			}
		}

		// Past the end -- held triggers and A_ReFire both do this -- hold.
		if (ct > N - 1) ct = N - 1;
		if (ct < 0) ct = 0;

		int i0 = int(ct);
		int i1 = (i0 + 1 < N) ? i0 + 1 : i0;

		psp.ModelFrame     = frames[i0];
		psp.ModelFrameNext = frames[i1];
		// Sub-tic blend: the model moves at display rate instead of stepping
		// at 35Hz. Lerp 0 with next == current is also the hard-frame case,
		// which is what a 1-frame clip (every `ready`) resolves to.
		psp.ModelFrameLerp = (frames[i0] == frames[i1]) ? 0 : (ct - i0);
	}

	// Learn from the sequence that just ended.
	void Commit(RS_ForeignHand hs, Weapon w)
	{
		if (!hs.entry || hs.elapsed <= 0) return;

		int li = FindLearned(w.GetClassName(), hs.entry);
		if (li < 0)
		{
			let L = new("RS_ForeignLearned");
			L.clsName = w.GetClassName();
			L.entry   = hs.entry;
			L.seq     = GuessSeq(hs, w);
			L.plays   = 0;

			// Seen this weapon's sequence in a previous session? Then it is
			// already known and arrives locked -- no relearning, no first few
			// reloads at the wrong pace.
			if (mPersist)
			{
				int pd, pb, pr;
				if (mPersist.Get(L.clsName, L.seq, pd, pb, pr))
				{
					L.observedTics  = pd;
					L.brightTic     = pb;
					L.restoreUnits  = pr;
					L.plays         = 3;   // already locked
				}
			}

			mLearned.Push(L);
			li = mLearned.Size() - 1;
		}
		else if (hs.liveSeq.Length() > 0 && mLearned[li].seq != hs.liveSeq)
		{
			// The run proved itself something other than what we had recorded.
			// Believe the run. The old label was a guess from an earlier one,
			// and a duration learned under the wrong label is meaningless, so
			// it starts over.
			mLearned[li].seq          = hs.liveSeq;
			mLearned[li].observedTics = 0;
			mLearned[li].brightTic    = -1;
			mLearned[li].restoreUnits = 0;
		}
		// REJECT RUNS THAT WERE NOT REAL.
		//
		// The estimate is the shortest run seen, which makes it exactly as
		// good as the worst outlier. A reload cancelled two tics in by
		// switching weapons, or a fire loop clipped by running out of ammo,
		// would become the new "shortest" and every subsequent play would be
		// crushed into a fraction of its proper length.
		//
		// Two guards. A run has to be long enough to be plausible at all, and
		// once an estimate exists a run has to be within reach of it -- a
		// quarter is generous for genuine variation (a one-shell top-up
		// against a full tube reload) and still rejects a cancel.
		// The trailing idle gap that the glue kept alive is not part of the
		// action; counting it would inflate every learned duration by six.
		if (hs.idleRun > 0) hs.elapsed -= hs.idleRun;

		if (hs.elapsed < 3) { mLearned[li].plays++; return; }
		if (mLearned[li].observedTics > 0
		 && hs.elapsed * 4 < mLearned[li].observedTics)
		{
			mLearned[li].plays++;
			return;
		}

		// LEARN, THEN LOCK.
		//
		// The timing used to be refitted on every single play, and THAT is
		// what made the animation different every time -- not the warp, which
		// is a pure function of elapsed tics and duration and yields the same
		// frame for the same tick, always. A moving duration was the entire
		// source of "it worked once and then it didn't".
		//
		// So: watch the first few runs, take the SHORTEST of them, and never
		// move it again. Shortest rather than average because a run that
		// outlives the estimate is handled gracefully -- the clip stretches
		// and keeps moving -- while one that ends early is cut off mid-motion,
		// which is the failure that looks broken.
		//
		// After LOCK_AFTER plays the animation for that sequence is fixed
		// forever: time-matched to how that weapon actually behaves, and
		// identical on the hundredth reload as on the fourth.
		//
		// PAIRED WITH A RATE, NOT JUST A NUMBER, for reloads that actually
		// scale with how much ammo is missing. What ammo THIS run restored,
		// read now while it is still fresh, is recorded alongside the run's
		// duration below. A fire/altfire run has ammo going DOWN, so
		// restored stays 0 and nothing here applies -- exactly the old
		// flat-duration behavior, unchanged.
		int restored = 0;
		int a1now = (w.Ammo1 ? w.Ammo1.Amount : -1);
		int a2now = (w.Ammo2 ? w.Ammo2.Amount : -1);
		if (hs.ammoAtEntry >= 0 && a1now > hs.ammoAtEntry)
			restored = a1now - hs.ammoAtEntry;
		else if (hs.ammo2AtEntry >= 0 && a2now > hs.ammo2AtEntry)
			restored = a2now - hs.ammo2AtEntry;

		if (mLearned[li].plays < LOCK_AFTER)
		{
			if (mLearned[li].observedTics <= 0 || hs.elapsed < mLearned[li].observedTics)
			{
				mLearned[li].observedTics = hs.elapsed;
				mLearned[li].restoreUnits = restored;   // paired with the run above
			}

			// EVIDENCE FOR THE LOCK DECISION, tracked separately from which
			// run anchors the rate. A single (duration, restored) pair can't
			// tell a reload that scales with ammo missing apart from one
			// that always takes the same time and happened to restore that
			// much -- most fixed-magazine weapons (pistols, SMGs, rifles:
			// eject whatever's left, load a fresh mag, same motion either
			// way) are the second kind, and scaling THEM would predict a
			// short partial reload's duration from a long full one, rushing
			// the clip through early and then freezing for what's left --
			// worse than the flat duration this is meant to improve on.
			// Two runs that actually restored different amounts, with
			// duration moving the same direction, is the bar for evidence.
			if (restored > 0)
			{
				if (mLearned[li].minRestore <= 0 || restored < mLearned[li].minRestore)
				{
					mLearned[li].minRestore     = restored;
					mLearned[li].minRestoreTics = hs.elapsed;
				}
				if (restored > mLearned[li].maxRestore)
				{
					mLearned[li].maxRestore     = restored;
					mLearned[li].maxRestoreTics = hs.elapsed;
				}
			}
		}
		else if (mLearned[li].plays == LOCK_AFTER && mPersist)
		{
			// Reject the rate at the moment of locking unless the evidence
			// actually supports it: a real difference in restored amount
			// (2, not 1 -- filters a single stray round from counting as
			// "variation") whose duration moved the same direction. Anything
			// less -- every observed reload restored about the same amount,
			// or duration didn't track the amount that did vary -- and this
			// entry keeps the flat duration it would have had before rate
			// learning existed, permanently, same as a weapon whose ammo
			// never went up at all.
			// The direction check alone was too easy to pass: durations are
			// measured with a tic or two of jitter (glue timing, branch
			// differences inside the mod's own reload), so two runs that
			// restored different amounts and happened to differ by ONE tic
			// read as correlation. Demand a difference that noise can't
			// fake: at least 4 tics AND at least a fifth of the shorter
			// run. A real per-shell reload clears both bars trivially; a
			// mag swap's jitter clears neither.
			int td = mLearned[li].maxRestoreTics - mLearned[li].minRestoreTics;
			bool scales = (mLearned[li].maxRestore - mLearned[li].minRestore >= 2)
			           && (td >= 4)
			           && (td * 5 >= mLearned[li].minRestoreTics);
			if (!scales) mLearned[li].restoreUnits = 0;

			// Just locked: archive it, keyed by something that survives a
			// restart. Written once per sequence, ever.
			mPersist.Store(mLearned[li].clsName, mLearned[li].seq,
			               mLearned[li].observedTics, mLearned[li].brightTic,
			               mLearned[li].restoreUnits);
		}

		if (hs.sawBrightAt >= 0) mLearned[li].brightTic = hs.sawBrightAt;
		mLearned[li].plays++;
	}

	// The PRIOR. Behaviour, not names -- what the weapon DID over the
	// sequence, because what it is called is unreliable across mods.
	//   ammo went DOWN -> they shot
	//   clip went UP    -> they reloaded
	//   a bright frame appeared and it was short -> they shot
	// It is allowed to be wrong. The picker is the correction path.
	string GuessSeq(RS_ForeignHand hs, Weapon w)
	{
		int a1 = (w.Ammo1 ? w.Ammo1.Amount : -1);
		int a2 = (w.Ammo2 ? w.Ammo2.Amount : -1);

		// Anything the run PROVED outranks a fresh reading -- liveSeq already
		// applied the alt-fire distinction and the UP-before-DOWN priority.
		if (hs.liveSeq.Length() > 0) return hs.liveSeq;

		if (hs.ammoAtEntry >= 0 && a1 > hs.ammoAtEntry)  return "reload";
		if (hs.ammo2AtEntry >= 0 && a2 > hs.ammo2AtEntry) return "reload";
		if (hs.ammoAtEntry >= 0 && a1 < hs.ammoAtEntry)  return hs.altHeld ? "altfire" : "fire";
		if (hs.ammo2AtEntry >= 0 && a2 < hs.ammo2AtEntry) return hs.altHeld ? "altfire" : "fire";
		if (hs.sawBrightAt >= 0) return "fire";
		return "ready";
	}

	int FindLearned(string cls, State entry) const
	{
		for (int i = 0; i < mLearned.Size(); ++i)
			if (mLearned[i].entry == entry && mLearned[i].clsName == cls) return i;
		return -1;
	}

	// Release every weapon we bound. A_ChangeModel with an empty modeldef name
	// is the documented clear (NAME_None), which drops modelData->modelDef and
	// lets the weapon render its own sprite again.
	void Unbind()
	{
		if (mLastMain) mLastMain.A_ChangeModel("");
		if (mLastOff)  mLastOff.A_ChangeModel("");

		// Hand the psprites back too. ModelFrame persists on the layer and is
		// serialised, so leaving it set would keep forcing a frame number onto
		// whatever the weapon renders next.
		if (playeringame[consolePlayer] && players[consolePlayer].mo)
		{
			let pi = players[consolePlayer];
			for (int lay = 0; lay < 2; ++lay)
			{
				let psp = pi.FindPSprite(lay == 0 ? PSP_WEAPON : PSP_OFFHANDWEAPON);
				if (!psp) continue;
				psp.ModelFrame     = -1;
				psp.ModelFrameNext = -1;
				psp.ModelFrameLerp = -1;
			}
		}

		mLastMain = null; mLastOff = null;
		mBound    = false;
	}

	// ----- picker plumbing -----
	//
	// SCOPE LAW (same as RS_Screens.zs): the menu runs in UI scope. It may
	// READ plain data off this play handler through const methods, but it
	// may NOT call anything that mutates. Every selector write comes back
	// as a netevent -- see NetworkProcess() below. Calling the mutators
	// directly from a menu is what produced the "unknown type" scope errors
	// that killed the previous attempt at this feature.

	// Cycling order for the FAMILY selector.
	static void ArchetypeList(out Array<string> a)
	{
		static const string ARCHE[] = {
			"pistol", "revolver", "smg", "rifle", "shotgun", "supershotgun",
			"chaingun", "rocket", "plasma", "railgun", "flamethrower",
			"bfg", "melee", "saw", "grenade", "sniper",
			"machinegun", "launcher", "unmaker", "axe",
			// Last, so cycling forward through the sensible families reaches
			// it only after they are exhausted -- but it is one step BACK
			// from "pistol", which is where most weapons start.
			"any"
		};
		a.Clear();
		for (int i = 0; i < ARCHE.Size(); ++i) a.Push(ARCHE[i]);
	}

	// Archetype for a live weapon class, by name. The ballistics muzzle
	// offset needs it -- a pistol's barrel ends a lot closer to the grip
	// than a rifle's -- and it is the only thing outside the binder that
	// asks a question about a specific weapon rather than a row index.
	string ArchetypeForClass(string cls)
	{
		int i = FindEntry(cls);
		return (i >= 0) ? mEntries[i].archetype : "";
	}

	int EntryCount() const             { return mScanned ? mEntries.Size() : 0; }
	string EntryName(int i) const      { return (i >= 0 && i < mEntries.Size()) ? mEntries[i].clsName : ""; }
	string EntryTag(int i) const       { return (i >= 0 && i < mEntries.Size()) ? mEntries[i].tag : ""; }
	string EntryArchetype(int i) const { return (i >= 0 && i < mEntries.Size()) ? mEntries[i].archetype : ""; }
	bool   EntryUnsure(int i) const    { return (i >= 0 && i < mEntries.Size()) ? mEntries[i].guessedBySlot : false; }
	bool   EntryPinned(int i) const    { return (i >= 0 && i < mEntries.Size()) ? mEntries[i].pinned : false; }
	bool   EntryLocated(int i) const   { return (i >= 0 && i < mEntries.Size()) ? mEntries[i].located : false; }
	bool   EntryModDefined(int i) const { return (i >= 0 && i < mEntries.Size()) ? mEntries[i].modDefined : false; }
	string EntryContainer(int i) const { return (i >= 0 && i < mEntries.Size()) ? mEntries[i].srcContainer : ""; }
	int    EntrySlot(int i) const      { return (i >= 0 && i < mEntries.Size()) ? mEntries[i].slot : -1; }

	// hand: 1 = mainhand (Model_1), 2 = offhand (Model_2)
	int EntryPick(int i, int hand) const
	{
		if (i < 0 || i >= mEntries.Size()) return 0;
		return (hand == 2) ? mEntries[i].modelPick2 : mEntries[i].modelPick1;
	}

	// Does the model on that hand have a reload animation at all?
	//
	// Some donors genuinely do not -- a knife, a chainsaw, the shorter
	// MeatGrinder meshes. Bind one of those to a weapon that reloads and the
	// reload is silent: the mesh holds its rest pose while the ammo count
	// changes. That is the honest thing for it to do, but the player should
	// be able to see it coming rather than discover it mid-fight.
	bool EntryModelHasReload(int i, int hand) const
	{
		if (i < 0 || i >= mEntries.Size() || !mShelf || !mClips) return true;
		int pick = (hand == 2) ? mEntries[i].modelPick2 : mEntries[i].modelPick1;
		string mcls, anchor; int hf, rf, fc;
		if (!mShelf.Get(mEntries[i].archetype, pick, mcls, anchor, hf, rf, fc)) return true;
		return mClips.Has(mcls, "reload");
	}

	// Which of OUR models that hand is currently wearing (for the row label).
	string EntryModelName(int i, int hand) const
	{
		if (i < 0 || i >= mEntries.Size() || !mShelf) return "";
		int pick = (hand == 2) ? mEntries[i].modelPick2 : mEntries[i].modelPick1;
		string mcls, anchor; int hf, rf, fc;
		if (!mShelf.Get(mEntries[i].archetype, pick, mcls, anchor, hf, rf, fc))
			return "(none)";
		return mcls;
	}

	// ----- the ONE write path -----
	//   netevent: rs-fm-cycle <row> <selector> <dir>
	//   selector 0 = family, 1 = mainhand model, 2 = offhand model
	// Three int args is exactly what SendNetworkEvent carries, so a row's
	// three selectors need no packing.
	override void NetworkProcess(ConsoleEvent e)
	{
		// Re-run the scan without reloading the map. Pinned rows keep their
		// player-chosen family and models; everything else re-guesses.
		if (e.name == "rs-fm-rescan") { Rescan(); return; }

		if (e.name == "rs-fm-random-onehand")
		{
			if (multiplayer) return;   // per-client row indices; see WorldTick
			RandomizeOneHanded();
			return;
		}

		// Throw away every learned timing, this session's and the archive's.
		// For when a mod is updated and its weapons no longer behave the way
		// they did when this was measured.
		if (e.name == "rs-fm-forget")
		{
			mLearned.Clear();
			if (mPersist) mPersist.Forget();
			if (mHandMain) mHandMain.Reset();
			if (mHandOff)  mHandOff.Reset();
			return;
		}

		// Separate from the above on purpose -- timing is a measured fact,
		// picks are a deliberate choice, and clearing one should never
		// silently take the other with it.
		if (e.name == "rs-fm-forget-picks")
		{
			if (mPicks) mPicks.Forget();
			for (int i = 0; i < mEntries.Size(); ++i) mEntries[i].pinned = false;
			Rescan();
			return;
		}

		if (e.name != "rs-fm-cycle") return;
		if (multiplayer) return;   // row indices are per-client; see WorldTick

		int row = e.args[0];
		int sel = e.args[1];
		int dir = e.args[2];
		if (row < 0 || row >= mEntries.Size()) return;
		// Netevent args are attacker-controlled in principle and unvalidated
		// sel fell through to CyclePick, which treats anything != 2 as the
		// mainhand.
		if (sel < 0 || sel > 2) return;
		if (dir != 1 && dir != -1) return;

		if (sel == 0) CycleArchetype(row, dir);
		else          CyclePick(row, sel, dir);
	}

	void CycleArchetype(int i, int dir)
	{
		if (i < 0 || i >= mEntries.Size()) return;
		Array<string> a; ArchetypeList(a);

		int cur = 0;
		for (int k = 0; k < a.Size(); ++k)
			if (a[k] == mEntries[i].archetype) { cur = k; break; }

		int v = (cur + dir) % a.Size();
		if (v < 0) v += a.Size();
		SetArchetype(i, a[v]);
	}

	void SetArchetype(int i, string a)
	{
		if (i < 0 || i >= mEntries.Size()) return;
		mEntries[i].archetype  = a;
		mEntries[i].modelPick1 = 0;
		mEntries[i].modelPick2 = 0;
		mEntries[i].pinned     = true;
		mLastMain = null; mLastOff = null;      // force a re-bind on both hands
		SavePick(i);
	}

	// The one place a pick reaches the archive. Called after every write to
	// archetype/modelPick1/modelPick2, so the saved copy can never drift
	// from what is actually bound.
	void SavePick(int i)
	{
		if (!mPicks || i < 0 || i >= mEntries.Size()) return;
		mPicks.Store(mEntries[i].clsName, mEntries[i].archetype,
			mEntries[i].modelPick1, mEntries[i].modelPick2);
	}

	void CyclePick(int i, int hand, int dir)
	{
		if (i < 0 || i >= mEntries.Size()) return;
		if (!mShelf) return;
		int n = mShelf.Count(mEntries[i].archetype);
		if (n <= 0) return;

		int cur = (hand == 2) ? mEntries[i].modelPick2 : mEntries[i].modelPick1;
		int v = (cur + dir) % n;
		if (v < 0) v += n;

		if (hand == 2) mEntries[i].modelPick2 = v;
		else           mEntries[i].modelPick1 = v;

		mEntries[i].pinned = true;
		mLastMain = null; mLastOff = null;      // force a re-bind on both hands
		SavePick(i);
	}

	// One-button "give everything a one-handed model" -- pistol, revolver or
	// smg, chosen per weapon rather than picking one family for the whole
	// list, so the result actually looks like a varied loadout instead of
	// fifteen copies of the same gun. Every entry ends up pinned and saved,
	// same as if the player had dialled in each one by hand.
	void RandomizeOneHanded()
	{
		if (!mShelf) return;

		for (int i = 0; i < mEntries.Size(); ++i)
		{
			string arch;
			switch (random[MSRandomize](0, 2))
			{
			case 0:  arch = "pistol";   break;
			case 1:  arch = "revolver"; break;
			default: arch = "smg";      break;
			}
			int n = mShelf.Count(arch);
			if (n <= 0) continue;   // standalone build dropped every donor for this row

			mEntries[i].archetype  = arch;
			mEntries[i].modelPick1 = random[MSRandomize](0, n - 1);
			mEntries[i].modelPick2 = random[MSRandomize](0, n - 1);
			mEntries[i].pinned     = true;
			SavePick(i);
		}

		mLastMain = null; mLastOff = null;
	}

	void Dump()
	{
		Console.Printf("\cd[RS Foreign] %d foreign weapons:", mEntries.Size());
		for (int i = 0; i < mEntries.Size(); ++i)
		{
			let en = mEntries[i];
			string mcls, anchor; int hf, rf, fc;
			mShelf.Get(en.archetype, en.modelPick1, mcls, anchor, hf, rf, fc);
			Console.Printf("  %s%-24s\c-  slot %d  -> \cf%-14s\c- %s [%s %d]",
				en.guessedBySlot ? "\cj?\c- " : "  ",
				en.clsName, en.slot, en.archetype,
				mcls.Length() > 0 ? mcls : "(no shelf)", anchor, hf);
		}
	}
}
