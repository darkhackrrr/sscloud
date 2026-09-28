
# ScreenshotCloud - Fully Unattended Installer
# Windows PowerShell 5.1+

$ErrorActionPreference = "Stop"

# Website
$Site = "https://sscloud.vercel.app"

# Public GitHub uploader
$UploaderUrl = "https://raw.githubusercontent.com/darkhackrrr/sscloud/main/Screenshot.ps1"

# Local paths
$InstallDir = Join-Path $env:LOCALAPPDATA "ScreenshotCloud"
$TargetScript = Join-Path $InstallDir "Screenshot.ps1"
$ConfigFile = Join-Path $InstallDir "config.ps1"

# Create installation directory
New-Item -ItemType Directory -Path $InstallDir -Force |
    Out-Null

# Download uploader
$TempScript = Join-Path $env:TEMP "ScreenshotCloud-Download.ps1"

Invoke-WebRequest `
    -Uri $UploaderUrl `
    -OutFile $TempScript `
    -UseBasicParsing

# Validate download
$Content = Get-Content -LiteralPath $TempScript -Raw

if (
    [string]::IsNullOrWhiteSpace($Content) -or
    $Content -match '(?i)<!DOCTYPE html|<html'
) {
    Remove-Item $TempScript -Force -ErrorAction SilentlyContinue
    throw "ScreenshotCloud: Uploader download failed."
}

# Install uploader
Move-Item `
    -LiteralPath $TempScript `
    -Destination $TargetScript `
    -Force

# Preserve existing config.
# If no config exists, create one without a secret.
if (-not (Test-Path $ConfigFile)) {
    @"
`$Site = '$Site'
`$UploadKey = ''
"@ | Set-Content -LiteralPath $ConfigFile -Encoding UTF8
}

# Restrict config permissions
$Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

& icacls.exe $ConfigFile /inheritance:r /grant:r "$($Identity):(F)" "SYSTEM:(F)" |
    Out-Null

if ($LASTEXITCODE -ne 0) {
    throw "ScreenshotCloud: Could not secure config permissions."
}

# PowerShell profile
$ProfilePath = $PROFILE.CurrentUserCurrentHost
$ProfileDir = Split-Path -Parent $ProfilePath

New-Item -ItemType Directory -Path $ProfileDir -Force |
    Out-Null

if (-not (Test-Path $ProfilePath)) {
    New-Item -ItemType File -Path $ProfilePath -Force |
        Out-Null
}

# Install or update the command
$Marker = "# ScreenshotCloud Installed"

$FunctionBlock = @"
# ScreenshotCloud Installed
function ScreenshotCloud {
    & "$TargetScript" @args
}
"@

$ExistingProfile = Get-Content -LiteralPath $ProfilePath -Raw -ErrorAction SilentlyContinue

if ($ExistingProfile -match '(?s)# ScreenshotCloud Installed.*?function ScreenshotCloud\s*\{.*?\}') {
    $UpdatedProfile = [regex]::Replace(
        $ExistingProfile,
        '(?s)# ScreenshotCloud Installed.*?function ScreenshotCloud\s*\{.*?\}',
        [System.Text.RegularExpressions.MatchEvaluator]{
            param($Match)
            $FunctionBlock
        }
    )

    Set-Content -LiteralPath $ProfilePath -Value $UpdatedProfile -Encoding UTF8
}
else {
    Add-Content -LiteralPath $ProfilePath -Value "`r`n$FunctionBlock" -Encoding UTF8
}

Write-Host "ScreenshotCloud installed successfully!" -ForegroundColor Green
Write-Host "Open a new PowerShell window and type ScreenshotCloud"