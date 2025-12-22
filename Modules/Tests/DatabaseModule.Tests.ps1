Set-StrictMode -Version Latest

Describe "DatabaseModule ConvertTo-DbRowList" {
    BeforeAll {
        $modulePath = Join-Path (Split-Path $PSCommandPath) "..\\DatabaseModule.psm1"
        Import-Module (Resolve-Path $modulePath) -Force
    }

    AfterAll {
        Remove-Module DatabaseModule -Force
    }

    It "flattens DataTable rows" {
        $dt = New-Object System.Data.DataTable
        [void]$dt.Columns.Add("Name") 
        $row1 = $dt.NewRow(); $row1.Name = 'a'; $dt.Rows.Add($row1) | Out-Null
        $row2 = $dt.NewRow(); $row2.Name = 'b'; $dt.Rows.Add($row2) | Out-Null

        $rows = DatabaseModule\ConvertTo-DbRowList -Data $dt
        $rows.Count | Should Be 2
        ($rows[0].Name) | Should Be 'a'
        ($rows[1].Name) | Should Be 'b'
    }

    It "preserves enumerable items" {
        $items = @(
            [pscustomobject]@{ Value = 1 },
            [pscustomobject]@{ Value = 2 }
        )

        $rows = DatabaseModule\ConvertTo-DbRowList -Data $items
        $rows.Count | Should Be 2
        ($rows[0].Value) | Should Be 1
        ($rows[1].Value) | Should Be 2
    }

    It "returns an empty collection for null input" {
        $rows = DatabaseModule\ConvertTo-DbRowList -Data $null
        $rows = @($rows)
        $rows.Count | Should Be 0
    }
}

Describe "DatabaseModule Invoke-DbSchemaStatement" {
    BeforeAll {
        $modulePath = Join-Path (Split-Path $PSCommandPath) "..\\DatabaseModule.psm1"
        Import-Module (Resolve-Path $modulePath) -Force
    }

    AfterAll {
        Remove-Module DatabaseModule -Force
    }

    It "returns true when Execute succeeds" {
        InModuleScope DatabaseModule {
            $calls = [System.Collections.Generic.List[string]]::new()
            $connection = [pscustomobject]@{}
            $connection | Add-Member -MemberType ScriptMethod -Name Execute -Value {
                param($statement)
                $calls.Add($statement) | Out-Null
                return $null
            }

            $result = Invoke-DbSchemaStatement -Connection $connection -Statement 'SELECT 1' -Label 'Test'
            $result | Should Be $true
            $calls.Count | Should Be 1
        }
    }

    It "ignores already exists when requested" {
        InModuleScope DatabaseModule {
            $connection = [pscustomobject]@{}
            $connection | Add-Member -MemberType ScriptMethod -Name Execute -Value {
                throw [System.Exception]::new('Table already exists')
            }

            $result = Invoke-DbSchemaStatement -Connection $connection -Statement 'CREATE TABLE X' -IgnoreIfExists
            $result | Should Be $false
        }
    }

    It "warns and continues when ContinueOnFailure is set" {
        InModuleScope DatabaseModule {
            $connection = [pscustomobject]@{}
            $connection | Add-Member -MemberType ScriptMethod -Name Execute -Value {
                throw [System.Exception]::new('boom')
            }

            Mock -CommandName Write-Warning -ModuleName DatabaseModule
            $result = Invoke-DbSchemaStatement -Connection $connection -Statement 'CREATE TABLE X' -ContinueOnFailure
            $result | Should Be $false
            Assert-MockCalled Write-Warning -ModuleName DatabaseModule -Times 1
        }
    }

    It "throws when failure is not ignored" {
        InModuleScope DatabaseModule {
            $connection = [pscustomobject]@{}
            $connection | Add-Member -MemberType ScriptMethod -Name Execute -Value {
                throw [System.Exception]::new('boom')
            }

            $threw = $false
            try {
                Invoke-DbSchemaStatement -Connection $connection -Statement 'CREATE TABLE X' -Label 'Test'
            } catch {
                $threw = $true
            }
            $threw | Should Be $true
        }
    }
}
