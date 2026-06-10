#Requires -Version 5.1
<#
.SYNOPSIS
Steam-style night session launcher - colors, chrome, copy, tray.
#>

function Get-LightsOutThemePalette {
    param(
        [ValidateSet('classic', 'steam')]
        [string]$Name = 'classic'
    )
    if ($Name -eq 'steam') {
        return @{
            Bg           = [System.Drawing.Color]::FromArgb(13, 18, 28)
            Card         = [System.Drawing.Color]::FromArgb(24, 32, 46)
            Elevated     = [System.Drawing.Color]::FromArgb(36, 49, 70)
            RingCard     = [System.Drawing.Color]::FromArgb(18, 24, 36)
            Ink          = [System.Drawing.Color]::FromArgb(236, 242, 249)
            Muted        = [System.Drawing.Color]::FromArgb(137, 151, 170)
            Section      = [System.Drawing.Color]::FromArgb(118, 201, 255)
            Amber        = [System.Drawing.Color]::FromArgb(242, 185, 93)
            Mint         = [System.Drawing.Color]::FromArgb(104, 225, 186)
            Rose         = [System.Drawing.Color]::FromArgb(255, 118, 136)
            Blue         = [System.Drawing.Color]::FromArgb(126, 176, 255)
            Violet       = [System.Drawing.Color]::FromArgb(186, 154, 255)
            Slate        = [System.Drawing.Color]::FromArgb(162, 174, 194)
            Track        = [System.Drawing.Color]::FromArgb(57, 78, 106)
            Border       = [System.Drawing.Color]::FromArgb(58, 79, 108)
            Glow         = [System.Drawing.Color]::FromArgb(110, 198, 255)
            Sidebar      = [System.Drawing.Color]::FromArgb(10, 14, 22)
            Header       = [System.Drawing.Color]::FromArgb(15, 21, 31)
            HeaderTop    = [System.Drawing.Color]::FromArgb(28, 37, 53)
            HeaderBottom = [System.Drawing.Color]::FromArgb(13, 18, 28)
            HeroTop      = [System.Drawing.Color]::FromArgb(34, 48, 69)
            HeroBottom   = [System.Drawing.Color]::FromArgb(20, 28, 41)
            AccentSoft   = [System.Drawing.Color]::FromArgb(30, 77, 110)
            DangerSoft   = [System.Drawing.Color]::FromArgb(72, 40, 48)
            SuccessSoft  = [System.Drawing.Color]::FromArgb(24, 56, 46)
            Play         = [System.Drawing.Color]::FromArgb(124, 194, 67)
            PlayHover    = [System.Drawing.Color]::FromArgb(150, 224, 84)
            NavOn        = [System.Drawing.Color]::FromArgb(47, 97, 136)
            NavOff       = [System.Drawing.Color]::FromArgb(33, 42, 57)
            Online       = [System.Drawing.Color]::FromArgb(104, 225, 186)
            Away         = [System.Drawing.Color]::FromArgb(137, 151, 170)
        }
    }
    return @{
        Bg        = [System.Drawing.Color]::FromArgb(10, 10, 14)
        Card      = [System.Drawing.Color]::FromArgb(20, 20, 30)
        Elevated  = [System.Drawing.Color]::FromArgb(26, 26, 38)
        RingCard  = [System.Drawing.Color]::FromArgb(16, 16, 24)
        Ink       = [System.Drawing.Color]::FromArgb(252, 250, 244)
        Muted     = [System.Drawing.Color]::FromArgb(118, 118, 132)
        Section   = [System.Drawing.Color]::FromArgb(148, 146, 162)
        Amber     = [System.Drawing.Color]::FromArgb(242, 182, 92)
        Mint      = [System.Drawing.Color]::FromArgb(92, 218, 172)
        Rose      = [System.Drawing.Color]::FromArgb(238, 108, 122)
        Blue      = [System.Drawing.Color]::FromArgb(124, 176, 255)
        Violet    = [System.Drawing.Color]::FromArgb(176, 148, 238)
        Slate     = [System.Drawing.Color]::FromArgb(168, 174, 196)
        Track     = [System.Drawing.Color]::FromArgb(38, 38, 52)
        Border    = [System.Drawing.Color]::FromArgb(48, 48, 64)
        Glow      = [System.Drawing.Color]::FromArgb(99, 102, 241)
        Sidebar   = [System.Drawing.Color]::FromArgb(10, 10, 14)
        Header    = [System.Drawing.Color]::FromArgb(10, 10, 14)
        Play      = [System.Drawing.Color]::FromArgb(242, 182, 92)
        PlayHover = [System.Drawing.Color]::FromArgb(255, 195, 110)
        NavOn     = [System.Drawing.Color]::FromArgb(26, 26, 38)
        NavOff    = [System.Drawing.Color]::FromArgb(32, 32, 44)
        Online    = [System.Drawing.Color]::FromArgb(92, 218, 172)
        Away      = [System.Drawing.Color]::FromArgb(118, 118, 132)
    }
}

function Get-RitualGameCatalog {
    return @(
        @{
            Id = 'weeknight'; Label = 'Weeknight'; Hint = '24m shutdown'
            Title = 'Weeknight Shutdown'; Tagline = 'Quick run - lights off in 24 minutes.'; Genre = 'Casual'
            Seconds = 1440; Action = 'Shutdown'; Mode = 'duration'
        }
        @{
            Id = 'classic'; Label = '28:20'; Hint = 'Classic ritual'
            Title = 'Lights Out: Classic'; Tagline = 'The nightly speedrun. 28:20 to full shutdown.'; Genre = 'Ritual'
            Seconds = 1700; Action = 'Shutdown'; Mode = 'duration'
        }
        @{
            Id = 'movie'; Label = 'Movie'; Hint = '45m sleep'
            Title = 'After Credits'; Tagline = 'Credits rolled - PC sleeps in 45 minutes.'; Genre = 'Story'
            Seconds = 2700; Action = 'Sleep'; Mode = 'duration'
        }
        @{
            Id = 'bedtime'; Label = 'Bedtime'; Hint = '11:30 PM off'
            Title = 'Bedtime Protocol'; Tagline = 'Scheduled finale - shutdown at 11:30 PM.'; Genre = 'Scheduled'
            Action = 'Shutdown'; Mode = 'clock'; Clock = '23:30'
        }
    )
}

function Get-RitualGameById {
    param([string]$Id)
    if (-not $Id) { return $null }
    Get-RitualGameCatalog | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
}

function Resolve-SteamInt {
    param(
        $Value,
        [int]$Default = 0
    )
    if ($null -eq $Value) { return $Default }
    if ($Value -is [System.Array]) {
        $Value = @($Value | Select-Object -First 1)[0]
    }
    try {
        return [int]$Value
    } catch {
        return $Default
    }
}

