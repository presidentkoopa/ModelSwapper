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
			"chaingun|RS_GH_Machinegun|HBMG|0|4|36",
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
			"melee|RS_GH_Chainsaw|HBCS|0|27|65",
			"melee|VR_Chainsaw|SAWG|0|0|8",
			"melee|RS_PS_Fist|FSTZ|0|0|9",
			"melee|RS_PS_Chainsaw|SAWG|2|2|6",   // rests on SAWG C, not A

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
			"bfg|MS_BFG10k|BFGG|0|6|21",
			"melee|MS_Fist|PUNG|0|0|57",
			"melee|MS_Chainsaw|SAWG|0|0|8"
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
		if (a == "smg")          return "pistol";
		if (a == "railgun")      return "rifle";
		if (a == "revolver")     return "pistol";
		if (a == "supershotgun") return "shotgun";
		if (a == "flamethrower") return "plasma";
		return "";
	}

	// how many models sit on this archetype's shelf
	int Count(string arche) const
	{
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
		if (hay.IndexOf("chaingun") >= 0 || hay.IndexOf("minigun") >= 0
		 || hay.IndexOf("gatling") >= 0 || hay.IndexOf("machinegun") >= 0) return "chaingun";
		if (hay.IndexOf("rifle") >= 0 || hay.IndexOf("assault") >= 0
		 || hay.IndexOf("ar15") >= 0 || hay.IndexOf("m16") >= 0
		 || hay.IndexOf("ak47") >= 0 || hay.IndexOf("carbine") >= 0
		 || hay.IndexOf("musket") >= 0 || hay.IndexOf("sniper") >= 0
		 || hay.IndexOf("marksman") >= 0 || hay.IndexOf("garand") >= 0
		 || hay.IndexOf("mosin") >= 0) return "rifle";
		// pipebomb/dynamite before any "pipe" melee token.
		// BFG and RAILGUN must be tested BEFORE the rocket line, because
		// "launcher" lives there and would eat BFGLauncher / RailLauncher.
		if (hay.IndexOf("bfg") >= 0) return "bfg";
		// "rail" alone false-positives on guardrail/trail/derail.
		if (hay.IndexOf("railgun") >= 0 || hay.IndexOf("rail gun") >= 0
		 || hay.IndexOf("railrifle") >= 0) return "railgun";
		if (hay.IndexOf("flame") >= 0 || hay.IndexOf("thrower") >= 0) return "flamethrower";
		if (hay.IndexOf("rocket") >= 0 || hay.IndexOf("launcher") >= 0
		 || hay.IndexOf("bazooka") >= 0 || hay.IndexOf("grenade") >= 0
		 || hay.IndexOf("pipebomb") >= 0 || hay.IndexOf("dynamite") >= 0
		 || hay.IndexOf("molotov") >= 0 || hay.IndexOf("satchel") >= 0
		 || hay.IndexOf("mortar") >= 0 || hay.IndexOf("napalm") >= 0) return "rocket";
		if (hay.IndexOf("plasma") >= 0 || hay.IndexOf("energy") >= 0
		 || hay.IndexOf("beam") >= 0)  return "plasma";
		if (hay.IndexOf("pistol") >= 0 || hay.IndexOf("handgun") >= 0
		 || hay.IndexOf("glock") >= 0 || hay.IndexOf("autoloader") >= 0
		 || hay.IndexOf("9mm") >= 0 || hay.IndexOf("luger") >= 0
		 || hay.IndexOf("beretta") >= 0 || hay.IndexOf("deagle") >= 0
		 || hay.IndexOf("desert eagle") >= 0 || hay.IndexOf("sidearm") >= 0) return "pistol";
		if (hay.IndexOf("chainsaw") >= 0 || hay.IndexOf("fist") >= 0
		 || hay.IndexOf("punch") >= 0 || hay.IndexOf("knuckle") >= 0
		 || hay.IndexOf("machete") >= 0 || hay.IndexOf("knife") >= 0
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

	// Is this one of OURS (or a base-game class we don't want to touch)?
	// NOTE: unlike the old scanner this does NOT blanket-skip IWAD names --
	// a mod that REPLACES Shotgun is still a foreign weapon worth modelling.
	static bool IsOurs(string cn)
	{
		return (cn.IndexOf("RS_") == 0 || cn.IndexOf("VR_") == 0
		     || cn.IndexOf("Vanilla_") == 0);
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
	static void Scan(in out Array<RS_ForeignEntry> outList)
	{
		outList.Clear();
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

	RS_ForeignShelf mShelf;   // built once at world-load

	static bool Enabled()
	{
		CVar c = CVar.FindCVar("rs_foreignmodels");
		return (c && c.GetBool());
	}

	static RS_ForeignModelHandler Get()
	{
		return RS_ForeignModelHandler(EventHandler.Find("RS_ForeignModelHandler"));
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
	Weapon ApplyHand(PlayerInfo pi, Weapon w, int layer, int pick, Weapon lastBound)
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
			//
			// The engine does not bounds-check: an out-of-range ModelFrame
			// draws NOTHING, so the weapon vanishes rather than glitching.
			// Clamp here, where the donor's real frame count is known.
			int mf = restFrame;
			if (frameCount > 0 && mf >= frameCount) mf = frameCount - 1;
			if (mf < 0) mf = 0;

			psp.ModelFrame     = mf;
			psp.ModelFrameNext = mf;
			// Lerp 0 with next == current forces nextFrame false: a hard,
			// exact frame with no tween. This is also the kill-switch for the
			// donors whose MODELDEF lacks NoInterpolation (Fist, every
			// RS_PS_*) -- their vanilla-adjacent anchors (PUNG, SHTG, SAWG,
			// PLSC, MGNG, MGUG, BFGN, RLNC, SSGG) can otherwise catch a
			// foreign mod's nextState->sprite and lerp toward garbage.
			psp.ModelFrameLerp = 0;
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
			mi >= 0 ? mEntries[mi].modelPick1 : 0, mLastMain);

		// SAME ACTOR IN BOTH HANDS: A_ChangeModel writes modelData on the
		// actor, not the psprite, so binding the offhand would overwrite the
		// mainhand's modelDef while the mainhand psprite is still pinned to
		// modelPick1's anchor -- lookup misses and a raw sprite appears. One
		// actor gets one model; the mainhand wins.
		if (pi.OffhandWeapon && pi.OffhandWeapon != pi.ReadyWeapon)
			mLastOff = ApplyHand(pi, pi.OffhandWeapon, PSP_OFFHANDWEAPON,
				oi >= 0 ? mEntries[oi].modelPick2 : 0, mLastOff);
		else
			mLastOff = null;

		mBound = (mLastMain != null || mLastOff != null);
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
			"bfg", "melee"
		};
		a.Clear();
		for (int i = 0; i < ARCHE.Size(); ++i) a.Push(ARCHE[i]);
	}

	int EntryCount() const             { return mScanned ? mEntries.Size() : 0; }
	string EntryName(int i) const      { return (i >= 0 && i < mEntries.Size()) ? mEntries[i].clsName : ""; }
	string EntryTag(int i) const       { return (i >= 0 && i < mEntries.Size()) ? mEntries[i].tag : ""; }
	string EntryArchetype(int i) const { return (i >= 0 && i < mEntries.Size()) ? mEntries[i].archetype : ""; }
	bool   EntryUnsure(int i) const    { return (i >= 0 && i < mEntries.Size()) ? mEntries[i].guessedBySlot : false; }
	bool   EntryPinned(int i) const    { return (i >= 0 && i < mEntries.Size()) ? mEntries[i].pinned : false; }
	bool   EntryLocated(int i) const   { return (i >= 0 && i < mEntries.Size()) ? mEntries[i].located : false; }
	int    EntrySlot(int i) const      { return (i >= 0 && i < mEntries.Size()) ? mEntries[i].slot : -1; }

	// hand: 1 = mainhand (Model_1), 2 = offhand (Model_2)
	int EntryPick(int i, int hand) const
	{
		if (i < 0 || i >= mEntries.Size()) return 0;
		return (hand == 2) ? mEntries[i].modelPick2 : mEntries[i].modelPick1;
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
