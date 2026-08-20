// =====================================================================
// RS_Fork -- STOCK GZDOOM / QUESTZDOOM BUILD.
//
// The twin of zscript/RS_ForeignFork.zs. Same class, same signatures,
// same scopes, every fork-only engine symbol removed. build.ps1
// -Static ships this file in place of the other one; nothing else in
// the pk3 differs.
//
// It has to be a whole separate FILE rather than a runtime branch:
// ZScript resolves every field and method reference at compile time,
// so one mention of psp.ModelFrame or Actor.CountStateLabels anywhere
// in the pk3 is a hard load failure on an engine without them. Not a
// warning, not a skipped line -- the mod does not load.
//
// WHAT STILL WORKS HERE, which is most of it: scanning the loaded mod,
// classifying weapons into families, provenance filtering, the picker
// menu, saved picks, Randomize and Assign All, and the actual model
// bind -- A_ChangeModel has been stock since GZDoom 4.11. The psprite
// pin is stock behaviour too. Each weapon therefore wears its donor
// mesh at the anchored rest pose: a correct, properly oriented 3D
// weapon in your hands that does not animate. On a headset that is
// still a large step up from a flat sprite.
//
// WHAT IS GONE: per-frame animation, the state remap table, and the
// "does this mod already ship 3D models" check (which needs the
// hasmodel export). HasOwnModel returning false means a mod that
// already has its own HUD models gets painted over -- switch the mod
// off in the menu when playing one of those.
// =====================================================================

class RS_Fork play
{
	static clearscope bool Supported() { return false; }

	// Needs AActor::hasmodel, a fork export. Answering false is the
	// conservative direction: we paint, rather than silently declining
	// to paint. See the header note.
	static clearscope bool HasOwnModel(class<Weapon> type) { return false; }

	// No per-tick frame override exists to release.
	static void SetNoDraw(PSprite psp, bool v) {}
	static void ReleaseFrames(PSprite psp) {}

	// No native state->frame table. Callers check Supported() before
	// building one, so these should never be reached; they are here so
	// every call site compiles unchanged.
	static void ClearRows(Actor w) {}
	static bool RegisterRow(Actor w, State st, int frameNum, int frameNext) { return false; }

	// No label enumeration. Zero labels means the remap builder produces
	// an empty table and the binder skips the animation path entirely.
	static clearscope int CountLabels(class<Actor> cls) { return 0; }
	static clearscope Name, State LabelAt(class<Actor> cls, int index)
	{
		Name n = 'None';
		State s = null;
		return n, s;
	}
}
