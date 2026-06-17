#!/usr/bin/env pwsh
# SPDX-License-Identifier: GPL-3.0-only
# MuseScore-Studio-CLA-applies
#
# MuseScore Studio
# Music Composition & Notation
#
# Copyright (C) 2021 MuseScore Limited and others
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3 as
# published by the Free Software Foundation.

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Get-Location).Path
}

$Target = "release"
$Jobs = [Environment]::ProcessorCount
if ($Jobs -lt 1) {
    $Jobs = 4
}
$ShowHelp = $false

function Get-EnvDefault {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Default
    )

    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrEmpty($value)) {
        return $Default
    }

    return $value
}

function Resolve-BuildRelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string] $BuildDir,

        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    if ([IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return [IO.Path]::GetFullPath((Join-Path $BuildDir $Path))
}

function Show-Usage {
    @"
Usage: ninja_build.ps1
    -t, --target <string> [default: $Target]
        Provided targets:
        release, debug, relwithdebinfo, install, installrelwithdebinfo,
        installdebug, clean, compile_commands, revision
    -j, --jobs <number> [default: $Jobs]
        Number of parallel compilation jobs
    -h, --help
        Show this help

AppImage targets remain supported by ninja_build.sh on Unix-like systems.
"@ | Write-Host
}

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string] $FilePath,

        [Parameter(Mandatory = $true)]
        [string[]] $Arguments,

        [Parameter(Mandatory = $true)]
        [string] $WorkingDirectory
    )

    $displayArgs = $Arguments -join " "
    Write-Host "> $FilePath $displayArgs"

    Push-Location $WorkingDirectory
    try {
        & $FilePath @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "$FilePath failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }
}

function Require-Command {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name was not found on PATH. Run ninja_build.bat from Windows so Visual Studio and Ninja are configured first."
    }
}

for ($i = 0; $i -lt $args.Count; $i++) {
    $arg = $args[$i]

    if ($arg -eq "-t" -or $arg -eq "--target") {
        if ($i + 1 -ge $args.Count) {
            throw "Missing value for $arg"
        }
        $i++
        $Target = $args[$i]
    }
    elseif ($arg -eq "-j" -or $arg -eq "--jobs") {
        if ($i + 1 -ge $args.Count) {
            throw "Missing value for $arg"
        }
        $i++
        if (-not [int]::TryParse($args[$i], [ref] $Jobs) -or $Jobs -lt 1) {
            throw "Jobs must be a positive integer. Received: $($args[$i])"
        }
    }
    elseif ($arg -eq "-h" -or $arg -eq "--help") {
        $ShowHelp = $true
    }
    else {
        throw "Unknown parameter passed: $arg"
    }
}

if ($ShowHelp) {
    Show-Usage
    exit 0
}

$CMakeOsxArchitectures = Get-EnvDefault "CMAKE_OSX_ARCHITECTURES" ""
$MuseScoreMacosDepsPath = Get-EnvDefault "MUSESCORE_MACOS_DEPS_PATH" ""
$MuseScoreInstallDir = Get-EnvDefault "MUSESCORE_INSTALL_DIR" "../build.install"
$MuseAppInstallSuffix = Get-EnvDefault "MUSE_APP_INSTALL_SUFFIX" ""
$MuseScoreBuildConfiguration = Get-EnvDefault "MUSESCORE_BUILD_CONFIGURATION" "app"
$MuseAppBuildMode = Get-EnvDefault "MUSE_APP_BUILD_MODE" "dev"
$MuseScoreBuildNumber = Get-EnvDefault "MUSESCORE_BUILD_NUMBER" "12345678"
$MuseScoreRevision = Get-EnvDefault "MUSESCORE_REVISION" "abc123456"
$MuseScoreRunLrelease = Get-EnvDefault "MUSESCORE_RUN_LRELEASE" "ON"
$MuseScoreCrashreportUrl = Get-EnvDefault "MUSESCORE_CRASHREPORT_URL" ""
$MuseScoreBuildCrashpadClient = Get-EnvDefault "MUSESCORE_BUILD_CRASHPAD_CLIENT" "OFF"
$MuseScoreDebugLevelEnabled = "OFF"
$MuseScoreDownloadSoundfont = Get-EnvDefault "MUSESCORE_DOWNLOAD_SOUNDFONT" "ON"
$MuseScoreBuildUnitTests = Get-EnvDefault "MUSESCORE_BUILD_UNIT_TESTS" "OFF"
$MuseScoreUnitTestsEnableCodeCoverage = Get-EnvDefault "MUSESCORE_UNIT_TESTS_ENABLE_CODE_COVERAGE" "OFF"
$MuseScoreNoRpath = Get-EnvDefault "MUSESCORE_NO_RPATH" "OFF"
$MuseScoreModuleUpdate = Get-EnvDefault "MUSESCORE_MODULE_UPDATE" "ON"
$MuseScoreBuildVstModule = Get-EnvDefault "MUSESCORE_BUILD_VST_MODULE" "OFF"
$MuseScoreBuildWebsocket = Get-EnvDefault "MUSESCORE_BUILD_WEBSOCKET" "OFF"
$MuseScoreBuildPipewireAudioDriver = Get-EnvDefault "MUSESCORE_BUILD_PIPEWIRE_AUDIO_DRIVER" "OFF"
$MuseScoreCompileUseUnity = Get-EnvDefault "MUSESCORE_COMPILE_USE_UNITY" "ON"

