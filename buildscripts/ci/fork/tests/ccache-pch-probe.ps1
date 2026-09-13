#!/usr/bin/env pwsh
# SPDX-License-Identifier: GPL-3.0-only
# MuseScore-Studio-CLA-applies
#
# Focused hosted probe for the pinned ccache/MSVC PCH contract. This intentionally
# runs before the desktop build so a broken compiler-cache/PCH combination fails
# without spending the full build time.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $CcacheDirectory,

    [Parameter(Mandatory = $true)]
    [string] $LogDirectory
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$ProgressPreference = "SilentlyContinue"

$PinnedCcacheVersion = "4.14"
$encoding = New-Object System.Text.UTF8Encoding($false)
$LogDirectory = [IO.Path]::GetFullPath($LogDirectory)
$CcacheDirectory = [IO.Path]::GetFullPath($CcacheDirectory)
New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null
New-Item -ItemType Directory -Force -Path $CcacheDirectory | Out-Null

$eventLog = Join-Path $LogDirectory "ccache-pch-probe.log"
[IO.File]::WriteAllText($eventLog, "", $encoding)

function Write-Event {
    param([Parameter(Mandatory = $true)][string] $Message)

    Write-Host $Message
    [IO.File]::AppendAllText($eventLog, $Message + [Environment]::NewLine, $encoding)
}

function Invoke-CapturedTool {
    param(
        [Parameter(Mandatory = $true)][string] $FilePath,
        [Parameter(Mandatory = $true)][string[]] $Arguments,
        [Parameter(Mandatory = $true)][string] $Name
    )

    $commandLine = "> $FilePath $($Arguments -join ' ')"
    Write-Event $commandLine
    $output = & $FilePath @Arguments 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    $output = $output.TrimEnd()
    if ($output) {
        Write-Event $output
    }
    [IO.File]::WriteAllText((Join-Path $LogDirectory "$Name.log"), $commandLine + [Environment]::NewLine + $output + [Environment]::NewLine, $encoding)
    if ($exitCode -ne 0) {
        throw "$Name failed with exit code $exitCode. See $LogDirectory\$Name.log"
    }
    return $output
}

function Import-MsvcEnvironment {
    param([Parameter(Mandatory = $true)][string] $InstallationPath)

    $vcvars = Join-Path $InstallationPath "VC\Auxiliary\Build\vcvars64.bat"
    if (-not (Test-Path -LiteralPath $vcvars)) {
        throw "vcvars64.bat was not found at '$vcvars'."
    }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $env:ComSpec
    $startInfo.Arguments = '/s /c "call "' + $vcvars + '" >nul 2>&1 && set"'
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true

    $process = [System.Diagnostics.Process]::Start($startInfo)
    $rawOutput = $process.StandardOutput.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        throw "vcvars64.bat failed with exit code $($process.ExitCode): $vcvars"
    }

    foreach ($line in ($rawOutput -split "`r?`n")) {
        if (($line -match '^([^=]+)=(.*)$') -and (-not $Matches[1].StartsWith("="))) {
            [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2])
        }
    }

    if (-not ($env:VCToolsVersion -and $env:VSCMD_ARG_TGT_ARCH)) {
        throw "vcvars64.bat did not initialise the MSVC environment (VCToolsVersion/VSCMD_ARG_TGT_ARCH missing): $vcvars"
    }
    if ($env:VSCMD_ARG_TGT_ARCH -ne "x64") {
        throw "Expected an x64 MSVC environment, got VSCMD_ARG_TGT_ARCH='$($env:VSCMD_ARG_TGT_ARCH)'."
    }

    Write-Event "MSVC environment imported from $vcvars"
}
function Parse-CcacheStats {
    param(
        [Parameter(Mandatory = $true)][string] $Output,
        [Parameter(Mandatory = $true)][string] $Name
    )

    $cacheableMatch = [regex]::Match($Output, '(?im)^\s*Cacheable calls:\s*(?<value>\d+)\b')
    $hitsMatch = [regex]::Match($Output, '(?im)^\s*Hits:\s*(?<value>\d+)\b')
    $uncacheableMatch = [regex]::Match($Output, '(?im)^\s*Uncacheable calls:\s*(?<value>\d+)\b')
    if (-not ($cacheableMatch.Success -and $hitsMatch.Success -and $uncacheableMatch.Success)) {
        throw "ccache statistics did not contain leading counts for Cacheable calls, Hits, and Uncacheable calls. See $LogDirectory\$Name.log"
    }

    return [ordered]@{
        cacheable   = [int]$cacheableMatch.Groups["value"].Value
        hits        = [int]$hitsMatch.Groups["value"].Value
        uncacheable = [int]$uncacheableMatch.Groups["value"].Value
    }
}

