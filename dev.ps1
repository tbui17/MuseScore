#!/usr/bin/env pwsh
# SPDX-License-Identifier: GPL-3.0-only
# MuseScore-Studio-CLA-applies

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Get-Location).Path
}

function Show-Usage {
    @"
Usage: .\dev.ps1 <command> [args]

Daily commands:
  build [-j <jobs>|--jobs <jobs>]
      Build the Debug configuration using the existing Ninja build wrapper.

  run [args...]
      Run build.debug\MuseScoreStudio5.exe with optional arguments.

  test <script> [args...]
      Run a MuseScore app test-case script through the Debug executable.

  release [args...]
      Release build to build.release/.

  install [args...]
      Release build + install to build.install/.

  package [args...]
      Package build.install/ into a distributable ZIP at dist/.

  publish [--dry-run]
      Build release, install, package, and push to GitHub Releases.

  clean [debug|release|install] [--yes]
      Preview deletion of build directories. Add --yes to delete.

  lint [qml] [--accessible-only] [--filter <pattern>]
      Run qmllint on QML files. Requires a prior build to resolve imports.

  help, -h, --help
      Show this help.
"@ | Write-Host
}

function Show-TestUsage {
    @"
Usage: .\dev.ps1 test <script> [args...]

Example:
  .\dev.ps1 test vtest\vtest.js --test-case-context vtest\vtest_context.json
"@ | Write-Host
}

function Show-CleanUsage {
    @"
Usage: .\dev.ps1 clean [debug|release|install] [--yes]

Without --yes, clean only previews what would be deleted.
"@ | Write-Host
}

function Show-LintUsage {
    @"
Usage: .\dev.ps1 lint [qml] [options]

Options:
  --accessible-only    Show only accessible-related warnings
  --filter <pattern>   Only lint files matching the pattern
  --fix                 Auto-fix where possible (uses qmllint --fix)
  --help                Show this help

Requires:
  - qmllint on PATH (ships with Qt)
  - build.debug directory (run .\dev.ps1 build first)
"@ | Write-Host
}

function Get-DebugExecutablePath {
    return (Join-Path $RepoRoot "build.debug\MuseScoreStudio5.exe")
}

function Require-DebugExecutable {
    $exePath = Get-DebugExecutablePath
    if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
        Write-Error @"
Debug executable not found:
  $exePath

Run:
  .\dev.ps1 build
"@
    }

    return $exePath
}

