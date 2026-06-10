#Requires -Version 5.1
# Sleep Timer Backend - Electron Communication Bridge
param(
    [Parameter(Mandatory=$true)]
    [int]$Minutes,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet('shutdown', 'restart', 'sleep', 'hibernate', 'logout')]
    [string]$Action = 'shutdown',
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun,
    
    [Parameter(Mandatory=$false)]
    [int]$GracePeriod = 2,
    
    [Parameter(Mandatory=$false)]
    [switch]$ForceShutdown,
    
    [Parameter(Mandatory=$false)]
    [switch]$MuteSystem,
    
    [Parameter(Mandatory=$false)]
    [switch]$ElectronMode
)

# Global state
$script:StartTime = Get-Date
$script:TotalSeconds = $Minutes * 60
$script:RemainingSeconds = $script:TotalSeconds
$script:Paused = $false
$script:Cancelled = $false
$script:SnoozeAdded = 0

# Output JSON to stdout for Electron
function Send-Status($Type, $Data) {
    $message = @{
        type = $Type
        timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        data = $Data
    } | ConvertTo-Json -Compress
    Write-Output $message
}

# Read stdin for commands from Electron
function Read-Command {
    if ($Host.UI.RawUI.KeyAvailable) {
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyUp")
        return $key.Character
    }
    return $null
}

# Mute system audio
function Set-Mute($Enable) {
    try {
        $wsh = New-Object -ComObject WScript.Shell
        $wsh.SendKeys([char]173)  # Mute key
        return $true
    } catch {
        return $false
    }
}

# Get battery status
function Get-BatteryStatus {
    try {
        $battery = Get-WmiObject -Class Win32_Battery -ErrorAction SilentlyContinue
        if ($battery) {
            return @{
                level = $battery.EstimatedChargeRemaining
                status = $battery.BatteryStatus
                hasBattery = $true
            }
        }
    } catch {}
    return @{ hasBattery = $false }
}

# Check for blocking applications
function Get-BlockingApps {
    $blockers = @()
    
    # Check for full-screen apps
    try {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinAPI {
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
    
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);
    
    public struct RECT { public int Left, Top, Right, Bottom; }
    
    public static bool IsFullScreen() {
        IntPtr hWnd = GetForegroundWindow();
        if (hWnd == IntPtr.Zero) return false;
        
        RECT rect;
        GetWindowRect(hWnd, out rect);
        
        int screenWidth = System.Windows.Forms.Screen.PrimaryScreen.Bounds.Width;
        int screenHeight = System.Windows.Forms.Screen.PrimaryScreen.Bounds.Height;
        
        return (rect.Right - rect.Left >= screenWidth && 
                rect.Bottom - rect.Top >= screenHeight);
    }
}
"@ -ReferencedAssemblies System.Windows.Forms -ErrorAction SilentlyContinue
        
        if ([WinAPI]::IsFullScreen()) {
            $blockers += "Full-screen application active"
        }
    } catch {}
    
    # Check for processes that typically prevent shutdown
    $preventShutdownProcesses = @('vlc', 'chrome', 'firefox', 'edge', 'spotify', 
                                    'steam', 'epicgameslauncher', 'discord', 
                                    'obs64', 'obs32', 'zoom', 'teams')
    
    $running = Get-Process | Where-Object { 
        $preventShutdownProcesses -contains $_.ProcessName.ToLower() 
    } | Select-Object -ExpandProperty ProcessName -Unique
    
    if ($running) {
        $blockers += "Running apps: $($running -join ', ')"
    }
    
    return $blockers
}

# Execute power action
function Invoke-PowerAction($ActionType) {
    Send-Status 'executing' @{ action = $ActionType }
    
    if ($DryRun) {
        Send-Status 'dryrun' @{ action = $ActionType; message = 'Dry run - no actual action taken' }
        return $true
    }
    
    try {
        switch ($ActionType) {
            'shutdown' {
                $arg = if ($ForceShutdown) { '/s /f /t 0' } else { '/s /t 0' }
                Start-Process -FilePath 'shutdown.exe' -ArgumentList $arg -Wait:$false
            }
            'restart' {
                $arg = if ($ForceShutdown) { '/r /f /t 0' } else { '/r /t 0' }
                Start-Process -FilePath 'shutdown.exe' -ArgumentList $arg -Wait:$false
            }
            'sleep' {
                # Modern sleep command
                Start-Process -FilePath 'rundll32.exe' -ArgumentList 'powrprof.dll,SetSuspendState 0,1,0' -Wait:$false
            }
            'hibernate' {
                Start-Process -FilePath 'rundll32.exe' -ArgumentList 'powrprof.dll,SetSuspendState 1,1,0' -Wait:$false
            }
            'logout' {
                Start-Process -FilePath 'shutdown.exe' -ArgumentList '/l' -Wait:$false
            }
        }
        return $true
    } catch {
        Send-Status 'error' @{ message = $_.Exception.Message }
        return $false
    }
}

