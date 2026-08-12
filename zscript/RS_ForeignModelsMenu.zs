// =====================================================================
// RS_ForeignModelsMenu -- THE WEAPON MODEL PICKER.
//
// Left column: every foreign weapon the scanner found. Right: three
// cycling selectors per row -- FAMILY, MAINHAND model, OFFHAND model.
//
// The classifier only guesses the FAMILY, and it is wrong roughly a
// quarter of the time (a trumpet that fires musical notes has no Doom
// archetype). So this menu is not a convenience, it is the load-bearing
// half of the feature. Rows the classifier could not read -- the ones
// that fell through to the slot fallback -- are marked '?' and sorted to
// the top, because those are the only ones worth your attention.
//
// SCOPE LAW (see RS_Screens.zs): a menu is UI scope. It may READ plain
// data from the play-side handler through const accessors, but every
// write goes out as the netevent
//
//     rs-fm-cycle <row> <selector> <dir>
//        selector 0 = family, 1 = mainhand model, 2 = offhand model
//
// which RS_ForeignModelHandler.NetworkProcess applies play-side. Calling
// the handler's mutators directly from here is what produced the
// "unknown type" scope errors that killed the previous attempt at this.
//
// Draw() re-reads the handler every frame, so a cycled value updates in
// place without rebuilding the menu -- and because binding is a runtime
// A_ChangeModel call, the gun in your hands changes as you cycle. You
// are looking, not guessing.
// =====================================================================

class RS_Menu_ForeignModels : OptionMenu
{
	override void Init(Menu parent, OptionMenuDescriptor desc)
	{
		desc.mItems.Clear();
		Super.Init(parent, desc);
		Build(desc);
	}

	void Build(OptionMenuDescriptor desc)
	{
		desc.mItems.Push(new("OptionMenuItemStaticText").InitDirect(
			"Foreign Weapon Models", Font.CR_GOLD));

		let h = RS_ForeignModelHandler(EventHandler.Find("RS_ForeignModelHandler"));
		if (!h || h.EntryCount() == 0)
		{
			desc.mItems.Push(new("OptionMenuItemStaticText").InitDirect(
				"No foreign weapons detected.", Font.CR_DARKGRAY));
			desc.mItems.Push(new("OptionMenuItemStaticText").InitDirect(
				"Enable 'rs_foreignmodels' and reload the map.", Font.CR_DARKGRAY));
			desc.mItems.Push(new("OptionMenuItemStaticText").InitDirect(
				"If the list stays empty, try 'rs_foreignmodels_showall 1'.", Font.CR_DARKGRAY));
			return;
		}

		desc.mItems.Push(new("OptionMenuItemStaticText").InitDirect(
			"Left/Right cycles \c[Gold]the highlighted field\c-.  Enter moves between fields.", Font.CR_DARKGRAY));
		desc.mItems.Push(new("OptionMenuItemStaticText").InitDirect(
			"\c[Brick]?\c- = guessed from weapon slot only -- worth a look.", Font.CR_DARKGRAY));
		desc.mItems.Push(new("OptionMenuItemStaticText").InitDirect(" ", Font.CR_WHITE));

		int n = h.EntryCount();

		// Weapons the player has no slot binding for are usually the
		// Heretic/Hexen/Strife arsenals GZDoom compiles into every session --
		// 40-odd rows nobody can ever hold. Hidden unless asked for.
		//
		// They are HIDDEN here rather than dropped at scan time, because some
		// mods (Golden Souls) bind their whole arsenal on their own player
		// class and legitimately report unbound. Dropping them made the
		// feature do nothing at all on those mods.
		bool showAll = false;
		{
			CVar sa = CVar.FindCVar("rs_foreignmodels_showall");
			showAll = (sa && sa.GetBool());
		}

		// UNSURE FIRST. The rows that fell through to the slot fallback are
		// the ones the classifier is admitting it could not read; everything
		// below them is a confident guess that probably needs no attention.
		int shown = 0;
		for (int pass = 0; pass < 2; ++pass)
		{
			bool wantUnsure = (pass == 0);
			for (int i = 0; i < n; ++i)
			{
				if (h.EntryUnsure(i) != wantUnsure) continue;
				if (!showAll && !h.EntryLocated(i)) continue;
				desc.mItems.Push(new("OptionMenuItemRS_ForeignRow").InitRow(i));
				shown++;
			}
		}

		if (shown == 0)
		{
			desc.mItems.Push(new("OptionMenuItemStaticText").InitDirect(
				"Nothing bound to a weapon slot.", Font.CR_BRICK));
			desc.mItems.Push(new("OptionMenuItemStaticText").InitDirect(
				"Switch on 'List Unbound Weapons' to see all " .. n .. ".", Font.CR_DARKGRAY));
		}
	}
}

