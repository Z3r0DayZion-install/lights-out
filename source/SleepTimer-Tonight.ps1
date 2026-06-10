#Requires -Version 5.1
# Sleep Timer - desktop nightly build
param(
    [switch]$NoAutoStart,
    [switch]$DryRun,
    [switch]$Demo,
    [switch]$Minimized,
    [switch]$Start,
    [switch]$Help,
    [switch]$SteamUi,
    [switch]$ClassicUi,
    [switch]$Simple,
    [switch]$ForceShutdown,
    [Alias('m', 'mins')]
    [int]$Minutes = 0,
    [Alias('a')]
    [string]$Action = '',
    [Alias('sec', 's')]
    [int]$Seconds = 0,
    [Alias('schedule')]
    [string]$ScheduleAt = '',
    [string]$IcsPath = '',
    [string]$LastLightSequence = ''
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Global hotkey - C# 5 only (no ?. / async); Add-Type must not crash the app
$script:GlobalHotKeyReady = $false
function Initialize-GlobalHotKeyType {
    if ($script:GlobalHotKeyReady) { return $true }
    $existing = [Type]::GetType('GlobalHotKey', $false)
    if ($existing) { $script:GlobalHotKeyReady = $true; return $true }
    try {
        Add-Type -Language CSharp -ReferencedAssemblies System.Windows.Forms @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class GlobalHotKey : NativeWindow, IDisposable {
    public event EventHandler HotKeyPressed;
    const int WM_HOTKEY = 0x0312;
    readonly int _id;
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    public GlobalHotKey(IntPtr handle, int hotkeyId, uint mod, uint key) {
        _id = hotkeyId;
        AssignHandle(handle);
        if (!RegisterHotKey(handle, hotkeyId, mod, key))
            throw new InvalidOperationException("RegisterHotKey failed");
    }
    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_HOTKEY && m.WParam.ToInt32() == _id) {
            if (HotKeyPressed != null) { HotKeyPressed(this, EventArgs.Empty); }
            return;
        }
        base.WndProc(ref m);
    }
    public void Dispose() {
        UnregisterHotKey(Handle, _id);
        ReleaseHandle();
    }
}
'@
        $script:GlobalHotKeyReady = $true
        return $true
    } catch {
        return $false
    }
}
Initialize-GlobalHotKeyType | Out-Null

$script:AppVersion = '5.3.0'
$script:AppName = 'Lights Out'
$script:SettingsDir = Join-Path $env:LOCALAPPDATA 'CoolTimer'
$script:SettingsPath = Join-Path $script:SettingsDir 'settings.json'
$script:AuditLogPath = Join-Path $script:SettingsDir 'actions.log'
$script:MinTimerSec = 60
$script:PowerFailsafeMinSec = 120
$script:PowerFailsafeMaxSec = 300
$script:DefaultSec = 1700
$script:Action = 'Shutdown'
$script:Total = 0
$script:Left = 0
$script:Running = $false
$script:Paused = $false
$script:Warn5 = $false
$script:Warn60 = $false
$script:Warn30 = $false
$script:PulsePhase = 0.0
$script:BreathPhase = 0.0
if ($env:SLEEPTIMER_SECONDS) { $Seconds = [int]$env:SLEEPTIMER_SECONDS }
if ($env:SLEEPTIMER_MINUTES) { $Minutes = [int]$env:SLEEPTIMER_MINUTES }
if ($env:SLEEPTIMER_ACTION) { $Action = [string]$env:SLEEPTIMER_ACTION }
if ($env:SLEEPTIMER_MINIMIZED -eq '1') { $Minimized = $true }
if ($env:SLEEPTIMER_NO_AUTOSTART -eq '1') { $NoAutoStart = $true }
if ($env:SLEEPTIMER_START -eq '1') { $Start = $true; $NoAutoStart = $false }
if ($env:SLEEPTIMER_AT) { $ScheduleAt = [string]$env:SLEEPTIMER_AT }
if ($env:SLEEPTIMER_CALENDAR) { $script:CliCalendar = [string]$env:SLEEPTIMER_CALENDAR }
if ($IcsPath) { $script:CliCalendar = $IcsPath }

function Get-AppDir {
    if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'modules'))) { return $PSScriptRoot }
    if ($PSScriptRoot) {
        $parentRoot = Split-Path $PSScriptRoot -Parent
        if ($parentRoot -and (Test-Path (Join-Path $parentRoot 'modules'))) { return $parentRoot }
    }
    if ($PSCommandPath) {
        $cmdDir = Split-Path $PSCommandPath -Parent
        if ($cmdDir -and (Test-Path (Join-Path $cmdDir 'modules'))) { return $cmdDir }
        if ($cmdDir) {
            $cmdParent = Split-Path $cmdDir -Parent
            if ($cmdParent -and (Test-Path (Join-Path $cmdParent 'modules'))) { return $cmdParent }
        }
    }
    try {
        $exeDir = Split-Path ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) -Parent
        if ($exeDir) { return $exeDir }
    } catch { }
    if ($PSScriptRoot) { return $PSScriptRoot }
    if ($PSCommandPath) { return Split-Path $PSCommandPath -Parent }
    return $env:USERPROFILE
}
$modRoot = Get-AppDir
foreach ($modName in @('LightsOut.Calendar.psm1', 'LightsOut.Novel.psm1', 'LightsOut.Profiles.psm1', 'LightsOut.LastLight.psm1', 'LightsOut.TonightCards.psm1', 'LightsOut.SteamTheme.psm1', 'LightsOut.Demo.psm1', 'LightsOut.SmartLights.psm1')) {
    $modPath = Join-Path $modRoot "modules\$modName"
    if (-not (Test-Path $modPath)) { continue }
    $prevWarn = $WarningPreference
    $WarningPreference = 'SilentlyContinue'
    Import-Module $modPath -Force -ErrorAction SilentlyContinue
    $WarningPreference = $prevWarn
}

$script:DebugLogPath = Join-Path $modRoot 'lightsout-debug.log'
function Write-LightsOutDebugLog {
    param(
        [string]$Stage,
        $ErrorRecord = $null
    )
    if ($env:LIGHTSOUT_DEBUG -ne '1') { return }
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
    $lines = @("[$stamp] $Stage")
    if ($ErrorRecord) {
        $lines += "  Message: $($ErrorRecord.Exception.Message)"
        if ($ErrorRecord.InvocationInfo) {
            $lines += "  At: $($ErrorRecord.InvocationInfo.PositionMessage)"
        }
        if ($ErrorRecord.ScriptStackTrace) {
            $lines += "  Stack: $($ErrorRecord.ScriptStackTrace)"
        }
    }
    Add-Content -Path $script:DebugLogPath -Value $lines
}
if ($env:LIGHTSOUT_DEBUG -eq '1') {
    trap {
        Write-LightsOutDebugLog 'Trap' $_
        continue
    }
}

function Normalize-ActionName {
    param([string]$Raw)
    if (-not $Raw) { return $null }
    switch ($Raw.Trim().ToLower()) {
        'shutdown' { return 'Shutdown' }
        'shut' { return 'Shutdown' }
        'sleep' { return 'Sleep' }
        'restart' { return 'Restart' }
        'reboot' { return 'Restart' }
        'hibernate' { return 'Hibernate' }
        'hib' { return 'Hibernate' }
        'lock' { return 'Lock' }
        default { return $null }
    }
}

function Show-CliHelp {
    $msg = @"
Lights Out v$script:AppVersion

Examples:
  SleepTimer.exe -Minutes 28 -Action Shutdown -Start
  SleepTimer.exe -DryRun -NoAutoStart
  SleepTimer.exe -Demo -NoAutoStart
  SleepTimer.exe -Demo -Seconds 90 -Start
  SleepTimer.exe -Demo -LastLightSequence ExitTheGrid

-Minutes, /minutes     Countdown length in minutes
-Seconds, /seconds     Countdown length in seconds
-Action, /action       shutdown | sleep | restart | hibernate | lock
-Start, /start          Start countdown immediately on launch
-NoAutoStart            Never auto-start (overrides settings)
-Minimized, /min         Start minimized to tray
-DryRun                 Safe mode - no power action
-Demo                   Marketing preview (implies DryRun; lobby-first)
-ClassicUi, -Simple     Original timer layout (ring + minutes + START)
-ForceShutdown, -Force  Force shutdown/restart (closes blocking apps)
-LastLightSequence      Last Light sequence id (ClassicFade, ExitTheGrid, ...)
-Help, /help            Show this help
-ScheduleAt, /at        Time or date+time (23:30, 2026-06-15 23:30)
-Calendar, /calendar     Path to .ics file (Google/Outlook/Apple export)

Graceful exit (default on): lets apps save before shutdown.
Emergency cancel: Ctrl+Shift+S (press twice if >1 min left)
Snooze / control (global, works from tray):
  Ctrl+Alt+5   +5 minutes
  Ctrl+Alt+0   +10 minutes
  Ctrl+Alt+P   pause / resume
  Ctrl+Alt+L   show window
"@
    [System.Windows.Forms.MessageBox]::Show($msg, $script:AppName, 'OK', 'Information') | Out-Null
}

function Apply-StartupArguments {
    for ($i = 0; $i -lt $args.Count; $i++) {
        $tok = [string]$args[$i]
        $next = if ($i + 1 -lt $args.Count) { [string]$args[$i + 1] } else { $null }
        $hasNext = ($null -ne $next) -and ($next -notmatch '^(/|-)')
        switch -Regex ($tok) {
            '^(/|-)(help|\?|h)$' { $script:CliHelp = $true; continue }
            '^(/|-)(minutes|mins|m)$' { if ($hasNext) { $script:CliMinutes = [int]$next; $i++ }; continue }
            '^(/|-)(seconds|sec|s)$' { if ($hasNext) { $script:CliSeconds = [int]$next; $i++ }; continue }
            '^(/|-)(action|a)$' { if ($hasNext) { $script:CliAction = $next; $i++ }; continue }
            '^(/|-)(start)$' { $script:CliStart = $true; continue }
            '^(/|-)(no(start)?|wait)$' { $script:CliNoStart = $true; continue }
            '^(/|-)(minimized|min|tray)$' { $script:CliMinimized = $true; continue }
            '^(/|-)(dryrun|dry-run)$' { $script:CliDryRun = $true; continue }
            '^(/|-)(demo)$' { $script:CliDemo = $true; continue }
            '^(/|-)(lastlightsequence|last-light|lastlight)$' { if ($hasNext) { $script:CliLastLightSequence = $next; $i++ }; continue }
            '^(/|-)(at|time)$' { if ($hasNext) { $script:CliAt = $next; $i++ }; continue }
            '^(/|-)(calendar|ics)$' { if ($hasNext) { $script:CliCalendar = $next; $i++ }; continue }
            '^(/|-)(classicui|classic|simple)$' { $script:CliClassicUi = $true; continue }
            '^(/|-)(steamui|steam)$' { $script:CliSteamUi = $true; continue }
            '^(/|-)(forceshutdown|force)$' { $script:CliForceShutdown = $true; continue }
        }
    }
}

$script:CliHelp = $false
$script:CliMinutes = 0
$script:CliSeconds = 0
$script:CliAction = $null
$script:CliStart = $false
$script:CliNoStart = $false
$script:CliMinimized = $false
$script:CliDryRun = $false
$script:CliDemo = $false
$script:CliLastLightSequence = $null
$script:CliAt = $null
$script:CliCalendar = $null
$script:CliClassicUi = $false
$script:CliSteamUi = $false
$script:CliForceShutdown = $false
$script:ScheduledAt = $null
$script:CalendarSource = ''
$script:CalendarEventUid = ''
$script:CalendarEventTitle = ''
$script:PactBreaks = 0
$script:PactSnoozeLocked = $false
$script:HouseholdPartner = $null
$script:DimPhaseSec = 90
Apply-StartupArguments

if ($Help -or $script:CliHelp) { Show-CliHelp; return }
if ($script:CliClassicUi) { $ClassicUi = $true }
if ($script:CliSteamUi) { $SteamUi = $true }
if ($ForceShutdown -or $script:CliForceShutdown) { $ForceShutdown = $true }
$script:ForceShutdownRequested = [bool]$ForceShutdown
if ($Simple) { $ClassicUi = $true }
if ($Start -or $script:CliStart) { $NoAutoStart = $false }
if ($script:CliNoStart) { $NoAutoStart = $true }
if ($Minimized -or $script:CliMinimized) { $Minimized = $true }
$script:DemoMode = $Demo -or $script:CliDemo -or ($env:SLEEPTIMER_DEMO -eq '1')
$script:DemoProofDismissed = [bool]$script:DemoMode
$script:DryRun = $DryRun -or $script:CliDryRun -or $script:DemoMode -or ($env:SLEEPTIMER_DRY_RUN -eq '1') -or ($env:SLEEPTIMER_CI -eq '1')
if ($script:DemoMode) {
    $script:DryRun = $true
    $hasStartupDuration = ($Minutes -gt 0) -or ($Seconds -gt 0) -or ($script:CliMinutes -gt 0) -or ($script:CliSeconds -gt 0)
    if (-not ($Start -or $script:CliStart) -and -not $hasStartupDuration) {
        $NoAutoStart = $true
    }
}
if ($Minutes -gt 0) { $script:CliMinutes = $Minutes }
if ($Seconds -gt 0) { $script:CliSeconds = $Seconds }
if ($Action) { $script:CliAction = $Action }
if ($ScheduleAt) { $script:CliAt = $ScheduleAt }
if ($LastLightSequence) { $script:CliLastLightSequence = $LastLightSequence }

function Parse-ClockTime {
    param([string]$Raw)
    if (-not $Raw) { return $null }
    $Raw = $Raw.Trim()
    foreach ($fmt in @('HH:mm', 'H:mm', 'h:mm tt', 'hh:mm tt')) {
        try {
            $dt = [DateTime]::ParseExact($Raw, $fmt, [System.Globalization.CultureInfo]::InvariantCulture)
            return $dt.ToString('HH:mm')
        } catch { }
    }
    try {
        return ([DateTime]::Parse($Raw)).ToString('HH:mm')
    } catch {
        return $null
    }
}

function Parse-ScheduleDateTime {
    param([string]$Raw)
    if (-not $Raw) { return $null }
    $Raw = $Raw.Trim()
    if ($Raw -match '^\d{1,2}:\d{2}') { return $null }
    $formats = @(
        'yyyy-MM-dd HH:mm',
        'yyyy-MM-ddTHH:mm',
        'yyyy-MM-dd HH:mm:ss',
        'MM/dd/yyyy h:mm tt',
        'M/d/yyyy h:mm tt',
        'dd/MM/yyyy HH:mm'
    )
    foreach ($fmt in $formats) {
        try {
            return [DateTime]::ParseExact($Raw, $fmt, [System.Globalization.CultureInfo]::CurrentCulture)
        } catch { }
    }
    try { return [DateTime]::Parse($Raw) } catch { return $null }
}

function Sync-ScheduledFromPickers {
    if ($script:TimerMode -ne 'calendar') { return }
    if (-not $script:dtpDate -or -not $script:dtpClock) { return }
    $d = $script:dtpDate.Value.Date
    $t = $script:dtpClock.Value
    $script:ScheduledAt = $d.AddHours($t.Hour).AddMinutes($t.Minute).AddSeconds(0)
    $script:ClockTime = $script:dtpClock.Value.ToString('HH:mm')
}

function Set-ScheduledTarget {
    param(
        [DateTime]$When,
        [string]$Title = '',
        [string]$Uid = '',
        [string]$SourcePath = ''
    )
    $script:ScheduledAt = $When
    $script:CalendarEventTitle = $Title
    $script:CalendarEventUid = $Uid
    if ($SourcePath) { $script:CalendarSource = $SourcePath }
    if ($script:UiReady -and $script:dtpDate -and $script:dtpClock) {
        $script:dtpDate.Value = $When
        $script:dtpClock.Value = $When
        $script:ClockTime = $When.ToString('HH:mm')
    }
    Set-TimerMode 'calendar'
    if ($script:UiReady) { Update-CalendarEventLabel }
}

function Get-ClockTargetDateTime {
    param([string]$TimeStr)
    if ($script:TimerMode -eq 'calendar' -and $script:ScheduledAt) {
        $t = [DateTime]$script:ScheduledAt
        if ($t -gt (Get-Date)) { return $t }
    }
    $hm = if ($TimeStr) { Parse-ClockTime $TimeStr }
          elseif ($script:ClockTime) { $script:ClockTime }
          elseif ($script:UiReady -and $script:dtpClock) { $script:dtpClock.Value.ToString('HH:mm') }
          else { '23:30' }
    if (-not $hm) { $hm = '23:30' }
    $parts = $hm.Split(':')
    $h = [int]$parts[0]
    $m = [int]$parts[1]
    $now = Get-Date
    $target = Get-Date -Year $now.Year -Month $now.Month -Day $now.Day -Hour $h -Minute $m -Second 0
    if ($target -le $now) { $target = $target.AddDays(1) }
    return $target
}

function Get-SecondsUntilClock {
    param([string]$TimeStr)
    $target = Get-ClockTargetDateTime $TimeStr
    $sec = [int][math]::Ceiling(($target - (Get-Date)).TotalSeconds)
    return [math]::Max((Get-MinTimerSec), $sec)
}

function Format-ClockDisplay {
    param([DateTime]$When)
    if ($script:TimerMode -eq 'calendar') {
        return $When.ToString('ddd MMM d, h:mm tt')
    }
    return $When.ToString('h:mm tt')
}

function Get-RingTargetDateTime {
    if ($script:TimerMode -in @('clock', 'calendar')) {
        return Get-ClockTargetDateTime
    }
    $sec = if ($script:Running -or $script:Paused) { $script:Left } else { $script:DefaultSec }
    return (Get-Date).AddSeconds([math]::Max(0, $sec))
}

function Get-ClockHandAngleRad {
    param([DateTime]$When)
    $deg = (($When.Hour % 12) * 30.0) + ($When.Minute * 0.5) + ($When.Second / 120.0) - 90.0
    return $deg * [math]::PI / 180.0
}

function Format-RingEndSubtitle {
    param([int]$SecondsFromNow)
    if ($script:TimerMode -in @('clock', 'calendar')) {
        return "At $(Format-ClockDisplay (Get-ClockTargetDateTime))"
    }
    return "Ends about $(Format-EndClock $SecondsFromNow)"
}

function Show-CalendarEventDialog {
    if (-not (Get-Command Import-IcsCalendarFile -ErrorAction SilentlyContinue)) {
        [System.Windows.Forms.MessageBox]::Show(
            'Calendar module not found. Run from the Lights Out folder or reinstall.',
            $script:AppName, 'OK', 'Error') | Out-Null
        return $false
    }
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = 'Import calendar (.ics)'
    $dlg.Filter = 'iCalendar (*.ics)|*.ics|All files (*.*)|*.*'
    $last = if ($script:CalendarSource) { Split-Path $script:CalendarSource -Parent } else { [Environment]::GetFolderPath('MyDocuments') }
    if ($last -and (Test-Path $last)) { $dlg.InitialDirectory = $last }
    if ($dlg.ShowDialog() -ne 'OK') { return $false }

    try {
        $imported = Import-IcsCalendarFile -Path $dlg.FileName
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, $script:AppName, 'OK', 'Error') | Out-Null
        return $false
    }

    $upcoming = Get-IcsUpcomingEvents -Events $imported.Events
    if (-not $upcoming.Count) {
        [System.Windows.Forms.MessageBox]::Show(
            'No upcoming events in the next 90 days. Export a fresh .ics from your calendar app.',
            $script:AppName, 'OK', 'Information') | Out-Null
        return $false
    }

    $pick = New-Object System.Windows.Forms.Form
    $pick.Text = "$script:AppName - pick calendar event"
    $pick.Size = New-Object System.Drawing.Size(520, 380)
    $pick.StartPosition = 'CenterParent'
    $pick.FormBorderStyle = 'FixedDialog'
    $pick.MaximizeBox = $false
    $pick.MinimizeBox = $false
    $pick.BackColor = Get-UiColor 'Bg' ([System.Drawing.Color]::FromArgb(27, 40, 56))

    $hint = New-Object System.Windows.Forms.Label
    $hint.Location = New-Object System.Drawing.Point(12, 10)
    $hint.Size = New-Object System.Drawing.Size(480, 36)
    $hint.Text = "From: $([IO.Path]::GetFileName($dlg.FileName))`nSelect an event - Lights Out will $($script:Action.ToLower()) at that date and time."
    $hint.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
    $hint.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $pick.Controls.Add($hint)

    $list = New-Object System.Windows.Forms.ListView
    $list.Location = New-Object System.Drawing.Point(12, 52)
    $list.Size = New-Object System.Drawing.Size(480, 230)
    $list.View = 'Details'
    $list.FullRowSelect = $true
    $list.GridLines = $false
    $list.BackColor = Get-UiColor 'Card' ([System.Drawing.Color]::FromArgb(22, 32, 45))
    $list.ForeColor = Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
    $list.BorderStyle = 'FixedSingle'
    [void]$list.Columns.Add('When', 160)
    [void]$list.Columns.Add('Event', 300)
    foreach ($ev in $upcoming) {
        $li = New-Object System.Windows.Forms.ListViewItem ($ev.Start.ToString('ddd MMM d, h:mm tt'))
        $li.SubItems.Add($ev.Summary) | Out-Null
        $li.Tag = $ev
        [void]$list.Items.Add($li)
    }
    if ($list.Items.Count -gt 0) { $list.Items[0].Selected = $true }
    $pick.Controls.Add($list)

    $script:calendarPickResult = $null
    $okPick = {
        if ($list.SelectedItems.Count -lt 1) { return }
        $script:calendarPickResult = $list.SelectedItems[0].Tag
        $pick.DialogResult = 'OK'
        $pick.Close()
    }.GetNewClosure()

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = 'Use this event'
    $btnOk.Size = New-Object System.Drawing.Size(140, 36)
    $btnOk.Location = New-Object System.Drawing.Point(232, 292)
    Style-Button $btnOk $script:C.Amber ([System.Drawing.Color]::FromArgb(18, 14, 8)) 9
    $btnOk.Add_Click($okPick)
    $pick.Controls.Add($btnOk)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = 'Cancel'
    $btnCancel.Size = New-Object System.Drawing.Size(100, 36)
    $btnCancel.Location = New-Object System.Drawing.Point(380, 292)
    Style-Button $btnCancel ([System.Drawing.Color]::FromArgb(36, 36, 50)) $script:C.Ink 9
    $btnCancel.Add_Click({ $pick.Close() })
    $pick.Controls.Add($btnCancel)

    $list.Add_DoubleClick($okPick)
    [void]$pick.ShowDialog($form)
    if (-not $script:calendarPickResult) { return $false }

    $ev = $script:calendarPickResult
    Set-ScheduledTarget -When $ev.Start -Title $ev.Summary -Uid $ev.Uid -SourcePath $dlg.FileName
    Write-AuditLog 'calendar_event' "$($ev.Summary) at $($ev.Start.ToString('o'))"
    if (-not $script:Running) { Save-Settings; Update-Ui }
    return $true
}

function Get-CurrentTimerSnapshot {
    return [pscustomobject]@{
        Action             = $script:Action
        Mode               = $script:TimerMode
        Seconds            = $script:DefaultSec
        Clock              = $script:ClockTime
        ScheduledAt        = if ($script:ScheduledAt) { ([DateTime]$script:ScheduledAt).ToString('o') } else { '' }
        CalendarSource     = $script:CalendarSource
        CalendarEventUid   = $script:CalendarEventUid
        CalendarEventTitle = $script:CalendarEventTitle
        AutoStart          = $true
    }
}

function Invoke-TimerProfile {
    param(
        $Profile,
        [switch]$StartNow
    )
    if (-not $Profile) { return }
    $p = if (Get-Command Normalize-TimerProfile -ErrorAction SilentlyContinue) {
        Normalize-TimerProfile $Profile
    } else { $Profile }
    if (-not $p) { return }
    Set-Action $p.Action
    $ritualIds = @('weeknight', 'classic', 'movie', 'bedtime')
    if ($p.Id -in $ritualIds) {
        $script:LastRitualId = $p.Id
        $script:LastProfileId = ''
    } else {
        $script:LastProfileId = $p.Id
        $script:LastRitualId = ''
    }
    switch ($p.Mode) {
        'clock' {
            Set-TimerMode 'clock'
            $script:ClockTime = $p.Clock
            if ($script:UiReady -and $script:dtpClock) {
                $parts = $script:ClockTime.Split(':')
                $script:dtpClock.Value = Get-Date -Hour ([int]$parts[0]) -Minute ([int]$parts[1]) -Second 0
            }
        }
        'calendar' {
            if ($p.ScheduledAt) {
                try {
                    Set-ScheduledTarget -When ([DateTime]::Parse($p.ScheduledAt)) `
                        -Title $p.CalendarEventTitle -Uid $p.CalendarEventUid -SourcePath $p.CalendarSource
                } catch {
                    Set-TimerMode 'calendar'
                }
            } else {
                Set-TimerMode 'calendar'
            }
        }
        default {
            Set-TimerMode 'duration'
            $script:DefaultSec = [math]::Max((Get-MinTimerSec), [int]$p.Seconds)
        }
    }
    Write-AuditLog 'profile_applied' "$($p.Name) mode=$($p.Mode) action=$($p.Action)"
    if ($script:Running) {
        if ($p.Mode -eq 'duration') {
            $script:Left = [int]$p.Seconds
            $script:Total = [int]$p.Seconds
            $script:Warn5 = $false
            $script:Warn60 = $false
            $script:Warn30 = $false
        }
        Save-Settings
        Update-Ui
        return
    }
    if ($script:Paused) { Cancel-PausedTimer }
    Save-Settings
    Update-Ui
    if ($StartNow -or $p.AutoStart) { Invoke-StartTimer (Get-StartSeconds) }
}

function Sync-LobbyMinutesControl {
    if (-not $script:numLobbyMin) { return }
    if ($script:numLobbyMin.IsDisposed) { return }
    if ($script:ApplyingLobbyMin) { return }
    $script:ApplyingLobbyMin = $true
    try {
        $min = [math]::Max(1, [math]::Round($script:DefaultSec / 60.0))
        $min = [math]::Min([int]$script:numLobbyMin.Maximum, [math]::Max([int]$script:numLobbyMin.Minimum, $min))
        if ([int]$script:numLobbyMin.Value -ne $min) { $script:numLobbyMin.Value = $min }
    } finally {
        $script:ApplyingLobbyMin = $false
    }
}

function Set-TimerMinutes {
    param([int]$Minutes)
    $sec = [math]::Max((Get-MinTimerSec), ($Minutes * 60))
    $script:DefaultSec = $sec
    $script:LastRitualId = ''
    Mark-TonightCardCustom
    if ($script:Running) {
        $script:Left = $sec
        $script:Total = $sec
        $script:Warn5 = $false
        $script:Warn60 = $false
        $script:Warn30 = $false
    }
    Sync-LobbyMinutesControl
    Update-PresetHighlight
    Update-LobbyQuickHighlight
    if (-not $script:Running -and $script:UiReady) { Save-Settings }
    Update-Ui
}

function Update-ScheduleSectionLayout {
    if (-not $script:pnlSchedule) { return }
    $hasProfiles = @($script:SavedTimers).Count -gt 0
    if ($script:lblMyTimers) { $script:lblMyTimers.Visible = $hasProfiles }
    if ($script:pnlMyTimers) { $script:pnlMyTimers.Visible = $hasProfiles }
    if ($script:btnEditProfiles) { $script:btnEditProfiles.Visible = $hasProfiles }
    if ($script:btnSaveProfile) {
        $saveY = if ($script:UseSteamUi) { 170 } else { if ($hasProfiles) { 132 } else { 80 } }
        if ($hasProfiles) {
            $script:btnSaveProfile.Location = New-Object System.Drawing.Point(280, $saveY)
        } else {
            $script:btnSaveProfile.Location = New-Object System.Drawing.Point(($script:contentW - 66), $(if ($script:UseSteamUi) { 170 } else { 80 }))
        }
    }
    $cardExtra = if ($script:UseSteamUi) { 130 } else { 0 }
    $h = if ($hasProfiles) { 192 + $cardExtra } else { 176 + $cardExtra }
    if ($script:ySchedule -eq $h) { return }
    $script:ySchedule = $h
    $script:pnlSchedule.Height = $h
    $delta = (192 + $cardExtra) - $h
    $steamOff = if ($script:UseSteamUi) { 50 } else { 0 }
    $cardY = 550 + $steamOff + $script:yBoost + $script:yNovel - $delta
    $calY = 530 + $steamOff + $script:yBoost - $delta
    if ($script:pnlCard) { $script:pnlCard.Location = New-Object System.Drawing.Point(20, $cardY) }
    if ($script:lblCalEvent) { $script:lblCalEvent.Location = New-Object System.Drawing.Point(24, $calY) }
    $profileY = if ($script:UseSteamUi) { 90 } else { 0 }
    if ($script:lblMyTimers) { $script:lblMyTimers.Location = New-Object System.Drawing.Point(8, (136 + $profileY)) }
    if ($script:btnEditProfiles) { $script:btnEditProfiles.Location = New-Object System.Drawing.Point(342, (132 + $profileY)) }
    if ($script:pnlMyTimers) { $script:pnlMyTimers.Location = New-Object System.Drawing.Point(8, (154 + $profileY)) }
    $steamOff2 = if ($script:UseSteamUi) { 50 } else { 0 }
    $formH = 606 + $steamOff2 + $script:yBoost + $script:yCal + $script:yNovel + $script:ySchedule + $script:formExtraH - $script:yCardSave
    if ($form -and $form.Height -ne $formH) { $form.Height = $formH }
}

function Update-MyTimersPanel {
    if (-not $script:pnlMyTimers) { return }
    $pnl = $script:pnlMyTimers
    $pnl.Controls.Clear()
    $script:MyTimerBtns = @()
    $profiles = @($script:SavedTimers)
    if (-not $profiles.Count) {
        Update-ScheduleSectionLayout
        return
    }
    foreach ($prof in ($profiles | Select-Object -First 6)) {
        $pb = New-Object System.Windows.Forms.Button
        $label = if ($prof.Name.Length -gt 14) { $prof.Name.Substring(0, 12) + '..' } else { $prof.Name }
        $pb.Text = $label
        $pb.Tag = $prof
        $pb.Size = New-Object System.Drawing.Size(88, 30)
        $pb.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
        $profCopy = $prof
        $hi = ($prof.Id -eq $script:LastProfileId)
        if ($hi) {
            Style-Button $pb $script:C.Mint ([System.Drawing.Color]::FromArgb(12, 18, 16)) 8 ([System.Drawing.Color]::FromArgb(120, 220, 180))
        } else {
            Style-Button $pb ([System.Drawing.Color]::FromArgb(28, 30, 42)) $script:C.Ink 8 ([System.Drawing.Color]::FromArgb(42, 44, 58))
        }
        if ($script:uiToolTip) {
            $hint = if (Get-Command Get-TimerProfileHint -ErrorAction SilentlyContinue) {
                Get-TimerProfileHint $prof
            } else { $prof.Name }
            $script:uiToolTip.SetToolTip($pb, $hint)
        }
        $pb.Add_Click({ Invoke-TimerProfile $profCopy -StartNow })
        $pnl.Controls.Add($pb)
        $script:MyTimerBtns += $pb
    }
    Update-ScheduleSectionLayout
}

function Show-SaveTimerProfileDialog {
    if (-not (Get-Command Normalize-TimerProfile -ErrorAction SilentlyContinue)) {
        [System.Windows.Forms.MessageBox]::Show('Profiles module not found.', $script:AppName, 'OK', 'Error') | Out-Null
        return
    }
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "$script:AppName - save timer"
    $dlg.Size = New-Object System.Drawing.Size(400, 220)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.BackColor = Get-UiColor 'Bg' ([System.Drawing.Color]::FromArgb(27, 40, 56))

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Location = New-Object System.Drawing.Point(16, 16)
    $lbl.Size = New-Object System.Drawing.Size(360, 40)
    $lbl.Text = "Save current setup ($($script:Action), $($script:TimerMode) mode) as a one-tap timer:"
    $lbl.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
    $dlg.Controls.Add($lbl)

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Location = New-Object System.Drawing.Point(16, 62)
    $tb.Size = New-Object System.Drawing.Size(360, 28)
    $tb.Text = switch ($script:TimerMode) {
        'clock' { "At $($script:ClockTime)" }
        'calendar' {
            if ($script:CalendarEventTitle) { $script:CalendarEventTitle } else { 'Calendar timer' }
        }
        default { "$(Format-DurationLong $script:DefaultSec) $($script:Action)" }
    }
    $dlg.Controls.Add($tb)

    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Text = 'Start immediately when tapped'
    $chk.Location = New-Object System.Drawing.Point(16, 98)
    $chk.Checked = $true
    $chk.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
    $chk.BackColor = Get-UiColor 'Bg' ([System.Drawing.Color]::FromArgb(27, 40, 56))
    $dlg.Controls.Add($chk)

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = 'Save'
    $btnOk.Location = New-Object System.Drawing.Point(176, 132)
    $btnOk.Size = New-Object System.Drawing.Size(90, 32)
    Style-Button $btnOk $script:C.Amber ([System.Drawing.Color]::FromArgb(18, 14, 8)) 9
    $btnOk.Add_Click({
        $snap = Get-CurrentTimerSnapshot
        $snap.Name = $tb.Text.Trim()
        $snap.AutoStart = $chk.Checked
        $norm = Normalize-TimerProfile $snap
        if (-not $norm) {
            [System.Windows.Forms.MessageBox]::Show('Enter a name.', $script:AppName, 'OK', 'Warning') | Out-Null
            return
        }
        $list = [System.Collections.Generic.List[object]]::new()
        foreach ($x in @($script:SavedTimers)) { $list.Add($x) }
        $list.Add($norm)
        if ($list.Count -gt 24) {
            [System.Windows.Forms.MessageBox]::Show('Max 24 saved timers. Remove one in Edit.', $script:AppName, 'OK', 'Warning') | Out-Null
            return
        }
        $script:SavedTimers = @($list)
        $script:LastProfileId = $norm.Id
        Save-Settings
        Update-MyTimersPanel
        Write-AuditLog 'profile_saved' $norm.Name
        $dlg.Close()
    })
    $dlg.Controls.Add($btnOk)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = 'Cancel'
    $btnCancel.Location = New-Object System.Drawing.Point(276, 132)
    $btnCancel.Size = New-Object System.Drawing.Size(90, 32)
    Style-Button $btnCancel ([System.Drawing.Color]::FromArgb(36, 36, 50)) $script:C.Ink 9
    $btnCancel.Add_Click({ $dlg.Close() })
    $dlg.Controls.Add($btnCancel)

    [void]$dlg.ShowDialog($form)
}

function Show-ManageTimerProfilesDialog {
    if (-not @($script:SavedTimers).Count) {
        [System.Windows.Forms.MessageBox]::Show('No saved timers yet. Use + Save first.', $script:AppName, 'OK', 'Information') | Out-Null
        return
    }
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "$script:AppName - my timers"
    $dlg.Size = New-Object System.Drawing.Size(480, 360)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.BackColor = Get-UiColor 'Bg' ([System.Drawing.Color]::FromArgb(27, 40, 56))

    $list = New-Object System.Windows.Forms.ListView
    $list.Location = New-Object System.Drawing.Point(12, 12)
    $list.Size = New-Object System.Drawing.Size(450, 250)
    $list.View = 'Details'
    $list.FullRowSelect = $true
    $list.BackColor = Get-UiColor 'Card' ([System.Drawing.Color]::FromArgb(22, 32, 45))
    $list.ForeColor = Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
    [void]$list.Columns.Add('Name', 140)
    [void]$list.Columns.Add('Details', 290)
    foreach ($prof in @($script:SavedTimers)) {
        $li = New-Object System.Windows.Forms.ListViewItem ($prof.Name)
        $li.SubItems.Add((Get-TimerProfileHint $prof)) | Out-Null
        $li.Tag = $prof
        [void]$list.Items.Add($li)
    }
    $dlg.Controls.Add($list)

    $btnDel = New-Object System.Windows.Forms.Button
    $btnDel.Text = 'Delete'
    $btnDel.Location = New-Object System.Drawing.Point(12, 272)
    $btnDel.Size = New-Object System.Drawing.Size(90, 32)
    Style-Button $btnDel ([System.Drawing.Color]::FromArgb(48, 28, 32)) $script:C.Ink 9
    $btnDel.Add_Click({
        if ($list.SelectedItems.Count -lt 1) { return }
        $id = $list.SelectedItems[0].Tag.Id
        $script:SavedTimers = @($script:SavedTimers | Where-Object { $_.Id -ne $id })
        if ($script:LastProfileId -eq $id) { $script:LastProfileId = '' }
        Save-Settings
        Update-MyTimersPanel
        $dlg.Close()
        Show-ManageTimerProfilesDialog
    })
    $dlg.Controls.Add($btnDel)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = 'Close'
    $btnClose.Location = New-Object System.Drawing.Point(372, 272)
    $btnClose.Size = New-Object System.Drawing.Size(90, 32)
    Style-Button $btnClose ([System.Drawing.Color]::FromArgb(36, 36, 50)) $script:C.Ink 9
    $btnClose.Add_Click({ $dlg.Close() })
    $dlg.Controls.Add($btnClose)

    [void]$dlg.ShowDialog($form)
}

function Update-CalendarEventLabel {
    if (-not $script:lblCalEvent) { return }
    if ($script:CalendarFeedUrl) {
        $feed = 'Live calendar feed'
        if ($script:CalendarFeedLastSync) {
            try {
                $ls = [DateTime]::Parse($script:CalendarFeedLastSync)
                $feed += " - synced $($ls.ToString('h:mm tt'))"
            } catch { }
        }
        $script:lblCalEvent.Text = $feed
        $script:lblCalEvent.ForeColor = Get-UiColor 'Mint' ([System.Drawing.Color]::FromArgb(102, 192, 244))
        $script:lblCalEvent.Visible = ($script:TimerMode -eq 'calendar')
        return
    }
    $script:lblCalEvent.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
    if ($script:CalendarEventTitle -and $script:ScheduledAt) {
        $script:lblCalEvent.Text = "$($script:CalendarEventTitle) - $([DateTime]$script:ScheduledAt.ToString('ddd MMM d, h:mm tt'))"
        $script:lblCalEvent.Visible = ($script:TimerMode -eq 'calendar')
    } elseif ($script:TimerMode -eq 'calendar' -and $script:ScheduledAt) {
        $script:lblCalEvent.Text = "Scheduled - $([DateTime]$script:ScheduledAt.ToString('ddd MMM d, h:mm tt'))"
        $script:lblCalEvent.Visible = $true
    } else {
        $script:lblCalEvent.Text = ''
        $script:lblCalEvent.Visible = $false
    }
}

function Sync-CalendarFeed {
    param([switch]$Quiet)
    if (-not $script:CalendarFeedUrl) { return $false }
    if (-not (Get-Command Import-IcsFromUrl -ErrorAction SilentlyContinue)) { return $false }
    try {
        $imported = Import-IcsFromUrl -Url $script:CalendarFeedUrl
        $next = Get-IcsUpcomingEvents -Events $imported.Events -MaxCount 1
        if (-not $next.Count) {
            if (-not $Quiet) {
                [System.Windows.Forms.MessageBox]::Show(
                    'No upcoming events in feed (next 90 days).',
                    $script:AppName, 'OK', 'Information') | Out-Null
            }
            return $false
        }
        $ev = $next[0]
        Set-ScheduledTarget -When $ev.Start -Title $ev.Summary -Uid $ev.Uid -SourcePath $script:CalendarFeedUrl
        $script:CalendarFeedLastSync = (Get-Date).ToString('o')
        Write-AuditLog 'calendar_feed_sync' "$($ev.Summary) at $($ev.Start.ToString('o'))"
        Save-Settings
        Update-CalendarEventLabel
        Update-Ui
        if ($script:CalendarFeedAutoStart -and -not $script:Running -and -not $script:Paused) {
            Invoke-StartTimer (Get-StartSeconds)
        }
        if (-not $Quiet) {
            $script:tray.ShowBalloonTip(4000, $script:AppName,
                "Next: $($ev.Summary) at $($ev.Start.ToString('h:mm tt'))", 'Info') | Out-Null
        }
        return $true
    } catch {
        Write-AuditLog 'calendar_feed_fail' $_.Exception.Message
        if (-not $Quiet) {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, $script:AppName, 'OK', 'Error') | Out-Null
        }
        return $false
    }
}

function Sync-CalendarFeedIfDue {
    if (-not $script:CalendarFeedUrl) { return }
    $mins = [math]::Max(5, [int]$script:CalendarFeedIntervalMin)
    if ($script:CalendarFeedLastSync) {
        try {
            $last = [DateTime]::Parse($script:CalendarFeedLastSync)
            if ((Get-Date) -lt $last.AddMinutes($mins)) { return }
        } catch { }
    }
    Sync-CalendarFeed -Quiet
}

function Show-CalendarFeedDialog {
    if (-not (Get-Command Test-CalendarFeedUrl -ErrorAction SilentlyContinue)) {
        [System.Windows.Forms.MessageBox]::Show('Calendar module not found.', $script:AppName, 'OK', 'Error') | Out-Null
        return
    }
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "$script:AppName - live calendar feed"
    $dlg.Size = New-Object System.Drawing.Size(520, 320)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.BackColor = Get-UiColor 'Bg' ([System.Drawing.Color]::FromArgb(27, 40, 56))

    $hint = New-Object System.Windows.Forms.Label
    $hint.Location = New-Object System.Drawing.Point(14, 10)
    $hint.Size = New-Object System.Drawing.Size(480, 72)
    $hint.Text = @"
Paste your Google Calendar secret iCal URL (Calendar settings - Integrate calendar - Secret address in iCal format).
Outlook and Apple also provide https subscribe links. Lights Out refreshes the feed and schedules the next event.
"@
    $hint.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
    $dlg.Controls.Add($hint)

    $tbUrl = New-Object System.Windows.Forms.TextBox
    $tbUrl.Location = New-Object System.Drawing.Point(14, 88)
    $tbUrl.Size = New-Object System.Drawing.Size(480, 24)
    $tbUrl.Text = $script:CalendarFeedUrl
    $dlg.Controls.Add($tbUrl)

    $lblMin = New-Object System.Windows.Forms.Label
    $lblMin.Text = 'Refresh every (minutes):'
    $lblMin.Location = New-Object System.Drawing.Point(14, 122)
    $lblMin.AutoSize = $true
    $lblMin.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
    $dlg.Controls.Add($lblMin)

    $numMin = New-Object System.Windows.Forms.NumericUpDown
    $numMin.Location = New-Object System.Drawing.Point(180, 118)
    $numMin.Width = 60
    $numMin.Minimum = 5
    $numMin.Maximum = 240
    $numMin.Value = [math]::Max(5, [int]$script:CalendarFeedIntervalMin)
    $dlg.Controls.Add($numMin)

    $chkAuto = New-Object System.Windows.Forms.CheckBox
    $chkAuto.Text = 'Auto-start timer after each sync'
    $chkAuto.Location = New-Object System.Drawing.Point(14, 150)
    $chkAuto.Checked = $script:CalendarFeedAutoStart
    $chkAuto.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
    $chkAuto.BackColor = Get-UiColor 'Bg' ([System.Drawing.Color]::FromArgb(27, 40, 56))
    $dlg.Controls.Add($chkAuto)

    $btnTest = New-Object System.Windows.Forms.Button
    $btnTest.Text = 'Sync now'
    $btnTest.Location = New-Object System.Drawing.Point(14, 188)
    $btnTest.Size = New-Object System.Drawing.Size(100, 32)
    Style-Button $btnTest $script:C.Mint ([System.Drawing.Color]::FromArgb(12, 18, 16)) 9
    $btnTest.Add_Click({
        $script:CalendarFeedUrl = $tbUrl.Text.Trim()
        $script:CalendarFeedIntervalMin = [int]$numMin.Value
        $script:CalendarFeedAutoStart = $chkAuto.Checked
        Sync-CalendarFeed
    })
    $dlg.Controls.Add($btnTest)

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = 'Save'
    $btnSave.Location = New-Object System.Drawing.Point(300, 188)
    $btnSave.Size = New-Object System.Drawing.Size(90, 32)
    Style-Button $btnSave $script:C.Amber ([System.Drawing.Color]::FromArgb(18, 14, 8)) 9
    $btnSave.Add_Click({
        $url = $tbUrl.Text.Trim()
        if ($url -and -not (Test-CalendarFeedUrl $url)) {
            [System.Windows.Forms.MessageBox]::Show('URL must start with https://', $script:AppName, 'OK', 'Warning') | Out-Null
            return
        }
        $script:CalendarFeedUrl = $url
        $script:CalendarFeedIntervalMin = [int]$numMin.Value
        $script:CalendarFeedAutoStart = $chkAuto.Checked
        Save-Settings
        if ($url) {
            if ($script:feedTimer) { $script:feedTimer.Start() }
            Sync-CalendarFeed -Quiet
        } elseif ($script:feedTimer) { $script:feedTimer.Stop() }
        Update-CalendarEventLabel
        $dlg.Close()
    })
    $dlg.Controls.Add($btnSave)

    $btnClear = New-Object System.Windows.Forms.Button
    $btnClear.Text = 'Clear feed'
    $btnClear.Location = New-Object System.Drawing.Point(400, 188)
    $btnClear.Size = New-Object System.Drawing.Size(90, 32)
    Style-Button $btnClear ([System.Drawing.Color]::FromArgb(36, 36, 50)) $script:C.Ink 9
    $btnClear.Add_Click({
        $script:CalendarFeedUrl = ''
        $script:CalendarFeedLastSync = ''
        Save-Settings
        Update-CalendarEventLabel
        $dlg.Close()
    })
    $dlg.Controls.Add($btnClear)

    [void]$dlg.ShowDialog($form)
}

function Format-DurationLong {
    param([int]$Seconds)
    if ($Seconds -ge 3600) {
        $h = [int][math]::Floor($Seconds / 3600.0)
        $m = [int][math]::Floor(($Seconds % 3600) / 60.0)
        if ($m -eq 0) { return "${h}h" }
        return "${h}h ${m}m"
    }
    $m = [math]::Ceiling($Seconds / 60.0)
    if ($m -le 1) { return 'under a minute' }
    return "$m minutes"
}

function Get-StartSeconds {
    if ($script:TimerMode -in @('clock', 'calendar')) { return Get-SecondsUntilClock }
    return $script:DefaultSec
}

function Get-RitualCatalog {
    if ($script:UseSteamUi -and (Get-Command Get-RitualGameCatalog -ErrorAction SilentlyContinue)) {
        return Get-RitualGameCatalog
    }
    return @(
        @{ Id = 'weeknight'; Label = 'Weeknight'; Hint = '24m off'; Seconds = 1440; Action = 'Shutdown'; Mode = 'duration' }
        @{ Id = 'classic'; Label = '28:20'; Hint = 'shut down'; Seconds = 1700; Action = 'Shutdown'; Mode = 'duration' }
        @{ Id = 'movie'; Label = 'Movie'; Hint = '45m sleep'; Seconds = 2700; Action = 'Sleep'; Mode = 'duration' }
        @{ Id = 'bedtime'; Label = 'Bedtime'; Hint = '11:30 PM'; Action = 'Shutdown'; Mode = 'clock'; Clock = '23:30' }
    )
}

function Show-SessionToast {
    param(
        [string]$Message,
        [System.Windows.Forms.ToolTipIcon]$Icon = 'Info',
        [int]$Ms = 3200
    )
    if (-not $script:tray) { return }
    try {
        $t = $Message
        if ($t.Length -gt 120) { $t = $t.Substring(0, 117) + '...' }
        $script:tray.ShowBalloonTip($Ms, $script:AppName, $t, $Icon)
    } catch { }
}

function Show-AchievementToast {
    param([string]$Title, [string]$Detail)
    Write-AuditLog 'achievement' $Title
    Show-SessionToast "$Title - $Detail" 'Info' 4500
}

function Test-AndCelebrateStreak {
    if (-not (Get-Command Get-SleepLedgerStats -ErrorAction SilentlyContinue)) { return }
    $stats = Get-SleepLedgerStats -AuditLogPath $script:AuditLogPath
    $milestones = @{
        3  = @{ T = '3-Night Streak'; D = 'Three nights in a row. You are building the habit.' }
        7  = @{ T = 'Week Warrior'; D = 'Seven nights straight. Lights Out is your ritual now.' }
        14 = @{ T = 'Fortnight Club'; D = 'Two weeks of discipline. Legendary bedtime energy.' }
        30 = @{ T = 'Monthly Master'; D = 'Thirty nights. You own the night.' }
    }
    foreach ($m in ($milestones.Keys | Sort-Object)) {
        if ($stats.Streak -ge $m -and $script:LastAchievementStreak -lt $m) {
            Show-AchievementToast $milestones[$m].T $milestones[$m].D
            $script:LastAchievementStreak = $m
            if ($script:UiReady) { Save-Settings }
            break
        }
    }
}

function Get-CinemaScreen {
    $screens = [System.Windows.Forms.Screen]::AllScreens
    if ($screens.Count -le 1) { return [System.Windows.Forms.Screen]::PrimaryScreen }
    $idx = $script:CinemaScreenIndex
    if ($idx -ge 0 -and $idx -lt $screens.Count) { return $screens[$idx] }
    return [System.Windows.Forms.Screen]::PrimaryScreen
}

function Get-CinemaScreenChoices {
    $screens = [System.Windows.Forms.Screen]::AllScreens
    $choices = @()
    for ($i = 0; $i -lt $screens.Count; $i++) {
        $s = $screens[$i]
        $primary = if ($s.Primary) { ' (primary)' } else { '' }
        $choices += [pscustomobject]@{
            Index = $i
            Label = "Display $($i + 1): $($s.Bounds.Width)x$($s.Bounds.Height)$primary"
        }
    }
    return $choices
}

function Initialize-BigPictureForm {
    if ($script:frmBigPicture) { return }
    $script:frmBigPicture = New-Object System.Windows.Forms.Form
    $script:frmBigPicture.Text = $script:AppName
    $script:frmBigPicture.FormBorderStyle = 'None'
    $script:frmBigPicture.WindowState = 'Normal'
    $script:frmBigPicture.StartPosition = 'Manual'
    $script:frmBigPicture.BackColor = [System.Drawing.Color]::FromArgb(8, 12, 18)
    $script:frmBigPicture.TopMost = $true
    $script:frmBigPicture.KeyPreview = $true
    $script:frmBigPicture.Add_KeyDown({
        if ($_.KeyCode -eq 'Escape') { Hide-BigPicture; Show-MainWindow }
    })

    $script:bpRing = New-Object System.Windows.Forms.Panel
    $script:bpRing.Size = New-Object System.Drawing.Size(420, 420)
    Enable-DoubleBuffer $script:bpRing
    $script:bpRing.Add_Paint({
        param($s, $e)
        Draw-Ring $e.Graphics $s.Width $s.Height
    })
    $script:frmBigPicture.Controls.Add($script:bpRing)

    $script:bpTime = New-Object System.Windows.Forms.Label
    $script:bpTime.Size = New-Object System.Drawing.Size(420, 100)
    $script:bpTime.TextAlign = 'MiddleCenter'
    $script:bpTime.Font = New-Object System.Drawing.Font('Consolas', 72, [System.Drawing.FontStyle]::Bold)
    $script:bpTime.ForeColor = Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
    $script:bpTime.BackColor = [System.Drawing.Color]::Transparent
    $script:frmBigPicture.Controls.Add($script:bpTime)

    $script:bpSub = New-Object System.Windows.Forms.Label
    $script:bpSub.Size = New-Object System.Drawing.Size(600, 36)
    $script:bpSub.TextAlign = 'MiddleCenter'
    $script:bpSub.Font = New-Object System.Drawing.Font('Segoe UI', 14)
    $script:bpSub.ForeColor = Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))
    $script:bpSub.BackColor = [System.Drawing.Color]::Transparent
    $script:frmBigPicture.Controls.Add($script:bpSub)

    $script:bpHint = New-Object System.Windows.Forms.Label
    $script:bpHint.Size = New-Object System.Drawing.Size(400, 24)
    $script:bpHint.Text = 'Esc or double-click to exit Cinema mode'
    $script:bpHint.TextAlign = 'MiddleCenter'
    $script:bpHint.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $script:bpHint.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
    $script:bpHint.BackColor = [System.Drawing.Color]::Transparent
    $script:frmBigPicture.Controls.Add($script:bpHint)

    $script:frmBigPicture.Add_Resize({
        $w = $script:frmBigPicture.ClientSize.Width
        $h = $script:frmBigPicture.ClientSize.Height
        $ringS = [math]::Min(420, [math]::Min($w, $h) - 120)
        $script:bpRing.Size = New-Object System.Drawing.Size($ringS, $ringS)
        $script:bpRing.Location = New-Object System.Drawing.Point(([int](($w - $ringS) / 2)), ([int](($h - $ringS) / 2) - 40))
        $script:bpTime.Location = New-Object System.Drawing.Point(([int](($w - $ringS) / 2)), ($script:bpRing.Top + 90))
        $script:bpTime.Size = New-Object System.Drawing.Size($ringS, 100)
        $script:bpSub.Location = New-Object System.Drawing.Point(([int](($w - 600) / 2)), ($script:bpRing.Bottom + 8))
        $script:bpHint.Location = New-Object System.Drawing.Point(([int](($w - 400) / 2)), ($h - 48))
    })
    $script:frmBigPicture.Add_DoubleClick({ Hide-BigPicture; Show-MainWindow })
    $script:bpRing.Add_DoubleClick({ Hide-BigPicture; Show-MainWindow })
}

function Update-BigPictureDisplay {
    if (-not $script:frmBigPicture -or -not $script:frmBigPicture.Visible) { return }
    if (-not $script:Running -and -not $script:Paused) { Hide-BigPicture; return }
    $secs = [math]::Max(0, $script:Left)
    $script:bpTime.Text = ([TimeSpan]::FromSeconds($secs)).ToString('mm\:ss')
    $script:bpTime.ForeColor = Get-CountdownAccentColor
    $endAt = Format-EndClock $secs
    $state = if ($script:Paused) { 'PAUSED' } else { 'IN SESSION' }
    $script:bpSub.Text = "$state - $($script:Action) - ends $endAt"
    $script:bpRing.Invalidate()
}

function Show-BigPicture {
    if (-not $script:Running -and -not $script:Paused -and -not $script:lastLightRunning) { return }
    Initialize-BigPictureForm
    $screen = Get-CinemaScreen
    $script:frmBigPicture.Bounds = $screen.Bounds
    $script:frmBigPicture.WindowState = 'Maximized'
    Update-BigPictureDisplay
    $script:frmBigPicture.Show()
    $script:frmBigPicture.BringToFront()
    $script:frmBigPicture.Activate()
    if ($chkMinTray.Checked) { $form.Hide(); $form.ShowInTaskbar = $false }
}

function Hide-BigPicture {
    if ($script:frmBigPicture) {
        $script:frmBigPicture.Hide()
    }
}

function Test-BigPictureActive {
    return ($script:frmBigPicture -and $script:frmBigPicture.Visible)
}

function Register-SessionSnooze {
    if ($script:Running) { $script:SessionSnoozeCount++ }
}

function Mark-TonightCardCustom {
    if ($script:ApplyingTonightCard) { return }
    if (-not $script:UseSteamUi) { return }
    if ($script:TonightCardId -eq 'custom') { return }
    $script:TonightCardId = 'custom'
    $script:TonightCardSnoozePolicy = 'default'
    Update-TonightCardHighlight
}

function Select-TonightCard {
    param([string]$CardId)
    if (-not (Get-Command Get-TonightCardById -ErrorAction SilentlyContinue)) { return }
    $card = Get-TonightCardById $CardId
    if (-not $card) { return }
    $script:TonightCardId = $card.Id
    $script:TonightCardSnoozePolicy = [string]$card.SnoozePolicy
    $script:ApplyingTonightCard = $true
    try {
        if ($card.Id -eq 'custom') {
            Write-AuditLog 'tonight_card' 'custom'
            if (-not $script:Running -and $script:UiReady) { Save-Settings }
            Update-TonightCardHighlight
            Update-Ui
            return
        }
        $script:Action = [string]$card.Action
        foreach ($p in $script:Pills) {
            $on = ($p.Tag -eq $script:Action)
            if ($on) {
                $p.BackColor = switch ($script:Action) {
                    'Sleep' { Get-UiColor 'Mint' ([System.Drawing.Color]::FromArgb(102, 192, 244)) }
                    'Restart' { Get-UiColor 'Blue' ([System.Drawing.Color]::FromArgb(102, 192, 244)) }
                    'Hibernate' { Get-UiColor 'Violet' ([System.Drawing.Color]::FromArgb(177, 152, 255)) }
                    'Lock' { Get-UiColor 'Slate' ([System.Drawing.Color]::FromArgb(143, 152, 160)) }
                    default { Get-UiColor 'Amber' ([System.Drawing.Color]::FromArgb(164, 208, 7)) }
                }
                $p.ForeColor = [System.Drawing.Color]::FromArgb(14, 12, 10)
            } else {
                $off = if ($script:UseSteamUi) { Get-UiColor 'NavOff' ([System.Drawing.Color]::FromArgb(46, 54, 64)) } else { [System.Drawing.Color]::FromArgb(32, 32, 44) }
                $p.BackColor = $off
                $p.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
            }
        }
        if ($card.TimerMode -eq 'clock') {
            $script:TimerMode = 'clock'
            $script:ClockTime = [string]$card.ClockTime
            $pnlPresets.Visible = $false
            $pnlClock.Visible = $true
            if ($script:UiReady -and $script:dtpClock) {
                $parts = $script:ClockTime.Split(':')
                $script:dtpClock.Value = Get-Date -Hour ([int]$parts[0]) -Minute ([int]$parts[1]) -Second 0
            }
        } else {
            $script:TimerMode = 'duration'
            $script:DefaultSec = [math]::Max((Get-MinTimerSec), [int]$card.DurationSeconds)
            Sync-LobbyMinutesControl
            $pnlPresets.Visible = $script:UseSteamUi
            $pnlClock.Visible = $false
            if ($script:pnlLobbyTimer) { $script:pnlLobbyTimer.Visible = ($script:UseSteamUi -and $script:SteamMainPage -eq 'library') }
        }
        if ($card.DefaultLastLightSequence -and (Get-Command Normalize-LastLightSequenceId -ErrorAction SilentlyContinue)) {
            $script:LastLightSequence = Normalize-LastLightSequenceId ([string]$card.DefaultLastLightSequence)
            if ($script:cboLastLight -and (Get-Command Get-LastLightSequenceCatalog -ErrorAction SilentlyContinue)) {
                $pick = Get-LastLightSequenceCatalog | Where-Object { $_.Id -eq $script:LastLightSequence } | Select-Object -First 1
                if ($pick) { $script:cboLastLight.SelectedItem = $pick }
            }
        }
        if ($card.RitualId) { $script:LastRitualId = [string]$card.RitualId }
        else { $script:LastRitualId = '' }
        $script:LastProfileId = ''
        Write-AuditLog 'tonight_card' "$($card.Id) action=$($card.Action) mode=$($card.TimerMode) last_light=$($card.DefaultLastLightSequence)"
        if (-not $script:Running -and $script:UiReady) { Save-Settings }
        Update-TonightCardHighlight
        Update-RitualHighlight
        Update-PresetHighlight
        Update-GracefulCheckbox
        Update-Ui
    } finally {
        $script:ApplyingTonightCard = $false
    }
}

function Update-TonightCardHighlight {
    if (-not $script:TonightCardBtns) { return }
    foreach ($btn in $script:TonightCardBtns) {
        $c = $btn.Tag
        if (-not $c) { continue }
        Style-TonightCardButton -Button $btn -Selected:($c.Id -eq $script:TonightCardId)
    }
}

function Update-LobbyQuickHighlight {
    if (-not $script:LobbyQuickBtns) { return }
    $matchMin = [math]::Round($script:DefaultSec / 60.0)
    foreach ($qb in $script:LobbyQuickBtns) {
        if ($qb.Tag -eq $matchMin) {
            Style-Button $qb $script:C.Amber ([System.Drawing.Color]::FromArgb(18, 14, 8)) 8 ([System.Drawing.Color]::FromArgb(255, 195, 110))
        } else {
            Style-Button $qb ([System.Drawing.Color]::FromArgb(30, 30, 42)) (Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))) 8 ([System.Drawing.Color]::FromArgb(44, 44, 58))
        }
    }
}

function Get-ClassicStatusStripHeight {
    $h = 0
    if ($lblDry -and $lblDry.Visible) { $h = [math]::Max($h, 18) }
    if ($script:lblDemo -and $script:lblDemo.Visible) { $h = [math]::Max($h, 18) }
    if ($lblHotkey -and $lblHotkey.Visible) { $h = [math]::Max($h, 18) }
    return $h
}

function Apply-ClassicSimpleLayout {
    if ($script:UseSteamUi) { return }
    $yb = $script:yBoost
    $inLobby = -not $script:Running -and -not $script:Paused
    $durationLobby = ($script:TimerMode -eq 'duration') -and $inLobby
    if ($script:pnlLobbyTimer) {
        $script:pnlLobbyTimer.Visible = ($script:TimerMode -eq 'duration') -and $inLobby
    }
    if ($script:pnlCard) {
        $script:pnlCard.Visible = $durationLobby -or ($script:TimerMode -ne 'duration')
    }
    if ($script:pnlClassicDivider) { $script:pnlClassicDivider.Visible = $false }
    if ($lblBrand -and $lblBrand.Visible) { $lblBrand.Text = 'Lights Out PC' }
    if ($lblSub -and $durationLobby) { $lblSub.Text = 'Sleep Timer' }
    if ($durationLobby) {
        $timerY = $script:statusY + (Get-ClassicStatusStripHeight) + 8
        $timerH = 86
        $ringY = $timerY + $timerH + 10
        $pillsY = $ringY + 220 + 10
        $startY = $pillsY + 54
        if ($script:pnlLobbyTimer) {
            $script:pnlLobbyTimer.Location = New-Object System.Drawing.Point(24, $timerY)
            $script:pnlLobbyTimer.Size = New-Object System.Drawing.Size(($script:contentW - 8), $timerH)
            $script:pnlLobbyTimer.BringToFront()
        }
        if ($pnlRing) { $pnlRing.Location = New-Object System.Drawing.Point(88, $ringY) }
        if ($script:pnlCard) {
            $script:pnlCard.Location = New-Object System.Drawing.Point(20, $pillsY)
            $script:pnlCard.BringToFront()
        }
        $script:pnlClassicStartY = $startY
        if ($lblEnd) { $lblEnd.Visible = $false }
        if ($btnStart) { $btnStart.BringToFront() }
        $formH = $startY + 44 + 24
    } else {
        $ringY = 78 + $yb
        if ($pnlRing) { $pnlRing.Location = New-Object System.Drawing.Point(88, $ringY) }
        $script:pnlClassicStartY = 328 + $yb
        if ($lblEnd) {
            $lblEnd.Visible = $true
            $lblEnd.Location = New-Object System.Drawing.Point(24, ($ringY + 226))
        }
        if ($script:pnlCard) { $script:pnlCard.Location = New-Object System.Drawing.Point(20, (550 + $yb + $script:yNovel)) }
        $formH = 606 + $yb + $script:yCal + $script:yNovel + $script:ySchedule + $script:formExtraH - $script:yCardSave
    }
    if ($form -and $form.Height -ne $formH) { $form.Height = $formH }
}

function Sync-TonightCardsPageLayout {
    if (-not $script:UseSteamUi) {
        if ($pnlMode) { $pnlMode.Visible = $false }
        if ($lblRitual) { $lblRitual.Visible = $false }
        if ($pnlRituals) { $pnlRituals.Visible = $false }
        $hideSchedule = ($script:TimerMode -eq 'duration')
        if ($script:lblSchedule) { $script:lblSchedule.Visible = -not $hideSchedule }
        if ($script:pnlSchedule) { $script:pnlSchedule.Visible = -not $hideSchedule }
        Apply-ClassicSimpleLayout
        return
    }
    $isLib = ($script:SteamMainPage -eq 'library')
    $isSch = ($script:SteamMainPage -eq 'schedule')
    if ($script:pnlTonightCards) { $script:pnlTonightCards.Visible = $isLib }
    if ($script:lblTonightCards) { $script:lblTonightCards.Visible = $isLib }
    if ($lblRitual) { $lblRitual.Visible = (-not $script:UseSteamUi) }
    if ($pnlRituals) { $pnlRituals.Visible = (-not $script:UseSteamUi) }
    if ($pnlMode) { $pnlMode.Visible = $isSch -or (-not $script:UseSteamUi) }
    if ($script:pnlLobbyTimer) {
        $script:pnlLobbyTimer.Visible = $isLib -and ($script:TimerMode -eq 'duration')
    }
    if ($pnlPresets) {
        $showPresets = ($script:TimerMode -eq 'duration') -and ($isSch -or (-not $script:UseSteamUi))
        $pnlPresets.Visible = $showPresets
    }
    if ($script:lblMyTimers) { $script:lblMyTimers.Visible = $isSch -and (@($script:SavedTimers).Count -gt 0) }
    if ($script:pnlMyTimers) { $script:pnlMyTimers.Visible = $isSch -and (@($script:SavedTimers).Count -gt 0) }
    if ($script:btnEditProfiles) { $script:btnEditProfiles.Visible = $isSch -and (@($script:SavedTimers).Count -gt 0) }
    if ($script:btnSaveProfile) { $script:btnSaveProfile.Visible = $isSch -or (-not $script:UseSteamUi) }
    if ($script:lblSchedule) {
    $script:lblSchedule.Text = 'Tonight'
    }
}

function Set-SteamMainPage {
    param(
        [ValidateSet('library', 'schedule', 'settings')]
        [string]$Page
    )
    if (-not $script:UseSteamUi) { return }
    $script:SteamMainPage = $Page
    if (Get-Command Set-SteamNavHighlight -ErrorAction SilentlyContinue) {
        Set-SteamNavHighlight -Page $Page
    }
    $showTonight = ($Page -ne 'settings')
    $showSettings = ($Page -eq 'settings')
    if ($script:pnlSchedule) { $script:pnlSchedule.Visible = $showTonight }
    if ($script:lblSchedule) { $script:lblSchedule.Visible = $showTonight }
    if ($script:lblCalEvent) { $script:lblCalEvent.Visible = $showTonight -and $script:lblCalEvent.Text }
    if ($pnlRing) { $pnlRing.Visible = -not $showSettings }
    if ($lblEnd) { $lblEnd.Visible = $showTonight }
    if ($lblHotkey) { $lblHotkey.Visible = $showTonight -and -not (Test-NoPowerAction) }
    if ($lblDry) { $lblDry.Visible = $showTonight -and (Test-NoPowerAction) }
    if ($script:pnlSteamHero) { $script:pnlSteamHero.Visible = -not $showSettings }
    if ($showSettings) {
        $script:CardOptsExpanded = $true
        Update-CardOptionsPanel
        if ($script:pnlCard) {
            $script:pnlCard.Location = New-Object System.Drawing.Point(20, (300 + $script:yBoost))
        }
        Show-SessionToast 'Settings - power actions and options below' 'Info' 2200
    } else {
        if ($script:pnlCard) { Update-ScheduleSectionLayout }
    }
    Sync-TonightCardsPageLayout
    Update-Ui
}

function Get-UiSessionState {
    param(
        [string]$TimeStr,
        [string]$EndClock,
        [string]$EndLine,
        [int]$IdleSec
    )
    $streak = 0
    if (Get-Command Get-SleepLedgerStats -ErrorAction SilentlyContinue) {
        $st = Get-SleepLedgerStats -AuditLogPath $script:AuditLogPath
        $streak = [int]$st.Streak
    }
    $evTitle = $script:CalendarEventTitle
    $clockDisp = ''
    if ($script:TimerMode -in @('clock', 'calendar')) {
        $clockDisp = Format-ClockDisplay (Get-ClockTargetDateTime)
    }
    if (Get-Command Get-SessionState -ErrorAction SilentlyContinue) {
        return Get-SessionState -Running $script:Running -Paused $script:Paused `
            -TimerMode $script:TimerMode -Action $script:Action `
            -Left $script:Left -Total $script:Total -DefaultSec $script:DefaultSec `
            -LastRitualId $script:LastRitualId -TimeStr $TimeStr -EndClock $EndClock `
            -EndLine $EndLine -RemainFriendly (Format-RemainingFriendly) `
            -DurationLong (Format-DurationLong $IdleSec) -ClockDisplay $clockDisp `
            -EventTitle $evTitle -Streak $streak
    }

    $remainFriendly = Format-RemainingFriendly
    $durationLong = Format-DurationLong $IdleSec
    $actionLabel = if ($script:Action) { $script:Action.ToLower() } else { 'sleep' }
    $subtitle = if ($script:Running) {
        "In session - $actionLabel in $TimeStr"
    } elseif ($script:Paused) {
        "Paused - $actionLabel in $TimeStr"
    } elseif ($script:TimerMode -eq 'clock' -and $clockDisp) {
        "Scheduled - $actionLabel at $clockDisp"
    } elseif ($script:TimerMode -eq 'calendar' -and $clockDisp) {
        "Calendar run - $actionLabel at $clockDisp"
    } else {
        "Ready - $actionLabel in $durationLong"
    }
    $header = if ($script:Running) {
        'PLAYING > Lights Out'
    } elseif ($script:Paused) {
        'PAUSED > Lights Out'
    } elseif ($script:TimerMode -in @('clock', 'calendar')) {
        'TONIGHT > Scheduled run'
    } else {
        'TONIGHT > Ready'
    }
    $startText = if ($script:Running) {
        'IN SESSION'
    } elseif ($script:Paused) {
        "RESUME $TimeStr"
    } elseif ($script:TimerMode -eq 'duration') {
        "PLAY TONIGHT - $([TimeSpan]::FromSeconds([math]::Max(0, $script:DefaultSec)).ToString('mm\:ss'))"
    } else {
        'PLAY TONIGHT'
    }
    return @{
        State       = if ($script:Running) { 'ingame' } elseif ($script:Paused) { 'paused' } else { 'lobby' }
        Online      = if ($script:Paused) { 'Away' } else { 'Online' }
        OnlineColor = if ($script:Paused) { 'Away' } else { 'Online' }
        Header      = $header
        TrayHeader  = $subtitle
        HeroTitle   = $script:AppName
        HeroTagline = $subtitle
        Subtitle    = $subtitle
        RingHint    = if ($EndLine) { $EndLine } else { $remainFriendly }
        RingSub     = if ($EndClock) { "Ends about $EndClock" } elseif ($EndLine) { $EndLine } else { $remainFriendly }
        RingMain    = $null
        PctLabel    = if ($script:Paused) { 'Session paused' } elseif ($script:Running) { 'Session live' } else { $null }
        StartText   = $startText
        FormTitle   = if ($script:Running) { "Lights Out - $TimeStr" } elseif ($script:Paused) { 'Lights Out - Paused' } else { $script:AppName }
    }
}

function Invoke-Ritual {
    param([hashtable]$Ritual)
    if (-not $Ritual) { return }
    $prof = @{
        Id      = $Ritual.Id
        Name    = $Ritual.Label
        Action  = $Ritual.Action
        Mode    = $Ritual.Mode
        Seconds = if ($Ritual.Seconds) { $Ritual.Seconds } else { $script:DefaultSec }
        Clock   = if ($Ritual.Clock) { $Ritual.Clock } else { $script:ClockTime }
        AutoStart = $true
    }
    Write-AuditLog 'ritual_selected' "$($Ritual.Id) action=$($Ritual.Action) mode=$($Ritual.Mode)"
    Invoke-TimerProfile $prof -StartNow
}

function Format-PowerBlockerTarget {
    param([string]$Target)
    $t = $Target.Trim()
    if ($t -match '\\([^\\]+\.exe)\s*$') { return $Matches[1] }
    if ($t -match '\\([^\\]+)\s*$') { return $Matches[1] }
    return $t
}

function Get-PowerRequestBlockers {
    param([string]$ForAction = $script:Action)
    if ($ForAction -eq 'Lock') { return @() }
    try {
        $lines = @(& powercfg.exe /requests 2>&1)
    } catch {
        return @()
    }
    $found = [System.Collections.Generic.List[object]]::new()
    $section = $null
    $pending = $null
    foreach ($line in $lines) {
        $t = "$line".Trim()
        if ($t -match '^([A-Z][A-Z0-9]+):$') {
            if ($pending -and $section) {
                $found.Add([pscustomobject]@{
                        Section = $section
                        Kind    = $pending.Kind
                        Name    = (Format-PowerBlockerTarget $pending.Target)
                        Reason  = if ($pending.Detail) { $pending.Detail } else { 'Power request active' }
                    })
            }
            $section = $Matches[1]
            $pending = $null
            continue
        }
        if (-not $section) { continue }
        if (-not $t -or $t -eq 'None.' -or $t -eq 'None') {
            if ($pending) {
                $found.Add([pscustomobject]@{
                        Section = $section
                        Kind    = $pending.Kind
                        Name    = (Format-PowerBlockerTarget $pending.Target)
                        Reason  = if ($pending.Detail) { $pending.Detail } else { 'Power request active' }
                    })
                $pending = $null
            }
            continue
        }
        if ($t -match '^\[(.+?)\]\s*(.+)$') {
            if ($pending) {
                $found.Add([pscustomobject]@{
                        Section = $section
                        Kind    = $pending.Kind
                        Name    = (Format-PowerBlockerTarget $pending.Target)
                        Reason  = if ($pending.Detail) { $pending.Detail } else { 'Power request active' }
                    })
            }
            $pending = @{ Kind = $Matches[1]; Target = $Matches[2].Trim(); Detail = '' }
        } elseif ($pending) {
            $pending.Detail = $t
            $found.Add([pscustomobject]@{
                    Section = $section
                    Kind    = $pending.Kind
                    Name    = (Format-PowerBlockerTarget $pending.Target)
                    Reason  = $t
                })
            $pending = $null
        }
    }
    if ($pending -and $section) {
        $found.Add([pscustomobject]@{
                Section = $section
                Kind    = $pending.Kind
                Name    = (Format-PowerBlockerTarget $pending.Target)
                Reason  = if ($pending.Detail) { $pending.Detail } else { 'Power request active' }
            })
    }
    $sleepSections = @('DISPLAY', 'SYSTEM', 'AWAYMODE', 'EXECUTION', 'PERFBOOST', 'ACTIVELOCKSCREEN')
    $all = @($found)
    switch ($ForAction) {
        'Sleep' { return @($all | Where-Object { $_.Section -in $sleepSections }) }
        'Hibernate' { return @($all | Where-Object { $_.Section -in $sleepSections }) }
        default { return @($all | Where-Object { $_.Section -in @('DISPLAY', 'SYSTEM', 'EXECUTION') }) }
    }
}

function Test-ShouldWarnPowerBlockers {
    if (Test-NoPowerAction) { return $false }
    if ($script:Action -eq 'Lock') { return $false }
    if ($script:UiReady -and $script:chkPowerWarn) { return [bool]$script:chkPowerWarn.Checked }
    return [bool]$script:WarnPowerBlockers
}

function Confirm-PowerBlockerWarning {
    param([array]$Blockers)
    $verb = switch ($script:Action) {
        'Sleep' { 'sleep' }
        'Hibernate' { 'hibernate' }
        'Restart' { 'restart' }
        default { 'shut down' }
    }
    $lines = @($Blockers | Select-Object -First 6 | ForEach-Object {
            "- $($_.Name): $($_.Reason) [$($_.Section)]"
        })
    if ($Blockers.Count -gt 6) { $lines += "- and $($Blockers.Count - 6) more" }
    $body = @(
        "Windows reports apps that may block $verb when the timer ends:"
        ''
        ($lines -join [Environment]::NewLine)
        ''
        'Lights Out will force-close blockers at timer end if needed.'
        ''
        'Start the countdown anyway?'
    ) -join [Environment]::NewLine
    $r = [System.Windows.Forms.MessageBox]::Show(
        $body, "$script:AppName - sleep blockers", 'YesNo', 'Warning')
    return ($r -eq 'Yes')
}

function Get-SleepClearanceReport {
    $issues = [System.Collections.Generic.List[string]]::new()
    $checks = [System.Collections.Generic.List[object]]::new()

    $checks.Add(@{
            Name  = 'Power action'
            Value = [string]$script:Action
            State = 'ok'
        })

    $modeState = 'ok'
    $modeVal = switch ($script:TimerMode) {
        'clock' {
            "At $(Format-ClockDisplay (Get-ClockTargetDateTime))"
        }
        'calendar' {
            if ($script:CalendarEventTitle) {
                $script:CalendarEventTitle
            } elseif ($script:ScheduledAt) {
                "At $(Format-ClockDisplay (Get-ClockTargetDateTime))"
            } else {
                $modeState = 'warning'
                $issues.Add('Pick a calendar event')
                'Calendar (no event selected)'
            }
        }
        default {
            "$(([TimeSpan]::FromSeconds($script:DefaultSec)).ToString('mm\:ss')) countdown"
        }
    }
    $checks.Add(@{ Name = 'Timer mode'; Value = $modeVal; State = $modeState })

    $autoVal = if ($script:AutoStartOnOpen) { 'Auto-play on open' } else { 'Lobby-first' }
    $checks.Add(@{ Name = 'Auto-start'; Value = $autoVal; State = 'ok' })

    $gateParts = @('5s confirm')
    if ((Get-Command Test-GracefulApplies -ErrorAction SilentlyContinue) -and (Test-GracefulApplies) -and $script:GracefulShutdown) {
        $gateParts += 'graceful shutdown'
    }
    $gateParts += 'Ctrl+Shift+S'
    if (Test-NoPowerAction) { $gateParts += 'dry-run' }
    $checks.Add(@{
            Name  = 'Safety gates'
            Value = ($gateParts -join ' - ')
            State = 'ok'
        })

    $blockers = @()
    if ($script:Action -ne 'Lock') {
        try { $blockers = @(Get-PowerRequestBlockers) } catch { }
    }
    if ($blockers.Count -gt 0) {
        $preview = ($blockers | Select-Object -First 2 | ForEach-Object { $_.Name }) -join ', '
        $bVal = if ($blockers.Count -eq 1) { $blockers[0].Name } else { "$($blockers.Count) detected ($preview)" }
        $checks.Add(@{ Name = 'Power blockers'; Value = $bVal; State = 'warning' })
        foreach ($b in $blockers) {
            $issues.Add("$($b.Name) active")
        }
    } else {
        $checks.Add(@{ Name = 'Power blockers'; Value = 'None detected'; State = 'ok' })
    }

    $luxVal = if ($script:EmitLuxGridEvents) { 'On (optional)' } else { 'Off (optional)' }
    $checks.Add(@{ Name = 'LuxGrid'; Value = $luxVal; State = 'ok' })

    if ($script:UseSteamUi -and $script:TonightCardId -and (Get-Command Get-TonightCardClearanceChecks -ErrorAction SilentlyContinue)) {
        foreach ($extra in (Get-TonightCardClearanceChecks -CardId $script:TonightCardId -LastLightSequence $script:LastLightSequence)) {
            $checks.Add($extra)
        }
    }

    $issueCount = $issues.Count
    $headline = switch ($issueCount) {
        0 { 'Clear for Lights Out' }
        1 { '1 thing may keep your PC awake' }
        default { "$issueCount things may keep your PC awake" }
    }

    if ($issueCount -eq 0) {
        $action = [string]$script:Action
        $subtitle = "$action - $modeVal - Confirm enabled - Emergency cancel ready"
        if ($script:UseSteamUi -and $script:TonightCardId -and (Get-Command Get-TonightCardHeroPreview -ErrorAction SilentlyContinue)) {
            $prev = Get-TonightCardHeroPreview -CardId $script:TonightCardId -Action $script:Action `
                -TimerMode $script:TimerMode -DefaultSec $script:DefaultSec -ClockTime $script:ClockTime `
                -LastLightSequence $script:LastLightSequence -ClearanceStatus 'Clear'
            if ($prev.ClearanceLine) { $subtitle = $prev.ClearanceLine }
        }
    } else {
            $subtitle = (@($issues | Select-Object -First 2)) -join ' - '
    }

    [pscustomobject]@{
        Status     = if ($issueCount -gt 0) { 'Warning' } else { 'Clear' }
        IssueCount = $issueCount
        Issues     = @($issues)
        Checks     = @($checks)
        Headline   = $headline
        Subtitle   = $subtitle
    }
}

function Invoke-StartTimer {
    param(
        [int]$Sec,
        [switch]$FromAutoStart
    )
    if (Test-ShouldWarnPowerBlockers -and -not (Test-UseForcePower)) {
        $blockers = @(Get-PowerRequestBlockers)
        if ($blockers.Count -gt 0) {
            Write-AuditLog 'power_blockers' "count=$($blockers.Count) action=$script:Action autostart=$FromAutoStart"
            $names = ($blockers | Select-Object -First 2 | ForEach-Object { $_.Name }) -join ', '
            if ($FromAutoStart) {
                $script:tray.ShowBalloonTip(
                    5000, $script:AppName,
                    "Timer started. Force shutdown will close blockers: $names",
                    [System.Windows.Forms.ToolTipIcon]::Warning)
                Write-AuditLog 'power_blockers' 'autostart_balloon'
            } elseif (-not (Confirm-PowerBlockerWarning $blockers)) {
                Write-AuditLog 'power_blockers' 'user_cancelled'
                return
            } else {
                Write-AuditLog 'power_blockers' 'user_confirmed'
                if ($script:Action -in @('Shutdown', 'Restart')) {
                    $script:GracefulShutdown = $false
                    if ($script:UiReady -and $chkGraceful) { $chkGraceful.Checked = $false }
                    Write-AuditLog 'power_force_armed' "apps=$names"
                }
            }
        }
    }
    Start-Timer $Sec
}

function Test-NoPowerAction {
    # CI/tests must NEVER shut down, sleep, or restart the machine.
    return $script:DryRun -or ($env:SLEEPTIMER_DRY_RUN -eq '1') -or ($env:SLEEPTIMER_CI -eq '1')
}

function Get-MinTimerSec {
    if (Test-NoPowerAction) { return 3 }
    return $script:MinTimerSec
}

function Write-AuditLog {
    param([string]$Event, [string]$Detail = '')
    if ($script:DemoMode) { return }
    try {
        if (-not (Test-Path $script:SettingsDir)) {
            New-Item -ItemType Directory -Path $script:SettingsDir -Force | Out-Null
        }
        $line = "$(Get-Date -Format o) $Event"
        if ($Detail) { $line += " $Detail" }
        $line | Add-Content $script:AuditLogPath -Encoding UTF8
    } catch { }
}

$script:LuxGridEventDir = Join-Path $env:LOCALAPPDATA 'LuxGrid\events\inbox'
$script:LuxGridTimerName = 'Sleep Ritual'
$script:EmitLuxGridEvents = $false

function Test-LuxGridEnabled {
    if ($script:UiReady -and $chkLuxGrid) { return [bool]$chkLuxGrid.Checked }
    return [bool]$script:EmitLuxGridEvents
}

function Get-LuxGridPhase {
    param([int]$Remaining)
    if ($Remaining -le 0) { return 'completed' }
    if ($Remaining -lt 120) { return 'warning' }
    return 'countdown'
}

function Publish-LuxGridEvent {
    param(
        [Parameter(Mandatory)]
        [string]$EventName,
        [hashtable]$Payload = @{}
    )
    if (-not (Test-LuxGridEnabled)) { return }
    try {
        if (-not (Test-Path $script:LuxGridEventDir)) {
            New-Item -ItemType Directory -Path $script:LuxGridEventDir -Force | Out-Null
        }
        $body = @{
            id        = [guid]::NewGuid().ToString()
            timestamp = (Get-Date).ToUniversalTime().ToString('o')
            sourceApp = 'LightsOut'
            eventName = $EventName
            channel   = 'sleep'
            payload   = $Payload
            processed = $false
        }
        $file = Join-Path $script:LuxGridEventDir ("lightsout_{0}.json" -f ([guid]::NewGuid().ToString('N')))
        $body | ConvertTo-Json -Depth 6 | Set-Content $file -Encoding UTF8
    } catch { }
}

function Publish-LuxGridTick {
    param([int]$Remaining, [int]$Total = $script:Total)
    $pct = if ($Total -gt 0) { [math]::Round(($Remaining / $Total) * 100, 1) } else { 0 }
    Publish-LuxGridEvent -EventName 'timer.tick' -Payload @{
        timerName        = $script:LuxGridTimerName
        totalSeconds     = $Total
        remainingSeconds = $Remaining
        percentRemaining = $pct
        phase            = (Get-LuxGridPhase $Remaining)
        action           = $script:Action
    }
}

function Publish-LuxGridWarning {
    param(
        [int]$Remaining,
        [ValidateSet('info', 'warning', 'critical')]
        [string]$Severity = 'warning'
    )
    Publish-LuxGridEvent -EventName 'timer.warning' -Payload @{
        remainingSeconds = $Remaining
        severity         = $Severity
        timerName        = $script:LuxGridTimerName
        action           = $script:Action
    }
}

function Publish-LuxGridCancelled {
    param([string]$Reason = 'pause')
    Publish-LuxGridEvent -EventName 'timer.cancelled' -Payload @{
        result           = 'cancelled'
        timerName        = $script:LuxGridTimerName
        durationSeconds  = [math]::Max(0, $script:Total - $script:Left)
        reason           = $Reason
        remainingSeconds = $script:Left
    }
}

function Publish-LuxGridCompleted {
    Publish-LuxGridEvent -EventName 'timer.completed' -Payload @{
        result          = 'completed'
        timerName       = $script:LuxGridTimerName
        durationSeconds = $script:Total
        action          = $script:Action
    }
}

function Invoke-EmergencyCancel {
    $cancelMsg = if ($script:UseSteamUi) {
        'Session ended - back to library'
    } else {
        'Countdown cancelled (Ctrl+Shift+S)'
    }
    if (Test-SessionEndingActive) {
        Write-AuditLog 'emergency_cancel' "phase=last_light action=$script:Action left=$script:Left"
        Publish-LuxGridCancelled -Reason 'emergency'
        Stop-PowerFailsafeWatchdog
        Stop-SessionEndTimer
        Stop-LastLightSequence
        Stop-LightsDimPhase
        if ($script:punchTimer) { $script:punchTimer.Stop() }
        if ($pnlPunch) { $pnlPunch.Visible = $false }
        $script:punchFrame = -1
        $script:LastLightProceedLabel = $null
        Stop-TrayFlash
        Hide-BigPicture
        Show-MainWindow
        $script:Left = 0
        Update-Ui
        Show-SessionToast $cancelMsg 'Info' 3500
        return
    }
    if (-not $script:Running -and -not $script:Paused) { return }
    if ($script:Left -gt 60) {
        $now = [DateTime]::UtcNow
        if (-not $script:CancelArmUtc -or ($now - $script:CancelArmUtc).TotalSeconds -gt 2) {
            $script:CancelArmUtc = $now
            Show-SessionToast 'Press Ctrl+Shift+S again within 2s to cancel' 'Warning' 2200
            return
        }
        $script:CancelArmUtc = $null
    }
    Write-AuditLog 'emergency_cancel' "action=$script:Action left=$script:Left"
    Publish-LuxGridCancelled -Reason 'emergency'
    Stop-TrayFlash
    Stop-Timer -Reason 'emergency'
    Hide-BigPicture
    Show-MainWindow
    Show-SessionToast $cancelMsg 'Info' 3500
}

function Invoke-SessionSnooze {
    param([int]$Seconds)
    if (-not $script:Running) { return }
    if (-not (Test-AllowSnooze $Seconds)) { return }
    $script:Left += $Seconds
    $script:Warn5 = $false
    $script:Warn60 = $false
    $script:Warn30 = $false
    Write-AuditLog 'snooze' "hotkey+$Seconds"
    Register-SessionSnooze
    Update-Ui
    if (-not (Test-NoPowerAction)) {
        if ($Seconds -ge 600) {
            $label = '+10 min'
        } elseif ($Seconds -ge 300) {
            $label = '+5 min'
        } else {
            $label = ('+' + $Seconds + ' s')
        }
        $leftText = [TimeSpan]::FromSeconds($script:Left).ToString('mm\:ss')
        Show-SessionToast ($label + ' - ' + $leftText + ' left') 'Info' 2500
    }
}

function Invoke-SessionPauseToggle {
    if ($script:Paused) {
        Resume-Timer
    } elseif ($script:Running) {
        Stop-Timer -Reason 'pause'
    }
}

function Register-SessionHotkeys {
    if (-not (Initialize-GlobalHotKeyType)) {
        Write-AuditLog 'hotkey_failed' 'GlobalHotKey type not available'
        return
    }
    $script:globalHotkeys = [System.Collections.Generic.List[object]]::new()
    $ctrlShift = 6   # MOD_CONTROL | MOD_SHIFT
    $ctrlAlt = 3     # MOD_CONTROL | MOD_ALT
    try {
        $hk = New-Object GlobalHotKey($form.Handle, 9001, $ctrlShift, 0x53)
        $hk.Add_HotKeyPressed({ Invoke-EmergencyCancel })
        $script:globalHotkeys.Add($hk) | Out-Null
        Write-AuditLog 'hotkey_ok' 'cancel Ctrl+Shift+S'
    } catch {
        Write-AuditLog 'hotkey_failed' ('cancel ' + $_.Exception.Message)
    }
    try {
        $hk = New-Object GlobalHotKey($form.Handle, 9002, $ctrlAlt, 0x35)
        $hk.Add_HotKeyPressed({ Invoke-SessionSnooze 300 })
        $script:globalHotkeys.Add($hk) | Out-Null
        Write-AuditLog 'hotkey_ok' '+5m Ctrl+Alt+5'
    } catch {
        Write-AuditLog 'hotkey_failed' ('+5m ' + $_.Exception.Message)
    }
    try {
        $hk = New-Object GlobalHotKey($form.Handle, 9003, $ctrlAlt, 0x30)
        $hk.Add_HotKeyPressed({ Invoke-SessionSnooze 600 })
        $script:globalHotkeys.Add($hk) | Out-Null
        Write-AuditLog 'hotkey_ok' '+10m Ctrl+Alt+0'
    } catch {
        Write-AuditLog 'hotkey_failed' ('+10m ' + $_.Exception.Message)
    }
    try {
        $hk = New-Object GlobalHotKey($form.Handle, 9004, $ctrlAlt, 0x50)
        $hk.Add_HotKeyPressed({ Invoke-SessionPauseToggle })
        $script:globalHotkeys.Add($hk) | Out-Null
        Write-AuditLog 'hotkey_ok' 'pause Ctrl+Alt+P'
    } catch {
        Write-AuditLog 'hotkey_failed' ('pause ' + $_.Exception.Message)
    }
    try {
        $hk = New-Object GlobalHotKey($form.Handle, 9005, $ctrlAlt, 0x4C)
        $hk.Add_HotKeyPressed({ Show-MainWindow })
        $script:globalHotkeys.Add($hk) | Out-Null
        Write-AuditLog 'hotkey_ok' 'show Ctrl+Alt+L'
    } catch {
        Write-AuditLog 'hotkey_failed' ('show ' + $_.Exception.Message)
    }
}

function Get-BuiltinLightsOutPalette {
    param([ValidateSet('classic', 'steam')][string]$Name = 'steam')
    if (Get-Command Get-LightsOutThemePalette -ErrorAction SilentlyContinue) {
        return Get-LightsOutThemePalette -Name $Name
    }
    if ($Name -eq 'steam') {
        return @{
            Bg = [System.Drawing.Color]::FromArgb(13, 18, 28)
            Card = [System.Drawing.Color]::FromArgb(24, 32, 46)
            Elevated = [System.Drawing.Color]::FromArgb(36, 49, 70)
            RingCard = [System.Drawing.Color]::FromArgb(18, 24, 36)
            Ink = [System.Drawing.Color]::FromArgb(236, 242, 249)
            Muted = [System.Drawing.Color]::FromArgb(137, 151, 170)
            Section = [System.Drawing.Color]::FromArgb(118, 201, 255)
            Amber = [System.Drawing.Color]::FromArgb(242, 185, 93)
            Mint = [System.Drawing.Color]::FromArgb(104, 225, 186)
            Rose = [System.Drawing.Color]::FromArgb(255, 118, 136)
            Blue = [System.Drawing.Color]::FromArgb(126, 176, 255)
            Violet = [System.Drawing.Color]::FromArgb(186, 154, 255)
            Slate = [System.Drawing.Color]::FromArgb(162, 174, 194)
            Track = [System.Drawing.Color]::FromArgb(57, 78, 106)
            Border = [System.Drawing.Color]::FromArgb(58, 79, 108)
            Glow = [System.Drawing.Color]::FromArgb(110, 198, 255)
            Sidebar = [System.Drawing.Color]::FromArgb(10, 14, 22)
            Header = [System.Drawing.Color]::FromArgb(15, 21, 31)
            HeaderTop = [System.Drawing.Color]::FromArgb(28, 37, 53)
            HeaderBottom = [System.Drawing.Color]::FromArgb(13, 18, 28)
            HeroTop = [System.Drawing.Color]::FromArgb(34, 48, 69)
            HeroBottom = [System.Drawing.Color]::FromArgb(20, 28, 41)
            AccentSoft = [System.Drawing.Color]::FromArgb(30, 77, 110)
            DangerSoft = [System.Drawing.Color]::FromArgb(72, 40, 48)
            SuccessSoft = [System.Drawing.Color]::FromArgb(24, 56, 46)
            Play = [System.Drawing.Color]::FromArgb(124, 194, 67)
            PlayHover = [System.Drawing.Color]::FromArgb(150, 224, 84)
            NavOn = [System.Drawing.Color]::FromArgb(47, 97, 136)
            NavOff = [System.Drawing.Color]::FromArgb(33, 42, 57)
            Online = [System.Drawing.Color]::FromArgb(104, 225, 186)
            Away = [System.Drawing.Color]::FromArgb(137, 151, 170)
        }
    }
    return @{
        Bg = [System.Drawing.Color]::FromArgb(10, 10, 14)
        Card = [System.Drawing.Color]::FromArgb(20, 20, 30)
        Elevated = [System.Drawing.Color]::FromArgb(26, 26, 38)
        RingCard = [System.Drawing.Color]::FromArgb(16, 16, 24)
        Ink = [System.Drawing.Color]::FromArgb(252, 250, 244)
        Muted = [System.Drawing.Color]::FromArgb(118, 118, 132)
        Section = [System.Drawing.Color]::FromArgb(148, 146, 162)
        Amber = [System.Drawing.Color]::FromArgb(242, 182, 92)
        Mint = [System.Drawing.Color]::FromArgb(92, 218, 172)
        Rose = [System.Drawing.Color]::FromArgb(238, 108, 122)
        Blue = [System.Drawing.Color]::FromArgb(124, 176, 255)
        Violet = [System.Drawing.Color]::FromArgb(176, 148, 238)
        Slate = [System.Drawing.Color]::FromArgb(168, 174, 196)
        Track = [System.Drawing.Color]::FromArgb(38, 38, 52)
        Border = [System.Drawing.Color]::FromArgb(48, 48, 64)
        Glow = [System.Drawing.Color]::FromArgb(99, 102, 241)
        Sidebar = [System.Drawing.Color]::FromArgb(10, 10, 14)
        Header = [System.Drawing.Color]::FromArgb(10, 10, 14)
        Play = [System.Drawing.Color]::FromArgb(242, 182, 92)
        PlayHover = [System.Drawing.Color]::FromArgb(255, 195, 110)
        NavOn = [System.Drawing.Color]::FromArgb(26, 26, 38)
        NavOff = [System.Drawing.Color]::FromArgb(32, 32, 44)
        Online = [System.Drawing.Color]::FromArgb(92, 218, 172)
        Away = [System.Drawing.Color]::FromArgb(118, 118, 132)
    }
}

function Initialize-LightsOutThemePalette {
    param([string]$Name = 'steam')
    if ($Name -notin @('classic', 'steam')) { $Name = 'steam' }
    if (Get-Command Set-LightsOutTheme -ErrorAction SilentlyContinue) {
        Set-LightsOutTheme -Name $Name
    }
    $script:UiTheme = $Name
    $script:UseSteamUi = ($Name -eq 'steam')
    $script:C = if (Get-Command Get-LightsOutThemePalette -ErrorAction SilentlyContinue) {
        Get-LightsOutThemePalette -Name $Name
    } else {
        Get-BuiltinLightsOutPalette -Name $Name
    }
}

Initialize-LightsOutThemePalette -Name 'steam'

function Switch-ThemeLive {
    param([string]$Name)
    if ($Name -notin @('classic', 'steam')) { return }
    if ($Name -eq $script:UiTheme) { return }
    Initialize-LightsOutThemePalette -Name $Name
    $bg = Get-UiColor 'Bg' ([System.Drawing.Color]::FromArgb(27, 40, 56))
    $ink = Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
    $card = Get-UiColor 'Card' ([System.Drawing.Color]::FromArgb(22, 32, 45))
    $muted = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
    if ($form) {
        $form.BackColor = $bg
        if ($lblSub) { $lblSub.ForeColor = $muted; $lblSub.BackColor = $bg }
        if ($lblEnd) { $lblEnd.BackColor = $bg }
        if ($lblTime) { $lblTime.ForeColor = $ink }
        if ($lblRemain) { $lblRemain.ForeColor = $muted }
        if ($lblPct) { $lblPct.ForeColor = $muted }
        if ($pnlRing) { $pnlRing.Invalidate() }
        if ($script:pnlCard) { $script:pnlCard.BackColor = $card }
        if ($script:pnlCardAdv) { $script:pnlCardAdv.BackColor = $card }
        foreach ($p in $script:Pills) { Style-Button $p ([System.Drawing.Color]::FromArgb(32, 32, 44)) $muted 9 }
        Set-Action $script:Action
    }
    Update-StartButtonStyle
    Update-RitualHighlight
    Update-PresetHighlight
    Update-ClockPresetHighlight
    if ($script:UiReady) { Save-Settings; Update-Ui }
    Write-AuditLog 'theme_switch' "to=$Name"
}

$trayIconFactorySource = @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
public static class TrayIconFactory {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern bool DestroyIcon(IntPtr hIcon);
    public static Icon FromBitmap(Bitmap bmp) {
        IntPtr h = bmp.GetHicon();
        Icon tmp = Icon.FromHandle(h);
        Icon clone = (Icon)tmp.Clone();
        tmp.Dispose();
        DestroyIcon(h);
        return clone;
    }
}
'@

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition $trayIconFactorySource

function Get-ActionIconColor { Get-ActionAccentColor }

function Test-GracefulApplies {
    return $script:Action -in @('Shutdown', 'Restart')
}

function New-ProgressTrayIcon {
    param(
        [double]$RemainRatio,
        [System.Drawing.Color]$ArcColor,
        [int]$Size = 32
    )
    $bmp = New-Object System.Drawing.Bitmap $Size, $Size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $trayBg = if ($script:UseSteamUi) { $script:C.Sidebar } else { [System.Drawing.Color]::FromArgb(14, 14, 18) }
    $g.Clear($trayBg)

    $pad = [math]::Max(2, [int]($Size * 0.1))
    $rect = New-Object System.Drawing.Rectangle $pad, $pad, ($Size - 2 * $pad), ($Size - 2 * $pad)
    $w = [math]::Max(2, [int]($Size / 7.5))

    $trackPen = New-Object System.Drawing.Pen $script:C.Track, $w
    $g.DrawArc($trackPen, $rect, 0, 360)
    $trackPen.Dispose()

    $sweep = 360.0 * [math]::Max(0, [math]::Min(1.0, $RemainRatio))
    if ($sweep -gt 0.5) {
        $arcPen = New-Object System.Drawing.Pen $ArcColor, $w
        $arcPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $arcPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $g.DrawArc($arcPen, $rect, -90, $sweep)
        $arcPen.Dispose()
    }

    $g.Dispose()
    return [TrayIconFactory]::FromBitmap($bmp)
}

function Set-TrayIconSafe {
    param([System.Drawing.Icon]$NewIcon)
    if (-not $NewIcon) { return }
    if ($script:trayLiveIcon -and $script:trayLiveIcon -ne $NewIcon -and $script:trayLiveIcon -ne $script:trayIconStatic) {
        $script:trayLiveIcon.Dispose()
    }
    if ($NewIcon -ne $script:trayIconStatic) {
        $script:trayLiveIcon = $NewIcon
    }
    $script:tray.Icon = $NewIcon
}

function Get-TrayFallbackIcon {
    if ($script:trayIconStatic) { return $script:trayIconStatic }
    return [System.Drawing.SystemIcons]::Application
}

function Update-TrayProgressIcon {
    if (-not $script:tray) { return }
    if ($script:trayFlash -and $script:trayFlash.Enabled -and $script:trayFlashState) {
        if ($script:tray.Icon -ne [System.Drawing.SystemIcons]::Warning) {
            $script:tray.Icon = [System.Drawing.SystemIcons]::Warning
        }
        return
    }
    # Classic UI: branded .ico stays visible on Win11 (generated ring icon is too dark in the tray)
    if (-not $script:UseSteamUi) {
        Set-TrayIconSafe (Get-TrayFallbackIcon)
        return
    }
    try {
        $ratio = if ($script:Running -and $script:Total -gt 0) {
            $script:Left / $script:Total
        } elseif (-not $script:Running) {
            1.0
        } else { 1.0 }
        $color = if ($script:Running -and $script:Left -le 30) { Get-RingColor } else { Get-ActionIconColor }
        Set-TrayIconSafe (New-ProgressTrayIcon -RemainRatio $ratio -ArcColor $color)
    } catch {
        Set-TrayIconSafe (Get-TrayFallbackIcon)
    }
}

function Get-AppIconPath {
    $dir = Get-AppDir
    foreach ($name in @('SleepTimer.ico', 'LightsOut.ico', 'Nightfall.ico')) {
        $p = Join-Path $dir $name
        if (Test-Path $p) { return $p }
    }
    $repoIcon = Join-Path (Split-Path $dir -Parent) 'assets\Nightfall.ico'
    if (Test-Path $repoIcon) { return $repoIcon }
    return $null
}

function Get-LogoPath {
    $dir = Get-AppDir
    foreach ($p in @(
        (Join-Path $dir 'LightsOut-Logo.png')
        (Join-Path $dir 'assets\LightsOut-Logo.png')
    )) {
        if (Test-Path $p) { return $p }
    }
    $parent = Split-Path $dir -Parent
    foreach ($p in @(
        (Join-Path $parent 'assets\LightsOut-Logo.png')
        (Join-Path $parent 'windsurf-project\assets\LightsOut-Logo.png')
    )) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Get-StartupShortcutPath {
    Join-Path ([Environment]::GetFolderPath('Startup')) 'Lights Out.lnk'
}

function Get-StartupShortcutArguments {
    '-SteamUi -Minimized -NoAutoStart'
}

function Test-RunAtLogin { Test-Path (Get-StartupShortcutPath) }

function Set-RunAtLogin {
    param([bool]$Enabled)
    $lnk = Get-StartupShortcutPath
    $oldLnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Sleep Timer.lnk'
    if (Test-Path $oldLnk) { Remove-Item $oldLnk -Force }
    if (-not $Enabled) {
        if (Test-Path $lnk) { Remove-Item $lnk -Force }
        return
    }
    $exe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $wsh = New-Object -ComObject WScript.Shell
    $s = $wsh.CreateShortcut($lnk)
    $s.TargetPath = $exe
    $s.Arguments = Get-StartupShortcutArguments
    $s.WorkingDirectory = Split-Path $exe -Parent
    $s.Description = 'Lights Out - starts minimized and idle'
    $s.WindowStyle = 7
    $icon = Get-AppIconPath
    if ($icon) { $s.IconLocation = "$icon,0" }
    $s.Save()
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh)
}

function Get-Settings {
    $s = @{
        DefaultSeconds = 1700
        Action         = 'Shutdown'
        TopMost        = $true
        Warn5Min       = $true
        RunAtLogin     = $false
        MinimizeToTray = $true
        EmitLuxGridEvents = $false
        GracefulShutdown  = $false
        TimerMode           = 'duration'
        ClockTime           = '23:30'
        ScheduledAt         = ''
        CalendarSource      = ''
        CalendarEventUid    = ''
        CalendarEventTitle  = ''
        WarnPowerBlockers = $true
        QuickWarnPanel    = $true
        DimPhaseEnabled   = $true
        DimPhaseSeconds   = 90
        PactEnabled       = $false
        PactTime          = '23:00'
        LastRitualId      = ''
        LastProfileId     = ''
        SavedTimers       = @()
        CalendarFeedUrl           = ''
        CalendarFeedIntervalMin   = 30
        CalendarFeedAutoStart     = $false
        CalendarFeedLastSync      = ''
        UiTheme                   = 'steam'
        AutoStart                 = $false
        BigPictureOnStart         = $false
        LastAchievementStreak     = 0
        MorningProofLastSeen      = ''
        LastLightEnabled          = $true
        LastLightSequence         = 'ClassicFade'
        LastLightUseCinema        = $false
        LastLightLuxPulse         = $false
        LastLightSound            = 'Off'
        TonightCardId             = 'weeknight'
        CinemaScreenIndex         = -1
        QuietHoursAutoStart       = $false
        ClockFaceStyle            = 'Analog'
        CustomAccentColor         = ''
        SmartLightEnabled         = $false
        SmartLightProvider        = 'none'
        SmartLightMode            = 'gradual_dim'
        SmartLightDimMinutes      = 10
        HueBridgeIp               = ''
        HueUsername               = ''
        HueLightIds               = @()
        HueGroupId                = ''
        HueTargetLabel            = ''
        HttpLightUrl              = ''
    }
    if (Test-Path $script:SettingsPath) {
        try {
            $j = Get-Content $script:SettingsPath -Raw | ConvertFrom-Json
            if ($j.DefaultSeconds) { $s.DefaultSeconds = [math]::Max((Get-MinTimerSec), [int]$j.DefaultSeconds) }
            if ($j.Action -in @('Shutdown', 'Restart', 'Sleep', 'Hibernate', 'Lock')) { $s.Action = [string]$j.Action }
            elseif ($j.Restart -eq $true) { $s.Action = 'Restart' }
            if ($null -ne $j.TopMost) { $s.TopMost = [bool]$j.TopMost }
            if ($null -ne $j.WarnAt5Min) { $s.Warn5Min = [bool]$j.WarnAt5Min }
            if ($null -ne $j.RunAtLogin) { $s.RunAtLogin = [bool]$j.RunAtLogin }
            if ($null -ne $j.MinimizeToTray) { $s.MinimizeToTray = [bool]$j.MinimizeToTray }
            if ($null -ne $j.EmitLuxGridEvents) { $s.EmitLuxGridEvents = [bool]$j.EmitLuxGridEvents }
            if ($null -ne $j.GracefulShutdown) { $s.GracefulShutdown = [bool]$j.GracefulShutdown }
            if ($j.TimerMode -in @('duration', 'clock', 'calendar')) { $s.TimerMode = [string]$j.TimerMode }
            if ($j.ClockTime) {
                $ct = Parse-ClockTime ([string]$j.ClockTime)
                if ($ct) { $s.ClockTime = $ct }
            }
            if ($j.ScheduledAt) {
                try {
                    $sa = [DateTime]::Parse([string]$j.ScheduledAt)
                    if ($sa -gt (Get-Date)) { $s.ScheduledAt = $sa.ToString('o') }
                } catch { }
            }
            if ($j.CalendarSource) { $s.CalendarSource = [string]$j.CalendarSource }
            if ($j.CalendarEventUid) { $s.CalendarEventUid = [string]$j.CalendarEventUid }
            if ($j.CalendarEventTitle) { $s.CalendarEventTitle = [string]$j.CalendarEventTitle }
            if ($null -ne $j.WarnPowerBlockers) { $s.WarnPowerBlockers = [bool]$j.WarnPowerBlockers }
            if ($null -ne $j.QuickWarnPanel) { $s.QuickWarnPanel = [bool]$j.QuickWarnPanel }
            if ($null -ne $j.DimPhaseEnabled) { $s.DimPhaseEnabled = [bool]$j.DimPhaseEnabled }
            if ($j.DimPhaseSeconds) { $s.DimPhaseSeconds = [math]::Max(15, [int]$j.DimPhaseSeconds) }
            if ($null -ne $j.PactEnabled) { $s.PactEnabled = [bool]$j.PactEnabled }
            if ($j.PactTime) {
                $pt = Parse-ClockTime ([string]$j.PactTime)
                if ($pt) { $s.PactTime = $pt }
            }
            if ($j.LastRitualId) { $s.LastRitualId = [string]$j.LastRitualId }
            if ($j.LastProfileId) { $s.LastProfileId = [string]$j.LastProfileId }
            if ($j.SavedTimers -and (Get-Command ConvertFrom-TimerProfilesJson -ErrorAction SilentlyContinue)) {
                $s.SavedTimers = ConvertFrom-TimerProfilesJson $j.SavedTimers
            }
            if ($j.CalendarFeedUrl) { $s.CalendarFeedUrl = [string]$j.CalendarFeedUrl }
            if ($j.CalendarFeedIntervalMin) { $s.CalendarFeedIntervalMin = [math]::Max(5, [int]$j.CalendarFeedIntervalMin) }
            if ($null -ne $j.CalendarFeedAutoStart) { $s.CalendarFeedAutoStart = [bool]$j.CalendarFeedAutoStart }
            if ($j.CalendarFeedLastSync) { $s.CalendarFeedLastSync = [string]$j.CalendarFeedLastSync }
            if ($j.UiTheme -in @('classic', 'steam')) { $s.UiTheme = [string]$j.UiTheme }
            if ($null -ne $j.AutoStart) { $s.AutoStart = [bool]$j.AutoStart }
            if ($null -ne $j.BigPictureOnStart) { $s.BigPictureOnStart = [bool]$j.BigPictureOnStart }
            if ($j.LastAchievementStreak) { $s.LastAchievementStreak = [int]$j.LastAchievementStreak }
            if ($j.MorningProofLastSeen) { $s.MorningProofLastSeen = [string]$j.MorningProofLastSeen }
            if ($null -ne $j.LastLightEnabled) { $s.LastLightEnabled = [bool]$j.LastLightEnabled }
            if ($j.LastLightSequence) {
                $s.LastLightSequence = if (Get-Command Normalize-LastLightSequenceId -ErrorAction SilentlyContinue) {
                    Normalize-LastLightSequenceId ([string]$j.LastLightSequence)
                } else { [string]$j.LastLightSequence }
            }
            if ($null -ne $j.LastLightUseCinema) { $s.LastLightUseCinema = [bool]$j.LastLightUseCinema }
            if ($null -ne $j.LastLightLuxPulse) { $s.LastLightLuxPulse = [bool]$j.LastLightLuxPulse }
            if ($j.LastLightSound) {
                $s.LastLightSound = if (Get-Command Normalize-LastLightSoundId -ErrorAction SilentlyContinue) {
                    Normalize-LastLightSoundId ([string]$j.LastLightSound)
                } else { [string]$j.LastLightSound }
            }
            if ($j.TonightCardId) {
                $s.TonightCardId = if (Get-Command Normalize-TonightCardId -ErrorAction SilentlyContinue) {
                    Normalize-TonightCardId ([string]$j.TonightCardId)
                } else { [string]$j.TonightCardId }
            }
            if ($null -ne $j.CinemaScreenIndex) { $s.CinemaScreenIndex = [int]$j.CinemaScreenIndex }
            if ($null -ne $j.QuietHoursAutoStart) { $s.QuietHoursAutoStart = [bool]$j.QuietHoursAutoStart }
            if ($j.ClockFaceStyle -in $script:ValidClockFaceIds) { $s.ClockFaceStyle = [string]$j.ClockFaceStyle }
            if ($j.CustomAccentColor) { $s.CustomAccentColor = [string]$j.CustomAccentColor }
            if ($null -ne $j.SmartLightEnabled) { $s.SmartLightEnabled = [bool]$j.SmartLightEnabled }
            if ($j.SmartLightProvider -in @('none', 'hue', 'http')) { $s.SmartLightProvider = [string]$j.SmartLightProvider }
            if ($j.SmartLightMode -in @('gradual_dim', 'warm_dim', 'off_at_end')) { $s.SmartLightMode = [string]$j.SmartLightMode }
            if ($null -ne $j.SmartLightDimMinutes) { $s.SmartLightDimMinutes = [math]::Max(1, [int]$j.SmartLightDimMinutes) }
            if ($j.HueBridgeIp) { $s.HueBridgeIp = [string]$j.HueBridgeIp }
            if ($j.HueUsername) { $s.HueUsername = [string]$j.HueUsername }
            if ($null -ne $j.HueLightIds) { $s.HueLightIds = @($j.HueLightIds | ForEach-Object { [string]$_ }) }
            if ($j.HueGroupId) { $s.HueGroupId = [string]$j.HueGroupId }
            if ($j.HueTargetLabel) { $s.HueTargetLabel = [string]$j.HueTargetLabel }
            if ($j.HttpLightUrl) { $s.HttpLightUrl = [string]$j.HttpLightUrl }
        } catch { }
    }
    return $s
}

function Sync-SmartLightConfig {
    if (-not (Get-Command Set-SmartLightConfig -ErrorAction SilentlyContinue)) { return }
    Set-SmartLightConfig @{
        Provider = [string]$script:SmartLightProvider
        Mode = [string]$script:SmartLightMode
        DimMinutes = [int]$script:SmartLightDimMinutes
        Enabled = [bool]$script:SmartLightEnabled
        HueBridgeIp = [string]$script:HueBridgeIp
        HueUsername = [string]$script:HueUsername
        HueLightIds = @($script:HueLightIds)
        HueGroupId = [string]$script:HueGroupId
        HttpUrl = [string]$script:HttpLightUrl
    }
}

function Get-SmartLightTargetSummary {
    switch ([string]$script:SmartLightProvider) {
        'hue' {
            if (-not $script:HueBridgeIp) { return 'Hue bridge not paired yet.' }
            $label = if ($script:HueTargetLabel) { [string]$script:HueTargetLabel }
                     elseif ($script:HueGroupId) { "Group #$($script:HueGroupId)" }
                     elseif ($script:HueLightIds -and $script:HueLightIds.Count -gt 0) { "Light #$($script:HueLightIds[0])" }
                     else { 'All paired lights' }
            return "Hue: $label on $($script:HueBridgeIp)"
        }
        'http' {
            if (-not $script:HttpLightUrl) { return 'HTTP webhook not configured.' }
            try {
                return "Webhook: $(([Uri]$script:HttpLightUrl).Host)"
            } catch {
                return 'Webhook URL saved.'
            }
        }
        default {
            return 'Choose a provider, then connect lights.'
        }
    }
}

function Update-SmartLightStatusLabel {
    if (-not $script:lblLightStatus -or $script:lblLightStatus.IsDisposed) { return }
    $script:lblLightStatus.Text = Get-SmartLightTargetSummary
}

function Save-SmartLightSettings {
    Sync-SmartLightConfig
    Update-SmartLightStatusLabel
    if (-not $script:Running) { Save-Settings }
}

function Show-HttpLightSetupDialog {
    $dlgHttp = New-Object System.Windows.Forms.Form
    $dlgHttp.Text = 'HTTP Light Setup'
    $dlgHttp.Size = New-Object System.Drawing.Size(440, 152)
    $dlgHttp.StartPosition = 'CenterParent'
    $dlgHttp.FormBorderStyle = 'FixedDialog'
    $dlgHttp.MaximizeBox = $false
    $dlgHttp.MinimizeBox = $false
    $dlgHttp.BackColor = [System.Drawing.Color]::FromArgb(22, 28, 38)

    $dlgHttpLbl = New-Object System.Windows.Forms.Label
    $dlgHttpLbl.Text = 'Webhook URL'
    $dlgHttpLbl.Location = New-Object System.Drawing.Point(12, 14)
    $dlgHttpLbl.AutoSize = $true
    $dlgHttpLbl.ForeColor = [System.Drawing.Color]::FromArgb(200, 210, 220)
    $dlgHttp.Controls.Add($dlgHttpLbl)

    $dlgHttpTxt = New-Object System.Windows.Forms.TextBox
    $dlgHttpTxt.Location = New-Object System.Drawing.Point(12, 36)
    $dlgHttpTxt.Size = New-Object System.Drawing.Size(398, 24)
    $dlgHttpTxt.Text = $script:HttpLightUrl
    $dlgHttpTxt.BackColor = [System.Drawing.Color]::FromArgb(32, 36, 48)
    $dlgHttpTxt.ForeColor = [System.Drawing.Color]::FromArgb(210, 220, 230)
    $dlgHttp.Controls.Add($dlgHttpTxt)

    $dlgHttpCancel = New-Object System.Windows.Forms.Button
    $dlgHttpCancel.Text = 'Cancel'
    $dlgHttpCancel.Location = New-Object System.Drawing.Point(240, 76)
    $dlgHttpCancel.Size = New-Object System.Drawing.Size(80, 28)
    $dlgHttpCancel.DialogResult = 'Cancel'
    Style-Button $dlgHttpCancel ([System.Drawing.Color]::FromArgb(38, 44, 58)) (Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(148, 162, 176))) 8
    $dlgHttp.Controls.Add($dlgHttpCancel)

    $dlgHttpOk = New-Object System.Windows.Forms.Button
    $dlgHttpOk.Text = 'Save'
    $dlgHttpOk.Location = New-Object System.Drawing.Point(330, 76)
    $dlgHttpOk.Size = New-Object System.Drawing.Size(80, 28)
    $dlgHttpOk.DialogResult = 'OK'
    Style-Button $dlgHttpOk ([System.Drawing.Color]::FromArgb(28, 32, 44)) $script:C.Mint 8
    $dlgHttp.AcceptButton = $dlgHttpOk
    $dlgHttp.CancelButton = $dlgHttpCancel
    $dlgHttp.Controls.Add($dlgHttpOk)

    try {
        if ($dlgHttp.ShowDialog() -eq 'OK' -and $dlgHttpTxt.Text.Trim()) {
            $script:HttpLightUrl = $dlgHttpTxt.Text.Trim()
            Save-SmartLightSettings
            [System.Windows.Forms.MessageBox]::Show("Webhook URL saved: $($script:HttpLightUrl)", 'HTTP Setup', 'OK', 'Information') | Out-Null
            return $true
        }
    } finally {
        $dlgHttp.Dispose()
    }
    return $false
}

function Show-HueTargetPicker {
    param(
        [string]$BridgeIp,
        [array]$Groups,
        [array]$Lights
    )

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Connect Lights'
    $dlg.Size = New-Object System.Drawing.Size(540, 428)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.BackColor = [System.Drawing.Color]::FromArgb(18, 24, 34)

    $lblHead = New-Object System.Windows.Forms.Label
    $lblHead.Text = "Hue bridge found at $BridgeIp"
    $lblHead.Location = New-Object System.Drawing.Point(14, 14)
    $lblHead.Size = New-Object System.Drawing.Size(490, 20)
    $lblHead.ForeColor = Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(210, 220, 232))
    $lblHead.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9, [System.Drawing.FontStyle]::Bold)
    $dlg.Controls.Add($lblHead)

    $lblSub = New-Object System.Windows.Forms.Label
    $lblSub.Text = 'Search results include rooms, zones, and individual lights.'
    $lblSub.Location = New-Object System.Drawing.Point(14, 36)
    $lblSub.Size = New-Object System.Drawing.Size(500, 18)
    $lblSub.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(150, 162, 176))
    $dlg.Controls.Add($lblSub)

    $lvTargets = New-Object System.Windows.Forms.ListView
    $lvTargets.Location = New-Object System.Drawing.Point(14, 62)
    $lvTargets.Size = New-Object System.Drawing.Size(494, 280)
    $lvTargets.View = 'Details'
    $lvTargets.FullRowSelect = $true
    $lvTargets.MultiSelect = $false
    $lvTargets.HideSelection = $false
    $lvTargets.GridLines = $true
    $lvTargets.BackColor = [System.Drawing.Color]::FromArgb(28, 32, 44)
    $lvTargets.ForeColor = Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(208, 218, 230))
    [void]$lvTargets.Columns.Add('Target', 218)
    [void]$lvTargets.Columns.Add('Type', 114)
    [void]$lvTargets.Columns.Add('Status', 144)
    $dlg.Controls.Add($lvTargets)

    $allItem = New-Object System.Windows.Forms.ListViewItem('All paired lights')
    [void]$allItem.SubItems.Add('Target')
    [void]$allItem.SubItems.Add("$(@($Lights).Count) lights")
    $allItem.Tag = @{ Kind = 'all'; Label = 'All paired lights' }
    [void]$lvTargets.Items.Add($allItem)

    foreach ($group in @($Groups | Sort-Object Name)) {
        $groupItem = New-Object System.Windows.Forms.ListViewItem([string]$group.Name)
        [void]$groupItem.SubItems.Add([string]$group.Type)
        [void]$groupItem.SubItems.Add(("{0} lights" -f @($group.Lights).Count))
        $groupItem.Tag = @{ Kind = 'group'; Id = [string]$group.Id; Label = [string]$group.Name }
        [void]$lvTargets.Items.Add($groupItem)
    }

    foreach ($light in @($Lights | Sort-Object Name)) {
        $lightItem = New-Object System.Windows.Forms.ListViewItem([string]$light.Name)
        [void]$lightItem.SubItems.Add('Light')
        [void]$lightItem.SubItems.Add($(if ($light.On) { 'On' } else { 'Off' }))
        $lightItem.Tag = @{ Kind = 'light'; Id = [string]$light.Id; Label = [string]$light.Name }
        [void]$lvTargets.Items.Add($lightItem)
    }

    foreach ($item in $lvTargets.Items) {
        $tag = $item.Tag
        if (($script:HueGroupId -and $tag.Kind -eq 'group' -and $tag.Id -eq $script:HueGroupId) -or
            ($script:HueLightIds.Count -gt 0 -and $tag.Kind -eq 'light' -and $tag.Id -eq $script:HueLightIds[0]) -or
            ((-not $script:HueGroupId) -and $script:HueLightIds.Count -eq 0 -and $tag.Kind -eq 'all')) {
            $item.Selected = $true
            $item.Focused = $true
            break
        }
    }
    if ($lvTargets.SelectedItems.Count -eq 0 -and $lvTargets.Items.Count -gt 0) {
        $lvTargets.Items[0].Selected = $true
        $lvTargets.Items[0].Focused = $true
    }

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = 'Cancel'
    $btnCancel.Location = New-Object System.Drawing.Point(340, 352)
    $btnCancel.Size = New-Object System.Drawing.Size(80, 30)
    $btnCancel.DialogResult = 'Cancel'
    Style-Button $btnCancel ([System.Drawing.Color]::FromArgb(38, 44, 58)) (Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(148, 162, 176))) 8
    $dlg.Controls.Add($btnCancel)

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = 'Use selection'
    $btnSave.Location = New-Object System.Drawing.Point(428, 352)
    $btnSave.Size = New-Object System.Drawing.Size(80, 30)
    $btnSave.DialogResult = 'OK'
    Style-Button $btnSave ([System.Drawing.Color]::FromArgb(28, 32, 44)) $script:C.Mint 8
    $dlg.AcceptButton = $btnSave
    $dlg.CancelButton = $btnCancel
    $dlg.Controls.Add($btnSave)

    try {
        if ($dlg.ShowDialog() -ne 'OK') { return $false }
        if ($lvTargets.SelectedItems.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show('Choose a room or light first.', 'Connect Lights', 'OK', 'Information') | Out-Null
            return $false
        }
        $selected = $lvTargets.SelectedItems[0].Tag
        $script:HueGroupId = ''
        $script:HueLightIds = @()
        switch ([string]$selected.Kind) {
            'group' { $script:HueGroupId = [string]$selected.Id }
            'light' { $script:HueLightIds = @([string]$selected.Id) }
        }
        $script:HueTargetLabel = [string]$selected.Label
        return $true
    } finally {
        $dlg.Dispose()
    }
}

function Invoke-HueDeviceSearch {
    param([switch]$ForcePair)

    if (-not (Get-Command Find-HueBridge -ErrorAction SilentlyContinue)) {
        [System.Windows.Forms.MessageBox]::Show('Smart Lights module not loaded.', 'Lights', 'OK', 'Warning') | Out-Null
        return
    }

    $bridge = Find-HueBridge
    if (-not $bridge) {
        [System.Windows.Forms.MessageBox]::Show('No Hue Bridge found on the local network.', 'Connect Lights', 'OK', 'Warning') | Out-Null
        return
    }

    $script:HueBridgeIp = [string]$bridge.Ip
    $groups = @()
    $lights = @()
    $username = [string]$script:HueUsername
    $needPair = $ForcePair.IsPresent -or [string]::IsNullOrWhiteSpace($username)

    if (-not $needPair) {
        $groups = @(Get-HueGroups -BridgeIp $script:HueBridgeIp -Username $username)
        $lights = @(Get-HueLights -BridgeIp $script:HueBridgeIp -Username $username)
        if ($groups.Count -eq 0 -and $lights.Count -eq 0) {
            $needPair = $true
        }
    }

    if ($needPair) {
        [System.Windows.Forms.MessageBox]::Show(
            "Found bridge at $($script:HueBridgeIp)`nPress the link button on the Hue Bridge, then click OK.",
            'Hue Setup', 'OK', 'Information') | Out-Null
        $user = Register-HueBridge -BridgeIp $script:HueBridgeIp
        if ($user -is [string]) {
            $script:HueUsername = $user
        } elseif ($user.Error) {
            [System.Windows.Forms.MessageBox]::Show("Error: $($user.Error)", 'Hue Setup', 'OK', 'Error') | Out-Null
            return
        } else {
            [System.Windows.Forms.MessageBox]::Show('Hue pairing did not complete.', 'Hue Setup', 'OK', 'Warning') | Out-Null
            return
        }
        $groups = @(Get-HueGroups -BridgeIp $script:HueBridgeIp -Username $script:HueUsername)
        $lights = @(Get-HueLights -BridgeIp $script:HueBridgeIp -Username $script:HueUsername)
    }

    if ($groups.Count -eq 0 -and $lights.Count -eq 0) {
        Save-SmartLightSettings
        [System.Windows.Forms.MessageBox]::Show(
            "Hue bridge paired at $($script:HueBridgeIp), but no rooms or lights were returned.",
            'Connect Lights', 'OK', 'Warning') | Out-Null
        return
    }

    if (Show-HueTargetPicker -BridgeIp $script:HueBridgeIp -Groups $groups -Lights $lights) {
        Save-SmartLightSettings
        [System.Windows.Forms.MessageBox]::Show((Get-SmartLightTargetSummary), 'Connect Lights', 'OK', 'Information') | Out-Null
    }
}

function Show-ConnectLightsMenu {
    param([System.Windows.Forms.Control]$Anchor)

    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $menu.ShowImageMargin = $false
    $menu.BackColor = [System.Drawing.Color]::FromArgb(28, 32, 44)
    $menu.ForeColor = Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(208, 218, 230))
    $menu.Add_Closed({ $this.Dispose() })

    switch ([string]$script:SmartLightProvider) {
        'hue' {
            $searchItem = $menu.Items.Add('Search devices')
            $searchItem.Add_Click({ Invoke-HueDeviceSearch })

            $repairItem = $menu.Items.Add('Pair bridge again')
            $repairItem.Add_Click({ Invoke-HueDeviceSearch -ForcePair })

            $allItem = $menu.Items.Add('Use all paired lights')
            $allItem.Enabled = [bool]($script:HueBridgeIp -and $script:HueUsername)
            $allItem.Add_Click({
                $script:HueGroupId = ''
                $script:HueLightIds = @()
                $script:HueTargetLabel = 'All paired lights'
                Save-SmartLightSettings
            })
        }
        'http' {
            $setupItem = $menu.Items.Add('Configure webhook')
            $setupItem.Add_Click({ Show-HttpLightSetupDialog | Out-Null })

            $clearItem = $menu.Items.Add('Clear webhook')
            $clearItem.Enabled = [bool]$script:HttpLightUrl
            $clearItem.Add_Click({
                $script:HttpLightUrl = ''
                Save-SmartLightSettings
            })
        }
        default {
            $hintItem = $menu.Items.Add('Select a provider first')
            $hintItem.Enabled = $false
        }
    }

    $menu.Show($Anchor, 0, $Anchor.Height)
}

function Save-Settings {
    if ($script:DemoMode) { return }
    if (-not (Test-Path $script:SettingsDir)) {
        New-Item -ItemType Directory -Path $script:SettingsDir -Force | Out-Null
    }
    Sync-SmartLightConfig
    try { Set-RunAtLogin -Enabled $chkLogin.Checked } catch { }
    @{
        DefaultSeconds = $script:DefaultSec
        Action         = $script:Action
        ConfirmAtEnd   = $true
        AutoStart      = $script:AutoStartOnOpen
        TopMost        = $chkTop.Checked
        WarnAt5Min     = $chkWarn5.Checked
        RunAtLogin     = $chkLogin.Checked
        MinimizeToTray    = $chkMinTray.Checked
        EmitLuxGridEvents = $chkLuxGrid.Checked
        GracefulShutdown  = $chkGraceful.Checked
        TimerMode           = $script:TimerMode
        ClockTime           = if ($script:UiReady -and $script:dtpClock) { $script:dtpClock.Value.ToString('HH:mm') } else { $script:ClockTime }
        ScheduledAt         = if ($script:ScheduledAt) { ([DateTime]$script:ScheduledAt).ToString('o') } else { '' }
        CalendarSource      = $script:CalendarSource
        CalendarEventUid    = $script:CalendarEventUid
        CalendarEventTitle  = $script:CalendarEventTitle
        WarnPowerBlockers = $script:chkPowerWarn.Checked
        QuickWarnPanel    = $chkQuick.Checked
        DimPhaseEnabled   = $script:chkDimPhase.Checked
        DimPhaseSeconds   = $script:DimPhaseSec
        PactEnabled       = $script:chkPact.Checked
        PactTime          = if ($script:dtpPact) { $script:dtpPact.Value.ToString('HH:mm') } else { $script:PactTime }
        LastRitualId      = $script:LastRitualId
        LastProfileId     = $script:LastProfileId
        SavedTimers       = @($script:SavedTimers)
        CalendarFeedUrl           = $script:CalendarFeedUrl
        CalendarFeedIntervalMin   = $script:CalendarFeedIntervalMin
        CalendarFeedAutoStart     = $script:CalendarFeedAutoStart
        CalendarFeedLastSync      = $script:CalendarFeedLastSync
        UiTheme                   = $script:UiTheme
        BigPictureOnStart         = $script:BigPictureOnStart
        LastAchievementStreak     = $script:LastAchievementStreak
        MorningProofLastSeen      = $script:MorningProofLastSeen
        LastLightEnabled          = [bool]$script:LastLightEnabled
        LastLightSequence         = if (Get-Command Normalize-LastLightSequenceId -ErrorAction SilentlyContinue) {
            Normalize-LastLightSequenceId $script:LastLightSequence
        } else { [string]$script:LastLightSequence }
        LastLightUseCinema        = [bool]$script:LastLightUseCinema
        LastLightLuxPulse         = [bool]$script:LastLightLuxPulse
        LastLightSound            = if (Get-Command Normalize-LastLightSoundId -ErrorAction SilentlyContinue) {
            Normalize-LastLightSoundId $script:LastLightSound
        } else { [string]$script:LastLightSound }
        TonightCardId             = if (Get-Command Normalize-TonightCardId -ErrorAction SilentlyContinue) {
            Normalize-TonightCardId $script:TonightCardId
        } else { [string]$script:TonightCardId }
        CinemaScreenIndex         = $script:CinemaScreenIndex
        QuietHoursAutoStart       = $script:QuietHoursAutoStart
        ClockFaceStyle            = $script:ClockFaceStyle
        CustomAccentColor         = if ($script:CustomAccentColor) { '{0},{1},{2}' -f $script:CustomAccentColor.R, $script:CustomAccentColor.G, $script:CustomAccentColor.B } else { '' }
        SmartLightEnabled         = [bool]$script:SmartLightEnabled
        SmartLightProvider        = [string]$script:SmartLightProvider
        SmartLightMode            = [string]$script:SmartLightMode
        SmartLightDimMinutes      = [int]$script:SmartLightDimMinutes
        HueBridgeIp               = [string]$script:HueBridgeIp
        HueUsername               = [string]$script:HueUsername
        HueLightIds               = @($script:HueLightIds)
        HueGroupId                = [string]$script:HueGroupId
        HueTargetLabel            = [string]$script:HueTargetLabel
        HttpLightUrl              = [string]$script:HttpLightUrl
        DryRun            = $false
    } | ConvertTo-Json -Depth 6 | Set-Content $script:SettingsPath -Encoding UTF8
    $script:EmitLuxGridEvents = $chkLuxGrid.Checked
    $script:GracefulShutdown = $chkGraceful.Checked
    $script:WarnPowerBlockers = $script:chkPowerWarn.Checked
    $script:QuickWarnPanel = $chkQuick.Checked
    if ($script:chkDimPhase) { $script:DimPhaseEnabled = $script:chkDimPhase.Checked }
    if ($script:chkLastLight) { $script:LastLightEnabled = $script:chkLastLight.Checked }
    if ($script:cboLastLight -and $script:cboLastLight.SelectedItem) {
        $script:LastLightSequence = Normalize-LastLightSequenceId ([string]$script:cboLastLight.SelectedItem.Id)
    }
    if ($script:chkLastLightCinema) { $script:LastLightUseCinema = $script:chkLastLightCinema.Checked }
    if ($script:cboLastLightSound -and $script:cboLastLightSound.SelectedItem) {
        $script:LastLightSound = Normalize-LastLightSoundId ([string]$script:cboLastLightSound.SelectedItem.Id)
    }
    $script:TonightCardId = if (Get-Command Normalize-TonightCardId -ErrorAction SilentlyContinue) {
        Normalize-TonightCardId $script:TonightCardId
    } else { [string]$script:TonightCardId }
    if ($script:chkPact) { $script:PactEnabled = $script:chkPact.Checked }
    if ($script:dtpPact) { $script:PactTime = $script:dtpPact.Value.ToString('HH:mm') }
    if ($script:UiReady -and $script:dtpClock) { $script:ClockTime = $script:dtpClock.Value.ToString('HH:mm') }
}

function Enable-DoubleBuffer {
    param($Control)
    $flags = [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic
    $prop = $Control.GetType().GetProperty('DoubleBuffered', $flags)
    if ($prop) { $prop.SetValue($Control, $true, $null) }
}

function Coalesce-UiColor {
    param($Preferred, $Fallback)
    if ($null -eq $Preferred) { return $Fallback }
    return $Preferred
}

function Get-UiColor {
    param(
        [string]$Key,
        [System.Drawing.Color]$Fallback
    )
    if (-not $script:C -or $script:C.Count -eq 0) {
        Initialize-LightsOutThemePalette -Name $(if ($script:UiTheme) { $script:UiTheme } else { 'steam' })
    }
    if ($script:C -and $script:C.ContainsKey($Key)) {
        return Coalesce-UiColor $script:C[$Key] $Fallback
    }
    return $Fallback
}

function Style-Button {
    param($B, $Bg, $Fg, [int]$Size = 9, $Hover = $null, [int]$Border = 0)
# Do not use $script:C in param defaults - they bind at parse time when $C is still empty.
    $Fg = Coalesce-UiColor $Fg (Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224)))
    $Bg = Coalesce-UiColor $Bg (Get-UiColor 'Elevated' ([System.Drawing.Color]::FromArgb(42, 71, 94)))
    $B.FlatStyle = 'Flat'
    $B.FlatAppearance.BorderSize = $Border
    if ($Border -gt 0) {
        $borderClr = Get-UiColor 'Border' ([System.Drawing.Color]::FromArgb(42, 71, 94))
        $B.FlatAppearance.BorderColor = $borderClr
    }
    $B.BackColor = $Bg
    $B.ForeColor = $Fg
    try {
        $B.Font = New-Object System.Drawing.Font('Segoe UI', $Size, [System.Drawing.FontStyle]::Bold)
    } catch {
        $B.Font = New-Object System.Drawing.Font('Segoe UI', $Size)
    }
    $B.Cursor = [System.Windows.Forms.Cursors]::Hand
    if ($null -ne $Hover) { $B.FlatAppearance.MouseOverBackColor = $Hover }
    $B.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(
        [math]::Max(0, $Bg.R - 18),
        [math]::Max(0, $Bg.G - 18),
        [math]::Max(0, $Bg.B - 18))
}

function Set-SectionLabelStyle {
    param($Label, [string]$Text)
    $Label.Text = if ($script:UseSteamUi) { $Text } else { $Text.ToUpper() }
    $Label.Font = New-Object System.Drawing.Font('Segoe UI Semibold', $(if ($script:UseSteamUi) { 8.5 } else { 7.5 }), [System.Drawing.FontStyle]::Bold)
    $Label.ForeColor = Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))
    $Label.BackColor = [System.Drawing.Color]::Transparent
}

function New-UiDivider {
    param([int]$X, [int]$Y, [int]$W = 372)
    $d = New-Object System.Windows.Forms.Panel
    $d.Location = New-Object System.Drawing.Point($X, $Y)
    $d.Size = New-Object System.Drawing.Size($W, 2)
    $d.BackColor = [System.Drawing.Color]::Transparent
    Enable-DoubleBuffer $d
    $d.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $accent = Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(118, 201, 255))
        $pen1 = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(20, $accent.R, $accent.G, $accent.B)), 1
        $g.DrawLine($pen1, 0, 0, $s.Width, 0)
        $pen1.Dispose()
        $pen2 = New-Object System.Drawing.Pen (Get-UiColor 'Border' ([System.Drawing.Color]::FromArgb(42, 71, 94))), 1
        $g.DrawLine($pen2, 0, 1, $s.Width, 1)
        $pen2.Dispose()
    })
    return $d
}

function Apply-SteamSurfaceStyle {
    param(
        $Panel,
        [string]$AccentKey = 'Section'
    )
    if (-not $script:UseSteamUi -or -not $Panel) { return }
    Enable-DoubleBuffer $Panel
    $accentColor = Get-UiColor $AccentKey (Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244)))
    $Panel.Add_Paint({
        param($sender, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $w = $sender.Width; $h = $sender.Height
        $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush (
            (New-Object System.Drawing.Rectangle 0, 0, $w, $h),
            [System.Drawing.Color]::FromArgb(16, 24, 36),
            (Get-UiColor 'Card' ([System.Drawing.Color]::FromArgb(22, 32, 45))),
            90)
        $g.FillRectangle($grad, 0, 0, $w, $h)
        $grad.Dispose()
        $sheen = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(18, $accentColor.R, $accentColor.G, $accentColor.B))
        $g.FillRectangle($sheen, 0, 0, $w, [math]::Min(18, $h))
        $sheen.Dispose()
        $border = Get-UiColor 'Border' ([System.Drawing.Color]::FromArgb(42, 71, 94))
        $pen = New-Object System.Drawing.Pen $border
        $g.DrawRectangle($pen, 0, 0, ($w - 1), ($h - 1))
        $pen.Dispose()
        $acPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(80, $accentColor.R, $accentColor.G, $accentColor.B)), 1
        $g.DrawLine($acPen, 1, 0, ($w - 2), 0)
        $acPen.Dispose()
    }.GetNewClosure())
}

function Get-TonightCardAccentColor {
    param([string]$Accent = 'calm')
    switch ($Accent) {
        'hard' { return Get-UiColor 'Rose' ([System.Drawing.Color]::FromArgb(255, 107, 107)) }
        'dream' { return Get-UiColor 'Mint' ([System.Drawing.Color]::FromArgb(104, 225, 186)) }
        'focus' { return Get-UiColor 'Blue' ([System.Drawing.Color]::FromArgb(126, 176, 255)) }
        'custom' { return Get-UiColor 'Violet' ([System.Drawing.Color]::FromArgb(186, 154, 255)) }
        default { return Get-UiColor 'Amber' ([System.Drawing.Color]::FromArgb(242, 185, 93)) }
    }
}

function Style-TonightCardButton {
    param($Button, [bool]$Selected)
    if (-not $Button) { return }
    $card = $Button.Tag
    $accent = Get-TonightCardAccentColor $(if ($card) { [string]$card.Accent } else { 'calm' })
    $Button.FlatStyle = 'Flat'
    $Button.FlatAppearance.BorderSize = 1
    $Button.UseCompatibleTextRendering = $true
    $Button.TextAlign = 'TopLeft'
    $Button.Padding = New-Object System.Windows.Forms.Padding(10, 8, 8, 6)
    if ($Selected) {
        $Button.BackColor = [System.Drawing.Color]::FromArgb(42, $accent.R, $accent.G, $accent.B)
        $Button.ForeColor = Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
        $Button.FlatAppearance.BorderColor = $accent
        $Button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(56, $accent.R, $accent.G, $accent.B)
        $Button.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(70, $accent.R, $accent.G, $accent.B)
    } else {
        $Button.BackColor = Get-UiColor 'NavOff' ([System.Drawing.Color]::FromArgb(46, 54, 64))
        $Button.ForeColor = Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
        $Button.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(92, $accent.R, $accent.G, $accent.B)
        $Button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(26, $accent.R, $accent.G, $accent.B)
        $Button.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(38, $accent.R, $accent.G, $accent.B)
    }
}

function Update-StartButtonStyle {
    if (-not $script:btnStartUi) { return }
    $b = $script:btnStartUi
    if ($script:Running) {
        Style-Button $b $script:C.Elevated $script:C.Muted 10
        $b.FlatAppearance.BorderSize = 1
        $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(60, 70, 90)
        $b.Enabled = $false
        if ($script:UseSteamUi) { $b.Text = 'IN GAME' }
        return
    }
    if ($script:UseSteamUi) {
        if (-not $b.Text -or $b.Text -eq 'Running') { $b.Text = 'PLAY' }
        $play = Get-UiColor 'Play' ([System.Drawing.Color]::FromArgb(117, 176, 34))
        $playHover = Get-UiColor 'PlayHover' ([System.Drawing.Color]::FromArgb(142, 214, 41))
        Style-Button $b $play ([System.Drawing.Color]::FromArgb(12, 22, 8)) 11 $playHover 1
        $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(
            [math]::Min(255, $play.R + 40),
            [math]::Min(255, $play.G + 40),
            [math]::Min(255, $play.B + 20))
        $b.Enabled = $true
        return
    }
    $accent = Get-ActionAccentColor
    $fg = [System.Drawing.Color]::FromArgb(14, 14, 12)
    $hover = [System.Drawing.Color]::FromArgb(
        [math]::Min(255, $accent.R + 28),
        [math]::Min(255, $accent.G + 28),
        [math]::Min(255, $accent.B + 28))
    Style-Button $b $accent $fg 10 $hover 1
    $b.FlatAppearance.BorderColor = $accent
    $b.Enabled = $true
}

function Set-Action {
    param([string]$Name)
    Mark-TonightCardCustom
    $script:Action = $Name
    foreach ($p in $script:Pills) {
        $on = ($p.Tag -eq $Name)
        $p.FlatStyle = 'Flat'
        $p.FlatAppearance.BorderSize = 1
        if ($on) {
            $accent = switch ($Name) {
                'Sleep' { Get-UiColor 'Mint' ([System.Drawing.Color]::FromArgb(102, 192, 244)) }
                'Restart' { Get-UiColor 'Blue' ([System.Drawing.Color]::FromArgb(102, 192, 244)) }
                'Hibernate' { Get-UiColor 'Violet' ([System.Drawing.Color]::FromArgb(177, 152, 255)) }
                'Lock' { Get-UiColor 'Slate' ([System.Drawing.Color]::FromArgb(143, 152, 160)) }
                default { Get-UiColor 'Amber' ([System.Drawing.Color]::FromArgb(164, 208, 7)) }
            }
            $p.BackColor = $accent
            $p.ForeColor = [System.Drawing.Color]::FromArgb(14, 12, 10)
            $p.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(
                [math]::Min(255, $accent.R + 40),
                [math]::Min(255, $accent.G + 40),
                [math]::Min(255, $accent.B + 40))
            $p.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(
                [math]::Min(255, $accent.R + 20),
                [math]::Min(255, $accent.G + 20),
                [math]::Min(255, $accent.B + 20))
        } else {
            $off = if ($script:UseSteamUi) {
                Get-UiColor 'NavOff' ([System.Drawing.Color]::FromArgb(46, 54, 64))
            } else {
                [System.Drawing.Color]::FromArgb(32, 32, 44)
            }
            $p.BackColor = $off
            $p.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
            $p.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(56, 66, 82)
            $p.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(56, 66, 82)
        }
    }
    if (-not $script:Running -and $script:UiReady) { Save-Settings }
    Update-GracefulCheckbox
    Update-Ui
}

function Get-ActionAccentColor {
    switch ($script:Action) {
        'Sleep' { return Get-UiColor 'Mint' ([System.Drawing.Color]::FromArgb(102, 192, 244)) }
        'Restart' { return Get-UiColor 'Blue' ([System.Drawing.Color]::FromArgb(102, 192, 244)) }
        'Hibernate' { return Get-UiColor 'Violet' ([System.Drawing.Color]::FromArgb(177, 152, 255)) }
        'Lock' { return Get-UiColor 'Slate' ([System.Drawing.Color]::FromArgb(143, 152, 160)) }
        default { return Get-UiColor 'Amber' ([System.Drawing.Color]::FromArgb(164, 208, 7)) }
    }
}

function Blend-UiColor {
    param(
        [System.Drawing.Color]$From,
        [System.Drawing.Color]$To,
        [double]$Mix = 0.5
    )
    $Mix = [math]::Max(0.0, [math]::Min(1.0, $Mix))
    $keep = 1.0 - $Mix
    return [System.Drawing.Color]::FromArgb(
        [int]([math]::Round(($From.A * $keep) + ($To.A * $Mix))),
        [int]([math]::Round(($From.R * $keep) + ($To.R * $Mix))),
        [int]([math]::Round(($From.G * $keep) + ($To.G * $Mix))),
        [int]([math]::Round(($From.B * $keep) + ($To.B * $Mix))))
}

function Get-CountdownMotionProfile {
    $urgency = Get-CountdownUrgencyLevel
    if ($script:Paused) {
        return @{
            PulseStep           = 0.0
            BreathStep          = 0.020
            ArcWidth            = 12.0
            ArcPulseScale       = 0.0
            HaloAlpha           = 10
            OuterGlowBase       = 8
            OuterGlowPulseScale = 0
            HeadGlowBase        = 0
            HeadGlowPulseScale  = 0
            HeadRadius          = 0
            AccentMix           = 0.20
            TrackAlpha          = 255
        }
    }
    switch ($urgency) {
        'critical' {
            return @{
                PulseStep           = 0.125
                BreathStep          = 0.060
                ArcWidth            = 12.5
                ArcPulseScale       = 4.5
                HaloAlpha           = 34
                OuterGlowBase       = 16
                OuterGlowPulseScale = 28
                HeadGlowBase        = 26
                HeadGlowPulseScale  = 54
                HeadRadius          = 7.5
                AccentMix           = 1.0
                TrackAlpha          = 255
            }
        }
        'final' {
            return @{
                PulseStep           = 0.070
                BreathStep          = 0.042
                ArcWidth            = 12.0
                ArcPulseScale       = 2.4
                HaloAlpha           = 22
                OuterGlowBase       = 12
                OuterGlowPulseScale = 18
                HeadGlowBase        = 18
                HeadGlowPulseScale  = 28
                HeadRadius          = 6.0
                AccentMix           = 0.72
                TrackAlpha          = 248
            }
        }
        'soon' {
            return @{
                PulseStep           = 0.032
                BreathStep          = 0.032
                ArcWidth            = 11.5
                ArcPulseScale       = 1.3
                HaloAlpha           = 14
                OuterGlowBase       = 8
                OuterGlowPulseScale = 10
                HeadGlowBase        = 10
                HeadGlowPulseScale  = 14
                HeadRadius          = 5.0
                AccentMix           = 0.38
                TrackAlpha          = 238
            }
        }
        'calm' {
            return @{
                PulseStep           = 0.012
                BreathStep          = 0.024
                ArcWidth            = 11.0
                ArcPulseScale       = 0.6
                HaloAlpha           = 8
                OuterGlowBase       = 4
                OuterGlowPulseScale = 6
                HeadGlowBase        = 8
                HeadGlowPulseScale  = 8
                HeadRadius          = 4.0
                AccentMix           = 0.12
                TrackAlpha          = 230
            }
        }
        default {
            return @{
                PulseStep           = 0.0
                BreathStep          = 0.018
                ArcWidth            = 10.5
                ArcPulseScale       = 0.0
                HaloAlpha           = 0
                OuterGlowBase       = 0
                OuterGlowPulseScale = 0
                HeadGlowBase        = 0
                HeadGlowPulseScale  = 0
                HeadRadius          = 0
                AccentMix           = 0.0
                TrackAlpha          = 220
            }
        }
    }
}

function Get-CountdownPulseValue {
    $wave = 0.5 + (0.5 * [math]::Sin($script:PulsePhase * [math]::PI * 2.0))
    if ($script:Running -and $script:Left -le 30) {
        return [math]::Pow($wave, 2.2)
    }
    return $wave
}

function Get-CountdownAccentColor {
    $baseAccent = if ($script:CustomAccentColor) { $script:CustomAccentColor } else { Get-ActionAccentColor }
    if (-not $script:Running) {
        return $baseAccent
    }
    $profile = Get-CountdownMotionProfile
    $warnAccent = if ($script:Left -le 30) {
        Get-UiColor 'Rose' ([System.Drawing.Color]::FromArgb(255, 107, 107))
    } elseif ($script:Left -le 60) {
        Blend-UiColor (Get-UiColor 'Amber' ([System.Drawing.Color]::FromArgb(164, 208, 7))) (Get-UiColor 'Rose' ([System.Drawing.Color]::FromArgb(255, 107, 107))) 0.65
    } elseif ($script:Left -le 300) {
        Get-UiColor 'Amber' ([System.Drawing.Color]::FromArgb(164, 208, 7))
    } else {
        $baseAccent
    }
    $accent = Blend-UiColor $baseAccent $warnAccent $profile.AccentMix
    if ($script:Paused) {
        return Blend-UiColor $accent (Get-UiColor 'Slate' ([System.Drawing.Color]::FromArgb(162, 174, 194))) 0.25
    }
    if ($script:Running -and $script:Left -le 60) {
        $pulse = Get-CountdownPulseValue
        return Blend-UiColor $accent (Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(236, 242, 249))) (0.10 + (0.18 * $pulse))
    }
    return $accent
}

function Get-RingColor { Get-CountdownAccentColor }

function Get-CountdownUrgencyLevel {
    if (-not $script:Running) { return 'idle' }
    if ($script:Left -le 30) { return 'critical' }
    if ($script:Left -le 60) { return 'final' }
    if ($script:Left -le 300) { return 'soon' }
    return 'calm'
}

function Get-UrgencyRingBackColor {
    if ($script:UseSteamUi) {
        switch (Get-CountdownUrgencyLevel) {
            'critical' { return [System.Drawing.Color]::FromArgb(48, 28, 32) }
            'final' { return [System.Drawing.Color]::FromArgb(40, 32, 36) }
            'soon' { return [System.Drawing.Color]::FromArgb(32, 36, 44) }
            default { return Get-UiColor 'RingCard' ([System.Drawing.Color]::FromArgb(23, 26, 33)) }
        }
    }
    switch (Get-CountdownUrgencyLevel) {
        'critical' { return [System.Drawing.Color]::FromArgb(28, 14, 16) }
        'final' { return [System.Drawing.Color]::FromArgb(24, 16, 18) }
        'soon' { return [System.Drawing.Color]::FromArgb(20, 18, 14) }
        default { return Get-UiColor 'RingCard' ([System.Drawing.Color]::FromArgb(16, 16, 24)) }
    }
}

function Get-ClockFaceStyles {
    return @(
        [pscustomobject]@{ Id = 'Analog'; Name = 'Analog (ticks + hand)' }
        [pscustomobject]@{ Id = 'Minimal'; Name = 'Minimal (ring only)' }
        [pscustomobject]@{ Id = 'Digital'; Name = 'Digital (no hand)' }
        [pscustomobject]@{ Id = 'Numerals'; Name = 'Numerals (12h markers)' }
        [pscustomobject]@{ Id = 'Dots'; Name = 'Dots (dot markers)' }
        [pscustomobject]@{ Id = 'Roman'; Name = 'Roman (I-XII)' }
        [pscustomobject]@{ Id = 'Military'; Name = '24h (military)' }
    )
}

$script:ValidClockFaceIds = @('Analog', 'Minimal', 'Digital', 'Numerals', 'Dots', 'Roman', 'Military')

function Draw-RingFace-Analog {
    param($G, [int]$Cx, [int]$Cy, [int]$Radius, [DateTime]$TargetWhen)
    $tickColor = if ($script:UseSteamUi) {
        [System.Drawing.Color]::FromArgb(90, 100, 120)
    } else {
        [System.Drawing.Color]::FromArgb(72, 82, 98)
    }
    $majorQuarter = if ($script:UseSteamUi) {
        Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))
    } else {
        [System.Drawing.Color]::FromArgb(110, 122, 140)
    }
    for ($i = 0; $i -lt 12; $i++) {
        $rad = (($i * 30.0) - 90.0) * [math]::PI / 180.0
        $isQuarter = ($i % 3 -eq 0)
        $len = if ($isQuarter) { 9 } else { 5 }
        $w = if ($isQuarter) { 2.0 } else { 1.0 }
        $clr = if ($isQuarter) { $majorQuarter } else { $tickColor }
        $rOut = $Radius - 8
        $rIn = $rOut - $len
        $pen = New-Object System.Drawing.Pen $clr, $w
        $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $G.DrawLine($pen, ($Cx + $rOut * [math]::Cos($rad)), ($Cy + $rOut * [math]::Sin($rad)), `
            ($Cx + $rIn * [math]::Cos($rad)), ($Cy + $rIn * [math]::Sin($rad)))
        $pen.Dispose()
    }
    Draw-ClockHand $G $Cx $Cy $Radius $TargetWhen
}

function Draw-RingFace-Numerals {
    param($G, [int]$Cx, [int]$Cy, [int]$Radius, [DateTime]$TargetWhen)
    $numColor = if ($script:UseSteamUi) {
        Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
    } else {
        [System.Drawing.Color]::FromArgb(100, 112, 130)
    }
    $majorColor = if ($script:UseSteamUi) {
        Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))
    } else {
        [System.Drawing.Color]::FromArgb(130, 142, 160)
    }
    $font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = 'Center'
    $sf.LineAlignment = 'Center'
    for ($i = 1; $i -le 12; $i++) {
        $rad = (($i * 30.0) - 90.0) * [math]::PI / 180.0
        $rPos = $Radius - 16
        $nx = $Cx + $rPos * [math]::Cos($rad)
        $ny = $Cy + $rPos * [math]::Sin($rad)
        $isQuarter = ($i % 3 -eq 0)
        $brush = New-Object System.Drawing.SolidBrush $(if ($isQuarter) { $majorColor } else { $numColor })
        $G.DrawString("$i", $font, $brush, $nx, $ny, $sf)
        $brush.Dispose()
    }
    $font.Dispose()
    $sf.Dispose()
    Draw-ClockHand $G $Cx $Cy $Radius $TargetWhen
}

function Draw-RingFace-Digital {
    param($G, [int]$Cx, [int]$Cy, [int]$Radius, [DateTime]$TargetWhen)
    $tickColor = if ($script:UseSteamUi) {
        [System.Drawing.Color]::FromArgb(60, 70, 86)
    } else {
        [System.Drawing.Color]::FromArgb(50, 58, 72)
    }
    for ($i = 0; $i -lt 12; $i++) {
        $rad = (($i * 30.0) - 90.0) * [math]::PI / 180.0
        $isQuarter = ($i % 3 -eq 0)
        if (-not $isQuarter) { continue }
        $rOut = $Radius - 8
        $rIn = $rOut - 4
        $pen = New-Object System.Drawing.Pen $tickColor, 1.5
        $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $G.DrawLine($pen, ($Cx + $rOut * [math]::Cos($rad)), ($Cy + $rOut * [math]::Sin($rad)), `
            ($Cx + $rIn * [math]::Cos($rad)), ($Cy + $rIn * [math]::Sin($rad)))
        $pen.Dispose()
    }
}

function Draw-RingFace-Minimal {
    param($G, [int]$Cx, [int]$Cy, [int]$Radius, [DateTime]$TargetWhen)
}

function Draw-RingFace-Dots {
    param($G, [int]$Cx, [int]$Cy, [int]$Radius, [DateTime]$TargetWhen)
    $dotColor = if ($script:UseSteamUi) {
        [System.Drawing.Color]::FromArgb(80, 90, 110)
    } else {
        [System.Drawing.Color]::FromArgb(62, 72, 88)
    }
    $majorColor = if ($script:UseSteamUi) {
        Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))
    } else {
        [System.Drawing.Color]::FromArgb(110, 122, 140)
    }
    for ($i = 0; $i -lt 12; $i++) {
        $rad = (($i * 30.0) - 90.0) * [math]::PI / 180.0
        $isQuarter = ($i % 3 -eq 0)
        $dotSz = if ($isQuarter) { 6 } else { 3 }
        $rPos = $Radius - 12
        $dx = $Cx + $rPos * [math]::Cos($rad) - ($dotSz / 2)
        $dy = $Cy + $rPos * [math]::Sin($rad) - ($dotSz / 2)
        $brush = New-Object System.Drawing.SolidBrush $(if ($isQuarter) { $majorColor } else { $dotColor })
        $G.FillEllipse($brush, $dx, $dy, $dotSz, $dotSz)
        $brush.Dispose()
    }
    Draw-ClockHand $G $Cx $Cy $Radius $TargetWhen
}

function Draw-RingFace-Roman {
    param($G, [int]$Cx, [int]$Cy, [int]$Radius, [DateTime]$TargetWhen)
    $romans = @('XII','I','II','III','IV','V','VI','VII','VIII','IX','X','XI')
    $numColor = if ($script:UseSteamUi) {
        Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
    } else {
        [System.Drawing.Color]::FromArgb(100, 112, 130)
    }
    $majorColor = if ($script:UseSteamUi) {
        Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))
    } else {
        [System.Drawing.Color]::FromArgb(130, 142, 160)
    }
    $font = New-Object System.Drawing.Font('Segoe UI', 7, [System.Drawing.FontStyle]::Bold)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = 'Center'
    $sf.LineAlignment = 'Center'
    for ($i = 0; $i -lt 12; $i++) {
        $rad = (($i * 30.0) - 90.0) * [math]::PI / 180.0
        $rPos = $Radius - 16
        $nx = $Cx + $rPos * [math]::Cos($rad)
        $ny = $Cy + $rPos * [math]::Sin($rad)
        $isQuarter = ($i % 3 -eq 0)
        $brush = New-Object System.Drawing.SolidBrush $(if ($isQuarter) { $majorColor } else { $numColor })
        $G.DrawString($romans[$i], $font, $brush, $nx, $ny, $sf)
        $brush.Dispose()
    }
    $font.Dispose()
    $sf.Dispose()
    Draw-ClockHand $G $Cx $Cy $Radius $TargetWhen
}

function Draw-RingFace-Military {
    param($G, [int]$Cx, [int]$Cy, [int]$Radius, [DateTime]$TargetWhen)
    $numColor = if ($script:UseSteamUi) {
        Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
    } else {
        [System.Drawing.Color]::FromArgb(90, 100, 118)
    }
    $majorColor = if ($script:UseSteamUi) {
        Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))
    } else {
        [System.Drawing.Color]::FromArgb(120, 132, 150)
    }
    $font = New-Object System.Drawing.Font('Consolas', 7)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = 'Center'
    $sf.LineAlignment = 'Center'
    $hours24 = @(0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22)
    for ($i = 0; $i -lt 12; $i++) {
        $rad = (($i * 30.0) - 90.0) * [math]::PI / 180.0
        $rPos = $Radius - 16
        $nx = $Cx + $rPos * [math]::Cos($rad)
        $ny = $Cy + $rPos * [math]::Sin($rad)
        $h = $hours24[$i]
        $txt = '{0:D2}' -f $h
        $isQuarter = ($i % 3 -eq 0)
        $brush = New-Object System.Drawing.SolidBrush $(if ($isQuarter) { $majorColor } else { $numColor })
        $G.DrawString($txt, $font, $brush, $nx, $ny, $sf)
        $brush.Dispose()
    }
    $font.Dispose()
    $sf.Dispose()
    Draw-ClockHand $G $Cx $Cy $Radius $TargetWhen
}

function Draw-ClockHand {
    param($G, [int]$Cx, [int]$Cy, [int]$Radius, [DateTime]$TargetWhen)
    $handRad = Get-ClockHandAngleRad $TargetWhen
    $handLen = [int]($Radius * 0.50)
    $hx = $Cx + $handLen * [math]::Cos($handRad)
    $hy = $Cy + $handLen * [math]::Sin($handRad)
    $handColor = if ($script:UseSteamUi) {
        $accent = Get-CountdownAccentColor
        if ($script:Running -or $script:Paused) {
            [System.Drawing.Color]::FromArgb(235, $accent.R, $accent.G, $accent.B)
        } else {
            Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
        }
    } else {
        Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
    }
    if ($script:UseSteamUi) {
        $glowPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(36, $handColor.R, $handColor.G, $handColor.B)), 5
        $glowPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $glowPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $G.DrawLine($glowPen, $Cx, $Cy, $hx, $hy)
        $glowPen.Dispose()
    }
    $handPen = New-Object System.Drawing.Pen $handColor, $(if ($script:UseSteamUi) { 2.5 } else { 2.0 })
    $handPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $handPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $G.DrawLine($handPen, $Cx, $Cy, $hx, $hy)
    $handPen.Dispose()
    $dot = [math]::Max(3, [int]($Radius * 0.07))
    $dotBrush = New-Object System.Drawing.SolidBrush $handColor
    $G.FillEllipse($dotBrush, ($Cx - ($dot / 2)), ($Cy - ($dot / 2)), $dot, $dot)
    $dotBrush.Dispose()
}

function Draw-RingAnalogFace {
    param($G, [int]$Cx, [int]$Cy, [int]$Radius, [DateTime]$TargetWhen)
    switch ($script:ClockFaceStyle) {
        'Minimal'  { Draw-RingFace-Minimal $G $Cx $Cy $Radius $TargetWhen }
        'Digital'  { Draw-RingFace-Digital $G $Cx $Cy $Radius $TargetWhen }
        'Numerals' { Draw-RingFace-Numerals $G $Cx $Cy $Radius $TargetWhen }
        'Dots'     { Draw-RingFace-Dots $G $Cx $Cy $Radius $TargetWhen }
        'Roman'    { Draw-RingFace-Roman $G $Cx $Cy $Radius $TargetWhen }
        'Military' { Draw-RingFace-Military $G $Cx $Cy $Radius $TargetWhen }
        default    { Draw-RingFace-Analog $G $Cx $Cy $Radius $TargetWhen }
    }
}

function Draw-Ring {
    param($G, [int]$W, [int]$H)
    $G.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $G.Clear((Get-UrgencyRingBackColor))

    $card = New-Object System.Drawing.Rectangle 8, 8, ($W - 16), ($H - 16)
    $cardInner = if ($script:UseSteamUi) { $script:C.Card } else { [System.Drawing.Color]::FromArgb(28, 28, 40) }
    $cardBrush = New-Object System.Drawing.SolidBrush $cardInner
    $G.FillEllipse($cardBrush, $card)
    $cardBrush.Dispose()

    $cx = [int]($W / 2)
    $cy = [int]($H / 2)
    $tickRadius = [int](($W - 28) / 2)
    $targetWhen = if ($script:RingTargetDateTime) { [DateTime]$script:RingTargetDateTime } else { Get-RingTargetDateTime }
    Draw-RingAnalogFace $G $cx $cy $tickRadius $targetWhen

    $accent = Get-CountdownAccentColor
    $profile = Get-CountdownMotionProfile
    $pulse = Get-CountdownPulseValue
    $glowA = if ($script:Running -or $script:Paused) {
        [int]($profile.HaloAlpha + (6 * $pulse))
    } else { 0 }
    if ($glowA -gt 0) {
        $glowBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($glowA, $accent.R, $accent.G, $accent.B))
        $haloInset = [int][math]::Max(14, 18 - (2 * $pulse))
        $glowRect = New-Object System.Drawing.Rectangle $haloInset, $haloInset, ($W - ($haloInset * 2)), ($H - ($haloInset * 2))
        $G.FillEllipse($glowBrush, $glowRect)
        $glowBrush.Dispose()
    }

    $rect = New-Object System.Drawing.Rectangle(14, 14, ($W - 28), ($H - 28))

    $breathVal = [math]::Sin($script:BreathPhase)
    $breathAlpha = [int](6 + 6 * $breathVal)
    $trackBase = Get-UiColor 'Track' ([System.Drawing.Color]::FromArgb(55, 78, 102))
    if ($script:Running -or $script:Paused) {
        $trackBase = [System.Drawing.Color]::FromArgb($profile.TrackAlpha, $trackBase.R, $trackBase.G, $trackBase.B)
    }
    $trackPen = New-Object System.Drawing.Pen $trackBase, 12
    $G.DrawArc($trackPen, $rect, 0, 360)
    $trackPen.Dispose()
    if (-not $script:Running -and -not $script:Paused) {
        $breathGlow = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb($breathAlpha, $accent.R, $accent.G, $accent.B)), 14
        $G.DrawArc($breathGlow, $rect, 0, 360)
        $breathGlow.Dispose()
    }

    if ($script:Running -or $script:Paused) {
        $remainPct = if ($script:Total -gt 0) { $script:Left / $script:Total } else { 1.0 }
        $sweep = [int](360 * $remainPct)
        if ($sweep -gt 0) {
            $pulseW = [float]($profile.ArcWidth + ($profile.ArcPulseScale * $pulse) + (0.6 * $breathVal))
            $arcPen = New-Object System.Drawing.Pen($accent, $pulseW)
            $arcPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
            $arcPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
            $G.DrawArc($arcPen, $rect, -90, $sweep)
            $arcPen.Dispose()
            $outerGlowAlpha = [int]($profile.OuterGlowBase + $profile.OuterGlowPulseScale * $pulse)
            $outerGlow = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb($outerGlowAlpha, $accent.R, $accent.G, $accent.B)), ($pulseW + 6)
            $outerGlow.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
            $outerGlow.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
            $G.DrawArc($outerGlow, $rect, -90, $sweep)
            $outerGlow.Dispose()
            if ($sweep -lt 360 -and $profile.HeadRadius -gt 0) {
                $endDeg = $sweep - 90
                $endRad = $endDeg * [math]::PI / 180.0
                $radius = ($rect.Width / 2.0)
                $headX = $cx + ($radius * [math]::Cos($endRad))
                $headY = $cy + ($radius * [math]::Sin($endRad))
                $headR = [float]($profile.HeadRadius + (2.0 * $pulse))
                $headGlow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(
                        [int]($profile.HeadGlowBase + ($profile.HeadGlowPulseScale * $pulse)),
                        $accent.R, $accent.G, $accent.B))
                $G.FillEllipse($headGlow, ($headX - ($headR + 4)), ($headY - ($headR + 4)), (($headR + 4) * 2), (($headR + 4) * 2))
                $headGlow.Dispose()
                $headBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(240, $accent.R, $accent.G, $accent.B))
                $G.FillEllipse($headBrush, ($headX - $headR), ($headY - $headR), ($headR * 2), ($headR * 2))
                $headBrush.Dispose()
            }
        }
    } elseif ($script:MorningProofRingBadge -and -not $script:Running -and -not $script:Paused) {
        $badgeColor = if ($script:MorningProofRingBadge -eq 'complete') {
            Get-UiColor 'Online' ([System.Drawing.Color]::FromArgb(87, 192, 87))
        } else {
            Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))
        }
        $badgePen = New-Object System.Drawing.Pen($badgeColor, 6)
        $badgePen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $badgePen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $G.DrawArc($badgePen, $rect, -90, 360)
        $badgePen.Dispose()
    }
}

function Draw-Fist {
    param($G, [int]$Cx, [int]$Cy, [float]$Scale, [float]$Deg)
    $state = $G.Save()
    $G.TranslateTransform($Cx, $Cy)
    $G.RotateTransform($Deg)
    $G.ScaleTransform($Scale, $Scale)
    $skin = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(228, 188, 148))
    $shade = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(168, 118, 78))
    $glove = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(42, 38, 52))
    $G.FillEllipse($skin, -30, -16, 58, 50)
    foreach ($kx in @(-20, -7, 7, 20)) {
        $G.FillEllipse($skin, ($kx - 9), -34, 18, 18)
    }
    $G.FillRectangle($glove, -24, 14, 48, 16)
    $G.FillEllipse($shade, -12, 20, 24, 10)
    $skin.Dispose()
    $shade.Dispose()
    $glove.Dispose()
    $G.Restore($state)
}

function Draw-PunchScene {
    param($G, [int]$Frame, [int]$W, [int]$H)
    $G.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $G.Clear($script:C.Bg)
    $cx = [int]($W / 2)
    $cy = [int]($H / 2)

    # Flickering bulb at top ( dims on punch )
    $bulbA = if ($Frame -lt 12) { 255 } else { [int](255 * [math]::Max(0, 1 - (($Frame - 12) / 6.0))) }
    if ($bulbA -gt 8) {
        $bulb = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($bulbA, 255, 230, 160))
        $G.FillEllipse($bulb, ($cx - 14), 18, 28, 28)
        $glow = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb([int]($bulbA / 2), 255, 220, 120)), 3
        $G.DrawLine($glow, ($cx - 6), 46, ($cx - 6), 58)
        $G.DrawLine($glow, ($cx + 6), 46, ($cx + 6), 58)
        $bulb.Dispose()
        $glow.Dispose()
    }

    # Ring shatters / drains after impact
    if ($Frame -lt 14) {
        $rect = New-Object System.Drawing.Rectangle 14, 14, ($W - 28), ($H - 28)
        $trackPen = New-Object System.Drawing.Pen $script:C.Track, 10
        $G.DrawArc($trackPen, $rect, 0, 360)
        $col = Get-ActionIconColor
        $arcPen = New-Object System.Drawing.Pen $col, 10
        $arcPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $arcPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $G.DrawArc($arcPen, $rect, -90, 360)
        $trackPen.Dispose()
        $arcPen.Dispose()
    } elseif ($Frame -lt 24) {
        $shrink = [math]::Max(0, 1 - (($Frame - 14) / 8.0))
        if ($shrink -gt 0.05) {
            $inset = [int](14 + (1 - $shrink) * 40)
            $size = [int](($W - 28) * $shrink)
            $rect = New-Object System.Drawing.Rectangle $inset, $inset, $size, $size
            $frag = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb([int](200 * $shrink), 237, 175, 88)), 4
            $G.DrawArc($frag, $rect, -90 + ($Frame * 17), 80)
            $G.DrawArc($frag, $rect, 40 - ($Frame * 11), 60)
            $frag.Dispose()
        }
    }

    # Fist motion: wind-up -> punch -> recoil -> exit
    $t = [math]::Min(1.0, $Frame / 12.0)
    $ease = $t * $t * (3 - 2 * $t)
    $fx = if ($Frame -lt 13) {
        [int]($W + 40 - ($W * 0.55 + 40) * $ease)
    } elseif ($Frame -lt 18) {
        $cx + ($Frame - 13) * 3
    } else {
        [int]($cx + 20 + ($Frame - 18) * 14)
    }
    $fScale = if ($Frame -eq 12 -or $Frame -eq 13) { 1.35 } else { 0.95 + 0.1 * $ease }
    $fDeg = -30 + (35 * $ease)
    if ($Frame -ge 13) { $fDeg = 8 + ($Frame - 13) * 4 }
    Draw-Fist $G $fx $cy $fScale $fDeg

    # Impact flash
    if ($Frame -ge 11 -and $Frame -le 16) {
        $flashA = [int](160 * (1 - [math]::Abs($Frame - 13) / 3.5))
        if ($flashA -gt 0) {
            $flash = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($flashA, 255, 210, 120))
            $G.FillRectangle($flash, 0, 0, $W, $H)
            $flash.Dispose()
        }
    }

    # Sparks
    if ($Frame -ge 12 -and $Frame -le 22) {
        $sparkPen = New-Object System.Drawing.Pen $script:C.Amber, 2
        for ($i = 0; $i -lt 10; $i++) {
            $rad = ($i * 36 + $Frame * 13) * [math]::PI / 180
            $len = 12 + ($Frame - 12) * 4 + ($i * 2)
            $x1 = $cx + [math]::Cos($rad) * 8
            $y1 = $cy + [math]::Sin($rad) * 8
            $x2 = $cx + [math]::Cos($rad) * $len
            $y2 = $cy + [math]::Sin($rad) * $len
            $G.DrawLine($sparkPen, $x1, $y1, $x2, $y2)
        }
        $sparkPen.Dispose()
    }

    # LIGHTS OUT title slam
    if ($Frame -ge 16) {
        $textA = [int][math]::Min(255, ($Frame - 16) * 28)
        $fontSize = 11.0 + [math]::Min(9.0, ($Frame - 16) * 0.85)
        $font = New-Object System.Drawing.Font('Segoe UI', $fontSize, [System.Drawing.FontStyle]::Bold)
        $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($textA, 237, 175, 88))
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment = 'Center'
        $sf.LineAlignment = 'Center'
        $shake = if ($Frame -le 20) { ($Frame % 2) * 2 - 1 } else { 0 }
        $rect = New-Object System.Drawing.RectangleF (0, ($cy + 36 + $shake), $W, 44)
        $G.DrawString('LIGHTS OUT', $font, $brush, $rect, $sf)
        $font.Dispose()
        $brush.Dispose()
        $sf.Dispose()
    }
}

function Test-UseDimPhase {
    if ($script:UiReady -and $script:chkDimPhase) { return [bool]$script:chkDimPhase.Checked }
    return [bool]$script:DimPhaseEnabled
}

function Get-DimPhaseDuration {
    if (Test-NoPowerAction) { return 5 }
    return [math]::Max(15, [int]$script:DimPhaseSec)
}

function Get-DimPhaseAccentColor {
    param([double]$Progress = 0.0)
    $start = if (Get-Command Get-LastLightAccentColor -ErrorAction SilentlyContinue) {
        Get-LastLightAccentColor 0.18
    } else {
        Get-UiColor 'Amber' ([System.Drawing.Color]::FromArgb(232, 188, 96))
    }
    $finish = [System.Drawing.Color]::FromArgb(255, 124, 84)
    return Blend-UiColor $start $finish ([math]::Min(1.0, [math]::Max(0.0, $Progress)))
}

function Invoke-DimPhaseTick {
    if ($script:dimLeft -le 0) {
        $cb = $script:dimComplete
        $script:dimComplete = $null
        Stop-LightsDimPhase
        if ($cb) { & $cb }
        return
    }
    $script:dimLeft--
    $total = Get-DimPhaseDuration
    $ratio = $script:dimLeft / [math]::Max(1, $total)
    $progress = 1.0 - $ratio
    $alpha = [int](220 * (1 - $ratio) + 40)
    if ($script:pnlDim) { $script:pnlDim.BackColor = [System.Drawing.Color]::FromArgb($alpha, 0, 0, 0) }
    if ($script:lblDimCount) { $script:lblDimCount.Text = ([TimeSpan]::FromSeconds($script:dimLeft)).ToString('mm\:ss') }
    if ($script:lblDimMsg) {
        $script:lblDimMsg.ForeColor = Get-DimPhaseAccentColor $progress
        $script:lblDimMsg.Text = "Settle in - breathe - $($script:Action.ToLower()) in $($script:dimLeft) s"
    }
}

function Start-LightsDimPhase {
    param([scriptblock]$OnComplete)
    if (-not (Test-UseDimPhase)) {
        & $OnComplete
        return
    }
    Show-MainWindow
    $sec = Get-DimPhaseDuration
    $script:dimLeft = $sec
    $script:dimComplete = $OnComplete
    Write-AuditLog 'dim_phase_start' "seconds=$sec"
    Publish-LuxGridEvent -EventName 'lights.dim' -Payload @{
        timerName = $script:LuxGridTimerName
        seconds   = $sec
        action    = $script:Action
    }
    if ($script:pnlDim) {
        $script:pnlDim.BackColor = [System.Drawing.Color]::FromArgb(40, 0, 0, 0)
        $script:pnlDim.Visible = $true
        $script:pnlDim.BringToFront()
    }
    if ($script:lblDimMsg) {
        $script:lblDimMsg.ForeColor = Get-DimPhaseAccentColor 0.0
        $script:lblDimMsg.Text = "Settle in - $($script:Action.ToLower()) in ${sec}s"
    }
    $script:endPhase = 'dim'
    $script:timer.Interval = 1000
    $script:timer.Start()
}

function Stop-LightsDimPhase {
    if ($script:endPhase -eq 'dim') { $script:endPhase = $null }
    Stop-SessionEndTimer
    if ($script:timer) { $script:timer.Stop() }
    if ($script:dimTimer) { $script:dimTimer.Stop() }
    if ($script:pnlDim) { $script:pnlDim.Visible = $false }
}

function Invoke-AfterTimerEnd {
    if (Test-UseDimPhase) { Start-LightsDimPhase { Complete-TimerEnd } }
    else { Complete-TimerEnd }
}

function Test-AllowSnooze {
    param([int]$AddSeconds)
    if ($script:TonightCardSnoozePolicy -eq 'limited' -and $script:SessionSnoozeCount -ge 1) {
        [System.Windows.Forms.MessageBox]::Show(
            'Hard Stop: no snooze drift tonight.`n`nEmergency cancel (Ctrl+Shift+S) still works.',
            $script:AppName, 'OK', 'Warning') | Out-Null
        return $false
    }
    if ($script:PactSnoozeLocked) {
        [System.Windows.Forms.MessageBox]::Show(
            'Bedtime pact: snooze locked after repeated late extensions. Cancel or proceed.',
            $script:AppName, 'OK', 'Warning') | Out-Null
        return $false
    }
    if (-not $script:PactEnabled) { return $true }
    if (-not (Test-SnoozeCrossesPact -SecondsToAdd $AddSeconds -RemainingSeconds $script:Left -PactTimeHm $script:PactTime)) {
        return $true
    }
    $script:PactBreaks++
    Write-AuditLog 'pact_break' "breaks=$($script:PactBreaks) add=$AddSeconds"
    $deadline = Get-PactDeadline $script:PactTime
    $r = [System.Windows.Forms.MessageBox]::Show(
        "Bedtime pact: you pledged to $($script:Action.ToLower()) by $(Format-ClockDisplay $deadline).`n`nSnooze anyway?",
        "$script:AppName - pact warning", 'YesNo', 'Warning')
    if ($r -ne 'Yes') { return $false }
    if ($script:PactBreaks -ge 2) {
        $script:PactSnoozeLocked = $true
        Write-AuditLog 'pact_snooze_locked' ''
    }
    return $true
}

function Update-SleepLedgerBadge {
    if (-not $script:lblLedger -or -not (Get-Command Get-SleepLedgerStats -ErrorAction SilentlyContinue)) { return }
    $stats = Get-SleepLedgerStats -AuditLogPath $script:AuditLogPath
    if ($script:UseSteamUi) {
        $script:lblLedger.Text = if ($stats.Streak -gt 0) {
            "Stats - $($stats.Streak)-night streak"
        } else { 'View stats' }
    } else {
        $script:lblLedger.Text = if ($stats.Streak -gt 0) {
            "Sleep streak: $($stats.Streak) night$(if ($stats.Streak -ne 1) { 's' })"
        } else { 'Sleep ledger' }
    }
}

function Dismiss-MorningProof {
    if (-not $script:MorningProofReport -or -not $script:MorningProofReport.ShowProof) { return }
    if ($script:DemoMode -and [string]$script:MorningProofReport.EventKey -eq 'demo-morning-proof') {
        $script:DemoProofDismissed = $true
        $script:MorningProofReport = $null
        $script:MorningProofRingBadge = $null
        Update-Ui
        return
    }
    $script:MorningProofLastSeen = [string]$script:MorningProofReport.EventKey
    $script:MorningProofReport = $null
    $script:MorningProofRingBadge = $null
    Save-Settings
    Update-Ui
}

function Export-SleepLedgerReport {
    param($Stats, [string]$OutputPath)
    $date = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    $lines = @(
        "# Lights Out - Sleep Report"
        "Generated: $date"
        ""
        "## Summary"
        "| Metric | Value |"
        "|--------|-------|"
        "| Current Streak | $($Stats.Streak) nights |"
        "| Best Streak | $($Stats.BestStreak) nights |"
        "| Total Nights | $($Stats.NightsDone) |"
        "| Total Snoozes | $($Stats.Snoozes) |"
        "| Total Cancels | $($Stats.Cancels) |"
        "| Last Lights-Out | $($Stats.LastDoneLabel) |"
        ""
        "## Last 7 Nights"
        "| Day | Status |"
        "|-----|--------|"
    )
    if ($Stats.WeekDots) {
        foreach ($dot in $Stats.WeekDots) {
            $status = if ($dot.Done) { '✓ Done' } else { '— Missed' }
            $lines += "| $($dot.Label) | $status |"
        }
    }
    $lines += ""
    $lines += "---"
    $lines += "*Exported by Lights Out v$($script:AppVersion)*"
    $lines -join "`r`n" | Set-Content $OutputPath -Encoding UTF8
    Write-AuditLog 'ledger_export' "path=$OutputPath"
}

function Show-SleepLedgerDialog {
    if (-not (Get-Command Get-SleepLedgerStats -ErrorAction SilentlyContinue)) { return }
    $stats = Get-SleepLedgerStats -AuditLogPath $script:AuditLogPath
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "$script:AppName - Stats"
    $dlg.Size = New-Object System.Drawing.Size(420, 340)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.BackColor = Get-UiColor 'Bg' ([System.Drawing.Color]::FromArgb(27, 40, 56))

    $title = New-Object System.Windows.Forms.Label
    $title.Text = if ($stats.Streak -gt 0) { "$($stats.Streak)-night streak" } else { 'Start your streak tonight' }
    $title.Location = New-Object System.Drawing.Point(20, 16)
    $title.Size = New-Object System.Drawing.Size(380, 32)
    $title.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
    $title.BackColor = $dlg.BackColor
    $dlg.Controls.Add($title)

    $grid = New-Object System.Windows.Forms.TableLayoutPanel
    $grid.Location = New-Object System.Drawing.Point(20, 56)
    $grid.Size = New-Object System.Drawing.Size(380, 88)
    $grid.ColumnCount = 4
    $grid.RowCount = 2
    foreach ($c in 0..3) { $grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 25))) }
    foreach ($r in 0..1) { $grid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 40))) }
    $cells = @(
        @{ L = 'Best'; V = "$($stats.BestStreak)" }
        @{ L = 'Nights'; V = "$($stats.NightsDone)" }
        @{ L = 'Snoozes'; V = "$($stats.Snoozes)" }
        @{ L = 'Cancels'; V = "$($stats.Cancels)" }
    )
    $ci = 0
    foreach ($cell in $cells) {
        $box = New-Object System.Windows.Forms.Panel
        $box.Dock = 'Fill'
        $box.BackColor = Get-UiColor 'Card' ([System.Drawing.Color]::FromArgb(22, 32, 45))
        $box.Margin = New-Object System.Windows.Forms.Padding(4)
        $vl = New-Object System.Windows.Forms.Label
        $vl.Text = $cell.V
        $vl.Dock = 'Top'
        $vl.Height = 22
        $vl.TextAlign = 'MiddleCenter'
        $vl.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
        $vl.ForeColor = Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))
        $vl.BackColor = $box.BackColor
        $ll = New-Object System.Windows.Forms.Label
        $ll.Text = $cell.L
        $ll.Dock = 'Bottom'
        $ll.Height = 16
        $ll.TextAlign = 'MiddleCenter'
        $ll.Font = New-Object System.Drawing.Font('Segoe UI', 7.5)
        $ll.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
        $ll.BackColor = $box.BackColor
        $box.Controls.Add($vl)
        $box.Controls.Add($ll)
        $grid.Controls.Add($box, $ci, 0)
        $ci++
    }
    $dlg.Controls.Add($grid)

    $weekLbl = New-Object System.Windows.Forms.Label
    $weekLbl.Text = 'Last 7 nights'
    $weekLbl.Location = New-Object System.Drawing.Point(20, 152)
    $weekLbl.AutoSize = $true
    $weekLbl.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
    $weekLbl.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
    $weekLbl.BackColor = $dlg.BackColor
    $dlg.Controls.Add($weekLbl)

    $wx = 20
    foreach ($dot in $stats.WeekDots) {
        $d = New-Object System.Windows.Forms.Label
        $d.Text = $dot.Label.ToUpper()
        $d.Size = New-Object System.Drawing.Size(48, 52)
        $d.Location = New-Object System.Drawing.Point($wx, 176)
        $d.TextAlign = 'MiddleCenter'
        $d.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
        if ($dot.Done) {
            $d.BackColor = Get-UiColor 'Play' ([System.Drawing.Color]::FromArgb(117, 176, 34))
            $d.ForeColor = [System.Drawing.Color]::FromArgb(22, 32, 12)
        } else {
            $d.BackColor = Get-UiColor 'NavOff' ([System.Drawing.Color]::FromArgb(46, 54, 64))
            $d.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
        }
        $dlg.Controls.Add($d)
        $wx += 52
    }

    $foot = New-Object System.Windows.Forms.Label
    $foot.Text = "Last lights-out: $($stats.LastDoneLabel)"
    $foot.Location = New-Object System.Drawing.Point(20, 248)
    $foot.Size = New-Object System.Drawing.Size(380, 40)
    $foot.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $foot.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
    $foot.BackColor = $dlg.BackColor
    $dlg.Controls.Add($foot)

    $btnExport = New-Object System.Windows.Forms.Button
    $btnExport.Text = 'Export'
    $btnExport.Size = New-Object System.Drawing.Size(80, 32)
    $btnExport.Location = New-Object System.Drawing.Point(20, 288)
    Style-Button $btnExport ([System.Drawing.Color]::FromArgb(36, 36, 50)) (Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))) 9
    $btnExport.Add_Click({
        $outPath = Join-Path $script:SettingsDir "sleep-report-$(Get-Date -Format 'yyyyMMdd').md"
        Export-SleepLedgerReport -Stats $stats -OutputPath $outPath
        [System.Windows.Forms.MessageBox]::Show(
            "Week report exported to:`n$outPath",
            $script:AppName, 'OK', 'Information') | Out-Null
    }.GetNewClosure())
    $dlg.Controls.Add($btnExport)

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = 'Close'
    $btnOk.Size = New-Object System.Drawing.Size(100, 32)
    $btnOk.Location = New-Object System.Drawing.Point(300, 288)
    Style-Button $btnOk (Get-UiColor 'Play' ([System.Drawing.Color]::FromArgb(117, 176, 34))) ([System.Drawing.Color]::FromArgb(22, 32, 12)) 9
    $btnOk.Add_Click({ $dlg.Close() })
    $dlg.Controls.Add($btnOk)

    Write-AuditLog 'ledger_view' "streak=$($stats.Streak)"
    [void]$dlg.ShowDialog($form)
    Update-SleepLedgerBadge
}

function Show-HouseholdHarmonyDialog {
    if (-not (Get-Command New-HouseholdSyncPayload -ErrorAction SilentlyContinue)) { return }
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "$script:AppName - Household Harmony"
    $dlg.Size = New-Object System.Drawing.Size(440, 280)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.BackColor = Get-UiColor 'Bg' ([System.Drawing.Color]::FromArgb(27, 40, 56))

    $info = New-Object System.Windows.Forms.Label
    $info.Location = New-Object System.Drawing.Point(16, 12)
    $info.Size = New-Object System.Drawing.Size(400, 56)
    $info.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
    $info.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $info.Text = 'Sync shutdown with another PC in your home. Export a plan, send the file (or code), partner imports - both machines aim for the same lights-out moment.'
    $dlg.Controls.Add($info)

    $btnExport = New-Object System.Windows.Forms.Button
    $btnExport.Text = 'Export my plan'
    $btnExport.Size = New-Object System.Drawing.Size(190, 40)
    $btnExport.Location = New-Object System.Drawing.Point(16, 80)
    Style-Button $btnExport $script:C.Amber ([System.Drawing.Color]::FromArgb(18, 14, 8)) 9
    $btnExport.Add_Click({
        $target = Get-ClockTargetDateTime
        if ($script:Running) { $target = (Get-Date).AddSeconds($script:Left) }
        $payload = New-HouseholdSyncPayload -Action $script:Action -TargetWhen $target
        $out = Join-Path $script:SettingsDir 'household-export.json'
        ($payload | ConvertTo-Json) | Set-Content $out -Encoding UTF8
        [System.Windows.Forms.Clipboard]::SetText([string]$payload.code)
        [System.Windows.Forms.MessageBox]::Show(
            "Plan exported.`nCode: $($payload.code) (copied)`nFile: $out`n`nShare the file or code with your partner PC.",
            $script:AppName, 'OK', 'Information') | Out-Null
        Write-AuditLog 'household_export' "code=$($payload.code) target=$($payload.targetIso)"
    }.GetNewClosure())
    $dlg.Controls.Add($btnExport)

    $btnImport = New-Object System.Windows.Forms.Button
    $btnImport.Text = 'Import partner plan'
    $btnImport.Size = New-Object System.Drawing.Size(190, 40)
    $btnImport.Location = New-Object System.Drawing.Point(220, 80)
    Style-Button $btnImport ([System.Drawing.Color]::FromArgb(36, 36, 50)) $script:C.Ink 9
    $btnImport.Add_Click({
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = 'JSON (*.json)|*.json|All (*.*)|*.*'
        if ($ofd.ShowDialog() -ne 'OK') { return }
        try {
            $partner = Import-HouseholdSyncPayload -Path $ofd.FileName
        } catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, $script:AppName, 'OK', 'Error') | Out-Null
            return
        }
        if ($partner.Target -le (Get-Date)) {
            [System.Windows.Forms.MessageBox]::Show('Partner plan is in the past. Ask them to export again.', $script:AppName) | Out-Null
            return
        }
        $script:HouseholdPartner = $partner
        $localTarget = Get-ClockTargetDateTime
        if ($script:Running) { $localTarget = (Get-Date).AddSeconds($script:Left) }
        $aligned = Test-HouseholdPlansAlign -LocalTarget $localTarget -PartnerTarget $partner.Target
        $alignMsg = if ($aligned) { 'Plans align within 15 minutes - harmonious!' } else { 'Plans differ - consider matching times.' }
        Set-ScheduledTarget -When $partner.Target -Title "Household: $($partner.Machine)" -Uid "household-$($partner.Code)"
        if ($partner.Action -in @('Shutdown', 'Restart', 'Sleep', 'Hibernate', 'Lock')) { Set-Action $partner.Action }
        Write-AuditLog 'household_import' "code=$($partner.Code) machine=$($partner.Machine) aligned=$aligned"
        [System.Windows.Forms.MessageBox]::Show(
            "Partner: $($partner.Machine)`nAction: $($partner.Action)`nAt: $(Format-ClockDisplay $partner.Target)`n`n$alignMsg",
            $script:AppName, 'OK', 'Information') | Out-Null
        Save-Settings
        Update-Ui
    }.GetNewClosure())
    $dlg.Controls.Add($btnImport)

    [void]$dlg.ShowDialog($form)
}

function Start-PunchAnimation {
    param([scriptblock]$OnComplete)
    Publish-LuxGridTick -Remaining 0
    Publish-LuxGridEvent -EventName 'lights.out' -Payload @{
        timerName = $script:LuxGridTimerName
        action    = $script:Action
    }
    $script:punchComplete = $OnComplete
    $script:punchFrame = 0
    $script:punchImpactPlayed = $false
    $lblTime.Text = '00:00'
    $lblRemain.Text = ''
    $pnlPunch.Visible = $true
    $pnlPunch.BringToFront()
    $script:punchTimer.Start()
}

function Test-SessionEndingActive {
    if ($script:punchFrame -ge 0) { return $true }
    if ($script:lastLightRunning) { return $true }
    if ($script:endPhase -in @('lastlight', 'dim')) { return $true }
    if ($script:pnlDim -and $script:pnlDim.Visible) { return $true }
    if ($script:dimTimer -and $script:dimTimer.Enabled) { return $true }
    return $false
}

function Stop-SessionEndTimer {
    if ($script:sessionEndTimer) { $script:sessionEndTimer.Stop() }
}

function Stop-LastLightSequence {
    if ($script:endPhase -eq 'lastlight') { $script:endPhase = $null }
    Stop-SessionEndTimer
    if ($script:timer) { $script:timer.Stop() }
    if ($script:lastLightTimer) { $script:lastLightTimer.Stop() }
    if ($script:lastLightWatchdog) { $script:lastLightWatchdog.Stop() }
    if ($script:pnlLastLight) { $script:pnlLastLight.Visible = $false }
    $script:lastLightRunning = $false
    $script:lastLightComplete = $null
    $script:lastLightSteps = @()
    $script:lastLightStepIndex = 0
    $script:lastLightSeqMeta = $null
    $script:lastLightStepStartedAt = $null
    $script:lastLightStepDwellMs = 0
}

function Dismiss-ActiveQuickWarnDialog {
    if (-not $script:quickWarnDialog) { return }
    $dlg = $script:quickWarnDialog
    $script:quickWarnDialog = $null
    if ($dlg.IsDisposed) { return }
    try {
        $dlg.Tag = 'Continue'
        $dlg.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $dlg.Close()
    } catch { }
}

function Dismiss-ActiveFinalConfirmDialog {
    if (-not $script:finalConfirmDialog) { return }
    $dlg = $script:finalConfirmDialog
    $script:finalConfirmDialog = $null
    if ($dlg.IsDisposed) { return }
    try {
        $dlg.Tag = 'OK'
        $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dlg.Close()
    } catch { }
}

function Get-PowerFailsafeTimeoutSec {
    if (Test-NoPowerAction) { return 30 }
    $sec = 45
    if ($script:LastLightEnabled) {
        $ms = 8000
        if (Get-Command Get-LastLightSequenceDurationMs -ErrorAction SilentlyContinue) {
            $seqId = if (Get-Command Normalize-LastLightSequenceId -ErrorAction SilentlyContinue) {
                Normalize-LastLightSequenceId $script:LastLightSequence
            } else { 'ClassicFade' }
            $ms = Get-LastLightSequenceDurationMs -SequenceId $seqId -DryRun:$false
        }
        $sec += [int][math]::Ceiling($ms / 1000.0) + 15
    }
    if (Test-UseDimPhase) { $sec += (Get-DimPhaseDuration) + 15 }
    $sec += 25
    return [math]::Min($script:PowerFailsafeMaxSec, [math]::Max($script:PowerFailsafeMinSec, $sec))
}

function Stop-PowerFailsafeWatchdog {
    $script:powerFailsafeArmed = $false
    if ($script:powerFailsafeTimer) { $script:powerFailsafeTimer.Stop() }
}

function Start-PowerFailsafeWatchdog {
    if (Test-NoPowerAction) { return }
    Stop-PowerFailsafeWatchdog
    $script:powerFailsafeArmed = $true
    $timeoutSec = Get-PowerFailsafeTimeoutSec
    Write-AuditLog 'failsafe_armed' "timeout_sec=$timeoutSec action=$script:Action"
    if (-not $script:powerFailsafeTimer) {
        $script:powerFailsafeTimer = New-Object System.Windows.Forms.Timer
        $script:powerFailsafeTimer.Add_Tick({
            if (-not $script:powerFailsafeArmed -or $script:powerActionDone) {
                Stop-PowerFailsafeWatchdog
                return
            }
            Invoke-PowerFailsafe -Reason 'watchdog_timeout'
        })
    }
    $script:powerFailsafeTimer.Interval = $timeoutSec * 1000
    $script:powerFailsafeTimer.Start()
}

function Invoke-PowerFailsafe {
    param([string]$Reason = 'unknown')
    if ($script:powerActionDone) { return }
    if (Test-NoPowerAction) { return }
    Write-AuditLog 'failsafe_trigger' $Reason
    Dismiss-ActiveQuickWarnDialog
    Dismiss-ActiveFinalConfirmDialog
    Stop-LastLightSequence
    Stop-LightsDimPhase
    if ($script:punchTimer) { $script:punchTimer.Stop() }
    if ($pnlPunch) { $pnlPunch.Visible = $false }
    $script:punchFrame = -1
    $script:LastLightProceedLabel = $null
    Stop-TrayFlash
    try { Show-MainWindow } catch { }
    Publish-LuxGridCompleted
    Invoke-GuaranteedPowerAction -Failsafe
}

function Invoke-GuaranteedPowerAction {
    param([switch]$Failsafe)
    if ($script:powerActionDone) { return }
    Stop-PowerFailsafeWatchdog
    try {
        Do-PowerAction -Failsafe:$Failsafe
    } catch {
        Write-AuditLog 'power_action_fatal' $_.Exception.Message
        if (-not (Test-NoPowerAction)) {
            try {
                switch ($script:Action) {
                    'Restart' { & shutdown.exe /r /t 0 /f }
                    'Shutdown' { & shutdown.exe /s /t 0 /f }
                }
            } catch {
                Write-AuditLog 'power_action_fatal2' $_.Exception.Message
            }
        }
    }
}

function Complete-LastLightSequence {
    if (-not $script:lastLightRunning) { return }
    if ($script:endPhase -eq 'lastlight') { $script:endPhase = $null }
    Stop-SessionEndTimer
    if ($script:timer) { $script:timer.Stop() }
    if ($script:lastLightTimer) { $script:lastLightTimer.Stop() }
    if ($script:lastLightWatchdog) { $script:lastLightWatchdog.Stop() }
    $script:lastLightRunning = $false
    if ($script:pnlLastLight) { $script:pnlLastLight.Visible = $false }
    if ($script:LastLightUseCinema) { Hide-BigPicture }
    $script:lastLightStepStartedAt = $null
    $script:lastLightStepDwellMs = 0
    $seqId = if (Get-Command Normalize-LastLightSequenceId -ErrorAction SilentlyContinue) {
        Normalize-LastLightSequenceId $script:LastLightSequence
    } else { [string]$script:LastLightSequence }
    Write-AuditLog 'last_light_complete' "sequence=$seqId"
    if (Get-Command Invoke-LastLightSound -ErrorAction SilentlyContinue) {
        try { Invoke-LastLightSound -Mode $script:LastLightSound } catch { }
    }
    $cb = $script:lastLightComplete
    $script:lastLightComplete = $null
    if ($cb) {
        try { & $cb } catch {
            Write-AuditLog 'last_light_callback_error' $_.Exception.Message
        }
    }
}

function Get-LastLightRemainingSeconds {
    if (-not $script:lastLightSteps -or $script:lastLightStepIndex -ge $script:lastLightSteps.Count) { return 0 }
    $ms = 0
    for ($i = $script:lastLightStepIndex; $i -lt $script:lastLightSteps.Count; $i++) {
        $ms += [int]$script:lastLightSteps[$i].DwellMs
    }
    return [math]::Max(0, [int][math]::Ceiling($ms / 1000.0))
}

function Get-LastLightAccentColor {
    $meta = $script:lastLightSeqMeta
    $base = Get-ActionAccentColor
    if (-not $meta) { return $base }
    $accent = switch ([string]$meta.Id) {
        'ExitTheGrid' {
            Blend-UiColor (Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))) (Get-UiColor 'Blue' ([System.Drawing.Color]::FromArgb(126, 176, 255))) 0.45
        }
        'AntiAlgorithm' {
            Blend-UiColor (Get-UiColor 'Amber' ([System.Drawing.Color]::FromArgb(242, 185, 93))) (Get-UiColor 'Rose' ([System.Drawing.Color]::FromArgb(255, 118, 136))) 0.25
        }
        'SignalSeverance' {
            Blend-UiColor (Get-UiColor 'Mint' ([System.Drawing.Color]::FromArgb(104, 225, 186))) (Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))) 0.30
        }
        default {
            Blend-UiColor $base (Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))) 0.18
        }
    }
    if ($script:lastLightSteps -and $script:lastLightStepIndex -ge ($script:lastLightSteps.Count - 1)) {
        $pulse = 0.5 + (0.5 * [math]::Sin($script:PulsePhase * [math]::PI * 2.0))
        return Blend-UiColor $accent (Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(236, 242, 249))) (0.10 + (0.18 * $pulse))
    }
    return $accent
}

function Get-LastLightProgressState {
    $state = [ordered]@{
        RemainingPct = 1.0
        StepCount    = 0
        StepIndex    = 0
        IsFinalStep  = $false
        Pulse        = 0.5
        ElapsedMs    = 0
        CurrentDwell = 0
    }
    if (-not $script:lastLightSteps -or $script:lastLightSteps.Count -eq 0) {
        return [pscustomobject]$state
    }
    $totalMs = 0
    foreach ($step in $script:lastLightSteps) {
        $totalMs += [int]$step.DwellMs
    }
    $doneMs = 0
    for ($i = 0; $i -lt $script:lastLightStepIndex; $i++) {
        if ($i -lt $script:lastLightSteps.Count) {
            $doneMs += [int]$script:lastLightSteps[$i].DwellMs
        }
    }
    $currentDwell = [math]::Max(1, [int]$script:lastLightStepDwellMs)
    $elapsedMs = 0
    if ($script:lastLightStepStartedAt -and $script:lastLightRunning) {
        $elapsedMs = [int]((Get-Date) - $script:lastLightStepStartedAt).TotalMilliseconds
        $elapsedMs = [math]::Max(0, [math]::Min($currentDwell, $elapsedMs))
    }
    $doneMs += $elapsedMs
    $remainingPct = if ($totalMs -gt 0) { 1.0 - ($doneMs / $totalMs) } else { 1.0 }
    $pulse = 0.5 + (0.5 * [math]::Sin($script:PulsePhase * [math]::PI * 2.0))
    $state.RemainingPct = [math]::Max(0.02, $remainingPct)
    $state.StepCount = $script:lastLightSteps.Count
    $state.StepIndex = [math]::Min(($script:lastLightSteps.Count - 1), [math]::Max(0, $script:lastLightStepIndex))
    $state.IsFinalStep = ($script:lastLightStepIndex -ge ($script:lastLightSteps.Count - 1))
    $state.Pulse = $pulse
    $state.ElapsedMs = $elapsedMs
    $state.CurrentDwell = $currentDwell
    return [pscustomobject]$state
}

function Draw-LastLightRing {
    param($G, [int]$W, [int]$H, [double]$Pct)
    $G.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $cx = [int]($W / 2)
    $cy = [int]($H / 2)
    $state = Get-LastLightProgressState
    $accent = Get-LastLightAccentColor
    $radius = [math]::Min($W, $H) / 2 - 16
    $rect = New-Object System.Drawing.Rectangle (($cx - $radius), ($cy - $radius), ($radius * 2), ($radius * 2))
    $haloR = $radius + 8 + (4 * $state.Pulse)
    $haloBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb([int](22 + (16 * $state.Pulse)), $accent.R, $accent.G, $accent.B))
    $G.FillEllipse($haloBrush, ($cx - $haloR), ($cy - $haloR), ($haloR * 2), ($haloR * 2))
    $haloBrush.Dispose()
    $innerBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(18, 24, 34))
    $G.FillEllipse($innerBrush, ($cx - ($radius - 10)), ($cy - ($radius - 10)), (($radius - 10) * 2), (($radius - 10) * 2))
    $innerBrush.Dispose()
    $track = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(230, 55, 78, 102), 10)
    $G.DrawArc($track, $rect, 0, 360)
    $track.Dispose()
    if ($state.StepCount -gt 1) {
        $dotRadius = $radius + 6
        for ($i = 0; $i -lt $state.StepCount; $i++) {
            $deg = -90 + (($i / [double]$state.StepCount) * 360)
            $rad = $deg * [math]::PI / 180.0
            $dx = $cx + ($dotRadius * [math]::Cos($rad))
            $dy = $cy + ($dotRadius * [math]::Sin($rad))
            $done = ($i -lt $state.StepIndex) -or ($i -eq $state.StepIndex -and $state.ElapsedMs -gt ($state.CurrentDwell * 0.55))
            $dotColor = if ($done) {
                [System.Drawing.Color]::FromArgb(220, $accent.R, $accent.G, $accent.B)
            } else {
                [System.Drawing.Color]::FromArgb(120, 74, 88, 106)
            }
            $dotBrush = New-Object System.Drawing.SolidBrush $dotColor
            $G.FillEllipse($dotBrush, ($dx - 3), ($dy - 3), 6, 6)
            $dotBrush.Dispose()
        }
    }
    $sweep = [int](360 * [math]::Max(0.04, $state.RemainingPct))
    if ($sweep -gt 0) {
        $arcWidth = [float](10.5 + (2.0 * $state.Pulse))
        $arc = New-Object System.Drawing.Pen($accent, $arcWidth)
        $arc.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $arc.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $G.DrawArc($arc, $rect, -90, $sweep)
        $arc.Dispose()
        $glow = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb([int](18 + (34 * $state.Pulse)), $accent.R, $accent.G, $accent.B), ($arcWidth + 6))
        $glow.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $glow.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $G.DrawArc($glow, $rect, -90, $sweep)
        $glow.Dispose()
        if ($sweep -lt 360) {
            $endDeg = $sweep - 90
            $endRad = $endDeg * [math]::PI / 180.0
            $hx = $cx + ($radius * [math]::Cos($endRad))
            $hy = $cy + ($radius * [math]::Sin($endRad))
            $headGlow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb([int](26 + (58 * $state.Pulse)), $accent.R, $accent.G, $accent.B))
            $G.FillEllipse($headGlow, ($hx - 9), ($hy - 9), 18, 18)
            $headGlow.Dispose()
            $head = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(240, $accent.R, $accent.G, $accent.B))
            $G.FillEllipse($head, ($hx - 4), ($hy - 4), 8, 8)
            $head.Dispose()
        }
    }
    $coreBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(230, $accent.R, $accent.G, $accent.B))
    $G.FillEllipse($coreBrush, ($cx - 4), ($cy - 4), 8, 8)
    $coreBrush.Dispose()
}

function Set-LastLightStepDisplay {
    param($Step)
    if (-not $Step) { return }
    $head = [string]$Step.Headline
    $line = [string]$Step.Line
    $meta = $script:lastLightSeqMeta
    $isLast = ($script:lastLightSteps -and ($script:lastLightStepIndex -ge ($script:lastLightSteps.Count - 1)))
    $stepNum = $script:lastLightStepIndex + 1
    $stepCount = if ($script:lastLightSteps) { $script:lastLightSteps.Count } else { 0 }
    $accent = Get-LastLightAccentColor
    $remain = Get-LastLightRemainingSeconds
    $remainText = ([TimeSpan]::FromSeconds([math]::Max(0, $remain))).ToString('mm\:ss')

    if ($script:lblLastLightSeq -and $meta) {
        $seq = [string]$meta.SequenceLabel
        if ($seq) {
            $script:lblLastLightSeq.Text = if ($stepCount -gt 1) { "$seq   STEP $stepNum/$stepCount" } else { $seq }
            $script:lblLastLightSeq.ForeColor = $accent
            $script:lblLastLightSeq.Visible = $true
        } else {
            $script:lblLastLightSeq.Visible = $false
        }
    }
    if ($script:lblLastLightMainTitle) {
        $main = if ($meta -and $meta.CinematicTitle) { [string]$meta.CinematicTitle } else { 'LAST LIGHT' }
        if ($head -and $meta -and -not $meta.CinematicTitle) { $main = $head }
        $script:lblLastLightMainTitle.Text = $main
        $script:lblLastLightMainTitle.Visible = $true
    }
    if ($script:lblLastLightSideHead) {
        $sideHead = if ($head) { $head } elseif ($meta) { [string]$meta.SequenceLabel } else { '' }
        $script:lblLastLightSideHead.Text = $sideHead
        $script:lblLastLightSideHead.ForeColor = $accent
        $script:lblLastLightSideHead.Visible = ($sideHead.Length -gt 0)
    }
    if ($script:lblLastLightSideBody) {
        $script:lblLastLightSideBody.Text = $line
        $script:lblLastLightSideBody.Visible = ($line.Length -gt 0)
    }
    if ($script:lblLastLightRingTime) {
        $script:lblLastLightRingTime.Text = $remainText
        $script:lblLastLightRingTime.ForeColor = if ($isLast) {
            Blend-UiColor $accent (Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(236, 242, 249))) 0.25
        } else {
            Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
        }
    }
    if ($script:lblLastLightRingSub) {
        $script:lblLastLightRingSub.Text = if ($isLast) { 'FINAL WINDOW' } elseif ($stepCount -gt 1) { "STEP $stepNum OF $stepCount" } else { 'TO DISCONNECT' }
        $script:lblLastLightRingSub.ForeColor = $accent
    }
    try { if ($script:pnlLastLightRing) { $script:pnlLastLightRing.Invalidate() } } catch { }
    if ($script:lblLastLightProceed) {
        $showProceed = [bool]($isLast -and $meta -and [string]$meta.ProceedLabel)
        $script:lblLastLightProceed.Text = if ($showProceed) { [string]$meta.ProceedLabel } else { '' }
        $script:lblLastLightProceed.BackColor = $accent
        $script:lblLastLightProceed.ForeColor = [System.Drawing.Color]::FromArgb(12, 16, 24)
        $script:lblLastLightProceed.Visible = $showProceed
    }
    if ($script:lblLastLightConfirm) {
        $script:lblLastLightConfirm.ForeColor = if ($isLast) { $accent } else { Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165)) }
        $script:lblLastLightConfirm.Visible = [bool]$isLast
    }
    if ($script:lblLastLightHead) {
        $script:lblLastLightHead.Text = $head
        $script:lblLastLightHead.Visible = $false
    }
    if ($script:lblLastLightBody) {
        $script:lblLastLightBody.Text = $line
        $script:lblLastLightBody.Visible = $false
    }
    if ($script:frmBigPicture -and ($script:frmBigPicture.Visible -or $script:lastLightRunning)) {
        if ($script:bpTime -and $head) { $script:bpTime.Text = $head }
        if ($script:bpSub) { $script:bpSub.Text = $line }
        if ($script:bpRing) { $script:bpRing.Invalidate() }
    }
}

function Start-LastLightSequence {
    param([scriptblock]$OnComplete)
    if (-not $script:LastLightEnabled) {
        Write-AuditLog 'last_light_skipped' 'reason=disabled'
        & $OnComplete
        return
    }
    if (-not (Get-Command Get-LastLightSequenceSteps -ErrorAction SilentlyContinue)) {
        Write-AuditLog 'last_light_skipped' 'reason=module_missing'
        & $OnComplete
        return
    }
    Stop-LastLightSequence
    Show-MainWindow
    $seqId = Normalize-LastLightSequenceId $script:LastLightSequence
    $dry = Test-NoPowerAction
    $script:lastLightSteps = @(Get-LastLightSequenceSteps -SequenceId $seqId -DryRun:$dry)
    if ($script:lastLightSteps.Count -eq 0) {
        Write-AuditLog 'last_light_skipped' "reason=no_steps sequence=$seqId"
        & $OnComplete
        return
    }
    $meta = Get-LastLightSequenceMeta -SequenceId $seqId -DryRun:$dry
    $script:LastLightProceedLabel = $meta.ProceedLabel
    $script:lastLightSeqMeta = $meta
    Write-AuditLog 'last_light_start' "sequence=$seqId dry_run=$dry"
    $script:lastLightComplete = $OnComplete
    $script:lastLightRunning = $true
    $script:lastLightStepIndex = 0
    $script:lastLightFade = 40
    $script:lastLightStepStartedAt = Get-Date
    $script:lastLightStepDwellMs = [math]::Max(400, [int]$script:lastLightSteps[0].DwellMs)
    $script:endPhase = 'lastlight'
    $script:PulsePhase = 0.0
    if ($script:LastLightUseCinema) {
        Initialize-BigPictureForm
        if ($script:bpTime) { $script:bpTime.Text = '00:00' }
        if ($script:bpHint) { $script:bpHint.Text = 'Last Light sequence' }
        $script:frmBigPicture.Show()
        $script:frmBigPicture.BringToFront()
    }
    if ($script:pnlLastLight) {
        $script:pnlLastLight.BackColor = [System.Drawing.Color]::FromArgb(40, 0, 0, 0)
        $script:pnlLastLight.Visible = $true
        $script:pnlLastLight.BringToFront()
    }
    try {
        Set-LastLightStepDisplay $script:lastLightSteps[0]
    } catch {
        Write-AuditLog 'last_light_display_error' $_.Exception.Message
    }
    if (-not $script:lastLightTimer) {
        $script:lastLightTimer = New-Object System.Windows.Forms.Timer
        $script:lastLightTimer.Add_Tick({ Invoke-LastLightSequenceTick })
    }
    if (-not $script:lastLightWatchdog) {
        $script:lastLightWatchdog = New-Object System.Windows.Forms.Timer
        $script:lastLightWatchdog.Add_Tick({
            if (-not $script:lastLightRunning) { return }
            Write-AuditLog 'last_light_watchdog' 'sequence_timeout'
            Complete-LastLightSequence
        })
    }
    try {
        $script:lastLightTimer.Interval = $script:lastLightStepDwellMs
        $script:lastLightTimer.Start()
        $totalMs = 0
        foreach ($seqStep in $script:lastLightSteps) { $totalMs += [int]$seqStep.DwellMs }
        $script:lastLightWatchdog.Interval = [math]::Max(1000, ($totalMs + 2500))
        $script:lastLightWatchdog.Start()
    } catch {
        Write-AuditLog 'last_light_timer_error' $_.Exception.Message
        $script:lastLightRunning = $false
        if ($script:lastLightComplete) {
            $cb = $script:lastLightComplete
            $script:lastLightComplete = $null
            & $cb
        }
    }
}

function Invoke-LastLightSequenceTick {
    if (-not $script:lastLightRunning) { return }
    try {
        $script:lastLightStepIndex++
        if ($script:lastLightFade -lt 220) { $script:lastLightFade = [math]::Min(220, $script:lastLightFade + 18) }
        if ($script:pnlLastLight) {
            $script:pnlLastLight.BackColor = [System.Drawing.Color]::FromArgb($script:lastLightFade, 0, 0, 0)
        }
        if ($script:lastLightStepIndex -ge $script:lastLightSteps.Count) {
            Write-AuditLog 'last_light_timer_complete' "sequence=$($script:lastLightSeqMeta.Id)"
            Complete-LastLightSequence
            return
        }
        $script:lastLightStepStartedAt = Get-Date
        $script:lastLightStepDwellMs = [math]::Max(400, [int]$script:lastLightSteps[$script:lastLightStepIndex].DwellMs)
        Set-LastLightStepDisplay $script:lastLightSteps[$script:lastLightStepIndex]
        try { if ($script:pnlLastLightRing) { $script:pnlLastLightRing.Invalidate() } } catch { }
        $script:lastLightTimer.Interval = $script:lastLightStepDwellMs
    } catch {
        Write-AuditLog 'last_light_error' $_.Exception.Message
        $script:lastLightStepStartedAt = $null
        $script:lastLightStepDwellMs = 0
        Complete-LastLightSequence
    }
}

function Invoke-AfterPunchForLastLight {
    Start-LastLightSequence { Invoke-AfterTimerEnd }
}

function Complete-TimerEnd {
    Dismiss-ActiveQuickWarnDialog
    $proceedOverride = $script:LastLightProceedLabel
    $script:LastLightProceedLabel = $null
    try {
        $r = Show-FinalConfirm -ProceedText $proceedOverride
    } catch {
        Write-AuditLog 'final_confirm_error' $_.Exception.Message
        $r = 'OK'
    }
    if ($r -eq 'Retry') {
        Stop-PowerFailsafeWatchdog
        if (-not (Test-AllowSnooze 600)) { Update-Ui; return }
        Write-AuditLog 'snooze_final' '600s'
        $script:Left = 600
        $script:Running = $true
        Reset-CountdownWarnFlags
        $script:timer.Start()
        $script:pulseTimer.Start()
        Update-Ui
        return
    }
    if ($r -eq 'Retry5') {
        Stop-PowerFailsafeWatchdog
        if (-not (Test-AllowSnooze 300)) { Update-Ui; return }
        Write-AuditLog 'snooze_final' '300s'
        $script:Left = 300
        $script:Running = $true
        Reset-CountdownWarnFlags
        $script:timer.Start()
        $script:pulseTimer.Start()
        Update-Ui
        return
    }
    if ($r -eq 'Cancel') {
        Stop-PowerFailsafeWatchdog
        Write-AuditLog 'final_cancelled' "action=$($script:Action)"
        Publish-LuxGridCancelled -Reason 'final_cancel'
        $script:Left = 0
        Update-Ui
        return
    }
    if ($r -in @('Shutdown', 'Restart', 'Sleep', 'Hibernate', 'Lock')) {
        Set-Action $r
        Save-Settings
    }
    Publish-LuxGridCompleted
    if (-not (Test-NoPowerAction)) {
        try {
            Show-AchievementToast 'Session complete' 'You made it to lights out. Power action next.'
        } catch { }
    }
    Invoke-GuaranteedPowerAction
}

function Format-RemainingFriendly {
    $m = [math]::Ceiling($script:Left / 60.0)
    if ($script:Left -le 60) { return 'under a minute' }
    if ($m -eq 1) { return '1 minute left' }
    return "$m minutes left"
}

function Format-EndClock {
    param([int]$SecondsFromNow)
    (Get-Date).AddSeconds([math]::Max(0, $SecondsFromNow)).ToString('h:mm tt')
}

function Format-EndLine {
    param([int]$SecondsFromNow, [switch]$Preview)
    $clock = Format-EndClock $SecondsFromNow
    $verb = $script:Action.ToLower()
    if ($Preview) { return "Start now -> ends about $clock - $verb" }
    return "Ends at $clock - $verb"
}

# Mutex
$mutex = $null
if ($env:SLEEPTIMER_CI -ne '1') {
    $mutex = New-Object System.Threading.Mutex($false, 'Global\SleepTimerTonight')
    if (-not $mutex.WaitOne(0, $false)) {
        [System.Windows.Forms.MessageBox]::Show("$script:AppName is already running. Check the tray.", $script:AppName) | Out-Null
        return
    }
}

$cfg = Get-Settings
# CLI theme flags win over saved settings.json UiTheme
if ($SteamUi -or $script:CliSteamUi) { $cfg.UiTheme = 'steam' }
elseif ($ClassicUi -or $script:CliClassicUi -or $Simple) { $cfg.UiTheme = 'classic' }
elseif ($cfg.UiTheme -notin @('classic', 'steam')) { $cfg.UiTheme = 'steam' }
Initialize-LightsOutThemePalette -Name $(if ($cfg.UiTheme -in @('classic', 'steam')) { $cfg.UiTheme } else { 'classic' })
$startupSec = 0
if ($script:CliMinutes -gt 0) { $startupSec = $script:CliMinutes * 60 }
elseif ($script:CliSeconds -gt 0) { $startupSec = $script:CliSeconds }
elseif ($Seconds -gt 0) { $startupSec = $Seconds }
$script:DefaultSec = if ($startupSec -gt 0) { [math]::Max((Get-MinTimerSec), $startupSec) } else { $cfg.DefaultSeconds }
$script:Action = $cfg.Action
$cliAct = Normalize-ActionName $script:CliAction
if ($cliAct) { $script:Action = $cliAct }
$script:EmitLuxGridEvents = [bool]$cfg.EmitLuxGridEvents
$script:GracefulShutdown = [bool]$cfg.GracefulShutdown
if ($ForceShutdown) {
    $script:GracefulShutdown = $false
    $cfg.GracefulShutdown = $false
}
$script:TimerMode = if ($cfg.TimerMode -in @('clock', 'calendar')) { $cfg.TimerMode } else { 'duration' }
$cliAt = Parse-ClockTime $script:CliAt
if (-not $script:UseSteamUi -and -not $ScheduleAt -and -not $script:CliCalendar -and -not $cliAt -and $Minutes -le 0 -and $Seconds -le 0) {
    $script:TimerMode = 'duration'
}
$hasCliDuration = ($script:CliMinutes -gt 0) -or ($script:CliSeconds -gt 0) -or ($Minutes -gt 0) -or ($Seconds -gt 0)
if (-not $script:UseSteamUi -and $script:TimerMode -eq 'duration' -and -not $hasCliDuration -and ($script:DefaultSec -gt 7200 -or $script:DefaultSec -lt 60)) {
    $script:DefaultSec = 1380
}
$script:ClockTime = [string]$cfg.ClockTime
$script:CalendarSource = [string]$cfg.CalendarSource
$script:CalendarEventUid = [string]$cfg.CalendarEventUid
$script:CalendarEventTitle = [string]$cfg.CalendarEventTitle
if ($cfg.ScheduledAt) {
    try { $script:ScheduledAt = [DateTime]::Parse([string]$cfg.ScheduledAt) } catch { $script:ScheduledAt = $null }
} else { $script:ScheduledAt = $null }
$script:WarnPowerBlockers = [bool]$cfg.WarnPowerBlockers
$script:DimPhaseEnabled = [bool]$cfg.DimPhaseEnabled
$script:DimPhaseSec = [int]$cfg.DimPhaseSeconds
$script:PactEnabled = [bool]$cfg.PactEnabled
$script:PactTime = [string]$cfg.PactTime
$script:LastRitualId = [string]$cfg.LastRitualId
$script:LastProfileId = [string]$cfg.LastProfileId
$script:SavedTimers = if ($cfg.SavedTimers) { @($cfg.SavedTimers) } else { @() }
$script:CalendarFeedUrl = [string]$cfg.CalendarFeedUrl
$script:CalendarFeedIntervalMin = [int]$cfg.CalendarFeedIntervalMin
$script:CalendarFeedAutoStart = [bool]$cfg.CalendarFeedAutoStart
$script:AutoStartOnOpen = [bool]$cfg.AutoStart
$script:MorningProofLastSeen = [string]$cfg.MorningProofLastSeen
$script:MorningProofReport = $null
$script:MorningProofRingBadge = $null
$script:LastLightEnabled = if ($null -ne $cfg.LastLightEnabled) { [bool]$cfg.LastLightEnabled } else { $true }
$llCli = if ($script:CliLastLightSequence) { $script:CliLastLightSequence } elseif ($LastLightSequence) { $LastLightSequence } else { $null }
if ($llCli -and (Get-Command Normalize-LastLightSequenceId -ErrorAction SilentlyContinue)) {
    $script:LastLightSequence = Normalize-LastLightSequenceId ([string]$llCli)
} elseif (Get-Command Normalize-LastLightSequenceId -ErrorAction SilentlyContinue) {
    $script:LastLightSequence = Normalize-LastLightSequenceId ([string]$cfg.LastLightSequence)
} else {
    $script:LastLightSequence = [string]$cfg.LastLightSequence
}
$script:LastLightUseCinema = [bool]$cfg.LastLightUseCinema
$script:LastLightLuxPulse = [bool]$cfg.LastLightLuxPulse
$script:LastLightSound = if (Get-Command Normalize-LastLightSoundId -ErrorAction SilentlyContinue) {
    Normalize-LastLightSoundId ([string]$cfg.LastLightSound)
} else { 'Off' }
$script:TonightCardId = if (Get-Command Normalize-TonightCardId -ErrorAction SilentlyContinue) {
    Normalize-TonightCardId ([string]$cfg.TonightCardId)
} else { 'weeknight' }
$script:CinemaScreenIndex = [int]$cfg.CinemaScreenIndex
$script:QuietHoursAutoStart = [bool]$cfg.QuietHoursAutoStart
$script:ClockFaceStyle = if ($cfg.ClockFaceStyle -in $script:ValidClockFaceIds) { $cfg.ClockFaceStyle } else { 'Analog' }
if ($cfg.CustomAccentColor -and $cfg.CustomAccentColor -match '^(\d+),(\d+),(\d+)$') {
    $script:CustomAccentColor = [System.Drawing.Color]::FromArgb([int]$Matches[1], [int]$Matches[2], [int]$Matches[3])
} else { $script:CustomAccentColor = $null }
$script:SmartLightProvider = if ($cfg.SmartLightProvider) { $cfg.SmartLightProvider } else { 'none' }
$script:SmartLightMode = if ($cfg.SmartLightMode) { $cfg.SmartLightMode } else { 'gradual_dim' }
$script:SmartLightDimMinutes = if ($cfg.SmartLightDimMinutes) { [int]$cfg.SmartLightDimMinutes } else { 10 }
$script:SmartLightEnabled = [bool]$cfg.SmartLightEnabled
$script:HueBridgeIp = if ($cfg.HueBridgeIp) { $cfg.HueBridgeIp } else { '' }
$script:HueUsername = if ($cfg.HueUsername) { $cfg.HueUsername } else { '' }
$script:HueLightIds = if ($cfg.HueLightIds) { @($cfg.HueLightIds | ForEach-Object { [string]$_ }) } else { @() }
$script:HueGroupId = if ($cfg.HueGroupId) { [string]$cfg.HueGroupId } else { '' }
$script:HueTargetLabel = if ($cfg.HueTargetLabel) { [string]$cfg.HueTargetLabel } else { '' }
$script:HttpLightUrl = if ($cfg.HttpLightUrl) { $cfg.HttpLightUrl } else { '' }
Sync-SmartLightConfig
$script:TonightCardSnoozePolicy = 'default'
$script:SessionSnoozeCount = 0
$script:ApplyingTonightCard = $false
$script:lastLightRunning = $false
$script:LastLightProceedLabel = $null
$script:lastLightSeqMeta = $null
$script:quickWarnDialog = $null
$script:finalConfirmDialog = $null
$script:lastLightWatchdog = $null
$script:powerFailsafeTimer = $null
$script:powerFailsafeArmed = $false
$script:powerActionDone = $false
$script:endPhase = $null
Initialize-LightsOutThemePalette -Name $(if ($cfg.UiTheme -in @('classic', 'steam')) { $cfg.UiTheme } else { 'classic' })
$script:CalendarFeedLastSync = [string]$cfg.CalendarFeedLastSync
if ($cliAt) {
    $script:ClockTime = $cliAt
    $script:TimerMode = 'clock'
}
$cliSchedule = Parse-ScheduleDateTime $script:CliAt
if ($cliSchedule -and $cliSchedule -gt (Get-Date)) {
    $script:ScheduledAt = $cliSchedule
    $script:TimerMode = 'calendar'
}
if ($script:CliCalendar -and (Test-Path $script:CliCalendar) -and (Get-Command Import-IcsCalendarFile -ErrorAction SilentlyContinue)) {
    try {
        $imported = Import-IcsCalendarFile -Path $script:CliCalendar
        $next = Get-IcsUpcomingEvents -Events $imported.Events -MaxCount 1
        if ($next.Count -gt 0) {
            $ev = $next[0]
            $script:ScheduledAt = $ev.Start
            $script:CalendarSource = $script:CliCalendar
            $script:CalendarEventUid = $ev.Uid
            $script:CalendarEventTitle = $ev.Summary
            $script:TimerMode = 'calendar'
        }
    } catch {
        Write-AuditLog 'calendar_cli_fail' $_.Exception.Message
    }
}
if (-not $script:UseSteamUi -and -not $ScheduleAt -and -not $script:CliCalendar -and -not $cliAt -and $Minutes -le 0 -and $Seconds -le 0) {
    $script:TimerMode = 'duration'
}
$hasCliDuration = ($script:CliMinutes -gt 0) -or ($script:CliSeconds -gt 0) -or ($Minutes -gt 0) -or ($Seconds -gt 0)
if (-not $script:UseSteamUi -and $script:TimerMode -eq 'duration' -and -not $hasCliDuration -and ($script:DefaultSec -gt 7200 -or $script:DefaultSec -lt 60)) {
    $script:DefaultSec = 1380
}

$script:LogoPath = Get-LogoPath
$script:yCal = 18
$script:yNovel = 34
$script:ySchedule = 136
$script:yBoost = if ($script:LogoPath -and -not $script:UseSteamUi) { 16 } else { 0 }
if ($script:UseSteamUi) { $script:yBoost += 62 }
$script:formW = if ($script:UseSteamUi) { 480 } else { 436 }
$script:contentW = $script:formW - 48
$script:formExtraW = if ($script:UseSteamUi) { 72 } else { 0 }
$script:formExtraH = if ($script:UseSteamUi) { 34 } else { 0 }
$script:statusY = if ($script:UseSteamUi) { (74 + $script:yBoost) } else { (58 + $script:yBoost) }

$form = New-Object System.Windows.Forms.Form
$form.Text = if (-not $script:UseSteamUi) { 'Sleep Timer' } else { $script:AppName }
$script:yCardSave = if ($script:UseSteamUi) { 108 } else { 0 }
$script:steamLayoutOff = if ($script:UseSteamUi) { 50 } else { 0 }
$form.Size = New-Object System.Drawing.Size(
    ($script:formW + $script:formExtraW),
    (606 + $script:steamLayoutOff + $script:yBoost + $script:yCal + $script:yNovel + $script:ySchedule + $script:formExtraH - $script:yCardSave))
$form.FormBorderStyle = if ($script:UseSteamUi) { 'None' } else { 'FixedSingle' }
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.StartPosition = 'CenterScreen'
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$form.TopMost = $cfg.TopMost
$form.BackColor = Get-UiColor 'Bg' ([System.Drawing.Color]::FromArgb(27, 40, 56))
$form.ShowInTaskbar = $true
Enable-DoubleBuffer $form

# ========== COCKPIT UI CHROME ==========
if ($script:UseSteamUi) {
    # Main chrome panel (replaces title bar)
    $script:pnlChrome = New-Object System.Windows.Forms.Panel
    $script:pnlChrome.Dock = [System.Windows.Forms.DockStyle]::Top
    $script:pnlChrome.Height = 64
    $script:pnlChrome.BackColor = [System.Drawing.Color]::FromArgb(10, 14, 22)
    Enable-DoubleBuffer $script:pnlChrome
    
    # App title/logo area
    $script:lblAppTitle = New-Object System.Windows.Forms.Label
    $script:lblAppTitle.Text = $script:AppName
    $script:lblAppTitle.Location = New-Object System.Drawing.Point(12, 8)
    $script:lblAppTitle.AutoSize = $true
    $script:lblAppTitle.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $script:lblAppTitle.ForeColor = [System.Drawing.Color]::FromArgb(220, 230, 240)
    $script:pnlChrome.Controls.Add($script:lblAppTitle)
    
    # Main menu strip (Cockpit navigation)
    $script:mainMenuStrip = New-Object System.Windows.Forms.MenuStrip
    $script:mainMenuStrip.Location = New-Object System.Drawing.Point(0, 32)
    $script:mainMenuStrip.Size = New-Object System.Drawing.Size($form.ClientSize.Width, 32)
    $script:mainMenuStrip.BackColor = [System.Drawing.Color]::FromArgb(14, 18, 26)
    $script:mainMenuStrip.ForeColor = [System.Drawing.Color]::FromArgb(200, 210, 220)
    $script:mainMenuStrip.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $script:mainMenuStrip.Dock = [System.Windows.Forms.DockStyle]::None
    $script:mainMenuStrip.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    
    # File menu
    $menuFile = New-Object System.Windows.Forms.ToolStripMenuItem 'File'
    $miExit = New-Object System.Windows.Forms.ToolStripMenuItem 'Exit'
    $miExit.Add_Click({ $form.Close() })
    $menuFile.DropDownItems.Add($miExit)
    $script:mainMenuStrip.Items.Add($menuFile)
    
    # Power menu (main action menu)
    $menuPower = New-Object System.Windows.Forms.ToolStripMenuItem 'Power'
    $miShutdown = New-Object System.Windows.Forms.ToolStripMenuItem 'Shutdown'
    $miRestart = New-Object System.Windows.Forms.ToolStripMenuItem 'Restart'
    $miSleep = New-Object System.Windows.Forms.ToolStripMenuItem 'Sleep'
    $miHibernate = New-Object System.Windows.Forms.ToolStripMenuItem 'Hibernate'
    $menuPower.DropDownItems.Add($miShutdown)
    $menuPower.DropDownItems.Add($miRestart)
    $menuPower.DropDownItems.Add($miSleep)
    $menuPower.DropDownItems.Add($miHibernate)
    $script:mainMenuStrip.Items.Add($menuPower)
    
    # View menu
    $menuView = New-Object System.Windows.Forms.ToolStripMenuItem 'View'
    $miCinema = New-Object System.Windows.Forms.ToolStripMenuItem 'Cinema Mode'
    $miTopmost = New-Object System.Windows.Forms.ToolStripMenuItem 'Always on Top'
    $menuView.DropDownItems.Add($miCinema)
    $menuView.DropDownItems.Add($miTopmost)
    $script:mainMenuStrip.Items.Add($menuView)
    
    # Settings menu
    $menuSettings = New-Object System.Windows.Forms.ToolStripMenuItem 'Settings'
    $miOptions = New-Object System.Windows.Forms.ToolStripMenuItem 'Options...'
    $menuSettings.DropDownItems.Add($miOptions)
    $script:mainMenuStrip.Items.Add($menuSettings)
    
    # Help menu
    $menuHelp = New-Object System.Windows.Forms.ToolStripMenuItem 'Help'
    $miAbout = New-Object System.Windows.Forms.ToolStripMenuItem 'About'
    $menuHelp.DropDownItems.Add($miAbout)
    $script:mainMenuStrip.Items.Add($menuHelp)
    
    $script:pnlChrome.Controls.Add($script:mainMenuStrip)
    
    # Window controls (right side)
    $btnMinimize = New-Object System.Windows.Forms.Button
    $btnMinimize.Text = [char]0x2014
    $btnMinimize.Size = New-Object System.Drawing.Size(44, 28)
    $btnMinimize.Location = New-Object System.Drawing.Point(($form.ClientSize.Width - 88), 4)
    $btnMinimize.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $btnMinimize.FlatStyle = 'Flat'
    $btnMinimize.FlatAppearance.BorderSize = 0
    $btnMinimize.BackColor = [System.Drawing.Color]::FromArgb(28, 32, 40)
    $btnMinimize.ForeColor = [System.Drawing.Color]::FromArgb(160, 170, 180)
    $btnMinimize.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $btnMinimize.Add_Click({ $form.WindowState = 'Minimized' })
    $script:pnlChrome.Controls.Add($btnMinimize)
    
    $btnCloseWin = New-Object System.Windows.Forms.Button
    $btnCloseWin.Text = [char]0x2715
    $btnCloseWin.Size = New-Object System.Drawing.Size(44, 28)
    $btnCloseWin.Location = New-Object System.Drawing.Point(($form.ClientSize.Width - 44), 4)
    $btnCloseWin.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $btnCloseWin.FlatStyle = 'Flat'
    $btnCloseWin.FlatAppearance.BorderSize = 0
    $btnCloseWin.BackColor = [System.Drawing.Color]::FromArgb(28, 32, 40)
    $btnCloseWin.ForeColor = [System.Drawing.Color]::FromArgb(160, 170, 180)
    $btnCloseWin.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $btnCloseWin.Add_Click({ $form.Close() })
    $script:pnlChrome.Controls.Add($btnCloseWin)
    
    # Chrome paint gradient
    $script:pnlChrome.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush (
            (New-Object System.Drawing.Rectangle 0, 0, $s.Width, $s.Height),
            [System.Drawing.Color]::FromArgb(14, 20, 30),
            [System.Drawing.Color]::FromArgb(8, 12, 18),
            90)
        $g.FillRectangle($grad, 0, 0, $s.Width, $s.Height)
        $grad.Dispose()
        # Accent line at bottom
        $accent = [System.Drawing.Color]::FromArgb(118, 201, 255)
        $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(100, $accent.R, $accent.G, $accent.B)), 1
        $g.DrawLine($pen, 0, ($s.Height - 1), $s.Width, ($s.Height - 1))
        $pen.Dispose()
    })
    
    # Drag support for chrome
    $script:dragStart = $null
    $script:pnlChrome.Add_MouseDown({
        param($s, $e)
        if ($e.Button -eq 'Left') { $script:dragStart = $e.Location }
    })
    $script:pnlChrome.Add_MouseMove({
        param($s, $e)
        if ($script:dragStart -and $e.Button -eq 'Left') {
            $form.Location = New-Object System.Drawing.Point(
                ($form.Location.X + $e.X - $script:dragStart.X),
                ($form.Location.Y + $e.Y - $script:dragStart.Y))
        }
    })
    $script:pnlChrome.Add_MouseUp({ $script:dragStart = $null })
    
    $form.Controls.Add($script:pnlChrome)
    
    # Bring menus to front to fix z-order
    $script:mainMenuStrip.BringToFront()
}

# Legacy title bar (fallback only when cockpit chrome isn't used AND module unavailable)
if ($script:UseSteamUi -and -not $script:pnlChrome -and -not (Get-Command Add-SteamFormChrome -ErrorAction SilentlyContinue)) {
    # Custom title bar for borderless form (fallback when external chrome module unavailable)
    $script:pnlTitleBar = New-Object System.Windows.Forms.Panel
    $script:pnlTitleBar.Dock = [System.Windows.Forms.DockStyle]::Top
    $script:pnlTitleBar.Height = 32
    $script:pnlTitleBar.BackColor = [System.Drawing.Color]::FromArgb(10, 14, 22)
    Enable-DoubleBuffer $script:pnlTitleBar

    # Title label
    $script:lblTitleBar = New-Object System.Windows.Forms.Label
    $script:lblTitleBar.Text = $script:AppName
    $script:lblTitleBar.Location = New-Object System.Drawing.Point(12, 7)
    $script:lblTitleBar.AutoSize = $true
    $script:lblTitleBar.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $script:lblTitleBar.ForeColor = Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(220, 230, 240))
    $script:lblTitleBar.BackColor = [System.Drawing.Color]::Transparent
    $script:pnlTitleBar.Controls.Add($script:lblTitleBar)

    # Close button
    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = [char]0x2715
    $btnClose.Size = New-Object System.Drawing.Size(36, 32)
    $btnClose.Location = New-Object System.Drawing.Point(($form.ClientSize.Width - 36), 0)
    $btnClose.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $btnClose.FlatStyle = 'Flat'
    $btnClose.FlatAppearance.BorderSize = 0
    $btnClose.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(196, 43, 28)
    $btnClose.BackColor = [System.Drawing.Color]::Transparent
    $btnClose.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(160, 170, 180))
    $btnClose.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $btnClose.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnClose.Add_Click({ $form.Close() })
    $script:pnlTitleBar.Controls.Add($btnClose)

    # Minimize button
    $btnMin = New-Object System.Windows.Forms.Button
    $btnMin.Text = [char]0x2014
    $btnMin.Size = New-Object System.Drawing.Size(36, 32)
    $btnMin.Location = New-Object System.Drawing.Point(($form.ClientSize.Width - 72), 0)
    $btnMin.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $btnMin.FlatStyle = 'Flat'
    $btnMin.FlatAppearance.BorderSize = 0
    $btnMin.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(42, 52, 68)
    $btnMin.BackColor = [System.Drawing.Color]::Transparent
    $btnMin.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(160, 170, 180))
    $btnMin.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $btnMin.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnMin.Add_Click({ $form.WindowState = 'Minimized' })
    $script:pnlTitleBar.Controls.Add($btnMin)

    # Paint the title bar with gradient + accent
    $script:pnlTitleBar.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $w = $s.Width; $h = $s.Height
        $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush (
            (New-Object System.Drawing.Rectangle 0, 0, $w, $h),
            [System.Drawing.Color]::FromArgb(14, 20, 32),
            [System.Drawing.Color]::FromArgb(8, 12, 20),
            90)
        $g.FillRectangle($grad, 0, 0, $w, $h)
        $grad.Dispose()
        # Hot accent line at top
        $accent = Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(118, 201, 255))
        $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(200, $accent.R, $accent.G, $accent.B)), 2
        $g.DrawLine($pen, 0, 0, $w, 0)
        $pen.Dispose()
        # Glow fade below
        $glowBr = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(16, $accent.R, $accent.G, $accent.B))
        $g.FillRectangle($glowBr, 0, 2, $w, 8)
        $glowBr.Dispose()
        # Bottom separator
        $sep = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(40, $accent.R, $accent.G, $accent.B)), 1
        $g.DrawLine($sep, 0, ($h - 1), $w, ($h - 1))
        $sep.Dispose()
    })

    # Drag support
    $script:dragOffset = $null
    $script:pnlTitleBar.Add_MouseDown({
        param($s, $e)
        if ($e.Button -eq 'Left') { $script:dragOffset = $e.Location }
    })
    $script:pnlTitleBar.Add_MouseMove({
        param($s, $e)
        if ($script:dragOffset -and $e.Button -eq 'Left') {
            $form.Location = New-Object System.Drawing.Point(
                ($form.Location.X + $e.X - $script:dragOffset.X),
                ($form.Location.Y + $e.Y - $script:dragOffset.Y))
        }
    })
    $script:pnlTitleBar.Add_MouseUp({ $script:dragOffset = $null })
    $script:lblTitleBar.Add_MouseDown({
        param($s, $e)
        if ($e.Button -eq 'Left') { $script:dragOffset = $e.Location }
    })
    $script:lblTitleBar.Add_MouseMove({
        param($s, $e)
        if ($script:dragOffset -and $e.Button -eq 'Left') {
            $form.Location = New-Object System.Drawing.Point(
                ($form.Location.X + $e.X - $script:dragOffset.X),
                ($form.Location.Y + $e.Y - $script:dragOffset.Y))
        }
    })
    $script:lblTitleBar.Add_MouseUp({ $script:dragOffset = $null })

    [void]$form.Controls.Add($script:pnlTitleBar)
}
if ($script:UseSteamUi) {
    # Form body paint — deep bg + glow orbs + border frame + vignette
    $form.Add_Paint({
        param($sender, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $w = $sender.ClientSize.Width
        $h = $sender.ClientSize.Height

        # Deep gradient background
        $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush (
            (New-Object System.Drawing.Rectangle 0, 0, $w, $h),
            [System.Drawing.Color]::FromArgb(6, 8, 16),
            [System.Drawing.Color]::FromArgb(12, 16, 26),
            [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
        $g.FillRectangle($bg, 0, 0, $w, $h)
        $bg.Dispose()

        # Corner glow orbs — top-right (cyan), bottom-left (blue), center-top (warm)
        $glow = Get-UiColor 'Glow' ([System.Drawing.Color]::FromArgb(110, 198, 255))
        $g1 = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(22, $glow.R, $glow.G, $glow.B))
        $g.FillEllipse($g1, ($w - 260), -60, 380, 240)
        $g1.Dispose()
        $g2 = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(12, $glow.R, $glow.G, $glow.B))
        $g.FillEllipse($g2, -120, ($h - 200), 300, 200)
        $g2.Dispose()
        $g3 = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(8, 180, 140, 255))
        $g.FillEllipse($g3, [int]($w / 2 - 120), -80, 240, 160)
        $g3.Dispose()

        # Inner vignette — darken edges
        $vigT = New-Object System.Drawing.Drawing2D.LinearGradientBrush (
            (New-Object System.Drawing.Rectangle 0, 0, $w, 40),
            [System.Drawing.Color]::FromArgb(40, 0, 0, 0),
            [System.Drawing.Color]::FromArgb(0, 0, 0, 0),
            [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
        $g.FillRectangle($vigT, 0, 0, $w, 40)
        $vigT.Dispose()
        $vigB = New-Object System.Drawing.Drawing2D.LinearGradientBrush (
            (New-Object System.Drawing.Rectangle 0, ($h - 40), $w, 40),
            [System.Drawing.Color]::FromArgb(0, 0, 0, 0),
            [System.Drawing.Color]::FromArgb(50, 0, 0, 0),
            [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
        $g.FillRectangle($vigB, 0, ($h - 40), $w, 40)
        $vigB.Dispose()

        # Border frame — double stroke: outer dark, inner accent
        $darkPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(80, 0, 0, 0)), 1
        $g.DrawRectangle($darkPen, 0, 0, ($w - 1), ($h - 1))
        $darkPen.Dispose()
        $accent = Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(118, 201, 255))
        $accentPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(40, $accent.R, $accent.G, $accent.B)), 1
        $g.DrawRectangle($accentPen, 1, 1, ($w - 3), ($h - 3))
        $accentPen.Dispose()
        # Top accent highlight
        $topPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(70, $accent.R, $accent.G, $accent.B)), 1
        $g.DrawLine($topPen, 2, 0, ($w - 3), 0)
        $topPen.Dispose()
    })
}

function Add-MainControl {
    param($Control, [switch]$NoOffset)
    if (Get-Command Add-UiControl -ErrorAction SilentlyContinue) {
        Add-UiControl -Form $form -Control $Control -NoOffset:$NoOffset
    } else {
        [void]$form.Controls.Add($Control)
    }
}

$script:SteamMainPage = 'library'
if ($script:UseSteamUi -and (Get-Command Add-SteamFormChrome -ErrorAction SilentlyContinue)) {
    Add-SteamFormChrome -Form $form -FormW $script:formW -AppVersion $script:AppVersion `
        -OnLibrary { Set-SteamMainPage 'library' } `
        -OnSchedule { Set-SteamMainPage 'schedule' } `
        -OnSettings { Set-SteamMainPage 'settings' } `
        -OnStats { Show-SleepLedgerDialog }
}

$lblBrand = New-Object System.Windows.Forms.Label
$lblBrand.Text = $script:AppName
$lblBrand.Visible = $false

$lblVer = New-Object System.Windows.Forms.Label
$lblVer.Text = "v$script:AppVersion"
$lblVer.AutoSize = $true
$lblVer.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$lblVer.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
$lblVer.BackColor = Get-UiColor 'Bg' ([System.Drawing.Color]::FromArgb(27, 40, 56))

$script:lblLedger = New-Object System.Windows.Forms.LinkLabel
$script:lblLedger.Text = if ($script:UseSteamUi) { 'View stats' } else { 'Sleep ledger' }
$script:lblLedger.AutoSize = $true
$script:lblLedger.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$script:lblLedger.LinkColor = Get-UiColor 'Mint' ([System.Drawing.Color]::FromArgb(102, 192, 244))
$script:lblLedger.ActiveLinkColor = Get-UiColor 'Amber' ([System.Drawing.Color]::FromArgb(164, 208, 7))
$script:lblLedger.BackColor = Get-UiColor 'Bg' ([System.Drawing.Color]::FromArgb(27, 40, 56))
$script:lblLedger.Add_Click({ Show-SleepLedgerDialog })

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Size = New-Object System.Drawing.Size($script:contentW, 20)
$lblSub.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
$lblSub.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
$lblSub.BackColor = Get-UiColor 'Bg' ([System.Drawing.Color]::FromArgb(27, 40, 56))

$logoPath = $script:LogoPath
if ($logoPath) {
    $picLogo = New-Object System.Windows.Forms.PictureBox
    $picLogo.Location = New-Object System.Drawing.Point(20, 10)
    $picLogo.Size = New-Object System.Drawing.Size(240, 48)
    $picLogo.SizeMode = 'Zoom'
    $picLogo.BackColor = Get-UiColor 'Bg' ([System.Drawing.Color]::FromArgb(27, 40, 56))
    $picLogo.Image = [System.Drawing.Image]::FromFile($logoPath)
    Add-MainControl($picLogo)
    $lblVer.Location = New-Object System.Drawing.Point(272, 26)
    $script:lblLedger.Location = New-Object System.Drawing.Point(312, 26)
    $lblSub.Location = New-Object System.Drawing.Point(24, 58)
} else {
    $lblBrand.Visible = $true
    $lblBrand.Location = New-Object System.Drawing.Point(24, 14)
    $lblBrand.AutoSize = $true
    $lblBrand.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
    $lblBrand.ForeColor = Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
    $lblBrand.BackColor = Get-UiColor 'Bg' ([System.Drawing.Color]::FromArgb(27, 40, 56))
    Add-MainControl($lblBrand)
    $lblVer.Location = New-Object System.Drawing.Point(140, 18)
    $script:lblLedger.Location = New-Object System.Drawing.Point(312, 18)
    $lblSub.Location = New-Object System.Drawing.Point(24, 44)
}
Add-MainControl($lblVer)
Add-MainControl($script:lblLedger)
Add-MainControl($lblSub)
if ($script:UseSteamUi -and (Get-Command Add-SteamHeroPanel -ErrorAction SilentlyContinue)) {
    $lblSub.Visible = $false
    if ($logoPath) { $picLogo.Visible = $false }
    $lblVer.Visible = $false
    $script:lblLedger.Visible = $false
    $heroY = 12
    Add-SteamHeroPanel -Form $form -Y $heroY -Width $script:contentW
    Add-SteamTrustBadgesPanel -Form $form -Y (98 + $script:yBoost) -Width $script:contentW
    Add-SteamSleepClearancePanel -Form $form -Y (312 + $script:yBoost) -Width $script:contentW
    Add-SteamMorningProofActions -Form $form -Y (378 + $script:yBoost) -Width $script:contentW `
        -OnLedger { Show-SleepLedgerDialog } `
        -OnDismiss { Dismiss-MorningProof }
}

$lblDry = New-Object System.Windows.Forms.Label
$lblDry.Text = 'DRY RUN - no power action'
$lblDry.Location = New-Object System.Drawing.Point(24, $script:statusY)
$lblDry.Size = New-Object System.Drawing.Size($script:contentW, 16)
$lblDry.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
$lblDry.ForeColor = Get-UiColor 'Amber' ([System.Drawing.Color]::FromArgb(164, 208, 7))
$lblDry.BackColor = Get-UiColor 'Bg' ([System.Drawing.Color]::FromArgb(27, 40, 56))
$lblDry.Visible = (Test-NoPowerAction)
Add-MainControl($lblDry)

$script:lblDemo = New-Object System.Windows.Forms.Label
$script:lblDemo.Text = 'DEMO MODE - safe preview - sample data - no settings or log writes'
$script:lblDemo.Location = New-Object System.Drawing.Point(24, $script:statusY)
$script:lblDemo.Size = New-Object System.Drawing.Size($script:contentW, 16)
$script:lblDemo.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
$script:lblDemo.ForeColor = Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))
$script:lblDemo.BackColor = Get-UiColor 'Bg' ([System.Drawing.Color]::FromArgb(27, 40, 56))
$script:lblDemo.Visible = [bool]$script:DemoMode
Add-MainControl($script:lblDemo)

$lblHotkey = New-Object System.Windows.Forms.Label
$lblHotkey.Text = 'Ctrl+Alt+5/0/P = +5m/+10m/pause - Ctrl+Shift+S = cancel (x2)'
$hotkeyY = if ($script:DemoMode) { ($script:statusY + 18) } else { $script:statusY }
$lblHotkey.Location = New-Object System.Drawing.Point(24, $hotkeyY)
$lblHotkey.Size = New-Object System.Drawing.Size($script:contentW, 16)
$lblHotkey.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$lblHotkey.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
$lblHotkey.BackColor = Get-UiColor 'Bg' ([System.Drawing.Color]::FromArgb(27, 40, 56))
$lblHotkey.Visible = -not (Test-NoPowerAction)
if ($script:DemoMode -and (Test-NoPowerAction)) {
    $lblDry.Location = New-Object System.Drawing.Point(24, ($script:statusY + 18))
}
Add-MainControl($lblHotkey)

$pnlRing = New-Object System.Windows.Forms.Panel
$pnlRing.Location = New-Object System.Drawing.Point(108, (98 + $script:yBoost))
$pnlRing.Size = New-Object System.Drawing.Size(180, 180)
$pnlRing.BackColor = Get-UiColor 'Bg' ([System.Drawing.Color]::FromArgb(27, 40, 56))
Enable-DoubleBuffer $pnlRing
$pnlRing.Add_Paint({ param($s, $e); Draw-Ring $e.Graphics $s.Width $s.Height })
$pnlRing.Add_DoubleClick({
    if ($script:Running -or $script:Paused) { Show-BigPicture }
})
$script:ringCtxMenu = New-Object System.Windows.Forms.ContextMenuStrip
$script:ringCtxMenu.BackColor = [System.Drawing.Color]::FromArgb(16, 20, 30)
$script:ringCtxMenu.ForeColor = [System.Drawing.Color]::FromArgb(210, 220, 230)
$script:ringCtxMenu.ShowImageMargin = $false
$script:ringCtxMenu.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$ctxRenderer = New-Object System.Windows.Forms.ToolStripProfessionalRenderer (
    New-Object System.Windows.Forms.ProfessionalColorTable)
$script:ringCtxMenu.Renderer = $ctxRenderer
$script:ringCtxMenu.Add_Paint({
    param($s, $e)
    $accent = Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(118, 201, 255))
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(60, $accent.R, $accent.G, $accent.B)), 1
    $e.Graphics.DrawRectangle($pen, 0, 0, ($s.Width - 1), ($s.Height - 1))
    $pen.Dispose()
})
$headerItem = New-Object System.Windows.Forms.ToolStripLabel ([char]0x23F0 + '  Clock Face')
$headerItem.ForeColor = Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))
$headerItem.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5, [System.Drawing.FontStyle]::Bold)
[void]$script:ringCtxMenu.Items.Add($headerItem)
[void]$script:ringCtxMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
foreach ($cfs in (Get-ClockFaceStyles)) {
    $mi = New-Object System.Windows.Forms.ToolStripMenuItem $cfs.Name
    $mi.Tag = $cfs.Id
    $mi.Checked = ($cfs.Id -eq $script:ClockFaceStyle)
    $mi.Add_Click({
        $clickedId = $this.Tag
        $script:ClockFaceStyle = $clickedId
        foreach ($item in $script:ringCtxMenu.Items) {
            if ($item -is [System.Windows.Forms.ToolStripMenuItem]) {
                $item.Checked = ($item.Tag -eq $clickedId)
            }
        }
        if ($script:cboClockFace) {
            $pick = $script:cboClockFace.Items | Where-Object { $_.Id -eq $clickedId } | Select-Object -First 1
            if ($pick) { $script:cboClockFace.SelectedItem = $pick }
        }
        if ($pnlRing) { $pnlRing.Invalidate() }
        if ($script:bpRing) { $script:bpRing.Invalidate() }
        if (-not $script:Running) { Save-Settings }
    }.GetNewClosure())
    [void]$script:ringCtxMenu.Items.Add($mi)
}
[void]$script:ringCtxMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$miAccent = New-Object System.Windows.Forms.ToolStripMenuItem 'Custom Accent Color...'
$miAccent.Add_Click({
    $dlg = New-Object System.Windows.Forms.ColorDialog
    $dlg.AllowFullOpen = $true
    $dlg.AnyColor = $true
    if ($script:CustomAccentColor) { $dlg.Color = $script:CustomAccentColor }
    else { $dlg.Color = Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244)) }
    if ($dlg.ShowDialog() -eq 'OK') {
        $script:CustomAccentColor = $dlg.Color
        if ($pnlRing) { $pnlRing.Invalidate() }
        if (-not $script:Running) { Save-Settings }
        Write-AuditLog 'accent_color' "rgb=$($dlg.Color.R),$($dlg.Color.G),$($dlg.Color.B)"
    }
})
[void]$script:ringCtxMenu.Items.Add($miAccent)
$miResetAccent = New-Object System.Windows.Forms.ToolStripMenuItem 'Reset Accent Color'
$miResetAccent.Add_Click({
    $script:CustomAccentColor = $null
    if ($pnlRing) { $pnlRing.Invalidate() }
    if (-not $script:Running) { Save-Settings }
    Write-AuditLog 'accent_color' 'reset'
})
[void]$script:ringCtxMenu.Items.Add($miResetAccent)
$pnlRing.ContextMenuStrip = $script:ringCtxMenu
Add-MainControl($pnlRing)

$pnlPunch = New-Object System.Windows.Forms.Panel
$pnlPunch.Location = $pnlRing.Location
$pnlPunch.Size = $pnlRing.Size
$pnlPunch.BackColor = Get-UiColor 'Bg' ([System.Drawing.Color]::FromArgb(27, 40, 56))
$pnlPunch.Visible = $false
Enable-DoubleBuffer $pnlPunch
$pnlPunch.Add_Paint({
    param($s, $e)
    if ($script:punchFrame -ge 0) {
        Draw-PunchScene $e.Graphics $script:punchFrame $s.Width $s.Height
    }
})
Add-MainControl($pnlPunch)

$script:pnlDim = New-Object System.Windows.Forms.Panel
$script:pnlDim.Dock = 'Fill'
$script:pnlDim.BackColor = [System.Drawing.Color]::FromArgb(220, 0, 0, 0)
$script:pnlDim.Visible = $false
Add-MainControl $script:pnlDim -NoOffset

$script:lblDimMsg = New-Object System.Windows.Forms.Label
$script:lblDimMsg.Size = New-Object System.Drawing.Size(380, 48)
$script:lblDimMsg.Location = New-Object System.Drawing.Point(20, 120)
$script:lblDimMsg.TextAlign = 'MiddleCenter'
$script:lblDimMsg.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$script:lblDimMsg.ForeColor = Get-UiColor 'Amber' ([System.Drawing.Color]::FromArgb(164, 208, 7))
$script:lblDimMsg.BackColor = [System.Drawing.Color]::Transparent
$script:pnlDim.Controls.Add($script:lblDimMsg)

$script:lblDimCount = New-Object System.Windows.Forms.Label
$script:lblDimCount.Size = New-Object System.Drawing.Size(380, 36)
$script:lblDimCount.Location = New-Object System.Drawing.Point(20, 168)
$script:lblDimCount.TextAlign = 'MiddleCenter'
$script:lblDimCount.Font = New-Object System.Drawing.Font('Consolas', 28, [System.Drawing.FontStyle]::Bold)
$script:lblDimCount.ForeColor = Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
$script:lblDimCount.BackColor = [System.Drawing.Color]::Transparent
$script:pnlDim.Controls.Add($script:lblDimCount)

$btnDimSnooze = New-Object System.Windows.Forms.Button
$btnDimSnooze.Text = '+5 min wind-down'
$btnDimSnooze.Size = New-Object System.Drawing.Size(160, 36)
$btnDimSnooze.Location = New-Object System.Drawing.Point(40, 260)
Style-Button $btnDimSnooze ([System.Drawing.Color]::FromArgb(36, 36, 50)) $script:C.Ink 9
$btnDimSnooze.Add_Click({
    Stop-LightsDimPhase
    Write-AuditLog 'dim_phase_snooze' '300'
    $script:Left = 300
    $script:Running = $true
    Reset-CountdownWarnFlags
    $script:timer.Start()
    $script:pulseTimer.Start()
    Update-Ui
})
$script:pnlDim.Controls.Add($btnDimSnooze)

$btnDimProceed = New-Object System.Windows.Forms.Button
$btnDimProceed.Text = 'Proceed now'
$btnDimProceed.Size = New-Object System.Drawing.Size(160, 36)
$btnDimProceed.Location = New-Object System.Drawing.Point(220, 260)
Style-Button $btnDimProceed $script:C.Amber ([System.Drawing.Color]::FromArgb(18, 14, 8)) 9
$btnDimProceed.Add_Click({
    Stop-LightsDimPhase
    Write-AuditLog 'dim_phase_skip' ''
    if ($script:dimComplete) { & $script:dimComplete }
})
$script:pnlDim.Controls.Add($btnDimProceed)

$script:dimTimer = New-Object System.Windows.Forms.Timer
$script:dimTimer.Interval = 1000
$script:dimTimer.Add_Tick({
    if ($script:dimLeft -le 0) {
        Stop-LightsDimPhase
        if ($script:dimComplete) { & $script:dimComplete }
        return
    }
    $script:dimLeft--
    $total = Get-DimPhaseDuration
    $ratio = $script:dimLeft / [math]::Max(1, $total)
    $alpha = [int](220 * (1 - $ratio) + 40)
    $script:pnlDim.BackColor = [System.Drawing.Color]::FromArgb($alpha, 0, 0, 0)
    $script:lblDimCount.Text = ([TimeSpan]::FromSeconds($script:dimLeft)).ToString('mm\:ss')
    $script:lblDimMsg.Text = "Dim the room - breathe - $($script:Action.ToLower()) in $script:dimLeft s"
})

$script:pnlLastLight = New-Object System.Windows.Forms.Panel
$script:pnlLastLight.Dock = 'Fill'
$script:pnlLastLight.BackColor = [System.Drawing.Color]::FromArgb(230, 12, 18, 28)
$script:pnlLastLight.Visible = $false
$script:pnlLastLight.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $top = [System.Drawing.Color]::FromArgb(18, 24, 36)
    $bot = [System.Drawing.Color]::FromArgb(8, 10, 16)
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush (
        (New-Object System.Drawing.Rectangle 0, 0, $s.Width, $s.Height),
        $top, $bot, 90)
    $g.FillRectangle($brush, 0, 0, $s.Width, $s.Height)
    $brush.Dispose()
})
Add-MainControl $script:pnlLastLight -NoOffset

$script:lblLastLightSeq = New-Object System.Windows.Forms.Label
$script:lblLastLightSeq.Size = New-Object System.Drawing.Size(420, 20)
$script:lblLastLightSeq.TextAlign = 'MiddleCenter'
$script:lblLastLightSeq.Font = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Bold)
$script:lblLastLightSeq.ForeColor = Get-UiColor 'Amber' ([System.Drawing.Color]::FromArgb(164, 208, 7))
$script:lblLastLightSeq.BackColor = [System.Drawing.Color]::Transparent
$script:pnlLastLight.Controls.Add($script:lblLastLightSeq)

$script:lblLastLightMainTitle = New-Object System.Windows.Forms.Label
$script:lblLastLightMainTitle.Size = New-Object System.Drawing.Size(420, 48)
$script:lblLastLightMainTitle.TextAlign = 'MiddleCenter'
$script:lblLastLightMainTitle.Font = New-Object System.Drawing.Font('Segoe UI', 24, [System.Drawing.FontStyle]::Bold)
$script:lblLastLightMainTitle.ForeColor = Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
$script:lblLastLightMainTitle.BackColor = [System.Drawing.Color]::Transparent
$script:pnlLastLight.Controls.Add($script:lblLastLightMainTitle)

$script:pnlLastLightRing = New-Object System.Windows.Forms.Panel
$script:pnlLastLightRing.Size = New-Object System.Drawing.Size(180, 180)
$script:pnlLastLightRing.BackColor = [System.Drawing.Color]::Transparent
Enable-DoubleBuffer $script:pnlLastLightRing
$script:pnlLastLightRing.Add_Paint({
    param($s, $e)
    $totalMs = 0
    $doneMs = 0
    if ($script:lastLightSteps -and $script:lastLightSteps.Count -gt 0) {
        for ($i = 0; $i -lt $script:lastLightSteps.Count; $i++) {
            $totalMs += [int]$script:lastLightSteps[$i].DwellMs
            if ($i -lt $script:lastLightStepIndex) { $doneMs += [int]$script:lastLightSteps[$i].DwellMs }
        }
    }
    $pct = if ($totalMs -gt 0) { 1.0 - ($doneMs / $totalMs) } else { 1.0 }
    Draw-LastLightRing $e.Graphics $s.Width $s.Height $pct
})
$script:pnlLastLight.Controls.Add($script:pnlLastLightRing)

$script:lblLastLightRingTime = New-Object System.Windows.Forms.Label
$script:lblLastLightRingTime.Size = New-Object System.Drawing.Size(120, 34)
$script:lblLastLightRingTime.TextAlign = 'MiddleCenter'
$script:lblLastLightRingTime.Font = New-Object System.Drawing.Font('Consolas', 20, [System.Drawing.FontStyle]::Bold)
$script:lblLastLightRingTime.ForeColor = Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
$script:lblLastLightRingTime.BackColor = [System.Drawing.Color]::Transparent
$script:pnlLastLightRing.Controls.Add($script:lblLastLightRingTime)

$script:lblLastLightRingSub = New-Object System.Windows.Forms.Label
$script:lblLastLightRingSub.Size = New-Object System.Drawing.Size(120, 16)
$script:lblLastLightRingSub.TextAlign = 'MiddleCenter'
$script:lblLastLightRingSub.Font = New-Object System.Drawing.Font('Segoe UI', 7.5, [System.Drawing.FontStyle]::Bold)
$script:lblLastLightRingSub.ForeColor = Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))
$script:lblLastLightRingSub.BackColor = [System.Drawing.Color]::Transparent
$script:pnlLastLightRing.Controls.Add($script:lblLastLightRingSub)

$script:lblLastLightSideHead = New-Object System.Windows.Forms.Label
$script:lblLastLightSideHead.Size = New-Object System.Drawing.Size(160, 22)
$script:lblLastLightSideHead.Font = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Bold)
$script:lblLastLightSideHead.ForeColor = Get-UiColor 'Amber' ([System.Drawing.Color]::FromArgb(164, 208, 7))
$script:lblLastLightSideHead.BackColor = [System.Drawing.Color]::Transparent
$script:pnlLastLight.Controls.Add($script:lblLastLightSideHead)

$script:lblLastLightSideBody = New-Object System.Windows.Forms.Label
$script:lblLastLightSideBody.Size = New-Object System.Drawing.Size(160, 48)
$script:lblLastLightSideBody.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$script:lblLastLightSideBody.ForeColor = Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
$script:lblLastLightSideBody.BackColor = [System.Drawing.Color]::Transparent
$script:pnlLastLight.Controls.Add($script:lblLastLightSideBody)

$script:lblLastLightProceed = New-Object System.Windows.Forms.Label
$script:lblLastLightProceed.Size = New-Object System.Drawing.Size(220, 36)
$script:lblLastLightProceed.TextAlign = 'MiddleCenter'
$script:lblLastLightProceed.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$script:lblLastLightProceed.ForeColor = Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
$script:lblLastLightProceed.BackColor = Get-UiColor 'NavOn' ([System.Drawing.Color]::FromArgb(62, 126, 167))
$script:lblLastLightProceed.Visible = $false
$script:pnlLastLight.Controls.Add($script:lblLastLightProceed)

$script:lblLastLightConfirm = New-Object System.Windows.Forms.Label
$script:lblLastLightConfirm.Size = New-Object System.Drawing.Size(260, 16)
$script:lblLastLightConfirm.Text = 'CONFIRM FINAL DISCONNECTION'
$script:lblLastLightConfirm.TextAlign = 'MiddleCenter'
$script:lblLastLightConfirm.Font = New-Object System.Drawing.Font('Segoe UI', 7.5)
$script:lblLastLightConfirm.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
$script:lblLastLightConfirm.BackColor = [System.Drawing.Color]::Transparent
$script:lblLastLightConfirm.Visible = $false
$script:pnlLastLight.Controls.Add($script:lblLastLightConfirm)

$script:lblLastLightCancel = New-Object System.Windows.Forms.Label
$script:lblLastLightCancel.Size = New-Object System.Drawing.Size(320, 18)
$script:lblLastLightCancel.Text = 'EMERGENCY CANCEL    Ctrl+Shift+S'
$script:lblLastLightCancel.TextAlign = 'MiddleCenter'
$script:lblLastLightCancel.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
$script:lblLastLightCancel.ForeColor = Get-UiColor 'Amber' ([System.Drawing.Color]::FromArgb(164, 208, 7))
$script:lblLastLightCancel.BackColor = [System.Drawing.Color]::Transparent
$script:pnlLastLight.Controls.Add($script:lblLastLightCancel)

$script:lblLastLightHead = New-Object System.Windows.Forms.Label
$script:lblLastLightHead.Visible = $false
$script:pnlLastLight.Controls.Add($script:lblLastLightHead)

$script:lblLastLightBody = New-Object System.Windows.Forms.Label
$script:lblLastLightBody.Visible = $false
$script:pnlLastLight.Controls.Add($script:lblLastLightBody)

function Layout-LastLightOverlay {
    if (-not $script:pnlLastLight) { return }
    try {
    $w = $form.ClientSize.Width
    $h = $form.ClientSize.Height
    $cx = [int]($w / 2)
    $cy = [int]($h / 2)
    $seqX = [int]($cx - 210)
    $seqY = [int][math]::Max(24, ($cy - 190))
    $script:lblLastLightSeq.Location = New-Object System.Drawing.Point($seqX, $seqY)
    $titleY = [int]($script:lblLastLightSeq.Location.Y + 24)
    $script:lblLastLightMainTitle.Location = New-Object System.Drawing.Point($seqX, $titleY)
    $script:pnlLastLightRing.Location = New-Object System.Drawing.Point([int]($cx - 90), [int]($cy - 70))
    $script:lblLastLightRingTime.Location = New-Object System.Drawing.Point(30, 62)
    $script:lblLastLightRingSub.Location = New-Object System.Drawing.Point(30, 96)
    $script:lblLastLightSideHead.Location = New-Object System.Drawing.Point(24, [int]($cy - 20))
    $script:lblLastLightSideBody.Location = New-Object System.Drawing.Point(24, [int]($cy + 4))
    $script:lblLastLightProceed.Location = New-Object System.Drawing.Point([int]($cx - 110), [int]($cy + 108))
    $script:lblLastLightConfirm.Location = New-Object System.Drawing.Point([int]($cx - 130), [int]($cy + 148))
    $script:lblLastLightCancel.Location = New-Object System.Drawing.Point([int]($cx - 160), [int]($h - 42))
    } catch {
        Write-AuditLog 'last_light_layout_error' $_.Exception.Message
    }
}

$form.Add_Resize({
    Layout-LastLightOverlay
})
Layout-LastLightOverlay

$script:punchFrame = -1
$script:punchComplete = $null
$script:punchImpactPlayed = $false
$script:sessionEndTimer = New-Object System.Windows.Forms.Timer
$script:sessionEndTimer.Add_Tick({
    if ($script:endPhase -eq 'lastlight') {
        $script:sessionEndTimer.Stop()
        if ($script:lastLightRunning) {
            Write-AuditLog 'last_light_timer_complete' "sequence=$($script:LastLightSequence)"
            Complete-LastLightSequence
        }
        return
    }
    if ($script:endPhase -eq 'dim') {
        Invoke-DimPhaseTick
    }
})

$script:punchTimer = New-Object System.Windows.Forms.Timer
$script:punchTimer.Interval = 36
$script:punchTimer.Add_Tick({
    if ($script:punchFrame -lt 0) { return }
    if ($script:punchFrame -eq 12 -and -not $script:punchImpactPlayed) {
        [System.Media.SystemSounds]::Hand.Play()
        $script:punchImpactPlayed = $true
    }
    $script:punchFrame++
    $pnlPunch.Invalidate()
    if ($script:punchFrame -gt 34) {
        $script:punchTimer.Stop()
        $pnlPunch.Visible = $false
        $script:punchFrame = -1
        if ($script:punchComplete) {
            $cb = $script:punchComplete
            $script:punchComplete = $null
            & $cb
        }
    }
})

$timeFont = 'Consolas'
try { $null = New-Object System.Drawing.Font('Cascadia Mono', 12); $timeFont = 'Cascadia Mono' } catch { }

$lblLobbyTag = New-Object System.Windows.Forms.Label
$lblLobbyTag.Location = New-Object System.Drawing.Point(0, 48)
$lblLobbyTag.Size = New-Object System.Drawing.Size(220, 18)
$lblLobbyTag.Text = 'LOBBY'
$lblLobbyTag.TextAlign = 'MiddleCenter'
$lblLobbyTag.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 7.5, [System.Drawing.FontStyle]::Bold)
$lblLobbyTag.ForeColor = Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))
$lblLobbyTag.BackColor = [System.Drawing.Color]::Transparent
$lblLobbyTag.Visible = $false
$pnlRing.Controls.Add($lblLobbyTag)

$lblUrgent = New-Object System.Windows.Forms.Label
$lblUrgent.Location = New-Object System.Drawing.Point(0, 6)
$lblUrgent.Size = New-Object System.Drawing.Size(220, 18)
$lblUrgent.TextAlign = 'MiddleCenter'
$lblUrgent.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
$lblUrgent.ForeColor = Get-UiColor 'Rose' ([System.Drawing.Color]::FromArgb(255, 107, 107))
$lblUrgent.BackColor = [System.Drawing.Color]::Transparent
$lblUrgent.Visible = $false
$pnlRing.Controls.Add($lblUrgent)

$lblTime = New-Object System.Windows.Forms.Label
$lblTime.Location = New-Object System.Drawing.Point(0, 72)
$lblTime.Size = New-Object System.Drawing.Size(220, 48)
$lblTime.TextAlign = 'MiddleCenter'
$lblTime.Font = New-Object System.Drawing.Font($timeFont, 38, [System.Drawing.FontStyle]::Bold)
$lblTime.ForeColor = Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(220, 232, 240))
$lblTime.BackColor = [System.Drawing.Color]::Transparent
$pnlRing.Controls.Add($lblTime)

$lblRemain = New-Object System.Windows.Forms.Label
$lblRemain.Location = New-Object System.Drawing.Point(0, 120)
$lblRemain.Size = New-Object System.Drawing.Size(220, 18)
$lblRemain.TextAlign = 'MiddleCenter'
$lblRemain.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5)
$lblRemain.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(150, 162, 178))
$lblRemain.BackColor = [System.Drawing.Color]::Transparent
$pnlRing.Controls.Add($lblRemain)

$lblPct = New-Object System.Windows.Forms.Label
$lblPct.Location = New-Object System.Drawing.Point(0, 136)
$lblPct.Size = New-Object System.Drawing.Size(220, 16)
$lblPct.TextAlign = 'MiddleCenter'
$lblPct.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$lblPct.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
$lblPct.BackColor = [System.Drawing.Color]::Transparent
$pnlRing.Controls.Add($lblPct)

$lblEnd = New-Object System.Windows.Forms.Label
$lblEnd.Location = New-Object System.Drawing.Point(24, ($(if ($script:UseSteamUi) { 348 } else { 304 }) + $script:yBoost))
$lblEnd.Size = New-Object System.Drawing.Size($script:contentW, 24)
$lblEnd.TextAlign = 'MiddleCenter'
$lblEnd.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5, [System.Drawing.FontStyle]::Bold)
$lblEnd.ForeColor = Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))
$lblEnd.BackColor = [System.Drawing.Color]::FromArgb(14, 20, 32)
Add-MainControl($lblEnd)

$script:pnlClassicDivider = New-UiDivider -X 24 -Y (362 + $script:yBoost) -W $script:contentW
Add-MainControl($script:pnlClassicDivider)

# Control row
$btnSnooze5 = New-Object System.Windows.Forms.Button
$btnSnooze5.Text = '+5'
$btnSnooze5.Location = New-Object System.Drawing.Point(24, (328 + $script:yBoost))
$btnSnooze5.Size = New-Object System.Drawing.Size(52, 40)
Style-Button $btnSnooze5 ([System.Drawing.Color]::FromArgb(28, 36, 50)) $script:C.Ink 10 ([System.Drawing.Color]::FromArgb(42, 52, 68)) 1
$btnSnooze5.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(56, 72, 96)
Add-MainControl($btnSnooze5)

$btnSnooze = New-Object System.Windows.Forms.Button
$btnSnooze.Text = '+10'
$btnSnooze.Location = New-Object System.Drawing.Point(82, (328 + $script:yBoost))
$btnSnooze.Size = New-Object System.Drawing.Size(52, 40)
Style-Button $btnSnooze ([System.Drawing.Color]::FromArgb(28, 36, 50)) $script:C.Ink 10 ([System.Drawing.Color]::FromArgb(42, 52, 68)) 1
$btnSnooze.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(56, 72, 96)
Add-MainControl($btnSnooze)

$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Text = 'Pause'
$btnStop.Location = New-Object System.Drawing.Point(140, (328 + $script:yBoost))
$btnStop.Size = New-Object System.Drawing.Size(120, 40)
Style-Button $btnStop ([System.Drawing.Color]::FromArgb(28, 36, 50)) $script:C.Ink 10 ([System.Drawing.Color]::FromArgb(42, 52, 68)) 1
$btnStop.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(56, 72, 96)
Add-MainControl($btnStop)

$btnStart = New-Object System.Windows.Forms.Button
$script:btnStartUi = $btnStart
$btnStart.Location = New-Object System.Drawing.Point(272, (328 + $script:yBoost))
$btnStart.Size = New-Object System.Drawing.Size(140, 42)
Add-MainControl($btnStart)
Update-StartButtonStyle

$script:lblSchedule = New-Object System.Windows.Forms.Label
Set-SectionLabelStyle $script:lblSchedule $(if ($script:UseSteamUi) { 'Tonight' } else { 'Schedule' })
$script:lblSchedule.Location = New-Object System.Drawing.Point(24, ($(if ($script:UseSteamUi) { 422 } else { 372 }) + $script:yBoost))
$script:lblSchedule.Size = New-Object System.Drawing.Size(80, 14)
Add-MainControl($script:lblSchedule)
$lblSchedule = $script:lblSchedule

$script:pnlSchedule = New-Object System.Windows.Forms.Panel
$script:pnlSchedule.Location = New-Object System.Drawing.Point(20, ($(if ($script:UseSteamUi) { 438 } else { 388 }) + $script:yBoost))
$script:pnlSchedule.Size = New-Object System.Drawing.Size($script:contentW, $script:ySchedule)
$script:pnlSchedule.BackColor = Get-UiColor 'Elevated' ([System.Drawing.Color]::FromArgb(42, 71, 94))
Add-MainControl($script:pnlSchedule)
Apply-SteamSurfaceStyle $script:pnlSchedule 'Blue'
$pnlSchedule = $script:pnlSchedule

$script:uiToolTip = New-Object System.Windows.Forms.ToolTip
$script:uiToolTip.AutoPopDelay = 8000
$script:uiToolTip.InitialDelay = 400
$script:uiToolTip.SetToolTip($pnlRing, 'Double-click for Cinema mode (fullscreen countdown)')

# Mode + presets
$pnlMode = New-Object System.Windows.Forms.FlowLayoutPanel
$pnlMode.Location = New-Object System.Drawing.Point(8, 8)
$pnlMode.Size = New-Object System.Drawing.Size(($script:contentW - 16), 30)
$pnlMode.BackColor = Get-UiColor 'Elevated' ([System.Drawing.Color]::FromArgb(42, 71, 94))
$pnlSchedule.Controls.Add($pnlMode)
Apply-SteamSurfaceStyle $pnlMode 'Section'

$btnModeDuration = New-Object System.Windows.Forms.Button
$btnModeDuration.Text = 'Countdown'
$btnModeDuration.Size = New-Object System.Drawing.Size(88, 28)
$btnModeDuration.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
Style-Button $btnModeDuration ([System.Drawing.Color]::FromArgb(30, 30, 42)) $script:C.Muted 8 ([System.Drawing.Color]::FromArgb(44, 44, 58))
$pnlMode.Controls.Add($btnModeDuration)

$btnModeClock = New-Object System.Windows.Forms.Button
$btnModeClock.Text = 'Tonight'
$btnModeClock.Size = New-Object System.Drawing.Size(72, 28)
$btnModeClock.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
Style-Button $btnModeClock ([System.Drawing.Color]::FromArgb(30, 30, 42)) $script:C.Muted 8 ([System.Drawing.Color]::FromArgb(44, 44, 58))
$pnlMode.Controls.Add($btnModeClock)

$btnModeCalendar = New-Object System.Windows.Forms.Button
$btnModeCalendar.Text = 'Calendar'
$btnModeCalendar.Size = New-Object System.Drawing.Size(80, 28)
$btnModeCalendar.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
Style-Button $btnModeCalendar ([System.Drawing.Color]::FromArgb(30, 30, 42)) $script:C.Muted 8 ([System.Drawing.Color]::FromArgb(44, 44, 58))
$pnlMode.Controls.Add($btnModeCalendar)

function Set-TimerMode {
    param([ValidateSet('duration', 'clock', 'calendar')][string]$Mode)
    $script:TimerMode = $Mode
    $onDuration = ($Mode -eq 'duration')
    $pnlPresets.Visible = $onDuration -and $script:UseSteamUi
    if ($script:pnlLobbyTimer) {
        $showLobbyTimer = $onDuration -and (
            (-not $script:UseSteamUi) -or ($script:SteamMainPage -eq 'library')
        )
        $script:pnlLobbyTimer.Visible = $showLobbyTimer
    }
    $pnlClock.Visible = ($Mode -in @('clock', 'calendar'))
    if ($script:dtpDate) { $script:dtpDate.Visible = ($Mode -eq 'calendar') }
    if ($script:btnCalImport) { $script:btnCalImport.Visible = ($Mode -eq 'calendar') }
    if ($script:btnCalFeed) { $script:btnCalFeed.Visible = ($Mode -eq 'calendar') }
    if ($script:lblCalEvent) { Update-CalendarEventLabel }
    $off = if ($script:UseSteamUi) {
        Get-UiColor 'NavOff' ([System.Drawing.Color]::FromArgb(46, 54, 64))
    } else {
        Get-UiColor 'Card' ([System.Drawing.Color]::FromArgb(20, 20, 30))
    }
    $offFg = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
    $onFg = if ($script:UseSteamUi) {
        Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
    } else {
        [System.Drawing.Color]::FromArgb(14, 12, 10)
    }
    $onDur = if ($script:UseSteamUi) {
        Get-UiColor 'NavOn' ([System.Drawing.Color]::FromArgb(62, 126, 167))
    } else {
        Get-UiColor 'Amber' ([System.Drawing.Color]::FromArgb(242, 182, 92))
    }
    $onCal = if ($script:UseSteamUi) {
        Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))
    } else {
        Get-UiColor 'Mint' ([System.Drawing.Color]::FromArgb(92, 218, 172))
    }
    Style-Button $btnModeDuration $(if ($Mode -eq 'duration') { $onDur } else { $off }) $(if ($Mode -eq 'duration') { $onFg } else { $offFg }) 8
    Style-Button $btnModeClock $(if ($Mode -eq 'clock') { $onDur } else { $off }) $(if ($Mode -eq 'clock') { $onFg } else { $offFg }) 8
    Style-Button $btnModeCalendar $(if ($Mode -eq 'calendar') { $onCal } else { $off }) $(if ($Mode -eq 'calendar') { $onFg } else { $offFg }) 8
    if ($script:btnCalFeed) {
        $feedOn = ($Mode -eq 'calendar' -and $script:CalendarFeedUrl)
        Style-Button $script:btnCalFeed $(if ($feedOn) { [System.Drawing.Color]::FromArgb(20, 36, 32) } else { $off }) `
            $(if ($feedOn) { $script:C.Mint } else { $offFg }) 8
    }
    if ($Mode -eq 'calendar' -and -not $script:ScheduledAt) { Sync-ScheduledFromPickers }
    if (-not $script:Running -and $script:UiReady) { Save-Settings }
    Mark-TonightCardCustom
    Update-CalendarEventLabel
    Update-ScheduleSectionLayout
    if (-not $script:UseSteamUi) { Apply-ClassicSimpleLayout }
    Update-Ui
}

$btnModeDuration.Add_Click({ Set-TimerMode 'duration' })
$btnModeClock.Add_Click({ Set-TimerMode 'clock' })
$btnModeCalendar.Add_Click({ Set-TimerMode 'calendar' })
$script:uiToolTip.SetToolTip($btnModeDuration, 'Count down minutes from now')
$script:uiToolTip.SetToolTip($btnModeClock, 'Shut down at a time tonight or tomorrow')
$script:uiToolTip.SetToolTip($btnModeCalendar, 'Pick a date, import .ics, or live feed')

# One-tap rituals
$lblRitual = New-Object System.Windows.Forms.Label
Set-SectionLabelStyle $lblRitual $(if ($script:UseSteamUi) { 'Installed tonight' } else { 'Quick rituals' })
$lblRitual.Location = New-Object System.Drawing.Point(8, 82)
$lblRitual.Size = New-Object System.Drawing.Size(120, 14)
$pnlSchedule.Controls.Add($lblRitual)

$pnlRituals = New-Object System.Windows.Forms.FlowLayoutPanel
$pnlRituals.Location = New-Object System.Drawing.Point(8, 98)
$pnlRituals.Size = New-Object System.Drawing.Size(($script:contentW - 16), 34)
$pnlRituals.BackColor = Get-UiColor 'Elevated' ([System.Drawing.Color]::FromArgb(42, 71, 94))
$pnlSchedule.Controls.Add($pnlRituals)
Apply-SteamSurfaceStyle $pnlRituals 'Amber'

$script:RitualBtns = @()
foreach ($rit in Get-RitualCatalog) {
    $rb = New-Object System.Windows.Forms.Button
    $rb.Text = $rit.Label
    $rb.Tag = $rit
    $rb.Size = New-Object System.Drawing.Size(94, 30)
    $rb.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
    $ritCopy = $rit
    Style-Button $rb ([System.Drawing.Color]::FromArgb(28, 26, 38)) $script:C.Ink 8 ([System.Drawing.Color]::FromArgb(42, 40, 56))
    $rb.Add_Click({ Invoke-Ritual $ritCopy })
    $tip = if ($rit.Tagline) { "$($rit.Title)`n$($rit.Tagline) - $($rit.Genre)" } else { $rit.Hint }
    $script:uiToolTip.SetToolTip($rb, $tip)
    $pnlRituals.Controls.Add($rb)
    $script:RitualBtns += $rb
}

$script:lblTonightCards = New-Object System.Windows.Forms.Label
Set-SectionLabelStyle $script:lblTonightCards 'Tonight picks'
$script:lblTonightCards.Location = New-Object System.Drawing.Point(8, 82)
$script:lblTonightCards.Size = New-Object System.Drawing.Size(120, 14)
$script:lblTonightCards.Visible = $script:UseSteamUi
$pnlSchedule.Controls.Add($script:lblTonightCards)

$script:pnlTonightCards = New-Object System.Windows.Forms.FlowLayoutPanel
$script:pnlTonightCards.Location = New-Object System.Drawing.Point(8, 98)
$script:pnlTonightCards.Size = New-Object System.Drawing.Size(($script:contentW - 16), 158)
$script:pnlTonightCards.BackColor = Get-UiColor 'Elevated' ([System.Drawing.Color]::FromArgb(42, 71, 94))
$script:pnlTonightCards.Visible = $script:UseSteamUi
$script:pnlTonightCards.WrapContents = $true
$pnlSchedule.Controls.Add($script:pnlTonightCards)
Apply-SteamSurfaceStyle $script:pnlTonightCards 'Mint'

$script:TonightCardBtns = @()
if (Get-Command Get-TonightCardCatalog -ErrorAction SilentlyContinue) {
    foreach ($tc in (Get-TonightCardCatalog)) {
        $tb = New-Object System.Windows.Forms.Button
        $tb.Tag = $tc
        $tb.Text = Get-TonightCardTileText -Card $tc
        $tb.Size = New-Object System.Drawing.Size(136, 74)
        $tb.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 6)
        $tb.TextAlign = 'TopLeft'
        $tb.Font = New-Object System.Drawing.Font('Segoe UI', 8.25, [System.Drawing.FontStyle]::Bold)
        $tb.Padding = New-Object System.Windows.Forms.Padding(10, 8, 8, 6)
        $tb.UseCompatibleTextRendering = $true
        $cardCopy = $tc
        $tb.Add_Click({ Select-TonightCard $cardCopy.Id }.GetNewClosure())
        if ($script:uiToolTip -and (Get-Command Get-TonightCardToolTip -ErrorAction SilentlyContinue)) {
            $script:uiToolTip.SetToolTip($tb, (Get-TonightCardToolTip -Card $tc -LastLightSequence $script:LastLightSequence))
        }
        $script:pnlTonightCards.Controls.Add($tb)
        $script:TonightCardBtns += $tb
    }
}
if ($script:UseSteamUi) {
    $lblRitual.Visible = $false
    $pnlRituals.Visible = $false
}

$script:LobbyQuickBtns = @()
$script:numLobbyMin = New-Object System.Windows.Forms.NumericUpDown
$script:numLobbyMin.Minimum = 1
$script:numLobbyMin.Maximum = 480
$script:numLobbyMin.Width = 56
$script:numLobbyMin.Height = 28
$script:numLobbyMin.Value = [math]::Min(480, [math]::Max(1, [math]::Round($script:DefaultSec / 60.0)))
$script:numLobbyMin.Add_ValueChanged({
    if ($script:numLobbyMin.IsDisposed) { return }
    if (-not $script:UiReady -or $script:ApplyingLobbyMin) { return }
    Set-TimerMinutes ([int]$script:numLobbyMin.Value)
})
$script:ApplyingLobbyMin = $false

if ($script:UseSteamUi) {
    $script:pnlLobbyTimer = New-Object System.Windows.Forms.FlowLayoutPanel
    $script:pnlLobbyTimer.Location = New-Object System.Drawing.Point(8, 260)
    $script:pnlLobbyTimer.Size = New-Object System.Drawing.Size(($script:contentW - 16), 34)
    $script:pnlLobbyTimer.BackColor = Get-UiColor 'Elevated' ([System.Drawing.Color]::FromArgb(42, 71, 94))
    $script:pnlLobbyTimer.Visible = $false
    $pnlSchedule.Controls.Add($script:pnlLobbyTimer)
    Apply-SteamSurfaceStyle $script:pnlLobbyTimer 'Violet'

    $lblLobbyMin = New-Object System.Windows.Forms.Label
    $lblLobbyMin.Text = 'Timer:'
    $lblLobbyMin.AutoSize = $true
    $lblLobbyMin.Margin = New-Object System.Windows.Forms.Padding(0, 6, 8, 0)
    $lblLobbyMin.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
    $lblLobbyMin.BackColor = Get-UiColor 'Elevated' ([System.Drawing.Color]::FromArgb(42, 71, 94))
    $lblLobbyMin.Font = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Bold)
    $script:pnlLobbyTimer.Controls.Add($lblLobbyMin)

    $script:numLobbyMin.Margin = New-Object System.Windows.Forms.Padding(0, 2, 8, 0)
    $script:pnlLobbyTimer.Controls.Add($script:numLobbyMin)

    $lblLobbyMinUnit = New-Object System.Windows.Forms.Label
    $lblLobbyMinUnit.Text = 'min'
    $lblLobbyMinUnit.AutoSize = $true
    $lblLobbyMinUnit.Margin = New-Object System.Windows.Forms.Padding(0, 6, 10, 0)
    $lblLobbyMinUnit.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
    $lblLobbyMinUnit.BackColor = Get-UiColor 'Elevated' ([System.Drawing.Color]::FromArgb(42, 71, 94))
    $lblLobbyMinUnit.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
    $script:pnlLobbyTimer.Controls.Add($lblLobbyMinUnit)

    foreach ($quickMin in @(10, 15, 23, 24, 30, 45, 60)) {
        $qb = New-Object System.Windows.Forms.Button
        $qb.Text = "${quickMin}m"
        $qb.Tag = $quickMin
        $qb.Size = New-Object System.Drawing.Size(36, 28)
        $qb.Margin = New-Object System.Windows.Forms.Padding(0, 0, 4, 0)
        $qm = $quickMin
        Style-Button $qb ([System.Drawing.Color]::FromArgb(30, 30, 42)) (Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))) 8 ([System.Drawing.Color]::FromArgb(44, 44, 58))
        $qb.Add_Click({ Set-TimerMinutes $qm }.GetNewClosure())
        $script:pnlLobbyTimer.Controls.Add($qb)
        $script:LobbyQuickBtns += $qb
    }
} else {
    $lobbyBg = Get-UiColor 'Bg' ([System.Drawing.Color]::FromArgb(27, 40, 56))
    $script:pnlLobbyTimer = New-Object System.Windows.Forms.Panel
    $script:pnlLobbyTimer.Location = New-Object System.Drawing.Point(24, (304 + $script:yBoost))
    $script:pnlLobbyTimer.Size = New-Object System.Drawing.Size(($script:contentW - 8), 86)
    $script:pnlLobbyTimer.BackColor = $lobbyBg
    $script:pnlLobbyTimer.Visible = ($script:TimerMode -eq 'duration')

    $lblLobbyHead = New-Object System.Windows.Forms.Label
    $lblLobbyHead.Text = 'Timer amount'
    $lblLobbyHead.Location = New-Object System.Drawing.Point(0, 0)
    $lblLobbyHead.Size = New-Object System.Drawing.Size(160, 18)
    $lblLobbyHead.ForeColor = Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
    $lblLobbyHead.BackColor = $lobbyBg
    $lblLobbyHead.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $script:pnlLobbyTimer.Controls.Add($lblLobbyHead)

    $script:btnLobbyMinDown = New-Object System.Windows.Forms.Button
    $script:btnLobbyMinDown.Text = '-'
    $script:btnLobbyMinDown.Location = New-Object System.Drawing.Point(0, 22)
    $script:btnLobbyMinDown.Size = New-Object System.Drawing.Size(32, 28)
    Style-Button $script:btnLobbyMinDown ([System.Drawing.Color]::FromArgb(36, 36, 50)) (Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))) 8 ([System.Drawing.Color]::FromArgb(48, 48, 64))
    $script:btnLobbyMinDown.Add_Click({
        Set-TimerMinutes ([math]::Max(1, [int]$script:numLobbyMin.Value - 1))
    })
    $script:pnlLobbyTimer.Controls.Add($script:btnLobbyMinDown)

    $script:numLobbyMin.Location = New-Object System.Drawing.Point(36, 20)
    $script:pnlLobbyTimer.Controls.Add($script:numLobbyMin)

    $lblLobbyMinUnit = New-Object System.Windows.Forms.Label
    $lblLobbyMinUnit.Text = 'minutes'
    $lblLobbyMinUnit.Location = New-Object System.Drawing.Point(98, 26)
    $lblLobbyMinUnit.AutoSize = $true
    $lblLobbyMinUnit.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
    $lblLobbyMinUnit.BackColor = $lobbyBg
    $lblLobbyMinUnit.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $script:pnlLobbyTimer.Controls.Add($lblLobbyMinUnit)

    $script:btnLobbyMinUp = New-Object System.Windows.Forms.Button
    $script:btnLobbyMinUp.Text = '+'
    $script:btnLobbyMinUp.Location = New-Object System.Drawing.Point(168, 22)
    $script:btnLobbyMinUp.Size = New-Object System.Drawing.Size(32, 28)
    Style-Button $script:btnLobbyMinUp ([System.Drawing.Color]::FromArgb(36, 36, 50)) (Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))) 8 ([System.Drawing.Color]::FromArgb(48, 48, 64))
    $script:btnLobbyMinUp.Add_Click({
        Set-TimerMinutes ([math]::Min(480, [int]$script:numLobbyMin.Value + 1))
    })
    $script:pnlLobbyTimer.Controls.Add($script:btnLobbyMinUp)

    $script:pnlLobbyChips = New-Object System.Windows.Forms.FlowLayoutPanel
    $script:pnlLobbyChips.Location = New-Object System.Drawing.Point(0, 54)
    $script:pnlLobbyChips.Size = New-Object System.Drawing.Size(($script:contentW - 8), 30)
    $script:pnlLobbyChips.BackColor = $lobbyBg
    $script:pnlLobbyChips.WrapContents = $false
    $script:pnlLobbyTimer.Controls.Add($script:pnlLobbyChips)

    foreach ($quickMin in @(10, 15, 23, 24, 30, 45, 60)) {
        $qb = New-Object System.Windows.Forms.Button
        $qb.Text = "${quickMin}m"
        $qb.Tag = $quickMin
        $qb.Size = New-Object System.Drawing.Size(40, 26)
        $qb.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
        $qm = $quickMin
        Style-Button $qb ([System.Drawing.Color]::FromArgb(30, 30, 42)) (Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))) 8 ([System.Drawing.Color]::FromArgb(44, 44, 58))
        $qb.Add_Click({ Set-TimerMinutes $qm }.GetNewClosure())
        $script:pnlLobbyChips.Controls.Add($qb)
        $script:LobbyQuickBtns += $qb
    }
    Add-MainControl($script:pnlLobbyTimer)
    Apply-ClassicSimpleLayout
}
$script:uiToolTip.SetToolTip($script:numLobbyMin, 'Countdown length in minutes')

# Saved named timers
$script:lblMyTimers = New-Object System.Windows.Forms.Label
Set-SectionLabelStyle $script:lblMyTimers $(if ($script:UseSteamUi) { 'Saved runs' } else { 'My timers' })
$script:lblMyTimers.Location = New-Object System.Drawing.Point(8, 136)
$script:lblMyTimers.Size = New-Object System.Drawing.Size(80, 14)
$script:lblMyTimers.Visible = $false
$pnlSchedule.Controls.Add($script:lblMyTimers)

$script:btnSaveProfile = New-Object System.Windows.Forms.Button
$script:btnSaveProfile.Text = '+ Save'
$script:btnSaveProfile.Size = New-Object System.Drawing.Size(58, 24)
$script:btnSaveProfile.Location = New-Object System.Drawing.Point(($script:contentW - 66), 80)
Style-Button $script:btnSaveProfile $script:C.Card $script:C.Mint 8
$script:btnSaveProfile.Add_Click({ Show-SaveTimerProfileDialog })
$script:uiToolTip.SetToolTip($script:btnSaveProfile, 'Save current action, duration, and schedule as a preset')
$pnlSchedule.Controls.Add($script:btnSaveProfile)

$script:btnEditProfiles = New-Object System.Windows.Forms.Button
$script:btnEditProfiles.Text = 'Edit'
$script:btnEditProfiles.Size = New-Object System.Drawing.Size(48, 24)
$script:btnEditProfiles.Location = New-Object System.Drawing.Point(342, 132)
$script:btnEditProfiles.Visible = $false
Style-Button $script:btnEditProfiles $script:C.Card $script:C.Muted 8
$script:btnEditProfiles.Add_Click({ Show-ManageTimerProfilesDialog })
$pnlSchedule.Controls.Add($script:btnEditProfiles)

$script:pnlMyTimers = New-Object System.Windows.Forms.FlowLayoutPanel
$script:pnlMyTimers.Location = New-Object System.Drawing.Point(8, 154)
$script:pnlMyTimers.Size = New-Object System.Drawing.Size(($script:contentW - 16), 36)
$script:pnlMyTimers.BackColor = Get-UiColor 'Elevated' ([System.Drawing.Color]::FromArgb(42, 71, 94))
$pnlSchedule.Controls.Add($script:pnlMyTimers)
Apply-SteamSurfaceStyle $script:pnlMyTimers 'Mint'
$script:MyTimerBtns = @()

# Duration presets
$pnlPresets = New-Object System.Windows.Forms.FlowLayoutPanel
$pnlPresets.Location = New-Object System.Drawing.Point(8, 42)
$pnlPresets.Size = New-Object System.Drawing.Size(($script:contentW - 16), 34)
$pnlPresets.BackColor = Get-UiColor 'Elevated' ([System.Drawing.Color]::FromArgb(42, 71, 94))
$pnlPresets.Visible = $false
$pnlSchedule.Controls.Add($pnlPresets)
Apply-SteamSurfaceStyle $pnlPresets 'Amber'

$script:PresetBtns = @()
foreach ($preset in @(
    @{ L = '24m'; S = 1440 }
    @{ L = '28:20'; S = 1700 }
    @{ L = '30m'; S = 1800 }
    @{ L = '45m'; S = 2700 }
)) {
    $pb = New-Object System.Windows.Forms.Button
    $pb.Text = $preset.L
    $pb.Tag = $preset.S
    $pb.Size = New-Object System.Drawing.Size(58, 28)
    $pb.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
    $sec = $preset.S
    Style-Button $pb ([System.Drawing.Color]::FromArgb(30, 30, 42)) $script:C.Muted 8 ([System.Drawing.Color]::FromArgb(44, 44, 58))
    $pb.Add_Click({
        Set-TimerMinutes ([math]::Max(1, [math]::Round($sec / 60.0)))
    }.GetNewClosure())
    $pnlPresets.Controls.Add($pb)
    $script:PresetBtns += $pb
}

# Clock / calendar schedule row
$pnlClock = New-Object System.Windows.Forms.FlowLayoutPanel
$pnlClock.Location = New-Object System.Drawing.Point(8, 42)
$pnlClock.Size = New-Object System.Drawing.Size(($script:contentW - 16), 34)
$pnlClock.BackColor = Get-UiColor 'Elevated' ([System.Drawing.Color]::FromArgb(42, 71, 94))
$pnlClock.Visible = $false
$pnlSchedule.Controls.Add($pnlClock)
Apply-SteamSurfaceStyle $pnlClock 'Blue'

$script:dtpDate = New-Object System.Windows.Forms.DateTimePicker
$script:dtpDate.Format = [System.Windows.Forms.DateTimePickerFormat]::Short
$script:dtpDate.Width = 108
$script:dtpDate.Height = 28
$script:dtpDate.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
$script:dtpDate.Visible = $false
if ($script:ScheduledAt) { $script:dtpDate.Value = [DateTime]$script:ScheduledAt }
$script:dtpDate.Add_ValueChanged({ Sync-ScheduledFromPickers; if (-not $script:Running) { Save-Settings }; Update-Ui })
$pnlClock.Controls.Add($script:dtpDate)

$script:dtpClock = New-Object System.Windows.Forms.DateTimePicker
$script:dtpClock.Format = [System.Windows.Forms.DateTimePickerFormat]::Time
$script:dtpClock.ShowUpDown = $true
$script:dtpClock.Width = 110
$script:dtpClock.Height = 28
$script:dtpClock.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
try {
    $ctParts = $script:ClockTime.Split(':')
    $script:dtpClock.Value = Get-Date -Hour ([int]$ctParts[0]) -Minute ([int]$ctParts[1]) -Second 0
} catch {
    $script:dtpClock.Value = Get-Date -Hour 23 -Minute 30 -Second 0
}
$script:dtpClock.Add_ValueChanged({
    if (-not $script:UiReady) { return }
    $script:ClockTime = $script:dtpClock.Value.ToString('HH:mm')
    if ($script:TimerMode -eq 'calendar') { Sync-ScheduledFromPickers }
    if (-not $script:Running) { Save-Settings; Update-Ui }
})
$pnlClock.Controls.Add($script:dtpClock)

$script:btnCalImport = New-Object System.Windows.Forms.Button
$script:btnCalImport.Text = 'Import .ics'
$script:btnCalImport.Size = New-Object System.Drawing.Size(88, 28)
$script:btnCalImport.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
$script:btnCalImport.Visible = $false
Style-Button $script:btnCalImport ([System.Drawing.Color]::FromArgb(30, 30, 42)) $script:C.Ink 8
$script:btnCalImport.Add_Click({ Show-CalendarEventDialog | Out-Null })
$pnlClock.Controls.Add($script:btnCalImport)

$script:btnCalFeed = New-Object System.Windows.Forms.Button
$script:btnCalFeed.Text = 'Live feed'
$script:btnCalFeed.Size = New-Object System.Drawing.Size(72, 28)
$script:btnCalFeed.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
$script:btnCalFeed.Visible = $false
Style-Button $script:btnCalFeed ([System.Drawing.Color]::FromArgb(28, 32, 40)) $script:C.Mint 8
$script:btnCalFeed.Add_Click({ Show-CalendarFeedDialog })
$pnlClock.Controls.Add($script:btnCalFeed)

$script:lblCalEvent = New-Object System.Windows.Forms.Label
$script:lblCalEvent.Size = New-Object System.Drawing.Size(388, 18)
$script:lblCalEvent.Location = New-Object System.Drawing.Point(24, ($(if ($script:UseSteamUi) { 580 } else { 530 }) + $script:yBoost))
$script:lblCalEvent.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
$script:lblCalEvent.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
$script:lblCalEvent.BackColor = Get-UiColor 'Bg' ([System.Drawing.Color]::FromArgb(27, 40, 56))
$script:lblCalEvent.Visible = $false
Add-MainControl($script:lblCalEvent)

$script:ClockPresetBtns = @()
foreach ($cp in @(
    @{ L = '10:30 PM'; T = '22:30' }
    @{ L = '11:00 PM'; T = '23:00' }
    @{ L = '11:30 PM'; T = '23:30' }
    @{ L = '12:00 AM'; T = '00:00' }
)) {
    $cb = New-Object System.Windows.Forms.Button
    $cb.Text = $cp.L
    $cb.Tag = $cp.T
    $cb.Size = New-Object System.Drawing.Size(58, 28)
    $cb.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
    $timeTag = $cp.T
    Style-Button $cb ([System.Drawing.Color]::FromArgb(30, 30, 42)) $script:C.Muted 8 ([System.Drawing.Color]::FromArgb(44, 44, 58))
    $cb.Add_Click({
        $parts = $timeTag.Split(':')
        $script:dtpClock.Value = Get-Date -Hour ([int]$parts[0]) -Minute ([int]$parts[1]) -Second 0
        $script:ClockTime = $timeTag
        if (-not $script:Running) { Save-Settings; Update-Ui }
    }.GetNewClosure())
    $pnlClock.Controls.Add($cb)
    $script:ClockPresetBtns += $cb
}

# Card
$script:pnlCard = New-Object System.Windows.Forms.Panel
$script:pnlCard.Location = New-Object System.Drawing.Point(20, ($(if ($script:UseSteamUi) { 600 } else { 550 }) + $script:yBoost + $script:yNovel))
$pnlCard = $script:pnlCard
$script:pnlCardAdvHeight = 0
$pnlCard.Size = New-Object System.Drawing.Size($script:contentW, (50 + $script:pnlCardAdvHeight))
$pnlCard.BackColor = Get-UiColor 'Card' ([System.Drawing.Color]::FromArgb(22, 32, 45))
$pnlCard.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $w = $s.Width; $h = $s.Height
    $border = Get-UiColor 'Border' ([System.Drawing.Color]::FromArgb(42, 71, 94))
    $pen = New-Object System.Drawing.Pen $border
    $g.DrawRectangle($pen, 0, 0, ($w - 1), ($h - 1))
    $pen.Dispose()
    $accent = Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(118, 201, 255))
    $topPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(100, $accent.R, $accent.G, $accent.B)), 1
    $g.DrawLine($topPen, 0, 0, $w, 0)
    $topPen.Dispose()
})
Add-MainControl($pnlCard)
Apply-SteamSurfaceStyle $pnlCard 'Section'

$script:Pills = @()
foreach ($a in @('Shutdown', 'Sleep', 'Restart', 'Hibernate', 'Lock')) {
    $i = $script:Pills.Count
    $p = New-Object System.Windows.Forms.Button
    $p.Text = $a
    $p.Tag = $a
    $pw = [int](($script:contentW - 20) / 5)
    $p.Size = New-Object System.Drawing.Size([math]::Max(70, $pw - 4), 32)
    $p.Location = New-Object System.Drawing.Point((8 + $i * $pw), 8)
    Style-Button $p ([System.Drawing.Color]::FromArgb(32, 32, 44)) $script:C.Muted 9
    $p.Add_Click({ Set-Action $this.Tag })
    $pnlCard.Controls.Add($p)
    $script:Pills += $p
}

$script:pnlCardAdv = New-Object System.Windows.Forms.Panel
$script:pnlCardAdv.Location = New-Object System.Drawing.Point(0, 46)
$script:pnlCardAdv.Size = New-Object System.Drawing.Size($script:contentW, 200)
$script:pnlCardAdv.BackColor = Get-UiColor 'Card' ([System.Drawing.Color]::FromArgb(22, 32, 45))
$script:pnlCardAdv.Visible = $false
$script:pnlCardAdv.AutoScroll = $true
$pnlCard.Controls.Add($script:pnlCardAdv)
Apply-SteamSurfaceStyle $script:pnlCardAdv 'Violet'

function New-OptionsSectionLabel {
    param([string]$Text, [int]$Y)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Text.ToUpper()
    $lbl.Location = New-Object System.Drawing.Point(10, $Y)
    $lbl.Size = New-Object System.Drawing.Size(($script:contentW - 20), 20)
    $lbl.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 7.5, [System.Drawing.FontStyle]::Bold)
    $lbl.ForeColor = Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))
    $lbl.BackColor = [System.Drawing.Color]::Transparent
    $script:pnlCardAdv.Controls.Add($lbl)
}

function New-OptionsDivider {
    param([int]$Y)
    $d = New-Object System.Windows.Forms.Panel
    $d.Location = New-Object System.Drawing.Point(10, $Y)
    $d.Size = New-Object System.Drawing.Size(($script:contentW - 20), 2)
    $d.BackColor = [System.Drawing.Color]::Transparent
    Enable-DoubleBuffer $d
    $d.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $accent = Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(118, 201, 255))
        $pen1 = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(16, $accent.R, $accent.G, $accent.B)), 1
        $g.DrawLine($pen1, 0, 0, $s.Width, 0)
        $pen1.Dispose()
        $pen2 = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(48, 58, 72)), 1
        $g.DrawLine($pen2, 0, 1, $s.Width, 1)
        $pen2.Dispose()
    })
    $script:pnlCardAdv.Controls.Add($d)
}

$script:lnkCardOpts = New-Object System.Windows.Forms.LinkLabel
$script:lnkCardOpts.Text = ([char]0x2699) + ' Options'
$script:lnkCardOpts.AutoSize = $true
$script:lnkCardOpts.Location = New-Object System.Drawing.Point(($script:contentW - 80), 14)
$script:lnkCardOpts.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8)
$script:lnkCardOpts.LinkColor = Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))
$script:lnkCardOpts.ActiveLinkColor = [System.Drawing.Color]::FromArgb(160, 220, 255)
$script:lnkCardOpts.BackColor = [System.Drawing.Color]::Transparent
$script:lnkCardOpts.Visible = $true
$script:lnkCardOpts.Add_Click({
    $script:CardOptsExpanded = -not $script:CardOptsExpanded
    Update-CardOptionsPanel
})
$pnlCard.Controls.Add($script:lnkCardOpts)
$script:CardOptsExpanded = $false

function Update-CardOptionsPanel {
    if (-not $script:pnlCardAdv) { return }
    $open = $script:CardOptsExpanded
    $script:pnlCardAdv.Visible = $open
    $script:lnkCardOpts.Text = if ($open) { ([char]0x2699) + ' Hide' } else { ([char]0x2699) + ' Options' }
    $advH = if ($open) { if ($script:UseSteamUi) { 510 } else { 210 } } else { 0 }
    $script:pnlCardAdv.Height = $advH
    $pnlCard.Height = 50 + $advH
}

function New-Chk {
    param($Text, $X, $Y, $Checked)
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text = $Text
    $c.Location = New-Object System.Drawing.Point($X, $Y)
    $c.AutoSize = $true
    $c.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
    $c.BackColor = Get-UiColor 'Card' ([System.Drawing.Color]::FromArgb(22, 32, 45))
    $c.Checked = $Checked
    $c.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
    $script:pnlCardAdv.Controls.Add($c)
    return $c
}

# ── GENERAL section ──
New-OptionsSectionLabel ([char]0x2699 + '  GENERAL') 4

$chkTop = New-Chk 'Always on top' 10 24 $cfg.TopMost
$chkTop.Add_CheckedChanged({ $form.TopMost = $chkTop.Checked })
$chkLogin = New-Chk 'Run at login (idle)' 210 24 $(if ($cfg.RunAtLogin) { $true } else { Test-RunAtLogin })
$script:uiToolTip.SetToolTip($chkLogin, 'Starts minimized and idle at Windows sign-in; it does not start a countdown.')
$chkLogin.Add_CheckedChanged({ if (-not $script:Running) { Save-Settings } })

$chkAutoOpen = New-Chk $(if ($script:UseSteamUi) { 'Auto-play on open' } else { 'Start on open' }) 10 48 $script:AutoStartOnOpen
$script:uiToolTip.SetToolTip($chkAutoOpen, 'Starts a countdown when you manually open Lights Out. Login startup stays idle.')
$chkAutoOpen.Add_CheckedChanged({
    $script:AutoStartOnOpen = $chkAutoOpen.Checked
    if (-not $script:Running) { Save-Settings }
})
$chkMinTray = New-Chk 'Tray on minimize' 210 48 $cfg.MinimizeToTray

# ── DISPLAY section ──
New-OptionsDivider 74
New-OptionsSectionLabel ([char]0x25A3 + '  DISPLAY') 78

$script:BigPictureOnStart = [bool]$cfg.BigPictureOnStart
$script:LastAchievementStreak = [int]$cfg.LastAchievementStreak
$script:chkBigPicture = New-Chk 'Cinema on start' 10 98 $script:BigPictureOnStart
$script:chkBigPicture.Add_CheckedChanged({
    $script:BigPictureOnStart = $script:chkBigPicture.Checked
    if (-not $script:Running) { Save-Settings }
})

$script:cboCinemaScreen = New-Object System.Windows.Forms.ComboBox
$script:cboCinemaScreen.Location = New-Object System.Drawing.Point(210, 98)
$script:cboCinemaScreen.Size = New-Object System.Drawing.Size(92, 24)
$script:cboCinemaScreen.DropDownStyle = 'DropDownList'
$script:cboCinemaScreen.BackColor = [System.Drawing.Color]::FromArgb(32, 32, 44)
$script:cboCinemaScreen.ForeColor = Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
$script:cboCinemaScreen.Font = New-Object System.Drawing.Font('Segoe UI', 7.5)
$cinemaChoices = Get-CinemaScreenChoices
foreach ($ch in $cinemaChoices) { [void]$script:cboCinemaScreen.Items.Add($ch.Label) }
$selIdx = if ($script:CinemaScreenIndex -ge 0 -and $script:CinemaScreenIndex -lt $cinemaChoices.Count) { $script:CinemaScreenIndex } else { 0 }
if ($script:cboCinemaScreen.Items.Count -gt 0) { $script:cboCinemaScreen.SelectedIndex = $selIdx }
$script:cboCinemaScreen.Add_SelectedIndexChanged({
    $script:CinemaScreenIndex = $script:cboCinemaScreen.SelectedIndex
    if (-not $script:Running) { Save-Settings }
})
$script:pnlCardAdv.Controls.Add($script:cboCinemaScreen)

$script:lblClockFace = New-Object System.Windows.Forms.Label
$script:lblClockFace.Text = 'Clock face'
$script:lblClockFace.Location = New-Object System.Drawing.Point(10, 124)
$script:lblClockFace.AutoSize = $true
$script:lblClockFace.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
$script:lblClockFace.BackColor = Get-UiColor 'Card' ([System.Drawing.Color]::FromArgb(22, 32, 45))
$script:lblClockFace.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$script:pnlCardAdv.Controls.Add($script:lblClockFace)

$script:cboClockFace = New-Object System.Windows.Forms.ComboBox
$script:cboClockFace.Location = New-Object System.Drawing.Point(76, 122)
$script:cboClockFace.Size = New-Object System.Drawing.Size(128, 24)
$script:cboClockFace.DropDownStyle = 'DropDownList'
$script:cboClockFace.BackColor = [System.Drawing.Color]::FromArgb(32, 32, 44)
$script:cboClockFace.ForeColor = Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
$script:cboClockFace.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$clockFaceStyles = Get-ClockFaceStyles
foreach ($cfs in $clockFaceStyles) { [void]$script:cboClockFace.Items.Add($cfs) }
$script:cboClockFace.DisplayMember = 'Name'
$cfsPick = $clockFaceStyles | Where-Object { $_.Id -eq $script:ClockFaceStyle } | Select-Object -First 1
if ($cfsPick) { $script:cboClockFace.SelectedItem = $cfsPick }
elseif ($script:cboClockFace.Items.Count -gt 0) { $script:cboClockFace.SelectedIndex = 0 }
$script:cboClockFace.Add_SelectedIndexChanged({
    if ($script:cboClockFace.SelectedItem) {
        $script:ClockFaceStyle = [string]$script:cboClockFace.SelectedItem.Id
        if ($pnlRing) { $pnlRing.Invalidate() }
        if ($script:bpRing) { $script:bpRing.Invalidate() }
        if (-not $script:Running) { Save-Settings }
    }
})
$script:pnlCardAdv.Controls.Add($script:cboClockFace)

# ── BEHAVIOR section ──
New-OptionsDivider 150
New-OptionsSectionLabel ([char]0x26A1 + '  BEHAVIOR') 154

$chkWarn5 = New-Chk '5 min warn' 10 174 $cfg.Warn5Min
$chkQuick = New-Chk 'Quick choices' 210 174 $cfg.QuickWarnPanel
$chkQuick.Add_CheckedChanged({
    $script:QuickWarnPanel = $chkQuick.Checked
    if (-not $script:Running) { Save-Settings }
})
$script:QuickWarnPanel = $cfg.QuickWarnPanel

$script:chkQuietHours = New-Chk 'Quiet Hours auto-start' 10 198 $script:QuietHoursAutoStart
$script:chkQuietHours.Add_CheckedChanged({
    $script:QuietHoursAutoStart = $script:chkQuietHours.Checked
    if ($script:chkQuietHours.Checked -and $script:quietHoursTimer) { $script:quietHoursTimer.Start() }
    elseif ($script:quietHoursTimer) { $script:quietHoursTimer.Stop() }
    if (-not $script:Running) { Save-Settings }
})

$chkLuxGrid = New-Chk 'LuxGrid RGB' 10 222 $cfg.EmitLuxGridEvents
$chkLuxGrid.Add_CheckedChanged({ if (-not $script:Running) { Save-Settings } })

$chkGraceful = New-Chk 'Graceful exit' 210 222 $cfg.GracefulShutdown
$chkGraceful.Add_CheckedChanged({ if (-not $script:Running) { Save-Settings } })

$script:chkPowerWarn = New-Chk 'Blocker warn' 10 246 $cfg.WarnPowerBlockers
$script:chkPowerWarn.Add_CheckedChanged({ if (-not $script:Running) { Save-Settings } })

$script:chkDimPhase = New-Chk 'Dim phase (90s)' 210 246 $cfg.DimPhaseEnabled
$script:chkDimPhase.Add_CheckedChanged({ if (-not $script:Running) { Save-Settings } })

$script:chkPact = New-Chk 'Bedtime pact' 10 270 $cfg.PactEnabled
$script:chkPact.Add_CheckedChanged({
    if ($script:dtpPact) { $script:dtpPact.Visible = $script:chkPact.Checked }
    if (-not $script:Running) { Save-Settings }
})

$script:dtpPact = New-Object System.Windows.Forms.DateTimePicker
$script:dtpPact.Format = [System.Windows.Forms.DateTimePickerFormat]::Time
$script:dtpPact.ShowUpDown = $true
$script:dtpPact.Width = 90
$script:dtpPact.Height = 22
$script:dtpPact.Location = New-Object System.Drawing.Point(108, 268)
$ptParts = $cfg.PactTime.Split(':')
$script:dtpPact.Value = Get-Date -Hour ([int]$ptParts[0]) -Minute ([int]$ptParts[1]) -Second 0
$script:dtpPact.Visible = $cfg.PactEnabled
$script:dtpPact.Add_ValueChanged({ if (-not $script:Running) { Save-Settings } })
$script:pnlCardAdv.Controls.Add($script:dtpPact)

$btnHousehold = New-Object System.Windows.Forms.Button
$btnHousehold.Text = 'Household sync'
$btnHousehold.Size = New-Object System.Drawing.Size(110, 24)
$btnHousehold.Location = New-Object System.Drawing.Point(($script:contentW - 122), 268)
Style-Button $btnHousehold ([System.Drawing.Color]::FromArgb(28, 32, 44)) $script:C.Mint 8
$btnHousehold.Add_Click({ Show-HouseholdHarmonyDialog })
$script:pnlCardAdv.Controls.Add($btnHousehold)

# ── FINALE section ──
New-OptionsDivider 296
New-OptionsSectionLabel ([char]0x263E + '  FINALE') 300

$script:chkLastLight = New-Chk 'Last Light finale' 10 320 $script:LastLightEnabled
$script:chkLastLight.Add_CheckedChanged({
    $script:LastLightEnabled = $script:chkLastLight.Checked
    if ($script:cboLastLight) { $script:cboLastLight.Enabled = $script:LastLightEnabled }
    if ($script:cboLastLightSound) { $script:cboLastLightSound.Enabled = $script:LastLightEnabled }
    if (-not $script:Running) { Save-Settings }
})

$script:chkLastLightCinema = New-Chk 'Cinema finale' 210 320 $script:LastLightUseCinema
$script:chkLastLightCinema.Add_CheckedChanged({
    $script:LastLightUseCinema = $script:chkLastLightCinema.Checked
    if (-not $script:Running) { Save-Settings }
})

$lblLastLightSeq = New-Object System.Windows.Forms.Label
$lblLastLightSeq.Text = 'Sequence'
$lblLastLightSeq.Location = New-Object System.Drawing.Point(10, 346)
$lblLastLightSeq.AutoSize = $true
$lblLastLightSeq.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
$lblLastLightSeq.BackColor = Get-UiColor 'Card' ([System.Drawing.Color]::FromArgb(22, 32, 45))
$lblLastLightSeq.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
$script:pnlCardAdv.Controls.Add($lblLastLightSeq)

$script:cboLastLight = New-Object System.Windows.Forms.ComboBox
$script:cboLastLight.Location = New-Object System.Drawing.Point(72, 344)
$script:cboLastLight.Size = New-Object System.Drawing.Size(220, 24)
$script:cboLastLight.DropDownStyle = 'DropDownList'
$script:cboLastLight.BackColor = [System.Drawing.Color]::FromArgb(32, 32, 44)
$script:cboLastLight.ForeColor = Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
$script:cboLastLight.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
if (Get-Command Get-LastLightSequenceCatalog -ErrorAction SilentlyContinue) {
    foreach ($entry in (Get-LastLightSequenceCatalog)) {
        [void]$script:cboLastLight.Items.Add($entry)
    }
    $script:cboLastLight.DisplayMember = 'Name'
    $pick = Get-LastLightSequenceCatalog | Where-Object { $_.Id -eq $script:LastLightSequence } | Select-Object -First 1
    if ($pick) { $script:cboLastLight.SelectedItem = $pick }
    elseif ($script:cboLastLight.Items.Count -gt 0) { $script:cboLastLight.SelectedIndex = 0 }
}
$script:cboLastLight.Enabled = $script:LastLightEnabled
if ($script:cboLastLightSound) { $script:cboLastLightSound.Enabled = $script:LastLightEnabled }
$script:cboLastLight.Add_SelectedIndexChanged({
    if ($script:cboLastLight.SelectedItem) {
        $script:LastLightSequence = [string]$script:cboLastLight.SelectedItem.Id
        Mark-TonightCardCustom
        if (-not $script:Running) { Save-Settings }
    }
})
$script:pnlCardAdv.Controls.Add($script:cboLastLight)

$lblLastLightSound = New-Object System.Windows.Forms.Label
$lblLastLightSound.Text = 'Sound'
$lblLastLightSound.Location = New-Object System.Drawing.Point(10, 372)
$lblLastLightSound.AutoSize = $true
$lblLastLightSound.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
$lblLastLightSound.BackColor = Get-UiColor 'Card' ([System.Drawing.Color]::FromArgb(22, 32, 45))
$lblLastLightSound.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
$script:pnlCardAdv.Controls.Add($lblLastLightSound)

$script:cboLastLightSound = New-Object System.Windows.Forms.ComboBox
$script:cboLastLightSound.Location = New-Object System.Drawing.Point(72, 370)
$script:cboLastLightSound.Size = New-Object System.Drawing.Size(220, 24)
$script:cboLastLightSound.DropDownStyle = 'DropDownList'
$script:cboLastLightSound.BackColor = [System.Drawing.Color]::FromArgb(32, 32, 44)
$script:cboLastLightSound.ForeColor = Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
$script:cboLastLightSound.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
if (Get-Command Get-LastLightSoundCatalog -ErrorAction SilentlyContinue) {
    foreach ($entry in (Get-LastLightSoundCatalog)) {
        [void]$script:cboLastLightSound.Items.Add($entry)
    }
    $script:cboLastLightSound.DisplayMember = 'Name'
    $soundPick = Get-LastLightSoundCatalog | Where-Object { $_.Id -eq $script:LastLightSound } | Select-Object -First 1
    if ($soundPick) { $script:cboLastLightSound.SelectedItem = $soundPick }
    elseif ($script:cboLastLightSound.Items.Count -gt 0) { $script:cboLastLightSound.SelectedIndex = 0 }
}
$script:cboLastLightSound.Add_SelectedIndexChanged({
    if ($script:cboLastLightSound.SelectedItem) {
        $pickId = [string]$script:cboLastLightSound.SelectedItem.Id
        if ($pickId -in @('Off', 'Soft')) {
            $script:LastLightSound = Normalize-LastLightSoundId $pickId
            if (-not $script:Running) { Save-Settings }
        } elseif ($pickId -eq 'Cyber') {
            [System.Windows.Forms.MessageBox]::Show('Cyber sound pack is coming soon. Using Off for now.', 'Last Light Sound', 'OK', 'Information') | Out-Null
            $off = Get-LastLightSoundCatalog | Where-Object { $_.Id -eq 'Off' } | Select-Object -First 1
            if ($off) { $script:cboLastLightSound.SelectedItem = $off }
        }
    }
})
$script:pnlCardAdv.Controls.Add($script:cboLastLightSound)

# ── LIGHTS section ──
New-OptionsDivider 400
New-OptionsSectionLabel ([System.Char]::ConvertFromUtf32(0x1F4A1) + '  LIGHTS') 404

$script:chkSmartLight = New-Chk 'Smart Light control' 10 424 $script:SmartLightEnabled
$script:chkSmartLight.Add_CheckedChanged({
    $script:SmartLightEnabled = $script:chkSmartLight.Checked
    Save-SmartLightSettings
})

$lblLightProvider = New-Object System.Windows.Forms.Label
$lblLightProvider.Text = 'Provider'
$lblLightProvider.Location = New-Object System.Drawing.Point(10, 450)
$lblLightProvider.AutoSize = $true
$lblLightProvider.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
$lblLightProvider.BackColor = [System.Drawing.Color]::Transparent
$lblLightProvider.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
$script:pnlCardAdv.Controls.Add($lblLightProvider)

$script:cboLightProvider = New-Object System.Windows.Forms.ComboBox
$script:cboLightProvider.Location = New-Object System.Drawing.Point(72, 448)
$script:cboLightProvider.Size = New-Object System.Drawing.Size(140, 24)
$script:cboLightProvider.DropDownStyle = 'DropDownList'
$script:cboLightProvider.BackColor = [System.Drawing.Color]::FromArgb(32, 32, 44)
$script:cboLightProvider.ForeColor = Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
$script:cboLightProvider.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
[void]$script:cboLightProvider.Items.Add('None')
[void]$script:cboLightProvider.Items.Add('Philips Hue')
[void]$script:cboLightProvider.Items.Add('HTTP Webhook')
$provIdx = switch ($cfg.SmartLightProvider) {
    'hue' { 1 }
    'http' { 2 }
    default { 0 }
}
$script:cboLightProvider.SelectedIndex = $provIdx
$script:cboLightProvider.Add_SelectedIndexChanged({
    $script:SmartLightProvider = switch ($script:cboLightProvider.SelectedIndex) {
        1 { 'hue' }
        2 { 'http' }
        default { 'none' }
    }
    Update-SmartLightStatusLabel
    Save-SmartLightSettings
})
$script:pnlCardAdv.Controls.Add($script:cboLightProvider)

$lblLightMode = New-Object System.Windows.Forms.Label
$lblLightMode.Text = 'Mode'
$lblLightMode.Location = New-Object System.Drawing.Point(10, 476)
$lblLightMode.AutoSize = $true
$lblLightMode.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
$lblLightMode.BackColor = [System.Drawing.Color]::Transparent
$lblLightMode.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
$script:pnlCardAdv.Controls.Add($lblLightMode)

$script:cboLightMode = New-Object System.Windows.Forms.ComboBox
$script:cboLightMode.Location = New-Object System.Drawing.Point(72, 474)
$script:cboLightMode.Size = New-Object System.Drawing.Size(140, 24)
$script:cboLightMode.DropDownStyle = 'DropDownList'
$script:cboLightMode.BackColor = [System.Drawing.Color]::FromArgb(32, 32, 44)
$script:cboLightMode.ForeColor = Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
$script:cboLightMode.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
[void]$script:cboLightMode.Items.Add('Gradual dim')
[void]$script:cboLightMode.Items.Add('Warm shift + dim')
[void]$script:cboLightMode.Items.Add('Off at end only')
$modeIdx = switch ($cfg.SmartLightMode) {
    'warm_dim' { 1 }
    'off_at_end' { 2 }
    default { 0 }
}
$script:cboLightMode.SelectedIndex = $modeIdx
$script:cboLightMode.Add_SelectedIndexChanged({
    $script:SmartLightMode = switch ($script:cboLightMode.SelectedIndex) {
        1 { 'warm_dim' }
        2 { 'off_at_end' }
        default { 'gradual_dim' }
    }
    Save-SmartLightSettings
})
$script:pnlCardAdv.Controls.Add($script:cboLightMode)

$lblDimMin = New-Object System.Windows.Forms.Label
$lblDimMin.Text = 'Dim (min)'
$lblDimMin.Location = New-Object System.Drawing.Point(224, 450)
$lblDimMin.AutoSize = $true
$lblDimMin.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
$lblDimMin.BackColor = [System.Drawing.Color]::Transparent
$lblDimMin.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
$script:pnlCardAdv.Controls.Add($lblDimMin)

$script:nudDimMinutes = New-Object System.Windows.Forms.NumericUpDown
$script:nudDimMinutes.Location = New-Object System.Drawing.Point(290, 448)
$script:nudDimMinutes.Size = New-Object System.Drawing.Size(60, 24)
$script:nudDimMinutes.Minimum = 1
$script:nudDimMinutes.Maximum = 60
$dimVal = [math]::Max(1, [math]::Min(60, [int]$script:SmartLightDimMinutes))
$script:nudDimMinutes.Value = $dimVal
$script:nudDimMinutes.BackColor = [System.Drawing.Color]::FromArgb(32, 32, 44)
$script:nudDimMinutes.ForeColor = Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
$script:nudDimMinutes.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
$script:nudDimMinutes.Add_ValueChanged({
    if ($script:nudDimMinutes.IsDisposed) { return }
    $script:SmartLightDimMinutes = [int]$script:nudDimMinutes.Value
    Save-SmartLightSettings
})
$script:pnlCardAdv.Controls.Add($script:nudDimMinutes)

$script:btnLightSetup = New-Object System.Windows.Forms.Button
$script:btnLightSetup.Text = 'Connect...'
$script:btnLightSetup.Size = New-Object System.Drawing.Size(96, 24)
$script:btnLightSetup.Location = New-Object System.Drawing.Point(224, 474)
Style-Button $script:btnLightSetup ([System.Drawing.Color]::FromArgb(28, 32, 44)) $script:C.Mint 8
$script:btnLightSetup.Add_Click({
    Show-ConnectLightsMenu -Anchor $script:btnLightSetup
})
$script:pnlCardAdv.Controls.Add($script:btnLightSetup)

$script:btnLightTest = New-Object System.Windows.Forms.Button
$script:btnLightTest.Text = 'Test'
$script:btnLightTest.Size = New-Object System.Drawing.Size(56, 24)
$script:btnLightTest.Location = New-Object System.Drawing.Point(324, 474)
Style-Button $script:btnLightTest ([System.Drawing.Color]::FromArgb(28, 32, 44)) (Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))) 8
$script:btnLightTest.Add_Click({
    if (Get-Command Test-SmartLightConnection -ErrorAction SilentlyContinue) {
        Sync-SmartLightConfig
        $result = Test-SmartLightConnection
        $icon = if ($result.Success) { 'Information' } else { 'Warning' }
        [System.Windows.Forms.MessageBox]::Show($result.Message, 'Light Test', 'OK', $icon) | Out-Null
    } else {
        [System.Windows.Forms.MessageBox]::Show('Smart Lights module not loaded.', 'Test', 'OK', 'Warning') | Out-Null
    }
})
$script:pnlCardAdv.Controls.Add($script:btnLightTest)

$script:lblLightStatus = New-Object System.Windows.Forms.Label
$script:lblLightStatus.Location = New-Object System.Drawing.Point(10, 504)
$script:lblLightStatus.Size = New-Object System.Drawing.Size(364, 32)
$script:lblLightStatus.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(147, 160, 175))
$script:lblLightStatus.BackColor = [System.Drawing.Color]::Transparent
$script:lblLightStatus.Font = New-Object System.Drawing.Font('Segoe UI', 8.25)
$script:lblLightStatus.TextAlign = 'TopLeft'
$script:lblLightStatus.AutoEllipsis = $true
$script:pnlCardAdv.Controls.Add($script:lblLightStatus)
Update-SmartLightStatusLabel

$script:btnThemeSwap = New-Object System.Windows.Forms.Button
$script:btnThemeSwap.Text = if ($script:UseSteamUi) { 'Classic' } else { 'Steam' }
$script:btnThemeSwap.Size = New-Object System.Drawing.Size(72, 24)
$script:btnThemeSwap.Location = New-Object System.Drawing.Point(300, 122)
Style-Button $script:btnThemeSwap ([System.Drawing.Color]::FromArgb(36, 36, 50)) (Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))) 8
$script:btnThemeSwap.Add_Click({
    $target = if ($script:UseSteamUi) { 'classic' } else { 'steam' }
    Switch-ThemeLive $target
    $script:btnThemeSwap.Text = if ($script:UseSteamUi) { 'Classic' } else { 'Steam' }
})
$script:pnlCardAdv.Controls.Add($script:btnThemeSwap)
$script:uiToolTip.SetToolTip($script:btnThemeSwap, 'Switch UI theme without restart')

Update-CardOptionsPanel

function Update-GracefulCheckbox {
    if (-not $script:UiReady) { return }
    $applies = Test-GracefulApplies
    if ($script:ForceShutdownRequested -and $applies -and $chkGraceful.Checked) {
        $chkGraceful.Checked = $false
    }
    $enabled = $applies -and -not ($script:ForceShutdownRequested -and $applies)
    $chkGraceful.Enabled = $enabled
    if (-not $enabled) { $chkGraceful.ForeColor = [System.Drawing.Color]::FromArgb(70, 70, 80) }
    else { $chkGraceful.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165)) }
}

function Update-ControlRowLayout {
    if (-not $script:UseSteamUi -and $script:pnlClassicStartY -and -not $script:Running -and -not $script:Paused) {
        $y = $script:pnlClassicStartY
    } elseif ($script:UseSteamUi) {
        $y = 370 + $script:yBoost
    } else {
        $y = 328 + $script:yBoost
    }
    $proofActive = ($script:MorningProofReport -and $script:MorningProofReport.ShowProof -and -not $script:Running -and -not $script:Paused)
    if ($script:Running -or $script:Paused) {
        $btnSnooze5.Visible = $true
        $btnSnooze.Visible = $true
        $btnStop.Visible = $true
        $btnSnooze5.Location = New-Object System.Drawing.Point(24, $y)
        $btnSnooze.Location = New-Object System.Drawing.Point(82, $y)
        $btnStop.Location = New-Object System.Drawing.Point(140, $y)
        $btnStart.Location = New-Object System.Drawing.Point(272, $y)
        $btnStart.Size = New-Object System.Drawing.Size(140, 40)
        if (Get-Command Update-SteamMorningProofActions -ErrorAction SilentlyContinue) {
            Update-SteamMorningProofActions -Visible $false -Y ($y + 46)
        }
    } else {
        $btnSnooze5.Visible = $false
        $btnSnooze.Visible = $false
        $btnStop.Visible = $false
        $btnStart.Location = New-Object System.Drawing.Point(24, $y)
        if ($proofActive) {
            $btnStart.Size = New-Object System.Drawing.Size($script:contentW, 40)
            if (Get-Command Update-SteamMorningProofActions -ErrorAction SilentlyContinue) {
                Update-SteamMorningProofActions -Visible $true -Y ($y + 46)
            }
        } else {
            $btnStart.Size = New-Object System.Drawing.Size($script:contentW, 44)
            if (Get-Command Update-SteamMorningProofActions -ErrorAction SilentlyContinue) {
                Update-SteamMorningProofActions -Visible $false -Y ($y + 46)
            }
        }
    }
}

# Tray
$script:tray = New-Object System.Windows.Forms.NotifyIcon
$script:trayIconStatic = $null
$iconPath = Get-AppIconPath
if ($iconPath) { $script:trayIconStatic = New-Object System.Drawing.Icon($iconPath) }
$script:trayLiveIcon = $null
$script:trayFlashState = $false
if ($script:trayIconStatic) { $script:tray.Icon = $script:trayIconStatic }
else { $script:tray.Icon = [System.Drawing.SystemIcons]::Application }
$script:tray.Visible = $true
$script:tray.Text = $script:AppName
Update-TrayProgressIcon

function Show-MainWindow {
    $form.Show()
    $form.WindowState = 'Normal'
    $form.ShowInTaskbar = $true
    $form.Activate()
    $form.BringToFront()
}

function Stop-TrayFlash {
    if ($script:trayFlash) { $script:trayFlash.Stop() }
    $script:trayFlashState = $false
    Update-TrayProgressIcon
}

function Hide-ToTray {
    param([switch]$Balloon)
    $script:tray.Visible = $true
    Update-TrayProgressIcon
    $form.Hide()
    $form.ShowInTaskbar = $false
    if ($Balloon) {
        $msg = if ($script:Running) {
            @(
                "Timer ends at $(Format-EndClock $script:Left)."
                'Look near the clock (click ^ if hidden).'
                'Double-click icon to show; right-click for menu.'
            ) -join ' '
        } elseif ($script:Paused) {
            @(
                "Paused $([TimeSpan]::FromSeconds($script:Left).ToString('mm\:ss'))."
                'Double-click tray icon to show; right-click for menu.'
            ) -join ' '
        } else {
            'Idle in tray. Double-click to show; right-click for menu.'
        }
        $script:tray.ShowBalloonTip(5000, $script:AppName, $msg, [System.Windows.Forms.ToolTipIcon]::Info)
    }
}

function Set-TrayText {
    param([string]$Text)
    if ($Text.Length -gt 63) { $Text = $Text.Substring(0, 63) }
    try { $script:tray.Text = $Text } catch { }
}

if ($script:UseSteamUi -and (Get-Command New-SteamTrayMenu -ErrorAction SilentlyContinue)) {
    $menu = New-SteamTrayMenu `
        -OnShow { Show-MainWindow } `
        -OnSnooze10 { if ($script:Running -and (Test-AllowSnooze 600)) { $script:Left += 600; $script:Warn5 = $false; $script:Warn60 = $false; $script:Warn30 = $false; Write-AuditLog 'snooze' 'tray+600'; Register-SessionSnooze; Update-Ui } } `
        -OnSnooze5 { if ($script:Running -and (Test-AllowSnooze 300)) { $script:Left += 300; $script:Warn5 = $false; $script:Warn60 = $false; $script:Warn30 = $false; Write-AuditLog 'snooze' 'tray+300'; Register-SessionSnooze; Update-Ui } } `
        -OnPause {
            if ($script:Paused) { Resume-Timer; Show-MainWindow }
            elseif ($script:Running) { Stop-Timer -Reason 'tray_pause'; Show-MainWindow }
        } `
        -OnCancel { Invoke-EmergencyCancel } `
        -OnStats { Show-SleepLedgerDialog } `
        -OnBigPicture { Show-BigPicture } `
        -OnExit {
            $script:Running = $false
            $script:timer.Stop()
            $script:pulseTimer.Stop()
            $script:tray.Visible = $false
            $form.Close()
        }
} else {
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $menu.BackColor = [System.Drawing.Color]::FromArgb(14, 18, 28)
    $menu.ForeColor = [System.Drawing.Color]::FromArgb(210, 220, 232)
    $menu.ShowImageMargin = $false
    $menu.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $menu.Add_Paint({
        param($s, $e)
        $accent = Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(118, 201, 255))
        $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(50, $accent.R, $accent.G, $accent.B)), 1
        $e.Graphics.DrawRectangle($pen, 0, 0, ($s.Width - 1), ($s.Height - 1))
        $pen.Dispose()
    })
    # Header
    $trayHeader = New-Object System.Windows.Forms.ToolStripLabel (([char]0x263E) + '  ' + $script:AppName)
    $trayHeader.ForeColor = Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))
    $trayHeader.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5, [System.Drawing.FontStyle]::Bold)
    [void]$menu.Items.Add($trayHeader)
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    # Main actions
    $miShow = New-Object System.Windows.Forms.ToolStripMenuItem (([char]0x25B6) + '  Show')
    $miShow.Add_Click({ Show-MainWindow })
    [void]$menu.Items.Add($miShow)
    $miCinema = New-Object System.Windows.Forms.ToolStripMenuItem (([System.Char]::ConvertFromUtf32(0x1F3AC)) + '  Cinema mode')
    $miCinema.Add_Click({ Show-BigPicture })
    [void]$menu.Items.Add($miCinema)
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    # Tools section
    $miCal = New-Object System.Windows.Forms.ToolStripMenuItem (([System.Char]::ConvertFromUtf32(0x1F4C5)) + '  Calendar event...')
    $miCal.Add_Click({ Show-CalendarEventDialog | Out-Null })
    [void]$menu.Items.Add($miCal)
    $miFeed = New-Object System.Windows.Forms.ToolStripMenuItem (([System.Char]::ConvertFromUtf32(0x1F4E1)) + '  Calendar live feed...')
    $miFeed.Add_Click({ Show-CalendarFeedDialog })
    [void]$menu.Items.Add($miFeed)
    $miSave = New-Object System.Windows.Forms.ToolStripMenuItem (([System.Char]::ConvertFromUtf32(0x1F4BE)) + '  Save current timer...')
    $miSave.Add_Click({ Show-SaveTimerProfileDialog })
    [void]$menu.Items.Add($miSave)
    $miLedger = New-Object System.Windows.Forms.ToolStripMenuItem (([System.Char]::ConvertFromUtf32(0x1F4CA)) + '  Sleep ledger')
    $miLedger.Add_Click({ Show-SleepLedgerDialog })
    [void]$menu.Items.Add($miLedger)
    $miHouse = New-Object System.Windows.Forms.ToolStripMenuItem (([System.Char]::ConvertFromUtf32(0x1F3E0)) + '  Household sync...')
    $miHouse.Add_Click({ Show-HouseholdHarmonyDialog })
    [void]$menu.Items.Add($miHouse)
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    # Timer controls
    $miSnooze = New-Object System.Windows.Forms.ToolStripMenuItem (([char]0x23F0) + '  +10 min')
    $miSnooze.Add_Click({ if ($script:Running -and (Test-AllowSnooze 600)) { $script:Left += 600; $script:Warn5 = $false; $script:Warn60 = $false; $script:Warn30 = $false; Write-AuditLog 'snooze' 'tray+600'; Register-SessionSnooze; Update-Ui } })
    [void]$menu.Items.Add($miSnooze)
    $miPause = New-Object System.Windows.Forms.ToolStripMenuItem (([char]0x23F8) + '  Pause')
    $miPause.Add_Click({
        if ($script:Paused) { Resume-Timer; Show-MainWindow }
        elseif ($script:Running) { Stop-Timer -Reason 'tray_pause'; Show-MainWindow }
    })
    $script:trayPauseItem = $miPause
    [void]$menu.Items.Add($miPause)
    $miCancel = New-Object System.Windows.Forms.ToolStripMenuItem (([char]0x26D4) + '  Cancel')
    $miCancel.Add_Click({ Invoke-EmergencyCancel })
    [void]$menu.Items.Add($miCancel)
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    # Exit
    $miExit = New-Object System.Windows.Forms.ToolStripMenuItem (([char]0x2715) + '  Exit')
    $miExit.ForeColor = [System.Drawing.Color]::FromArgb(200, 100, 100)
    $miExit.Add_Click({
        $script:Running = $false
        $script:timer.Stop()
        $script:pulseTimer.Stop()
        $script:tray.Visible = $false
        $form.Close()
    })
    [void]$menu.Items.Add($miExit)
    if (Get-Command Set-SteamTrayMenuStyle -ErrorAction SilentlyContinue) {
        Set-SteamTrayMenuStyle $menu
    }
}
$script:tray.ContextMenuStrip = $menu
$script:tray.Add_MouseClick({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Show-MainWindow }
})
$script:tray.Add_DoubleClick({ Show-MainWindow })

function Update-RitualHighlight {
    foreach ($rb in $script:RitualBtns) {
        $rit = $rb.Tag
        if ($rit.Id -eq $script:LastRitualId) {
            if ($script:UseSteamUi) {
                Style-Button $rb (Get-UiColor 'Play' ([System.Drawing.Color]::FromArgb(117, 176, 34))) `
                    ([System.Drawing.Color]::FromArgb(22, 32, 12)) 8 (Get-UiColor 'PlayHover' ([System.Drawing.Color]::FromArgb(142, 214, 41)))
            } else {
                Style-Button $rb $script:C.Violet ([System.Drawing.Color]::FromArgb(14, 12, 18)) 8 ([System.Drawing.Color]::FromArgb(190, 160, 255))
            }
        } else {
            $off = if ($script:UseSteamUi) { $script:C.NavOff } else { [System.Drawing.Color]::FromArgb(28, 26, 38) }
            Style-Button $rb $off $script:C.Ink 8 ([System.Drawing.Color]::FromArgb(42, 40, 56))
        }
    }
}

function Update-PresetHighlight {
    foreach ($pb in $script:PresetBtns) {
        if ($pb.Tag -eq $script:DefaultSec) {
            Style-Button $pb $script:C.Amber ([System.Drawing.Color]::FromArgb(18, 14, 8)) 8 ([System.Drawing.Color]::FromArgb(255, 195, 110))
        } else {
            Style-Button $pb ([System.Drawing.Color]::FromArgb(30, 30, 42)) $script:C.Muted 8 ([System.Drawing.Color]::FromArgb(44, 44, 58))
        }
    }
}

function Update-ClockPresetHighlight {
    foreach ($cb in $script:ClockPresetBtns) {
        if ($cb.Tag -eq $script:ClockTime) {
            Style-Button $cb $script:C.Amber ([System.Drawing.Color]::FromArgb(18, 14, 8)) 8 ([System.Drawing.Color]::FromArgb(255, 195, 110))
        } else {
            Style-Button $cb ([System.Drawing.Color]::FromArgb(30, 30, 42)) $script:C.Muted 8 ([System.Drawing.Color]::FromArgb(44, 44, 58))
        }
    }
}

function Update-Ui {
    if ($env:LIGHTSOUT_DEBUG -eq '1' -and $error.Count -gt 0) {
        Write-LightsOutDebugLog 'BufferedError' $error[0]
        $error.Clear()
    }
    if ($script:TimerMode -eq 'duration') { Sync-LobbyMinutesControl }
    $idleSec = if ($script:TimerMode -in @('clock', 'calendar')) { Get-SecondsUntilClock } else { $script:DefaultSec }
    if ($script:Running) {
        $secs = $script:Left
    } elseif ($script:Paused) {
        $secs = $script:Left
    } else {
        $secs = $idleSec
    }
    $timeStr = ([TimeSpan]::FromSeconds([math]::Max(0, $secs))).ToString('mm\:ss')
    $inLobby = (-not $script:Running -and -not $script:Paused)
    if ($lblLobbyTag) {
        if ($inLobby -and $script:DemoMode) {
            $lblLobbyTag.Text = 'DEMO'
            $lblLobbyTag.ForeColor = Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))
        } elseif ($inLobby -and $script:MorningProofRingBadge -eq 'complete') {
            $lblLobbyTag.Text = 'DONE'
            $lblLobbyTag.ForeColor = Get-UiColor 'Online' ([System.Drawing.Color]::FromArgb(87, 192, 87))
        } elseif ($inLobby -and $script:MorningProofRingBadge -eq 'dry-run') {
            $lblLobbyTag.Text = 'DRY'
            $lblLobbyTag.ForeColor = Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))
        } elseif ($inLobby -and $script:UseSteamUi) {
            $lblLobbyTag.Text = 'PREVIEW'
            $lblLobbyTag.ForeColor = Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))
        } else {
            $lblLobbyTag.Text = 'LOBBY'
            $lblLobbyTag.ForeColor = Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))
        }
        $lblLobbyTag.Visible = $inLobby
    }
    $script:MorningProofReport = $null
    $script:MorningProofRingBadge = $null
    if ($inLobby -and (Get-Command Get-MorningProofReport -ErrorAction SilentlyContinue)) {
        $mp = Get-MorningProofReport -AuditLogPath $script:AuditLogPath -LastSeen $script:MorningProofLastSeen
        if ($mp.ShowProof) {
            $script:MorningProofReport = $mp
            $script:MorningProofRingBadge = switch ($mp.State) {
                'completed' { 'complete' }
                'dry-run' { 'dry-run' }
                default { $null }
            }
        } elseif ($script:DemoMode -and -not $script:DemoProofDismissed -and (Get-Command Get-DemoMorningProofReport -ErrorAction SilentlyContinue)) {
            $script:MorningProofReport = Get-DemoMorningProofReport
            $script:MorningProofRingBadge = 'dry-run'
        }
    }
    if ($inLobby -and $script:TimerMode -in @('clock', 'calendar')) {
        $target = Get-ClockTargetDateTime
        $lblTime.Text = Format-ClockDisplay $target
        $tfSize = if ($lblTime.Text.Length -gt 14) { 13 } else { 26 }
        $lblTime.Font = New-Object System.Drawing.Font('Segoe UI', $tfSize, [System.Drawing.FontStyle]::Bold)
        $lblRemain.Text = Format-RingEndSubtitle $idleSec
        $lblRemain.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    } elseif ($inLobby) {
        $lblTime.Text = $timeStr
        $lblTime.Font = New-Object System.Drawing.Font($timeFont, 34, [System.Drawing.FontStyle]::Bold)
        $lblRemain.Text = Format-RingEndSubtitle $idleSec
        $lblRemain.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8.5)
    } else {
        $lblTime.Text = $timeStr
        $lblTime.Font = New-Object System.Drawing.Font($timeFont, 38, [System.Drawing.FontStyle]::Bold)
    }
    $accent = Get-CountdownAccentColor
    $lblTime.ForeColor = if ($script:Running -or $script:Paused) {
        Coalesce-UiColor $accent (Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224)))
    } else {
        Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
    }
    $urgency = Get-CountdownUrgencyLevel
    if ($script:Running -and $urgency -in @('final', 'critical')) {
        $verb = switch ($script:Action) {
            'Sleep' { 'sleep' }
            'Restart' { 'restart' }
            'Hibernate' { 'hibernate' }
            'Lock' { 'lock' }
            default { 'shut down' }
        }
        $lblUrgent.Text = if ($urgency -eq 'critical') { "Last seconds - will $verb" } else { "Under 1 min - will $verb" }
        $lblUrgent.Visible = $true
        $lblUrgent.ForeColor = if ($urgency -eq 'critical') { Get-RingColor } else { Get-UiColor 'Rose' ([System.Drawing.Color]::FromArgb(255, 107, 107)) }
    } else {
        $lblUrgent.Visible = $false
    }
    if ($script:Running -and $script:Total -gt 0) {
        $pctLeft = [int](100 * $script:Left / $script:Total)
        $lblPct.Text = "$pctLeft% remaining"
        $lblPct.ForeColor = Coalesce-UiColor $accent (Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165)))
        $lblPct.Visible = $true
    } elseif ($script:Paused) {
        $lblPct.Text = 'paused'
        $lblPct.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
        $lblPct.Visible = $true
    } else {
        $lblPct.Visible = $false
    }
    $pnlRing.BackColor = Get-UrgencyRingBackColor
    $btnStart.Text = if ($script:Running) {
        'Running'
    } elseif ($script:Paused) {
        "Resume $timeStr"
    } elseif ($script:TimerMode -eq 'clock') {
        "Start at $(Format-ClockDisplay (Get-ClockTargetDateTime))"
    } elseif ($script:TimerMode -eq 'calendar') {
        "Start at $(Format-ClockDisplay (Get-ClockTargetDateTime))"
    } elseif (-not $script:UseSteamUi -and $script:TimerMode -eq 'duration') {
        $startMin = [math]::Max(1, [math]::Round($script:DefaultSec / 60.0))
        "START - ${startMin} min"
    } else {
        "PLAY TONIGHT - $(([TimeSpan]::FromSeconds($script:DefaultSec)).ToString('mm\:ss'))"
    }

    if ($script:Running) {
        $pct = [int](100 * ($script:Total - $script:Left) / [math]::Max(1, $script:Total))
        $lblSub.Text = "Countdown active - $pct% elapsed"
        $lblRemain.Text = Format-RingEndSubtitle $script:Left
        $lblRemain.Font = New-Object System.Drawing.Font('Segoe UI', 8)
        $lblEnd.Text = Format-EndLine $script:Left
        $endClock = Format-EndClock $script:Left
        $btnStart.Enabled = $false
        $btnSnooze.Enabled = $true
        $btnSnooze5.Enabled = $true
        $btnStop.Enabled = $true
        $btnStop.Text = 'Pause'
        foreach ($p in $script:Pills) { $p.Enabled = $false }
        $pnlPresets.Enabled = $true
        $pnlMode.Enabled = $false
        if ($script:trayPauseItem) { $script:trayPauseItem.Text = ([char]0x23F8) + '  Pause' }
        Set-TrayText "$script:AppName $timeStr -> $endClock ($($script:Action))"
        $form.Text = "$script:AppName - $timeStr ($($script:Action))"
    } elseif ($script:Paused) {
        $pct = [int](100 * ($script:Total - $script:Left) / [math]::Max(1, $script:Total))
        $lblSub.Text = "Paused - $($script:Action.ToLower()) in $timeStr"
        $lblRemain.Text = Format-RingEndSubtitle $script:Left
        $lblRemain.Font = New-Object System.Drawing.Font('Segoe UI', 8)
        $lblEnd.Text = Format-EndLine $script:Left
        $btnStart.Enabled = $true
        $btnSnooze.Enabled = $false
        $btnSnooze5.Enabled = $false
        $btnStop.Enabled = $true
        $btnStop.Text = 'Cancel'
        foreach ($p in $script:Pills) { $p.Enabled = $false }
        $pnlPresets.Enabled = $false
        $pnlClock.Enabled = $false
        $pnlMode.Enabled = $false
        if ($script:trayPauseItem) { $script:trayPauseItem.Text = ([char]0x25B6) + '  Resume' }
        Set-TrayText "$script:AppName PAUSED $timeStr ($($script:Action))"
        $form.Text = "$script:AppName - paused $timeStr"
    } else {
        if ($script:TimerMode -eq 'clock') {
            $target = Get-ClockTargetDateTime
            $lblSub.Text = "Daily time - $($script:Action.ToLower()) at $(Format-ClockDisplay $target)"
            $lblRemain.Text = Format-DurationLong $idleSec
            $lblEnd.Text = "$(Format-ClockDisplay $target) - in $(Format-DurationLong $idleSec)"
        } elseif ($script:TimerMode -eq 'calendar') {
            $target = Get-ClockTargetDateTime
            $evName = if ($script:CalendarEventTitle) { $script:CalendarEventTitle } else { 'scheduled event' }
            $lblSub.Text = "Calendar - $($script:Action.ToLower()) for $evName"
            $lblRemain.Text = Format-DurationLong $idleSec
            $lblEnd.Text = "$(Format-ClockDisplay $target) - in $(Format-DurationLong $idleSec)"
            if ($script:lblCalEvent) {
                $script:lblCalEvent.Text = "Event: $evName"
                $script:lblCalEvent.Visible = $true
            }
        } else {
            if ($script:lblCalEvent) { Update-CalendarEventLabel }
            if (-not $script:UseSteamUi) {
                $lblSub.Text = 'Sleep Timer'
                $lblRemain.Text = "$($script:Action) when timer ends"
            } else {
                $lblSub.Text = 'Pick a run, tune the action, then hit Play'
                $lblRemain.Text = 'Ready when you are'
            }
            $lblEnd.Text = Format-EndLine $script:DefaultSec -Preview
        }
        $btnStart.Enabled = $true
        $btnSnooze.Enabled = $false
        $btnSnooze5.Enabled = $false
        $btnStop.Enabled = $false
        $btnStop.Text = 'Pause'
        foreach ($p in $script:Pills) { $p.Enabled = $true }
        $pnlPresets.Enabled = $true
        $pnlClock.Enabled = $true
        $pnlMode.Enabled = $true
        if ($script:trayPauseItem) { $script:trayPauseItem.Text = ([char]0x23F8) + '  Pause' }
        Set-TrayText "$script:AppName - ready"
        $form.Text = $script:AppName
    }
    Update-RitualHighlight
    Update-PresetHighlight
    Update-LobbyQuickHighlight
    Update-ClockPresetHighlight
    Update-StartButtonStyle
    if ($script:Running) { $lblEnd.ForeColor = Get-CountdownAccentColor }
    elseif ($script:Paused) { $lblEnd.ForeColor = Get-UiColor 'Amber' ([System.Drawing.Color]::FromArgb(164, 208, 7)) }
    else { $lblEnd.ForeColor = Get-UiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244)) }
    if ($script:Running) {
        $lblSub.Font = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
        $lblSub.ForeColor = Get-UiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
    } else {
        $lblSub.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
        $lblSub.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
    }
    Update-TrayProgressIcon
    Update-SleepLedgerBadge
    if ($script:HouseholdPartner -and $script:lblCalEvent -and -not $script:Running) {
        $script:lblCalEvent.Text = "Household: $($script:HouseholdPartner.Machine) at $(Format-ClockDisplay $script:HouseholdPartner.Target)"
        $script:lblCalEvent.Visible = $true
    }
    $script:RingTargetDateTime = Get-RingTargetDateTime
    $pnlRing.Invalidate()
    if ($script:UseSteamUi -and (Get-Command Get-UiSessionState -ErrorAction SilentlyContinue)) {
        $endClockUi = Format-EndClock $(if ($script:Running -or $script:Paused) { $script:Left } else { $idleSec })
        $endLineUi = if ($script:Running -or $script:Paused) {
            Format-EndLine $script:Left
        } else {
            Format-EndLine $idleSec -Preview
        }
        $sess = Get-UiSessionState -TimeStr $timeStr -EndClock $endClockUi -EndLine $endLineUi -IdleSec $idleSec
        $proofActive = ($null -ne $script:MorningProofReport)
        if ($proofActive -and (Get-Command Update-SteamMorningProofHero -ErrorAction SilentlyContinue)) {
            try {
                Write-LightsOutDebugLog 'Before Update-SteamMorningProofHero active'
                Update-SteamMorningProofHero -Report $script:MorningProofReport -Active $true
                Write-LightsOutDebugLog 'After Update-SteamMorningProofHero active'
            } catch {
                Write-LightsOutDebugLog 'Update-SteamMorningProofHero active failed' $_
            }
        } elseif ($inLobby -and (Get-Command Get-TonightCardHeroPreview -ErrorAction SilentlyContinue)) {
            $clStatus = if ($script:DemoMode -and (Get-Command Get-DemoClearanceStatus -ErrorAction SilentlyContinue)) {
                Get-DemoClearanceStatus
            } else {
                (Get-SleepClearanceReport).Status
            }
            $preview = Get-TonightCardHeroPreview -CardId $script:TonightCardId -Action $script:Action `
                -TimerMode $script:TimerMode -DefaultSec $script:DefaultSec -ClockTime $script:ClockTime `
                -LastLightSequence $script:LastLightSequence -ClearanceStatus $clStatus
            $sess.HeroTitle = $preview.Title
            $sess.HeroTagline = $preview.Tagline
            $sess.Header = $preview.Header
            $sess.StartText = $preview.StartText
            if ($script:lblHeroTitle) {
                try {
                    Write-LightsOutDebugLog 'Before Update-SteamExperience preview'
                    Update-SteamExperience $sess
                    Write-LightsOutDebugLog 'After Update-SteamExperience preview'
                } catch {
                    Write-LightsOutDebugLog 'Update-SteamExperience preview failed' $_
                }
                if (Get-Command Update-SteamTonightPreviewHero -ErrorAction SilentlyContinue) {
                    try {
                        Write-LightsOutDebugLog 'Before Update-SteamTonightPreviewHero active'
                        Update-SteamTonightPreviewHero -Preview $preview -Active $true
                        Write-LightsOutDebugLog 'After Update-SteamTonightPreviewHero active'
                    } catch {
                        Write-LightsOutDebugLog 'Update-SteamTonightPreviewHero active failed' $_
                    }
                }
            }
        } elseif ($script:lblHeroTitle) {
            if (Get-Command Update-SteamTonightPreviewHero -ErrorAction SilentlyContinue) {
                try {
                    Write-LightsOutDebugLog 'Before Update-SteamTonightPreviewHero idle'
                    Update-SteamTonightPreviewHero -Preview $null -Active $false
                    Write-LightsOutDebugLog 'After Update-SteamTonightPreviewHero idle'
                } catch {
                    Write-LightsOutDebugLog 'Update-SteamTonightPreviewHero idle failed' $_
                }
            }
            if (Get-Command Update-SteamExperience -ErrorAction SilentlyContinue) {
                try {
                    Write-LightsOutDebugLog 'Before Update-SteamExperience idle'
                    Update-SteamExperience $sess
                    Write-LightsOutDebugLog 'After Update-SteamExperience idle'
                } catch {
                    Write-LightsOutDebugLog 'Update-SteamExperience idle failed' $_
                }
            } else {
                $lblSub.Text = $sess.Subtitle
            }
        } else {
            $lblSub.Text = $sess.Subtitle
            if (Get-Command Update-SteamHeaderStatus -ErrorAction SilentlyContinue) {
                try {
                    Write-LightsOutDebugLog 'Before Update-SteamHeaderStatus fallback'
                    Update-SteamHeaderStatus $sess.Header
                    Write-LightsOutDebugLog 'After Update-SteamHeaderStatus fallback'
                } catch {
                    Write-LightsOutDebugLog 'Update-SteamHeaderStatus fallback failed' $_
                }
            }
        }
        if ($inLobby -and $sess.RingMain) {
            $lblTime.Text = $sess.RingMain
            $rs = if ($sess.RingMain.Length -gt 14) { 13 } else { 26 }
            $lblTime.Font = New-Object System.Drawing.Font('Segoe UI', $rs, [System.Drawing.FontStyle]::Bold)
        }
        if ($sess.RingSub) { $lblRemain.Text = $sess.RingSub }
        else { $lblRemain.Text = $sess.RingHint }
        if ($script:Running -or $script:Paused) {
            if ($sess.PctLabel) {
                $lblPct.Text = $sess.PctLabel
                $lblPct.Visible = $true
            }
        } elseif ($inLobby) {
            $lblPct.Visible = $false
        }
        if ($script:btnStartUi) {
            if ($proofActive) {
                $script:btnStartUi.Text = 'PLAY TONIGHT AGAIN'
                Update-StartButtonStyle
            } else {
                $script:btnStartUi.Text = $sess.StartText
                if ($script:Running) {
                    Style-Button $script:btnStartUi $script:C.Elevated $script:C.Muted 10
                    $script:btnStartUi.Enabled = $false
                } else {
                    Update-StartButtonStyle
                }
            }
        }
        if (-not $proofActive) {
            $form.Text = $sess.FormTitle
            Set-TrayText $sess.TrayHeader
            if (Get-Command Update-SteamTrayHeader -ErrorAction SilentlyContinue) {
                try {
                    Update-SteamTrayHeader $sess.TrayHeader
                } catch {
                    Write-LightsOutDebugLog 'Update-SteamTrayHeader active failed' $_
                }
            }
        } elseif (Get-Command Update-SteamTrayHeader -ErrorAction SilentlyContinue) {
            Set-TrayText 'Lights Out - last run complete'
            try {
                Update-SteamTrayHeader 'Last run complete'
            } catch {
                Write-LightsOutDebugLog 'Update-SteamTrayHeader complete failed' $_
            }
        }
        if ($script:trayPauseItem) {
            $script:trayPauseItem.Text = if ($script:Paused) { ([char]0x25B6) + '  Resume session' } else { ([char]0x23F8) + '  Pause session' }
        }
        if ($script:lblHeroTitle -and -not $script:Running -and -not $script:Paused) {
            $lblEnd.Visible = $false
        } else {
            $lblEnd.Visible = $true
        }
        if (Get-Command Update-SteamSleepClearancePanel -ErrorAction SilentlyContinue) {
            $previewLobby = $inLobby -and -not $proofActive -and (Get-Command Get-TonightCardHeroPreview -ErrorAction SilentlyContinue)
            if ($inLobby -and -not $previewLobby) {
                try {
                    Write-LightsOutDebugLog 'Before Update-SteamSleepClearancePanel visible'
                    Update-SteamSleepClearancePanel -Report (Get-SleepClearanceReport) -Visible $true
                    Write-LightsOutDebugLog 'After Update-SteamSleepClearancePanel visible'
                } catch {
                    Write-LightsOutDebugLog 'Update-SteamSleepClearancePanel visible failed' $_
                }
            } else {
                try {
                    Write-LightsOutDebugLog 'Before Update-SteamSleepClearancePanel hidden'
                    Update-SteamSleepClearancePanel -Report $null -Visible $false
                    Write-LightsOutDebugLog 'After Update-SteamSleepClearancePanel hidden'
                } catch {
                    Write-LightsOutDebugLog 'Update-SteamSleepClearancePanel hidden failed' $_
                }
            }
        }
        if (Get-Command Update-SteamTrustBadgesPanel -ErrorAction SilentlyContinue) {
            try {
                Write-LightsOutDebugLog 'Before Update-SteamTrustBadgesPanel'
                Update-SteamTrustBadgesPanel -Visible (($inLobby -or $proofActive)) -DryRun:(Test-NoPowerAction) -DemoMode:([bool]$script:DemoMode)
                Write-LightsOutDebugLog 'After Update-SteamTrustBadgesPanel'
            } catch {
                Write-LightsOutDebugLog 'Update-SteamTrustBadgesPanel failed' $_
            }
        }
        $previewLobby = $inLobby -and -not $proofActive -and (Get-Command Get-TonightCardHeroPreview -ErrorAction SilentlyContinue)
        if (Get-Command Update-SteamLobbyRingLayout -ErrorAction SilentlyContinue) {
            try {
                Write-LightsOutDebugLog 'Before Update-SteamLobbyRingLayout'
                Update-SteamLobbyRingLayout -RingPanel $pnlRing -PreviewLobby $previewLobby -YBoost $script:yBoost
                Write-LightsOutDebugLog 'After Update-SteamLobbyRingLayout'
            } catch {
                Write-LightsOutDebugLog 'Update-SteamLobbyRingLayout failed' $_
            }
            if ($pnlPunch) {
                $pnlPunch.Location = $pnlRing.Location
                $pnlPunch.Size = $pnlRing.Size
            }
        }
        if (-not $proofActive -and (Get-Command Update-SteamTonightPreviewHero -ErrorAction SilentlyContinue) -and -not $inLobby) {
            try {
                Write-LightsOutDebugLog 'Before Update-SteamTonightPreviewHero trailing idle'
                Update-SteamTonightPreviewHero -Preview $null -Active $false
                Write-LightsOutDebugLog 'After Update-SteamTonightPreviewHero trailing idle'
            } catch {
                Write-LightsOutDebugLog 'Update-SteamTonightPreviewHero trailing idle failed' $_
            }
        }
        if (-not $proofActive -and (Get-Command Update-SteamMorningProofHero -ErrorAction SilentlyContinue)) {
            try {
                Write-LightsOutDebugLog 'Before Update-SteamMorningProofHero trailing idle'
                Update-SteamMorningProofHero -Report $null -Active $false
                Write-LightsOutDebugLog 'After Update-SteamMorningProofHero trailing idle'
            } catch {
                Write-LightsOutDebugLog 'Update-SteamMorningProofHero trailing idle failed' $_
            }
        }
    }
    Write-LightsOutDebugLog 'Before Update-BigPictureDisplay'
    Update-BigPictureDisplay
    Write-LightsOutDebugLog 'After Update-BigPictureDisplay'
    if (-not $script:UseSteamUi) { Apply-ClassicSimpleLayout }
    Write-LightsOutDebugLog 'Before Update-ControlRowLayout'
    Update-ControlRowLayout
    Write-LightsOutDebugLog 'After Update-ControlRowLayout'
}

function Stop-Timer {
    param([string]$Reason = 'pause')
    if ($script:Running) {
        Write-AuditLog 'timer_stopped' "$Reason left=$script:Left"
        if ($Reason -ne 'emergency') { Publish-LuxGridCancelled -Reason $Reason }
    }
    $script:Running = $false
    $script:timer.Stop()
    $script:pulseTimer.Stop()
    Stop-TrayFlash
    if (Get-Command Reset-SmartLightState -ErrorAction SilentlyContinue) { Reset-SmartLightState }
    if ($Reason -eq 'pause' -and $script:Left -gt 0) {
        $script:Paused = $true
        if (-not (Test-NoPowerAction)) {
            $pauseLeft = [TimeSpan]::FromSeconds($script:Left).ToString('mm\:ss')
            Show-SessionToast "Session paused - $pauseLeft left" 'Info'
        }
    } else {
        $script:Paused = $false
        if ($Reason -eq 'emergency' -and -not (Test-NoPowerAction)) {
            Show-SessionToast 'Session ended - back to library' 'Info'
        }
    }
    Hide-BigPicture
    Update-Ui
}

function Resume-Timer {
    if ($script:Left -le 0) { return }
    $script:Paused = $false
    $script:Running = $true
    Write-AuditLog 'timer_resumed' "left=$script:Left action=$script:Action"
    Publish-LuxGridEvent -EventName 'timer.start' -Payload @{
        timerName        = $script:LuxGridTimerName
        totalSeconds     = $script:Total
        remainingSeconds = $script:Left
        action           = $script:Action
        resumed          = $true
    }
    $script:timer.Start()
    $script:pulseTimer.Start()
    Update-Ui
    if (-not (Test-NoPowerAction)) {
        $resumeLeft = [TimeSpan]::FromSeconds($script:Left).ToString('mm\:ss')
        Show-SessionToast "Session resumed - $resumeLeft left" 'Info'
    }
}

function Cancel-PausedTimer {
    if (-not $script:Paused) { return }
    Write-AuditLog 'timer_cancelled' 'paused_clear'
    Publish-LuxGridCancelled -Reason 'cancel'
    $script:Paused = $false
    $script:Left = 0
    Update-Ui
}

function Reset-CountdownWarnFlags {
    $script:Warn5 = $false
    $script:Warn60 = $false
    $script:Warn30 = $false
}

function Add-QuickDialogButton {
    param(
        $Parent,
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$W,
        [int]$H,
        [string]$Tag,
        [System.Drawing.Color]$Bg,
        [System.Drawing.Color]$Fg,
        [scriptblock]$OnClick
    )
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Tag = $Tag
    $b.Location = New-Object System.Drawing.Point($X, $Y)
    $b.Size = New-Object System.Drawing.Size($W, $H)
    Style-Button $b $Bg $Fg 9
    $b.Add_Click($OnClick)
    $Parent.Controls.Add($b)
    return $b
}

function Show-CountdownQuickPanel {
    param([int]$MarkerSeconds)
    if (Test-NoPowerAction) { return 'Continue' }
    Show-MainWindow
    Stop-TrayFlash

    $title = switch ($MarkerSeconds) {
        300 { '5 minutes left' }
        60  { '1 minute left' }
        30  { '30 seconds left' }
        default { "$([TimeSpan]::FromSeconds($script:Left).ToString('mm\:ss')) left" }
    }
    $timeLeft = [TimeSpan]::FromSeconds([math]::Max(0, $script:Left)).ToString('mm\:ss')
    $endAt = Format-EndClock $script:Left

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "$script:AppName - quick choices"
    $dlg.Size = New-Object System.Drawing.Size(440, 318)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.TopMost = $true
    $dlg.BackColor = Get-UiColor 'Bg' ([System.Drawing.Color]::FromArgb(27, 40, 56))
    $dlg.KeyPreview = $true

    $head = New-Object System.Windows.Forms.Label
    $head.Location = New-Object System.Drawing.Point(16, 14)
    $head.Size = New-Object System.Drawing.Size(400, 28)
    $head.Text = $title
    $head.Font = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
    $head.ForeColor = if ($MarkerSeconds -le 60) { Get-UiColor 'Rose' ([System.Drawing.Color]::FromArgb(255, 107, 107)) } else { Get-UiColor 'Amber' ([System.Drawing.Color]::FromArgb(164, 208, 7)) }
    $head.TextAlign = 'MiddleCenter'
    $dlg.Controls.Add($head)

    $sub = New-Object System.Windows.Forms.Label
    $sub.Location = New-Object System.Drawing.Point(16, 44)
    $sub.Size = New-Object System.Drawing.Size(400, 36)
    $sub.Text = "$timeLeft remaining - $($script:Action) at $endAt`nPick more time, change action, or cancel."
    $sub.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $sub.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
    $sub.TextAlign = 'MiddleCenter'
    $dlg.Controls.Add($sub)

    $pick = {
        param($tag)
        $dlg.Tag = $tag
        $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dlg.Close()
    }.GetNewClosure()

    $btnBg = [System.Drawing.Color]::FromArgb(36, 36, 50)
    $btnHi = [System.Drawing.Color]::FromArgb(48, 48, 64)
    Add-QuickDialogButton $dlg '+5 min' 16 92 200 38 'Snooze300' $btnBg $script:C.Ink { & $pick 'Snooze300' } | Out-Null
    Add-QuickDialogButton $dlg '+10 min' 224 92 200 38 'Snooze600' $btnBg $script:C.Ink { & $pick 'Snooze600' } | Out-Null

    $actions = @(
        @{ L = 'Shutdown'; T = 'Shutdown'; C = $script:C.Amber }
        @{ L = 'Restart'; T = 'Restart'; C = $script:C.Blue }
        @{ L = 'Sleep'; T = 'Sleep'; C = $script:C.Mint }
        @{ L = 'Hibernate'; T = 'Hibernate'; C = $script:C.Violet }
        @{ L = 'Lock'; T = 'Lock'; C = $script:C.Slate }
    )
    $ax = 16
    foreach ($act in $actions) {
        $w = 78
        $actionTag = $act.T
        Add-QuickDialogButton $dlg $act.L $ax 138 $w 34 $actionTag ([System.Drawing.Color]::FromArgb(28, 28, 40)) $act.C {
            & $pick $actionTag
        } | Out-Null
        $ax += ($w + 6)
    }

    Add-QuickDialogButton $dlg 'Cancel countdown' 16 182 408 36 'Cancel' ([System.Drawing.Color]::FromArgb(48, 22, 28)) $script:C.Rose {
        & $pick 'Cancel'
    } | Out-Null
    Add-QuickDialogButton $dlg 'Keep countdown' 16 226 408 40 'Continue' $script:C.Amber ([System.Drawing.Color]::FromArgb(18, 14, 8)) {
        & $pick 'Continue'
    } | Out-Null

    $dlg.Add_KeyDown({
        if ($_.KeyCode -eq 'Escape') {
            $dlg.Tag = 'Continue'
            $dlg.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
            $dlg.Close()
        }
    })

    $dlg.Add_FormClosed({ $script:quickWarnDialog = $null })
    $script:quickWarnDialog = $dlg
    try {
        [void]$dlg.ShowDialog($form)
    } finally {
        if ($script:quickWarnDialog -eq $dlg) { $script:quickWarnDialog = $null }
    }
    if ($dlg.Tag) { return [string]$dlg.Tag }
    return 'Continue'
}

function Apply-CountdownQuickResult {
    param([string]$Result, [int]$MarkerSeconds = 0)
    if (-not $Result -or $Result -eq 'Continue') { return }

    Write-AuditLog 'quick_warn_choice' "marker=$MarkerSeconds result=$Result left=$($script:Left)"

    switch ($Result) {
        'Snooze300' {
            if ($script:Running -and (Test-AllowSnooze 300)) {
                $script:Left += 300
                Reset-CountdownWarnFlags
                Update-Ui
            }
        }
        'Snooze600' {
            if ($script:Running -and (Test-AllowSnooze 600)) {
                $script:Left += 600
                Reset-CountdownWarnFlags
                Update-Ui
            }
        }
        'Cancel' { Invoke-EmergencyCancel }
        default {
            if ($Result -in @('Shutdown', 'Restart', 'Sleep', 'Hibernate', 'Lock')) {
                Set-Action $Result
                if ($script:Running) { Save-Settings; Update-Ui }
            }
        }
    }
}

function Invoke-CountdownWarning {
    param([int]$MarkerSeconds)
    $severity = if ($MarkerSeconds -le 30) { 'critical' } elseif ($MarkerSeconds -le 60) { 'warning' } else { 'info' }
    Publish-LuxGridWarning -Remaining $MarkerSeconds -Severity $severity

    if ($MarkerSeconds -le 30) {
        [System.Media.SystemSounds]::Exclamation.Play()
        if ($script:trayFlash -and -not $script:trayFlash.Enabled) { $script:trayFlash.Start() }
    }

    if ($script:QuickWarnPanel) {
        $choice = Show-CountdownQuickPanel -MarkerSeconds $MarkerSeconds
        Apply-CountdownQuickResult -Result $choice -MarkerSeconds $MarkerSeconds
        return
    }

    if (Test-NoPowerAction) { return }
    $verb = switch ($script:Action) {
        'Sleep' { 'sleep' }
        'Restart' { 'restart' }
        'Hibernate' { 'hibernate' }
        'Lock' { 'lock' }
        default { 'shut down' }
    }
    switch ($MarkerSeconds) {
        300 {
            $msg5 = "5 minutes left - ends at $(Format-EndClock $script:Left)"
            $script:tray.ShowBalloonTip(5000, $script:AppName, $msg5, [System.Windows.Forms.ToolTipIcon]::Warning)
        }
        60 {
            $script:tray.ShowBalloonTip(
                5000, $script:AppName,
                "1 minute left - PC will $verb. Ctrl+Shift+S to cancel.",
                [System.Windows.Forms.ToolTipIcon]::Warning)
        }
        30 {
            $script:tray.ShowBalloonTip(
                6000, $script:AppName, '30 seconds - Ctrl+Shift+S to cancel',
                [System.Windows.Forms.ToolTipIcon]::Warning)
        }
    }
}

function Show-FinalConfirm {
    param([string]$ProceedText = '')
    if (Test-NoPowerAction) { return 'OK' }
    Show-MainWindow
    Stop-TrayFlash
    $proceedText = if ($ProceedText) { $ProceedText } else {
        switch ($script:Action) {
            'Restart' { 'Restart now' }
            'Sleep'   { 'Sleep now' }
            'Hibernate' { 'Hibernate now' }
            'Lock' { 'Lock now' }
            default   { 'Shut down now' }
        }
    }
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Still awake?'
    $dlg.Size = New-Object System.Drawing.Size(440, 340)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.TopMost = $true
    $dlg.BackColor = Get-UiColor 'Bg' ([System.Drawing.Color]::FromArgb(27, 40, 56))
    $dlg.KeyPreview = $true
    $t = New-Object System.Windows.Forms.Label
    $t.Location = New-Object System.Drawing.Point(16, 16)
    $t.Size = New-Object System.Drawing.Size(400, 44)
    $t.ForeColor = Get-ActionAccentColor
    $t.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
    $t.TextAlign = 'MiddleCenter'
    $dlg.Controls.Add($t)
    $hint = New-Object System.Windows.Forms.Label
    $hint.Location = New-Object System.Drawing.Point(16, 58)
    $hint.Size = New-Object System.Drawing.Size(400, 32)
    $hint.ForeColor = Get-UiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
    $hint.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
    $hint.TextAlign = 'MiddleCenter'
    $hint.Text = 'Add time, switch action, cancel, or proceed when the countdown ends.'
    $dlg.Controls.Add($hint)
    $script:confirmLeft = 5
    $cd = New-Object System.Windows.Forms.Timer
    $cd.Interval = 1000
    $cd.Add_Tick({
        $script:confirmLeft--
        $t.Text = "$($script:Action) in $script:confirmLeft..."
        if ($script:confirmLeft -le 0) { $cd.Stop(); $dlg.Tag = 'OK'; $dlg.DialogResult = 'OK'; $dlg.Close() }
    })
    $t.Text = "$($script:Action) in 5..."
    $cd.Start()

    $finalPick = {
        param($tag)
        $cd.Stop()
        $dlg.Tag = $tag
        $dlg.DialogResult = 'OK'
        $dlg.Close()
    }.GetNewClosure()

    $btnBg = [System.Drawing.Color]::FromArgb(36, 36, 50)
    Add-QuickDialogButton $dlg '+5 min' 16 98 200 36 'Retry5' $btnBg $script:C.Ink { & $finalPick 'Retry5' } | Out-Null
    Add-QuickDialogButton $dlg '+10 min' 224 98 200 36 'Retry' $btnBg $script:C.Ink { & $finalPick 'Retry' } | Out-Null

    $ax = 16
    foreach ($act in @(
            @{ L = 'Shutdown'; T = 'Shutdown'; C = $script:C.Amber }
            @{ L = 'Restart'; T = 'Restart'; C = $script:C.Blue }
            @{ L = 'Sleep'; T = 'Sleep'; C = $script:C.Mint }
            @{ L = 'Hibernate'; T = 'Hibernate'; C = $script:C.Violet }
            @{ L = 'Lock'; T = 'Lock'; C = $script:C.Slate }
        )) {
        $actionTag = $act.T
        Add-QuickDialogButton $dlg $act.L $ax 142 78 34 $actionTag ([System.Drawing.Color]::FromArgb(28, 28, 40)) $act.C {
            & $finalPick $actionTag
        } | Out-Null
        $ax += 84
    }

    Add-QuickDialogButton $dlg 'Cancel countdown' 16 186 408 34 'Cancel' ([System.Drawing.Color]::FromArgb(48, 22, 28)) $script:C.Rose {
        & $finalPick 'Cancel'
    } | Out-Null
    Add-QuickDialogButton $dlg $proceedText 16 228 408 44 'OK' $script:C.Amber ([System.Drawing.Color]::FromArgb(18, 14, 8)) {
        & $finalPick 'OK'
    } | Out-Null

    $dlg.Add_KeyDown({
        if ($_.KeyCode -eq 'Escape') {
            $cd.Stop()
            $dlg.Tag = 'Cancel'
            $dlg.DialogResult = 'Cancel'
            $dlg.Close()
        }
    })

    $dlg.Add_FormClosed({ if ($script:finalConfirmDialog -eq $dlg) { $script:finalConfirmDialog = $null } })
    $script:finalConfirmDialog = $dlg
    try {
        [void]$dlg.ShowDialog($form)
    } catch {
        Write-AuditLog 'final_confirm_dialog_error' $_.Exception.Message
        $dlg.Tag = 'OK'
    } finally {
        if ($script:finalConfirmDialog -eq $dlg) { $script:finalConfirmDialog = $null }
    }
    $cd.Dispose()
    if ($dlg.Tag) { return [string]$dlg.Tag }
    return 'OK'
}

function Test-UseForcePower {
    if ($script:Action -notin @('Shutdown', 'Restart')) { return $false }
    if ($script:ForceShutdownRequested) { return $true }
    if ($script:UiReady -and $chkGraceful) { return -not $chkGraceful.Checked }
    return -not [bool]$script:GracefulShutdown
}

function Invoke-ShutdownExe {
    param(
        [ValidateSet('Shutdown', 'Restart')]
        [string]$Action,
        [bool]$Force
    )
    $mode = if ($Action -eq 'Restart') { '/r' } else { '/s' }
    $shutdownArgs = @($mode, '/t', '0')
    if ($Force) { $shutdownArgs += '/f' }
    & shutdown.exe @shutdownArgs
    if ($LASTEXITCODE -ne 0) {
        throw "shutdown.exe $($shutdownArgs -join ' ') exited with code $LASTEXITCODE"
    }
}

function Invoke-PowerCommand {
    param(
        [string]$Action,
        [bool]$Force
    )
    switch ($Action) {
        'Restart' {
            if ($Force) { Invoke-ShutdownExe -Action 'Restart' -Force $true }
            else { Restart-Computer }
        }
        'Sleep' {
            $crit = if ($Force) { 1 } else { 0 }
            & rundll32.exe powrprof.dll,SetSuspendState 0, $crit, 0
        }
        'Hibernate' {
            $crit = if ($Force) { 1 } else { 0 }
            & rundll32.exe powrprof.dll,SetSuspendState 1, $crit, 0
        }
        'Lock' {
            & rundll32.exe user32.dll,LockWorkStation
        }
        default {
            if ($Force) { Invoke-ShutdownExe -Action 'Shutdown' -Force $true }
            else { Stop-Computer }
        }
    }
}

function Invoke-PowerCommandFallback {
    param(
        [string]$Action,
        [bool]$Force
    )
    switch ($Action) {
        'Restart' {
            if ($Force) { Restart-Computer -Force }
            else { Invoke-ShutdownExe -Action 'Restart' -Force $true }
        }
        'Shutdown' {
            if ($Force) { Stop-Computer -Force }
            else { Invoke-ShutdownExe -Action 'Shutdown' -Force $true }
        }
        'Sleep' { & rundll32.exe powrprof.dll,SetSuspendState 0, 1, 0 }
        'Hibernate' { & rundll32.exe powrprof.dll,SetSuspendState 1, 1, 0 }
        'Lock' { & rundll32.exe user32.dll,LockWorkStation }
    }
}

function Do-PowerAction {
    param([switch]$Failsafe)
    if ($script:powerActionDone) { return }
    $script:powerActionDone = $true
    Stop-PowerFailsafeWatchdog
    if (Get-Command Invoke-SmartLightOff -ErrorAction SilentlyContinue) {
        Invoke-SmartLightOff
    }
    Save-Settings
    if (Test-NoPowerAction) {
        Write-AuditLog 'power_blocked' "safe_mode action=$script:Action"
        $logDir = Join-Path $env:LOCALAPPDATA 'CoolTimer'
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        "$(Get-Date -Format o) SAFE_MODE action=$script:Action (no power command)" | Add-Content (Join-Path $logDir 'ci-smoke.log')
        $script:timer.Stop()
        $script:pulseTimer.Stop()
        $script:tray.Visible = $false
        try { [System.Windows.Forms.Application]::Exit() } catch { }
        return
    }
    $force = Test-UseForcePower
    $blockers = @()
    try { $blockers = @(Get-PowerRequestBlockers) } catch { }
    if ($blockers.Count -gt 0) {
        $names = ($blockers | Select-Object -First 4 | ForEach-Object { $_.Name }) -join ', '
        Write-AuditLog 'power_blockers_at_action' "count=$($blockers.Count) apps=$names"
        if ($script:Action -in @('Shutdown', 'Restart', 'Sleep', 'Hibernate') -and -not $force) {
            Write-AuditLog 'power_force_upgrade' "reason=blockers apps=$names"
            $force = $true
        }
    }
    if ($Failsafe -and $script:Action -in @('Shutdown', 'Restart', 'Sleep', 'Hibernate')) {
        $force = $true
    }
    Write-AuditLog 'power_action' "action=$script:Action force=$force failsafe=$([bool]$Failsafe) blockers=$($blockers.Count)"
    try { Test-AndCelebrateStreak } catch { }
    $acted = $false
    $lastErr = $null
    foreach ($attempt in @('primary', 'fallback')) {
        try {
            if ($attempt -eq 'primary') {
                Invoke-PowerCommand -Action $script:Action -Force $force
            } else {
                Invoke-PowerCommandFallback -Action $script:Action -Force $force
            }
            $acted = $true
            Write-AuditLog 'power_action_ok' "method=$attempt action=$script:Action"
            break
        } catch {
            $lastErr = $_.Exception.Message
            Write-AuditLog 'power_action_error' "method=$attempt err=$lastErr"
        }
    }
    if (-not $acted -and $lastErr) {
        Write-AuditLog 'power_action_failed' $lastErr
        try {
            [System.Windows.Forms.MessageBox]::Show(
                "Lights Out could not $($script:Action.ToLower()).`n`n$lastErr`n`nTry closing Edge and other apps, then start again.",
                $script:AppName, 'OK', 'Error') | Out-Null
        } catch { }
        $script:powerActionDone = $false
    }
}

function Start-Timer {
    param([int]$Sec)
    $script:Paused = $false
    $script:PulsePhase = 0.0
    $minSec = Get-MinTimerSec
    if ($Sec -lt $minSec) { $Sec = $minSec }
    $script:DefaultSec = $Sec
    $script:Total = $Sec
    $script:Left = $Sec
    $script:Warn5 = $false
    $script:Warn60 = $false
    $script:Warn30 = $false
    $script:PactBreaks = 0
    $script:PactSnoozeLocked = $false
    $script:SessionSnoozeCount = 0
    $script:Running = $true
    $script:powerActionDone = $false
    Stop-PowerFailsafeWatchdog
    Write-AuditLog 'timer_started' "action=$script:Action seconds=$Sec mode=$($script:TimerMode) clock=$($script:ClockTime) card=$($script:TonightCardId)"
    Publish-LuxGridEvent -EventName 'timer.start' -Payload @{
        timerName        = $script:LuxGridTimerName
        totalSeconds     = $Sec
        remainingSeconds = $Sec
        action           = $script:Action
    }
    Save-Settings
    $script:timer.Start()
    $script:pulseTimer.Start()
    Update-Ui
    if (-not (Test-NoPowerAction)) {
        if ($script:UseSteamUi) {
            $g = Get-RitualGameById $script:LastRitualId
            $name = if ($g) { $g.Title } else { 'Night session' }
            $endAt = Format-EndClock $Sec
            $msg = "Session started - $name - ends $endAt"
        } elseif ($script:TimerMode -eq 'clock') {
            $target = Format-ClockDisplay (Get-ClockTargetDateTime)
            $msg = "Started - $($script:Action) at $target"
        } else {
            $msg = "Started - $($script:Action) at $(Format-EndClock $Sec)"
        }
        Show-SessionToast $msg 'Info' 3500
    }
    if ($script:BigPictureOnStart) { Show-BigPicture }
    elseif ($chkMinTray.Checked) { Hide-ToTray -Balloon }
}

$script:timer = New-Object System.Windows.Forms.Timer
$script:timer.Interval = 1000
$script:timer.Add_Tick({
    if ($script:endPhase -eq 'dim') {
        Invoke-DimPhaseTick
        return
    }
    if (-not $script:Running) { return }
    $script:Left--
    if ($chkWarn5.Checked -and $script:Left -eq 300 -and -not $script:Warn5) {
        $script:Warn5 = $true
        Invoke-CountdownWarning -MarkerSeconds 300
    }
    if ($script:Left -eq 60 -and -not $script:Warn60) {
        $script:Warn60 = $true
        Invoke-CountdownWarning -MarkerSeconds 60
    }
    if ($script:Left -eq 30 -and -not $script:Warn30) {
        $script:Warn30 = $true
        Invoke-CountdownWarning -MarkerSeconds 30
    }
    if ($script:Left -gt 0 -and $script:Left % 30 -eq 0) {
        Publish-LuxGridTick -Remaining $script:Left
    }
    if (Get-Command Start-SmartLightDim -ErrorAction SilentlyContinue) {
        $dimSec = $script:SmartLightDimMinutes * 60
        if ($script:Left -le $dimSec -and $script:Left -gt 0) {
            Start-SmartLightDim
            Update-SmartLightTick -SecondsLeft $script:Left -DimDurationSec $dimSec
        }
    }
    if ($script:Left -le 0) {
        $script:timer.Stop()
        $script:pulseTimer.Stop()
        $script:Running = $false
        Stop-TrayFlash
        Update-TrayProgressIcon
        Dismiss-ActiveQuickWarnDialog
        $form.BeginInvoke([System.Action]{
            Start-PowerFailsafeWatchdog
            Start-PunchAnimation { Invoke-AfterPunchForLastLight }
        }) | Out-Null
        return
    }
    Update-Ui
})

$script:trayFlash = New-Object System.Windows.Forms.Timer
$script:trayFlash.Interval = 450
$script:trayFlash.Add_Tick({
    if (-not $script:Running -or $script:Left -gt 30) {
        Stop-TrayFlash
        return
    }
    $script:trayFlashState = -not $script:trayFlashState
    Update-TrayProgressIcon
})

$script:pulseTimer = New-Object System.Windows.Forms.Timer
$script:pulseTimer.Interval = 50
$script:pulseTimer.Add_Tick({
    $profile = Get-CountdownMotionProfile
    if ($script:Running) {
        $script:PulsePhase = ($script:PulsePhase + $profile.PulseStep) % 1.0
    } elseif ($script:lastLightRunning) {
        $script:PulsePhase = ($script:PulsePhase + 0.045) % 1.0
    }
    $breathStep = if ($script:lastLightRunning) { 0.042 } else { $profile.BreathStep }
    $script:BreathPhase = ($script:BreathPhase + $breathStep) % ([math]::PI * 2)
    $pnlRing.Invalidate()
    if ($script:lastLightRunning -and $script:pnlLastLightRing) { $script:pnlLastLightRing.Invalidate() }
})

$btnStart.Add_Click({
    if ($script:Paused) { Resume-Timer }
    else { Invoke-StartTimer (Get-StartSeconds) }
})
$btnSnooze.Add_Click({ if ($script:Running -and (Test-AllowSnooze 600)) { $script:Left += 600; $script:Warn5 = $false; $script:Warn60 = $false; $script:Warn30 = $false; Write-AuditLog 'snooze' '+600'; Register-SessionSnooze; Update-Ui } })
$btnSnooze5.Add_Click({ if ($script:Running -and (Test-AllowSnooze 300)) { $script:Left += 300; $script:Warn5 = $false; $script:Warn60 = $false; $script:Warn30 = $false; Write-AuditLog 'snooze' '+300'; Register-SessionSnooze; Update-Ui } })
$btnStop.Add_Click({
    if ($script:Paused) { Cancel-PausedTimer }
    elseif ($script:Running) { Stop-Timer -Reason 'pause' }
})

$form.Add_Resize({
    if ($form.WindowState -eq 'Minimized' -and $chkMinTray.Checked) {
        Hide-ToTray -Balloon
    }
})

$form.Add_KeyDown({
    if ($_.Control -and $_.Shift -and $_.KeyCode -eq 'S') {
        Invoke-EmergencyCancel
        $_.Handled = $true
        return
    }
    if ($_.Control -and $_.Alt) {
        switch ($_.KeyCode) {
            'D5' { Invoke-SessionSnooze 300; $_.Handled = $true }
            'NumPad5' { Invoke-SessionSnooze 300; $_.Handled = $true }
            'D0' { Invoke-SessionSnooze 600; $_.Handled = $true }
            'NumPad0' { Invoke-SessionSnooze 600; $_.Handled = $true }
            'P' { Invoke-SessionPauseToggle; $_.Handled = $true }
            'L' { Show-MainWindow; $_.Handled = $true }
        }
    }
})
$form.KeyPreview = $true

$form.Add_FormClosing({
    param($s, $e)
    if (Test-NoPowerAction) { return }
    if ($script:Running -or $script:Paused) {
        $state = if ($script:Paused) { 'paused' } else { 'running' }
        $r = [System.Windows.Forms.MessageBox]::Show(
            @(
                "Timer $state ($([TimeSpan]::FromSeconds($script:Left).ToString('mm\:ss')))."
                ''
                'Yes = hide to tray (near the clock; click ^ if hidden)'
                'No = stop and exit'
                'Cancel = keep window open'
            ) -join [Environment]::NewLine,
            $script:AppName, 'YesNoCancel', 'Question')
        if ($r -eq 'Yes') {
            $e.Cancel = $true
            $form.BeginInvoke([System.Action]{
                Hide-ToTray -Balloon
            }) | Out-Null
        }
        elseif ($r -eq 'No') {
            Publish-LuxGridCancelled -Reason 'exit'
            $script:Running = $false
            $script:Paused = $false
            $script:timer.Stop()
            $script:pulseTimer.Stop()
            $script:tray.Visible = $false
        }
        else { $e.Cancel = $true }
    } else {
        $script:tray.Visible = $false
    }
})

Set-Action $script:Action
Set-TimerMode $script:TimerMode
$script:UiReady = $false
Update-GracefulCheckbox
Update-SleepLedgerBadge
Update-MyTimersPanel
Update-CalendarEventLabel
if ($script:UseSteamUi) {
    Sync-TonightCardsPageLayout; Update-TonightCardHighlight
    if ($pnlRing) { $pnlRing.BringToFront() }
}
else { Sync-TonightCardsPageLayout }
Update-Ui

$script:feedTimer = New-Object System.Windows.Forms.Timer
$script:feedTimer.Interval = 60000
$script:feedTimer.Add_Tick({ Sync-CalendarFeedIfDue })

function Test-QuietHoursActive {
    try {
        $key = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CloudStore\Store\DefaultAccount\Current\default$windows.data.notifications.quiethourssettings\windows.data.notifications.quiethourssettings'
        if (-not (Test-Path $key)) { return $false }
        $data = (Get-ItemProperty $key -Name 'Data' -ErrorAction SilentlyContinue).Data
        if (-not $data -or $data.Count -lt 8) { return $false }
        return ($data[6] -ne 0)
    } catch { return $false }
}

$script:quietHoursWasActive = $false
$script:quietHoursTimer = New-Object System.Windows.Forms.Timer
$script:quietHoursTimer.Interval = 30000
$script:quietHoursTimer.Add_Tick({
    if (-not $script:QuietHoursAutoStart) { return }
    if ($script:Running -or $script:Paused) { return }
    $active = Test-QuietHoursActive
    if ($active -and -not $script:quietHoursWasActive) {
        Write-AuditLog 'quiet_hours_trigger' 'Focus Assist activated - auto-starting timer'
        $script:quietHoursWasActive = $true
        Invoke-StartTimer (Get-StartSeconds) -FromAutoStart
    } elseif (-not $active) {
        $script:quietHoursWasActive = $false
    }
})

$form.Add_Load({
    $script:UiReady = $true
    $script:pulseTimer.Start()
    if (-not $script:UseSteamUi) {
        if ($script:TimerMode -ne 'duration') { Set-TimerMode 'duration' }
        else {
            Sync-LobbyMinutesControl
            Apply-ClassicSimpleLayout
            Update-Ui
        }
    }
    try {
        Register-SessionHotkeys
    } catch {
        Write-AuditLog 'hotkey_failed' $_.Exception.Message
    }
    Update-MyTimersPanel
    Update-CalendarEventLabel
    if ($script:UseSteamUi -and (Get-Command Select-TonightCard -ErrorAction SilentlyContinue)) {
        if ($script:TonightCardId -and $script:TonightCardId -ne 'custom') {
            Select-TonightCard $script:TonightCardId
        } else {
            $card = if (Get-Command Get-TonightCardById -ErrorAction SilentlyContinue) {
                Get-TonightCardById $script:TonightCardId
            } else { $null }
            if ($card) { $script:TonightCardSnoozePolicy = [string]$card.SnoozePolicy }
            Update-TonightCardHighlight
            Sync-TonightCardsPageLayout
        }
    }
    if ($script:CalendarFeedUrl) {
        $script:feedTimer.Start()
        Sync-CalendarFeedIfDue
    }
    if ($script:QuietHoursAutoStart) { $script:quietHoursTimer.Start() }
    if ($Minimized) { $form.WindowState = 'Minimized' }
    else { $form.Activate(); $form.BringToFront() }
    if (($Start -or $script:AutoStartOnOpen) -and -not $NoAutoStart) {
        Invoke-StartTimer (Get-StartSeconds) -FromAutoStart
    }
    if ($Minimized -and $chkMinTray.Checked) { Hide-ToTray }
})

$form.Add_FormClosed({
    if ($script:feedTimer) { $script:feedTimer.Stop() }
    if ($script:quietHoursTimer) { $script:quietHoursTimer.Stop() }
    if ($script:globalHotkeys) {
        foreach ($hk in $script:globalHotkeys) { $hk.Dispose() }
    } elseif ($script:globalHotkey) { $script:globalHotkey.Dispose() }
    if ($script:trayLiveIcon) { $script:trayLiveIcon.Dispose() }
    if ($script:trayIconStatic) { $script:trayIconStatic.Dispose() }
})

try {
    if (-not $form.Visible) { [void]$form.Show() }
    [System.Windows.Forms.Application]::Run($form)
} catch {
    $err = $_.Exception.Message
    if ($form -and $form.IsDisposed) {
        Write-AuditLog 'ui_exit' 'form_closed'
    } else {
        Write-AuditLog 'ui_crash' $err
        [System.Windows.Forms.MessageBox]::Show(
            "Lights Out could not start:`n`n$err`n`nTry: Desktop\Lights Out\Lights Out.bat`nOr reinstall from the project folder.",
            $script:AppName, 'OK', 'Error') | Out-Null
    }
}
$script:tray.Visible = $false
$script:tray.Dispose()
if ($mutex) { $mutex.ReleaseMutex() | Out-Null }
