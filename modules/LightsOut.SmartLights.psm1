# LightsOut.SmartLights.psm1
# Smart light integration for Lights Out Sleep Timer
# Supports: Philips Hue Bridge, Generic HTTP webhook

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

$script:SmartLightProvider = 'none'        # 'none', 'hue', 'http'
$script:SmartLightMode = 'gradual_dim'     # 'gradual_dim', 'warm_dim', 'off_at_end'
$script:SmartLightDimMinutes = 10          # how many minutes before end to start dimming
$script:SmartLightEnabled = $false

# Hue settings
$script:HueBridgeIp = ''
$script:HueUsername = ''
$script:HueLightIds = @()                  # array of light IDs to control (empty = all)
$script:HueGroupId = ''                    # group/room ID (optional, overrides individual lights)

# HTTP webhook settings
$script:HttpLightUrl = ''
$script:HttpLightMethod = 'POST'
$script:HttpLightHeaders = @{}
$script:HttpLightBodyTemplate = '{"brightness": {{BRIGHTNESS}}, "color_temp": {{COLOR_TEMP}}, "on": {{ON}}}'

# State tracking
$script:LightDimStarted = $false
$script:LightOriginalState = $null

# ─────────────────────────────────────────────────────────────────────────────
# Philips Hue Functions
# ─────────────────────────────────────────────────────────────────────────────

function Find-HueBridge {
    <#
    .SYNOPSIS Discover Hue Bridge on local network via mDNS/UPnP
    #>
    try {
        $resp = Invoke-RestMethod -Uri 'https://discovery.meethue.com' -TimeoutSec 5
        if ($resp -and $resp.Count -gt 0) {
            return @{
                Ip = $resp[0].internalipaddress
                Id = $resp[0].id
            }
        }
    } catch { }
    return $null
}

function Register-HueBridge {
    <#
    .SYNOPSIS Register with Hue Bridge (user must press link button first)
    .PARAMETER BridgeIp IP address of the Hue Bridge
    #>
    param([string]$BridgeIp)
    try {
        $body = @{ devicetype = 'LightsOut#SleepTimer' } | ConvertTo-Json
        $resp = Invoke-RestMethod -Uri "http://$BridgeIp/api" -Method POST -Body $body -ContentType 'application/json' -TimeoutSec 10
        if ($resp[0].success) {
            return $resp[0].success.username
        }
        if ($resp[0].error) {
            return @{ Error = $resp[0].error.description }
        }
    } catch {
        return @{ Error = $_.Exception.Message }
    }
    return $null
}

function Get-HueLights {
    <#
    .SYNOPSIS Get all lights from Hue Bridge
    #>
    param([string]$BridgeIp, [string]$Username)
    try {
        $resp = Invoke-RestMethod -Uri "http://$BridgeIp/api/$Username/lights" -TimeoutSec 5
        $lights = @()
        foreach ($id in $resp.PSObject.Properties.Name) {
            $l = $resp.$id
            $lights += @{
                Id = $id
                Name = $l.name
                On = $l.state.on
                Bri = $l.state.bri
                Ct = if ($l.state.ct) { $l.state.ct } else { 0 }
                Type = $l.type
            }
        }
        return $lights
    } catch {
        return @()
    }
}

function Get-HueGroups {
    <#
    .SYNOPSIS Get all groups/rooms from Hue Bridge
    #>
    param([string]$BridgeIp, [string]$Username)
    try {
        $resp = Invoke-RestMethod -Uri "http://$BridgeIp/api/$Username/groups" -TimeoutSec 5
        $groups = @()
        foreach ($id in $resp.PSObject.Properties.Name) {
            $g = $resp.$id
            $groups += @{
                Id = $id
                Name = $g.name
                Type = $g.type
                Lights = $g.lights
            }
        }
        return $groups
    } catch {
        return @()
    }
}

function Set-HueLightState {
    <#
    .SYNOPSIS Set state of a Hue light
    .PARAMETER BridgeIp Hue Bridge IP
    .PARAMETER Username API username
    .PARAMETER LightId Light ID
    .PARAMETER State Hashtable with state properties (on, bri, ct, transitiontime)
    #>
    param([string]$BridgeIp, [string]$Username, [string]$LightId, [hashtable]$State)
    try {
        $body = $State | ConvertTo-Json -Compress
        Invoke-RestMethod -Uri "http://$BridgeIp/api/$Username/lights/$LightId/state" `
            -Method PUT -Body $body -ContentType 'application/json' -TimeoutSec 5 | Out-Null
    } catch { }
}

function Set-HueGroupState {
    <#
    .SYNOPSIS Set state of a Hue group/room
    #>
    param([string]$BridgeIp, [string]$Username, [string]$GroupId, [hashtable]$State)
    try {
        $body = $State | ConvertTo-Json -Compress
        Invoke-RestMethod -Uri "http://$BridgeIp/api/$Username/groups/$GroupId/action" `
            -Method PUT -Body $body -ContentType 'application/json' -TimeoutSec 5 | Out-Null
    } catch { }
}