function Get-ConfigureArgs {
    param(
        [Parameter(Mandatory = $true)]
        [string] $BuildType,

        [Parameter(Mandatory = $true)]
        [string] $BuildDir,

        [string[]] $AdditionalArgs = @()
    )

    $installPrefix = Resolve-BuildRelativePath -BuildDir $BuildDir -Path $MuseScoreInstallDir

    $args = @(
        "-S", $RepoRoot,
        "-B", $BuildDir,
        "-G", "Ninja",
        "-DCMAKE_BUILD_TYPE=$BuildType",
        "-DCMAKE_OSX_ARCHITECTURES=$CMakeOsxArchitectures",
        "-DMUE_COMPILE_MACOS_PRECOMPILED_DEPS_PATH=$MuseScoreMacosDepsPath",
        "-DCMAKE_INSTALL_PREFIX=$installPrefix",
        "-DMUSE_APP_INSTALL_SUFFIX=$MuseAppInstallSuffix",
        "-DMUSESCORE_BUILD_CONFIGURATION=$MuseScoreBuildConfiguration",
        "-DMUSE_APP_BUILD_MODE=$MuseAppBuildMode",
        "-DCMAKE_BUILD_NUMBER=$MuseScoreBuildNumber",
        "-DMUSESCORE_REVISION=$MuseScoreRevision",
        "-DMUE_RUN_LRELEASE=$MuseScoreRunLrelease",
        "-DMUSE_MODULE_UPDATE=$MuseScoreModuleUpdate",
        "-DMUE_DOWNLOAD_SOUNDFONT=$MuseScoreDownloadSoundfont",
        "-DMUSE_ENABLE_UNIT_TESTS=$MuseScoreBuildUnitTests",
        "-DMUSE_ENABLE_UNIT_TESTS_CODE_COVERAGE=$MuseScoreUnitTestsEnableCodeCoverage",
        "-DMUSE_MODULE_DIAGNOSTICS_CRASHPAD_CLIENT=$MuseScoreBuildCrashpadClient",
        "-DMUSE_MODULE_DIAGNOSTICS_CRASHREPORT_URL=$MuseScoreCrashreportUrl",
        "-DMUSE_MODULE_GLOBAL_LOGGER_DEBUGLEVEL=$MuseScoreDebugLevelEnabled",
        "-DMUSE_MODULE_VST=$MuseScoreBuildVstModule",
        "-DMUSE_MODULE_NETWORK_WEBSOCKET=$MuseScoreBuildWebsocket",
        "-DMUSE_MODULE_AUDIO_PIPEWIRE=$MuseScoreBuildPipewireAudioDriver",
        "-DCMAKE_SKIP_RPATH=$MuseScoreNoRpath",
        "-DMUSE_COMPILE_USE_UNITY=$MuseScoreCompileUseUnity"
    ) + $AdditionalArgs

    if ($CMakeMakeProgramOverride) {
        $args += "-DCMAKE_MAKE_PROGRAM=$CMakeMakeProgramOverride"
    }

    return $args
}

function Start-Build {
    param(
        [Parameter(Mandatory = $true)]
        [string] $BuildType,

        [Parameter(Mandatory = $true)]
        [string] $BuildDir
    )

    New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
    Invoke-CheckedCommand -FilePath "cmake" -Arguments (Get-ConfigureArgs -BuildType $BuildType -BuildDir $BuildDir) -WorkingDirectory $RepoRoot
    Invoke-CheckedCommand -FilePath "cmake" -Arguments @("--build", $BuildDir, "--parallel", "$Jobs") -WorkingDirectory $RepoRoot
}

function Start-InstallBuild {
    param(
        [Parameter(Mandatory = $true)]
        [string] $BuildType,

        [Parameter(Mandatory = $true)]
        [string] $BuildDir
    )

    Start-Build -BuildType $BuildType -BuildDir $BuildDir
    Invoke-CheckedCommand -FilePath "cmake" -Arguments @("--install", $BuildDir, "--config", $BuildType) -WorkingDirectory $RepoRoot
}

