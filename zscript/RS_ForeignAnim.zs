// =====================================================================
// RS_ForeignAnim -- PLAYING OUR ANIMATION ON THEIR TIMING.
//
// Their weapon runs its own states at its own pace. We do not get to know
// what those states MEAN -- every structural way of asking was tried and
// each one broke on real mods:
//
//   * psprite y-kinematics: Offset(x,y) compiles to Misc1/Misc2 and
//     SetState writes `oldx = x` in one statement, so the delta is zero
//     on exactly the states the maths needed.
//   * the muzzle-flash layer: A_GunFlash appears ZERO times in either
//     Golden Souls or Ashes.
//   * state-chain membership: a walk from the Reload head reaches the
//     idle loop through NextState, so it labels Ready as Reload.
//   * summing state tics for a duration: Ashes' revolver reload hides
//     its whole body behind a 0-tic conditional jump. Predicts 1 tic,
//     actually runs 68.
//
// So identity is not a NAME here. It is the ENTRY STATE POINTER.
// (foreignClass, entryState) is stable, exact and mod-independent. We
// watch a sequence once to learn how long it really ran and where its
// bright frame fell, then replay our matching clip stretched across that
// learned duration. We never have to be RIGHT about whether it is called
// "Fire" -- only CONSISTENT.
//
// Which clip to play for a learned key is a PRIOR. It is allowed to be
// wrong, because the picker is the correction path.
// =====================================================================

// ---------------------------------------------------------------------
// One donor animation clip, expanded to one frame per tic.
//
// Table rows: donorClass|seq|steps|markFire|markEject|markFeed
//   steps -- comma separated; "f@t" holds frame f for t tics,
//            "a-b@t" runs a to b inclusive (either direction), t tics
//            PER FRAME.
//   marks -- clip-tic offsets of the shot / shell eject / magazine
//            seat. -1 = none. Used to anchor the warp so the recoil
//            lands on their shot rather than merely near it.
// ---------------------------------------------------------------------
// ---------------------------------------------------------------------
// ADDONS. A pk3 loaded beside ModelSwapper can bring its own models. It
// declares its donor classes (class X : Actor {}) and their MODELDEF
// blocks as the built-in ones are, and carries a text lump named MSADDON
// (msaddon.txt at its root) whose lines join the built-in tables:
//
//   shelf family|donorClass|anchor|hand|restFrame|frameCount
//   name  donorClass|Name shown in the menu
//   clip  donorClass|seq|steps|markFire|markEject|markFeed
//
// Row formats are exactly the built-in SHELF, NAMES and CLIP rows. Shelf
// rows from addons go FIRST in their family, so loading an addon makes
// its models the default there. Every MSADDON lump in the load is read;
// lines with any other start are ignored, so // comments are free.
// No MSADDON lump, no change.
// ---------------------------------------------------------------------
class RS_ForeignAddon
{
	static clearscope void Rows(string tag, out Array<string> rows)
	{
		rows.Clear();
		string pfx = tag .. " ";
		int lump = -1;
		while ((lump = Wads.FindLump("MSADDON", lump + 1)) != -1)
		{
			string text = Wads.ReadLump(lump);
			Array<string> lines;
			text.Split(lines, "\n");
			for (int i = 0; i < lines.Size(); ++i)
			{
				string l = lines[i];
				l.Replace("\r", "");
				l.StripLeftRight();
				if (l.IndexOf(pfx) == 0) rows.Push(l.Mid(pfx.Length()));
			}
		}
	}
}

class RS_ForeignClip
{
	Array<string> mRows;