function Get-SessionState {
    param(
        [bool]$Running,
        [bool]$Paused,
        [string]$TimerMode,
        [string]$Action,
        [int]$Left,
        [int]$Total,
        [int]$DefaultSec,
        [string]$LastRitualId,
        [string]$TimeStr,
        [string]$EndClock,
        [string]$EndLine,
        [string]$RemainFriendly,
        [string]$DurationLong,
        [string]$ClockDisplay,
        [string]$EventTitle,
        [int]$Streak = 0
    )
    $game = Get-RitualGameById $LastRitualId
    $gameName = if ($game) { $game.Title } else { 'Free Play - Custom Night' }
    $genre = if ($game) { $game.Genre } else { 'Custom' }

    if ($Running) {
        $pctDone = if ($Total -gt 0) { [int](100 * ($Total - $Left) / $Total) } else { 0 }
        $pctLeft = if ($Total -gt 0) { [int](100 * $Left / $Total) } else { 100 }
        return @{
            State       = 'ingame'
            Online      = 'In-Game'
            OnlineColor = 'Online'
            Header      = "PLAYING > $gameName"
            TrayHeader  = "$gameName - $TimeStr left"
            HeroTitle   = $gameName
            HeroTagline = "Session live - $pctDone% complete - ends $EndClock"
            Subtitle    = "In session - $($Action.ToLower()) in $TimeStr"
            RingHint    = $RemainFriendly
            RingSub     = if ($EndClock) { "Ends about $EndClock" } else { $RemainFriendly }
            PctLabel    = "Session progress - $pctLeft% left"
            StartText   = 'IN SESSION'
            FormTitle   = "Playing $gameName - $TimeStr"
        }
    }
    if ($Paused) {
        return @{
            State       = 'paused'
            Online      = 'Away'
            OnlineColor = 'Away'
            Header      = "PAUSED > $gameName"
            TrayHeader  = "Paused - $TimeStr remaining"
            HeroTitle   = $gameName
            HeroTagline = 'Session on hold - resume when you are ready.'
            Subtitle    = "Paused - $($Action.ToLower()) in $TimeStr"
            RingHint    = 'Press RESUME to continue your session'
            RingSub     = if ($EndClock) { "Ends about $EndClock" } else { 'Press RESUME to continue your session' }
            PctLabel    = 'Session paused'
            StartText   = "RESUME $TimeStr"
            FormTitle   = "Paused - $gameName"
        }
    }
    $streakLine = if ($Streak -gt 0) { " - $Streak-night streak" } else { '' }
    if ($TimerMode -eq 'clock') {
        return @{
            State       = 'lobby'
            Online      = 'Online'
            OnlineColor = 'Online'
            Header      = 'TONIGHT > Scheduled run'
            TrayHeader  = "Lobby - $ClockDisplay ($Action)"
            HeroTitle   = if ($game) { $game.Title } else { 'Tonight at ' + $ClockDisplay }
            HeroTagline = "$($Action.ToLower()) at $ClockDisplay - starts in $DurationLong$streakLine"
            Subtitle    = "Scheduled - $($Action.ToLower()) at $ClockDisplay"
            RingMain    = $ClockDisplay
            RingSub     = "At $ClockDisplay"
            RingHint    = "Starts in $DurationLong"
            PctLabel    = 'Not running - lobby'
            StartText   = "PLAY - $ClockDisplay"
            FormTitle   = "$script:AppName - Tonight"
        }
    }
    if ($TimerMode -eq 'calendar') {
        $ev = if ($EventTitle) { $EventTitle } else { 'Calendar event' }
        return @{
            State       = 'lobby'
            Online      = 'Online'
            OnlineColor = 'Online'
            Header      = 'TONIGHT > Calendar'
            TrayHeader  = "Lobby - $ev"
            HeroTitle   = $ev
            HeroTagline = "$ClockDisplay - $($Action.ToLower())$streakLine"
            Subtitle    = "Event - $($Action.ToLower()) at $ClockDisplay"
            RingMain    = $ClockDisplay
            RingSub     = "At $ClockDisplay"
            RingHint    = "Starts in $DurationLong"
            PctLabel    = 'Not running - lobby'
            StartText   = 'PLAY EVENT'
            FormTitle   = "$script:AppName - Event lobby"
        }
    }
    $dur = ([TimeSpan]::FromSeconds($DefaultSec)).ToString('mm\:ss')
    return @{
        State       = 'lobby'
        Online      = 'Online'
        OnlineColor = 'Online'
        Header      = 'LIBRARY > Pick a game'
        TrayHeader  = 'Lobby - choose a ritual and hit PLAY'
        HeroTitle   = if ($game) { $game.Title } else { 'Lights Out' }
        HeroTagline = if ($game) { $game.Tagline } else { 'Select a ritual below or set your own run.' }
        Subtitle    = 'Pick a ritual, then PLAY to start your night session'
        RingMain    = $dur
        RingSub     = if ($EndClock) { "Ends about $EndClock" } else { 'countdown length' }
        RingHint    = 'Lobby - press PLAY to start'
        PctLabel    = 'Not running - lobby'
        StartText   = "PLAY $dur"
        FormTitle   = "$script:AppName - Library"
    }
}

function Set-LightsOutTheme {
    param([ValidateSet('classic', 'steam')][string]$Name = 'classic')
    $script:UiTheme = $Name
    $script:UseSteamUi = ($Name -eq 'steam')
    # Replace whole palette (do not merge into an empty hashtable from parse-time defaults)
    $script:C = Get-LightsOutThemePalette -Name $Name
}

function Add-UiControl {
    param($Form, $Control, [switch]$NoOffset)
    if ($script:UseSteamUi -and -not $NoOffset -and $null -ne $Control.Location) {
        $Control.Location = New-Object System.Drawing.Point (
            ($Control.Location.X + $script:SteamPadX),
            ($Control.Location.Y + $script:SteamPadY))
    }
    [void]$Form.Controls.Add($Control)
}

function Get-SteamUiColor {
    param([string]$Name, [System.Drawing.Color]$Fallback)
    if ($script:C -and $script:C.ContainsKey($Name) -and $null -ne $script:C[$Name]) {
        return $script:C[$Name]
    }
    return $Fallback
}

function Reset-SteamHeroExtras {
    $heroWidth = Resolve-SteamInt $(if ($script:pnlSteamHero) { $script:pnlSteamHero.Width } else { $null }) 388
    if ($script:lblHeroKicker) { $script:lblHeroKicker.Visible = $false }
    if ($script:lblHeroEncourage) { $script:lblHeroEncourage.Visible = $false }
    if ($script:lblHeroStatLine) { $script:lblHeroStatLine.Visible = $false }
    if ($script:lblHeroDone) { $script:lblHeroDone.Visible = $false }
    if ($script:lblHeroTitle) {
        $script:lblHeroTitle.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
        $script:lblHeroTitle.Location = New-Object System.Drawing.Point(12, 12)
        $script:lblHeroTitle.Size = New-Object System.Drawing.Size(($heroWidth - 24), 22)
    }
}

