Set-StrictMode -Version Latest

$modulePath = Join-Path $PSScriptRoot '..\CommandReferenceModule.psm1'
Import-Module $modulePath -Force -ErrorAction Stop

Describe 'CommandReferenceModule - Vendor Functions' -Tag 'CommandReference', 'Unit' {

    Context 'Get-SupportedVendors' {
        It 'returns list of supported vendors' {
            $vendors = Get-SupportedVendors

            $vendors -contains 'Cisco' | Should Be $true
            $vendors -contains 'Arista' | Should Be $true
            $vendors -contains 'Juniper' | Should Be $true
            $vendors -contains 'HP' | Should Be $true
        }

        It 'returns vendors in sorted order' {
            $vendors = Get-SupportedVendors

            $vendors[0] | Should Be 'Arista'
            $vendors[1] | Should Be 'Cisco'
        }
    }

    Context 'Get-VendorInfo' {
        It 'returns vendor metadata for valid vendor' {
            $info = Get-VendorInfo -Name 'Cisco'

            $info.Name | Should Be 'Cisco'
            $info.SyntaxStyle | Should Be 'IOS'
            $info.Aliases -contains 'IOS-XE' | Should Be $true
        }

        It 'resolves vendor aliases' {
            $info = Get-VendorInfo -Name 'IOS-XE'

            $info.Name | Should Be 'Cisco'
        }

        It 'handles case-insensitive lookup' {
            $info = Get-VendorInfo -Name 'cisco'

            $info.Name | Should Be 'Cisco'
        }

        It 'returns null for unknown vendor' {
            $info = Get-VendorInfo -Name 'UnknownVendor'

            $info | Should BeNullOrEmpty
        }
    }

    Context 'Get-CommandCategories' {
        It 'returns available categories' {
            $categories = Get-CommandCategories

            $categories.Name -contains 'Show' | Should Be $true
            $categories.Name -contains 'Routing' | Should Be $true
            $categories.Name -contains 'Switching' | Should Be $true
        }

        It 'includes descriptions' {
            $categories = Get-CommandCategories

            $routing = $categories | Where-Object { $_.Name -eq 'Routing' }
            $routing.Description | Should Not BeNullOrEmpty
        }
    }
}

Describe 'CommandReferenceModule - Command Lookup' -Tag 'CommandReference', 'Unit' {

    Context 'Get-NetworkCommand' {
        It 'retrieves command by exact match' {
            $cmd = Get-NetworkCommand -Command 'show ip route' -Vendor 'Cisco'

            $cmd | Should Not BeNullOrEmpty
            $cmd.Vendor | Should Be 'Cisco'
            $cmd.Command | Should Be 'show ip route'
            $cmd.Category | Should Be 'Routing'
        }

        It 'retrieves command with prefix match' {
            $cmd = Get-NetworkCommand -Command 'show ip route 10.0.0.0' -Vendor 'Cisco'

            $cmd | Should Not BeNullOrEmpty
            $cmd.Command | Should Be 'show ip route'
        }

        It 'returns syntax information' {
            $cmd = Get-NetworkCommand -Command 'show ip route' -Vendor 'Cisco'

            $cmd.Syntax | Should Not BeNullOrEmpty
            $cmd.Syntax | Should Match 'show ip route'
        }

        It 'returns status codes when available' {
            $cmd = Get-NetworkCommand -Command 'show ip route' -Vendor 'Cisco'

            $cmd.StatusCodes | Should Not BeNullOrEmpty
            $cmd.StatusCodes['C'] | Should Be 'Connected'
            $cmd.StatusCodes['O'] | Should Be 'OSPF'
        }

        It 'returns null for unknown command' {
            $cmd = Get-NetworkCommand -Command 'show nonexistent' -Vendor 'Cisco'

            $cmd | Should BeNullOrEmpty
        }

        It 'handles vendor aliases' {
            $cmd = Get-NetworkCommand -Command 'show ip route' -Vendor 'IOS-XE'

            $cmd | Should Not BeNullOrEmpty
            $cmd.Vendor | Should Be 'Cisco'
        }
    }

    Context 'Search-NetworkCommands' {
        It 'finds commands by keyword' {
            $results = Search-NetworkCommands -Keyword 'interface'

            $results.Count | Should BeGreaterThan 3
        }

        It 'filters by vendor' {
            $results = Search-NetworkCommands -Keyword 'route' -Vendor 'Cisco'

            $results | ForEach-Object { $_.Vendor | Should Be 'Cisco' }
        }

        It 'filters by category' {
            $results = Search-NetworkCommands -Keyword 'show' -Category 'Routing'

            $results | ForEach-Object { $_.Category | Should Be 'Routing' }
        }

        It 'searches in descriptions' {
            $results = Search-NetworkCommands -Keyword 'neighbor'

            $results.Count | Should BeGreaterThan 0
        }
    }

    Context 'Find-CommandByTask' {
        It 'finds commands by task description' {
            $results = Find-CommandByTask -Task 'show routing table'

            $results.Count | Should BeGreaterThan 0
        }

        It 'returns vendors for each task' {
            $results = Find-CommandByTask -Task 'show vlan'

            $results[0].Vendors | Should Not BeNullOrEmpty
        }

        It 'sorts by match score descending' {
            $results = Find-CommandByTask -Task 'ip route'

            # First result should have highest score
            $results[0].MatchScore | Should BeGreaterThan 0
        }
    }
}

