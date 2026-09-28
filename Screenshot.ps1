<#
.SYNOPSIS
    Captures the primary monitor and uploads the screenshot to a ScreenshotCloud site.

.DESCRIPTION
    Screenshot.ps1 takes a PNG screenshot of the entire primary monitor using
    System.Drawing / System.Windows.Forms, POSTs it to <Site>/api/upload with your
    upload key, parses the JSON response and prints the public Vercel Blob URL.

    Compatible with Windows 10 / Windows 11, Windows PowerShell 5.1 and PowerShell 7+.
    No WSL, Linux tools, Python or browser are required.

    Configuration is resolved in this order:
      1. -Site / -UploadKey command line parameters
      2. The $Site / $UploadKey variables below
      3. SCREENSHOTCLOUD_SITE / SCREENSHOTCLOUD_UPLOAD_KEY environment variables
      4. %LOCALAPPDATA%\ScreenshotCloud\config.ps1 (written by the installer)

.PARAMETER Site
    Base URL of the deployed site, for example https://my-site.vercel.app

.PARAMETER UploadKey
    The SCREENSHOT_UPLOAD_KEY value configured on the server. Never logged or printed.

.PARAMETER Help
    Print this help text and exit.

.EXAMPLE
    .\Screenshot.ps1 -Site "https://my-site.vercel.app" -UploadKey "MY_SECRET"

.EXAMPLE
    .\Screenshot.ps1
    $link = .\Screenshot.ps1 | Select-Object -Last 1

.NOTES
    This script only captures the screen when you run it. It never runs on a
    schedule, never runs in the background and never opens a browser.
#>

#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Site,

    [Parameter()]
    [string]$UploadKey,

    [Parameter()]
    [switch]$Help
)

# Capture values supplied on the command line before the configuration block
# below is applied, so that parameters always win.
$ParamSite      = $Site
$ParamUploadKey = $UploadKey

# ===========================================================================
# CONFIGURATION
# Set the two values below if you prefer editing the script itself.
# Leave them empty to use -Site / -UploadKey, environment variables, or the
# config file created by Install-ScreenshotCloud.ps1.
# ===========================================================================
$Site      = ""
$UploadKey = ""
# ===========================================================================

$script:IsDotSourced = $MyInvocation.InvocationName -eq "."
$script:ExitCode     = 0
$script:TempFiles    = @()

$ErrorActionPreference = "Continue"

# ---------------------------------------------------------------------------
# Small output helpers
# ---------------------------------------------------------------------------

function Write-Info([string]$Message) {
    Write-Host ("  " + $Message) -ForegroundColor DarkGray
}

function Write-Ok([string]$Message) {
    Write-Host ("  [ok] " + $Message) -ForegroundColor Green
}

function Write-WarnText([string]$Message) {
    Write-Host ("  [!] " + $Message) -ForegroundColor Yellow
}

function Write-Fail([string]$Message) {
    Write-Host ""
    Write-Host ("ERROR: " + $Message) -ForegroundColor Red
}

function New-TempFile([string]$Extension) {
    $path = [System.IO.Path]::Combine(
        [System.IO.Path]::GetTempPath(),
        ("ScreenshotCloud-" + [guid]::NewGuid().ToString("N") + $Extension)
    )
    $script:TempFiles += $path
    return $path
}

function Remove-TempFiles {
    foreach ($path in $script:TempFiles) {
        if ($path -and (Test-Path -LiteralPath $path)) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }
    $script:TempFiles = @()
}

function Stop-Screenshot([string]$Message, [int]$Code = 1) {
    $script:ExitCode = $Code
    throw $Message
}

function Show-Usage {
    @"

ScreenshotCloud - PowerShell screenshot uploader
===============================================

Usage:
  .\Screenshot.ps1 [-Site <url>] [-UploadKey <secret>]
  .\Screenshot.ps1 -Help

Parameters:
  -Site        Base URL of your ScreenshotCloud deployment
               Example: -Site "https://my-site.vercel.app"
  -UploadKey   Your SCREENSHOT_UPLOAD_KEY. Never printed by this script.
  -Help        Show this message.

Environment variables (used when a parameter is not supplied):
  SCREENSHOTCLOUD_SITE          Base URL of the site
  SCREENSHOTCLOUD_UPLOAD_KEY    Upload key

Config file (used when neither of the above is set):
  `$env:LOCALAPPDATA\ScreenshotCloud\config.ps1

Examples:
  .\Screenshot.ps1 -Site "https://my-site.vercel.app" -UploadKey "MY_SECRET"
  `$link = .\Screenshot.ps1 | Select-Object -Last 1

"@ | Write-Host
}

