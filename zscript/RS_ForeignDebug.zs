// =====================================================================
// RS_ForeignDebug -- TWO CONSOLE COMMANDS THAT ANSWER "WHY DIDN'T IT".
//
// The mod already prints a bind trace, and there is already a Scan
// Report menu. Neither is any use when the question is a specific one
// about a specific weapon, because both make you go looking. These two
// bring the answer to you instead.
//
//     msdebug     every weapon, what it was filed as, what model it
//                 got, and -- when it got nothing -- why not
//     mstrace     watch the mesh frame of the gun in your hands
//                 change, live, one line per change
//
// mstrace is the one for "it twitches". A weapon at rest should print
// nothing at all after the first line: one state, one frame, held. Every
// line it prints while you stand still is a frame change you can see,
// and it names the state that caused it. A twitch stops being a mystery
// once you can read which two frames it is flipping between.
//
// (For a filtered dump: netevent rs-fm-debug:saw . The console alias
// cannot pass one, because netevent takes its arguments in the event
// NAME after a colon rather than as separate tokens.)
//
// NO STATIC FIELDS. ZScript allows static METHODS on a class but not
// static member variables -- "Invalid qualifiers ... (static not
// allowed)". A StaticEventHandler is already a singleton, so the state
// lives on the instance and the static helpers below reach it through
// Find(). This is the standard way to hold mod-global state and the
// reason every accessor here is a two-step.
// =====================================================================
class RS_ForeignDebug : StaticEventHandler
{
	// Live frame trace. Off until asked for, and it only prints on a
	// CHANGE, so a weapon that is genuinely holding still stays silent
	// instead of filling the console with the same number.
	bool  bTrace;
	int   lastFrame;
	State lastState;

	static RS_ForeignDebug Get()
	{
		return RS_ForeignDebug(StaticEventHandler.Find("RS_ForeignDebug"));
	}

	// The per-tick hook tests this before doing any work at all.
	static bool TraceOn()
	{
		let d = Get();
		return d && d.bTrace;
	}

	void ToggleTrace()
	{
		bTrace    = !bTrace;
		lastFrame = -12345;
		lastState = null;
		if (bTrace)
			Console.Printf("\c[Gold][MSTRACE] on. Hold a weapon still -- every line from here is a frame CHANGE.");
		else
			Console.Printf("\c[Gold][MSTRACE] off.");
	}

	// Called from the per-tick pin, once the table has been consulted.
	// row < 0 means the renderer would have found no row for this state.
	static void Frame(Actor w, State cur, int row, int mesh)
	{
		let d = Get();
		if (!d || !d.bTrace || !w) return;
		if (cur == d.lastState && mesh == d.lastFrame) return;   // holding: silent

		string lbl = StateLabel(w, cur);
		if (row < 0)
			Console.Printf("\c[Brick][MSTRACE] %s  state %s  -> NO ROW (renderer falls back)",
				w.GetClassName(), lbl);
		else if (d.lastFrame == -12345)
			Console.Printf("\c[White][MSTRACE] %s  state %s  -> mesh frame %d",
				w.GetClassName(), lbl, mesh);
		else
			Console.Printf("\c[White][MSTRACE] %s  state %s  -> mesh frame %d   (was %d)",
				w.GetClassName(), lbl, mesh, d.lastFrame);

		d.lastState = cur;
		d.lastFrame = mesh;
	}

	// Best-effort name for a state: states have no name of their own, so
	// this walks the label table the remap already relies on and reports
	// the innermost label whose chain contains this state.
	static string StateLabel(Actor w, State s)
	{
		if (!s) return "(null)";
		class<Actor> cls = w.GetClass();
		int n = RS_Fork.CountLabels(cls);
		Name  bestN; State bestS = null;
		for (int i = 0; i < n; ++i)
		{
			Name ln; State ls;
			[ln, ls] = RS_Fork.LabelAt(cls, i);
			if (!ls) continue;
			if (ls == s) return "" .. ln;
			// Keep the label whose chain starts LATEST while still
			// containing s -- that is the one it actually belongs to.
			if (w.InStateSequence(s, ls)
			 && (bestS == null || w.InStateSequence(ls, bestS)))
			{
				bestN = ln; bestS = ls;
			}
		}
		return bestS ? ("" .. bestN) : "?";
	}

