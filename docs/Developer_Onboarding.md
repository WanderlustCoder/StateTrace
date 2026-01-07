# StateTrace Developer Onboarding

Welcome to StateTrace development! This guide helps you set up your environment and get productive quickly.

## Quick Start

```powershell
# Clone the repository
git clone <repository-url>
cd StateTrace

# Run the bootstrap script
.\Tools\Bootstrap-DevSeat.ps1

# Run CI harness to verify everything works
.\Tools\Invoke-CIHarness.ps1

# Launch the application
.\Main\MainWindow.ps1
```

## Prerequisites

### Required

| Component | Version | Purpose |
|-----------|---------|---------|
| PowerShell | 5.1+ | Runtime environment |
| .NET Framework | 4.7.2+ | WPF support |
| Git | 2.30+ | Version control |

### Recommended

| Component | Version | Purpose |
|-----------|---------|---------|
| VS Code | Latest | Editor with PowerShell extension |
| Pester | 5.0+ | Unit testing |
| PSScriptAnalyzer | 1.20+ | Code quality |
| Access Database Engine | 2016 | OLEDB provider for .accdb files |

## Environment Setup

### Automatic Setup

The easiest way to set up your environment:

```powershell
.\Tools\Bootstrap-DevSeat.ps1
```

This script will:
1. Check PowerShell version
2. Install required modules (Pester, PSScriptAnalyzer)
3. Verify database provider availability
4. Configure Git hooks
5. Create required directories
6. Run smoke tests

### Manual Setup

If you prefer manual setup:

#### 1. Install PowerShell Modules

```powershell
Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -Scope CurrentUser
Install-Module -Name PSScriptAnalyzer -MinimumVersion 1.20.0 -Force -Scope CurrentUser
```

#### 2. Install Database Provider