# ---------------------------------------------------------------------------
# Configuration resolution
# ---------------------------------------------------------------------------

function Get-FirstNonEmpty([object[]]$Values) {
    foreach ($value in $Values) {
        if ($null -ne $value) {
            $text = [string]$value
            if ($text.Trim().Length -gt 0) { return $text.Trim() }
        }
    }
    return ""
}

function Read-ScreenshotCloudConfig([string]$Path) {
    $empty = [pscustomobject]@{ Site = ""; UploadKey = "" }

    if ([string]::IsNullOrWhiteSpace($Path)) { return $empty }
    if (-not (Test-Path -LiteralPath $Path)) { return $empty }

    try {
        # Dot-source inside a child scope so the config file can set $Site and
        # $UploadKey without overwriting the values we already resolved.
        $loaded = & {
            $Site      = $null
            $UploadKey = $null
            . $Path
            [pscustomobject]@{
                Site      = $(if ($Site) { [string]$Site } else { "" })
                UploadKey = $(if ($UploadKey) { [string]$UploadKey } else { "" })
            }
        }
        if ($loaded) { return $loaded }
    }
    catch {
        Write-WarnText ("Could not read config file: " + $_.Exception.Message)
    }

    return $empty
}

# ---------------------------------------------------------------------------
# Screenshot capture
# ---------------------------------------------------------------------------

function Enable-DpiAwareness {
    if (-not ("ScreenshotCloud.NativeMethods" -as [type])) {
        Add-Type -Namespace ScreenshotCloud -Name NativeMethods -MemberDefinition @"
[DllImport("user32.dll")]
public static extern bool SetProcessDPIAware();
"@
    }
    try { [ScreenshotCloud.NativeMethods]::SetProcessDPIAware() | Out-Null } catch { }
}

function Capture-PrimaryScreen {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    }
    catch {
        Stop-Screenshot ("Could not load System.Windows.Forms / System.Drawing: " + $_.Exception.Message)
    }

    Enable-DpiAwareness

    $bitmap   = $null
    $graphics = $null

    try {
        $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        if ($null -eq $bounds -or $bounds.Width -le 0 -or $bounds.Height -le 0) {
            Stop-Screenshot "Could not determine the size of the primary monitor."
        }

        Write-Info ("Capturing primary monitor (" + [string]$bounds.Width + " x " + [string]$bounds.Height + ")...")

        $bitmap = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.CopyFromScreen(
            $bounds.Location,
            [System.Drawing.Point]::Empty,
            $bounds.Size
        )

        $path = New-TempFile ".png"
        $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)

        if (-not (Test-Path -LiteralPath $path)) {
            Stop-Screenshot "The screenshot file was not written to disk."
        }

        $length = (Get-Item -LiteralPath $path).Length
        if ($length -le 0) {
            Stop-Screenshot "The captured screenshot is empty."
        }

        Write-Ok ("Captured " + [math]::Round($length / 1KB, 1) + " KB")
        return $path
    }
    catch {
        if ($script:ExitCode -eq 0) {
            Stop-Screenshot ("Screenshot capture failed: " + $_.Exception.Message)
        }
        throw
    }
    finally {
        if ($null -ne $graphics) { $graphics.Dispose() }
        if ($null -ne $bitmap)   { $bitmap.Dispose() }
    }
}

# ---------------------------------------------------------------------------
# Upload
# ---------------------------------------------------------------------------

function Get-CurlPath {
    $command = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    if (Test-Path -LiteralPath "$env:SystemRoot\System32\curl.exe") {
        return "$env:SystemRoot\System32\curl.exe"
    }
    return $null
}

