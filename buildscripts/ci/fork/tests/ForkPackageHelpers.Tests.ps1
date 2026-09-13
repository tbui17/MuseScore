#!/usr/bin/env pwsh
# SPDX-License-Identifier: GPL-3.0-only
#
# Pester 5 wrapper for the fork Windows packaging helper suite.
#
# The suite itself lives in Test-PackageHelpers.ps1 so it can also run without
# Pester (`pwsh -File buildscripts/ci/fork/tests/Test-PackageHelpers.ps1`).
# This wrapper exists so `Invoke-Pester -Path buildscripts/ci/fork/tests` also
# executes it during preflight.

BeforeAll {
    $script:HelperSuite = Join-Path $PSScriptRoot 'Test-PackageHelpers.ps1'
}

Describe 'MuseScore fork Windows package helpers' {
    It 'passes the structural and negative helper suite' {
        & pwsh -NoProfile -NonInteractive -File $script:HelperSuite
        $LASTEXITCODE | Should -Be 0 -Because 'the helper suite must pass before an expensive Windows build is queued'
    }
}
