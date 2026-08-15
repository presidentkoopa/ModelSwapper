# Generate ModelSwapper assets from Brutal Doom v21's own weapon MODELDEFs.
#
# BD's defs are section-annotated (//Ready, //Aim and Fire, //Reload, //Zoom,
# //Sprint, //Rude), so which frames belong to which animation is DERIVED from
# the source rather than guessed. That is the whole reason this is a script and
# not a hand transcription.
#
# Emits three fragments:
#   bd21.modeldef   -- our MODELDEF blocks, re-anchored onto stock Doom sprites
#   bd21.stubs      -- the bodyless Actor stubs each block needs to exist
#   bd21.clips      -- clip rows, one per (model, animation section)

$src = "D:\SteamLibrary\steamapps\Common\DooM VR\__Games\BrutalDoom\_BD_1.01_WeaponModels"
$out = "C:\Users\Command\AppData\Local\Temp\claude\E--ModelSwapper\d584ff43-5514-4c35-8f33-afd790fbe555\scratchpad"

# BD model name -> (our family, anchor sprite). Anchors are stock Doom sprite
# names so we ship no sprites of our own; the pin only has to resolve.
$MAP = @{
  'Fist'            = @('melee','PUNG');   'BrutalAxe'   = @('axe','PUNG')
  'Chain_saw'       = @('saw','SAWG');     'HitlersBuzzsaw' = @('saw','SAWG')
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
}

# section comment -> our clip name. Anything unlisted is ignored.
function Sect([string]$c){
  $c = ($c -replace '//','').Trim().ToLower()
  if ($c -match '^ready')                    { return 'ready'   }
  if ($c -match 'aim and fire|^fire|alt-?fire'){ return 'fire'   }
  if ($c -match '^reload')                   { return 'reload'  }
  if ($c -match '^zoom')                     { return 'ads'     }
  if ($c -match '^sprint')                   { return 'sprint'  }
  if ($c -match '^rude')                     { return 'taunt'   }
  if ($c -match 'nade')                      { return 'grenade' }
  return ''
}

$md = New-Object System.Text.StringBuilder
$st = New-Object System.Text.StringBuilder
$cl = New-Object System.Text.StringBuilder
$rows = @()
# Several defs point at the SAME mesh folder -- Modeldef.ClassicShotgun.def and
# Modeldef.Shotgun.def are one model with two sprite mappings. One class per
# mesh, first definition wins; sorted order puts the non-Classic one first,
# which is the BD-native mapping we want. A duplicate class is a hard compile
# error, so this is not optional.
$seen = @{}

# A .def is NOT one model. BD declares the same actor name several times in
# one file, each block bound to a DIFFERENT mesh -- the gun, plus Boot.md3 for
# the kick and nade.md3 for the grenade toss. The sprite name selects which
# mesh; the frame index selects within it. Parsing a file as a unit merges
# three meshes' frame numbering into nonsense, so split on block boundaries
# and treat each as its own model, named after its MESH rather than the folder.
$blocks = @()
foreach ($f in Get-ChildItem "$src\Modeldef.*.def" | Sort-Object Name) {
  $lines = Get-Content $f.FullName
  $cur = $null
  foreach ($line in $lines) {
    if ($line -match '(?i)^\s*Model\s+\S+\s*$') {
      if ($cur) { $blocks += ,$cur }
      $cur = [pscustomobject]@{ Lines = New-Object System.Collections.Generic.List[string] }
      continue
    }
    if ($cur) { $cur.Lines.Add($line) }
  }
  if ($cur) { $blocks += ,$cur }
}

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
  $seen[$cls] = $true

  # Family/anchor follow the MESH when we know it, else the folder it sat in.
  $fam    = $MAP[$leaf][0]
  $anchor = $MAP[$leaf][1]
  if ($MAP.ContainsKey($meshName)) { $fam = $MAP[$meshName][0]; $anchor = $MAP[$meshName][1] }

  $skn = if ($txt -match '(?im)^\s*Skin\s+0\s+"([^"]+)"')  { $matches[1] } else { '' }
  $scl = if ($txt -match '(?im)^\s*Scale\s+(\S+)\s+(\S+)\s+(\S+)') { "$($matches[1]) $($matches[2]) $($matches[3])" } else { '-1.0 1.0 1.0' }
  $zof = if ($txt -match '(?im)^\s*ZOffset\s+(\S+)') { $matches[1] } else { '0' }

  $cur2 = ''; $buckets = @{}
  $maxIdx = 0
  foreach ($line in $b.Lines) {
    $t = $line.Trim()
    if ($t -match '^//') {
      # A commented-out FrameIndex is dead data, not a section header.
      if ($t -notmatch '(?i)frameindex') { $s = Sect $t; if ($s) { $cur2 = $s } }
      continue
    }
    if ($t -match '(?i)^FrameIndex\s+\S+\s+\S+\s+\d+\s+(\d+)') {
      $i = [int]$matches[1]
      if ($i -gt $maxIdx) { $maxIdx = $i }
      if ($cur2) {
        if (-not $buckets.ContainsKey($cur2)) { $buckets[$cur2] = New-Object System.Collections.Generic.List[int] }
        if (-not $buckets[$cur2].Contains($i)) { $buckets[$cur2].Add($i) }
      }
    }
  }
  if ($maxIdx -eq 0 -and $buckets.Count -eq 0) { continue }

  $frameCount = $maxIdx + 1
  $rest = if ($buckets.ContainsKey('ready') -and $buckets['ready'].Count) { ($buckets['ready'] | Sort-Object)[0] } else { 0 }

  # BD only comments some sections, so a mesh can carry a full reload with no
  # //Reload header above it. Where that happens, infer it the same way the
  # original tables were derived: the frames past the end of the fire range
  # are the reload. Requires a real run (>=4 frames) so a couple of stray
  # indices do not masquerade as an animation.
  if (-not $buckets.ContainsKey('reload')) {
    $used = @(); foreach ($k in $buckets.Keys) { $used += $buckets[$k] }
    $top = if ($used.Count) { ($used | Measure-Object -Maximum).Maximum } else { 0 }
    if (($maxIdx - $top) -ge 4) {
      $inf = New-Object System.Collections.Generic.List[int]
      for ($i = $top + 1; $i -le $maxIdx; $i++) { $inf.Add($i) }
      $buckets['reload'] = $inf
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
  [void]$md.AppendLine("}")
  [void]$md.AppendLine("")

  [void]$st.AppendLine("class $cls : Actor {}")

  foreach ($k in $buckets.Keys) {
    $ix = ($buckets[$k] | Sort-Object)
    if (-not $ix.Count) { continue }
    $steps = ($ix | ForEach-Object { "$_@1" }) -join ','
    $mark = if ($k -eq 'fire') { 0 } else { -1 }
    [void]$cl.AppendLine("`t`t`t`"$cls|$k|$steps|$mark|-1|-1`",")
  }

  $rows += "`t`t`t`"$fam|$cls|$anchor|0|$rest|$frameCount`","
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