function Save-HueCurrentState {
    <#
    .SYNOPSIS Capture current brightness/color of lights for restore later
    #>
    param([string]$BridgeIp, [string]$Username)
    $lights = Get-HueLights -BridgeIp $BridgeIp -Username $Username
    $script:LightOriginalState = $lights | Where-Object { $_.On }
}

# ─────────────────────────────────────────────────────────────────────────────
# Generic HTTP Functions
# ─────────────────────────────────────────────────────────────────────────────

function Invoke-HttpLightAction {
    <#
    .SYNOPSIS Send HTTP request to control lights via webhook
    .PARAMETER Brightness 0-254 brightness value
    .PARAMETER ColorTemp Color temperature in mireds (153=cold, 500=warm)
    .PARAMETER On Boolean, light on/off
    #>
    param([int]$Brightness = 254, [int]$ColorTemp = 366, [bool]$On = $true)
    if (-not $script:HttpLightUrl) { return }
    try {
        $bodyStr = $script:HttpLightBodyTemplate `
            -replace '{{BRIGHTNESS}}', $Brightness `
            -replace '{{COLOR_TEMP}}', $ColorTemp `
            -replace '{{ON}}', $(if ($On) { 'true' } else { 'false' })
        $params = @{
            Uri = $script:HttpLightUrl
            Method = $script:HttpLightMethod
            Body = $bodyStr
            ContentType = 'application/json'
            TimeoutSec = 5
        }
        if ($script:HttpLightHeaders.Count -gt 0) {
            $params.Headers = $script:HttpLightHeaders
        }
        Invoke-RestMethod @params | Out-Null
    } catch { }
}

# ─────────────────────────────────────────────────────────────────────────────
# Timer Integration — called from main timer tick
# ─────────────────────────────────────────────────────────────────────────────

function Start-SmartLightDim {
    <#
    .SYNOPSIS Begin the dim sequence — called when countdown enters the dim window
    #>
    if (-not $script:SmartLightEnabled) { return }
    if ($script:LightDimStarted) { return }
    $script:LightDimStarted = $true

    if ($script:SmartLightProvider -eq 'hue' -and $script:HueBridgeIp -and $script:HueUsername) {
        Save-HueCurrentState -BridgeIp $script:HueBridgeIp -Username $script:HueUsername
    }
}

function Update-SmartLightTick {
    <#
    .SYNOPSIS Called every timer tick to update light levels during dim phase
    .PARAMETER SecondsLeft Seconds remaining in countdown
    .PARAMETER DimDurationSec Total dim duration in seconds
    #>
    param([int]$SecondsLeft, [int]$DimDurationSec)
    if (-not $script:SmartLightEnabled -or -not $script:LightDimStarted) { return }
    if ($script:SmartLightMode -eq 'off_at_end') { return }

    $progress = 1.0 - ([math]::Max(0, $SecondsLeft) / [math]::Max(1, $DimDurationSec))
    $progress = [math]::Min(1.0, [math]::Max(0.0, $progress))

    # Calculate target brightness (254 -> 0)
    $targetBri = [int](254 * (1.0 - $progress))

    # Calculate color temp for warm_dim mode (neutral 366 -> warm 500)
    $targetCt = if ($script:SmartLightMode -eq 'warm_dim') {
        [int](366 + (134 * $progress))
    } else { 366 }

    # Transition time in 100ms units (smooth 1-second steps)
    $transition = 10

    switch ($script:SmartLightProvider) {
        'hue' {
            $state = @{ bri = $targetBri; transitiontime = $transition }
            if ($script:SmartLightMode -eq 'warm_dim') { $state.ct = $targetCt }
            if ($targetBri -le 0) { $state.on = $false }

            if ($script:HueGroupId) {
                Set-HueGroupState -BridgeIp $script:HueBridgeIp -Username $script:HueUsername `
                    -GroupId $script:HueGroupId -State $state
            } else {
                $ids = if ($script:HueLightIds.Count -gt 0) { $script:HueLightIds }
                       else { ($script:LightOriginalState | ForEach-Object { $_.Id }) }
                foreach ($id in $ids) {
                    Set-HueLightState -BridgeIp $script:HueBridgeIp -Username $script:HueUsername `
                        -LightId $id -State $state
                }
            }
        }
        'http' {
            Invoke-HttpLightAction -Brightness $targetBri -ColorTemp $targetCt -On ($targetBri -gt 0)
        }
    }
}

function Invoke-SmartLightOff {
    <#
    .SYNOPSIS Turn off lights immediately — called at timer end
    #>
    if (-not $script:SmartLightEnabled) { return }

    switch ($script:SmartLightProvider) {
        'hue' {
            $state = @{ on = $false; transitiontime = 10 }
            if ($script:HueGroupId) {
                Set-HueGroupState -BridgeIp $script:HueBridgeIp -Username $script:HueUsername `
                    -GroupId $script:HueGroupId -State $state
            } else {
                $ids = if ($script:HueLightIds.Count -gt 0) { $script:HueLightIds }
                       elseif ($script:LightOriginalState) { $script:LightOriginalState | ForEach-Object { $_.Id } }
                       else { @() }
                foreach ($id in $ids) {
                    Set-HueLightState -BridgeIp $script:HueBridgeIp -Username $script:HueUsername `
                        -LightId $id -State $state
                }
            }
        }
        'http' {
            Invoke-HttpLightAction -Brightness 0 -ColorTemp 366 -On $false
        }
    }
    $script:LightDimStarted = $false
}

function Reset-SmartLightState {
    <#
    .SYNOPSIS Reset internal tracking when timer is cancelled/stopped
    #>
    $script:LightDimStarted = $false
    $script:LightOriginalState = $null
}

function Test-SmartLightConnection {
    <#
    .SYNOPSIS Test connectivity to configured light provider
    .RETURNS Hashtable with Success bool and Message string
    #>
    switch ($script:SmartLightProvider) {
        'hue' {
            if (-not $script:HueBridgeIp -or -not $script:HueUsername) {
                return @{ Success = $false; Message = 'Hue Bridge not configured' }
            }
            $lights = Get-HueLights -BridgeIp $script:HueBridgeIp -Username $script:HueUsername
            if ($lights.Count -gt 0) {
                return @{ Success = $true; Message = "Connected: $($lights.Count) lights found" }
            }
            return @{ Success = $false; Message = 'No lights found - check bridge IP/username' }
        }
        'http' {
            if (-not $script:HttpLightUrl) {
                return @{ Success = $false; Message = 'No webhook URL configured' }
            }
            try {
                Invoke-HttpLightAction -Brightness 254 -ColorTemp 366 -On $true
                return @{ Success = $true; Message = "Sent test to $($script:HttpLightUrl)" }
            } catch {
                return @{ Success = $false; Message = $_.Exception.Message }
            }
        }
        default {
            return @{ Success = $false; Message = 'No provider selected' }
        }
    }
}

function Get-SmartLightConfig {
    <#
    .SYNOPSIS Export current configuration as hashtable for saving
    #>
    return @{
        Provider = $script:SmartLightProvider
        Mode = $script:SmartLightMode
        DimMinutes = $script:SmartLightDimMinutes
        Enabled = $script:SmartLightEnabled
        HueBridgeIp = $script:HueBridgeIp
        HueUsername = $script:HueUsername
        HueLightIds = $script:HueLightIds
        HueGroupId = $script:HueGroupId
        HttpUrl = $script:HttpLightUrl
        HttpMethod = $script:HttpLightMethod
        HttpHeaders = $script:HttpLightHeaders
        HttpBodyTemplate = $script:HttpLightBodyTemplate
    }
}

function Set-SmartLightConfig {
    <#
    .SYNOPSIS Load configuration from saved hashtable
    #>
    param([hashtable]$Config)
    if (-not $Config) { return }
    if ($Config.Provider) { $script:SmartLightProvider = $Config.Provider }
    if ($Config.Mode) { $script:SmartLightMode = $Config.Mode }
    if ($null -ne $Config.DimMinutes) { $script:SmartLightDimMinutes = [int]$Config.DimMinutes }
    if ($null -ne $Config.Enabled) { $script:SmartLightEnabled = [bool]$Config.Enabled }
    if ($Config.HueBridgeIp) { $script:HueBridgeIp = $Config.HueBridgeIp }
    if ($Config.HueUsername) { $script:HueUsername = $Config.HueUsername }
    if ($Config.HueLightIds) { $script:HueLightIds = @($Config.HueLightIds) }
    if ($Config.HueGroupId) { $script:HueGroupId = $Config.HueGroupId }
    if ($Config.HttpUrl) { $script:HttpLightUrl = $Config.HttpUrl }
    if ($Config.HttpMethod) { $script:HttpLightMethod = $Config.HttpMethod }
    if ($Config.HttpHeaders) { $script:HttpLightHeaders = $Config.HttpHeaders }
    if ($Config.HttpBodyTemplate) { $script:HttpLightBodyTemplate = $Config.HttpBodyTemplate }
}

# Export module members
Export-ModuleMember -Function @(
    'Find-HueBridge',
    'Register-HueBridge',
    'Get-HueLights',
    'Get-HueGroups',
    'Set-HueLightState',
    'Set-HueGroupState',
    'Invoke-HttpLightAction',
    'Start-SmartLightDim',
    'Update-SmartLightTick',
    'Invoke-SmartLightOff',
    'Reset-SmartLightState',
    'Test-SmartLightConnection',
    'Get-SmartLightConfig',
    'Set-SmartLightConfig'
)