function Get-CcacheStats {
    param([Parameter(Mandatory = $true)][string] $Name)

    $output = Invoke-CapturedTool -FilePath $script:CcachePath -Arguments @("-s", "-vv") -Name $Name
    return Parse-CcacheStats -Output $output -Name $Name
}

$statsFixture = @'
Cacheable calls:      3 / 3 (100.00%)
  Hits:               1 / 3 (33.33%)
  Misses:             2 / 3 (66.67%)
Uncacheable calls:    0 / 3 (0.00%)
'@
$fixtureStats = Parse-CcacheStats -Output $statsFixture -Name "ccache-stats-fixture"
if ($fixtureStats.cacheable -ne 3 -or $fixtureStats.hits -ne 1 -or $fixtureStats.uncacheable -ne 0) {
    throw "ccache statistics parser fixture returned unexpected counts."
}

if (-not $IsWindows) {
    Write-Event "Skipping MSVC ccache PCH probe on non-Windows host."
    exit 0
}

try {
    $ccacheCommand = Get-Command ccache -ErrorAction Stop
    $script:CcachePath = if ($ccacheCommand.Source) { $ccacheCommand.Source } else { $ccacheCommand.Path }
    $versionOutput = Invoke-CapturedTool -FilePath $script:CcachePath -Arguments @("--version") -Name "ccache-version"
    $versionMatch = [regex]::Match($versionOutput, '(?im)^\s*ccache version (?<version>\d+(?:\.\d+)+)\s*$')
    if (-not $versionMatch.Success -or $versionMatch.Groups["version"].Value -ne $PinnedCcacheVersion) {
        throw "Probe found ccache '$($versionMatch.Groups["version"].Value)' instead of pinned $PinnedCcacheVersion."
    }

    if (Test-Path Env:CCACHE_CPP2) {
        throw "Obsolete CCACHE_CPP2 is set before the pinned ccache probe."
    }
    $env:CCACHE_DIR = $CcacheDirectory
    $env:CCACHE_MAXSIZE = "4G"
    $env:CCACHE_SLOPPINESS = "pch_defines,time_macros"
    Write-Event "CCACHE_DIR=$env:CCACHE_DIR"
    Write-Event "CCACHE_MAXSIZE=$env:CCACHE_MAXSIZE"
    Write-Event "CCACHE_SLOPPINESS=$env:CCACHE_SLOPPINESS"
    $null = Invoke-CapturedTool -FilePath $script:CcachePath -Arguments @("-p") -Name "ccache-config"

    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path -LiteralPath $vswhere)) {
        throw "vswhere.exe was not found; Visual Studio with the x64 C++ tools is required."
    }
    $vsJson = Invoke-CapturedTool -FilePath $vswhere -Arguments @(
        "-latest", "-products", "*",
        "-requires", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
        "-format", "json") -Name "vswhere"
    $instances = @($vsJson | ConvertFrom-Json)
    if ($instances.Count -eq 0) {
        throw "vswhere found no Visual Studio instance with the x64 C++ tools."
    }
    Import-MsvcEnvironment -InstallationPath "$($instances[0].installationPath)"
    $clCommand = Get-Command cl.exe -ErrorAction Stop
    $clPath = if ($clCommand.Source) { $clCommand.Source } else { $clCommand.Path }
    Write-Event "cl.exe=$clPath (VCToolsVersion=$env:VCToolsVersion)"

    $probeRoot = Join-Path $env:RUNNER_TEMP ("musescore-ccache-pch-probe-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $probeRoot | Out-Null
    $headerPath = Join-Path $probeRoot "probe.hpp"
    $producerPath = Join-Path $probeRoot "producer.cpp"
    $consumerPath = Join-Path $probeRoot "consumer.cpp"
    $pchPath = Join-Path $probeRoot "probe.pch"
    $producerObjectPath = Join-Path $probeRoot "producer.obj"
    $consumerObjectPath = Join-Path $probeRoot "consumer.obj"
    [IO.File]::WriteAllText($headerPath, "#pragma once`r`nstruct ProbeValue { int value; };`r`n", $encoding)
    [IO.File]::WriteAllText($producerPath, "int produce_probe() { return 41; }`r`n", $encoding)
    [IO.File]::WriteAllText($consumerPath, "int consume_probe() { ProbeValue value{41}; return value.value; }`r`n", $encoding)
    $env:CCACHE_BASEDIR = $probeRoot

    $null = Invoke-CapturedTool -FilePath $script:CcachePath -Arguments @("-z") -Name "ccache-zero-stats"
    $commonArguments = @("/nologo", "/TP", "/c", "/EHsc", "/std:c++20", "/Z7")
    $producerArguments = $commonArguments + @(
        "/Yc$headerPath", "/Fp$pchPath", "/FI$headerPath", "/Fo$producerObjectPath", $producerPath)
    $consumerArguments = $commonArguments + @(
        "/Yu$headerPath", "/Fp$pchPath", "/FI$headerPath", "/Fo$consumerObjectPath", $consumerPath)

    $null = Invoke-CapturedTool -FilePath $script:CcachePath -Arguments (@($clPath) + $producerArguments) -Name "ccache-pch-producer"
    if (-not ((Test-Path -LiteralPath $pchPath -PathType Leaf) -and (Test-Path -LiteralPath $producerObjectPath -PathType Leaf))) {
        throw "The ccache PCH producer did not create both the .pch and producer .obj outputs."
    }
    $producerStats = Get-CcacheStats -Name "ccache-stats-after-producer"

    $null = Invoke-CapturedTool -FilePath $script:CcachePath -Arguments (@($clPath) + $consumerArguments) -Name "ccache-pch-consumer-first"
    if (-not (Test-Path -LiteralPath $consumerObjectPath -PathType Leaf)) {
        throw "The first ccache PCH consumer invocation did not create the consumer .obj output."
    }
    $firstConsumerStats = Get-CcacheStats -Name "ccache-stats-after-consumer-first"

    $null = Invoke-CapturedTool -FilePath $script:CcachePath -Arguments (@($clPath) + $consumerArguments) -Name "ccache-pch-consumer-second"
    if (-not (Test-Path -LiteralPath $consumerObjectPath -PathType Leaf)) {
        throw "The second ccache PCH consumer invocation removed the consumer .obj output."
    }
    $secondConsumerStats = Get-CcacheStats -Name "ccache-stats-after-consumer-second"

    if ($secondConsumerStats.hits -le $firstConsumerStats.hits) {
        throw "The second identical PCH consumer invocation did not increase ccache hits (first=$($firstConsumerStats.hits), second=$($secondConsumerStats.hits))."
    }
    if ($secondConsumerStats.cacheable -lt 3) {
        throw "The PCH probe recorded fewer than three cacheable compilations (producer plus two consumers): $($secondConsumerStats.cacheable)."
    }
    if ($secondConsumerStats.uncacheable -ne 0) {
        throw "The PCH probe recorded uncacheable calls: $($secondConsumerStats.uncacheable)."
    }

    $summary = [ordered]@{
        ccache_version       = $PinnedCcacheVersion
        compiler              = $clPath
        pch                   = $pchPath
        producer_stats        = $producerStats
        first_consumer_stats  = $firstConsumerStats
        second_consumer_stats = $secondConsumerStats
    }
    $summaryJson = $summary | ConvertTo-Json -Depth 4
    [IO.File]::WriteAllText((Join-Path $LogDirectory "ccache-pch-probe-summary.json"), $summaryJson + [Environment]::NewLine, $encoding)
    Write-Event "Pinned ccache MSVC PCH probe passed: second consumer hit count increased from $($firstConsumerStats.hits) to $($secondConsumerStats.hits)."
} catch {
    Write-Event "Pinned ccache MSVC PCH probe failed: $($_.Exception.Message)"
    throw
}
