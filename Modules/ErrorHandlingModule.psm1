# ErrorHandlingModule.psm1
# Provides enhanced error handling with context-rich messages, suggestions, and structured logging.

Set-StrictMode -Version Latest

# Known error patterns and their suggested fixes
$script:ErrorSuggestions = @{
    'Cannot find path' = @{
        Category = 'FileNotFound'
        Suggestion = 'Verify the file path exists. Check for typos or ensure the file was created.'
        DocLink = 'docs/troubleshooting/Common_Failures.md#file-not-found'
    }
    'Access.*denied' = @{
        Category = 'PermissionDenied'
        Suggestion = 'Check file permissions. Ensure no other process has the file locked.'
        DocLink = 'docs/troubleshooting/Common_Failures.md#access-denied'
    }
    'Provider.*not.*found|OLEDB' = @{
        Category = 'DatabaseProvider'
        Suggestion = 'Install Microsoft Access Database Engine. Run Bootstrap-DevSeat.ps1 to configure prerequisites.'
        DocLink = 'docs/Developer_Setup.md#database-providers'
    }
    'Connection.*failed|cannot.*connect' = @{
        Category = 'ConnectionFailure'
        Suggestion = 'Check network connectivity. Verify the target host is reachable.'
        DocLink = 'docs/troubleshooting/Common_Failures.md#connection-issues'
    }
    'JSON.*invalid|ConvertFrom-Json' = @{
        Category = 'JsonParseError'
        Suggestion = 'Check JSON syntax. Use a JSON validator to find formatting issues.'
        DocLink = 'docs/troubleshooting/Common_Failures.md#json-errors'
    }
    'Module.*not.*found|Import-Module' = @{
        Category = 'ModuleNotFound'
        Suggestion = 'Ensure the module exists in the Modules directory. Check module name spelling.'
        DocLink = 'docs/Developer_Setup.md#module-dependencies'
    }
    'timeout|timed out' = @{
        Category = 'Timeout'
        Suggestion = 'Increase timeout value or check for slow operations blocking the pipeline.'
        DocLink = 'docs/troubleshooting/Common_Failures.md#timeouts'
    }
    'out of memory|memory.*exceeded' = @{
        Category = 'OutOfMemory'
        Suggestion = 'Close unused applications. Consider processing data in smaller batches.'
        DocLink = 'docs/troubleshooting/Common_Failures.md#memory-issues'
    }
}

function Get-ErrorContext {
    <#
    .SYNOPSIS
    Extracts detailed context from an error record.
    .PARAMETER ErrorRecord
    The PowerShell ErrorRecord to analyze.
    .OUTPUTS
    PSCustomObject with file path, line number, function name, and stack trace.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $context = [ordered]@{
        Message = $ErrorRecord.Exception.Message
        ExceptionType = $ErrorRecord.Exception.GetType().FullName
        Category = $ErrorRecord.CategoryInfo.Category.ToString()
        TargetObject = $null
        ScriptPath = $null
        ScriptName = $null
        LineNumber = 0
        ColumnNumber = 0
        FunctionName = $null
        Command = $null
        StackTrace = $null
        InnerException = $null
    }

    # Extract invocation info
    if ($ErrorRecord.InvocationInfo) {
        $inv = $ErrorRecord.InvocationInfo
        $context.ScriptPath = $inv.ScriptName
        $context.ScriptName = if ($inv.ScriptName) { Split-Path -Leaf $inv.ScriptName } else { $null }
        $context.LineNumber = $inv.ScriptLineNumber
        $context.ColumnNumber = $inv.OffsetInLine
        $context.FunctionName = $inv.MyCommand.Name
        $context.Command = $inv.Line.Trim()
    }

    # Extract target object
    if ($ErrorRecord.TargetObject) {
        $context.TargetObject = $ErrorRecord.TargetObject.ToString()
    }

    # Get stack trace
    if ($ErrorRecord.ScriptStackTrace) {
        $context.StackTrace = $ErrorRecord.ScriptStackTrace
    }

    # Get inner exception
    if ($ErrorRecord.Exception.InnerException) {
        $context.InnerException = $ErrorRecord.Exception.InnerException.Message
    }

    return [PSCustomObject]$context
}

function Get-ErrorSuggestion {
    <#
    .SYNOPSIS
    Matches an error message against known patterns and returns suggestions.
    .PARAMETER ErrorMessage
    The error message to analyze.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ErrorMessage
    )

    foreach ($pattern in $script:ErrorSuggestions.Keys) {
        if ($ErrorMessage -match $pattern) {
            return [PSCustomObject]$script:ErrorSuggestions[$pattern]
        }
    }

    return [PSCustomObject]@{
        Category = 'Unknown'
        Suggestion = 'Check the error message and stack trace for details. Search the codebase for similar issues.'
        DocLink = 'docs/troubleshooting/Common_Failures.md'
    }
}

