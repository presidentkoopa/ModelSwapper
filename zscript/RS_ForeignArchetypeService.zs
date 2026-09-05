// WHAT KIND OF GUN IS THIS -- answered for anyone, by string.
//
// The classifier (RS_ForeignScanner.Classify) is the one thing in this
// package the rest of the family keeps needing: a support point for two-hand
// stabilize is a per-archetype default, a holster prop wants to know what
// shape to expect, a weapon wheel wants to group. None of them can NAME this
// package -- EventHandler.Find and Service.Find(class) both resolve their
// argument at compile time, and a miss is fatal and global (thingdef.cpp:
// 420-424 refuses every pk3 later in the load order). The wheel already
// reaches the bridge fields through level.GetField* on a handler found by
// Object.FindClass, which works but only answers for a weapon that is in a
// hand right now.
//
// A Service is the one path with no compile-time link in either direction.
// InitServices() instantiates every Service subclass by itself, so this
// registers with nobody naming it, and a consumer finds it with
// ServiceIterator.Find("RS_WeaponArchetypeService") -- a plain string whose
// Next() is simply null when this package is not loaded. Same arrangement the
// grip arbiter uses, for the same reason.
//
// REQUESTS
//   GetInt("hello")                          1 -- "are you there"
//   GetString("weapon.archetype", cls)       archetype for a weapon class name,
//                                            "" if it is not a weapon
//   GetString("weapon.archetype.hand", "", h) archetype of the weapon in hand
//                                            h (0 main, 1 off), "" if none
//   GetString("weapon.donor", "", h)         donor model class currently worn
//                                            by the weapon in hand h, "" when
//                                            that weapon has no bridged model
//
// The archetype comes from the scan table when the weapon was scanned, and
// from a fresh Classify when it was not -- so the answer is the same vocabulary
// either way (pistol, shotgun, rifle, chaingun, rocket, plasma, bfg, melee and
// their leaves; see FallbackArchetype for the tree).
class RS_WeaponArchetypeService : Service
{
	const IDENTITY = 1;

	private RS_ForeignModelHandler handler()
	{
		return RS_ForeignModelHandler(StaticEventHandler.Find("RS_ForeignModelHandler"));
	}

	override int GetInt(String request, string stringArg, int intArg, double doubleArg, Object objectArg, Name nameArg)
	{
		if (request == "hello") return IDENTITY;
		return -1;
	}

	override String GetString(String request, string stringArg, int intArg, double doubleArg, Object objectArg, Name nameArg)
	{
		let h = handler();

		if (request == "weapon.archetype")
		{
			if (stringArg.Length() == 0) return "";
			if (h)
			{
				int i = h.FindEntry(stringArg);
				if (i >= 0) return h.mEntries[i].archetype;
			}
			// Not scanned (a weapon spawned into an inventory the scan never
			// saw, or asked before the scan ran): classify it cold, from the
			// same inputs the scan would have used.
			class<Weapon> type = (class<Weapon>)(stringArg);
			if (!type) return "";
			readonly<Weapon> def = GetDefaultByType(type);
			if (!def) return "";
			string ammo1 = "";
			string ammo2 = "";
			if (def.AmmoType1 != null) ammo1 = "" .. def.AmmoType1.GetClassName();
			if (def.AmmoType2 != null) ammo2 = "" .. def.AmmoType2.GetClassName();
			bool bySlot; int pick;
			return RS_ForeignScanner.Classify(type, stringArg, def.GetTag(), def.SlotNumber,
			                                  ammo1, ammo2, bySlot, pick);
		}

		if (request == "weapon.archetype.hand")
		{
			if (!h) return "";
			if (intArg == 1) return h.mBridgeHasOff  ? h.mBridgeArcheOff  : "";
			return h.mBridgeHasMain ? h.mBridgeArcheMain : "";
		}

		if (request == "weapon.donor")
		{
			if (!h) return "";
			if (intArg == 1) return h.mBridgeHasOff  ? h.mBridgeDonorOff  : "";
			return h.mBridgeHasMain ? h.mBridgeDonorMain : "";
		}

		return "";
	}
}
