#Requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Pester tests for DocumentationGeneratorModule.

.DESCRIPTION
    Tests template engine, document generation, export formats, and scheduling.
#>

# Import the module under test
$modulePath = Join-Path $PSScriptRoot '..\DocumentationGeneratorModule.psm1'
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force
}
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')

Describe 'DocumentationGeneratorModule' {

    BeforeEach {
        # Initialize in test mode to avoid persisting data
        Initialize-DocumentationDatabase -TestMode
    }

    AfterEach {
        Clear-DocumentationData
    }

    #region Initialization Tests

    Context 'Module Initialization' {
        It 'loads built-in templates on initialization' {
            $templates = Get-DocumentTemplate
            ($templates | Measure-Object).Count | Should BeGreaterThan 0
        }

        It 'has Site-AsBuilt built-in template' {
            $template = Get-DocumentTemplate -TemplateID 'Site-AsBuilt'
            $template | Should Not BeNullOrEmpty
            $template.IsBuiltIn | Should Be $true
        }

        It 'has Device-Summary built-in template' {
            $template = Get-DocumentTemplate -TemplateID 'Device-Summary'
            $template | Should Not BeNullOrEmpty
            $template.IsBuiltIn | Should Be $true
        }

        It 'has all 7 built-in templates' {
            $builtIn = @(Get-DocumentTemplate | Where-Object { $_.IsBuiltIn })
            $builtIn.Count | Should Be 7
        }
    }

    #endregion

    #region Template Engine Tests

    Context 'Template Engine - Variable Substitution' {
        It 'substitutes simple variables' {
            $template = 'Hello {{name}}!'
            $result = Expand-DocumentTemplate -Template $template -Variables @{ name = 'World' }
            $result | Should Be 'Hello World!'
        }

        It 'substitutes multiple variables' {
            $template = '{{greeting}} {{name}}, welcome to {{place}}!'
            $result = Expand-DocumentTemplate -Template $template -Variables @{
                greeting = 'Hello'
                name = 'John'
                place = 'StateTrace'
            }
            $result | Should Be 'Hello John, welcome to StateTrace!'
        }

        It 'replaces missing variables with N/A' {
            $template = 'Value: {{missing}}'
            $result = Expand-DocumentTemplate -Template $template -Variables @{}
            $result | Should Be 'Value: N/A'
        }
    }

    Context 'Template Engine - Conditionals' {
        It 'processes {{#if}} with true condition' {
            $template = '{{#if enabled}}Feature is ON{{/if}}'
            $result = Expand-DocumentTemplate -Template $template -Variables @{ enabled = $true }
            $result | Should Be 'Feature is ON'
        }

        It 'processes {{#if}} with false condition' {
            $template = '{{#if enabled}}Feature is ON{{/if}}'
            $result = Expand-DocumentTemplate -Template $template -Variables @{ enabled = $false }
            $result | Should Be ''
        }

        It 'processes {{#if}}{{else}}{{/if}} true branch' {
            $template = '{{#if active}}Active{{else}}Inactive{{/if}}'
            $result = Expand-DocumentTemplate -Template $template -Variables @{ active = $true }
            $result | Should Be 'Active'
        }

        It 'processes {{#if}}{{else}}{{/if}} false branch' {
            $template = '{{#if active}}Active{{else}}Inactive{{/if}}'
            $result = Expand-DocumentTemplate -Template $template -Variables @{ active = $false }
            $result | Should Be 'Inactive'
        }

        It 'treats empty string as false' {
            $template = '{{#if value}}Has value{{else}}Empty{{/if}}'
            $result = Expand-DocumentTemplate -Template $template -Variables @{ value = '' }
            $result | Should Be 'Empty'
        }

        It 'treats zero as false' {
            $template = '{{#if count}}Has items{{else}}No items{{/if}}'
            $result = Expand-DocumentTemplate -Template $template -Variables @{ count = 0 }
            $result | Should Be 'No items'
        }
    }

    Context 'Template Engine - Loops' {
        It 'processes {{#each}} with array of strings' {
            $template = '{{#each items}}- {{this}}{{/each}}'
            $result = Expand-DocumentTemplate -Template $template -Variables @{ items = @('A', 'B', 'C') }
            $result | Should Be '- A- B- C'
        }

        It 'processes {{#each}} with hashtable items' {
            $template = '{{#each devices}}| {{hostname}} | {{model}} |{{/each}}'
            $result = Expand-DocumentTemplate -Template $template -Variables @{
                devices = @(
                    @{ hostname = 'SW1'; model = 'C9300' }
                    @{ hostname = 'SW2'; model = 'C9200' }
                )
            }
            $result | Should Match 'SW1.*C9300'
            $result | Should Match 'SW2.*C9200'
        }

        It 'processes {{@index}} in loops' {
            $template = '{{#each items}}{{@index}}.{{this}} {{/each}}'
            $result = Expand-DocumentTemplate -Template $template -Variables @{ items = @('A', 'B') }
            $result | Should Match '1\.A'
            $result | Should Match '2\.B'
        }

        It 'handles empty array in loop' {
            $template = 'Items:{{#each items}}- {{this}}{{/each}}'
            $result = Expand-DocumentTemplate -Template $template -Variables @{ items = @() }
            $result | Should Be 'Items:'
        }
    }

    #endregion

    #region Template Management Tests

    Context 'Template Management - Create' {
        It 'creates a custom template' {
            $template = New-DocumentTemplate -Name 'Test Template' -Content 'Hello {{name}}' -Description 'Test desc'
            $template | Should Not BeNullOrEmpty
            $template.TemplateID | Should Match '^CUSTOM-'
            $template.Name | Should Be 'Test Template'
            $template.IsBuiltIn | Should Be $false
        }

        It 'sets template category to Custom by default' {
            $template = New-DocumentTemplate -Name 'Test' -Content 'Content'
            $template.Category | Should Be 'Custom'
        }

        It 'allows custom category' {
            $template = New-DocumentTemplate -Name 'Test' -Content 'Content' -Category 'Reports'
            $template.Category | Should Be 'Reports'
        }

        It 'records creation date' {
            $template = New-DocumentTemplate -Name 'Test' -Content 'Content'
            $template.CreatedDate | Should Not BeNullOrEmpty
        }
    }

    Context 'Template Management - Read' {
        It 'retrieves template by ID' {
            $created = New-DocumentTemplate -Name 'Test' -Content 'Content'
            $retrieved = Get-DocumentTemplate -TemplateID $created.TemplateID
            $retrieved.Name | Should Be 'Test'
        }

        It 'retrieves templates by category' {
            $templates = Get-DocumentTemplate -Category 'As-Built'
            @($templates).Count | Should BeGreaterThan 0
        }

        It 'searches templates by name' {
            $templates = Get-DocumentTemplate -Name 'Summary'
            @($templates).Count | Should BeGreaterThan 0
        }
    }

    Context 'Template Management - Update' {
        It 'updates custom template name' {
            $template = New-DocumentTemplate -Name 'Original' -Content 'Content'
            $updated = Update-DocumentTemplate -TemplateID $template.TemplateID -Name 'Updated'
            $updated.Name | Should Be 'Updated'
        }

        It 'updates template content' {
            $template = New-DocumentTemplate -Name 'Test' -Content 'Original'
            $updated = Update-DocumentTemplate -TemplateID $template.TemplateID -Content 'Updated content'
            $updated.Content | Should Be 'Updated content'
        }

        It 'increments version on update' {
            $template = New-DocumentTemplate -Name 'Test' -Content 'Content'
            $original = $template.Version
            $updated = Update-DocumentTemplate -TemplateID $template.TemplateID -Name 'Updated'
            $updated.Version | Should Not Be $original
        }

        It 'throws when updating built-in template' {
            { Update-DocumentTemplate -TemplateID 'Site-AsBuilt' -Name 'Renamed' } | Assert-Throws -Message 'Cannot modify built-in'
        }
    }

    Context 'Template Management - Delete' {
        It 'removes custom template' {
            $template = New-DocumentTemplate -Name 'ToDelete' -Content 'Content'
            Remove-DocumentTemplate -TemplateID $template.TemplateID
            $result = Get-DocumentTemplate -TemplateID $template.TemplateID
            $result | Should BeNullOrEmpty
        }

        It 'throws when removing built-in template' {
            { Remove-DocumentTemplate -TemplateID 'Site-AsBuilt' } | Assert-Throws -Message 'Cannot remove built-in'
        }
    }

    Context 'Template Validation' {
        It 'validates matching each blocks' {
            $result = Test-DocumentTemplate -Content '{{#each items}}{{/each}}'
            $result.IsValid | Should Be $true
        }

        It 'detects unmatched each blocks' {
            $result = Test-DocumentTemplate -Content '{{#each items}}'
            $result.IsValid | Should Be $false
            $result.Errors | Should Match 'Unmatched.*each'
        }

        It 'detects unmatched if blocks' {
            $result = Test-DocumentTemplate -Content '{{#if cond}}'
            $result.IsValid | Should Be $false
            $result.Errors | Should Match 'Unmatched.*if'
        }

        It 'extracts variable names' {
            $result = Test-DocumentTemplate -Content 'Hello {{name}}, your score is {{score}}'
            ($result.Variables -contains 'name') | Should Be $true
            ($result.Variables -contains 'score') | Should Be $true
        }
    }

    #endregion

    #region Document Generation Tests

    Context 'Document Generation - New-Document' {
        It 'generates document from template' {
            $doc = New-Document -TemplateID 'Site-AsBuilt' -Title 'Test Site Doc' -Variables @{ site_name = 'TestSite' }
            $doc | Should Not BeNullOrEmpty
            $doc.DocumentID | Should Match '^DOC-'
        }

        It 'includes generated_date variable by default' {
            $doc = New-Document -TemplateID 'Site-AsBuilt' -Title 'Test' -Variables @{ site_name = 'Test' }
            $doc.Variables.generated_date | Should Not BeNullOrEmpty
        }

        It 'extracts section headings' {
            $doc = New-Document -TemplateID 'Site-AsBuilt' -Title 'Test' -Variables @{ site_name = 'Test' }
            @($doc.Sections).Count | Should BeGreaterThan 0
        }

        It 'stores document in generated documents list' {
            $doc = New-Document -TemplateID 'Site-AsBuilt' -Title 'Test' -Variables @{ site_name = 'Test' }
            $retrieved = Get-GeneratedDocument -DocumentID $doc.DocumentID
            $retrieved | Should Not BeNullOrEmpty
        }

        It 'throws for non-existent template' {
            { New-Document -TemplateID 'NonExistent' -Title 'Test' } | Assert-Throws -Message 'not found'
        }
    }

    Context 'Document Generation - New-SiteAsBuilt' {
        It 'generates site as-built document' {
            $doc = New-SiteAsBuilt -SiteName 'WLLS' -SiteLocation 'Building A'
            $doc | Should Not BeNullOrEmpty
            $doc.Content | Should Match 'WLLS'
        }

        It 'includes device count' {
            $devices = @(
                @{ hostname = 'SW1'; vendor = 'Cisco'; model = 'C9300'; port_count = 48 }
                @{ hostname = 'SW2'; vendor = 'Cisco'; model = 'C9200'; port_count = 24 }
            )
            $doc = New-SiteAsBuilt -SiteName 'Test' -Devices $devices
            $doc.Variables.device_count | Should Be 2
        }

        It 'calculates total port count' {
            $devices = @(
                @{ hostname = 'SW1'; port_count = 48 }
                @{ hostname = 'SW2'; port_count = 24 }
            )
            $doc = New-SiteAsBuilt -SiteName 'Test' -Devices $devices
            $doc.Variables.port_count | Should Be 72
        }

        It 'adds table of contents when requested' {
            $doc = New-SiteAsBuilt -SiteName 'Test' -IncludeTOC
            $doc.TableOfContents | Should Not BeNullOrEmpty
        }
    }

    Context 'Document Generation - New-DeviceDocumentation' {
        It 'generates device documentation' {
            $doc = New-DeviceDocumentation -Hostname 'WLLS-A01-AS-01' -Vendor 'Cisco' -Model 'C9300'
            $doc | Should Not BeNullOrEmpty
            $doc.Content | Should Match 'WLLS-A01-AS-01'
        }

        It 'calculates port utilization' {
            $interfaces = @(
                @{ name = 'Gi1/0/1'; status = 'connected' }
                @{ name = 'Gi1/0/2'; status = 'connected' }
                @{ name = 'Gi1/0/3'; status = 'notconnect' }
                @{ name = 'Gi1/0/4'; status = 'notconnect' }
            )
            $doc = New-DeviceDocumentation -Hostname 'Test' -Interfaces $interfaces
            $doc.Variables.total_ports | Should Be 4
            $doc.Variables.connected_ports | Should Be 2
            $doc.Variables.utilization_percent | Should Be 50
        }

        It 'attaches hardware info' {
            $doc = New-DeviceDocumentation -Hostname 'Test' -Vendor 'Cisco' -Model 'C9300' -Serial 'FOC123'
            $doc.Hardware.Vendor | Should Be 'Cisco'
            $doc.Hardware.Model | Should Be 'C9300'
            $doc.Hardware.Serial | Should Be 'FOC123'
        }
    }

    Context 'Report Generation' {
        It 'generates executive report' {
            $doc = New-ExecutiveReport -ReportTitle 'Q1 Summary' -SiteCount 5 -DeviceCount 100
            $doc | Should Not BeNullOrEmpty
            $doc.Content | Should Match 'Q1 Summary'
        }

        It 'generates VLAN report' {
            $vlans = @(
                @{ id = 10; name = 'Data'; type = 'Standard' }
                @{ id = 20; name = 'Voice'; type = 'Voice' }
            )
            $doc = New-VLANReport -SiteName 'WLLS' -VLANs $vlans
            $doc | Should Not BeNullOrEmpty
            $doc.Content | Should Match 'Data'
        }

        It 'generates IP allocation report' {
            $subnets = @(
                @{ network = '10.0.0.0'; cidr = '/24'; purpose = 'Management' }
            )
            $doc = New-IPAllocationReport -SiteName 'WLLS' -Subnets $subnets
            $doc | Should Not BeNullOrEmpty
            $doc.Content | Should Match '10.0.0.0'
        }
    }

    #endregion

    #region Export Tests

    Context 'Export - Markdown' {
        It 'exports document as markdown' {
            $doc = New-SiteAsBuilt -SiteName 'TestExport'
            $tempPath = [System.IO.Path]::GetTempFileName() + '.md'
            try {
                $result = Export-Document -Document $doc -Format 'Markdown' -OutputPath $tempPath
                Test-Path $result | Should Be $true
                Get-Content $result -Raw | Should Match 'TestExport'
            }
            finally {
                if (Test-Path $tempPath) { Remove-Item $tempPath -Force }
            }
        }
    }

    Context 'Export - HTML' {
        It 'exports document as HTML' {
            $doc = New-SiteAsBuilt -SiteName 'HTMLTest'
            $tempPath = [System.IO.Path]::GetTempFileName() + '.html'
            try {
                $result = Export-Document -Document $doc -Format 'HTML' -OutputPath $tempPath
                Test-Path $result | Should Be $true
                $content = Get-Content $result -Raw
                $content | Should Match '<html>'
                $content | Should Match 'HTMLTest'
            }
            finally {
                if (Test-Path $tempPath) { Remove-Item $tempPath -Force }
            }
        }
    }

    Context 'Export - Text' {
        It 'exports document as plain text' {
            $doc = New-SiteAsBuilt -SiteName 'TextTest'
            $tempPath = [System.IO.Path]::GetTempFileName() + '.txt'
            try {
                $result = Export-Document -Document $doc -Format 'Text' -OutputPath $tempPath
                Test-Path $result | Should Be $true
                Get-Content $result -Raw | Should Match 'TextTest'
            }
            finally {
                if (Test-Path $tempPath) { Remove-Item $tempPath -Force }
            }
        }
    }

    Context 'Export - CSV' {
        It 'exports tables as CSV' {
            $devices = @(
                @{ hostname = 'SW1'; vendor = 'Cisco'; model = 'C9300'; role = 'Access'; location = 'MDF'; port_count = 48 }
            )
            $doc = New-SiteAsBuilt -SiteName 'CSVTest' -Devices $devices
            $tempPath = [System.IO.Path]::GetTempFileName() + '.csv'
            try {
                $result = Export-Document -Document $doc -Format 'CSV' -OutputPath $tempPath
                Test-Path $result | Should Be $true
                Get-Content $result -Raw | Should Match 'SW1'
            }
            finally {
                if (Test-Path $tempPath) { Remove-Item $tempPath -Force }
            }
        }
    }

    #endregion

    #region Scheduling Tests

    Context 'Document Scheduling' {
        It 'creates daily schedule' {
            $schedule = New-DocumentSchedule -TemplateID 'Site-AsBuilt' -Frequency 'Daily' -StartTime '08:00'
            $schedule | Should Not BeNullOrEmpty
            $schedule.Frequency | Should Be 'Daily'
        }

        It 'creates weekly schedule' {
            $schedule = New-DocumentSchedule -TemplateID 'Site-AsBuilt' -Frequency 'Weekly'
            $schedule.Frequency | Should Be 'Weekly'
        }

        It 'creates monthly schedule' {
            $schedule = New-DocumentSchedule -TemplateID 'Site-AsBuilt' -Frequency 'Monthly'
            $schedule.Frequency | Should Be 'Monthly'
        }

        It 'calculates next run time' {
            $schedule = New-DocumentSchedule -TemplateID 'Site-AsBuilt' -Frequency 'Daily' -StartTime '06:00'
            $schedule.NextRunTime | Should Not BeNullOrEmpty
        }

        It 'retrieves schedules' {
            $null = New-DocumentSchedule -TemplateID 'Site-AsBuilt' -Frequency 'Daily'
            $schedules = Get-DocumentSchedule
            @($schedules).Count | Should BeGreaterThan 0
        }

        It 'enables and disables schedule' {
            $schedule = New-DocumentSchedule -TemplateID 'Site-AsBuilt' -Frequency 'Daily'
            $schedule.IsEnabled | Should Be $false

            $null = Set-DocumentScheduleEnabled -ScheduleID $schedule.ScheduleID -IsEnabled $true
            $updated = Get-DocumentSchedule -ScheduleID $schedule.ScheduleID
            $updated.IsEnabled | Should Be $true
        }

        It 'removes schedule' {
            $schedule = New-DocumentSchedule -TemplateID 'Site-AsBuilt' -Frequency 'Daily'
            Remove-DocumentSchedule -ScheduleID $schedule.ScheduleID
            $result = Get-DocumentSchedule -ScheduleID $schedule.ScheduleID
            $result | Should BeNullOrEmpty
        }

        It 'throws for non-existent template' {
            { New-DocumentSchedule -TemplateID 'NonExistent' -Frequency 'Daily' } | Assert-Throws -Message 'not found'
        }
    }

    #endregion

    #region History Tests

    Context 'Document History' {
        It 'logs document generation' {
            $doc = New-Document -TemplateID 'Site-AsBuilt' -Title 'Test' -Variables @{ site_name = 'Test' }
            $history = Get-DocumentHistory -DocumentID $doc.DocumentID
            @($history).Count | Should BeGreaterThan 0
            $history[0].Action | Should Be 'Generated'
        }

        It 'logs document export' {
            $doc = New-SiteAsBuilt -SiteName 'HistoryTest'
            $tempPath = [System.IO.Path]::GetTempFileName() + '.md'
            try {
                $null = Export-Document -Document $doc -Format 'Markdown' -OutputPath $tempPath
                $history = Get-DocumentHistory -DocumentID $doc.DocumentID
                @($history | Where-Object { $_.Action -eq 'Exported' }).Count | Should BeGreaterThan 0
            }
            finally {
                if (Test-Path $tempPath) { Remove-Item $tempPath -Force }
            }
        }
    }

    #endregion

    #region Statistics Tests

    Context 'Statistics' {
        It 'returns document statistics' {
            $null = New-SiteAsBuilt -SiteName 'Stats1'
            $null = New-SiteAsBuilt -SiteName 'Stats2'
            $stats = Get-DocumentStatistics
            $stats.TotalDocuments | Should BeGreaterThan 1
        }

        It 'counts built-in templates' {
            $stats = Get-DocumentStatistics
            $stats.BuiltInTemplates | Should Be 7
        }

        It 'groups documents by template' {
            $null = New-SiteAsBuilt -SiteName 'Group1'
            $null = New-SiteAsBuilt -SiteName 'Group2'
            $stats = Get-DocumentStatistics
            $stats.ByTemplate['Site-AsBuilt'] | Should BeGreaterThan 1
        }
    }

    #endregion

    #region Document Retrieval and Removal Tests

    Context 'Document Retrieval' {
        It 'retrieves documents by scope' {
            $null = New-SiteAsBuilt -SiteName 'WLLS'
            $null = New-SiteAsBuilt -SiteName 'BOYO'
            $docs = Get-GeneratedDocument -Scope 'WLLS'
            @($docs).Count | Should BeGreaterThan 0
            @($docs)[0].Scope | Should Be 'WLLS'
        }

        It 'retrieves documents by template' {
            $null = New-SiteAsBuilt -SiteName 'Test'
            $docs = Get-GeneratedDocument -TemplateID 'Site-AsBuilt'
            @($docs).Count | Should BeGreaterThan 0
        }

        It 'sorts documents by date descending' {
            $null = New-SiteAsBuilt -SiteName 'First'
            Start-Sleep -Milliseconds 50
            $null = New-SiteAsBuilt -SiteName 'Second'
            $docs = Get-GeneratedDocument
            $docs[0].Variables.site_name | Should Be 'Second'
        }
    }

    Context 'Document Removal' {
        It 'removes generated document' {
            $doc = New-SiteAsBuilt -SiteName 'ToRemove'
            Remove-GeneratedDocument -DocumentID $doc.DocumentID
            $result = Get-GeneratedDocument -DocumentID $doc.DocumentID
            $result | Should BeNullOrEmpty
        }

        It 'throws for non-existent document' {
            { Remove-GeneratedDocument -DocumentID 'DOC-00000000-0000' } | Assert-Throws -Message 'not found'
        }
    }

    #endregion

    #region ST-AA-003: Word/PDF Export Tests

    Context 'Word (.docx) Export' {
        BeforeAll {
            $script:wordTestDir = Join-Path $env:TEMP 'WordExportTest'
            if (-not (Test-Path $script:wordTestDir)) {
                New-Item -ItemType Directory -Path $script:wordTestDir -Force | Out-Null
            }
        }

        AfterAll {
            if (Test-Path $script:wordTestDir) {
                Remove-Item -Path $script:wordTestDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'exports document to Word format' {
            $doc = New-SiteAsBuilt -SiteName 'WordTest' -Devices @(
                @{ hostname = 'SW-01'; vendor = 'Cisco'; model = 'C9300'; role = 'Access'; location = 'MDF'; port_count = 48 }
            )
            $outputPath = Join-Path $script:wordTestDir 'test.docx'

            $result = Export-Document -Document $doc -Format Word -OutputPath $outputPath

            Test-Path $result | Should Be $true
        }

        It 'creates valid ZIP archive (docx format)' {
            $doc = New-SiteAsBuilt -SiteName 'ZipTest'
            $outputPath = Join-Path $script:wordTestDir 'ziptest.docx'

            Export-Document -Document $doc -Format Word -OutputPath $outputPath

            # Verify it's a valid ZIP by trying to open it
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead($outputPath)
            $zip.Entries.Count | Should BeGreaterThan 0
            $zip.Dispose()
        }

        It 'includes document.xml in docx' {
            $doc = New-SiteAsBuilt -SiteName 'XmlTest'
            $outputPath = Join-Path $script:wordTestDir 'xmltest.docx'

            Export-Document -Document $doc -Format Word -OutputPath $outputPath

            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead($outputPath)
            $docEntry = $zip.Entries | Where-Object { $_.FullName -match 'word[/\\]document\.xml$' }
            $docEntry | Should Not BeNullOrEmpty
            $zip.Dispose()
        }

        It 'includes styles.xml in docx' {
            $doc = New-SiteAsBuilt -SiteName 'StylesTest'
            $outputPath = Join-Path $script:wordTestDir 'stylestest.docx'

            Export-Document -Document $doc -Format Word -OutputPath $outputPath

            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead($outputPath)
            $stylesEntry = $zip.Entries | Where-Object { $_.FullName -match 'word[/\\]styles\.xml$' }
            $stylesEntry | Should Not BeNullOrEmpty
            $zip.Dispose()
        }

        It 'includes Content_Types.xml in docx' {
            $doc = New-SiteAsBuilt -SiteName 'ContentTypesTest'
            $outputPath = Join-Path $script:wordTestDir 'contenttypestest.docx'

            Export-Document -Document $doc -Format Word -OutputPath $outputPath

            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead($outputPath)
            $contentEntry = $zip.Entries | Where-Object { $_.FullName -eq '[Content_Types].xml' }
            $contentEntry | Should Not BeNullOrEmpty
            $zip.Dispose()
        }

        It 'handles tables in Word export' {
            $doc = New-SiteAsBuilt -SiteName 'TableTest' -Devices @(
                @{ hostname = 'SW-01'; vendor = 'Cisco'; model = 'C9300'; role = 'Access'; location = 'MDF'; port_count = 48 },
                @{ hostname = 'SW-02'; vendor = 'Arista'; model = '7050X'; role = 'Core'; location = 'MDF'; port_count = 52 }
            )
            $outputPath = Join-Path $script:wordTestDir 'tabletest.docx'

            Export-Document -Document $doc -Format Word -OutputPath $outputPath

            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead($outputPath)
            $docEntry = $zip.Entries | Where-Object { $_.FullName -match 'word[/\\]document\.xml$' }
            $stream = $docEntry.Open()
            $reader = New-Object System.IO.StreamReader($stream)
            $content = $reader.ReadToEnd()
            $reader.Dispose()
            $stream.Dispose()
            $zip.Dispose()

            $content | Should Match '<w:tbl>'
        }
    }

    Context 'PDF Export' {
        BeforeAll {
            $script:pdfTestDir = Join-Path $env:TEMP 'PDFExportTest'
            if (-not (Test-Path $script:pdfTestDir)) {
                New-Item -ItemType Directory -Path $script:pdfTestDir -Force | Out-Null
            }
        }

        AfterAll {
            if (Test-Path $script:pdfTestDir) {
                Remove-Item -Path $script:pdfTestDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'exports document to PDF-ready HTML format' {
            $doc = New-SiteAsBuilt -SiteName 'PDFTest'
            $outputPath = Join-Path $script:pdfTestDir 'test.html'

            $result = Export-Document -Document $doc -Format PDF -OutputPath $outputPath -WarningAction SilentlyContinue

            Test-Path $result | Should Be $true
        }

        It 'includes print-specific CSS' {
            $doc = New-SiteAsBuilt -SiteName 'PrintCSSTest'
            $outputPath = Join-Path $script:pdfTestDir 'printcss.html'

            Export-Document -Document $doc -Format PDF -OutputPath $outputPath -WarningAction SilentlyContinue

            $content = Get-Content -Path $outputPath -Raw
            $content | Should Match '@page'
            $content | Should Match '@media print'
        }

        It 'includes page size settings' {
            $doc = New-SiteAsBuilt -SiteName 'PageSizeTest'
            $outputPath = Join-Path $script:pdfTestDir 'pagesize.html'

            Export-Document -Document $doc -Format PDF -OutputPath $outputPath -WarningAction SilentlyContinue

            $content = Get-Content -Path $outputPath -Raw
            $content | Should Match 'size:\s*letter'
        }

        It 'includes footer with generation info' {
            $doc = New-SiteAsBuilt -SiteName 'FooterTest'
            $outputPath = Join-Path $script:pdfTestDir 'footer.html'

            Export-Document -Document $doc -Format PDF -OutputPath $outputPath -WarningAction SilentlyContinue

            $content = Get-Content -Path $outputPath -Raw
            $content | Should Match 'StateTrace Documentation Generator'
            $content | Should Match 'Save as PDF'
        }
    }

    Context 'WordML Content Validation' {
        It 'converts headings to WordML styles in docx' {
            $templateContent = @'
# Heading 1
## Heading 2
### Heading 3
'@
            $template = New-DocumentTemplate -Name 'HeadingTestTemplate' -Content $templateContent -Category 'Test'
            $doc = New-Document -TemplateID $template.TemplateID -Title 'HeadingTest'
            $outputPath = Join-Path $script:wordTestDir 'HeadingTest.docx'
            Export-Document -Document $doc -Format Word -OutputPath $outputPath

            # Read document.xml from ZIP
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead($outputPath)
            $docEntry = $zip.Entries | Where-Object { $_.FullName -match 'word[/\\]document\.xml$' }
            $stream = $docEntry.Open()
            $reader = New-Object System.IO.StreamReader($stream)
            $docXml = $reader.ReadToEnd()
            $reader.Dispose()
            $stream.Dispose()
            $zip.Dispose()

            $docXml | Should Match 'w:pStyle w:val="Heading1"'
            $docXml | Should Match 'w:pStyle w:val="Heading2"'
            $docXml | Should Match 'w:pStyle w:val="Heading3"'
        }

        It 'converts bold text to WordML runs in docx' {
            $templateContent = 'This is **bold** text.'
            $template = New-DocumentTemplate -Name 'BoldTestTemplate' -Content $templateContent -Category 'Test'
            $doc = New-Document -TemplateID $template.TemplateID -Title 'BoldTest'
            $outputPath = Join-Path $script:wordTestDir 'BoldTest.docx'
            Export-Document -Document $doc -Format Word -OutputPath $outputPath

            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead($outputPath)
            $docEntry = $zip.Entries | Where-Object { $_.FullName -match 'word[/\\]document\.xml$' }
            $stream = $docEntry.Open()
            $reader = New-Object System.IO.StreamReader($stream)
            $docXml = $reader.ReadToEnd()
            $reader.Dispose()
            $stream.Dispose()
            $zip.Dispose()

            $docXml | Should Match '<w:b/>'
        }

        It 'escapes special XML characters in docx' {
            $templateContent = 'Test with <angle> & "quotes"'
            $template = New-DocumentTemplate -Name 'EscapeTestTemplate' -Content $templateContent -Category 'Test'
            $doc = New-Document -TemplateID $template.TemplateID -Title 'EscapeTest'
            $outputPath = Join-Path $script:wordTestDir 'EscapeTest.docx'
            Export-Document -Document $doc -Format Word -OutputPath $outputPath

            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead($outputPath)
            $docEntry = $zip.Entries | Where-Object { $_.FullName -match 'word[/\\]document\.xml$' }
            $stream = $docEntry.Open()
            $reader = New-Object System.IO.StreamReader($stream)
            $docXml = $reader.ReadToEnd()
            $reader.Dispose()
            $stream.Dispose()
            $zip.Dispose()

            $docXml | Should Match '&lt;angle&gt;'
            $docXml | Should Match '&amp;'
        }
    }

    #endregion
}