function ConvertTo-CurlConfigValue([string]$Value) {
    return ($Value -replace "\\", "\\" -replace """", "\""")
}

function Invoke-CurlUpload(
    [string]$CurlPath,
    [string]$UploadUrl,
    [string]$FilePath,
    [string]$Key,
    [string]$BodyPath
) {
    $headerPath = New-TempFile ".curlheader"
    $header     = "header = """ + (ConvertTo-CurlConfigValue ("Authorization: Bearer " + $Key)) + """"

    # Written as ASCII and passed with -K so the upload key never appears on the
    # command line (where other processes could read it) or in the terminal.
    [System.IO.File]::WriteAllText($headerPath, $header + "`r`n", [System.Text.Encoding]::ASCII)

    $arguments = @(
        "-s",
        "-X", "POST",
        $UploadUrl,
        "-K", $headerPath,
        "-F", ("file=@" + $FilePath + ";type=image/png"),
        "-o", $BodyPath,
        "-w", "%{http_code}",
        "--max-time", "180"
    )

    $rawCode = & $CurlPath @arguments
    $exitCode = $LASTEXITCODE

    Remove-Item -LiteralPath $headerPath -Force -ErrorAction SilentlyContinue

    $statusCode = $null
    $rawText    = ("$rawCode").Trim()
    if ($rawText -match "(\d+)\s*$") {
        $statusCode = [int]$Matches[1]
    }

    return [pscustomobject]@{
        ExitCode   = $exitCode
        StatusCode = $statusCode
        Raw        = $rawText
    }
}

function Get-WebRequestParams(
    [string]$UploadUrl,
    [string]$FilePath,
    [string]$Key,
    [string]$ContentType
) {
    $params = @{
        Uri         = $UploadUrl
        Method      = "Post"
        Headers     = @{ Authorization = "Bearer " + $Key }
        ContentType = $ContentType
        InFile      = $FilePath
        TimeoutSec  = 180
    }

    # -UseBasicParsing only matters for Windows PowerShell 5.1 but is accepted
    # (and ignored) by PowerShell 7, so it is always passed.
    $params["UseBasicParsing"] = $true
    return $params
}

function Get-HttpErrorDetails([object]$Exception) {
    $status  = $null
    $body    = ""

    $response = $null
    if ($Exception.PSObject.Properties["Response"]) {
        $response = $Exception.Response
    }

    if ($null -ne $response) {
        try {
            $status = [int]$response.StatusCode
        }
        catch { }

        try {
            # PowerShell 7 throws HttpResponseException (System.Net.Http response)
            if ($response.PSObject.Properties["Content"] -and $null -ne $response.Content) {
                $body = [string]$response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            }
            else {
                # Windows PowerShell 5.1 throws WebException (HttpWebResponse)
                $stream = $response.GetResponseStream()
                if ($null -ne $stream) {
                    $stream.Position = 0
                    $reader = New-Object System.IO.StreamReader($stream)
                    try { $body = $reader.ReadToEnd() } finally { $reader.Dispose() }
                }
            }
        }
        catch { }
    }

    return [pscustomobject]@{ StatusCode = $status; Body = $body }
}

function Send-ScreenshotUpload(
    [string]$UploadUrl,
    [string]$FilePath,
    [string]$Key
) {
    $bodyPath   = New-TempFile ".response"
    $curlPath   = Get-CurlPath
    $status     = $null
    $body       = ""
    $transport  = ""

    if ($curlPath) {
        $transport = "curl.exe"
        $result = Invoke-CurlUpload -CurlPath $curlPath -UploadUrl $UploadUrl -FilePath $FilePath -Key $Key -BodyPath $bodyPath

        if ($result.ExitCode -ne 0) {
            $messages = @{
                6  = "Could not resolve the host name. Check your internet connection and the -Site URL."
                7  = "Could not connect to the site. It may be down or your internet connection is unavailable."
                28 = "The upload timed out. Check your connection and try again."
                35 = "A TLS/SSL handshake error occurred. Check that -Site uses https://"
                60 = "The site's TLS certificate could not be verified."
            }
            $detail = $messages[$result.ExitCode]
            if (-not $detail) { $detail = "curl.exe failed with exit code " + $result.ExitCode + "." }
            Stop-Screenshot ("Upload failed (" + $detail + ")")
        }

        $status = $result.StatusCode
        if (Test-Path -LiteralPath $bodyPath) {
            $body = [System.IO.File]::ReadAllText($bodyPath)
        }
    }
    else {
        $transport = "Invoke-WebRequest"
        Write-WarnText "curl.exe not found - falling back to Invoke-WebRequest."

        $params = Get-WebRequestParams -UploadUrl $UploadUrl -FilePath $FilePath -Key $Key -ContentType "image/png"

        try {
            $response = Invoke-WebRequest @params
            $status   = [int]$response.StatusCode
            $body     = [string]$response.Content
        }
        catch {
            $details = Get-HttpErrorDetails -Exception $_.Exception
            if ($null -ne $details.StatusCode) {
                $status = $details.StatusCode
                $body   = $details.Body
            }
            else {
                Stop-Screenshot ("Could not reach the site: " + $_.Exception.Message)
            }
        }
    }

    return [pscustomobject]@{
        Transport = $transport
        Status    = $status
        Body      = $body
    }
}

function Convert-ResponseToUrl([string]$Body) {
    if ([string]::IsNullOrWhiteSpace($Body)) { return $null }

    try {
        $json = $Body | ConvertFrom-Json
    }
    catch {
        return $null
    }

    if ($null -eq $json) { return $null }

    $property = $json.PSObject.Properties["url"]
    if ($property -and $property.Value) { return [string]$property.Value }
    return $null
}

function Get-ResponseMessage([string]$Body) {
    if ([string]::IsNullOrWhiteSpace($Body)) { return "" }
    try { $json = $Body | ConvertFrom-Json } catch { return "" }
    if ($null -eq $json) { return "" }
    $property = $json.PSObject.Properties["message"]
    if ($property -and $property.Value) { return [string]$property.Value }
    return ""
}

function Show-UploadError([object]$Result) {
    $status  = $Result.Status
    $message = Get-ResponseMessage -Body $Result.Body

    if ($null -eq $status) {
        Stop-Screenshot ("No valid HTTP status was returned. The site may be unreachable, or a " +
            "proxy / captive portal returned an HTML page instead of JSON.")
    }

    switch ($status) {
        401 {
            $text = "The upload key was rejected (HTTP 401)."
            if ($message) { $text += " Server said: " + $message }
            $text += " Check that -UploadKey / SCREENSHOTCLOUD_UPLOAD_KEY matches SCREENSHOT_UPLOAD_KEY on the server."
            Stop-Screenshot $text 401
        }
        403 {
            $text = "The request was forbidden (HTTP 403)."
            if ($message) { $text += " Server said: " + $message }
            Stop-Screenshot $text 403
        }
        413 {
            Stop-Screenshot ("The screenshot is larger than the server allows (HTTP 413). " + $(if ($message) { $message } else { "Maximum size is 10 MB." }))
        }
        415 {
            Stop-Screenshot ("The server rejected the file type (HTTP 415). " + $(if ($message) { $message } else { "Only PNG, JPEG and WebP are accepted." }))
        }
        400 {
            Stop-Screenshot ("The server rejected the request (HTTP 400). " + $message)
        }
        429 {
            Stop-Screenshot ("Too many requests (HTTP 429). " + $message)
        }
        503 {
            Stop-Screenshot ("The server is not configured (HTTP 503). " + $message)
        }
        default {
            if ($status -ge 500) {
                Stop-Screenshot ("The site returned a server error (HTTP " + $status + "). " + $message)
            }
            Stop-Screenshot ("Upload failed with HTTP " + $status + ". " + $message)
        }
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

function Invoke-ScreenshotCloud {
    if ($Help) {
        Show-Usage
        return 0
    }

    # ---- resolve configuration -------------------------------------------
    $configPath = $null
    if ($env:LOCALAPPDATA) {
        $configPath = Join-Path $env:LOCALAPPDATA "ScreenshotCloud\config.ps1"
    }
    $config = Read-ScreenshotCloudConfig -Path $configPath

    $resolvedSite = Get-FirstNonEmpty @(
        $ParamSite,
        $Site,
        $env:SCREENSHOTCLOUD_SITE,
        $config.Site
    )

    $resolvedKey = Get-FirstNonEmpty @(
        $ParamUploadKey,
        $UploadKey,
        $env:SCREENSHOTCLOUD_UPLOAD_KEY,
        $config.UploadKey
    )

    if (-not $resolvedSite) {
        Stop-Screenshot ("No site URL configured. Pass -Site `"https://your-site.vercel.app`", " +
            "set the SCREENSHOTCLOUD_SITE environment variable, or run Install-ScreenshotCloud.ps1.")
    }

    if (-not $resolvedKey) {
        Stop-Screenshot ("No upload key configured. Pass -UploadKey, set the SCREENSHOTCLOUD_UPLOAD_KEY " +
            "environment variable, or run Install-ScreenshotCloud.ps1 to store it securely.")
    }

    $resolvedSite = $resolvedSite.Trim().TrimEnd("/")
    if (-not $resolvedSite.ToLower().StartsWith("http://") -and
        -not $resolvedSite.ToLower().StartsWith("https://")) {
        Stop-Screenshot ("The site URL must start with http:// or https:// - got: " + $resolvedSite)
    }

    $uri = $null
    if (-not [System.Uri]::TryCreate($resolvedSite, [System.UriKind]::Absolute, [ref]$uri)) {
        Stop-Screenshot ("The site URL is not a valid URL: " + $resolvedSite)
    }

    $uploadUrl = $resolvedSite + "/api/upload"

    Write-Host ""
    Write-Host "ScreenshotCloud" -ForegroundColor Cyan
    Write-Info ("Endpoint: " + $uploadUrl)

    # ---- capture ----------------------------------------------------------
    $file = Capture-PrimaryScreen

    # ---- local size guard -------------------------------------------------
    $size = (Get-Item -LiteralPath $file).Length
    $maxBytes = 10MB
    if ($size -gt $maxBytes) {
        Stop-Screenshot ("The screenshot is " + [math]::Round($size / 1MB, 2) + " MB, which exceeds the 10 MB upload limit.")
    }

    # ---- upload -----------------------------------------------------------
    Write-Info ("Uploading to " + $resolvedSite + " ...")
    $result = Send-ScreenshotUpload -UploadUrl $uploadUrl -FilePath $file -Key $resolvedKey

    if ($result.Status -lt 200 -or $result.Status -ge 300) {
        Show-UploadError -Result $result
    }

    $url = Convert-ResponseToUrl -Body $result.Body
    if (-not $url) {
        $looksLikeHtml = ($result.Body -match "(?i)<(!doctype|html)")
        if ($looksLikeHtml) {
            Stop-Screenshot ("The site returned an HTML page instead of JSON. It may be a login page, a proxy or an error page. URL used: " + $uploadUrl)
        }
        Stop-Screenshot ("The server response did not contain an image URL. Raw response: " +
            $(if ($result.Body) { $result.Body.Substring(0, [Math]::Min(300, $result.Body.Length)) } else { "<empty>" }))
    }

    Write-Ok ("Uploaded via " + $result.Transport + " (HTTP " + $result.Status + ")")

    # The success block is printed by the entry point so that only strings end
    # up on the output stream and the returned value stays an integer.
    $script:ResultUrl = $url
    return 0
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

$script:ResultUrl = $null

try {
    $exitCode = Invoke-ScreenshotCloud
}
catch {
    Write-Fail ($_.Exception.Message)
    $exitCode = if ($script:ExitCode -ne 0) { $script:ExitCode } else { 1 }
}
finally {
    Remove-TempFiles
}

if ($exitCode -eq 0 -and $script:ResultUrl) {
    # Written to the output stream so it can be captured, for example:
    #   $link = .\Screenshot.ps1 | Select-Object -Last 1
    ""
    "Screenshot uploaded successfully!"
    ""
    "Screenshot link:"
    $script:ResultUrl
    ""
}

if (-not $script:IsDotSourced) {
    exit $exitCode
}

$global:LASTEXITCODE = $exitCode