Download and install [Microsoft Access Database Engine 2016 Redistributable](https://www.microsoft.com/en-us/download/details.aspx?id=54920).

> **Note:** Install the x64 version for 64-bit PowerShell.

#### 3. Configure Git

```powershell
git config user.name "Your Name"
git config user.email "your@email.com"
```

#### 4. Install Pre-commit Hooks

```powershell
.\Tools\Install-PreCommitHooks.ps1
```

## Project Structure

```
StateTrace/
├── Data/                    # Runtime data and settings
│   ├── StateTraceSettings.json
│   ├── WLLS/               # Site-specific data
│   └── BOYO/
├── docs/                    # Documentation
│   ├── plans/              # Implementation plans
│   ├── schemas/            # Data schemas
│   └── troubleshooting/    # Common issues
├── Logs/                    # Application logs
├── Main/                    # Application entry point
│   └── MainWindow.xaml
├── Modules/                 # PowerShell modules
│   ├── DatabaseModule.psm1
│   ├── InterfaceModule.psm1
│   └── Tests/              # Module tests
├── Resources/               # Shared XAML resources
├── Tests/                   # Integration tests
│   └── Fixtures/           # Test data
├── Themes/                  # UI themes
├── Tools/                   # Development tools
└── Views/                   # XAML views
```

## Development Workflow

### Daily Development

1. **Pull latest changes**
   ```powershell
   git pull origin main
   ```

2. **Create feature branch**
   ```powershell
   git checkout -b feature/your-feature-name
   ```

3. **Make changes and test**
   ```powershell
   # Run specific tests
   Invoke-Pester -Path .\Modules\Tests\YourModule.Tests.ps1

   # Run all tests
   .\Tools\Invoke-CIHarness.ps1
   ```

4. **Commit changes**
   ```powershell
   git add .
   git commit -m "feat: your change description"
   ```

5. **Push and create PR**
   ```powershell
   git push origin feature/your-feature-name
   ```

### Running the Application

```powershell
# Standard launch
.\Main\MainWindow.ps1

# With verbose logging
.\Main\MainWindow.ps1 -Verbose

# With specific site
.\Main\MainWindow.ps1 -Site WLLS
```

### Running Tests

```powershell
# All Pester tests
Invoke-Pester -Path .\Modules\Tests

# Specific test file
Invoke-Pester -Path .\Modules\Tests\InterfaceModule.Tests.ps1

# With code coverage
Invoke-Pester -Path .\Modules\Tests -CodeCoverage .\Modules\*.psm1

# Full CI harness
.\Tools\Invoke-CIHarness.ps1
```

### Code Quality

```powershell
# Run PSScriptAnalyzer
Invoke-ScriptAnalyzer -Path .\Modules -Recurse

# Auto-fix some issues
Invoke-ScriptAnalyzer -Path .\Modules -Recurse -Fix
```

## Module Development

### Creating a New Module

1. Create `Modules/YourModule.psm1`:
   ```powershell
   # YourModule.psm1
   Set-StrictMode -Version Latest

   function Get-YourFunction {
       <#
       .SYNOPSIS
       Brief description.
       .DESCRIPTION
       Detailed description.
       .PARAMETER Param1
       Parameter description.
       .EXAMPLE
       Get-YourFunction -Param1 'value'
       #>
       [CmdletBinding()]
       param(
           [Parameter(Mandatory)][string]$Param1
       )

       # Implementation
   }

   Export-ModuleMember -Function @('Get-YourFunction')
   ```

2. Create `Modules/Tests/YourModule.Tests.ps1`:
   ```powershell
   BeforeAll {
       $modulePath = Join-Path $PSScriptRoot '..\YourModule.psm1'
       Import-Module $modulePath -Force
   }

   Describe 'Get-YourFunction' {
       It 'Returns expected result' {
           $result = Get-YourFunction -Param1 'test'
           $result | Should -Not -BeNullOrEmpty
       }
   }

   AfterAll {
       Remove-Module YourModule -Force -ErrorAction SilentlyContinue
   }
   ```

3. Generate documentation:
   ```powershell
   .\Tools\New-ModuleDocumentation.ps1
   ```

### Module Best Practices

- Use `Set-StrictMode -Version Latest` at the top
- Add comment-based help to all exported functions
- Export functions explicitly with `Export-ModuleMember`
- Use `[CmdletBinding()]` for advanced function features
- Validate parameters with `[Parameter(Mandatory)]`, `[ValidateNotNullOrEmpty()]`, etc.
- Avoid `Write-Host` for data output; use `Write-Verbose` for diagnostics

## Debugging

### PowerShell Debugging in VS Code

1. Open the PowerShell file
2. Set breakpoints (F9)
3. Press F5 to start debugging
4. Use the Debug Console to inspect variables

### Common Debug Commands

```powershell
# Enable verbose output
$VerbosePreference = 'Continue'

# Enable debug output
$DebugPreference = 'Continue'

# Trace command execution
Set-PSDebug -Trace 1

# Turn off tracing
Set-PSDebug -Off
```

### Logging

StateTrace uses structured logging:

```powershell
# Log to console and file
Write-Verbose "Operation completed"

# Use telemetry for metrics
Publish-TelemetryEvent -EventType 'OperationComplete' -Data @{ Duration = 150 }
```

Logs are written to `Logs/` directory.

## Hot Reload

StateTrace supports hot-reload for settings:

1. Modify `Data/StateTraceSettings.json`
2. Changes are automatically detected and applied
3. No application restart required

To use hot-reload in your code:

```powershell
Import-Module .\Modules\SettingsWatcherModule.psm1

# Register a callback
Register-SettingsChangeCallback -Callback {
    param($settings)
    Write-Host "Settings changed: $($settings | ConvertTo-Json -Compress)"
}

# Initialize watcher
Initialize-SettingsWatcher -SettingsPath '.\Data\StateTraceSettings.json'
```

## Error Handling

Use the ErrorHandlingModule for context-rich errors:

```powershell
Import-Module .\Modules\ErrorHandlingModule.psm1

try {
    # Your code
} catch {
    Write-EnhancedError -ErrorRecord $_ -IncludeStackTrace
}

# Or wrap operations
Invoke-WithEnhancedErrorHandling -ScriptBlock {
    # Your code here
} -ErrorAction Throw
```

## Troubleshooting

### Module Import Errors

```powershell
# Check for syntax errors
$tokens = $null; $errors = $null
[System.Management.Automation.Language.Parser]::ParseFile('.\Modules\YourModule.psm1', [ref]$tokens, [ref]$errors)
$errors | ForEach-Object { Write-Host $_.Message }
```

### Database Connection Issues

```powershell
# Test OLEDB provider
$providers = (New-Object System.Data.OleDb.OleDbEnumerator).GetElements()
$providers | Where-Object { $_.SOURCES_NAME -match 'ACE|Jet' }

# Repair corrupted database
.\Tools\Repair-AccessDatabase.ps1 -DatabasePath '.\Data\WLLS\StateTrace.accdb'
```

### Pre-commit Hook Failures

```powershell
# Run checks manually
.\Tools\Invoke-PreCommitChecks.ps1

# Bypass hooks (not recommended)
git commit --no-verify -m "your message"
```

## Resources

- **Architecture:** `docs/StateTrace_Software_Architecture_Document.md`
- **Test Strategy:** `docs/Test_Strategy.md`
- **Troubleshooting:** `docs/troubleshooting/Common_Failures.md`
- **Plan Index:** `docs/plans/PlanIndex.md`

## Getting Help

1. Check the `docs/troubleshooting/` directory
2. Run `.\Troubleshooting\Invoke-StateTraceDiagnostics.ps1`
3. Search existing GitHub issues
4. Ask in the team chat

---

*Last updated: Auto-generated by Bootstrap-DevSeat.ps1*
