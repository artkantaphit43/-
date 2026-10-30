#!/usr/bin/env python3
"""สร้างแบบ SVG บ่อเวียร์ V-notch 90°: รูปตัดตามยาว, แปลน, รายละเอียดแผ่นเวียร์ (หน่วย m)

ลำดับการไหล: น้ำเข้า -> โซนรับน้ำ -> ผนังกั้นลอดใต้ -> แผ่นกันคลื่นรูพรุน -> ช่วงตรง -> V-notch -> ท่อออก 8"
"""
import os

OUT = "drawings"
FONT = "font-family='Sarabun, Tahoma, sans-serif'"

# ---- ค่าออกแบบ (ตรงกับ weir_design.py ค่า default) ----
WALL = 0.20
B = 1.00                # ความกว้างภายใน
X_BAFFLE = 0.60         # ผนังกั้นลอดใต้ หนา 0.10
X_PERF = 1.00           # แผ่นกันคลื่นรูพรุน (ต้นช่วงตรง)
X_WEIR = 2.80           # แผ่นเวียร์
X_TAP = X_WEIR - 0.80   # จุดวัดระดับ
X_END = 3.60            # ผิวในผนังท้าย
Z_VERTEX = 0.50
Z_NOTCH_TOP = 0.80
Z_WALL_TOP = 1.00
Z_MAX = 0.673           # 62 m³/h (ปั๊ม recycle หยุด)
Z_NORMAL = 0.661        # 52 m³/h
Z_GAP = 0.25            # ขอบล่างผนังกั้น
Z_TAIL = 0.15           # น้ำท้ายโดยประมาณที่ Qmax
Z_INLET = 0.30          # ท้องท่อน้ำเข้า
D_IN = 0.20
D_OUT = 0.20


def svg(w, h, body, title):
    return (f"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 {w} {h}' width='{w}' height='{h}' {FONT}>"
            f"<title>{title}</title>"
            "<defs><pattern id='rc' width='8' height='8' patternUnits='userSpaceOnUse' patternTransform='rotate(45)'>"
            "<rect width='8' height='8' fill='#d9d9d9'/><line x1='0' y1='0' x2='0' y2='8' stroke='#888' stroke-width='1.5'/></pattern>"
            "<marker id='a' viewBox='0 0 10 10' refX='5' refY='5' markerWidth='6' markerHeight='6' orient='auto-start-reverse'>"
            "<path d='M0,0 L10,5 L0,10 z' fill='#333'/></marker></defs>"
            f"<rect width='{w}' height='{h}' fill='white'/>{body}</svg>")


def text(x, y, t, size=13, anchor="start", color="#222", weight="normal"):
    return f"<text x='{x:.1f}' y='{y:.1f}' font-size='{size}' text-anchor='{anchor}' fill='{color}' font-weight='{weight}'>{t}</text>"


def line(x1, y1, x2, y2, color="#333", w=1.2, dash=None, arrow=False):
    d = f" stroke-dasharray='{dash}'" if dash else ""
    m = " marker-start='url(#a)' marker-end='url(#a)'" if arrow else ""
    return f"<line x1='{x1:.1f}' y1='{y1:.1f}' x2='{x2:.1f}' y2='{y2:.1f}' stroke='{color}' stroke-width='{w}'{d}{m}/>"


def rect(x, y, w, h, fill="url(#rc)", stroke="#333", sw=1.2):
    return f"<rect x='{x:.1f}' y='{y:.1f}' width='{w:.1f}' height='{h:.1f}' fill='{fill}' stroke='{stroke}' stroke-width='{sw}'/>"


def poly(pts, fill, stroke="#333", sw=1.2, opacity=1):
    p = " ".join(f"{x:.1f},{y:.1f}" for x, y in pts)
    return f"<polygon points='{p}' fill='{fill}' stroke='{stroke}' stroke-width='{sw}' fill-opacity='{opacity}'/>"


def flow_arrow(x, y, length=35):
    return (f"<line x1='{x:.1f}' y1='{y:.1f}' x2='{x+length:.1f}' y2='{y:.1f}' stroke='#3182bd' "
            "stroke-width='2.5' marker-end='url(#a)'/>")