// ---------------------------------------------------------------------
// One weapon. Three selectors, one focus cursor.
//
// Focus order is MAIN -> OFF -> FAMILY, not family-first: swapping the
// model you are actually holding is the common action, and changing the
// family is the rarer repair. The common case costs zero keypresses.
// ---------------------------------------------------------------------
class OptionMenuItemRS_ForeignRow : OptionMenuItem
{
	int mRow;        // index into the handler's entry list (NOT the display order)
	int mFocus;      // 0 = mainhand, 1 = offhand, 2 = family

	OptionMenuItemRS_ForeignRow InitRow(int row)
	{
		mRow   = row;
		mFocus = 0;
		Super.Init("", "");
		return self;
	}

	override bool Selectable() { return true; }

	// Selector id as NetworkProcess understands it: 0 family, 1 main, 2 off.
	int SelectorId()
	{
		if (mFocus == 2) return 0;
		return mFocus + 1;
	}

	override bool MenuEvent(int mkey, bool fromcontroller)
	{
		if (mkey == Menu.MKey_Left || mkey == Menu.MKey_Right)
		{
			Menu.MenuSound("menu/change");
			EventHandler.SendNetworkEvent("rs-fm-cycle", mRow, SelectorId(),
				(mkey == Menu.MKey_Right) ? 1 : -1);
			return true;
		}
		if (mkey == Menu.MKey_Enter)
		{
			Menu.MenuSound("menu/cursor");
			mFocus = (mFocus + 1) % 3;
			return true;
		}
		return Super.MenuEvent(mkey, fromcontroller);
	}

	// Trim the donor class name down to something readable in a menu row.
	static string Pretty(string cls)
	{
		if (cls.Length() == 0) return "-";
		if (cls.IndexOf("RS_GH_") == 0) return cls.Mid(6);
		if (cls.IndexOf("RS_PS_") == 0) return cls.Mid(6) .. " (MG)";
		if (cls.IndexOf("MS_")    == 0) return cls.Mid(3);
		if (cls.IndexOf("VR_")    == 0) return cls.Mid(3);
		return cls;
	}

	override int Draw(OptionMenuDescriptor desc, int y, int indent, bool selected)
	{
		let h = RS_ForeignModelHandler(EventHandler.Find("RS_ForeignModelHandler"));
		if (!h) return indent;

		// Re-read every frame so a cycled value updates without a rebuild.
		string tag    = h.EntryTag(mRow);
		if (tag.Length() == 0) tag = h.EntryName(mRow);
		bool   unsure = h.EntryUnsure(mRow);
		string fam    = h.EntryArchetype(mRow);
		string m1     = Pretty(h.EntryModelName(mRow, 1));
		string m2     = Pretty(h.EntryModelName(mRow, 2));

		string label = (unsure ? "\c[Brick]?\c- " : "  ") .. tag;
		mLabel = label;
		int x = drawLabel(indent, y, selected ? OptionMenuSettings.mFontColorSelection
		                                      : OptionMenuSettings.mFontColor);

		// Bracket whichever field Left/Right will move.
		string sf = (selected && mFocus == 2) ? "\c[Gold]" : "\c[White]";
		string s1 = (selected && mFocus == 0) ? "\c[Gold]" : "\c[White]";
		string s2 = (selected && mFocus == 1) ? "\c[Gold]" : "\c[White]";

		string val = sf .. fam .. "\c-  " .. s1 .. m1 .. "\c-  \c[DarkGray]/\c- " .. s2 .. m2 .. "\c-";
		drawValue(indent, y, OptionMenuSettings.mFontColorValue, val, false, false);
		return indent;
	}
}

