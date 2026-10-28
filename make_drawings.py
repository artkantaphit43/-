#!/usr/bin/env python3
"""สร้างแบบ SVG: รูปตัดตามยาว, แปลน และรายละเอียดแผ่นเวียร์ V-notch 90°  (หน่วย m)

ลำดับการไหล: ท่อน้ำเข้า -> บ่อน้ำเข้า/บ่อปั๊ม (baffle กันน้ำกระฉอก) -> รางนำน้ำ -> V-notch -> ท่อน้ำออก
"""
import os

OUT = "drawings"
FONT = "font-family='Sarabun, Tahoma, sans-serif'"

# ---- ค่าออกแบบ (ตรงกับ weir_design.py ค่า default) ----
WALL = 0.20
X_SPLASH = 0.45         # ผนังกันน้ำกระฉอก (under-flow baffle) หนา 0.10
X_SUMP_END = 1.40       # ปลายบ่อปั๊ม / ต้นรางนำน้ำ
X_PUMP = 1.00
X_BAFFLE_IN = 1.80      # แผ่นกันคลื่นรูพรุน (ต้นช่วงรางตรง)
X_WEIR = 3.80           # แผ่นเวียร์
X_TAP = X_WEIR - 0.65   # จุดวัดระดับ (≈4.7·hmax)
X_END = 4.40            # ผนังท้ายบ่อน้ำออก
Z_FLOOR_CH = 0.0
Z_FLOOR_SUMP = -1.00
Z_FLOOR_OUT = -0.30
Z_VERTEX = 0.45
Z_NOTCH_TOP = 0.70
Z_WALL_TOP = 0.90
Z_HMAX = 0.589          # ปั๊มหยุด น้ำทั้งหมด 10 L/s ผ่านเวียร์
Z_NORMAL = 0.555        # ปั๊มเดิน: 10 - 5 = 5 L/s ผ่านเวียร์ (h ≈ 105 mm)
Z_HLA = 0.65            # High alarm (เวียร์อุดตัน)
Z_START = 0.35
Z_STOP = -0.40
Z_SPLASH_BOTTOM = -0.70
Z_INLET = 0.65          # ท้องท่อน้ำเข้า
Z_DIP = -0.50           # ปลายท่อจุ่ม (ต่ำกว่า STOP)
B_CH = 0.90
B_SUMP = 1.20


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


def flow_arrow(x, y, length=40):
    return (f"<line x1='{x:.1f}' y1='{y:.1f}' x2='{x+length:.1f}' y2='{y:.1f}' stroke='#3182bd' "
            "stroke-width='2.5' marker-end='url(#a)'/>")


