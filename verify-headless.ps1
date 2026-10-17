#requires -Version 7.0
[CmdletBinding()]
param(
    [switch]$NoBuild,
    [switch]$ManagerUiSmoke,
    [switch]$RetailGameplaySmoke,
    [switch]$RetailItemSmoke,
    [switch]$RetailDungeonSmoke,
    [switch]$RetailCharacterSmoke,
    [switch]$RetailGeoramaSmoke,
    [switch]$RetailLocationSmoke,
    [ValidateRange(1, 256)][int]$Jobs = 12,
    [ValidateRange(5, 3600)][int]$ProcessTimeoutSeconds = 120,
    [string]$ChronicleDataRoot,
    [string]$ChronicleTwoDataRoot
)

$ErrorActionPreference = 'Stop'

$sharedRetailFixtureModes = @()
if ($RetailGameplaySmoke) { $sharedRetailFixtureModes += '-RetailGameplaySmoke' }
if ($RetailItemSmoke) { $sharedRetailFixtureModes += '-RetailItemSmoke' }
if ($RetailDungeonSmoke) { $sharedRetailFixtureModes += '-RetailDungeonSmoke' }
if ($RetailCharacterSmoke) { $sharedRetailFixtureModes += '-RetailCharacterSmoke' }
if ($RetailGeoramaSmoke) { $sharedRetailFixtureModes += '-RetailGeoramaSmoke' }
if ($sharedRetailFixtureModes.Count -gt 1) {
    throw "Retail gameplay, item, dungeon, character, and Georama smoke modes share one fixture per port. Run one of these modes per verifier invocation: $($sharedRetailFixtureModes -join ', ')."
}

function Invoke-BoundedProcess([string]$Executable, [string[]]$Arguments, [string]$WorkingDirectory, [int]$TimeoutSeconds) {
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Executable
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) { [void]$startInfo.ArgumentList.Add([string]$argument) }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $finished = $process.WaitForExit($TimeoutSeconds * 1000)
    if (-not $finished) {
        try { $process.Kill($true) } catch { }
        $process.WaitForExit()
    }
    $output = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
    if (-not $finished) {
        $output += "`nMoonFactory verification timed out after $TimeoutSeconds seconds; the child process tree was stopped.`n"
    }
    $exitCode = if ($finished) { $process.ExitCode } else { 124 }
    $process.Dispose()
    return [pscustomobject]@{ exit_code = $exitCode; timed_out = -not $finished; output = $output }
}

function Get-ApiCatalogCoverageError($Catalog) {
    $operations = @($Catalog.operations)
    $domains = @($Catalog.domains)
    if ($operations.Count -eq 0) { return 'the catalog contains no operations' }
    if ($operations.Count -ne [int]$Catalog.operation_count) { return 'operation_count does not match operations' }
    if (@($operations | Where-Object { [string]::IsNullOrWhiteSpace($_.path) -or [string]::IsNullOrWhiteSpace($_.domain) }).Count -gt 0) {
        return 'an API operation has an empty path or domain'
    }
    if (@($operations | Where-Object { $_.status -notin @('supported', 'unsupported') }).Count -gt 0) {
        return 'an API operation has an invalid support status'
    }
    if (@($operations | Where-Object { $_.status -eq 'unsupported' -and [string]::IsNullOrWhiteSpace($_.reason) }).Count -gt 0) {
        return 'an unsupported API operation has no reason'
    }

    $supportedCount = @($operations | Where-Object status -eq 'supported').Count
    $unsupportedCount = @($operations | Where-Object status -eq 'unsupported').Count
    if ($supportedCount -ne [int]$Catalog.supported_count -or $unsupportedCount -ne [int]$Catalog.unsupported_count) {
        return 'catalog support totals do not match operations'
    }

    $groups = @($operations | Group-Object -Property { $_.domain })
    if ($groups.Count -ne $domains.Count) { return 'domain summary does not cover each API domain exactly once' }
    foreach ($group in $groups) {
        if ([string]::IsNullOrWhiteSpace($group.Name)) { return 'an API operation has an empty domain' }
        $summary = @($domains | Where-Object domain -eq $group.Name)
        if ($summary.Count -ne 1) { return "domain summary is missing or duplicates '$($group.Name)'" }
        $domainSupported = @($group.Group | Where-Object status -eq 'supported').Count
        $domainUnsupported = @($group.Group | Where-Object status -eq 'unsupported').Count
        if ([int]$summary[0].operation_count -ne $group.Count -or
            [int]$summary[0].supported_count -ne $domainSupported -or
            [int]$summary[0].unsupported_count -ne $domainUnsupported) {
            return "domain summary totals do not match '$($group.Name)' operations"
        }
    }

    $verificationDocPath = Join-Path $PSScriptRoot 'docs\VERIFICATION.md'
    if (-not (Test-Path -LiteralPath $verificationDocPath -PathType Leaf)) {
        return 'the API-domain verification matrix is missing'
    }
    $matrixDomains = @(
        foreach ($line in Get-Content -LiteralPath $verificationDocPath) {
            if ($line -match '^\| `([^`]+)` \|') { $Matches[1] }
        }
    )
    if ($matrixDomains.Count -ne @($matrixDomains | Sort-Object -Unique).Count) {
        return 'the API-domain verification matrix contains duplicate domains'
    }
    $catalogDomains = @($groups | ForEach-Object Name | Sort-Object)
    $missingDomains = @($catalogDomains | Where-Object { $_ -notin $matrixDomains })
    $extraDomains = @($matrixDomains | Where-Object { $_ -notin $catalogDomains })
    if ($missingDomains.Count -gt 0 -or $extraDomains.Count -gt 0) {
        return 'the API-domain verification matrix does not match the catalog domains'
    }
    return $null
}

function Get-NormalizedMarkerLines([string]$Path, [string[]]$Prefixes) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $markers = [System.Collections.Generic.List[string]]::new()
    foreach ($line in Get-Content -LiteralPath $Path) {
        foreach ($prefix in $Prefixes) {
            $index = $line.IndexOf($prefix, [StringComparison]::Ordinal)
            if ($index -ge 0) {
                $markers.Add($line.Substring($index).Trim())
                break
            }
        }
    }
    return $markers.ToArray()
}

if (-not $ChronicleDataRoot) {
    if ($env:DC_DATA) { $ChronicleDataRoot = $env:DC_DATA }
    else {
        $candidate = Join-Path $env:LOCALAPPDATA 'chronicle\data'
        if ((Test-Path -LiteralPath (Join-Path $candidate 'data.hd2') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $candidate 'gedit\s13\mapinfo.cfg') -PathType Leaf)) {
            $ChronicleDataRoot = $candidate
        }
    }
}
if (-not $ChronicleTwoDataRoot) {
    if ($env:DC2_DATA) { $ChronicleTwoDataRoot = $env:DC2_DATA }
    else {
        $candidate = Join-Path $env:LOCALAPPDATA 'chronicletwo\data'
        $candidateParent = Split-Path -Parent $candidate
        if ((Test-Path -LiteralPath (Join-Path $candidate 'manifest.json') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $candidateParent 'port_data\manifest.json') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $candidateParent 'data.json') -PathType Leaf)) {
            $ChronicleTwoDataRoot = $candidate
        }
    }
}
foreach ($configuredRoot in @(
    @{ Name = 'Chronicle'; Path = $ChronicleDataRoot },
    @{ Name = 'ChronicleTwo'; Path = $ChronicleTwoDataRoot }
)) {
    if ($configuredRoot.Path) {
        if (-not (Test-Path -LiteralPath $configuredRoot.Path -PathType Container)) {
            throw "$($configuredRoot.Name) data root does not exist: $($configuredRoot.Path)"
        }
        if ($configuredRoot.Name -eq 'Chronicle') { $ChronicleDataRoot = (Resolve-Path -LiteralPath $configuredRoot.Path).Path }
        else { $ChronicleTwoDataRoot = (Resolve-Path -LiteralPath $configuredRoot.Path).Path }
    }
}
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$overallExitCode = 0
$portReports = [System.Collections.Generic.List[object]]::new()
$pythonCases = [System.Collections.Generic.List[object]]::new()
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    throw 'Python 3 is required to run the ChronicleTwo-Script bridge verification.'
}
$toolTests = Join-Path $PSScriptRoot 'tools\tests'
Write-Host 'Running Moon Factory Python verification (bridge scanner, package CLI, examples)...'
$pythonOutput = @(& $python.Source -m unittest discover -s $toolTests -p 'test_*.py' -v 2>&1 | ForEach-Object { $_.ToString() })
$pythonExitCode = $LASTEXITCODE
foreach ($line in $pythonOutput) {
    Write-Host $line
    if ($line -match '^(test_\S+) \(([^)]+)\) \.\.\. (ok|FAIL|ERROR)$') {
        $pythonCases.Add([ordered]@{
            name = $Matches[2]
            status = if ($Matches[3] -eq 'ok') { 'passed' } else { 'failed' }
        })
    }
}
if ($pythonExitCode -ne 0 -and $overallExitCode -eq 0) { $overallExitCode = $pythonExitCode }

$cmake = 'C:\Program Files\CMake\bin\cmake.exe'
if (-not (Test-Path -LiteralPath $cmake)) {
    $cmakeCommand = Get-Command cmake -ErrorAction SilentlyContinue
    if ($cmakeCommand) { $cmake = $cmakeCommand.Source }
}
if (-not (Test-Path -LiteralPath $cmake)) {
    throw 'Could not find CMake. Install CMake or add it to PATH.'
}

$ports = @(
    @{
        Name = 'Chronicle'
        Directory = 'Chronicle'
        BuildDirectory = 'port\build\moonmod-api-verification'
        NativeTestExecutable = 'darkcloud_tests.exe'
    },
    @{
        Name = 'ChronicleTwo'
        Directory = 'ChronicleTwo'
        BuildDirectory = 'port\build\moonmod-api-verification'
        NativeTestExecutable = 'darkchronicle_tests.exe'
    }
)

Write-Host 'Checking MoonFactory canonical C++ source parity across ports...'
$canonicalFiles = Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'src'), (Join-Path $PSScriptRoot 'include\moonmod') -File
foreach ($canonicalFile in $canonicalFiles) {
    $canonicalHash = (Get-FileHash -LiteralPath $canonicalFile.FullName).Hash
    $isSource = $canonicalFile.DirectoryName.EndsWith('\src', [System.StringComparison]::OrdinalIgnoreCase)
    foreach ($port in $ports) {
        $portSubdir = if ($isSource) { 'port\src\moonmod' } else { 'port\include\moonmod' }
        $portFile = Join-Path (Join-Path $workspace $port.Directory) (Join-Path $portSubdir $canonicalFile.Name)
        if (-not (Test-Path -LiteralPath $portFile -PathType Leaf)) {
            throw "Missing shared MoonFactory file in $($port.Name): $portFile"
        }
        $portHash = (Get-FileHash -LiteralPath $portFile).Hash
        if ($canonicalHash -ne $portHash) {
            throw "Shared MoonFactory file drift detected for $($canonicalFile.Name) in $($port.Name): $portFile"
        }
    }
}

