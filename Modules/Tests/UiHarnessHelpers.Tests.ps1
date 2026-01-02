Set-StrictMode -Version Latest

Describe "UI harness preflight" {
    BeforeAll {
        $helperPath = Join-Path (Split-Path $PSCommandPath) "..\..\Tools\UiHarnessHelpers.ps1"
        . (Resolve-Path $helperPath)
    }

    # LANDMARK: UI harness preflight tests - deterministic status classification
    It "returns RequiresDesktop when user is not interactive" {
        $result = Test-StateTraceUiHarnessPreflight -RequireDesktop -UserInteractiveOverride $false -ApartmentStateOverride ([System.Threading.ApartmentState]::STA)
        $result.Status | Should Be 'RequiresDesktop'
        $result.Reason | Should Be 'NonInteractiveSession'
    }

    It "returns RequiresSTA when apartment state mismatch" {
        $result = Test-StateTraceUiHarnessPreflight -RequireSta -UserInteractiveOverride $true -ApartmentStateOverride ([System.Threading.ApartmentState]::MTA)
        $result.Status | Should Be 'RequiresSTA'
        $result.Reason | Should Be 'ApartmentStateMismatch'
    }

    It "returns Ready when requirements are met" {
        $result = Test-StateTraceUiHarnessPreflight -RequireDesktop -RequireSta -UserInteractiveOverride $true -ApartmentStateOverride ([System.Threading.ApartmentState]::STA)
        $result.Status | Should Be 'Ready'
        $result.Reason | Should Be ''
    }
}
