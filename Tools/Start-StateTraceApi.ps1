<#
.SYNOPSIS
Starts the StateTrace REST API server.

.DESCRIPTION
Lightweight HTTP API using HttpListener for external integrations.
Provides endpoints for device inventory, interface status, and alerts.

.PARAMETER Port
Port to listen on. Default 8080.

.PARAMETER Prefix
URL prefix. Default 'http://localhost'.

.PARAMETER EnableCors
Enable CORS headers for cross-origin requests.

.PARAMETER ApiKey
Optional API key for authentication.

.EXAMPLE
.\Start-StateTraceApi.ps1 -Port 8080

.EXAMPLE
.\Start-StateTraceApi.ps1 -Port 9000 -ApiKey 'secret123' -EnableCors
#>

[CmdletBinding()]
param(
    [int]$Port = 8080,
    [string]$Prefix = 'http://localhost',
    [switch]$EnableCors,
    [string]$ApiKey
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$projectRoot = Split-Path -Parent $PSScriptRoot

# Import modules
Import-Module (Join-Path $projectRoot 'Modules\IntegrationApiModule.psm1') -Force -DisableNameChecking

# Create listener
$listener = [System.Net.HttpListener]::new()
$baseUrl = "${Prefix}:${Port}/"
$listener.Prefixes.Add($baseUrl)

Write-Host @"

╔═══════════════════════════════════════════════════════════════╗
║              StateTrace REST API Server                        ║
╚═══════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

Write-Host "Starting API server on $baseUrl" -ForegroundColor Green
Write-Host "Press Ctrl+C to stop`n" -ForegroundColor Gray

# API routes
$routes = @{
    'GET /api/health' = { Get-ApiHealth }
    'GET /api/devices' = { param($Request) Get-ApiDevices -Request $Request }
    'GET /api/devices/{id}' = { param($Request, $Params) Get-ApiDeviceById -DeviceId $Params.id }
    'GET /api/interfaces' = { param($Request) Get-ApiInterfaces -Request $Request }
    'GET /api/interfaces/{device}' = { param($Request, $Params) Get-ApiInterfacesByDevice -Device $Params.device }
    'GET /api/alerts' = { param($Request) Get-ApiAlerts -Request $Request }
    'GET /api/alerts/active' = { Get-ApiActiveAlerts }
    'GET /api/alerts/summary' = { Get-ApiAlertSummary }
    'POST /api/alerts/{id}/acknowledge' = { param($Request, $Params) Set-ApiAlertAcknowledged -AlertId $Params.id }
    'DELETE /api/alerts/{id}' = { param($Request, $Params) Remove-ApiAlert -AlertId $Params.id }
    'GET /api/vendors' = { Get-ApiVendors }
    'GET /api/stats' = { Get-ApiStats }
}

function Send-Response {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [int]$StatusCode = 200,
        [object]$Body,
        [string]$ContentType = 'application/json'
    )

    $Response.StatusCode = $StatusCode
    $Response.ContentType = $ContentType

    if ($EnableCors.IsPresent) {
        $Response.Headers.Add('Access-Control-Allow-Origin', '*')
        $Response.Headers.Add('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS')
        $Response.Headers.Add('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-API-Key')
    }

    $jsonBody = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 10 -Compress }
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)
    $Response.ContentLength64 = $buffer.Length
    $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $Response.OutputStream.Close()
}

function Send-Error {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [int]$StatusCode,
        [string]$Message
    )

    $errorBody = @{
        error = $true
        status = $StatusCode
        message = $Message
        timestamp = [datetime]::UtcNow.ToString('o')
    }

    Send-Response -Response $Response -StatusCode $StatusCode -Body $errorBody
}

