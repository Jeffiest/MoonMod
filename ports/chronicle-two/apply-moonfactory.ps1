#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ChronicleTwo,
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
$base = '9b7794d51dce6ed59fd56c0a343bb2ed8c3a1e55'
$kazarovBase = '25a4c5a89ae736517a467b5e05dea4894c255afc'
$patch = Join-Path $PSScriptRoot 'moonfactory-chronicle-two.patch'
$inputPatch = Join-Path $PSScriptRoot 'moonfactory-kazarov.patch'

function Invoke-Git([string]$Root, [string[]]$Arguments) {
    $result = & git -C $Root @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed in ${Root}:`n$($result -join "`n")"
    }
    return $result
}

$root = (Resolve-Path -LiteralPath $ChronicleTwo).Path
$top = Invoke-Git $root @('rev-parse', '--show-toplevel')
if ([IO.Path]::GetFullPath([string]$top) -ne [IO.Path]::GetFullPath($root)) {
    throw "$root must be the root of a Chronicle Two checkout."
}
foreach ($file in @($patch, $inputPatch)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing patch: $file" }
}

# Include untracked files and nested changes: neither checkout may contain work we could overwrite.
$dirty = Invoke-Git $root @('status', '--porcelain', '--untracked-files=all', '--ignore-submodules=none')
if ($dirty) { throw "Chronicle Two has local changes. Commit or stash them first.`n$($dirty -join "`n")" }

if ($CheckOnly) {
    if ((Invoke-Git $root @('rev-parse', 'HEAD')) -ne $base) {
        throw "CheckOnly requires Chronicle Two at $base; no files were changed."
    }
} else {
    & git -C $root cat-file -e "$base^{commit}" 2>$null
    if ($LASTEXITCODE -ne 0) { Invoke-Git $root @('fetch', 'origin', $base) | Out-Null }
    Invoke-Git $root @('checkout', '--detach', $base) | Out-Null
    Invoke-Git $root @('submodule', 'update', '--init', '--recursive') | Out-Null
}

$kazarov = Join-Path $root 'tools/kazarov'
if ((Invoke-Git $kazarov @('rev-parse', '--show-toplevel')) -ne ($kazarov -replace '\\', '/')) {
    throw 'Kazarov is not initialized. Run git submodule update --init --recursive.'
}
if ((Invoke-Git $kazarov @('rev-parse', 'HEAD')) -ne $kazarovBase) {
    throw "Kazarov must be at $kazarovBase."
}
if (Invoke-Git $kazarov @('status', '--porcelain', '--untracked-files=all')) {
    throw 'Kazarov has local changes. Commit or stash them first.'
}

# Preflight both patches before applying either one. This also catches untracked path collisions.
Invoke-Git $root @('apply', '--check', '--whitespace=nowarn', $patch) | Out-Null
Invoke-Git $kazarov @('apply', '--check', '--whitespace=nowarn', $inputPatch) | Out-Null
if ($CheckOnly) {
    Write-Host 'MoonFactory Chronicle Two and Kazarov patches both apply cleanly. No files changed.'
    return
}
Invoke-Git $root @('apply', '--whitespace=nowarn', $patch) | Out-Null
try {
    Invoke-Git $kazarov @('apply', '--whitespace=nowarn', $inputPatch) | Out-Null
} catch {
    Invoke-Git $root @('apply', '--reverse', '--whitespace=nowarn', $patch) | Out-Null
    throw
}
Write-Host "MoonFactory applied to Chronicle Two $base and Kazarov $kazarovBase."
Write-Host 'Next: put your PAL disc image in rom/pal and run build.bat windows-x64-release.'
