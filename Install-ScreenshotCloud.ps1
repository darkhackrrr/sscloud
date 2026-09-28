
# ScreenshotCloud - Silent Installer
# No prompts, no Read-Host, no environment variable required.

$ErrorActionPreference = "Stop"

# URLs
$UploaderUrl = "https://raw.githubusercontent.com/darkhackrrr/sscloud/main/Screenshot.ps1"

# Installation paths
$InstallDir = Join-Path $env:LOCALAPPDATA "ScreenshotCloud"
$UploaderPath = Join-Path $InstallDir "Screenshot.ps1"
$ConfigPath = Join-Path $InstallDir "config.ps1"

# PowerShell profile
$ProfilePath = $PROFILE

Write-Host ""
Write-Host "Installing ScreenshotCloud..." -ForegroundColor Cyan

# Create installation directory
if (-not (Test-Path $InstallDir)) {
    New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null
}

# Download uploader
Write-Host "Downloading uploader..." -ForegroundColor Gray

try {
    $Response = Invoke-WebRequest `
        -Uri $UploaderUrl `
        -UseBasicParsing `
        -ErrorAction Stop

    $UploaderContent = $Response.Content

    if ([string]::IsNullOrWhiteSpace($UploaderContent)) {
        throw "The downloaded uploader is empty."
    }

    if ($UploaderContent -match "(?i)^\s*<!DOCTYPE html|^\s*<html") {
        throw "GitHub returned a webpage instead of the PowerShell script."
    }

    if ($UploaderContent -notmatch "param\s*\(|SCREENSHOT_UPLOAD_KEY|Upload") {
        Write-Host "Warning: The downloaded file may not be the expected uploader." -ForegroundColor Yellow
    }

    Set-Content `
        -Path $UploaderPath `
        -Value $UploaderContent `
        -Encoding UTF8 `
        -Force

    Write-Host "Uploader downloaded." -ForegroundColor Green
}
catch {
    Write-Host "Failed to download uploader: $($_.Exception.Message)" -ForegroundColor Red
    return
}

# Create config only if it does not already exist.
# Existing configuration and keys are preserved.
if (-not (Test-Path $ConfigPath)) {

    $ConfigContent = @'
# ScreenshotCloud configuration

$Site = "https://sscloud.vercel.app"

# Set this to a valid upload key if your backend requires one.
# Do not put your private key in a public GitHub repository.
$UploadKey = ""
'@

    Set-Content `
        -Path $ConfigPath `
        -Value $ConfigContent `
        -Encoding UTF8 `
        -Force

    Write-Host "Configuration created." -ForegroundColor Green
}
else {
    Write-Host "Existing configuration preserved." -ForegroundColor Yellow
}

# Set restrictive permissions on local configuration.
try {
    $CurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    & icacls.exe $ConfigPath /inheritance:r /grant:r "${CurrentUser}:(F)" | Out-Null

    Write-Host "Configuration permissions secured." -ForegroundColor Green
}
catch {
    Write-Host "Could not update configuration permissions." -ForegroundColor Yellow
}

# Ensure PowerShell profile directory exists
$ProfileDirectory = Split-Path -Parent $ProfilePath

if (-not (Test-Path $ProfileDirectory)) {
    New-Item -Path $ProfileDirectory -ItemType Directory -Force | Out-Null
}

if (-not (Test-Path $ProfilePath)) {
    New-Item -Path $ProfilePath -ItemType File -Force | Out-Null
}

# Command function
$FunctionBlock = @'

# ScreenshotCloud command
function ScreenshotCloud {
    $UploaderPath = Join-Path $env:LOCALAPPDATA "ScreenshotCloud\Screenshot.ps1"
    $ConfigPath = Join-Path $env:LOCALAPPDATA "ScreenshotCloud\config.ps1"

    if (-not (Test-Path $UploaderPath)) {
        Write-Host "ScreenshotCloud uploader not found. Reinstall it." -ForegroundColor Red
        return
    }

    if (Test-Path $ConfigPath) {
        . $ConfigPath
    }

    & $UploaderPath
}

'@

# Remove the old ScreenshotCloud function from the profile
$ProfileContent = Get-Content -Path $ProfilePath -Raw -ErrorAction SilentlyContinue

if ($null -eq $ProfileContent) {
    $ProfileContent = ""
}

$Pattern = '(?ms)# ScreenshotCloud command\s*function ScreenshotCloud\s*\{.*?^\}'

$ProfileContent = [regex]::Replace(
    $ProfileContent,
    $Pattern,
    ""
)

# Append the updated function
Set-Content `
    -Path $ProfilePath `
    -Value ($ProfileContent.TrimEnd() + "`r`n" + $FunctionBlock) `
    -Encoding UTF8 `
    -Force

# Load command in current PowerShell session
. $ProfilePath

Write-Host ""
Write-Host "ScreenshotCloud installed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Run ScreenshotCloud to start the uploader." -ForegroundColor Cyan
Write-Host "Installed at: $InstallDir" -ForegroundColor Gray
Write-Host ""