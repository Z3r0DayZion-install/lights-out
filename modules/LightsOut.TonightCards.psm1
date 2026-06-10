#Requires -Version 5.1
<#
.SYNOPSIS
    Tonight Cards — Night Lobby library presets (select only, no auto-start).
#>

$script:TonightCardValidIds = @('weeknight', 'movie', 'bedtime', 'hard_stop', 'custom')

function Get-TonightCardCatalog {
    return @(
        [pscustomobject]@{
            Id                       = 'weeknight'
            Title                    = 'Weeknight'
            Subtitle                 = 'A clean shutdown before the night drifts.'
            DurationSeconds          = 1440
            ClockTime                = $null
            TimerMode                = 'duration'
            Action                   = 'Shutdown'
            Strictness               = 'normal'
            SnoozePolicy             = 'default'
            DefaultLastLightSequence = 'ClassicFade'
            RitualId                 = 'weeknight'
            ClearanceSummary         = 'Calm shutdown path with the classic fade ending.'
            Accent                   = 'calm'
        }
        [pscustomobject]@{
            Id                       = 'movie'
            Title                    = 'Movie'
            Subtitle                 = 'Let the credits roll into sleep.'
            DurationSeconds          = 2700
            ClockTime                = $null
            TimerMode                = 'duration'
            Action                   = 'Sleep'
            Strictness               = 'normal'
            SnoozePolicy             = 'default'
            DefaultLastLightSequence = 'ClassicFade'
            RitualId                 = 'movie'
            ClearanceSummary         = 'Gentle sleep landing after the credits finish.'
            Accent                   = 'dream'
        }
        [pscustomobject]@{
            Id                       = 'bedtime'
            Title                    = 'Bedtime'
            Subtitle                 = 'A clock-based lights out ritual.'
            DurationSeconds          = $null
            ClockTime                = '23:30'
            TimerMode                = 'clock'
            Action                   = 'Shutdown'
            Strictness               = 'normal'
            SnoozePolicy             = 'default'
            DefaultLastLightSequence = 'ExitTheGrid'
            RitualId                 = 'bedtime'
            ClearanceSummary         = 'Clock lock for 11:30 PM with Exit the Grid.'
            Accent                   = 'focus'
        }
        [pscustomobject]@{
            Id                       = 'hard_stop'
            Title                    = 'Hard Stop'
            Subtitle                 = 'No drift. No bargaining. Full stop.'
            DurationSeconds          = 1440
            ClockTime                = $null
            TimerMode                = 'duration'
            Action                   = 'Shutdown'
            Strictness               = 'hard'
            SnoozePolicy             = 'limited'
            DefaultLastLightSequence = 'AntiAlgorithm'
            RitualId                 = ''
            ClearanceSummary         = 'Strict shutdown with limited snooze and the Anti-Algorithm ending.'
            Accent                   = 'hard'
        }
        [pscustomobject]@{
            Id                       = 'custom'
            Title                    = 'Custom'
            Subtitle                 = 'Shape the run your way.'
            DurationSeconds          = $null
            ClockTime                = $null
            TimerMode                = $null
            Action                   = $null
            Strictness               = 'normal'
            SnoozePolicy             = 'default'
            DefaultLastLightSequence = $null
            RitualId                 = ''
            ClearanceSummary         = ''
            Accent                   = 'custom'
        }
    )
}

function Normalize-TonightCardId {
    param([string]$Id)
    if (-not $Id) { return 'custom' }
    $raw = ($Id -replace '\s', '' -replace '_', '-').ToLower()
    switch ($raw) {
        'weeknight' { return 'weeknight' }
        'movie' { return 'movie' }
        'bedtime' { return 'bedtime' }
        'hardstop' { return 'hard_stop' }
        'hard-stop' { return 'hard_stop' }
        'custom' { return 'custom' }
        default { return 'custom' }
    }
}

function Get-TonightCardById {
    param([string]$Id)
    $norm = Normalize-TonightCardId $Id
    Get-TonightCardCatalog | Where-Object { $_.Id -eq $norm } | Select-Object -First 1
}

