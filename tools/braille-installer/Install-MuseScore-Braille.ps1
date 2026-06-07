[CmdletBinding(SupportsShouldProcess = $true)]
param()

$ErrorActionPreference = 'Stop'

$PackageName = 'MuseScore Braille Installer'
$ShortcutName = 'MuseScore Braille Test Build'
$ExpectedExeRelativePath = 'bin\MuseScoreStudio5.exe'

function Write-Log {
    param([Parameter(Mandatory = $true)][string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] $Message"
    Write-Host $Message
    if (-not $WhatIfPreference) {
        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    }
}

function Assert-64BitWindows {
    if (-not $IsWindows -and $PSVersionTable.PSEdition -eq 'Core') {
        throw 'This installer is for 64-bit Windows only.'
    }

    if (-not [Environment]::Is64BitOperatingSystem) {
        throw 'This installer is for 64-bit Windows only.'
    }
}

function Assert-NoMuseScoreRunning {
    $running = Get-Process -Name 'MuseScoreStudio*' -ErrorAction SilentlyContinue
    if ($running) {
        $processList = ($running | ForEach-Object { "$($_.ProcessName) (PID $($_.Id))" }) -join ', '
        throw "Please close MuseScore before installing. Running process(es): $processList"
    }
}

function Assert-RequiredPath {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowEmptyString()][string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "$Name path could not be resolved."
    }
}

