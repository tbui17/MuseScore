#!/usr/bin/env pwsh
# SPDX-License-Identifier: GPL-3.0-only
# MuseScore-Studio-CLA-applies
#
# Negative tests for buildscripts/ci/fork/windows-build.ps1.
#
# The helper runs as a child process so each test asserts the exit code and the
# message a workflow would see. Nothing here builds the application: the tests
# either stop before the toolchain is touched (input/source/layout validation) or
# replace the driver with a stub that fails.
#
#   pwsh -NoProfile -Command "Invoke-Pester -Path buildscripts/ci/fork/tests/windows-build.tests.ps1"

BeforeDiscovery {
    # Only the driver-exit-code test needs the real MSVC toolchain.
    $script:ToolchainAvailable = $false
    if ($IsWindows) {
        $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
        $script:ToolchainAvailable = (Test-Path -LiteralPath $vswhere) `
            -and [bool](Get-Command cmake -ErrorAction SilentlyContinue) `
            -and [bool](Get-Command ninja -ErrorAction SilentlyContinue)
    }
}

BeforeAll {
    $Helper = (Resolve-Path (Join-Path $PSScriptRoot "../windows-build.ps1")).Path

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
            [switch] $WithoutSoundfont
        )

        New-Item -ItemType Directory -Force -Path $Root | Out-Null
        Set-Content -LiteralPath (Join-Path $Root "CMakeLists.txt") -Value "cmake_minimum_required(VERSION 3.22)"
        Set-Content -LiteralPath (Join-Path $Root "version.cmake") -Value @(
            'set(MUSE_APP_NAME_MACHINE_READABLE "MuseScoreStudio")',
            'set(MUSE_APP_VERSION_MAJOR "5")',
            'set(MUSE_APP_VERSION_MINOR "0")',
            'set(MUSE_APP_VERSION_PATCH "0")'
        )
        Set-Content -LiteralPath (Join-Path $Root "ninja_build.ps1") -Value $DriverBody

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

    function New-FakeQt {
        param([Parameter(Mandatory = $true)][string] $Root)

        New-Item -ItemType Directory -Force -Path (Join-Path $Root "lib/cmake/Qt6") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $Root "bin") | Out-Null
        Set-Content -LiteralPath (Join-Path $Root "lib/cmake/Qt6/Qt6Config.cmake") -Value "# fixture"
        Set-Content -LiteralPath (Join-Path $Root "lib/cmake/Qt6/Qt6ConfigVersion.cmake") -Value 'set(PACKAGE_VERSION "6.10.2")'
        Set-Content -LiteralPath (Join-Path $Root "bin/windeployqt.exe") -Value ""
        Set-Content -LiteralPath (Join-Path $Root "bin/lrelease.exe") -Value ""

        return $Root
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
        param([Parameter(Mandatory = $true)][string[]] $Arguments)

        $pwsh = if ($IsWindows) { "pwsh.exe" } else { "pwsh" }
        $previousWorkflowSha = $env:WORKFLOW_SHA
        try {
            $env:WORKFLOW_SHA = "c" * 40
            $output = & $pwsh -NoProfile -NonInteractive -File $Helper @Arguments 2>&1 | Out-String
            $exitCode = $LASTEXITCODE
        } finally {
            $env:WORKFLOW_SHA = $previousWorkflowSha
        }

        # PowerShell wraps formatted error text and may colour it; flatten both so
        # assertions do not depend on the console width or on ANSI escapes.
        $escape = [char]27
        $normalized = ($output -replace "$escape\[[0-9;]*[A-Za-z]", ' ' -replace '\|', ' ') -replace '\s+', ' '

        return @{ ExitCode = $exitCode; Output = $output; Normalized = $normalized }
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

Describe "windows-build.ps1 build failure propagation" -Skip:(-not $script:ToolchainAvailable) {
    It "surfaces a non-zero driver exit code" {
        $caseRoot = Join-Path $TestDrive ("case-" + [Guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Force -Path $caseRoot | Out-Null
        $fixture = New-SourceFixture -Root (Join-Path $caseRoot "source-stub") -DriverBody "Write-Host 'stub driver'; exit 9"
        $env:QT_ROOT_DIR = New-FakeQt -Root (Join-Path $caseRoot "qt")
        $output = Join-Path $caseRoot "stub-output"
        $provenance = Join-Path $caseRoot "stub-provenance/provenance.json"

        $result = Invoke-BuildHelper -Arguments (New-HelperArguments -Fixture $fixture -OutputDirectory $output -ProvenancePath $provenance)

        $result.ExitCode | Should -Not -Be 0
        $result.Normalized | Should -Match "exit code 9"
        $result.Normalized | Should -Match "ninja-build.log"
        $record = Get-Content -LiteralPath $provenance -Raw | ConvertFrom-Json -AsHashtable
        $record.ContainsKey("application_version") | Should -BeFalse
    }
}
