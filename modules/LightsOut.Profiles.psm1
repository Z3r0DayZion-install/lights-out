#Requires -Version 5.1
<#
.SYNOPSIS
    Saved named timer profiles for Lights Out.
#>

function ConvertTo-TimerProfile {
    param($Raw)
    if (-not $Raw) { return $null }
    $p = if ($Raw -is [hashtable]) { $Raw } else { @{
            Id                  = $Raw.Id
            Name                = $Raw.Name
            Action              = $Raw.Action
            Mode                = $Raw.Mode
            Seconds             = $Raw.Seconds
            Clock               = $Raw.Clock
            ScheduledAt         = $Raw.ScheduledAt
            CalendarSource      = $Raw.CalendarSource
            CalendarEventUid    = $Raw.CalendarEventUid
            CalendarEventTitle  = $Raw.CalendarEventTitle
            AutoStart           = $Raw.AutoStart
        } }
    $name = if ($p.Name) { "$($p.Name)".Trim() } else { '' }
    if (-not $name) { return $null }
    $mode = if ($p.Mode -in @('duration', 'clock', 'calendar')) { [string]$p.Mode } else { 'duration' }
    $action = if ($p.Action -in @('Shutdown', 'Restart', 'Sleep', 'Hibernate', 'Lock')) { [string]$p.Action } else { 'Shutdown' }
    $id = if ($p.Id) { [string]$p.Id } else { [guid]::NewGuid().ToString('N') }
    $sec = 0
    if ($null -ne $p.Seconds) { $sec = [math]::Max(60, [int]$p.Seconds) }
    $clock = if ($p.Clock) { [string]$p.Clock } else { '23:30' }
    $sched = ''
    if ($p.ScheduledAt) {
        try {
            $dt = [DateTime]::Parse([string]$p.ScheduledAt)
            $sched = $dt.ToString('o')
        } catch { }
    }
    return [pscustomobject]@{
        Id                 = $id
        Name               = $name.Substring(0, [math]::Min(32, $name.Length))
        Action             = $action
        Mode               = $mode
        Seconds            = $sec
        Clock              = $clock
        ScheduledAt        = $sched
        CalendarSource     = if ($p.CalendarSource) { [string]$p.CalendarSource } else { '' }
        CalendarEventUid   = if ($p.CalendarEventUid) { [string]$p.CalendarEventUid } else { '' }
        CalendarEventTitle = if ($p.CalendarEventTitle) { [string]$p.CalendarEventTitle } else { '' }
        AutoStart          = if ($null -eq $p.AutoStart) { $true } else { [bool]$p.AutoStart }
    }
}

function Get-TimerProfileHint {
    param($Profile)
    if (-not $Profile) { return '' }
    switch ($Profile.Mode) {
        'clock' { return "$($Profile.Action) at $($Profile.Clock)" }
        'calendar' {
            if ($Profile.CalendarEventTitle) { return "$($Profile.Action) - $($Profile.CalendarEventTitle)" }
            if ($Profile.ScheduledAt) {
                try {
                    $dt = [DateTime]::Parse($Profile.ScheduledAt)
                    return "$($Profile.Action) at $($dt.ToString('MMM d h:mm tt'))"
                } catch { }
            }
            return "$($Profile.Action) (calendar)"
        }
        default {
            $m = [math]::Ceiling([int]$Profile.Seconds / 60.0)
            return "$($Profile.Action) in ${m}m"
        }
    }
}

function ConvertFrom-TimerProfilesJson {
    param($JsonArray)
    $out = [System.Collections.Generic.List[object]]::new()
    if (-not $JsonArray) { return @() }
    foreach ($item in @($JsonArray)) {
        $norm = ConvertTo-TimerProfile $item
        if ($norm) { $out.Add($norm) }
    }
    return @($out)
}

Set-Alias -Name Normalize-TimerProfile -Value ConvertTo-TimerProfile -Scope Script
Export-ModuleMember -Function ConvertTo-TimerProfile, Get-TimerProfileHint, ConvertFrom-TimerProfilesJson -Alias Normalize-TimerProfile
