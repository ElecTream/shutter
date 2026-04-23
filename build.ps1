#!/usr/bin/env pwsh
# Shutter release builder.
# Bumps patch version in pubspec.yaml, builds split-per-ABI release APKs,
# renames arm64-v8a as shutter-<ver>.apk, archives prior v8a builds,
# stores other ABIs alongside.
#
# Usage:
#   .\build.ps1              # bump patch, build, archive
#   .\build.ps1 -NoBump      # rebuild current version (overwrites)
#   .\build.ps1 -Bump minor  # bump minor (resets patch)
#   .\build.ps1 -Bump major  # bump major (resets minor + patch)

[CmdletBinding()]
param(
    [ValidateSet('patch', 'minor', 'major')]
    [string]$Bump = 'patch',
    [switch]$NoBump
)

$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

$pubspec = Join-Path $PSScriptRoot 'pubspec.yaml'
if (-not (Test-Path $pubspec)) { throw "pubspec.yaml not found at $pubspec" }

# --- Read current version ---
$content = Get-Content $pubspec -Raw
if ($content -notmatch '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?\s*$') {
    throw "Could not find 'version: X.Y.Z' in pubspec.yaml"
}
$major = [int]$Matches[1]
$minor = [int]$Matches[2]
$patch = [int]$Matches[3]
$buildNum = if ($Matches[4]) { [int]$Matches[4] } else { $null }
$current = "$major.$minor.$patch"

# --- Compute next version ---
if ($NoBump) {
    $next = $current
} else {
    switch ($Bump) {
        'patch' { $patch++ }
        'minor' { $minor++; $patch = 0 }
        'major' { $major++; $minor = 0; $patch = 0 }
    }
    $next = "$major.$minor.$patch"
}

# Auto-increment build number if pubspec had +N suffix, else just X.Y.Z
$newVersionLine = if ($buildNum -ne $null) {
    $nextBuild = if ($NoBump) { $buildNum } else { $buildNum + 1 }
    "version: $next+$nextBuild"
} else {
    "version: $next"
}

Write-Host "Version: $current -> $next" -ForegroundColor Cyan

# --- Write pubspec.yaml back ---
if (-not $NoBump) {
    $updated = [regex]::Replace(
        $content,
        '(?m)^version:\s*\d+\.\d+\.\d+(?:\+\d+)?\s*$',
        $newVersionLine
    )
    Set-Content -Path $pubspec -Value $updated -NoNewline:$false
}

# --- Prepare output dirs ---
$releases = Join-Path $PSScriptRoot 'releases'
$archive  = Join-Path $releases 'archive'
$abis     = Join-Path $releases 'abis'
New-Item -ItemType Directory -Force -Path $releases, $archive, $abis | Out-Null

# --- Archive existing v8a builds (top-level shutter-*.apk) ---
Get-ChildItem -Path $releases -Filter 'shutter-*.apk' -File -ErrorAction SilentlyContinue |
    ForEach-Object {
        $dest = Join-Path $archive $_.Name
        if (Test-Path $dest) { Remove-Item $dest -Force }
        Move-Item $_.FullName $dest
        Write-Host "  archived $($_.Name)" -ForegroundColor DarkGray
    }

# --- Build ---
Write-Host "Running flutter build apk --split-per-abi --release" -ForegroundColor Cyan
& flutter build apk --split-per-abi --release
if ($LASTEXITCODE -ne 0) { throw "flutter build failed (exit $LASTEXITCODE)" }

# --- Rename + copy outputs ---
$out = Join-Path $PSScriptRoot 'build\app\outputs\flutter-apk'
$map = @{
    'app-arm64-v8a-release.apk'   = Join-Path $releases "shutter-$next.apk"
    'app-armeabi-v7a-release.apk' = Join-Path $abis     "shutter-$next-armeabi-v7a.apk"
    'app-x86_64-release.apk'      = Join-Path $abis     "shutter-$next-x86_64.apk"
}

foreach ($src in $map.Keys) {
    $srcPath = Join-Path $out $src
    if (-not (Test-Path $srcPath)) {
        Write-Warning "Missing expected output: $src"
        continue
    }
    Copy-Item $srcPath $map[$src] -Force
    $size = [math]::Round((Get-Item $map[$src]).Length / 1MB, 1)
    Write-Host "  $(Split-Path $map[$src] -Leaf)  ($size MB)" -ForegroundColor Green
}

Write-Host ""
Write-Host "Done. shutter-$next.apk in $releases" -ForegroundColor Green

# --- Push to phone ---
$targetApk = Join-Path $releases "shutter-$next.apk"
if (Test-Path $targetApk) {
    Write-Host "Pushing $(Split-Path $targetApk -Leaf) to phone..." -ForegroundColor Cyan
    & push-apk $targetApk
    if ($LASTEXITCODE -ne 0) { Write-Warning "push-apk exit $LASTEXITCODE (build ok)" }
} else {
    Write-Warning "No APK at $targetApk; skipping push."
}