function Get-LastLightSequenceLabel {
    param([string]$SequenceId)
    if (-not $SequenceId) { return 'User pick' }
    switch ($SequenceId) {
        'ExitTheGrid' { return 'Exit the Grid' }
        'AntiAlgorithm' { return 'Anti-Algorithm' }
        'SignalSeverance' { return 'Signal Severance' }
        'ClassicFade' { return 'Classic Fade' }
        default { return 'Classic Fade' }
    }
}

function Get-TonightCardRunSummary {
    param(
        [string]$Action,
        [string]$TimerMode,
        [int]$DefaultSec,
        [string]$ClockTime
    )
    if ($TimerMode -eq 'clock') {
        $hm = if ($ClockTime) { $ClockTime } else { '23:30' }
        try {
            $parts = $hm.Split(':')
            $dt = Get-Date -Hour ([int]$parts[0]) -Minute ([int]$parts[1]) -Second 0
            $hm = $dt.ToString('h:mm tt')
        } catch { }
        return "$hm $Action"
    }
    if ($TimerMode -eq 'calendar') { return "Calendar $Action" }
    $mins = [math]::Round($DefaultSec / 60.0)
    if ($mins -ge 60) {
        $span = [TimeSpan]::FromSeconds($DefaultSec)
        return "$($span.ToString('mm\:ss')) $Action"
    }
    return "${mins} min $Action"
}

function Get-TonightCardSnoozeNote {
    param([string]$SnoozePolicy)
    switch ($SnoozePolicy) {
        'limited' { return 'No snooze' }
        'none' { return 'Snooze off' }
        default { return 'Normal snooze' }
    }
}

function Get-TonightCardTileText {
    param($Card, [string]$LastLightSequence = 'ClassicFade')
    if (-not $Card) { return 'CUSTOM' }
    if ($Card.Id -eq 'custom') {
        return "CUSTOM`nUse current setup`nManual run"
    }
    $run = switch ($Card.TimerMode) {
        'clock' {
            $hm = $Card.ClockTime
            try {
                $p = $hm.Split(':')
                $hm = (Get-Date -Hour ([int]$p[0]) -Minute ([int]$p[1]) -Second 0).ToString('h:mm tt')
            } catch { }
            "$hm $($Card.Action)"
        }
        default {
            $m = [math]::Round($Card.DurationSeconds / 60.0)
            "$m min $($Card.Action)"
        }
    }
    $line3 = switch ($Card.Id) {
        'movie' { 'Cinema landing' }
        'bedtime' { 'Clock ritual' }
        'hard_stop' { 'No snooze' }
        default { 'Calm exit' }
    }
    return "$($Card.Title.ToUpper())`n$run`n$line3"
}

