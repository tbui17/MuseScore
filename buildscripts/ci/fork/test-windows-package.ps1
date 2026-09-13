#!/usr/bin/env pwsh
# SPDX-License-Identifier: GPL-3.0-only
#
# MuseScore fork CI: fresh-runner Windows package runtime helper.
#
# Runs on a runner that has NO Qt installation. It verifies the downloaded
# package against its manifest/checksums, extracts it outside the source and
# build trees, then exercises the real installed application:
#
#   1. structural checks (executable, Qt runtime, resources, installed tests)
#   2. bounded `--version` check with output assertion (a spawn is not success)
#   3. bounded headless exports through the revision's `-o` converter path: a PDF
#      (exercises layout, rendering and font embedding) and a score container
#      (MSCZ opened as a ZIP and required to carry the score XML)
#   4. GUI testflow TC11 + TC14 through `--test-case-gui`: the reviewed script from the
#      source checkout must be present, the run must exit 0, and the testflow runner must
#      have recorded the test case under the helper-owned MUSE_TESTFLOW_DATA_PATH
#
# Developer Qt/QML environment overrides and development Qt search paths are
# removed for every child process; the profile is isolated from the user's own
# MuseScore settings. Every process is timeout-bounded and its tree is killed on
# timeout, with stdout/stderr and application logs retained.
#
# What this proves: the distribution package is self-contained enough to start,
# export, and run its GUI regression tests without a developer Qt install.
# What it does NOT prove: behavior on a minimal end-user Windows installation,
# or NVDA/JAWS/physical Braille-device announcement behavior.
#
# Usage:
#   pwsh -File buildscripts/ci/fork/test-windows-package.ps1 `
#       -ArtifactDirectory <dir with zip + SHA256SUMS.txt + build-manifest.json> `
#       -SourceDirectory   <same source_sha checkout; fixtures only> `
#       -OutputDirectory   <logs, isolated profile, extraction, report>