# ---------------------------------------------------------------- Section
def section():
    S = 165
    X = lambda x: 110 + (x + WALL) * S
    Y = lambda z: 80 + (1.25 - z) * S
    b = []
    water = "#9ecae1"
    b.append(rect(X(0), Y(Z_MAX), X(X_WEIR) - X(0), Y(0) - Y(Z_MAX), fill=water, stroke="none"))
    b.append(rect(X(X_WEIR), Y(Z_TAIL), X(X_END) - X(X_WEIR), Y(0) - Y(Z_TAIL), fill=water, stroke="none"))
    # nappe
    xw = X(X_WEIR)
    b.append(f"<path d='M{xw:.1f},{Y(Z_MAX-0.01):.1f} Q{xw+60:.1f},{Y(0.72):.1f} {xw+75:.1f},{Y(Z_TAIL):.1f} "
             f"L{xw+48:.1f},{Y(Z_TAIL):.1f} Q{xw+30:.1f},{Y(0.50):.1f} {xw:.1f},{Y(Z_VERTEX):.1f} z' fill='{water}' stroke='#3182bd'/>")
    # concrete
    b.append(rect(X(-WALL), Y(0), X(X_END + WALL) - X(-WALL), 0.2 * S))
    b.append(rect(X(-WALL), Y(Z_WALL_TOP), WALL * S, Y(0) - Y(Z_WALL_TOP)))
    b.append(rect(X(X_END), Y(Z_WALL_TOP), WALL * S, Y(0) - Y(Z_WALL_TOP)))
    # inlet pipe
    b.append(rect(X(-WALL) - 50, Y(Z_INLET + D_IN), 50 + WALL * S, D_IN * S, fill="#bbb"))
    b.append(text(X(-WALL) - 50, Y(Z_INLET + D_IN) - 6, "น้ำเข้า", 12))
    b.append(flow_arrow(X(0.03), Y(Z_INLET + D_IN / 2), 50))
    # baffle (under-flow)
    b.append(rect(X(X_BAFFLE), Y(Z_WALL_TOP), 0.10 * S, Y(Z_GAP) - Y(Z_WALL_TOP)))
    b.append(line(X(X_BAFFLE + 0.14), Y(Z_GAP), X(X_BAFFLE + 0.14), Y(0), arrow=True))
    b.append(text(X(X_BAFFLE + 0.16), Y(0.10), "0.25", 11))
    b.append(f"<path d='M{X(0.45):.1f},{Y(0.15):.1f} H{X(0.85):.1f}' stroke='#3182bd' stroke-width='2.5' marker-end='url(#a)'/>")
    # perforated baffle
    for i in range(0, 9):
        z = i / 10
        b.append(rect(X(X_PERF) - 2, Y(z + 0.08), 4, 0.06 * S, fill="#666", stroke="none"))
    # measuring point
    xt = X(X_TAP)
    b.append(line(xt, Y(Z_WALL_TOP + 0.12), xt, Y(0), "#c00", 1.2, "6 3"))
    b.append(text(xt, Y(Z_WALL_TOP + 0.16), "จุดวัดระดับ h", 12, "middle", "#c00", "bold"))
    # weir plate
    b.append(rect(X(X_WEIR) - 3, Y(Z_NOTCH_TOP + 0.10), 5, Y(0) - Y(Z_NOTCH_TOP + 0.10), fill="#555"))
    b.append(text(X(X_WEIR) + 8, Y(Z_NOTCH_TOP + 0.14), "แผ่นเวียร์ V-notch 90°", 11))
    b.append(text(X(X_WEIR) + 8, Y(Z_NOTCH_TOP + 0.14) + 14, "SS304 หนา 6 mm", 11))
    # outlet pipe
    b.append(rect(X(X_END), Y(D_OUT), WALL * S + 50, D_OUT * S, fill="#bbb"))
    b.append(text(X(X_END + WALL) + 4, Y(D_OUT) - 6, "ท่อออก 8\"", 12))
    # elevations (left of measuring point)
    for z, name, c in [(Z_WALL_TOP, "สันกำแพง", "#333"), (Z_NOTCH_TOP, "ขอบบนร่อง V", "#333"),
                       (Z_MAX, "น้ำสูงสุด 62 m³/h", "#1f5f8b"), (Z_NORMAL, "น้ำปกติ 52 m³/h", "#1f5f8b"),
                       (Z_VERTEX, "ยอด V (h = 0)", "#c00"), (0.0, "พื้นบ่อ", "#333")]:
        dy = 11 if z in (Z_NORMAL, 0.0) else -3
        b.append(line(X(1.10), Y(z), X(X_WEIR) - 4, Y(z), c, 0.8, "3 2"))
        b.append(text(X(X_TAP) + 6, Y(z) + dy, f"{name} {z:+.3f}", 11, "start", c))
    b.append(text(X(X_END) - 4, Y(Z_TAIL) - 4, f"น้ำท้าย ≈ {Z_TAIL:+.2f}", 11, "end", "#1f5f8b"))
    # dims
    xv = X(X_WEIR) - 14
    b.append(line(xv, Y(Z_VERTEX), xv, Y(0), arrow=True))
    b.append(text(xv - 4, Y(0.30), f"P = {Z_VERTEX:.2f}", 12, "end"))
    b.append(line(X(X_TAP), Y(0.28), X(X_WEIR), Y(0.28), arrow=True))
    b.append(text((X(X_TAP) + X(X_WEIR)) / 2 - 20, Y(0.28) - 4, f"{X_WEIR - X_TAP:.2f}", 12, "middle"))
    yd = Y(-0.2) + 32
    for x1, x2, t in [(0, X_BAFFLE, "0.60"), (X_BAFFLE, X_PERF, "0.40"),
                      (X_PERF, X_WEIR, f"{X_WEIR - X_PERF:.2f} (ช่วงตรง)"), (X_WEIR, X_END, f"{X_END - X_WEIR:.2f}")]:
        b.append(line(X(x1), yd, X(x2), yd, arrow=True))
        b.append(text((X(x1) + X(x2)) / 2, yd - 5, t, 12, "middle"))
    b.append(line(X(-WALL), yd + 30, X(X_END + WALL), yd + 30, arrow=True))
    b.append(text((X(-WALL) + X(X_END + WALL)) / 2, yd + 25, f"{X_END + 2 * WALL:.2f} (ภายนอก) / {X_END:.2f} (ภายใน)", 12, "middle"))
    # labels
    b.append(text(X(0.30), Y(0.90), "โซนรับน้ำ", 12, "middle", weight="bold"))
    b.append(text(X(X_BAFFLE + 0.05), Y(Z_WALL_TOP) - 8, "ผนังกั้นลอดใต้", 11, "middle"))
    b.append(text(X(X_PERF) + 4, Y(Z_WALL_TOP) - 22, "แผ่นกันคลื่นรูพรุน", 11, "middle"))
    b.append(text(X(X_WEIR + 0.45), Y(0.38), "ช่องท้ายเวียร์", 12, "middle", weight="bold"))
    W, H = int(X(X_END + WALL) + 130), int(yd + 50)
    b.insert(0, text(W / 2, 30, "รูปตัดตามยาว A–A บ่อเวียร์  (พื้นบ่อ ±0.000, หน่วย m)", 16, "middle", weight="bold"))
    return svg(W, H, "".join(b), "รูปตัดตามยาวบ่อเวียร์ V-notch 90°")


