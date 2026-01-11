Set-StrictMode -Version Latest

function Assert-Throws {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [scriptblock]$Script,

        [Parameter(Position = 1)]
        [string]$Message
    )

    process {
        $threw = $false
        $actualMessage = $null

        try {
            & $Script > $null
        } catch {
            $threw = $true
            $actualMessage = $_.Exception.Message
        }

        $threw | Should Be $true

        if ($Message) {
            $actualMessage | Should Match ([regex]::Escape($Message))
        }
    }
}
