#Requires -Version 5.1
<#
.SYNOPSIS
    Last Light Sequences — timer-zero finale copy and step timing (visual layer only).
#>

$script:LastLightValidIds = @('ClassicFade', 'ExitTheGrid', 'AntiAlgorithm', 'SignalSeverance')

function Get-LastLightSequenceCatalog {
    return @(
        [pscustomobject]@{ Id = 'ClassicFade'; Name = 'Classic Fade'; Description = 'Calm fade before confirm' }
        [pscustomobject]@{ Id = 'ExitTheGrid'; Name = 'Exit the Grid'; Description = 'Cyber unplug finale' }
        [pscustomobject]@{ Id = 'AntiAlgorithm'; Name = 'Anti-Algorithm Protocol'; Description = 'Feed-resist shutdown ritual' }
        [pscustomobject]@{ Id = 'SignalSeverance'; Name = 'Signal Severance'; Description = 'Premium severance checklist' }
    )
}

function Normalize-LastLightSequenceId {
    param([string]$Id)
    if (-not $Id) { return 'ClassicFade' }
    $raw = ($Id -replace '\s', '' -replace '_', '')
    switch -Regex ($raw) {
        '^(?i)ClassicFade$' { return 'ClassicFade' }
        '^(?i)ExitTheGrid$' { return 'ExitTheGrid' }
        '^(?i)AntiAlgorithm(Protocol)?$' { return 'AntiAlgorithm' }
        '^(?i)SignalSeverance$' { return 'SignalSeverance' }
        default { return 'ClassicFade' }
    }
}

function Test-LastLightSequenceIdValid {
    param([string]$Id)
    return (Normalize-LastLightSequenceId $Id) -in $script:LastLightValidIds
}

function Get-LastLightSequenceMeta {
    param(
        [string]$SequenceId = 'ClassicFade',
        [bool]$DryRun = $false
    )
    $id = Normalize-LastLightSequenceId $SequenceId
    $finalLine = switch ($id) {
        'ExitTheGrid' { 'You are no longer available to the system.' }
        'AntiAlgorithm' { 'The algorithm lost tonight.' }
        'SignalSeverance' { 'Signal severed. Night secured.' }
        default {
            if ($DryRun) { 'No power action will run.' }
            else { 'Night recovered.' }
        }
    }
    $proceedLabel = switch ($id) {
        'ExitTheGrid' { 'UNPLUG' }
        'AntiAlgorithm' { 'UNPLUG' }
        default { $null }
    }
    $sequenceLabel = switch ($id) {
        'ExitTheGrid' { 'EXIT THE GRID' }
        'AntiAlgorithm' { 'ANTI-ALGORITHM PROTOCOL' }
        'SignalSeverance' { 'SIGNAL SEVERANCE' }
        default { 'LAST LIGHT' }
    }
    [pscustomobject]@{
        Id            = $id
        FinalLine     = $finalLine
        ProceedLabel  = $proceedLabel
        SequenceLabel = $sequenceLabel
        CinematicTitle = 'LAST LIGHT'
        StampLine     = if ($DryRun) { 'DRY RUN' } else { 'UNPLUGGED' }
    }
}

