#!/usr/bin/env pwsh
# SPDX-License-Identifier: GPL-3.0-only
# MuseScore-Studio-CLA-applies
#
# Negative tests for buildscripts/ci/fork/windows-build.ps1.
#
# The helper runs as a child process so each test asserts the exit code and the
# message a workflow would see. Nothing here compiles the application:
#
#   * the input/source/layout cases stop before the toolchain is touched and run
#     on any host with pwsh and git;
#   * the failure-propagation cases need the hosted Windows toolchain the
#     workflow provisions (Visual Studio via vswhere, cmake, ninja) and the
#     installed Qt that windows-build.ps1 resolves through QT_ROOT_DIR/Qt6_DIR.
#     They inject the failure either into the driver itself or into a
#     configure/build/install stage of a minimal CMake project.
#
# A step that has installed the toolchain exports MUSE_FORK_REQUIRE_NATIVE_TOOLCHAIN=1:
# the suite then fails instead of skipping when a required tool is missing.
#
#   pwsh -NoProfile -Command "Invoke-Pester -Path buildscripts/ci/fork/tests/windows-build.tests.ps1"

BeforeDiscovery {
    # Discovery only decides whether the toolchain cases are skipped. BeforeAll
    # repeats the check so a hosted Windows step cannot pass by skipping them.
    $script:ToolchainAvailable = $false
    $script:QtAvailable = $false
    if ($IsWindows) {
        $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
        $script:ToolchainAvailable = (Test-Path -LiteralPath $vswhere) `
            -and [bool](Get-Command cmake -ErrorAction SilentlyContinue) `
            -and [bool](Get-Command ninja -ErrorAction SilentlyContinue)

        $qtCandidates = @()
        if ($env:QT_ROOT_DIR) { $qtCandidates += $env:QT_ROOT_DIR }
        if ($env:Qt6_DIR) { $qtCandidates += (Join-Path $env:Qt6_DIR "..\..\..") }
        foreach ($candidate in $qtCandidates) {
            if (Test-Path -LiteralPath (Join-Path $candidate "bin\qmake.exe")) {
                $script:QtAvailable = $true
                break
            }
        }
    }
    $script:NativeAvailable = $script:ToolchainAvailable -and $script:QtAvailable
}