# Main timer loop
function Start-TimerLoop {
    Send-Status 'started' @{ 
        totalSeconds = $script:TotalSeconds
        action = $Action
        dryRun = $DryRun.IsPresent
    }
    
    $lastSecond = -1
    
    while ($script:RemainingSeconds -gt 0) {
        # Check for cancellation (stdin would close or we could check a file)
        if ($script:Cancelled) {
            Send-Status 'cancelled' @{ reason = 'User requested cancellation' }
            return
        }
        
        if (-not $script:Paused) {
            # Calculate remaining time
            $elapsed = ([DateTime]::Now - $script:StartTime).TotalSeconds - $script:SnoozeAdded
            $script:RemainingSeconds = [Math]::Max(0, $script:TotalSeconds - [int]$elapsed)
            
            # Send tick update (every second)
            if ($script:RemainingSeconds -ne $lastSecond) {
                $battery = Get-BatteryStatus
                $blockers = Get-BlockingApps
                
                Send-Status 'tick' @{
                    remaining = $script:RemainingSeconds
                    total = $script:TotalSeconds
                    percent = [Math]::Round(($script:RemainingSeconds / $script:TotalSeconds) * 100, 1)
                    formatted = Format-Time $script:RemainingSeconds
                    battery = $battery
                    warnings = $blockers
                    paused = $script:Paused
                }
                
                $lastSecond = $script:RemainingSeconds
                
                # Check for grace period warning
                if ($script:RemainingSeconds -eq ($GracePeriod * 60)) {
                    Send-Status 'warning' @{ 
                        message = "Shutdown in $GracePeriod minutes"
                        gracePeriod = $true
                    }
                }
            }
            
            # Check for final warning
            if ($script:RemainingSeconds -le 10 -and $script:RemainingSeconds -gt 0) {
                Send-Status 'final' @{ seconds = $script:RemainingSeconds }
            }
        } else {
            Send-Status 'paused' @{ remaining = $script:RemainingSeconds }
        }
        
        # Small delay to prevent CPU spinning
        Start-Sleep -Milliseconds 100
    }
    
    # Timer complete - execute action
    Send-Status 'complete' @{ message = 'Timer complete - executing action' }
    
    if ($MuteSystem) {
        Set-Mute $true
        Start-Sleep -Seconds 1
    }
    
    Invoke-PowerAction $Action
}

# Format time as HH:MM:SS or MM:SS
function Format-Time($Seconds) {
    $ts = [TimeSpan]::FromSeconds($Seconds)
    if ($ts.Hours -gt 0) {
        return "{0}:{1:D2}:{2:D2}" -f $ts.Hours, $ts.Minutes, $ts.Seconds
    }
    return "{0:D2}:{1:D2}" -f $ts.Minutes, $ts.Seconds
}

# Grace period check
function Test-GracePeriod {
    if ($GracePeriod -gt 0) {
        Send-Status 'grace' @{ minutes = $GracePeriod }
        
        $graceEnd = (Get-Date).AddMinutes($GracePeriod)
        while ((Get-Date) -lt $graceEnd -and -not $script:Cancelled) {
            $remainingGrace = [int]($graceEnd - (Get-Date)).TotalSeconds
            if ($remainingGrace % 10 -eq 0) {  # Every 10 seconds
                Send-Status 'grace-tick' @{ seconds = $remainingGrace }
            }
            Start-Sleep -Seconds 1
        }
        
        if ($script:Cancelled) {
            return $false
        }
    }
    return $true
}

# Signal handling for clean shutdown
$null = Register-EngineEvent -SourceIdentifier ([System.Management.Automation.PSEngineEvent]::Exiting) -Action {
    Send-Status 'terminated' @{ message = 'Backend process terminating' }
}

# ===== MAIN EXECUTION =====
try {
    # Send initial status
    Send-Status 'ready' @{ 
        version = '5.3.0'
        pid = $PID
        action = $Action
        minutes = $Minutes
    }
    
    # Check battery
    $battery = Get-BatteryStatus
    if ($battery.hasBattery -and $battery.level -lt 20) {
        Send-Status 'low-battery' @{ level = $battery.level }
    }
    
    # Check for blocking apps
    $blockers = Get-BlockingApps
    if ($blockers.Count -gt 0) {
        Send-Status 'blockers' @{ apps = $blockers }
    }
    
    # Start the timer
    Start-TimerLoop
    
    # Clean exit
    Send-Status 'exiting' @{ code = 0 }
    exit 0
    
} catch {
    Send-Status 'error' @{ 
        message = $_.Exception.Message
        stack = $_.ScriptStackTrace
    }
    exit 1
}