[CmdletBinding()]
param(
    [string] $ArtifactDirectory,
    [string] $SourceDirectory,
    [string] $OutputDirectory,
    [int] $VersionTimeoutSeconds = 60,
    [int] $ExportTimeoutSeconds = 300,
    [int] $GuiTimeoutSeconds = 600
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:IsWindowsHost = ($env:OS -eq 'Windows_NT')
$script:Failures = @()
$script:Results = @()

$script:RequiredTestScripts = @(
    'TC11_CommandPaletteDialog.js'
    'TC14_CommandPaletteAnnounce.js'
)

# The testflow runner records each executed test case under
# <MUSE_TESTFLOW_DATA_PATH>/reports. Pointing that at the helper's own output directory
# makes the record of the run helper-owned evidence instead of a path inside the package.
$script:TestflowDataRelative = 'testflow-data'

# Developer-only Qt/QML environment overrides that must not leak into the test.
$script:QtEnvironmentVariables = @(
    'QTDIR'
    'QT_PLUGIN_PATH'
    'QT_QPA_PLATFORM_PLUGIN_PATH'
    'QML_IMPORT_PATH'
    'QML2_IMPORT_PATH'
    'QT_QML_IMPORT_PATH'
    'QT_QPA_PLATFORM'
    'QT_QUICK_BACKEND'
    'QT_SCALE_FACTOR'
    'MUSE_TESTFLOW_SCRIPTS_PATH'
    'MUSE_TESTFLOW_FILES_PATH'
)

function Fail {
    param([Parameter(Mandatory = $true)][string] $Message)
    throw "test-windows-package: $Message"
}

function Add-Failure {
    param([Parameter(Mandatory = $true)][string] $Message)
    Write-Host "FAIL: $Message"
    $script:Failures += $Message
}

function Add-Result {
    param([Parameter(Mandatory = $true)][hashtable] $Result)
    $script:Results += $Result
}

function Write-Section {
    param([Parameter(Mandatory = $true)][string] $Message)
    Write-Host "== $Message"
}

function Get-JsonField {
    param(
        [Parameter(Mandatory = $false)] $Object,
        [Parameter(Mandatory = $true)][string] $Name
    )

    if ($null -eq $Object) {
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Fail "cannot hash missing file: $Path"
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Resolve-RequiredDirectory {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $Name
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        Fail "-$Name is required"
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Fail "-$Name directory not found: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
}

function Resolve-FullPath {
    param([Parameter(Mandatory = $true)][string] $Path)
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
}

function Test-PathInside {
    param(
        [Parameter(Mandatory = $true)][string] $Parent,
        [Parameter(Mandatory = $true)][string] $Child
    )

    $parentFull = Resolve-FullPath -Path $Parent
    $childFull = Resolve-FullPath -Path $Child
    $separator = [IO.Path]::DirectorySeparatorChar
    return $childFull.StartsWith("$parentFull$separator", [StringComparison]::OrdinalIgnoreCase)
}

function Assert-ZipEntrySafe {
    param([Parameter(Mandatory = $true)][string] $EntryName)

    $normalized = $EntryName -replace '\\', '/'
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        Fail 'path is empty'
    }
    if ($normalized.StartsWith('/') -or $normalized -match '^[A-Za-z]:') {
        Fail "absolute path is not allowed: $EntryName"
    }
    foreach ($segment in $normalized.Split('/')) {
        if ($segment -eq '..') {
            Fail "path escapes the extraction root: $EntryName"
        }
    }
}

function Read-VersionCmake {
    param([Parameter(Mandatory = $true)][string] $Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    $text = Get-Content -LiteralPath $Path -Raw
    $values = @{}
    foreach ($name in @('MUSE_APP_NAME_MACHINE_READABLE', 'MUSE_APP_VERSION_MAJOR', 'MUSE_APP_VERSION_MINOR', 'MUSE_APP_VERSION_PATCH', 'MUSE_APP_UNSTABLE')) {
        $pattern = "(?m)^\s*set\(\s*$name\s+""?([^""\)\r\n]+)""?\s*\)"
        $match = [regex]::Match($text, $pattern)
        if ($match.Success) {
            $values[$name] = $match.Groups[1].Value.Trim()
        }
    }
    return $values
}

function Get-GitHead {
    param([Parameter(Mandatory = $true)][string] $Directory)

    if (-not (Test-Path -LiteralPath (Join-Path $Directory '.git'))) {
        Fail "-SourceDirectory is not a git checkout (no .git): $Directory"
    }
    $head = & git -C $Directory rev-parse HEAD 2>&1
    if ($LASTEXITCODE -ne 0) {
        Fail "git rev-parse HEAD failed in $Directory (exit $LASTEXITCODE): $head"
    }
    return ($head | Select-Object -First 1).ToString().Trim()
}

function Get-EnvValue {
    param(
        [Parameter(Mandatory = $true)][System.Diagnostics.ProcessStartInfo] $StartInfo,
        [Parameter(Mandatory = $true)][string] $Name
    )

    foreach ($key in @($StartInfo.Environment.Keys)) {
        if ($key.Equals($Name, [StringComparison]::OrdinalIgnoreCase)) {
            return $StartInfo.Environment[$key]
        }
    }
    return $null
}

function Remove-EnvValue {
    param(
        [Parameter(Mandatory = $true)][System.Diagnostics.ProcessStartInfo] $StartInfo,
        [Parameter(Mandatory = $true)][string] $Name
    )

    foreach ($key in @($StartInfo.Environment.Keys)) {
        if ($key.Equals($Name, [StringComparison]::OrdinalIgnoreCase)) {
            $StartInfo.Environment.Remove($key) | Out-Null
        }
    }
}

function Set-EnvValue {
    param(
        [Parameter(Mandatory = $true)][System.Diagnostics.ProcessStartInfo] $StartInfo,
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][string] $Value
    )

    Remove-EnvValue -StartInfo $StartInfo -Name $Name
    $StartInfo.Environment[$Name] = $Value
}

# Builds a child environment with developer Qt/QML overrides and Qt search
# paths removed, an isolated profile, and the documented software-rendering
# accommodation. Returns the number of PATH entries and variables removed.
function New-ChildProcessStartInfo {
    param(
        [Parameter(Mandatory = $true)][string] $Executable,
        [Parameter(Mandatory = $true)][string] $WorkingDirectory,
        [Parameter(Mandatory = $true)][string] $IsolatedAppData,
        [Parameter(Mandatory = $true)][string] $IsolatedLocalAppData
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Executable
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true

    $removedVariables = 0
    foreach ($name in $script:QtEnvironmentVariables) {
        if ($null -ne (Get-EnvValue -StartInfo $startInfo -Name $name)) {
            Remove-EnvValue -StartInfo $startInfo -Name $name
            $removedVariables++
        }
    }

    $pathSeparator = [IO.Path]::PathSeparator
    $pathValue = Get-EnvValue -StartInfo $startInfo -Name 'PATH'
    $removedPathEntries = 0
    if ($null -ne $pathValue) {
        $kept = @()
        foreach ($entry in ($pathValue -split [regex]::Escape($pathSeparator))) {
            if ([string]::IsNullOrWhiteSpace($entry)) {
                continue
            }
            $isQt = $false
            foreach ($segment in ($entry -split '[\\/]')) {
                if ($segment -match '^(?i)qt') {
                    $isQt = $true
                    break
                }
            }
            if ($isQt) {
                Write-Host "   cleared Qt PATH entry: $entry"
                $removedPathEntries++
            } else {
                $kept += $entry
            }
        }
        Set-EnvValue -StartInfo $startInfo -Name 'PATH' -Value ($kept -join $pathSeparator)
    }

    Set-EnvValue -StartInfo $startInfo -Name 'APPDATA' -Value $IsolatedAppData
    Set-EnvValue -StartInfo $startInfo -Name 'LOCALAPPDATA' -Value $IsolatedLocalAppData
    Set-EnvValue -StartInfo $startInfo -Name 'MUSE_TESTFLOW_DATA_PATH' -Value $script:TestflowDataRoot
    Set-EnvValue -StartInfo $startInfo -Name 'QT_QUICK_BACKEND' -Value 'software'
    Set-EnvValue -StartInfo $startInfo -Name 'QT_COMMAND_LINE_PARSER_NO_GUI_MESSAGE_BOXES' -Value '1'

    return @{
        StartInfo              = $startInfo
        RemovedVariables       = $removedVariables
        RemovedPathEntries     = $removedPathEntries
    }
}

function Stop-ProcessTree {
    param([Parameter(Mandatory = $true)][System.Diagnostics.Process] $Process)

    if ($Process.HasExited) {
        return
    }

    if ($script:IsWindowsHost) {
        & taskkill.exe /PID $Process.Id /T /F 2>&1 | Out-Null
    } else {
        & pkill -TERM -P $Process.Id 2>&1 | Out-Null
        & kill -TERM $Process.Id 2>&1 | Out-Null
        Start-Sleep -Milliseconds 500
        & pkill -KILL -P $Process.Id 2>&1 | Out-Null
        & kill -KILL $Process.Id 2>&1 | Out-Null
    }

    try {
        $Process.WaitForExit(10000) | Out-Null
    } catch {
        # Process already reaped.
    }
}

function Invoke-BoundedProcess {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][string] $Executable,
        [Parameter(Mandatory = $true)][string[]] $Arguments,
        [Parameter(Mandatory = $true)][string] $WorkingDirectory,
        [Parameter(Mandatory = $true)][string] $IsolatedAppData,
        [Parameter(Mandatory = $true)][string] $IsolatedLocalAppData,
        [Parameter(Mandatory = $true)][int] $TimeoutSeconds,
        [Parameter(Mandatory = $true)][string] $LogRoot
    )

    $startInfoResult = New-ChildProcessStartInfo -Executable $Executable -WorkingDirectory $WorkingDirectory `
        -IsolatedAppData $IsolatedAppData -IsolatedLocalAppData $IsolatedLocalAppData
    $startInfo = $startInfoResult.StartInfo
    foreach ($argument in $Arguments) {
        $startInfo.ArgumentList.Add($argument)
    }

    $stdoutPath = Join-Path $LogRoot "$Name.stdout.log"
    $stderrPath = Join-Path $LogRoot "$Name.stderr.log"
    Write-Host "> $Executable $($Arguments -join ' ')"
    Write-Host "   timeout ${TimeoutSeconds}s, log $stdoutPath"

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $null = $process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()

    $timedOut = $false
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        $timedOut = $true
        Write-Host "   TIMEOUT after ${TimeoutSeconds}s; killing process tree"
        Stop-ProcessTree -Process $process
    }

    try {
        $process.WaitForExit()
    } catch {
        # Already exited.
    }

    $stdout = ''
    $stderr = ''
    try { $stdout = $stdoutTask.GetAwaiter().GetResult() } catch { $stdout = '' }
    try { $stderr = $stderrTask.GetAwaiter().GetResult() } catch { $stderr = '' }

    [IO.File]::WriteAllText($stdoutPath, $stdout, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($stderrPath, $stderr, [Text.UTF8Encoding]::new($false))

    $exitCode = $null
    if (-not $timedOut) {
        $exitCode = $process.ExitCode
    }
    $process.Dispose()

    return @{
        Name           = $Name
        Executable     = $Executable
        Arguments      = $Arguments
        TimedOut       = $timedOut
        ExitCode       = $exitCode
        Stdout         = $stdout
        Stderr         = $stderr
        StdoutLog      = $stdoutPath
        StderrLog      = $stderrPath
        RemovedPathEntries = $startInfoResult.RemovedPathEntries
        RemovedVariables   = $startInfoResult.RemovedVariables
    }
}

# ---------------------------------------------------------------------------
# Preflight: manifest, checksums, identities, extraction
# ---------------------------------------------------------------------------
$artifactRoot = Resolve-RequiredDirectory -Path $ArtifactDirectory -Name 'ArtifactDirectory'
$sourceRoot = Resolve-RequiredDirectory -Path $SourceDirectory -Name 'SourceDirectory'

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    Fail '-OutputDirectory is required'
}
$outputRoot = Resolve-FullPath -Path $OutputDirectory
# The helper recreates directories under -OutputDirectory, so it must not be able to land on
# (or inside) an input it does not own.
foreach ($protected in @($sourceRoot, $artifactRoot)) {
    if ($outputRoot -ieq $protected -or (Test-PathInside -Parent $protected -Child $outputRoot)) {
        Fail "-OutputDirectory must not be -SourceDirectory/-ArtifactDirectory or inside them ($outputRoot)"
    }
}
if (Test-PathInside -Parent $outputRoot -Child $artifactRoot) {
    Fail "-ArtifactDirectory must not be inside -OutputDirectory ($artifactRoot)"
}
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null

$extractRoot = Join-Path $outputRoot 'extract'
$logRoot = Join-Path $outputRoot 'logs'
$profileRoot = Join-Path $outputRoot 'profile'
$exportRoot = Join-Path $outputRoot 'export'
$script:TestflowDataRoot = Join-Path $outputRoot $script:TestflowDataRelative
foreach ($dir in @($extractRoot, $logRoot, $profileRoot, $exportRoot, $script:TestflowDataRoot)) {
    # Only helper-owned directories strictly below -OutputDirectory are ever removed.
    if (-not (Test-PathInside -Parent $outputRoot -Child $dir)) {
        Fail "refusing to remove '$dir': it is not inside -OutputDirectory ($outputRoot)"
    }
    if (Test-Path -LiteralPath $dir) {
        Remove-Item -LiteralPath $dir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

Write-Section 'Verifying package metadata'
$manifestPath = Join-Path $artifactRoot 'build-manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    Fail "build-manifest.json not found in $artifactRoot"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($null -eq $manifest) {
    Fail "build-manifest.json is not valid JSON: $manifestPath"
}

$packageInfo = Get-JsonField -Object $manifest -Name 'package'
if ($null -eq $packageInfo) {
    Fail 'manifest is missing the package object'
}
$packageFileName = [string] (Get-JsonField -Object $packageInfo -Name 'filename')
$packageSize = Get-JsonField -Object $packageInfo -Name 'size'
$packageSha = [string] (Get-JsonField -Object $packageInfo -Name 'sha256')
if ([string]::IsNullOrWhiteSpace($packageFileName) -or $null -eq $packageSize -or [string]::IsNullOrWhiteSpace($packageSha)) {
    Fail 'manifest package object is missing filename/size/sha256'
}

# The manifest is untrusted input: bound every path taken from it before it is joined to a
# directory, and derive the executable from the source metadata as well instead of accepting
# whatever the manifest names.
$executableRelativePath = [string] (Get-JsonField -Object $manifest -Name 'executable')
if ([string]::IsNullOrWhiteSpace($executableRelativePath)) {
    Fail 'manifest is missing the executable relative path'
}
Assert-ZipEntrySafe -EntryName $executableRelativePath
$sourceVersion = Read-VersionCmake -Path (Join-Path $sourceRoot 'version.cmake')
if ($null -eq $sourceVersion -or -not $sourceVersion.ContainsKey('MUSE_APP_NAME_MACHINE_READABLE') -or -not $sourceVersion.ContainsKey('MUSE_APP_VERSION_MAJOR')) {
    Fail "-SourceDirectory does not provide a usable version.cmake: $sourceRoot"
}
$derivedExecutableRelativePath = "bin/$($sourceVersion['MUSE_APP_NAME_MACHINE_READABLE'])$($sourceVersion['MUSE_APP_VERSION_MAJOR']).exe"
if (($executableRelativePath -replace '\\', '/') -ne $derivedExecutableRelativePath) {
    Fail "manifest executable '$executableRelativePath' does not match '$derivedExecutableRelativePath' derived from the source checkout"
}
$resourceExpectations = @(Get-JsonField -Object $manifest -Name 'resource_expectations')
if ($resourceExpectations.Count -eq 0) {
    Fail 'manifest resource_expectations is empty'
}
foreach ($expectation in $resourceExpectations) {
    Assert-ZipEntrySafe -EntryName ([string] $expectation)
}

$zips = @(Get-ChildItem -LiteralPath $artifactRoot -File -Filter '*.zip' -ErrorAction SilentlyContinue)
if ($zips.Count -ne 1) {
    Fail "expected exactly one package in $artifactRoot, found $($zips.Count): $($zips.Name -join ', ')"
}
if ($zips[0].Name -ne $packageFileName) {
    Fail "artifact directory contains '$($zips[0].Name)' but the manifest names '$packageFileName'"
}
$packagePath = $zips[0].FullName

$actualSize = (Get-Item -LiteralPath $packagePath).Length
if ([int64] $actualSize -ne [int64] $packageSize) {
    Fail "package size mismatch: manifest $packageSize, actual $actualSize"
}
$actualSha = Get-Sha256 -Path $packagePath
if ($actualSha -ne $packageSha.ToLowerInvariant()) {
    Fail "package sha256 mismatch: manifest $packageSha, actual $actualSha"
}

$sumsPath = Join-Path $artifactRoot 'SHA256SUMS.txt'
if (-not (Test-Path -LiteralPath $sumsPath -PathType Leaf)) {
    Fail "SHA256SUMS.txt not found in $artifactRoot"
}
$sumsLines = @(Get-Content -LiteralPath $sumsPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($sumsLines.Count -ne 1) {
    Fail "SHA256SUMS.txt must contain exactly one line, found $($sumsLines.Count)"
}
$sumsMatch = [regex]::Match($sumsLines[0], '^([0-9a-f]{64})  (\S+)$')
if (-not $sumsMatch.Success) {
    Fail "SHA256SUMS.txt line is not '<lowercase sha256>  <filename>': $($sumsLines[0])"
}
if ($sumsMatch.Groups[2].Value -ne $packageFileName) {
    Fail "SHA256SUMS.txt names '$($sumsMatch.Groups[2].Value)' but the manifest names '$packageFileName'"
}
if ($sumsMatch.Groups[1].Value -ne $actualSha) {
    Fail "SHA256SUMS.txt hash '$($sumsMatch.Groups[1].Value)' does not match the package hash '$actualSha'"
}

Write-Section 'Verifying source/workflow identity'
$manifestSourceSha = ([string] (Get-JsonField -Object $manifest -Name 'source_sha')).Trim()
if ($manifestSourceSha -notmatch '^[0-9a-fA-F]{7,40}$') {
    Fail "manifest source_sha is not a git object id: '$manifestSourceSha'"
}
$headSha = Get-GitHead -Directory $sourceRoot
if ($headSha.ToLowerInvariant() -ne $manifestSourceSha.ToLowerInvariant()) {
    Fail "-SourceDirectory HEAD ($headSha) does not match manifest source_sha ($manifestSourceSha)"
}
Write-Host "source_sha confirmed against fixture checkout: $headSha"

$manifestWorkflowSha = ([string] (Get-JsonField -Object $manifest -Name 'workflow_sha')).Trim()
if (-not [string]::IsNullOrWhiteSpace($env:MUSE_EXPECTED_WORKFLOW_SHA)) {
    if ($manifestWorkflowSha.ToLowerInvariant() -ne $env:MUSE_EXPECTED_WORKFLOW_SHA.Trim().ToLowerInvariant()) {
        Fail "manifest workflow_sha '$manifestWorkflowSha' does not match MUSE_EXPECTED_WORKFLOW_SHA '$($env:MUSE_EXPECTED_WORKFLOW_SHA)'"
    }
    Write-Host "workflow_sha confirmed against MUSE_EXPECTED_WORKFLOW_SHA"
} else {
    Write-Host 'MUSE_EXPECTED_WORKFLOW_SHA not set; workflow_sha not cross-checked here'
}

$manifestFrameworkSha = ([string] (Get-JsonField -Object $manifest -Name 'framework_sha')).Trim()
if (-not [string]::IsNullOrWhiteSpace($env:MUSE_EXPECTED_FRAMEWORK_SHA)) {
    if ($manifestFrameworkSha.ToLowerInvariant() -ne $env:MUSE_EXPECTED_FRAMEWORK_SHA.Trim().ToLowerInvariant()) {
        Fail "manifest framework_sha '$manifestFrameworkSha' does not match MUSE_EXPECTED_FRAMEWORK_SHA '$($env:MUSE_EXPECTED_FRAMEWORK_SHA)'"
    }
    Write-Host 'framework_sha confirmed against MUSE_EXPECTED_FRAMEWORK_SHA'
} else {
    Write-Host 'MUSE_EXPECTED_FRAMEWORK_SHA not set; framework_sha not cross-checked here'
}

Write-Section 'Extracting package outside the source tree'
if (Test-Path -LiteralPath $extractRoot) {
    Remove-Item -LiteralPath $extractRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null

$archive = [System.IO.Compression.ZipFile]::OpenRead($packagePath)
try {
    foreach ($entry in $archive.Entries) {
        Assert-ZipEntrySafe -EntryName $entry.FullName
    }
} finally {
    $archive.Dispose()
}
[System.IO.Compression.ZipFile]::ExtractToDirectory($packagePath, $extractRoot)

$executableFullPath = Join-Path $extractRoot ($executableRelativePath -replace '/', [IO.Path]::DirectorySeparatorChar)
if (-not (Test-Path -LiteralPath $executableFullPath -PathType Leaf)) {
    Fail "extracted package is missing the executable '$executableRelativePath'"
}
if (Test-PathInside -Parent $sourceRoot -Child $executableFullPath) {
    Fail 'the tested executable resolved inside the source tree; tests must run from the extracted package'
}

Write-Section 'Structural checks on the extracted package'
foreach ($expectation in $resourceExpectations) {
    $relative = ([string] $expectation) -replace '\\', '/'
    $full = Join-Path $extractRoot ($relative -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $full)) {
        Add-Failure "extracted package is missing manifest resource '$relative'"
    }
}
$qtDlls = @(Get-ChildItem -LiteralPath (Join-Path $extractRoot 'bin') -File -Filter 'Qt6*.dll' -ErrorAction SilentlyContinue)
if ($qtDlls.Count -eq 0) {
    Add-Failure 'extracted package contains no Qt6*.dll runtime libraries in bin/'
}
Write-Host "manifest resource expectations verified: $($resourceExpectations.Count) paths, $($qtDlls.Count) Qt6 DLLs in bin/"

# ---------------------------------------------------------------------------
# Isolated profile
# ---------------------------------------------------------------------------
Write-Section 'Seeding isolated profile'
$isolatedAppData = Join-Path $profileRoot 'AppData/Roaming'
$isolatedLocalAppData = Join-Path $profileRoot 'AppData/Local'
New-Item -ItemType Directory -Path (Join-Path $isolatedAppData 'MuseScore') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $isolatedLocalAppData 'MuseScore') -Force | Out-Null

$version = Read-VersionCmake -Path (Join-Path $sourceRoot 'version.cmake')
$applicationVersion = [string] (Get-JsonField -Object $manifest -Name 'application_version')
$versionParts = ($applicationVersion -split '\.')
$welcomeVersion = $applicationVersion
if ($versionParts.Count -ge 3) {
    $welcomeVersion = "$($versionParts[0]).$($versionParts[1]).$($versionParts[2])"
}

$settingsNames = @('MuseScoreStudio5Development', 'MuseScoreStudio5')
if ($null -ne $version -and $version.ContainsKey('MUSE_APP_NAME_MACHINE_READABLE') -and $version.ContainsKey('MUSE_APP_VERSION_MAJOR')) {
    $baseName = "$($version['MUSE_APP_NAME_MACHINE_READABLE'])$($version['MUSE_APP_VERSION_MAJOR'])"
    if ($version['MUSE_APP_UNSTABLE'] -eq 'ON') {
        $settingsNames = @("${baseName}Development", $baseName)
    } else {
        $settingsNames = @($baseName, "${baseName}Development")
    }
}
$iniContent = "[application]`r`nhasCompletedFirstLaunchSetup=true`r`nwelcomeDialogShowOnStartup=false`r`nwelcomeDialogLastShownVersion=$welcomeVersion`r`n"
foreach ($settingsName in ($settingsNames | Select-Object -Unique)) {
    $iniPath = Join-Path (Join-Path $isolatedAppData 'MuseScore') "$settingsName.ini"
    [IO.File]::WriteAllText($iniPath, $iniContent, [Text.UTF8Encoding]::new($false))
    Write-Host "seeded $iniPath"
}

$expectedAppName = ($settingsNames | Select-Object -First 1)

# ---------------------------------------------------------------------------
# 1. Bounded version check
# ---------------------------------------------------------------------------
Write-Section 'CLI version check (bounded, output asserted)'
$versionResult = Invoke-BoundedProcess -Name 'version' -Executable $executableFullPath -Arguments @('--version') `
    -WorkingDirectory $extractRoot -IsolatedAppData $isolatedAppData -IsolatedLocalAppData $isolatedLocalAppData `
    -TimeoutSeconds $VersionTimeoutSeconds -LogRoot $logRoot
$versionOutput = "$($versionResult.Stdout)`n$($versionResult.Stderr)"
$versionOk = $false
if ($versionResult.TimedOut) {
    Add-Failure "--version timed out after ${VersionTimeoutSeconds}s (log $($versionResult.StdoutLog))"
} elseif ($versionResult.ExitCode -ne 0) {
    Add-Failure "--version exited with $($versionResult.ExitCode) (log $($versionResult.StdoutLog))"
} elseif ($versionOutput -notmatch 'MuseScoreStudio\S*\s+\d+\.\d+\.\d+') {
    Add-Failure "--version produced no recognisable version banner; a spawned process is not a passing test (log $($versionResult.StdoutLog))"
} elseif (-not [string]::IsNullOrWhiteSpace($welcomeVersion) -and $versionOutput -notmatch [regex]::Escape($welcomeVersion)) {
    Add-Failure "--version output does not contain manifest application_version $welcomeVersion (log $($versionResult.StdoutLog))"
} else {
    Write-Host "version banner: $($versionResult.Stdout.Trim())"
    $versionOk = $true
}
Add-Result -Result @{ name = 'version'; argv = @('--version'); exit_code = $versionResult.ExitCode; timed_out = $versionResult.TimedOut; ok = $versionOk; log = $versionResult.StdoutLog }

# ---------------------------------------------------------------------------
# 2. Bounded headless exports
# ---------------------------------------------------------------------------
Write-Section 'Headless exports (PDF document + score container)'
$fixtureCandidates = @(
    (Join-Path $sourceRoot 'vtest/scores/layout-5.mscx')
    (Join-Path $sourceRoot 'vtest/scores_small/test.mscx')
    (Join-Path $sourceRoot 'vtest/scores_small/Pitch.mscz')
)
$fixture = $null
foreach ($candidate in $fixtureCandidates) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $fixture = $candidate
        break
    }
}
if ($null -eq $fixture) {
    Add-Failure "no committed score fixture found under -SourceDirectory (looked for: $($fixtureCandidates -join ', '))"
} else {
    Write-Host "fixture: $fixture"
    # PDF: layout, painting and the embedded music/text fonts, i.e. the application renders
    # the score instead of only re-serialising it.
    $pdfPath = Join-Path $exportRoot 'exported-score.pdf'
    $pdfResult = Invoke-BoundedProcess -Name 'export-pdf' -Executable $executableFullPath `
        -Arguments @('-o', $pdfPath, $fixture) `
        -WorkingDirectory $exportRoot -IsolatedAppData $isolatedAppData -IsolatedLocalAppData $isolatedLocalAppData `
        -TimeoutSeconds $ExportTimeoutSeconds -LogRoot $logRoot

    $pdfOk = $false
    if ($pdfResult.TimedOut) {
        Add-Failure "PDF export timed out after ${ExportTimeoutSeconds}s (log $($pdfResult.StdoutLog))"
    } elseif ($pdfResult.ExitCode -ne 0) {
        Add-Failure "PDF export exited with $($pdfResult.ExitCode) (log $($pdfResult.StderrLog))"
    } elseif (-not (Test-Path -LiteralPath $pdfPath -PathType Leaf)) {
        Add-Failure 'PDF export reported success but wrote no output file'
    } else {
        $pdfSize = (Get-Item -LiteralPath $pdfPath).Length
        if ($pdfSize -le 0) {
            Add-Failure 'PDF export produced an empty output file'
        } else {
            # Only the five header bytes are read; the exported file is never buffered whole.
            $header = New-Object byte[] 5
            $headerRead = 0
            $pdfStream = [IO.File]::OpenRead($pdfPath)
            try { $headerRead = $pdfStream.Read($header, 0, 5) } finally { $pdfStream.Dispose() }
            $signature = ''
            if ($headerRead -eq 5) { $signature = [Text.Encoding]::ASCII.GetString($header) }
            if ($signature -ne '%PDF-') {
                Add-Failure "exported PDF is not a PDF document (header '$signature')"
            } else {
                Write-Host "PDF export OK: $pdfPath ($pdfSize bytes, rendered document)"
                $pdfOk = $true
            }
        }
    }
    Add-Result -Result @{ name = 'export-pdf'; argv = @('-o', $pdfPath, $fixture); exit_code = $pdfResult.ExitCode; timed_out = $pdfResult.TimedOut; ok = $pdfOk; log = $pdfResult.StdoutLog }

    # Score container: opened as a ZIP and required to carry the score XML, not merely a
    # two-byte file signature.
    $msczPath = Join-Path $exportRoot 'exported-score.mscz'
    $msczResult = Invoke-BoundedProcess -Name 'export-mscz' -Executable $executableFullPath `
        -Arguments @('-o', $msczPath, $fixture) `
        -WorkingDirectory $exportRoot -IsolatedAppData $isolatedAppData -IsolatedLocalAppData $isolatedLocalAppData `
        -TimeoutSeconds $ExportTimeoutSeconds -LogRoot $logRoot

    $msczOk = $false
    if ($msczResult.TimedOut) {
        Add-Failure "score container export timed out after ${ExportTimeoutSeconds}s (log $($msczResult.StdoutLog))"
    } elseif ($msczResult.ExitCode -ne 0) {
        Add-Failure "score container export exited with $($msczResult.ExitCode) (log $($msczResult.StderrLog))"
    } elseif (-not (Test-Path -LiteralPath $msczPath -PathType Leaf)) {
        Add-Failure 'score container export reported success but wrote no output file'
    } else {
        $entryNames = @()
        $scoreXmlEntries = @()
        $openError = $null
        try {
            $scoreArchive = [System.IO.Compression.ZipFile]::OpenRead($msczPath)
            try {
                foreach ($entry in $scoreArchive.Entries) {
                    $entryNames += $entry.FullName
                    if ($entry.FullName -match '(?i)\.mscx$' -and $entry.Length -gt 0) {
                        $scoreXmlEntries += $entry.FullName
                    }
                }
            } finally {
                $scoreArchive.Dispose()
            }
        } catch {
            $openError = $_.Exception.Message
        }
        if ($null -ne $openError) {
            Add-Failure "exported score container is not a readable ZIP archive ($openError)"
        } else {
            foreach ($entryName in $entryNames) {
                Assert-ZipEntrySafe -EntryName $entryName
            }
            if ($scoreXmlEntries.Count -eq 0) {
                Add-Failure 'exported score container carries no score XML (*.mscx) entry'
            } else {
                Write-Host "score container OK: $msczPath ($((Get-Item -LiteralPath $msczPath).Length) bytes, score XML: $($scoreXmlEntries -join ', '))"
                $msczOk = $true
            }
        }
    }
    Add-Result -Result @{ name = 'export-mscz'; argv = @('-o', $msczPath, $fixture); exit_code = $msczResult.ExitCode; timed_out = $msczResult.TimedOut; ok = $msczOk; log = $msczResult.StdoutLog }
}

