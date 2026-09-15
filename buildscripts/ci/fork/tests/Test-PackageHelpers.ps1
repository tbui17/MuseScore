#!/usr/bin/env pwsh
# SPDX-License-Identifier: GPL-3.0-only
#
# Cheap negative/structural tests for the fork Windows packaging helpers:
#   buildscripts/ci/fork/package-windows.ps1
#   buildscripts/ci/fork/test-windows-package.ps1
#
# These tests use a synthetic install tree and a synthetic git checkout. They
# intentionally do NOT build or run MuseScore. Cases that must launch the
# packaged executable use a POSIX stub and are skipped on Windows; the real
# executable is exercised by the hosted fresh-runner job.
#
# Runs anywhere pwsh 7 is available:
#   pwsh -File buildscripts/ci/fork/tests/Test-PackageHelpers.ps1
#
# Exit code 0 = every applicable case passed.

[CmdletBinding()]
param(
    [string] $RepositoryRoot = '',
    [string] $WorkRoot = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:IsWindowsHost = ($env:OS -eq 'Windows_NT')

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../..')).Path
}
if ([string]::IsNullOrWhiteSpace($WorkRoot)) {
    $WorkRoot = Join-Path ([IO.Path]::GetTempPath()) ("musescore-fork-package-tests-" + [Guid]::NewGuid().ToString('n'))
}

$PackageHelper = Join-Path $RepositoryRoot 'buildscripts/ci/fork/package-windows.ps1'
$RuntimeHelper = Join-Path $RepositoryRoot 'buildscripts/ci/fork/test-windows-package.ps1'

$script:Passed = 0
$script:Failed = 0
$script:Skipped = 0

function Assert-True {
    param(
        [Parameter(Mandatory = $false)] $Condition,
        [Parameter(Mandatory = $true)][string] $Message
    )
    if (-not $Condition) {
        throw $Message
    }
}

function Invoke-Case {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][scriptblock] $Body
    )
    try {
        & $Body
        $script:Passed++
        Write-Host "PASS $Name"
    } catch {
        $script:Failed++
        Write-Host "FAIL $Name :: $($_.Exception.Message)"
    }
}

function Skip-Case {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][string] $Reason
    )
    $script:Skipped++
    Write-Host "SKIP $Name :: $Reason"
}

function Invoke-Helper {
    param(
        [Parameter(Mandatory = $true)][string] $Script,
        [Parameter(Mandatory = $true)][string[]] $Arguments,
        [Parameter(Mandatory = $false)][hashtable] $Environment = @{}
    )

    $saved = @{}
    foreach ($name in $Environment.Keys) {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name)
        [Environment]::SetEnvironmentVariable($name, $Environment[$name])
    }
    try {
        $output = & pwsh -NoProfile -NonInteractive -File $Script @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        foreach ($name in $saved.Keys) {
            [Environment]::SetEnvironmentVariable($name, $saved[$name])
        }
    }

    # Collapse the console-wrapped error text so assertions can match phrases that PowerShell
    # formatting may break across lines: it renders a thrown message wrapped and prefixed with '|',
    # so those continuation lines are joined before whitespace is collapsed.
    $flattened = ((($output | Out-String) -replace '(?m)\r?\n\s*\|\s*', ' ') -replace '\s+', ' ').Trim()
    return @{ ExitCode = $exitCode; Output = $flattened }
}

function Invoke-ProfilePlan {
    <#
        Runs the runtime helper's first-run profile hook. Keeps the emitted text unflattened so the
        JSON stays parseable, and restores the environment afterwards.
    #>
    param(
        [Parameter(Mandatory = $true)][string[]] $Arguments,
        [Parameter(Mandatory = $false)][hashtable] $Environment = @{}
    )

    $saved = @{}
    foreach ($name in $Environment.Keys) {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name)
        [Environment]::SetEnvironmentVariable($name, $Environment[$name])
    }
    try {
        $raw = & pwsh -NoProfile -NonInteractive -File $RuntimeHelper @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        foreach ($name in $saved.Keys) {
            [Environment]::SetEnvironmentVariable($name, $saved[$name])
        }
    }

    $text = ($raw | Out-String).Trim()
    # PowerShell renders a thrown message wrapped and prefixed with '|'; join those continuation
    # lines before collapsing whitespace so assertions can match a phrase that spans the wrap.
    $flattened = (($text -replace '(?m)\r?\n\s*\|\s*', ' ') -replace '\s+', ' ').Trim()
    $plan = $null
    try {
        $plan = $text | ConvertFrom-Json
    } catch {
        $plan = $null
    }
    return @{ ExitCode = $exitCode; Text = $text; Flattened = $flattened; Plan = $plan }
}

function New-FakeSource {
    param(
        [Parameter(Mandatory = $true)][string] $Root,
        [switch] $IncludeFeatureTest
    )

    New-Item -ItemType Directory -Path $Root -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $Root 'version.cmake'), @'
set(MUSE_APP_NAME_MACHINE_READABLE "MuseScoreStudio")
set(MUSE_APP_VERSION_MAJOR "5")
set(MUSE_APP_VERSION_MINOR "0")
set(MUSE_APP_VERSION_PATCH "0")
set(MUSE_APP_UNSTABLE ON)
'@, [Text.UTF8Encoding]::new($false))

    $scriptsDir = Join-Path $Root 'share/testflowscripts'
    New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null
    foreach ($fixtureName in $script:FixtureTestCases.Keys) {
        $fixtureCase = $script:FixtureTestCases[$fixtureName]
        $stepEntries = @($fixtureCase.Steps | ForEach-Object { "        {name: `"$_`", func: function() {}}" })
        $scriptText = @"
var testCase = {
    name: "$($fixtureCase.Name)",
    description: "fixture test case, not the reviewed case",
    steps: [
$($stepEntries -join ",`n")
    ]
};
function main()
{
    api.testflow.runTestCase(testCase)
}
"@
        [IO.File]::WriteAllText((Join-Path $scriptsDir $fixtureName), $scriptText, [Text.UTF8Encoding]::new($false))
    }

    if ($IncludeFeatureTest) {
        $fixtureCase = $script:FeatureFixtureCase
        $stepEntries = @($fixtureCase.Steps | ForEach-Object { "        {name: `"$_`", func: function() {}}" })
        $scriptText = @"
var testCase = {
    name: "$($fixtureCase.Name)",
    description: "feature fixture shape, not a GUI assertion",
    steps: [
$($stepEntries -join ",`n")
    ]
};
function main()
{
    api.testflow.runTestCase(testCase)
}
"@
        [IO.File]::WriteAllText((Join-Path $scriptsDir $script:FeatureFixtureName), $scriptText, [Text.UTF8Encoding]::new($false))
    }

    $fixtureDir = Join-Path $Root 'vtest/scores'
    New-Item -ItemType Directory -Path $fixtureDir -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $fixtureDir 'layout-5.mscx'), '<museScore/>', [Text.UTF8Encoding]::new($false))

    & git -C $Root init -q
    & git -C $Root -c user.email=ci@example.invalid -c user.name=ci add -A
    & git -C $Root -c user.email=ci@example.invalid -c user.name=ci commit -q -m 'fixture'
    $head = (& git -C $Root rev-parse HEAD).Trim()
    return $head
}

function Get-ObjectProperty {
    param(
        [Parameter(Mandatory = $false)] $Object,
        [Parameter(Mandatory = $true)][string] $Name
    )
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-ResourceExpectations {
    $result = & pwsh -NoProfile -NonInteractive -File $PackageHelper -ExportResourceExpectations
    Assert-True ($LASTEXITCODE -eq 0) 'ExportResourceExpectations must exit 0'
    $parsed = ($result | Out-String) | ConvertFrom-Json
    Assert-True ($null -ne $parsed) 'ExportResourceExpectations must emit JSON'
    Assert-True (@($parsed).Count -gt 0) 'ExportResourceExpectations must not be empty'
    return @($parsed)
}

function New-FakeInstall {
    param(
        [Parameter(Mandatory = $true)][string] $Root,
        [Parameter(Mandatory = $true)][object[]] $Expectations,
        [Parameter(Mandatory = $true)][string] $ExecutableRelativePath,
        [Parameter(Mandatory = $false)][string] $ExecutableBody = '#!/bin/sh
exit 0'
    )

    New-Item -ItemType Directory -Path $Root -Force | Out-Null

    $exeFull = Join-Path $Root ($ExecutableRelativePath -replace '/', [IO.Path]::DirectorySeparatorChar)
    New-Item -ItemType Directory -Path (Split-Path -Parent $exeFull) -Force | Out-Null
    [IO.File]::WriteAllText($exeFull, "$ExecutableBody`n", [Text.UTF8Encoding]::new($false))
    if (-not $script:IsWindowsHost) {
        & chmod +x $exeFull
    }

    foreach ($expectation in $Expectations) {
        $kind = [string] $expectation.kind
        switch ($kind) {
            'file' {
                $full = Join-Path $Root (([string] $expectation.path) -replace '/', [IO.Path]::DirectorySeparatorChar)
                New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
                [IO.File]::WriteAllText($full, 'resource', [Text.UTF8Encoding]::new($false))
            }
            'anyfile' {
                $full = Join-Path $Root (([string] $expectation.paths[0]) -replace '/', [IO.Path]::DirectorySeparatorChar)
                New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
                [IO.File]::WriteAllText($full, 'runtime', [Text.UTF8Encoding]::new($false))
            }
            'dirhas' {
                $dir = Join-Path $Root (([string] $expectation.path) -replace '/', [IO.Path]::DirectorySeparatorChar)
                $sub = Join-Path $dir 'sub'
                New-Item -ItemType Directory -Path $sub -Force | Out-Null
                $filter = Get-ObjectProperty -Object $expectation -Name 'filter'
                if ([string]::IsNullOrWhiteSpace($filter) -or $filter -eq '*') {
                    $name = 'item.txt'
                } else {
                    $name = $filter.Replace('*', 'x')
                }
                [IO.File]::WriteAllText((Join-Path $sub $name), 'resource', [Text.UTF8Encoding]::new($false))
            }
            default { throw "unknown expectation kind '$kind'" }
        }
    }
}

function New-FakeProvenance {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $SourceSha,
        [Parameter(Mandatory = $false)][string] $WorkflowSha = 'a' * 40,
        [Parameter(Mandatory = $false)][string] $FrameworkSha = 'b' * 40,
        [Parameter(Mandatory = $false)][string] $ApplicationVersion = '5.0.0.12345678',
        [Parameter(Mandatory = $false)][string[]] $DropKeys = @()
    )

    $provenance = [ordered]@{
        repository           = 'tbui17/MuseScore'
        requested_source_ref = 'refs/heads/ci/fork-windows-releases'
        source_sha           = $SourceSha
        framework_url        = 'https://github.com/tbui17/muse_framework.git'
        framework_sha        = $FrameworkSha
        workflow_sha         = $WorkflowSha
        run_id               = '1234567890'
        run_attempt          = '1'
        application_version  = $ApplicationVersion
        channel              = 'development'
        build_type           = 'RelWithDebInfo'
        features             = [ordered]@{ audio_export = $true; braille = $true }
        toolchain            = [ordered]@{ cmake = '3.30.0'; ninja = '1.12.1'; qt = '6.10.2' }
        dependency_lock      = "muse_framework@$FrameworkSha"
    }
    foreach ($key in $DropKeys) {
        $provenance.Remove($key) | Out-Null
    }
    [IO.File]::WriteAllText($Path, (ConvertTo-Json -InputObject $provenance -Depth 8), [Text.UTF8Encoding]::new($false))
}