function Get-RouteMatch {
    param(
        [string]$Method,
        [string]$Path
    )

    $path = $Path.TrimEnd('/')
    if (-not $path) { $path = '/' }

    foreach ($route in $routes.Keys) {
        $parts = $route -split ' ', 2
        $routeMethod = $parts[0]
        $routePath = $parts[1]

        if ($Method -ne $routeMethod) { continue }

        # Check for exact match
        if ($routePath -eq $path) {
            return @{ Handler = $routes[$route]; Params = @{} }
        }

        # Check for parameterized match
        $routePattern = $routePath -replace '\{(\w+)\}', '(?<$1>[^/]+)'
        $routePattern = "^$routePattern$"

        if ($path -match $routePattern) {
            $params = @{}
            foreach ($key in $Matches.Keys) {
                if ($key -ne '0') {
                    $params[$key] = $Matches[$key]
                }
            }
            return @{ Handler = $routes[$route]; Params = $params }
        }
    }

    return $null
}

function Get-QueryParams {
    param([string]$QueryString)

    $params = @{}
    if (-not $QueryString) { return $params }

    $QueryString.TrimStart('?').Split('&') | ForEach-Object {
        $kv = $_ -split '=', 2
        if ($kv.Length -eq 2) {
            $params[[System.Web.HttpUtility]::UrlDecode($kv[0])] = [System.Web.HttpUtility]::UrlDecode($kv[1])
        }
    }

    return $params
}

try {
    $listener.Start()
    Write-Host "API server listening on $baseUrl" -ForegroundColor Green
    Write-Host "`nEndpoints:" -ForegroundColor Yellow
    foreach ($route in ($routes.Keys | Sort-Object)) {
        Write-Host "  $route" -ForegroundColor Gray
    }
    Write-Host ""

    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        $method = $request.HttpMethod
        $path = $request.Url.AbsolutePath
        $query = $request.Url.Query

        $timestamp = Get-Date -Format 'HH:mm:ss'
        Write-Host "[$timestamp] $method $path$query" -ForegroundColor Gray

        try {
            # Handle CORS preflight
            if ($method -eq 'OPTIONS') {
                Send-Response -Response $response -StatusCode 204 -Body ''
                continue
            }

            # Check API key if configured
            if ($ApiKey) {
                $providedKey = $request.Headers['X-API-Key']
                if (-not $providedKey) {
                    $authHeader = $request.Headers['Authorization']
                    if ($authHeader -and $authHeader.StartsWith('Bearer ')) {
                        $providedKey = $authHeader.Substring(7)
                    }
                }

                if ($providedKey -ne $ApiKey) {
                    Send-Error -Response $response -StatusCode 401 -Message 'Invalid or missing API key'
                    continue
                }
            }

            # Find matching route
            $match = Get-RouteMatch -Method $method -Path $path

            if (-not $match) {
                Send-Error -Response $response -StatusCode 404 -Message "Endpoint not found: $method $path"
                continue
            }

            # Build request object
            $apiRequest = @{
                Method = $method
                Path = $path
                Query = Get-QueryParams -QueryString $query
                Headers = @{}
                Body = $null
            }

            foreach ($header in $request.Headers.AllKeys) {
                $apiRequest.Headers[$header] = $request.Headers[$header]
            }

            if ($request.HasEntityBody) {
                $reader = [System.IO.StreamReader]::new($request.InputStream)
                $bodyText = $reader.ReadToEnd()
                $reader.Close()
                try {
                    $apiRequest.Body = $bodyText | ConvertFrom-Json
                } catch {
                    $apiRequest.Body = $bodyText
                }
            }

            # Execute handler
            $result = & $match.Handler $apiRequest $match.Params

            if ($result -is [hashtable] -and $result.ContainsKey('StatusCode')) {
                Send-Response -Response $response -StatusCode $result.StatusCode -Body $result.Body
            } else {
                Send-Response -Response $response -Body $result
            }

        } catch {
            Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
            Send-Error -Response $response -StatusCode 500 -Message $_.Exception.Message
        }
    }
} finally {
    if ($listener.IsListening) {
        $listener.Stop()
    }
    $listener.Close()
    Write-Host "`nAPI server stopped" -ForegroundColor Yellow
}
