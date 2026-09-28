
# ScreenshotCloud - Silent Installer
# Windows PowerShell 5.1+

$ErrorActionPreference = "Stop"

# CHANGE THIS to your real Vercel website
$Site = "https://sscloud.vercel.app"

# Public download location for the uploader
$UploaderUrl = "$Site/Screenshot.ps1"

# Local installation directory
$InstallDir = Join-Path $env:LOCALAPPDATA "ScreenshotCloud"
$TargetScript = Join-Path $InstallDir "Screenshot.ps1"
$ConfigFile = Join-Path $InstallDir "config.ps1"

# Create installation directory
New-Item -ItemType Directory -Path $InstallDir -Force |
    Out-Null

# Download Screenshot.ps1 from Vercel
Invoke-WebRequest `
    -Uri $UploaderUrl `
    -OutFile $TargetScript `
    -UseBasicParsing

# Preserve existing config if it already exists.
# The upload key must be configured locally.
if (-not (Test-Path $ConfigFile)) {
    if ([string]::IsNullOrWhiteSpace($env:SCREENSHOT_UPLOAD_KEY)) {
        throw "Set SCREENSHOT_UPLOAD_KEY in your Windows user environment first."
    }

    $SafeSite = $Site.Replace("'", "''")
    $SafeKey = $env:SCREENSHOT_UPLOAD_KEY.Replace("'", "''")

    @"
`$Site = '$SafeSite'
`$UploadKey = '$SafeKey'
"@ | Set-Content -LiteralPath $ConfigFile -Encoding UTF8
}

# Restrict config file access to current Windows user
$Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

& icacls.exe $ConfigFile /inheritance:r /grant:r "$($Identity):(F)" "SYSTEM:(F)" |
    Out-Null

# Add ScreenshotCloud command to current user's PowerShell profile
$ProfilePath = $PROFILE.CurrentUserCurrentHost
$ProfileDir = Split-Path -Parent $ProfilePath

New-Item -ItemType Directory -Path $ProfileDir -Force |
    Out-Null

if (-not (Test-Path $ProfilePath)) {
    New-Item -ItemType File -Path $ProfilePath -Force |
        Out-Null
}

$Marker = "# ScreenshotCloud Installed"

$ExistingProfile = Get-Content $ProfilePath -Raw -ErrorAction SilentlyContinue

if ($ExistingProfile -notlike "*$Marker*") {
    @"

$Marker
function ScreenshotCloud {
    & "$TargetScript" @args
}
"@ | Add-Content -LiteralPath $ProfilePath -Encoding UTF8
}

Write-Host "ScreenshotCloud installed successfully!"
Write-Host "Open a new PowerShell window and type ScreenshotCloud"