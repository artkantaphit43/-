#!/usr/bin/env python3
"""สร้างแบบ SVG บ่อ 3 ช่อง: รูปตัดตามยาว, แปลน, รายละเอียดแผ่นเวียร์ (หน่วย m)

ช่อง 1 รับน้ำ + ปั๊มจุ่ม -> ช่อง 2 พื้นยก น้ำไหลบางโชว์ความใส -> ช่อง 3 V-notch 90° -> ท่อออก 8"
"""
import os

OUT = "drawings"
FONT = "font-family='Sarabun, Tahoma, sans-serif'"

# ---- ค่าออกแบบ (ตรงกับ weir_design.py ค่า default) ----
WALL = 0.20
B = 1.50                # ความกว้างภายใน (เกณฑ์ 1.44 + เผื่อ → b = 0.45 ≥ 2Hmax)
# ช่อง 1
X_BAFFLE = 0.50         # ผนังกั้นลอดใต้ หนา 0.10
X_C1_END = 3.25         # ช่อง 1 ยาว 3.25 (HRT 15 นาที ที่ Qavg) — ทางเลือก A
X_PUMP = 1.90           # ศก.ปั๊ม กลางโซนปั๊ม
W1 = 2.50               # ช่อง 1 กว้าง 2.50
OFF1 = (W1 - 1.50) / 2  # ช่อง 1 กว้างกว่าบ่อข้างละ
Z_F1 = -1.00            # พื้นช่อง 1
# ช่อง 2
X_C2_END = X_C1_END + 1.00  # ปลายพื้นยก + สันปลาย (ช่อง 2 ยาว 1.00)
X_C2_MID = (X_C1_END + X_C2_END) / 2
Z_RAISED = 0.90
SILL = 0.02
# ช่อง 3
T_B3 = 0.10               # ผนังลอดใต้ / สันล้น ช่อง 3 คสล. หนา 0.10
X_B3 = X_C2_END + 0.30    # ① ผิวต้นน้ำผนังลอดใต้ (รับน้ำตก 0.30)
X_S3U = X_B3 + T_B3 + 0.20  # ② ผิวต้นน้ำสันล้น (ห่าง ① 0.20)
X_PERF = X_S3U + T_B3     # ผิวท้ายน้ำสันล้น = ต้นช่วงตรง
Z_B3 = 0.20               # ขอบล่างผนังลอดใต้ (ช่องลอด 0.20)
Z_S3 = 0.30               # สันล้น
X_WEIR = X_PERF + 2.10  # ผิวเหนือน้ำของกำแพงเวียร์ (ช่วงตรง 2.10)
T_WW = 0.20             # กำแพงเวียร์ คสล.
X_TAP = X_WEIR - 0.95
X_BOD = X_PERF + 0.30      # BOD probe: ต้นช่วงตรง + 0.30, ชิดผนัง 0.15
Z_BOD = 0.30               # ปลาย probe
Z_DL = 1.10                # หน้าเซนเซอร์ DL10
X_END = X_WEIR + T_WW + 0.95  # ท้ายเวียร์ 0.95
Z_VERTEX = 0.60
Z_NOTCH_TOP = 0.90
Z_WALL_TOP = 1.20
Z_MAX = 0.810           # ช่อง 3 ที่ 100 m³/h
Z_C1 = 0.97             # ช่อง 1 ที่ 100 m³/h
Z_C2 = Z_RAISED + 0.067 # ช่อง 2 ที่ 100 m³/h
Z_GAP = Z_F1 + 0.30     # ขอบล่างผนังกั้นช่อง 1 (ช่องลอด 0.30)
Z_WW = 0.50             # สันกำแพงเวียร์ คสล.
Z_PB = 0.40             # ขอบล่างแผ่นเวียร์
Z_START = 0.80
Z_STOP = Z_F1 + 0.60    # ปั๊ม STOP
Z_DIP = Z_F1 + 0.50     # ปลายท่อจุ่ม
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
    b.append(rect(X(0), Y(Z_C1), X(X_C1_END) - X(0), Y(Z_F1) - Y(Z_C1), fill=water, stroke="none"))
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
    b.append(rect(X(-WALL), Y(Z_F1), X(X_C1_END + WALL) - X(-WALL), 0.2 * S))
    b.append(rect(X(X_C1_END), Y(0), X(X_END + WALL) - X(X_C1_END), 0.2 * S))
    b.append(rect(X(X_C1_END), Y(0), WALL * S, Y(Z_F1) - Y(0)))
    b.append(rect(X(-WALL), Y(Z_WALL_TOP), WALL * S, Y(Z_F1) - Y(Z_WALL_TOP)))
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
    b.append(line(X(X_BAFFLE + 0.13), Y(Z_GAP), X(X_BAFFLE + 0.13), Y(Z_F1), arrow=True))
    b.append(text(X(X_BAFFLE + 0.15), Y(Z_F1 + 0.10), f"{Z_GAP - Z_F1:.2f}", 10))
    b.append(text(X(-WALL) - 6, Y(Z_F1) + 4, f"พื้นช่อง 1 {Z_F1:+.2f}", 11, "end"))
    xp = X(X_PUMP)
    b.append(rect(xp - 20, Y(Z_F1 + 0.55), 40, 0.55 * S, fill="#f2a541"))
    b.append(text(xp, Y(Z_F1 + 0.28), "ปั๊ม", 11, "middle", weight="bold"))
    b.append(f"<path d='M{xp+20:.1f},{Y(Z_F1 + 0.35):.1f} H{X(X_PUMP + 0.35):.1f} V{Y(1.38):.1f} H{X(X_C1_END + 0.6):.1f}' fill='none' stroke='#2c7a2c' stroke-width='6'/>")
    b.append(text(X(X_C1_END + 0.6) + 6, Y(1.38) + 4, "→ Water recycle 10 m³/h", 12, color="#2c7a2c"))
    for z, name, c in [(Z_START, "START", "#2c7a2c"), (Z_STOP, "STOP", "#2c7a2c")]:
        b.append(line(X(X_BAFFLE + 0.12), Y(z), X(X_C1_END), Y(z), c, 1, "6 3"))
        b.append(text(X(X_BAFFLE + 0.13), Y(z) - 3, f"{name} {z:+.2f}", 10, "start", c))
    # ช่อง 3: ผนังลอดใต้ + สันล้น (แผ่น SS), tap, plate, outlet
    b.append(rect(X(X_B3), Y(Z_WALL_TOP), T_B3 * S, (Z_WALL_TOP - Z_B3) * S))
    vdim(b, Y(Z_WALL_TOP), Y(Z_B3), X(X_B3) - 10, f"{Z_WALL_TOP - Z_B3:.2f}", size=10)
    vdim(b, Y(Z_B3), Y(0), X(X_B3) - 10, f"ลอด {Z_B3:.2f}", size=10)
    vdim(b, Y(Z_S3), Y(0), X(X_S3U + T_B3) + 10, f"สัน {Z_S3:.2f}", side=1, size=10)
    b.append(text(X(X_B3 + 0.05), Y(Z_WALL_TOP) - 6, "① คสล. 0.10", 10, "middle"))
    b.append(text(X(X_S3U + 0.05), Y(Z_S3) - 6, "② คสล. 0.10", 10, "middle"))
    b.append(rect(X(X_S3U), Y(Z_S3), T_B3 * S, Z_S3 * S))
    xt = X(X_TAP)
    b.append(line(xt, Y(Z_WALL_TOP + 0.08), xt, Y(0), "#c00", 1.2, "6 3"))
    b.append(text(xt, Y(Z_WALL_TOP + 0.11), "จุดวัดระดับ h", 12, "middle", "#c00", "bold"))
    b.append(rect(xt - 30, Y(Z_WALL_TOP + 0.03), 60, 5, fill="#666"))
    b.append(rect(xt - 9, Y(Z_DL + 0.08), 18, 0.08 * S, fill="#f5f5f5", stroke="#333"))
    b.append(text(xt + 14, Y(Z_DL + 0.02), "Flow meter", 10, "start", "#333", "bold"))
    xb = X(X_BOD)
    b.append(line(xb, Y(Z_WALL_TOP + 0.15), xb, Y(Z_BOD + 0.12), "#777", 3))
    b.append(rect(xb - 6, Y(Z_BOD + 0.30), 12, 0.30 * S, fill="#e8eef2", stroke="#333"))
    b.append(text(xb + 9, Y(Z_BOD + 0.18), "BOD probe", 10, "start", "#333", "bold"))
    b.append(text(xb + 9, Y(Z_BOD + 0.18) + 12, f"ปลาย {Z_BOD:+.2f}", 9, "start", "#333"))
    b.append(rect(X(X_WEIR), Y(Z_WW), T_WW * S, Y(0) - Y(Z_WW)))
    b.append(rect(X(X_WEIR) - 3, Y(Z_NOTCH_TOP + 0.10), 5, Y(Z_PB) - Y(Z_NOTCH_TOP + 0.10), fill="#555"))
    b.append(text(X(X_WEIR) + 8, Y(Z_NOTCH_TOP + 0.14), "แผ่น V-notch SS304", 11))
    b.append(text(X(X_WEIR + T_WW) + 4, Y(Z_WW) + 14, f"กำแพงเวียร์ คสล. {Z_WW:+.2f}", 10))
    b.append(rect(X(X_END), Y(D_OUT), WALL * S + 45, D_OUT * S, fill="#bbb"))
    b.append(text(X(X_END + WALL) + 4, Y(D_OUT) - 6, "ท่อออก 8\"", 12))
    # elevations
    for z, name, c in [(Z_WALL_TOP, "สันกำแพง", "#333"), (Z_NOTCH_TOP, "ขอบบนร่อง V", "#333"),
                       (Z_MAX, "น้ำสูงสุด", "#1f5f8b"), (Z_VERTEX, "ยอด V (h = 0)", "#c00")]:
        b.append(line(X(X_PERF + 0.15), Y(z), X(X_WEIR) - 4, Y(z), c, 0.8, "3 2"))
        b.append(text(X(X_TAP) - 6, Y(z) + (11 if z == Z_MAX else -3), f"{name} {z:+.3f}", 11, "end", c))
    b.append(text(X(X_C2_MID), Y(Z_RAISED) + 18, f"ผิวพื้นยก {Z_RAISED:+.2f}", 11, "middle"))
    b.append(text(X(X_C2_MID), Y(Z_C2) - 24, "ชั้นน้ำใส 4.5–7 cm", 12, "middle", "#1f5f8b", "bold"))
    b.append(text(X(X_C2_END) - 6, Y(Z_RAISED) + 34, f"สันปลาย {SILL*100:.0f} cm", 10, "end"))
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
    yd = Y(Z_F1 - 0.2) + 30
    for x1, x2, t in [(0, X_C1_END, f"{X_C1_END:.2f}"), (X_C1_END, X_C2_END, f"{X_C2_END - X_C1_END:.2f}"),
                      (X_C2_END, X_PERF, f"{X_PERF - X_C2_END:.2f} (รับน้ำตก+ลอดใต้+สันล้น)"), (X_PERF, X_WEIR, f"{X_WEIR - X_PERF:.2f} (ช่วงตรง)"),
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
    Y = lambda y: 80 + (y + OFF1 + WALL) * S
    b = []
    b.append(rect(X(0), Y(-OFF1), X(X_C1_END) - X(0), W1 * S, fill="#deebf7", stroke="none"))
    b.append(rect(X(X_C1_END), Y(0), X(X_C2_END) - X(X_C1_END), B * S, fill="#f2fbff", stroke="#888", sw=0.6))
    b.append(rect(X(X_C2_END), Y(0), X(X_END) - X(X_C2_END), B * S, fill="#deebf7", stroke="none"))
    b.append(rect(X(X_C1_END), Y(-WALL), X(X_END + WALL) - X(X_C1_END), WALL * S))
    b.append(rect(X(X_C1_END), Y(B), X(X_END + WALL) - X(X_C1_END), WALL * S))
    b.append(rect(X(-WALL), Y(-OFF1 - WALL), (X_C1_END + 2 * WALL) * S, WALL * S))
    b.append(rect(X(-WALL), Y(B + OFF1), (X_C1_END + 2 * WALL) * S, WALL * S))
    b.append(rect(X(X_C1_END), Y(-OFF1), WALL * S, OFF1 * S))
    b.append(rect(X(X_C1_END), Y(B), WALL * S, OFF1 * S))
    b.append(rect(X(-WALL), Y(-OFF1), WALL * S, W1 * S))
    b.append(rect(X(X_END), Y(0), WALL * S, B * S))
    # items
    yi = -OFF1 + 0.30
    b.append(rect(X(-WALL) - 40, Y(yi) - D_IN * S / 2, 40 + (WALL + 0.20) * S, D_IN * S, fill="#bbb"))
    b.append(f"<circle cx='{X(0.20) - D_IN*S/2:.1f}' cy='{Y(yi):.1f}' r='{D_IN*S/2:.1f}' fill='#bbb' stroke='#333'/>")
    b.append(text(X(-WALL) - 42, Y(yi) - 14, "ท่อน้ำเข้า 6\"", 12))
    b.append(rect(X(X_BAFFLE), Y(-OFF1), 0.10 * S, W1 * S))
    b.append(f"<circle cx='{X(X_PUMP):.1f}' cy='{Y(B/2):.1f}' r='{0.16*S:.1f}' fill='#f2a541' stroke='#333'/>")
    b.append(text(X(X_PUMP), Y(B/2) + 5, "P", 14, "middle", weight="bold"))
    b.append(f"<path d='M{X(X_PUMP)+0.16*S:.1f},{Y(B/2):.1f} H{X(X_PUMP + 0.5):.1f} V{Y(-OFF1-WALL)-28:.1f}' fill='none' stroke='#2c7a2c' stroke-width='5'/>")
    b.append(text(X(X_PUMP + 0.5) + 6, Y(-OFF1-WALL) - 18, "→ Water recycle", 11, color="#2c7a2c"))
    b.append(rect(X(X_C2_END) - 3, Y(0), 4, B * S, fill="#555"))
    b.append(rect(X(X_WEIR), Y(0), T_WW * S, B * S))
    b.append(rect(X(X_B3), Y(0), T_B3 * S, B * S))
    b.append(rect(X(X_S3U), Y(0), T_B3 * S, B * S))
    b.append(rect(X(X_WEIR) - 2, Y(-0.10), 5, (B + 0.2) * S, fill="#333"))
    b.append(f"<circle cx='{X(X_TAP):.1f}' cy='{Y(0.15):.1f}' r='6' fill='none' stroke='#c00' stroke-width='2'/>")
    b.append(text(X(X_TAP) + 10, Y(0.15) + 4, "จุดวัด h + Flow meter", 11, color="#c00"))
    b.append(f"<circle cx='{X(X_BOD):.1f}' cy='{Y(0.15):.1f}' r='7' fill='#e8eef2' stroke='#333' stroke-width='1.5'/>")
    b.append(text(X(X_BOD) + 10, Y(0.15) + 4, "BOD probe", 11))
    b.append(rect(X(X_END), Y(B / 2) - D_OUT * S / 2, WALL * S + 40, D_OUT * S, fill="#bbb"))
    b.append(text(X(X_END + WALL) + 42, Y(B / 2) + 4, "ท่อออก 8\"", 12))
    for x in (0.15, X_C2_MID - 0.15, X_PERF + 0.5, X_PERF + 1.4, X_WEIR + 0.4):
        b.append(flow_arrow(X(x), Y(0.95)))
    b.append(text(X(X_C2_MID), Y(0.28), "พื้นยก +0.90 กรุกระเบื้องขาว", 12, "middle", "#1f5f8b", "bold"))
    b.append(text(X(X_C2_MID), Y(0.28) + 16, "ชั้นน้ำใส 4.5–7 cm", 12, "middle", "#1f5f8b"))
    ya = Y(B / 2)
    b.append(line(X(-WALL) - 20, ya, X(X_END + WALL) + 20, ya, "#c00", 1, "12 4 2 4"))
    b.append(text(X(-WALL) - 22, ya + 18, "A", 14, "end", "#c00", "bold"))
    b.append(text(X(X_END + WALL) + 22, ya + 18, "A", 14, "start", "#c00", "bold"))
    yl = Y(B + OFF1 + WALL) + 18
    for x, t in [(X_BAFFLE + 0.05, "ผนังกั้นลอดใต้"), (X_C2_END, "สันปลาย SS"), (X_WEIR, "แผ่นเวียร์")]:
        b.append(text(X(x), yl, t, 11, "middle"))
    yd = yl + 30
    for x1, x2, t in [(-WALL, X_C1_END, "ช่อง 1"), (X_C1_END, X_C2_END, "ช่อง 2"), (X_C2_END, X_END + WALL, "ช่อง 3")]:
        b.append(line(X(x1), yd, X(x2), yd, arrow=True))
        b.append(text((X(x1) + X(x2)) / 2, yd - 5, t, 12, "middle"))
    xd = X(X_END + WALL) + 25
    b.append(line(xd, Y(0), xd, Y(B), arrow=True))
    b.append(text(xd + 6, Y(0.3), f"{B:.2f}", 12))
    xl1 = X(-WALL) - 60
    b.append(line(xl1, Y(-OFF1), xl1, Y(B + OFF1), arrow=True))
    b.append(text(xl1 - 4, Y(B + OFF1) + 16, f"ช่อง 1 กว้าง {W1:.2f}", 11, "middle"))
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


# ---------------------------------------------------------------- Dimension sheet
TS = 0.20                # พื้น คสล.


def hdim(b, x1, x2, y, label, ext=None, size=11):
    """มิติแนวนอน: เส้นมิติที่ y, เส้นต่อจาก ext (ถ้ามี), ขีดเฉียงที่ปลาย"""
    if ext is not None:
        for x in (x1, x2):
            b.append(line(x, ext, x, y + (4 if y > ext else -4), "#888", 0.6))
    b.append(line(x1, y, x2, y, "#333", 0.8))
    for x in (x1, x2):
        b.append(line(x - 4, y + 4, x + 4, y - 4, "#333", 1.2))
    b.append(text((x1 + x2) / 2, y - 4, label, size, "middle"))


def vdim(b, y1, y2, x, label, ext=None, size=11, side=-1):
    """มิติแนวตั้ง: เส้นมิติที่ x, ตัวเลขหมุน 90° ด้าน side (-1 ซ้าย, 1 ขวา)"""
    if ext is not None:
        for y in (y1, y2):
            b.append(line(ext, y, x + (4 if x > ext else -4), y, "#888", 0.6))
    b.append(line(x, y1, x, y2, "#333", 0.8))
    for y in (y1, y2):
        b.append(line(x - 4, y + 4, x + 4, y - 4, "#333", 1.2))
    tx, ty = x + side * 5, (y1 + y2) / 2
    b.append(f"<text x='{tx:.1f}' y='{ty:.1f}' font-size='{size}' text-anchor='middle' fill='#222' "
             f"transform='rotate(-90 {tx:.1f} {ty:.1f})'>{label}</text>")


def dimensions():
    S = 112
    b = []
    xs = [-WALL, 0, X_BAFFLE, X_BAFFLE + 0.10, X_C1_END, X_C2_END, X_B3, X_B3 + T_B3, X_S3U, X_PERF, X_WEIR, X_WEIR + T_WW, X_END, X_END + WALL]
    W = int(150 + (X_END + 2 * WALL) * S + 260)

    # ===================== แปลน =====================
    X = lambda x: 150 + (x + WALL) * S
    Y = lambda y: 260 + (y + WALL) * S
    b.append(text(X(-WALL) - 110, 140, "แปลน", 15, "start", weight="bold"))
    b.append(rect(X(0), Y(-OFF1), X_C1_END * S, W1 * S, fill="#eef6fc", stroke="none"))
    b.append(rect(X(X_C1_END), Y(0), (X_END - X_C1_END) * S, B * S, fill="#eef6fc", stroke="none"))
    b.append(rect(X(X_C1_END), Y(0), (X_C2_END - X_C1_END) * S, B * S, fill="#ffffff", stroke="#999", sw=0.6))
    b.append(rect(X(X_C1_END), Y(-WALL), (X_END + WALL - X_C1_END) * S, WALL * S))
    b.append(rect(X(X_C1_END), Y(B), (X_END + WALL - X_C1_END) * S, WALL * S))
    b.append(rect(X(-WALL), Y(-OFF1 - WALL), (X_C1_END + 2 * WALL) * S, WALL * S))
    b.append(rect(X(-WALL), Y(B + OFF1), (X_C1_END + 2 * WALL) * S, WALL * S))
    b.append(rect(X(X_C1_END), Y(-OFF1), WALL * S, OFF1 * S))
    b.append(rect(X(X_C1_END), Y(B), WALL * S, OFF1 * S))
    b.append(rect(X(-WALL), Y(-OFF1), WALL * S, W1 * S))
    b.append(rect(X(X_END), Y(0), WALL * S, B * S))
    b.append(rect(X(X_BAFFLE), Y(-OFF1), 0.10 * S, W1 * S))
    b.append(rect(X(X_WEIR), Y(0), T_WW * S, B * S))
    b.append(rect(X(X_B3), Y(0), T_B3 * S, B * S))
    b.append(rect(X(X_S3U), Y(0), T_B3 * S, B * S))
    b.append(rect(X(X_WEIR) - 2, Y(-0.10), 4, (B + 0.2) * S, fill="#333"))
    b.append(rect(X(X_C2_END) - 2, Y(0), 3, B * S, fill="#555"))
    b.append(f"<circle cx='{X(0.20):.1f}' cy='{Y(-OFF1 + 0.30):.1f}' r='{0.084*S:.1f}' fill='#bbb' stroke='#333'/>")
    b.append(rect(X(-WALL) - 30, Y(-OFF1 + 0.30) - 0.084 * S, 30 + (WALL + 0.20) * S, 0.168 * S, fill="#bbb"))
    b.append(f"<circle cx='{X(X_PUMP):.1f}' cy='{Y(B/2):.1f}' r='{0.20*S:.1f}' fill='#f2a541' stroke='#333'/>")
    b.append(text(X(X_PUMP), Y(B / 2) + 4, "P", 12, "middle", weight="bold"))
    b.append(rect(X(X_END), Y(B / 2) - 0.11 * S, WALL * S + 30, 0.22 * S, fill="#bbb"))
    b.append(f"<circle cx='{X(X_TAP):.1f}' cy='{Y(-WALL/2):.1f}' r='6' fill='white' stroke='#c00' stroke-width='2'/>")
    b.append(rect(X(X_TAP) - 6, Y(0.10) - 6, 12, 12, fill="#f5f5f5", stroke="#333"))
    b.append(text(X(X_TAP) + 9, Y(0.10) + 4, "Flow", 9))
    b.append(f"<circle cx='{X(X_BOD):.1f}' cy='{Y(0.15):.1f}' r='6' fill='#e8eef2' stroke='#333' stroke-width='1.5'/>")
    b.append(text(X(X_BOD) + 9, Y(0.15) + 4, "BOD", 9))
    for x1, x2, t in [(0, X_C1_END, "ช่อง 1"), (X_C1_END, X_C2_END, "ช่อง 2 (พื้นยก)"), (X_C2_END, X_END, "ช่อง 3")]:
        b.append(text((X(x1) + X(x2)) / 2, Y(B) - 8, t, 11, "middle", "#1f5f8b", "bold"))
    # chain dims ด้านบน
    yt = Y(-OFF1 - WALL)
    for i in range(len(xs) - 1):
        hdim(b, X(xs[i]), X(xs[i + 1]), yt - 18, f"{xs[i+1]-xs[i]:.2f}", ext=yt, size=10)
    for x1, x2, t in [(-WALL, X_C1_END, f"{X_C1_END + WALL:.2f}"), (X_C1_END, X_C2_END, f"{X_C2_END - X_C1_END:.2f}"), (X_C2_END, X_END + WALL, f"{X_END + WALL - X_C2_END:.2f}")]:
        hdim(b, X(x1), X(x2), yt - 42, t, ext=yt - 18)
    hdim(b, X(-WALL), X(X_END + WALL), yt - 66, f"ยาวภายนอก {X_END + 2*WALL:.2f}", ext=yt - 42, size=12)
    # ด้านล่าง: ภายใน + ตำแหน่งท่อ/ปั๊ม/จุดวัด
    yb = Y(B + OFF1 + WALL)
    hdim(b, X(0), X(X_END), yb + 22, f"ยาวภายใน {X_END:.2f}", ext=yb, size=12)
    hdim(b, X(0), X(X_PUMP), yb + 46, f"ศก.ปั๊ม {X_PUMP:.2f}", ext=yb + 22, size=10)
    hdim(b, X(X_TAP), X(X_WEIR), yb + 46, f"จุดวัด H {X_WEIR - X_TAP:.2f}", ext=yb + 22, size=10)
    hdim(b, X(X_PERF), X(X_BOD), yb + 46, f"BOD {X_BOD - X_PERF:.2f}", ext=yb + 22, size=10)
    # ด้านข้าง
    xr = X(X_END + WALL) + 50
    for y1, y2, t in [(-WALL, 0, "0.20"), (0, B, f"{B:.2f}"), (B, B + WALL, "0.20")]:
        vdim(b, Y(y1), Y(y2), xr, t, ext=X(X_END + WALL), side=1 if t != "0.20" else 1, size=10)
    vdim(b, Y(-WALL), Y(B + WALL), xr + 34, f"{B + 2*WALL:.2f}", ext=xr, side=1)
    xl = X(-WALL) - 30
    vdim(b, Y(-OFF1), Y(-OFF1 + 0.30), xl, "0.30", ext=X(0.20), size=9)
    b.append(text(X(-WALL) - 32, Y(-OFF1 + 0.30) + 22, "ท่อเข้า 6\"", 10, "start"))
    for y1, y2, t in [(-OFF1 - WALL, -OFF1, "0.20"), (-OFF1, 0, f"{OFF1:.2f}"), (0, B, f"{B:.2f}"), (B, B + OFF1, f"{OFF1:.2f}"), (B + OFF1, B + OFF1 + WALL, "0.20")]:
        vdim(b, Y(y1), Y(y2), xl - 28, t, ext=X(-WALL), size=9)
    vdim(b, Y(-OFF1), Y(B + OFF1), xl - 56, f"ช่อง 1 ภายใน {W1:.2f}", ext=xl - 28, size=10)
    vdim(b, Y(-OFF1 - WALL), Y(B + OFF1 + WALL), xl - 84, f"ภายนอก {W1 + 2*WALL:.2f}", ext=xl - 56, size=10)
    b.append(text(X(X_END + WALL) + 34, Y(B / 2) - 12, "ท่อออก 8\"", 10))
    b.append(line(X(-WALL) - 20, Y(B / 2), X(X_END + WALL) + 20, Y(B / 2), "#c00", 0.8, "10 3 2 3"))
    b.append(text(X(-WALL) - 22, Y(B / 2) + 16, "A", 13, "end", "#c00", "bold"))
    b.append(text(X(X_END + WALL) + 22, Y(B / 2) + 16, "A", 13, "start", "#c00", "bold"))
    b.append(line(X(X_WEIR) - 14, Y(-WALL) - 8, X(X_WEIR) - 14, Y(B + WALL) + 8, "#c00", 0.8, "10 3 2 3"))
    b.append(text(X(X_WEIR) - 14, Y(B + OFF1 + WALL) + 74, "B", 13, "middle", "#c00", "bold"))

    # ===================== รูปตัด A-A =====================
    top = Y(B + OFF1 + WALL) + 140
    Z = lambda z: top + (Z_WALL_TOP + 0.05 - z) * S
    b.append(text(X(-WALL), top - 6, "รูปตัด A–A", 15, "start", weight="bold"))
    b.append(rect(X(0), Z(Z_C1), X_C1_END * S, Z(Z_F1) - Z(Z_C1), fill="#cfe5f3", stroke="none"))
    b.append(rect(X(X_C1_END), Z(Z_C2), (X_C2_END - X_C1_END) * S, Z(Z_RAISED) - Z(Z_C2), fill="#cfe5f3", stroke="none"))
    b.append(rect(X(X_C2_END), Z(Z_MAX), (X_WEIR - X_C2_END) * S, Z(0) - Z(Z_MAX), fill="#cfe5f3", stroke="none"))
    b.append(rect(X(X_WEIR + T_WW), Z(Z_TAIL), (X_END - X_WEIR - T_WW) * S, Z(0) - Z(Z_TAIL), fill="#cfe5f3", stroke="none"))
    b.append(rect(X(-WALL), Z(Z_F1), (X_C1_END + 2 * WALL) * S, TS * S))
    b.append(rect(X(X_C1_END), Z(0), (X_END + WALL - X_C1_END) * S, TS * S))
    b.append(rect(X(X_C1_END), Z(0), WALL * S, (0 - Z_F1) * S))
    b.append(rect(X(-WALL), Z(Z_WALL_TOP), WALL * S, (Z_WALL_TOP - Z_F1) * S))
    b.append(rect(X(X_END), Z(Z_WALL_TOP), WALL * S, Z_WALL_TOP * S))
    b.append(rect(X(X_BAFFLE), Z(Z_WALL_TOP), 0.10 * S, (Z_WALL_TOP - Z_GAP) * S))
    b.append(rect(X(X_C1_END), Z(Z_RAISED), (X_C2_END - X_C1_END) * S, Z_RAISED * S))
    b.append(rect(X(X_C2_END) - 2, Z(Z_RAISED + SILL), 3, SILL * S, fill="#555"))
    b.append(rect(X(X_WEIR), Z(Z_WW), T_WW * S, Z_WW * S))
    b.append(rect(X(X_B3), Z(Z_WALL_TOP), T_B3 * S, (Z_WALL_TOP - Z_B3) * S))
    vdim(b, Z(Z_WALL_TOP), Z(Z_B3), X(X_B3) - 10, f"{Z_WALL_TOP - Z_B3:.2f}", size=9)
    vdim(b, Z(Z_B3), Z(0), X(X_B3) - 10, f"ลอด {Z_B3:.2f}", size=9)
    vdim(b, Z(Z_S3), Z(0), X(X_S3U + T_B3) + 10, f"สัน {Z_S3:.2f}", side=1, size=9)
    b.append(rect(X(X_S3U), Z(Z_S3), T_B3 * S, Z_S3 * S))
    b.append(rect(X(X_WEIR) - 3, Z(Z_NOTCH_TOP + 0.10), 4, (Z_NOTCH_TOP + 0.10 - Z_PB) * S, fill="#333"))
    b.append(rect(X(-WALL) - 30, Z(1.10), 30 + (WALL + 0.20) * S, 0.168 * S, fill="#bbb"))
    b.append(rect(X(0.20) - 0.168 * S, Z(1.10), 0.168 * S, (1.10 - Z_DIP) * S, fill="#bbb"))
    b.append(rect(X(X_PUMP) - 0.20 * S, Z(Z_F1 + 0.55), 0.40 * S, 0.55 * S, fill="#f2a541"))
    b.append(rect(X(X_END), Z(D_OUT), WALL * S + 30, D_OUT * S, fill="#bbb"))
    b.append(rect(X(X_TAP) - 24, Z(Z_WALL_TOP + 0.03), 48, 4, fill="#666"))
    b.append(rect(X(X_TAP) - 7, Z(Z_DL + 0.07), 14, 0.07 * S, fill="#f5f5f5", stroke="#333"))
    b.append(line(X(X_TAP), Z(Z_DL), X(X_TAP), Z(Z_VERTEX), "#c00", 0.8, "3 3"))
    b.append(line(X(X_BOD), Z(Z_WALL_TOP + 0.12), X(X_BOD), Z(Z_BOD + 0.12), "#777", 2.5))
    b.append(rect(X(X_BOD) - 5, Z(Z_BOD + 0.30), 10, 0.30 * S, fill="#e8eef2", stroke="#333"))
    b.append(text(X(X_BOD) + 8, Z(Z_BOD + 0.20), "BOD", 10, "start", "#333", "bold"))
    b.append(text(X(X_TAP) + 10, Z(Z_DL + 0.02), "Flow meter", 10, "start", "#333", "bold"))
    # ระดับ (ด้านขวา)
    xe = X(X_END + WALL) + 40
    levels = [(Z_WALL_TOP, "สันกำแพง"), (Z_DL, "หน้าเซนเซอร์ Flow meter"), (Z_BOD, "ปลาย BOD probe"), (Z_C1, "น้ำช่อง 1 (100 m³/h)"), (Z_RAISED + SILL, "สันปลายช่อง 2"),
              (Z_RAISED, "ผิวพื้นยก"), (Z_NOTCH_TOP + 0.10, "ขอบบนแผ่นเวียร์"), (Z_NOTCH_TOP, "ขอบบนร่อง V"),
              (Z_MAX, "น้ำช่อง 3 (100 m³/h)"), (Z_START, "ปั๊ม START"), (Z_VERTEX, "ยอด V"), (Z_WW, "สันกำแพงเวียร์"),
              (Z_PB, "ขอบล่างแผ่นเวียร์"), (Z_S3, "สันล้นช่อง 3"), (Z_B3, "ขอบล่างผนังลอดใต้ช่อง 3"), (Z_TAIL, "น้ำท้ายเวียร์"),
              (0.0, "ผิวพื้นช่อง 2–3"), (Z_STOP, "ปั๊ม STOP"), (Z_DIP, "ปลายท่อจุ่ม"), (Z_GAP, "ขอบล่างผนังกั้นช่อง 1"),
              (Z_F1, "ผิวพื้นช่อง 1"), (Z_F1 - TS, "ใต้พื้นช่อง 1")]
    ly = Z(Z_WALL_TOP)
    for z, name in sorted(levels, key=lambda t: -t[0]):
        yy = max(Z(z), ly)
        b.append(f"<path d='M{X(X_END + WALL) + 4:.1f},{Z(z):.1f} H{xe - 12:.1f} L{xe - 4:.1f},{yy:.1f}' fill='none' stroke='#999' stroke-width='0.6'/>")
        b.append(f"<polygon points='{xe-4:.1f},{yy:.1f} {xe-10:.1f},{yy-5:.1f} {xe+2:.1f},{yy-5:.1f}' fill='#333'/>")
        b.append(text(xe + 6, yy + 4, f"{z:+.3f}  {name}", 10, "start", "#c00" if z == Z_VERTEX else "#222"))
        ly = yy + 13
    # มิติแนวตั้ง
    vdim(b, Z(Z_WALL_TOP), Z(Z_F1), X(-WALL) - 22, f"{Z_WALL_TOP - Z_F1:.2f}", ext=X(-WALL))
    vdim(b, Z(Z_F1), Z(Z_F1 - TS), X(-WALL) - 22, "0.20", ext=X(-WALL), size=10)
    vdim(b, Z(Z_WALL_TOP), Z(Z_F1 - TS), X(-WALL) - 48, f"ช่อง 1 สูงภายนอก {Z_WALL_TOP - Z_F1 + TS:.2f}", ext=X(-WALL) - 22)
    vdim(b, Z(Z_GAP), Z(Z_F1), X(X_BAFFLE + 0.10) + 14, f"{Z_GAP - Z_F1:.2f}", side=1, size=10)
    vdim(b, Z(Z_C1), Z(Z_F1), X(X_PUMP) + 40, f"น้ำลึก {Z_C1 - Z_F1:.2f}", side=1, size=10)
    vdim(b, Z(0), Z(Z_F1), X(X_C1_END) - 12, f"{-Z_F1:.2f}", size=10)
    vdim(b, Z(Z_RAISED), Z(0), X(X_C2_MID), f"{Z_RAISED:.2f}", side=1)
    vdim(b, Z(Z_VERTEX), Z(0), X(X_WEIR) - 22, f"P {Z_VERTEX:.2f}")
    vdim(b, Z(Z_WW), Z(0), X(X_WEIR + T_WW) + 16, f"{Z_WW:.2f}", side=1, size=10)
    vdim(b, Z(Z_NOTCH_TOP + 0.10), Z(Z_PB), X(X_WEIR + T_WW) + 16, f"แผ่น {Z_NOTCH_TOP + 0.10 - Z_PB:.2f}", side=1, size=10)
    # มิติแนวนอน
    yb2 = Z(Z_F1 - TS)
    for i in range(len(xs) - 1):
        hdim(b, X(xs[i]), X(xs[i + 1]), yb2 + 20, f"{xs[i+1]-xs[i]:.2f}", ext=yb2, size=10)
    b.append(text(X(1.0), Z(0.70), "ช่อง 1", 11, "middle", "#1f5f8b", "bold"))
    b.append(text(X(X_C2_MID), Z(1.10), "ช่อง 2", 11, "middle", "#1f5f8b", "bold"))
    b.append(text(X(X_PERF + 0.65), Z(1.10), "ช่อง 3", 11, "middle", "#1f5f8b", "bold"))

    # ===================== รูปตัด B-B (ที่เวียร์ มองตามน้ำ) =====================
    top3 = yb2 + 120
    S3 = 150
    half = B / 2 + WALL
    Xc = lambda x: 190 + (x + half) * S3
    Z3 = lambda z: top3 + 30 + (Z_WALL_TOP + 0.05 - z) * S3
    b.append(text(Xc(-half) - 110, top3 - 20, "รูปตัด B–B ที่แผ่นเวียร์ (มองตามทิศน้ำ)", 15, "start", weight="bold"))
    b.append(rect(Xc(-half), Z3(0), (2 * half) * S3, TS * S3))
    for xw in (-half, B / 2):
        b.append(rect(Xc(xw), Z3(Z_WALL_TOP), WALL * S3, Z_WALL_TOP * S3))
    b.append(rect(Xc(-B / 2), Z3(Z_WW), B * S3, Z_WW * S3))
    w = Z_NOTCH_TOP - Z_VERTEX
    pt = Z_NOTCH_TOP + 0.10
    hp = B / 2 + 0.10
    pts = [(-hp, pt), (-w, pt), (-w, Z_NOTCH_TOP), (0, Z_VERTEX), (w, Z_NOTCH_TOP), (w, pt), (hp, pt), (hp, Z_PB), (-hp, Z_PB)]
    b.append(poly([(Xc(x), Z3(z)) for x, z in pts], "#cfd8dc", "#333", 1.2, 0.95))
    for xb in (-0.42, -0.21, 0.21, 0.42):
        b.append(f"<circle cx='{Xc(xb):.1f}' cy='{Z3(0.45):.1f}' r='4' fill='white' stroke='#333'/>")
    b.append(poly([(Xc(-(Z_MAX - Z_VERTEX)), Z3(Z_MAX)), (Xc(0), Z3(Z_VERTEX)), (Xc(Z_MAX - Z_VERTEX), Z3(Z_MAX))], "#9ecae1", "#3182bd", 1, 0.9))
    # มิติ B-B
    yb3 = Z3(-TS)
    hdim(b, Xc(-half), Xc(-B / 2), yb3 + 20, "0.20", ext=yb3, size=10)
    hdim(b, Xc(-B / 2), Xc(B / 2), yb3 + 20, f"B = {B:.2f}", ext=yb3)
    hdim(b, Xc(B / 2), Xc(half), yb3 + 20, "0.20", ext=yb3, size=10)
    hdim(b, Xc(-half), Xc(half), yb3 + 44, f"กว้างภายนอก {2*half:.2f}", ext=yb3 + 20)
    yt3 = Z3(Z_WALL_TOP)
    hdim(b, Xc(-hp), Xc(-B / 2), yt3 - 14, "0.10", ext=Z3(pt), size=9)
    hdim(b, Xc(-w), Xc(w), yt3 - 14, f"ปากร่อง {2*w:.2f}", ext=Z3(pt))
    hdim(b, Xc(B / 2), Xc(hp), yt3 - 14, "0.10", ext=Z3(pt), size=9)
    hdim(b, Xc(-hp), Xc(hp), yt3 - 36, f"แผ่น SS {2*hp:.2f}", ext=yt3 - 14)
    yb_b = Z3(Z_NOTCH_TOP + 0.05)
    hdim(b, Xc(-B / 2), Xc(-w), yb_b, f"b {(B/2 - w):.3f} ≥ 2H", size=10)
    hdim(b, Xc(w), Xc(B / 2), yb_b, f"b {(B/2 - w):.3f}", size=10)
    xr3 = Xc(half) + 30
    vdim(b, Z3(pt), Z3(Z_NOTCH_TOP), xr3, "0.10", ext=Xc(hp), side=1, size=9)
    vdim(b, Z3(Z_NOTCH_TOP), Z3(Z_VERTEX), xr3, f"{w:.2f}", ext=Xc(w), side=1, size=10)
    vdim(b, Z3(Z_VERTEX), Z3(Z_WW), xr3, f"{Z_VERTEX - Z_WW:.2f}", ext=Xc(0), side=1, size=10)
    vdim(b, Z3(Z_WW), Z3(0), xr3, f"{Z_WW:.2f}", ext=Xc(B / 2), side=1, size=10)
    vdim(b, Z3(Z_VERTEX), Z3(0), xr3 + 30, f"P = {Z_VERTEX:.2f}", ext=xr3, side=1)
    vdim(b, Z3(pt), Z3(Z_PB), Xc(-half) - 22, f"แผ่น {pt - Z_PB:.2f}", ext=Xc(-hp))
    vdim(b, Z3(Z_PB), Z3(Z_WW), Xc(-half) - 22, "0.10", ext=Xc(-hp), size=9)
    b.append(text(Xc(0), Z3(0.22), "กำแพงเวียร์ คสล. หนา 0.20", 11, "middle", weight="bold"))
    b.append(text(Xc(0), Z3(0.45) + 16, "พุก SS ยึดแผ่นทับกำแพง", 9, "middle"))
    b.append(text(Xc(-(Z_MAX - Z_VERTEX)) - 4, Z3(Z_MAX) - 4, f"น้ำสูงสุด H = {Z_MAX - Z_VERTEX:.2f}", 10, "end", "#1f5f8b"))

    # ===================== ตารางสรุป =====================
    tx, ty = Xc(half) + 160, top3 + 10
    rows = [("รายการ", "ขนาด (m)"),
            ("ขนาดภายใน (ยาว × กว้าง × สูง)", f"{X_END:.2f} × {B:.2f} × {Z_WALL_TOP:.2f}  (ช่อง 1: {W1:.2f} × {Z_WALL_TOP - Z_F1:.2f})"),
            ("ขนาดภายนอก (ยาว × กว้างช่อง 1 / ช่อง 2–3)", f"{X_END + 2*WALL:.2f} × {W1 + 2*WALL:.2f} / {B + 2*WALL:.2f}"),
            ("ผนัง / พื้น คสล.", "0.20 / 0.20"),
            ("ช่อง 1 (โซนน้ำเข้า + ผนังกั้น + โซนปั๊ม)", f"0.50 + 0.10 + {X_C1_END - 0.60:.2f} = {X_C1_END:.2f}"),
            ("ช่อง 1 กว้าง × น้ำลึก (พื้น −1.00)", f"{W1:.2f} × {Z_C1 - Z_F1:.2f}  →  HRT 15 นาที"),
            ("ช่อง 2 พื้นยก (ยาว × สูง)", f"{X_C2_END - X_C1_END:.2f} × {Z_RAISED:.2f}"),
            ("ช่อง 3 (รับน้ำตก + ผนังลอดใต้ + ห่าง + สันล้น + ช่วงตรง + กำแพง + ท้าย)", f"0.30 + 0.10 + 0.20 + 0.10 + 2.10 + 0.20 + 0.95 = {X_END - X_C2_END:.2f}"),
            ("กำแพงเวียร์ คสล. (หนา × สูง)", f"0.20 × {Z_WW:.2f}"),
            ("แผ่นเวียร์ SS304 (กว้าง × สูง × หนา)", f"{2*hp:.2f} × {pt - Z_PB:.2f} × 0.006"),
            ("ร่อง V 90° (ลึก × ปาก)", f"{w:.2f} × {2*w:.2f}"),
            ("ช่องลอดใต้ผนังกั้นช่อง 1 / ช่อง 3", f"{Z_GAP - Z_F1:.2f} / {Z_B3:.2f}"),
            ("สันปลายช่อง 2 (SS)", f"{SILL:.2f}")]
    cw = (330, 270)
    for i, (a, c) in enumerate(rows):
        yy = ty + i * 22
        fill = "#1f4e78" if i == 0 else ("#f2f2f2" if i % 2 else "#ffffff")
        col = "#fff" if i == 0 else "#222"
        b.append(rect(tx, yy, cw[0], 22, fill=fill, stroke="#bbb", sw=0.6))
        b.append(rect(tx + cw[0], yy, cw[1], 22, fill=fill, stroke="#bbb", sw=0.6))
        b.append(text(tx + 6, yy + 15, a, 11, "start", col, "bold" if i == 0 else "normal"))
        b.append(text(tx + cw[0] + cw[1] / 2, yy + 15, c, 11, "middle", col, "bold"))
    b.append(text(tx, ty + len(rows) * 22 + 20, "ระดับวัดจากผิวพื้นในบ่อ (±0.000) / หน่วย m", 10, "start", "#555"))
    b.append(text(tx, ty + len(rows) * 22 + 36, "แผ่นเวียร์ติดด้านเหนือน้ำของกำแพงเวียร์", 10, "start", "#555"))

    W = max(W, int(tx + cw[0] + cw[1] + 30))
    H = int(max(Z3(-TS) + 80, ty + len(rows) * 22 + 60))
    b.insert(0, text(W / 2, 40, "แบบแสดงขนาด (Dimension) — บ่อ 3 ช่อง: ปั๊มจุ่ม | โชว์น้ำใส | V-notch 90°", 18, "middle", weight="bold"))
    return svg(W, H, "".join(b), "แบบแสดงขนาดบ่อ 3 ช่อง")


# ---------------------------------------------------------------- Sensor detail (ช่อง 3)
def sensors():
    S = 190
    x0, x1e = X_C2_END - 0.35, X_END + WALL + 0.05
    X = lambda x: 110 + (x - x0) * S
    W_ = int(X(x1e) + 230)
    b = []
    # ---------- แปลน ----------
    Y = lambda y: 120 + (y + WALL) * S
    b.append(text(X(x0), 100, "แปลนช่อง 3", 15, "start", weight="bold"))
    b.append(rect(X(X_C2_END), Y(0), (X_END - X_C2_END) * S, B * S, fill="#eef6fc", stroke="none"))
    b.append(rect(X(x0), Y(0), (X_C2_END - x0) * S, B * S, fill="#ffffff", stroke="#999", sw=0.6))
    b.append(rect(X(x0), Y(-WALL), (X_END + WALL - x0) * S, WALL * S))
    b.append(rect(X(x0), Y(B), (X_END + WALL - x0) * S, WALL * S))
    b.append(rect(X(X_END), Y(0), WALL * S, B * S))
    b.append(rect(X(X_WEIR), Y(0), T_WW * S, B * S))
    b.append(rect(X(X_B3), Y(0), T_B3 * S, B * S))
    b.append(rect(X(X_S3U), Y(0), T_B3 * S, B * S))
    b.append(text(X(X_B3) - 4, Y(B) - 8, '① ผนังลอดใต้ คสล.', 10, 'end', '#333'))
    b.append(text(X(X_PERF) + 6, Y(B) - 8, '② สันล้น คสล.', 10, 'start', '#333'))
    b.append(rect(X(X_WEIR) - 2, Y(-0.10), 4, (B + 0.2) * S, fill="#333"))
    b.append(rect(X(X_C2_END) - 2, Y(0), 3, B * S, fill="#555"))
    b.append(text(X(x0) + 8, Y(B / 2) + 4, "ช่อง 2", 11, "start", "#1f5f8b", "bold"))
    # คาน Flow meter + หัววัด
    b.append(rect(X(X_TAP) - 5, Y(-WALL), 10, (B + 2 * WALL) * S, fill="#9aa4ab", stroke="#555", sw=0.8))
    b.append(rect(X(X_TAP) - 11, Y(B / 2) - 11, 22, 22, fill="#ffffff", stroke="#c00", sw=2))
    b.append(text(X(X_TAP) + 16, Y(B / 2) + 4, "Flow meter", 12, "start", "#c00", "bold"))
    b.append(text(X(X_TAP) + 16, Y(B / 2) + 18, "(กลางบ่อ บนคานพาดขวาง)", 10, "start", "#555"))
    # BOD
    b.append(f"<circle cx='{X(X_BOD):.1f}' cy='{Y(0.15):.1f}' r='10' fill='#e8eef2' stroke='#333' stroke-width='2'/>")
    b.append(text(X(X_BOD) + 15, Y(0.15) + 4, "BOD probe", 12, "start", "#222", "bold"))
    # มิติแปลน
    yb = Y(B + WALL)
    hdim(b, X(X_C2_END), X(X_BOD), yb + 24, f"{X_BOD - X_C2_END:.2f}", ext=yb)
    hdim(b, X(X_BOD), X(X_TAP), yb + 24, f"{X_TAP - X_BOD:.2f}", ext=yb)
    hdim(b, X(X_TAP), X(X_WEIR), yb + 24, f"{X_WEIR - X_TAP:.2f}", ext=yb)
    hdim(b, X(X_C2_END), X(X_TAP), yb + 50, f"{X_TAP - X_C2_END:.2f}", ext=yb + 24)
    hdim(b, X(X_BOD), X(X_WEIR), yb + 76, f"{X_WEIR - X_BOD:.2f}", ext=yb + 50)
    hdim(b, X(X_C2_END), X(X_B3), yb + 102, f"{X_B3 - X_C2_END:.2f}", ext=yb + 76, size=10)
    hdim(b, X(X_B3), X(X_B3 + T_B3), yb + 102, "①0.10", ext=yb + 76, size=9)
    hdim(b, X(X_B3 + T_B3), X(X_S3U), yb + 102, f"{X_S3U - X_B3 - T_B3:.2f}", ext=yb + 76, size=10)
    hdim(b, X(X_S3U), X(X_PERF), yb + 102, "②0.10", ext=yb + 76, size=9)
    hdim(b, X(X_PERF), X(X_WEIR), yb + 102, f"ช่วงตรง {X_WEIR - X_PERF:.2f}", ext=yb + 76)
    b.append(text(X(X_C2_END), yb + 40, "สันปลายช่อง 2", 10, "middle", "#555"))
    b.append(text(X(X_WEIR), yb + 40, "แผ่นเวียร์", 10, "middle", "#555"))
    vdim(b, Y(0), Y(0.15), X(X_BOD) - 20, "0.15", ext=X(X_BOD), size=10)
    xr = X(X_END + WALL) + 26
    vdim(b, Y(0), Y(B / 2), xr, f"{B/2:.3f}", ext=X(X_TAP), side=1, size=10)
    vdim(b, Y(B / 2), Y(B), xr, f"{B/2:.3f}", ext=X(X_END + WALL), side=1, size=10)
    vdim(b, Y(0), Y(B), xr + 30, f"B {B:.2f}", ext=xr, side=1)
    # ---------- รูปตัด ----------
    top = yb + 180
    Z = lambda z: top + (Z_WALL_TOP + 0.25 - z) * S
    b.append(text(X(x0), top - 10, "รูปตัดช่อง 3", 15, "start", weight="bold"))
    b.append(rect(X(X_C2_END), Z(Z_MAX), (X_WEIR - X_C2_END) * S, Z_MAX * S, fill="#cfe5f3", stroke="none"))
    b.append(line(X(X_C2_END), Z(Z_VERTEX), X(X_WEIR), Z(Z_VERTEX), "#3182bd", 1, "6 3"))
    b.append(rect(X(x0), Z(Z_RAISED), (X_C2_END - x0) * S, Z_RAISED * S))
    b.append(rect(X(x0), Z(0), (X_END + WALL - x0) * S, 0.20 * S))
    b.append(rect(X(X_WEIR), Z(Z_WW), T_WW * S, Z_WW * S))
    b.append(rect(X(X_B3), Z(Z_WALL_TOP), T_B3 * S, (Z_WALL_TOP - Z_B3) * S))
    b.append(rect(X(X_S3U), Z(Z_S3), T_B3 * S, Z_S3 * S))
    vdim(b, Z(Z_B3), Z(0), X(X_B3) - 14, f'ลอด {Z_B3:.2f}', size=10)
    vdim(b, Z(Z_S3), Z(0), X(X_S3U) - 12, f'สัน {Z_S3:.2f}', size=10)
    b.append(rect(X(X_WEIR) - 3, Z(Z_NOTCH_TOP + 0.10), 4, (Z_NOTCH_TOP + 0.10 - Z_PB) * S, fill="#333"))
    b.append(rect(X(X_END), Z(Z_WALL_TOP), WALL * S, Z_WALL_TOP * S))
    b.append(line(X(x0), Z(Z_WALL_TOP), X(X_END), Z(Z_WALL_TOP), "#999", 0.8, "4 3"))
    b.append(text(X(x0) + 4, Z(Z_WALL_TOP) - 4, "สันกำแพง +1.20", 10, "start", "#555"))
    # Flow meter
    xt = X(X_TAP)
    b.append(rect(xt - 34, Z(Z_WALL_TOP + 0.05), 68, 0.05 * S, fill="#9aa4ab", stroke="#555", sw=0.8))
    b.append(rect(xt - 11, Z(Z_DL + 0.10), 22, 0.10 * S, fill="#ffffff", stroke="#c00", sw=2))
    b.append(line(xt, Z(Z_DL), xt, Z(Z_MAX), "#c00", 1, "3 3"))
    b.append(text(xt + 40, Z(Z_WALL_TOP + 0.03), "คาน SS วางบนสันกำแพง", 10, "start", "#555"))
    b.append(text(xt + 16, Z(Z_DL + 0.05) + 4, "Flow meter", 12, "start", "#c00", "bold"))
    # BOD
    xb = X(X_BOD)
    b.append(line(xb, Z(Z_WALL_TOP + 0.20), xb, Z(Z_BOD + 0.25), "#777", 4))
    b.append(rect(xb - 8, Z(Z_BOD + 0.30), 16, 0.30 * S, fill="#e8eef2", stroke="#333", sw=1.5))
    b.append(text(xb + 14, Z(Z_BOD + 0.20), "BOD probe", 12, "start", "#222", "bold"))
    b.append(text(xb + 14, Z(Z_BOD + 0.20) + 15, "เสา SS ยึดขอบบ่อ", 10, "start", "#555"))
    # ระดับ
    xl = X(x0) - 20
    for z, name, c in [(Z_DL, "หน้า Flow meter +1.10", "#c00"), (Z_MAX, "น้ำสูงสุด +0.81", "#1f5f8b"),
                       (Z_VERTEX, "ยอด V / น้ำต่ำสุด +0.60", "#1f5f8b"), (Z_BOD, "ปลาย BOD +0.30", "#222"), (0.0, "พื้นบ่อ ±0.00", "#222")]:
        b.append(line(X(x0), Z(z), X(X_WEIR) + 30, Z(z), c, 0.6, "2 3"))
        b.append(text(X(X_WEIR) + 34 + T_WW * S, Z(z) - 4, name, 11, "start", c))
    vdim(b, Z(Z_DL), Z(Z_MAX), xt - 26, f"{Z_DL - Z_MAX:.2f}", size=10)
    vdim(b, Z(Z_MAX), Z(Z_VERTEX), xt - 26, f"{Z_MAX - Z_VERTEX:.2f}", size=10)
    vdim(b, Z(Z_DL), Z(Z_VERTEX), xt - 52, f"{Z_DL - Z_VERTEX:.2f}", size=10)
    vdim(b, Z(Z_VERTEX), Z(Z_BOD), xb - 22, f"จม {Z_VERTEX - Z_BOD:.2f}", size=10)
    vdim(b, Z(Z_BOD), Z(0), xb - 22, f"{Z_BOD:.2f}", size=10)
    yb2 = Z(-0.20)
    hdim(b, X(X_C2_END), X(X_BOD), yb2 + 24, f"{X_BOD - X_C2_END:.2f}", ext=yb2)
    hdim(b, X(X_BOD), X(X_TAP), yb2 + 24, f"{X_TAP - X_BOD:.2f}", ext=yb2)
    hdim(b, X(X_TAP), X(X_WEIR), yb2 + 24, f"{X_WEIR - X_TAP:.2f}", ext=yb2)
    H_ = int(yb2 + 60)
    b.insert(0, text(W_ / 2, 40, "ตำแหน่งติดตั้ง Flow meter และ BOD probe (ช่อง 3, หน่วย m, ระดับจากผิวพื้นในบ่อ)", 16, "middle", weight="bold"))
    return svg(W_, H_, "".join(b), "ตำแหน่งติดตั้งเซนเซอร์")


# ---------------------------------------------------------------- Folded layouts (แบบตรง / U / L)
def folded():
    S = 105
    W_ = 1180
    b = []
    L1A, L2A = 1.00, 1.00            # ช่อง 2 ยาว / โซนรับน้ำตก (= ความยาวสัน)
    LA, LD = 2.10, 0.95
    row1 = (X_C1_END) + L1A          # 2.60
    lin = L2A + LA + T_WW + LD       # 4.25
    wl = B                           # ความกว้างแต่ละแถว
    win = 2 * wl + WALL

    def panel(x0, y0, kind, opp=False):
        X = lambda x: x0 + (x + WALL) * S
        Y = lambda y: y0 + (win + WALL - y) * S       # y = 0 ที่ผิวในผนังล่าง (แถว 2)
        g = []
        # เปลือกนอก
        if kind == "L":
            pts = [(-WALL, -WALL), (lin + WALL, -WALL), (lin + WALL, wl + WALL), (row1 + WALL, wl + WALL),
                   (row1 + WALL, win + WALL), (-WALL, win + WALL)]
        else:
            pts = [(-WALL, -WALL), (lin + WALL, -WALL), (lin + WALL, win + WALL), (-WALL, win + WALL)]
        g.append(poly([(X(x), Y(y)) for x, y in pts], "url(#rc)", "#333", 1.2))
        # แถว 2 (ล่าง): รับน้ำตก + ช่วงตรง | กำแพงเวียร์ | ท้ายเวียร์
        g.append(rect(X(0), Y(wl), (L2A + LA) * S, wl * S, fill="#dbeefa", stroke="none"))
        g.append(rect(X(L2A + LA + T_WW), Y(wl), LD * S, wl * S, fill="#dbeefa", stroke="none"))
        g.append(rect(X(L2A + LA) - 2, Y(wl + 0.08), 4, (wl + 0.16) * S, fill="#333"))
        # แถว 1 (บน): ช่อง 2 พื้นยก (ซ้าย) | ช่อง 1 (ขวา)
        yb1 = wl + WALL
        g.append(rect(X(0), Y(win), L1A * S, (wl + WALL) * S, fill="#ffffff", stroke="#999", sw=0.6))   # พื้นยกรวมแนวสัน
        g.append(rect(X(L1A), Y(win), X_C1_END * S, wl * S, fill="#dbeefa", stroke="none"))
        g.append(rect(X(L1A + 1.00), Y(win), 0.10 * S, wl * S))                                  # ผนังกั้นช่อง 1
        g.append(rect(X(0), Y(wl) - 2, L1A * S, 3, fill="#555"))                                  # สันข้าง SS
        if kind == "U":
            g.append(rect(X(row1 + WALL), Y(win), (lin - row1 - WALL) * S, wl * S, fill="#f1f1f1", stroke="none"))
            g.append(text(X((row1 + WALL + lin) / 2), Y(yb1 + 0.20), "พื้นที่ว่าง / ตู้คอนโทรล", 11, "middle", "#777"))
            g.append(text(X((row1 + WALL + lin) / 2), Y(yb1 + 0.20) + 14, "(ท่อเข้าต้องลอดผ่าน)", 10, "middle", "#999"))
        # ปั๊ม ท่อ เซนเซอร์
        g.append(f"<circle cx='{X(L1A + 0.5):.1f}' cy='{Y(yb1 + wl/2):.1f}' r='{0.17*S:.1f}' fill='#f2a541' stroke='#333'/>")
        g.append(text(X(L1A + 0.5), Y(yb1 + wl / 2) + 4, "P", 12, "middle", weight="bold"))
        if opp:
            xi = row1 - 0.25
            g.append(rect(X(xi) - 8, Y(win + WALL) - 34, 16, WALL * S + 34 + 0.30 * S, fill="#bbb"))
            g.append(f"<circle cx='{X(xi):.1f}' cy='{Y(win - 0.30):.1f}' r='9' fill='#bbb' stroke='#333'/>")
            g.append(text(X(xi) + 14, Y(win + WALL) - 22, "ท่อเข้า 6\" (เข้าทางด้านบน)", 12, "start", "#c2410c", "bold"))
            xo = (L2A + LA + T_WW + lin) / 2
            g.append(rect(X(xo) - 10, Y(0), 20, WALL * S + 34, fill="#bbb"))
            g.append(text(X(xo) + 14, Y(-WALL) + 30, "ท่อออก 8\" (ออกทางด้านล่าง)", 12, "start", "#c2410c", "bold"))
        else:
            g.append(rect(X(row1), Y(yb1 + wl / 2) - 8, WALL * S + 34, 16, fill="#bbb"))
            g.append(text(X(row1 + WALL) + 38, Y(yb1 + wl / 2) + 4, "ท่อเข้า 6\"", 11))
            g.append(rect(X(lin), Y(wl / 2) - 10, WALL * S + 34, 20, fill="#bbb"))
            g.append(text(X(lin + WALL) + 38, Y(wl / 2) + 4, "ท่อออก 8\"", 11))
        xt = L2A + LA - 0.95
        g.append(rect(X(xt) - 4, Y(wl + 0.02), 8, (wl + 0.04) * S, fill="#9aa4ab", stroke="#555", sw=0.6))
        g.append(rect(X(xt) - 8, Y(wl / 2) - 8, 16, 16, fill="#fff", stroke="#c00", sw=2))
        g.append(f"<circle cx='{X(L2A + 0.30):.1f}' cy='{Y(0.15):.1f}' r='7' fill='#e8eef2' stroke='#333' stroke-width='1.5'/>")
        g.append(text(X(L2A + 0.30) + 10, Y(0.15) + 4, "BOD", 10))
        g.append(text(X(xt) + 12, Y(wl / 2) - 12, "Flow meter", 10, "start", "#c00"))
        # ลูกศรทางน้ำ
        arr = "stroke='#2f7fb3' stroke-width='3' fill='none' marker-end='url(#a)'"
        g.append(f"<path d='M{X(row1 - 0.15):.1f},{Y(yb1 + 0.25):.1f} H{X(L1A + 0.9):.1f}' {arr}/>")
        g.append(f"<path d='M{X(L1A - 0.05):.1f},{Y(yb1 + 0.25):.1f} H{X(0.5):.1f} V{Y(wl - 0.15):.1f}' {arr}/>")
        g.append(f"<path d='M{X(0.5):.1f},{Y(wl - 0.35):.1f} V{Y(0.45):.1f} H{X(L2A + LA - 0.15):.1f}' {arr}/>")
        if opp:
            g.append(f"<path d='M{X(L2A + LA + T_WW + 0.1):.1f},{Y(0.45):.1f} H{X((L2A + LA + T_WW + lin) / 2):.1f} V{Y(-WALL) + 20:.1f}' {arr}/>")
        else:
            g.append(f"<path d='M{X(L2A + LA + T_WW + 0.1):.1f},{Y(0.45):.1f} H{X(lin - 0.1):.1f}' {arr}/>")
        # ป้ายช่อง
        g.append(text(X(L1A / 2), Y(yb1 + wl) + 16, "ช่อง 2 พื้นยก", 11, "middle", "#1f5f8b", "bold"))
        g.append(text(X(L1A / 2), Y(yb1 + wl) + 30, "(น้ำไหลขวาง)", 10, "middle", "#1f5f8b"))
        g.append(text(X(L1A + 1.3), Y(yb1 + wl) + 16, "ช่อง 1", 11, "middle", "#1f5f8b", "bold"))
        g.append(text(X(L2A / 2), Y(0.12), "รับน้ำตก", 10, "middle", "#1f5f8b", "bold"))
        g.append(text(X(L2A + LA / 2), Y(0.12), "ช่วงตรง 2.10", 10, "middle", "#1f5f8b", "bold"))
        # มิติ
        yt = Y(win + WALL)
        for a, c, t in [(0, L1A, "1.00"), (L1A, L1A + 1.00, "1.00"), (L1A + 1.00, L1A + 1.10, "0.10"), (L1A + 1.10, row1, "0.50")]:
            hdim(g, X(a), X(c), yt - 16, t, ext=yt, size=9)
        yb_ = Y(-WALL)
        for a, c, t in [(0, L2A, "1.00"), (L2A, L2A + LA, "2.10"), (L2A + LA, L2A + LA + T_WW, "0.20"), (L2A + LA + T_WW, lin, "0.95")]:
            hdim(g, X(a), X(c), yb_ + 18, t, ext=yb_, size=9)
        hdim(g, X(-WALL), X(lin + WALL), yb_ + (62 if opp else 42), f"ยาวภายนอก {lin + 2*WALL:.2f}", ext=yb_ + 18, size=12)
        xr = X(lin + WALL) + 14 if kind == "U" else X(lin + WALL) + 14
        vdim(g, Y(-WALL), Y(win + WALL), X(-WALL) - 18, f"กว้าง {win + 2*WALL:.2f}", ext=X(-WALL))
        vdim(g, Y(0), Y(wl), X(-WALL) - 44, f"{wl:.2f}", ext=X(-WALL) - 18, size=9)
        vdim(g, Y(wl), Y(wl + WALL), X(-WALL) - 44, "0.20", ext=X(-WALL) - 18, size=8)
        vdim(g, Y(wl + WALL), Y(win), X(-WALL) - 44, f"{wl:.2f}", ext=X(-WALL) - 18, size=9)
        return g, Y(-WALL) + 60

    # แบบตรง (ย่อ)
    y = 90
    b.append(text(60, y - 30, f"แบบตรง (ปัจจุบัน) — ภายนอก {X_END + 2*WALL:.2f} × {B + 2*WALL:.2f} m", 15, "start", weight="bold"))
    X = lambda x: 100 + (x + WALL) * S
    Y0 = lambda yy: y + (B + WALL - yy) * S
    b.append(rect(X(-WALL), Y0(B + WALL), (X_END + 2 * WALL) * S, (B + 2 * WALL) * S))
    for a, c, fill in [(0, X_C1_END, "#dbeefa"), (X_C1_END, X_C2_END, "#ffffff"), (X_C2_END, X_WEIR, "#dbeefa"), (X_WEIR + T_WW, X_END, "#dbeefa")]:
        b.append(rect(X(a), Y0(B), (c - a) * S, B * S, fill=fill, stroke="#999", sw=0.4))
    b.append(rect(X(X_BAFFLE), Y0(B), 0.10 * S, B * S))
    b.append(f"<circle cx='{X(X_PUMP):.1f}' cy='{Y0(B/2):.1f}' r='{0.17*S:.1f}' fill='#f2a541' stroke='#333'/>")
    b.append(rect(X(X_WEIR) - 2, Y0(B + 0.08), 4, (B + 0.16) * S, fill="#333"))
    b.append(f"<path d='M{X(0.1):.1f},{Y0(0.25):.1f} H{X(X_END - 0.1):.1f}' stroke='#2f7fb3' stroke-width='3' fill='none' marker-end='url(#a)'/>")
    for a, c, t in [(0, X_C1_END, "ช่อง 1  1.60"), (X_C1_END, X_C2_END, "ช่อง 2  1.00"), (X_C2_END, X_END, "ช่อง 3  3.75")]:
        hdim(b, X(a), X(c), Y0(-WALL) + 18, t, ext=Y0(-WALL), size=10)
    hdim(b, X(-WALL), X(X_END + WALL), Y0(-WALL) + 42, f"ยาวภายนอก {X_END + 2*WALL:.2f}", ext=Y0(-WALL) + 18, size=12)
    y = Y0(-WALL) + 110

    for kind, opp, ttl in [("U", False, f"แบบ U (สี่เหลี่ยม) — ภายนอก {lin + 2*WALL:.2f} × {win + 2*WALL:.2f} m"),
                           ("L", False, "แบบ L (ตัดมุมว่าง) — ท่อเข้า–ออกด้านเดียวกัน"),
                           ("L", True, "แบบ L — ท่อเข้า–ออกคนละฝั่ง (เข้าด้านบน / ออกด้านล่าง)  ← แนะนำ")]:
        b.append(text(60, y - 6, ttl, 15, "start", weight="bold"))
        g, y_end = panel(150, y + (70 if opp else 40), kind, opp)
        b.extend(g)
        y = y_end + 70
    H_ = int(y - 20)
    b.insert(0, text(W_ / 2, 30, "แบบพับบ่อ: เทียบแบบตรง / U / L (แปลน, หน่วย m)", 18, "middle", weight="bold"))
    return svg(W_, H_, "".join(b), "แบบพับบ่อ U และ L")


# ---------------------------------------------------------------- ทางเลือกช่อง 1 สำหรับ HRT 15 นาที
def hrt_options():
    S = 82
    W_ = 1150
    b = []
    zw = 0.953                       # น้ำช่อง 1 ที่ Qavg
    L2, L3 = X_C2_END - X_C1_END, X_END - X_C2_END
    opts = [("A", "ทางเลือก A: ช่อง 1 ลึก −1.00 กว้าง 2.50 m", 3.25, 2.50, -1.00),
            ("B", "ทางเลือก B: ช่อง 1 ลึก −1.50 กว้าง 1.50 m (เท่าบ่อ)", 4.30, 1.50, -1.50)]
    y = 70
    for key, ttl, L1, W1, zf in opts:
        lin = L1 + L2 + L3
        V = L1 * W1 * (zw - zf) - 0.09
        hrt = V / 62.8 * 60
        b.append(text(40, y, ttl, 16, "start", weight="bold"))
        b.append(text(40, y + 22, f"ปริมาตรน้ำช่อง 1 ≈ {V:.1f} m³  →  HRT = {hrt:.1f} นาที ที่ Qavg 62.8 m³/h  |  บ่อยาวภายนอก {lin + 2*WALL:.2f} m",
                      12, "start", "#1f5f8b", "bold"))
        # ---------- รูปตัด ----------
        X = lambda x: 110 + (x + WALL) * S
        top = y + 50
        Z = lambda z: top + (1.30 - z) * S
        x1, x2 = L1, L1 + L2
        xp = x2 + 0.50; xw = xp + 2.10
        # น้ำ
        b.append(rect(X(0), Z(zw), L1 * S, (zw - zf) * S, fill="#cfe5f3", stroke="none"))
        b.append(rect(X(x1), Z(Z_RAISED + 0.06), L2 * S, 0.06 * S, fill="#e3f4fb", stroke="none"))
        b.append(rect(X(x2), Z(Z_MAX), (xw - x2) * S, Z_MAX * S, fill="#cfe5f3", stroke="none"))
        b.append(rect(X(xw + T_WW), Z(Z_TAIL), 0.95 * S, Z_TAIL * S, fill="#cfe5f3", stroke="none"))
        # คอนกรีต: พื้นช่อง 1 (ลึก), พื้นช่อง 2–3, ผนัง
        b.append(rect(X(-WALL), Z(zf), (L1 + 2 * WALL) * S, 0.20 * S))
        b.append(rect(X(x1 + WALL), Z(0), (lin - x1) * S, 0.20 * S))
        b.append(rect(X(x1), Z(Z_RAISED), L2 * S, (Z_RAISED - zf) * S))
        b.append(rect(X(-WALL), Z(Z_WALL_TOP), WALL * S, (Z_WALL_TOP - zf) * S))
        b.append(rect(X(lin), Z(Z_WALL_TOP), WALL * S, Z_WALL_TOP * S))
        b.append(rect(X(0.50), Z(Z_WALL_TOP), 0.10 * S, (Z_WALL_TOP - zf - 0.30) * S))
        b.append(rect(X(xw), Z(Z_WW), T_WW * S, Z_WW * S))
        b.append(rect(X(xw) - 2, Z(1.0), 3, 0.60 * S, fill="#333"))
        b.append(rect(X(x2 + 0.30) - 1.5, Z(Z_WALL_TOP), 3, (Z_WALL_TOP - 0.20) * S, fill="#4a5560"))
        b.append(rect(X(xp) - 1.5, Z(0.30), 3, 0.30 * S, fill="#4a5560"))
        # ท่อเข้า + ท่อจุ่ม, ปั๊ม
        b.append(rect(X(-WALL) - 24, Z(1.10), 24 + (WALL + 0.25) * S, 0.168 * S, fill="#bbb"))
        b.append(rect(X(0.25) - 0.168 * S, Z(1.10), 0.168 * S, (1.10 - (zf + 0.30)) * S, fill="#bbb"))
        xpmp = 0.60 + (L1 - 0.60) / 2
        b.append(rect(X(xpmp) - 0.2 * S, Z(zf + 0.55), 0.4 * S, 0.55 * S, fill="#f2a541"))
        b.append(line(X(0.6), Z(zw), X(x1), Z(zw), "#1f5f8b", 0.8, "4 3"))
        b.append(text(X(x1) - 4, Z(zw) - 4, f"น้ำ +{zw:.2f}", 10, "end", "#1f5f8b"))
        b.append(text(X(xpmp), Z(zf + 0.27), "ปั๊ม", 10, "middle", weight="bold"))
        # มิติ
        vdim(b, Z(zw), Z(zf), X(-WALL) - 16, f"ลึก {zw - zf:.2f}", size=10)
        b.append(text(X(-WALL) - 30, Z(zf) + 4, f"พื้น {zf:+.2f}", 10, "end"))
        b.append(text(X(lin + WALL) + 6, Z(0) + 4, "พื้น ±0.00", 10))
        yd = Z(min(zf, -0.2) - 0.2) + 18
        for a, c, t in [(0, x1, f"ช่อง 1  {L1:.2f}"), (x1, x2, f"ช่อง 2  {L2:.2f}"), (x2, lin, f"ช่อง 3  {L3:.2f}")]:
            hdim(b, X(a), X(c), yd, t, ext=Z(min(zf, 0) - 0.2), size=10)
        hdim(b, X(-WALL), X(lin + WALL), yd + 24, f"ยาวภายนอก {lin + 2*WALL:.2f}", ext=yd, size=11)
        # ---------- แปลน ----------
        y0 = yd + 60
        Wmax = max(W1, B)
        Yp = lambda yy: y0 + (Wmax / 2 + WALL - yy) * S           # yy = 0 ที่แนวกลางบ่อ
        def box(xa, xb_, w, fill):
            b.append(rect(X(xa), Yp(w / 2), (xb_ - xa) * S, w * S, fill=fill, stroke="none"))
        # เปลือก
        pts = [(-WALL, W1 / 2 + WALL), (x1 + (WALL if W1 > B else 0), W1 / 2 + WALL)]
        b.append(rect(X(-WALL), Yp(W1 / 2 + WALL), (L1 + 2 * WALL if W1 > B else L1 + WALL) * S, (W1 + 2 * WALL) * S))
        b.append(rect(X(x1), Yp(B / 2 + WALL), (lin - x1 + WALL) * S, (B + 2 * WALL) * S))
        box(0, L1, W1, "#dbeefa")
        box(x1, x2, B, "#ffffff")
        box(x2, xw, B, "#dbeefa")
        box(xw + T_WW, lin, B, "#dbeefa")
        if W1 > B:
            b.append(rect(X(x1), Yp(B / 2), WALL * S, B * S, fill="#ffffff", stroke="none"))
        b.append(rect(X(0.50), Yp(W1 / 2), 0.10 * S, W1 * S))
        b.append(rect(X(xw), Yp(B / 2), T_WW * S, B * S))
        b.append(f"<circle cx='{X(xpmp):.1f}' cy='{Yp(0):.1f}' r='{0.2*S:.1f}' fill='#f2a541' stroke='#333'/>")
        b.append(rect(X(-WALL) - 24, Yp(0) - 7, 24 + (WALL + 0.25) * S, 14, fill="#bbb"))
        b.append(text(X(L1 / 2), Yp(-W1 / 2) - 6, f"ช่อง 1  {L1:.2f} × {W1:.2f}", 11, "middle", "#1f5f8b", "bold"))
        b.append(text(X((x1 + x2) / 2), Yp(-B / 2) - 6, "ช่อง 2", 10, "middle", "#1f5f8b", "bold"))
        b.append(text(X((x2 + lin) / 2), Yp(-B / 2) - 6, "ช่อง 3", 10, "middle", "#1f5f8b", "bold"))
        vdim(b, Yp(W1 / 2), Yp(-W1 / 2), X(-WALL) - 16, f"{W1:.2f}", ext=X(-WALL), size=10)
        vdim(b, Yp(B / 2), Yp(-B / 2), X(lin + WALL) + 16, f"{B:.2f}", ext=X(lin + WALL), side=1, size=10)
        y = Yp(-Wmax / 2 - WALL) + 60
    H_ = int(y)
    b.insert(0, text(W_ / 2, 30, "ช่อง 1 สำหรับ HRT 15 นาที (ที่ Qavg 62.8 m³/h) — รูปตัดและแปลน, หน่วย m", 17, "middle", weight="bold"))
    return svg(W_, H_, "".join(b), "ทางเลือกช่อง 1 HRT 15 นาที")


# ---------------------------------------------------------------- รายละเอียดช่อง 1 (ทางเลือก A)
def comp1_detail():
    S = 150
    x0, x1e = -WALL - 0.10, X_C1_END + 1.10
    X = lambda x: 150 + (x - x0) * S
    b = []
    xi = 0.20                      # ศก.ท่อจุ่ม จากผิวในผนังหัวบ่อ
    dpo = 0.168
    # ---------- แปลน ----------
    Y = lambda y: 190 + (y + OFF1 + WALL) * S
    b.append(text(X(x0) - 120, 105, "แปลนช่อง 1", 15, "start", weight="bold"))
    b.append(rect(X(0), Y(-OFF1), X_C1_END * S, W1 * S, fill="#eef6fc", stroke="none"))
    b.append(rect(X(X_C1_END), Y(0), (x1e - X_C1_END) * S, B * S, fill="#ffffff", stroke="#999", sw=0.6))
    b.append(rect(X(-WALL), Y(-OFF1 - WALL), (X_C1_END + 2 * WALL) * S, WALL * S))
    b.append(rect(X(-WALL), Y(B + OFF1), (X_C1_END + 2 * WALL) * S, WALL * S))
    b.append(rect(X(-WALL), Y(-OFF1), WALL * S, W1 * S))
    b.append(rect(X(X_C1_END), Y(-OFF1), WALL * S, OFF1 * S))
    b.append(rect(X(X_C1_END), Y(B), WALL * S, OFF1 * S))
    b.append(rect(X(X_C1_END), Y(-WALL), (x1e - X_C1_END) * S, WALL * S))
    b.append(rect(X(X_C1_END), Y(B), (x1e - X_C1_END) * S, WALL * S))
    b.append(rect(X(X_BAFFLE), Y(-OFF1), 0.10 * S, W1 * S))
    yi = -OFF1 + 0.30
    b.append(rect(X(-WALL) - 40, Y(yi) - dpo * S / 2, 40 + (WALL + xi) * S, dpo * S, fill="#bbb"))
    b.append(f"<circle cx='{X(xi):.1f}' cy='{Y(yi):.1f}' r='{dpo*S/2:.1f}' fill='#bbb' stroke='#333'/>")
    b.append(text(X(-WALL) - 44, Y(yi) - 16, "ท่อเข้า 6\"", 12))
    b.append(f"<circle cx='{X(X_PUMP):.1f}' cy='{Y(B/2):.1f}' r='{0.20*S:.1f}' fill='#f2a541' stroke='#333'/>")
    b.append(text(X(X_PUMP), Y(B / 2) + 5, "P", 14, "middle", weight="bold"))
    b.append(text(X(X_PUMP), Y(B / 2) + 0.20 * S + 16, "ฐานปั๊ม 0.40 × 0.40", 10, "middle"))
    b.append(text(X((X_C1_END + x1e) / 2), Y(B / 2), "ช่อง 2 (พื้นยก)", 11, "middle", "#1f5f8b", "bold"))
    b.append(text(X(0.25), Y(B + OFF1) - 10, "โซนน้ำเข้า", 10, "middle", "#1f5f8b"))
    b.append(text(X((0.60 + X_C1_END) / 2), Y(B + OFF1) - 10, "โซนปั๊ม", 11, "middle", "#1f5f8b", "bold"))
    # มิติแปลน (บน)
    yt = Y(-OFF1 - WALL)
    for a, c, t in [(-WALL, 0, "0.20"), (0, X_BAFFLE, "0.50"), (X_BAFFLE, X_BAFFLE + 0.10, "0.10"),
                    (X_BAFFLE + 0.10, X_C1_END, f"{X_C1_END - 0.60:.2f}"), (X_C1_END, X_C1_END + WALL, "0.20")]:
        hdim(b, X(a), X(c), yt - 18, t, ext=yt, size=10)
    hdim(b, X(0), X(X_C1_END), yt - 42, f"ช่อง 1 ยาวภายใน {X_C1_END:.2f}", ext=yt - 18, size=12)
    # มิติแปลน (ล่าง): ท่อจุ่ม, ปั๊ม
    yb = Y(B + OFF1 + WALL)
    hdim(b, X(0), X(xi), yb + 20, f"{xi:.2f}", ext=yb, size=9)
    hdim(b, X(0), X(X_PUMP), yb + 44, f"ศก.ปั๊ม {X_PUMP:.2f}", ext=yb + 20, size=10)
    hdim(b, X(X_PUMP), X(X_C1_END), yb + 44, f"{X_C1_END - X_PUMP:.2f}", ext=yb + 20, size=10)
    hdim(b, X(X_BAFFLE + 0.10), X(X_PUMP), yb + 68, f"ผนังกั้น → ศก.ปั๊ม {X_PUMP - 0.60:.2f}", ext=yb + 44, size=10)
    # มิติแปลน (ซ้าย/ขวา)
    xl = X(-WALL) - 60
    vdim(b, Y(-OFF1), Y(yi), X(-WALL) - 22, "0.30", ext=X(xi), size=9)
    for y1, y2, t in [(-OFF1 - WALL, -OFF1, "0.20"), (-OFF1, B + OFF1, f"ภายใน {W1:.2f}"), (B + OFF1, B + OFF1 + WALL, "0.20")]:
        vdim(b, Y(y1), Y(y2), xl, t, ext=X(-WALL), size=10)
    vdim(b, Y(-OFF1 - WALL), Y(B + OFF1 + WALL), xl - 30, f"ภายนอก {W1 + 2*WALL:.2f}", ext=xl)
    xr = X(x1e) + 20
    for y1, y2, t in [(-OFF1, 0, f"{OFF1:.2f}"), (0, B / 2, f"{B/2:.2f}"), (B / 2, B, f"{B/2:.2f}"), (B, B + OFF1, f"{OFF1:.2f}")]:
        vdim(b, Y(y1), Y(y2), xr, t, ext=X(X_C1_END + WALL), side=1, size=9)
    b.append(text(xr + 14, Y(B / 2) + 18, "ศก.ปั๊ม = แนวกลางบ่อ", 10, "start", "#555"))
    # ---------- รูปตัด ----------
    top = Y(B + OFF1 + WALL) + 140
    Z = lambda z: top + (1.40 - z) * S
    b.append(text(X(x0), top - 10, "รูปตัดช่อง 1 (แนว A–A)", 15, "start", weight="bold"))
    b.append(rect(X(0), Z(Z_C1), X_C1_END * S, (Z_C1 - Z_F1) * S, fill="#cfe5f3", stroke="none"))
    b.append(rect(X(X_C1_END), Z(Z_RAISED + 0.067), (x1e - X_C1_END) * S, 0.067 * S, fill="#e3f4fb", stroke="none"))
    b.append(rect(X(-WALL), Z(Z_F1), (X_C1_END + 2 * WALL) * S, 0.20 * S))
    b.append(rect(X(-WALL), Z(Z_WALL_TOP), WALL * S, (Z_WALL_TOP - Z_F1) * S))
    b.append(rect(X(X_C1_END), Z(Z_RAISED), (x1e - X_C1_END) * S, (Z_RAISED - Z_F1) * S))
    b.append(rect(X(X_BAFFLE), Z(Z_WALL_TOP), 0.10 * S, (Z_WALL_TOP - Z_GAP) * S))
    b.append(rect(X(-WALL) - 40, Z(1.10 + dpo / 2), 40 + (WALL + xi) * S, dpo * S, fill="#bbb"))
    b.append(rect(X(xi) - dpo * S / 2, Z(1.10 + dpo / 2), dpo * S, (1.10 + dpo / 2 - Z_DIP) * S, fill="#bbb"))
    b.append(f"<circle cx='{X(xi):.1f}' cy='{Z(1.10 + dpo/2) + 4:.1f}' r='3' fill='#fff' stroke='#333'/>")
    b.append(text(X(xi) + 14, Z(1.10 + dpo / 2) - 4, "รูกันกาลักน้ำ Ø10–15", 9, "start", "#555"))
    b.append(rect(X(X_PUMP) - 0.20 * S, Z(Z_F1 + 0.55), 0.40 * S, 0.55 * S, fill="#f2a541"))
    b.append(text(X(X_PUMP), Z(Z_F1 + 0.28), "ปั๊มจุ่ม", 11, "middle", weight="bold"))
    b.append(f"<path d='M{X(X_PUMP) + 0.2*S:.1f},{Z(Z_F1 + 0.35):.1f} H{X(X_PUMP + 0.45):.1f} V{Z(1.45):.1f} H{X(X_C1_END + 0.9):.1f}' fill='none' stroke='#2c7a2c' stroke-width='6'/>")
    b.append(text(X(X_C1_END + 0.9) - 4, Z(1.45) - 8, "→ Water recycle 10 m³/h", 11, "end", "#2c7a2c"))
    for z, name, c in [(Z_START, "ปั๊ม START", "#2c7a2c"), (Z_STOP, "ปั๊ม STOP", "#2c7a2c")]:
        b.append(line(X(0.62), Z(z), X(X_C1_END), Z(z), c, 1, "6 3"))
    # ระดับด้านขวา
    xe = X(x1e) + 30
    lv = [(Z_WALL_TOP, "สันกำแพง"), (1.10, "ศก.ท่อเข้า 6\""), (Z_C1, "น้ำช่อง 1 (100 m³/h)"), (Z_RAISED, "ผิวพื้นยกช่อง 2"),
          (Z_START, "ปั๊ม START"), (Z_STOP, "ปั๊ม STOP"), (Z_DIP, "ปลายท่อจุ่ม"), (Z_GAP, "ขอบล่างผนังกั้น"),
          (Z_F1 + 0.55, "หัวปั๊ม (สูง 0.55)"), (Z_F1, "ผิวพื้นช่อง 1"), (Z_F1 - TS, "ใต้พื้น")]
    ly = Z(Z_WALL_TOP)
    for z, name in sorted(lv, key=lambda t: -t[0]):
        yy = max(Z(z), ly)
        b.append(f"<path d='M{X(x1e) + 2:.1f},{Z(z):.1f} H{xe - 12:.1f} L{xe - 4:.1f},{yy:.1f}' fill='none' stroke='#aaa' stroke-width='0.6'/>")
        b.append(f"<polygon points='{xe-4:.1f},{yy:.1f} {xe-10:.1f},{yy-5:.1f} {xe+2:.1f},{yy-5:.1f}' fill='#333'/>")
        b.append(text(xe + 6, yy + 4, f"{z:+.3f}  {name}", 11))
        ly = yy + 15
    # มิติแนวตั้ง
    vdim(b, Z(Z_WALL_TOP), Z(Z_F1), X(-WALL) - 24, f"ผนังสูง {Z_WALL_TOP - Z_F1:.2f}", ext=X(-WALL))
    vdim(b, Z(Z_F1), Z(Z_F1 - TS), X(-WALL) - 24, "0.20", ext=X(-WALL), size=9)
    vdim(b, Z(Z_C1), Z(Z_F1), X(X_C1_END) - 20, f"น้ำลึก {Z_C1 - Z_F1:.2f}", size=10)
    vdim(b, Z(Z_GAP), Z(Z_F1), X(X_BAFFLE + 0.10) + 16, f"ช่องลอด {Z_GAP - Z_F1:.2f}", side=1, size=10)
    vdim(b, Z(Z_DIP), Z(Z_F1), X(xi) + 20, f"{Z_DIP - Z_F1:.2f}", side=1, size=9)
    vdim(b, Z(Z_STOP), Z(Z_F1), X(X_PUMP) - 46, f"STOP {Z_STOP - Z_F1:.2f}", size=9)
    vdim(b, Z(Z_RAISED), Z(Z_F1), X(X_C1_END) + 24, f"ขั้นพื้นยก {Z_RAISED - Z_F1:.2f}", side=1, size=10)
    # มิติแนวนอน
    yb2 = Z(Z_F1 - TS)
    for a, c, t in [(-WALL, 0, "0.20"), (0, X_BAFFLE, "0.50"), (X_BAFFLE, X_BAFFLE + 0.10, "0.10"),
                    (X_BAFFLE + 0.10, X_C1_END, f"{X_C1_END - 0.60:.2f}"), (X_C1_END, X_C1_END + WALL, "0.20")]:
        hdim(b, X(a), X(c), yb2 + 20, t, ext=yb2, size=10)
    # ตารางสรุป
    tx, ty = X(x0), yb2 + 70
    vol = X_C1_END * W1 * (0.953 - Z_F1) - 0.09
    rows = [("ช่อง 1 ภายใน (ยาว × กว้าง × ลึกน้ำ)", f"{X_C1_END:.2f} × {W1:.2f} × {0.953 - Z_F1:.2f} m (ที่ Qavg)"),
            ("ปริมาตรน้ำ / HRT", f"≈ {vol:.1f} m³  →  {vol/62.8*60:.1f} นาที ที่ Qavg 62.8 m³/h"),
            ("ผิวพื้น / ใต้พื้น", f"{Z_F1:+.2f} / {Z_F1 - TS:+.2f}  (พื้นช่อง 2–3 ±0.00)"),
            ("ผนังช่อง 1", f"คสล. 0.20 สูง {Z_WALL_TOP - Z_F1:.2f} m — วิศวกรโยธาตรวจเหล็กเสริม/แรงดันดิน"),
            ("พื้นช่อง 1", "ลาดเข้าหาปั๊ม 1:10 เพื่อไม่ให้ตะกอนค้าง")]
    for i, (a_, c_) in enumerate(rows):
        yy = ty + i * 24
        b.append(rect(tx, yy, 300, 24, fill="#f2f2f2" if i % 2 else "#ffffff", stroke="#bbb", sw=0.6))
        b.append(rect(tx + 300, yy, 520, 24, fill="#f2f2f2" if i % 2 else "#ffffff", stroke="#bbb", sw=0.6))
        b.append(text(tx + 6, yy + 16, a_, 11))
        b.append(text(tx + 306, yy + 16, c_, 11, "start", "#222", "bold"))
    W_ = int(xe + 230)
    H_ = int(ty + len(rows) * 24 + 30)
    b.insert(0, text(W_ / 2, 40, "รายละเอียดช่อง 1 (ทางเลือก A, HRT 15 นาที) — หน่วย m, ระดับจากผิวพื้นช่อง 2–3 (±0.00)", 16, "middle", weight="bold"))
    return svg(W_, H_, "".join(b), "รายละเอียดช่อง 1")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, fn in [("section", section), ("plan", plan), ("weir_plate", plate), ("dimensions", dimensions), ("sensors", sensors), ("hrt_options", hrt_options), ("comp1_detail", comp1_detail)]:
        with open(os.path.join(OUT, f"{name}.svg"), "w", encoding="utf-8") as f:
            f.write(fn())
        print(f"{OUT}/{name}.svg")
