[CmdletBinding(SupportsShouldProcess = $true)]
param()

$ErrorActionPreference = 'Stop'

$ShortcutName = 'MuseScore Braille Test Build'
$LogPath = $null

function Write-Log {
    param([Parameter(Mandatory = $true)][string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] $Message"
    Write-Host $Message
    if (-not $WhatIfPreference) {
        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    }
}

function Assert-NoMuseScoreRunning {
    $running = Get-Process -Name 'MuseScoreStudio*' -ErrorAction SilentlyContinue
    if ($running) {
        $processList = ($running | ForEach-Object { "$($_.ProcessName) (PID $($_.Id))" }) -join ', '
        throw "Please close MuseScore before uninstalling. Running process(es): $processList"
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

try {
    $localAppData = $env:LOCALAPPDATA
    $desktopPath = [Environment]::GetFolderPath('Desktop')
    $programsPath = [Environment]::GetFolderPath('Programs')

    Assert-RequiredPath -Name 'LOCALAPPDATA' -Value $localAppData
    Assert-RequiredPath -Name 'Desktop' -Value $desktopPath
    Assert-RequiredPath -Name 'Start Menu Programs' -Value $programsPath

    $InstallRoot = Join-Path $localAppData 'MuseScore-Braille'
    $LogPath = Join-Path $localAppData 'MuseScore-Braille-Install.log'
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
        Add-Content -LiteralPath $LogPath -Value "Uninstall started $(Get-Date -Format o)" -Encoding UTF8
    }
    Write-Log 'Uninstalling MuseScore Braille Test Build...'

    Assert-NoMuseScoreRunning
    Write-Log 'Confirmed no MuseScoreStudio process is running.'

    foreach ($shortcut in @($DesktopShortcut, $StartMenuShortcut)) {
        if (Test-Path -LiteralPath $shortcut) {
            Write-Log "Removing shortcut: $shortcut"
            if ($PSCmdlet.ShouldProcess($shortcut, 'Remove shortcut')) {
                Remove-Item -LiteralPath $shortcut -Force
            }
        }
    }

    if (Test-Path -LiteralPath $StartMenuDir) {
        $remaining = Get-ChildItem -LiteralPath $StartMenuDir -Force -ErrorAction SilentlyContinue
        if (-not $remaining) {
            Write-Log "Removing empty Start Menu folder: $StartMenuDir"
            if ($PSCmdlet.ShouldProcess($StartMenuDir, 'Remove empty Start Menu folder')) {
                Remove-Item -LiteralPath $StartMenuDir -Force
            }
        }
    }

    if (Test-Path -LiteralPath $InstallRoot) {
        $existingInstallRoot = Get-Item -LiteralPath $InstallRoot -Force
        if (($existingInstallRoot.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing to remove install root because it is a reparse point: $InstallRoot"
        }

        Write-Log "Removing install folder: $InstallRoot"
        if ($PSCmdlet.ShouldProcess($InstallRoot, 'Remove custom install folder')) {
            Remove-Item -LiteralPath $InstallRoot -Recurse -Force
        }
    }

    if (Test-Path -LiteralPath $LogPath) {
        Write-Log "Removing installer log: $LogPath"
        if ($PSCmdlet.ShouldProcess($LogPath, 'Remove installer log')) {
            Remove-Item -LiteralPath $LogPath -Force
        }
    }

    Write-Host ''
    Write-Host 'Uninstall complete.'
}
catch {
    Write-Host ''
    Write-Host "Uninstall failed: $($_.Exception.Message)" -ForegroundColor Red
    if (-not $WhatIfPreference -and -not [string]::IsNullOrWhiteSpace($LogPath)) {
        Add-Content -LiteralPath $LogPath -Value "Uninstall failed: $($_.Exception.Message)" -Encoding UTF8
    }
    exit 1
}