# ---------------------------------------------------------------- Plan
def plan():
    S = 150
    X = lambda x: 110 + (x + WALL) * S
    Y = lambda y: 80 + (y + WALL) * S
    b = []
    b.append(rect(X(0), Y(0), X(X_END) - X(0), B * S, fill="#deebf7", stroke="none"))
    b.append(rect(X(-WALL), Y(-WALL), X(X_END + WALL) - X(-WALL), WALL * S))
    b.append(rect(X(-WALL), Y(B), X(X_END + WALL) - X(-WALL), WALL * S))
    b.append(rect(X(-WALL), Y(0), WALL * S, B * S))
    b.append(rect(X(X_END), Y(0), WALL * S, B * S))
    # inlet / outlet
    b.append(rect(X(-WALL) - 45, Y(B / 2) - D_IN * S / 2, 45 + WALL * S, D_IN * S, fill="#bbb"))
    b.append(text(X(-WALL) - 47, Y(B / 2) - D_IN * S / 2 - 6, "น้ำเข้า", 12))
    b.append(rect(X(X_END), Y(B / 2) - D_OUT * S / 2, WALL * S + 45, D_OUT * S, fill="#bbb"))
    b.append(text(X(X_END + WALL) + 47, Y(B / 2) + 4, "ท่อออก 8\"", 12))
    # baffles, plate
    b.append(rect(X(X_BAFFLE), Y(0), 0.10 * S, B * S))
    b.append(line(X(X_PERF), Y(0), X(X_PERF), Y(B), "#555", 4, "6 4"))
    b.append(rect(X(X_WEIR) - 2, Y(-0.10), 5, (B + 0.2) * S, fill="#333"))
    b.append(f"<circle cx='{X(X_TAP):.1f}' cy='{Y(0.15):.1f}' r='6' fill='none' stroke='#c00' stroke-width='2'/>")
    b.append(text(X(X_TAP) + 10, Y(0.15) + 4, "จุดวัดระดับ h", 11, color="#c00"))
    for x in (0.15, 1.4, 2.2, 3.05):
        b.append(flow_arrow(X(x), Y(B / 2 + 0.25)))
    ya = Y(B / 2)
    b.append(line(X(-WALL) - 20, ya, X(X_END + WALL) + 20, ya, "#c00", 1, "12 4 2 4"))
    b.append(text(X(-WALL) - 22, ya + 18, "A", 14, "end", "#c00", "bold"))
    b.append(text(X(X_END + WALL) + 22, ya + 18, "A", 14, "start", "#c00", "bold"))
    # labels and dims
    yl = Y(B + WALL) + 18
    for x, t in [(X_BAFFLE + 0.05, "ผนังกั้นลอดใต้"), (X_PERF + 0.25, "แผ่นกันคลื่นรูพรุน"), (X_WEIR, "แผ่นเวียร์")]:
        b.append(text(X(x), yl, t, 11, "middle"))
    yd = yl + 30
    b.append(line(X(-WALL), yd, X(X_END + WALL), yd, arrow=True))
    b.append(text((X(-WALL) + X(X_END + WALL)) / 2, yd - 5, f"{X_END + 2 * WALL:.2f}", 12, "middle"))
    xd = X(X_END + WALL) + 25
    b.append(line(xd, Y(0), xd, Y(B), arrow=True))
    b.append(text(xd + 6, Y(0.3), f"{B:.2f} (ภายใน)", 12))
    W, H = int(xd + 110), int(yd + 25)
    b.insert(0, text(W / 2, 30, "แปลนบ่อเวียร์ (หน่วย m, ผนัง คสล. หนา 0.20)", 16, "middle", weight="bold"))
    return svg(W, H, "".join(b), "แปลนบ่อเวียร์ V-notch 90°")