// =====================================================================
// RS_Menu_ForeignReport -- the scan dump, as a screen.
//
// The console version of this is useless in VR, so everything the
// scanner knows is shown here instead: what it found, which slot each
// weapon sits in, what family it guessed, and whether that guess came
// from reading the weapon or from falling back to its slot number.
//
// Read-only. Changes are made in the picker.
// =====================================================================
class RS_Menu_ForeignReport : OptionMenu
{
	override void Init(Menu parent, OptionMenuDescriptor desc)
	{
		desc.mItems.Clear();
		Super.Init(parent, desc);
		Build(desc);
	}

	void Build(OptionMenuDescriptor desc)
	{
		let h = RS_ForeignModelHandler(EventHandler.Find("RS_ForeignModelHandler"));

		desc.mItems.Push(new("OptionMenuItemStaticText").InitDirect(
			"Scan Report", Font.CR_GOLD));

		if (!h || h.EntryCount() == 0)
		{
			desc.mItems.Push(new("OptionMenuItemStaticText").InitDirect(
				"Nothing scanned.", Font.CR_BRICK));
			desc.mItems.Push(new("OptionMenuItemStaticText").InitDirect(
				"Turn Enable on, then Rescan -- or load a map.", Font.CR_DARKGRAY));
			desc.mItems.Push(new("OptionMenuItemStaticText").InitDirect(
				"Still empty? Switch on 'List unbound weapons':", Font.CR_DARKGRAY));
			desc.mItems.Push(new("OptionMenuItemStaticText").InitDirect(
				"some mods put weapon slots on their own player class.", Font.CR_DARKGRAY));
			return;
		}

		int n = h.EntryCount();
		int unsure = 0, pinned = 0;
		for (int i = 0; i < n; ++i)
		{
			if (h.EntryUnsure(i)) unsure++;
			if (h.EntryPinned(i)) pinned++;
		}

		desc.mItems.Push(new("OptionMenuItemStaticText").InitDirect(
			String.Format("%d foreign weapons  --  %d guessed from slot only  --  %d set by you",
				n, unsure, pinned), Font.CR_DARKGRAY));
		desc.mItems.Push(new("OptionMenuItemStaticText").InitDirect(" ", Font.CR_WHITE));

		for (int i = 0; i < n; ++i)
		{
			string src;
			if (h.EntryPinned(i))       src = "\c[Green]yours\c-";
			else if (h.EntryUnsure(i))  src = "\c[Brick]slot only\c-";
			else                        src = "\c[Gold]read\c-";

			string slot = (h.EntrySlot(i) >= 0)
				? String.Format("slot %d", h.EntrySlot(i))
				: "no slot";

			desc.mItems.Push(new("OptionMenuItemStaticText").InitDirect(
				String.Format("%s  \c[DarkGray](%s)\c-", h.EntryName(i), slot), Font.CR_WHITE));
			desc.mItems.Push(new("OptionMenuItemStaticText").InitDirect(
				String.Format("      %s  ->  %s   [%s]",
					h.EntryArchetype(i),
					OptionMenuItemRS_ForeignRow.Pretty(h.EntryModelName(i, 1)),
					src), Font.CR_DARKGRAY));
		}
	}
}