	void Build()
	{
		static const string CLIP[] = {
			"MS_AE_Pistol|ready|0@1|-1|-1|-1",
			"MS_AE_Pistol|fire|1@2,2@2,3@2,4@2,5@2|0|-1|-1",
			"MS_AE_Pistol|reload|6-19@2|-1|0|10",
			"MS_AE_Shotgun|ready|0@1|-1|-1|-1",
			// FROM THE SOURCE'S OWN SECTIONS (modeldef.shotgun.txt): Ready 0,
			// Fire 1-3, Pump 4-13, Reloading 14-28. The old fire clip was a
			// hand-made bounce over 0-5 and never reached most of the pump --
			// the pump surface travels 17 units across 6-12 and nothing played
			// it. Fire is the shot then the whole pump, as authored.
			"MS_AE_Shotgun|fire|1@1,2@1,3@1,4-13@1|0|-1|-1",
			"MS_AE_Shotgun|reload|14-28@2|-1|0|12",
			// FROM THE SOURCE'S OWN SECTION COMMENTS (Aliens Eradication,
			// modeldef.flamethrower.txt): Ready 0, Fire 1-3, "Reloading -
			// drop canister" 5-9, "Reloading - add new canister" 11-19.
			// Frame 4 duplicates 0; frame 10 is its no-canister ready pose.
			//
			// The reload is fourteen frames and nothing had ever played it.
			// It also explains the pitch readings on 7-10: the canister
			// leaves the gun, so the measured long axis briefly becomes the
			// canister's path rather than the barrel.
			"MS_AE_Flamer|fire|1@1,2@1,3@1|0|-1|-1",
			"MS_AE_Flamer|ready|0@1|-1|-1|-1",
			"MS_AE_Flamer|reload|5@1,6@1,7@1,8@1,9@1,11@1,12@1,13@1,14@1,15@1,16@1,17@1,18@1,19@1|-1|-1|-1",
			"MS_AE_Flamer|select|0@1|-1|-1|-1",
			"MS_RC_Auto9|ready|0@1|-1|-1|-1",
			"MS_RC_Auto9|fire|1@2,1@2,1@2,2@8|0|-1|-1",
			"MS_Cola_Revolver|ready|0@1|-1|-1|-1",
			// FROM THE SOURCE (Cola-3-VR-Weapons, modeldef.revolver.txt): Ready 0,
			// then SIX fire cycles of five frames, one per chamber -- 1-5, 6-10,
			// 11-15, 16-20, 21-25, 26-30 -- and the reload at 31-54: eject 31-33,
			// drop 34-37, insert 38-41, close 42-44, spin-up 45-54. Our old rows
			// called 7-30 "reload" (it is fire cycles two to six) and never
			// reached the reload at all. Fire is one chamber cycle; the mod's
			// own fire states already repeat it per shot.
			"MS_Cola_Revolver|fire|1-5@1|0|-1|-1",
			"MS_Cola_Revolver|reload|31-54@1|-1|0|20",
			"MS_RC_Chainsaw|ready|0-10@1|-1|-1|-1",
			// FROM THE SOURCE (Robocop-Retribution, modeldefs/weapons/grinder.txt):
			// //Fire is 37-40, //Hold is 41-44. Measured: the whole saw swings 45
			// units forward across 37-40 and holds there through 44. Our old fire
			// row, 11-24, was a guess. 11-36 sits under the source's Ready block
			// on a second sprite set with no comment; measured, only the blade
			// moves there (a smooth 13-16-0 cycle), hand static, pitch flat --
			// the chain running. That is the rev, so it is altfire: the second
			// trigger on a saw in every mod that has one, and nothing plays it
			// in a mod that does not. Ready stays 0-10, chain still.
			// (chainsaw_hand is a baked-in hand surface that swings with the
			// saw; removing it is mesh surgery, not a clip change.)
			"MS_RC_Chainsaw|fire|37-44@1|0|-1|-1",
			"MS_RC_Chainsaw|altfire|11-36@1|0|-1|-1",
			// A RECIPROCATING STROKE, and the duplicate analysis shows it
			// plainly: frames 6/19, 7/18, 8/17 and 9/16 are IDENTICAL pairs
			// and 10-15 are one held pose. The animation drives out to the
			// top of the stroke, holds, and returns along the same poses.
			// 0-5 are all the same idle.
			//
			// So fire is the whole stroke. It reaches 19 degrees above the
			// rest pose at the top, which is the tool working rather than
			// the gun swinging, and fire carries no pitch tolerance for
			// exactly that reason.
			"MS_Jackhammer|fire|6@1,7@1,8@1,9@1,10@1,11@1,12@1,13@1,14@1,15@1,16@1,17@1,18@1,19@1|0|-1|-1",
			"MS_Jackhammer|altfire|6@1,7@1,8@1,9@1,10@1,16@1,17@1,18@1,19@1|0|-1|-1",
			"MS_Jackhammer|ready|0@1|-1|-1|-1",
			"MS_Jackhammer|select|0@1|-1|-1|-1",
			"MS_RC_M32|ready|0@1|-1|-1|-1",
			"MS_RC_M32|fire|1@3,2@3,3@3,4@3,5@3,6@3|0|-1|-1",
			"MS_RC_M32|reload|7-36@2|-1|0|24",
			"MS_Beretta|fire|1@1,2@1,3@1,4@1,5@1,6@1,7@1|0|-1|-1",
			"MS_Beretta|ready|0@1|-1|-1|-1",
			"MS_Beretta|reload|22@1|-1|-1|-1",
			"MS_Beretta|select|0@1|-1|-1|-1",
			"MS_BD_AssaultShotgun|ads|4@1,5@1,6@1,7@1,8@1,9@1,10@1|-1|-1|-1",
			"MS_BD_AssaultShotgun|fire|4@1,5@1,6@1,7@1,8@1,9@1,10@1|0|-1|-1",
			"MS_BD_AssaultShotgun|ready|4@1|-1|-1|-1",
			"MS_BD_AssaultShotgun|reload|11@1,12@1,13@1,14@1,15@1,16@1,17@1,18@1,19@1,20@1,21@1,22@1,23@1,24@1,25@1,26@1,27@1,28@1,29@1,30@1,31@1|-1|-1|-1",
			"MS_BD_AssaultShotgun|select|3@1,4@1|-1|-1|-1",
			"MS_BD_AssaultShotgun|sprint|3@1|-1|-1|-1",
			"MS_BD_Rifle|ads|27@1,28@1,29@1|-1|-1|-1",
			"MS_BD_Rifle|fire|3@1,4@1,5@1,6@1|0|-1|-1",
			"MS_BD_Rifle|ready|3@1|-1|-1|-1",
			"MS_BD_Rifle|reload|7@1,8@1,9@1,10@1,11@1,12@1,13@1,14@1,15@1,16@1,17@1,18@1,19@1,20@1,21@1,22@1,23@1,24@1,25@1,26@1|-1|-1|-1",
			"MS_BD_Rifle|select|3@1|-1|-1|-1",
			"MS_BD_Rifle|sprint|21@1,22@1,23@1,24@1,25@1,30@1,31@1|-1|-1|-1",
			"MS_BD_Boot|fire|5@1,6@1,7@1,8@1,9@1,10@1,11@1,12@1,13@1,14@1,15@1,16@1,17@1,18@1,19@1,20@1,21@1,22@1,23@1,24@1,25@1,26@1,27@1,28@1,29@1,30@1,31@1,32@1,33@1,34@1,35@1,36@1,37@1,38@1,39@1,40@1,53@1,54@1,55@1,56@1,57@1|0|-1|-1",
			// VanAlek's VR fist, the melee family's only model. Fire is that
			// weapon's real punch, read from its source (RS_Fist.zs Fire: PUNG
			// B 4 / C 4 / D 5 / C 4 / B 5) through the fist MODELDEF's letter map,
			// B/C/D = frames 1/2/3 -- not measured, so the pre-2026-09-04 frame
			// reader bug never touched it. Ready, select and sprint hold the rest
			// pose. Restored from c689d32 after the shelf trim left fists bare.
			"MS_Fist|fire|1@4,2@4,3@5,2@4,1@5,0@1|0|-1|-1",
			"MS_Fist|ready|0@1|-1|-1|-1",
			"MS_Fist|select|0@1|-1|-1|-1",
			"MS_Fist|sprint|0@1|-1|-1|-1",
			"MS_BD_BrutalAxe|fire|5@1,6@1,7@1,8@1,9@1,10@1,11@1,12@1,13@1,14@1|0|-1|-1",
			"MS_BD_BrutalAxe|ready|5@1|-1|-1|-1",
			"MS_BD_BrutalAxe|select|5@1|-1|-1|-1",
			"MS_BD_BrutalAxe|sprint|5@1|-1|-1|-1",
			// Dragonslayer, read off Brutal Doom's own DSweap states and its
			// model's FrameIndex table (DSLA A-E = 0-4, DSLC A-D = 5-8). Ready
			// and Select both hold DSLA A, so frame 0 is the rest and the draw
			// snaps. Fire: DSLC A-D wind-up, DSLA B strike, DSLA C held through
			// the follow-through and the hidden recovery, DSLC D-A back out.
			// Frames 3 and 9 are never shown by BD.
			"MS_BD_DSweap|fire|5-8@1,1@1,2@26,8@3,7@1,6@1,5@1|5|-1|-1",
			"MS_BD_DSweap|ready|0@1|-1|-1|-1",
			"MS_BD_DSweap|select|0@1|-1|-1|-1",
			"MS_BD_DSweap|sprint|0@1|-1|-1|-1",
			"MS_BD_BrutalSMG|ads|2@1,3@1,4@1,5@1,6@1|-1|-1|-1",
			"MS_BD_BrutalSMG|fire|3@1,4@1,5@1,6@1|0|-1|-1",
			"MS_BD_BrutalSMG|ready|3@1|-1|-1|-1",
			"MS_BD_BrutalSMG|reload|7@1,8@1,9@1,10@1,11@1,12@1,13@1,14@1,15@1,16@1,17@1,18@1,19@1,20@1,21@1,22@1,23@1,24@1,25@1,26@1|-1|-1|-1",
			"MS_BD_BrutalSMG|select|3@1|-1|-1|-1",
			"MS_BD_BrutalSMG|sprint|2@1|-1|-1|-1",
			"MS_BD_Flamethrower2|fire|0@1,1@1,2@1,3@1,4@1|0|-1|-1",
			"MS_BD_M79|fire|3@1,4@1,5@1,6@1|0|-1|-1",
			"MS_BD_M79|ready|3@1|-1|-1|-1",
			"MS_BD_M79|reload|7@1,8@1,9@1,10@1,11@1,12@1,13@1,14@1,15@1,16@1,17@1,18@1,19@1,20@1,21@1,22@1,23@1,24@1,25@1,26@1,27@1,28@1,29@1,30@1,31@1,32@1|-1|-1|-1",
			"MS_BD_M79|select|3@1|-1|-1|-1",
			"MS_BD_M79|sprint|2@1|-1|-1|-1",
			"MS_BD_Machinegun|fire|4@1,5@1,7@1,8@1,9@1,10@1|0|-1|-1",
			"MS_BD_Machinegun|altfire|11-17@1|0|-1|-1",
			"MS_BD_Machinegun|ready|10@1|-1|-1|-1",
			"MS_BD_Machinegun|reload|18@1,19@1,20@1,21@1,22@1,23@1,24@1,25@1,26@1,27@1,28@1,29@1,30@1,31@1,32@1,33@1,34@1,35@1|-1|-1|-1",
			// SELECT SKIPS FRAMES 0-3. Measured off the mesh, they sit at
			// -28.7, -38.3, -33.5 and -20.8 degrees: Brutal Doom draws the
			// raise by swinging the gun up from below the view, which is
			// right for a flat sprite and wrong for a model in a tracked
			// hand -- your hand is not moving, so the gun just points at
			// the floor for four tics every time you draw it. 4 and 5 are
			// -8.1 and -3.3, so the raise survives as a short settle into
			// the rest pose instead of a swing.
			"MS_BD_Machinegun|select|4@1,5@1|-1|-1|-1",
			"MS_BD_Machinegun|sprint|5@1|-1|-1|-1",
			"MS_BD_nade|fire|3@1,4@1,5@1,6@1,7@1,8@1,9@1,10@1,11@1,12@1,13@1,14@1,15@1|0|-1|-1",
			"MS_BD_nade|reload|16@1,17@1,18@1,19@1,20@1,21@1,22@1,23@1,24@1,25@1,26@1|-1|-1|-1",
			"MS_BD_RailGun|ads|3@1,36@1|-1|-1|-1",
			"MS_BD_RailGun|fire|3@1,4@1,5@1,6@1,7@1,8@1,9@1,10@1|0|-1|-1",
			"MS_BD_RailGun|ready|3@1|-1|-1|-1",
			"MS_BD_RailGun|reload|11@1,12@1,13@1,14@1,15@1,16@1,17@1,18@1,19@1,20@1,21@1,22@1,23@1,24@1,25@1,26@1,27@1,28@1,29@1,30@1,31@1,32@1,33@1,34@1|-1|-1|-1",
			"MS_BD_RailGun|select|3@1|-1|-1|-1",
			"MS_BD_RailGun|sprint|2@1|-1|-1|-1",
			"MS_BD_Unmaker|ready|4@1|-1|-1|-1",
			"MS_BD_Unmaker|reload|5@1,6@1,7@1,8@1,9@1,10@1,11@1,12@1,13@1,14@1,15@1|-1|-1|-1",
			// THE SOURCE ONLY EVER USED TWO FRAMES OF SIXTEEN.
			//
			// VanAlek's own modeldef declares CHGG A -> 4 and CHGG B -> 10
			// and stops, because vanilla Doom's chaingun psprite alternates
			// exactly two frames and nothing more was needed. We copied
			// that faithfully, so on a mod with a real chaingun animation
			// the model sat on one pose.
			//
			// Measured off the mesh, it holds far more than that:
			//
			//   0       exploded -- 1382 units on a 103-unit gun, unusable
			//   1-4     the raise, -31 to -6 degrees
			//   5-15    level at -1.5, length cycling 102.8 -> 103.0:
			//           eleven frames of the barrels turning
			//
			// So fire is the whole spin rather than two poses of it, and
			// select is the tail of the raise. Frames 1 and 2 are left out:
			// they sit 22 and 26 degrees off the rest pose, and a gun that
			// swings that far in a tracked hand is the artefact the pitch
			// pass exists to remove.
			//
			// No reload clip. The mesh has no reload frames and inventing
			// one from the spin would be a lie -- a weapon with nothing to
			// show holds its rest pose, which is honest.
			"MS_Chaingun|fire|4@1,5@1,6@1,7@1,8@1,9@1,10@1,11@1,12@1,13@1,14@1,15@1|0|-1|-1",
			"MS_Chaingun|altfire|4@1,5@1,6@1,7@1,8@1,9@1,10@1,11@1,12@1,13@1,14@1,15@1|0|-1|-1",
			"MS_Chaingun|ready|4@1|-1|-1|-1",
			"MS_Chaingun|select|3@1,4@1|-1|-1|-1",
			"MS_Chaingun|sprint|4@1|-1|-1|-1",
			"MS_Chainsaw|deselect|11@1|-1|-1|-1",
			"MS_Chainsaw|fire|6@1,7@1,8@1,9@1,10@1,11@1,12@1,7@1|0|-1|-1",
			"MS_Chainsaw|ready|13@4,14@4|-1|-1|-1",
			"MS_Chainsaw|select|1@1,2@1,3@1,4@1,5@1|-1|-1|-1",
			"MS_MG_Bolter|ready|0@1|-1|-1|-1",
			"MS_MG_Tec9|ready|0@1|-1|-1|-1",
			"MS_MG_Bolter|fire|3@1,1@1,1@1,2@1|0|-1|-1",
			"MS_MG_Tec9|fire|4@1,1@1,2@1,0@1|0|-1|-1",
			"MS_Pistol|fire|1@2,2@2,0@1|0|-1|-1",
			"MS_MG_Bolter|ready|0@1|-1|-1|-1",
			"MS_MG_Tec9|ready|0@1|-1|-1|-1",
			"MS_MG_Bolter|fire|3@1,1@1,1@1,2@1|0|-1|-1",
			"MS_MG_Tec9|fire|4@1,1@1,2@1,0@1|0|-1|-1",
			"MS_Pistol|ready|0@1|-1|-1|-1",
			// FRAMES 26-31 ARE THE DRAW. The source labels them "//draw, cowboy"
			// (Modeldef.Weapons1, PISD A-F) and no state of ours ever reached
			// them. Frame 25 is PISG Z, referenced by nothing, left alone.
			"MS_Pistol|select|26-31@1|-1|-1|-1",
			"MS_MG_Bolter|ready|0@1|-1|-1|-1",
			"MS_MG_Tec9|ready|0@1|-1|-1|-1",
			"MS_MG_Bolter|fire|3@1,1@1,1@1,2@1|0|-1|-1",
			"MS_MG_Tec9|fire|4@1,1@1,2@1,0@1|0|-1|-1",
			"MS_Pistol|reload|5-17@1,18-22@1,23-24@1|0|-1|-1",
			"MS_Pistol2|fire|1@2,2@2,0@1|0|-1|-1",
			"MS_Pistol2|ready|0@1|-1|-1|-1",
			// FRAMES 26-31 ARE THE DRAW. The source labels them "//draw, cowboy"
			// (Modeldef.Weapons1, PISD A-F) and no state of ours ever reached
			// them. Frame 25 is PISG Z, referenced by nothing, left alone.
			"MS_Pistol2|select|26-31@1|-1|-1|-1",
			"MS_Pistol2|reload|5-17@1,18-22@1,23-24@1|0|-1|-1",
			"MS_PlasmaRifle|fire|4@1,5@1,6@1,7@1,8@1,9@1,10@1,11@1,12@1,13@1,14@1,15@1,16@1,17@1|0|-1|-1",
			"MS_PlasmaRifle|ready|4@1|-1|-1|-1",
			"MS_PlasmaRifle|reload|18@1,19@1,20@1,21@1,22@1,23@1,24@1,25@1,26@1,27@1,28@1,29@1|-1|-1|-1",
			"MS_PlasmaRifle|select|4@1|-1|-1|-1",
			"MS_PlasmaRifle|sprint|3@1|-1|-1|-1",
			"MS_Revolver|fire|1-3@1,4-5@2,6-15@1|0|-1|-1",
			"MS_Revolver|ready|0@1|-1|-1|-1",
			// RELOAD IS 16-39, MEASURED. The cylinder (python.014, 257 verts) swings
			// out at 20, holds open through 29, and closes across 30-39 while
			// the pitch dips then snaps +22 at 31 -- a wrist flick shutting it.
			// The source's "//draw, cowboy" comment at 26 marks where its REVO
			// sprite set begins, not where the animation changes; a first pass
			// here read it as a select clip and cut the reload off with the
			// cylinder still open. There is no separate draw animation.
			"MS_Revolver|reload|16-25@2,26-39@1,0@1|0|-1|-1",
			"MS_Revolver2|fire|1-3@1,4-5@2,6-15@1|0|-1|-1",
			"MS_Revolver2|ready|0@1|-1|-1|-1",
			// RELOAD IS 16-39, MEASURED. The cylinder (python.014, 257 verts) swings
			// out at 20, holds open through 29, and closes across 30-39 while
			// the pitch dips then snaps +22 at 31 -- a wrist flick shutting it.
			// The source's "//draw, cowboy" comment at 26 marks where its REVO
			// sprite set begins, not where the animation changes; a first pass
			// here read it as a select clip and cut the reload off with the
			// cylinder still open. There is no separate draw animation.
			"MS_Revolver2|reload|16-25@2,26-39@1,0@1|0|-1|-1",
			"MS_Rifle|fire|1-10@1|0|-1|-1",
			"MS_Rifle|ready|0@1|-1|-1|-1",
			"MS_Rifle|reload|11-13@2,14-25@1,26-34@2,35-37@1,38-40@2,0@1|-1|-1|-1",
			"MS_RocketLauncher|fire|10@6,10@4,5@1|0|-1|-1",
			"MS_RocketLauncher|ready|5@1|-1|-1|-1",
			"MS_RocketLauncher|reload|11-38@1|-1|0|14",
			"MS_Shotgun|fire|1-4@1,5@1,6@1,7@1,8-12@1,13@1,14-19@1,0@1|0|-1|-1",
			"MS_Shotgun|ready|0@1|-1|-1|-1",
			// FRAMES 20-31 ARE THE SHELL GOING IN. Never referenced by the
			// source (VanAlek maps SHTG A-Z to 0-25 and no state uses U-Z),
			// found by measuring which surface moves: the shell surface
			// travels 60 units across them while the receiver moves 0.35.
			// Reload is now insert-then-pump instead of pump alone.
			"MS_Shotgun|reload|20-31@1,5@2,6@2,19@1,18@1,17@1,16@1,15@1,14@1,13@1,12@1,11@1,10@1,9@1,8@1,7@1,6@1,5@1|0|-1|-1",
			"MS_SuperShotgun|fire|0@2,1-7@2|0|-1|-1",
			"MS_SuperShotgun|ready|0@1|-1|-1|-1",
			"MS_SuperShotgun|reload|8@2,9-17@3,18@2,19-21@3,23@2,24@2,24@1|0|-1|-1",
			// MEASURED, because no source modeldef documents this mesh --
			// RS_Main's only declares BFGG A->6, B->7, C->14. Distinct-frame
			// analysis gives the real shape:
			//
			//   0-5      six distinct poses: the raise
			//   6-11     one pose repeated six times: the idle
			//   12-15    four distinct poses: the shot
			//
			// So the fire clip is 12-15, not the single frame 14 the source
			// named, and select is the tail of the raise. Frames 0-3 are
			// left out: 3 sits 22 degrees off the rest pose.
			"MS_VR_BFG9000|fire|12@1,13@1,14@1,15@1|0|-1|-1",
			"MS_VR_BFG9000|ready|6@1|-1|-1|-1",
			"MS_VR_BFG9000|select|4@1,5@1,6@1|-1|-1|-1"
		};
		mRows.Clear();
		for (int i = 0; i < CLIP.Size(); ++i) mRows.Push(CLIP[i]);
		Array<string> addon;
		RS_ForeignAddon.Rows("clip", addon);
		for (int i = 0; i < addon.Size(); ++i) mRows.Push(addon[i]);
	}

