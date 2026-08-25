# ============================================================================
# tools_gen_pickups.ps1 -- generate the IN-WORLD PICKUP half of the shelf.
#
# WHAT THIS SOLVES. A HUD model and a floor pickup are the same mesh seen from
# two completely different places. The HUD block's Scale is tuned for a mesh
# held at arm's length in view space; drop that number on a world actor and you
# get a gun the size of a car, posed at whatever angle the artist found
# comfortable for the hand. Every donor was authored independently, so there is
# no single correction: our 44 meshes span 27 to 214 local units end to end.
#
# So each pickup gets its OWN MODELDEF block, with Scale, Offset and the three
# rotation offsets SOLVED FROM THE MESH rather than found by eye.
#
# THE DISJOINT-ANCHOR INVARIANT -- the reason this is safe to ship.
# HUD blocks anchor on the stock HAND sprites (PISG, SHTG, CHGG, MISG, PLSG,
# BFGG, PUNG, SAWG and the donors' own). Every block generated here anchors on
# SHOT A instead, which appears in NO hud shelf row. Because the two sprite
# spaces never overlap, a binding that is stale in either direction resolves to
# NOTHING: FindModelFrame returns null and the actor falls back to drawing its
# sprite. There is no arrangement of bugs that can render a HUD-scaled gun on
# the floor. That property is worth more than careful event handling, because
# it is what holds WHEN the event handling is wrong.
#
# SHOT A specifically because it is in every Doom IWAD including Doom 1 (SGN2
# is Doom 2 only), and because one anchor for all 44 makes the invariant a
# one-line audit instead of a table to cross-check.
#
# ---------------------------------------------------------------------------
# THE GEOMETRY, and where every convention below was read from.
# Engine paths cited are UZDXREMA; stock GZDoom is identical in all of them.
#
# COORDINATES. The MD3 loader writes vertices Quake-style and the renderer
# consumes them GL-style, so the mapping is fixed:
#     GL x = md3 x  (forward)   GL y = md3 z  (UP)   GL z = md3 y  (side)
# confirmed by r_data/models.cpp:597, which translates the actor position as
# (X, Z, Y), and by the scale call at :715 handing GL y the MODELDEF *zscale*.
#
# PIXEL STRETCH. models.cpp:731 applies scale(1, stretch, 1) as the LAST matrix
# call, which makes it the FIRST transform a vertex sees -- the mesh is squashed
# vertically BEFORE our rotation offsets act on it. stretch is
# getAspectFactor()/pixelstretch = 1.0/1.2 for MD3 (model.h:177 returns 1.f;
# only voxels override it), so the fit has to be done on squashed vertices or
# every derived pitch is wrong by the tangent of a 17% vertical crush.
#
# ROTATION ORDER. models.cpp:725-727 is
#     rotate(-angleoffset, 0,1,0)  -> yaw   about GL y
#     rotate(+pitchoffset, 0,0,1)  -> pitch about GL z
#     rotate(-rolloffset,  1,0,0)  -> roll  about GL x
# VSMatrix::rotate post-multiplies, so as applied to a vertex that is
# R = Ry(a) . Rz(p) . Rx(r) -- roll first, yaw last. Writing that product out
# and reading the entries off gives the closed-form decomposition used below.
# Note the SIGNS: two of the three are negated on the way in.
#
# OFFSET UNITS. models.cpp:721 translates by offset/scale and the surrounding
# scale call multiplies it straight back, so Offset x and y land in world units
# unchanged. Offset z does NOT: its divisor carries the stretch term as well
# (zoffset/(zscale*stretch)), so a lift of L world units is written as
# L*stretch. This is the one number that cannot be found by staring at the file.
#
# SCALE MUST BE UNIFORM. The scale at :715 is applied AFTER our rotations, so
# three different numbers would shear a rotated mesh rather than resize it.
# ---------------------------------------------------------------------------
#
# WHAT IS SOLVED PER MESH:
#   1. Principal axis of the rest-frame vertex cloud (covariance + power
#      iteration) -- for a gun this is the barrel line.
#   2. Rotation offsets that lay that axis horizontal along +X.
#   3. Scale = the family's target length / the measured post-rotation length.
#   4. Offset that centres the mesh on the actor and rests it on the floor.
#
# MINIMAL ROTATION, ON PURPOSE. The mesh's own up direction is preserved --
# "up" is world up projected perpendicular to the barrel, not the second
# eigenvector -- so a mesh authored upright STAYS upright and roll comes out
# near zero. Deriving roll from the vertex cloud instead would let a densely
# tessellated scope or a fat magazine bank a gun that was already level. The
# eigenvector is the fallback, used only when the barrel is within 18 degrees
# of vertical and world up cannot be projected.
#
# Run:  pwsh -File tools_gen_pickups.ps1
# Then paste .gen/pickups.modeldef into modeldef, .gen/pickups.stubs into
# zscript.txt, and .gen/pickups.shelf into RS_ForeignPickups.zs.
# ============================================================================

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$gen  = Join-Path $root '.gen'
if (-not (Test-Path $gen)) { New-Item -ItemType Directory -Path $gen | Out-Null }