foreach ($port in $ports) {
    $gameRoot = Join-Path $workspace $port.Directory
    $buildDirectory = Join-Path $gameRoot $port.BuildDirectory
    if (-not (Test-Path -LiteralPath $gameRoot)) {
        throw "Missing game checkout: $gameRoot"
    }
    if (-not $NoBuild) {
        $buildScript = Join-Path $gameRoot 'tools\windows\build.ps1'
        if (-not (Test-Path -LiteralPath $buildScript)) {
            throw "Missing build script: $buildScript"
        }
        Write-Host "Building $($port.Name) MoonFactory verification targets..."
        & $buildScript -Root $gameRoot -BuildDirectory $buildDirectory -Tests -Jobs $Jobs
        if ($LASTEXITCODE -ne 0) {
            $portReports.Add([ordered]@{
                name = $port.Name
                status = 'build_failed'
                native_tests = $null
                headless_smoke = $null
                headless_preflight = $null
                api_catalog = $null
            })
            if ($overallExitCode -eq 0) { $overallExitCode = $LASTEXITCODE }
            continue
        }
    }
    if (-not (Test-Path -LiteralPath $buildDirectory)) {
        throw "Missing build directory: $buildDirectory (run without -NoBuild first)"
    }

    $nativeTest = Join-Path $buildDirectory $port.NativeTestExecutable
    if (-not (Test-Path -LiteralPath $nativeTest)) {
        throw "Missing native test executable: $nativeTest (build with -Tests first)"
    }
    Write-Host "Running $($port.Name) MoonFactory native verification..."
    $nativeRun = Invoke-BoundedProcess $nativeTest @('--gtest_filter=MoonMod*.*:EventScriptHooks.*:DataRead.NativeResourceOverride*:PlatformPad.TriggerAxisNormalization') $workspace $ProcessTimeoutSeconds
    $nativeOutput = @($nativeRun.output -split "`r?`n")
    $nativeExitCode = $nativeRun.exit_code
    foreach ($line in $nativeOutput) { Write-Host $line }
    $nativeCases = [System.Collections.Generic.List[object]]::new()
    foreach ($line in $nativeOutput) {
        if ($line -match '^\[ RUN      \] (.+)$') {
            $nativeCases.Add([ordered]@{ name = $Matches[1]; status = 'not_run' })
        } elseif ($line -match '^\[       OK \] (.+?) \(\d+ ms\)$') {
            $case = $nativeCases | Where-Object name -eq $Matches[1] | Select-Object -Last 1
            if ($null -ne $case) { $case.status = 'passed' }
        } elseif ($line -match '^\[  FAILED  \] (.+?) \(\d+ ms\)$') {
            $case = $nativeCases | Where-Object name -eq $Matches[1] | Select-Object -Last 1
            if ($null -ne $case) { $case.status = 'failed' }
        }
    }
    $nativePassed = @($nativeCases | Where-Object status -eq 'passed').Count
    $nativeFailed = @($nativeCases | Where-Object status -eq 'failed').Count
    if ($nativeExitCode -ne 0 -and $overallExitCode -eq 0) { $overallExitCode = $nativeExitCode }

    $smokeStatus = 'not_run'
    $preflightStatus = 'not_run'
    $apiCatalog = $null
    $preflightReport = $null
    $headlessDeterminism = [ordered]@{
        status = 'not_run'
        run_count = 0
        marker_count = 0
        normalized_reports = @()
        error = $null
        note = 'Each synthetic headless probe is repeated from two clean roots; stable API and feature markers must match.'
    }
    $retailDataSmoke = [ordered]@{
        status = 'not_configured'
        data_root = $null
        exit_code = $null
        timed_out = $false
        frames = 120
        phase = 'startup'
        capture_validated = $false
        screenshot = $null
        log = $null
    }
    $managerUiSmokeReport = [ordered]@{
        status = if ($ManagerUiSmoke -and $port.Name -in @('Chronicle', 'ChronicleTwo')) { 'not_configured' }
                 elseif ($port.Name -in @('Chronicle', 'ChronicleTwo')) { 'not_requested' }
                 else { 'not_applicable' }
        fixture_ready_markers = @()
        fixture_errors = @()
        data_root = $null
        exit_code = $null
        timed_out = $false
        frames = if ($port.Name -eq 'Chronicle') { 600 } else { 1100 }
        screenshot = $null
        log = $null
        note = 'Launches the in-game mod manager Journal with two enabled sample quest packages and captures the 1280x720 panel.'
    }
    $retailLocationSmokeReport = [ordered]@{
        status = if ($RetailLocationSmoke -and $port.Name -in @('Chronicle', 'ChronicleTwo')) { 'not_configured' }
                 elseif ($port.Name -in @('Chronicle', 'ChronicleTwo')) { 'not_requested' }
                 else { 'not_applicable' }
        location_id = $null
        source_map_id = $null
        texture_source_map = $null
        reused_native_assets = @()
        map_script_probe = 'not_run'
        registered_map_index = $null
        queued_marker = $null
        loaded_marker = $null
        return_queued_marker = $null
        returned_marker = $null
        data_root = $null
        exit_code = $null
        entry_exit_code = $null
        timed_out = $false
        entry_screenshot = $null
        return_screenshot = $null
        screenshot = $null
        entry_log = $null
        log = $null
        note = 'Retail-data map registration, entry, loading, and return proof.'
    }
    $retailGameplay = [ordered]@{
        status = if ($RetailGameplaySmoke -or $RetailItemSmoke -or ($RetailCharacterSmoke -and $port.Name -in @('Chronicle', 'ChronicleTwo')) -or ($RetailGeoramaSmoke -and $port.Name -in @('Chronicle', 'ChronicleTwo'))) { 'not_configured' } else { 'not_requested' }
        checkpoint = $null
        data_root = $null
        exit_code = $null
        timed_out = $false
        frames = $null
        input_script = $null
        capture_validated = $false
        screenshot = $null
        log = $null
    }
    $retailItemSmokeReport = [ordered]@{
        status = if ($RetailItemSmoke) { 'not_configured' } else { 'not_requested' }
        mod_id = 'moonfactory.retail-item-probe'
        verification_marker = $null
        item_capacity_marker = $null
        weapon_verification_marker = $null
        item_given_quest_marker = $null
        weapon_quest_reward_marker = $null
        item_removed_quest_marker = $null
        native_item_pickup_marker = $null
        enemy_spawned_event_marker = $null
        enemy_defeat_event_marker = $null
        enemy_defeat_quest_marker = $null
        enemy_defeat_queued_marker = $null
        error_lines = @()
        screenshot = $null
        log = $null
    }
    $retailGeoramaSmokeReport = [ordered]@{
        status = if ($RetailGeoramaSmoke -and $port.Name -in @('Chronicle', 'ChronicleTwo')) { 'not_configured' } else { 'not_applicable' }
        registration_marker = $null
        placement_marker = $null
        removal_marker = $null
        initial_stock_hook = $null
        screenshot = $null
        log = $null
        note = if ($port.Name -eq 'ChronicleTwo') {
            'Uses a disposable save and test-only built stock to verify a Lua-registered data-only Georama variant is materialized by the retail map loader, placed and removed through native edit routines, and read back from the town layout. Visual persistence after process reload and compatibility with player saves remain unverified.'
        } elseif ($port.Name -eq 'Chronicle') {
            'Uses a disposable save to register a solid data-only variant in an appended native editor slot, then place and remove it through the native editor routines with saved-layout readback. The variant inherits a retail template model and collision; custom geometry, visual persistence after process reload, and compatibility with player saves remain unverified.'
        } else {
            'Uses a disposable save and test-only initial stock. The game native editor methods place and remove the piece; authored Georama definitions and retail save compatibility remain unverified.'
        }
    }
    $retailDungeonSmokeReport = [ordered]@{
        status = if (($RetailItemSmoke -and $port.Name -eq 'ChronicleTwo') -or
            ($RetailDungeonSmoke -and $port.Name -eq 'Chronicle')) { 'not_configured' } else { 'not_applicable' }
        dungeon_id = if ($port.Name -eq 'Chronicle') { 'moonfactory.retail-dungeon-probe:moon-vault' }
                     else { 'moonfactory.retail-item-probe:retail-moon-vault' }
        floor_id = $null
        native_floor_id = $null
        context = $null
        verification_marker = $null
        camera_verification_marker = $null
        screenshot = $null
        log = $null
    }
    $retailCharacterSmokeReport = [ordered]@{
        status = if ($RetailCharacterSmoke -and $port.Name -in @('Chronicle', 'ChronicleTwo')) { 'not_configured' } else { 'not_applicable' }
        character_id = 'moonfactory.retail-character-probe:retail-sentinel'
        entity_handle = $null
        verification_marker = $null
        dungeon_floor_marker = $null
        native_floor_id = $null
        model_asset_path = $null
        model_verification_marker = $null
        model_replacement_verification_marker = $null
        overlay_registration_marker = $null
        enemy_spawned_event_marker = $null
        enemy_defeat_quest_marker = $null
        enemy_defeat_queued_marker = $null
        combat_formula_verification_marker = $null
        skill_damage_bonus_verification_marker = $null
        animation_play_verification_marker = $null
        animation_stop_verification_marker = $null
        animation_despawn_cleanup_verification_marker = $null
        runtime_errors = @()
        screenshot = $null
        log = $null
    }
    $retailPhysicsSmokeReport = [ordered]@{
        status = if ($RetailCharacterSmoke -and $port.Name -in @('Chronicle', 'ChronicleTwo')) { 'not_configured' } else { 'not_applicable' }
        operation = 'physics.velocity_set'
        verification_marker = $null
        screenshot = $null
        log = $null
    }
    $retailPhysicsQuerySmokeReport = [ordered]@{
        status = if ($RetailCharacterSmoke -and $port.Name -in @('Chronicle', 'ChronicleTwo')) { 'not_configured' } else { 'not_applicable' }
        operation = 'physics.query'
        verification_marker = $null
        semantics = 'Sphere query over live monster actor origins; does not test collision geometry.'
        screenshot = $null
        log = $null
    }

    if ($port.Name -eq 'Chronicle') {
        Write-Host 'Running Chronicle executable MoonFactory Lua preflight...'
        $preflightRoot = Join-Path $buildDirectory 'smoke-preflight-fixture'
        $preflightScript = Join-Path $gameRoot 'port\src\tests\smoke_headless_preflight.cmake'
        $gameExecutable = Join-Path $buildDirectory 'darkcloud.exe'
        $preflightOutput = @(& $cmake "-DEXE=$gameExecutable" "-DROOT=$preflightRoot" -P $preflightScript 2>&1 | ForEach-Object { $_.ToString() })
        $preflightExitCode = $LASTEXITCODE
        foreach ($line in $preflightOutput) { Write-Host $line }
        if ($preflightExitCode -eq 0) {
            $preflightStatus = 'passed'
            $smokeStatus = 'blocked_missing_game_data'
        } else {
            $preflightStatus = 'failed'
            $smokeStatus = 'failed_preflight'
            if ($overallExitCode -eq 0) { $overallExitCode = $preflightExitCode }
        }
        $preflightLogPath = Join-Path $preflightRoot 'preflight.log'
        $apiOperations = [System.Collections.Generic.List[object]]::new()
        if (Test-Path -LiteralPath $preflightLogPath) {
            foreach ($line in Get-Content -LiteralPath $preflightLogPath) {
                if ($line -match 'MOONFACTORY_PREFLIGHT_API\|([^|]+)\|(supported|unsupported)\|(.*)$') {
                    $path = $Matches[1]
                    $domain = ($path -split '\.', 2)[0]
                    $apiOperations.Add([ordered]@{
                        path = $path
                        domain = $domain
                        status = $Matches[2]
                        reason = $Matches[3]
                    })
                }
            }
            if ($apiOperations.Count -gt 0) {
                $apiCatalog = [ordered]@{
                    report = $preflightLogPath
                    operation_count = $apiOperations.Count
                    supported_count = @($apiOperations | Where-Object status -eq 'supported').Count
                    unsupported_count = @($apiOperations | Where-Object status -eq 'unsupported').Count
                    domains = @($apiOperations | Group-Object -Property { $_.domain } | Sort-Object Name | ForEach-Object {
                        [ordered]@{
                            domain = $_.Name
                            operation_count = $_.Count
                            supported_count = @($_.Group | Where-Object status -eq 'supported').Count
                            unsupported_count = @($_.Group | Where-Object status -eq 'unsupported').Count
                        }
                    })
                    operations = @($apiOperations)
                }
            } else {
                $preflightStatus = 'failed_missing_api_catalog'
                $smokeStatus = 'failed_preflight'
                if ($overallExitCode -eq 0) { $overallExitCode = 1 }
            }
        }
        $preflightReport = [ordered]@{
            status = $preflightStatus
            executable = $gameExecutable
            log = $preflightLogPath
            note = 'The Lua runtime and API catalog load before retail game startup; the fixture verifies exported Lua function discovery, invocation, and removal; skill-tree registration, prerequisite gating, rank changes, and reads; native monster model resolution; procedural native dungeon floors through both API names; dungeons.list/get; and the locations.list no-save path. The assetless fixture then stops at the first required retail resource.'
        }
    } elseif ($port.Name -eq 'ChronicleTwo') {
        Write-Host 'Running ChronicleTwo executable headless smoke...'
        $smokeRoot = Join-Path $buildDirectory 'smoke-fixture'
        $smokeScript = Join-Path $buildDirectory 'port\src\tests\smoke_headless.cmake'
        $gameExecutable = Join-Path $buildDirectory 'darkchronicle.exe'
        $emptyDataFixture = Join-Path $gameRoot 'port\src\tests\cmake\empty_data.cmake'
        $dataVersionSource = Join-Path $gameRoot 'tools\kazarov\data_version.json'
        $env:DC2_SAVE = Join-Path $smokeRoot 'save'
        $env:DC2_DATA = Join-Path $smokeRoot 'data'
        & $cmake "-DEXE=$gameExecutable" "-DROOT=$smokeRoot" `
            "-DEMPTY_DATA_FIXTURE=$emptyDataFixture" "-DDATA_VERSION_SOURCE=$dataVersionSource" `
            -P $smokeScript
        if ($LASTEXITCODE -eq 0) { $smokeStatus = 'passed' }
        else {
            $smokeStatus = 'failed'
            if ($overallExitCode -eq 0) { $overallExitCode = $LASTEXITCODE }
        }
        $apiReportPath = Join-Path $smokeRoot 'save\moonmod-api-report.json'
        if (Test-Path -LiteralPath $apiReportPath) {
            $apiReport = Get-Content -LiteralPath $apiReportPath -Raw | ConvertFrom-Json
            $apiCatalog = [ordered]@{
                report = $apiReportPath
                operation_count = [int]$apiReport.operation_count
                supported_count = @($apiReport.operations | Where-Object status -eq 'supported').Count
                unsupported_count = @($apiReport.operations | Where-Object status -eq 'unsupported').Count
                domains = @($apiReport.operations | Group-Object -Property { $_.domain } | Sort-Object Name | ForEach-Object {
                    [ordered]@{
                        domain = $_.Name
                        operation_count = $_.Count
                        supported_count = @($_.Group | Where-Object status -eq 'supported').Count
                        unsupported_count = @($_.Group | Where-Object status -eq 'unsupported').Count
                    }
                })
                operations = @($apiReport.operations | ForEach-Object {
                    [ordered]@{ path = $_.path; domain = $_.domain; status = $_.status; reason = $_.reason }
                })
            }
        } else {
            $smokeStatus = 'missing_api_catalog'
            if ($overallExitCode -eq 0) { $overallExitCode = 1 }
        }
    }

    Write-Host "Running $($port.Name) deterministic headless repeatability check from two clean roots..."
    $determinismRunId = [Guid]::NewGuid().ToString('N')
    $determinismRoots = @(
        (Join-Path $buildDirectory "determinism-$determinismRunId-a"),
        (Join-Path $buildDirectory "determinism-$determinismRunId-b")
    )
    $determinismSnapshots = [System.Collections.Generic.List[object]]::new()
    $determinismTimeout = [Math]::Max(240, $ProcessTimeoutSeconds)
    if ($port.Name -eq 'Chronicle') {
        foreach ($runRoot in $determinismRoots) {
            $run = Invoke-BoundedProcess $cmake @(
                "-DEXE=$gameExecutable", "-DROOT=$runRoot", '-P', $preflightScript
            ) $workspace $determinismTimeout
            if ($run.exit_code -ne 0 -or $run.timed_out) {
                $headlessDeterminism.error = "Chronicle repeatability preflight failed with exit code $($run.exit_code)."
                continue
            }
            $logPath = Join-Path $runRoot 'preflight.log'
            $markers = @(Get-NormalizedMarkerLines $logPath @('MOONFACTORY_PREFLIGHT_'))
            if ($markers.Count -lt 100) {
                $headlessDeterminism.error = "Chronicle repeatability preflight produced only $($markers.Count) stable markers."
                continue
            }
            $snapshotPath = Join-Path $runRoot 'normalized-report.txt'
            Set-Content -LiteralPath $snapshotPath -Value ($markers -join "`n") -Encoding utf8
            $determinismSnapshots.Add([pscustomobject]@{
                path = $snapshotPath
                markers = $markers
                text = $markers -join "`n"
            })
        }
    } else {
        $previousDc2Save = $env:DC2_SAVE
        $previousDc2Data = $env:DC2_DATA
        try {
            foreach ($runRoot in $determinismRoots) {
                $saveRoot = Join-Path $runRoot 'save'
                $dataRoot = Join-Path $runRoot 'data'
                $env:DC2_SAVE = $saveRoot
                $env:DC2_DATA = $dataRoot
                $run = Invoke-BoundedProcess $cmake @(
                    "-DEXE=$gameExecutable", "-DROOT=$runRoot",
                    "-DEMPTY_DATA_FIXTURE=$emptyDataFixture",
                    "-DDATA_VERSION_SOURCE=$dataVersionSource",
                    '-P', $smokeScript
                ) $workspace $determinismTimeout
                if ($run.exit_code -ne 0 -or $run.timed_out) {
                    $headlessDeterminism.error = "ChronicleTwo repeatability smoke failed with exit code $($run.exit_code)."
                    continue
                }
                $logPath = Join-Path $saveRoot 'moonmod-api-report.txt'
                $markers = @(Get-NormalizedMarkerLines $logPath @('MOONMOD_API_STATUS|', 'MOONMOD_HEADLESS_'))
                if ($markers.Count -lt 200) {
                    $headlessDeterminism.error = "ChronicleTwo repeatability smoke produced only $($markers.Count) stable markers."
                    continue
                }
                $snapshotPath = Join-Path $runRoot 'normalized-report.txt'
                Set-Content -LiteralPath $snapshotPath -Value ($markers -join "`n") -Encoding utf8
                $determinismSnapshots.Add([pscustomobject]@{
                    path = $snapshotPath
                    markers = $markers
                    text = $markers -join "`n"
                })
            }
        } finally {
            $env:DC2_SAVE = $previousDc2Save
            $env:DC2_DATA = $previousDc2Data
        }
    }
    $headlessDeterminism.run_count = $determinismSnapshots.Count
    $headlessDeterminism.normalized_reports = @($determinismSnapshots | ForEach-Object path)
    if ($determinismSnapshots.Count -eq 2 -and $determinismSnapshots[0].text -ceq $determinismSnapshots[1].text) {
        $headlessDeterminism.status = 'passed'
        $headlessDeterminism.marker_count = $determinismSnapshots[0].markers.Count
    } else {
        $headlessDeterminism.status = 'failed'
        if ($null -eq $headlessDeterminism.error) {
            $headlessDeterminism.error = 'Stable headless marker reports differed between clean runs.'
        }
        if ($overallExitCode -eq 0) { $overallExitCode = 1 }
    }
    if ($null -ne $apiCatalog) {
        $apiCatalogError = Get-ApiCatalogCoverageError $apiCatalog
        $apiCatalog['validation'] = [ordered]@{
            status = if ($null -eq $apiCatalogError) { 'passed' } else { 'failed' }
            error = $apiCatalogError
        }
        if ($null -ne $apiCatalogError) {
            Write-Host "API catalog coverage failed for $($port.Name): $apiCatalogError"
            $smokeStatus = 'failed_api_catalog_coverage'
            if ($port.Name -eq 'Chronicle') {
                $preflightStatus = 'failed_api_catalog_coverage'
                if ($null -ne $preflightReport) { $preflightReport.status = $preflightStatus }
            }
            if ($overallExitCode -eq 0) { $overallExitCode = 1 }
        }
    }

    $retailDataRoot = if ($port.Name -eq 'Chronicle') { $ChronicleDataRoot } else { $ChronicleTwoDataRoot }
    if ($retailDataRoot) {
        $retailRunRoot = Join-Path $buildDirectory ('retail-data-smoke-' + [Guid]::NewGuid().ToString('N'))
        $retailSave = Join-Path $retailRunRoot 'save'
        $retailScreenshot = Join-Path $retailRunRoot 'startup.png'
        $retailLog = Join-Path $retailRunRoot 'run.log'
        New-Item -ItemType Directory -Path $retailSave -Force | Out-Null
        Write-Host "Running $($port.Name) retail-data headless startup smoke..."
        if ($port.Name -eq 'Chronicle') {
            $retailRun = Invoke-BoundedProcess $gameExecutable @('--data', $retailDataRoot, '--save', $retailSave, '--headless', '--offscreen',
                '--frames', '120', '--jump', 'title', '--screenshot', $retailScreenshot) $workspace $ProcessTimeoutSeconds
            $retailOutput = @($retailRun.output -split "`r?`n")
            $retailExitCode = $retailRun.exit_code
        } else {
            $previousJump = $env:DC2_JUMP
            $previousFastLoad = $env:DC2_FAST_LOAD
            $env:DC2_JUMP = 'title'
            $env:DC2_FAST_LOAD = '1'
            try {
                $retailRun = Invoke-BoundedProcess $gameExecutable @('--data', $retailDataRoot, '--save', $retailSave, '--headless', '--offscreen',
                    '--frames', '120', '--screenshot', $retailScreenshot) $workspace $ProcessTimeoutSeconds
                $retailOutput = @($retailRun.output -split "`r?`n")
                $retailExitCode = $retailRun.exit_code
            } finally {
                if ($null -eq $previousJump) { Remove-Item Env:DC2_JUMP -ErrorAction SilentlyContinue }
                else { $env:DC2_JUMP = $previousJump }
                if ($null -eq $previousFastLoad) { Remove-Item Env:DC2_FAST_LOAD -ErrorAction SilentlyContinue }
                else { $env:DC2_FAST_LOAD = $previousFastLoad }
            }
        }
        $retailOutput | Set-Content -LiteralPath $retailLog -Encoding utf8
        foreach ($line in $retailOutput) { Write-Host $line }
        $screenshotReady = (Test-Path -LiteralPath $retailScreenshot -PathType Leaf) -and
                           (Get-Item -LiteralPath $retailScreenshot -ErrorAction SilentlyContinue).Length -gt 0
        $retailDataSmoke.status = if ($retailExitCode -eq 0 -and $screenshotReady) { 'passed' } else { 'failed' }
        $retailDataSmoke.data_root = $retailDataRoot
        $retailDataSmoke.exit_code = $retailExitCode
        $retailDataSmoke.timed_out = $retailRun.timed_out
        $retailDataSmoke.screenshot = $retailScreenshot
        $retailDataSmoke.log = $retailLog
        $retailDataSmoke.note = 'A successful startup and screenshot file are checked; screenshot pixels and in-game scene content are not validated by this smoke.'
        if ($retailDataSmoke.status -eq 'failed') {
            if ($overallExitCode -eq 0) { $overallExitCode = if ($retailExitCode -ne 0) { $retailExitCode } else { 1 } }
        } elseif ($port.Name -eq 'Chronicle') {
            $smokeStatus = 'passed'
        }
    }

    if ($ManagerUiSmoke -and $port.Name -in @('Chronicle', 'ChronicleTwo') -and $retailDataRoot) {
        $managerUiRunRoot = Join-Path $buildDirectory ('manager-ui-smoke-' + [Guid]::NewGuid().ToString('N'))
        $managerUiSave = Join-Path $managerUiRunRoot 'save'
        $managerUiScreenshot = Join-Path $managerUiRunRoot 'manager-journal.png'
        $managerUiLog = Join-Path $managerUiRunRoot 'run.log'
        $managerUiFixture = Join-Path $PSScriptRoot 'tools\fixtures\manager-ui-smoke'
        $managerUiPackages = Join-Path $managerUiFixture 'packages'
        $managerUiMods = Join-Path $managerUiSave 'mods'
        $managerUiProfile = Join-Path $managerUiSave 'moonmod'
        New-Item -ItemType Directory -Path $managerUiMods, $managerUiProfile -Force | Out-Null
        $managerUiModIds = @('moonfactory.manager-ui.journal', 'moonfactory.manager-ui.status')
        Copy-Item -LiteralPath (Join-Path $managerUiPackages 'journal') -Destination $managerUiMods -Recurse
        Copy-Item -LiteralPath (Join-Path $managerUiPackages 'status') -Destination $managerUiMods -Recurse
        $managerUiEnabled = [ordered]@{}
        foreach ($modId in $managerUiModIds) { $managerUiEnabled[$modId] = $true }
        [ordered]@{
            format_version = 1
            enabled = $managerUiEnabled
            settings = [ordered]@{}
        } | ConvertTo-Json -Depth 5 -Compress | Set-Content -LiteralPath (Join-Path $managerUiProfile 'profile.json') -Encoding utf8

        $inputName = if ($port.Name -eq 'Chronicle') { 'chronicle-input.txt' } else { 'chronicle-two-input.txt' }
        $managerUiInput = Join-Path $managerUiRunRoot $inputName
        Copy-Item -LiteralPath (Join-Path $managerUiFixture $inputName) -Destination $managerUiInput
        $managerUiArguments = @('--data', $retailDataRoot, '--save', $managerUiSave, '--offscreen',
            '--jump', 'title', '--fast-load', '--frames', [string]$managerUiSmokeReport.frames)
        if ($port.Name -eq 'Chronicle') {
            $managerUiArguments += @('--width', '1280', '--height', '720')
        } else {
            $managerUiArguments += @('--window', '1280x720')
        }
        $managerUiArguments += @('--input', $managerUiInput, '--screenshot', $managerUiScreenshot)
        Write-Host "Running $($port.Name) headless mod-manager Journal screenshot smoke..."
        $managerUiRun = Invoke-BoundedProcess $gameExecutable $managerUiArguments $workspace $ProcessTimeoutSeconds
        $managerUiOutput = @($managerUiRun.output -split "`r?`n")
        $managerUiOutput | Set-Content -LiteralPath $managerUiLog -Encoding utf8
        foreach ($line in $managerUiOutput) { Write-Host $line }
        $managerUiReadyMarkers = @(
            foreach ($modId in $managerUiModIds) {
                $marker = 'MOONFACTORY_MANAGER_UI_READY|' + $modId
                if (@($managerUiOutput | Where-Object { $_.Contains($marker) }).Count -gt 0) { $marker }
            }
        )
        $managerUiErrors = @($managerUiOutput | Where-Object {
            $_ -match 'moonmod\[error\]\[(moonfactory\.manager-ui\.journal|moonfactory\.manager-ui\.status)\]'
        })
        $managerUiScreenshotReady = (Test-Path -LiteralPath $managerUiScreenshot -PathType Leaf) -and
            (Get-Item -LiteralPath $managerUiScreenshot -ErrorAction SilentlyContinue).Length -gt 0
        $managerUiPassed = $managerUiRun.exit_code -eq 0 -and -not $managerUiRun.timed_out -and
            $managerUiScreenshotReady -and $managerUiReadyMarkers.Count -eq $managerUiModIds.Count -and
            $managerUiErrors.Count -eq 0
        $managerUiSmokeReport.status = if ($managerUiPassed) { 'passed' } else { 'failed' }
        $managerUiSmokeReport.fixture_ready_markers = $managerUiReadyMarkers
        $managerUiSmokeReport.fixture_errors = $managerUiErrors
        $managerUiSmokeReport.data_root = $retailDataRoot
        $managerUiSmokeReport.exit_code = $managerUiRun.exit_code
        $managerUiSmokeReport.timed_out = $managerUiRun.timed_out
        $managerUiSmokeReport.screenshot = $managerUiScreenshot
        $managerUiSmokeReport.log = $managerUiLog
        if (-not $managerUiPassed -and $overallExitCode -eq 0) {
            $overallExitCode = if ($managerUiRun.exit_code -ne 0) { $managerUiRun.exit_code } else { 1 }
        }
    }

    $runChronicleCharacterSmoke = $RetailCharacterSmoke -and $port.Name -eq 'Chronicle'
    $runChronicleTwoCharacterSmoke = $RetailCharacterSmoke -and $port.Name -eq 'ChronicleTwo'
    $runRetailCharacterSmoke = $runChronicleTwoCharacterSmoke
    $runRetailDungeonSmoke = $RetailDungeonSmoke -and $port.Name -eq 'Chronicle'
    $runRetailGeoramaSmoke = $RetailGeoramaSmoke -and $port.Name -eq 'Chronicle'
    $runChronicleTwoGeoramaSmoke = $RetailGeoramaSmoke -and $port.Name -eq 'ChronicleTwo'
    if (($RetailGameplaySmoke -or $RetailItemSmoke -or $RetailCharacterSmoke -or $runRetailDungeonSmoke -or $runRetailGeoramaSmoke -or $runChronicleTwoGeoramaSmoke) -and $retailDataRoot) {
        $gameplayRunRoot = Join-Path $buildDirectory ('retail-gameplay-smoke-' + [Guid]::NewGuid().ToString('N'))
        $gameplaySave = Join-Path $gameplayRunRoot 'save'
        $gameplayScreenshot = Join-Path $gameplayRunRoot 'gameplay.png'
        $gameplayLog = Join-Path $gameplayRunRoot 'run.log'
        New-Item -ItemType Directory -Path $gameplaySave -Force | Out-Null
        $createRetailItemFixture = $RetailItemSmoke
        $createRetailCharacterFixture = $runRetailCharacterSmoke -or $runChronicleCharacterSmoke
        $createRetailDungeonFixture = $runRetailDungeonSmoke
        $createRetailGeoramaFixture = $runRetailGeoramaSmoke -or $runChronicleTwoGeoramaSmoke
        if ($createRetailItemFixture -or $createRetailCharacterFixture -or $createRetailDungeonFixture -or $createRetailGeoramaFixture) {
            if ($createRetailCharacterFixture) {
                $characterGame = if ($runChronicleCharacterSmoke) { 'chronicle' } else { 'chronicle-two' }
                $fixtureSource = Join-Path $PSScriptRoot ('tools\fixtures\retail-character-smoke\' + $characterGame)
                $fixtureModId = 'moonfactory.retail-character-probe'
            } elseif ($createRetailGeoramaFixture) {
                $georamaGame = if ($runChronicleTwoGeoramaSmoke) { 'chronicle-two' } else { 'chronicle' }
                $fixtureSource = Join-Path $PSScriptRoot ('tools\fixtures\retail-georama-smoke\' + $georamaGame)
                $fixtureModId = 'moonfactory.retail-georama-probe'
            } elseif ($createRetailDungeonFixture) {
                $fixtureSource = Join-Path $PSScriptRoot 'tools\fixtures\retail-dungeon-smoke\chronicle'
                $fixtureModId = 'moonfactory.retail-dungeon-probe'
            } else {
                $fixturePort = if ($port.Name -eq 'Chronicle') { 'chronicle' } else { 'chronicle-two' }
                $fixtureSource = Join-Path $PSScriptRoot ('tools\fixtures\retail-item-smoke\' + $fixturePort)
                $fixtureModId = 'moonfactory.retail-item-probe'
            }
            if (-not (Test-Path -LiteralPath (Join-Path $fixtureSource 'mod.json') -PathType Leaf) -or
                -not (Test-Path -LiteralPath (Join-Path $fixtureSource 'main.lua') -PathType Leaf)) {
                throw "Missing $($port.Name) retail smoke package: $fixtureSource"
            }
            $fixturePackage = Join-Path $gameplaySave ('mods\' + $fixtureModId)
            New-Item -ItemType Directory -Path $fixturePackage -Force | Out-Null
            Get-ChildItem -LiteralPath $fixtureSource -File | Copy-Item -Destination $fixturePackage
            if ($runChronicleTwoCharacterSmoke) {
                $retailModelSource = Join-Path $retailDataRoot 'dungeon\monster\e201a.chr'
                if (-not (Test-Path -LiteralPath $retailModelSource -PathType Leaf)) {
                    throw "Chronicle Two character model smoke requires the extracted model file: $retailModelSource"
                }
                $fixtureResources = Join-Path $fixturePackage 'resources'
                New-Item -ItemType Directory -Path $fixtureResources -Force | Out-Null
                $retailModelBytes = [System.IO.File]::ReadAllBytes($retailModelSource)
                $packEntryOffset = 0
                $renamedModelInfo = $false
                while ($packEntryOffset + 76 -le $retailModelBytes.Length) {
                    $nameLength = 0
                    while ($nameLength -lt 64 -and $retailModelBytes[$packEntryOffset + $nameLength] -ne 0) {
                        $nameLength++
                    }
                    if ($nameLength -eq 0) { break }
                    $packEntryName = [System.Text.Encoding]::ASCII.GetString($retailModelBytes, $packEntryOffset, $nameLength)
                    if ($packEntryName -eq 'e201a.cfg') {
                        $newInfoName = [System.Text.Encoding]::ASCII.GetBytes('moon_sentinel.cfg')
                        if ($newInfoName.Length -ge 64) { throw 'The custom model info filename exceeds the native pack entry field.' }
                        [System.Array]::Clear($retailModelBytes, $packEntryOffset, 64)
                        [System.Array]::Copy($newInfoName, 0, $retailModelBytes, $packEntryOffset, $newInfoName.Length)
                        $renamedModelInfo = $true
                        break
                    }
                    $nextPackEntry = [System.BitConverter]::ToInt32($retailModelBytes, $packEntryOffset + 72)
                    if ($nextPackEntry -le 0) { break }
                    $packEntryOffset += $nextPackEntry
                }
                if (-not $renamedModelInfo) { throw "Could not find the model info script in the retail pack: $retailModelSource" }
                [System.IO.File]::WriteAllBytes((Join-Path $fixtureResources 'retail-model.chr'), $retailModelBytes)
            } elseif ($runChronicleCharacterSmoke) {
                $retailModelSource = Join-Path $retailDataRoot 'dun\monstor\e01a.chr'
                if (-not (Test-Path -LiteralPath $retailModelSource -PathType Leaf)) {
                    throw "Chronicle character model smoke requires the extracted model file: $retailModelSource"
                }
                $fixtureResources = Join-Path $fixturePackage 'resources'
                New-Item -ItemType Directory -Path $fixtureResources -Force | Out-Null
                Copy-Item -LiteralPath $retailModelSource -Destination (Join-Path $fixtureResources 'retail-model.chr')
            }
            $profileDirectory = Join-Path $gameplaySave 'moonmod'
            New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null
            $enabledMods = [ordered]@{}
            $enabledMods[$fixtureModId] = $true
            [ordered]@{
                format_version = 1
                enabled = $enabledMods
                settings = [ordered]@{}
            } | ConvertTo-Json -Depth 5 -Compress | Set-Content -LiteralPath (Join-Path $profileDirectory 'profile.json') -Encoding utf8
        }
        # Let the launcher select a headless Vulkan surface when available. Explicit
        # --offscreen forces surface-free rendering even when the normal headless path
        # can use a hidden window or SDL's headless surface.
        $gameplayArgs = @('--data', $retailDataRoot, '--save', $gameplaySave, '--headless')
        if ($port.Name -eq 'Chronicle') {
            if ($RetailItemSmoke) {
                # The item fixture runs on the target-scene entry event. Keep this retail-backed API
                # proof independent of the longer movement/gameplay replay.
                $gameplayFrames = 1
                $gameplayCheckpoint = 'Norune Village entry before the first simulation frame'
            } elseif ($runRetailDungeonSmoke -or $runChronicleCharacterSmoke -or $runRetailGeoramaSmoke) {
                $gameplayFrames = 600
                $gameplayCheckpoint = if ($runRetailGeoramaSmoke) {
                    'Norune Village with a registered Georama variant native place/save/remove round trip'
                } elseif ($runChronicleCharacterSmoke) {
                    'registered Sentinel Depths floor 15 with a mod-owned encounter and native physics write'
                } else { 'mod-registered Divine Beast Cave floor 16 after native dungeon entry' }
            } else {
                $gameplayFrames = 180
                $gameplayCheckpoint = 'Norune Village (edit:0)'
            }
            $gameplayJump = 'edit:0'
            $gameplayArgs += @('--frames', "$gameplayFrames", '--jump', $gameplayJump, '--fast-load', '--screenshot', $gameplayScreenshot)
            if ($runChronicleCharacterSmoke) { $gameplayArgs += '--screenshot-fps' }
            if ($RetailItemSmoke) { Write-Host 'Running Chronicle retail-data assetless item integration smoke...' }
            elseif ($runRetailGeoramaSmoke) { Write-Host 'Running Chronicle retail-data Georama registration and native place/save/remove smoke...' }
            elseif ($runChronicleCharacterSmoke) { Write-Host 'Running Chronicle retail-data character and physics smoke (600 headless frames)...' }
            elseif ($runRetailDungeonSmoke) { Write-Host 'Running Chronicle retail-data registered-floor gameplay smoke (600 headless frames)...' }
            else { Write-Host 'Running Chronicle retail-data Norune Village gameplay smoke...' }
        } else {
            if ($runChronicleTwoGeoramaSmoke) {
                $gameplayFrames = 300
                $gameplayCheckpoint = 'Sindain town map after retail mod Georama placement/removal and saved-layout readback'
                $gameplayArgs += @('--window', '640x480', '--frames', "$gameplayFrames", '--jump', 'town:0', '--fast-load',
                    '--georama-stock', '0:moonfactory.retail-georama-probe:retail-moonstone-variant:1',
                    '--screenshot', $gameplayScreenshot)
                Write-Host 'Running ChronicleTwo retail-data Lua Georama register/place/remove smoke (up to 300 headless frames)...'
            } elseif ($RetailCharacterSmoke) {
                $gameplayFrames = 180
                $gameplayCheckpoint = 'Underground Channel floor 1 with its native monster loader initialized'
                $gameplayInput = Join-Path $PSScriptRoot 'tools\fixtures\retail-character-smoke\chronicle-two\enter-floor.input'
                if (-not (Test-Path -LiteralPath $gameplayInput -PathType Leaf)) {
                    throw "Missing ChronicleTwo character smoke input script: $gameplayInput"
                }
                $retailGameplay.input_script = $gameplayInput
                $gameplayArgs += @('--window', '640x480', '--frames', "$gameplayFrames", '--jump', 'dungeon:0:1', '--fast-load',
                    '--input', $gameplayInput, '--screenshot', $gameplayScreenshot, '--screenshot-fps')
                Write-Host "Running ChronicleTwo retail-data floor-one character and physics smoke ($gameplayFrames headless frames)..."
            } elseif ($RetailGameplaySmoke) {
                $gameplayFrames = 2300
                $gameplayCheckpoint = 'Underground Channel floor 1 after scripted entry and movement'
                $gameplayInput = Join-Path $gameRoot 'tools\input\jump-dungeon-floor1.input'
                if (-not (Test-Path -LiteralPath $gameplayInput -PathType Leaf)) {
                    throw "Missing ChronicleTwo gameplay input script: $gameplayInput"
                }
                $retailGameplay.input_script = $gameplayInput
                $gameplayArgs += @('--window', '640x480', '--frames', "$gameplayFrames", '--jump', 'dungeon:0:1', '--fast-load', '--input', $gameplayInput,
                    '--screenshot', $gameplayScreenshot)
                Write-Host 'Running ChronicleTwo retail-data dungeon gameplay smoke (2300 headless frames)...'
            } elseif ($RetailItemSmoke) {
                $gameplayFrames = 2400
                $gameplayCheckpoint = 'Underground Channel floor 1 item use, mod annex entry, and live data-only enemy spawn'
                $gameplayInput = Join-Path $PSScriptRoot 'tools\fixtures\retail-item-smoke\enter-annex.input'
                if (-not (Test-Path -LiteralPath $gameplayInput -PathType Leaf)) {
                    throw "Missing ChronicleTwo retail annex input script: $gameplayInput"
                }
                $retailGameplay.input_script = $gameplayInput
                $gameplayArgs += @('--window', '640x480', '--frames', "$gameplayFrames", '--jump', 'dungeon:0:1', '--fast-load',
                    '--input', $gameplayInput, '--pickup', '274', '--screenshot', $gameplayScreenshot)
                Write-Host "Running ChronicleTwo retail-data item, connected-floor entry, and enemy-spawn smoke ($gameplayFrames headless frames)..."
            } else {
                $gameplayFrames = 300
                $gameplayCheckpoint = 'Underground Channel floor 1 entry'
                $gameplayArgs += @('--window', '640x480', '--frames', "$gameplayFrames", '--jump', 'dungeon:0:1', '--fast-load',
                    '--screenshot', $gameplayScreenshot)
                Write-Host 'Running ChronicleTwo retail-data dungeon smoke (300 headless frames)...'
            }
        }
        $gameplayRun = Invoke-BoundedProcess $gameExecutable $gameplayArgs $workspace $ProcessTimeoutSeconds
        $gameplayOutput = @($gameplayRun.output -split "`r?`n")
        $characterSmokeErrorLines = @()
        if ($runChronicleCharacterSmoke -or $runChronicleTwoCharacterSmoke) {
            $characterSmokeErrorLines = @($gameplayOutput | Where-Object { $_ -match 'moonmod\[error\]' })
        }
        $gameplayOutput | Set-Content -LiteralPath $gameplayLog -Encoding utf8
        $gameplayExitCode = $gameplayRun.exit_code
        foreach ($line in $gameplayOutput) { Write-Host $line }
        $gameplayScreenshotReady = (Test-Path -LiteralPath $gameplayScreenshot -PathType Leaf) -and
            (Get-Item -LiteralPath $gameplayScreenshot -ErrorAction SilentlyContinue).Length -gt 0
        $expectedItemMarker = 'MOONFACTORY_RETAIL_ITEM_OK|moonfactory.retail-item-probe:retail-starlight-tonic|'
        $itemMarkerFound = @($gameplayOutput | Where-Object { $_.Contains($expectedItemMarker) }).Count -gt 0
        $expectedItemCapacityMarker = 'MOONFACTORY_RETAIL_ITEM_CAPACITY_OK|'
        $itemCapacityMarker = @($gameplayOutput | Where-Object { $_.Contains($expectedItemCapacityMarker) }) | Select-Object -First 1
        $itemCapacityMarkerFound = $null -ne $itemCapacityMarker
        if ($itemCapacityMarkerFound) {
            $itemCapacityOffset = $itemCapacityMarker.IndexOf($expectedItemCapacityMarker, [System.StringComparison]::Ordinal)
            $itemCapacityFields = $itemCapacityMarker.Substring($itemCapacityOffset) -split '\|'
            $legacyItemSlots = @('143', '144', '156', '157', '158', '184', '194', '214', '215', '223', '232')
            $itemCapacityMarkerFound = $itemCapacityFields.Count -ge 3 -and
                $itemCapacityFields[1] -eq '12' -and $itemCapacityFields[2] -match '^\d+$' -and
                $legacyItemSlots -notcontains $itemCapacityFields[2]
        }
        $itemProbeErrorLines = @($gameplayOutput | Where-Object {
            $_.Contains('moonmod[error][moonfactory.retail-item-probe]:')
        })
        $expectedGeoramaMarker = 'MOONFACTORY_RETAIL_GEORAMA_PLACE_REMOVE_OK|'
        $georamaMarker = @($gameplayOutput | Where-Object { $_.Contains($expectedGeoramaMarker) }) | Select-Object -First 1
        $georamaMarkerFound = $null -ne $georamaMarker
        if ($georamaMarkerFound) {
            $georamaMarkerFields = $georamaMarker -split '\|'
            $georamaMarkerFound = $georamaMarkerFields.Count -ge 6 -and
                $georamaMarkerFields[1] -match '^\d+$' -and
                $georamaMarkerFields[2] -match '^chronicle:georama-placement:\d+(?::\d+){6}$' -and
                $georamaMarkerFields[3] -match '^\d+$' -and
                $georamaMarkerFields[4] -match '^\d+$' -and
                $georamaMarkerFields[5] -match '^\d+$'
        }
        $expectedGeoramaRegistrationMarker = if ($port.Name -eq 'Chronicle') {
            'MOONFACTORY_RETAIL_GEORAMA_REGISTERED|moonfactory.retail-georama-probe:retail-post-variant|'
        } else {
            'MOONFACTORY_RETAIL_GEORAMA_REGISTERED|moonfactory.retail-georama-probe:retail-moonstone-variant|'
        }
        $georamaRegistrationMarker = @($gameplayOutput | Where-Object { $_.Contains($expectedGeoramaRegistrationMarker) }) | Select-Object -First 1
        $georamaRegistrationMarkerFound = $null -ne $georamaRegistrationMarker
        if ($georamaRegistrationMarkerFound) {
            $georamaRegistrationOffset = $georamaRegistrationMarker.IndexOf($expectedGeoramaRegistrationMarker, [System.StringComparison]::Ordinal)
            $georamaRegistrationFields = $georamaRegistrationMarker.Substring($georamaRegistrationOffset) -split '\|'
            if ($port.Name -eq 'Chronicle') {
                $georamaRegistrationMarkerFound = $georamaRegistrationFields.Count -ge 4 -and
                    $georamaRegistrationFields[1] -eq 'moonfactory.retail-georama-probe:retail-post-variant' -and
                    $georamaRegistrationFields[2] -match '^\d+$' -and [int]$georamaRegistrationFields[2] -ge 24 -and
                    [int]$georamaRegistrationFields[2] -lt 56 -and
                    $georamaRegistrationFields[3] -match '^\d+$' -and [int]$georamaRegistrationFields[3] -ge 0 -and
                    [int]$georamaRegistrationFields[3] -lt 24
            } else {
                $georamaRegistrationMarkerFound = $georamaRegistrationFields.Count -ge 4 -and
                    $georamaRegistrationFields[1] -eq 'moonfactory.retail-georama-probe:retail-moonstone-variant' -and
                    $georamaRegistrationFields[2] -match '^\d+$' -and [int]$georamaRegistrationFields[2] -gt 0 -and
                    $georamaRegistrationFields[3] -eq 'registered'
            }
        }
        $expectedChronicleTwoGeoramaVariantMarker = 'MOONFACTORY_RETAIL_GEORAMA_VARIANT_PLACE_REMOVE_OK|moonfactory.retail-georama-probe:retail-moonstone-variant|'
        $chronicleTwoGeoramaVariantMarker = @($gameplayOutput | Where-Object { $_.Contains($expectedChronicleTwoGeoramaVariantMarker) }) | Select-Object -First 1
        $chronicleTwoGeoramaVariantMarkerFound = $null -ne $chronicleTwoGeoramaVariantMarker
        if ($chronicleTwoGeoramaVariantMarkerFound) {
            $chronicleTwoGeoramaVariantMarkerOffset = $chronicleTwoGeoramaVariantMarker.IndexOf($expectedChronicleTwoGeoramaVariantMarker, [System.StringComparison]::Ordinal)
            $chronicleTwoGeoramaVariantFields = $chronicleTwoGeoramaVariantMarker.Substring($chronicleTwoGeoramaVariantMarkerOffset) -split '\|'
            $chronicleTwoGeoramaVariantMarkerFound = $chronicleTwoGeoramaVariantFields.Count -ge 5 -and
                $chronicleTwoGeoramaVariantFields[1] -eq 'moonfactory.retail-georama-probe:retail-moonstone-variant' -and
                $chronicleTwoGeoramaVariantFields[2] -match '^\d+$' -and [int]$chronicleTwoGeoramaVariantFields[2] -gt 0 -and
                $chronicleTwoGeoramaVariantFields[3] -match '^chronicle-two:georama-placement:0:\d+$' -and
                $chronicleTwoGeoramaVariantFields[4] -eq '0'
        }
        $expectedGeoramaStockMarker = 'MOONFACTORY_TEST_GEORAMA_STOCK|0|moonfactory.retail-georama-probe:retail-moonstone-variant|'
        $georamaStockMarker = @($gameplayOutput | Where-Object { $_.Contains($expectedGeoramaStockMarker) }) | Select-Object -First 1
        $georamaStockMarkerFound = $null -ne $georamaStockMarker
        if ($georamaStockMarkerFound) {
            $georamaStockMarkerOffset = $georamaStockMarker.IndexOf($expectedGeoramaStockMarker, [System.StringComparison]::Ordinal)
            $georamaStockFields = $georamaStockMarker.Substring($georamaStockMarkerOffset) -split '\|'
            $georamaStockMarkerFound = $georamaStockFields.Count -ge 5 -and
                $georamaStockFields[3] -match '^\d+$' -and [int]$georamaStockFields[3] -gt 0 -and
                $georamaStockFields[4] -match '^\d+$' -and [int]$georamaStockFields[4] -ge 1
        }
        $expectedContentMarker = 'MOONFACTORY_RETAIL_CONTENT_OK|'
        $contentMarkerFound = @($gameplayOutput | Where-Object { $_.Contains($expectedContentMarker) }).Count -gt 0
        $expectedWeaponMarker = 'MOONFACTORY_RETAIL_WEAPON_OK|moonfactory.retail-item-probe:retail-starlight-blade|'
        $weaponMarker = @($gameplayOutput | Where-Object { $_.Contains($expectedWeaponMarker) }) | Select-Object -First 1
        $weaponMarkerFound = $null -ne $weaponMarker
        if ($weaponMarkerFound) {
            $weaponMarkerOffset = $weaponMarker.IndexOf($expectedWeaponMarker, [System.StringComparison]::Ordinal)
            $weaponMarkerFields = $weaponMarker.Substring($weaponMarkerOffset) -split '\|'
            $weaponMarkerFound = $weaponMarkerFields.Count -ge 4 -and
                $weaponMarkerFields[1] -eq 'moonfactory.retail-item-probe:retail-starlight-blade' -and
                $weaponMarkerFields[2] -match '^\d+$' -and [int]$weaponMarkerFields[2] -gt 0
            if ($weaponMarkerFound -and $port.Name -eq 'ChronicleTwo') {
                $weaponMarkerFound = $weaponMarkerFields.Count -ge 5 -and
                    $weaponMarkerFields[3] -eq '1' -and $weaponMarkerFields[4] -eq '1'
            }
        }
        $expectedItemGivenQuestMarker = 'MOONFACTORY_RETAIL_ITEM_GIVEN_QUEST_OK|moonfactory.retail-item-probe:retail-item-grants|2'
        $itemGivenQuestMarker = @($gameplayOutput | Where-Object { $_.Contains($expectedItemGivenQuestMarker) }) | Select-Object -First 1
        $itemGivenQuestMarkerFound = $null -ne $itemGivenQuestMarker
        if ($itemGivenQuestMarkerFound) {
            $itemGivenQuestFields = $itemGivenQuestMarker -split '\|'
            $itemGivenQuestMarkerFound = $itemGivenQuestFields.Count -ge 3 -and
                $itemGivenQuestFields[1] -eq 'moonfactory.retail-item-probe:retail-item-grants' -and
                $itemGivenQuestFields[2] -eq '2'
        }
        $expectedWeaponQuestRewardMarker = 'MOONFACTORY_RETAIL_WEAPON_QUEST_REWARD_OK|moonfactory.retail-item-probe:retail-quest-blade|1'
        $weaponQuestRewardMarker = @($gameplayOutput | Where-Object { $_.Contains($expectedWeaponQuestRewardMarker) }) | Select-Object -First 1
        $weaponQuestRewardMarkerFound = $null -ne $weaponQuestRewardMarker
        if ($weaponQuestRewardMarkerFound) {
            $weaponQuestRewardFields = $weaponQuestRewardMarker -split '\|'
            $weaponQuestRewardMarkerFound = $weaponQuestRewardFields.Count -ge 3 -and
                $weaponQuestRewardFields[1] -eq 'moonfactory.retail-item-probe:retail-quest-blade' -and
                $weaponQuestRewardFields[2] -eq '1'
        }
        $expectedItemRemovedQuestMarker = 'MOONFACTORY_RETAIL_ITEM_REMOVED_QUEST_OK|moonfactory.retail-item-probe:retail-item-removals|1'
        $itemRemovedQuestMarker = @($gameplayOutput | Where-Object { $_.Contains($expectedItemRemovedQuestMarker) }) | Select-Object -First 1
        $itemRemovedQuestMarkerFound = $null -ne $itemRemovedQuestMarker
        if ($itemRemovedQuestMarkerFound) {
            $itemRemovedQuestFields = $itemRemovedQuestMarker -split '\|'
            $itemRemovedQuestMarkerFound = $itemRemovedQuestFields.Count -ge 3 -and
                $itemRemovedQuestFields[1] -eq 'moonfactory.retail-item-probe:retail-item-removals' -and
                $itemRemovedQuestFields[2] -eq '1'
        }
        $expectedNativeItemPickupMarker = 'MOONFACTORY_RETAIL_NATIVE_ITEM_PICKUP_OK|chronicle-two:item:274|1'
        $nativeItemPickupMarker = @($gameplayOutput | Where-Object { $_.Contains($expectedNativeItemPickupMarker) }) | Select-Object -First 1
        $nativeItemPickupMarkerFound = $null -ne $nativeItemPickupMarker
        $expectedDungeonMarker = 'MOONFACTORY_RETAIL_DUNGEON_OK|moonfactory.retail-item-probe:retail-moon-vault.annex|'
        $expectedChronicleDungeonMarker = 'MOONFACTORY_RETAIL_DUNGEON_OK|moonfactory.retail-dungeon-probe:moon-vault:annex|'
        $dungeonMarkerPrefix = if ($runRetailDungeonSmoke) { $expectedChronicleDungeonMarker }
            else { $expectedDungeonMarker }
        $dungeonMarker = @($gameplayOutput | Where-Object { $_.Contains($dungeonMarkerPrefix) }) | Select-Object -First 1
        $dungeonMarkerFound = $null -ne $dungeonMarker
        if ($dungeonMarkerFound -and ($runRetailDungeonSmoke -or ($RetailItemSmoke -and $port.Name -eq 'ChronicleTwo'))) {
            $dungeonMarkerFields = $dungeonMarker -split '\|'
            $dungeonMarkerFound = $dungeonMarkerFields.Count -ge 5 -and $dungeonMarkerFields[3] -eq 'dungeon' -and
                -not [string]::IsNullOrWhiteSpace($dungeonMarkerFields[4])
        }
        $expectedCharacterMarker = 'MOONFACTORY_RETAIL_CHARACTER_OK|moonfactory.retail-character-probe:retail-sentinel|'
        $characterMarker = @($gameplayOutput | Where-Object { $_.Contains($expectedCharacterMarker) }) | Select-Object -First 1
        $characterMarkerFound = $null -ne $characterMarker
        $expectedEnemyDefeatQuestId = if ($port.Name -eq 'ChronicleTwo') {
            'moonfactory.retail-item-probe:annex-sentinel-hunt'
        } else { 'moonfactory.retail-character-probe:sentinel-hunt' }
        $expectedEnemyDefeatCharacterId = if ($port.Name -eq 'ChronicleTwo') {
            'moonfactory.retail-item-probe:retail-annex-sentinel'
        } else { 'moonfactory.retail-character-probe:retail-sentinel' }
        $enemyDefeatQuestMarker = @($gameplayOutput | Where-Object {
            $_.Contains('MOONFACTORY_RETAIL_ENEMY_DEFEAT_QUEST_OK|' + $expectedEnemyDefeatQuestId + '|')
        }) | Select-Object -First 1
        $enemyDefeatQuestMarkerFound = $null -ne $enemyDefeatQuestMarker
        if ($enemyDefeatQuestMarkerFound) {
            $enemyDefeatQuestFields = $enemyDefeatQuestMarker -split '\|'
            $expectedEnemyHandlePrefix = if ($port.Name -eq 'ChronicleTwo') { 'chronicle-two:' } else { 'chronicle:' }
            $enemyDefeatQuestMarkerFound = $enemyDefeatQuestFields.Count -ge 3 -and
                $enemyDefeatQuestFields[1] -eq $expectedEnemyDefeatQuestId -and
                $enemyDefeatQuestFields[2] -match ('^' + [regex]::Escape($expectedEnemyHandlePrefix) + 'monster:\d+:\d+$')
        }
        $expectedEnemySpawnModId = if ($port.Name -eq 'ChronicleTwo') {
            'moonfactory.retail-item-probe'
        } else { 'moonfactory.retail-character-probe' }
        $expectedEnemySpawnEventPrefix = 'MOONFACTORY_RETAIL_ENEMY_SPAWNED_EVENT|' + $expectedEnemyDefeatCharacterId + '|'
        $enemySpawnEventMarker = @($gameplayOutput | Where-Object {
            $_.Contains($expectedEnemySpawnEventPrefix)
        }) | Select-Object -Last 1
        $enemySpawnEventMarkerFound = $null -ne $enemySpawnEventMarker
        if ($enemySpawnEventMarkerFound) {
            $enemySpawnEventFields = $enemySpawnEventMarker -split '\|'
            $expectedEnemyHandlePrefix = if ($port.Name -eq 'ChronicleTwo') { 'chronicle-two:' } else { 'chronicle:' }
            $enemySpawnHandleMatch = if ($enemySpawnEventFields.Count -ge 3) {
                [regex]::Match($enemySpawnEventFields[2], '^chronicle(-two)?:monster:(\d+):(\d+)$')
            } else { [regex]::Match('', 'a^') }
            $enemySpawnEventMarkerFound = $enemySpawnEventFields.Count -ge 8 -and
                $enemySpawnEventFields[1] -eq $expectedEnemyDefeatCharacterId -and
                $enemySpawnEventFields[2] -match ('^' + [regex]::Escape($expectedEnemyHandlePrefix) + 'monster:\d+:\d+$') -and
                $enemySpawnEventFields[3] -match '^\d+$' -and [int]$enemySpawnEventFields[3] -gt 0 -and
                $enemySpawnEventFields[4] -match '^\d+$' -and $enemySpawnHandleMatch.Success -and
                $enemySpawnEventFields[4] -eq $enemySpawnHandleMatch.Groups[2].Value -and
                $enemySpawnEventFields[5] -match '^\d+$' -and
                $enemySpawnEventFields[5] -eq $enemySpawnHandleMatch.Groups[3].Value -and
                $enemySpawnEventFields[6] -eq $expectedEnemySpawnModId -and
                $enemySpawnEventFields[7] -match '^\d+$'
        }
        $expectedEnemyDefeatEventPrefix = 'MOONFACTORY_RETAIL_ENEMY_DEFEAT_EVENT|' + $expectedEnemyDefeatCharacterId + '|'
        $enemyDefeatEventMarker = @($gameplayOutput | Where-Object {
            $_.Contains($expectedEnemyDefeatEventPrefix)
        }) | Select-Object -First 1
        $enemyDefeatEventMarkerFound = $null -ne $enemyDefeatEventMarker
        if ($enemyDefeatEventMarkerFound) {
            $enemyDefeatEventFields = $enemyDefeatEventMarker -split '\|'
            $expectedEnemyHandlePrefix = if ($port.Name -eq 'ChronicleTwo') { 'chronicle-two:' } else { 'chronicle:' }
            $enemyDefeatEventMarkerFound = $enemyDefeatEventFields.Count -ge 5 -and
                $enemyDefeatEventFields[1] -eq $expectedEnemyDefeatCharacterId -and
                $enemyDefeatEventFields[2] -match ('^' + [regex]::Escape($expectedEnemyHandlePrefix) + 'monster:\d+:\d+$') -and
                $enemyDefeatEventFields[3] -in @('combat', 'scripted') -and
                $enemyDefeatEventFields[4] -match '^\d+$' -and [int]$enemyDefeatEventFields[4] -gt 0
        }
        $expectedEnemyDefeatQueuedPrefix = 'MOONFACTORY_RETAIL_ENEMY_DEFEAT_QUEUED|'
        $enemyDefeatQueuedMarker = @($gameplayOutput | Where-Object { $_.Contains($expectedEnemyDefeatQueuedPrefix) }) | Select-Object -First 1
        $enemyDefeatQueuedMarkerFound = $null -ne $enemyDefeatQueuedMarker
        if ($enemyDefeatQueuedMarkerFound) {
            $enemyDefeatQueuedFields = $enemyDefeatQueuedMarker -split '\|'
            $expectedEnemyHandlePrefix = if ($port.Name -eq 'ChronicleTwo') { 'chronicle-two:' } else { 'chronicle:' }
            $enemyDefeatQueuedMarkerFound = $enemyDefeatQueuedFields.Count -ge 2 -and
                $enemyDefeatQueuedFields[1] -match ('^' + [regex]::Escape($expectedEnemyHandlePrefix) + 'monster:\d+:\d+$')
            if ($enemyDefeatQueuedMarkerFound -and $enemyDefeatQuestMarkerFound) {
                $enemyDefeatQueuedMarkerFound = $enemyDefeatQueuedFields[1] -eq $enemyDefeatQuestFields[2]
            }
            if ($enemyDefeatQueuedMarkerFound -and $enemyDefeatEventMarkerFound) {
                $enemyDefeatQueuedMarkerFound = $enemyDefeatQueuedFields[1] -eq $enemyDefeatEventFields[2]
            }
            if ($enemyDefeatQueuedMarkerFound -and $enemySpawnEventMarkerFound) {
                $enemyDefeatQueuedMarkerFound = $enemyDefeatQueuedFields[1] -eq $enemySpawnEventFields[2]
            }
        }
        $requiresEnemyDefeatQuest = $runChronicleCharacterSmoke -or ($RetailItemSmoke -and $port.Name -eq 'ChronicleTwo')
        $requiresEnemyDefeatEventMarker = $RetailItemSmoke -and $port.Name -eq 'ChronicleTwo'
        $requiresEnemySpawnEventMarker = $runChronicleCharacterSmoke -or ($RetailItemSmoke -and $port.Name -eq 'ChronicleTwo')
        $enemySpawnEventPassed = -not $requiresEnemySpawnEventMarker -or $enemySpawnEventMarkerFound
        $enemyDefeatQuestPassed = -not $requiresEnemyDefeatQuest -or
            ($enemyDefeatQuestMarkerFound -and $enemyDefeatQueuedMarkerFound -and
             (-not $requiresEnemyDefeatEventMarker -or $enemyDefeatEventMarkerFound))
        $expectedDebugOverlayMarker = 'MOONFACTORY_RETAIL_DEBUG_OVERLAY_OK|moonfactory.retail-character-probe:character-probe|CHARACTER PROBE READY'
        $debugOverlayMarkerFound = @($gameplayOutput | Where-Object { $_.Contains($expectedDebugOverlayMarker) }).Count -gt 0
        $expectedRenderLayerMarker = 'MOONFACTORY_RETAIL_RENDER_LAYER_OK|moonfactory.retail-character-probe:character-probe-hud|MOONMOD HUD VERIFIED|true'
        $renderLayerMarkerFound = @($gameplayOutput | Where-Object { $_.Contains($expectedRenderLayerMarker) }).Count -gt 0
        $expectedCombatRoundTripMarker = 'MOONFACTORY_RETAIL_COMBAT_ROUNDTRIP_OK|moonfactory.retail-character-probe:retail-sentinel|'
        $combatRoundTripMarker = @($gameplayOutput | Where-Object { $_.Contains($expectedCombatRoundTripMarker) }) | Select-Object -First 1
        $combatRoundTripMarkerFound = $null -ne $combatRoundTripMarker
        if ($combatRoundTripMarkerFound) {
            $combatRoundTripFields = $combatRoundTripMarker -split '\|'
            $combatRoundTripMarkerFound = $combatRoundTripFields.Count -ge 6 -and
                $combatRoundTripFields[2] -match '^chronicle(-two)?:monster:\d+:\d+$' -and
                $combatRoundTripFields[3] -match '^\d+$' -and
                $combatRoundTripFields[4] -match '^\d+$' -and
                $combatRoundTripFields[3] -eq $combatRoundTripFields[4] -and
                $combatRoundTripFields[5] -eq '2'
        }
        $expectedCombatFormulaMarker = 'MOONFACTORY_RETAIL_COMBAT_FORMULA_OK|moonfactory.retail-character-probe:retail-double-damage|2'
        $combatFormulaMarker = @($gameplayOutput | Where-Object { $_.Contains($expectedCombatFormulaMarker) }) | Select-Object -First 1
        $combatFormulaMarkerFound = $null -ne $combatFormulaMarker
        $expectedSkillDamageBonusMarker = 'MOONFACTORY_RETAIL_SKILL_DAMAGE_BONUS_OK|moonfactory.retail-character-probe:retail-combat.power|3|2'
        $skillDamageBonusMarker = @($gameplayOutput | Where-Object { $_.Contains($expectedSkillDamageBonusMarker) }) | Select-Object -First 1
        $skillDamageBonusMarkerFound = $null -ne $skillDamageBonusMarker
        $expectedCharacterFloorMarker = 'MOONFACTORY_RETAIL_CHARACTER_FLOOR_OK|moonfactory.retail-character-probe:sentinel-depths:sentinel-floor|'
        $characterFloorMarker = @($gameplayOutput | Where-Object { $_.Contains($expectedCharacterFloorMarker) }) | Select-Object -First 1
        $characterFloorMarkerFound = $null -ne $characterFloorMarker
        if ($characterFloorMarkerFound) {
            $characterFloorMarkerFields = $characterFloorMarker -split '\|'
            $characterFloorMarkerFound = $characterFloorMarkerFields.Count -ge 4 -and
                $characterFloorMarkerFields[2] -eq 'dungeon' -and $characterFloorMarkerFields[3] -eq '15'
        }
        $expectedModelMarker = 'MOONFACTORY_RETAIL_MODEL_OK|moonfactory.retail-character-probe:retail-sentinel-model|'
        $modelMarker = @($gameplayOutput | Where-Object { $_.Contains($expectedModelMarker) }) | Select-Object -First 1
        $modelMarkerFound = $null -ne $modelMarker
        $expectedModelGamePath = if ($port.Name -eq 'Chronicle') { 'dun/monstor/moon_sentinel.chr' }
            else { 'dungeon/monster/moon_sentinel.chr' }
        if ($modelMarkerFound) {
            $modelMarkerFields = $modelMarker -split '\|'
            $modelMarkerFound = $modelMarkerFields.Count -ge 4 -and
                $modelMarkerFields[2] -eq $expectedModelGamePath -and $modelMarkerFields[3] -eq 'loaded'
        }
        $expectedModelReplacementMarker = 'MOONFACTORY_RETAIL_MODEL_REPLACE_OK|'
        $modelReplacementMarker = @($gameplayOutput | Where-Object { $_.Contains($expectedModelReplacementMarker) }) | Select-Object -First 1
        $modelReplacementMarkerFound = $null -ne $modelReplacementMarker
        if ($modelReplacementMarkerFound) {
            $modelReplacementMarkerFields = $modelReplacementMarker -split '\|'
            $modelReplacementMarkerFound = $modelReplacementMarkerFields.Count -ge 4 -and
                $modelReplacementMarkerFields[1] -match '^\d+$' -and
                $modelReplacementMarkerFields[2] -eq $expectedModelGamePath -and
                $modelReplacementMarkerFields[3] -eq 'restored'
        }
        $expectedAnimationPlayMarker = 'MOONFACTORY_RETAIL_ANIMATION_PLAY_OK|moonfactory.retail-character-probe:retail-sentinel-idle|'
        $animationPlayMarker = @($gameplayOutput | Where-Object { $_.Contains($expectedAnimationPlayMarker) }) | Select-Object -First 1
        $animationPlayMarkerFound = $null -ne $animationPlayMarker
        if ($animationPlayMarkerFound) {
            $animationPlayMarkerFields = $animationPlayMarker -split '\|'
            $animationPlayMarkerFound = $animationPlayMarkerFields.Count -ge 4 -and
                $animationPlayMarkerFields[1] -eq 'moonfactory.retail-character-probe:retail-sentinel-idle' -and
                $animationPlayMarkerFields[2] -match '^chronicle(-two)?:monster:\d+:\d+$' -and
                -not [string]::IsNullOrWhiteSpace($animationPlayMarkerFields[3])
        }
        $expectedAnimationStopMarker = 'MOONFACTORY_RETAIL_ANIMATION_STOP_OK|moonfactory.retail-character-probe:retail-sentinel-idle|'
        $animationStopMarker = @($gameplayOutput | Where-Object { $_.Contains($expectedAnimationStopMarker) }) | Select-Object -First 1
        $animationStopMarkerFound = $null -ne $animationStopMarker
        if ($animationStopMarkerFound) {
            $animationStopMarkerFields = $animationStopMarker -split '\|'
            $animationStopMarkerFound = $animationStopMarkerFields.Count -ge 4 -and
                $animationStopMarkerFields[1] -eq 'moonfactory.retail-character-probe:retail-sentinel-idle' -and
                $animationStopMarkerFields[2] -match '^chronicle(-two)?:monster:\d+:\d+$' -and
                $animationStopMarkerFields[3] -in @('true', 'false')
        }
        $expectedAnimationDespawnCleanupMarker = 'MOONFACTORY_RETAIL_ANIMATION_DESPAWN_CLEANUP_OK|moonfactory.retail-character-probe:retail-sentinel-idle|'
        $animationDespawnCleanupMarker = @($gameplayOutput | Where-Object { $_.Contains($expectedAnimationDespawnCleanupMarker) }) | Select-Object -First 1
        $animationDespawnCleanupMarkerFound = $null -ne $animationDespawnCleanupMarker
        if ($animationDespawnCleanupMarkerFound) {
            $animationDespawnCleanupMarkerFields = $animationDespawnCleanupMarker -split '\|'
            $animationDespawnCleanupMarkerFound = $animationDespawnCleanupMarkerFields.Count -ge 4 -and
                $animationDespawnCleanupMarkerFields[1] -eq 'moonfactory.retail-character-probe:retail-sentinel-idle' -and
                $animationDespawnCleanupMarkerFields[2] -match '^chronicle(-two)?:monster:\d+:\d+$' -and
                $animationDespawnCleanupMarkerFields[3] -eq 'true'
        }
        $expectedPhysicsMarker = 'MOONFACTORY_RETAIL_VELOCITY_SET_OK|moonfactory.retail-character-probe:retail-sentinel|'
        $physicsMarker = @($gameplayOutput | Where-Object { $_.Contains($expectedPhysicsMarker) }) | Select-Object -First 1
        $physicsMarkerFound = $null -ne $physicsMarker
        $expectedPhysicsQueryMarker = 'MOONFACTORY_RETAIL_PHYSICS_QUERY_OK|moonfactory.retail-character-probe:retail-sentinel|'
        $physicsQueryMarker = @($gameplayOutput | Where-Object { $_.Contains($expectedPhysicsQueryMarker) }) | Select-Object -First 1
        $physicsQueryMarkerFound = $null -ne $physicsQueryMarker
        $expectedCameraMarker = 'MOONFACTORY_RETAIL_CAMERA_OK|'
        $cameraMarkerFound = @($gameplayOutput | Where-Object { $_.Contains($expectedCameraMarker) }).Count -gt 0
        $requiresRetailItem = $RetailItemSmoke
        $requiresRetailDungeon = ($port.Name -eq 'ChronicleTwo' -and $RetailItemSmoke) -or $runRetailDungeonSmoke
        $requiresRetailCharacter = $RetailCharacterSmoke -and $port.Name -in @('Chronicle', 'ChronicleTwo')
        $requiresRetailGeorama = $runRetailGeoramaSmoke -or $runChronicleTwoGeoramaSmoke
        $requiresRetailCamera = $RetailItemSmoke -and $port.Name -eq 'ChronicleTwo'
        $retailGameplay.status = if ($gameplayExitCode -eq 0 -and $gameplayScreenshotReady -and
            (-not $requiresRetailItem -or ($itemMarkerFound -and $weaponMarkerFound -and
                $weaponQuestRewardMarkerFound -and $itemProbeErrorLines.Count -eq 0 -and
                ($port.Name -ne 'ChronicleTwo' -or $nativeItemPickupMarkerFound) -and
                ($port.Name -ne 'Chronicle' -or ($contentMarkerFound -and $itemCapacityMarkerFound)))) -and
            (-not $requiresRetailDungeon -or $dungeonMarkerFound) -and
            (-not $runRetailGeoramaSmoke -or ($georamaRegistrationMarkerFound -and $georamaMarkerFound)) -and
            (-not $runChronicleTwoGeoramaSmoke -or ($georamaRegistrationMarkerFound -and
                $chronicleTwoGeoramaVariantMarkerFound -and $georamaStockMarkerFound)) -and
            (-not $requiresRetailCamera -or $cameraMarkerFound) -and
            $enemySpawnEventPassed -and
            $enemyDefeatQuestPassed -and
            (-not $requiresRetailCharacter -or ($characterSmokeErrorLines.Count -eq 0 -and
                $characterMarkerFound -and $physicsMarkerFound -and $physicsQueryMarkerFound -and
                $modelMarkerFound -and $modelReplacementMarkerFound -and $debugOverlayMarkerFound -and
                $combatFormulaMarkerFound -and $skillDamageBonusMarkerFound -and
                (-not ($runChronicleTwoCharacterSmoke -or $runChronicleCharacterSmoke) -or
                    ($animationPlayMarkerFound -and $animationStopMarkerFound -and $animationDespawnCleanupMarkerFound)) -and
                (-not $runChronicleCharacterSmoke -or $characterFloorMarkerFound)))) { 'passed' } else { 'failed' }
        $retailGameplay.checkpoint = $gameplayCheckpoint
        if ($requiresEnemyDefeatQuest -and $enemyDefeatQuestPassed) {
            $retailGameplay.checkpoint += ' and completed a character-filtered quest from native enemy-spawn and enemy-defeat events'
        }
        $retailGameplay.data_root = $retailDataRoot
        $retailGameplay.exit_code = $gameplayExitCode
        $retailGameplay.timed_out = $gameplayRun.timed_out
        $retailGameplay.frames = $gameplayFrames
        $retailGameplay.screenshot = $gameplayScreenshot
        $retailGameplay.log = $gameplayLog
        $retailGameplay.note = 'The executable accepts the retail data and scripted gameplay checkpoint and writes a screenshot; visual scene content is reviewed separately.'
        if ($RetailItemSmoke -or $RetailCharacterSmoke -or $runRetailDungeonSmoke -or $runRetailGeoramaSmoke -or $runChronicleTwoGeoramaSmoke) {
            if ($requiresRetailGeorama) {
                $georamaPassed = if ($runChronicleTwoGeoramaSmoke) {
                    $georamaRegistrationMarkerFound -and $chronicleTwoGeoramaVariantMarkerFound -and $georamaStockMarkerFound
                } else { $georamaRegistrationMarkerFound -and $georamaMarkerFound }
                $retailGeoramaSmokeReport.status = if ($gameplayExitCode -eq 0 -and $gameplayScreenshotReady -and $georamaPassed) { 'passed' } else { 'failed' }
                if ($georamaRegistrationMarkerFound) { $retailGeoramaSmokeReport.registration_marker = $expectedGeoramaRegistrationMarker }
                if ($chronicleTwoGeoramaVariantMarkerFound) {
                    $retailGeoramaSmokeReport.placement_marker = $expectedChronicleTwoGeoramaVariantMarker
                    $retailGeoramaSmokeReport.removal_marker = $expectedChronicleTwoGeoramaVariantMarker
                }
                if ($georamaMarkerFound) {
                    $retailGeoramaSmokeReport.placement_marker = $expectedGeoramaMarker
                    $retailGeoramaSmokeReport.removal_marker = $expectedGeoramaMarker
                }
                if ($runChronicleTwoGeoramaSmoke) {
                    $retailGeoramaSmokeReport.initial_stock_hook = '0:moonfactory.retail-georama-probe:retail-moonstone-variant:1'
                }
                $retailGeoramaSmokeReport.screenshot = $gameplayScreenshot
                $retailGeoramaSmokeReport.log = $gameplayLog
                if ($runRetailGeoramaSmoke -and -not $georamaPassed) {
                    if (@($gameplayOutput | Where-Object { $_.Contains('MOONFACTORY_RETAIL_GEORAMA_UNVERIFIED|registered variant is not materialized with stock') }).Count -gt 0) {
                        $retailGeoramaSmokeReport.note = 'Chronicle did not materialize the registered variant with its configured stock.'
                    } elseif (-not $georamaRegistrationMarkerFound) {
                        $retailGeoramaSmokeReport.note = 'The retail executable did not report successful registration in an appended native Georama slot.'
                    } elseif (@($gameplayOutput | Where-Object { $_.Contains('MOONFACTORY_RETAIL_GEORAMA_UNVERIFIED|') }).Count -gt 0) {
                        $retailGeoramaSmokeReport.note = 'The registered variant did not complete native placement, saved-layout readback, and removal.'
                    }
                }
                if ($runChronicleTwoGeoramaSmoke -and -not $georamaPassed) {
                    $retailGeoramaSmokeReport.note = 'The retail smoke requires the registered variant, test-granted built stock, native placement/removal, and saved-layout readback markers. Check the gameplay log for the last native placement rejection.'
                }
            }
            if ($RetailItemSmoke) {
            $retailItemSmokeReport.status = if ($gameplayExitCode -eq 0 -and $gameplayScreenshotReady -and $itemMarkerFound -and
                $weaponMarkerFound -and $itemGivenQuestMarkerFound -and $weaponQuestRewardMarkerFound -and
                $itemRemovedQuestMarkerFound -and $itemProbeErrorLines.Count -eq 0 -and
                ($port.Name -ne 'ChronicleTwo' -or $nativeItemPickupMarkerFound) -and
                ($port.Name -ne 'Chronicle' -or ($contentMarkerFound -and $itemCapacityMarkerFound))) { 'passed' } else { 'failed' }
            $retailItemSmokeReport.verification_marker = if ($itemMarkerFound) { $expectedItemMarker } else { $null }
            $retailItemSmokeReport.item_capacity_marker = if ($itemCapacityMarkerFound) { $itemCapacityMarker.Trim() } else { $null }
            $retailItemSmokeReport.weapon_verification_marker = if ($weaponMarkerFound) { $expectedWeaponMarker } else { $null }
            $retailItemSmokeReport.item_given_quest_marker = if ($itemGivenQuestMarkerFound) { $expectedItemGivenQuestMarker } else { $null }
            $retailItemSmokeReport.weapon_quest_reward_marker = if ($weaponQuestRewardMarkerFound) { $expectedWeaponQuestRewardMarker } else { $null }
            $retailItemSmokeReport.item_removed_quest_marker = if ($itemRemovedQuestMarkerFound) { $expectedItemRemovedQuestMarker } else { $null }
            $retailItemSmokeReport.native_item_pickup_marker = if ($nativeItemPickupMarkerFound) { $expectedNativeItemPickupMarker } else { $null }
            $retailItemSmokeReport.error_lines = $itemProbeErrorLines
            $retailItemSmokeReport.content_registry_marker = if ($contentMarkerFound) { $expectedContentMarker } else { $null }
            if ($port.Name -eq 'ChronicleTwo') {
                $retailItemSmokeReport.enemy_spawned_event_marker = if ($enemySpawnEventMarkerFound) { $enemySpawnEventMarker.Trim() } else { $null }
                $retailItemSmokeReport.enemy_defeat_event_marker = if ($enemyDefeatEventMarkerFound) { $enemyDefeatEventMarker.Trim() } else { $null }
                $retailItemSmokeReport.enemy_defeat_quest_marker = if ($enemyDefeatQuestMarkerFound) { $enemyDefeatQuestMarker.Trim() } else { $null }
                $retailItemSmokeReport.enemy_defeat_queued_marker = if ($enemyDefeatQueuedMarkerFound) { $enemyDefeatQueuedMarker.Trim() } else { $null }
                $retailItemSmokeReport.status = if ($retailItemSmokeReport.status -eq 'passed' -and
                    $enemySpawnEventPassed -and $enemyDefeatQuestPassed) { 'passed' } else { 'failed' }
            }
            $retailItemSmokeReport.screenshot = $gameplayScreenshot
            $retailItemSmokeReport.log = $gameplayLog
            $retailItemSmokeReport.note = if ($port.Name -eq 'Chronicle') {
                'The enabled Lua package registers and reads back 12 data-only consumables, proving allocation can use a safe native row beyond the 11 legacy reserved rows. It then uses a data-only healing item, checks deferred game.item_given and game.item_removed delivery advances filtered quests, grants a data-only weapon directly, and verifies a completed quest pays a second weapon through the native inventory API. The smoke requires success markers and a screenshot file; it does not visually inspect the capture.'
            } else {
                'The enabled Lua package verifies a built-in dungeon pickup emits game.item_picked_up and completes a matching quest, then registers a data-only healing item, uses one of two native inventory copies, removes the other, and verifies deferred game.item_given and game.item_removed delivery advances filtered quests. It grants a data-only weapon directly and verifies a completed quest pays a second weapon through the native inventory API, enters a connected annex, and completes a filtered quest from a native enemy-defeat event. Pickup, weapon, dungeon, camera, quest markers, and a screenshot file are required. The capture is not visually inspected.'
            }
            if ($retailItemSmokeReport.status -eq 'passed') { $retailGameplay.checkpoint += ' and verified the mod-owned data-only tonic' }
            if ($retailItemSmokeReport.status -eq 'passed') { $retailGameplay.checkpoint += ' plus a registered and granted mod weapon' }
            if ($retailItemSmokeReport.status -eq 'passed') { $retailGameplay.checkpoint += ' plus a native quest weapon reward' }
            }
            if ($requiresRetailCharacter) {
                $retailCharacterSmokeReport.status = if ($gameplayExitCode -eq 0 -and $gameplayScreenshotReady -and
                $characterSmokeErrorLines.Count -eq 0 -and
                $characterMarkerFound -and $modelMarkerFound -and $modelReplacementMarkerFound -and $debugOverlayMarkerFound -and $renderLayerMarkerFound -and $combatRoundTripMarkerFound -and $combatFormulaMarkerFound -and
                    $skillDamageBonusMarkerFound -and
                    (-not $runChronicleCharacterSmoke -or $enemySpawnEventPassed) -and
                    (-not $runChronicleCharacterSmoke -or $enemyDefeatQuestPassed) -and
                    (-not ($runChronicleTwoCharacterSmoke -or $runChronicleCharacterSmoke) -or
                        ($animationPlayMarkerFound -and $animationStopMarkerFound -and $animationDespawnCleanupMarkerFound)) -and
                    (-not $runChronicleCharacterSmoke -or $characterFloorMarkerFound)) { 'passed' } else { 'failed' }
                if ($characterMarkerFound) {
                    $retailCharacterSmokeReport.verification_marker = $expectedCharacterMarker
                    $retailCharacterSmokeReport.entity_handle = ($characterMarker -split '\|')[3]
                    if ($modelMarkerFound) {
                        $retailCharacterSmokeReport.model_verification_marker = $expectedModelMarker
                        $retailCharacterSmokeReport.model_asset_path = ($modelMarker -split '\|')[2]
                    }
                    if ($modelReplacementMarkerFound) {
                        $retailCharacterSmokeReport.model_replacement_verification_marker = $expectedModelReplacementMarker
                    }
                    if ($debugOverlayMarkerFound) {
                        $retailCharacterSmokeReport.overlay_registration_marker = $expectedDebugOverlayMarker
                    }
                    if ($renderLayerMarkerFound) {
                        $retailCharacterSmokeReport.render_layer_verification_marker = $expectedRenderLayerMarker
                    }
                    if ($enemySpawnEventMarkerFound) {
                        $retailCharacterSmokeReport.enemy_spawned_event_marker = $enemySpawnEventMarker.Trim()
                    }
                    if ($enemyDefeatQuestMarkerFound) {
                        $retailCharacterSmokeReport.enemy_defeat_quest_marker = $enemyDefeatQuestMarker.Trim()
                    }
                    if ($enemyDefeatQueuedMarkerFound) {
                        $retailCharacterSmokeReport.enemy_defeat_queued_marker = $enemyDefeatQueuedMarker.Trim()
                    }
                    if ($combatRoundTripMarkerFound) {
                        $retailCharacterSmokeReport.combat_round_trip_verification_marker = $expectedCombatRoundTripMarker
                    }
                    if ($combatFormulaMarkerFound) {
                        $retailCharacterSmokeReport.combat_formula_verification_marker = $expectedCombatFormulaMarker
                    }
                    if ($skillDamageBonusMarkerFound) {
                        $retailCharacterSmokeReport.skill_damage_bonus_verification_marker = $expectedSkillDamageBonusMarker
                    }
                    if ($animationPlayMarkerFound) {
                        $retailCharacterSmokeReport.animation_play_verification_marker = $expectedAnimationPlayMarker
                    }
                    if ($animationStopMarkerFound) {
                        $retailCharacterSmokeReport.animation_stop_verification_marker = $expectedAnimationStopMarker
                    }
                    if ($animationDespawnCleanupMarkerFound) {
                        $retailCharacterSmokeReport.animation_despawn_cleanup_verification_marker = $expectedAnimationDespawnCleanupMarker
                    }
                    if ($characterFloorMarkerFound) {
                        $retailCharacterSmokeReport.dungeon_floor_marker = $expectedCharacterFloorMarker
                        $retailCharacterSmokeReport.native_floor_id = 15
                    }
                } elseif (@($gameplayOutput | Where-Object { $_.Contains('MOONFACTORY_RETAIL_CHARACTER_UNVERIFIED|') }).Count -gt 0) {
                    $retailCharacterSmokeReport.note = 'Dungeon entry completed, but the native template did not become spawnable before the probe attempt limit.'
                } elseif ($gameplayRun.timed_out) {
                    $retailCharacterSmokeReport.note = 'The retail dungeon process exceeded its configured timeout before the character marker and screenshot were produced.'
                } elseif ($characterMarkerFound -and -not $modelMarkerFound) {
                    $retailCharacterSmokeReport.note = 'The registered custom model did not report loaded on the active floor.'
                } elseif ($characterMarkerFound -and $modelMarkerFound -and -not $modelReplacementMarkerFound) {
                    $retailCharacterSmokeReport.note = 'Native model replacement and restoration did not produce the expected retail verification marker.'
                } elseif (-not $debugOverlayMarkerFound) {
                    $retailCharacterSmokeReport.note = 'The Lua fixture did not register its mod-owned diagnostic overlay.'
                } elseif (-not $renderLayerMarkerFound) {
                    $retailCharacterSmokeReport.note = 'The Lua fixture did not complete the HUD text layer register, update, and remove round trip.'
                } elseif (-not $combatRoundTripMarkerFound) {
                    $retailCharacterSmokeReport.note = 'The live enemy did not complete a native combat damage and heal round trip.'
                } elseif (-not $combatFormulaMarkerFound) {
                    $retailCharacterSmokeReport.note = 'The live enemy damage did not reflect the mod-registered combat formula.'
                } elseif (-not $skillDamageBonusMarkerFound) {
                    $retailCharacterSmokeReport.note = 'A persisted skill rank did not add and then remove its expected native enemy-damage bonus.'
                } elseif ($runChronicleCharacterSmoke -and -not $enemySpawnEventPassed) {
                    $retailCharacterSmokeReport.note = 'The registered enemy did not publish a matching game.enemy_spawned event.'
                } elseif ($runChronicleCharacterSmoke -and -not $enemyDefeatQuestPassed) {
                    $retailCharacterSmokeReport.note = 'The filtered quest did not complete from the native enemy-spawn and enemy-defeat events for the registered character.'
                } elseif ($characterSmokeErrorLines.Count -gt 0) {
                    $retailCharacterSmokeReport.note = 'The retail character fixture logged an error: ' + $characterSmokeErrorLines[0]
                } elseif ($runChronicleTwoCharacterSmoke -and $characterMarkerFound -and $modelMarkerFound -and
                          (-not $animationPlayMarkerFound -or -not $animationStopMarkerFound)) {
                    $retailCharacterSmokeReport.note = 'The registered native motion could not be played and stopped through the animation API.'
                }
                $retailCharacterSmokeReport.screenshot = $gameplayScreenshot
                $retailCharacterSmokeReport.log = $gameplayLog
                $retailCharacterSmokeReport.runtime_errors = $characterSmokeErrorLines
                if ($retailCharacterSmokeReport.status -eq 'passed') {
                    if ($requiresRetailCharacter) {
                        $retailGameplay.checkpoint += ' and loaded a mod-owned custom model on a registered enemy variant'
                        $retailGameplay.checkpoint += ' and verified native combat damage/healing on its live handle'
                        $retailGameplay.checkpoint += ' and applied a mod-registered damage formula'
                        if ($runChronicleTwoCharacterSmoke) { $retailGameplay.checkpoint += ' with a native animation play/stop round trip' }
                    } else {
                        $retailGameplay.checkpoint += ' and spawned a mod-owned enemy variant'
                    }
                }

                $retailPhysicsSmokeReport.status = if ($gameplayExitCode -eq 0 -and $gameplayScreenshotReady -and $physicsMarkerFound) { 'passed' } else { 'failed' }
                if ($physicsMarkerFound) { $retailPhysicsSmokeReport.verification_marker = $expectedPhysicsMarker }
                $retailPhysicsSmokeReport.screenshot = $gameplayScreenshot
                $retailPhysicsSmokeReport.log = $gameplayLog
                if ($retailPhysicsSmokeReport.status -eq 'passed') { $retailGameplay.checkpoint += ' and changed the spawned enemy velocity through the physics API' }

                $retailPhysicsQuerySmokeReport.status = if ($gameplayExitCode -eq 0 -and $gameplayScreenshotReady -and $physicsQueryMarkerFound) { 'passed' } else { 'failed' }
                if ($physicsQueryMarkerFound) { $retailPhysicsQuerySmokeReport.verification_marker = $expectedPhysicsQueryMarker }
                $retailPhysicsQuerySmokeReport.screenshot = $gameplayScreenshot
                $retailPhysicsQuerySmokeReport.log = $gameplayLog
                if ($retailPhysicsQuerySmokeReport.status -eq 'passed') { $retailGameplay.checkpoint += ' and found the spawned enemy with a native-position sphere query' }
            }
            if ($port.Name -eq 'ChronicleTwo') {
                $retailDungeonSmokeReport.status = if (-not $RetailItemSmoke) { 'not_requested' } elseif ($gameplayExitCode -eq 0 -and $gameplayScreenshotReady -and $dungeonMarkerFound -and $cameraMarkerFound) { 'passed' } else { 'failed' }
                if ($RetailItemSmoke -and $dungeonMarkerFound) {
                    $retailDungeonSmokeReport.verification_marker = $expectedDungeonMarker
                    $dungeonFields = $dungeonMarker -split '\|'
                    $retailDungeonSmokeReport.floor_id = $dungeonFields[1]
                    $retailDungeonSmokeReport.native_floor_id = [int]$dungeonFields[2]
                    $retailDungeonSmokeReport.context = $dungeonFields[3]
                }
                if ($RetailItemSmoke -and $cameraMarkerFound) {
                    $retailDungeonSmokeReport.camera_verification_marker = $expectedCameraMarker
                }
                $retailDungeonSmokeReport.screenshot = $gameplayScreenshot
                $retailDungeonSmokeReport.log = $gameplayLog
                $retailDungeonSmokeReport.note = 'The enabled Lua package enters its connected annex through world.transition, spawns a data-only enemy, resolves it with entities.get, verifies the active native dungeon floor, and adjusts the live follow camera through render.camera_set. The annex reuses native room geometry and enemy assets.'
                if ($RetailItemSmoke -and $dungeonMarkerFound) {
                    $retailDungeonSmokeReport.entity_handle = ($dungeonMarker -split '\|')[4]
                }
                if ($retailDungeonSmokeReport.status -eq 'passed') { $retailGameplay.checkpoint += ' and entered the mod-owned connected floor, spawned a data-only enemy, and adjusted the live dungeon camera through Lua' }
            } elseif ($runRetailDungeonSmoke) {
                $retailDungeonSmokeReport.status = if ($gameplayExitCode -eq 0 -and $gameplayScreenshotReady -and $dungeonMarkerFound) { 'passed' } else { 'failed' }
                if ($dungeonMarkerFound) {
                    $dungeonFields = $dungeonMarker -split '\|'
                    $retailDungeonSmokeReport.floor_id = $dungeonFields[1]
                    $retailDungeonSmokeReport.native_floor_id = [int]$dungeonFields[2]
                    $retailDungeonSmokeReport.context = $dungeonFields[3]
                    $retailDungeonSmokeReport.verification_marker = $expectedChronicleDungeonMarker
                }
                $retailDungeonSmokeReport.screenshot = $gameplayScreenshot
                $retailDungeonSmokeReport.log = $gameplayLog
                $retailDungeonSmokeReport.verification_marker = $expectedChronicleDungeonMarker
                $retailDungeonSmokeReport.note = 'The mod registers a procedural floor, enters its appended native floor number, and reads that floor from the running dungeon state. The native adapter test separately verifies both enemy-layout tables match the selected source floor.'
                if ($retailDungeonSmokeReport.status -eq 'passed') { $retailGameplay.checkpoint += ' and entered the mod-owned floor through the native dungeon loader' }
            }
        }
        if ($retailGameplay.status -eq 'failed' -and $overallExitCode -eq 0) {
            $overallExitCode = if ($gameplayExitCode -ne 0) { $gameplayExitCode } else { 1 }
        }
    }

    if ($RetailLocationSmoke -and $port.Name -eq 'Chronicle' -and $retailDataRoot) {
        $locationRunRoot = Join-Path $buildDirectory ('retail-location-smoke-' + [Guid]::NewGuid().ToString('N'))
        $locationSave = Join-Path $locationRunRoot 'save'
        $locationPackage = Join-Path $locationSave 'mods\moonfactory.retail-location-probe'
        $locationResources = Join-Path $locationPackage 'resources'
        $entryScreenshot = Join-Path $locationRunRoot 'location-entry.png'
        $returnScreenshot = Join-Path $locationRunRoot 'location-return.png'
        $entryLog = Join-Path $locationRunRoot 'entry.log'
        $returnLog = Join-Path $locationRunRoot 'return.log'
        $sourceMapInfo = Join-Path $retailDataRoot 'gedit\s13\mapinfo.cfg'
        if (-not (Test-Path -LiteralPath $sourceMapInfo -PathType Leaf)) {
            throw "Chronicle location smoke requires the native s13 field script: $sourceMapInfo"
        }
        New-Item -ItemType Directory -Path $locationResources -Force | Out-Null
        Copy-Item -LiteralPath $sourceMapInfo -Destination (Join-Path $locationResources 'mapinfo.cfg')
        $locationFixture = Join-Path $PSScriptRoot 'tools\fixtures\retail-location-smoke\chronicle'
        foreach ($fixtureFile in Get-ChildItem -LiteralPath $locationFixture -File) {
            Copy-Item -LiteralPath $fixtureFile.FullName -Destination $locationPackage
        }
        $profileDirectory = Join-Path $locationSave 'moonmod'
        New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null
        [ordered]@{
            format_version = 1
            enabled = [ordered]@{ 'moonfactory.retail-location-probe' = $true }
            settings = [ordered]@{}
        } | ConvertTo-Json -Depth 5 -Compress | Set-Content -LiteralPath (Join-Path $profileDirectory 'profile.json') -Encoding utf8

        $retailLocationSmokeReport.location_id = 'moonfactory.retail-location-probe:copied-field'
        $retailLocationSmokeReport.source_map_id = 23
        $retailLocationSmokeReport.map_script_probe = 'Package-owned mapinfo.cfg copied from retail gedit/s13 into gedit/s60.'
        Write-Host 'Running Chronicle retail-data copied-field registration, entry, and render smoke...'
        $entryRun = Invoke-BoundedProcess $gameExecutable @('--data', $retailDataRoot, '--save', $locationSave,
            '--headless', '--offscreen', '--fast-load', '--frames', '240', '--jump', 'edit:0',
            '--screenshot', $entryScreenshot) $workspace $ProcessTimeoutSeconds
        $entryOutput = @($entryRun.output -split "`r?`n")
        $entryOutput | Set-Content -LiteralPath $entryLog -Encoding utf8
        foreach ($line in $entryOutput) { Write-Host $line }

        Write-Host 'Running Chronicle retail-data copied-field return-trip smoke...'
        $returnRun = Invoke-BoundedProcess $gameExecutable @('--data', $retailDataRoot, '--save', $locationSave,
            '--headless', '--offscreen', '--fast-load', '--frames', '700', '--jump', 'edit:0',
            '--screenshot', $returnScreenshot) $workspace $ProcessTimeoutSeconds
        $returnOutput = @($returnRun.output -split "`r?`n")
        $returnOutput | Set-Content -LiteralPath $returnLog -Encoding utf8
        foreach ($line in $returnOutput) { Write-Host $line }

        $entryScreenshotReady = (Test-Path -LiteralPath $entryScreenshot -PathType Leaf) -and
            (Get-Item -LiteralPath $entryScreenshot -ErrorAction SilentlyContinue).Length -gt 0
        $returnScreenshotReady = (Test-Path -LiteralPath $returnScreenshot -PathType Leaf) -and
            (Get-Item -LiteralPath $returnScreenshot -ErrorAction SilentlyContinue).Length -gt 0
        $expectedLocationId = 'chronicle:location:moonfactory.retail-location-probe:copied-field'
        $registeredLocationMarker = @($entryOutput | Where-Object {
            $_.Contains('MOONFACTORY_RETAIL_LOCATION_REGISTERED|' + $expectedLocationId + '|70')
        }) | Select-Object -First 1
        $queuedLocationMarker = @($entryOutput | Where-Object {
            $_.Contains('MOONFACTORY_RETAIL_LOCATION_QUEUED|70')
        }) | Select-Object -First 1
        $loadedLocationMarker = @($entryOutput | Where-Object {
            $_.Contains('MOONFACTORY_RETAIL_LOCATION_LOADED|' + $expectedLocationId + '|70')
        }) | Select-Object -First 1
        $queuedReturnMarker = @($returnOutput | Where-Object {
            $_.Contains('MOONFACTORY_RETAIL_LOCATION_RETURN_QUEUED|0')
        }) | Select-Object -First 1
        $returnedLocationMarker = @($returnOutput | Where-Object {
            $_.Contains('MOONFACTORY_RETAIL_LOCATION_RETURNED|' + $expectedLocationId + '|0')
        }) | Select-Object -First 1
        $locationChangedMarker = @($entryOutput | Where-Object {
            $_.Contains('MOONFACTORY_RETAIL_LOCATION_EVENT|entered|70')
        }) | Select-Object -First 1
        $returnLocationChangedMarker = @($returnOutput | Where-Object {
            $_.Contains('MOONFACTORY_RETAIL_LOCATION_EVENT|returned|0')
        }) | Select-Object -First 1
        $locationPassed = $entryRun.exit_code -eq 0 -and $returnRun.exit_code -eq 0 -and
            $entryScreenshotReady -and $returnScreenshotReady -and
            $null -ne $registeredLocationMarker -and $null -ne $queuedLocationMarker -and
            $null -ne $loadedLocationMarker -and $null -ne $queuedReturnMarker -and $null -ne $returnedLocationMarker -and
            $null -ne $locationChangedMarker -and $null -ne $returnLocationChangedMarker
        $retailLocationSmokeReport.status = if ($locationPassed) { 'passed' } else { 'failed' }
        $retailLocationSmokeReport.registered_map_index = if ($null -ne $loadedLocationMarker) { 70 } else { $null }
        $retailLocationSmokeReport.queued_marker = if ($null -ne $queuedLocationMarker) { $queuedLocationMarker.Trim() } else { $null }
        $retailLocationSmokeReport.loaded_marker = if ($null -ne $loadedLocationMarker) { $loadedLocationMarker.Trim() } else { $null }
        $retailLocationSmokeReport.return_queued_marker = if ($null -ne $queuedReturnMarker) { $queuedReturnMarker.Trim() } else { $null }
        $retailLocationSmokeReport.returned_marker = if ($null -ne $returnedLocationMarker) { $returnedLocationMarker.Trim() } else { $null }
        $retailLocationSmokeReport.location_changed_marker = if ($null -ne $locationChangedMarker) { $locationChangedMarker.Trim() } else { $null }
        $retailLocationSmokeReport.return_location_changed_marker = if ($null -ne $returnLocationChangedMarker) { $returnLocationChangedMarker.Trim() } else { $null }
        $retailLocationSmokeReport.data_root = $retailDataRoot
        $retailLocationSmokeReport.exit_code = $returnRun.exit_code
        $retailLocationSmokeReport.entry_exit_code = $entryRun.exit_code
        $retailLocationSmokeReport.timed_out = $entryRun.timed_out -or $returnRun.timed_out
        $retailLocationSmokeReport.entry_screenshot = $entryScreenshot
        $retailLocationSmokeReport.screenshot = $entryScreenshot
        $retailLocationSmokeReport.return_screenshot = $returnScreenshot
        $retailLocationSmokeReport.entry_log = $entryLog
        $retailLocationSmokeReport.log = $returnLog
        $retailLocationSmokeReport.note = 'Loads a copied native Chronicle mapinfo.cfg through an owner-controlled path under the reserved gedit/s60 directory, uses aliased native s13 assets, transitions to map 70, verifies entry and return location-change events, and returns to Norune. This verifies a compatible native map copy, not a wholly authored map format.'
        if (-not $locationPassed -and $overallExitCode -eq 0) {
            $overallExitCode = if ($entryRun.exit_code -ne 0) { $entryRun.exit_code }
                               elseif ($returnRun.exit_code -ne 0) { $returnRun.exit_code }
                               else { 1 }
        }
    }

    if ($RetailLocationSmoke -and $port.Name -eq 'ChronicleTwo' -and $retailDataRoot) {
        $locationRunRoot = Join-Path $buildDirectory ('retail-location-smoke-' + [Guid]::NewGuid().ToString('N'))
        $locationSave = Join-Path $locationRunRoot 'save'
        $locationPackage = Join-Path $locationSave 'mods\moonfactory.retail-location-probe'
        $locationResources = Join-Path $locationPackage 'resources'
        $entryScreenshot = Join-Path $locationRunRoot 'location-entry.png'
        $locationScreenshot = Join-Path $locationRunRoot 'location.png'
        $entryLog = Join-Path $locationRunRoot 'entry.log'
        $locationLog = Join-Path $locationRunRoot 'run.log'
        $nativeMapDirectory = Join-Path $retailDataRoot 'map\i\i01\h01'
        New-Item -ItemType Directory -Path $locationResources -Force | Out-Null
        foreach ($extension in @('map', 'cfg', 'stb')) {
            $sourceAsset = Join-Path $nativeMapDirectory ('i01h01.' + $extension)
            if (-not (Test-Path -LiteralPath $sourceAsset -PathType Leaf)) {
                throw "ChronicleTwo location smoke requires the retail map asset: $sourceAsset"
            }
            Copy-Item -LiteralPath $sourceAsset -Destination $locationResources
        }
        $mapScriptPath = Join-Path $locationResources 'i01h01.map'
        $mapScript = [System.IO.File]::ReadAllText($mapScriptPath, [System.Text.Encoding]::ASCII)
        $placementPattern = [regex]::new('(MAP_PARTS\s+"p01_i01h01",1;.*?PARTS_POS\s+)0,0,0;', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $placementMatch = $placementPattern.Match($mapScript)
        if (-not $placementMatch.Success) {
            throw 'ChronicleTwo location smoke could not find the expected native p01 map-part placement in i01h01.map'
        }
        $mapScript = $placementPattern.Replace($mapScript, '${1}4,0,0;', 1)
        if (-not $mapScript.Contains('PARTS_POS 4,0,0;')) {
            throw 'ChronicleTwo location smoke failed to author the p01 map-part position'
        }
        [System.IO.File]::WriteAllText($mapScriptPath, $mapScript, [System.Text.Encoding]::ASCII)
        $retailLocationSmokeReport.map_script_probe = 'Modified native MAP_PARTS script: p01_i01h01 offset +4 units on X.'
        $skyAsset = Join-Path $retailDataRoot 'map\def.sky'
        if (-not (Test-Path -LiteralPath $skyAsset -PathType Leaf)) {
            throw "ChronicleTwo location smoke requires the retail sky asset: $skyAsset"
        }
        Copy-Item -LiteralPath $skyAsset -Destination (Join-Path $locationResources 'def.sky')
        $locationFixture = Join-Path $PSScriptRoot 'tools\fixtures\retail-location-smoke\chronicle-two'
        foreach ($fixtureFile in Get-ChildItem -LiteralPath $locationFixture -File) {
            Copy-Item -LiteralPath $fixtureFile.FullName -Destination $locationPackage
        }
        $profileDirectory = Join-Path $locationSave 'moonmod'
        New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null
        [ordered]@{
            format_version = 1
            enabled = [ordered]@{ 'moonfactory.retail-location-probe' = $true }
            settings = [ordered]@{}
        } | ConvertTo-Json -Depth 5 -Compress | Set-Content -LiteralPath (Join-Path $profileDirectory 'profile.json') -Encoding utf8

        $retailLocationSmokeReport.location_id = 'moonfactory.retail-location-probe:copied-interior'
        $retailLocationSmokeReport.texture_source_map = 'i01h01'
        $retailLocationSmokeReport.reused_native_assets = @('.mpk', '.ipk')
        $retailLocationSmokeReport.map_script_probe = 'Modified native MAP_PARTS script: p01_i01h01 offset +4 units on X; .mpk/.ipk inherited from i01h01.'

        Write-Host 'Running ChronicleTwo retail-data modified-map entry and render smoke...'
        $entryRun = Invoke-BoundedProcess $gameExecutable @('--data', $retailDataRoot, '--save', $locationSave,
            '--headless', '--offscreen', '--fast-load', '--frames', '180', '--jump', 'town:10',
            '--screenshot', $entryScreenshot) $workspace $ProcessTimeoutSeconds
        $entryOutput = @($entryRun.output -split "`r?`n")
        $entryOutput | Set-Content -LiteralPath $entryLog -Encoding utf8
        foreach ($line in $entryOutput) { Write-Host $line }

        Write-Host 'Running ChronicleTwo retail-data copied-map return-trip smoke...'
        $locationRun = Invoke-BoundedProcess $gameExecutable @('--data', $retailDataRoot, '--save', $locationSave,
            '--headless', '--offscreen', '--fast-load', '--frames', '600', '--jump', 'town:10',
            '--screenshot', $locationScreenshot) $workspace $ProcessTimeoutSeconds
        $locationOutput = @($locationRun.output -split "`r?\n")
        $locationOutput | Set-Content -LiteralPath $locationLog -Encoding utf8
        foreach ($line in $locationOutput) { Write-Host $line }
        $locationScreenshotReady = (Test-Path -LiteralPath $locationScreenshot -PathType Leaf) -and
            (Get-Item -LiteralPath $locationScreenshot -ErrorAction SilentlyContinue).Length -gt 0
        $entryScreenshotReady = (Test-Path -LiteralPath $entryScreenshot -PathType Leaf) -and
            (Get-Item -LiteralPath $entryScreenshot -ErrorAction SilentlyContinue).Length -gt 0
        $expectedLocationId = 'chronicle-two:location:moonfactory.retail-location-probe:copied-interior'
        $registeredLocationMarker = @($entryOutput | Where-Object {
            $_.Contains('MOONFACTORY_RETAIL_LOCATION_REGISTERED|' + $expectedLocationId + '|')
        }) | Select-Object -First 1
        $queuedLocationMarker = @($entryOutput | Where-Object { $_.Contains('MOONFACTORY_RETAIL_LOCATION_QUEUED|') }) |
            Select-Object -First 1
        $loadedLocationMarker = @($entryOutput | Where-Object {
            $_.Contains('MOONFACTORY_RETAIL_LOCATION_LOADED|' + $expectedLocationId + '|')
        }) | Select-Object -First 1
        $queuedReturnMarker = @($locationOutput | Where-Object {
            $_.Contains('MOONFACTORY_RETAIL_LOCATION_RETURN_QUEUED|')
        }) | Select-Object -First 1
        $returnedLocationMarker = @($locationOutput | Where-Object {
            $_.Contains('MOONFACTORY_RETAIL_LOCATION_RETURNED|')
        }) | Select-Object -First 1
        $locationChangedMarker = @($entryOutput | Where-Object {
            $_.Contains('MOONFACTORY_RETAIL_LOCATION_EVENT|entered|')
        }) | Select-Object -First 1
        $returnLocationChangedMarker = @($locationOutput | Where-Object {
            $_.Contains('MOONFACTORY_RETAIL_LOCATION_EVENT|returned|')
        }) | Select-Object -First 1
        $queuedMapIndex = $null
        if ($null -ne $queuedLocationMarker) {
            $queuedFields = $queuedLocationMarker -split '\|'
            if ($queuedFields.Count -ge 2 -and $queuedFields[1] -match '^\d+$') {
                $queuedMapIndex = [int]$queuedFields[1]
            }
        }
        $loadedMapIndex = $null
        if ($null -ne $loadedLocationMarker) {
            $loadedFields = $loadedLocationMarker -split '\|'
            if ($loadedFields.Count -ge 3 -and $loadedFields[2] -match '^\d+$') {
                $loadedMapIndex = [int]$loadedFields[2]
            }
        }
        $locationPassed = $entryRun.exit_code -eq 0 -and $locationRun.exit_code -eq 0 -and
            $entryScreenshotReady -and $locationScreenshotReady -and
            $null -ne $registeredLocationMarker -and $null -ne $queuedLocationMarker -and
            $null -ne $loadedLocationMarker -and $null -ne $queuedReturnMarker -and
            $null -ne $returnedLocationMarker -and $null -ne $queuedMapIndex -and
            $queuedMapIndex -gt 0 -and $loadedMapIndex -eq $queuedMapIndex -and
            $null -ne $locationChangedMarker -and $null -ne $returnLocationChangedMarker
        $retailLocationSmokeReport.status = if ($locationPassed) { 'passed' } else { 'failed' }
        $retailLocationSmokeReport.registered_map_index = $loadedMapIndex
        $retailLocationSmokeReport.queued_marker = if ($null -ne $queuedLocationMarker) { $queuedLocationMarker.Trim() } else { $null }
        $retailLocationSmokeReport.loaded_marker = if ($null -ne $loadedLocationMarker) { $loadedLocationMarker.Trim() } else { $null }
        $retailLocationSmokeReport.return_queued_marker = if ($null -ne $queuedReturnMarker) { $queuedReturnMarker.Trim() } else { $null }
        $retailLocationSmokeReport.returned_marker = if ($null -ne $returnedLocationMarker) { $returnedLocationMarker.Trim() } else { $null }
        $retailLocationSmokeReport.location_changed_marker = if ($null -ne $locationChangedMarker) { $locationChangedMarker.Trim() } else { $null }
        $retailLocationSmokeReport.return_location_changed_marker = if ($null -ne $returnLocationChangedMarker) { $returnLocationChangedMarker.Trim() } else { $null }
        $retailLocationSmokeReport.data_root = $retailDataRoot
        $retailLocationSmokeReport.exit_code = $locationRun.exit_code
        $retailLocationSmokeReport.entry_exit_code = $entryRun.exit_code
        $retailLocationSmokeReport.timed_out = $entryRun.timed_out -or $locationRun.timed_out
        $retailLocationSmokeReport.entry_screenshot = $entryScreenshot
        $retailLocationSmokeReport.screenshot = $entryScreenshot
        $retailLocationSmokeReport.return_screenshot = $locationScreenshot
        $retailLocationSmokeReport.entry_log = $entryLog
        $retailLocationSmokeReport.log = $locationLog
        if (-not $locationPassed -and $overallExitCode -eq 0) {
            $overallExitCode = if ($entryRun.exit_code -ne 0) { $entryRun.exit_code }
                               elseif ($locationRun.exit_code -ne 0) { $locationRun.exit_code }
                               else { 1 }
        }
    }

    $portStatus = 'passed'
    if ($nativeExitCode -ne 0 -or
        ($port.Name -eq 'Chronicle' -and $preflightStatus -ne 'passed') -or
        ($port.Name -eq 'ChronicleTwo' -and $smokeStatus -ne 'passed') -or
        ($retailDataRoot -and $retailDataSmoke.status -ne 'passed') -or
        ($ManagerUiSmoke -and $retailDataRoot -and $managerUiSmokeReport.status -ne 'passed') -or
        (($RetailGameplaySmoke -or $RetailItemSmoke -or ($RetailCharacterSmoke -and $port.Name -in @('Chronicle', 'ChronicleTwo')) -or ($RetailGeoramaSmoke -and $port.Name -in @('Chronicle', 'ChronicleTwo'))) -and $retailDataRoot -and $retailGameplay.status -ne 'passed') -or
        ($RetailItemSmoke -and $retailDataRoot -and $retailItemSmokeReport.status -ne 'passed') -or
        ($RetailGeoramaSmoke -and $port.Name -in @('Chronicle', 'ChronicleTwo') -and $retailDataRoot -and $retailGeoramaSmokeReport.status -ne 'passed') -or
        ($RetailItemSmoke -and $port.Name -eq 'ChronicleTwo' -and $retailDataRoot -and
            $retailDungeonSmokeReport.status -ne 'passed') -or
        ($RetailDungeonSmoke -and $port.Name -eq 'Chronicle' -and $retailDataRoot -and
            $retailDungeonSmokeReport.status -ne 'passed') -or
        ($RetailCharacterSmoke -and $port.Name -in @('Chronicle', 'ChronicleTwo') -and $retailDataRoot -and
            ($retailCharacterSmokeReport.status -ne 'passed' -or $retailPhysicsSmokeReport.status -ne 'passed' -or
             $retailPhysicsQuerySmokeReport.status -ne 'passed')) -or
        ($RetailLocationSmoke -and $port.Name -in @('Chronicle', 'ChronicleTwo') -and $retailDataRoot -and
            $retailLocationSmokeReport.status -ne 'passed')) {
        $portStatus = 'failed'
        if ($overallExitCode -eq 0) { $overallExitCode = 1 }
    }
    $portReports.Add([ordered]@{
        name = $port.Name
        status = $portStatus
        native_tests = [ordered]@{
            status = if ($nativeExitCode -eq 0) { 'passed' } else { 'failed' }
            exit_code = $nativeExitCode
            executed = $nativeCases.Count
            passed = $nativePassed
            failed = $nativeFailed
            cases = @($nativeCases)
        }
        headless_smoke = $smokeStatus
        retail_data_smoke = $retailDataSmoke
        manager_ui_smoke = $managerUiSmokeReport
        retail_location_smoke = $retailLocationSmokeReport
        retail_gameplay_smoke = $retailGameplay
        retail_item_smoke = $retailItemSmokeReport
        retail_georama_smoke = $retailGeoramaSmokeReport
        retail_dungeon_smoke = $retailDungeonSmokeReport
        retail_character_smoke = $retailCharacterSmokeReport
        retail_physics_smoke = $retailPhysicsSmokeReport
        retail_physics_query_smoke = $retailPhysicsQuerySmokeReport
        headless_preflight = $preflightReport
        headless_determinism = $headlessDeterminism
        api_catalog = $apiCatalog
    })
}

$reportDirectory = Join-Path $PSScriptRoot 'artifacts'
New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
$reportPath = Join-Path $reportDirectory 'verification-report.json'
$report = [ordered]@{
    format_version = 1
    generated_at_utc = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    status = if ($overallExitCode -eq 0) { 'passed' } else { 'failed' }
    python_tests = [ordered]@{
        status = if ($pythonExitCode -eq 0) { 'passed' } else { 'failed' }
        executed = $pythonCases.Count
        passed = @($pythonCases | Where-Object status -eq 'passed').Count
        failed = @($pythonCases | Where-Object status -eq 'failed').Count
        cases = @($pythonCases)
    }
    ports = @($portReports)
}
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding utf8
if ($overallExitCode -ne 0) {
    Write-Host "MoonFactory headless verification failed. Report: $reportPath"
    exit $overallExitCode
}
Write-Host "MoonFactory headless verification passed for both ports. Report: $reportPath"