function Add-SteamHeroPanel {
    param($Form, [int]$Y, [int]$Width = 388)
    $heroPanelW = Resolve-SteamInt $Width 388
    $heroWide = [int]($heroPanelW - 24)
    $heroStatWide = [int]($heroPanelW - 104)
    $heroDoneX = [int]($heroPanelW - 82)
    $script:pnlSteamHero = New-Object System.Windows.Forms.Panel
    $script:pnlSteamHero.Location = New-Object System.Drawing.Point(24, $Y)
    $script:pnlSteamHero.Size = New-Object System.Drawing.Size($heroPanelW, 72)
    $script:pnlSteamHero.BackColor = Get-SteamUiColor 'Card' ([System.Drawing.Color]::FromArgb(22, 32, 45))
    $script:pnlSteamHero.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $paintW = Resolve-SteamInt $s.Width 388
        $paintH = Resolve-SteamInt $s.Height 72
        $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush (
            (New-Object System.Drawing.Rectangle 0, 0, $paintW, $paintH),
            (Get-SteamUiColor 'HeroTop' ([System.Drawing.Color]::FromArgb(34, 48, 69))),
            (Get-SteamUiColor 'HeroBottom' ([System.Drawing.Color]::FromArgb(20, 28, 41))),
            90)
        $g.FillRectangle($grad, 0, 0, $paintW, $paintH)
        $grad.Dispose()
        $glow = Get-SteamUiColor 'Glow' ([System.Drawing.Color]::FromArgb(102, 192, 244))
        $glowBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(24, $glow.R, $glow.G, $glow.B))
        $g.FillEllipse($glowBrush, ($paintW - 124), -42, 148, 116)
        $glowBrush.Dispose()
        $border = Get-SteamUiColor 'Border' ([System.Drawing.Color]::FromArgb(42, 71, 94))
        $outer = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(28, $glow.R, $glow.G, $glow.B)), 1
        $g.DrawRectangle($outer, 1, 1, $paintW - 3, $paintH - 3)
        $outer.Dispose()
        $pen = New-Object System.Drawing.Pen $border
        $g.DrawRectangle($pen, 0, 0, $paintW - 1, $paintH - 1)
        $pen.Dispose()
        $accent = New-Object System.Drawing.Pen (Get-SteamUiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))), 3
        $g.DrawLine($accent, 0, 0, 0, $paintH)
        $accent.Dispose()
    })

    $script:lblHeroKicker = New-Object System.Windows.Forms.Label
    $script:lblHeroKicker.Location = New-Object System.Drawing.Point(12, 6)
    $script:lblHeroKicker.Size = New-Object System.Drawing.Size(160, 14)
    $script:lblHeroKicker.Font = New-Object System.Drawing.Font('Segoe UI', 7.5, [System.Drawing.FontStyle]::Bold)
    $script:lblHeroKicker.ForeColor = Get-SteamUiColor 'Amber' ([System.Drawing.Color]::FromArgb(164, 208, 7))
    $script:lblHeroKicker.BackColor = Get-SteamUiColor 'Card' ([System.Drawing.Color]::FromArgb(22, 32, 45))
    $script:lblHeroKicker.Visible = $false
    $script:pnlSteamHero.Controls.Add($script:lblHeroKicker)

    $script:lblHeroTitle = New-Object System.Windows.Forms.Label
    $script:lblHeroTitle.Location = New-Object System.Drawing.Point(12, 12)
    $script:lblHeroTitle.Size = New-Object System.Drawing.Size($heroWide, 22)
    $script:lblHeroTitle.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
    $script:lblHeroTitle.ForeColor = Get-SteamUiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
    $script:lblHeroTitle.BackColor = Get-SteamUiColor 'Card' ([System.Drawing.Color]::FromArgb(22, 32, 45))
    $script:pnlSteamHero.Controls.Add($script:lblHeroTitle)

    $script:lblHeroTag = New-Object System.Windows.Forms.Label
    $script:lblHeroTag.Location = New-Object System.Drawing.Point(12, 38)
    $script:lblHeroTag.Size = New-Object System.Drawing.Size($heroWide, 18)
    $script:lblHeroTag.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
    $script:lblHeroTag.ForeColor = Get-SteamUiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
    $script:lblHeroTag.BackColor = Get-SteamUiColor 'Card' ([System.Drawing.Color]::FromArgb(22, 32, 45))
    $script:pnlSteamHero.Controls.Add($script:lblHeroTag)

    $script:lblHeroDetail = New-Object System.Windows.Forms.Label
    $script:lblHeroDetail.Location = New-Object System.Drawing.Point(12, 54)
    $script:lblHeroDetail.Size = New-Object System.Drawing.Size($heroWide, 18)
    $script:lblHeroDetail.Font = New-Object System.Drawing.Font('Segoe UI', 7.5)
    $script:lblHeroDetail.ForeColor = Get-SteamUiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))
    $script:lblHeroDetail.BackColor = Get-SteamUiColor 'Card' ([System.Drawing.Color]::FromArgb(22, 32, 45))
    $script:lblHeroDetail.Visible = $false
    $script:pnlSteamHero.Controls.Add($script:lblHeroDetail)

    $script:lblHeroStatLine = New-Object System.Windows.Forms.Label
    $script:lblHeroStatLine.Location = New-Object System.Drawing.Point(12, 54)
    $script:lblHeroStatLine.Size = New-Object System.Drawing.Size($heroStatWide, 16)
    $script:lblHeroStatLine.Font = New-Object System.Drawing.Font('Segoe UI', 7.5)
    $script:lblHeroStatLine.ForeColor = Get-SteamUiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
    $script:lblHeroStatLine.BackColor = Get-SteamUiColor 'Card' ([System.Drawing.Color]::FromArgb(22, 32, 45))
    $script:lblHeroStatLine.Visible = $false
    $script:pnlSteamHero.Controls.Add($script:lblHeroStatLine)

    $script:lblHeroDone = New-Object System.Windows.Forms.Label
    $script:lblHeroDone.Location = New-Object System.Drawing.Point($heroDoneX, 22)
    $script:lblHeroDone.Size = New-Object System.Drawing.Size(70, 20)
    $script:lblHeroDone.Text = 'DONE'
    $script:lblHeroDone.TextAlign = 'MiddleCenter'
    $script:lblHeroDone.Font = New-Object System.Drawing.Font('Segoe UI', 7, [System.Drawing.FontStyle]::Bold)
    $script:lblHeroDone.ForeColor = Get-SteamUiColor 'Online' ([System.Drawing.Color]::FromArgb(87, 192, 87))
    $script:lblHeroDone.BackColor = Get-SteamUiColor 'SuccessSoft' ([System.Drawing.Color]::FromArgb(24, 48, 32))
    $script:lblHeroDone.Visible = $false
    $script:pnlSteamHero.Controls.Add($script:lblHeroDone)

    $script:lblHeroEncourage = New-Object System.Windows.Forms.Label
    $script:lblHeroEncourage.Location = New-Object System.Drawing.Point(12, 56)
    $script:lblHeroEncourage.Size = New-Object System.Drawing.Size($heroWide, 16)
    $script:lblHeroEncourage.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $script:lblHeroEncourage.ForeColor = Get-SteamUiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
    $script:lblHeroEncourage.BackColor = Get-SteamUiColor 'Card' ([System.Drawing.Color]::FromArgb(22, 32, 45))
    $script:lblHeroEncourage.Visible = $false
    $script:pnlSteamHero.Controls.Add($script:lblHeroEncourage)

    Add-UiControl -Form $Form -Control $script:pnlSteamHero
}

function Update-SteamOnlineBadge {
    param([hashtable]$Session)
    if (-not $script:pnlSteamOnline) { return }
    $color = switch ($Session.OnlineColor) {
        'Online' { Get-SteamUiColor 'Online' ([System.Drawing.Color]::FromArgb(87, 192, 87)) }
        default { Get-SteamUiColor 'Away' ([System.Drawing.Color]::FromArgb(139, 152, 165)) }
    }
    $script:pnlSteamOnline.BackColor = $color
    if ($script:lblSteamOnline) {
        $script:lblSteamOnline.ForeColor = $color
        $script:lblSteamOnline.Text = $Session.Online.ToUpper()
    }
}