function Format-EnhancedError {
    <#
    .SYNOPSIS
    Formats an error with full context and suggestions.
    .PARAMETER ErrorRecord
    The PowerShell ErrorRecord to format.
    .PARAMETER IncludeStackTrace
    Include the full stack trace in output.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord,
        [switch]$IncludeStackTrace
    )

    $context = Get-ErrorContext -ErrorRecord $ErrorRecord
    $suggestion = Get-ErrorSuggestion -ErrorMessage $context.Message

    $sb = [System.Text.StringBuilder]::new()

    # Header
    [void]$sb.AppendLine("═══════════════════════════════════════════════════════════════")
    [void]$sb.AppendLine("ERROR: $($context.Message)")
    [void]$sb.AppendLine("═══════════════════════════════════════════════════════════════")

    # Location
    if ($context.ScriptPath) {
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("Location:")
        [void]$sb.AppendLine("  File:     $($context.ScriptPath)")
        [void]$sb.AppendLine("  Line:     $($context.LineNumber)")
        if ($context.ColumnNumber -gt 0) {
            [void]$sb.AppendLine("  Column:   $($context.ColumnNumber)")
        }
        if ($context.FunctionName) {
            [void]$sb.AppendLine("  Function: $($context.FunctionName)")
        }
    }

    # Command that caused error
    if ($context.Command) {
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("Command:")
        [void]$sb.AppendLine("  $($context.Command)")
    }

    # Suggestion
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Category: $($suggestion.Category)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Suggested Fix:")
    [void]$sb.AppendLine("  $($suggestion.Suggestion)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Documentation:")
    [void]$sb.AppendLine("  $($suggestion.DocLink)")

    # Stack trace
    if ($IncludeStackTrace.IsPresent -and $context.StackTrace) {
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("Stack Trace:")
        foreach ($line in $context.StackTrace -split "`n") {
            [void]$sb.AppendLine("  $line")
        }
    }

    [void]$sb.AppendLine("═══════════════════════════════════════════════════════════════")

    return $sb.ToString()
}

function Write-EnhancedError {
    <#
    .SYNOPSIS
    Writes an enhanced error message to the console and optionally to a log file.
    .PARAMETER ErrorRecord
    The PowerShell ErrorRecord to write.
    .PARAMETER LogPath
    Optional path to write the error to a log file.
    .PARAMETER IncludeStackTrace
    Include the full stack trace.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord,
        [string]$LogPath,
        [switch]$IncludeStackTrace
    )

    $formatted = Format-EnhancedError -ErrorRecord $ErrorRecord -IncludeStackTrace:$IncludeStackTrace

    # Write to console with color
    Write-Host $formatted -ForegroundColor Red

    # Write to log file if specified
    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
        try {
            $logEntry = @{
                Timestamp = [datetime]::UtcNow.ToString('o')
                Context = Get-ErrorContext -ErrorRecord $ErrorRecord
                Suggestion = Get-ErrorSuggestion -ErrorMessage $ErrorRecord.Exception.Message
            }

            $logDir = Split-Path -Parent $LogPath
            if (-not (Test-Path -LiteralPath $logDir)) {
                New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            }

            $json = $logEntry | ConvertTo-Json -Depth 10
            Add-Content -Path $LogPath -Value $json -Encoding UTF8
        } catch {
            Write-Verbose "Failed to write error log: $_"
        }
    }
}

function New-StateTraceException {
    <#
    .SYNOPSIS
    Creates a new StateTrace-specific exception with context.
    .PARAMETER Message
    The error message.
    .PARAMETER Category
    The error category.
    .PARAMETER InnerException
    Optional inner exception.
    .PARAMETER Context
    Optional hashtable of additional context.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Category = 'OperationError',
        [System.Exception]$InnerException,
        [hashtable]$Context
    )

    $fullMessage = $Message
    if ($Context -and $Context.Count -gt 0) {
        $contextStr = ($Context.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '; '
        $fullMessage = "$Message [$contextStr]"
    }

    if ($InnerException) {
        return [System.Exception]::new($fullMessage, $InnerException)
    }

    return [System.Exception]::new($fullMessage)
}

function Invoke-WithEnhancedErrorHandling {
    <#
    .SYNOPSIS
    Executes a scriptblock with enhanced error handling.
    .PARAMETER ScriptBlock
    The code to execute.
    .PARAMETER ErrorAction
    What to do on error: 'Throw', 'Continue', 'SilentlyContinue'.
    .PARAMETER LogPath
    Optional path to log errors.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [ValidateSet('Throw', 'Continue', 'SilentlyContinue')]
        [string]$ErrorAction = 'Throw',
        [string]$LogPath
    )

    try {
        & $ScriptBlock
    } catch {
        Write-EnhancedError -ErrorRecord $_ -LogPath $LogPath -IncludeStackTrace

        switch ($ErrorAction) {
            'Throw' { throw }
            'Continue' { return $null }
            'SilentlyContinue' { return $null }
        }
    }
}

function Add-ErrorSuggestion {
    <#
    .SYNOPSIS
    Adds a custom error pattern and suggestion.
    .PARAMETER Pattern
    Regex pattern to match against error messages.
    .PARAMETER Category
    Error category name.
    .PARAMETER Suggestion
    Suggested fix text.
    .PARAMETER DocLink
    Link to documentation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Suggestion,
        [string]$DocLink = ''
    )

    $script:ErrorSuggestions[$Pattern] = @{
        Category = $Category
        Suggestion = $Suggestion
        DocLink = $DocLink
    }
}

Export-ModuleMember -Function @(
    'Get-ErrorContext',
    'Get-ErrorSuggestion',
    'Format-EnhancedError',
    'Write-EnhancedError',
    'New-StateTraceException',
    'Invoke-WithEnhancedErrorHandling',
    'Add-ErrorSuggestion'
)
