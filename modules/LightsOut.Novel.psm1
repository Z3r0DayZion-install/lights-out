#Requires -Version 5.1
<#
.SYNOPSIS
    Novel Lights Out features: Sleep Ledger, Bedtime Pact, Household Harmony.
#>

function ConvertTo-LightsOutAuditDate {
    param([string]$Value)
    if (-not $Value) { return $null }
    [DateTime]$parsed = [DateTime]::MinValue
    if ([DateTime]::TryParse($Value, [ref]$parsed)) { return $parsed }
    return $null
}

function Get-SleepLedgerStats {
    param(
        [string]$AuditLogPath,
        [int]$LookbackDays = 60
    )
    $stats = [ordered]@{
        Streak       = 0
        BestStreak   = 0
        NightsDone   = 0
        Snoozes      = 0
        Cancels      = 0
        LastDone     = $null
        LastDoneLabel = 'never'
        WeekDots     = @()
    }
    if (-not (Test-Path $AuditLogPath)) { return [pscustomobject]$stats }

    $doneDays = [System.Collections.Generic.HashSet[string]]::new()
    $snooze = 0
    $cancel = 0
    $lastDone = $null

    foreach ($line in Get-Content $AuditLogPath -ErrorAction SilentlyContinue) {
        if ($line -notmatch '^(\S+)\s+(\S+)') { continue }
        $ts = $Matches[1]
        $ev = $Matches[2]
        $dt = ConvertTo-LightsOutAuditDate $ts
        if (-not $dt) { continue }
        $day = $dt.ToString('yyyy-MM-dd')
        switch -Regex ($ev) {
            '^power_action' { [void]$doneDays.Add($day); if (-not $lastDone -or $dt -gt $lastDone) { $lastDone = $dt } }
            '^snooze' { $snooze++ }
            '^(emergency_cancel|final_cancelled|timer_cancelled)' { $cancel++ }
        }
    }

    $stats.NightsDone = $doneDays.Count
    $stats.Snoozes = $snooze
    $stats.Cancels = $cancel
    if ($lastDone) {
        $stats.LastDone = $lastDone
        $stats.LastDoneLabel = $lastDone.ToString('ddd MMM d')
    }

    $cursor = (Get-Date).Date
    $streak = 0
    while ($true) {
        $key = $cursor.ToString('yyyy-MM-dd')
        if ($doneDays.Contains($key)) { $streak++ } else { break }
        $cursor = $cursor.AddDays(-1)
        if ($streak -gt $LookbackDays) { break }
    }
    $stats.Streak = $streak

    $best = 0
    $run = 0
    $prev = $null
    foreach ($d in ($doneDays | Sort-Object)) {
        $cur = [DateTime]::ParseExact($d, 'yyyy-MM-dd', $null)
        if ($prev -and ($cur - $prev).Days -eq 1) { $run++ } else { $run = 1 }
        if ($run -gt $best) { $best = $run }
        $prev = $cur
    }
    $stats.BestStreak = [math]::Max($best, $streak)

    for ($i = 6; $i -ge 0; $i--) {
        $day = (Get-Date).Date.AddDays(-$i).ToString('yyyy-MM-dd')
        $stats.WeekDots += [pscustomobject]@{
            Day   = $day
            Label = (Get-Date).Date.AddDays(-$i).ToString('ddd')
            Done  = $doneDays.Contains($day)
        }
    }
    return [pscustomobject]$stats
}

function Get-MorningProofAuditField {
    param(
        [string]$Detail,
        [string]$Name
    )
    if ($Detail -match "$Name=([^\s]+)") { return $Matches[1] }
    return $null
}