# Minimal fixture test cases standing in for the reviewed scripts. They declare the shape the
# runtime helper reads from a reviewed script (a test case name and a nonempty ordered step
# list) but they are deliberately not the real TC11/TC14 cases. The helper tests never claim
# packaged-application evidence from them.
$script:FixtureTestCases = [ordered]@{
    'TC11_CommandPaletteDialog.js'    = @{
        Name  = 'TC11: fixture command palette dialog'
        Steps = @('Open command palette', 'Verify the dialog is open')
    }
    'TC14_CommandPaletteAnnounce.js'  = @{
        Name  = 'TC14: fixture command palette announcement'
        Steps = @('Open command palette', 'Navigate and announce a result')
    }
}

# The feature fixture mirrors the reviewed TC15 shape so the runtime-selection and missing-install
# regressions can run without pretending that a POSIX stub is evidence for a real GUI binary.
$script:FeatureFixtureName = 'TC15_RegionEntryAnnounce.js'
$script:FeatureFixtureCase = @{
    Name  = 'TC15: Region entry announces score view on focus'
    Steps = @(
        'Close score (if opened) and go to home to start'
        'Open New Score Dialog'
        'Select Instruments'
        'Create score'
        'Wait for notation page to settle'
        "Verify 'Score view' was announced on score open"
        'Tab to status bar — should NOT re-announce ''Score view'''
        "Return to score canvas — should announce 'Score view'"
        "F6 to next section — should NOT re-announce 'Score view'"
    )
}

$script:StubTemplate = @'
#!/bin/sh
case "$1" in
  --version)
    printf 'MuseScoreStudio5Development 5.0.0\n'
    ENV_PROBE
    STRAY_OUTPUT
    exit 0
    ;;
  -o)
    case "$2" in
      *.pdf)
        PDF_WRITER
        ;;
      *.mscz)
        ZIP_WRITER
        ;;
      *)
        exit 1
        ;;
    esac
    exit 0
    ;;
  --test-case-gui)
    case "$2" in
      *TC11_CommandPaletteDialog.js)
        TC11_REPORT
        ;;
      *TC14_CommandPaletteAnnounce.js)
        TC14_REPORT
        ;;
PROBE_BRANCHES
    esac
    ;;
esac
exit 1
'@

function New-TestflowStubReport {
    <#
        Builds the shell block that stands in for Testflow::runTestCase()/TestCaseReport for one
        fixture test script. It writes the same report shape the application writes under
        $MUSE_TESTFLOW_DATA_PATH/reports, so the runtime helper's report validation can be
        exercised without the application; $ReportMode selects the defect it reproduces.
    #>
    param(
        [Parameter(Mandatory = $true)][string] $ScriptFileName,
        [Parameter(Mandatory = $true)][string] $ReportMode
    )

    $fixtureCase = $script:FixtureTestCases[$ScriptFileName]
    $safeName = ($fixtureCase.Name -replace '[^A-Za-z0-9]+', '_').Trim('_')
    $reportFile = '$MUSE_TESTFLOW_DATA_PATH/reports/' + $safeName + '_250101000000.txt'

    $body = @()
    switch ($ReportMode) {
        'Missing' {
            # No reports directory at all, while the stub still exits 0: the behaviour a zero
            # exit status alone cannot distinguish from a test case that ran.
            $body += ':'
        }
        'DirectoryOnly' {
            $body += 'mkdir -p "$MUSE_TESTFLOW_DATA_PATH/reports"'
        }
        default {
            $reportLines = @()
            $reportLines += "Test: $($fixtureCase.Name)"
            $reportLines += 'date: 2026.01.01 00:00'
            if ($ReportMode -eq 'Empty') {
                $reportLines += 'steps: '
            } else {
                $reportLines += "steps: $($fixtureCase.Steps -join ' -> ')"
                $reportLines += ''
                if ($ReportMode -eq 'Incomplete') {
                    $reportLines += "  started step: $($fixtureCase.Steps[0])"
                    $reportLines += "  finished step: $($fixtureCase.Steps[0]) [10 msec]"
                } elseif ($ReportMode -eq 'Aborted') {
                    $reportLines += "  started step: $($fixtureCase.Steps[0])"
                    $reportLines += "  finished step: $($fixtureCase.Steps[0]) [10 msec]"
                    $reportLines += "  started step: $($fixtureCase.Steps[1])"
                    $reportLines += "  abort step: $($fixtureCase.Steps[1])"
                    $reportLines += 'Test case aborted!'
                } else {
                    foreach ($step in $fixtureCase.Steps) {
                        $reportLines += "  started step: $step"
                        $reportLines += "  finished step: $step [10 msec]"
                    }
                }
            }

            $body += 'mkdir -p "$MUSE_TESTFLOW_DATA_PATH/reports"'
            $body += "cat > `"$reportFile`" <<'REPORT_EOF'"
            $body += ($reportLines -join "`n")
            $body += 'REPORT_EOF'
        }
    }

    # Every mode still exits 0: the defect is in the report, not in the exit status.
    $body += 'exit 0'
    return ($body -join "`n")
}

function New-TestflowProbeStubBranches {
    <#
        Builds the --test-case-gui branches that answer the runtime helper's source-semantics
        probes the way the fixed application does. $Broken answers every probe with success and
        no report, which the helper's probe checks must reject; $UnexpectedExit keeps the
        reports but replaces the expected exit 1 of a rejection with exit 3, standing in for a
        crash or an unexpected exit status that must not count as a correct rejection.
    #>
    param(
        [switch] $Broken,
        [switch] $UnexpectedExit
    )

    if ($Broken) {
        return (@(
            '      *empty.js)'
            '        exit 0'
            '        ;;'
            '      *aborted.js)'
            '        exit 0'
            '        ;;'
            '      *finished.js)'
            '        exit 0'
            '        ;;'
            '      *)'
            '        exit 1'
            '        ;;'
        ) -join "`n")
    }

    $branches = @'
      *empty.js)
        # The fixed application refuses a test case without steps.
        exit 1
        ;;
      *aborted.js)
        mkdir -p "$MUSE_TESTFLOW_DATA_PATH/reports" || exit 1
        cat > "$MUSE_TESTFLOW_DATA_PATH/reports/helper_probe_aborted_case_250101000000.txt" <<'PROBE_REPORT'
Test: helper probe: aborted case
date: 2026.01.01 00:00
steps: Abort the run

  started step: Abort the run
  abort step: Abort the run
Test case aborted!
PROBE_REPORT
        exit 1
        ;;
      *finished.js)
        # The report cannot be created when the data path is an existing file.
        mkdir -p "$MUSE_TESTFLOW_DATA_PATH/reports" || exit 1
        cat > "$MUSE_TESTFLOW_DATA_PATH/reports/helper_probe_trivially_finished_case_250101000000.txt" <<'PROBE_REPORT'
Test: helper probe: trivially finished case
date: 2026.01.01 00:00
steps: Trivial step

  started step: Trivial step
  finished step: Trivial step [10 msec]
PROBE_REPORT
        exit 0
        ;;
      *)
        exit 1
        ;;
'@

    if ($UnexpectedExit) {
        return $branches.Replace('exit 1', 'exit 3')
    }

    return $branches
}

function New-StubBody {
    <#
        POSIX stub standing in for the packaged application: it answers --version, writes a
        real PDF and a real one-entry ZIP for -o, and answers --test-case-gui with the report
        files and probe outcomes the fixed application produces. $ReportMode replaces the
        fixture test case reports with a defect the runtime helper must reject; a switch asks
        it to reproduce another failure mode.
    #>
    param(
        [ValidateSet('Valid', 'Missing', 'DirectoryOnly', 'Empty', 'Incomplete', 'Aborted')]
        [string] $ReportMode = 'Valid',
        [switch] $InvalidPdf,
        [switch] $BrokenProbes,
        [switch] $UnexpectedProbeExit,
        [switch] $StrandedOutput
    )

    $pdfWriter = if ($InvalidPdf) {
        'printf ''not a PDF document'' > "$2"'
    } else {
        'printf ''%%PDF-1.4
1 0 obj<</Type/Catalog>>endobj
trailer<<>>
%%EOF
'' > "$2"'
    }
    $zipWriter = 'python3 -c ''import sys, zipfile; archive = zipfile.ZipFile(sys.argv[1], "w"); archive.writestr("stub-score.mscx", "<museScore/>"); archive.close()'' "$2"'
    # Records the profile roots the helper handed to the child process, so the fixture can assert
    # the sandbox redirection without a Windows host.
    $envProbe = 'printf ''%s\n'' "$APPDATA" "$LOCALAPPDATA" > "$MUSE_TESTFLOW_DATA_PATH/child-profile-env.txt"'
    $stub = $script:StubTemplate.Replace('PDF_WRITER', $pdfWriter).Replace('ZIP_WRITER', $zipWriter)
    $stub = $stub.Replace('ENV_PROBE', $envProbe)
    # A descendant that inherits the redirected pipes keeps them open after the stub exits, which is
    # how a read to end of stream can wait indefinitely.
    $strayOutput = if ($StrandedOutput) { '    sleep 45 &' } else { '' }
    $stub = $stub.Replace('STRAY_OUTPUT', $strayOutput)
    $stub = $stub.Replace('PROBE_BRANCHES', (New-TestflowProbeStubBranches -Broken:$BrokenProbes -UnexpectedExit:$UnexpectedProbeExit))
    foreach ($scriptFileName in $script:FixtureTestCases.Keys) {
        $placeholder = ($scriptFileName -replace '_CommandPalette.*', '') + '_REPORT'
        $stub = $stub.Replace($placeholder, (New-TestflowStubReport -ScriptFileName $scriptFileName -ReportMode $ReportMode))
    }
    return $stub
}

function Get-PackageFile {
    param([Parameter(Mandatory = $true)][string] $ArtifactRoot)
    $zips = @(Get-ChildItem -LiteralPath $ArtifactRoot -File -Filter '*.zip')
    Assert-True ($zips.Count -eq 1) "expected exactly one zip in $ArtifactRoot, found $($zips.Count)"
    return $zips[0]
}