function Update-SteamExperience {
    param([hashtable]$Session)
    Reset-SteamHeroExtras
    if ($script:lblHeroTitle) { $script:lblHeroTitle.Text = $Session.HeroTitle }
    if ($script:lblHeroTag) {
        $script:lblHeroTag.Text = $Session.HeroTagline
        $script:lblHeroTag.Visible = $true
    }
    if ($script:lblHeroDetail) { $script:lblHeroDetail.Visible = $false }
    Update-SteamHeaderStatus $Session.Header
    Update-SteamOnlineBadge $Session
    if ($script:lblSteamStatus) {
        $script:lblSteamStatus.Text = if ($Session.State -eq 'ingame') { "PLAYING > $($Session.HeroTitle)" } else { $Session.Header }
    }
}

function Set-SteamTrayMenuStyle {
    param($Menu)
    if (-not $script:UseSteamUi) { return }
    $Menu.BackColor = Get-SteamUiColor 'Sidebar' ([System.Drawing.Color]::FromArgb(23, 26, 33))
    $Menu.ForeColor = Get-SteamUiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
    $Menu.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $Menu.ShowImageMargin = $false
    foreach ($item in $Menu.Items) {
        if ($item -is [System.Windows.Forms.ToolStripMenuItem]) {
            $item.BackColor = Get-SteamUiColor 'Sidebar' ([System.Drawing.Color]::FromArgb(23, 26, 33))
            $item.ForeColor = Get-SteamUiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
            if ($item.Tag -eq 'header') {
                $item.ForeColor = Get-SteamUiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))
                $item.Font = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Bold)
            }
        }
    }
}

function New-SteamTrayMenu {
    param(
        [scriptblock]$OnShow,
        [scriptblock]$OnSnooze10,
        [scriptblock]$OnSnooze5,
        [scriptblock]$OnPause,
        [scriptblock]$OnCancel,
        [scriptblock]$OnStats,
        [scriptblock]$OnBigPicture = $null,
        [scriptblock]$OnExit
    )
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $script:trayHeaderItem = $menu.Items.Add('Lights Out - Lobby')
    $script:trayHeaderItem.Tag = 'header'
    $script:trayHeaderItem.Enabled = $false
    [void]$menu.Items.Add('-')
    [void]$menu.Items.Add('Open Library', $null, $OnShow)
    [void]$menu.Items.Add('+10 min', $null, $OnSnooze10)
    [void]$menu.Items.Add('+5 min', $null, $OnSnooze5)
    $script:trayPauseItem = $menu.Items.Add('Pause session', $null, $OnPause)
    [void]$menu.Items.Add('End session', $null, $OnCancel)
    [void]$menu.Items.Add('-')
    [void]$menu.Items.Add('View stats', $null, $OnStats)
    if ($OnBigPicture) { [void]$menu.Items.Add('Cinema mode', $null, $OnBigPicture) }
    [void]$menu.Items.Add('-')
    [void]$menu.Items.Add('Exit', $null, $OnExit)
    Set-SteamTrayMenuStyle $menu
    return $menu
}

function Update-SteamTrayHeader {
    param([string]$Text)
    if ($script:trayHeaderItem) {
        $t = $Text
        if ($t.Length -gt 48) { $t = $t.Substring(0, 48) }
        $script:trayHeaderItem.Text = $t
    }
}

function Update-SteamHeaderStatus {
    param([string]$Text)
    if ($script:lblSteamStatus) { $script:lblSteamStatus.Text = $Text }
}

function Set-SteamNavHighlight {
    param([ValidateSet('library', 'schedule', 'settings')][string]$Page)
    if (-not $script:SteamNavBtns) { return }
    foreach ($pair in $script:SteamNavBtns.GetEnumerator()) {
        $on = ($pair.Key -eq $Page)
        $btn = $pair.Value
        if ($on) {
            $btn.BackColor = Get-SteamUiColor 'NavOn' ([System.Drawing.Color]::FromArgb(62, 126, 167))
            $btn.ForeColor = Get-SteamUiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
            $btn.FlatAppearance.BorderSize = 1
            $btn.FlatAppearance.BorderColor = Get-SteamUiColor 'Glow' ([System.Drawing.Color]::FromArgb(110, 198, 255))
        } else {
            $btn.BackColor = Get-SteamUiColor 'Sidebar' ([System.Drawing.Color]::FromArgb(23, 26, 33))
            $btn.ForeColor = Get-SteamUiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
            $btn.FlatAppearance.BorderSize = 0
        }
    }
}

