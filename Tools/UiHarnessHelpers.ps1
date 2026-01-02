Set-StrictMode -Version Latest

# LANDMARK: UI harness preflight - reusable desktop/STA readiness check
function Test-StateTraceUiHarnessPreflight {
    [CmdletBinding()]
    param(
        [switch]$RequireDesktop,
        [switch]$RequireSta,
        [object]$UserInteractiveOverride,
        [object]$ApartmentStateOverride
    )

    $details = [ordered]@{}
    $userInteractive = $null
    if ($PSBoundParameters.ContainsKey('UserInteractiveOverride')) {
        $userInteractive = [bool]$UserInteractiveOverride
    } else {
        try { $userInteractive = [Environment]::UserInteractive } catch { $userInteractive = $false }
    }

    $apartmentState = $null
    if ($PSBoundParameters.ContainsKey('ApartmentStateOverride')) {
        $apartmentState = $ApartmentStateOverride
    } else {
        try { $apartmentState = [System.Threading.Thread]::CurrentThread.ApartmentState } catch { $apartmentState = $null }
    }

    $details.UserInteractive = $userInteractive
    $details.ApartmentState = if ($apartmentState) { $apartmentState.ToString() } else { '' }

    if ($RequireDesktop -and -not $userInteractive) {
        return [pscustomobject]@{
            Status  = 'RequiresDesktop'
            Reason  = 'NonInteractiveSession'
            Details = $details
        }
    }

    if ($RequireSta -and $apartmentState -ne [System.Threading.ApartmentState]::STA) {
        return [pscustomobject]@{
            Status  = 'RequiresSTA'
            Reason  = 'ApartmentStateMismatch'
            Details = $details
        }
    }

    return [pscustomobject]@{
        Status  = 'Ready'
        Reason  = ''
        Details = $details
    }
}
