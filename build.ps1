# Package ModelSwapper.pk3.
#
# A pk3 is a zip, and zip entries must use forward slashes. Compress-Archive on
# Windows PowerShell writes BACKSLASHES, which GZDoom cannot read -- so this
# builds the archive entry by entry instead.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = $PSScriptRoot
$out  = Join-Path $root 'ModelSwapper.pk3'

# Everything that belongs in the pk3. Anything else in the repo (README, this
# script, .git) stays out.
$include = @('zscript.txt', 'modeldef', 'MENUDEF', 'CVARINFO', 'MAPINFO', 'KEYCONF')
$dirs    = @('zscript', 'models')   # no sprites: donors anchor on stock Doom sprite names

$files = @()
foreach ($f in $include) {
    $p = Join-Path $root $f
    if (Test-Path $p) { $files += Get-Item $p } else { Write-Warning "missing: $f" }
}
foreach ($d in $dirs) {
    $p = Join-Path $root $d
    if (Test-Path $p) { $files += Get-ChildItem $p -Recurse -File } else { Write-Warning "missing: $d/" }
}

$fs  = [System.IO.File]::Open($out, 'Create')
$zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
foreach ($f in $files) {
    $rel = ($f.FullName.Substring($root.Length + 1)) -replace '\\', '/'
    $e   = $zip.CreateEntry($rel, [System.IO.Compression.CompressionLevel]::Optimal)
    $st  = $e.Open()
    $b   = [System.IO.File]::ReadAllBytes($f.FullName)
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

Write-Host "ModelSwapper.pk3  --  $n entries, $mb MB"
Write-Host "  backslash entries : $bad"
Write-Host "  asset refs        : $refs checked, $miss unresolved"
Write-Host "  donors            : $($donors.Count), $($dupes.Count) duplicate, $($nostub.Count) unstubbed"
if ($bad -gt 0 -or $miss -gt 0 -or $dupes.Count -gt 0 -or $stubdup.Count -gt 0 -or $nostub.Count -gt 0) {
    throw "package verification failed"
}
