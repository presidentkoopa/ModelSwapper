# Generate ModelSwapper assets from Brutal Doom v21's own weapon MODELDEFs.
#
# BD's defs are section-annotated (//Ready, //Aim and Fire, //Reload, //Zoom,
# //Sprint, //Rude), so which frames belong to which animation is DERIVED from
# the source rather than guessed. That is the whole reason this is a script and
# not a hand transcription.
#
# Emits four fragments:
#   bd21.modeldef   -- our MODELDEF blocks, re-anchored onto stock Doom sprites
#   bd21.stubs      -- the bodyless Actor stubs each block needs to exist
#   bd21.clips      -- clip rows, one per (model, animation section)
#   bd21.shelf      -- shelf rows, one per (family, model)

$src = "D:\SteamLibrary\steamapps\Common\DooM VR\__Games\BrutalDoom\_BD_1.01_WeaponModels"
# Both relative to this script, so the generator follows the repo instead of
# pointing at wherever it happened to live when it was written -- it spent a
# release aimed at a worktree that no longer exists, and silently emitted an
# empty table rather than failing.
$dst = Join-Path $PSScriptRoot 'models\bd21'
$out = Join-Path $PSScriptRoot '.gen'
if (-not (Test-Path $out)) { New-Item -ItemType Directory $out | Out-Null }
if (-not (Test-Path $dst)) { throw "model folder not found: $dst" }

# BD model name -> (our family, anchor sprite). Anchors are stock Doom sprite
# names so we ship no sprites of our own; the pin only has to resolve.
$MAP = @{
  'Fist'            = @('melee','PUNG');   'BrutalAxe'   = @('axe','PUNG')
  'Chain_saw'       = @('saw','SAWG')
  # Hitler's Buzzsaw is the MG42's wartime nickname -- a belt-fed machinegun,
  # not a saw. It was on the saw shelf here purely because of the word.
  'HitlersBuzzsaw'  = @('machinegun','CHGG')
  'BrutalPistol'    = @('pistol','PISG');  'Revolver'    = @('revolver','PISG')
  'BrutalSMG'       = @('smg','CHGG');     'MP40'        = @('smg','CHGG')
  'Shotgun'         = @('shotgun','SHTG'); 'AssaultShotgun' = @('shotgun','SHTG')
  'SSG'             = @('supershotgun','SHT2')
  'Rifle'           = @('rifle','CHGG');   'Snipa'       = @('sniper','CHGG')
  'Machinegun'      = @('machinegun','CHGG')
  'Minigun'         = @('chaingun','CHGG')
  'RPG'             = @('rocket','MISG');  'HellishMissile' = @('rocket','MISG')
  'M79'             = @('launcher','MISG');'Grenade'     = @('grenade','MISG')
  'Plasma_Gun'      = @('plasma','PLSG')
  'Flamethrower2'   = @('flamethrower','PLSG'); 'FlameCannon' = @('flamethrower','PLSG')
  'RailGun'         = @('railgun','PLSG')
  'BFG'             = @('bfg','BFGG')
  'Unmaker'         = @('unmaker','BFGG')
  'Boot'            = @('kick','PUNG')
  'DSweap'          = @('axe','PUNG')      # the Dragonslayer, BD's greatsword
}

# A handful of meshes are named differently from the folder they sit in and
# want their own family rather than the folder's.
$MESHFAM = @{
  'Boot'      = @('kick','PUNG')
  'nade'      = @('grenade','MISG')
  'DSweap'    = @('axe','PUNG')
  'fistclosed'= @('melee','PUNG')
  'BFG_10k'   = @('bfg','BFGG')
}

# Meshes that earn a place on a second shelf. The Dragonslayer sat on melee
# for a while, but melee is meant to hold one fist and one knife -- a
# greatsword is an axe-shelf weapon, and having it on both put a third
# silhouette in a family that wanted two.
$EXTRAFAM = @{
}