function Get-TonightCardToolTip {
    param($Card, [string]$LastLightSequence = 'ClassicFade')
    if (-not $Card) { return 'Use your current settings for tonight.' }
    if ($Card.Id -eq 'custom') {
        $ll = Get-LastLightSequenceLabel $LastLightSequence
        return "Use current action and schedule.`nLast Light: $ll"
    }
    $run = Get-TonightCardRunSummary -Action $Card.Action -TimerMode $Card.TimerMode `
        -DefaultSec ([int]$Card.DurationSeconds) -ClockTime $Card.ClockTime
    $ll = Get-LastLightSequenceLabel $Card.DefaultLastLightSequence
    $sn = Get-TonightCardSnoozeNote $Card.SnoozePolicy
    return "$($Card.Subtitle)`n$run`nLast Light: $ll - $sn"
}

function Get-TonightCardHeroPreview {
    param(
        [string]$CardId,
        [string]$Action = 'Shutdown',
        [string]$TimerMode = 'duration',
        [int]$DefaultSec = 1700,
        [string]$ClockTime = '23:30',
        [string]$LastLightSequence = 'ClassicFade',
        [string]$ClearanceStatus = 'Clear'
    )
    $clearLabel = if ($ClearanceStatus -eq 'Clear') { 'Clear' } else { 'Check' }
    $card = Get-TonightCardById $CardId
    if (-not $card -or $card.Id -eq 'custom') {
        $run = Get-TonightCardRunSummary -Action $Action -TimerMode $TimerMode -DefaultSec $DefaultSec -ClockTime $ClockTime
        $ll = Get-LastLightSequenceLabel $LastLightSequence
        $sn = Get-TonightCardSnoozeNote 'default'
        $cardTitle = 'Custom'
        $ending = $ll
    } else {
        $run = Get-TonightCardRunSummary -Action $card.Action -TimerMode $card.TimerMode `
            -DefaultSec ([int]$card.DurationSeconds) -ClockTime $card.ClockTime
        $cardTitle = $card.Title
        $ending = Get-LastLightSequenceLabel $card.DefaultLastLightSequence
        $sn = Get-TonightCardSnoozeNote $card.SnoozePolicy
    }
    $detail = "Clearance: $clearLabel - Proof: Tomorrow morning"
    $metric = "Run: $run   -   Ending: $ending   -   Snooze: $sn"
    $startText = if ($TimerMode -eq 'clock' -and (-not $card -or $card.Id -eq 'custom')) {
        'PLAY - ' + (Get-TonightCardRunSummary -Action $Action -TimerMode $TimerMode -DefaultSec $DefaultSec -ClockTime $ClockTime)
    } elseif ($card -and $card.TimerMode -eq 'clock') {
        "PLAY - $run"
    } else {
        $sec = if ($card -and $card.Id -ne 'custom') { [int]$card.DurationSeconds } else { $DefaultSec }
        $dur = ([TimeSpan]::FromSeconds($sec)).ToString('mm\:ss')
        "PLAY $dur"
    }
    [pscustomobject]@{
        Header        = "TONIGHT > $cardTitle"
        Title         = "TONIGHT'S PICK"
        Tagline       = "$cardTitle - $run"
        DetailLine    = $detail
        MetricLine    = $metric
        StartText     = $startText
        ClearanceLine = if ($ClearanceStatus -eq 'Clear') { 'Clearance ready.' } else { '' }
        BadgeText     = if ($ClearanceStatus -eq 'Clear') { 'READY' } else { 'CHECK' }
    }
}

function Get-TonightCardClearanceChecks {
    param(
        [string]$CardId,
        [string]$LastLightSequence = 'ClassicFade'
    )
    $card = Get-TonightCardById $CardId
    if (-not $card -or $card.Id -eq 'custom') {
        return @(
            @{ Name = 'Tonight card'; Value = 'Custom'; State = 'ok' }
            @{ Name = 'Last Light'; Value = (Get-LastLightSequenceLabel $LastLightSequence); State = 'ok' }
        )
    }
    $run = Get-TonightCardRunSummary -Action $card.Action -TimerMode $card.TimerMode `
        -DefaultSec ([int]$card.DurationSeconds) -ClockTime $card.ClockTime
    $checks = [System.Collections.Generic.List[object]]::new()
    $checks.Add(@{ Name = 'Tonight card'; Value = $card.Title; State = 'ok' })
    $checks.Add(@{ Name = 'Run preview'; Value = $run; State = 'ok' })
    $checks.Add(@{ Name = 'Last Light'; Value = (Get-LastLightSequenceLabel $card.DefaultLastLightSequence); State = 'ok' })
    $sn = Get-TonightCardSnoozeNote $card.SnoozePolicy
    $snState = if ($card.SnoozePolicy -eq 'limited') { 'ok' } else { 'ok' }
    $checks.Add(@{ Name = 'Snooze policy'; Value = $sn; State = $snState })
    return @($checks)
}

Export-ModuleMember -Function @(
    'Get-TonightCardCatalog'
    'Normalize-TonightCardId'
    'Get-TonightCardById'
    'Get-TonightCardTileText'
    'Get-TonightCardToolTip'
    'Get-TonightCardHeroPreview'
    'Get-TonightCardClearanceChecks'
    'Get-TonightCardRunSummary'
    'Get-LastLightSequenceLabel'
)
