#!/usr/bin/env python3
"""สร้างแบบ SVG บ่อ 3 ช่อง: รูปตัดตามยาว, แปลน, รายละเอียดแผ่นเวียร์ (หน่วย m)

ช่อง 1 รับน้ำ + ปั๊มจุ่ม -> ช่อง 2 พื้นยก น้ำไหลบางโชว์ความใส -> ช่อง 3 V-notch 90° -> ท่อออก 8"
"""
import os

OUT = "drawings"
FONT = "font-family='Sarabun, Tahoma, sans-serif'"

# ---- ค่าออกแบบ (ตรงกับ weir_design.py ค่า default) ----
WALL = 0.20
B = 1.05                # ความกว้างภายใน
# ช่อง 1
X_BAFFLE = 0.50         # ผนังกั้นลอดใต้ หนา 0.10
X_PUMP = 1.10
X_C1_END = 1.60
# ช่อง 2
X_C2_END = 3.60         # ปลายพื้นยก + สันปลาย
Z_RAISED = 0.90
SILL = 0.02
# ช่อง 3
X_PERF = 4.10           # แผ่นกันคลื่นรูพรุน
X_WEIR = 6.20           # ผิวเหนือน้ำของกำแพงเวียร์ (ช่วงตรง 2.10)
T_WW = 0.20             # กำแพงเวียร์ คสล.
X_TAP = X_WEIR - 0.95
X_END = 7.35             # ท้ายเวียร์ 0.95
Z_VERTEX = 0.60
Z_NOTCH_TOP = 0.90
Z_WALL_TOP = 1.20
Z_MAX = 0.810           # ช่อง 3 ที่ 100 m³/h
Z_C1 = 0.99             # ช่อง 1 ที่ 100 m³/h
Z_C2 = Z_RAISED + 0.079 # ช่อง 2 ที่ 100 m³/h
Z_GAP = 0.30
Z_WW = 0.50             # สันกำแพงเวียร์ คสล.
Z_PB = 0.40             # ขอบล่างแผ่นเวียร์
Z_START = 0.80
Z_STOP = 0.40
Z_DIP = 0.30
Z_TAIL = 0.21
D_IN = 0.15
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
    S = 140
    X = lambda x: 90 + (x + WALL) * S
    Y = lambda z: 110 + (1.45 - z) * S
    b = []
    water = "#9ecae1"
    clear = "#c6e9f5"
    # water
    b.append(rect(X(0), Y(Z_C1), X(X_C1_END) - X(0), Y(0) - Y(Z_C1), fill=water, stroke="none"))
    b.append(poly([(X(X_C1_END), Y(Z_C1)), (X(X_C1_END + 0.3), Y(Z_C2)), (X(X_C2_END), Y(Z_C2)),
                   (X(X_C2_END), Y(Z_RAISED)), (X(X_C1_END), Y(Z_RAISED))], clear, "#3182bd", 0.8))
    b.append(rect(X(X_C2_END), Y(Z_MAX), X(X_WEIR) - X(X_C2_END), Y(0) - Y(Z_MAX), fill=water, stroke="none"))
    b.append(rect(X(X_WEIR + T_WW), Y(Z_TAIL), X(X_END) - X(X_WEIR + T_WW), Y(0) - Y(Z_TAIL), fill=water, stroke="none"))
    # sheet falling from ช่อง 2
    xs = X(X_C2_END)
    b.append(f"<path d='M{xs:.1f},{Y(Z_C2):.1f} Q{xs+22:.1f},{Y(Z_C2-0.02):.1f} {xs+30:.1f},{Y(Z_MAX):.1f} "
             f"L{xs+18:.1f},{Y(Z_MAX):.1f} Q{xs+12:.1f},{Y(Z_RAISED+0.01):.1f} {xs:.1f},{Y(Z_RAISED+SILL):.1f} z' fill='{clear}' stroke='#3182bd'/>")
    # V-notch nappe
    xw = X(X_WEIR)
    b.append(f"<path d='M{xw:.1f},{Y(Z_MAX-0.01):.1f} Q{xw+55:.1f},{Y(0.72):.1f} {xw+68:.1f},{Y(Z_TAIL):.1f} "
             f"L{xw+44:.1f},{Y(Z_TAIL):.1f} Q{xw+28:.1f},{Y(0.50):.1f} {xw:.1f},{Y(Z_VERTEX):.1f} z' fill='{water}' stroke='#3182bd'/>")
    # concrete
    b.append(rect(X(-WALL), Y(0), X(X_END + WALL) - X(-WALL), 0.2 * S))
    b.append(rect(X(-WALL), Y(Z_WALL_TOP), WALL * S, Y(0) - Y(Z_WALL_TOP)))
    b.append(rect(X(X_END), Y(Z_WALL_TOP), WALL * S, Y(0) - Y(Z_WALL_TOP)))
    b.append(rect(X(X_C1_END), Y(Z_RAISED), X(X_C2_END) - X(X_C1_END), Y(0) - Y(Z_RAISED)))   # พื้นยก
    b.append(rect(X(X_C1_END), Y(Z_RAISED) - 3, X(X_C2_END) - X(X_C1_END), 3, fill="#fff", stroke="#888", sw=0.6))
    b.append(rect(X(X_C2_END) - 3, Y(Z_RAISED + SILL), 3, SILL * S, fill="#555"))           # สันปลาย SS
    # ช่อง 1: inlet + dip pipe, baffle, pump
    b.append(rect(X(-WALL) - 45, Y(1.10), 45 + (WALL + 0.20) * S, D_IN * S, fill="#bbb"))
    b.append(rect(X(0.20) - D_IN * S, Y(1.10), D_IN * S, Y(Z_DIP) - Y(1.10), fill="#bbb"))
    b.append(text(X(-WALL) - 45, Y(1.10) - 6, "ท่อน้ำเข้า 6\"", 12))
    b.append(f"<line x1='{X(0.20) - D_IN*S/2:.1f}' y1='{Y(Z_DIP)+3:.1f}' x2='{X(0.20) - D_IN*S/2:.1f}' y2='{Y(Z_DIP)+26:.1f}' stroke='#3182bd' stroke-width='2.5' marker-end='url(#a)'/>")
    b.append(rect(X(X_BAFFLE), Y(Z_WALL_TOP), 0.10 * S, Y(Z_GAP) - Y(Z_WALL_TOP)))
    b.append(line(X(X_BAFFLE + 0.13), Y(Z_GAP), X(X_BAFFLE + 0.13), Y(0), arrow=True))
    b.append(text(X(X_BAFFLE + 0.15), Y(0.10), f"{Z_GAP:.2f}", 10))
    xp = X(X_PUMP)
    b.append(rect(xp - 20, Y(0.55), 40, 0.55 * S, fill="#f2a541"))
    b.append(text(xp, Y(0.28), "ปั๊ม", 11, "middle", weight="bold"))
    b.append(f"<path d='M{xp+20:.1f},{Y(0.35):.1f} H{X(1.40):.1f} V{Y(1.38):.1f} H{X(2.2):.1f}' fill='none' stroke='#2c7a2c' stroke-width='6'/>")
    b.append(text(X(2.2) + 6, Y(1.38) + 4, "→ Water recycle 10 m³/h", 12, color="#2c7a2c"))
    for z, name, c in [(Z_START, "START", "#2c7a2c"), (Z_STOP, "STOP", "#2c7a2c")]:
        b.append(line(X(X_BAFFLE + 0.12), Y(z), X(X_C1_END), Y(z), c, 1, "6 3"))
        b.append(text(X(X_BAFFLE + 0.13), Y(z) - 3, f"{name} {z:+.2f}", 10, "start", c))
    # ช่อง 3: perforated baffle, tap, plate, outlet
    for i in range(0, 9):
        b.append(rect(X(X_PERF) - 2, Y(i / 10 + 0.08), 4, 0.06 * S, fill="#666", stroke="none"))
    xt = X(X_TAP)
    b.append(line(xt, Y(Z_WALL_TOP + 0.08), xt, Y(0), "#c00", 1.2, "6 3"))
    b.append(text(xt, Y(Z_WALL_TOP + 0.11), "จุดวัดระดับ h", 12, "middle", "#c00", "bold"))
    b.append(rect(X(X_WEIR), Y(Z_WW), T_WW * S, Y(0) - Y(Z_WW)))
    b.append(rect(X(X_WEIR) - 3, Y(Z_NOTCH_TOP + 0.10), 5, Y(Z_PB) - Y(Z_NOTCH_TOP + 0.10), fill="#555"))
    b.append(text(X(X_WEIR) + 8, Y(Z_NOTCH_TOP + 0.14), "แผ่น V-notch SS304", 11))
    b.append(text(X(X_WEIR + T_WW) + 4, Y(Z_WW) + 14, f"กำแพงเวียร์ คสล. {Z_WW:+.2f}", 10))
    b.append(rect(X(X_END), Y(D_OUT), WALL * S + 45, D_OUT * S, fill="#bbb"))
    b.append(text(X(X_END + WALL) + 4, Y(D_OUT) - 6, "ท่อออก 8\"", 12))
    # elevations
    for z, name, c in [(Z_WALL_TOP, "สันกำแพง", "#333"), (Z_NOTCH_TOP, "ขอบบนร่อง V", "#333"),
                       (Z_MAX, "น้ำสูงสุด", "#1f5f8b"), (Z_VERTEX, "ยอด V (h = 0)", "#c00")]:
        b.append(line(X(4.25), Y(z), X(X_WEIR) - 4, Y(z), c, 0.8, "3 2"))
        b.append(text(X(X_TAP) - 6, Y(z) + (11 if z == Z_MAX else -3), f"{name} {z:+.3f}", 11, "end", c))
    b.append(text(X(2.6), Y(Z_RAISED) + 18, f"ผิวพื้นยก {Z_RAISED:+.2f}", 11, "middle"))
    b.append(text(X(2.6), Y(Z_C2) - 6, "ชั้นน้ำใส 5–7 cm", 12, "middle", "#1f5f8b", "bold"))
    b.append(text(X(X_C2_END) - 6, Y(Z_RAISED + SILL) - 22, f"สันปลาย {SILL*100:.0f} cm", 10, "end"))
    b.append(text(X(0.95), Y(Z_C1) - 5, f"น้ำ {Z_C1:+.2f}", 11, "middle", "#1f5f8b"))
    b.append(text(X(X_END) - 4, Y(Z_TAIL) - 4, f"น้ำท้าย ≈ {Z_TAIL:+.2f}", 11, "end", "#1f5f8b"))
    xv = X(X_WEIR) - 14
    b.append(line(xv, Y(Z_VERTEX), xv, Y(0), arrow=True))
    b.append(text(xv - 4, Y(0.30), f"P = {Z_VERTEX:.2f}", 12, "end"))
    b.append(line(X(X_TAP), Y(0.40), X(X_WEIR), Y(0.40), arrow=True))
    b.append(text((X(X_TAP) + X(X_WEIR)) / 2 - 18, Y(0.40) - 4, f"{X_WEIR - X_TAP:.2f}", 12, "middle"))
    # compartment headers
    for x1, x2, t in [(0, X_C1_END, "ช่อง 1  รับน้ำ + ปั๊มจุ่ม"), (X_C1_END, X_C2_END, "ช่อง 2  โชว์น้ำใส (พื้นยก)"),
                      (X_C2_END, X_END, "ช่อง 3  เวียร์ V-notch 90°")]:
        b.append(text((X(x1) + X(x2)) / 2, Y(Z_WALL_TOP) - 52, t, 14, "middle", weight="bold"))
    # dims
    yd = Y(-0.2) + 30
    for x1, x2, t in [(0, X_C1_END, f"{X_C1_END:.2f}"), (X_C1_END, X_C2_END, f"{X_C2_END - X_C1_END:.2f}"),
                      (X_C2_END, X_PERF, f"{X_PERF - X_C2_END:.2f}"), (X_PERF, X_WEIR, f"{X_WEIR - X_PERF:.2f} (ช่วงตรง)"),
                      (X_WEIR, X_WEIR + T_WW, f"{T_WW:.2f}"), (X_WEIR + T_WW, X_END, f"{X_END - X_WEIR - T_WW:.2f}")]:
        b.append(line(X(x1), yd, X(x2), yd, arrow=True))
        b.append(text((X(x1) + X(x2)) / 2, yd - 5, t, 12, "middle"))
    b.append(line(X(-WALL), yd + 30, X(X_END + WALL), yd + 30, arrow=True))
    b.append(text((X(-WALL) + X(X_END + WALL)) / 2, yd + 25, f"{X_END + 2*WALL:.2f} (ภายนอก) / {X_END:.2f} (ภายใน)", 12, "middle"))
    W, H = int(X(X_END + WALL) + 120), int(yd + 50)
    b.insert(0, text(W / 2, 30, "รูปตัดตามยาว A–A บ่อ 3 ช่อง  (พื้นบ่อ ±0.000, หน่วย m, แสดงที่ 100 m³/h)", 16, "middle", weight="bold"))
    return svg(W, H, "".join(b), "รูปตัดตามยาวบ่อ 3 ช่อง")


