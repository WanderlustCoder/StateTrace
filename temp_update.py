from pathlib import Path
import re

path = Path("Modules/ParserPersistenceModule.psm1")
text = path.read_text(newline='')

if "$script:AdTypeVarChar" not in text:
    text = text.replace("$script:AdTypeVarWChar = 202\r\n    $script:AdTypeLongVarWChar = 203",
                        "$script:AdTypeVarWChar = 202\r\n    $script:AdTypeVarChar = 200\r\n    $script:AdTypeLongVarChar = 201\r\n    $script:AdTypeLongVarWChar = 203", 1)

new_provider = (
    "function Get-InterfaceBulkProviderInfo {\r\n"
    "    [CmdletBinding()]\r\n"
    "    param(\r\n"
    "        [Parameter(Mandatory=$true)][object]$Connection\r\n"
    "    )\r\n\r\n"
    "    if (-not (Test-IsAdodbConnection -Connection $Connection)) {\r\n"
    "        return [PSCustomObject]@{\r\n"
    "            Name = $null\r\n"
    "            Kind = 'Unknown'\r\n"
    "            TextParameterType = $script:AdTypeVarWChar\r\n"
    "            MemoParameterType = $script:AdTypeLongVarWChar\r\n"
    "        }\r\n"
    "    }\r\n\r\n"
    "    $providerName = $null\r\n"
    "    try {\r\n"
    "        if ($Connection.PSObject.Properties.Name -contains 'Provider') {\r\n"
    "            $candidate = [string]$Connection.Provider\r\n"
    "            if (-not [string]::IsNullOrWhiteSpace($candidate)) { $providerName = $candidate }\r\n"
    "        }\r\n"
    "    } catch { }\r\n\r\n"
    "    if (-not $providerName) {\r\n"
    "        try {\r\n"
    "            if ($Connection.PSObject.Properties.Name -contains 'ConnectionString') {\r\n"
    "                $connString = [string]$Connection.ConnectionString\r\n"
    "                if (-not [string]::IsNullOrWhiteSpace($connString)) {\r\n"
    "                    foreach ($segment in ($connString -split ';')) {\r\n"
    "                        if ($segment -match '^\\s*Provider\\s*=\\s*(.+?)\\s*$') {\r\n"
    "                            $providerName = $matches[1].Trim()\r\n"
    "                            break\r\n"
    "                        }\r\n"
    "                    }\r\n"
    "                }\r\n"
    "            }\r\n"
    "        } catch { }\r\n"
    "    }\r\n\r\n"
    "    $providerKind = 'Unknown'\r\n"
    "    if ($providerName) {\r\n"
    "        if ($providerName -match '(?i)ACE\\.OLEDB') {\r\n"
    "            $providerKind = 'ACE'\r\n"
    "        } elseif ($providerName -match '(?i)Jet\\.OLEDB') {\r\n"
    "            $providerKind = 'Jet'\r\n"
    "        }\r\n"
    "    }\r\n\r\n"
    "    $textType = $script:AdTypeVarWChar\r\n"
    "    $memoType = $script:AdTypeLongVarWChar\r\n\r\n"
    "    if ($providerKind -eq 'Jet') {\r\n"
    "        $textType = $script:AdTypeVarChar\r\n"
    "        $memoType = $script:AdTypeLongVarChar\r\n"
    "    }\r\n\r\n"
    "    return [PSCustomObject]@{\r\n"
    "        Name = if ($providerName) { $providerName } else { $null }\r\n"
    "        Kind = $providerKind\r\n"
    "        TextParameterType = [int]$textType\r\n"
    "        MemoParameterType = [int]$memoType\r\n"
    "    }\r\n"
    "}\r\n\r\n"
)

if 'function Get-InterfaceBulkProviderInfo' not in text:
    anchor = 'function Test-IsAdodbConnection {'
    idx = text.find(anchor)
    if idx == -1:
        raise SystemExit('anchor for provider info insertion not found')
    text = text[:idx] + new_provider + text[idx:]
else:
    # replace existing definition if present
    def find_function_span(src: str, name: str):
        ident = f"function {name}"
        start = src.find(ident)
        if start == -1:
            raise ValueError(f"function {name} not found")
        idx = start
        brace_count = 0
        inside = False
        length = len(src)
        while idx < length:
            ch = src[idx]
            if ch == '{':
                brace_count += 1
                inside = True
            elif ch == '}':
                brace_count -= 1
                if inside and brace_count == 0:
                    end = idx + 1
                    while end < length and src[end] in '\r\n':
                        end += 1
                    return start, end
            idx += 1
        raise ValueError(f"Could not determine span for {name}")
    start, end = find_function_span(text, 'Get-InterfaceBulkProviderInfo')
    text = text[:start] + new_provider + text[end:]

# helper to get function spans
if 'function Get-InterfaceBulkProviderInfo' not in text:
    raise SystemExit('failed to insert Get-InterfaceBulkProviderInfo')

