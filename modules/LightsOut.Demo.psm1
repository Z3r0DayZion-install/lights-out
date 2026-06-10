# Lights Out PC - Demo Mode (safe marketing / screenshot preview)
Set-StrictMode -Version Latest

function Test-DemoModeActive {
    param([bool]$DemoMode = $false)
    return [bool]$DemoMode
}

function Get-DemoMorningProofReport {
    $sampleAt = (Get-Date).Date.AddHours(23).AddMinutes(32)
    if ($sampleAt -gt (Get-Date)) { $sampleAt = $sampleAt.AddDays(-1) }
    $timeLabel = $sampleAt.ToString('h:mm tt')
    [pscustomobject]@{
        State       = 'dry-run'
        ShowProof   = $true
        CompletedAt = $sampleAt
        TimeLabel   = $timeLabel
        Action      = 'Shutdown'
        Mode        = 'duration'
        SnoozeCount = 0
        Streak      = 4
        ResultLine  = 'Demo sample - no real shutdown logged'
        HeroTitle   = 'Mission complete - ' + $timeLabel
        HeroTagline = "Action: Shutdown - Streak: 4 nights - Snoozes: 0"
        DetailLine  = 'Demo sample - Snoozes: 0 - Streak: 4 nights'
        EncourageLine = 'Promise kept. Rest well.'
        Headline    = 'DEMO SAMPLE'
        Subtitle    = "Sample proof - $timeLabel - Snoozes: 0"
        EventKey    = 'demo-morning-proof'
    }
}

function Get-DemoClearanceStatus {
    return 'Clear'
}

Export-ModuleMember -Function @(
    'Test-DemoModeActive'
    'Get-DemoMorningProofReport'
    'Get-DemoClearanceStatus'
)