function Get-MorningProofReport {
    param(
        [string]$AuditLogPath,
        [string]$LastSeen = ''
    )

    $base = [ordered]@{
        State         = 'unknown'
        ShowProof     = $false
        CompletedAt   = $null
        TimeLabel     = ''
        Action        = 'Shutdown'
        Mode          = 'duration'
        SnoozeCount   = 0
        Streak        = 0
        ResultLine    = ''
        HeroTitle     = ''
        HeroTagline   = ''
        DetailLine    = ''
        EncourageLine = ''
        Headline      = ''
        Subtitle      = ''
        EventKey      = ''
    }

    if (-not $AuditLogPath -or -not (Test-Path $AuditLogPath)) {
        return [pscustomobject]$base
    }

    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($line in Get-Content $AuditLogPath -ErrorAction SilentlyContinue) {
        if ($line -notmatch '^(\S+)\s+(\S+)(?:\s+(.*))?$') { continue }
        $dt = ConvertTo-LightsOutAuditDate $Matches[1]
        if (-not $dt) { continue }
        $entries.Add([pscustomobject]@{
                Ts      = $dt
                EventKey = $Matches[1]
                Event   = $Matches[2]
                Detail  = if ($Matches[3]) { $Matches[3].Trim() } else { '' }
            })
    }
    if ($entries.Count -eq 0) { return [pscustomobject]$base }

    $terminalMap = [ordered]@{
        power_action      = 'completed'
        power_blocked     = 'dry-run'
        emergency_cancel  = 'cancelled'
        final_cancelled   = 'cancelled'
        timer_cancelled   = 'cancelled'
    }

    $termIdx = -1
    $state = 'unknown'
    for ($i = $entries.Count - 1; $i -ge 0; $i--) {
        $ev = [string]$entries[$i].Event
        foreach ($key in $terminalMap.Keys) {
            if ($ev -eq $key) {
                $termIdx = $i
                $state = [string]$terminalMap[$key]
                break
            }
        }
        if ($termIdx -ge 0) { break }
    }
    if ($termIdx -lt 0) { return [pscustomobject]$base }

    $term = $entries[$termIdx]
    $startIdx = -1
    for ($j = $termIdx - 1; $j -ge 0; $j--) {
        if ($entries[$j].Event -eq 'timer_started') {
            $startIdx = $j
            break
        }
    }
    if ($state -eq 'cancelled' -and $startIdx -lt 0) {
        return [pscustomobject]$base
    }

    $windowStart = if ($startIdx -ge 0) { $startIdx } else { $termIdx }
    $snoozeCount = 0
    $action = 'Shutdown'
    $mode = 'duration'
    for ($k = $windowStart; $k -le $termIdx; $k++) {
        $row = $entries[$k]
        if ($row.Event -match '^snooze') { $snoozeCount++ }
        if ($row.Event -eq 'timer_started') {
            $a = Get-MorningProofAuditField $row.Detail 'action'
            $m = Get-MorningProofAuditField $row.Detail 'mode'
            if ($a) { $action = $a }
            if ($m) { $mode = $m }
        }
    }
    $pa = Get-MorningProofAuditField $term.Detail 'action'
    if ($pa) { $action = $pa }

    $showProof = $true
    if ($LastSeen) {
        $seenAt = ConvertTo-LightsOutAuditDate $LastSeen
        if ($seenAt -and $term.Ts -le $seenAt) { $showProof = $false }
    }

    $stats = Get-SleepLedgerStats -AuditLogPath $AuditLogPath
    $timeLabel = $term.Ts.ToString('h:mm tt')
    $streak = [int]$stats.Streak
    $streakLabel = if ($streak -eq 1) { '1 night' } elseif ($streak -gt 1) { "$streak nights" } else { '0 nights' }

    switch ($state) {
        'completed' {
            $heroTitle = "Mission complete - $timeLabel"
            $heroTag = "Action: $action - Streak: $streakLabel - Snoozes: $snoozeCount"
            $detail = $heroTag
            $encourage = 'Promise kept. Rest well.'
            $headline = 'LIGHTS OUT COMPLETE'
            $subtitle = "Last run: $timeLabel - Action: $action - Snoozes: $snoozeCount"
            $result = 'Clean shutdown path'
        }
        'dry-run' {
            $heroTitle = "Mission complete - $timeLabel"
            $heroTag = 'Dry run - no power action was performed.'
            $detail = "Action: $action (simulated) - Snoozes: $snoozeCount"
            $encourage = 'Dry run complete - no power action was performed.'
            $headline = 'DRY RUN COMPLETE'
            $subtitle = "Last run: $timeLabel - Snoozes: $snoozeCount"
            $result = 'Safe mode - PC stayed on'
        }
        'cancelled' {
            $heroTitle = 'Session cancelled'
            $heroTag = 'No shutdown was performed.'
            $detail = "Cancelled at $timeLabel - Snoozes: $snoozeCount"
            $encourage = 'You stopped the session before shutdown.'
            $headline = 'SESSION CANCELLED'
            $subtitle = "Cancelled at $timeLabel - Snoozes: $snoozeCount"
            $result = 'No shutdown logged'
        }
        default {
            return [pscustomobject]$base
        }
    }

    [pscustomobject]@{
        State       = $state
        ShowProof   = $showProof
        CompletedAt = $term.Ts
        TimeLabel   = $timeLabel
        Action      = $action
        Mode        = $mode
        SnoozeCount = $snoozeCount
        Streak      = $streak
        ResultLine  = $result
        HeroTitle   = $heroTitle
        HeroTagline = $heroTag
        DetailLine  = $detail
        EncourageLine = $encourage
        Headline    = $headline
        Subtitle    = $subtitle
        EventKey    = $term.EventKey
    }
}