def find_function_span(src: str, name: str):
    ident = f"function {name}"
    start = src.find(ident)
    if start == -1:
        raise ValueError(f"function {name} not found")
    idx = start
    brace_count = 0
    inside = False
    length = len(src)
    while idx < length:
        ch = src[idx]
        if ch == '{':
            brace_count += 1
            inside = True
        elif ch == '}':
            brace_count -= 1
            if inside and brace_count == 0:
                end = idx + 1
                while end < length and src[end] in '\r\n':
                    end += 1
                return start, end
        idx += 1
    raise ValueError(f"Could not determine span for {name}")

# modify Invoke-InterfaceBulkInsertInternal
start, end = find_function_span(text, 'Invoke-InterfaceBulkInsertInternal')
func = text[start:end]
old_block = (
    "    $providerName = $null\r\n"
    "    $providerKind = 'Unknown'\r\n"
    "    if ($providerInfo) {\r\n"
    "        try {\r\n"
    "            $candidateName = $providerInfo['Name']\r\n"
    "            if (-not [string]::IsNullOrWhiteSpace($candidateName)) { $providerName = $candidateName }\r\n"
    "        } catch { }\r\n"
    "        try {\r\n"
    "            $candidateKind = $providerInfo['Kind']\r\n"
    "            if (-not [string]::IsNullOrWhiteSpace($candidateKind)) { $providerKind = $candidateKind }\r\n"
    "        } catch { }\r\n"
    "    }\r\n"
)
if old_block not in func:
    raise SystemExit('provider block not found in Invoke-InterfaceBulkInsertInternal')
new_block = (
    "    $providerName = $null\r\n"
    "    $providerKind = 'Unknown'\r\n"
    "    $textParameterType = $script:AdTypeVarWChar\r\n"
    "    $memoParameterType = $script:AdTypeLongVarWChar\r\n"
    "    if ($providerInfo) {\r\n"
    "        try {\r\n"
    "            $candidateName = $providerInfo.Name\r\n"
    "            if (-not [string]::IsNullOrWhiteSpace($candidateName)) { $providerName = $candidateName }\r\n"
    "        } catch { }\r\n"
    "        try {\r\n"
    "            $candidateKind = $providerInfo.Kind\r\n"
    "            if (-not [string]::IsNullOrWhiteSpace($candidateKind)) { $providerKind = $candidateKind }\r\n"
    "        } catch { }\r\n"
    "        try {\r\n"
    "            if ($providerInfo.PSObject.Properties.Name -contains 'TextParameterType') {\r\n"
    "                $candidateTextType = $providerInfo.TextParameterType\r\n"
    "                if ($null -ne $candidateTextType) { $textParameterType = [int]$candidateTextType }\r\n"
    "            }\r\n"
    "        } catch { }\r\n"
    "        try {\r\n"
    "            if ($providerInfo.PSObject.Properties.Name -contains 'MemoParameterType') {\r\n"
    "                $candidateMemoType = $providerInfo.MemoParameterType\r\n"
    "                if ($null -ne $candidateMemoType) { $memoParameterType = [int]$candidateMemoType }\r\n"
    "            }\r\n"
    "        } catch { }\r\n"
    "    }\r\n"
)
func = func.replace(old_block, new_block, 1)
func = func.replace("$providerInfo['Name']", "$providerInfo.Name")
func = func.replace("$providerInfo['Kind']", "$providerInfo.Kind")
func = func.replace('$script:AdTypeVarWChar', '$textParameterType')
func = func.replace('$script:AdTypeLongVarWChar', '$memoParameterType')
text = text[:start] + func + text[end:]

insert_block = (
    "    $textParameterType = $script:AdTypeVarWChar\r\n"
    "    $memoParameterType = $script:AdTypeLongVarWChar\r\n"
    "    $providerInfo = Get-InterfaceBulkProviderInfo -Connection $Connection\r\n"
    "    if ($providerInfo) {\r\n"
    "        try {\r\n"
    "            if ($providerInfo.PSObject.Properties.Name -contains 'TextParameterType') {\r\n"
    "                $candidateTextType = $providerInfo.TextParameterType\r\n"
    "                if ($null -ne $candidateTextType) { $textParameterType = [int]$candidateTextType }\r\n"
    "            }\r\n"
    "        } catch { }\r\n"
    "        try {\r\n"
    "            if ($providerInfo.PSObject.Properties.Name -contains 'MemoParameterType') {\r\n"
    "                $candidateMemoType = $providerInfo.MemoParameterType\r\n"
    "                if ($null -ne $candidateMemoType) { $memoParameterType = [int]$candidateMemoType }\r\n"
    "            }\r\n"
    "        } catch { }\r\n"
    "    }\r\n\r\n"
)

for func_name in ('Invoke-DeviceSummaryParameterized', 'Invoke-InterfaceRowParameterized'):
    start, end = find_function_span(text, func_name)
    func = text[start:end]
    pattern = re.compile(r"(    \)\r\n)")
    match = pattern.search(func)
    if not match:
        raise SystemExit(f'could not locate insertion point in {func_name}')
    insert_point = match.end(1)
    func = func[:insert_point] + insert_block + func[insert_point:]
    func = func.replace('$script:AdTypeVarWChar', '$textParameterType')
    func = func.replace('$script:AdTypeLongVarWChar', '$memoParameterType')
    text = text[:start] + func + text[end:]

path.write_text(text, newline='')
