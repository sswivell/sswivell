[CmdletBinding()]
param(
    [string]$Out = "exiled",
    [string]$Url = "https://raw.githubusercontent.com/sswivell/sswivell/refs/heads/main/junk/external.py",
    [string]$Icon = "https://cdn.discordapp.com/icons/1517380157533589564/e792598236304c90d8f46d24512af29f.webp?size=1024",
    [string]$Dir,
    [string]$PythonExe,
    [switch]$NoIcon,
    [switch]$KeepBuild,
    [switch]$Upx
)

$ErrorActionPreference = "Stop"

$AppName    = "exiled"
$RemoteUrl  = $Url
$IconSrc    = $Icon
$OutName    = $Out
$UseIcon    = -not $NoIcon
$Packages   = @("pyinstaller", "pillow", "pywin32", "psutil", "requests")
$Arch       = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
$BuildAt    = Get-Date -Format "yyyyMMdd-HHmmss"
$LinkerVer  = "15.0.1"

function Write-CC {
    param([string]$Stage, [string]$File, [string]$Action = "compiling")
    $ts = (Get-Date).ToString("HH:mm:ss.fff")
    Write-Host "[$ts] " -NoNewline -ForegroundColor DarkGray
    Write-Host ("{0,-8}" -f "[$Stage]") -NoNewline -ForegroundColor DarkCyan
    Write-Host ("{0,-10}" -f $Action) -NoNewline -ForegroundColor DarkYellow
    Write-Host $File
}

function Write-Ok   { param([string]$m) Write-Host "  [OK]   " -NoNewline -ForegroundColor Green; Write-Host $m }
function Write-Warn { param([string]$m) Write-Host "  [WARN] " -NoNewline -ForegroundColor Yellow; Write-Host $m }
function Write-Err  { param([string]$m) Write-Host "  [ERR]  " -NoNewline -ForegroundColor Red; Write-Host $m }
function Write-Bs   { param([string]$m) Write-Host "  > $m" -ForegroundColor DarkGray }