Describe 'CommandReferenceModule - Translation' -Tag 'CommandReference', 'Unit' {

    Context 'Convert-NetworkCommand' {
        It 'translates command between identical syntax vendors' {
            $result = Convert-NetworkCommand `
                -Command 'show ip interface brief' `
                -FromVendor 'Cisco' `
                -ToVendor 'Arista'

            $result.Success | Should Be $true
            $result.TranslatedCommand | Should Be 'show ip interface brief'
            $result.HasEquivalent | Should Be $true
        }

        It 'translates command with different syntax' {
            $result = Convert-NetworkCommand `
                -Command 'show ip route' `
                -FromVendor 'Cisco' `
                -ToVendor 'Juniper'

            $result.Success | Should Be $true
            $result.TranslatedCommand | Should Be 'show route'
        }

        It 'includes translation notes' {
            $result = Convert-NetworkCommand `
                -Command 'show ip route' `
                -FromVendor 'Cisco' `
                -ToVendor 'Arista'

            $result.Notes | Should Not BeNullOrEmpty
        }

        It 'handles commands with no equivalent' {
            $result = Convert-NetworkCommand `
                -Command 'show cdp neighbors' `
                -FromVendor 'Cisco' `
                -ToVendor 'Juniper'

            $result.HasEquivalent | Should Be $false
        }

        It 'returns error for unknown source vendor' {
            $result = Convert-NetworkCommand `
                -Command 'show ip route' `
                -FromVendor 'UnknownVendor' `
                -ToVendor 'Cisco'

            $result.Success | Should Be $false
            $result.Error | Should Match 'Unknown.*vendor'
        }

        It 'returns error for unknown command' {
            $result = Convert-NetworkCommand `
                -Command 'show nonexistent' `
                -FromVendor 'Cisco' `
                -ToVendor 'Arista'

            $result.Success | Should Be $false
            $result.HasEquivalent | Should Be $false
        }

        It 'preserves task context in result' {
            $result = Convert-NetworkCommand `
                -Command 'show spanning-tree' `
                -FromVendor 'Cisco' `
                -ToVendor 'Arista'

            $result.Task | Should Not BeNullOrEmpty
            $result.Category | Should Be 'Switching'
        }
    }

    Context 'Get-CommandComparison' {
        It 'returns side-by-side comparison' {
            $comparison = Get-CommandComparison -Task 'show routing table'

            $comparison.Count | Should BeGreaterThan 0
            $comparison[0].Cisco | Should Not BeNullOrEmpty
            $comparison[0].Arista | Should Not BeNullOrEmpty
        }

        It 'filters to specified vendors' {
            $comparison = Get-CommandComparison -Task 'vlan' -Vendors @('Cisco', 'Arista')

            $comparison[0].PSObject.Properties.Name -contains 'Cisco' | Should Be $true
            $comparison[0].PSObject.Properties.Name -contains 'Arista' | Should Be $true
        }
    }
}

Describe 'CommandReferenceModule - Config Snippets' -Tag 'CommandReference', 'Unit' {

    Context 'Get-ConfigSnippet' {
        It 'retrieves snippet by task name' {
            $snippet = Get-ConfigSnippet -Task 'VLAN' -Vendor 'Cisco'

            $snippet | Should Not BeNullOrEmpty
            $snippet.Template | Should Match 'vlan'
        }

        It 'returns required variables' {
            $snippet = Get-ConfigSnippet -Task 'Create VLAN' -Vendor 'Cisco'

            $snippet.Variables -contains 'vlan_id' | Should Be $true
            $snippet.Variables -contains 'vlan_name' | Should Be $true
        }

        It 'returns null for unknown task' {
            $snippet = Get-ConfigSnippet -Task 'NonexistentTask' -Vendor 'Cisco'

            $snippet | Should BeNullOrEmpty
        }

        It 'handles different vendors' {
            $ciscoSnippet = Get-ConfigSnippet -Task 'trunk' -Vendor 'Cisco'
            $juniperSnippet = Get-ConfigSnippet -Task 'trunk' -Vendor 'Juniper'

            $ciscoSnippet.Template | Should Not Be $juniperSnippet.Template
        }
    }

    Context 'Expand-ConfigSnippet' {
        It 'expands variables in template' {
            $snippet = Get-ConfigSnippet -Task 'VLAN' -Vendor 'Cisco'
            $config = Expand-ConfigSnippet -Snippet $snippet -Variables @{
                vlan_id = 100
                vlan_name = 'Users'
            }

            $config | Should Match 'vlan 100'
            $config | Should Match 'name Users'
        }

        It 'preserves unmatched placeholders' {
            $snippet = Get-ConfigSnippet -Task 'VLAN' -Vendor 'Cisco'
            $config = Expand-ConfigSnippet -Snippet $snippet -Variables @{
                vlan_id = 100
            }

            $config | Should Match 'vlan 100'
            $config | Should Match '\{\{vlan_name\}\}'
        }
    }

    Context 'Get-ConfigSnippets' {
        It 'lists all snippets' {
            $snippets = Get-ConfigSnippets

            $snippets.Count | Should BeGreaterThan 2
        }

        It 'filters by category' {
            $snippets = Get-ConfigSnippets -Category 'Switching'

            $snippets | ForEach-Object { $_.Category | Should Be 'Switching' }
        }

        It 'filters by vendor' {
            $snippets = Get-ConfigSnippets -Vendor 'Arista'

            $snippets | ForEach-Object { $_.Vendors -contains 'Arista' | Should Be $true }
        }

        It 'returns task names and variables' {
            $snippets = Get-ConfigSnippets

            $snippets[0].TaskName | Should Not BeNullOrEmpty
            $snippets[0].Variables | Should Not BeNullOrEmpty
        }
    }

    Context 'Test-ConfigSnippet' {
        It 'validates complete variable set' {
            $snippet = Get-ConfigSnippet -Task 'VLAN' -Vendor 'Cisco'
            $validation = Test-ConfigSnippet -Snippet $snippet -Variables @{
                vlan_id = 100
                vlan_name = 'Users'
            }

            $validation.IsValid | Should Be $true
            $validation.MissingVariables.Count | Should Be 0
        }

        It 'identifies missing variables' {
            $snippet = Get-ConfigSnippet -Task 'VLAN' -Vendor 'Cisco'
            $validation = Test-ConfigSnippet -Snippet $snippet -Variables @{
                vlan_id = 100
            }

            $validation.IsValid | Should Be $false
            $validation.MissingVariables -contains 'vlan_name' | Should Be $true
        }

        It 'returns all required variables' {
            $snippet = Get-ConfigSnippet -Task 'trunk' -Vendor 'Cisco'
            $validation = Test-ConfigSnippet -Snippet $snippet -Variables @{}

            $validation.RequiredVariables.Count | Should BeGreaterThan 2
        }
    }
}

Describe 'CommandReferenceModule - Output Helpers' -Tag 'CommandReference', 'Unit' {

    Context 'Get-OutputFormat' {
        It 'returns column information' {
            $format = Get-OutputFormat -Command 'show interface status' -Vendor 'Cisco'

            $format | Should Not BeNullOrEmpty
            $format.Columns -contains 'Status' | Should Be $true
            $format.Columns -contains 'Vlan' | Should Be $true
        }

        It 'returns null for unknown command' {
            $format = Get-OutputFormat -Command 'show nonexistent' -Vendor 'Cisco'

            $format | Should BeNullOrEmpty
        }
    }

    Context 'Get-StatusCodes' {
        It 'returns status code definitions' {
            $codes = Get-StatusCodes -Command 'show ip route' -Vendor 'Cisco'

            $codes.Count | Should BeGreaterThan 0
            $codes['C'] | Should Be 'Connected'
            $codes['S'] | Should Be 'Static'
        }
    }
}

Describe 'CommandReferenceModule - Integration' -Tag 'CommandReference', 'Integration' {

    Context 'Real-World Translation Scenarios' {
        It 'translates common show commands Cisco to Arista' {
            $commands = @(
                'show ip route',
                'show ip interface brief',
                'show vlan brief',
                'show spanning-tree'
            )

            foreach ($cmd in $commands) {
                $result = Convert-NetworkCommand -Command $cmd -FromVendor 'Cisco' -ToVendor 'Arista'
                $result.Success | Should Be $true
            }
        }

        It 'translates Cisco to Juniper routing command' {
            $result = Convert-NetworkCommand -Command 'show ip route' -FromVendor 'Cisco' -ToVendor 'Juniper'
            $result.TranslatedCommand | Should Be 'show route'
        }
    }

    Context 'Configuration Snippet Workflows' {
        It 'generates valid VLAN configuration for Cisco' {
            $snippet = Get-ConfigSnippet -Task 'VLAN' -Vendor 'Cisco'
            $config = Expand-ConfigSnippet -Snippet $snippet -Variables @{
                vlan_id = 100
                vlan_name = 'TestVLAN'
            }
            $config | Should Match '100'
        }

        It 'generates valid trunk configuration for Cisco' {
            $snippet = Get-ConfigSnippet -Task 'trunk' -Vendor 'Cisco'
            $validation = Test-ConfigSnippet -Snippet $snippet -Variables @{
                interface = 'GigabitEthernet1/0/24'
                allowed_vlans = '10,20,30'
                native_vlan = '1'
                description = 'Uplink'
            }

            $validation.IsValid | Should Be $true

            $config = Expand-ConfigSnippet -Snippet $snippet -Variables @{
                interface = 'GigabitEthernet1/0/24'
                allowed_vlans = '10,20,30'
                native_vlan = '1'
                description = 'Uplink'
            }

            $config | Should Match 'interface GigabitEthernet1/0/24'
            $config | Should Match 'switchport mode trunk'
        }
    }
}

#region ST-AD-006: Learning Mode Tests

Describe 'CommandReferenceModule - Learning Mode' -Tag 'CommandReference', 'LearningMode', 'Unit' {

    Context 'New-CommandQuiz' {
        It 'generates translation quiz questions' {
            $quiz = New-CommandQuiz -Type Translation -Count 5

            $quiz | Should Not BeNullOrEmpty
            $quiz.QuizId | Should Not BeNullOrEmpty
            $quiz.Type | Should Be 'Translation'
            $quiz.Questions.Count | Should Be 5
        }

        It 'includes source command and correct answer' {
            $quiz = New-CommandQuiz -Type Translation -Count 3

            $quiz.Questions[0].SourceCommand | Should Not BeNullOrEmpty
            $quiz.Questions[0].CorrectAnswer | Should Not BeNullOrEmpty
            $quiz.Questions[0].Options.Count | Should BeGreaterThan 1
        }

        It 'generates options including correct answer' {
            $quiz = New-CommandQuiz -Count 5

            foreach ($q in $quiz.Questions) {
                $q.Options -contains $q.CorrectAnswer | Should Be $true
            }
        }

        It 'filters by category' {
            $quiz = New-CommandQuiz -Category 'Routing' -Count 10

            foreach ($q in $quiz.Questions) {
                $q.Category | Should Be 'Routing'
            }
        }

        It 'limits to specified vendors' {
            $quiz = New-CommandQuiz -Vendors @('Cisco', 'Arista') -Count 5

            foreach ($q in $quiz.Questions) {
                @('Cisco', 'Arista') -contains $q.SourceVendor | Should Be $true
                @('Cisco', 'Arista') -contains $q.TargetVendor | Should Be $true
            }
        }

        It 'returns null when fewer than 2 vendors specified' {
            $quiz = New-CommandQuiz -Vendors @('Cisco') -Count 5 -WarningAction SilentlyContinue

            $quiz | Should BeNullOrEmpty
        }
    }

    Context 'Submit-QuizAnswers' {
        BeforeEach {
            Reset-LearningProgress -User 'testuser' | Out-Null
        }

        It 'scores correct answers' {
            $quiz = New-CommandQuiz -Count 3
            $answers = @(
                @{ QuestionIndex = 0; Answer = $quiz.Questions[0].CorrectAnswer }
            )

            $result = Submit-QuizAnswers -Quiz $quiz -Answers $answers -User 'testuser'

            $result.Correct | Should Be 1
            $result.Incorrect | Should Be 0
        }

        It 'scores incorrect answers' {
            $quiz = New-CommandQuiz -Count 3
            $answers = @(
                @{ QuestionIndex = 0; Answer = 'wrong answer' }
            )

            $result = Submit-QuizAnswers -Quiz $quiz -Answers $answers -User 'testuser'

            $result.Correct | Should Be 0
            $result.Incorrect | Should Be 1
        }

        It 'calculates percentage correctly' {
            $quiz = New-CommandQuiz -Count 4
            $answers = @(
                @{ QuestionIndex = 0; Answer = $quiz.Questions[0].CorrectAnswer },
                @{ QuestionIndex = 1; Answer = 'wrong' }
            )

            $result = Submit-QuizAnswers -Quiz $quiz -Answers $answers -User 'testuser'

            $result.Percentage | Should Be 50
        }

        It 'tracks unanswered questions' {
            $quiz = New-CommandQuiz -Count 5
            $answers = @(
                @{ QuestionIndex = 0; Answer = $quiz.Questions[0].CorrectAnswer }
            )

            $result = Submit-QuizAnswers -Quiz $quiz -Answers $answers -User 'testuser'

            $result.Unanswered | Should Be 4
        }

        It 'returns detailed results' {
            $quiz = New-CommandQuiz -Count 2
            $answers = @(
                @{ QuestionIndex = 0; Answer = $quiz.Questions[0].CorrectAnswer },
                @{ QuestionIndex = 1; Answer = 'wrong' }
            )

            $result = Submit-QuizAnswers -Quiz $quiz -Answers $answers -User 'testuser'

            $result.Results.Count | Should Be 2
            $result.Results[0].IsCorrect | Should Be $true
            $result.Results[1].IsCorrect | Should Be $false
        }
    }

    Context 'Get-LearningProgress' {
        BeforeEach {
            Reset-LearningProgress -User 'progresstest' | Out-Null
        }

        It 'returns zero progress for new user' {
            $progress = Get-LearningProgress -User 'newuser'

            $progress.TotalQuizzes | Should Be 0
            $progress.TotalQuestions | Should Be 0
            $progress.AverageScore | Should Be 0
        }

        It 'tracks progress after quiz submission' {
            $quiz = New-CommandQuiz -Count 2
            $answers = @(
                @{ QuestionIndex = 0; Answer = $quiz.Questions[0].CorrectAnswer },
                @{ QuestionIndex = 1; Answer = $quiz.Questions[1].CorrectAnswer }
            )
            Submit-QuizAnswers -Quiz $quiz -Answers $answers -User 'progresstest' | Out-Null

            $progress = Get-LearningProgress -User 'progresstest'

            $progress.TotalQuizzes | Should Be 1
            $progress.TotalQuestions | Should Be 2
            $progress.TotalCorrect | Should Be 2
            $progress.AverageScore | Should Be 100
        }

        It 'accumulates progress across multiple quizzes' {
            $quiz1 = New-CommandQuiz -Count 2
            $quiz2 = New-CommandQuiz -Count 2

            Submit-QuizAnswers -Quiz $quiz1 -Answers @(
                @{ QuestionIndex = 0; Answer = $quiz1.Questions[0].CorrectAnswer }
                @{ QuestionIndex = 1; Answer = 'wrong' }
            ) -User 'progresstest' | Out-Null

            Submit-QuizAnswers -Quiz $quiz2 -Answers @(
                @{ QuestionIndex = 0; Answer = $quiz2.Questions[0].CorrectAnswer }
                @{ QuestionIndex = 1; Answer = $quiz2.Questions[1].CorrectAnswer }
            ) -User 'progresstest' | Out-Null

            $progress = Get-LearningProgress -User 'progresstest'

            $progress.TotalQuizzes | Should Be 2
            $progress.TotalQuestions | Should Be 4
            $progress.TotalCorrect | Should Be 3
            $progress.AverageScore | Should Be 75
        }

        It 'maintains quiz history' {
            $quiz = New-CommandQuiz -Count 2
            Submit-QuizAnswers -Quiz $quiz -Answers @(
                @{ QuestionIndex = 0; Answer = $quiz.Questions[0].CorrectAnswer }
            ) -User 'progresstest' | Out-Null

            $progress = Get-LearningProgress -User 'progresstest'

            $progress.QuizHistory.Count | Should Be 1
            $progress.QuizHistory[0].QuizId | Should Be $quiz.QuizId
        }
    }

    Context 'Reset-LearningProgress' {
        It 'clears user progress' {
            $quiz = New-CommandQuiz -Count 2
            Submit-QuizAnswers -Quiz $quiz -Answers @(
                @{ QuestionIndex = 0; Answer = $quiz.Questions[0].CorrectAnswer }
            ) -User 'resettest' | Out-Null

            Reset-LearningProgress -User 'resettest'

            $progress = Get-LearningProgress -User 'resettest'
            $progress.TotalQuizzes | Should Be 0
        }
    }

    Context 'New-FlashCards' {
        It 'generates flash cards with front and back' {
            $cards = New-FlashCards -Count 5

            $cards.Count | Should Be 5
            $cards[0].Front | Should Not BeNullOrEmpty
            $cards[0].Back | Should Not BeNullOrEmpty
        }

        It 'includes task description on front' {
            $cards = New-FlashCards -Count 10

            foreach ($card in $cards) {
                $card.Front | Should Not BeNullOrEmpty
            }
        }

        It 'includes vendor commands on back' {
            $cards = New-FlashCards -Vendors @('Cisco', 'Arista') -Count 5

            foreach ($card in $cards) {
                $card.Back | Should Match 'Cisco:'
                $card.Back | Should Match 'Arista:'
            }
        }

        It 'filters by category' {
            $cards = New-FlashCards -Category 'Routing' -Count 10

            foreach ($card in $cards) {
                $card.Category | Should Be 'Routing'
            }
        }

        It 'respects count limit' {
            $cards = New-FlashCards -Count 3

            $cards.Count -le 3 | Should Be $true
        }

        It 'includes multiple vendors when specified' {
            $cards = New-FlashCards -Vendors @('Cisco', 'Arista', 'Juniper') -Count 5

            foreach ($card in $cards) {
                $card.Back | Should Match 'Cisco:'
                $card.Back | Should Match 'Arista:'
                $card.Back | Should Match 'Juniper:'
            }
        }
    }
}

#endregion
