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
class RS_ForeignClip
{
	Array<string> mRows;

	void Build()
	{
		static const string CLIP[] = {

			// BD21 set -- derived from BD's own section comments.
			"MS_BD_AssaultShotgun|ads|4@1,5@1,6@1,7@1,8@1,9@1,10@1|-1|-1|-1",
			"MS_BD_AssaultShotgun|fire|4@1,5@1,6@1,7@1,8@1,9@1,10@1|0|-1|-1",
			"MS_BD_AssaultShotgun|ready|0@1,1@1,2@1,3@1|-1|-1|-1",
			"MS_BD_AssaultShotgun|reload|11@1,12@1,13@1,14@1,15@1,16@1,17@1,18@1,19@1,20@1,21@1,22@1,23@1,24@1,25@1,26@1,27@1,28@1,29@1,30@1,31@1|-1|-1|-1",
			"MS_BD_AssaultShotgun|sprint|3@1|-1|-1|-1",
			"MS_BD_nade|fire|3@1,4@1,5@1,6@1,7@1,8@1,9@1,10@1,11@1,12@1,13@1,14@1,15@1|0|-1|-1",
			"MS_BD_nade|reload|16@1,17@1,18@1,19@1,20@1,21@1,22@1,23@1,24@1,25@1,26@1|-1|-1|-1",
			"MS_BD_Boot|fire|5@1,6@1,7@1,8@1,9@1,10@1,11@1,12@1,13@1,14@1,15@1,16@1,17@1,18@1,19@1,20@1,21@1,22@1,23@1,24@1,25@1,26@1,27@1,28@1,29@1,30@1,31@1,32@1,33@1,34@1,35@1,36@1,37@1,38@1,39@1,40@1,53@1,54@1,55@1,56@1,57@1|0|-1|-1",
			"MS_BD_fistclosed|taunt|61@1,62@1,63@1,64@1,66@1,67@1,68@1,69@1,71@1,72@1,73@1,74@1|-1|-1|-1",
			"MS_BD_BFG|fire|6@1|0|-1|-1",
			"MS_BD_BFG|ready|0@1,1@1,2@1,3@1,4@1,5@1|-1|-1|-1",
			"MS_BD_BFG|reload|7@1,8@1,9@1,10@1,11@1,12@1,13@1,14@1,15@1|-1|-1|-1",
			"MS_BD_BFG|sprint|5@1|-1|-1|-1",
			"MS_BD_BFG_10k|fire|6@1,10@1|0|-1|-1",
			"MS_BD_BFG_10k|ready|6@1,7@1,8@1,9@1|-1|-1|-1",
			"MS_BD_BFG_10k|reload|11@1,12@1,13@1,14@1,15@1,16@1,17@1,18@1,19@1,20@1|-1|-1|-1",
			"MS_BD_BrutalAxe|fire|5@1,6@1,7@1,8@1,9@1,10@1,11@1,12@1,13@1,14@1|0|-1|-1",
			"MS_BD_BrutalAxe|ready|0@1,1@1,2@1,3@1|-1|-1|-1",
			"MS_BD_BrutalAxe|sprint|3@1|-1|-1|-1",
			"MS_BD_Chain_saw|fire|13@1,14@1,15@1,16@1,27@1,28@1,29@1,30@1,31@1,32@1,33@1,34@1,35@1,36@1,37@1,38@1,39@1,40@1,41@1,42@1,43@1,44@1,45@1,46@1,47@1,48@1,49@1,50@1,51@1,52@1,53@1,54@1,55@1,56@1,57@1,58@1,59@1,60@1|0|-1|-1",
			"MS_BD_Chain_saw|ready|0@1,1@1,2@1,3@1,4@1,5@1,6@1,7@1,8@1,9@1,10@1,11@1,12@1|-1|-1|-1",
			"MS_BD_Chain_saw|reload|61@1,62@1,63@1,64@1|-1|-1|-1",
			"MS_BD_DSweap|ready|5@1,6@1,7@1,8@1|-1|-1|-1",
			"MS_BD_FlameCannon|fire|1@1,2@1,3@1,4@1,5@1,6@1,7@1|0|-1|-1",
			"MS_BD_FlameCannon|ready|0@1|-1|-1|-1",
			"MS_BD_Flamethrower2|fire|0@1,1@1,2@1,3@1,4@1|0|-1|-1",
			"MS_BD_HellishMissile|fire|1@1,2@1,3@1,4@1,5@1,6@1,7@1,8@1,9@1|0|-1|-1",
			"MS_BD_HellishMissile|ready|0@1|-1|-1|-1",
			"MS_BD_HitlersBuzzsaw|fire|0@1,1@1,2@1|0|-1|-1",
			"MS_BD_M79|fire|3@1,4@1,5@1,6@1|0|-1|-1",
			"MS_BD_M79|ready|0@1,1@1,2@1|-1|-1|-1",
			"MS_BD_M79|reload|7@1,8@1,9@1,10@1,11@1,12@1,13@1,14@1,15@1,16@1,17@1,18@1,19@1,20@1,21@1,22@1,23@1,24@1,25@1,26@1,27@1,28@1,29@1,30@1,31@1,32@1|-1|-1|-1",
			"MS_BD_M79|sprint|2@1|-1|-1|-1",
			"MS_BD_Machinegun|fire|4@1,5@1,6@1,7@1,8@1,9@1,10@1,11@1,12@1,13@1,14@1,15@1,16@1,17@1|0|-1|-1",
			"MS_BD_Machinegun|ready|0@1,1@1,2@1,3@1|-1|-1|-1",
			"MS_BD_Machinegun|reload|18@1,19@1,20@1,21@1,22@1,23@1,24@1,25@1,26@1,27@1,28@1,29@1,30@1,31@1,32@1,33@1,34@1,35@1|-1|-1|-1",
			"MS_BD_Machinegun|sprint|3@1|-1|-1|-1",
			"MS_BD_Minigun|fire|4@1,5@1,6@1,7@1,8@1,9@1,10@1,11@1,12@1,13@1,14@1,15@1|0|-1|-1",
			"MS_BD_Minigun|ready|0@1,1@1,2@1,3@1|-1|-1|-1",
			"MS_BD_Minigun|sprint|3@1|-1|-1|-1",
			"MS_BD_MP40|ads|2@1,3@1,4@1,5@1,6@1|-1|-1|-1",
			"MS_BD_MP40|fire|2@1,3@1,4@1,5@1,6@1|0|-1|-1",
			"MS_BD_MP40|ready|0@1,1@1|-1|-1|-1",
			"MS_BD_MP40|reload|7@1,8@1,9@1,10@1,11@1,12@1,13@1|-1|-1|-1",
			"MS_BD_MP40|sprint|1@1|-1|-1|-1",
			"MS_BD_Dual_MP40|fire|2@1,3@1,4@1,5@1,6@1,7@1|0|-1|-1",
			"MS_BD_Dual_MP40|reload|7@1,8@1,9@1,10@1,11@1,12@1,13@1,14@1,15@1,16@1,17@1,18@1,19@1|-1|-1|-1",
			"MS_BD_BrutalPistol|fire|2@1,3@1,4@1,5@1,6@1,7@1|0|-1|-1",
			"MS_BD_BrutalPistol|ready|0@1,1@1|-1|-1|-1",
			"MS_BD_BrutalPistol|reload|8@1,9@1,10@1,11@1,12@1,13@1,14@1,15@1,16@1,17@1,18@1,19@1,20@1,21@1,22@1,23@1,24@1,25@1|-1|-1|-1",
			"MS_BD_BrutalPistol|sprint|27@1,28@1,29@1,30@1,31@1,32@1,33@1,34@1,35@1,36@1,37@1|-1|-1|-1",
			"MS_BD_Plasma|fire|4@1,5@1,6@1,7@1,8@1,9@1,10@1,11@1,12@1,13@1,14@1,15@1,16@1,17@1|0|-1|-1",
			"MS_BD_Plasma|ready|0@1,1@1,2@1,3@1|-1|-1|-1",
			"MS_BD_Plasma|reload|18@1,19@1,20@1,21@1,22@1,23@1,24@1,25@1,26@1,27@1,28@1,29@1|-1|-1|-1",
			"MS_BD_Plasma|sprint|3@1|-1|-1|-1",
			"MS_BD_RailGun|ads|3@1,36@1|-1|-1|-1",
			"MS_BD_RailGun|fire|3@1,4@1,5@1,6@1,7@1,8@1,9@1,10@1|0|-1|-1",
			"MS_BD_RailGun|ready|0@1,1@1,2@1|-1|-1|-1",
			"MS_BD_RailGun|reload|11@1,12@1,13@1,14@1,15@1,16@1,17@1,18@1,19@1,20@1,21@1,22@1,23@1,24@1,25@1,26@1,27@1,28@1,29@1,30@1,31@1,32@1,33@1,34@1|-1|-1|-1",
			"MS_BD_RailGun|sprint|2@1|-1|-1|-1",
			"MS_BD_Revolver|fire|0@1,1@1,2@1,3@1,4@1,5@1,6@1,7@1,8@1,9@1,10@1,11@1,12@1,13@1,14@1,15@1,16@1,17@1|0|-1|-1",
			"MS_BD_Revolver|reload|18@1,19@1,20@1,21@1,22@1,23@1,24@1,25@1,26@1,27@1,28@1,29@1,30@1|-1|-1|-1",
			"MS_BD_Revolver|sprint|32@1|-1|-1|-1",
			"MS_BD_Rifle|ads|27@1,28@1,29@1|-1|-1|-1",
			"MS_BD_Rifle|fire|3@1,4@1,5@1,6@1|0|-1|-1",
			"MS_BD_Rifle|ready|0@1,1@1,2@1,3@1,4@1,5@1,6@1|-1|-1|-1",
			"MS_BD_Rifle|reload|7@1,8@1,9@1,10@1,11@1,12@1,13@1,14@1,15@1,16@1,17@1,18@1,19@1,20@1,21@1,22@1,23@1,24@1,25@1,26@1|-1|-1|-1",
			"MS_BD_Rifle|sprint|21@1,22@1,23@1,24@1,25@1,30@1,31@1|-1|-1|-1",
			"MS_BD_Rifle_Dual|reload|5@1,6@1,7@1,8@1,9@1,10@1,11@1,12@1,13@1,14@1,15@1,16@1,17@1,18@1,19@1,20@1,21@1,22@1,23@1,24@1,25@1,26@1,27@1,28@1,29@1,30@1,31@1,32@1,33@1,34@1,35@1,36@1,37@1,38@1,39@1|-1|-1|-1",
			"MS_BD_RPG|ads|35@1,36@1,37@1,38@1|-1|-1|-1",
			"MS_BD_RPG|fire|9@1,10@1,11@1,12@1,13@1,14@1,15@1,16@1|0|-1|-1",
			"MS_BD_RPG|ready|0@1,1@1,2@1,3@1,4@1,5@1,6@1,7@1,8@1|-1|-1|-1",
			"MS_BD_RPG|reload|17@1,18@1,19@1,20@1,21@1,22@1,23@1,24@1,25@1,26@1,27@1,28@1,29@1,30@1,31@1,32@1,33@1,34@1|-1|-1|-1",
			"MS_BD_RPG|sprint|3@1|-1|-1|-1",
			"MS_BD_SnipaRPG|fire|0@1,4@1|0|-1|-1",
			"MS_BD_SnipaRPG|reload|5@1,6@1,7@1,8@1,9@1,10@1,11@1,12@1,13@1,14@1,15@1,16@1,17@1,18@1,19@1,20@1,21@1,22@1,23@1,24@1,25@1,26@1,27@1,28@1,29@1,30@1,31@1,32@1,33@1,34@1,35@1,36@1,37@1,38@1,39@1,40@1|-1|-1|-1",
			"MS_BD_Shotgun|ads|4@1,5@1,6@1,8@1,32@1,33@1,34@1,35@1|-1|-1|-1",
			"MS_BD_Shotgun|fire|4@1,5@1,6@1,7@1,8@1,9@1,10@1,11@1,12@1,13@1,14@1,15@1,16@1,17@1,18@1,19@1,20@1,21@1,22@1|0|-1|-1",
			"MS_BD_Shotgun|ready|0@1,1@1,2@1,3@1|-1|-1|-1",
			"MS_BD_Shotgun|reload|23@1,24@1,25@1,26@1,27@1,28@1,29@1,30@1,31@1|-1|-1|-1",
			"MS_BD_Shotgun|sprint|3@1|-1|-1|-1",
			"MS_BD_BrutalSMG|ads|2@1,3@1,4@1,5@1,6@1|-1|-1|-1",
			"MS_BD_BrutalSMG|fire|3@1,4@1,5@1,6@1|0|-1|-1",
			"MS_BD_BrutalSMG|ready|0@1,1@1,2@1|-1|-1|-1",
			"MS_BD_BrutalSMG|reload|7@1,8@1,9@1,10@1,11@1,12@1,13@1,14@1,15@1,16@1,17@1,18@1,19@1,20@1,21@1,22@1,23@1,24@1,25@1,26@1|-1|-1|-1",
			"MS_BD_BrutalSMG|sprint|2@1|-1|-1|-1",
			"MS_BD_DualSMG|fire|3@1,4@1,5@1,6@1,7@1|0|-1|-1",
			"MS_BD_DualSMG|ready|0@1,1@1,2@1|-1|-1|-1",
			"MS_BD_DualSMG|reload|8@1,9@1,10@1,11@1,12@1,13@1,14@1,15@1,16@1,17@1,18@1,19@1,20@1,21@1,22@1,23@1,24@1,25@1,26@1|-1|-1|-1",
			"MS_BD_SSG|fire|1@1,2@1,3@1,4@1,5@1,6@1,7@1,8@1,9@1,10@1,11@1,12@1|0|-1|-1",
			"MS_BD_SSG|ready|47@1,48@1,49@1,50@1,51@1|-1|-1|-1",
			"MS_BD_SSG|reload|13@1,14@1,15@1,16@1,17@1,18@1,19@1,20@1,21@1,22@1,23@1,24@1,25@1,26@1,27@1,28@1,29@1,30@1,31@1,32@1,33@1,34@1,35@1,36@1,37@1,38@1,39@1,40@1,41@1,42@1,43@1,44@1,45@1,46@1|-1|-1|-1",
			"MS_BD_SSG|sprint|0@1|-1|-1|-1",
			"MS_BD_Unmaker|ready|4@1,5@1,6@1,7@1,8@1,9@1,10@1,11@1,12@1,13@1,14@1,15@1|-1|-1|-1",

			"MS_BW_Colt|ready|1@1|-1|-1|-1",
			"MS_BW_Flamethrower|ready|0@1|-1|-1|-1",
			"MS_BW_Garand|ready|1@1|-1|-1|-1",
			"MS_BW_Kar98|ready|1@1|-1|-1|-1",
			"MS_BW_Luger|ready|0@1|-1|-1|-1",
			"MS_BW_MG42|ready|12@1|-1|-1|-1",
			"MS_BW_MP40|ready|13@1|-1|-1|-1",
			"MS_BW_STG44|ready|13@1|-1|-1|-1",
			"MS_BW_Thompson|ready|1@1|-1|-1|-1",
			"MS_BW_Trenchgun|ready|1@1|-1|-1|-1",
			"MS_Chaingun|ready|4@1|-1|-1|-1",
			"MS_Chainsaw|ready|0@1|-1|-1|-1",
			"MS_Fist|ready|0@1|-1|-1|-1",
			"MS_MG_BFG|ready|0@1|-1|-1|-1",
			"MS_MG_Bolter|ready|0@1|-1|-1|-1",
			"MS_MG_Chaingun|ready|0@1|-1|-1|-1",
			"MS_MG_Knife|ready|0@1|-1|-1|-1",
			"MS_MG_RPG|ready|0@1|-1|-1|-1",
			"MS_MG_SSG|ready|0@1|-1|-1|-1",
			"MS_MG_Saw|ready|2@1|-1|-1|-1",
			"MS_MG_Shotgun|ready|0@1|-1|-1|-1",
			"MS_MG_Tec9|ready|0@1|-1|-1|-1",
			"MS_Pistol|ready|0@1|-1|-1|-1",
			"MS_PlasmaRifle|ready|4@1|-1|-1|-1",
			"MS_Revolver|ready|0@1|-1|-1|-1",
			"MS_Rifle|ready|0@1|-1|-1|-1",
			"MS_RocketLauncher|ready|5@1|-1|-1|-1",
			"MS_SMG|ready|3@1|-1|-1|-1",
			"MS_Shotgun|ready|0@1|-1|-1|-1",
			"MS_SuperShotgun|ready|0@1|-1|-1|-1",

			"MS_VR_BFG9000|ready|6@1|-1|-1|-1",
			"MS_VR_BFG9000|fire|7@3,8@3,9@3,6@1|0|-1|-1",
			"MS_Chaingun|fire|4@2,10@2|0|-1|-1",
			"MS_Chainsaw|fire|5@2,7@2|0|-1|-1",
			// Derived the same way as every other row: the donor's own
			// source weapon (RS_Fist.zs, Fire state) is PUNG B 4 / C 4
			// (fires) / D 5 / C 4 / B 5 (refire), and VR_Fist's own
			// MODELDEF maps those letters straight to frames 1/2/3 -- so
			// this is that weapon's real punch, not an invented one. It was
			// simply never written down; every OTHER fist/knife/saw donor
			// already has a fire clip.
			"MS_Fist|fire|1@4,2@4,3@5,2@4,1@5,0@1|0|-1|-1",
			"MS_MG_BFG|fire|1-4@1,1-4@1,1-4@1,5-10@1,0@5|0|-1|-1",

			"MS_MG_Bolter|fire|3@1,1@1,1@1,2@1|0|-1|-1",
			"MS_MG_Chaingun|fire|4@1,5@1,0-3@1,0-3@1,0-3@1,0-3@2,0-3@2,0-3@2|0|-1|-1",
			"MS_MG_Knife|fire|1@1,2@1,3@1,4@1,5@1,6@1,7@1,8@1,0@1|0|-1|-1",
			"MS_MG_RPG|altfire|4@1,5@1,6@1,0@5,0-3@1,0-3@1,0-3@1|0|-1|-1",
			"MS_MG_RPG|fire|4@1,5@1,0@3,1@1,2@1,3@1,0@3|0|-1|-1",
			"MS_MG_Saw|fire|4@1,5@1,6@1,7@1|0|-1|-1",
			"MS_MG_Shotgun|fire|1@1,2@2,3@2,0@2|0|-1|-1",
			"MS_MG_Tec9|fire|4@1,1@1,2@1,0@1|0|-1|-1",
			"MS_Pistol|fire|1@2,2@2,0@1|0|-1|-1",
			"MS_Pistol|reload|5-17@1,18-22@1,23-24@1|0|-1|-1",
			"MS_PlasmaRifle|fire|4@2,12@2|0|-1|-1",
			"MS_Revolver|fire|1-3@1,4-5@2,6-15@1|0|-1|-1",
			"MS_Revolver|reload|16-25@2,26@1,27-33@2,34-37@1,0@1|0|-1|-1",
			"MS_Rifle|fire|1-2@1,0@1|0|-1|-1",
			"MS_Rifle|reload|11-13@2,14-24@1,26-34@2,35-37@1,38-40@2|0|-1|-1",
			"MS_RocketLauncher|fire|10@6,10@4,5@1|0|-1|-1",
			"MS_SMG|fire|4@1,5@1,6@1|0|-1|-1",
			"MS_SMG|reload|7@2,8-26@1|0|-1|-1",
			"MS_Shotgun|fire|1-4@1,5@1,6@1,7@1,8-12@1,13@1,14-19@1,0@1|0|-1|-1",
			"MS_Shotgun|reload|5@2,6@2,19@1,18@1,17@1,16@1,15@1,14@1,13@1,12@1,11@1,10@1,9@1,8@1,7@1,6@1,5@1|0|-1|-1",
			// INFERRED RELOADS.
			//
			// Only 18 of the 43 source weapons have a Reload: state at all, so
			// derivation found no reload for these -- but their MESHES do. The
			// rocket launcher plays 10 of its 39 frames; the GH machinegun 8 of
			// 36. Those unused tails are reload animations the source weapon
			// simply never triggered, and a foreign weapon that DOES reload
			// should get to use them.
			//
			// Unlike everything else in this table these are read off the frame
			// budget rather than off a state machine, so they are the one place
			// a range could be wrong. If one looks off, the picker is the fix --
			// every family has three or more donors.
			"MS_RocketLauncher|reload|11-38@1|-1|0|14",
			"MS_PlasmaRifle|reload|13-29@1|-1|0|8",
			"MS_MG_SSG|reload|2-11@2|-1|0|5",

			"MS_SuperShotgun|fire|0@2,1-7@2|0|-1|-1",
			"MS_SuperShotgun|reload|8@2,9-17@3,18@2,19-21@3,23@2,24@2,24@1|0|-1|-1",

			"MS_BW_Colt|fire|2@1,3@1,4-6@1|0|-1|-1",
			"MS_BW_Colt|reload|36-43@1,44-51@2,52-55@2,56-59@1,16-23@1,24-31@2,32-35@2,23-16@1|-1|0|20",
			"MS_BW_Luger|fire|1@1,2@1,3-4@1,5@1|0|-1|-1",
			"MS_BW_Luger|reload|6-13@1,14-16@2,17-22@2,22-26@2,27-28@2,29-30@3,31-39@1,40-43@1,44-46@2,47-48@2,49@4,50-52@2,39-31@1|-1|0|24",
			"MS_BW_Kar98|fire|2@1,3-6@1,6@3,7-10@2,11@6,10-7@2|0|-1|-1",
			"MS_BW_Kar98|reload|7-8@2,9-11@2,28-29@2,30-33@2,7-8@2,9-11@2,12-27@2,11-7@2|-1|0|18",
			"MS_BW_Garand|fire|2@1,3-5@1,6-9@1|0|-1|-1",
			"MS_BW_Garand|reload|19-24@1,25-30@2,31-35@1|-1|0|12",
			"MS_BW_STG44|fire|14@1,15-17@1,18@1|0|-1|-1",
			"MS_BW_STG44|reload|19-24@1,25-27@1,28@2,29-37@2,42-44@1,45@3,46-50@1,24-19@1|-1|0|22",
			"MS_BW_MP40|fire|14@1,15-16@1,17-18@1|0|-1|-1",
			"MS_BW_MP40|reload|19-27@1,28-31@2,32-34@2,35-37@2,38@2,39@10,40-42@3,43-47@3,27-19@1|-1|0|26",
			"MS_BW_Thompson|fire|2@1,3@1,4@1|0|-1|-1",
			"MS_BW_Thompson|reload|6-13@1,14-17@2,18-27@2,28-30@2,31-32@3,33-35@1,35-37@1,32-28@1,13-6@1|-1|0|28",
			"MS_BW_MG42|fire|13@1,14@1,17@1|0|-1|-1",
			"MS_BW_MG42|reload|18-28@1,29@3,30-46@1,47-72@2,73-78@1,79@3,80@1,81@3,82-87@1,88@3,89-92@1,93@3,94-96@1|-1|0|60",
			"MS_BW_Trenchgun|fire|2@1,3-7@1,23@1,25@1,27@1,29@1,31@1,32@1,34@1,32@1,30@1,28@1,26@1,23@1|0|4|-1",
			"MS_BW_Trenchgun|reload|23-31@1,35-36@2,37-44@1,45@4,34-23@1|-1|0|14",
			"MS_BW_Flamethrower|fire|14@1|0|-1|-1"
		};
		mRows.Clear();
		for (int i = 0; i < CLIP.Size(); ++i) mRows.Push(CLIP[i]);
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