function Add-SteamFormChrome {
    param(
        $Form,
        [int]$FormW,
        [string]$AppVersion = '',
        [scriptblock]$OnLibrary,
        [scriptblock]$OnSchedule,
        [scriptblock]$OnSettings,
        [scriptblock]$OnStats = $null
    )
    $FormW = Resolve-SteamInt $FormW 480
    $script:SteamPadX = 72
    $script:SteamPadY = 50
    $navTip = New-Object System.Windows.Forms.ToolTip
    $navTip.InitialDelay = 300
    $navTip.AutoPopDelay = 6000

    $side = New-Object System.Windows.Forms.Panel
    $side.Name = 'pnlSteamSide'
    $side.Location = New-Object System.Drawing.Point(0, 0)
    $side.Size = New-Object System.Drawing.Size($script:SteamPadX, $Form.Height)
    $side.BackColor = Get-SteamUiColor 'Sidebar' ([System.Drawing.Color]::FromArgb(23, 26, 33))
    $side.Add_Paint({
        param($sender, $e)
        $g = $e.Graphics
        $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush (
            (New-Object System.Drawing.Rectangle 0, 0, $sender.Width, $sender.Height),
            (Get-SteamUiColor 'Sidebar' ([System.Drawing.Color]::FromArgb(23, 26, 33))),
            (Get-SteamUiColor 'Header' ([System.Drawing.Color]::FromArgb(23, 26, 33))),
            90)
        $g.FillRectangle($grad, 0, 0, $sender.Width, $sender.Height)
        $grad.Dispose()
        $edge = New-Object System.Drawing.Pen (Get-SteamUiColor 'Border' ([System.Drawing.Color]::FromArgb(42, 71, 94)))
        $g.DrawLine($edge, ($sender.Width - 1), 0, ($sender.Width - 1), $sender.Height)
        $edge.Dispose()
    })
    [void]$Form.Controls.Add($side)

    $navY = 8
    $script:SteamNavBtns = @{}
    foreach ($nav in @(
        @{ Id = 'library'; Label = 'HOME'; Tip = 'Rituals, countdown, and tonight cards' }
        @{ Id = 'schedule'; Label = 'PLAN'; Tip = 'Tonight, clock, calendar, and saved runs' }
        @{ Id = 'settings'; Label = 'POWER'; Tip = 'Power action, tray, and finale settings' }
    )) {
        $nb = New-Object System.Windows.Forms.Button
        $nb.Text = $nav.Label
        $nb.Size = New-Object System.Drawing.Size(60, 40)
        $nb.Location = New-Object System.Drawing.Point(6, $navY)
        $nb.FlatStyle = 'Flat'
        $nb.FlatAppearance.BorderSize = 0
        $nb.Font = New-Object System.Drawing.Font('Segoe UI', 7.5, [System.Drawing.FontStyle]::Bold)
        $nb.Cursor = [System.Windows.Forms.Cursors]::Hand
        $nb.TextAlign = 'MiddleCenter'
        $navId = $nav.Id
        $nb.Add_Click({
            Set-SteamNavHighlight -Page $navId
            switch ($navId) {
                'library' { if ($OnLibrary) { & $OnLibrary } }
                'schedule' { if ($OnSchedule) { & $OnSchedule } }
                'settings' { if ($OnSettings) { & $OnSettings } }
            }
        }.GetNewClosure())
        [void]$side.Controls.Add($nb)
        $navTip.SetToolTip($nb, $nav.Tip)
        $script:SteamNavBtns[$nav.Id] = $nb
        $navY += 46
    }
    Set-SteamNavHighlight -Page 'library'

    $hdr = New-Object System.Windows.Forms.Panel
    $hdr.Name = 'pnlSteamHeader'
    $hdr.Location = New-Object System.Drawing.Point($script:SteamPadX, 0)
    $hdr.Size = New-Object System.Drawing.Size(($FormW + $script:SteamPadX - 2), $script:SteamPadY)
    $hdr.BackColor = Get-SteamUiColor 'Header' ([System.Drawing.Color]::FromArgb(23, 26, 33))
    $hdr.Anchor = 'Top, Left, Right'
    $hdr.Add_Paint({
        param($sender, $e)
        $g = $e.Graphics
        $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush (
            (New-Object System.Drawing.Rectangle 0, 0, $sender.Width, $sender.Height),
            (Get-SteamUiColor 'HeaderTop' ([System.Drawing.Color]::FromArgb(28, 37, 53))),
            (Get-SteamUiColor 'HeaderBottom' ([System.Drawing.Color]::FromArgb(13, 18, 28))),
            90)
        $g.FillRectangle($grad, 0, 0, $sender.Width, $sender.Height)
        $grad.Dispose()
        $glow = Get-SteamUiColor 'Glow' ([System.Drawing.Color]::FromArgb(102, 192, 244))
        $glowBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(18, $glow.R, $glow.G, $glow.B))
        $g.FillEllipse($glowBrush, ($sender.Width - 170), -28, 190, 100)
        $glowBrush.Dispose()
    })
    [void]$Form.Controls.Add($hdr)
    $hdr.BringToFront() | Out-Null

    $hdrWidth = Resolve-SteamInt $hdr.Width ($FormW + $script:SteamPadX)
    $brandW = [math]::Max(180, ($hdrWidth - 140))
    $brandX = [int](($hdrWidth - $brandW) / 2)

    $script:lblSteamBrand = New-Object System.Windows.Forms.Label
    $script:lblSteamBrand.Text = 'Lights Out'
    $script:lblSteamBrand.Location = New-Object System.Drawing.Point($brandX, 4)
    $script:lblSteamBrand.Size = New-Object System.Drawing.Size($brandW, 18)
    $script:lblSteamBrand.TextAlign = 'MiddleCenter'
    $script:lblSteamBrand.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
    $script:lblSteamBrand.ForeColor = Get-SteamUiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
    $script:lblSteamBrand.BackColor = Get-SteamUiColor 'Header' ([System.Drawing.Color]::FromArgb(23, 26, 33))
    $script:lblSteamBrand.Anchor = 'Top, Left, Right'
    [void]$hdr.Controls.Add($script:lblSteamBrand)

    $script:lblSteamBrandSub = New-Object System.Windows.Forms.Label
    $script:lblSteamBrandSub.Text = 'Sleep ritual control for Windows'
    $script:lblSteamBrandSub.Location = New-Object System.Drawing.Point($brandX, 22)
    $script:lblSteamBrandSub.Size = New-Object System.Drawing.Size($brandW, 14)
    $script:lblSteamBrandSub.TextAlign = 'MiddleCenter'
    $script:lblSteamBrandSub.Font = New-Object System.Drawing.Font('Segoe UI', 7.5)
    $script:lblSteamBrandSub.ForeColor = Get-SteamUiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))
    $script:lblSteamBrandSub.BackColor = Get-SteamUiColor 'Header' ([System.Drawing.Color]::FromArgb(23, 26, 33))
    $script:lblSteamBrandSub.Anchor = 'Top, Left, Right'
    [void]$hdr.Controls.Add($script:lblSteamBrandSub)

    $script:pnlSteamOnline = New-Object System.Windows.Forms.Panel
    $script:pnlSteamOnline.Size = New-Object System.Drawing.Size(8, 8)
    $script:pnlSteamOnline.Location = New-Object System.Drawing.Point(8, 20)
    $script:pnlSteamOnline.BackColor = Get-SteamUiColor 'Online' ([System.Drawing.Color]::FromArgb(87, 192, 87))
    [void]$hdr.Controls.Add($script:pnlSteamOnline)

    $script:lblSteamOnline = New-Object System.Windows.Forms.Label
    $script:lblSteamOnline.Text = 'ONLINE'
    $script:lblSteamOnline.Location = New-Object System.Drawing.Point(18, 16)
    $script:lblSteamOnline.AutoSize = $true
    $script:lblSteamOnline.Font = New-Object System.Drawing.Font('Segoe UI', 7, [System.Drawing.FontStyle]::Bold)
    $script:lblSteamOnline.ForeColor = Get-SteamUiColor 'Online' ([System.Drawing.Color]::FromArgb(87, 192, 87))
    $script:lblSteamOnline.BackColor = Get-SteamUiColor 'Header' ([System.Drawing.Color]::FromArgb(23, 26, 33))
    [void]$hdr.Controls.Add($script:lblSteamOnline)

    $script:lblSteamStatus = New-Object System.Windows.Forms.Label
    $script:lblSteamStatus.Text = 'LIBRARY > Pick a game'
    $script:lblSteamStatus.Location = New-Object System.Drawing.Point(8, 36)
    $script:lblSteamStatus.Size = New-Object System.Drawing.Size(280, 14)
    $script:lblSteamStatus.Font = New-Object System.Drawing.Font('Segoe UI', 7.5)
    $script:lblSteamStatus.ForeColor = Get-SteamUiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
    $script:lblSteamStatus.BackColor = Get-SteamUiColor 'Header' ([System.Drawing.Color]::FromArgb(23, 26, 33))
    [void]$hdr.Controls.Add($script:lblSteamStatus)

    if ($AppVersion) {
        $script:lblSteamVer = New-Object System.Windows.Forms.Label
        $script:lblSteamVer.Text = "v$AppVersion"
        $script:lblSteamVer.AutoSize = $true
        $script:lblSteamVer.Location = New-Object System.Drawing.Point(($hdrWidth - 118), 10)
        $script:lblSteamVer.Font = New-Object System.Drawing.Font('Segoe UI', 7.5)
        $script:lblSteamVer.ForeColor = Get-SteamUiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
        $script:lblSteamVer.BackColor = Get-SteamUiColor 'Header' ([System.Drawing.Color]::FromArgb(23, 26, 33))
        $script:lblSteamVer.Anchor = 'Top, Right'
        [void]$hdr.Controls.Add($script:lblSteamVer)
    }

    $script:lnkSteamStats = New-Object System.Windows.Forms.LinkLabel
    $script:lnkSteamStats.Text = 'STATS'
    $script:lnkSteamStats.AutoSize = $true
    $script:lnkSteamStats.Location = New-Object System.Drawing.Point(($hdrWidth - 168), 9)
    $script:lnkSteamStats.Font = New-Object System.Drawing.Font('Segoe UI', 7.5, [System.Drawing.FontStyle]::Bold)
    $script:lnkSteamStats.LinkColor = Get-SteamUiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))
    $script:lnkSteamStats.ActiveLinkColor = Get-SteamUiColor 'Amber' ([System.Drawing.Color]::FromArgb(164, 208, 7))
    $script:lnkSteamStats.BackColor = Get-SteamUiColor 'Header' ([System.Drawing.Color]::FromArgb(23, 26, 33))
    $script:lnkSteamStats.Anchor = 'Top, Right'
    if ($OnStats) { $script:lnkSteamStats.Add_Click({ & $OnStats }) }
    [void]$hdr.Controls.Add($script:lnkSteamStats)

    $user = $env:USERNAME
    if ($user.Length -gt 8) { $user = $user.Substring(0, 8) }
    $lblUser = New-Object System.Windows.Forms.Label
    $lblUser.Text = $user.ToUpper()
    $lblUser.Location = New-Object System.Drawing.Point(($hdrWidth - 52), 8)
    $lblUser.Size = New-Object System.Drawing.Size(44, 18)
    $lblUser.TextAlign = 'MiddleCenter'
    $lblUser.Font = New-Object System.Drawing.Font('Segoe UI', 8)
    $lblUser.ForeColor = Get-SteamUiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
    $lblUser.BackColor = Get-SteamUiColor 'AccentSoft' ([System.Drawing.Color]::FromArgb(30, 77, 110))
    $lblUser.Anchor = 'Top, Right'
    [void]$hdr.Controls.Add($lblUser)

    $line = New-Object System.Windows.Forms.Panel
    $line.Location = New-Object System.Drawing.Point($script:SteamPadX, ($script:SteamPadY - 1))
    $line.Size = New-Object System.Drawing.Size(($FormW + $script:SteamPadX), 1)
    $line.BackColor = Get-SteamUiColor 'Border' ([System.Drawing.Color]::FromArgb(42, 71, 94))
    $line.Anchor = 'Top, Left, Right'
    [void]$Form.Controls.Add($line)
}