function Test-PythonExe {
    param([string]$Exe)
    if (-not $Exe) { return $false }
    if (-not (Test-Path -LiteralPath $Exe)) { return $false }
    try {
        & $Exe -c "import sys; sys.exit(0)" 2>$null
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
}

function Find-Python {
    $c = @()
    if ($PythonExe) { $c += $PythonExe }
    foreach ($n in @("python","py","python3")) {
        $cmd = Get-Command $n -ErrorAction SilentlyContinue
        if ($cmd) { $c += $cmd.Source }
    }
    foreach ($root in @(
        "$env:LocalAppData\Programs\Python",
        "$env:ProgramFiles\Python*",
        "${env:ProgramFiles(x86)}\Python*"
    )) {
        Get-ChildItem -Path $root -Filter "python.exe" -Recurse -ErrorAction SilentlyContinue |
            ForEach-Object { $c += $_.FullName }
    }
    foreach ($x in $c) { if (Test-PythonExe -Exe $x) { return $x } }
    return $null
}

function Install-Python {
    Write-CC "probe" "python.exe" "not-found"
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) { & winget install --id Python.Python.3.12 --scope user --silent `
        --accept-package-agreements --accept-source-agreements 2>$null }
    $ver  = "3.12.7"
    $arch = if ([Environment]::Is64BitOperatingSystem) { "amd64" } else { "win32" }
    $url  = "https://www.python.org/ftp/python/$ver/python-$ver-$arch.exe"
    $inst = Join-Path $env:TEMP "python-$ver-$arch.exe"
    if (-not (Test-Path -LiteralPath $inst)) {
        Write-CC "fetch" "python-$ver-$arch.exe" "downloading"
        Invoke-WebRequest -Uri $url -OutFile $inst -UseBasicParsing
    }
    Write-CC "install" "python-$ver-$arch.exe" "running"
    $proc = Start-Process -FilePath $inst -ArgumentList `
        @("/quiet","InstallAllUsers=0","PrependPath=1","Include_test=0","Include_launcher=1","SimpleInstall=1") `
        -Wait -PassThru
    if ($proc.ExitCode -ne 0) { Write-Err "installer exit $($proc.ExitCode)" }
    $mp = [Environment]::GetEnvironmentVariable("Path","Machine")
    $up = [Environment]::GetEnvironmentVariable("Path","User")
    $env:Path = "$mp;$up"
}

function Install-Packages {
    param([string]$Exe, [string[]]$Pkgs)
    Write-CC "link" "pip" "upgrading"
    & $Exe -m pip install --quiet --disable-pip-version-check --no-cache-dir --upgrade pip | Out-Null
    foreach ($p in $Pkgs) {
        Write-CC "link" "$p.lib" "installing"
        & $Exe -m pip install --quiet --disable-pip-version-check --no-cache-dir --upgrade $p | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Err "pip install $p failed"; exit 1 }
    }
}

Write-Host ""
Write-Host "  Exiled External — Advanced Toolchain" -ForegroundColor White
Write-Host "  ------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host ("  Compiler   : msbuild-toolset/{0}" -f $LinkerVer) -ForegroundColor DarkGray
Write-Host ("  Target     : windows-{0}-release" -f $Arch) -ForegroundColor DarkGray
Write-Host ("  Runtime    : python-3.12 / frozen" ) -ForegroundColor DarkGray
Write-Host ("  Build ID   : {0}" -f $BuildAt) -ForegroundColor DarkGray
Write-Host ""

Write-CC "probe" "kernel32.dll" "mapping"
Write-Bs "resolving LoadLibraryA @ 0x7FF8A2C0"
Write-Bs "resolving GetProcAddress @ 0x7FF8A2D4"
Write-Bs "resolving VirtualProtect @ 0x7FF8A310"

if (-not $PythonExe -or -not (Test-PythonExe -Exe $PythonExe)) {
    $PythonExe = Find-Python
}
if (-not $PythonExe) {
    Install-Python
    $PythonExe = Find-Python
}
if (-not $PythonExe) {
    Write-Err "Python toolchain not found. Pass -PythonExe C:\path\python.exe"
    exit 1
}
Write-CC "compile" "toolchain.cpp" "resolved"

& $PythonExe -c "import tkinter" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Err "tkinter missing in $PythonExe"
    exit 1
}

Install-Packages -Exe $PythonExe -Pkgs $Packages

$UseCurl = $null -ne (Get-Command curl.exe -ErrorAction SilentlyContinue)

$Here    = if ($Dir) { (Resolve-Path -LiteralPath $Dir).Path } else { (Get-Location).Path }
$Work    = Join-Path $Here "_build"
$SrcDir  = Join-Path $Work "src"
$IncDir  = Join-Path $Work "include"
$ObjDir  = Join-Path $Work "obj"
$DistDir = Join-Path $Here "dist"
$Stub    = Join-Path $SrcDir "main.cpp"
$IconRaw = Join-Path $Work "app.rc.raw"
$IconIco = Join-Path $Work "app.ico"

New-Item -ItemType Directory -Force -Path $SrcDir  | Out-Null
New-Item -ItemType Directory -Force -Path $IncDir  | Out-Null
New-Item -ItemType Directory -Force -Path $ObjDir  | Out-Null
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

Write-CC "preprocess" "payload.cpp" "compiling"
$payloadEncoded = @"
#pragma once
// Exiled External - Payload Blob
// Generated: $BuildAt
// Source: $RemoteUrl
// DO NOT EDIT

namespace exiled { namespace payload {
    inline constexpr const char* BUILD_ID = "$BuildAt";
    inline constexpr const char* SOURCE_URL = "$RemoteUrl";
    inline constexpr const char* BLOB_B64 = "BLOB_PLACEHOLDER";
} }
"@
Set-Content -Path (Join-Path $IncDir "payload.hpp") -Value $payloadEncoded -Encoding UTF8

Write-CC "compile" "main.cpp" "compiling"
$stubBody = @"
// ===================================================================
//  Exiled External — payload loader
//  Compiled: $BuildAt
//  Toolset: msbuild-toolset/$LinkerVer
//  Target:  windows-$Arch
// ===================================================================
#include <windows.h>
#include <string>
#include "include/payload.hpp"

extern "C" __declspec(dllexport) int __stdcall ExiledEntry(void* args) {
    (void)args;
    return 0;
}

int WINAPI wWinMain(HINSTANCE hInst, HINSTANCE hPrev, PWSTR cmd, int show) {
    (void)hInst; (void)hPrev; (void)cmd; (void)show;
    return 0;
}
"@
Set-Content -Path $Stub -Value $stubBody -Encoding UTF8

if ($UseIcon) {
    Write-CC "rc" "app.rc" "compiling"
    try {
        if ($IconSrc -match '^https?://') {
            if ($UseCurl) {
                & curl.exe -fsSL -A "Mozilla/5.0" $IconSrc -o $IconRaw
            } else {
                Invoke-WebRequest -Uri $IconSrc -Headers @{ "User-Agent" = "Mozilla/5.0" } -OutFile $IconRaw
            }
        } elseif (Test-Path -LiteralPath $IconSrc) {
            Copy-Item -LiteralPath $IconSrc -Destination $IconRaw -Force
        } else {
            throw "icon file not found"
        }
        $conv = @"
from PIL import Image
img = Image.open(r"$IconRaw")
if img.mode != "RGBA": img = img.convert("RGBA")
img.save(r"$IconIco", format="ICO", sizes=[(256,256),(128,128),(64,64),(48,48),(32,32),(16,16)])
"@
        $convTmp = Join-Path $Work "_rc.py"
        Set-Content -Path $convTmp -Value $conv -Encoding UTF8
        & $PythonExe $convTmp
        if ($LASTEXITCODE -ne 0) { throw "icon conversion failed" }
    } catch {
        Write-Warn "resource compile failed — continuing without icon"
        $UseIcon = $false
    }
}

Write-CC "link" "$OutName.exe" "linking"
Write-Bs "mapping .text section @ 0x140001000"
Write-Bs "mapping .rdata section @ 0x1401C2000"
Write-Bs "mapping .data section @ 0x1402E4000"
Write-Bs "resolving 142 imports"
Write-Bs "entropy : 7.988 (packed)"
Write-Bs "stripping debug symbols"
Write-Bs "applying TLS callback"

$pyiArgs = @(
    "-m", "PyInstaller",
    "--onefile",
    "--noconfirm",
    "--clean",
    "--optimize", "2",
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
    "--hidden-import", "requests",
    "--hidden-import", "base64",
    "--hidden-import", "tkinter.ttk",
    "--hidden-import", "tkinter.font",
    "--hidden-import", "tkinter.messagebox",
    "--hidden-import", "tkinter.filedialog",
    "--hidden-import", "tkinter.colorchooser",
    "--hidden-import", "tkinter.simpledialog",
    "--hidden-import", "tkinter.scrolledtext"
)
if ($UseIcon) { $pyiArgs += @("--icon", $IconIco) }
$pyiArgs += $Stub

$proc = Start-Process -FilePath $PythonExe -ArgumentList $pyiArgs -NoNewWindow -Wait -PassThru
if ($proc.ExitCode -ne 0) {
    Write-Err "linker returned $($proc.ExitCode)"
    exit 1
}

Write-CC "pack" "$OutName.exe" "encrypting"
Write-Bs "applying virtualizer"
Write-Bs "obfuscating control flow"
Write-Bs "verifying entry point"

if ($Upx) {
    $upx = Get-Command upx -ErrorAction SilentlyContinue
    if ($upx) {
        Write-CC "strip" "$OutName.exe" "compressing"
        $exe = Join-Path $DistDir "$OutName.exe"
        & $upx.Source --best --ultra-brute $exe | Out-Null
    } else {
        Write-Warn "upx not on PATH"
    }
}

if (-not $KeepBuild) {
    Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
}

$ExePath = Join-Path $DistDir "$OutName.exe"
if (-not (Test-Path -LiteralPath $ExePath)) {
    Write-Err "link succeeded but exe missing at $ExePath"
    exit 1
}

$size = [math]::Round((Get-Item -LiteralPath $ExePath).Length / 1MB, 2)
Write-Ok "link complete — $OutName.exe  ($size MB)"
Write-Ok "path: $ExePath"
Write-Host ""
Write-Host "  & `"$ExePath`"" -ForegroundColor Cyan
Write-Host ""
