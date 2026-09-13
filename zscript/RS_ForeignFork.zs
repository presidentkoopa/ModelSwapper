// =====================================================================
// RS_Fork -- EVERY FORK-ONLY ENGINE CALL, IN ONE PLACE.
//
// THIS IS THE DESKTOP (DoomXR fork) VERSION. Its twin lives at
// zscript/static/RS_ForeignFork.zs and is the stock-GZDoom /
// QuestZDoom build: same class, same signatures, all no-ops. The build
// script swaps one for the other, so there is ONE codebase and no
// second copy to drift.
//
// Why a shim at all: ZScript resolves every field and method reference
// at COMPILE time, whether or not the line ever runs. A single mention
// of psp.ModelFrame or Actor.CountStateLabels anywhere in the pk3 is a
// hard load failure on an engine that lacks it -- there is no runtime
// feature test, no graceful skip. So every fork-only symbol has to be
// quarantined in a file that can be replaced wholesale.
//
// The fork adds three things this file wraps (FORK_CHANGES.md):
//   1. psp.ModelFrame / ModelFrameNext / ModelFrameLerp
//   2. Actor.RegisterModelStateFrame / ClearModelStateFrames
//   3. Actor.CountStateLabels / GetStateLabelAt
// ...plus AActor::hasmodel, exported for HasOwnModel.
//
// SCOPE: the class is `play` because writing psprite fields and calling
// the registration natives are play-side actions. The four read-only
// queries are marked `clearscope` individually so the scanner -- which
// runs in data context -- can still call them.
//
// Supported() is what callers branch on. When it is false the mod still
// scans, classifies, picks and BINDS -- A_ChangeModel is stock as of
// GZDoom 4.11 -- it simply never drives frames, so each weapon wears
// its donor at the anchored rest pose: a correct 3D weapon that does
// not animate.
// =====================================================================

class RS_Fork play
{
	// Does this engine have the animation extensions?
	static clearscope bool Supported() { return true; }

	// BT_OFFHANDATTACK / BT_OFFHANDALTATTACK -- VR dual-wield button bits,
	// fork-only like everything else here. Referenced directly by name
	// anywhere in the pk3, they are a hard compile failure on stock
	// GZDoom / QuestZDoom, same as every other symbol in this file --
	// see the header note. Quest gets no offhand distinction either way
	// (it never drives per-hand frames), so the static twin can return 0
	// with nothing lost.
	static clearscope int OffhandAttackButton() { return BT_OFFHANDATTACK; }
	static clearscope int OffhandAltAttackButton() { return BT_OFFHANDALTATTACK; }

	// AActor::hasmodel, set on class defaults by the MODELDEF parser --
	// the same flag FindModelFrameRaw gates on, so it answers exactly
	// "does this class already carry a HUD model of its own".
	//
	// READ OFF THE DEFAULTS, NEVER A LIVE ACTOR: A_ChangeModel sets
	// hasmodel on the instance as a side effect, so an instance read
	// reports true for every weapon we already painted.
	static clearscope bool HasOwnModel(class<Weapon> type)
	{
		readonly<Actor> def = GetDefaultByType(type);
		return (def && def.hasmodel);
	}

	// Release the per-tick frame override. ModelFrame persists on the
	// psprite layer and is serialised, so leaving it set would keep
	// forcing a frame number onto whatever renders next.
	// Stop a layer drawing outright. The weapon keeps its states, damage and
	// slot; only the pixels stop. Fork-only -- the static build has no such
	// field, and hiding a layer there falls back to pinning it at a frame the
	// mesh does not have.
	static void SetNoDraw(PSprite psp, bool v)
	{
		if (psp) psp.NoDraw = v;
	}

	static void ReleaseFrames(PSprite psp)
	{
		if (!psp) return;
		psp.ModelFrame     = -1;
		psp.ModelFrameNext = -1;
		psp.ModelFrameLerp = -1;
	}

	// The native state->frame table. Registration requires modelData,
	// which A_ChangeModel creates -- call order is load-bearing.
	static void ClearRows(Actor w)
	{
		if (w) w.ClearModelStateFrames();
	}

	static bool RegisterRow(Actor w, State st, int frameNum, int frameNext)
	{
		if (!w || !st) return false;
		return w.RegisterModelStateFrame(st, frameNum, frameNext);
	}

	// Full label enumeration, sorted by state address (= source
	// declaration order). FindState can only probe names known in
	// advance; this is what makes mod-custom labels visible at all.
	static clearscope int CountLabels(class<Actor> cls)
	{
		return Actor.CountStateLabels(cls);
	}

	static clearscope Name, State LabelAt(class<Actor> cls, int index)
	{
		Name n; State s;
		[n, s] = Actor.GetStateLabelAt(cls, index);
		return n, s;
	}
}