# ---------------------------------------------------------------- Section
def section():
    S = 150
    X0, ZTOP = 90, 1.40
    X = lambda x: X0 + (x + WALL) * S
    Y = lambda z: 70 + (ZTOP - z) * S
    b = []
    water = "#9ecae1"
    # water: sump + channel at normal level, outlet chamber shallow
    b.append(rect(X(0), Y(Z_NORMAL), X(X_SUMP_END) - X(0), Y(Z_FLOOR_SUMP) - Y(Z_NORMAL), fill=water, stroke="none"))
    b.append(rect(X(X_SUMP_END), Y(Z_NORMAL), X(X_WEIR) - X(X_SUMP_END), Y(Z_FLOOR_CH) - Y(Z_NORMAL), fill=water, stroke="none"))
    b.append(rect(X(X_WEIR), Y(-0.24), X(X_END) - X(X_WEIR), Y(Z_FLOOR_OUT) - Y(-0.24), fill=water, stroke="none"))
    # nappe
    xw = X(X_WEIR)
    b.append(f"<path d='M{xw:.1f},{Y(Z_NORMAL-0.01):.1f} Q{xw+45:.1f},{Y(0.45):.1f} {xw+55:.1f},{Y(-0.24):.1f} "
             f"L{xw+35:.1f},{Y(-0.24):.1f} Q{xw+22:.1f},{Y(0.35):.1f} {xw:.1f},{Y(Z_VERTEX):.1f} z' fill='{water}' stroke='#3182bd'/>")
    # concrete
    b.append(rect(X(-WALL), Y(Z_FLOOR_SUMP), X(X_SUMP_END + WALL) - X(-WALL), 0.2 * S))                # sump floor
    b.append(rect(X(-WALL), Y(Z_WALL_TOP), WALL * S, Y(Z_FLOOR_SUMP) - Y(Z_WALL_TOP)))                 # upstream wall
    b.append(rect(X(X_SUMP_END), Y(Z_FLOOR_CH), WALL * S, Y(Z_FLOOR_SUMP) - Y(Z_FLOOR_CH)))           # sump end (step) wall
    b.append(rect(X(X_SUMP_END), Y(Z_FLOOR_CH), X(X_WEIR) - X(X_SUMP_END), 0.2 * S))                 # channel slab
    b.append(rect(X(X_WEIR - 0.2), Y(-0.2), 0.2 * S, Y(Z_FLOOR_OUT) - Y(-0.2)))                       # wall under weir
    b.append(rect(X(X_WEIR - 0.2), Y(Z_FLOOR_OUT), X(X_END + WALL) - X(X_WEIR - 0.2), 0.2 * S))      # outlet floor
    b.append(rect(X(X_END), Y(Z_WALL_TOP), WALL * S, Y(Z_FLOOR_OUT - 0.2) - Y(Z_WALL_TOP)))            # end wall
    # inlet pipe + dip pipe + cover
    b.append(rect(X(-WALL) - 45, Y(Z_INLET + 0.12), 45 + (WALL + 0.12) * S, 0.12 * S, fill="#bbb"))
    b.append(rect(X(0.12) - 0.0, Y(Z_INLET + 0.12), 0.12 * S, Y(Z_DIP) - Y(Z_INLET + 0.12), fill="#bbb"))
    b.append(text(X(-WALL) - 45, Y(Z_INLET + 0.17), "ท่อน้ำเข้า", 12))
    b.append(f"<line x1='{X(0.18):.1f}' y1='{Y(Z_DIP)+4:.1f}' x2='{X(0.18):.1f}' y2='{Y(Z_DIP)+30:.1f}' stroke='#3182bd' stroke-width='2.5' marker-end='url(#a)'/>")
    b.append(line(X(0.12), Y(Z_DIP + 0.10), X(-WALL) - 8, Y(Z_DIP + 0.10), "#555", 0.8))
    b.append(text(X(-WALL) - 10, Y(Z_DIP + 0.10) - 4, "ท่อจุ่ม", 11, "end"))
    b.append(text(X(-WALL) - 10, Y(Z_DIP + 0.10) + 12, f"ปลาย {Z_DIP:+.2f}", 11, "end"))
    b.append(rect(X(0), Y(Z_WALL_TOP) - 5, (X_SPLASH + 0.10) * S, 5, fill="#666"))
    b.append(text(X(0.27), Y(Z_WALL_TOP) - 10, "ฝาปิด (Checker plate)", 11, "middle"))
    # splash baffle (under-flow)
    b.append(rect(X(X_SPLASH), Y(Z_WALL_TOP), 0.10 * S, Y(Z_SPLASH_BOTTOM) - Y(Z_WALL_TOP)))
    b.append(line(X(X_SPLASH + 0.13), Y(Z_SPLASH_BOTTOM), X(X_SPLASH + 0.13), Y(Z_FLOOR_SUMP), arrow=True))
    b.append(text(X(X_SPLASH + 0.15), Y(-0.83), "0.30", 10))
    # pump
    xp = X(X_PUMP)
    b.append(rect(xp - 21, Y(Z_FLOOR_SUMP + 0.55), 42, 0.55 * S, fill="#f2a541"))
    b.append(rect(xp - 28, Y(Z_FLOOR_SUMP + 0.06), 56, 0.06 * S, fill="#777"))
    b.append(f"<path d='M{xp+21:.1f},{Y(-0.65):.1f} H{X(1.25):.1f} V{Y(Z_WALL_TOP+0.25):.1f} H{X(2.00):.1f}' "
             f"fill='none' stroke='#2c7a2c' stroke-width='7'/>")
    b.append(text(X(1.00), Y(Z_WALL_TOP + 0.25) - 24, "ท่อส่งน้ำ → Water recycle", 12, color="#2c7a2c"))
    b.append(text(X(1.00), Y(Z_WALL_TOP + 0.25) - 10, "(Check valve + Gate valve + Flow meter)", 11, color="#2c7a2c"))
    b.append(line(X(1.16), Y(Z_FLOOR_SUMP + 0.10), X(1.16), Y(Z_WALL_TOP + 0.05), "#777", 1, "2 2"))
    b.append(text(X(1.16) + 4, Y(Z_WALL_TOP + 0.03), "Guide rail", 10, "start", "#555"))
    b.append(text(xp, Y(Z_FLOOR_SUMP + 0.30), "ปั๊ม", 11, "middle", weight="bold"))
    # level lines in pump zone
    for z, name, c in [(Z_HLA, "High alarm", "#e6550d"), (Z_START, "START", "#2c7a2c"), (Z_STOP, "STOP", "#2c7a2c")]:
        b.append(line(X(X_SPLASH + 0.12), Y(z), X(X_SUMP_END), Y(z), c, 1, "6 3"))
        b.append(text(X(X_SPLASH + 0.13), Y(z) - 3, f"{name} {z:+.3f}", 10, "start", c))
    # perforated baffle
    for z in [i / 10 for i in range(0, 8)]:
        b.append(rect(X(X_BAFFLE_IN) - 2, Y(z + 0.08), 4, 0.06 * S, fill="#666", stroke="none"))
    # stilling well + sensor
    xt = X(X_TAP)
    b.append(rect(xt - 17, Y(Z_WALL_TOP + 0.15), 34, Y(Z_FLOOR_CH) - Y(Z_WALL_TOP + 0.15), fill="none", stroke="#444", sw=1.5))
    b.append(rect(xt - 13, Y(Z_WALL_TOP + 0.22), 26, 0.07 * S, fill="#444"))
    b.append(text(xt, Y(Z_WALL_TOP + 0.27), "Ultrasonic level sensor", 12, "middle"))
    b.append(text(xt, Y(Z_WALL_TOP + 0.38), "Stilling well Ø100–150 mm", 12, "middle"))
    # weir plate
    b.append(rect(X(X_WEIR) - 3, Y(Z_NOTCH_TOP + 0.1), 4, Y(Z_FLOOR_CH) - Y(Z_NOTCH_TOP + 0.1), fill="#555"))
    b.append(text(X(X_WEIR) + 8, Y(Z_NOTCH_TOP + 0.13), "แผ่นเวียร์ SS304 หนา 6 mm", 11))
    # outlet pipe
    b.append(rect(X(X_END), Y(Z_FLOOR_OUT + 0.15), WALL * S + 40, 0.15 * S, fill="#bbb"))
    b.append(text(X(X_END + WALL) + 2, Y(Z_FLOOR_OUT + 0.20), "ท่อน้ำออก (ไหลอิสระ)", 11))
    # elevations
    for z, name in [(Z_WALL_TOP, "สันกำแพง"), (Z_NOTCH_TOP, "ขอบบนร่อง V"), (Z_HMAX, "น้ำสูงสุด (ปั๊มหยุด)"),
                    (Z_VERTEX, "ยอด V (h = 0)"), (Z_FLOOR_CH, "พื้นรางนำน้ำ")]:
        c = "#c00" if z == Z_VERTEX else "#666"
        b.append(line(X(X_TAP) - 21, Y(z), X(X_WEIR) - 4, Y(z), c, 0.8, "3 2"))
        b.append(text(X(X_TAP) - 25, Y(z) + 4, f"{name} {z:+.3f}", 11, "end", "#c00" if z == Z_VERTEX else "#333"))
    b.append(text(X(-WALL) - 6, Y(Z_FLOOR_SUMP) + 4, f"พื้นบ่อปั๊ม {Z_FLOOR_SUMP:+.3f}", 11, "end"))
    b.append(text(X(X_END + WALL) + 6, Y(Z_FLOOR_OUT) + 20, f"พื้นบ่อน้ำออก {Z_FLOOR_OUT:+.3f}", 11))
    # dims
    b.append(line(X(X_TAP), Y(0.10), X(X_WEIR), Y(0.10), arrow=True))
    b.append(text((X(X_TAP) + X(X_WEIR)) / 2, Y(0.10) - 4, "0.65 (4–5·hmax)", 11, "middle"))
    xv = X(X_WEIR) - 14
    b.append(line(xv, Y(Z_VERTEX), xv, Y(Z_FLOOR_CH), arrow=True))
    b.append(text(xv - 4, Y(0.30), "P = 0.45", 12, "end"))
    yd = Y(Z_FLOOR_SUMP - 0.2) + 30
    for x1, x2, t in [(0, X_SPLASH, "0.45"), (X_SPLASH, X_SUMP_END, "0.95"), (X_SUMP_END, X_BAFFLE_IN, "0.40"),
                      (X_BAFFLE_IN, X_WEIR, "2.00 (รางนำน้ำตรง)"), (X_WEIR, X_END, "0.60")]:
        b.append(line(X(x1), yd, X(x2), yd, arrow=True))
        b.append(text((X(x1) + X(x2)) / 2, yd - 5, t, 12, "middle"))
    # zone labels
    b.append(text(X(0.22), Y(-0.85), "โซนน้ำเข้า", 12, "middle", weight="bold"))
    b.append(text(X(0.95), Y(0.12), "โซนปั๊ม (น้ำนิ่ง)", 12, "middle", weight="bold"))
    b.append(text(X(X_SPLASH + 0.05), Y(Z_WALL_TOP) - 24, "ผนังกันน้ำกระฉอก", 11, "middle", "#c00", "bold"))
    b.append(text(X(X_BAFFLE_IN), Y(Z_WALL_TOP) - 6, "แผ่นกันคลื่นรูพรุน", 11, "middle"))
    b.append(text(X(2.55), Y(0.28), "รางนำน้ำ (Approach channel)", 13, "middle", weight="bold"))
    b.append(text(X(X_WEIR + 0.38), Y(0.15), "บ่อน้ำออก", 12, "middle", weight="bold"))
    W, H = int(X(X_END + WALL) + 170), int(yd + 40)
    b.insert(0, text(W / 2, 30, "รูปตัดตามยาว A–A  (ระดับอ้างอิง: พื้นรางนำน้ำ ±0.000, หน่วย m)", 16, "middle", weight="bold"))
    b.insert(1, text(W / 2, 50, "แสดงระดับน้ำขณะปั๊มเดิน: Qin 10 L/s, สูบ recycle 5 L/s, ผ่านเวียร์ 5 L/s", 12, "middle", "#555"))
    return svg(W, H, "".join(b), "รูปตัดตามยาว V-notch weir และบ่อปั๊ม")