# One anchor for all of them. See the header.
$ANCHOR = 'SHOT'

# GL-y squash the renderer applies before our rotations. See PIXEL STRETCH.
$STRETCH = 1.0 / 1.2

# ---------------------------------------------------------------------------
# TARGET LENGTHS, in world units, muzzle to stock, per archetype.
#
# Taken from the stock Doom pickup sprites these sit next to, because that is
# the only reference the player actually has on screen: SHOTA0 is 63px wide,
# MGUNA0 45, LAUNA0 61, PLASA0 55, BFUGA0 51, CSAWA0 37, and a Doom sprite is
# one unit per pixel. Trimmed a little from the raw widths -- a sprite's width
# includes its diagonal pose, while these numbers are along the barrel.
#
# NORMALISE PER MODEL, TARGET PER FAMILY. Fitting every mesh to one number is
# the failure this exists to avoid: it makes a BFG and a pistol the same size.
# The per-mesh measurement removes AUTHORING variance (our meshes span 8x); the
# per-family target is what keeps a real size difference between a holdout and
# a crew-served weapon.
# ---------------------------------------------------------------------------
$TARGET = @{
  'pistol'       = 22.0
  'revolver'     = 24.0
  'smg'          = 34.0
  'rifle'        = 46.0
  'sniper'       = 50.0
  'shotgun'      = 50.0
  'supershotgun' = 48.0
  'machinegun'   = 48.0
  'chaingun'     = 46.0
  'rocket'       = 56.0
  'launcher'     = 46.0
  'grenade'      = 12.0
  'plasma'       = 48.0
  'railgun'      = 52.0
  'flamethrower' = 50.0
  'bfg'          = 48.0
  'unmaker'      = 44.0
  'melee'        = 26.0
  'kick'         = 30.0
  'axe'          = 40.0
  'saw'          = 38.0
}
$TARGET_DEFAULT = 40.0

# Nothing may stand taller than Doom's own tallest weapon pickup sprite.
$MAX_HEIGHT = 28.0

# ---------------------------------------------------------------------------
# PER-MODEL OVERRIDES. Same unit as $TARGET -- a target length for one donor,
# replacing whatever its family would have given it.
#
# The family targets are the rule; this is where the exceptions live. There is
# no measurement that finds these, because they are not measurement errors:
# the fit does exactly what it was asked and the ASK was wrong for that mesh.
# The way to find one is to load MSZOO, walk the grid, and see what reads
# wrong beside its neighbours. Put the number here rather than moving a whole
# family for the sake of one gun.
# ---------------------------------------------------------------------------
$OVERRIDE = @{
  # Family 'plasma' asks for 48 long, which is right for a plasma rifle and
  # far too big for this. The bolter mesh is stubby -- 42 long against 29 tall
  # in its own space, where a rifle is more like 8:1 -- so matching a rifle's
  # LENGTH stood it up like a deck gun. Judged by eye in the zoo at 40% down.
  'MS_MG_Bolter' = 29.0
}