function Get-PactDeadline {
    param([string]$PactTimeHm)
    $hm = if ($PactTimeHm) { $PactTimeHm } else { '23:00' }
    $parts = $hm.Split(':')
    $h = [int]$parts[0]
    $m = [int]$parts[1]
    $now = Get-Date
    $deadline = Get-Date -Year $now.Year -Month $now.Month -Day $now.Day -Hour $h -Minute $m -Second 0
    if ($deadline -le $now) { $deadline = $deadline.AddDays(1) }
    return $deadline
}

function Test-SnoozeCrossesPact {
    param(
        [int]$SecondsToAdd,
        [int]$RemainingSeconds,
        [string]$PactTimeHm
    )
    if (-not $PactTimeHm) { return $false }
    $deadline = Get-PactDeadline $PactTimeHm
    $endAt = (Get-Date).AddSeconds($RemainingSeconds + $SecondsToAdd)
    return ($endAt -gt $deadline)
}

function New-HouseholdSyncPayload {
    param(
        [string]$Action,
        [DateTime]$TargetWhen,
        [string]$MachineName = $env:COMPUTERNAME
    )
    $code = -join ((48..57) + (65..90) | Get-Random -Count 6 | ForEach-Object { [char]$_ })
    return [ordered]@{
        version    = 1
        code       = $code
        machine    = $MachineName
        action     = $Action
        targetIso  = $TargetWhen.ToString('o')
        exportedAt = (Get-Date).ToString('o')
    }
}

function Import-HouseholdSyncPayload {
    param([string]$Path)
    if (-not (Test-Path $Path)) { throw "Not found: $Path" }
    $j = Get-Content $Path -Raw | ConvertFrom-Json
    if (-not $j.targetIso) { throw 'Invalid household sync file' }
    $target = [DateTime]::Parse([string]$j.targetIso)
    return [pscustomobject]@{
        Code      = [string]$j.code
        Machine   = [string]$j.machine
        Action    = [string]$j.action
        Target    = $target
        ExportedAt = if ($j.exportedAt) { [DateTime]::Parse([string]$j.exportedAt) } else { Get-Date }
    }
}

function Test-HouseholdPlansAlign {
    param(
        [DateTime]$LocalTarget,
        [DateTime]$PartnerTarget,
        [int]$WindowMinutes = 15
    )
    $delta = [math]::Abs(($LocalTarget - $PartnerTarget).TotalMinutes)
    return ($delta -le $WindowMinutes)
}

Export-ModuleMember -Function @(
    'Get-SleepLedgerStats'
    'Get-MorningProofReport'
    'Get-PactDeadline'
    'Test-SnoozeCrossesPact'
    'New-HouseholdSyncPayload'
    'Import-HouseholdSyncPayload'
    'Test-HouseholdPlansAlign'
)
