import tkinter as tk

class A(tk.Tk):
    def __init__(s):
        super().__init__()
        s.title("Coming Soon")
        s.geometry("400x240")
        s.overrideredirect(True)
        s.attributes("-topmost", True)
        s.attributes("-alpha", 0.0)
        s.configure(bg="#050814")
        
        sw = s.winfo_screenwidth()
        sh = s.winfo_screenheight()
        x = (sw - 400) // 2
        y = (sh - 240) // 2
        s.geometry(f"400x240+{x}+{y}")
        
        s.b1 = tk.Frame(s, bg="#6366f1", bd=0)
        s.b1.pack(fill="both", expand=True, padx=1, pady=1)
        
        s.b2 = tk.Frame(s.b1, bg="#0f1330", bd=0)
        s.b2.pack(fill="both", expand=True, padx=1, pady=1)
        
        s.b3 = tk.Label(s.b2, text="✕", bg="#0f1330", fg="#64748b", font=("Segoe UI", 12, "bold"), cursor="hand2")
        s.b3.place(relx=0.95, rely=0.12, anchor="center")
        s.b3.bind("<Button-1>", lambda e: s.destroy())
        s.b3.bind("<Enter>", lambda e: s.b3.config(fg="#ef4444"))
        s.b3.bind("<Leave>", lambda e: s.b3.config(fg="#64748b"))
        
        s.l1 = tk.Label(s.b2, text="◈", bg="#0f1330", fg="#6366f1", font=("Segoe UI", 36))
        s.l1.pack(pady=(40, 5))
        
        s.l2 = tk.Label(s.b2, text="C O M I N G   S O O N", bg="#0f1330", fg="#e2e8f0", font=("Segoe UI", 14, "bold"))
        s.l2.pack(pady=(0, 10))
        
        s.l3 = tk.Label(s.b2, text="This game is currently in development.\nCheck back later!", bg="#0f1330", fg="#94a3b8", font=("Segoe UI", 10), justify="center")
        s.l3.pack()
        
        for w in (s.b2, s.l1, s.l2, s.l3):
            w.bind("<Button-1>", s.f1)
            w.bind("<B1-Motion>", s.f2)

        s.f3()

    def f3(s):
        a = s.attributes("-alpha")
        if a < 0.95:
            s.attributes("-alpha", min(0.95, a + 0.05))
            s.after(20, s.f3)

    def f1(s, event):
        s.d1 = event.x_root - s.winfo_x()
        s.d2 = event.y_root - s.winfo_y()

    def f2(s, event):
        x = event.x_root - s.d1
        y = event.y_root - s.d2
        s.geometry(f"+{x}+{y}")

if __name__ == "__main__":
    a = A()
    a.mainloop()