# ---------------------------------------------------------------- Plan
def plan():
    S = 135
    X = lambda x: 130 + (x + WALL) * S
    Y = lambda y: 90 + (y + WALL) * S   # y = 0 ที่ผิวในผนังบ่อปั๊ม (ด้านบน)
    b = []
    off = (B_SUMP - B_CH) / 2
    water = "#deebf7"
    b.append(rect(X(0), Y(0), X(X_SUMP_END) - X(0), B_SUMP * S, fill=water, stroke="none"))
    b.append(rect(X(X_SUMP_END), Y(off), X(X_WEIR) - X(X_SUMP_END), B_CH * S, fill=water, stroke="none"))
    b.append(rect(X(X_WEIR), Y(0), X(X_END) - X(X_WEIR), B_SUMP * S, fill=water, stroke="none"))
    # walls: sump
    b.append(rect(X(-WALL), Y(-WALL), X(X_SUMP_END) - X(-WALL), WALL * S))
    b.append(rect(X(-WALL), Y(B_SUMP), X(X_SUMP_END) - X(-WALL), WALL * S))
    b.append(rect(X(-WALL), Y(0), WALL * S, B_SUMP * S))
    # walls: channel
    b.append(rect(X(X_SUMP_END), Y(-WALL), X(X_WEIR) - X(X_SUMP_END), (off + WALL) * S))
    b.append(rect(X(X_SUMP_END), Y(off + B_CH), X(X_WEIR) - X(X_SUMP_END), (off + WALL) * S))
    # walls: outlet chamber
    b.append(rect(X(X_WEIR), Y(-WALL), X(X_END + WALL) - X(X_WEIR), WALL * S))
    b.append(rect(X(X_WEIR), Y(B_SUMP), X(X_END + WALL) - X(X_WEIR), WALL * S))
    b.append(rect(X(X_END), Y(0), WALL * S, B_SUMP * S))
    # inlet pipe + dip pipe
    b.append(rect(X(-WALL) - 40, Y(0.6) - 8, 40 + (WALL + 0.18) * S, 16, fill="#bbb"))
    b.append(f"<circle cx='{X(0.18):.1f}' cy='{Y(0.6):.1f}' r='10' fill='#bbb' stroke='#333'/>")
    b.append(text(X(-WALL) - 42, Y(0.6) - 12, "ท่อน้ำเข้า", 12))
    # splash baffle
    b.append(rect(X(X_SPLASH), Y(0), 0.10 * S, B_SUMP * S, fill="#f4cccc", stroke="#c00"))
    b.append(text(X(X_SPLASH + 0.05), Y(-WALL) - 8, "ผนังกันน้ำกระฉอก", 11, "middle", "#c00", "bold"))
    b.append(f"<rect x='{X(0):.1f}' y='{Y(0):.1f}' width='{X_SPLASH*S:.1f}' height='{B_SUMP*S:.1f}' fill='none' stroke='#666' stroke-dasharray='5 3'/>")
    b.append(text(X(0.22), Y(B_SUMP) - 8, "ฝาปิด", 11, "middle", "#555"))
    # pump
    b.append(f"<circle cx='{X(X_PUMP):.1f}' cy='{Y(0.6):.1f}' r='{0.16*S:.1f}' fill='#f2a541' stroke='#333'/>")
    b.append(text(X(X_PUMP), Y(0.6) + 5, "P", 14, "middle", weight="bold"))
    b.append(text(X(X_PUMP), Y(0.88), "ปั๊มจุ่ม", 11, "middle"))
    b.append(text(X(X_PUMP), Y(0.88) + 14, "(+ ตัวสำรอง)", 11, "middle"))
    b.append(f"<path d='M{X(X_PUMP)+0.16*S:.1f},{Y(0.6):.1f} H{X(1.25):.1f} V{Y(-WALL)-30:.1f}' fill='none' stroke='#2c7a2c' stroke-width='5'/>")
    b.append(text(X(1.25) + 6, Y(-WALL) - 22, "→ Water recycle", 11, color="#2c7a2c"))
    b.append(f"<circle cx='{X(0.65):.1f}' cy='{Y(1.08):.1f}' r='6' fill='#2c7a2c'/>")
    b.append(text(X(0.65) + 9, Y(1.08) + 4, "ลูกลอย", 11))
    # perforated baffle, weir plate
    b.append(line(X(X_BAFFLE_IN), Y(off), X(X_BAFFLE_IN), Y(off + B_CH), "#555", 4, "6 4"))
    b.append(text(X(X_BAFFLE_IN), Y(B_SUMP + WALL) + 16, "แผ่นกันคลื่นรูพรุน", 11, "middle"))
    b.append(rect(X(X_WEIR) - 2, Y(off - 0.05), 5, (B_CH + 0.1) * S, fill="#333"))
    b.append(text(X(X_WEIR), Y(B_SUMP + WALL) + 16, "แผ่นเวียร์", 11, "middle"))
    # stilling well
    b.append(f"<circle cx='{X(X_TAP):.1f}' cy='{Y(off) - 0.13 * S:.1f}' r='{0.09*S:.1f}' fill='white' stroke='#333' stroke-width='1.5'/>")
    b.append(line(X(X_TAP), Y(off) - 0.04 * S, X(X_TAP), Y(off) + 4, "#333", 2))
    b.append(text(X(X_TAP), Y(off) - 0.30 * S, "Stilling well + Level sensor", 12, "middle"))
    # outlet pipe
    b.append(rect(X(X_END), Y(0.6) - 10, WALL * S + 40, 20, fill="#bbb"))
    b.append(text(X(X_END + WALL) + 44, Y(0.6) + 4, "ท่อน้ำออก", 12))
    # flow arrows
    for x, y in ((0.65, 0.35), (2.2, 0.45), (2.9, 0.45), (4.0, 0.35)):
        b.append(flow_arrow(X(x), Y(y), 35))
    # section line
    ya = Y(0.6)
    b.append(line(X(-WALL) - 30, ya, X(X_END + WALL) + 30, ya, "#c00", 1, "12 4 2 4"))
    b.append(text(X(-WALL) - 34, ya + 18, "A", 14, "end", "#c00", "bold"))
    b.append(text(X(X_END + WALL) + 34, ya + 18, "A", 14, "start", "#c00", "bold"))
    # dims
    yd = Y(B_SUMP + WALL) + 50
    for x1, x2, t in [(-WALL, X_SUMP_END, "1.60"), (X_SUMP_END, X_WEIR, "2.40"), (X_WEIR, X_END + WALL, "0.80")]:
        b.append(line(X(x1), yd, X(x2), yd, arrow=True))
        b.append(text((X(x1) + X(x2)) / 2, yd - 5, t, 12, "middle"))
    b.append(line(X(X_TAP), Y(off) - 0.42 * S, X(X_WEIR), Y(off) - 0.42 * S, arrow=True))
    b.append(text((X(X_TAP) + X(X_WEIR)) / 2, Y(off) - 0.42 * S - 5, "0.65", 12, "middle"))
    xd = X(-WALL) - 55
    b.append(line(xd, Y(0), xd, Y(B_SUMP), arrow=True))
    b.append(text(xd - 4, Y(B_SUMP) + 16, "1.20 (ภายใน)", 12, "middle"))
    b.append(line(X(3.4), Y(off), X(3.4), Y(off + B_CH), arrow=True))
    b.append(text(X(3.4) + 6, Y(off + B_CH) - 8, "B = 0.90", 12))
    b.append(text(X(0.95), Y(0.15), "บ่อปั๊ม", 12, "middle", weight="bold"))
    b.append(text(X(2.6), Y(off + B_CH) - 10, "รางนำน้ำ", 12, "middle"))
    W, H = int(X(X_END + WALL) + 120), int(yd + 30)
    b.insert(0, text(W / 2, 30, "แปลน (หน่วย m, ผนัง คสล. หนา 0.20)", 16, "middle", weight="bold"))
    return svg(W, H, "".join(b), "แปลน V-notch weir และบ่อปั๊ม")


