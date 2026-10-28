#!/usr/bin/env python3
"""สร้างแบบ SVG: รูปตัดตามยาว, แปลน และรายละเอียดแผ่นเวียร์ V-notch 90°  (หน่วย m)"""
import os

OUT = "drawings"
FONT = "font-family='Sarabun, Tahoma, sans-serif'"

# ---- ค่าออกแบบ (ตรงกับ weir_design.py ค่า default) ----
WALL = 0.20
X_BAFFLE_IN = 0.60      # แผ่นกันคลื่นรูพรุน
X_WEIR = 2.60           # แผ่นเวียร์
X_TAP = X_WEIR - 0.65   # จุดวัดระดับ (≈4.7·hmax)
X_BAFFLE_DS = 3.20      # ผนังกั้นใต้น้ำ (under-flow baffle)
X_END = 4.40            # ผนังท้ายบ่อปั๊ม
Z_FLOOR_CH = 0.0
Z_FLOOR_SUMP = -1.00
Z_VERTEX = 0.45
Z_NOTCH_TOP = 0.70
Z_WALL_TOP = 0.90
Z_HMAX = 0.589
Z_OVERFLOW = 0.39
Z_ALARM = 0.33
Z_START = 0.25
Z_STOP = -0.40
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


# ---------------------------------------------------------------- Section
def section():
    S = 160
    X0, ZTOP = 70, 1.35
    X = lambda x: X0 + (x + WALL) * S
    Y = lambda z: 70 + (ZTOP - z) * S
    b = []
    water = "#9ecae1"
    # water: approach channel at Qmax, sump at START level
    b.append(rect(X(0), Y(Z_HMAX), X(X_WEIR) - X(0), Y(Z_FLOOR_CH) - Y(Z_HMAX), fill=water, stroke="none"))
    b.append(rect(X(X_WEIR), Y(Z_START), X(X_END) - X(X_WEIR), Y(Z_FLOOR_SUMP) - Y(Z_START), fill=water, stroke="none"))
    # nappe
    xw = X(X_WEIR)
    b.append(f"<path d='M{xw:.1f},{Y(Z_HMAX-0.01):.1f} Q{xw+55:.1f},{Y(0.55):.1f} {xw+70:.1f},{Y(Z_START):.1f} "
             f"L{xw+45:.1f},{Y(Z_START):.1f} Q{xw+30:.1f},{Y(0.42):.1f} {xw:.1f},{Y(Z_VERTEX):.1f} z' fill='{water}' stroke='#3182bd'/>")
    # concrete: floor slabs and walls
    b.append(rect(X(-WALL), Y(Z_FLOOR_CH), X(X_WEIR) - X(-WALL), 0.2 * S))           # floor channel
    b.append(rect(X(X_WEIR), Y(Z_FLOOR_SUMP), X(X_END + WALL) - X(X_WEIR), 0.2 * S))  # floor sump
    b.append(rect(X(-WALL), Y(Z_WALL_TOP), WALL * S, Y(-0.2) - Y(Z_WALL_TOP)))       # upstream wall
    b.append(rect(X(X_END), Y(Z_WALL_TOP), WALL * S, Y(Z_FLOOR_SUMP - 0.2) - Y(Z_WALL_TOP)))  # end wall
    b.append(rect(X(X_WEIR - 0.2), Y(Z_FLOOR_CH), 0.2 * S, Y(Z_FLOOR_SUMP) - Y(Z_FLOOR_CH)))  # step wall under weir
    # weir plate (SS304)
    b.append(rect(X(X_WEIR) - 3, Y(Z_NOTCH_TOP + 0.1), 4, Y(Z_FLOOR_CH) - Y(Z_NOTCH_TOP + 0.1), fill="#555"))
    b.append(line(X(X_WEIR) - 25, Y(Z_VERTEX), X(X_WEIR) + 25, Y(Z_VERTEX), "#c00", 1.2, "4 3"))
    # perforated baffle
    for z in [i / 10 for i in range(0, 8)]:
        b.append(rect(X(X_BAFFLE_IN) - 2, Y(z + 0.08), 4, 0.06 * S, fill="#666", stroke="none"))
    # inlet pipe
    b.append(rect(X(-WALL) - 40, Y(0.55), 40 + WALL * S, 0.12 * S, fill="#bbb"))
    b.append(text(X(-WALL) - 40, Y(0.60), "ท่อน้ำเข้า", 12))
    # under-flow baffle
    b.append(rect(X(X_BAFFLE_DS), Y(Z_WALL_TOP), 0.12 * S, Y(-0.70) - Y(Z_WALL_TOP)))
    # stilling well + level sensor
    xt = X(X_TAP)
    b.append(rect(xt - 18, Y(Z_WALL_TOP + 0.15), 36, Y(Z_FLOOR_CH) - Y(Z_WALL_TOP + 0.15), fill="none", stroke="#444", sw=1.5))
    b.append(rect(xt - 14, Y(Z_WALL_TOP + 0.22), 28, 0.07 * S, fill="#444"))
    b.append(text(xt, Y(Z_WALL_TOP + 0.27), "Ultrasonic level sensor", 12, "middle"))
    b.append(text(xt, Y(Z_WALL_TOP + 0.38), "Stilling well Ø100–150 mm", 12, "middle"))
    # submersible pump
    xp = X(3.85)
    b.append(rect(xp - 22, Y(Z_FLOOR_SUMP + 0.55), 44, 0.55 * S, fill="#f2a541"))
    b.append(rect(xp - 30, Y(Z_FLOOR_SUMP + 0.06), 60, 0.06 * S, fill="#777"))
    b.append(f"<path d='M{xp+22:.1f},{Y(-0.65):.1f} H{X(4.15):.1f} V{Y(Z_WALL_TOP+0.25):.1f} H{X(X_END+WALL)+40:.1f}' "
             f"fill='none' stroke='#2c7a2c' stroke-width='7'/>")
    b.append(text(X(4.15) + 8, Y(Z_WALL_TOP + 0.30), "ท่อส่งน้ำ → Recycle tank", 12, color="#2c7a2c"))
    b.append(text(X(4.15) + 8, Y(Z_WALL_TOP + 0.42), "(Check valve + Gate valve)", 11, color="#2c7a2c"))
    b.append(text(xp - 28, Y(Z_FLOOR_SUMP + 0.30), "ปั๊มจุ่ม", 12, "end", weight="bold"))
    b.append(line(X(3.99), Y(Z_FLOOR_SUMP + 0.10), X(3.99), Y(Z_WALL_TOP + 0.05), "#777", 1, "2 2"))
    b.append(text(X(3.99), Y(Z_WALL_TOP + 0.08), "Guide rail / โซ่ยก", 11, "end", "#555"))
    # overflow pipe
    b.append(rect(X(X_END), Y(Z_OVERFLOW + 0.05), WALL * S + 40, 0.10 * S, fill="#bbb"))
    b.append(text(X(X_END + WALL) + 2, Y(Z_OVERFLOW + 0.09), f"Overflow {Z_OVERFLOW:+.3f}", 11))
    # level lines in sump
    for z, name, c in [(Z_OVERFLOW, "", "#c00"), (Z_ALARM, "High alarm", "#e6550d"),
                       (Z_START, "START", "#2c7a2c"), (Z_STOP, "STOP", "#2c7a2c")]:
        b.append(line(X(X_BAFFLE_DS + 0.15), Y(z), X(X_END), Y(z), c, 1, "6 3"))
        if name:
            b.append(text(X(X_BAFFLE_DS + 0.15), Y(z) + 11, f"{name} {z:+.3f}", 10, "start", c))
    # elevations on left
    for z, name in [(Z_WALL_TOP, "สันกำแพง"), (Z_NOTCH_TOP, "ขอบบนร่อง V"), (Z_HMAX, "น้ำสูงสุด (Qmax)"),
                    (Z_VERTEX, "ยอด V (h = 0)"), (Z_FLOOR_CH, "พื้นรางนำน้ำ"), (Z_FLOOR_SUMP, "พื้นบ่อปั๊ม")]:
        b.append(line(X(X_TAP) - 22, Y(z), X(X_WEIR) - 4, Y(z), "#c00" if z == Z_VERTEX else "#666", 0.8, "3 2"))
        b.append(text(X(X_TAP) - 26, Y(z) + 4, f"{name} {z:+.3f}", 11, "end", "#c00" if z == Z_VERTEX else "#333"))
    # dims
    yd = Y(Z_FLOOR_SUMP - 0.2) + 30
    for x1, x2, t in [(0, X_BAFFLE_IN, "0.60"), (X_BAFFLE_IN, X_WEIR, "2.00 (รางนำน้ำตรง)"),
                      (X_WEIR, X_BAFFLE_DS, "0.60"), (X_BAFFLE_DS, X_END, "1.20")]:
        b.append(line(X(x1), yd, X(x2), yd, arrow=True))
        b.append(text((X(x1) + X(x2)) / 2, yd - 5, t, 12, "middle"))
    b.append(line(X(X_TAP), Y(0.10), X(X_WEIR), Y(0.10), arrow=True))
    b.append(text((X(X_TAP) + X(X_WEIR)) / 2, Y(0.10) - 4, "0.65 (4–5·hmax)", 11, "middle"))
    xv = X(X_WEIR) - 14
    b.append(line(xv, Y(Z_VERTEX), xv, Y(Z_FLOOR_CH), arrow=True))
    b.append(text(xv - 4, Y(0.25), "P = 0.45", 12, "end"))
    # zone labels
    b.append(text(X(0.3), Y(0.08), "บ่อพักน้ำเข้า", 12, "middle", weight="bold"))
    b.append(text(X(1.25), Y(0.30), "รางนำน้ำ (Approach channel)", 13, "middle", weight="bold"))
    b.append(text(X(2.9), Y(-0.85), "โซนน้ำตก", 12, "middle", weight="bold"))
    b.append(text(X(2.9), Y(-0.85) + 15, "(ไล่ฟองอากาศ)", 11, "middle"))
    b.append(text(X(X_BAFFLE_DS) + 10, Y(-0.78), "ช่องลอดใต้ 0.30", 10, "middle"))
    b.append(text(X(X_BAFFLE_IN), Y(Z_WALL_TOP) - 6, "แผ่นกันคลื่นรูพรุน", 11, "middle"))
    b.append(text(X(X_WEIR) + 8, Y(Z_NOTCH_TOP + 0.13), "แผ่นเวียร์ SS304 หนา 6 mm", 11))
    W, H = int(X(X_END + WALL) + 200), int(yd + 50)
    b.insert(0, text(W / 2, 30, "รูปตัดตามยาว A–A  (ระดับอ้างอิง: พื้นรางนำน้ำ ±0.000, หน่วย m)", 16, "middle", weight="bold"))
    return svg(W, H, "".join(b), "รูปตัดตามยาว V-notch weir และบ่อปั๊ม")


