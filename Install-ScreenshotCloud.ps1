<#
.SYNOPSIS
    Installs the ScreenshotCloud PowerShell uploader for the current Windows user.

.DESCRIPTION
    Install-ScreenshotCloud.ps1

      * verifies it is running on Windows
      * creates %LOCALAPPDATA%\ScreenshotCloud
      * copies Screenshot.ps1 into that folder
      * prompts for your site URL and upload key
      * writes the values to %LOCALAPPDATA%\ScreenshotCloud\config.ps1
        with permissions limited to your account (where supported)
      * optionally adds a ScreenshotCloud function to your PowerShell profile

    Credentials are only ever written to your own profile-independent config file.
    Nothing is uploaded to Vercel or any other third-party service, no scheduled
    task or startup entry is created, and no background capture is configured.

.PARAMETER Site
    Your deployed site URL. Skips the interactive prompt.

.PARAMETER UploadKey
    Your SCREENSHOT_UPLOAD_KEY. Skips the interactive prompt.
    Prefer the prompt: command line arguments are recorded in shell history.

.PARAMETER InstallDir
    Destination folder. Defaults to %LOCALAPPDATA%\ScreenshotCloud.

.PARAMETER AddToProfile
    Add the ScreenshotCloud function to your PowerShell profile without asking.

.PARAMETER SkipProfile
    Do not touch your PowerShell profile.

.PARAMETER ScriptPath
    Explicit path to Screenshot.ps1 when it cannot be found automatically.

.EXAMPLE
    .\Install-ScreenshotCloud.ps1

.EXAMPLE
    .\Install-ScreenshotCloud.ps1 -Site "https://my-site.vercel.app" -AddToProfile
#>

#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter()]
    [string]$Site,

    [Parameter()]
    [string]$UploadKey,

    [Parameter()]
    [string]$InstallDir,

    [Parameter()]
    [switch]$AddToProfile,

    [Parameter()]
    [switch]$SkipProfile,

    [Parameter()]
    [string]$ScriptPath
)

$ErrorActionPreference = "Stop"

$BEGIN_MARKER = "# >>> ScreenshotCloud >>>"
$END_MARKER   = "# <<< ScreenshotCloud <<<"

function Write-Step([string]$Message) {
    Write-Host ("  -> " + $Message) -ForegroundColor Cyan
}

function Write-Done([string]$Message) {
    Write-Host ("  [ok] " + $Message) -ForegroundColor Green
}

function Write-Problem([string]$Message) {
    Write-Host ("  [!] " + $Message) -ForegroundColor Yellow
}

function Fail([string]$Message) {
    Write-Host ""
    Write-Host ("ERROR: " + $Message) -ForegroundColor Red
    Write-Host ""
    exit 1
}

function Test-IsWindows {
    if ($env:OS -eq "Windows_NT") { return $true }
    try {
        return ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)
    }
    catch {
        return $false
    }
}

