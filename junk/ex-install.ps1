[CmdletBinding()]
param(
    [string]$Out = "exiled",
    [string]$Icon = "https://raw.githubusercontent.com/sswivell/sswivell/refs/heads/main/junk/halloween.png",
    [string]$Dir,
    [switch]$NoIcon,
    [switch]$KeepBuild,
    [switch]$SkipSmokeTest
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

# ─────────────────────────────────────────────────────────────────────────────
# PAYLOAD — your actual key-validator source, in plain form.
# (No obfuscation wrapper = no more NameError: 'r' is not defined.)
# ─────────────────────────────────────────────────────────────────────────────
$stubBody = @'
import hashlib, hmac, sys, time, os, webbrowser, threading

SECRET       = b"my-super-secret-2026"
GUILD_ID     = 1517380157533589564
INVITE_URL   = "https://discord.gg/gBGFejkwyU"
KEY_LIFETIME = 20 * 60

class C:
    RST   = "\033[0m"
    BOLD  = "\033[1m"
    DIM   = "\033[2m"
    RED   = "\033[38;5;203m"
    G2    = "\033[38;5;28m"
    G3    = "\033[38;5;34m"
    G4    = "\033[38;5;40m"
    G5    = "\033[38;5;46m"
    G6    = "\033[38;5;82m"
    G7    = "\033[38;5;118m"
    G8    = "\033[38;5;154m"

def clr():
    os.system("cls" if os.name == "nt" else "clear")

def typed(text, color="", delay=0.008):
    for ch in text:
        sys.stdout.write(color + ch + C.RST)
        sys.stdout.flush()
        time.sleep(delay)
    print()

def line(char="─", n=62, color=C.G3):
    print(color + char * n + C.RST)

def panel(title, body, color=C.G3, width=60):
    print(color + "┌" + "─" * width + "┐" + C.RST)
    pad = width - len(title) - 1
    print(color + "│" + C.RST + f" {C.BOLD}{C.G8}{title}{C.RST}" + " " * pad + color + "│" + C.RST)
    print(color + "├" + "─" * width + "┤" + C.RST)
    for row in body:
        pad = width - len(row) - 1
        print(color + "│" + C.RST + f" {row}{' ' * max(pad, 0)}" + color + "│" + C.RST)
    print(color + "└" + "─" * width + "┘" + C.RST)

def spinner(msg, seconds=0.9):
    frames = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    end = time.time() + seconds
    i = 0
    while time.time() < end:
        sys.stdout.write(f"\r  {C.G6}{frames[i % len(frames)]}{C.RST}  {C.G3}{msg}{C.RST}")
        sys.stdout.flush()
        time.sleep(0.06)
        i += 1
    sys.stdout.write(f"\r  {C.G8}✓{C.RST}  {C.G5}{msg}{' ' * 20}\n")

LOGO = r"""
              ####              
        ################        
   ########++++++++++########   
 #####++++++++++++++++++++##### 
 ##++++++##############++++++## 
 ##+++++###############++++++## 
 ##+++++###++++++++++++++++++## 
 ###++++###+++++++++++++++++### 
  ##++++############++++++++##  
  ##++++###+++++++++++++++++##  
  ##++++###+++++++++++++++++##  
  ##++++###############+++++##  
   ##++++##############++++##   
   ####++++++++++++++++++####   
     #######++++++++#######     
         ##############         
              ####
"""

def draw_header():
    clr()
    rows = LOGO.strip("\n").split("\n")
    n = len(rows)
    for i, l in enumerate(rows):
        t = i / max(n - 1, 1)
        if   t < 0.25: col = C.G3
        elif t < 0.40: col = C.G4
        elif t < 0.55: col = C.G5
        elif t < 0.70: col = C.G6
        elif t < 0.85: col = C.G7
        else:          col = C.G8
        print(col + l + C.RST)
    print()
    sub = "E X I L E D · E X T E R N A L"
    print(f"  {C.G3}┈┈{C.RST} {C.BOLD}{C.G8}{sub}{C.RST} {C.G3}┈┈{C.RST}")
    print(f"  {C.G3}Join our discord to get the key. (completely free){C.RST}\n")

def _sig(body):
    msg = f"{body}|{GUILD_ID}".encode()
    return hmac.new(SECRET, msg, hashlib.sha256).hexdigest()[:8].upper()

def check_key(k):
    k = k.strip().upper()
    parts = k.split("-")
    if len(parts) != 7 or parts[0] != "ASCII":
        return False, "malformed", 0
    body = "-".join(parts[:6])
    want = _sig(body)
    got  = parts[6]
    if not hmac.compare_digest(want, got):
        return False, "bad signature", 0
    try:
        ts = int(parts[5], 16)
    except ValueError:
        return False, "bad timestamp", 0
    age = int(time.time()) - ts
    if age > KEY_LIFETIME:
        return False, "expired", 0
    if age < -60:
        return False, "timestamp in future", 0
    return True, "valid", KEY_LIFETIME - age

def show_success_popup(minutes_left):
    """Small tkinter window - green on black - auto-closes after 4s or click."""
    try:
        import tkinter as tk
    except ImportError:
        return

    def _run():
        root = tk.Tk()
        root.title("access granted")
        root.configure(bg="#0b0f0b")
        root.resizable(False, False)

        w, h = 380, 170
        sw = root.winfo_screenwidth()
        sh = root.winfo_screenheight()
        x = (sw - w) // 2
        y = (sh - h) // 2
        root.geometry(f"{w}x{h}+{x}+{y}")

        frame = tk.Frame(root, bg="#0b0f0b", highlightbackground="#28a03c",
                         highlightthickness=2)
        frame.pack(fill="both", expand=True, padx=1, pady=1)

        tk.Label(frame, text="ACCESS GRANTED",
                 font=("Consolas", 18, "bold"),
                 fg="#5cff7a", bg="#0b0f0b").pack(pady=(22, 6))

        tk.Label(frame, text=f"key valid · {minutes_left} min left",
                 font=("Consolas", 10),
                 fg="#3ca03a", bg="#0b0f0b").pack()

        tk.Button(frame, text="ok", command=root.destroy,
                  font=("Consolas", 10, "bold"),
                  fg="#0b0f0b", bg="#5cff7a",
                  activebackground="#3ca03a", activeforeground="#0b0f0b",
                  bd=0, padx=22, pady=4, cursor="hand2").pack(pady=(16, 0))

        root.after(4000, root.destroy)
        try:
            root.attributes("-topmost", True)
        except Exception:
            pass
        root.mainloop()

    t = threading.Thread(target=_run, daemon=True)
    t.start()
    t.join()

def do_join():
    draw_header()
    panel("JOIN DISCORD", [
        f"{C.G4}Opening the invite in your browser...{C.RST}",
        f"{C.G3}If nothing happens, open this link manually:{C.RST}",
        f"{C.G8}{C.BOLD}{INVITE_URL}{C.RST}",
    ], C.G6, width=60)
    print()
    spinner("resolving invite", 0.4)
    spinner("launching browser", 0.5)
    try:
        webbrowser.open(INVITE_URL)
        print(f"\n  {C.G8}✔  browser opened{C.RST}")
    except Exception:
        print(f"\n  {C.RED}✘  could not open browser automatically{C.RST}")
    print()
    line(color=C.G6)
    print(f"  {C.G3}Join the discord and dm the bot /gen.{C.RST}")
    print(f"  {C.G3}Use [2] Validate key to check it here.{C.RST}")
    line(color=C.G6)
    input(f"\n  {C.G4}press enter to return...{C.RST}")

def do_validate():
    draw_header()
    panel("VALIDATE KEY", [
        f"{C.G4}Paste your key below.{C.RST}",
        f"{C.G3}expires {KEY_LIFETIME // 60} min after issue · guild {GUILD_ID}{C.RST}",
    ], C.G4)
    print()
    k = input(f"  {C.G7}›{C.RST} ").strip()
    print()
    spinner("parsing", 0.4)
    spinner("verifying signature", 0.6)
    spinner("checking expiry", 0.4)
    print()
    line(color=C.G6)
    ok, reason, left = check_key(k)
    if ok:
        m, s = divmod(left, 60)
        print(f"  {C.G8}{C.BOLD}✔  VALID{C.RST}  {C.G4}— access granted{C.RST}")
        print(f"  {C.G3}expires in {m}m {s}s{C.RST}")
        line(color=C.G6)
        show_success_popup(m)
    else:
        print(f"  {C.RED}{C.BOLD}✘  INVALID{C.RST}  {C.G4}— {reason}{C.RST}")
        line(color=C.G6)
    input(f"\n  {C.G4}press enter to return...{C.RST}")

def do_menu():
    draw_header()
    items = [
        f"{C.G7}[1]{C.RST}  {C.G8}Join Discord{C.RST}",
        f"{C.G7}[2]{C.RST}  {C.G8}Validate key{C.RST}",
        f"{C.G7}[3]{C.RST}  {C.G8}Exit{C.RST}",
    ]
    panel("MAIN MENU", items, C.G4)
    print()
    return input(f"  {C.G7}›{C.RST} ").strip()

def main():
    while True:
        choice = do_menu()
        if choice == "1":
            do_join()
        elif choice == "2":
            do_validate()
        elif choice == "3":
            clr()
            typed("  good bye 👋\n", C.G4)
            return
        else:
            print(f"\n  {C.RED}unknown option{C.RST}")
            time.sleep(0.8)

if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, EOFError):
        print(f"\n  {C.G3}interrupted{C.RST}")
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
    "--log-level", "WARN",
    "--hidden-import", "tkinter",
    "--hidden-import", "tkinter.ttk",
    "--name", $OutName,
    "--distpath", $DistDir,
    "--workpath", (Join-Path $Work "pyi"),
    "--specpath", $Work
)
if ($UseIcon -and (Test-Path $IconIco)) {
    $pyiArgs += @("--icon", $IconIco)
}
$pyiArgs += $Stub

