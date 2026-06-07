[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Owner = 'tbui17',
    [string]$Repo = 'MuseScore',
    [string]$ReleaseTag = '',
    [string]$AssetPattern = 'MuseScore-Braille-Installer-*.zip',
    [string]$DownloadUrl = '',
    [string]$WorkRoot = ''
)

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

function Get-ReleaseAsset {
    param(
        [Parameter(Mandatory = $true)][string]$Owner,
        [Parameter(Mandatory = $true)][string]$Repo,
        [string]$ReleaseTag,
        [Parameter(Mandatory = $true)][string]$AssetPattern
    )

    $releaseUri = if ($ReleaseTag) {
        "https://api.github.com/repos/$Owner/$Repo/releases/tags/$ReleaseTag"
    } else {
        "https://api.github.com/repos/$Owner/$Repo/releases/latest"
    }

    Write-Host "Reading release metadata: $releaseUri"
    $release = Invoke-RestMethod -Uri $releaseUri -Headers @{ 'User-Agent' = 'MuseScore-Braille-Installer' }
    $asset = $release.assets | Where-Object { $_.name -like $AssetPattern } | Select-Object -First 1
    if (-not $asset) {
        throw "No release asset matching '$AssetPattern' was found in $Owner/$Repo."
    }

    return $asset
}

function Remove-DirectoryIfSafe {
    param([Parameter(Mandatory = $true)][string]$Path)

    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to remove reparse-point directory: $Path"
    }

    Remove-Item -LiteralPath $Path -Recurse -Force
}

function Resolve-PayloadFromGitHub {
    param(
        [Parameter(Mandatory = $true)][string]$WorkRoot,
        [Parameter(Mandatory = $true)][string]$Owner,
        [Parameter(Mandatory = $true)][string]$Repo,
        [string]$ReleaseTag,
        [Parameter(Mandatory = $true)][string]$AssetPattern,
        [string]$DownloadUrl
    )

    $assetName = 'MuseScore-Braille-Installer.zip'
    $assetUrl = $DownloadUrl
    if (-not $assetUrl) {
        $asset = Get-ReleaseAsset -Owner $Owner -Repo $Repo -ReleaseTag $ReleaseTag -AssetPattern $AssetPattern
        $assetName = $asset.name
        $assetUrl = $asset.browser_download_url
    }

    if (-not $assetUrl) {
        throw 'Could not determine release asset download URL.'
    }

    $zipPath = Join-Path $WorkRoot $assetName
    $extractRoot = Join-Path $WorkRoot 'extracted'

    Write-Host "Local payload not found. Downloading installer package from GitHub."
    Write-Host "Download URL: $assetUrl"
    Write-Host "Working folder: $WorkRoot"

    if (Test-Path -LiteralPath $WorkRoot) {
        if ($PSCmdlet.ShouldProcess($WorkRoot, 'Remove previous download working folder')) {
            Remove-DirectoryIfSafe -Path $WorkRoot
        }
    }

    if ($PSCmdlet.ShouldProcess($WorkRoot, 'Create download working folder')) {
        New-Item -ItemType Directory -Path $WorkRoot -Force | Out-Null
    }

    if ($PSCmdlet.ShouldProcess($zipPath, 'Download installer package')) {
        Invoke-WebRequest -Uri $assetUrl -OutFile $zipPath -UseBasicParsing
    }

    if ($PSCmdlet.ShouldProcess($extractRoot, 'Extract installer package')) {
        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractRoot -Force
    }

    if ($WhatIfPreference) {
        Write-Host 'WhatIf: GitHub download and package extraction were simulated.'
        return $null
    }

    $payload = Get-ChildItem -LiteralPath $extractRoot -Filter 'MuseScore-Braille.zip' -Recurse -File | Where-Object { $_.FullName -match '[\\/]payload[\\/]MuseScore-Braille\.zip$' } | Select-Object -First 1
    if (-not $payload) {
        throw 'Downloaded package did not contain payload\MuseScore-Braille.zip.'
    }

    return $payload.FullName
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
    $tempPath = $env:TEMP
    $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    $desktopPath = [Environment]::GetFolderPath('Desktop')
    $programsPath = [Environment]::GetFolderPath('Programs')

    Assert-RequiredPath -Name 'LOCALAPPDATA' -Value $localAppData
    Assert-RequiredPath -Name 'TEMP' -Value $tempPath
    Assert-RequiredPath -Name 'Script root' -Value $ScriptRoot
    Assert-RequiredPath -Name 'Desktop' -Value $desktopPath
    Assert-RequiredPath -Name 'Start Menu Programs' -Value $programsPath

    $InstallRoot = Join-Path $localAppData 'MuseScore-Braille'
    $LogPath = Join-Path $localAppData 'MuseScore-Braille-Install.log'
    if ([string]::IsNullOrWhiteSpace($WorkRoot)) {
        $WorkRoot = Join-Path $tempPath 'MuseScore-Braille-GitHub-Install'
    }

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

    if (-not (Test-Path -LiteralPath $PayloadZip -PathType Leaf)) {
        $downloadedPayload = Resolve-PayloadFromGitHub -WorkRoot $WorkRoot -Owner $Owner -Repo $Repo -ReleaseTag $ReleaseTag -AssetPattern $AssetPattern -DownloadUrl $DownloadUrl
        if ($downloadedPayload) {
            $PayloadZip = $downloadedPayload
            $ScriptRoot = Split-Path -Parent (Split-Path -Parent $PayloadZip)
        } elseif ($WhatIfPreference) {
            Write-Host 'WhatIf: install stopped after simulated GitHub package download.'
            return
        }
    }

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
        $existingInstallRoot = Get-Item -LiteralPath $InstallRoot -Force
        if (($existingInstallRoot.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing to remove existing install root because it is a reparse point: $InstallRoot"
        }

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