function New-FakePackage {
    <#
        Produces a valid package directory (zip + SHA256SUMS.txt + manifest) from a
        fresh synthetic install tree. Returns a hashtable with the paths.
    #>
    param(
        [Parameter(Mandatory = $true)][string] $Root,
        [switch] $IncludeFeatureTest
    )

    $source = Join-Path $Root 'source'
    $install = Join-Path $Root 'install'
    $artifact = Join-Path $Root 'artifact'
    New-Item -ItemType Directory -Path $artifact -Force | Out-Null

    $head = New-FakeSource -Root $source -IncludeFeatureTest:$IncludeFeatureTest
    $expectations = Get-ResourceExpectations
    New-FakeInstall -Root $install -Expectations $expectations -ExecutableRelativePath 'bin/MuseScoreStudio5.exe'

    # Installed testflowscripts must be byte-identical to the reviewed source
    # scripts at this SHA; the runtime helper verifies exactly that.
    $sourceScripts = Join-Path $source 'share/testflowscripts'
    $installedScripts = Join-Path $install 'testflowscripts'
    foreach ($script in @(Get-ChildItem -LiteralPath $sourceScripts -File)) {
        Copy-Item -LiteralPath $script.FullName -Destination (Join-Path $installedScripts $script.Name) -Force
    }

    New-FakeProvenance -Path (Join-Path $Root 'provenance.json') -SourceSha $head

    $result = Invoke-Helper -Script $PackageHelper -Arguments @(
        '-SourceDirectory', $source,
        '-InstallDirectory', $install,
        '-OutputDirectory', $artifact,
        '-ProvenancePath', (Join-Path $Root 'provenance.json')
    )
    Assert-True ($result.ExitCode -eq 0) "package helper failed ($($result.ExitCode)): $($result.Output)"

    return @{
        Source      = $source
        Install     = $install
        Artifact    = $artifact
        Head        = $head
        Package     = (Get-PackageFile -ArtifactRoot $artifact)
        Provenance  = (Join-Path $Root 'provenance.json')
    }
}

if (-not (Test-Path -LiteralPath $PackageHelper -PathType Leaf)) { throw "missing $PackageHelper" }
if (-not (Test-Path -LiteralPath $RuntimeHelper -PathType Leaf)) { throw "missing $RuntimeHelper" }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'git is required for these tests' }
if (-not (Get-Command python3 -ErrorAction SilentlyContinue)) { throw 'python3 is required to build the score-container stub export' }
if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) { throw 'pwsh is required for these tests' }

New-Item -ItemType Directory -Path $WorkRoot -Force | Out-Null
Write-Host "work root: $WorkRoot"