function Add-SteamSleepClearancePanel {
    param(
        $Form,
        [int]$Y,
        [int]$Width
    )
    $Width = Resolve-SteamInt $Width 388
    $script:pnlSleepClearance = New-Object System.Windows.Forms.Panel
    $script:pnlSleepClearance.Name = 'pnlSleepClearance'
    $script:pnlSleepClearance.Location = New-Object System.Drawing.Point(24, $Y)
    $script:pnlSleepClearance.Size = New-Object System.Drawing.Size($Width, 40)
    $script:pnlSleepClearance.BackColor = Get-SteamUiColor 'Card' ([System.Drawing.Color]::FromArgb(22, 32, 45))
    $script:pnlSleepClearance.Visible = $false
    $script:pnlSleepClearance.Add_Paint({
        param($sender, $e)
        $g = $e.Graphics
        $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush (
            (New-Object System.Drawing.Rectangle 0, 0, $sender.Width, $sender.Height),
            (Get-SteamUiColor 'Card' ([System.Drawing.Color]::FromArgb(22, 32, 45))),
            (Get-SteamUiColor 'Elevated' ([System.Drawing.Color]::FromArgb(42, 71, 94))),
            90)
        $g.FillRectangle($grad, 0, 0, $sender.Width, $sender.Height)
        $grad.Dispose()
        $pen = New-Object System.Drawing.Pen (Get-SteamUiColor 'Border' ([System.Drawing.Color]::FromArgb(42, 71, 94)))
        $g.DrawRectangle($pen, 0, 0, $sender.Width - 1, $sender.Height - 1)
        $pen.Dispose()
    })

    $script:lblClearanceHead = New-Object System.Windows.Forms.Label
    $script:lblClearanceHead.Location = New-Object System.Drawing.Point(10, 4)
    $script:lblClearanceHead.Size = New-Object System.Drawing.Size(($Width - 20), 14)
    $script:lblClearanceHead.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
    $script:lblClearanceHead.ForeColor = Get-SteamUiColor 'Online' ([System.Drawing.Color]::FromArgb(87, 192, 87))
    $script:lblClearanceHead.BackColor = Get-SteamUiColor 'Card' ([System.Drawing.Color]::FromArgb(22, 32, 45))
    $script:pnlSleepClearance.Controls.Add($script:lblClearanceHead)

    $script:lblClearanceSub = New-Object System.Windows.Forms.Label
    $script:lblClearanceSub.Location = New-Object System.Drawing.Point(10, 20)
    $script:lblClearanceSub.Size = New-Object System.Drawing.Size(($Width - 20), 14)
    $script:lblClearanceSub.Font = New-Object System.Drawing.Font('Segoe UI', 7.5)
    $script:lblClearanceSub.ForeColor = Get-SteamUiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
    $script:lblClearanceSub.BackColor = Get-SteamUiColor 'Card' ([System.Drawing.Color]::FromArgb(22, 32, 45))
    $script:pnlSleepClearance.Controls.Add($script:lblClearanceSub)

    Add-UiControl -Form $Form -Control $script:pnlSleepClearance
}

function Update-SteamTonightPreviewHero {
    param(
        $Preview,
        [bool]$Active
    )
    if (-not $script:pnlSteamHero) { return }
    $heroWidth = Resolve-SteamInt $script:pnlSteamHero.Width 388
    if (-not $Active -or -not $Preview) {
        $script:pnlSteamHero.Height = 72
        Reset-SteamHeroExtras
        if ($script:lblHeroDetail) { $script:lblHeroDetail.Visible = $false }
        if ($script:lblHeroTitle) {
            $script:lblHeroTitle.ForeColor = Get-SteamUiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
            $script:lblHeroTitle.Location = New-Object System.Drawing.Point(12, 12)
        }
        return
    }

    Reset-SteamHeroExtras
    $script:pnlSteamHero.Height = 112
    if ($script:lblHeroKicker) {
        $script:lblHeroKicker.Text = [string]$Preview.Title
        $script:lblHeroKicker.Visible = $true
    }
    if ($script:lblHeroTitle) {
        $script:lblHeroTitle.ForeColor = Get-SteamUiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
        $script:lblHeroTitle.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
        $script:lblHeroTitle.Location = New-Object System.Drawing.Point(12, 24)
        $script:lblHeroTitle.Size = New-Object System.Drawing.Size(($heroWidth - 106), 22)
        $script:lblHeroTitle.Text = [string]$Preview.Tagline
    }
    if ($script:lblHeroTag) { $script:lblHeroTag.Visible = $false }
    if ($script:lblHeroStatLine) {
        $script:lblHeroStatLine.Location = New-Object System.Drawing.Point(12, 54)
        $script:lblHeroStatLine.Text = [string]$Preview.MetricLine
        $script:lblHeroStatLine.Visible = ([string]$Preview.MetricLine).Length -gt 0
    }
    if ($script:lblHeroDetail) {
        $script:lblHeroDetail.Location = New-Object System.Drawing.Point(12, 74)
        $script:lblHeroDetail.Text = [string]$Preview.DetailLine
        $script:lblHeroDetail.Visible = ([string]$Preview.DetailLine).Length -gt 0
    }
    if ($script:lblHeroDone) {
        $script:lblHeroDone.Text = if ($Preview.BadgeText) { [string]$Preview.BadgeText } else { 'READY' }
        $script:lblHeroDone.BackColor = if ($script:lblHeroDone.Text -eq 'CHECK') {
            Get-SteamUiColor 'DangerSoft' ([System.Drawing.Color]::FromArgb(72, 40, 48))
        } else {
            Get-SteamUiColor 'SuccessSoft' ([System.Drawing.Color]::FromArgb(24, 56, 46))
        }
        $script:lblHeroDone.ForeColor = Get-SteamUiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
        $script:lblHeroDone.Visible = $true
    }
    if ($Preview.Header) { Update-SteamHeaderStatus ([string]$Preview.Header) }
    $script:pnlSteamHero.Invalidate()
}

