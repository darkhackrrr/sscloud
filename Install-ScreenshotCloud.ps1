
# ScreenshotCloud - Silent Installer
# Windows PowerShell 5.1+

$ErrorActionPreference = "Stop"

# Website
$Site = "https://sscloud.vercel.app"

# Public uploader hosted on GitHub
$UploaderUrl = "https://raw.githubusercontent.com/darkhackrrr/sscloud/main/Screenshot.ps1"

# Installation paths
$InstallDir = Join-Path $env:LOCALAPPDATA "ScreenshotCloud"
$TargetScript = Join-Path $InstallDir "Screenshot.ps1"
$ConfigFile = Join-Path $InstallDir "config.ps1"

# Create installation directory
New-Item -ItemType Directory -Path $InstallDir -Force |
    Out-Null

# Download uploader
Write-Host "Downloading ScreenshotCloud..." -ForegroundColor Cyan

$TempScript = Join-Path $env:TEMP "ScreenshotCloud-Download.ps1"

Invoke-WebRequest `
    -Uri $UploaderUrl `
    -OutFile $TempScript `
    -UseBasicParsing

# Verify the download is a script, not a 404 HTML page
$DownloadedContent = Get-Content -LiteralPath $TempScript -Raw

if (
    [string]::IsNullOrWhiteSpace($DownloadedContent) -or
    $DownloadedContent -match '(?i)<!DOCTYPE html|<html'
) {
    Remove-Item $TempScript -Force -ErrorAction SilentlyContinue
    throw "Download failed. Check that Screenshot.ps1 exists in the GitHub repository root."
}

Move-Item -LiteralPath $TempScript -Destination $TargetScript -Force

Write-Host "Uploader downloaded." -ForegroundColor Green

# Configure upload key locally
if (Test-Path $ConfigFile) {
    Write-Host "Existing configuration found." -ForegroundColor Yellow
    $KeepConfig = Read-Host "Keep existing upload key? (Y/N)"

    if ($KeepConfig -notmatch '^(Y|y)$') {
        Remove-Item -LiteralPath $ConfigFile -Force
    }
}

if (-not (Test-Path $ConfigFile)) {

    Write-Host ""
    Write-Host "Enter your Vercel upload key." -ForegroundColor Cyan
    Write-Host "Input is hidden. The key is saved locally." -ForegroundColor Gray

    $SecureKey = Read-Host "Upload key" -AsSecureString

    if ($SecureKey.Length -eq 0) {
        throw "Upload key cannot be empty."
    }

    # Convert secure input to plain text only for the local config
    $BSTR = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureKey)

    try {
        $UploadKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        $SecureKey.Dispose()
    }

    $SafeSite = $Site.Replace("'", "''")
    $SafeKey = $UploadKey.Replace("'", "''")

    @"
`$Site = '$SafeSite'
`$UploadKey = '$SafeKey'
"@ | Set-Content -LiteralPath $ConfigFile -Encoding UTF8

    # Clear temporary variable
    $UploadKey = $null
    $SafeKey = $null
}

# Restrict config access to current Windows user and SYSTEM
$Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

& icacls.exe $ConfigFile /inheritance:r /grant:r "$($Identity):(F)" "SYSTEM:(F)" |
    Out-Null

if ($LASTEXITCODE -ne 0) {
    throw "Could not secure the configuration file permissions."
}

# Install PowerShell command in current user's profile
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

$FunctionBlock = @"
# ScreenshotCloud Installed
function ScreenshotCloud {
    & "$TargetScript" @args
}
"@

if ($ExistingProfile -match '(?s)# ScreenshotCloud Installed.*?function ScreenshotCloud\s*\{.*?\}') {

    $UpdatedProfile = [regex]::Replace(
        $ExistingProfile,
        '(?s)# ScreenshotCloud Installed.*?function ScreenshotCloud\s*\{.*?\}',
        [System.Text.RegularExpressions.MatchEvaluator]{
            param($match)
            $FunctionBlock
        },
        1
    )

    Set-Content -LiteralPath $ProfilePath -Value $UpdatedProfile -Encoding UTF8
}
else {
    Add-Content -LiteralPath $ProfilePath -Value "`r`n$FunctionBlock" -Encoding UTF8
}

Write-Host ""
Write-Host "ScreenshotCloud installed successfully!" -ForegroundColor Green
Write-Host "Open a new PowerShell window and type ScreenshotCloud"