function Get-LastLightSequenceSteps {
    param(
        [string]$SequenceId = 'ClassicFade',
        [bool]$DryRun = $false
    )
    $id = Normalize-LastLightSequenceId $SequenceId
    $meta = Get-LastLightSequenceMeta -SequenceId $id -DryRun:$DryRun

    $lines = switch ($id) {
        'ExitTheGrid' {
            @(
                @{ Headline = 'GRID HOLD WEAKENING'; Line = 'The feed is losing control.'; DwellMs = 1800 }
                @{ Headline = ''; Line = 'Breaking signal...'; DwellMs = 1200 }
                @{ Headline = ''; Line = 'Disconnecting feed...'; DwellMs = 1200 }
                @{ Headline = ''; Line = 'Exiting the grid...'; DwellMs = 1500 }
                @{ Headline = ''; Line = $meta.FinalLine; DwellMs = 2000 }
            )
        }
        'AntiAlgorithm' {
            @(
                @{ Headline = 'THE FEED WANTS ONE MORE CLICK'; Line = 'Lights Out says no.'; DwellMs = 1800 }
                @{ Headline = 'ANTI-ALGORITHM PROTOCOL'; Line = ''; DwellMs = 1000 }
                @{ Headline = ''; Line = 'Autoplay resisted.'; DwellMs = 900 }
                @{ Headline = ''; Line = 'Recommendations ignored.'; DwellMs = 900 }
                @{ Headline = ''; Line = 'Infinite scroll denied.'; DwellMs = 900 }
                @{ Headline = ''; Line = 'Session ending.'; DwellMs = 1200 }
                @{ Headline = ''; Line = $meta.FinalLine; DwellMs = 2000 }
            )
        }
        'SignalSeverance' {
            @(
                @{ Headline = 'SIGNAL SEVERANCE INITIATED'; Line = ''; DwellMs = 1200 }
                @{ Headline = ''; Line = 'Browser noise: muted'; DwellMs = 900 }
                @{ Headline = ''; Line = 'Video loop: severed'; DwellMs = 900 }
                @{ Headline = ''; Line = 'System glow: fading'; DwellMs = 900 }
                @{ Headline = ''; Line = 'Session: closing'; DwellMs = 1200 }
                @{ Headline = ''; Line = $meta.FinalLine; DwellMs = 2000 }
            )
        }
        default {
            @(
                @{ Headline = 'LAST LIGHT'; Line = 'Your session is ending.'; DwellMs = 2000 }
                @{ Headline = $meta.StampLine; Line = $meta.FinalLine; DwellMs = 1800 }
            )
        }
    }

    if ($DryRun) {
        foreach ($step in $lines) {
            $step.DwellMs = [math]::Max(400, [int]($step.DwellMs * 0.35))
        }
    }
    return @($lines)
}

function Get-LastLightSequenceDurationMs {
    param(
        [string]$SequenceId = 'ClassicFade',
        [bool]$DryRun = $false
    )
    $sum = 0
    foreach ($step in (Get-LastLightSequenceSteps -SequenceId $SequenceId -DryRun:$DryRun)) {
        $sum += [int]$step.DwellMs
    }
    return $sum
}

function Get-LastLightSoundCatalog {
    return @(
        [pscustomobject]@{ Id = 'Off'; Name = 'Off' }
        [pscustomobject]@{ Id = 'Soft'; Name = 'Soft tick' }
        [pscustomobject]@{ Id = 'Cyber'; Name = 'Cyber (soon)' }
        [pscustomobject]@{ Id = 'Silent'; Name = 'Silent' }
    )
}

function Normalize-LastLightSoundId {
    param([string]$Id = 'Off')
    $v = [string]$Id
    switch -Regex ($v) {
        '^(?i)soft$' { return 'Soft' }
        '^(?i)cyber$' { return 'Cyber' }
        '^(?i)silent$' { return 'Silent' }
        default { return 'Off' }
    }
}

function Invoke-LastLightSound {
    param([string]$Mode = 'Off')
    switch (Normalize-LastLightSoundId $Mode) {
        'Soft' {
            try { [System.Media.SystemSounds]::Asterisk.Play() } catch { }
        }
    }
}

Export-ModuleMember -Function @(
    'Get-LastLightSequenceCatalog'
    'Normalize-LastLightSequenceId'
    'Test-LastLightSequenceIdValid'
    'Get-LastLightSequenceMeta'
    'Get-LastLightSequenceSteps'
    'Get-LastLightSequenceDurationMs'
    'Get-LastLightSoundCatalog'
    'Normalize-LastLightSoundId'
    'Invoke-LastLightSound'
)
