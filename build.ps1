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
$mb = [math]::Round((Get-Item $out).Length / 1MB, 1)
$n  = $z.Entries.Count
$z.Dispose()

Write-Host "ModelSwapper.pk3  --  $n entries, $mb MB"
Write-Host "  backslash entries : $bad"
Write-Host "  asset refs        : $refs checked, $miss unresolved"
if ($bad -gt 0 -or $miss -gt 0) { throw "package verification failed" }