function Assert-Payload {
    if (-not (Test-Path -LiteralPath $PayloadZip -PathType Leaf)) {
        throw "Payload ZIP not found: $PayloadZip"
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($PayloadZip)
    try {
        $normalizedExpected = $ExpectedExeRelativePath.Replace('\', '/')
        $entry = $zip.Entries | Where-Object { $_.FullName.Replace('\', '/') -eq $normalizedExpected } | Select-Object -First 1
        if (-not $entry) {
            throw "Payload ZIP does not contain expected executable: $ExpectedExeRelativePath"
        }
    }
    finally {
        $zip.Dispose()
    }
}

function New-Shortcut {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($Path)
    $shortcut.TargetPath = $TargetPath
    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.Description = $Description
    $shortcut.IconLocation = $TargetPath
    $shortcut.Save()
}

try {
    Assert-64BitWindows

    $localAppData = $env:LOCALAPPDATA
    $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    $desktopPath = [Environment]::GetFolderPath('Desktop')
    $programsPath = [Environment]::GetFolderPath('Programs')

    Assert-RequiredPath -Name 'LOCALAPPDATA' -Value $localAppData
    Assert-RequiredPath -Name 'Script root' -Value $ScriptRoot
    Assert-RequiredPath -Name 'Desktop' -Value $desktopPath
    Assert-RequiredPath -Name 'Start Menu Programs' -Value $programsPath

    $InstallRoot = Join-Path $localAppData 'MuseScore-Braille'
    $LogPath = Join-Path $localAppData 'MuseScore-Braille-Install.log'
    $PayloadZip = Join-Path $ScriptRoot 'payload\MuseScore-Braille.zip'
    $InstalledExe = Join-Path $InstallRoot $ExpectedExeRelativePath
    $MetadataPath = Join-Path $InstallRoot 'INSTALL-METADATA.txt'
    $DesktopShortcut = Join-Path $desktopPath "$ShortcutName.lnk"
    $StartMenuDir = Join-Path $programsPath $ShortcutName
    $StartMenuShortcut = Join-Path $StartMenuDir "$ShortcutName.lnk"

    $logParent = Split-Path -Parent $LogPath
    if (-not (Test-Path -LiteralPath $logParent)) {
        if ($PSCmdlet.ShouldProcess($logParent, 'Create log directory')) {
            New-Item -ItemType Directory -Path $logParent -Force | Out-Null
        }
    }

    if (-not $WhatIfPreference) {
        Set-Content -LiteralPath $LogPath -Value "$PackageName log started $(Get-Date -Format o)" -Encoding UTF8
    }
    Write-Log "Installing $PackageName..."
    Write-Log 'Validated 64-bit Windows.'

    Assert-Payload
    Write-Log "Validated payload: $PayloadZip"

    Assert-NoMuseScoreRunning
    Write-Log 'Confirmed no MuseScoreStudio process is running.'

    $installParent = Split-Path -Parent $InstallRoot
    if (-not (Test-Path -LiteralPath $installParent)) {
        if ($PSCmdlet.ShouldProcess($installParent, 'Create install parent directory')) {
            New-Item -ItemType Directory -Path $installParent -Force | Out-Null
        }
    }

    if (Test-Path -LiteralPath $InstallRoot) {
        Write-Log "Removing existing custom install: $InstallRoot"
        if ($PSCmdlet.ShouldProcess($InstallRoot, 'Remove existing custom install')) {
            Remove-Item -LiteralPath $InstallRoot -Recurse -Force
        }
    }

    Write-Log "Extracting payload to: $InstallRoot"
    if ($PSCmdlet.ShouldProcess($InstallRoot, 'Extract payload')) {
        New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
        Expand-Archive -LiteralPath $PayloadZip -DestinationPath $InstallRoot -Force
    }

    if (-not $WhatIfPreference -and -not (Test-Path -LiteralPath $InstalledExe -PathType Leaf)) {
        throw "Installed executable was not found after extraction: $InstalledExe"
    }

    $sourceCommit = 'UNKNOWN'
    $packageVersion = 'UNKNOWN'
    $metadataSource = Join-Path $ScriptRoot 'PACKAGE-METADATA.txt'
    if (Test-Path -LiteralPath $metadataSource -PathType Leaf) {
        $metadataLines = Get-Content -LiteralPath $metadataSource
        foreach ($line in $metadataLines) {
            if ($line -match '^SourceCommit=(.+)$') { $sourceCommit = $Matches[1] }
            if ($line -match '^PackageVersion=(.+)$') { $packageVersion = $Matches[1] }
        }
    }

    $metadata = @(
        'PackageName=MuseScore Braille Installer'
        "PackageVersion=$packageVersion"
        "SourceCommit=$sourceCommit"
        'BuildConfiguration=app Release'
        "InstalledAt=$(Get-Date -Format o)"
        "Executable=$InstalledExe"
    )

    Write-Log "Writing metadata: $MetadataPath"
    if ($PSCmdlet.ShouldProcess($MetadataPath, 'Write install metadata')) {
        Set-Content -LiteralPath $MetadataPath -Value $metadata -Encoding UTF8
    }

    Write-Log "Creating desktop shortcut: $DesktopShortcut"
    if ($PSCmdlet.ShouldProcess($DesktopShortcut, 'Create desktop shortcut')) {
        New-Shortcut -Path $DesktopShortcut -TargetPath $InstalledExe -WorkingDirectory (Split-Path -Parent $InstalledExe) -Description $ShortcutName
    }

    Write-Log "Creating Start Menu shortcut: $StartMenuShortcut"
    if ($PSCmdlet.ShouldProcess($StartMenuShortcut, 'Create Start Menu shortcut')) {
        New-Shortcut -Path $StartMenuShortcut -TargetPath $InstalledExe -WorkingDirectory (Split-Path -Parent $InstalledExe) -Description $ShortcutName
    }

    Write-Log 'Install complete.'
    Write-Host ''
    Write-Host 'Install complete.'
    Write-Host "Open `"$ShortcutName`" from your Desktop or Start Menu."
}
catch {
    Write-Host ''
    Write-Host "Install failed: $($_.Exception.Message)" -ForegroundColor Red
    if (-not $WhatIfPreference -and -not [string]::IsNullOrWhiteSpace($LogPath)) {
        Add-Content -LiteralPath $LogPath -Value "Install failed: $($_.Exception.Message)" -Encoding UTF8
    }
    exit 1
}