function Add-SteamTrustBadgesPanel {
    param(
        $Form,
        [int]$Y,
        [int]$Width
    )
    $Width = Resolve-SteamInt $Width 388
    $script:pnlTrustBadges = New-Object System.Windows.Forms.Panel
    $script:pnlTrustBadges.Name = 'pnlTrustBadges'
    $script:pnlTrustBadges.Location = New-Object System.Drawing.Point(12, $Y)
    $script:pnlTrustBadges.Size = New-Object System.Drawing.Size(($Width + 24), 56)
    $script:pnlTrustBadges.BackColor = Get-SteamUiColor 'Bg' ([System.Drawing.Color]::FromArgb(27, 40, 56))
    $script:pnlTrustBadges.Visible = $false

    $script:SteamTrustCards = @()
    for ($i = 0; $i -lt 5; $i++) {
        $card = New-Object System.Windows.Forms.Panel
        $card.Visible = $false
        $card.BackColor = Get-SteamUiColor 'Card' ([System.Drawing.Color]::FromArgb(22, 32, 45))
        $card.Add_Paint({
            param($sender, $e)
            $g = $e.Graphics
            $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush (
                (New-Object System.Drawing.Rectangle 0, 0, $sender.Width, $sender.Height),
                (Get-SteamUiColor 'Card' ([System.Drawing.Color]::FromArgb(22, 32, 45))),
                (Get-SteamUiColor 'Elevated' ([System.Drawing.Color]::FromArgb(42, 71, 94))),
                90)
            $g.FillRectangle($grad, 0, 0, $sender.Width, $sender.Height)
            $grad.Dispose()
            $pen = New-Object System.Drawing.Pen (Get-SteamUiColor 'Border' ([System.Drawing.Color]::FromArgb(42, 71, 94)))
            $g.DrawRectangle($pen, 0, 0, $sender.Width - 1, $sender.Height - 1)
            $pen.Dispose()
        })
        $title = New-Object System.Windows.Forms.Label
        $title.Location = New-Object System.Drawing.Point(3, 6)
        $title.Size = New-Object System.Drawing.Size(78, 14)
        $title.AutoEllipsis = $true
        $title.Font = New-Object System.Drawing.Font('Segoe UI', 6.5, [System.Drawing.FontStyle]::Bold)
        $title.ForeColor = Get-SteamUiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))
        $title.BackColor = Get-SteamUiColor 'Card' ([System.Drawing.Color]::FromArgb(22, 32, 45))
        $sub = New-Object System.Windows.Forms.Label
        $sub.Location = New-Object System.Drawing.Point(3, 22)
        $sub.Size = New-Object System.Drawing.Size(78, 26)
        $sub.Font = New-Object System.Drawing.Font('Segoe UI', 6.5)
        $sub.ForeColor = Get-SteamUiColor 'Muted' ([System.Drawing.Color]::FromArgb(139, 152, 165))
        $sub.BackColor = Get-SteamUiColor 'Card' ([System.Drawing.Color]::FromArgb(22, 32, 45))
        [void]$card.Controls.Add($title)
        [void]$card.Controls.Add($sub)
        [void]$script:pnlTrustBadges.Controls.Add($card)
        $script:SteamTrustCards += ,@($card, $title, $sub)
    }

    Add-UiControl -Form $Form -Control $script:pnlTrustBadges
}

function Update-SteamTrustBadgesPanel {
    param(
        [bool]$Visible,
        [bool]$DryRun = $false,
        [bool]$DemoMode = $false
    )
    if (-not $script:pnlTrustBadges) { return }
    $defs = [System.Collections.Generic.List[object]]::new()
    if ($DemoMode) {
        $defs.Add(@{ T = 'DEMO MODE'; S = 'Safe preview only'; W = $false })
    }
    if ($DryRun -or $DemoMode) {
        $defs.Add(@{ T = 'DRY-RUN SAFE'; S = 'No real shutdown'; W = $false })
    }
    $defs.Add(@{ T = 'LOCAL ONLY'; S = 'Everything stays on this PC'; W = $false })
    $defs.Add(@{ T = 'CONFIRM'; S = 'You confirm first'; W = $false })
    $defs.Add(@{ T = 'CANCEL'; S = 'Stop at any time'; W = $true })
    $defs.Add(@{ T = 'NO CLOUD'; S = 'No accounts. No tracking.'; W = $false })

    $show = @($defs | Select-Object -First 5)
    $gap = 4
    $panelWidth = Resolve-SteamInt $script:pnlTrustBadges.Width 388
    $cardW = [math]::Max(72, [int](($panelWidth - ($gap * ([math]::Max(0, ($show.Count - 1))))) / [math]::Max(1, $show.Count)))
    $x = 0
    for ($i = 0; $i -lt $script:SteamTrustCards.Count; $i++) {
        $entry = $script:SteamTrustCards[$i]
        $card = $entry[0]
        $title = $entry[1]
        $sub = $entry[2]
        if ($i -lt $show.Count) {
            $def = $show[$i]
            $title.Text = [string]$def.T
            $title.ForeColor = if ($def.W) {
                Get-SteamUiColor 'Amber' ([System.Drawing.Color]::FromArgb(164, 208, 7))
            } else {
                Get-SteamUiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244))
            }
            $sub.Text = [string]$def.S
            $card.Location = New-Object System.Drawing.Point($x, 0)
            $card.Size = New-Object System.Drawing.Size($cardW, 54)
            $title.Width = ($cardW - 6)
            $sub.Width = ($cardW - 6)
            $card.Visible = $true
            $x += ($cardW + $gap)
        } else {
            $card.Visible = $false
        }
    }
    $script:pnlTrustBadges.Visible = $Visible
}

function Update-SteamSleepClearancePanel {
    param(
        $Report,
        [bool]$Visible
    )
    if (-not $script:pnlSleepClearance) { return }
    $script:pnlSleepClearance.Visible = $Visible
    if (-not $Visible -or -not $Report) { return }

    $clear = ($Report.Status -eq 'Clear')
    $headColor = if ($clear) {
        Get-SteamUiColor 'Online' ([System.Drawing.Color]::FromArgb(87, 192, 87))
    } else {
        Get-SteamUiColor 'Amber' ([System.Drawing.Color]::FromArgb(164, 208, 7))
    }
    $script:lblClearanceHead.ForeColor = $headColor
    $script:lblClearanceHead.Text = [string]$Report.Headline
    $script:lblClearanceSub.Text = [string]$Report.Subtitle
    $script:pnlSleepClearance.Invalidate()
}

