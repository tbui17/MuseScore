[CmdletBinding()]
param(
    [string]$InstallSource = (Join-Path (Get-Location) 'build.install'),
    [string]$OutputRoot = (Join-Path (Get-Location) 'dist\musescore-braille-installer'),
    [string]$PackageVersion = (Get-Date -Format 'yyyy-MM-dd'),
    [string]$SourceCommit = ''
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Get-Location
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedExe = Join-Path $InstallSource 'bin\MuseScoreStudio5.exe'
$PackageName = "MuseScore-Braille-Installer-$PackageVersion"
$WorkRoot = Join-Path $OutputRoot 'work'
$OuterRoot = Join-Path $WorkRoot $PackageName
$PayloadDir = Join-Path $OuterRoot 'payload'
$PayloadZip = Join-Path $PayloadDir 'MuseScore-Braille.zip'
$OuterZip = Join-Path $OutputRoot "$PackageName.zip"
$PackageMetadata = Join-Path $OuterRoot 'PACKAGE-METADATA.txt'

function Resolve-SourceCommit {
    if ($SourceCommit) {
        return $SourceCommit
    }

    $commit = (& git rev-parse --short=12 HEAD 2>$null)
    if ($LASTEXITCODE -eq 0 -and $commit) {
        return $commit.Trim()
    }

    return 'UNKNOWN'
}

function Remove-DirectoryIfSafe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to remove reparse-point directory: $Path"
    }

    Remove-Item -LiteralPath $Path -Recurse -Force
}

if (-not (Test-Path -LiteralPath $InstallSource -PathType Container)) {
    throw "Install source folder not found: $InstallSource. Run .\ninja_build.bat -t install first."
}

if (-not (Test-Path -LiteralPath $ExpectedExe -PathType Leaf)) {
    throw "Expected installed executable not found: $ExpectedExe. Run .\ninja_build.bat -t install first."
}

$resolvedCommit = Resolve-SourceCommit

if (Test-Path -LiteralPath $WorkRoot) {
    Remove-DirectoryIfSafe -Path $WorkRoot
}

New-Item -ItemType Directory -Path $PayloadDir -Force | Out-Null

if (Test-Path -LiteralPath $OuterZip) {
    Remove-Item -LiteralPath $OuterZip -Force
}

Write-Host "Creating payload ZIP from $InstallSource"
Compress-Archive -Path (Join-Path $InstallSource '*') -DestinationPath $PayloadZip -CompressionLevel Optimal -Force

Copy-Item -LiteralPath (Join-Path $ScriptRoot 'Install-MuseScore-Braille.ps1') -Destination (Join-Path $OuterRoot 'Install-MuseScore-Braille.ps1')
Copy-Item -LiteralPath (Join-Path $ScriptRoot 'Uninstall-MuseScore-Braille.ps1') -Destination (Join-Path $OuterRoot 'Uninstall-MuseScore-Braille.ps1')
Copy-Item -LiteralPath (Join-Path $ScriptRoot 'README-FIRST.txt') -Destination (Join-Path $OuterRoot 'README-FIRST.txt')
Copy-Item -LiteralPath (Join-Path $ScriptRoot 'OPERATOR-NOTES.txt') -Destination (Join-Path $OuterRoot 'OPERATOR-NOTES.txt')

$metadata = @(
    'PackageName=MuseScore Braille Installer'
    "PackageVersion=$PackageVersion"
    "SourceCommit=$resolvedCommit"
    'BuildConfiguration=app Release'
    "BuiltAt=$(Get-Date -Format o)"
    "InstallSource=$InstallSource"
)
Set-Content -LiteralPath $PackageMetadata -Value $metadata -Encoding UTF8

Write-Host "Creating outer ZIP: $OuterZip"
Compress-Archive -Path $OuterRoot -DestinationPath $OuterZip -CompressionLevel Optimal -Force

Write-Host ''
Write-Host "Package created: $OuterZip"
Write-Host "Source commit: $resolvedCommit"
