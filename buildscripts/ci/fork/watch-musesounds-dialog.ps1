#!/usr/bin/env pwsh
# Diagnostic-only hosted-runner monitor for the deterministic MuseSounds update test-mode control.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $EvidencePath,
    [int] $OpenTimeoutSeconds = 900,
    [int] $SettleMilliseconds = 750,
    [int] $CloseTimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class MuseDialogWindowProbe
{
    private delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);

    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hwnd);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hwnd);

    [DllImport("user32.dll")]
    public static extern IntPtr GetWindow(IntPtr hwnd, uint command);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int count);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr hwnd, StringBuilder text, int count);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool PostMessage(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);

    public static IntPtr[] WindowsForProcess(uint expectedProcessId)
    {
        var windows = new List<IntPtr>();
        EnumWindows((hwnd, _) => {
            uint processId;
            GetWindowThreadProcessId(hwnd, out processId);
            if (processId == expectedProcessId) {
                windows.Add(hwnd);
            }
            return true;
        }, IntPtr.Zero);
        return windows.ToArray();
    }

    public static string WindowText(IntPtr hwnd)
    {
        var text = new StringBuilder(1024);
        GetWindowText(hwnd, text, text.Capacity);
        return text.ToString();
    }

    public static string WindowClass(IntPtr hwnd)
    {
        var text = new StringBuilder(256);
        GetClassName(hwnd, text, text.Capacity);
        return text.ToString();
    }
}
'@

$WM_CLOSE = 0x0010
$GW_OWNER = 4
$monitorStartedAt = [DateTime]::UtcNow
$logDirectory = Join-Path $env:LOCALAPPDATA 'MuseScore\MuseScoreStudio5Development\logs'
$evidence = [ordered]@{
    expected_process = 'MuseScoreStudio5.exe'
    expected_control_script = 'TC_MuseSoundsUpdateTestModeControl.js'
    selection_rule = 'single visible non-main, non-New-score top-level window after the MuseSounds release-dialog QML marker, from the exact control process'
    dialog_log_marker_observed = $false
    dialog_log_path = $null
    opened = $false
    settled = $false
    close_invoked = $false
    closed = $false
    process_id = $null
    main_window_handle = $null
    window_handle = $null
    owner_handle = $null
    window_class = $null
    window_title = $null
    opened_at_utc = $null
    close_invoked_at_utc = $null
    closed_at_utc = $null
    observed_windows = @()
    error = $null
}
$exitCode = 1

try {
    $deadline = [DateTime]::UtcNow.AddSeconds($OpenTimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline -and -not $evidence.opened) {
        $processes = @(Get-CimInstance Win32_Process -Filter "Name = 'MuseScoreStudio5.exe'" |
            Where-Object { [string]$_.CommandLine -like '*TC_MuseSoundsUpdateTestModeControl.js*' })

            $markerLog = @(Get-ChildItem -LiteralPath $logDirectory -Filter 'MuseScoreStudio_*.log' -File |
                Where-Object { $_.LastWriteTimeUtc -ge $monitorStartedAt } |
                Where-Object { Select-String -LiteralPath $_.FullName -SimpleMatch 'MuseSoundsReleaseInfoDialog.qml' -Quiet } |
                Sort-Object LastWriteTimeUtc -Descending |
                Select-Object -First 1)
            if ($markerLog.Count -eq 0) {
                continue
            }
            $evidence.dialog_log_marker_observed = $true
            $evidence.dialog_log_path = $markerLog[0].FullName

        foreach ($process in $processes) {
            $windows = @([MuseDialogWindowProbe]::WindowsForProcess([uint32]$process.ProcessId) |
                Where-Object { [MuseDialogWindowProbe]::IsWindowVisible($_) })
            $observed = @($windows | ForEach-Object {
                $owner = [MuseDialogWindowProbe]::GetWindow($_, $GW_OWNER)
                [ordered]@{
                    handle = $_.ToInt64()
                    owner_handle = $owner.ToInt64()
                    class = [MuseDialogWindowProbe]::WindowClass($_)
                    title = [MuseDialogWindowProbe]::WindowText($_)
                }
            })
            $evidence.observed_windows = $observed
            $mainWindow = [Diagnostics.Process]::GetProcessById([int]$process.ProcessId).MainWindowHandle
            $evidence.main_window_handle = $mainWindow.ToInt64()
            $candidates = @($windows | Where-Object {
                $_ -ne $mainWindow -and
                [MuseDialogWindowProbe]::WindowText($_) -ne 'New score'
            })
            if ($candidates.Count -eq 0) {
                continue
            }
            if ($candidates.Count -ne 1) {
                throw "expected one visible non-main dialog window for the exact control process, found $($candidates.Count)"
            }

            $target = $candidates[0]
            $owner = [MuseDialogWindowProbe]::GetWindow($target, $GW_OWNER)
            $evidence.opened = $true
            $evidence.process_id = [int]$process.ProcessId
            $evidence.window_handle = $target.ToInt64()
            $evidence.owner_handle = $owner.ToInt64()
            $evidence.window_class = [MuseDialogWindowProbe]::WindowClass($target)
            $evidence.window_title = [MuseDialogWindowProbe]::WindowText($target)
            $evidence.opened_at_utc = [DateTime]::UtcNow.ToString('o')

            Start-Sleep -Milliseconds $SettleMilliseconds
            if (-not [MuseDialogWindowProbe]::IsWindow($target) -or
                -not [MuseDialogWindowProbe]::IsWindowVisible($target)) {
                throw 'identified MuseSounds dialog disappeared before the settlement interval elapsed'
            }
            $evidence.settled = $true

            if (-not [MuseDialogWindowProbe]::PostMessage($target, $WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero)) {
                throw 'PostMessage(WM_CLOSE) failed for the identified MuseSounds dialog'
            }
            $evidence.close_invoked = $true
            $evidence.close_invoked_at_utc = [DateTime]::UtcNow.ToString('o')

            $closeDeadline = [DateTime]::UtcNow.AddSeconds($CloseTimeoutSeconds)
            while ([MuseDialogWindowProbe]::IsWindow($target) -and [DateTime]::UtcNow -lt $closeDeadline) {
                Start-Sleep -Milliseconds 100
            }
            if ([MuseDialogWindowProbe]::IsWindow($target)) {
                throw 'identified MuseSounds dialog did not close within the bounded close interval'
            }
            $evidence.closed = $true
            $evidence.closed_at_utc = [DateTime]::UtcNow.ToString('o')
            $exitCode = 0
            break
        }

        if (-not $evidence.opened) {
            Start-Sleep -Milliseconds 100
        }
    }

    if (-not $evidence.opened) {
        throw "identified MuseSounds dialog did not open within $OpenTimeoutSeconds seconds"
    }
} catch {
    $evidence.error = $_.Exception.Message
} finally {
    $evidence | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $EvidencePath -Encoding utf8NoBOM
}

exit $exitCode
