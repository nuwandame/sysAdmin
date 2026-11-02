# Apply the requested Intel Wi-Fi advanced properties and append an audit log.
# Run in an elevated Windows PowerShell session or as a computer startup script.
$AdapterName = 'Wi-Fi'
$LogPath = 'C:\itq\log\WiFi-Changes.log'

# Ensure the log directory exists before writing any results.
$LogDirectory = Split-Path -Path $LogPath -Parent
New-Item -Path $LogDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null

function Write-Log {
    param([Parameter(Mandatory = $true)][string]$Message)
    # Append each result with a timestamp and the originating computer name.
    $Line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $env:COMPUTERNAME, $Message
    Add-Content -Path $LogPath -Value $Line -Encoding UTF8
    Write-Output $Line
}

# Requested registry keywords and their target values.
$Settings = @(
    @{ Keyword = '*PacketCoalescing';       Value = '0'   }
    @{ Keyword = 'RoamAggressiveness';       Value = '1'   }
    @{ Keyword = 'uAPSDSupport';            Value = '0'   }
    @{ Keyword = 'MIMOPowerSaveMode';        Value = '3'   }
    @{ Keyword = 'IbssTxPower';             Value = '100' }
    @{ Keyword = 'RoamingPreferredBandType'; Value = '2'   }
)

Write-Log "START: Adapter=$AdapterName; NoRestart=True"

try {
    # Read the full driver property list once to identify supported settings.
    $Properties = @(Get-NetAdapterAdvancedProperty -Name $AdapterName -AllProperties -ErrorAction Stop)
}
catch {
    Write-Log "ERROR: Unable to read adapter '$AdapterName': $($_.Exception.Message)"
    exit 1
}

$Failures = 0
foreach ($Setting in $Settings) {
    $Keyword = $Setting.Keyword
    $TargetValue = $Setting.Value

    # Match keywords exactly, not as regular expressions (the leading * is literal).
    $Property = $Properties | Where-Object { $_.RegistryKeyword -eq $Keyword } | Select-Object -First 1
    if ($null -eq $Property) {
        Write-Log "SKIPPED: $Keyword is not exposed by this driver."
        continue
    }

    $Before = [string]($Property.RegistryValue -join ',')
    if ($Before -eq $TargetValue) {
        Write-Log "UNCHANGED: $Keyword is already $TargetValue ($($Property.DisplayValue))."
        continue
    }

    # Reject an unsupported value if the driver publishes an allowed-value list.
    $Allowed = @($Property.ValidRegistryValues | ForEach-Object { [string]$_ })
    if ($Allowed.Count -gt 0 -and $TargetValue -notin $Allowed) {
        Write-Log "SKIPPED: $Keyword requested $TargetValue, but driver allows [$($Allowed -join ', ')]."
        $Failures++
        continue
    }

    try {
        # Prevent an immediate network disconnect while applying the settings.
        Set-NetAdapterAdvancedProperty -Name $AdapterName -RegistryKeyword $Keyword `
            -RegistryValue $TargetValue -NoRestart -ErrorAction Stop

        # Read back the setting to verify the stored value.
        $Updated = Get-NetAdapterAdvancedProperty -Name $AdapterName `
            -RegistryKeyword $Keyword -ErrorAction Stop
        $After = [string]($Updated.RegistryValue -join ',')
        if ($After -eq $TargetValue) {
            Write-Log "CHANGED: $Keyword $Before -> $After ($($Updated.DisplayValue))."
        }
        else {
            Write-Log "WARNING: $Keyword requested $TargetValue; readback is $After (previously $Before)."
            $Failures++
        }
    }
    catch {
        Write-Log "ERROR: $Keyword ($Before -> $TargetValue): $($_.Exception.Message)"
        $Failures++
    }
}

Write-Log "END: Failures=$Failures; adapter restart/reboot may be needed for changes to take effect."
if ($Failures -gt 0) { exit 1 }
exit 0