$ErrorActionPreference = "Continue"
& $PythonExe @pyiArgs
$pyiExit = $LASTEXITCODE
$ErrorActionPreference = $oldEAP

if ($pyiExit -ne 0) {
    Log error "PyInstaller failed (exit $pyiExit)."
    exit 1
}

if (-not (Test-Path -LiteralPath $ExePath)) {
    Log error "Build reported success but $ExePath is missing."
    exit 1
}

# ── Smoke test — run the exe once, feed "3" (exit) so it doesn't hang ────────
if (-not $SkipSmokeTest) {
    Log info "Smoke-testing $ExePath (feeding '3' to exit)..."
    $ErrorActionPreference = "Continue"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ExePath
    $psi.RedirectStandardInput  = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute = $false
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.WriteLine("3")
    $p.StandardInput.Close()
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit(10000) | Out-Null
    $smokeExit = $p.ExitCode
    $ErrorActionPreference = $oldEAP

    if ($smokeExit -ne 0) {
        Log error "Payload crashed at runtime (exit $smokeExit):"
        ($stdout + "`n" + $stderr) -split "`n" | ForEach-Object { if ($_.Trim()) { Log error "$_" } }
        exit 1
    }
    Log success "Payload ran cleanly."
} else {
    Log warning "Smoke-test skipped (-SkipSmokeTest)."
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