try {
    # ------------------------------------------------------------------
    # package-windows.ps1: structural failure cases
    # ------------------------------------------------------------------
    Invoke-Case 'package: metadata-only install tree is rejected' {
        $root = Join-Path $WorkRoot 'pkg-metadata-only'
        $source = Join-Path $root 'source'
        $install = Join-Path $root 'install'
        $artifact = Join-Path $root 'artifact'
        New-Item -ItemType Directory -Path $install, $artifact -Force | Out-Null
        $head = New-FakeSource -Root $source
        New-FakeProvenance -Path (Join-Path $root 'provenance.json') -SourceSha $head

        $result = Invoke-Helper -Script $PackageHelper -Arguments @(
            '-SourceDirectory', $source, '-InstallDirectory', $install,
            '-OutputDirectory', $artifact, '-ProvenancePath', (Join-Path $root 'provenance.json'))
        Assert-True ($result.ExitCode -ne 0) 'expected a nonzero exit for a metadata-only install tree'
        Assert-True ($result.Output -match 'missing the application executable') "unexpected error text: $($result.Output)"
    }

    Invoke-Case 'package: missing Qt QML/resource directory is rejected' {
        $root = Join-Path $WorkRoot 'pkg-missing-resource'
        $source = Join-Path $root 'source'
        $install = Join-Path $root 'install'
        $artifact = Join-Path $root 'artifact'
        New-Item -ItemType Directory -Path $artifact -Force | Out-Null
        $head = New-FakeSource -Root $source
        $expectations = Get-ResourceExpectations
        New-FakeInstall -Root $install -Expectations $expectations -ExecutableRelativePath 'bin/MuseScoreStudio5.exe'
        Remove-Item -LiteralPath (Join-Path $install 'qml') -Recurse -Force
        New-FakeProvenance -Path (Join-Path $root 'provenance.json') -SourceSha $head

        $result = Invoke-Helper -Script $PackageHelper -Arguments @(
            '-SourceDirectory', $source, '-InstallDirectory', $install,
            '-OutputDirectory', $artifact, '-ProvenancePath', (Join-Path $root 'provenance.json'))
        Assert-True ($result.ExitCode -ne 0) 'expected a nonzero exit when a Qt QML tree is missing'
        Assert-True ($result.Output -match "'qml'") "unexpected error text: $($result.Output)"
    }

    Invoke-Case 'package: missing license notice is rejected' {
        $root = Join-Path $WorkRoot 'pkg-missing-notice'
        $source = Join-Path $root 'source'
        $install = Join-Path $root 'install'
        $artifact = Join-Path $root 'artifact'
        New-Item -ItemType Directory -Path $artifact -Force | Out-Null
        $head = New-FakeSource -Root $source
        $expectations = Get-ResourceExpectations
        $notices = @($expectations | Where-Object { ([string] $_.kind) -eq 'file' -and ([string] $_.path) -like 'licenses/*' })
        Assert-True ($notices.Count -ge 1) 'Get-CoreResourceExpectation must require the license notice files'
        New-FakeInstall -Root $install -Expectations $expectations -ExecutableRelativePath 'bin/MuseScoreStudio5.exe'
        # The tree is otherwise complete, so the only reason this package can be rejected is the
        # notice that was removed.
        $removed = [string] $notices[0].path
        Remove-Item -LiteralPath (Join-Path $install ($removed -replace '/', [IO.Path]::DirectorySeparatorChar)) -Force
        New-FakeProvenance -Path (Join-Path $root 'provenance.json') -SourceSha $head

        $result = Invoke-Helper -Script $PackageHelper -Arguments @(
            '-SourceDirectory', $source, '-InstallDirectory', $install,
            '-OutputDirectory', $artifact, '-ProvenancePath', (Join-Path $root 'provenance.json'))
        Assert-True ($result.ExitCode -ne 0) 'expected a nonzero exit when a required license notice is missing'
        Assert-True ($result.Output -match [regex]::Escape($removed)) "unexpected error text: $($result.Output)"
        Assert-True (@(Get-ChildItem -LiteralPath $artifact -File -ErrorAction SilentlyContinue).Count -eq 0) `
            'a rejected package must not leave a package file behind'
    }

    Invoke-Case 'package: provenance missing an identity key is rejected' {
        $root = Join-Path $WorkRoot 'pkg-missing-provenance-key'
        $source = Join-Path $root 'source'
        $install = Join-Path $root 'install'
        $artifact = Join-Path $root 'artifact'
        New-Item -ItemType Directory -Path $artifact -Force | Out-Null
        $head = New-FakeSource -Root $source
        New-FakeInstall -Root $install -Expectations (Get-ResourceExpectations) -ExecutableRelativePath 'bin/MuseScoreStudio5.exe'
        New-FakeProvenance -Path (Join-Path $root 'provenance.json') -SourceSha $head -DropKeys @('workflow_sha', 'toolchain')

        $result = Invoke-Helper -Script $PackageHelper -Arguments @(
            '-SourceDirectory', $source, '-InstallDirectory', $install,
            '-OutputDirectory', $artifact, '-ProvenancePath', (Join-Path $root 'provenance.json'))
        Assert-True ($result.ExitCode -ne 0) 'expected a nonzero exit for missing provenance keys'
        Assert-True ($result.Output -match 'workflow_sha') "unexpected error text: $($result.Output)"
    }

    Invoke-Case 'package: source_sha that does not match the checkout is rejected' {
        $root = Join-Path $WorkRoot 'pkg-source-mismatch'
        $source = Join-Path $root 'source'
        $install = Join-Path $root 'install'
        $artifact = Join-Path $root 'artifact'
        New-Item -ItemType Directory -Path $artifact -Force | Out-Null
        $null = New-FakeSource -Root $source
        New-FakeInstall -Root $install -Expectations (Get-ResourceExpectations) -ExecutableRelativePath 'bin/MuseScoreStudio5.exe'
        New-FakeProvenance -Path (Join-Path $root 'provenance.json') -SourceSha ('c' * 40)

        $result = Invoke-Helper -Script $PackageHelper -Arguments @(
            '-SourceDirectory', $source, '-InstallDirectory', $install,
            '-OutputDirectory', $artifact, '-ProvenancePath', (Join-Path $root 'provenance.json'))
        Assert-True ($result.ExitCode -ne 0) 'expected a nonzero exit for a source_sha mismatch'
        # Observable outcome only: the wrapped console text breaks the message across lines, so
        # assert that nothing was packaged rather than pinning the exact phrasing.
        Assert-True (@(Get-ChildItem -LiteralPath $artifact -File -ErrorAction SilentlyContinue).Count -eq 0) `
            'a rejected package must not leave a package file behind'
    }

    Invoke-Case 'package: output directory inside the install tree is rejected' {
        $root = Join-Path $WorkRoot 'pkg-output-inside-install'
        $source = Join-Path $root 'source'
        $install = Join-Path $root 'install'
        $head = New-FakeSource -Root $source
        New-FakeInstall -Root $install -Expectations (Get-ResourceExpectations) -ExecutableRelativePath 'bin/MuseScoreStudio5.exe'
        New-FakeProvenance -Path (Join-Path $root 'provenance.json') -SourceSha $head

        $result = Invoke-Helper -Script $PackageHelper -Arguments @(
            '-SourceDirectory', $source, '-InstallDirectory', $install,
            '-OutputDirectory', (Join-Path $install 'out'), '-ProvenancePath', (Join-Path $root 'provenance.json'))
        Assert-True ($result.ExitCode -ne 0) 'expected a nonzero exit when the output dir is inside the install tree'
        Assert-True ($result.Output -match 'must not be inside -InstallDirectory') "unexpected error text: $($result.Output)"
    }

    # ------------------------------------------------------------------
    # package-windows.ps1: success path and artifact contract
    # ------------------------------------------------------------------
    Invoke-Case 'package: valid tree produces exactly the zip/SHA256SUMS/manifest trio' {
        $package = New-FakePackage -Root (Join-Path $WorkRoot 'pkg-ok')
        $artifact = $package.Artifact

        $files = @(Get-ChildItem -LiteralPath $artifact -File | Sort-Object Name)
        Assert-True ($files.Count -eq 3) "expected exactly 3 artifact files, found $($files.Count): $($files.Name -join ', ')"
        $expectedNames = @('SHA256SUMS.txt', 'build-manifest.json', $package.Package.Name) | Sort-Object
        Assert-True (($files.Name -join ',') -eq ($expectedNames -join ',')) `
            "unexpected artifact set: $($files.Name -join ', ')"
        Assert-True ($package.Package.Name -match '^tbui17-MuseScore-5\.0\.0\.12345678-x64-[0-9a-f]{12}-unsigned\.zip$') `
            "unexpected package name: $($package.Package.Name)"

        $sha = (Get-FileHash -LiteralPath $package.Package.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $sums = @(Get-Content -LiteralPath (Join-Path $artifact 'SHA256SUMS.txt') | Where-Object { $_.Trim().Length -gt 0 })
        Assert-True ($sums.Count -eq 1) 'SHA256SUMS.txt must have exactly one line'
        Assert-True ($sums[0] -eq "$sha  $($package.Package.Name)") "unexpected SHA256SUMS.txt content: $($sums[0])"

        $manifest = Get-Content -LiteralPath (Join-Path $artifact 'build-manifest.json') -Raw | ConvertFrom-Json
        Assert-True ($manifest.source_sha -eq $package.Head) 'manifest source_sha must equal the checkout HEAD'
        Assert-True ($manifest.repository -eq 'tbui17/MuseScore') 'manifest repository mismatch'
        Assert-True ($manifest.executable -eq 'bin/MuseScoreStudio5.exe') "unexpected executable: $($manifest.executable)"
        Assert-True ($manifest.package.filename -eq $package.Package.Name) 'manifest package filename mismatch'
        Assert-True ([int64]$manifest.package.size -eq [int64]$package.Package.Length) 'manifest package size mismatch'
        Assert-True ($manifest.package.sha256 -eq $sha) 'manifest package sha256 mismatch'
        Assert-True ([int] $manifest.package.size -gt 0) 'manifest package size must be positive'
        Assert-True (@($manifest.resource_expectations).Count -ge 20) 'manifest resource expectations look too small'
        Assert-True (@($manifest.resource_expectations) -contains 'bin/platforms/qwindows.dll') 'manifest must record the Qt platform plugin'
        Assert-True (@($manifest.resource_expectations) -contains 'testflowscripts/TC11_CommandPaletteDialog.js') 'manifest must record installed test scripts'
        Assert-True ($manifest.dependency_lock -like '*muse_framework@*') 'manifest must carry the dependency lock identity'

        # The license/notice set is part of the package contract, so assert it inside the
        # archive itself rather than only inside the install tree the fixture built from the
        # same contract. The expected paths come from the manifest, which the helper derives
        # from Get-CoreResourceExpectation, so the fixture cannot drift from the contract.
        $notices = @($manifest.resource_expectations | Where-Object { $_ -like 'licenses/*' })
        Assert-True ($notices.Count -ge 1) 'the packaging contract must require the license/notice set'
        $archive = [System.IO.Compression.ZipFile]::OpenRead($package.Package.FullName)
        try {
            $entries = @($archive.Entries | ForEach-Object { $_.FullName -replace '\\', '/' })
        } finally {
            $archive.Dispose()
        }
        $missingNotices = @($notices | Where-Object { $entries -notcontains $_ })
        Assert-True ($missingNotices.Count -eq 0) "the package must contain every required license notice, missing: $($missingNotices -join ', ')"
    }

    Invoke-Case 'package: archive creation failure leaves no package, manifest or checksum' {
        $root = Join-Path $WorkRoot 'pkg-archive-failure'
        $source = Join-Path $root 'source'
        $install = Join-Path $root 'install'
        $artifact = Join-Path $root 'artifact'
        New-Item -ItemType Directory -Path $artifact -Force | Out-Null
        $head = New-FakeSource -Root $source
        New-FakeInstall -Root $install -Expectations (Get-ResourceExpectations) -ExecutableRelativePath 'bin/MuseScoreStudio5.exe'
        # A nonessential installed file that the resource contract does not name, so structural
        # validation still passes and the archive step is the only stage that can fail.
        $blocked = Join-Path $install 'extras/optional-note.txt'
        New-Item -ItemType Directory -Path (Split-Path -Parent $blocked) -Force | Out-Null
        [IO.File]::WriteAllText($blocked, 'not part of the resource contract', [Text.UTF8Encoding]::new($false))
        New-FakeProvenance -Path (Join-Path $root 'provenance.json') -SourceSha $head

        # The file exists and is listed (validation reads metadata only), but the archive tool
        # cannot read its bytes while this handle holds it with no sharing.
        $handle = [IO.File]::Open($blocked, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
        try {
            $result = Invoke-Helper -Script $PackageHelper -Arguments @(
                '-SourceDirectory', $source, '-InstallDirectory', $install,
                '-OutputDirectory', $artifact, '-ProvenancePath', (Join-Path $root 'provenance.json'))
        } finally {
            $handle.Dispose()
        }
        Assert-True ($result.ExitCode -ne 0) 'expected a nonzero exit when the archive tool cannot read an installed file'
        Assert-True ($result.Output -match 'archive creation failed') "unexpected error text: $($result.Output)"
        $leftovers = @(Get-ChildItem -LiteralPath $artifact -File -ErrorAction SilentlyContinue)
        Assert-True ($leftovers.Count -eq 0) `
            "a failed archive must not leave a package, manifest or checksum behind, found: $(($leftovers | ForEach-Object { $_.Name }) -join ', ')"
    }

    Invoke-Case 'package: provenance application_version that only shares a string prefix is rejected' {
        $root = Join-Path $WorkRoot 'pkg-version-boundary'
        $source = Join-Path $root 'source'
        $install = Join-Path $root 'install'
        $artifact = Join-Path $root 'artifact'
        New-Item -ItemType Directory -Path $artifact -Force | Out-Null
        $head = New-FakeSource -Root $source
        New-FakeInstall -Root $install -Expectations (Get-ResourceExpectations) -ExecutableRelativePath 'bin/MuseScoreStudio5.exe'
        # version.cmake derives 5.0.0; a plain prefix match would also accept 5.0.01.
        New-FakeProvenance -Path (Join-Path $root 'provenance.json') -SourceSha $head -ApplicationVersion '5.0.01'

        $result = Invoke-Helper -Script $PackageHelper -Arguments @(
            '-SourceDirectory', $source, '-InstallDirectory', $install,
            '-OutputDirectory', $artifact, '-ProvenancePath', (Join-Path $root 'provenance.json'))
        Assert-True ($result.ExitCode -ne 0) 'expected a nonzero exit for a version that only shares a string prefix'
        Assert-True ($result.Output -match 'application_version') "unexpected error text: $($result.Output)"
        Assert-True (@(Get-ChildItem -LiteralPath $artifact -File -ErrorAction SilentlyContinue).Count -eq 0) `
            'a rejected package must not leave a package file behind'
    }

    Invoke-Case 'package: export of resource expectations is valid JSON' {
        $expectations = Get-ResourceExpectations
        Assert-True (@($expectations).Count -ge 20) 'expected at least 20 default expectations'
        $kinds = @($expectations | ForEach-Object { $_.kind } | Sort-Object -Unique)
        foreach ($kind in $kinds) {
            Assert-True (@('file', 'anyfile', 'dirhas') -contains $kind) "unexpected expectation kind '$kind'"
        }
    }

    # ------------------------------------------------------------------
    # test-windows-package.ps1: preflight failure cases (no execution needed)
    # ------------------------------------------------------------------
    Invoke-Case 'runtime: package checksum mismatch is rejected before extraction' {
        $package = New-FakePackage -Root (Join-Path $WorkRoot 'rt-checksum')
        $bytes = [IO.File]::ReadAllBytes($package.Package.FullName)
        $bytes[$bytes.Length - 1] = $bytes[$bytes.Length - 1] -bxor 0xFF
        [IO.File]::WriteAllBytes($package.Package.FullName, $bytes)

        $result = Invoke-Helper -Script $RuntimeHelper -Arguments @(
            '-ArtifactDirectory', $package.Artifact, '-SourceDirectory', $package.Source,
            '-OutputDirectory', (Join-Path $WorkRoot 'rt-checksum-out'))
        Assert-True ($result.ExitCode -ne 0) 'expected a nonzero exit for a checksum mismatch'
        Assert-True ($result.Output -match 'sha256 mismatch') "unexpected error text: $($result.Output)"
    }

    Invoke-Case 'runtime: workflow_sha is compared against MUSE_EXPECTED_WORKFLOW_SHA' {
        $package = New-FakePackage -Root (Join-Path $WorkRoot 'rt-workflow-sha')
        $result = Invoke-Helper -Script $RuntimeHelper -Arguments @(
            '-ArtifactDirectory', $package.Artifact, '-SourceDirectory', $package.Source,
            '-OutputDirectory', (Join-Path $WorkRoot 'rt-workflow-sha-out')) `
            -Environment @{ MUSE_EXPECTED_WORKFLOW_SHA = ('e' * 40) }
        Assert-True ($result.ExitCode -ne 0) 'expected a nonzero exit for a workflow_sha mismatch'
        Assert-True ($result.Output -match 'workflow_sha') "unexpected error text: $($result.Output)"
    }

    Invoke-Case 'runtime: framework_sha is compared against MUSE_EXPECTED_FRAMEWORK_SHA' {
        $package = New-FakePackage -Root (Join-Path $WorkRoot 'rt-framework-sha')
        $result = Invoke-Helper -Script $RuntimeHelper -Arguments @(
            '-ArtifactDirectory', $package.Artifact, '-SourceDirectory', $package.Source,
            '-OutputDirectory', (Join-Path $WorkRoot 'rt-framework-sha-out')) `
            -Environment @{ MUSE_EXPECTED_FRAMEWORK_SHA = ('f' * 40) }
        Assert-True ($result.ExitCode -ne 0) 'expected a nonzero exit for a framework_sha mismatch'
        Assert-True ($result.Output -match 'framework_sha') "unexpected error text: $($result.Output)"
    }

    Invoke-Case 'runtime: manifest resource expectation missing from the archive is reported' {
        $package = New-FakePackage -Root (Join-Path $WorkRoot 'rt-missing-resource')
        $manifestPath = Join-Path $package.Artifact 'build-manifest.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $expectations = @($manifest.resource_expectations) + 'qml/does-not-exist/qmldir'
        $manifest.resource_expectations = $expectations
        [IO.File]::WriteAllText($manifestPath, (ConvertTo-Json -InputObject $manifest -Depth 10), [Text.UTF8Encoding]::new($false))

        $result = Invoke-Helper -Script $RuntimeHelper -Arguments @(
            '-ArtifactDirectory', $package.Artifact, '-SourceDirectory', $package.Source,
            '-OutputDirectory', (Join-Path $WorkRoot 'rt-missing-resource-out'),
            '-VersionTimeoutSeconds', '10', '-ExportTimeoutSeconds', '10', '-GuiTimeoutSeconds', '10')
        Assert-True ($result.ExitCode -ne 0) 'expected a nonzero exit when a resource is missing from the package'
        Assert-True ($result.Output -match 'missing manifest resource') "unexpected error text: $($result.Output)"
    }

    Invoke-Case 'runtime: archive entry escaping the extraction root is rejected' {
        $package = New-FakePackage -Root (Join-Path $WorkRoot 'rt-zipslip')
        $packagePath = $package.Package.FullName
        $archive = [System.IO.Compression.ZipFile]::Open($packagePath, [System.IO.Compression.ZipArchiveMode]::Update)
        try {
            $entry = $archive.CreateEntry('../escaped.txt')
            $writer = [IO.StreamWriter]::new($entry.Open())
            $writer.Write('escape')
            $writer.Dispose()
        } finally {
            $archive.Dispose()
        }

        $newSize = (Get-Item -LiteralPath $packagePath).Length
        $newSha = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
        $manifestPath = Join-Path $package.Artifact 'build-manifest.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.package.size = $newSize
        $manifest.package.sha256 = $newSha
        [IO.File]::WriteAllText($manifestPath, (ConvertTo-Json -InputObject $manifest -Depth 10), [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $package.Artifact 'SHA256SUMS.txt'), "$newSha  $($package.Package.Name)`n", [Text.UTF8Encoding]::new($false))

        $result = Invoke-Helper -Script $RuntimeHelper -Arguments @(
            '-ArtifactDirectory', $package.Artifact, '-SourceDirectory', $package.Source,
            '-OutputDirectory', (Join-Path $WorkRoot 'rt-zipslip-out'))
        Assert-True ($result.ExitCode -ne 0) 'expected a nonzero exit for an escaping archive entry'
        Assert-True ($result.Output -match 'escapes the extraction root') "unexpected error text: $($result.Output)"
    }

    # ------------------------------------------------------------------
    # test-windows-package.ps1: first-run profile contract
    # ------------------------------------------------------------------
    # The package opens the profile derived from its own version metadata inside the Windows known
    # folders, so these cases pin the path contract, the refusal to reuse an existing profile, and
    # the hosted-runner guard. They run on any host: the hook takes the known-folder roots as
    # arguments instead of using the host's own folders (the fixture hosts' real profile is never
    # touched). Whether the packaged binary actually reads the seeded INI remains hosted-runner
    # evidence.
    $hostedRunnerEnvironment = @{ GITHUB_ACTIONS = 'true'; RUNNER_ENVIRONMENT = 'github-hosted' }

    Invoke-Case 'profile: plan resolves the development profile in the profile sandbox' {
        $root = Join-Path $WorkRoot 'profile-plan'
        $roaming = Join-Path $root 'profile/AppData/Roaming'
        $local = Join-Path $root 'profile/AppData/Local'
        New-Item -ItemType Directory -Path $roaming, $local -Force | Out-Null
        $source = Join-Path $root 'source'
        $null = New-FakeSource -Root $source

        $result = Invoke-ProfilePlan -Environment $hostedRunnerEnvironment -Arguments @(
            '-ExportProfilePlan', '-SourceDirectory', $source, '-OutputDirectory', $root)
        Assert-True ($result.ExitCode -eq 0) "profile plan must resolve, got exit $($result.ExitCode): $($result.Text)"
        Assert-True ($null -ne $result.Plan) "profile plan must be JSON: $($result.Text)"
        Assert-True ($result.Plan.profile_name -eq 'MuseScoreStudio5Development') "unexpected profile name: $($result.Plan.profile_name)"
        Assert-True ($result.Plan.settings_file -eq (Join-Path $roaming 'MuseScore/MuseScoreStudio5Development.ini')) "unexpected settings file: $($result.Plan.settings_file)"
        Assert-True ($result.Plan.profile_directory -eq (Join-Path $local 'MuseScore/MuseScoreStudio5Development')) "unexpected profile directory: $($result.Plan.profile_directory)"
        Assert-True ($result.Plan.log_directory -eq (Join-Path $local 'MuseScore/MuseScoreStudio5Development/logs')) "unexpected log directory: $($result.Plan.log_directory)"
    }

    Invoke-Case 'runtime: timeout dump plan keeps spaced work root out of comsvcs path' {
        $spacedRoot = Join-Path $WorkRoot 'spaced Work Root'
        $runnerTemp = Join-Path $WorkRoot 'runner-temp'
        New-Item -ItemType Directory -Path $spacedRoot, $runnerTemp -Force | Out-Null
        $result = Invoke-ProfilePlan -Environment @{ RUNNER_TEMP = $runnerTemp } -Arguments @(
            '-ExportTimeoutDumpPlan', '-OutputDirectory', $spacedRoot)
        Assert-True ($result.ExitCode -eq 0) "timeout dump plan must resolve, got exit $($result.ExitCode): $($result.Text)"
        Assert-True ($null -ne $result.Plan) "timeout dump plan must be JSON: $($result.Text)"
        Assert-True ($result.Plan.working_directory -eq $spacedRoot) 'the plan must preserve the spaced work root for diagnostics'
        Assert-True ($result.Plan.temp_dump_path -like "$runnerTemp*") `
            "the comsvcs dump must be created under RUNNER_TEMP: $($result.Plan.temp_dump_path)"
        Assert-True ($result.Plan.temp_dump_path -notmatch ' ') `
            "the comsvcs dump path must not contain spaces: $($result.Plan.temp_dump_path)"
        $fullArguments = @($result.Plan.full_arguments)
        Assert-True ($fullArguments.Count -eq 4) 'full comsvcs invocation must have exactly four arguments'
        Assert-True ($fullArguments[0] -eq 'C:\Windows\System32\comsvcs.dll,MiniDump') `
            "unexpected comsvcs DLL export argument: $($fullArguments[0])"
        Assert-True ($fullArguments[1] -eq '1234') 'comsvcs invocation must target the requested process'
        Assert-True ($fullArguments[2] -eq $result.Plan.temp_dump_path) 'comsvcs must receive the space-free temporary dump path'
        Assert-True ($fullArguments[3] -eq 'full') 'the first comsvcs attempt must request a full dump'
        $smallArguments = @($result.Plan.small_arguments)
        Assert-True ($smallArguments[3] -eq '0x1000') `
            'the fallback comsvcs invocation must request MiniDumpNormal plus MiniDumpWithThreadInfo'
    }

    Invoke-Case 'profile: an existing development profile is refused, never overwritten' {
        $root = Join-Path $WorkRoot 'profile-existing'
        $roaming = Join-Path $root 'profile/AppData/Roaming'
        $local = Join-Path $root 'profile/AppData/Local'
        New-Item -ItemType Directory -Path (Join-Path $roaming 'MuseScore'), $local -Force | Out-Null
        $source = Join-Path $root 'source'
        $null = New-FakeSource -Root $source

        $existingIni = Join-Path $roaming 'MuseScore/MuseScoreStudio5Development.ini'
        $existingContent = "[application]`r`nhasCompletedFirstLaunchSetup=false`r`n"
        [IO.File]::WriteAllText($existingIni, $existingContent, [Text.UTF8Encoding]::new($false))
        $result = Invoke-ProfilePlan -Environment $hostedRunnerEnvironment -Arguments @(
            '-ExportProfilePlan', '-SourceDirectory', $source, '-OutputDirectory', $root)
        Assert-True ($result.ExitCode -ne 0) 'a profile that already exists must fail the run'
        Assert-True ($result.Flattened -match 'refusing to overwrite an existing development profile') "unexpected error text: $($result.Flattened)"
        Assert-True ([IO.File]::ReadAllText($existingIni) -eq $existingContent) 'the existing settings file must not be modified'

        # The application-local profile directory counts as an existing profile too.
        Remove-Item -LiteralPath $existingIni -Force
        New-Item -ItemType Directory -Path (Join-Path $local 'MuseScore/MuseScoreStudio5Development') -Force | Out-Null
        $result = Invoke-ProfilePlan -Environment $hostedRunnerEnvironment -Arguments @(
            '-ExportProfilePlan', '-SourceDirectory', $source, '-OutputDirectory', $root)
        Assert-True ($result.ExitCode -ne 0) 'an existing application-local profile directory must fail the run'
        Assert-True ($result.Flattened -match 'refusing to overwrite an existing development profile') "unexpected error text: $($result.Flattened)"
    }

    Invoke-Case 'profile: preparing a real profile requires a GitHub-hosted runner' {
        $root = Join-Path $WorkRoot 'profile-guard'
        New-Item -ItemType Directory -Path (Join-Path $root 'profile/AppData/Roaming'), (Join-Path $root 'profile/AppData/Local') -Force | Out-Null
        $source = Join-Path $root 'source'
        $null = New-FakeSource -Root $source

        foreach ($environment in @(
                @{ GITHUB_ACTIONS = $null; RUNNER_ENVIRONMENT = 'github-hosted'; Expect = 'outside GitHub Actions' }
                @{ GITHUB_ACTIONS = 'true'; RUNNER_ENVIRONMENT = 'self-hosted'; Expect = 'outside a GitHub-hosted runner' })) {
            $result = Invoke-ProfilePlan -Environment $environment -Arguments @(
                '-ExportProfilePlan', '-SourceDirectory', $source, '-OutputDirectory', $root)
            Assert-True ($result.ExitCode -ne 0) "expected a refusal for $($environment.Expect): $($result.Flattened)"
            Assert-True ($result.Flattened -match $environment.Expect) "unexpected error text: $($result.Flattened)"
        }
    }

    Invoke-Case 'profile: a checkout without the development channel is refused' {
        $root = Join-Path $WorkRoot 'profile-channel'
        New-Item -ItemType Directory -Path (Join-Path $root 'profile/AppData/Roaming'), (Join-Path $root 'profile/AppData/Local') -Force | Out-Null
        $source = Join-Path $root 'source'
        $null = New-FakeSource -Root $source
        $versionPath = Join-Path $source 'version.cmake'
        [IO.File]::WriteAllText($versionPath, ([IO.File]::ReadAllText($versionPath) -replace 'MUSE_APP_UNSTABLE ON', 'MUSE_APP_UNSTABLE OFF'), [Text.UTF8Encoding]::new($false))

        $result = Invoke-ProfilePlan -Environment $hostedRunnerEnvironment -Arguments @(
            '-ExportProfilePlan', '-SourceDirectory', $source, '-OutputDirectory', $root)
        Assert-True ($result.ExitCode -ne 0) 'a non-development checkout must not seed a profile'
        Assert-True ($result.Flattened -match 'MUSE_APP_UNSTABLE') "unexpected error text: $($result.Flattened)"
    }

    # ------------------------------------------------------------------
    # test-windows-package.ps1: execution cases (POSIX stub executable)
    # ------------------------------------------------------------------
    $executionSkipReason = 'the packaged executable stub requires a POSIX host; the real exe is exercised on the hosted Windows runner'

    if ($script:IsWindowsHost) {
        Skip-Case 'runtime: missing installed test script fails the run' $executionSkipReason
        Skip-Case 'runtime: --version with no output is not a pass' $executionSkipReason
        Skip-Case 'runtime: nonzero exit fails the run' $executionSkipReason
        Skip-Case 'runtime: hang is killed and reported as a timeout' $executionSkipReason
        Skip-Case 'runtime: stub application passes version/export/GUI checks' $executionSkipReason
        Skip-Case 'runtime: first-run profile is seeded in the sandbox and handed to the child' $executionSkipReason
        Skip-Case 'runtime: output that never reaches end of stream fails instead of hanging' $executionSkipReason
        Skip-Case "runtime: GUI run with a 'Missing' testflow report fails" $executionSkipReason
        Skip-Case "runtime: GUI run with a 'DirectoryOnly' testflow report fails" $executionSkipReason
        Skip-Case "runtime: GUI run with a 'Empty' testflow report fails" $executionSkipReason
        Skip-Case "runtime: GUI run with a 'Incomplete' testflow report fails" $executionSkipReason
        Skip-Case "runtime: GUI run with a 'Aborted' testflow report fails" $executionSkipReason
        Skip-Case 'runtime: probes that report success without evidence fail the run' $executionSkipReason
        Skip-Case 'runtime: probe with an unexpected exit status is not a correct rejection' $executionSkipReason
    } else {
        Invoke-Case 'runtime: missing installed test script fails the run' {
            $package = New-FakePackage -Root (Join-Path $WorkRoot 'rt-missing-test')
            $packagePath = $package.Package.FullName
            $archive = [System.IO.Compression.ZipFile]::Open($packagePath, [System.IO.Compression.ZipArchiveMode]::Update)
            try {
                foreach ($entry in @($archive.Entries | Where-Object { $_.FullName -like 'testflowscripts/*' })) {
                    $entry.Delete()
                }
            } finally {
                $archive.Dispose()
            }
            $newSize = (Get-Item -LiteralPath $packagePath).Length
            $newSha = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
            $manifestPath = Join-Path $package.Artifact 'build-manifest.json'
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $manifest.package.size = $newSize
            $manifest.package.sha256 = $newSha
            $manifest.resource_expectations = @($manifest.resource_expectations | Where-Object { $_ -notlike 'testflowscripts/*' })
            [IO.File]::WriteAllText($manifestPath, (ConvertTo-Json -InputObject $manifest -Depth 10), [Text.UTF8Encoding]::new($false))
            [IO.File]::WriteAllText((Join-Path $package.Artifact 'SHA256SUMS.txt'), "$newSha  $($package.Package.Name)`n", [Text.UTF8Encoding]::new($false))

            $result = Invoke-Helper -Script $RuntimeHelper -Arguments @(
                '-ArtifactDirectory', $package.Artifact, '-SourceDirectory', $package.Source,
                '-OutputDirectory', (Join-Path $WorkRoot 'rt-missing-test-out'),
                '-VersionTimeoutSeconds', '10', '-ExportTimeoutSeconds', '10', '-GuiTimeoutSeconds', '10')
            Assert-True ($result.ExitCode -ne 0) 'expected a nonzero exit for a missing installed test script'
            Assert-True ($result.Output -match 'does not contain the installed test script') "unexpected error text: $($result.Output)"
        }

        Invoke-Case 'runtime: source-present TC15 missing installed script fails' {
            $package = New-FakePackage -Root (Join-Path $WorkRoot 'rt-missing-feature-test') -IncludeFeatureTest
            $stub = Join-Path $package.Install 'bin/MuseScoreStudio5.exe'
            [IO.File]::WriteAllText($stub, (New-StubBody) + "`n", [Text.UTF8Encoding]::new($false))
            & chmod +x $stub
            & pwsh -NoProfile -NonInteractive -File $PackageHelper -SourceDirectory $package.Source `
                -InstallDirectory $package.Install -OutputDirectory $package.Artifact -ProvenancePath $package.Provenance | Out-Null
            Assert-True ($LASTEXITCODE -eq 0) 're-packaging the feature fixture with the passing stub failed'

            $packagePath = $package.Package.FullName
            $missingPath = "testflowscripts/$($script:FeatureFixtureName)"
            $archive = [System.IO.Compression.ZipFile]::Open($packagePath, [System.IO.Compression.ZipArchiveMode]::Update)
            try {
                $entries = @($archive.Entries | Where-Object { $_.FullName -eq $missingPath })
                Assert-True ($entries.Count -eq 1) "feature fixture package must contain exactly one '$missingPath' entry"
                $entries[0].Delete()
            } finally {
                $archive.Dispose()
            }
            $newSize = (Get-Item -LiteralPath $packagePath).Length
            $newSha = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
            $manifestPath = Join-Path $package.Artifact 'build-manifest.json'
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $manifest.package.size = $newSize
            $manifest.package.sha256 = $newSha
            $manifest.resource_expectations = @($manifest.resource_expectations | Where-Object { $_ -ne $missingPath })
            [IO.File]::WriteAllText($manifestPath, (ConvertTo-Json -InputObject $manifest -Depth 10), [Text.UTF8Encoding]::new($false))
            [IO.File]::WriteAllText((Join-Path $package.Artifact 'SHA256SUMS.txt'), "$newSha  $($package.Package.Name)`n", [Text.UTF8Encoding]::new($false))

            $result = Invoke-Helper -Script $RuntimeHelper -Arguments @(
                '-ArtifactDirectory', $package.Artifact, '-SourceDirectory', $package.Source,
                '-OutputDirectory', (Join-Path $WorkRoot 'rt-missing-feature-test-out'),
                '-VersionTimeoutSeconds', '10', '-ExportTimeoutSeconds', '10', '-GuiTimeoutSeconds', '10')
            Assert-True ($result.ExitCode -ne 0) 'expected a nonzero exit when the selected TC15 script is absent from the package'
            $reportPath = Join-Path $WorkRoot 'rt-missing-feature-test-out/logs/runtime-tests.json'
            Assert-True (Test-Path -LiteralPath $reportPath) 'runtime helper must retain the report when the selected feature script is absent'
            $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
            $guiResults = @($report | Where-Object { $_.name -like 'TC*.js' })
            Assert-True ($guiResults.Count -eq 2) "TC11/TC14 should be the only recorded GUI results before TC15 is rejected, found: $($guiResults.name -join ', ')"
            foreach ($guiResult in $guiResults) {
                Assert-True ([bool] $guiResult.ok -and [int] $guiResult.exit_code -eq 0) `
                    "$($guiResult.name) must pass before the missing TC15 fixture is rejected"
            }
        }

        Invoke-Case 'runtime: --version with no output is not a pass' {
            $package = New-FakePackage -Root (Join-Path $WorkRoot 'rt-version-silent')
            $stub = Join-Path $package.Install 'bin/MuseScoreStudio5.exe'
            [IO.File]::WriteAllText($stub, "#!/bin/sh`nexit 0`n", [Text.UTF8Encoding]::new($false))
            & chmod +x $stub
            # Re-package so the artifact carries the silent stub.
            & pwsh -NoProfile -NonInteractive -File $PackageHelper -SourceDirectory $package.Source `
                -InstallDirectory $package.Install -OutputDirectory $package.Artifact -ProvenancePath $package.Provenance | Out-Null
            Assert-True ($LASTEXITCODE -eq 0) 're-packaging with the silent stub failed'

            $result = Invoke-Helper -Script $RuntimeHelper -Arguments @(
                '-ArtifactDirectory', $package.Artifact, '-SourceDirectory', $package.Source,
                '-OutputDirectory', (Join-Path $WorkRoot 'rt-version-silent-out'),
                '-VersionTimeoutSeconds', '10', '-ExportTimeoutSeconds', '10', '-GuiTimeoutSeconds', '10')
            Assert-True ($result.ExitCode -ne 0) 'expected a nonzero exit when --version prints nothing'
            Assert-True ($result.Output -match 'no recognisable version banner') "unexpected error text: $($result.Output)"
        }

        Invoke-Case 'runtime: nonzero exit fails the run' {
            $package = New-FakePackage -Root (Join-Path $WorkRoot 'rt-exit-one')
            $stub = Join-Path $package.Install 'bin/MuseScoreStudio5.exe'
            [IO.File]::WriteAllText($stub, "#!/bin/sh`nexit 3`n", [Text.UTF8Encoding]::new($false))
            & chmod +x $stub
            & pwsh -NoProfile -NonInteractive -File $PackageHelper -SourceDirectory $package.Source `
                -InstallDirectory $package.Install -OutputDirectory $package.Artifact -ProvenancePath $package.Provenance | Out-Null
            Assert-True ($LASTEXITCODE -eq 0) 're-packaging with the failing stub failed'

            $result = Invoke-Helper -Script $RuntimeHelper -Arguments @(
                '-ArtifactDirectory', $package.Artifact, '-SourceDirectory', $package.Source,
                '-OutputDirectory', (Join-Path $WorkRoot 'rt-exit-one-out'),
                '-VersionTimeoutSeconds', '10', '-ExportTimeoutSeconds', '10', '-GuiTimeoutSeconds', '10')
            Assert-True ($result.ExitCode -ne 0) 'expected a nonzero exit when the application exits nonzero'
            Assert-True ($result.Output -match 'exited with 3') "unexpected error text: $($result.Output)"
        }

        Invoke-Case 'runtime: hang is killed and reported as a timeout' {
            $package = New-FakePackage -Root (Join-Path $WorkRoot 'rt-hang')
            $stub = Join-Path $package.Install 'bin/MuseScoreStudio5.exe'
            [IO.File]::WriteAllText($stub, "#!/bin/sh`nsleep 600`n", [Text.UTF8Encoding]::new($false))
            & chmod +x $stub
            & pwsh -NoProfile -NonInteractive -File $PackageHelper -SourceDirectory $package.Source `
                -InstallDirectory $package.Install -OutputDirectory $package.Artifact -ProvenancePath $package.Provenance | Out-Null
            Assert-True ($LASTEXITCODE -eq 0) 're-packaging with the hanging stub failed'

            $stopwatch = [Diagnostics.Stopwatch]::StartNew()
            $result = Invoke-Helper -Script $RuntimeHelper -Arguments @(
                '-ArtifactDirectory', $package.Artifact, '-SourceDirectory', $package.Source,
                '-OutputDirectory', (Join-Path $WorkRoot 'rt-hang-out'),
                '-VersionTimeoutSeconds', '3', '-ExportTimeoutSeconds', '3', '-GuiTimeoutSeconds', '3')
            $stopwatch.Stop()
            Assert-True ($result.ExitCode -ne 0) 'expected a nonzero exit for a hanging application'
            Assert-True ($result.Output -match 'timed out') "unexpected error text: $($result.Output)"
            Assert-True ($stopwatch.Elapsed.TotalSeconds -lt 60) "timeout handling took too long: $($stopwatch.Elapsed.TotalSeconds)s"
            $runtimeReportPath = Join-Path $WorkRoot 'rt-hang-out/logs/runtime-tests.json'
            Assert-True (Test-Path -LiteralPath $runtimeReportPath -PathType Leaf) `
                'a timed-out GUI run must retain its runtime result record'
            $runtimeReport = Get-Content -LiteralPath $runtimeReportPath -Raw | ConvertFrom-Json
            $timedOutRecord = @($runtimeReport | Where-Object { $_.name -eq 'TC11_CommandPaletteDialog.js' })[0]
            Assert-True ($null -ne $timedOutRecord) 'the timed-out GUI case must be recorded'
            Assert-True ($timedOutRecord.timed_out -eq $true -and $timedOutRecord.ok -eq $false -and $null -eq $timedOutRecord.exit_code) `
                'the original timeout must remain authoritative even when diagnostics are collected'
            $diagnosticRoot = Join-Path (Join-Path $WorkRoot 'rt-hang-out/logs/diagnostics') 'gui-TC11_CommandPaletteDialog'
            foreach ($requiredDiagnostic in @(
                    'stdout.log'
                    'stderr.log'
                    'profile-settings.ini'
                    'reports.missing.txt'
                    'process/process-before-termination.json'
                    'process/process-after-termination.json'
                    'manifest.json')) {
                Assert-True (Test-Path -LiteralPath (Join-Path $diagnosticRoot $requiredDiagnostic) -PathType Leaf) `
                    "timed-out GUI diagnostics must retain '$requiredDiagnostic' under $diagnosticRoot"
            }
            $diagnosticManifest = Get-Content -LiteralPath (Join-Path $diagnosticRoot 'manifest.json') -Raw | ConvertFrom-Json
            Assert-True ($diagnosticManifest.timed_out -eq $true) 'timeout diagnostics must identify the timed-out process'
            Assert-True (-not (Test-Path -LiteralPath (Join-Path $diagnosticRoot 'profile-local'))) `
                'diagnostics must not copy the whole profile tree'
            Assert-True ($diagnosticManifest.collection_timed_out -eq $false) `
                'bounded diagnostic collection must finish within its own deadline'
            Assert-True ($diagnosticManifest.collection_elapsed_sec -ge 0 -and $diagnosticManifest.collection_elapsed_sec -lt 30) `
                'bounded timeout diagnostics must finish within their collection deadline'
            Assert-True (-not (Test-Path -LiteralPath (Join-Path $diagnosticRoot 'timeout-stacks'))) `
                'POSIX fixtures must not run Windows-only debugger/minidump capture'
        }

        Invoke-Case 'runtime: stub application passes version/export/GUI checks' {
            $package = New-FakePackage -Root (Join-Path $WorkRoot 'rt-ok')
            $stub = Join-Path $package.Install 'bin/MuseScoreStudio5.exe'
            [IO.File]::WriteAllText($stub, (New-StubBody) + "`n", [Text.UTF8Encoding]::new($false))
            & chmod +x $stub
            & pwsh -NoProfile -NonInteractive -File $PackageHelper -SourceDirectory $package.Source `
                -InstallDirectory $package.Install -OutputDirectory $package.Artifact -ProvenancePath $package.Provenance | Out-Null
            Assert-True ($LASTEXITCODE -eq 0) 're-packaging with the passing stub failed'

            $result = Invoke-Helper -Script $RuntimeHelper -Arguments @(
                '-ArtifactDirectory', $package.Artifact, '-SourceDirectory', $package.Source,
                '-OutputDirectory', (Join-Path $WorkRoot 'rt-ok-out'),
                '-VersionTimeoutSeconds', '15', '-ExportTimeoutSeconds', '15', '-GuiTimeoutSeconds', '30')
            Assert-True ($result.ExitCode -eq 0) "expected the stub package to pass, got $($result.ExitCode): $($result.Output)"
            $reportPath = Join-Path $WorkRoot 'rt-ok-out/logs/runtime-tests.json'
            Assert-True (Test-Path -LiteralPath $reportPath) 'runtime helper must write logs/runtime-tests.json'
            $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
            $names = @($report | ForEach-Object { $_.name })
            Assert-True ($names -contains 'version') 'report must include the version check'
            Assert-True ($names -contains 'export-pdf') 'report must include the rendered PDF export'
            Assert-True ($names -contains 'export-mscz') 'report must include the score container export'
            Assert-True ($names -contains 'TC11_CommandPaletteDialog.js') 'report must include TC11'
            Assert-True ($names -contains 'TC14_CommandPaletteAnnounce.js') 'report must include TC14'
            $guiNames = @($names | Where-Object { $_ -like 'TC*.js' })
            Assert-True ($guiNames.Count -eq 2) "base source fixture must select exactly TC11/TC14, found: $($guiNames -join ', ')"
            Assert-True ($guiNames -notcontains $script:FeatureFixtureName) 'base source fixture must not select TC15'
            Assert-True (Test-Path -LiteralPath (Join-Path $WorkRoot 'rt-ok-out/logs/export-pdf.stdout.log')) 'PDF export output must be retained for diagnosis'
            Assert-True (-not (Test-Path -LiteralPath (Join-Path $WorkRoot 'rt-ok-out/logs/diagnostics'))) `
                'timeout diagnostics must be timeout-only and absent after a successful run'
        }

        Invoke-Case 'runtime: output that never reaches end of stream fails instead of hanging' {
            $package = New-FakePackage -Root (Join-Path $WorkRoot 'rt-stranded-output')
            $stub = Join-Path $package.Install 'bin/MuseScoreStudio5.exe'
            [IO.File]::WriteAllText($stub, (New-StubBody -StrandedOutput) + "`n", [Text.UTF8Encoding]::new($false))
            & chmod +x $stub
            & pwsh -NoProfile -NonInteractive -File $PackageHelper -SourceDirectory $package.Source `
                -InstallDirectory $package.Install -OutputDirectory $package.Artifact -ProvenancePath $package.Provenance | Out-Null
            Assert-True ($LASTEXITCODE -eq 0) 're-packaging with the stranded-output stub failed'

            # The version child exits 0 but leaves a descendant holding the inherited pipes open, so
            # the redirected streams never reach end of stream. The helper must stop reading at its
            # drain deadline and fail the run instead of waiting for that descendant to exit.
            $stopwatch = [Diagnostics.Stopwatch]::StartNew()
            $result = Invoke-Helper -Script $RuntimeHelper -Arguments @(
                '-ArtifactDirectory', $package.Artifact, '-SourceDirectory', $package.Source,
                '-OutputDirectory', (Join-Path $WorkRoot 'rt-stranded-output-out'),
                '-VersionTimeoutSeconds', '15', '-ExportTimeoutSeconds', '15', '-GuiTimeoutSeconds', '30')
            $stopwatch.Stop()
            Assert-True ($result.ExitCode -ne 0) 'expected a nonzero exit when a stream never reaches end of stream'
            Assert-True ($result.Output -match 'did not reach end of stream') "unexpected error text: $($result.Output)"
            Assert-True ($stopwatch.Elapsed.TotalSeconds -lt 40) "the run waited on the open pipe: $($stopwatch.Elapsed.TotalSeconds)s"
        }

        Invoke-Case 'runtime: first-run profile is seeded in the sandbox and handed to the child' {
            $package = New-FakePackage -Root (Join-Path $WorkRoot 'rt-profile')
            $stub = Join-Path $package.Install 'bin/MuseScoreStudio5.exe'
            [IO.File]::WriteAllText($stub, (New-StubBody) + "`n", [Text.UTF8Encoding]::new($false))
            & chmod +x $stub
            & pwsh -NoProfile -NonInteractive -File $PackageHelper -SourceDirectory $package.Source `
                -InstallDirectory $package.Install -OutputDirectory $package.Artifact -ProvenancePath $package.Provenance | Out-Null
            Assert-True ($LASTEXITCODE -eq 0) 're-packaging with the passing stub failed'

            $out = Join-Path $WorkRoot 'rt-profile-out'
            $result = Invoke-Helper -Script $RuntimeHelper -Arguments @(
                '-ArtifactDirectory', $package.Artifact, '-SourceDirectory', $package.Source,
                '-OutputDirectory', $out,
                '-VersionTimeoutSeconds', '15', '-ExportTimeoutSeconds', '15', '-GuiTimeoutSeconds', '30')
            Assert-True ($result.ExitCode -eq 0) "expected the stub package to pass, got $($result.ExitCode): $($result.Output)"

            # Exactly the development profile, seeded before the first process starts. Group and key
            # names mirror src/appshell/internal/appshellconfiguration.cpp; the version is the source
            # MUSE_APP_VERSION, which muse::Version compares equal to application version + build.
            $settingsRoot = Join-Path $out 'profile/AppData/Roaming/MuseScore'
            $iniPath = Join-Path $settingsRoot 'MuseScoreStudio5Development.ini'
            Assert-True (Test-Path -LiteralPath $iniPath -PathType Leaf) "the helper must seed the development profile INI: $iniPath"
            Assert-True (-not (Test-Path -LiteralPath (Join-Path $settingsRoot 'MuseScoreStudio5.ini'))) 'the helper must not seed an official/stable profile alias'
            $iniLines = @([IO.File]::ReadAllText($iniPath) -split "`r`n")
            foreach ($expectedLine in @(
                    '[application]',
                    'hasCompletedFirstLaunchSetup=true',
                    'welcomeDialogShowOnStartup=false',
                    'welcomeDialogLastShownVersion=5.0.0',
                    '[musesounds]',
                    'checkForUpdate=false')) {
                Assert-True ($iniLines -contains $expectedLine) "the seeded INI must contain '$expectedLine': $($iniLines -join ' | ')"
            }
            Assert-True ($iniLines -notcontains 'checkForUpdateTestMode=true') 'the acceptance profile must never enable MuseSounds update test mode'

            # The fixture host hands the sandbox roots to the stub; the real Windows run does not
            # redirect the environment at all (the profile there comes from the known folders).
            $envProbe = Join-Path $out 'testflow-data/child-profile-env.txt'
            Assert-True (Test-Path -LiteralPath $envProbe -PathType Leaf) 'the child process must record the profile roots it was given'
            $envLines = @([IO.File]::ReadAllLines($envProbe))
            Assert-True ($envLines[0] -eq (Join-Path $out 'profile/AppData/Roaming')) "unexpected APPDATA for the child: $($envLines[0])"
            Assert-True ($envLines[1] -eq (Join-Path $out 'profile/AppData/Local')) "unexpected LOCALAPPDATA for the child: $($envLines[1])"
        }

        Invoke-Case 'runtime: export that is not a PDF document fails the run' {
            $package = New-FakePackage -Root (Join-Path $WorkRoot 'rt-invalid-pdf')
            $stub = Join-Path $package.Install 'bin/MuseScoreStudio5.exe'
            [IO.File]::WriteAllText($stub, (New-StubBody -InvalidPdf) + "`n", [Text.UTF8Encoding]::new($false))
            & chmod +x $stub
            & pwsh -NoProfile -NonInteractive -File $PackageHelper -SourceDirectory $package.Source `
                -InstallDirectory $package.Install -OutputDirectory $package.Artifact -ProvenancePath $package.Provenance | Out-Null
            Assert-True ($LASTEXITCODE -eq 0) 're-packaging with the invalid-PDF stub failed'

            $result = Invoke-Helper -Script $RuntimeHelper -Arguments @(
                '-ArtifactDirectory', $package.Artifact, '-SourceDirectory', $package.Source,
                '-OutputDirectory', (Join-Path $WorkRoot 'rt-invalid-pdf-out'),
                '-VersionTimeoutSeconds', '15', '-ExportTimeoutSeconds', '15', '-GuiTimeoutSeconds', '30')
            Assert-True ($result.ExitCode -ne 0) 'expected a nonzero exit when the export is not a PDF document'
            Assert-True ($result.Output -match 'is not a PDF document') "unexpected error text: $($result.Output)"
        }

        # A zero exit status is only acceptable together with a report that proves the reviewed
        # test case ran; each mode reproduces one report defect the helper must reject.
        $reportNegatives = @(
            @{ Root = 'rt-report-missing'; Mode = 'Missing'; Expect = 'recorded 0 testflow report file' }
            @{ Root = 'rt-report-directory-only'; Mode = 'DirectoryOnly'; Expect = 'recorded 0 testflow report file' }
            @{ Root = 'rt-report-empty'; Mode = 'Empty'; Expect = 'declares no steps' }
            @{ Root = 'rt-report-incomplete'; Mode = 'Incomplete'; Expect = 'records 1 finished steps' }
            @{ Root = 'rt-report-aborted'; Mode = 'Aborted'; Expect = 'records an unsuccessful step' }
        )
        foreach ($reportNegative in $reportNegatives) {
            Invoke-Case "runtime: GUI run with a '$($reportNegative.Mode)' testflow report fails" {
                $package = New-FakePackage -Root (Join-Path $WorkRoot $reportNegative.Root)
                $stub = Join-Path $package.Install 'bin/MuseScoreStudio5.exe'
                [IO.File]::WriteAllText($stub, (New-StubBody -ReportMode $reportNegative.Mode) + "`n", [Text.UTF8Encoding]::new($false))
                & chmod +x $stub
                & pwsh -NoProfile -NonInteractive -File $PackageHelper -SourceDirectory $package.Source `
                    -InstallDirectory $package.Install -OutputDirectory $package.Artifact -ProvenancePath $package.Provenance | Out-Null
                Assert-True ($LASTEXITCODE -eq 0) "re-packaging with the $($reportNegative.Mode) stub failed"

                $result = Invoke-Helper -Script $RuntimeHelper -Arguments @(
                    '-ArtifactDirectory', $package.Artifact, '-SourceDirectory', $package.Source,
                    '-OutputDirectory', (Join-Path $WorkRoot ($reportNegative.Root + '-out')),
                    '-VersionTimeoutSeconds', '15', '-ExportTimeoutSeconds', '15', '-GuiTimeoutSeconds', '30')
                Assert-True ($result.ExitCode -ne 0) "expected a nonzero exit for report mode $($reportNegative.Mode)"
                Assert-True ($result.Output -match $reportNegative.Expect) "unexpected error text for $($reportNegative.Mode): $($result.Output)"
            }
        }

        # The probes must really run: a stub that answers every probe with success and no
        # evidence must fail the run instead of passing silently.
        Invoke-Case 'runtime: probes that report success without evidence fail the run' {
            $package = New-FakePackage -Root (Join-Path $WorkRoot 'rt-broken-probes')
            $stub = Join-Path $package.Install 'bin/MuseScoreStudio5.exe'
            [IO.File]::WriteAllText($stub, (New-StubBody -BrokenProbes) + "`n", [Text.UTF8Encoding]::new($false))
            & chmod +x $stub
            & pwsh -NoProfile -NonInteractive -File $PackageHelper -SourceDirectory $package.Source `
                -InstallDirectory $package.Install -OutputDirectory $package.Artifact -ProvenancePath $package.Provenance | Out-Null
            Assert-True ($LASTEXITCODE -eq 0) 're-packaging with the broken-probe stub failed'

            $result = Invoke-Helper -Script $RuntimeHelper -Arguments @(
                '-ArtifactDirectory', $package.Artifact, '-SourceDirectory', $package.Source,
                '-OutputDirectory', (Join-Path $WorkRoot 'rt-broken-probes-out'),
                '-VersionTimeoutSeconds', '15', '-ExportTimeoutSeconds', '15', '-GuiTimeoutSeconds', '30')
            Assert-True ($result.ExitCode -ne 0) 'expected a nonzero exit when the probes see no evidence'
            Assert-True ($result.Output -match 'probe finished: expected one report') "unexpected error text: $($result.Output)"
        }

        # A rejection probe must fail for the right reason: an unexpected exit status (a crash
        # or an abnormal termination) is not the exit 1 the GUI runner uses for a rejected run.
        Invoke-Case 'runtime: probe with an unexpected exit status is not a correct rejection' {
            $package = New-FakePackage -Root (Join-Path $WorkRoot 'rt-unexpected-probe-exit')
            $stub = Join-Path $package.Install 'bin/MuseScoreStudio5.exe'
            [IO.File]::WriteAllText($stub, (New-StubBody -UnexpectedProbeExit) + "`n", [Text.UTF8Encoding]::new($false))
            & chmod +x $stub
            & pwsh -NoProfile -NonInteractive -File $PackageHelper -SourceDirectory $package.Source `
                -InstallDirectory $package.Install -OutputDirectory $package.Artifact -ProvenancePath $package.Provenance | Out-Null
            Assert-True ($LASTEXITCODE -eq 0) 're-packaging with the unexpected-exit stub failed'

            $result = Invoke-Helper -Script $RuntimeHelper -Arguments @(
                '-ArtifactDirectory', $package.Artifact, '-SourceDirectory', $package.Source,
                '-OutputDirectory', (Join-Path $WorkRoot 'rt-unexpected-probe-exit-out'),
                '-VersionTimeoutSeconds', '15', '-ExportTimeoutSeconds', '15', '-GuiTimeoutSeconds', '30')
            Assert-True ($result.ExitCode -ne 0) 'expected a nonzero exit when a rejection probe exits unexpectedly'
            Assert-True ($result.Output -match 'expected exit 1') "unexpected error text: $($result.Output)"
        }

        Invoke-Case 'runtime: missing reviewed source script fails instead of falling back' {
            $package = New-FakePackage -Root (Join-Path $WorkRoot 'rt-no-reviewed-script')
            $stub = Join-Path $package.Install 'bin/MuseScoreStudio5.exe'
            [IO.File]::WriteAllText($stub, (New-StubBody) + "`n", [Text.UTF8Encoding]::new($false))
            & chmod +x $stub

            # Drop the reviewed script from the source checkout, then re-commit and re-package so
            # the source SHA, the install tree and the manifest stay consistent and only the
            # reviewed script is missing.
            Remove-Item -LiteralPath (Join-Path $package.Source 'share/testflowscripts/TC14_CommandPaletteAnnounce.js') -Force
            & git -C $package.Source -c user.email=ci@example.invalid -c user.name=ci add -A
            & git -C $package.Source -c user.email=ci@example.invalid -c user.name=ci commit -q -m 'drop reviewed script'
            $newHead = (& git -C $package.Source rev-parse HEAD).Trim()
            New-FakeProvenance -Path $package.Provenance -SourceSha $newHead
            # The new source SHA changes the package file name, so the repackaged artifact goes
            # to its own directory rather than beside the previous package.
            $rebuiltArtifact = Join-Path $WorkRoot 'rt-no-reviewed-script-artifact'
            & pwsh -NoProfile -NonInteractive -File $PackageHelper -SourceDirectory $package.Source `
                -InstallDirectory $package.Install -OutputDirectory $rebuiltArtifact -ProvenancePath $package.Provenance | Out-Null
            Assert-True ($LASTEXITCODE -eq 0) 're-packaging after dropping the reviewed script failed'

            $result = Invoke-Helper -Script $RuntimeHelper -Arguments @(
                '-ArtifactDirectory', $rebuiltArtifact, '-SourceDirectory', $package.Source,
                '-OutputDirectory', (Join-Path $WorkRoot 'rt-no-reviewed-script-out'),
                '-VersionTimeoutSeconds', '15', '-ExportTimeoutSeconds', '15', '-GuiTimeoutSeconds', '30')
            Assert-True ($result.ExitCode -ne 0) 'expected a nonzero exit when the reviewed script is absent'
            Assert-True ($result.Output -match 'refusing to run the packaged copy') "unexpected error text: $($result.Output)"
        }

        Invoke-Case 'runtime: manifest executable that escapes the root or contradicts source metadata fails' {
            foreach ($candidate in @('bin/../../evil.exe', 'bin/OtherStudio5.exe')) {
                $root = Join-Path $WorkRoot ("rt-executable-" + ($candidate -replace '[^A-Za-z0-9]', '-'))
                $package = New-FakePackage -Root $root
                $manifestPath = Join-Path $package.Artifact 'build-manifest.json'
                $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
                $manifest.executable = $candidate
                [IO.File]::WriteAllText($manifestPath, (ConvertTo-Json -InputObject $manifest -Depth 10), [Text.UTF8Encoding]::new($false))

                $result = Invoke-Helper -Script $RuntimeHelper -Arguments @(
                    '-ArtifactDirectory', $package.Artifact, '-SourceDirectory', $package.Source,
                    '-OutputDirectory', (Join-Path $root 'out'))
                Assert-True ($result.ExitCode -ne 0) "expected a nonzero exit for manifest executable '$candidate'"
                if ($candidate -like '*..*') {
                    Assert-True ($result.Output -match 'escapes the extraction root') "unexpected error text: $($result.Output)"
                } else {
                    Assert-True ($result.Output -match 'derived from the source checkout') "unexpected error text: $($result.Output)"
                }
            }
        }
    }
} finally {
    Write-Host ''
    Write-Host "cases: $($script:Passed) passed, $($script:Failed) failed, $($script:Skipped) skipped"
}

if ($script:Failed -gt 0) {
    exit 1
}
exit 0
