
# ScreenshotCloud - Silent Installer
# Windows PowerShell 5.1+

$ErrorActionPreference = "Stop"

# ScreenshotCloud website
$Site = "https://sscloud.vercel.app"

# Download uploader directly from GitHub (raw file)
$UploaderUrl = "https://raw.githubusercontent.com/darkhackrrr/sscloud/main/Screenshot.ps1"

# Local installation directory
$InstallDir = Join-Path $env:LOCALAPPDATA "ScreenshotCloud"
$TargetScript = Join-Path $InstallDir "Screenshot.ps1"
$ConfigFile = Join-Path $InstallDir "config.ps1"

# Create installation directory
New-Item -ItemType Directory -Path $InstallDir -Force |
    Out-Null

# Download uploader into a temporary file first
$TempScript = Join-Path $env:TEMP "ScreenshotCloud-Download.ps1"

Invoke-WebRequest `
    -Uri $UploaderUrl `
    -OutFile $TempScript `
    -UseBasicParsing

# Verify that GitHub returned a PowerShell script,
# not an HTML error page.
$DownloadedContent = Get-Content -LiteralPath $TempScript -Raw

if (
    [string]::IsNullOrWhiteSpace($DownloadedContent) -or
    $DownloadedContent -match '(?i)<!DOCTYPE html|<html'
) {
    Remove-Item $TempScript -Force -ErrorAction SilentlyContinue
    throw "Download failed: GitHub did not return a valid PowerShell script. Check the Screenshot.ps1 repository path."
}

# Install the uploader
Move-Item `
    -LiteralPath $TempScript `
    -Destination $TargetScript `
    -Force

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

# Replace the existing ScreenshotCloud function if already installed
if ($ExistingProfile -match '(?s)# ScreenshotCloud Installed.*?(?=\r?\n# |\z)') {

    $UpdatedProfile = [regex]::Replace(
        $ExistingProfile,
        '(?s)# ScreenshotCloud Installed.*?(?=\r?\n# |\z)',
        @"
# ScreenshotCloud Installed
function ScreenshotCloud {
    & "$TargetScript" @args
}
"@
    )

    Set-Content -LiteralPath $ProfilePath -Value $UpdatedProfile -Encoding UTF8
}
else {
    @"

$Marker
function ScreenshotCloud {
    & "$TargetScript" @args
}
"@ | Add-Content -LiteralPath $ProfilePath -Encoding UTF8
}

Write-Host ""
Write-Host "ScreenshotCloud installed successfully!" -ForegroundColor Green
Write-Host "Open a new PowerShell window and type ScreenshotCloud"