# ---------------------------------------------------------------- Plate detail
def plate():
    S = 380
    X = lambda x: 60 + (x + 0.55) * S       # x = 0 at notch centre
    Y = lambda z: 70 + (0.85 - z) * S       # z from channel floor
    b = []
    # plate outline 1.10 wide (embedded 0.10 into wall slot each side), height to +0.80
    top = 0.80
    plate_pts = [(-0.55, top), (-0.25, top), (0, Z_VERTEX), (0.25, top), (0.55, top), (0.55, 0.0), (-0.55, 0.0)]
    b.append(poly([(X(x), Y(z)) for x, z in plate_pts], "#cfd8dc", "#333", 1.5))
    for xs in (-0.55, 0.45):
        b.append(rect(X(xs), Y(top), 0.10 * S, top * S, fill="url(#rc)", stroke="#333", sw=0.8))
    b.append(text(X(-0.50), Y(0.40), "ฝังร่อง", 11, "middle"))
    b.append(text(X(-0.50), Y(0.40) + 14, "ในผนัง", 11, "middle"))
    # bolts / gasket
    for xb in (-0.40, -0.20, 0.20, 0.40):
        b.append(f"<circle cx='{X(xb):.1f}' cy='{Y(0.08):.1f}' r='5' fill='white' stroke='#333'/>")
    # water at hmax
    hz = Z_HMAX
    b.append(poly([(X(-(hz - Z_VERTEX)), Y(hz)), (X(0), Y(Z_VERTEX)), (X(hz - Z_VERTEX), Y(hz))], "#9ecae1", "#3182bd", 1, 0.9))
    # dims
    b.append(line(X(-0.25), Y(top) - 25, X(0.25), Y(top) - 25, arrow=True))
    b.append(text(X(0), Y(top) - 31, "0.50", 13, "middle"))
    b.append(line(X(0.30), Y(top), X(0.30), Y(Z_VERTEX), arrow=True))
    b.append(text(X(0.30) + 6, Y((top + Z_VERTEX) / 2), "ลึกร่อง 0.25", 12))
    b.append(line(X(0.30), Y(Z_VERTEX), X(0.30), Y(0), arrow=True))
    b.append(text(X(0.30) + 6, Y(Z_VERTEX / 2), "P = 0.45", 12))
    b.append(line(X(-0.45), Y(-0.05), X(0.45), Y(-0.05), arrow=True))
    b.append(text(X(0), Y(-0.05) + 16, "B = 0.90 (ช่องเปิดราง)", 12, "middle"))
    b.append(line(X(-0.55), Y(-0.15), X(0.55), Y(-0.15), arrow=True))
    b.append(text(X(0), Y(-0.15) + 16, "กว้างแผ่น 1.10", 12, "middle"))
    b.append(line(X(-0.24), Y(Z_VERTEX), X(-0.01), Y(Z_VERTEX), "#3182bd", 0.8, "3 2"))
    b.append(line(X(-0.22), Y(hz), X(-0.22), Y(Z_VERTEX), "#3182bd", 1.2, arrow=True))
    b.append(text(X(-0.23), Y((hz + Z_VERTEX) / 2) + 4, "hmax ≈ 0.139", 12, "end", "#1f5f8b"))
    b.append(f"<path d='M{X(-0.06):.1f},{Y(Z_VERTEX+0.06):.1f} Q{X(0):.1f},{Y(Z_VERTEX+0.10):.1f} {X(0.06):.1f},{Y(Z_VERTEX+0.06):.1f}' fill='none' stroke='#c00'/>")
    b.append(text(X(0), Y(Z_VERTEX + 0.11), "90° ± 0.1°", 13, "middle", "#c00", "bold"))
    # edge detail (inset)
    ox, oy, k = X(0.85), Y(0.70), 9  # 1 mm = 9 px
    t, land = 6, 1.5
    pts = [(ox, oy), (ox + land * k, oy), (ox + t * k, oy + (t - land) * k), (ox + t * k, oy + 40 * k * 0.5), (ox, oy + 40 * k * 0.5)]
    b.append(poly(pts, "#cfd8dc", "#333", 1.5))
    b.append(text(ox + 3 * k, oy - 46, "รายละเอียดขอบร่อง V", 13, "middle", weight="bold"))
    b.append(text(ox + 3 * k, oy - 30, "(ตัดตั้งฉากกับขอบ)", 11, "middle"))
    b.append(line(ox, oy - 12, ox + land * k, oy - 12, arrow=True))
    b.append(text(ox - 4, oy - 16, "1–2 mm", 11, "end"))
    b.append(line(ox, oy + 190, ox + t * k, oy + 190, arrow=True))
    b.append(text(ox + 3 * k, oy + 206, "t = 6 mm", 11, "middle"))
    b.append(text(ox - 6, oy + 90, "เหนือน้ำ ←", 11, "end", "#1f5f8b"))
    b.append(text(ox + t * k + 6, oy + 90, "→ ท้ายน้ำ", 11, "start", "#1f5f8b"))
    b.append(text(ox + t * k + 6, oy + 30, "ลบมุม 45°", 11))
    b.append(text(ox + t * k + 6, oy + 44, "ด้านท้ายน้ำ", 11))
    W, H = int(ox + 180), int(Y(-0.15) + 40)
    b.insert(0, text(W / 2, 30, "รายละเอียดแผ่นเวียร์ V-notch 90° (มองจากด้านเหนือน้ำ, หน่วย m)", 16, "middle", weight="bold"))
    return svg(W, H, "".join(b), "แผ่นเวียร์ V-notch 90°")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, fn in [("section", section), ("plan", plan), ("weir_plate", plate)]:
        with open(os.path.join(OUT, f"{name}.svg"), "w", encoding="utf-8") as f:
            f.write(fn())
        print(f"{OUT}/{name}.svg")