# ---------------------------------------------------------------- Plan
def plan():
    S = 125
    X = lambda x: 90 + (x + WALL) * S
    Y = lambda y: 80 + (y + WALL) * S
    b = []
    b.append(rect(X(0), Y(0), X(X_C1_END) - X(0), B * S, fill="#deebf7", stroke="none"))
    b.append(rect(X(X_C1_END), Y(0), X(X_C2_END) - X(X_C1_END), B * S, fill="#f2fbff", stroke="#888", sw=0.6))
    b.append(rect(X(X_C2_END), Y(0), X(X_END) - X(X_C2_END), B * S, fill="#deebf7", stroke="none"))
    b.append(rect(X(-WALL), Y(-WALL), X(X_END + WALL) - X(-WALL), WALL * S))
    b.append(rect(X(-WALL), Y(B), X(X_END + WALL) - X(-WALL), WALL * S))
    b.append(rect(X(-WALL), Y(0), WALL * S, B * S))
    b.append(rect(X(X_END), Y(0), WALL * S, B * S))
    # items
    b.append(rect(X(-WALL) - 40, Y(0.30) - D_IN * S / 2, 40 + (WALL + 0.20) * S, D_IN * S, fill="#bbb"))
    b.append(f"<circle cx='{X(0.20) - D_IN*S/2:.1f}' cy='{Y(0.30):.1f}' r='{D_IN*S/2:.1f}' fill='#bbb' stroke='#333'/>")
    b.append(text(X(-WALL) - 42, Y(0.30) - 14, "ท่อน้ำเข้า 6\"", 12))
    b.append(rect(X(X_BAFFLE), Y(0), 0.10 * S, B * S))
    b.append(f"<circle cx='{X(X_PUMP):.1f}' cy='{Y(0.6):.1f}' r='{0.16*S:.1f}' fill='#f2a541' stroke='#333'/>")
    b.append(text(X(X_PUMP), Y(0.6) + 5, "P", 14, "middle", weight="bold"))
    b.append(f"<path d='M{X(X_PUMP)+0.16*S:.1f},{Y(0.6):.1f} H{X(1.40):.1f} V{Y(-WALL)-28:.1f}' fill='none' stroke='#2c7a2c' stroke-width='5'/>")
    b.append(text(X(1.40) + 6, Y(-WALL) - 18, "→ Water recycle", 11, color="#2c7a2c"))
    b.append(rect(X(X_C2_END) - 3, Y(0), 4, B * S, fill="#555"))
    b.append(line(X(X_PERF), Y(0), X(X_PERF), Y(B), "#555", 4, "6 4"))
    b.append(rect(X(X_WEIR), Y(0), T_WW * S, B * S))
    b.append(rect(X(X_WEIR) - 2, Y(-0.10), 5, (B + 0.2) * S, fill="#333"))
    b.append(f"<circle cx='{X(X_TAP):.1f}' cy='{Y(0.15):.1f}' r='6' fill='none' stroke='#c00' stroke-width='2'/>")
    b.append(text(X(X_TAP) + 10, Y(0.15) + 4, "จุดวัด h", 11, color="#c00"))
    b.append(rect(X(X_END), Y(B / 2) - D_OUT * S / 2, WALL * S + 40, D_OUT * S, fill="#bbb"))
    b.append(text(X(X_END + WALL) + 42, Y(B / 2) + 4, "ท่อออก 8\"", 12))
    for x in (0.15, 2.0, 2.9, 4.6, 5.6, 6.6):
        b.append(flow_arrow(X(x), Y(0.95)))
    b.append(text(X(2.6), Y(0.28), "พื้นยก +0.90 กรุกระเบื้องขาว", 12, "middle", "#1f5f8b", "bold"))
    b.append(text(X(2.6), Y(0.28) + 16, "ชั้นน้ำใส 5–7 cm", 12, "middle", "#1f5f8b"))
    ya = Y(B / 2)
    b.append(line(X(-WALL) - 20, ya, X(X_END + WALL) + 20, ya, "#c00", 1, "12 4 2 4"))
    b.append(text(X(-WALL) - 22, ya + 18, "A", 14, "end", "#c00", "bold"))
    b.append(text(X(X_END + WALL) + 22, ya + 18, "A", 14, "start", "#c00", "bold"))
    yl = Y(B + WALL) + 18
    for x, t in [(X_BAFFLE + 0.05, "ผนังกั้นลอดใต้"), (X_C2_END, "สันปลาย SS"), (X_PERF + 0.1, "แผ่นรูพรุน"), (X_WEIR, "แผ่นเวียร์")]:
        b.append(text(X(x), yl, t, 11, "middle"))
    yd = yl + 30
    for x1, x2, t in [(-WALL, X_C1_END, "ช่อง 1"), (X_C1_END, X_C2_END, "ช่อง 2"), (X_C2_END, X_END + WALL, "ช่อง 3")]:
        b.append(line(X(x1), yd, X(x2), yd, arrow=True))
        b.append(text((X(x1) + X(x2)) / 2, yd - 5, t, 12, "middle"))
    xd = X(X_END + WALL) + 25
    b.append(line(xd, Y(0), xd, Y(B), arrow=True))
    b.append(text(xd + 6, Y(0.3), f"{B:.2f}", 12))
    W, H = int(xd + 110), int(yd + 25)
    b.insert(0, text(W / 2, 30, "แปลนบ่อ 3 ช่อง (หน่วย m, ผนัง คสล. หนา 0.20)", 16, "middle", weight="bold"))
    return svg(W, H, "".join(b), "แปลนบ่อ 3 ช่อง")