function Invoke-Build {
    param(
        [string[]] $BuildArgs
    )

    $jobs = $null

    for ($i = 0; $i -lt $BuildArgs.Count; $i++) {
        $arg = $BuildArgs[$i]
        if ($arg -eq "-j" -or $arg -eq "--jobs") {
            if ($i + 1 -ge $BuildArgs.Count) {
                throw "Missing value for $arg"
            }

            $i++
            $value = 0
            if (-not [int]::TryParse($BuildArgs[$i], [ref] $value) -or $value -lt 1) {
                throw "Jobs must be a positive integer. Received: $($BuildArgs[$i])"
            }

            $jobs = $value
        }
        else {
            throw "Unsupported build argument: $arg"
        }
    }

    $ninjaBuild = Join-Path $RepoRoot "ninja_build.bat"
    $invokeArgs = @("-t", "debug")
    if ($null -ne $jobs) {
        $invokeArgs += @("-j", "$jobs")
    }

    & $ninjaBuild @invokeArgs
    if (Test-Path Variable:\LASTEXITCODE -and $LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

function Invoke-Run {
    param(
        [string[]] $RunArgs
    )

    $exePath = Require-DebugExecutable
    Push-Location $RepoRoot
    try {
        & $exePath @RunArgs
        if (Test-Path Variable:\LASTEXITCODE) { exit $LASTEXITCODE }
    }
    finally {
        Pop-Location
    }
}

function Invoke-Test {
    param(
        [string[]] $TestArgs
    )

    if ($TestArgs.Count -lt 1) {
        Show-TestUsage
        exit 1
    }

    $script = $TestArgs[0]
    $remainingArgs = @()
    if ($TestArgs.Count -gt 1) {
        $remainingArgs = $TestArgs[1..($TestArgs.Count - 1)]
    }

    $exePath = Require-DebugExecutable
    $invokeArgs = @("--test-case", $script) + $remainingArgs
    Push-Location $RepoRoot
    try {
        & $exePath @invokeArgs
        if (Test-Path Variable:\LASTEXITCODE) { exit $LASTEXITCODE }
    }
    finally {
        Pop-Location
    }
}

function Invoke-Clean {
    param(
        [string[]] $CleanArgs
    )

    $targets = @{
        debug = "build.debug"
        release = "build.release"
        install = "build.install"
    }

    $selectedTarget = $null
    $confirmed = $false

    foreach ($arg in $CleanArgs) {
        if ($arg -eq "--yes") {
            $confirmed = $true
        }
        elseif ($targets.ContainsKey($arg)) {
            if ($null -ne $selectedTarget) {
                Show-CleanUsage
                throw "Only one clean target can be specified."
            }
            $selectedTarget = $arg
        }
        else {
            Show-CleanUsage
            throw "Unknown clean argument: $arg"
        }
    }

    $targetNames = @("debug", "release", "install")
    if ($null -ne $selectedTarget) {
        $targetNames = @($selectedTarget)
    }

    if (-not $confirmed) {
        Write-Host "Would delete:"
        foreach ($name in $targetNames) {
            $path = Join-Path $RepoRoot $targets[$name]
            if (Test-Path -LiteralPath $path) {
                Write-Host "  $path"
            }
            else {
                Write-Host "  $path (not found)"
            }
        }
        Write-Host ""
        Write-Host "Run with --yes to delete."
        return
    }

    foreach ($name in $targetNames) {
        $path = Join-Path $RepoRoot $targets[$name]
        if (Test-Path -LiteralPath $path) {
            Write-Host "Deleting $path"
            Remove-Item -LiteralPath $path -Recurse -Force
        }
        else {
            Write-Host "Skipping $path (not found)"
        }
    }
}

function Invoke-Ninja {
    param(
        [string] $Target,
        [string[]] $BuildArgs
    )

    $ninjaBuild = Join-Path $RepoRoot "ninja_build.bat"
    & $ninjaBuild "-t" $Target @BuildArgs
    if (Test-Path Variable:\LASTEXITCODE -and $LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

function Invoke-Package {
    param(
        [string[]] $PackageArgs
    )

    $buildScript = Join-Path $RepoRoot "tools\braille-installer\Build-MuseScore-Braille-Package.ps1"
    & $buildScript @PackageArgs
    if (Test-Path Variable:\LASTEXITCODE -and $LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

function Invoke-Publish {
    param(
        [string[]] $PublishArgs
    )

    $dryRun = $PublishArgs -contains "--dry-run"
    if ($dryRun) {
        $PublishArgs = $PublishArgs | Where-Object { $_ -ne "--dry-run" }
    }

    # Step 1: Build + install
    Write-Host "Step 1: Building release and installing to build.install/"
    Invoke-Ninja -Target "install" -BuildArgs $PublishArgs

    # Step 2: Package into ZIP
    Write-Host "Step 2: Packaging build.install/ into ZIP"
    Invoke-Package

    # Step 3: Create GitHub release
    $date = Get-Date -Format "yyyy-MM-dd"
    $tag = "braille-test-$date"
    $zipPattern = Join-Path $RepoRoot "dist\musescore-braille-installer\MuseScore-Braille-Installer-*.zip"
    $zipFile = Get-ChildItem -LiteralPath $zipPattern | Select-Object -First 1

    if (-not $zipFile) {
        throw "No ZIP found matching $zipPattern"
    }

    Write-Host "Step 3: Creating GitHub release $tag"
    if ($dryRun) {
        Write-Host "  [DRY RUN] Would run:"
        Write-Host "  gh release create $tag `"$($zipFile.FullName)`" --repo tbui17/MuseScore --title `"MuseScore Braille Test Build $date`""
    }
    else {
        gh release create $tag $zipFile.FullName --repo tbui17/MuseScore --title "MuseScore Braille Test Build $date"
        if ($LASTEXITCODE -ne 0) {
            throw "gh release create failed with exit code $LASTEXITCODE"
        }
        Write-Host "Done: https://github.com/tbui17/MuseScore/releases/tag/$tag"
    }
}

function Invoke-Lint {
    param(
        [string[]] $LintArgs
    )

    $lintScript = Join-Path $RepoRoot "lint_qml.py"
    if (-not (Test-Path -LiteralPath $lintScript -PathType Leaf)) {
        Write-Error "lint_qml.py not found: $lintScript"
        exit 1
    }

    $remainingArgs = @()
    if ($LintArgs.Count -gt 0 -and $LintArgs[0] -eq "qml") {
        $remainingArgs = $LintArgs[1..($LintArgs.Count - 1)]
    }
    else {
        $remainingArgs = $LintArgs
    }

    foreach ($arg in $remainingArgs) {
        if ($arg -eq "--help" -or $arg -eq "-h") {
            Show-LintUsage
            return
        }
    }

    & python $lintScript @remainingArgs
}

if ($args.Count -eq 0) {
    Show-Usage
    exit 0
}

$command = $args[0].ToLowerInvariant()
$commandArgs = @()
if ($args.Count -gt 1) {
    $commandArgs = $args[1..($args.Count - 1)]
}

try {
    switch ($command) {
        "build" { Invoke-Build -BuildArgs $commandArgs }
        "run" { Invoke-Run -RunArgs $commandArgs }
        "test" { Invoke-Test -TestArgs $commandArgs }
        "clean" { Invoke-Clean -CleanArgs $commandArgs }
        "lint" { Invoke-Lint -LintArgs $commandArgs }
        "release" { Invoke-Ninja -Target "release" -BuildArgs $commandArgs }
        "install" { Invoke-Ninja -Target "install" -BuildArgs $commandArgs }
        "package" { Invoke-Package -PackageArgs $commandArgs }
        "publish" { Invoke-Publish -PublishArgs $commandArgs }
        "help" { Show-Usage }
        "-h" { Show-Usage }
        "--help" { Show-Usage }
        default {
            Show-Usage
            throw "Unsupported command: $($args[0])"
        }
    }
}
catch {
    Write-Error $_
    exit 1
}
