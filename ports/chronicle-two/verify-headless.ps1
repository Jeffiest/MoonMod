#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BuildDirectory,
    [ValidateRange(1, 256)][int]$Jobs = 12,
    [switch]$NoBuild,
    [switch]$StartupSmoke
)

$ErrorActionPreference = 'Stop'
$build = (Resolve-Path -LiteralPath $BuildDirectory).Path
if (-not (Test-Path -LiteralPath (Join-Path $build 'CMakeCache.txt'))) {
    throw 'Pass a configured Chronicle Two PC build directory with CT_BUILD_TESTS=ON.'
}
if (-not $NoBuild) {
    & cmake --build $build --target darkchronicle_tests --parallel $Jobs
    if ($LASTEXITCODE -ne 0) { throw 'Chronicle Two build failed.' }
}

# ctest runs each case in its own process, isolating native game globals.
$filter = '^MoonMod'
if ($StartupSmoke) { $filter += '|^Smoke.HeadlessFramesScreenshot$' }
$report = Join-Path $build 'moonfactory-tests.xml'
$previousData = $env:DC2_DATA
$previousSave = $env:DC2_SAVE
$testData = Join-Path $build 'moonfactory-native-fixture/data'
$testSave = Join-Path $build 'moonfactory-native-fixture/save'
New-Item -ItemType Directory -Path $testData, $testSave -Force | Out-Null
try {
    # Native fixtures seed their own state; never discover the player's extraction or save.
    $env:DC2_DATA = $testData
    $env:DC2_SAVE = $testSave
    & ctest --test-dir $build -R $filter --no-tests=error --output-on-failure --output-junit $report --parallel $Jobs
    if ($LASTEXITCODE -ne 0) { throw "MoonFactory verification failed; inspect $report." }
} finally {
    $env:DC2_DATA = $previousData
    $env:DC2_SAVE = $previousSave
}
Write-Host "MoonFactory Chronicle Two tests passed. Report: $report"
if (-not $StartupSmoke) {
    Write-Host 'Add -StartupSmoke to check two executable launches, Lua loading, persistence and screenshot creation (requires Vulkan).'
}