	// Expand a step list into one frame per tic. Clamped to the donor's
	// real frame count -- an out-of-range ModelFrame draws NOTHING, so a
	// bad row would make the weapon vanish rather than look wrong.
	static void Expand(string steps, int frameCount, out Array<int> frames)
	{
		frames.Clear();
		Array<string> parts;
		steps.Split(parts, ",");

		for (int p = 0; p < parts.Size(); ++p)
		{
			string s = parts[p];
			int at = s.IndexOf("@");
			if (at < 0) continue;

			string range = s.Left(at);
			int tics = s.Mid(at + 1).ToInt();
			if (tics < 1) tics = 1;

			int dash = range.IndexOf("-", 1);   // from 1: allow a leading sign
			int a, b;
			if (dash > 0)
			{
				a = range.Left(dash).ToInt();
				b = range.Mid(dash + 1).ToInt();
			}
			else { a = range.ToInt(); b = a; }

			int step = (b >= a) ? 1 : -1;
			for (int f = a; ; f += step)
			{
				int cf = f;
				if (frameCount > 0 && cf >= frameCount) cf = frameCount - 1;
				if (cf < 0) cf = 0;
				for (int t = 0; t < tics; ++t) frames.Push(cf);
				if (f == b) break;
			}
		}
	}

	// donorClass + seq -> expanded frame list and its fire mark.
	bool Get(string donor, string seq, int frameCount, out Array<int> frames, out int markFire) const
	{
		frames.Clear(); markFire = -1;
		string key = donor .. "|" .. seq .. "|";
		for (int i = 0; i < mRows.Size(); ++i)
		{
			if (mRows[i].IndexOf(key) != 0) continue;
			Array<string> f;
			mRows[i].Split(f, "|");
			if (f.Size() < 4) return false;
			Expand(f[2], frameCount, frames);
			markFire = f[3].ToInt();
			return (frames.Size() > 0);
		}
		return false;
	}