function ConvertFrom-SecureStringPlain([System.Security.SecureString]$Secure) {
    if ($null -eq $Secure) { return "" }
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Read-NonEmptySecret([string]$Prompt) {
    while ($true) {
        $secure = Read-Host -Prompt $Prompt -AsSecureString
        $value  = ConvertFrom-SecureStringPlain $secure
        $secure.Dispose()

        if (-not [string]::IsNullOrWhiteSpace($value)) { return $value.Trim() }

        Write-Problem "The value cannot be empty. Try again."
    }
}

function Read-NonEmptyLine([string]$Prompt) {
    while ($true) {
        $value = Read-Host -Prompt $Prompt
        if (-not [string]::IsNullOrWhiteSpace($value)) { return $value.Trim() }
        Write-Problem "The value cannot be empty. Try again."
    }
}

function Find-UploaderScript {
    if ($ScriptPath) {
        if (Test-Path -LiteralPath $ScriptPath) { return (Resolve-Path -LiteralPath $ScriptPath).Path }
        Fail ("Screenshot.ps1 was not found at the path you supplied: " + $ScriptPath)
    }

    $candidates = @()

    if ($PSScriptRoot) {
        $candidates += (Join-Path $PSScriptRoot "Screenshot.ps1")
        $candidates += (Join-Path $PSScriptRoot "scripts\Screenshot.ps1")
    }

    $candidates += (Join-Path (Get-Location).Path "Screenshot.ps1")
    $candidates += (Join-Path (Get-Location).Path "scripts\Screenshot.ps1")

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    return $null
}

function Set-ConfigPermissions([string]$Path) {
    $icacls = Get-Command icacls.exe -ErrorAction SilentlyContinue
    if (-not $icacls) {
        Write-Problem "icacls.exe is unavailable; the config file keeps inherited permissions."
        return
    }

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    & icacls.exe $Path /inheritance:r /grant:r "$($identity):(F)" "SYSTEM:(F)" | Out-Null

    if ($LASTEXITCODE -ne 0) {
        Write-Problem "Could not tighten permissions on the config file (icacls exit $LASTEXITCODE)."
    }
    else {
        Write-Done "Config file permissions restricted to your account"
    }
}

function Write-ConfigFile([string]$Path, [string]$Url, [string]$Key) {
    $safeUrl = $Url.Replace("'", "''")
    $safeKey = $Key.Replace("'", "''")

    $content = @"
# ScreenshotCloud configuration
# Written by Install-ScreenshotCloud.ps1 for $env:USERNAME.
# Used by Screenshot.ps1. Do not share or commit this file.
`$Site      = '$safeUrl'
`$UploadKey = '$safeKey'
"@

    Set-Content -LiteralPath $Path -Value $content -Encoding UTF8
}

function Get-ProfileBlock([string]$UploaderPath) {
    $escaped = $UploaderPath.Replace("'", "''")

    return @"
$BEGIN_MARKER
# ScreenshotCloud: run ScreenshotCloud to capture, upload and print a link.
# This only defines a function - it never runs a capture on its own.
function ScreenshotCloud {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]`$Site,
        [Parameter()]
        [string]`$UploadKey,
        [Parameter()]
        [switch]`$Help
    )

    `$splat = @{}
    if (`$Site)      { `$splat.Site = `$Site }
    if (`$UploadKey) { `$splat.UploadKey = `$UploadKey }
    if (`$Help)      { `$splat.Help = `$true }

    & '$escaped' @splat
}
$END_MARKER
"@
}

function Install-ProfileFunction([string]$UploaderPath) {
    $profilePath = $PROFILE.CurrentUserCurrentHost

    if (Test-Path -LiteralPath $profilePath) {
        $existing = Get-Content -LiteralPath $profilePath -Raw -ErrorAction SilentlyContinue
        if ($existing -and $existing.Contains($BEGIN_MARKER)) {
            # Replace the previously installed block so re-running the installer works.
            $startIndex = $existing.IndexOf($BEGIN_MARKER)
            $endIndex   = $existing.IndexOf($END_MARKER)

            if ($startIndex -ge 0 -and $endIndex -gt $startIndex) {
                $before    = $existing.Substring(0, $startIndex)
                $after     = $existing.Substring($endIndex + $END_MARKER.Length)
                $replacement = Get-ProfileBlock $UploaderPath
                $updated   = $before + $replacement + $after
            }
            else {
                $updated = $existing + [System.Environment]::NewLine + (Get-ProfileBlock $UploaderPath)
            }

            Set-Content -LiteralPath $profilePath -Value $updated -Encoding UTF8
            Write-Done "Updated the ScreenshotCloud function in your profile"
            return $profilePath
        }
    }

    $directory = Split-Path -Parent $profilePath
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $block = (Get-ProfileBlock $UploaderPath) + [System.Environment]::NewLine

    if (Test-Path -LiteralPath $profilePath) {
        Add-Content -LiteralPath $profilePath -Value ([System.Environment]::NewLine + $block) -Encoding UTF8
    }
    else {
        Set-Content -LiteralPath $profilePath -Value $block -Encoding UTF8
    }

    Write-Done ("Added ScreenshotCloud to " + $profilePath)
    return $profilePath
}

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "ScreenshotCloud installer" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-IsWindows)) {
    Fail "This installer only supports Windows 10 and Windows 11."
}
Write-Done "Windows detected"

$sourceScript = Find-UploaderScript
if (-not $sourceScript) {
    Fail ("Screenshot.ps1 was not found next to this installer. Run this script from the " +
        "project's scripts folder, or pass -ScriptPath <path to Screenshot.ps1>.")
}
Write-Done ("Found uploader: " + $sourceScript)

if (-not $InstallDir) {
    if (-not $env:LOCALAPPDATA) {
        Fail "LOCALAPPDATA is not set; pass -InstallDir explicitly."
    }
    $InstallDir = Join-Path $env:LOCALAPPDATA "ScreenshotCloud"
}

try {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}
catch {
    Fail ("Could not create " + $InstallDir + ": " + $_.Exception.Message)
}

$targetScript = Join-Path $InstallDir "Screenshot.ps1"
$configFile   = Join-Path $InstallDir "config.ps1"

try {
    Copy-Item -LiteralPath $sourceScript -Destination $targetScript -Force
}
catch {
    Fail ("Could not copy Screenshot.ps1 to " + $InstallDir + ": " + $_.Exception.Message)
}
Write-Done ("Installed to " + $targetScript)

# ---- credentials ---------------------------------------------------------

if ([string]::IsNullOrWhiteSpace($Site)) {
    Write-Host ""
    Write-Host "Enter the URL of your deployed Vercel site." -ForegroundColor White
    Write-Host "Example: https://my-site.vercel.app" -ForegroundColor DarkGray
    $Site = Read-NonEmptyLine "Site URL"
}
else {
    $Site = $Site.Trim()
}

$Site = $Site.TrimEnd("/")
if (-not ($Site.ToLower().StartsWith("http://") -or $Site.ToLower().StartsWith("https://"))) {
    Fail ("The site URL must start with http:// or https:// - got: " + $Site)
}

$uri = $null
if (-not [System.Uri]::TryCreate($Site, [System.UriKind]::Absolute, [ref]$uri)) {
    Fail ("The site URL is not a valid URL: " + $Site)
}

if ([string]::IsNullOrWhiteSpace($UploadKey)) {
    Write-Host ""
    Write-Host "Paste your SCREENSHOT_UPLOAD_KEY from the Vercel dashboard." -ForegroundColor White
    Write-Host "It is masked while you type and is never printed back to you." -ForegroundColor DarkGray
    $UploadKey = Read-NonEmptySecret "Upload key"
}
else {
    $UploadKey = $UploadKey.Trim()
    Write-Problem "An upload key passed on the command line may be stored in your shell history."
}

try {
    Write-ConfigFile -Path $configFile -Url $Site -Key $UploadKey
}
catch {
    Fail ("Could not write " + $configFile + ": " + $_.Exception.Message)
}
$UploadKey = $null
Write-Done ("Configuration saved to " + $configFile)
Set-ConfigPermissions -Path $configFile

# ---- profile -------------------------------------------------------------

if (-not $SkipProfile) {
    $addToProfile = $AddToProfile

    if (-not $addToProfile) {
        Write-Host ""
        $answer = Read-Host "Add the ScreenshotCloud command to your PowerShell profile? [y/N]"
        $addToProfile = $answer -match "^(y|yes)$"
    }

    if ($addToProfile) {
        try {
            $profilePath = Install-ProfileFunction -UploaderPath $targetScript
            Write-Problem "Only a function definition was added - no automatic or scheduled capture."
            $profilePathOut = $profilePath
        }
        catch {
            Write-Problem ("Could not update your PowerShell profile: " + $_.Exception.Message)
            $profilePathOut = $null
        }
    }
    else {
        Write-Problem "Skipped your PowerShell profile. You can still run Screenshot.ps1 directly."
        $profilePathOut = $null
    }
}
else {
    $profilePathOut = $null
}

# ---- summary -------------------------------------------------------------

Write-Host ""
Write-Host "Installation complete" -ForegroundColor Green
Write-Host ""
Write-Host "  Files" -ForegroundColor White
Write-Host ("    " + $targetScript)
Write-Host ("    " + $configFile)
if ($profilePathOut) {
    Write-Host ("    " + $profilePathOut)
}
Write-Host ""
Write-Host "  Use it" -ForegroundColor White
if ($profilePathOut) {
    Write-Host "    ScreenshotCloud"
    Write-Host "    ScreenshotCloud -Help"
    Write-Host ("    ScreenshotCloud -Site `"https://another-site.vercel.app`"")
}
Write-Host ""
Write-Host "  Or run the script directly" -ForegroundColor White
Write-Host ("    & '" + $targetScript + "'")
Write-Host ""
Write-Host "  Reload your profile in this session with" -ForegroundColor White
Write-Host ("    . '" + $PROFILE.CurrentUserCurrentHost + "'")
Write-Host ""
Write-Host "  The installer created no startup entries, scheduled tasks or background jobs." -ForegroundColor DarkGray
Write-Host ""