	// -----------------------------------------------------------------
	// THE TABLE. One line per scanned weapon: what we filed it as, what
	// model it wears, and the flags that explain a blank.
	// -----------------------------------------------------------------
	static void Dump(string filter)
	{
		let h = RS_ForeignModelHandler.Get();
		if (!h) { Console.Printf("\c[Brick][MSDEBUG] handler not up yet -- start a map first."); return; }

		filter = filter.MakeLower();
		Console.Printf("\c[Gold]-- ModelSwapper: %d weapons scanned%s --",
			h.mEntries.Size(), filter.Length() > 0 ? (", filter '" .. filter .. "'") : "");
		Console.Printf("\c[DarkGray]%-28s %-13s %-4s %-22s %s",
			"WEAPON", "FAMILY", "SLOT", "MODEL", "NOTES");

		int shown = 0;
		for (int i = 0; i < h.mEntries.Size(); ++i)
		{
			let e = h.mEntries[i];
			if (filter.Length() > 0
			 && e.clsName.MakeLower().IndexOf(filter) < 0
			 && e.tag.MakeLower().IndexOf(filter) < 0
			 && e.archetype.MakeLower().IndexOf(filter) < 0) continue;
			shown++;

			string model = "(none)";
			if (h.mShelf)
			{
				if (h.mShelf.Count(e.archetype) <= 0) model = "(family is empty)";
				else                                  model = h.mShelf.NameAt(e.archetype, e.modelPick1);
			}

			// The flags that actually explain a weapon behaving oddly.
			string notes = "";
			if (!e.located)      notes = notes .. "no-slot ";
			if (e.guessedBySlot) notes = notes .. "guessed-from-slot ";
			if (e.pinned)        notes = notes .. "pinned ";
			if (!e.modDefined)   notes = notes .. "engine-class ";
			else if (e.srcContainer.Length() > 0)
				notes = notes .. e.srcContainer .. " ";

			Console.Printf("%-28s \c[Cyan]%-13s\c- %-4d %-22s \c[DarkGray]%s",
				e.clsName, e.archetype, e.slot, model, notes);
		}

		if (shown == 0)
			Console.Printf("\c[Brick]nothing matched. A weapon missing from an UNFILTERED msdebug was never offered a model at all -- that is a scanner miss, not a model miss.");
		else
			Console.Printf("\c[Gold]-- %d shown --", shown);

		DumpLayers();
	}

	// -----------------------------------------------------------------
	// EVERY PSPRITE LAYER, AND WHETHER WE ARE STANDING ON IT.
	//
	// This is the section for "the mod's own effects moved". A mod like
	// Project Brutality builds one gun out of several layers, and we
	// blank the extra ones so its flat art does not draw through our
	// mesh -- SetNoDraw, then the anchor sprite pinned to its
	// out-of-range frame (ApplyHand, and the layer sweep below it).
	//
	// That is correct for a layer drawing part of the GUN. It is wrong
	// for a layer drawing smoke, a flash or a casing, and the only test
	// standing between the two is "is the caller a Weapon" -- which is
	// true for both, because the weapon is what called A_Overlay either
	// way. So if a mod's effects have moved or vanished, the layer it
	// draws them on is in this list with OURS against it, and that is
	// the bug rather than anything about models.
	// -----------------------------------------------------------------
	static void DumpLayers()
	{
		PlayerInfo pi = players[consolePlayer];
		if (!pi) return;
		let h = RS_ForeignModelHandler.Get();

		Console.Printf("\c[Gold]-- psprite layers --");
		// No NODRAW column: NoDraw is a fork-only PSprite field, and this
		// file compiles into the static build too. Caller, sprite and frame
		// identify the layer on their own.
		Console.Printf("\c[DarkGray]%-8s %-28s %-7s %-6s %s",
			"LAYER", "CALLER", "SPRITE", "FRAME", "STATE");

		int n = 0;
		for (let psp = pi.psprites; psp != null; psp = psp.Next)
		{
			n++;
			Actor c = psp.Caller;
			string caller = c ? ("" .. c.GetClassName()) : "(none)";
			bool ours = h && (psp.Sprite == h.mFlashSprMain || psp.Sprite == h.mFlashSprOff);

			// Which layer this is, in words where the engine has a name.
			string lname = "" .. psp.ID;
			if (psp.ID == PSP_WEAPON)         lname = "WEAPON";
			else if (psp.ID == PSP_FLASH)     lname = "FLASH";
			else if (psp.ID == PSP_TARGETCENTER) lname = "RETICLE";

			Console.Printf("%-8s %-28s %-7d %-6d %s%s",
				lname, caller, psp.Sprite, psp.Frame,
				RS_ForeignDebug.StateLabel(c, psp.CurState),
				ours ? "   \c[Brick]<-- OURS (we overwrote this layer)\c-" : "");
		}
		Console.Printf("\c[Gold]-- %d layers --", n);

		// What we are currently painting a model onto, beyond the two hands.
		if (h)
		{
			Console.Printf("\c[Gold]-- overlay actors we bound models to: %d --", h.mOvlBound.Size());
			for (int i = 0; i < h.mOvlBound.Size(); ++i)
			{
				Actor b = h.mOvlBound[i];
				Console.Printf("   %s", b ? ("" .. b.GetClassName()) : "(gone)");
			}
		}
	}

	override void NetworkProcess(ConsoleEvent e)
	{
		if (e.name == "rs-fm-trace") { ToggleTrace(); return; }

		// "rs-fm-debug", or "rs-fm-debug:<filter>"
		string s = "" .. e.name;
		if (s == "rs-fm-debug")            { Dump(""); return; }
		if (s.Left(12) == "rs-fm-debug:")  { Dump(s.Mid(12)); return; }
	}
}