# ---------------------------------------------------------------- Plate detail
def plate():
    S = 330
    half = B / 2 + 0.10              # ฝังร่องผนังข้างละ 0.10
    top = Z_NOTCH_TOP + 0.10
    X = lambda x: 110 + (x + half) * S
    Y = lambda z: 80 + (top + 0.05 - z) * S
    b = []
    w = Z_NOTCH_TOP - Z_VERTEX
    b.append(rect(X(-B / 2), Y(Z_WW), B * S, Z_WW * S))
    b.append(text(X(0), Y(Z_WW / 2 - 0.04), "กำแพงเวียร์ คสล. หนา 0.20", 12, "middle", weight="bold"))
    pts = [(-half, top), (-w, top), (-w, Z_NOTCH_TOP), (0, Z_VERTEX), (w, Z_NOTCH_TOP), (w, top), (half, top), (half, Z_PB), (-half, Z_PB)]
    b.append(poly([(X(x), Y(z)) for x, z in pts], "#cfd8dc", "#333", 1.5))
    for xb in (-0.45, -0.25, 0.25, 0.45):
        b.append(f"<circle cx='{X(xb):.1f}' cy='{Y((Z_PB + Z_WW) / 2):.1f}' r='5' fill='white' stroke='#333'/>")
    b.append(text(X(0), Y((Z_PB + Z_WW) / 2) + 4, "พุก SS", 10, "middle"))
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
    xl = X(-half) - 18
    b.append(line(xl, Y(top), xl, Y(Z_PB), arrow=True))
    b.append(text(xl - 4, Y((top + Z_PB) / 2), f"{top - Z_PB:.2f}", 12, "end"))
    b.append(text(xr + 6, Y(Z_VERTEX / 2), f"P = {Z_VERTEX:.2f}", 12))
    b.append(line(X(-w - 0.05), Y(Z_VERTEX), X(-0.01), Y(Z_VERTEX), "#3182bd", 0.8, "3 2"))
    b.append(line(X(-w - 0.03), Y(hz), X(-w - 0.03), Y(Z_VERTEX), "#3182bd", 1.2, arrow=True))
    b.append(text(X(-w - 0.05), Y((hz + Z_VERTEX) / 2) + 4, f"hmax = {hz - Z_VERTEX:.2f}", 12, "end", "#1f5f8b"))
    b.append(f"<path d='M{X(-0.06):.1f},{Y(Z_VERTEX+0.06):.1f} Q{X(0):.1f},{Y(Z_VERTEX+0.10):.1f} {X(0.06):.1f},{Y(Z_VERTEX+0.06):.1f}' fill='none' stroke='#c00'/>")
    b.append(text(X(0), Y(Z_VERTEX + 0.12), "90° ± 0.1°", 13, "middle", "#c00", "bold"))
    b.append(line(X(-B / 2), Y(-0.05), X(B / 2), Y(-0.05), arrow=True))
    b.append(text(X(0), Y(-0.05) + 16, f"B = {B:.2f} (ภายในบ่อ)", 12, "middle"))
    b.append(line(X(-half), Y(-0.14), X(half), Y(-0.14), arrow=True))
    b.append(text(X(0), Y(-0.14) + 16, f"แผ่น SS กว้าง {2*half:.2f} × สูง {top - Z_PB:.2f} (ขอบล่าง {Z_PB:+.2f})", 12, "middle"))
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