# ---------------------------------------------------------------- Plan
def plan():
    S = 140
    X = lambda x: 70 + (x + WALL) * S
    Y = lambda y: 80 + (y + WALL) * S   # y = 0 at inside face of sump wall (top)
    b = []
    off = (B_SUMP - B_CH) / 2
    water = "#deebf7"
    b.append(rect(X(0), Y(off), X(X_WEIR) - X(0), B_CH * S, fill=water, stroke="none"))
    b.append(rect(X(X_WEIR), Y(0), X(X_END) - X(X_WEIR), B_SUMP * S, fill=water, stroke="none"))
    # walls
    b.append(rect(X(-WALL), Y(off - WALL), X(X_WEIR) - X(-WALL), WALL * S))
    b.append(rect(X(-WALL), Y(off + B_CH), X(X_WEIR) - X(-WALL), WALL * S))
    b.append(rect(X(-WALL), Y(off), WALL * S, B_CH * S))
    b.append(rect(X(X_WEIR - 0.0), Y(-WALL), X(X_END + WALL) - X(X_WEIR), WALL * S))
    b.append(rect(X(X_WEIR - 0.0), Y(B_SUMP), X(X_END + WALL) - X(X_WEIR), WALL * S))
    b.append(rect(X(X_END), Y(0), WALL * S, B_SUMP * S))
    b.append(rect(X(X_WEIR - 0.2), Y(-WALL), 0.2 * S, (off + WALL) * S - 0))
    b.append(rect(X(X_WEIR - 0.2), Y(off + B_CH), 0.2 * S, (off + WALL) * S))
    # weir plate, baffles
    b.append(rect(X(X_WEIR) - 2, Y(off - 0.05), 5, (B_CH + 0.1) * S, fill="#333"))
    b.append(line(X(X_BAFFLE_IN), Y(off), X(X_BAFFLE_IN), Y(off + B_CH), "#555", 4, "6 4"))
    b.append(rect(X(X_BAFFLE_DS), Y(0), 0.12 * S, B_SUMP * S))
    # stilling well
    b.append(f"<circle cx='{X(X_TAP):.1f}' cy='{Y(off) - 0.13 * S:.1f}' r='{0.09*S:.1f}' fill='white' stroke='#333' stroke-width='1.5'/>")
    b.append(line(X(X_TAP), Y(off) - 0.04 * S, X(X_TAP), Y(off) + 4, "#333", 2))
    b.append(text(X(X_TAP), Y(off) - 0.30 * S, "Stilling well + Level sensor", 12, "middle"))
    # pump
    b.append(f"<circle cx='{X(3.85):.1f}' cy='{Y(0.45):.1f}' r='{0.17*S:.1f}' fill='#f2a541' stroke='#333'/>")
    b.append(text(X(3.85), Y(0.45) + 5, "P", 14, "middle", weight="bold"))
    b.append(text(X(3.85), Y(0.80), "ปั๊มจุ่ม", 11, "middle"))
    b.append(text(X(3.85), Y(0.80) + 14, "(+ ตัวสำรอง ถ้ามี)", 11, "middle"))
    b.append(text(X(X_WEIR) + 6, Y(B_SUMP) - 8, "แผ่นเวียร์", 11))
    b.append(text(X(X_BAFFLE_DS + 0.06), Y(B_SUMP + WALL) + 16, "ผนังกั้นใต้น้ำ", 11, "middle"))
    b.append(text(X(X_BAFFLE_IN), Y(off + B_CH + WALL) + 16, "แผ่นกันคลื่นรูพรุน", 11, "middle"))
    b.append(f"<circle cx='{X(4.15):.1f}' cy='{Y(0.25):.1f}' r='7' fill='none' stroke='#2c7a2c' stroke-width='3'/>")
    b.append(f"<circle cx='{X(3.45):.1f}' cy='{Y(1.05):.1f}' r='6' fill='#2c7a2c'/>")
    b.append(text(X(3.45) + 10, Y(1.05) + 4, "ลูกลอย", 11))
    # flow arrows
    for x in (0.25, 1.6, 2.9):
        yy = Y(off + B_CH / 2) if x < X_WEIR else Y(B_SUMP / 2)
        b.append(f"<line x1='{X(x):.1f}' y1='{yy:.1f}' x2='{X(x)+40:.1f}' y2='{yy:.1f}' stroke='#3182bd' stroke-width='2.5' marker-end='url(#a)'/>")
    # section line
    ya = Y(0.45)
    b.append(line(X(-WALL) - 30, ya, X(X_END + WALL) + 30, ya, "#c00", 1, "12 4 2 4"))
    b.append(text(X(-WALL) - 34, ya + 4, "A", 14, "end", "#c00", "bold"))
    b.append(text(X(X_END + WALL) + 34, ya + 4, "A", 14, "start", "#c00", "bold"))
    # dims
    yd = Y(B_SUMP + WALL) + 45
    for x1, x2, t in [(-WALL, X_WEIR, "2.80"), (X_WEIR, X_END + WALL, "2.00"), (X_TAP, X_WEIR, "0.65")]:
        y_ = yd if t != "0.65" else Y(off) - 0.42 * S
        b.append(line(X(x1), y_, X(x2), y_, arrow=True))
        b.append(text((X(x1) + X(x2)) / 2, y_ - 5, t, 12, "middle"))
    xd = X(X_END + WALL) + 25
    b.append(line(xd, Y(0), xd, Y(B_SUMP), arrow=True))
    b.append(text(xd + 6, Y(B_SUMP / 2) + 4, "1.20 (ภายใน)", 12))
    b.append(line(X(0.9), Y(off), X(0.9), Y(off + B_CH), arrow=True))
    b.append(text(X(0.9) + 6, Y(off + B_CH / 2) + 4, "B = 0.90", 12))
    b.append(text(X(1.6), Y(off + B_CH) - 10, "รางนำน้ำ", 12, "middle"))
    b.append(text(X(3.8), Y(0.15), "บ่อปั๊ม", 12, "middle", weight="bold"))
    W, H = int(xd + 120), int(yd + 30)
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
