# Applies MoonFactory to a Chronicle checkout at the commit the patch was made against.
#   .\apply-moonfactory.ps1 -Chronicle C:\path\to\Chronicle
param(
    [Parameter(Mandatory = $true)][string]$Chronicle
)

$ErrorActionPreference = 'Stop'
$base = '6ec3b808dd8a9b15704cbce29e40be84591954ce'
$patch = Join-Path $PSScriptRoot 'moonfactory-chronicle.patch'
$kazarovPatch = Join-Path $PSScriptRoot 'moonfactory-kazarov.patch'
$kazarov = Join-Path $Chronicle 'tools\kazarov'

if (-not (Test-Path (Join-Path $Chronicle '.git'))) {
    throw "$Chronicle is not a Chronicle git checkout (clone it with --recurse-submodules first)."
}
if (git -C $Chronicle status --porcelain --untracked-files=no) {
    throw "$Chronicle has uncommitted changes; commit or stash them first."
}

git -C $Chronicle fetch --quiet origin
git -C $Chronicle checkout --quiet $base
if ($LASTEXITCODE -ne 0) { throw "Could not check out Chronicle commit $base." }
git -C $Chronicle submodule update --init --recursive

git -C $Chronicle apply --check --whitespace=nowarn $patch
if ($LASTEXITCODE -ne 0) { throw 'The patch does not apply cleanly to this checkout.' }
git -C $kazarov apply --check --whitespace=nowarn $kazarovPatch
if ($LASTEXITCODE -ne 0) { throw 'The Kazarov patch does not apply cleanly to tools\kazarov.' }
git -C $Chronicle apply --whitespace=nowarn $patch
if ($LASTEXITCODE -ne 0) { throw 'Applying the patch failed.' }
git -C $kazarov apply --whitespace=nowarn $kazarovPatch
if ($LASTEXITCODE -ne 0) { throw 'Applying the Kazarov patch failed.' }

Write-Host "MoonFactory applied to $Chronicle (Chronicle $base)."
Write-Host 'Next: put your disc image in rom/pal or rom/ntsc, then run build.bat windows-x64-release.'
