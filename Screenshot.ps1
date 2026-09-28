
# ScreenshotCloud Screenshot Uploader
# Windows PowerShell 5.1+
# Site: https://sscloud.vercel.app

[CmdletBinding()]
param(
    [string]$Site,
    [string]$UploadKey,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

# Default website
$DefaultSite = "https://sscloud.vercel.app"

# Local configuration
$ConfigPath = Join-Path $env:LOCALAPPDATA "ScreenshotCloud\config.ps1"

function Show-Help {
    Write-Host "ScreenshotCloud"
    Write-Host "Usage: ScreenshotCloud [-Site URL] [-UploadKey KEY] [-Help]"
}

if ($Help) {
    Show-Help
    return
}

# Load local configuration
$configSite = ""
$configKey = ""

if (Test-Path -LiteralPath $ConfigPath) {
    . $ConfigPath
    $configSite = $Site
    $configKey = $UploadKey
}

# Resolve configuration
$ResolvedSite = $DefaultSite
$ResolvedKey = ""

if ($configSite) {
    $ResolvedSite = $configSite
}

if ($configKey) {
    $ResolvedKey = $configKey
}

# Explicit parameters take priority
if ($PSBoundParameters.ContainsKey("Site") -and $Site) {
    $ResolvedSite = $Site
}

if ($PSBoundParameters.ContainsKey("UploadKey") -and $UploadKey) {
    $ResolvedKey = $UploadKey
}

# Environment variable fallback
if ($env:SCREENSHOTCLOUD_SITE -and
    -not $PSBoundParameters.ContainsKey("Site")) {
    $ResolvedSite = $env:SCREENSHOTCLOUD_SITE
}

if ($env:SCREENSHOTCLOUD_UPLOAD_KEY -and
    -not $PSBoundParameters.ContainsKey("UploadKey")) {
    $ResolvedKey = $env:SCREENSHOTCLOUD_UPLOAD_KEY
}

if ([string]::IsNullOrWhiteSpace($ResolvedKey)) {
    Write-Error "Upload key is not configured. Run the installer first."
    return
}

$ResolvedSite = $ResolvedSite.TrimEnd("/")
$UploadUrl = "$ResolvedSite/api/upload"

# Capture primary monitor
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $Bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds

    $Bitmap = New-Object System.Drawing.Bitmap(
        $Bounds.Width,
        $Bounds.Height
    )

    $Graphics = [System.Drawing.Graphics]::FromImage($Bitmap)

    try {
        $Graphics.CopyFromScreen(
            $Bounds.Location,
            [System.Drawing.Point]::Empty,
            $Bounds.Size
        )

        $ScreenshotPath = Join-Path $env:TEMP (
            "ScreenshotCloud-" + [guid]::NewGuid().ToString("N") + ".png"
        )

        $Bitmap.Save(
            $ScreenshotPath,
            [System.Drawing.Imaging.ImageFormat]::Png
        )
    }
    finally {
        $Graphics.Dispose()
        $Bitmap.Dispose()
    }
}
catch {
    Write-Error "Screenshot capture failed: $($_.Exception.Message)"
    return
}

try {
    $FileSize = (Get-Item $ScreenshotPath).Length

    if ($FileSize -gt 10MB) {
        throw "Screenshot exceeds the 10 MB upload limit."
    }

    $Curl = Get-Command curl.exe -ErrorAction SilentlyContinue

    if (-not $Curl) {
        throw "curl.exe was not found on this computer."
    }

    # Store authorization header in a temporary curl config file
    $HeaderPath = Join-Path $env:TEMP (
        "ScreenshotCloud-" + [guid]::NewGuid().ToString("N") + ".txt"
    )

    $Header = 'header = "Authorization: Bearer ' +
        ($ResolvedKey -replace '\\', '\\' -replace '"', '\"') + '"'

    [System.IO.File]::WriteAllText(
        $HeaderPath,
        $Header,
        [System.Text.Encoding]::ASCII
    )

    $ResponsePath = Join-Path $env:TEMP (
        "ScreenshotCloud-" + [guid]::NewGuid().ToString("N") + ".json"
    )

    try {
        $Status = & $Curl.Source `
            -s `
            -X POST `
            $UploadUrl `
            -K $HeaderPath `
            -F "file=@$ScreenshotPath;type=image/png" `
            -o $ResponsePath `
            -w "%{http_code}" `
            --max-time 180

        if ($LASTEXITCODE -ne 0) {
            throw "Upload failed. Check your internet connection."
        }

        $HttpStatus = [int]("$Status".Trim())
        $Response = Get-Content $ResponsePath -Raw |
            ConvertFrom-Json

        if ($HttpStatus -lt 200 -or $HttpStatus -ge 300) {
            throw "Upload failed with HTTP $HttpStatus. $($Response.message)"
        }

        if (-not $Response.url) {
            throw "The server did not return a screenshot URL."
        }

        Write-Host ""
        Write-Host "Screenshot uploaded successfully!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Screenshot link:"
        Write-Output $Response.url
    }
    finally {
        Remove-Item $HeaderPath -Force -ErrorAction SilentlyContinue
        Remove-Item $ResponsePath -Force -ErrorAction SilentlyContinue
    }
}
catch {
    Write-Error $_.Exception.Message
}
finally {
    Remove-Item $ScreenshotPath -Force -ErrorAction SilentlyContinue
}