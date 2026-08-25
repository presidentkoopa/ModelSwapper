# Package ModelSwapper.pk3.
#
# A pk3 is a zip, and zip entries must use forward slashes. Compress-Archive on
# Windows PowerShell writes BACKSLASHES, which GZDoom cannot read -- so this
# builds the archive entry by entry instead.

param(
    # Build the stock-GZDoom / QuestZDoom package instead of the desktop
    # one: zscript/static/RS_ForeignFork.zs is shipped in place of
    # zscript/RS_ForeignFork.zs, which is the ONLY file that differs.
    # Static models, no animation, no fork required.
    [switch]$Static
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = $PSScriptRoot
# The -REMAP suffix existed while the rebuilt engine lived in a second
# worktree beside the old one: two identically named pk3s in two folders is
# how a test session silently loads the wrong build and produces results that
# test nothing. That branch is now main and there is one tree, so the PCVR
# build takes the plain name again. The Quest build keeps a distinct one --
# it is a genuinely different artifact (static shim, no animation table) and
# must never be mistaken for the full build in a load order.
$out  = Join-Path $root $(if ($Static) { 'ModelSwapper-QUEST.pk3' } else { 'ModelSwapper.pk3' })

# Everything that belongs in the pk3. Anything else in the repo (README, this
# script, .git) stays out.
$include = @('zscript.txt', 'modeldef', 'MENUDEF', 'CVARINFO', 'MAPINFO', 'KEYCONF')
# Donors still anchor on stock Doom sprite names and ship no sprites of their
# own. sprites/ carries exactly one thing: RSB0, the ballistic round. That name
# is ours, collides with nothing stock, and overrides nothing a mod defines.
# maps/ is one map, MSZOO, under a name nothing else uses -- the model zoo.
$dirs    = @('zscript', 'models', 'sprites', 'maps')

$files = @()
foreach ($f in $include) {
    $p = Join-Path $root $f
    if (Test-Path $p) { $files += Get-Item $p } else { Write-Warning "missing: $f" }
}
foreach ($d in $dirs) {
    $p = Join-Path $root $d
    if (Test-Path $p) { $files += Get-ChildItem $p -Recurse -File } else { Write-Warning "missing: $d/" }
}

# zscript/static/ is the alternate fork shim, never shipped as itself --
# it is either substituted for zscript/RS_ForeignFork.zs (-Static) or
# left out entirely. Two RS_Fork classes in one pk3 would not compile.
$files = $files | Where-Object { $_.FullName -notmatch '\\zscript\\static\\' }

$fs  = [System.IO.File]::Open($out, 'Create')
$zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
foreach ($f in $files) {
    $rel = ($f.FullName.Substring($root.Length + 1)) -replace '\\', '/'
    $src = $f.FullName

    # The one substitution that makes the static build a build flag
    # rather than a second codebase.
    if ($Static -and $rel -eq 'zscript/RS_ForeignFork.zs') {
        $src = Join-Path $root 'zscript/static/RS_ForeignFork.zs'
    }

    $b = [System.IO.File]::ReadAllBytes($src)

    # PlacementCVars is a fork-only MODELDEF property, and an unrecognised
    # property is a FATAL parse error in the stock parser rather than something
    # it skips -- shipping the line to QuestZDoom would take the whole pk3 down
    # on load, not just the sliders. Stripped as text rather than kept in a
    # second copy of modeldef, for the same reason the fork shim is swapped and
    # not duplicated: one source, one place to edit.
    if ($Static -and $rel -eq 'modeldef') {
        # Line based, because a regex full of backslashes is the one thing
        # that does not survive being written by a generator. Splitting on LF
        # only leaves any CR attached to the line it came from, so the file
        # comes out of this with its line endings unchanged.
        $keep = ([System.Text.Encoding]::UTF8.GetString($b) -split "`n") |
                Where-Object { $_ -notmatch 'PlacementCVars' }
        $b    = [System.Text.Encoding]::UTF8.GetBytes(($keep -join "`n"))
    }

    $e   = $zip.CreateEntry($rel, [System.IO.Compression.CompressionLevel]::Optimal)
    $st  = $e.Open()
    $st.Write($b, 0, $b.Length)
    $st.Close()
}
$zip.Dispose()
$fs.Close()

# Verify: forward slashes only, and every modeldef asset reference resolves.
$z     = [System.IO.Compression.ZipFile]::OpenRead($out)
$names = @{}
$z.Entries | ForEach-Object { $names[$_.FullName.ToLower()] = $true }

$bad = ($z.Entries | Where-Object { $_.FullName -match '\\' }).Count

$md = $z.Entries | Where-Object { $_.FullName -eq 'modeldef' }
$sr = New-Object System.IO.StreamReader($md.Open())
$txt = $sr.ReadToEnd(); $sr.Close()

$path = ''; $refs = 0; $miss = 0
foreach ($line in ($txt -split "`n")) {
    if ($line -match '^\s*Path\s+"([^"]+)"') {
        $path = $matches[1].Replace('\', '/').TrimEnd('/')
    }
    elseif ($line -match '^\s*(?:Model|Skin)\s+\d+\s+"([^"]+)"') {
        $refs++
        $key = ($path + '/' + $matches[1]).ToLower()
        if (-not $names.ContainsKey($key)) { Write-Warning "unresolved asset: $key"; $miss++ }
    }
}
# Donor consistency. A duplicate Model block shipped once as a duplicate
# ZScript stub and refused to compile at all; a donor named in the shelf but
# absent from modeldef is silently dropped instead, which is worse because it
# looks like it worked.
$md      = ($z.Entries | Where-Object { $_.FullName -eq 'modeldef' })
$sr2     = New-Object System.IO.StreamReader($md.Open())
$mdtxt   = $sr2.ReadToEnd(); $sr2.Close()
$donors  = [regex]::Matches($mdtxt, '(?m)^Model\s+(\S+)') | ForEach-Object { $_.Groups[1].Value }
$dupes   = $donors | Group-Object | Where-Object { $_.Count -gt 1 }

$zsE     = $z.Entries | Where-Object { $_.FullName -eq 'zscript.txt' }
$sr3     = New-Object System.IO.StreamReader($zsE.Open())
$zstxt   = $sr3.ReadToEnd(); $sr3.Close()
$stubs   = [regex]::Matches($zstxt, '(?m)^class\s+(\S+)\s*:') | ForEach-Object { $_.Groups[1].Value }
$stubdup = $stubs | Group-Object | Where-Object { $_.Count -gt 1 }
$nostub  = $donors | Where-Object { $stubs -notcontains $_ }

foreach ($d in $dupes)   { Write-Warning "duplicate Model block: $($d.Name)" }
foreach ($d in $stubdup) { Write-Warning "duplicate class stub: $($d.Name)" }
foreach ($d in $nostub)  { Write-Warning "donor with no class stub: $d" }

$mb = [math]::Round((Get-Item $out).Length / 1MB, 1)
$n  = $z.Entries.Count
$z.Dispose()

Write-Host "$(Split-Path $out -Leaf)  --  $n entries, $mb MB$(if ($Static) { '  [STATIC / stock GZDoom]' })"
Write-Host "  backslash entries : $bad"
Write-Host "  asset refs        : $refs checked, $miss unresolved"
Write-Host "  donors            : $($donors.Count), $($dupes.Count) duplicate, $($nostub.Count) unstubbed"
if ($bad -gt 0 -or $miss -gt 0 -or $dupes.Count -gt 0 -or $stubdup.Count -gt 0 -or $nostub.Count -gt 0) {
    throw "package verification failed"
}