# ---------------------------------------------------------------------------
# 3. GUI testflow: TC11 + TC14
# ---------------------------------------------------------------------------
Write-Section 'GUI testflow regression tests'
foreach ($scriptName in $script:RequiredTestScripts) {
    $extractedScript = Join-Path $extractRoot (Join-Path 'testflowscripts' $scriptName)
    if (-not (Test-Path -LiteralPath $extractedScript -PathType Leaf)) {
        Add-Failure "package does not contain the installed test script testflowscripts/$scriptName"
        continue
    }

    $sourceScript = Join-Path $sourceRoot (Join-Path 'share/testflowscripts' $scriptName)
    if (-not (Test-Path -LiteralPath $sourceScript -PathType Leaf)) {
        # Running the packaged copy would test whatever the package happens to contain
        # instead of the reviewed test case, so a missing reviewed script fails the run.
        Add-Failure "the reviewed script share/testflowscripts/$scriptName is missing from -SourceDirectory; refusing to run the packaged copy instead"
        continue
    }
    $sourceSha256 = Get-Sha256 -Path $sourceScript
    $packagedSha256 = Get-Sha256 -Path $extractedScript
    if ($sourceSha256 -ne $packagedSha256) {
        Add-Failure "installed testflowscripts/$scriptName differs from the reviewed script at source_sha"
        continue
    }

    # Testflow::runTestCase() calls TestCaseReport::beginReport(), which creates
    # <MUSE_TESTFLOW_DATA_PATH>/reports before it writes the per-case report. A missing
    # reports directory therefore means the reviewed script never reached its assertions,
    # which a zero exit status alone cannot distinguish. The directory is used rather than
    # the report file because a test case name may contain characters that are not valid in
    # a Windows file name, while the directory name is always portable.
    $reportsRoot = Join-Path $script:TestflowDataRoot 'reports'
    if (Test-Path -LiteralPath $reportsRoot) {
        Remove-Item -LiteralPath $reportsRoot -Recurse -Force
    }

    $result = Invoke-BoundedProcess -Name ("gui-" + ($scriptName -replace '\.js$', '')) -Executable $executableFullPath `
        -Arguments @('--test-case-gui', $extractedScript) `
        -WorkingDirectory $extractRoot -IsolatedAppData $isolatedAppData -IsolatedLocalAppData $isolatedLocalAppData `
        -TimeoutSeconds $GuiTimeoutSeconds -LogRoot $logRoot

    $recordedReports = @()
    if (Test-Path -LiteralPath $reportsRoot -PathType Container) {
        $recordedReports = @(Get-ChildItem -LiteralPath $reportsRoot -File -ErrorAction SilentlyContinue)
    }

    $ok = $true
    if ($result.TimedOut) {
        Add-Failure "$scriptName timed out after ${GuiTimeoutSeconds}s; process tree killed (log $($result.StdoutLog))"
        $ok = $false
    } elseif ($result.ExitCode -ne 0) {
        Add-Failure "$scriptName failed with exit code $($result.ExitCode) (log $($result.StdoutLog))"
        $ok = $false
    } elseif (-not (Test-Path -LiteralPath $reportsRoot -PathType Container)) {
        Add-Failure "$scriptName exited 0 without the testflow runner recording a test case; the reviewed test case did not execute (log $($result.StdoutLog))"
        $ok = $false
    } else {
        Write-Host "$scriptName passed (exit 0, testflow record present, $($recordedReports.Count) report file(s))"
    }
    # Copy any recorded testflow report into the uploaded log directory for diagnosis.
    foreach ($recordedReport in $recordedReports) {
        Copy-Item -LiteralPath $recordedReport.FullName -Destination (Join-Path $logRoot ("testflow-" + $recordedReport.Name)) -Force -ErrorAction SilentlyContinue
    }
    Add-Result -Result @{ name = $scriptName; command = '--test-case-gui'; argv = @('--test-case-gui', $extractedScript); exit_code = $result.ExitCode; timed_out = $result.TimedOut; ok = $ok; recorded_reports = @($recordedReports | ForEach-Object { $_.Name }); log = $result.StdoutLog }
}

# ---------------------------------------------------------------------------
# Diagnostics
# ---------------------------------------------------------------------------
$appLogRoot = Join-Path $isolatedLocalAppData "MuseScore/$expectedAppName/logs"
if (-not (Test-Path -LiteralPath $appLogRoot)) {
    $appLogRoot = Join-Path $isolatedLocalAppData 'MuseScore'
}
if (Test-Path -LiteralPath $appLogRoot) {
    $appLogs = @(Get-ChildItem -LiteralPath $appLogRoot -Recurse -File -ErrorAction SilentlyContinue)
    foreach ($log in $appLogs) {
        Copy-Item -LiteralPath $log.FullName -Destination (Join-Path $logRoot ("app-" + $log.Name)) -Force -ErrorAction SilentlyContinue
    }
    Write-Host "collected $($appLogs.Count) application log file(s)"
}

# Every runtime log and the machine-readable report live under
# <OutputDirectory>/logs so the workflow can upload that single directory.
$reportPath = Join-Path $logRoot 'runtime-tests.json'
[IO.File]::WriteAllText(
    $reportPath,
    (ConvertTo-Json -InputObject @($script:Results) -Depth 6),
    [Text.UTF8Encoding]::new($false))
Write-Host "report: $reportPath"

Write-Host ''
if ($script:Failures.Count -gt 0) {
    Write-Host "test-windows-package: FAILED ($($script:Failures.Count) problem(s))"
    foreach ($failure in $script:Failures) {
        Write-Host "  - $failure"
    }
    exit 1
}

Write-Host 'test-windows-package: OK'
exit 0