	bool Has(string donor, string seq) const
	{
		string key = donor .. "|" .. seq .. "|";
		for (int i = 0; i < mRows.Size(); ++i)
			if (mRows[i].IndexOf(key) == 0) return true;
		return false;
	}
}

// ---------------------------------------------------------------------
// Display state for ONE hand. This used to be fifteen fields of watched
// behavior -- entry states, elapsed tics, ammo baselines, idle glue,
// live sequence proofs. The remap engine (RS_ForeignRemap) reads the
// weapon's own state machine every tic instead, so all that survives is
// who we're painting and where the mesh parked.
// ---------------------------------------------------------------------
class RS_ForeignHand
{
	Actor lastCaller;
	int   lastMesh;    // last mapped mesh frame; held on unmapped states

	// Heal context: the table and row of the last HIT, so a miss knows
	// which group's clip was interrupted and where it left off. The map
	// reference guards against a stale row after a donor change rebuilds
	// the table.
	RS_ForeignRemap lastMap;
	int lastHitRow;

	// Health telemetry: tics this hand spent on states the table resolved
	// vs. missed, printed and reset periodically by the handler so every
	// session's log answers "did it animate, and where are the holes"
	// without anyone being asked anything. The last missed state's
	// sprite/frame is kept so a hole names itself; healed counts states
	// the table repaired into itself this interval.
	int hits, misses, healed;
	int missSprite, missFrame, missTics;

	void Reset()
	{
		lastCaller = null;
		lastMesh   = -1;
		lastMap    = null;
		lastHitRow = -1;
		hits = 0; misses = 0; healed = 0;
		missSprite = -1; missFrame = -1; missTics = -1;
	}
}