# ---------------------------------------------------------------------------
# MD3 reading. Header: num_frames@76 num_surfaces@84 ofs_frames@92
# ofs_surfaces@100. Surface: name@4[64] num_verts@80 ofs_xyz@100 ofs_end@104,
# vertices frame-major (frame*num_verts + v), 8 bytes each, int16 coords at
# 1/64 unit. Same layout tools_gen_bd21.ps1 already reads num_frames out of.
# ---------------------------------------------------------------------------
function Read-MD3Frame([string]$path, [int]$frame)
{
  if (-not (Test-Path $path)) { return $null }
  $fs = [System.IO.File]::OpenRead($path)
  try {
    $br = New-Object System.IO.BinaryReader($fs)
    $h  = $br.ReadBytes(108)
    if ([Text.Encoding]::ASCII.GetString($h,0,4) -ne 'IDP3') { return $null }
    $numFrames = [BitConverter]::ToInt32($h,76)
    $numSurf   = [BitConverter]::ToInt32($h,84)
    $ofsSurf   = [BitConverter]::ToInt32($h,100)
    if ($frame -lt 0 -or $frame -ge $numFrames) { $frame = 0 }

    $verts = New-Object System.Collections.Generic.List[double[]]
    $surfNames = @()
    $dropped = @()
    $p = $ofsSurf
    for ($i = 0; $i -lt $numSurf; $i++) {
      $fs.Position = $p
      $sh = $br.ReadBytes(108)
      $sName   = [Text.Encoding]::ASCII.GetString($sh,4,64).Trim([char]0)
      $sFrames = [BitConverter]::ToInt32($sh,72)
      $nv      = [BitConverter]::ToInt32($sh,80)
      $ofsXyz  = [BitConverter]::ToInt32($sh,100)
      $ofsEnd  = [BitConverter]::ToInt32($sh,104)
      $surfNames += $sName
      # A surface can legitimately carry fewer frames than the header claims.
      $f = if ($frame -lt $sFrames) { $frame } else { 0 }
      if ($nv -gt 0) {
        $fs.Position = $p + $ofsXyz + ($f * $nv * 8)
        $raw = $br.ReadBytes($nv * 8)
        $sv = New-Object 'double[][]' $nv
        $mnx=[double]::MaxValue;$mxx=-[double]::MaxValue
        $mny=[double]::MaxValue;$mxy=-[double]::MaxValue
        $mnz=[double]::MaxValue;$mxz=-[double]::MaxValue
        for ($v = 0; $v -lt $nv; $v++) {
          $o = $v * 8
          # Parentheses are load-bearing: PowerShell's comma binds TIGHTER than
          # arithmetic, so `a / 64.0, b / 64.0` parses as `a / (64.0, b) / 64.0`
          # and dies on op_Division against an Object[]. Same everywhere below.
          $x = ([BitConverter]::ToInt16($raw,$o)   / 64.0)
          $y = ([BitConverter]::ToInt16($raw,$o+2) / 64.0)
          $z = ([BitConverter]::ToInt16($raw,$o+4) / 64.0)
          $sv[$v] = @($x,$y,$z)
          if ($x -lt $mnx){$mnx=$x}; if ($x -gt $mxx){$mxx=$x}
          if ($y -lt $mny){$mny=$y}; if ($y -gt $mxy){$mxy=$y}
          if ($z -lt $mnz){$mnz=$z}; if ($z -gt $mxz){$mxz=$z}
        }
        # COLLAPSED SURFACES ARE NOT GEOMETRY. Both donor sets hide an inactive
        # sub-mesh at the rest pose by welding all of its vertices to a single
        # point -- VanAlek's revolver parks 257 of its 859 vertices on one spot
        # 78 units off the gun, and the fist ships a duplicate glove collapsed
        # to (0,20,0), fully HALF that mesh's vertices. Invisible in game and
        # ruinous to a vertex fit: the revolver's principal axis came out
        # pointing at the dot rather than down the barrel, and the bounding box
        # it sized against was three times the length of the actual gun.
        # Anything with no extent at this frame draws nothing at this frame.
        $diag = [math]::Sqrt((($mxx-$mnx)*($mxx-$mnx)) + (($mxy-$mny)*($mxy-$mny)) + (($mxz-$mnz)*($mxz-$mnz)))
        if ($diag -lt 0.25) {
          $dropped += "$sName($nv)"
        } else {
          foreach ($q in $sv) { $verts.Add($q) }
        }
      }
      if ($ofsEnd -le 0) { break }
      $p += $ofsEnd
    }
    return @{ Verts = $verts; Frames = $numFrames; Surfaces = $surfNames; Dropped = $dropped }
  } finally { $fs.Close() }
}