# Meshes we deliberately do not ship, and why.
#
# The Dual_ family is a CATEGORY exclusion, not a size cut. Brutal Doom ships
# dual-wield meshes in both v21 and v22 -- two guns modelled as one object,
# because a flat-screen mod has one psprite to draw them on. ModelSwapper runs
# in VR with hand tracking and per-hand assignment: you put a gun in each hand
# and move it between them. A mesh with both hands baked in fights the thing
# this mod exists to do, and it costs a family slot that the single-barrelled
# version already fills. Any future Dual_/_Dual mesh should be skipped too.
#
# The two saws below are size cuts, not principle -- 23MB between them for one
# family that MeatGrinder's saw and VanAlek's chainsaw still cover.
$DROP = @{
  'Dual_MP40'      = 'dual-wield mesh'
  'DualSMG'        = 'dual-wield mesh'
  'Rifle_Dual'     = 'dual-wield mesh'
  'HitlersBuzzsaw' = 'size: 4.9MB; it is an MG42, and machinegun already has two'
  'Chain_saw'      = 'size: 18.4MB, the largest single asset in the pk3'
  # One model per silhouette. These lost a straight comparison against the
  # model kept for their family -- see the shelf in RS_ForeignModels.zs.
  'fistclosed'     = 'one fist: VanAlek keeps the melee slot'
  'MP40'           = 'one MP40: Brutal Wolfenstein keeps it'
  'RPG'            = 'same mesh as VanAlek RocketLauncher, which keeps the slot'
  # BD-ONLY SILHOUETTES. A Revenant arm and a Mancubus cannon are weapons no
  # other mod ships, so these two meshes would ride in every download to serve
  # exactly one. Brutal Doom's own launcher takes a rocket launcher and its arm
  # cannon takes a flamethrower; those families already cover them.
  'HellishMissile' = 'BD-only silhouette; the rocket family covers it'
  'FlameCannon'    = 'BD-only silhouette; the flamethrower family covers it'
  'SnipaRPG'       = 'a 2-frame def on a 41-frame mesh; its reload was inferred'
}

# section comment -> our clip name. Anything unlisted is ignored.
function Sect([string]$c){
  $c = ($c -replace '//','').Trim().ToLower()
  if ($c -match '^ready')                    { return 'ready'   }
  # BD is not consistent about this header. Across the v21 defs it writes
  # "//Aim and Fire" 66 times, "//Aim and Firing" twice, "//Aim Fire" twice
  # and "//Fire" four times. Matching only the long form cost the
  # Dragonslayer its entire swing -- the sword had a ready pose and nothing
  # to play when you attacked. "aim.*fir" covers every spelling BD uses.
  if ($c -match 'aim.*fir|^fire|alt-?fire|^throw') { return 'fire' }
  if ($c -match '^reload')                   { return 'reload'  }
  if ($c -match '^zoom')                     { return 'ads'     }
  if ($c -match '^sprint')                   { return 'sprint'  }
  if ($c -match '^rude')                     { return 'taunt'   }
  if ($c -match 'nade')                      { return 'grenade' }
  return ''
}

# MD3 header: ident(4) version(4) name(64) flags(4) num_frames(4) -> offset 76.
# The mesh itself is the authority on how many frames exist. A def that indexes
# past the end is a BD authoring artifact and must not become a clip row.
function MeshFrames([string]$p){
  if (-not (Test-Path $p)) { return -1 }
  $fs=[System.IO.File]::OpenRead($p)
  try { $b=New-Object byte[] 80; $null=$fs.Read($b,0,80); return [BitConverter]::ToInt32($b,76) }
  finally { $fs.Close() }
}

# A .def is NOT one model. BD declares the same actor name several times in
# one file, each block bound to a DIFFERENT mesh -- the gun, plus Boot.md3 for
# the kick and nade.md3 for the grenade toss. The sprite name selects which
# mesh; the frame index selects within it. Parsing a file as a unit merges
# three meshes' frame numbering into nonsense, so split on block boundaries
# and treat each as its own model, named after its MESH rather than the folder.
#
# ORDER IS LOAD-BEARING. Modeldef.ClassicPistol.def binds the SAME
# BrutalPistol.md3 as Modeldef.Pistol.def, but stops after the fire frames --
# the Classic defs exist to drive Brutal Doom's vanilla-sprite mode and do not
# animate the reload at all. Sorting by filename put Classic* FIRST (C before
# P), so first-wins silently handed ten weapons their stunted twin and threw
# the real reload away. Native defs are collected first now; Classic ones only
# fill meshes nothing else defined.
$files = @(Get-ChildItem "$src\Modeldef.*.def" | Sort-Object Name)
$ordered = @($files | Where-Object { $_.Name -notmatch '(?i)^Modeldef\.Classic' }) +
           @($files | Where-Object { $_.Name -match  '(?i)^Modeldef\.Classic' })