# ---------------------------------------------------------------- Plate detail
def plate():
    S = 330
    half = B / 2 + 0.10              # ฝังร่องผนังข้างละ 0.10
    top = Z_NOTCH_TOP + 0.10
    X = lambda x: 70 + (x + half) * S
    Y = lambda z: 80 + (top + 0.05 - z) * S
    b = []
    w = Z_NOTCH_TOP - Z_VERTEX
    pts = [(-half, top), (-w, top), (-w, Z_NOTCH_TOP), (0, Z_VERTEX), (w, Z_NOTCH_TOP), (w, top), (half, top), (half, 0), (-half, 0)]
    b.append(poly([(X(x), Y(z)) for x, z in pts], "#cfd8dc", "#333", 1.5))
    for xs in (-half, B / 2):
        b.append(rect(X(xs), Y(top), 0.10 * S, top * S, fill="url(#rc)", stroke="#333", sw=0.8))
    b.append(text(X(-half + 0.05), Y(0.45), "ฝังร่อง", 11, "middle"))
    b.append(text(X(-half + 0.05), Y(0.45) + 14, "ในผนัง", 11, "middle"))
    hz = Z_MAX
    b.append(poly([(X(-(hz - Z_VERTEX)), Y(hz)), (X(0), Y(Z_VERTEX)), (X(hz - Z_VERTEX), Y(hz))], "#9ecae1", "#3182bd", 1, 0.9))
    b.append(line(X(-w), Y(top) - 18, X(w), Y(top) - 18, arrow=True))
    b.append(text(X(0), Y(top) - 24, f"{2*w:.2f}", 13, "middle"))
    xr = X(w + 0.08)
    b.append(line(xr, Y(Z_NOTCH_TOP), xr, Y(Z_VERTEX), arrow=True))
    b.append(text(xr + 6, Y((Z_NOTCH_TOP + Z_VERTEX) / 2) + 4, f"ลึกร่อง {w:.2f}", 12))
    b.append(line(xr, Y(Z_VERTEX), xr, Y(0), arrow=True))
    b.append(text(xr + 6, Y(Z_VERTEX / 2), f"P = {Z_VERTEX:.2f}", 12))
    b.append(line(X(-w - 0.05), Y(Z_VERTEX), X(-0.01), Y(Z_VERTEX), "#3182bd", 0.8, "3 2"))
    b.append(line(X(-w - 0.03), Y(hz), X(-w - 0.03), Y(Z_VERTEX), "#3182bd", 1.2, arrow=True))
    b.append(text(X(-w - 0.05), Y((hz + Z_VERTEX) / 2) + 4, f"hmax = {hz - Z_VERTEX:.2f}", 12, "end", "#1f5f8b"))
    b.append(f"<path d='M{X(-0.06):.1f},{Y(Z_VERTEX+0.06):.1f} Q{X(0):.1f},{Y(Z_VERTEX+0.10):.1f} {X(0.06):.1f},{Y(Z_VERTEX+0.06):.1f}' fill='none' stroke='#c00'/>")
    b.append(text(X(0), Y(Z_VERTEX + 0.12), "90° ± 0.1°", 13, "middle", "#c00", "bold"))
    b.append(line(X(-B / 2), Y(-0.05), X(B / 2), Y(-0.05), arrow=True))
    b.append(text(X(0), Y(-0.05) + 16, f"B = {B:.2f} (ภายในบ่อ)", 12, "middle"))
    b.append(line(X(-half), Y(-0.14), X(half), Y(-0.14), arrow=True))
    b.append(text(X(0), Y(-0.14) + 16, f"กว้างแผ่น {2*half:.2f}  สูง {top:.2f}", 12, "middle"))
    # edge detail
    ox, oy, k = X(half) + 90, Y(Z_NOTCH_TOP), 9
    t, land = 6, 1.5
    pts = [(ox, oy), (ox + land * k, oy), (ox + t * k, oy + (t - land) * k), (ox + t * k, oy + 180), (ox, oy + 180)]
    b.append(poly(pts, "#cfd8dc", "#333", 1.5))
    b.append(text(ox + 3 * k, oy - 46, "รายละเอียดขอบร่อง V", 13, "middle", weight="bold"))
    b.append(text(ox + 3 * k, oy - 30, "(ตัดตั้งฉากกับขอบ)", 11, "middle"))
    b.append(line(ox, oy - 12, ox + land * k, oy - 12, arrow=True))
    b.append(text(ox - 4, oy - 16, "1–2 mm", 11, "end"))
    b.append(line(ox, oy + 195, ox + t * k, oy + 195, arrow=True))
    b.append(text(ox + 3 * k, oy + 211, "t = 6 mm", 11, "middle"))
    b.append(text(ox - 6, oy + 90, "เหนือน้ำ ←", 11, "end", "#1f5f8b"))
    b.append(text(ox + t * k + 6, oy + 90, "→ ท้ายน้ำ", 11, "start", "#1f5f8b"))
    b.append(text(ox + t * k + 6, oy + 30, "ลบมุม 45°", 11))
    b.append(text(ox + t * k + 6, oy + 44, "ด้านท้ายน้ำ", 11))
    W, H = int(ox + 140), int(Y(-0.14) + 40)
    b.insert(0, text(W / 2, 30, "แผ่นเวียร์ V-notch 90° (มองจากด้านเหนือน้ำ, หน่วย m)", 16, "middle", weight="bold"))
    return svg(W, H, "".join(b), "แผ่นเวียร์ V-notch 90°")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, fn in [("section", section), ("plan", plan), ("weir_plate", plate)]:
        with open(os.path.join(OUT, f"{name}.svg"), "w", encoding="utf-8") as f:
            f.write(fn())
        print(f"{OUT}/{name}.svg")
