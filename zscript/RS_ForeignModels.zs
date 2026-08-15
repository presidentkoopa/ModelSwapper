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
	int    slotPos;       // position WITHIN that slot, -1 = none. LocateWeapon
	                      // has always returned it and it was always thrown
	                      // away; it is what lets tiered/morphing variants of
	                      // one weapon share a single picker row. See GroupKey.
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

			// The complete BD21 set -- generated, see modeldef.
			"shotgun|MS_BD_AssaultShotgun|SHTG|0|0|32",
			"grenade|MS_BD_nade|MISG|0|0|27",
			"kick|MS_BD_Boot|PUNG|0|0|58",
			"melee|MS_BD_fistclosed|PUNG|0|0|75",
			"bfg|MS_BD_BFG|BFGG|0|0|16",
			"bfg|MS_BD_BFG_10k|BFGG|0|6|21",
			"axe|MS_BD_BrutalAxe|PUNG|0|0|15",
			"saw|MS_BD_Chain_saw|SAWG|0|0|65",
			"axe|MS_BD_DSweap|PUNG|0|5|10",
			"melee|MS_BD_DSweap|PUNG|0|5|10",
			"flamethrower|MS_BD_FlameCannon|PLSG|0|0|8",
			"flamethrower|MS_BD_Flamethrower2|PLSG|0|0|6",
			"rocket|MS_BD_HellishMissile|MISG|0|0|10",
			"saw|MS_BD_HitlersBuzzsaw|SAWG|0|0|3",
			"launcher|MS_BD_M79|MISG|0|0|33",
			"machinegun|MS_BD_Machinegun|CHGG|0|0|36",
			"chaingun|MS_BD_Minigun|CHGG|0|0|16",
			"smg|MS_BD_MP40|CHGG|0|0|14",
			"smg|MS_BD_Dual_MP40|CHGG|0|0|20",
			"pistol|MS_BD_BrutalPistol|PISG|0|0|38",
			"plasma|MS_BD_Plasma|PLSG|0|0|30",
			"railgun|MS_BD_RailGun|PLSG|0|0|37",
			"revolver|MS_BD_Revolver|PISG|0|0|33",
			"rifle|MS_BD_Rifle|CHGG|0|0|32",
			"rifle|MS_BD_Rifle_Dual|CHGG|0|0|40",
			"rocket|MS_BD_RPG|MISG|0|0|39",
			"rocket|MS_BD_SnipaRPG|MISG|0|0|41",
			"shotgun|MS_BD_Shotgun|SHTG|0|0|36",
			"smg|MS_BD_BrutalSMG|CHGG|0|0|27",
			"smg|MS_BD_DualSMG|CHGG|0|0|27",
			"supershotgun|MS_BD_SSG|SHT2|0|47|52",
			"unmaker|MS_BD_Unmaker|BFGG|0|4|16",

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
			"bfg|MS_VR_BFG9000|BFGG|0|6|16",
			"melee|MS_Fist|PUNG|0|0|57",
			// This set had no flamethrower or BFG10k of its own -- those three
			// rows pointed into the Brutal Doom folder while wearing a VanAlek
			// label. Both families are covered by real Bv21 rows above, so the
			// borrowing is gone rather than repointed. A family honestly absent
			// from a set beats one silently answered by another set's mesh.

			// The Bv21 rows above ARE the Brutal Doom set. There used to be a
			// second copy of these same guns here, taken from RS_Main's
			// re-export rather than from Brutal Doom itself -- 20 models and
			// 72MB duplicating meshes the block above already covers, minus
			// the axe, the boot, the Dragonslayer and the dual variants that
			// only the real set has. Shipping both meant the picker offered
			// each gun twice and "assign all Bv21" reached for the lesser of
			// the two. One set, sourced from BD's own MODELDEFs.

			// ---- MeatGrinder set. Nine models in 6MB, and a grittier look
			// than either of the others -- the cheapest breadth on offer.
			"melee|MS_MG_Knife|PUNG|0|0|9",

			// ---- axe/blade: a held edge, not a bare hand ----
			"axe|MS_MG_Knife|PUNG|0|0|9",

			// The Dragonslayer, Brutal Doom's greatsword. It sits on melee as
			// well as axe: a mod whose slot 1 is a blade of any size reads
			// better wearing this than a fist.

			// ---- thrown explosives ----
			// A hand grenade is not a rocket launcher. Every mod with a frag
			// or a pipe bomb was getting an RPG welded to its hand. The thrown
			// nade is a Bv21 row up top; this shelf exists so it is reachable.

			// ---- saws, on their own shelf ----
			"saw|MS_Chainsaw|SAWG|0|0|8",
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
			// silhouette. The Garand backs it up, and Brutal Doom's own scoped
			// railgun -- SnipaRG, a distinct mesh from the plain RailGun -- is
			// the long scoped option for a sci-fi mod.
			"sniper|MS_BW_Kar98|CHGG|0|1|44",
			"sniper|MS_BW_Garand|CHGG|0|1|36",

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
		// "1911" and "acp" earn their place from a real miss: Weapons of
		// Saturn's 1911 sits on slot 8, matched no name or ammo token, and
		// fell through to the slot fallback -- where slot 8 means "second
		// BFG". A BFG10k on a .45 automatic. Both tokens are unambiguous
		// (no other weapon word contains either), and "acp" also catches
		// the ammo class, since AmmoArchetype runs names through here too.
		if (hay.IndexOf("pistol") >= 0 || hay.IndexOf("handgun") >= 0
		 || hay.IndexOf("glock") >= 0 || hay.IndexOf("autoloader") >= 0
		 || hay.IndexOf("9mm") >= 0 || hay.IndexOf("luger") >= 0
		 || hay.IndexOf("beretta") >= 0 || hay.IndexOf("deagle") >= 0
		 || hay.IndexOf("1911") >= 0 || hay.IndexOf("acp") >= 0
		 || hay.IndexOf("makarov") >= 0 || hay.IndexOf("tokarev") >= 0
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
	// question. It is an RS-fork export (FORK_CHANGES.md Ã‚Â§15); on stock GZDoom
	// this is not answerable from ZScript at all.
	//
	// READ IT OFF THE DEFAULTS, NEVER OFF A LIVE ACTOR. A_ChangeModel sets
	// hasmodel on the instance as a side effect, so an instance read reports
	// true for every weapon we already painted -- and the second scan would
	// skip everything the first one bound.
	static bool HasOwnModel(class<Weapon> type)
	{
		return RS_Fork.HasOwnModel(type);
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

			// String.Length() is unsigned; every counter here is a signed
			// int. Hoisting the lengths into int locals keeps the loop
			// guards signed-vs-signed -- six "comparison between signed and
			// unsigned" warnings on every single load otherwise, which
			// buries real diagnostics in the session log.
			int lnLen  = int(ln.Length());
			int lowLen = int(low.Length());

			// #include -- and DECORATE includes are often UNQUOTED
			// ("#Include Actors/Weapons/Crowbar.txt", Ashes does exactly
			// this), so both forms have to parse.
			int inc = low.IndexOf("#include");
			if (inc >= 0)
			{
				int p = inc + 8;
				while (p < lnLen && (ln.ByteAt(p) == 32 || ln.ByteAt(p) == 9)) p++;
				string path = "";
				if (p < lnLen && ln.ByteAt(p) == 34)   // opening quote
				{
					int q2 = ln.IndexOf("\"", p + 1);
					if (q2 > p) path = ln.Mid(p + 1, q2 - p - 1);
				}
				else
				{
					int s0 = p;
					while (p < lnLen && ln.ByteAt(p) > 32) p++;
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
			while (p < lowLen && (low.ByteAt(p) == 32 || low.ByteAt(p) == 9)) p++;
			bool isDecl = false;
			if (low.Mid(p, 6) == "class " || low.Mid(p, 6) == "class\t") { p += 6; isDecl = true; }
			else if (low.Mid(p, 6) == "actor " || low.Mid(p, 6) == "actor\t") { p += 6; isDecl = true; }
			if (!isDecl) continue;

			while (p < lowLen && (low.ByteAt(p) == 32 || low.ByteAt(p) == 9)) p++;
			int s0 = p;
			while (p < lowLen)
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
	// djb2-style hash, deterministic per class name. Not for security --
	// only for spreading auto-guessed picks across a shelf without ever
	// changing which index a given class name lands on. Wrap-safe: the
	// multiply can overflow into negative territory on a long name, so the
	// final % is corrected the same way CyclePick already does.
	static int HashPick(string cls, int n)
	{
		if (n <= 0) return 0;
		int h = 5381;
		int len = cls.Length();
		for (int i = 0; i < len; ++i)
			h = h * 33 + cls.ByteAt(i);
		int r = h % n;
		if (r < 0) r += n;
		return r;
	}

	static void Scan(RS_ForeignShelf shelf, in out Array<RS_ForeignEntry> outList)
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

			// PICKUP PROXIES ARE NOT WEAPONS YOU HOLD. WeaponGiver derives
			// from Weapon (weapons.zs), so every one of them gets scanned --
			// but its entire job is to hand you a real weapon and vanish. It
			// is never in your hands, so it can never wear a model, and a
			// picker row for it is a row that does nothing. MetaDoom alone
			// ships one per weapon (MetaAxePickup, MetaChaingunPickup...),
			// which is a doubled menu for no benefit.
			if (type is 'WeaponGiver') continue;

			// A mod that already ships its own 3D weapon models is not asking
			// for ours. Leave it alone.
			if (RS_ForeignScanner.HasOwnModel(type)) continue;

			RS_ForeignEntry e = new("RS_ForeignEntry");
			e.clsName = cn;
			e.tag     = def.GetTag(cn);

			// SlotNumber is -1 for weapons that get their slot from
			// KEYCONF/MAPINFO instead of the actor property. Read the
			// player's REAL runtime slot when we can.
			e.slot    = def.SlotNumber;
			e.slotPos = -1;   // only a real slot binding sets this
			bool located = false;
			PlayerInfo pl = players[consolePlayer];
			if (pl && pl.mo)
			{
				int sl; int prio;
				[located, sl, prio] = pl.weapons.LocateWeapon(type);
				if (located) { e.slot = sl; e.slotPos = prio; }
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

			// pick == 0 is Classify's universal "no deliberate index" value
			// (the only nonzero it ever hands back is the forced pick 2 for
			// the slot-8 second BFG, which must never be overridden). Seed
			// the auto-guess by class name instead of leaving it at the
			// shelf's first entry for everything -- every unpinned weapon of
			// an archetype otherwise wore the exact same donor forever.
			if (pick == 0 && shelf)
			{
				int have = shelf.Count(e.archetype);
				if (have > 1) pick = HashPick(e.clsName, have);
			}

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
	RS_ForeignPickPersist mPicks; // player's model choices, keyed by class -- de facto per-mod profiles

	// Per-hand display state. Two fields now: the remap engine reads the
	// weapon's own state machine every tic, so there is nothing to track
	// between tics beyond who we're painting and where we parked.
	RS_ForeignHand  mHandMain;
	RS_ForeignHand  mHandOff;

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
		if (!mPicks)   { mPicks   = new("RS_ForeignPickPersist"); mPicks.Load(); }
		if (!mHandMain) mHandMain = new("RS_ForeignHand");
		if (!mHandOff)  mHandOff  = new("RS_ForeignHand");
		mHandMain.Reset();
		mHandOff.Reset();

		Array<RS_ForeignEntry> keep;
		for (int i = 0; i < mEntries.Size(); ++i)
			if (mEntries[i].pinned) keep.Push(mEntries[i]);

		RS_ForeignScanner.Scan(mShelf, mEntries);

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
		ReportScan();
	}

	// WHICH MOD IS THIS. The engine prints its "adding X.pk3" list before
	// autoexec opens the logfile, so a session log never says what was
	// actually loaded -- which makes reading a log after the fact a guessing
	// game. The scan already knows: provenance harvesting recorded the
	// archive that DEFINED each weapon class. Print that, once, with counts.
	// One line per source archive turns every log into a self-identifying
	// record of what was tested.
	void ReportScan()
	{
		Array<string> srcNames;
		Array<int>    srcCounts;
		int unknown = 0, visible = 0;

		for (int i = 0; i < mEntries.Size(); ++i)
		{
			if (!mEntries[i].located && !mEntries[i].modDefined) continue;
			visible++;
			string src = mEntries[i].srcContainer;
			if (src.Length() == 0) { unknown++; continue; }

			int at = -1;
			for (int k = 0; k < srcNames.Size(); ++k)
				if (srcNames[k] == src) { at = k; break; }
			if (at < 0) { srcNames.Push(src); srcCounts.Push(1); }
			else        { srcCounts[at] = srcCounts[at] + 1; }
		}

		Console.Printf("[RSRM] scan: %d weapons listed of %d classes compiled%s",
			visible, mEntries.Size(),
			RS_Fork.Supported() ? "" : "  [STATIC BUILD -- no animation]");
		for (int k = 0; k < srcNames.Size(); ++k)
			Console.Printf("[RSRM]   from %s: %d", srcNames[k], srcCounts[k]);
		if (unknown > 0)
			Console.Printf("[RSRM]   slot-bound only, no source archive: %d", unknown);
	}

	// -----------------------------------------------------------------
	// ONE PICKER ROW PER WEAPON *POSITION*, not per class.
	//
	// Mods routinely ship several classes that are the same gun: Ashes'
	// three jackhammer tiers, MetaDoom weapons that morph as you find
	// upgrades, DRLA assembly variants, purist-mode duplicates. Only one
	// of them can ever be in your hands at a given slot position, so
	// giving each its own row is pure menu bloat -- nobody wants to
	// assign a shotgun model three times to guarantee the shotgun slot
	// looks right whatever mode it is in.
	//
	// The slot table already answers this: LocateWeapon returns the slot
	// AND the position within it, and that pair is exactly "which weapon
	// is this, from the player's point of view". Variants that replace
	// each other share it. Genuinely different guns (shotgun at 3:0, SSG
	// at 3:1) do not.
	//
	// Weapons with no slot binding fall back to their own class name --
	// one row each, exactly as before. That keeps Golden Souls-style
	// mods (slots on a player class that never spawns, so located is
	// false for everything) working rather than collapsing their whole
	// arsenal into a single row.
	//
	// PERSISTENCE STAYS PER CLASS. A group write fans out to every
	// member, so the archive is still keyed by class name and still
	// scoped per mod -- "slot 3 pos 1" would collide between mods.
	// -----------------------------------------------------------------
	// The highest ancestor that is ITSELF a real, slot-bound weapon --
	// which is what a tier root looks like and what a shared abstract
	// base does not.
	//
	// Ashes: `actor Glock2 : Glock`, `actor Glock3 : Glock`, where Glock
	// is a genuine weapon sitting in a slot. All three collapse to Glock.
	// The tiers override only Tag, icon and pickup message; mechanically
	// they are one gun.
	//
	// GNRC-WPN: every weapon is `: ModWeapon`, a shared base with no slot
	// that is never in the player's weapon table. Walking blindly to the
	// top would merge that mod's whole arsenal into a single row, so the
	// `located` test is the thing that makes this safe: a base class
	// nobody can wield is not a group root.
	//
	// Weapons Of Saturn: everything derives straight from Weapon, so each
	// is its own root -- correct, they are genuinely different guns.
	//
	// A mod that implements tiers WITHOUT inheritance gets one row each,
	// exactly as before. This can only merge things that are provably
	// related, never guess.
	int GroupRoot(int i) const
	{
		if (i < 0 || i >= mEntries.Size()) return i;
		class<Actor> c = mEntries[i].clsName;
		if (!c) return i;

		readonly<Actor> dc = GetDefaultByType(c);
		if (!dc) return i;

		int best = i;
		class<Object> p = c.GetParentClass();
		for (int guard = 0; p != null && p != "Weapon" && guard < 16; ++guard)
		{
			int j = FindEntry("" .. p.GetClassName());
			if (j >= 0 && mEntries[j].located)
			{
				// INHERITED ANIMATION IS THE TEST, not merely descent.
				//
				// A tier that is the same gun overrides cosmetics and keeps
				// its parent's states: Ashes' `Glock2 : Glock` changes Tag,
				// icon and pickup text, so both resolve to the SAME Ready
				// state pointer, and one picker row is right.
				//
				// A subclass that redeclares States{} is a different weapon
				// wearing an inheritance link for convenience. Project
				// Brutality's `PB_PulseCannon : PB_M1Plasma` is a whole
				// separate sprite family; DoomRL Arsenal's 223 assemblies
				// each declare their own. Merging those is wrong, and in
				// DRLA's case catastrophic -- its RLWeapon base is itself
				// slot-bound, so a descent-only rule collapsed 222 weapons
				// into a single row.
				//
				// Comparing the resolved Ready pointer answers exactly
				// "does this share its parent's animation", which is the
				// real question. Falls back to Select for the rare weapon
				// with no Ready.
				class<Actor> pc = (class<Actor>)(p);
				readonly<Actor> dp = pc ? GetDefaultByType(pc) : null;
				if (dp)
				{
					State sc = dc.FindState('Ready');
					State sp = dp.FindState('Ready');
					if (sc == null && sp == null)
					{
						sc = dc.FindState('Select');
						sp = dp.FindState('Select');
					}
					if (sc != null && sc == sp) best = j;
				}
			}
			p = p.GetParentClass();
		}
		return best;
	}

	string GroupKey(int i) const
	{
		if (i < 0 || i >= mEntries.Size()) return "";

		// COLLAPSE BY FAMILY. Arsenal mods defeat ancestry grouping by
		// building weapons combinatorially rather than by inheritance --
		// DoomRL Arsenal's assemblies are base weapon x mod pack, so
		// "Demolition Ammo Chaingun" and "Nanomachic Chaingun" are
		// unrelated classes that are both, visibly, a chaingun. 150 rows
		// of that is unusable however correct each row is.
		//
		// With this on, one row per family: the whole menu becomes
		// "shotgun -> this model, chaingun -> that model", which is what
		// the player wanted to say in the first place. Off by default,
		// because on a normal mod each weapon deserves its own say.
		CVar fc = CVar.FindCVar("rs_foreignmodels_byfamily");
		if (fc && fc.GetBool())
			return "a:" .. mEntries[i].archetype;

		return "c:" .. mEntries[GroupRoot(i)].clsName;
	}

	bool ByFamily() const
	{
		CVar fc = CVar.FindCVar("rs_foreignmodels_byfamily");
		return (fc && fc.GetBool());
	}

	// How many entries share this row's group -- shown in the picker so a
	// collapsed row says so rather than silently hiding classes.
	int GroupSize(int i) const
	{
		string k = GroupKey(i);
		if (k.Length() == 0) return 0;
		int n = 0;
		for (int j = 0; j < mEntries.Size(); ++j)
			if (GroupKey(j) == k) n++;
		return n;
	}

	int FindEntry(string cls) const
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
		// our class (brings its Path/Skin/Scale/Offset along), then hand the
		// ENGINE the state->frame table. From that moment the renderer
		// resolves every frame against the psprite's own current state
		// natively -- there is no step 3 anymore, and no per-tick script in
		// the animation path at all. (RegisterModelStateFrame requires
		// modelData, which A_ChangeModel just created, so the order of
		// these two calls is load-bearing.)
		if (lastBound != w)
		{
			w.A_ChangeModel(mcls);

			// Static build (stock GZDoom / QuestZDoom): the bind above is
			// the whole feature there -- A_ChangeModel is stock, the pin
			// below is stock, and the weapon wears its donor at the rest
			// pose. Everything past here needs the fork's animation
			// extensions, so it is skipped wholesale rather than run into
			// no-op shims.
			if (RS_Fork.Supported())
			{
				let map = MapFor(w, mcls, frameCount, restFrame);
				RS_Fork.ClearRows(w);
				int pushed = 0;
				for (int i = 0; i < map.mStates.Size(); ++i)
					if (RS_Fork.RegisterRow(w, map.mStates[i], map.mMesh[i], map.mMeshNext[i]))
						pushed++;
				if (RS_ForeignRemap.DebugOn())
					Console.Printf("[RSRM] bound %s -> %s: %d/%d rows registered",
						w.GetClassName(), mcls, pushed, map.mStates.Size());
			}
		}

		// STEP 2 -- every tick: their states re-set the psprite each frame,
		// so re-pin it to our anchor at the resting pose. The pin is what
		// makes FindModelFrame resolve; the frame NUMBER now comes from the
		// engine-side table. The legacy per-tick fields are cleared so
		// nothing serialized from an older build can fight the table.
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

			RS_Fork.ReleaseFrames(psp);

			// HEALTH TELEMETRY + SELF-HEALING. Same lookup the renderer
			// performs, against the same table. A hit records the heal
			// context (which row, which table). A miss on a displaying
			// state is the unambiguous signature of a runtime jump the
			// walk could not see -- so the table repairs itself on the
			// spot: the orphaned chain is claimed into the interrupted
			// group and the rest of its clip distributed across it,
			// registered with the engine THIS tic. The renderer's next
			// consult already hits. See RS_ForeignRemap.HealFrom.
			State cur = psp.CurState;
			if (cur != null && RS_Fork.Supported())
			{
				let map = MapFor(w, mcls, frameCount, restFrame);
				if (map != null)
				{
					int row = map.LookupIndex(cur);

					if (row < 0 && cur.Tics != 0)
					{
						// WHICH CLIP DOES THE ORPHAN CHAIN BELONG TO?
						//
						// Inheriting the last mapped state's group is only
						// right MID-ACTION. Pressing altfire straight from
						// idle lands on an orphan chain while the last
						// mapped state was the ready loop -- healing off
						// that would spread the one-frame ready clip across
						// the whole altfire animation and cache it, freezing
						// that weapon's altfire permanently.
						//
						// The button is the honest signal: the engine's own
						// P_CheckWeaponButtons jumps to Fire/AltFire/Reload
						// by name, so a button held on the tic the psprite
						// leaves mapped territory names the sequence that
						// was just entered. Offhand buttons map the same way
						// for the offhand layer.
						int btn = pi.cmd.buttons;
						bool off = (layer == PSP_OFFHANDWEAPON);
						int gid = -1;
						if (btn & (off ? BT_OFFHANDALTATTACK : BT_ALTATTACK))
							gid = map.FindGroupByClip("altfire");
						else if (btn & (off ? BT_OFFHANDRELOAD : BT_RELOAD))
							gid = map.FindGroupByClip("reload");
						else if (btn & (off ? BT_OFFHANDATTACK : BT_ATTACK))
							gid = map.FindGroupByClip("fire");

						int startIdx = 0;   // a button press starts its clip
						if (gid < 0 && hs.lastMap == map && hs.lastHitRow >= 0)
						{
							// No button: this is a continuation of whatever
							// was already running. Only inherit a real
							// ACTION group -- never "ready", which is the
							// freeze case above.
							int g = map.GroupIdOfRow(hs.lastHitRow);
							if (g >= 0 && map.GroupClip(g) != "ready")
							{
								gid      = g;
								startIdx = map.EndIdxOfRow(hs.lastHitRow);
							}
						}

						// No confident group: hold the pose and DO NOT
						// cache. A wrong heal is permanent; a skipped one
						// costs a tic and retries.
						if (gid >= 0)
						{
							int n = map.HealInto(gid, startIdx, cur, w);
							if (n > 0)
							{
								hs.healed += n;
								row = map.LookupIndex(cur);
							}
						}
					}

					if (row >= 0)
					{
						hs.hits++;
						hs.lastMesh   = map.mMesh[row];
						hs.lastMap    = map;
						hs.lastHitRow = row;
					}
					else if (cur.Tics != 0)   // 0-tic states never display; not a hole
					{
						hs.misses++;
						hs.missSprite = cur.sprite;
						hs.missFrame  = cur.Frame;
						hs.missTics   = cur.Tics;
					}
				}
			}
		}
		return w;
	}

	// Print and reset both hands' telemetry. Ten-second cadence: coarse
	// enough to stay readable, fine enough that a session log shows every
	// stretch of play.
	void ReportHealth()
	{
		PlayerInfo pi = players[consolePlayer];
		for (int hand = 0; hand < 2; ++hand)
		{
			RS_ForeignHand hs = (hand == 1) ? mHandOff : mHandMain;
			if (hs == null || (hs.hits == 0 && hs.misses == 0)) continue;

			Weapon w = (hand == 1) ? pi.OffhandWeapon : pi.ReadyWeapon;
			string wn = w ? "" .. w.GetClassName() : "?";
			// Which table served this interval -- donor and size. An
			// all-miss interval with a healthy-sized table is a lookup
			// problem; with no table at all it is a bind problem. The
			// line should say which.
			if (hs.lastMap != null)
				wn = wn .. " [" .. hs.lastMap.donor .. ", table=" .. hs.lastMap.mStates.Size() .. "]";
			int total = hs.hits + hs.misses;
			string healedNote = (hs.healed > 0)
				? String.Format(" -- healed %d states", hs.healed) : "";
			if (hs.misses > 0)
				Console.Printf("[RSRM] health %s %s: %d/%d tics mapped -- top hole spr=%d fr=%d tics=%d%s",
					hand == 1 ? "offhand" : "mainhand", wn, hs.hits, total,
					hs.missSprite, hs.missFrame, hs.missTics, healedNote);
			else
				Console.Printf("[RSRM] health %s %s: %d/%d tics mapped%s",
					hand == 1 ? "offhand" : "mainhand", wn, hs.hits, total, healedNote);
			hs.hits = 0; hs.misses = 0; hs.healed = 0;
			hs.missSprite = -1; hs.missFrame = -1; hs.missTics = -1;
		}
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

		// Every ten seconds, say how the table did. See ReportHealth.
		if (mBound && level.maptime > 0 && level.maptime % 350 == 0)
			ReportHealth();

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
				if (loc) { mEntries[i].slot = sl; mEntries[i].slotPos = prio; }
			}
		}
	}

	// -----------------------------------------------------------------
	// THE ANIMATION, remap edition. Their state machine is the clock:
	// psp.CurState -> one table lookup -> mesh frame. The table is built
	// once per (weapon class, donor) by walking their labeled sequences
	// (see RS_ForeignRemap). Nothing here learns, predicts, glues, or
	// times -- the machinery that used to (boundary detection, duration
	// learning, ammo rates, evidence gates, timing persistence) is gone,
	// and every bug it hosted went with it.
	// -----------------------------------------------------------------
	Array<RS_ForeignRemap> mMaps;   // per (class, donor); session-lifetime

	RS_ForeignRemap MapFor(Weapon w, string donor, int frameCount, int restFrame)
	{
		string cn = w.GetClassName();
		for (int i = 0; i < mMaps.Size(); ++i)
			if (mMaps[i].clsName == cn && mMaps[i].donor == donor) return mMaps[i];

		let m = RS_ForeignRemap.Build((class<Weapon>)(w.GetClass()), donor,
		                              mClips, frameCount, restFrame);
		mMaps.Push(m);
		return m;
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
				RS_Fork.ReleaseFrames(psp);
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
	//   selector 0 = family, 1 = model (one model, both hands)
	// Three int args is exactly what SendNetworkEvent carries.
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

		// Themed loadout: every visible weapon wears one set, families kept.
		// arg 0: 0 VanAlek, 1 Bv21, 2 MeatG, 3 BWolf.
		if (e.name == "rs-fm-assign-set")
		{
			if (multiplayer) return;
			int setIdx = e.args[0];
			if (setIdx < 0 || setIdx > 3) return;
			AssignSet(setIdx);
			return;
		}

		// (rs-fm-forget is gone: the remap engine learns nothing, so there
		// is nothing to forget. Model choices are still clearable below.)
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
		// Netevent args are attacker-controlled in principle; validate.
		if (sel < 0 || sel > 1) return;
		if (dir != 1 && dir != -1) return;

		if (sel == 0) CycleArchetype(row, dir);
		else          CyclePick(row, dir);
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

	// Applies to the whole GROUP -- every class sharing this weapon's slot
	// position. One assignment covers a mod's tiers/modes of one gun. See
	// GroupKey.
	void SetArchetype(int i, string a)
	{
		if (i < 0 || i >= mEntries.Size()) return;
		string k = GroupKey(i);
		for (int j = 0; j < mEntries.Size(); ++j)
		{
			if (GroupKey(j) != k) continue;
			mEntries[j].archetype  = a;
			mEntries[j].modelPick1 = 0;
			mEntries[j].modelPick2 = 0;
			mEntries[j].pinned     = true;
			SavePick(j);
		}
		mLastMain = null; mLastOff = null;      // force a re-bind on both hands
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

	// ONE MODEL PER WEAPON, not per hand. Whichever hand is holding it, it
	// wears the same donor -- modelPick1 and modelPick2 are kept mirrored
	// rather than removing the second field outright, so the persistence
	// format (class:archetype:pick1:pick2) and ApplyHand's per-hand reads
	// need no changes; they simply always agree now.
	void CyclePick(int i, int dir)
	{
		if (i < 0 || i >= mEntries.Size()) return;
		if (!mShelf) return;
		int n = mShelf.Count(mEntries[i].archetype);
		if (n <= 0) return;

		int v = (mEntries[i].modelPick1 + dir) % n;
		if (v < 0) v += n;

		// Whole group, same as SetArchetype: the tiers and modes of one
		// weapon move together, because only one of them is ever the gun
		// in your hands.
		string k = GroupKey(i);
		for (int j = 0; j < mEntries.Size(); ++j)
		{
			if (GroupKey(j) != k) continue;
			mEntries[j].modelPick1 = v;
			mEntries[j].modelPick2 = v;
			mEntries[j].pinned     = true;
			SavePick(j);
		}
		mLastMain = null; mLastOff = null;      // force a re-bind on both hands
	}

	// One-button "give everything a one-handed model" -- pistol, revolver or
	// smg, chosen per weapon rather than picking one family for the whole
	// list, so the result actually looks like a varied loadout instead of
	// fifteen copies of the same gun. Every entry ends up pinned and saved,
	// same as if the player had dialled in each one by hand.
	void RandomizeOneHanded()
	{
		if (!mShelf || !mPicks) return;

		int touched = 0;
		for (int i = 0; i < mEntries.Size(); ++i)
		{
			// Only rows the picker shows: the loaded mod's weapons. The
			// engine compiles in hundreds of arsenal classes (Heretic,
			// Hexen, Strife, Chex) that are not part of any loaded mod --
			// randomizing those poisoned the picks archive with junk rows
			// forever, and the per-row save across ~500 entries was the
			// quadratic stall that took a whole VR session down.
			if (!mEntries[i].located && !mEntries[i].modDefined) continue;

			string arch;
			switch (random[MSRandomize](0, 2))
			{
			case 0:  arch = "pistol";   break;
			case 1:  arch = "revolver"; break;
			default: arch = "smg";      break;
			}
			int n = mShelf.Count(arch);
			if (n <= 0) continue;   // standalone build dropped every donor for this row

			int pick = random[MSRandomize](0, n - 1);
			mEntries[i].archetype  = arch;
			mEntries[i].modelPick1 = pick;
			mEntries[i].modelPick2 = pick;   // one model per weapon, both hands
			mEntries[i].pinned     = true;
			mPicks.Store(mEntries[i].clsName, arch, pick, pick, false);
			touched++;
		}

		// One save for the whole batch, not one per row.
		mPicks.Save();
		Console.Printf("[RSRM] randomized %d weapons", touched);

		mLastMain = null; mLastOff = null;
	}

	// Which SET a donor class belongs to -- same prefix logic the picker's
	// Pretty() uses for display, minus the formatting. 0 VanAlek, 1 Bv21,
	// 2 MeatG, 3 BWolf.
	static int SetOfDonor(string cls)
	{
		// sideloaded, supplies its own classes under that prefix and the
		// shelf keeps rows for them -- they are the same guns, so they
		// belong on the same button.
		if (cls.IndexOf("MS_MG_") == 0 || cls.IndexOf("RS_PS_") == 0) return 2;
		if (cls.IndexOf("MS_BW_") == 0)                               return 3;
		return 0;   // VanAlek: the plain MS_/VR_ donors
	}

	// One press: every visible weapon wears the chosen set, KEEPING its
	// family -- a shotgun gets that set's shotgun. Rows whose family has no
	// model in the requested set keep their current pick untouched: a
	// missing model honestly absent beats a wrong one silently present.
	// Batch-saved for the same reason Randomize is.
	void AssignSet(int setIdx)
	{
		if (!mShelf || !mPicks) return;

		int assigned = 0, missing = 0;
		for (int i = 0; i < mEntries.Size(); ++i)
		{
			if (!mEntries[i].located && !mEntries[i].modDefined) continue;

			string arch = mEntries[i].archetype;
			int have = mShelf.Count(arch);
			if (have <= 0) continue;

			int found = -1;
			for (int p = 0; p < have; ++p)
			{
				string mcls, anchor; int hf, rf, fc;
				if (!mShelf.Get(arch, p, mcls, anchor, hf, rf, fc)) continue;
				if (SetOfDonor(mcls) == setIdx) { found = p; break; }
			}
			if (found < 0) { missing++; continue; }

			mEntries[i].modelPick1 = found;
			mEntries[i].modelPick2 = found;
			mEntries[i].pinned     = true;
			mPicks.Store(mEntries[i].clsName, arch, found, found, false);
			assigned++;
		}
		mPicks.Save();

		string setName = setIdx == 1 ? "Bv21" : setIdx == 2 ? "MeatG"
		               : setIdx == 3 ? "BWolf" : "VanAlek";
		Console.Printf("[RSRM] assigned %d weapons to %s (%d families had no %s model, left as-is)",
			assigned, setName, missing, setName);

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