$blocks = @()
foreach ($f in $ordered) {
  $lines = Get-Content $f.FullName
  $cur = $null
  foreach ($line in $lines) {
    if ($line -match '(?i)^\s*Model\s+\S+\s*$') {
      if ($cur) { $blocks += ,$cur }
      $cur = [pscustomobject]@{ Lines = New-Object System.Collections.Generic.List[string]; Src = $f.Name }
      continue
    }
    if ($cur) { $cur.Lines.Add($line) }
  }
  if ($cur) { $blocks += ,$cur }
}

$md = New-Object System.Text.StringBuilder
$st = New-Object System.Text.StringBuilder
$cl = New-Object System.Text.StringBuilder
$rows = @()
$seen = @{}
$notes = @()

foreach ($b in $blocks) {
  $txt = ($b.Lines -join "`n")
  if ($txt -notmatch '(?im)^\s*Path\s+"([^"]+)"') { continue }
  $path = $matches[1] -replace '\\','/'
  $leaf = ($path -split '/')[-1]
  if (-not $MAP.ContainsKey($leaf)) { continue }

  $mdl = if ($txt -match '(?im)^\s*Model\s+0\s+"([^"]+)"') { $matches[1] } else { continue }
  # Name the class after the MESH, so a block bound to Boot.md3 becomes the
  # boot and not a second copy of whatever gun's file it happened to live in.
  $meshName = [System.IO.Path]::GetFileNameWithoutExtension($mdl)
  $cls = "MS_BD_$meshName"
  if ($seen.ContainsKey($cls)) { continue }
  if ($DROP.ContainsKey($meshName)) {
    if (-not $seen.ContainsKey("drop:$meshName")) {
      $seen["drop:$meshName"] = $true
      $notes += "DROP $cls -- $($DROP[$meshName])"
    }
    continue
  }
  # Catch any dual mesh the list above has not been told about yet.
  if ($meshName -match '(?i)(^dual|_dual|dual_)') {
    $notes += "DROP $cls -- looks like a dual-wield mesh, add it to `$DROP if intended"
    continue
  }

  # The mesh decides the frame count, not the def.
  $frameCount = MeshFrames (Join-Path $dst "$leaf\$mdl")
  if ($frameCount -lt 0) { $notes += "SKIP $cls -- mesh not present: $leaf/$mdl"; continue }
  # A one-frame mesh is a prop (SnipaRG is a scope, not a rifle). It cannot
  # carry an animation, and shelving it hands the player a frozen object.
  if ($frameCount -lt 2) { $notes += "SKIP $cls -- $frameCount-frame mesh, a static prop"; continue }

  $seen[$cls] = $true

  $fam    = $MAP[$leaf][0]
  $anchor = $MAP[$leaf][1]
  if ($MESHFAM.ContainsKey($meshName)) { $fam = $MESHFAM[$meshName][0]; $anchor = $MESHFAM[$meshName][1] }

  $skn = if ($txt -match '(?im)^\s*Skin\s+0\s+"([^"]+)"')  { $matches[1] } else { '' }
  $scl = if ($txt -match '(?im)^\s*Scale\s+(\S+)\s+(\S+)\s+(\S+)') { "$($matches[1]) $($matches[2]) $($matches[3])" } else { '-1.0 1.0 1.0' }
  $zof = if ($txt -match '(?im)^\s*ZOffset\s+(\S+)') { $matches[1] } else { '0' }

  $cur2 = ''; $buckets = @{}; $over = 0; $sprite = @{}; $letter = @{}; $slot = @{}
  $refs = New-Object System.Collections.Generic.List[object]
  $loose = New-Object System.Collections.Generic.List[int]
  foreach ($line in $b.Lines) {
    $t = $line.Trim()
    if ($t -match '^//') {
      # A commented-out FrameIndex is dead data, not a section header.
      if ($t -notmatch '(?i)frameindex') { $s = Sect $t; if ($s) { $cur2 = $s } }
      continue
    }
    if ($t -match '(?i)^FrameIndex\s+(\S+)\s+(\S+)\s+\d+\s+(\d+)') {
      $spr = $matches[1]
      $let = $matches[2]
      $i = [int]$matches[3]
      # PASS 1: only build the sprite+letter -> LAST frame table here, and
      # remember which section each reference belonged to. Buckets are
      # filled in PASS 2, once $slot is complete for the whole block --
      # MODELDEF assigns one frame per (sprite,letter) key GLOBALLY, so a
      # section that reuses a letter an earlier section already used is not
      # two frames, it is one, decided by whichever FrameIndex line comes
      # LAST in the file. Bucketing on first sighting (the old code) kept
      # the PRE-remap frame for every such letter -- the pistol's Ready
      # section maps PIST A/B to 0/1, and Fire remaps the SAME letters to
      # 3/4, so the old code parked the idle on a pose BD's own game never
      # shows either, one letter later than the rifle bug this was meant
      # to fix.
      # Recorded even with no section (cur2 empty), so the loose-frame
      # fallback below -- Boot.md3's unsectioned kick, Buzzsaw's swing --
      # still sees every frame the block references, resolved the same way.
      $refs.Add(@{sec=$cur2; spr=$spr; let=$let})
      $slot["$spr|$let"] = $i
    }
  }

  # PASS 2. Same references, now resolved through the completed $slot table.
  foreach ($r in $refs) {
    $cur2 = $r.sec; $spr = $r.spr; $let = $r.let
    $i = $slot["$spr|$let"]
    if ($i -ge $frameCount) { $over++; continue }
    if (-not $loose.Contains($i)) { $loose.Add($i) }
    if ($cur2) {
      if (-not $buckets.ContainsKey($cur2)) { $buckets[$cur2] = New-Object System.Collections.Generic.List[int] }
      if (-not $buckets[$cur2].Contains($i)) { $buckets[$cur2].Add($i) }
      # First sprite/letter each section uses -- the deploy-vs-idle signal below.
      if (-not $sprite.ContainsKey($cur2)) { $sprite[$cur2] = $spr }
      if (-not $letter.ContainsKey($cur2)) { $letter[$cur2] = $let }
    }
  }

  # "//Ready weapon" IS THE DEPLOY, NOT THE IDLE, and BD tells us which by
  # the SPRITE it uses. The rifle's ready section is RIFS; its held pose is
  # RIFG at frame 3. Park on RIFS frame 0 and the gun points at the floor --
  # which is exactly what it does, permanently, in the static Quest build
  # where nothing ever leaves the rest frame.
  #
  # Same shape on the shotgun (SHSS vs SHTN), plasma (PLS9 vs PLSN),
  # machinegun (MGS1 vs MGN1), assault shotgun, minigun and M79. The pistol
  # is the one that looked right, and it is the one weapon whose ready and
  # fire sections share a sprite (PIST) -- there frame 0 really is the idle.
  #
  # So: same sprite in both sections means the ready frames are a genuine
  # idle and are kept. A different sprite means the section is a deploy --
  # it becomes the select clip, where it belongs, and the idle becomes the
  # first frame of the fire section, which is the held pose by construction.
  if ($buckets.ContainsKey('ready') -and $buckets.ContainsKey('fire') -and
      $sprite['ready'] -ne $sprite['fire']) {
    $buckets['select'] = $buckets['ready']
    $held = $buckets['fire'][0]
    $r = New-Object System.Collections.Generic.List[int]; $r.Add($held)
    $buckets['ready'] = $r
    $notes += "$cls -- ready was $($sprite['ready']) (a deploy), moved to select; idle is $($sprite['fire']) frame $held"
    # This rule wins over the last-mapping resolution below: when the
    # ready section is a deploy on its own sprite, the held pose is the
    # fire section's first frame and nothing about the ready sprite
    # should decide where the model parks.
    $sprite['ready'] = $sprite['fire']
    $letter['ready'] = $letter['fire']
  }
  if ($over) { $notes += "$cls -- dropped $over frame refs past the mesh's $frameCount frames" }

  # Some blocks carry frames under no section header at all -- Boot.md3 (the
  # kick) is written that way in every def that includes it, as is the
  # Buzzsaw. Those frames are not nothing; they are one unlabelled animation.
  # Reading them as the fire clip is what a kick or a saw swing IS, and beats
  # dropping the only model a family has.
  if ($buckets.Count -eq 0 -and $loose.Count -gt 0) {
    $buckets['fire'] = $loose
    $notes += "$cls -- $($loose.Count) unsectioned frames read as the fire clip"
  }
  if ($buckets.Count -eq 0) { $notes += "SKIP $cls -- no frames at all"; $seen.Remove($cls); continue }

  # The ready bucket is already resolved as of PASS 2 -- every frame in it
  # went through the sprite+letter last-mapping table before being added, so
  # its own lowest frame IS the rest pose. BD remaps PIST A from 0 to 3 in a
  # later section; taking the bucket directly is what makes the pistol rest
  # on 3 rather than the dead pre-remap 0, without a second, separate lookup
  # that could drift from what the bucket actually contains.
  $rest = if ($buckets.ContainsKey('ready') -and $buckets['ready'].Count) { ($buckets['ready'] | Sort-Object)[0] } else { 0 }

  # BD only comments some sections, so a mesh can carry a full reload with no
  # //Reload header above it. Where that happens, infer it: the frames past the
  # end of every named section are the reload. Requires a real run (>=4 frames)
  # so a couple of stray indices do not masquerade as an animation.
  if (-not $buckets.ContainsKey('reload')) {
    $used = @(); foreach ($k in $buckets.Keys) { $used += $buckets[$k] }
    $top = if ($used.Count) { ($used | Measure-Object -Maximum).Maximum } else { 0 }
    if (($frameCount - 1 - $top) -ge 4) {
      $inf = New-Object System.Collections.Generic.List[int]
      for ($i = $top + 1; $i -lt $frameCount; $i++) { $inf.Add($i) }
      $buckets['reload'] = $inf
      $notes += "$cls -- reload inferred from frames $($top+1)-$($frameCount-1) (no //Reload header)"
    }
  }

  [void]$md.AppendLine("Model $cls")
  [void]$md.AppendLine("{")
  [void]$md.AppendLine("`tPath `"models/bd21/$leaf`"")
  [void]$md.AppendLine("`tModel 0 `"$mdl`"")
  if ($skn) { [void]$md.AppendLine("`tSkin 0 `"$skn`"") }
  [void]$md.AppendLine("`tScale $scl")
  [void]$md.AppendLine("`tZOffset $zof")
  [void]$md.AppendLine("`tNoInterpolation")
  [void]$md.AppendLine("`tFrameIndex $anchor A 0 $rest")
  [void]$md.AppendLine("`tFrameIndex $anchor B 0 9999")
  [void]$md.AppendLine("}")
  [void]$md.AppendLine("")

  [void]$st.AppendLine("class $cls : Actor {}")

  foreach ($k in ($buckets.Keys | Sort-Object)) {
    $ix = @($buckets[$k] | Sort-Object)
    if (-not $ix.Count) { continue }
    $steps = ($ix | ForEach-Object { "$_@1" }) -join ','
    $mark = if ($k -eq 'fire') { 0 } else { -1 }
    [void]$cl.AppendLine("`t`t`t`"$cls|$k|$steps|$mark|-1|-1`",")
  }

  $rows += "`t`t`t`"$fam|$cls|$anchor|0|$rest|$frameCount`","
  # A mesh may honestly belong on more than one shelf. Nothing stops a model
  # appearing under several archetypes; the row is the same, only the shelf
  # differs. The Dragonslayer is a blade, so it answers for melee too.
  if ($EXTRAFAM.ContainsKey($meshName)) {
    foreach ($xf in $EXTRAFAM[$meshName]) {
      $rows += "`t`t`t`"$xf|$cls|$anchor|0|$rest|$frameCount`","
    }
  }
}

Set-Content "$out\bd21.modeldef" $md.ToString() -Encoding utf8
Set-Content "$out\bd21.stubs"    $st.ToString() -Encoding utf8
Set-Content "$out\bd21.clips"    $cl.ToString() -Encoding utf8
Set-Content "$out\bd21.shelf"    (($rows -join "`n")) -Encoding utf8

Write-Host "models: $(($st.ToString() -split "`n" | Where-Object {$_ -match 'class'}).Count)"
Write-Host "clip rows: $(($cl.ToString() -split "`n" | Where-Object {$_.Trim()}).Count)"
Write-Host "--- clip coverage ---"
($cl.ToString() -split "`n") | Where-Object {$_ -match '\|'} | ForEach-Object {
  ($_ -split '\|')[1]
} | Group-Object | Sort-Object Count -Descending | ForEach-Object { "  $($_.Name): $($_.Count)" }
Write-Host "--- notes ---"
$notes | ForEach-Object { "  $_" }