$BuildTargets = @('release','debug','relwithdebinfo','install','installrelwithdebinfo','installdebug','compile_commands')

$Target = $Target.ToLowerInvariant()

$CMakeMakeProgramOverride = $null

function Find-VisualStudioNinja {
    $vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vsWhere)) {
        return $null
    }
    $vsPath = & $vsWhere -latest -property installationPath 2>$null
    if (-not $vsPath) {
        return $null
    }
    $ninjaPath = Join-Path $vsPath "Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe"
    if (Test-Path $ninjaPath) {
        return $ninjaPath
    }
    return $null
}

if ($Target -in $BuildTargets) {
    Require-Command 'cmake'
    Require-Command 'ninja'
    Invoke-CheckedCommand -FilePath 'cmake' -Arguments @('--version') -WorkingDirectory $RepoRoot
    $ninjaVersion = (& ninja --version)
    if ($LASTEXITCODE -ne 0) {
        throw "ninja --version failed with exit code $LASTEXITCODE"
    }
    Write-Host "ninja version $ninjaVersion"

    if ($ninjaVersion -match "1\.13\.0" -and $ninjaVersion -match "kitware") {
        Write-Host "WARNING: Ninja 1.13.0 (Kitware) has a known bug that truncates response files," -ForegroundColor Yellow
        Write-Host "         causing LNK1104 linker errors on large projects (ninja-build/ninja#2616)." -ForegroundColor Yellow
        $vsNinja = Find-VisualStudioNinja
        if ($vsNinja) {
            $vsNinjaVersion = (& $vsNinja --version)
            Write-Host "         Falling back to Visual Studio's Ninja ($vsNinjaVersion): $vsNinja" -ForegroundColor Yellow
            $CMakeMakeProgramOverride = $vsNinja
        } else {
            Write-Host "         Visual Studio's bundled Ninja was not found." -ForegroundColor Yellow
            Write-Host "         Fix: pip uninstall ninja  (to use VS's Ninja)" -ForegroundColor Yellow
            Write-Host "         Or:  pip install 'ninja>=1.14'" -ForegroundColor Yellow
        }
    }
}


switch ($Target) {
    "release" {
        Start-Build -BuildType "Release" -BuildDir (Join-Path $RepoRoot "build.release")
    }
    "debug" {
        Start-Build -BuildType "Debug" -BuildDir (Join-Path $RepoRoot "build.debug")
    }
    "relwithdebinfo" {
        Start-Build -BuildType "RelWithDebInfo" -BuildDir (Join-Path $RepoRoot "build.release")
    }
    "install" {
        Start-InstallBuild -BuildType "Release" -BuildDir (Join-Path $RepoRoot "build.release")
    }
    "installrelwithdebinfo" {
        Start-InstallBuild -BuildType "RelWithDebInfo" -BuildDir (Join-Path $RepoRoot "build.release")
    }
    "installdebug" {
        Start-InstallBuild -BuildType "Debug" -BuildDir (Join-Path $RepoRoot "build.debug")
    }
    "clean" {
        foreach ($dir in @("build.debug", "build.release")) {
            $path = Join-Path $RepoRoot $dir
            if (Test-Path -LiteralPath $path) {
                Write-Host "Deleting $path"
                Remove-Item -LiteralPath $path -Recurse -Force
            }
        }
    }
    "compile_commands" {
        $buildDir = Join-Path $RepoRoot "build/compile_commands"
        New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
        Invoke-CheckedCommand -FilePath "cmake" -Arguments (Get-ConfigureArgs -BuildType "Debug" -BuildDir $buildDir -AdditionalArgs @("-DCMAKE_EXPORT_COMPILE_COMMANDS=1", "-DMUSE_COMPILE_USE_UNITY=OFF")) -WorkingDirectory $RepoRoot
    }
    "revision" {
        $revision = (& git -C $RepoRoot rev-parse --short=7 HEAD)
        if ($LASTEXITCODE -ne 0) {
            throw "git rev-parse failed with exit code $LASTEXITCODE"
        }
        [IO.File]::WriteAllText((Join-Path $RepoRoot "local_build_revision.env"), $revision.Trim())
    }
    "appimage" {
        throw "The appimage target is Linux packaging and remains supported by ninja_build.sh."
    }
    "appimagedebug" {
        throw "The appimagedebug target is Linux packaging and remains supported by ninja_build.sh."
    }
    default {
        throw "Unknown target: $Target"
    }
}