BeforeAll {
    $Helper = (Resolve-Path (Join-Path $PSScriptRoot "../windows-build.ps1")).Path
    # The real build driver, exercised from a fixture source directory. It derives its
    # repository root from its own location, so the copy must live at the fixture root.
    $DriverSource = (Resolve-Path (Join-Path $PSScriptRoot "../../../../ninja_build.ps1")).Path

    function Get-ProvisionedQtRoot {
        # Mirrors windows-build.ps1's Resolve-QtRoot: the workflow installs Qt and
        # exports QT_ROOT_DIR. No Qt is synthesized here, because the helper queries
        # the installed qmake CLI and checks its sibling deployment tools.
        $candidates = @()
        if ($env:QT_ROOT_DIR) { $candidates += $env:QT_ROOT_DIR }
        if ($env:Qt6_DIR) { $candidates += (Join-Path $env:Qt6_DIR "..\..\..") }
        foreach ($candidate in $candidates) {
            # Both Test-Path calls are parenthesized operands: without the parentheses
            # PowerShell binds -and as a Test-Path parameter instead of the operator.
            if ((Test-Path -LiteralPath (Join-Path $candidate "lib\cmake\Qt6\Qt6Config.cmake")) `
                -and (Test-Path -LiteralPath (Join-Path $candidate "bin\qmake.exe"))) {
                return [IO.Path]::GetFullPath($candidate)
            }
        }

        return $null
    }

    function Get-MissingNativeTool {
        $missing = @()
        if (-not $IsWindows) {
            $missing += "a Windows host"
        } else {
            $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
            if (-not (Test-Path -LiteralPath $vswhere)) { $missing += "vswhere.exe (Visual Studio x64 C++ tools)" }
        }
        foreach ($tool in @("cmake", "ninja")) {
            if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { $missing += $tool }
        }
        if (-not (Get-ProvisionedQtRoot)) { $missing += "installed Qt (QT_ROOT_DIR/Qt6_DIR with bin\qmake.exe)" }

        return $missing
    }

    # A step that ran after the toolchain installation opts in here; a missing tool
    # must then fail the step rather than leave the native cases silently skipped.
    if ($env:MUSE_FORK_REQUIRE_NATIVE_TOOLCHAIN -eq "1") {
        $missing = @(Get-MissingNativeTool)
        if ($missing.Count -gt 0) {
            throw "MUSE_FORK_REQUIRE_NATIVE_TOOLCHAIN=1 but the native toolchain is incomplete; missing: $($missing -join ', ')."
        }
    }

    function New-GitRepository {
        param([Parameter(Mandatory = $true)][string] $Path)

        New-Item -ItemType Directory -Force -Path $Path | Out-Null
        & git -C $Path init -q
        if ($LASTEXITCODE -ne 0) { throw "git init failed in '$Path'" }
        & git -C $Path config user.email "fork-ci@example.invalid"
        & git -C $Path config user.name "fork-ci"
        & git -C $Path add --all
        $commitOutput = & git -C $Path -c commit.gpgsign=false commit -qm "fixture" 2>&1
        if ($LASTEXITCODE -ne 0) { throw "git commit failed in '$Path': $commitOutput" }

        return (& git -C $Path rev-parse HEAD).Trim()
    }

    function New-SourceFixture {
        param(
            [Parameter(Mandatory = $true)][string] $Root,
            [string] $DriverBody = "# stub driver",
            # Real driver copy; when set, (re)places -DriverBody.
            [string] $DriverSourcePath,
            [string[]] $CMakeListsBody = @("cmake_minimum_required(VERSION 3.22)"),
            [switch] $WithoutSoundfont
        )

        New-Item -ItemType Directory -Force -Path $Root | Out-Null
        Set-Content -LiteralPath (Join-Path $Root "CMakeLists.txt") -Value $CMakeListsBody
        Set-Content -LiteralPath (Join-Path $Root "version.cmake") -Value @(
            'set(MUSE_APP_NAME_MACHINE_READABLE "MuseScoreStudio")',
            'set(MUSE_APP_VERSION_MAJOR "5")',
            'set(MUSE_APP_VERSION_MINOR "0")',
            'set(MUSE_APP_VERSION_PATCH "0")'
        )
        if ($DriverSourcePath) {
            Copy-Item -LiteralPath $DriverSourcePath -Destination (Join-Path $Root "ninja_build.ps1")
        } else {
            Set-Content -LiteralPath (Join-Path $Root "ninja_build.ps1") -Value $DriverBody
        }

        if (-not $WithoutSoundfont) {
            # The fork builds the soundfont committed in the source tree
            # (MUSESCORE_DOWNLOAD_SOUNDFONT=OFF), so the fixture must carry it.
            $soundRoot = Join-Path $Root "share/sound"
            New-Item -ItemType Directory -Force -Path $soundRoot | Out-Null
            Set-Content -LiteralPath (Join-Path $soundRoot "MS Basic.sf3") -Value "fixture soundfont"
            Set-Content -LiteralPath (Join-Path $soundRoot "MS Basic_License.md") -Value "fixture license"
            Set-Content -LiteralPath (Join-Path $soundRoot "SF_VERSION") -Value "0.2.0"
        }

        $frameworkRoot = Join-Path $Root "muse"
        New-Item -ItemType Directory -Force -Path $frameworkRoot | Out-Null
        Set-Content -LiteralPath (Join-Path $frameworkRoot "CMakeLists.txt") -Value "project(muse_framework)"
        $lockDirectory = Join-Path $frameworkRoot "buildscripts/cmake/deps"
        New-Item -ItemType Directory -Force -Path $lockDirectory | Out-Null
        Set-Content -LiteralPath (Join-Path $lockDirectory "dependencies.lock.cmake") -Value "# controlled dependency fixture"
        $null = New-GitRepository -Path $frameworkRoot

        Set-Content -LiteralPath (Join-Path $Root ".gitmodules") -Value @(
            '[submodule "muse_framework"]',
            '    path = muse',
            '    url = https://github.com/tbui17/muse_framework.git'
        )
        $sourceSha = New-GitRepository -Path $Root

        return @{ Root = $Root; SourceSha = $sourceSha }
    }

    function New-HelperArguments {
        param(
            [Parameter(Mandatory = $true)][hashtable] $Fixture,
            [Parameter(Mandatory = $true)][string] $OutputDirectory,
            [Parameter(Mandatory = $true)][string] $ProvenancePath
        )

        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ProvenancePath) | Out-Null
        @{
            source_sha = $Fixture.SourceSha
            framework_sha = (& git -C (Join-Path $Fixture.Root "muse") rev-parse HEAD).Trim()
            framework_url = "https://github.com/tbui17/muse_framework.git"
            workflow_sha = ("c" * 40)
        } | ConvertTo-Json | Set-Content -LiteralPath $ProvenancePath
        return @(
            "-SourceDirectory", $Fixture.Root,
            "-OutputDirectory", $OutputDirectory,
            "-ProvenancePath", $ProvenancePath,
            "-SourceSha", $Fixture.SourceSha,
            "-BuildNumber", "4242"
        )
    }

    function Invoke-BuildHelper {
        param(
            [Parameter(Mandatory = $true)][string[]] $Arguments,
            [hashtable] $Environment = @{}
        )

        $pwsh = if ($IsWindows) { "pwsh.exe" } else { "pwsh" }
        $previousWorkflowSha = $env:WORKFLOW_SHA
        $restore = @{}
        foreach ($name in $Environment.Keys) {
            $restore[$name] = [Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name, $Environment[$name])
        }
        try {
            $env:WORKFLOW_SHA = "c" * 40
            $output = & $pwsh -NoProfile -NonInteractive -File $Helper @Arguments 2>&1 | Out-String
            $exitCode = $LASTEXITCODE
        } finally {
            $env:WORKFLOW_SHA = $previousWorkflowSha
            foreach ($name in $Environment.Keys) {
                [Environment]::SetEnvironmentVariable($name, $restore[$name])
            }
        }

        # PowerShell wraps formatted error text and may colour it; flatten both so
        # assertions do not depend on the console width or on ANSI escapes.
        $escape = [char]27
        $normalized = ($output -replace "$escape\[[0-9;]*[A-Za-z]", ' ' -replace '\|', ' ') -replace '\s+', ' '

        return @{ ExitCode = $exitCode; Output = $output; Normalized = $normalized }
    }

    function Assert-NativeFailure {
        param(
            [Parameter(Mandatory = $true)][hashtable] $Result,
            [Parameter(Mandatory = $true)][string] $Marker,
            [Parameter(Mandatory = $true)][string] $LogPath,
            [Parameter(Mandatory = $true)][string] $ProvenancePath
        )

        $Result.ExitCode | Should -Not -Be 0
        # The wrapper message proves the driver's non-zero status crossed the process
        # boundary instead of being swallowed.
        $Result.Normalized | Should -Match "The build driver failed with exit code [1-9][0-9]*"
        $Result.Normalized | Should -Match ([regex]::Escape($Marker))

        (Get-Content -LiteralPath $LogPath -Raw) | Should -Match ([regex]::Escape($Marker))
        $record = Get-Content -LiteralPath $ProvenancePath -Raw | ConvertFrom-Json -AsHashtable
        $record.ContainsKey("application_version") | Should -BeFalse
    }

    function New-StageCase {
        param([Parameter(Mandatory = $true)][string] $Name)

        $caseRoot = Join-Path $TestDrive ("case-" + [Guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Force -Path $caseRoot | Out-Null

        $output = Join-Path $caseRoot "build-output"

        return @{
            FixtureRoot = Join-Path $caseRoot $Name
            Output      = $output
            Log         = Join-Path (Join-Path $output "logs") "ninja-build.log"
            Provenance  = Join-Path (Join-Path $caseRoot "provenance") "provenance.json"
        }
    }
}

Describe "windows-build.ps1 input validation" {
    BeforeEach {
        # Every test gets its own case directory: a reused TestDrive would leave committed
        # fixture repositories behind and make the fixture commit a no-op.
        $caseRoot = Join-Path $TestDrive ("case-" + [Guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Force -Path $caseRoot | Out-Null
        $fixture = New-SourceFixture -Root (Join-Path $caseRoot "source")
        $output = Join-Path $caseRoot "build-output"
        $provenance = Join-Path $caseRoot "provenance/provenance.json"
    }

    It "rejects a placeholder source SHA" {
        $result = Invoke-BuildHelper -Arguments (@(
            "-SourceDirectory", $fixture.Root, "-OutputDirectory", $output, "-ProvenancePath", $provenance,
            "-SourceSha", "abc123456", "-BuildNumber", "4242"))
        $result.ExitCode | Should -Not -Be 0
        $result.Normalized | Should -Match "full 40-character"
    }

    It "rejects a SHA that does not match the checkout" {
        $result = Invoke-BuildHelper -Arguments (@(
            "-SourceDirectory", $fixture.Root, "-OutputDirectory", $output, "-ProvenancePath", $provenance,
            "-SourceSha", ("0" * 40), "-BuildNumber", "4242"))
        $result.ExitCode | Should -Not -Be 0
        $result.Normalized | Should -Match "does not match the checked out commit"
    }

    It "rejects a placeholder or malformed build number" {
        foreach ($number in @("abc", "1234567890")) {
            $result = Invoke-BuildHelper -Arguments (@(
                "-SourceDirectory", $fixture.Root, "-OutputDirectory", $output, "-ProvenancePath", $provenance,
                "-SourceSha", $fixture.SourceSha, "-BuildNumber", $number))
            $result.ExitCode | Should -Not -Be 0
        }
    }

    It "rejects a missing source directory" {
        $result = Invoke-BuildHelper -Arguments (@(
            "-SourceDirectory", (Join-Path $caseRoot "absent"), "-OutputDirectory", $output,
            "-ProvenancePath", $provenance, "-SourceSha", $fixture.SourceSha, "-BuildNumber", "4242"))
        $result.ExitCode | Should -Not -Be 0
        $result.Normalized | Should -Match "does not exist"
    }
}

Describe "windows-build.ps1 source and staging checks" {
    BeforeEach {
        $caseRoot = Join-Path $TestDrive ("case-" + [Guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Force -Path $caseRoot | Out-Null
        $fixture = New-SourceFixture -Root (Join-Path $caseRoot "source")
        $output = Join-Path $caseRoot "build-output"
        $provenance = Join-Path $caseRoot "provenance/provenance.json"
    }

    It "rejects a source tree without the build driver" {
        Remove-Item -LiteralPath (Join-Path $fixture.Root "ninja_build.ps1")
        $result = Invoke-BuildHelper -Arguments (New-HelperArguments -Fixture $fixture -OutputDirectory $output -ProvenancePath $provenance)
        $result.ExitCode | Should -Not -Be 0
        $result.Normalized | Should -Match "is missing 'ninja_build.ps1'"
    }

    It "rejects an output directory inside the source tree" {
        $result = Invoke-BuildHelper -Arguments (New-HelperArguments -Fixture $fixture `
            -OutputDirectory (Join-Path $fixture.Root "out") -ProvenancePath $provenance)
        $result.ExitCode | Should -Not -Be 0
        $result.Normalized | Should -Match "must not be inside"
    }

    It "rejects a provenance path inside the source tree" {
        $result = Invoke-BuildHelper -Arguments (New-HelperArguments -Fixture $fixture `
            -OutputDirectory $output -ProvenancePath (Join-Path $fixture.Root "provenance.json"))
        $result.ExitCode | Should -Not -Be 0
        $result.Normalized | Should -Match "must not be inside"
    }

    It "rejects a source tree without the committed soundfont" {
        # Deleted after the commit would just look like a dirty checkout, so the
        # fixture is built without the payload.
        $fixture = New-SourceFixture -Root (Join-Path $caseRoot "source-no-soundfont") -WithoutSoundfont
        $result = Invoke-BuildHelper -Arguments (New-HelperArguments -Fixture $fixture -OutputDirectory $output -ProvenancePath $provenance)
        $result.ExitCode | Should -Not -Be 0
        $result.Normalized | Should -Match "committed soundfont payload"
    }

    It "rejects a dirty application checkout" {
        Set-Content -LiteralPath (Join-Path $fixture.Root "CMakeLists.txt") -Value "cmake_minimum_required(VERSION 3.23)"
        $result = Invoke-BuildHelper -Arguments (New-HelperArguments -Fixture $fixture -OutputDirectory $output -ProvenancePath $provenance)
        $result.ExitCode | Should -Not -Be 0
        $result.Normalized | Should -Match "uncommitted tracked changes"
    }

    It "rejects a dirty framework checkout" {
        Set-Content -LiteralPath (Join-Path $fixture.Root "muse/CMakeLists.txt") -Value "project(muse_framework_patched)"
        $result = Invoke-BuildHelper -Arguments (New-HelperArguments -Fixture $fixture -OutputDirectory $output -ProvenancePath $provenance)
        $result.ExitCode | Should -Not -Be 0
        $result.Normalized | Should -Match "framework checkout"
    }

    It "rejects an already configured build tree" {
        $buildTree = Join-Path $fixture.Root "build.release"
        New-Item -ItemType Directory -Force -Path $buildTree | Out-Null
        Set-Content -LiteralPath (Join-Path $buildTree "CMakeCache.txt") -Value "# stale cache"
        $result = Invoke-BuildHelper -Arguments (New-HelperArguments -Fixture $fixture -OutputDirectory $output -ProvenancePath $provenance)
        $result.ExitCode | Should -Not -Be 0
        $result.Normalized | Should -Match "already exists"
    }

    It "rejects a non-empty install staging directory" {
        New-Item -ItemType Directory -Force -Path (Join-Path $output "install") | Out-Null
        Set-Content -LiteralPath (Join-Path $output "install/stale.txt") -Value "stale"
        $result = Invoke-BuildHelper -Arguments (New-HelperArguments -Fixture $fixture -OutputDirectory $output -ProvenancePath $provenance)
        $result.ExitCode | Should -Not -Be 0
        $result.Normalized | Should -Match "is not empty"
    }
}

Describe "windows-build.ps1 driver exit propagation" -Skip:(-not $script:NativeAvailable) {
    It "surfaces a non-zero driver exit code" {
        $case = New-StageCase -Name "source-stub"
        $fixture = New-SourceFixture -Root $case.FixtureRoot -DriverBody "Write-Host 'stub driver'; exit 9"
        $qtRoot = Get-ProvisionedQtRoot

        $result = Invoke-BuildHelper `
            -Arguments (New-HelperArguments -Fixture $fixture -OutputDirectory $case.Output -ProvenancePath $case.Provenance) `
            -Environment @{ QT_ROOT_DIR = $qtRoot }

        $result.ExitCode | Should -Not -Be 0
        $result.Normalized | Should -Match "exit code 9"
        $result.Normalized | Should -Match "ninja-build.log"
        # The stub driver fails before any install rule runs, so the build must not be
        # stamped with an application version.
        $record = Get-Content -LiteralPath $case.Provenance -Raw | ConvertFrom-Json -AsHashtable
        $record.ContainsKey("application_version") | Should -BeFalse
    }
}

Describe "windows-build.ps1 native stage exit propagation" -Skip:(-not $script:NativeAvailable) {
    BeforeEach {
        # The driver is the real ninja_build.ps1; only the CMake project is minimal, so no
        # application code is compiled. The injected stage fails through the real
        # cmake/ninja toolchain and must cross both the driver and the wrapper boundary.
        $qtRoot = Get-ProvisionedQtRoot
    }

    It "propagates a non-zero configure exit code" {
        $case = New-StageCase -Name "source-configure"
        $fixture = New-SourceFixture -Root $case.FixtureRoot -DriverSourcePath $DriverSource -CMakeListsBody @(
            "cmake_minimum_required(VERSION 3.22)",
            "project(fork_stage_failure LANGUAGES NONE)",
            'message(FATAL_ERROR "injected configure failure")'
        )

        $result = Invoke-BuildHelper `
            -Arguments (New-HelperArguments -Fixture $fixture -OutputDirectory $case.Output -ProvenancePath $case.Provenance) `
            -Environment @{ QT_ROOT_DIR = $qtRoot }

        Assert-NativeFailure -Result $result -Marker "injected configure failure" -LogPath $case.Log -ProvenancePath $case.Provenance
    }

    It "propagates a non-zero build exit code" {
        $case = New-StageCase -Name "source-build"
        $fixture = New-SourceFixture -Root $case.FixtureRoot -DriverSourcePath $DriverSource -CMakeListsBody @(
            "cmake_minimum_required(VERSION 3.22)",
            "project(fork_stage_failure LANGUAGES NONE)",
            "add_custom_target(fork_stage_failure ALL",
            '    COMMAND ${CMAKE_COMMAND} -E echo "injected build failure"',
            "    COMMAND ${CMAKE_COMMAND} -E false",
            "    VERBATIM)"
        )

        $result = Invoke-BuildHelper `
            -Arguments (New-HelperArguments -Fixture $fixture -OutputDirectory $case.Output -ProvenancePath $case.Provenance) `
            -Environment @{ QT_ROOT_DIR = $qtRoot }

        Assert-NativeFailure -Result $result -Marker "injected build failure" -LogPath $case.Log -ProvenancePath $case.Provenance
    }

    It "propagates a non-zero install exit code" {
        $case = New-StageCase -Name "source-install"
        $fixture = New-SourceFixture -Root $case.FixtureRoot -DriverSourcePath $DriverSource -CMakeListsBody @(
            "cmake_minimum_required(VERSION 3.22)",
            "project(fork_stage_failure LANGUAGES NONE)",
            'install(CODE "message(FATAL_ERROR \"injected install failure\")")'
        )

        $result = Invoke-BuildHelper `
            -Arguments (New-HelperArguments -Fixture $fixture -OutputDirectory $case.Output -ProvenancePath $case.Provenance) `
            -Environment @{ QT_ROOT_DIR = $qtRoot }

        Assert-NativeFailure -Result $result -Marker "injected install failure" -LogPath $case.Log -ProvenancePath $case.Provenance
    }
}