function Add-SteamMorningProofActions {
    param(
        $Form,
        [int]$Y,
        [int]$Width,
        [scriptblock]$OnLedger,
        [scriptblock]$OnDismiss
    )
    $half = [int](($Width - 8) / 2)
    $script:btnMorningLedger = New-Object System.Windows.Forms.Button
    $script:btnMorningLedger.Text = 'VIEW LEDGER'
    $script:btnMorningLedger.Location = New-Object System.Drawing.Point(24, $Y)
    $script:btnMorningLedger.Size = New-Object System.Drawing.Size($half, 32)
    $script:btnMorningLedger.Visible = $false
    Style-SteamMorningProofButton $script:btnMorningLedger
    $script:btnMorningLedger.Add_Click($OnLedger)
    Add-UiControl -Form $Form -Control $script:btnMorningLedger

    $script:btnMorningDismiss = New-Object System.Windows.Forms.Button
    $script:btnMorningDismiss.Text = 'DISMISS'
    $script:btnMorningDismiss.Location = New-Object System.Drawing.Point((24 + $half + 8), $Y)
    $script:btnMorningDismiss.Size = New-Object System.Drawing.Size($half, 32)
    $script:btnMorningDismiss.Visible = $false
    Style-SteamMorningProofButton $script:btnMorningDismiss
    $script:btnMorningDismiss.Add_Click($OnDismiss)
    Add-UiControl -Form $Form -Control $script:btnMorningDismiss
}

function Style-SteamMorningProofButton {
    param($Button)
    $Button.FlatStyle = 'Flat'
    $Button.FlatAppearance.BorderSize = 1
    $Button.FlatAppearance.BorderColor = Get-SteamUiColor 'Border' ([System.Drawing.Color]::FromArgb(42, 71, 94))
    $Button.BackColor = Get-SteamUiColor 'Elevated' ([System.Drawing.Color]::FromArgb(42, 71, 94))
    $Button.ForeColor = Get-SteamUiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224))
    $Button.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
}

function Update-SteamMorningProofHero {
    param(
        $Report,
        [bool]$Active
    )
    if (-not $script:pnlSteamHero) { return }
    $heroWidth = Resolve-SteamInt $script:pnlSteamHero.Width 388
    if (-not $Active -or -not $Report) {
        $script:pnlSteamHero.Height = 72
        Reset-SteamHeroExtras
        if ($script:lblHeroDetail) { $script:lblHeroDetail.Visible = $false }
        if ($script:lblHeroTitle) {
            $script:lblHeroTitle.Location = New-Object System.Drawing.Point(12, 12)
        }
        return
    }

    Reset-SteamHeroExtras
    $script:pnlSteamHero.Height = 120
    $titleColor = switch ($Report.State) {
        'completed' { Get-SteamUiColor 'Ink' ([System.Drawing.Color]::FromArgb(199, 213, 224)) }
        'dry-run' { Get-SteamUiColor 'Section' ([System.Drawing.Color]::FromArgb(102, 192, 244)) }
        default { Get-SteamUiColor 'Amber' ([System.Drawing.Color]::FromArgb(164, 208, 7)) }
    }
    $headline = if ([string]$Report.HeroTitle) { [string]$Report.HeroTitle } else {
        "Mission complete - $([string]$Report.TimeLabel)"
    }
    $script:lblHeroTitle.ForeColor = $titleColor
    $script:lblHeroTitle.Font = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
    $script:lblHeroTitle.Location = New-Object System.Drawing.Point(12, 8)
    $script:lblHeroTitle.Size = New-Object System.Drawing.Size(($heroWidth - 24), 24)
    $script:lblHeroTitle.Text = $headline

    $streakLabel = if ([int]$Report.Streak -eq 1) { '1 night' } elseif ([int]$Report.Streak -gt 1) { "$([int]$Report.Streak) nights" } else { '0 nights' }
    if ($script:lblHeroStatLine) {
        $script:lblHeroStatLine.Location = New-Object System.Drawing.Point(12, 40)
        $script:lblHeroStatLine.Text = "Action: $($Report.Action)   -   Streak: $streakLabel   -   Snoozes: $([int]$Report.SnoozeCount)"
        $script:lblHeroStatLine.Visible = $true
    }
    if ($script:lblHeroDone) {
        $script:lblHeroDone.Visible = ($Report.State -in @('completed', 'dry-run'))
    }
    $encourage = if ($Report.EncourageLine) { [string]$Report.EncourageLine } else {
        switch ($Report.State) {
            'completed' { 'Great job. You kept your promise. Rest well. You''ve got tomorrow.' }
            'dry-run' { 'Dry run complete - no power action was performed.' }
            default { 'Session ended without shutdown.' }
        }
    }
    if ($script:lblHeroEncourage) {
        $script:lblHeroEncourage.Text = $encourage
        $script:lblHeroEncourage.Location = New-Object System.Drawing.Point(12, 64)
        $script:lblHeroEncourage.Size = New-Object System.Drawing.Size(($heroWidth - 24), 32)
        $script:lblHeroEncourage.Visible = $true
    }
    if ($script:lblHeroTag) { $script:lblHeroTag.Visible = $false }
    if ($script:lblHeroDetail) { $script:lblHeroDetail.Visible = $false }
    Update-SteamHeaderStatus "RESULT > $([string]$Report.Headline)"
    $script:pnlSteamHero.Invalidate()
}

function Update-SteamLobbyRingLayout {
    param(
        $RingPanel,
        [bool]$PreviewLobby,
        [int]$YBoost = 0
    )
    if (-not $RingPanel) { return }
    if ($PreviewLobby) {
        $RingPanel.Location = New-Object System.Drawing.Point(292, (48 + $YBoost))
        $RingPanel.Size = New-Object System.Drawing.Size(176, 176)
    } else {
        $RingPanel.Location = New-Object System.Drawing.Point(88, (78 + $YBoost))
        $RingPanel.Size = New-Object System.Drawing.Size(220, 220)
    }
}

function Update-SteamMorningProofActions {
    param(
        [bool]$Visible,
        [int]$Y
    )
    if ($script:btnMorningLedger) { $script:btnMorningLedger.Visible = $Visible }
    if ($script:btnMorningDismiss) {
        if ($Visible) {
            $half = $script:btnMorningLedger.Width
            $script:btnMorningLedger.Location = New-Object System.Drawing.Point(24, $Y)
            $script:btnMorningDismiss.Location = New-Object System.Drawing.Point((24 + $half + 8), $Y)
        }
        $script:btnMorningDismiss.Visible = $Visible
    }
}

Export-ModuleMember -Function @(
    'Get-LightsOutThemePalette'
    'Get-RitualGameCatalog'
    'Get-RitualGameById'
    'Get-SessionState'
    'Set-LightsOutTheme'
    'Add-UiControl'
    'Add-SteamHeroPanel'
    'Add-SteamFormChrome'
    'Set-SteamTrayMenuStyle'
    'New-SteamTrayMenu'
    'Update-SteamTrayHeader'
    'Update-SteamHeaderStatus'
    'Update-SteamExperience'
    'Set-SteamNavHighlight'
    'Add-SteamSleepClearancePanel'
    'Add-SteamTrustBadgesPanel'
    'Update-SteamSleepClearancePanel'
    'Update-SteamTonightPreviewHero'
    'Update-SteamTrustBadgesPanel'
    'Add-SteamMorningProofActions'
    'Update-SteamMorningProofHero'
    'Update-SteamMorningProofActions'
    'Update-SteamLobbyRingLayout'
)