# --- small vector/matrix helpers (3x3 as a flat 9-array, row-major) ---------
function V-Sub($a,$b)   { ,@(($a[0]-$b[0]), ($a[1]-$b[1]), ($a[2]-$b[2])) }
function V-Dot($a,$b)   { $a[0]*$b[0] + $a[1]*$b[1] + $a[2]*$b[2] }
function V-Cross($a,$b) { ,@(($a[1]*$b[2]-$a[2]*$b[1]), ($a[2]*$b[0]-$a[0]*$b[2]), ($a[0]*$b[1]-$a[1]*$b[0])) }
function V-Norm($a) {
  $l = [math]::Sqrt((V-Dot $a $a))
  if ($l -lt 1e-12) { return ,@(1.0,0.0,0.0) }
  ,@(($a[0]/$l), ($a[1]/$l), ($a[2]/$l))
}
function M-Mul($m,$v) {
  ,@(($m[0]*$v[0]+$m[1]*$v[1]+$m[2]*$v[2]),
     ($m[3]*$v[0]+$m[4]*$v[1]+$m[5]*$v[2]),
     ($m[6]*$v[0]+$m[7]*$v[1]+$m[8]*$v[2]))
}

# Dominant eigenvector by power iteration. Deterministic seed so a rerun with
# an unchanged mesh produces a byte-identical block -- a generated file that
# churns on every run is a generated file nobody can review.
function Dominant-Eigen($cov, $seed) {
  $v = V-Norm $seed
  for ($i = 0; $i -lt 200; $i++) {
    $n = M-Mul $cov $v
    if ((V-Dot $n $n) -lt 1e-20) { return @{ Vec = $v; Val = 0.0 } }
    $v = V-Norm $n
  }
  @{ Vec = $v; Val = (V-Dot $v (M-Mul $cov $v)) }
}

# ---------------------------------------------------------------------------
# Inputs: the MODELDEF blocks this pk3 owns, and the shelf's rest frame and
# family for each. Both are READ, never duplicated -- the shelf stays the one
# place a donor's rest pose is written down.
# ---------------------------------------------------------------------------
$mdText = Get-Content (Join-Path $root 'modeldef') -Raw
$blocks = [regex]::Matches($mdText, '(?ms)^Model\s+(\S+)\s*\r?\n\{(.*?)^\}')

$shelfText = Get-Content (Join-Path $root 'zscript\RS_ForeignModels.zs') -Raw
$shelfBody = [regex]::Match($shelfText, '(?ms)static const string SHELF\[\]\s*=\s*\{(.*?)\};').Groups[1].Value
$shelf = @{}
foreach ($m in [regex]::Matches($shelfBody, '"([a-z]+)\|([A-Za-z0-9_]+)\|([A-Z0-9]{4})\|(-?\d+)\|(-?\d+)\|(\d+)"')) {
  $cls = $m.Groups[2].Value
  if (-not $shelf.ContainsKey($cls)) {
    $shelf[$cls] = @{ Family = $m.Groups[1].Value; RestFrame = [int]$m.Groups[5].Value }
  }
}

