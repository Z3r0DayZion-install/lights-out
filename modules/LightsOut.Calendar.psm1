#Requires -Version 5.1
<#
.SYNOPSIS
    Parse iCalendar (.ics) files for Lights Out scheduled shutdowns.
.NOTES
    Works with exports from Google Calendar, Outlook, Apple Calendar, etc.
#>

function Expand-IcsLines {
    param([string[]]$Lines)
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $Lines) {
        if ($line -match '^[ \t]' -and $out.Count -gt 0) {
            $out[$out.Count - 1] = $out[$out.Count - 1] + $line.TrimStart()
        } elseif ($line.Trim()) {
            $out.Add($line.Trim())
        }
    }
    return @($out)
}

function ConvertFrom-IcsDateTime {
    param(
        [string]$Value,
        [string]$PropLine = ''
    )
    if (-not $Value) { return $null }
    $Value = $Value.Trim()
    if ($PropLine -match 'TZID=([^:;]+)') {
        # Best-effort: treat as local wall time (same as Outlook export on same machine)
    }
    if ($Value -match '^\d{8}$') {
        $y = $Value.Substring(0, 4)
        $mo = $Value.Substring(4, 2)
        $d = $Value.Substring(6, 2)
        return Get-Date -Year $y -Month $mo -Day $d -Hour 0 -Minute 0 -Second 0
    }
    $v = $Value -replace 'Z$', ''
    $formats = @(
        'yyyyMMddTHHmmss',
        'yyyyMMddTHHmm',
        'yyyy-MM-ddTHH:mm:ss',
        'yyyy-MM-dd HH:mm:ss',
        'yyyy-MM-dd HH:mm'
    )
    foreach ($fmt in $formats) {
        try {
            $dt = [DateTime]::ParseExact($v, $fmt, [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::AssumeLocal)
            if ($Value.EndsWith('Z')) {
                $dt = $dt.ToUniversalTime().ToLocalTime()
            }
            return $dt
        } catch { }
    }
    try { return [DateTime]::Parse($Value) } catch { return $null }
}

function Read-IcsPropertyValue {
    param([string]$Line)
    $colon = $Line.IndexOf(':')
    if ($colon -lt 0) { return $null }
    return $Line.Substring($colon + 1).Trim()
}

function Get-IcsPropertyName {
    param([string]$Line)
    $colon = $Line.IndexOf(':')
    if ($colon -lt 0) { return $Line }
    $head = $Line.Substring(0, $colon)
    return ($head -split ';')[0].ToUpper()
}

function Parse-IcsContent {
    param([string]$Text)
    if (-not $Text) { return @() }
    $lines = Expand-IcsLines ($Text -split "`r?`n")
    $events = [System.Collections.Generic.List[object]]::new()
    $inEvent = $false
    $cur = @{}

    foreach ($line in $lines) {
        $name = Get-IcsPropertyName $line
        switch ($name) {
            'BEGIN' {
                if ((Read-IcsPropertyValue $line) -eq 'VEVENT') {
                    $inEvent = $true
                    $cur = @{ Uid = ''; Summary = 'Event'; Start = $null; End = $null; Location = '' }
                }
            }
            'END' {
                if ($inEvent -and (Read-IcsPropertyValue $line) -eq 'VEVENT') {
                    if ($cur.Start) {
                        $events.Add([pscustomobject]@{
                                Uid      = if ($cur.Uid) { $cur.Uid } else { [guid]::NewGuid().ToString() }
                                Summary  = if ($cur.Summary) { $cur.Summary } else { 'Event' }
                                Start    = $cur.Start
                                End      = if ($cur.End) { $cur.End } else { $cur.Start.AddHours(1) }
                                Location = $cur.Location
                            })
                    }
                    $inEvent = $false
                    $cur = @{}
                }
            }
            default {
                if (-not $inEvent) { continue }
                $val = Read-IcsPropertyValue $line
                if ($name -eq 'UID') { $cur.Uid = $val }
                elseif ($name -eq 'SUMMARY') { $cur.Summary = ($val -replace '\\n', ' ' -replace '\\,', ',') }
                elseif ($name -eq 'LOCATION') { $cur.Location = ($val -replace '\\,', ',') }
                elseif ($name -in @('DTSTART', 'DTSTART;VALUE=DATE')) {
                    $cur.Start = ConvertFrom-IcsDateTime $val $line
                }
                elseif ($name -eq 'DTEND') {
                    $cur.End = ConvertFrom-IcsDateTime $val $line
                }
            }
        }
    }
    return @($events)
}

function Import-IcsCalendarFile {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    if (-not (Test-Path $Path)) { throw "Calendar file not found: $Path" }
    $ext = [IO.Path]::GetExtension($Path).ToLower()
    if ($ext -ne '.ics') { throw 'Expected a .ics calendar file (export from Google, Outlook, or Apple Calendar).' }
    $text = Get-Content $Path -Raw -Encoding UTF8
    if (-not $text) { $text = Get-Content $Path -Raw }
    $events = Parse-IcsContent $text
    return [pscustomobject]@{
        Path   = $Path
        Events = $events
    }
}

function Test-CalendarFeedUrl {
    param([string]$Url)
    if (-not $Url) { return $false }
    $u = $Url.Trim()
    if ($u -notmatch '^https://') { return $false }
    if ($u -match '\s') { return $false }
    return $true
}

function Import-IcsFromUrl {
    param(
        [Parameter(Mandatory)]
        [string]$Url,
        [int]$TimeoutSec = 45
    )
    if (-not (Test-CalendarFeedUrl $Url)) {
        throw 'Calendar feed must be an https URL (Google Calendar secret iCal link or hosted .ics).'
    }
    $prev = [System.Net.ServicePointManager]::SecurityProtocol
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        $req = [System.Net.WebRequest]::Create($Url.Trim())
        $req.Method = 'GET'
        $req.Timeout = $TimeoutSec * 1000
        $req.UserAgent = 'LightsOut/5.2 CalendarSync'
        $resp = $req.GetResponse()
        $stream = $resp.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $text = $reader.ReadToEnd()
        $reader.Close()
        $resp.Close()
    } finally {
        [System.Net.ServicePointManager]::SecurityProtocol = $prev
    }
    if (-not $text -or $text -notmatch 'BEGIN:VCALENDAR') {
        throw 'Downloaded feed is not a valid iCalendar file.'
    }
    $events = Parse-IcsContent $text
    return [pscustomobject]@{
        Path   = $Url.Trim()
        Events = $events
    }
}

function Get-IcsUpcomingEvents {
    param(
        [Parameter(Mandatory)]
        [array]$Events,
        [DateTime]$From = (Get-Date),
        [int]$WithinDays = 90,
        [int]$MaxCount = 50
    )
    $cutoff = $From.AddDays($WithinDays)
    @($Events |
        Where-Object { $_.Start -and $_.Start -gt $From -and $_.Start -le $cutoff } |
        Sort-Object Start |
        Select-Object -First $MaxCount)
}

# Parse-IcsContent is internal only (Parse is not an approved verb — avoids import warning)
Export-ModuleMember -Function Import-IcsCalendarFile, Import-IcsFromUrl, Test-CalendarFeedUrl, Get-IcsUpcomingEvents