$rows = @(); $notes = @(); $defs = @(); $stubs = @(); $map = @()

foreach ($b in $blocks) {
  $cls  = $b.Groups[1].Value
  $body = $b.Groups[2].Value
  $path = ([regex]::Match($body,'(?im)^\s*Path\s+"([^"]+)"')).Groups[1].Value
  $mdl  = ([regex]::Match($body,'(?im)^\s*Model\s+0\s+"([^"]+)"')).Groups[1].Value
  $skin = ([regex]::Match($body,'(?im)^\s*Skin\s+0\s+"([^"]+)"')).Groups[1].Value

  # Our own output, from a previous run -- modeldef holds both halves now.
  # Skipped silently rather than reported, because it is not a finding.
  if ($cls -like 'MS_PU_*') { continue }

  if (-not $shelf.ContainsKey($cls)) { $notes += "SKIP $cls -- not on the shelf, nothing can pick it"; continue }
  $fam  = $shelf[$cls].Family
  $rest = $shelf[$cls].RestFrame

  # Path is a pk3-relative lump path; on disk it is the same path under root.
  $file = Join-Path $root ($path.Replace('/','\') + '\' + $mdl)
  $md3  = Read-MD3Frame $file $rest
  if ($md3 -eq $null)          { $notes += "SKIP $cls -- unreadable or not an MD3: $path/$mdl"; continue }
  if ($md3.Verts.Count -lt 8)  { $notes += "SKIP $cls -- only $($md3.Verts.Count) vertices at frame $rest"; continue }

  # --- to GL space, with the renderer's vertical squash already applied -----
  $n = $md3.Verts.Count
  $gl = New-Object 'double[][]' $n
  $cx = 0.0; $cy = 0.0; $cz = 0.0
  for ($i = 0; $i -lt $n; $i++) {
    $v = $md3.Verts[$i]
    $g = @($v[0], ($v[2] * $STRETCH), $v[1])   # GL x=md3x, y=md3z*stretch, z=md3y
    $gl[$i] = $g
    $cx += $g[0]; $cy += $g[1]; $cz += $g[2]
  }
  $centroid = @(($cx/$n), ($cy/$n), ($cz/$n))

  # --- covariance of the centred cloud --------------------------------------
  $c00=0.0;$c01=0.0;$c02=0.0;$c11=0.0;$c12=0.0;$c22=0.0
  for ($i = 0; $i -lt $n; $i++) {
    $d = V-Sub $gl[$i] $centroid
    $c00 += $d[0]*$d[0]; $c01 += $d[0]*$d[1]; $c02 += $d[0]*$d[2]
    $c11 += $d[1]*$d[1]; $c12 += $d[1]*$d[2]; $c22 += $d[2]*$d[2]
  }
  $cov = @(($c00/$n),($c01/$n),($c02/$n), ($c01/$n),($c11/$n),($c12/$n), ($c02/$n),($c12/$n),($c22/$n))

  # --- u: the barrel line ---------------------------------------------------
  $e1 = Dominant-Eigen $cov @(1.0,0.0,0.0)
  $u  = $e1.Vec
  # Sign: keep the mesh's own +X sense. PCA gives an axis, not a direction, and
  # nothing in a vertex cloud reliably says which end is the muzzle -- a rocket
  # launcher's muzzle is its WIDEST point, so "thin end forward" is not a rule.
  # If a whole donor set comes out backwards that is one 180 added to every
  # AngleOffset, not 44 individual corrections.
  if ($u[0] -lt 0) { $u = @((-$u[0]), (-$u[1]), (-$u[2])) }

  # Second eigenvector, by deflating the dominant one out so the iteration
  # cannot just re-find it. Wanted for its EIGENVALUE as much as its direction:
  # l1/l2 is the honest measure of whether a dominant axis exists at all.
  $l1  = $e1.Val
  $def = @(); for ($i=0;$i -lt 3;$i++){ for ($j=0;$j -lt 3;$j++){ $def += ($cov[$i*3+$j] - $l1*$u[$i]*$u[$j]) } }
  $e2  = Dominant-Eigen $def @(0.0,1.0,0.0)
  $ratio = if ($e2.Val -gt 1e-9) { $l1 / $e2.Val } else { 999.0 }

  $fitSrc = 'pca'
  if ($ratio -lt 1.5) {
    # NO DOMINANT AXIS. A grenade or a boot is not a rod, and fitting a barrel
    # line to one returns whichever diagonal the vertices happened to favour --
    # a 43-degree tilt on a thing that has no barrel. Leave the author's pose
    # alone and only resize it. Refusing to rotate what cannot be measured
    # beats rotating it confidently in an arbitrary direction.
    $fitSrc = 'axis-aligned'
    $u = @(1.0,0.0,0.0); $w = @(0.0,1.0,0.0); $nn = @(0.0,0.0,1.0)
  }
  else {
    # --- w: the mesh's up, kept as close to world up as the barrel allows ---
    $worldUp = @(0.0,1.0,0.0)
    if ([math]::Abs((V-Dot $u $worldUp)) -gt 0.95) {
      # Barrel within ~18 degrees of vertical: world up has nothing left to
      # project, so the second eigenvector supplies the up instead.
      $fitSrc = 'pca+eigen2'
      $w0 = $e2.Vec
      if ($w0[1] -lt 0) { $w0 = @((-$w0[0]),(-$w0[1]),(-$w0[2])) }   # prefer up over down
      $worldUp = $w0
    }
    # Project world up perpendicular to the barrel -- the minimal-rotation up.
    $dot = V-Dot $worldUp $u
    $w   = V-Norm @(($worldUp[0] - $dot*$u[0]), ($worldUp[1] - $dot*$u[1]), ($worldUp[2] - $dot*$u[2]))
    $nn  = V-Cross $u $w
  }

  # --- decompose R = Ry(a).Rz(p).Rx(r), rows of R being u, w, n ------------
  # Writing that product out gives R[1][0]=sin p, R[1][1]=cos p cos r,
  # R[1][2]=-cos p sin r, R[0][0]=cos a cos p, R[2][0]=-sin a cos p.
  $rad = 180.0 / [math]::PI
  $sp  = [math]::Max(-1.0, [math]::Min(1.0, $w[0]))
  $pDeg = [math]::Asin($sp) * $rad
  $rDeg = [math]::Atan2(-$w[2], $w[1]) * $rad
  $aDeg = [math]::Atan2(-$nn[0], $u[0]) * $rad

  # Into MODELDEF's signs: the engine applies -angleoffset, +pitchoffset,
  # -rolloffset (models.cpp:725-727).
  $angleOffset = -$aDeg
  $pitchOffset =  $pDeg
  $rollOffset  = -$rDeg

  # --- measure the mesh as it will actually be drawn -------------------------
  $R = @($u[0],$u[1],$u[2], $w[0],$w[1],$w[2], $nn[0],$nn[1],$nn[2])
  $mnx=[double]::MaxValue;$mny=[double]::MaxValue;$mnz=[double]::MaxValue
  $mxx=-[double]::MaxValue;$mxy=-[double]::MaxValue;$mxz=-[double]::MaxValue
  for ($i = 0; $i -lt $n; $i++) {
    $q = M-Mul $R $gl[$i]
    if ($q[0] -lt $mnx){$mnx=$q[0]}; if ($q[0] -gt $mxx){$mxx=$q[0]}
    if ($q[1] -lt $mny){$mny=$q[1]}; if ($q[1] -gt $mxy){$mxy=$q[1]}
    if ($q[2] -lt $mnz){$mnz=$q[2]}; if ($q[2] -gt $mxz){$mxz=$q[2]}
  }
  $lenX = $mxx - $mnx
  if ($lenX -lt 1e-6) { $notes += "SKIP $cls -- degenerate along its own principal axis"; continue }

  # NOT $target -- PowerShell variables are case-insensitive, so that name
  # would silently overwrite the $TARGET table on the first model.
  $targetLen = if ($OVERRIDE.ContainsKey($cls))  { $OVERRIDE[$cls] }
               elseif ($TARGET.ContainsKey($fam)) { $TARGET[$fam] }
               else                               { $TARGET_DEFAULT }
  if ($OVERRIDE.ContainsKey($cls)) {
    $notes += "$cls -- per-model override: $targetLen long instead of the $fam family's $(if ($TARGET.ContainsKey($fam)) { $TARGET[$fam] } else { $TARGET_DEFAULT })"
  }
  # With a fitted barrel the length IS the X extent. Without one, nothing says
  # X is the long way, so the target applies to whichever axis is longest --
  # otherwise a mesh that happens to be tall gets sized by its narrow side and
  # comes out enormous.
  $fitLen = if ($fitSrc -eq 'axis-aligned') {
              [math]::Max($lenX, [math]::Max(($mxy-$mny), ($mxz-$mnz)))
            } else { $lenX }
  $s = $targetLen / $fitLen

  # HEIGHT CEILING. Sizing purely by length assumes a mesh is roughly gun
  # shaped; one that is short and tall would be scaled UP to reach its family's
  # length and end up standing over the player. Doom's own tallest weapon
  # pickup sprites (LAUNA0, BFUGA0) are 27px, so nothing here has any business
  # exceeding that. Inert for all 44 current donors -- the Bolter is the
  # closest at 27 and still under -- and it stays inert until a donor with
  # genuinely odd proportions is added, which is exactly when it should fire.
  $hFit = $mxy - $mny
  if ($hFit -gt 1e-6 -and ($s * $hFit) -gt $MAX_HEIGHT) {
    $sCap = $MAX_HEIGHT / $hFit
    $notes += "$cls -- height-capped: sizing to $targetLen long would stand it $([math]::Round($s*$hFit,1)) tall, so scale drops $([math]::Round($s,3)) -> $([math]::Round($sCap,3))"
    $s = $sCap
  }

  # Centre horizontally on the actor, rest the lowest vertex on the floor.
  # Offset x/y are world units; Offset z carries the stretch term. See header.
  $offX = -$s * (($mnx + $mxx) / 2.0)
  $offY = -$s * (($mnz + $mxz) / 2.0)
  $offZ = -$s * $mny * $STRETCH

  $puCls = $cls -replace '^MS_', 'MS_PU_'

  $defs += @"
Model $puCls
{
	Path "$path"
	Model 0 "$mdl"
	Skin 0 "$skin"
	Scale $([math]::Round($s,4)) $([math]::Round($s,4)) $([math]::Round($s,4))
	Offset $([math]::Round($offX,3)) $([math]::Round($offY,3)) $([math]::Round($offZ,3))
	AngleOffset $([math]::Round($angleOffset,2))
	PitchOffset $([math]::Round($pitchOffset,2))
	RollOffset $([math]::Round($rollOffset,2))
	PlacementCVars "ms_pu"
	FrameIndex $ANCHOR A 0 $rest
}
"@
  $defs  += ""
  $stubs += "class $puCls : MS_PickupModel {}"
  $map   += "`t`t`t`"$cls|$puCls`","

  $rows += [pscustomobject]@{
    Class   = $cls
    Family  = $fam
    Frame   = $rest
    RawLen  = [math]::Round($lenX,1)
    Target  = $targetLen
    Scale   = [math]::Round($s,3)
    Yaw     = [math]::Round($angleOffset,1)
    Pitch   = [math]::Round($pitchOffset,1)
    Roll    = [math]::Round($rollOffset,1)
    Lift    = [math]::Round($offZ,2)
    WideW   = [math]::Round(($mxz-$mnz)*$s,1)
    TallH   = [math]::Round(($mxy-$mny)*$s,1)
    Elong   = [math]::Round($lenX / [math]::Max(1e-6, [math]::Max($mxy-$mny, $mxz-$mnz)), 2)
    Ratio   = [math]::Round($ratio, 2)
    Fit     = $fitSrc
    Verts   = $n
  }

  if ($md3.Dropped.Count -gt 0) {
    $notes += "$cls -- ignored $($md3.Dropped.Count) collapsed surface(s) at frame ${rest}: $($md3.Dropped -join ', ')"
  }
}

# ---------------------------------------------------------------------------
# Flag anything the fit is not confident about, so the survey is a review
# document and not just a dump. A silent generator that quietly produced a
# sideways minigun would be worse than no generator.
# ---------------------------------------------------------------------------
foreach ($r in $rows) {
  if ($r.Fit -eq 'axis-aligned') {
    $notes += "CHECK $($r.Class) -- no dominant axis (l1/l2 = $($r.Ratio)), so it was NOT rotated, only resized; its own authored pose is what you will see"
  }
  if ($r.Fit -eq 'pca+eigen2') {
    $notes += "CHECK $($r.Class) -- authored near-vertical, so its up came from the second eigenvector rather than world up"
  }
  if ($r.Fit -eq 'pca' -and $r.Ratio -lt 3.0) {
    $notes += "CHECK $($r.Class) -- axis is only mildly dominant (l1/l2 = $($r.Ratio)); a fitted barrel this weak is worth an eyeball"
  }
  if ($r.Scale -gt 3.0 -or $r.Scale -lt 0.12) {
    $notes += "CHECK $($r.Class) -- scale $($r.Scale) is far from 1; the mesh is authored at an unusual size, not necessarily wrong"
  }
  if ([math]::Abs($r.Pitch) -gt 60) {
    $notes += "CHECK $($r.Class) -- pitch correction $($r.Pitch) deg is large; confirm it is not standing on its muzzle"
  }
  if ([math]::Abs($r.Roll) -gt 20) {
    $notes += "CHECK $($r.Class) -- roll correction $($r.Roll) deg is large; the mesh was authored banked"
  }
}

# ---------------------------------------------------------------------------
Set-Content -Path (Join-Path $gen 'pickups.modeldef') -Encoding utf8 -Value (
  @("// GENERATED by tools_gen_pickups.ps1 -- do not hand-edit, rerun instead.",
    "// Scale/Offset/rotations are solved from each mesh's rest-frame vertices.",
    "// Every block anchors on $ANCHOR A: see the disjoint-anchor note in the tool.",
    "") + $defs)

Set-Content -Path (Join-Path $gen 'pickups.stubs') -Encoding utf8 -Value (
  @("// GENERATED by tools_gen_pickups.ps1.") + ($stubs | Sort-Object))

# No trailing comma on the last row: ZScript's initialiser list will not take
# one, and pasting a list that ends in ",};" is a parse error, not a warning.
if ($map.Count -gt 0) { $map[$map.Count - 1] = $map[$map.Count - 1] -replace ',$', '' }
Set-Content -Path (Join-Path $gen 'pickups.shelf') -Encoding utf8 -Value (
  @("// GENERATED by tools_gen_pickups.ps1 -- hud donor class | pickup class.") + $map)

$rows | Sort-Object Family, Class | Export-Csv -NoTypeInformation -Encoding utf8 -Path (Join-Path $gen 'pickups.survey.csv')

$report = @()
$report += "ModelSwapper -- pickup model survey"
$report += "generated by tools_gen_pickups.ps1"
$report += ""
$report += "$($rows.Count) models fitted, $($notes.Count) notes."
$report += ""
$report += ($rows | Sort-Object Family, Class | Format-Table -AutoSize | Out-String -Width 200)
$report += ""
$report += "NOTES"
if ($notes.Count -eq 0) { $report += "  (none)" } else { foreach ($x in $notes) { $report += "  $x" } }
Set-Content -Path (Join-Path $gen 'pickups.survey.txt') -Encoding utf8 -Value $report

Write-Host ($report -join "`n")
