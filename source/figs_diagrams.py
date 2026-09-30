"""Schematic diagrams drawn directly in SVG."""
import math
from svgplot import (wrap, t, arrow_px, INK, INK2, MUTED, GRID, AXIS, BLUE, ORANGE, AQUA, VIOLET,
                     RED, GREEN, BLUE_L, BLUE_D, Chart, ticks)
from calc import V, EX1, EX2

WATER_FILL = "#d6e8fa"
WATER_EDGE = "#6da7ec"
CONC = "#e9e7e1"
CONC_EDGE = "#a8a69e"
PIPE = "#5b6770"
SEW_FILL = "#e8dfcf"
SEW_EDGE = "#a38b5f"
GREEN_FILL = "#e3f3ea"
BOX = "#f4f6f8"
BROWN = "#8a6d3b"


def box(x, y, w, h, lines, fill=BOX, stroke=AXIS, size=11.5, weight=500, color=INK, rx=7, sw=1.2):
    out = [f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" rx="{rx}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"/>']
    if isinstance(lines, str):
        lines = [lines]
    n = len(lines)
    lh = size * 1.3
    y0 = y + h / 2 - (n - 1) * lh / 2 + size * 0.36
    for i, s in enumerate(lines):
        sz = size if i == 0 else size - 1.5
        col = color if i == 0 else INK2
        wt = weight if i == 0 else 400
        out.append(t(x + w / 2, y0 + i * lh, s, sz, "middle", col, wt))
    return "".join(out)


def pump(x, y, r=11, color=BLUE, direction=0, label=None, ldx=0, ldy=None, lsize=11):
    """Pump symbol: circle with triangle pointing in flow direction (deg, 0 = right, 90 = down)."""
    a = math.radians(direction)
    pts = []
    for ang, rr in ((0, 0.72), (140, 0.62), (-140, 0.62)):
        b = a + math.radians(ang)
        pts.append(f"{x + r * rr * math.cos(b):.1f},{y + r * rr * math.sin(b):.1f}")
    s = (f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r}" fill="#fff" stroke="{color}" stroke-width="2"/>'
         f'<polygon points="{" ".join(pts)}" fill="{color}"/>')
    if label:
        ly = y + r + 14 if ldy is None else y + ldy
        s += t(x + ldx, ly, label, lsize, "middle", INK, 600)
    return s


def flow(points, color=PIPE, width=2.2, head=True, dash=None):
    d = " ".join(f"{x:.1f},{y:.1f}" for x, y in points)
    da = f' stroke-dasharray="{dash}"' if dash else ""
    s = f'<polyline points="{d}" fill="none" stroke="{color}" stroke-width="{width}" stroke-linejoin="round"{da}/>'
    if head:
        (x0, y0), (x1, y1) = points[-2], points[-1]
        s += arrow_px(x0, y0, x1, y1, color, 0, head=8)
    return s


def dim_v(x, y0, y1, label, side="right", color=INK2, size=11, tick=6):
    s = arrow_px(x, y0, x, y1, color, 1.1, both=True, head=6)
    s += f'<line x1="{x - tick:.1f}" y1="{y0:.1f}" x2="{x + tick:.1f}" y2="{y0:.1f}" stroke="{color}" stroke-width="1"/>'
    s += f'<line x1="{x - tick:.1f}" y1="{y1:.1f}" x2="{x + tick:.1f}" y2="{y1:.1f}" stroke="{color}" stroke-width="1"/>'
    if label:
        ym = (y0 + y1) / 2 + 4
        if side == "right":
            s += t(x + 8, ym, label, size, "start", INK, 500)
        else:
            s += t(x - 8, ym, label, size, "end", INK, 500)
    return s


def water_lines(x0, x1, y, n=2):
    s = ""
    for i in range(n):
        xx = x0 + (x1 - x0) * (0.2 + 0.3 * i)
        s += f'<line x1="{xx:.1f}" y1="{y + 5 + 4 * i:.1f}" x2="{xx + 16:.1f}" y2="{y + 5 + 4 * i:.1f}" stroke="{WATER_EDGE}" stroke-width="1"/>'
    s += f'<polygon points="{x1 - 22:.1f},{y - 8:.1f} {x1 - 14:.1f},{y - 8:.1f} {x1 - 18:.1f},{y - 1:.1f}" fill="{WATER_EDGE}"/>'
    return s


def houses(x, y, n=3, gap=34):
    s = ""
    for i in range(n):
        hx = x + i * gap
        s += (f'<polygon points="{hx},{y - 2} {hx + 13},{y - 16} {hx + 26},{y - 2}" fill="#d9d6cc"/>'
              f'<rect x="{hx + 3}" y="{y - 2}" width="20" height="18" fill="#ebe8df" stroke="{CONC_EDGE}" stroke-width="0.8"/>')
    return s


# ---------------------------------------------------------------------------
def fig_wtp():
    W, H = 680, 330
    o = []
    y1 = 70
    o.append(f'<path d="M10,{y1 - 18} q20,-8 40,0 t40,0 v58 h-80 z" fill="{WATER_FILL}" stroke="{WATER_EDGE}"/>')
    o.append(t(50, y1 + 56, "แหล่งน้ำดิบ", 11.5, "middle", INK, 600))
    o.append(pump(122, y1 + 12))
    o.append(t(122, y1 - 22, "ปั๊มน้ำดิบ", 11, "middle", INK, 600))
    o.append(t(122, y1 - 9, "(intake)", 10, "middle", INK2))
    o.append(flow([(90, y1 + 12), (111, y1 + 12)], head=False))
    o.append(flow([(133, y1 + 12), (160, y1 + 12)]))
    bx = [("ถังกวนเร็ว", "สร้างตะกอน"), ("ถังกวนช้า", "รวมตะกอน"), ("ถังตกตะกอน", ""), ("ถังกรอง", "ทราย/แอนทราไซต์")]
    x = 162
    for a, b in bx:
        o.append(box(x, y1 - 12, 92, 48, [a, b] if b else [a], fill=GREEN_FILL, stroke="#9fd3b8"))
        o.append(flow([(x + 92, y1 + 12), (x + 106, y1 + 12)]))
        x += 108
    o.append(box(x, y1 - 12, 76, 48, ["ถังน้ำใส", "(clear well)"], fill=WATER_FILL, stroke=WATER_EDGE))
    cw = x + 38
    o.append(box(150, 150, 104, 36, ["ถังสารเคมี", "สารส้ม/PACl/คลอรีน"], size=11))
    o.append(pump(208, y1 + 60, r=9, color=VIOLET, direction=-90))
    o.append(flow([(208, 150), (208, y1 + 69)], VIOLET, 1.6, head=False))
    o.append(flow([(208, y1 + 51), (208, y1 + 37)], VIOLET, 1.6))
    o.append(t(222, y1 + 64, "ปั๊มจ่ายสารเคมี", 10.5, "start", INK, 600))
    sx = 162 + 2 * 108 + 46
    o.append(pump(sx, y1 + 60, r=9, color=BROWN, direction=90))
    o.append(flow([(sx, y1 + 36), (sx, y1 + 51)], BROWN, 1.6, head=False))
    o.append(flow([(sx, y1 + 69), (sx, y1 + 92)], BROWN, 1.6))
    o.append(t(sx + 14, y1 + 64, "ปั๊มตะกอน", 10.5, "start", INK, 600))
    o.append(t(sx, y1 + 106, "ไปลานตาก/เครื่องรีดตะกอน", 10, "middle", INK2))
    fx = 162 + 3 * 108 + 46
    o.append(pump(fx + 44, y1 + 60, r=9, color=AQUA, direction=180))
    o.append(flow([(cw - 18, y1 + 36), (cw - 18, y1 + 60), (fx + 53, y1 + 60)], AQUA, 1.6, head=False))
    o.append(flow([(fx + 35, y1 + 60), (fx, y1 + 60), (fx, y1 + 37)], AQUA, 1.6))
    o.append(t(fx + 40, y1 + 84, "ปั๊มน้ำล้างย้อน", 10.5, "middle", INK, 600))
    o.append(t(fx + 40, y1 + 97, "(backwash)", 10, "middle", INK2))
    y2 = 250
    hx = cw + 18
    o.append(flow([(hx, y1 + 36), (hx, y2 - 11)], PIPE, 2.2, head=False))
    o.append(pump(hx, y2, direction=180))
    o.append(t(hx - 4, y2 + 28, "ปั๊มส่งน้ำ", 11, "middle", INK, 600))
    o.append(t(hx - 4, y2 + 41, "(high lift)", 10, "middle", INK2))
    o.append(flow([(hx - 11, y2), (566, y2)]))
    o.append(t(598, y2 - 8, "ท่อส่งน้ำ", 10.5, "middle", INK2))
    o.append(box(470, y2 - 22, 94, 44, ["ถังเก็บน้ำ", "(ground reservoir)"], fill=WATER_FILL, stroke=WATER_EDGE))
    o.append(flow([(470, y2), (443, y2)], head=False))
    o.append(pump(432, y2, direction=180))
    o.append(t(432, y2 + 28, "ปั๊มเพิ่มแรงดัน", 11, "middle", INK, 600))
    o.append(t(432, y2 + 41, "(booster)", 10, "middle", INK2))
    o.append(flow([(421, y2), (330, y2)], head=False))
    tx = 330
    o.append(f'<rect x="{tx - 25}" y="{y2 - 70}" width="50" height="30" rx="4" fill="{WATER_FILL}" stroke="{WATER_EDGE}"/>')
    o.append(f'<line x1="{tx - 17}" y1="{y2 - 40}" x2="{tx - 21}" y2="{y2 + 22}" stroke="{AXIS}" stroke-width="2"/>'
             f'<line x1="{tx + 17}" y1="{y2 - 40}" x2="{tx + 21}" y2="{y2 + 22}" stroke="{AXIS}" stroke-width="2"/>')
    o.append(f'<line x1="{tx}" y1="{y2}" x2="{tx}" y2="{y2 - 40}" stroke="{PIPE}" stroke-width="2.2"/>')
    o.append(t(tx, y2 + 38, "หอถังสูง", 11, "middle", INK, 600))
    o.append(flow([(tx, y2), (150, y2)]))
    o.append(t(240, y2 - 8, "ระบบจ่ายน้ำ", 10.5, "middle", INK2))
    o.append(houses(40, y2))
    o.append(t(90, y2 + 38, "ผู้ใช้น้ำ", 11, "middle", INK, 600))
    return wrap(W, H, "".join(o))


# ---------------------------------------------------------------------------
def fig_wws():
    W, H = 680, 330
    o = []
    y = 80
    o.append(houses(10, y, gap=30))
    o.append(t(50, y + 34, "ชุมชน/อาคาร", 11.5, "middle", INK, 600))
    o.append(flow([(98, y + 8), (180, y + 40)], BROWN, 2.4))
    o.append(t(120, y + 52, "ท่อแรงโน้มถ่วง", 10.5, "middle", INK2))
    o.append(f'<rect x="182" y="{y + 10}" width="70" height="80" fill="{SEW_FILL}" stroke="{SEW_EDGE}"/>')
    o.append(pump(217, y + 70, r=10, color=BROWN, direction=-90))
    o.append(t(217, y + 108, "สถานีสูบน้ำเสีย", 11.5, "middle", INK, 600))
    o.append(t(217, y + 122, "(lift station)", 10.5, "middle", INK2))
    o.append(flow([(217, y + 60), (217, y - 10), (262, y - 40), (318, y - 40), (318, y - 18), (338, y - 18)], BROWN, 2.4))
    o.append(t(262, y - 48, "ท่อส่งแรงดัน (force main)", 10.5, "middle", INK2))
    o.append(f'<rect x="328" y="10" width="344" height="312" rx="10" fill="#fbfaf7" stroke="{AXIS}" stroke-dasharray="5 4"/>')
    o.append(t(500, 30, "โรงบำบัดน้ำเสีย (WWTP)", 12, "middle", INK, 700))
    o.append(box(340, y - 32, 80, 44, ["ตะแกรง/ดักกรวด", "screen & grit"], fill=SEW_FILL, stroke=SEW_EDGE, size=10.5))
    o.append(pump(441, y - 10, r=10, color=BROWN))
    o.append(flow([(420, y - 10), (431, y - 10)], BROWN, 2, head=False))
    o.append(flow([(451, y - 10), (464, y - 10)], BROWN, 2))
    o.append(t(441, y + 26, "ปั๊มน้ำเสียเข้าระบบ", 10.5, "middle", INK, 600))
    o.append(box(466, y - 32, 80, 44, ["ถังเติมอากาศ", "aeration"], fill=GREEN_FILL, stroke="#9fd3b8", size=10.5))
    o.append(flow([(546, y - 10), (566, y - 10)], BROWN, 2))
    o.append(box(568, y - 32, 80, 44, ["ถังตกตะกอน", "clarifier"], fill=GREEN_FILL, stroke="#9fd3b8", size=10.5))
    o.append(flow([(630, y - 32), (630, y - 44), (664, y - 44)], BLUE, 2))
    o.append(t(652, y - 50, "น้ำทิ้ง", 10.5, "middle", INK2))
    px, py = 608, y + 50
    o.append(flow([(px, y + 12), (px, py - 10)], BROWN, 2, head=False))
    o.append(pump(px, py, r=10, color=VIOLET, direction=180))
    o.append(flow([(px - 10, py), (506, py), (506, y + 13)], VIOLET, 1.8))
    o.append(t(556, py + 16, "RAS", 10.5, "middle", INK, 700))
    o.append(flow([(px, py + 10), (px, y + 130), (578, y + 130)], VIOLET, 1.8))
    o.append(t(px + 8, y + 104, "WAS", 10.5, "start", INK, 700))
    o.append(box(476, y + 110, 100, 40, ["ถังทำข้นตะกอน", "thickener"], fill=SEW_FILL, stroke=SEW_EDGE, size=10.5))
    o.append(pump(440, y + 130, r=10, color=BROWN, direction=90))
    o.append(flow([(476, y + 130), (450, y + 130)], BROWN, 1.8, head=False))
    o.append(flow([(440, y + 140), (440, y + 180)], BROWN, 1.8))
    o.append(t(428, y + 134, "ปั๊มตะกอน (PC)", 10.5, "end", INK, 600))
    o.append(box(340, y + 182, 106, 40, ["เครื่องรีดน้ำตะกอน", "dewatering"], fill=SEW_FILL, stroke=SEW_EDGE, size=10.5))
    o.append(pump(500, y + 202, r=9, color=VIOLET, direction=180))
    o.append(flow([(491, y + 202), (446, y + 202)], VIOLET, 1.5))
    o.append(t(514, y + 206, "ปั๊มโพลิเมอร์", 10.5, "start", INK, 600))
    o.append(t(10, 288, "สัญลักษณ์ ◯▶ = ปั๊ม (หัวลูกศรชี้ทิศการไหล)", 10.5, "start", INK2))
    o.append(t(10, 304, "RAS = ตะกอนย้อนกลับ · WAS = ตะกอนส่วนเกิน", 10.5, "start", INK2))
    o.append(t(10, 320, "PC = ปั๊มสกรูเยื้องศูนย์ (progressive cavity)", 10.5, "start", INK2))
    return wrap(W, H, "".join(o))


# ---------------------------------------------------------------------------
def fig_classify():
    W, H = 680, 330
    o = []

    def node(x, y, w, h, lines, fill, stroke, size=11.5):
        o.append(box(x, y, w, h, lines, fill=fill, stroke=stroke, size=size))

    def link(x0, y0, x1, y1):
        ym = (y0 + y1) / 2
        o.append(f'<path d="M{x0},{y0} V{ym} H{x1} V{y1}" fill="none" stroke="{AXIS}" stroke-width="1.4"/>')
    node(270, 8, 140, 34, ["ปั๊ม (Pumps)"], "#eef1f4", AXIS, 12.5)
    node(40, 70, 260, 44, ["ไดนามิก / โรโตไดนามิก", "เพิ่มพลังงานด้วยความเร็ว"], "#e7f0fb", BLUE_L)
    node(380, 70, 260, 44, ["แทนที่เชิงบวก (Positive displacement)", "ขังของเหลวเป็นก้อนแล้วดันไป"], "#f2eefb", "#b7aee6")
    link(340, 42, 170, 70)
    link(340, 42, 510, 70)
    kids = [(10, ["หอยโข่ง", "ไหลตามรัศมี"]), (106, ["ไหลผสม", "(mixed flow)"]), (202, ["ไหลตามแกน", "(axial/propeller)"])]
    for x, l in kids:
        node(x, 142, 90, 40, l, "#f4f8fd", BLUE_L, 11)
        link(170, 114, x + 45, 142)
    confs = ["ดูดปลาย (end-suction)", "เรือนแยก (split case)", "หลายใบพัด (multistage)", "เทอร์ไบน์แนวตั้ง (VTP)",
             "ปั๊มจุ่ม (submersible)", "ปั๊มบาดาล (borehole)", "ปั๊มดูดเองได้ (self-priming)"]
    yy = 200
    o.append(f'<rect x="10" y="{yy}" width="282" height="{(len(confs) + 1) // 2 * 16 + 30}" rx="7" fill="#fff" stroke="{GRID}"/>')
    o.append(t(20, yy + 16, "รูปแบบที่พบบ่อยในงานประปา/น้ำเสีย:", 11, "start", INK, 600))
    for i, c in enumerate(confs):
        col = i % 2
        row = i // 2
        o.append(t(24 + col * 140, yy + 34 + row * 16, "• " + c, 10.5, "start", INK2))
    pk = [(350, ["โรตารี (Rotary)"]), (520, ["ลูกสูบ (Reciprocating)"])]
    for x, l in pk:
        node(x, 142, 150, 34, l, "#f8f6fd", "#b7aee6", 11)
        link(510, 114, x + 75, 142)
    rot = ["สกรูเยื้องศูนย์ (PC pump)", "ใบพัดลอน (rotary lobe)", "ท่อบีบ (peristaltic)", "สกรูคู่ (twin screw)"]
    rec = ["ลูกสูบ/พลันเจอร์ (plunger)", "ไดอะแฟรม (metering)", "ไดอะแฟรมลม (AODD)"]
    for i, s in enumerate(rot):
        o.append(t(356, 196 + i * 16, "• " + s, 10.5, "start", INK2))
    for i, s in enumerate(rec):
        o.append(t(526, 196 + i * 16, "• " + s, 10.5, "start", INK2))
    o.append(box(350, 272, 320, 44, ["อื่น ๆ: สกรูอาร์คิมิดีส (screw pump), แอร์ลิฟต์ (air-lift),",
                                     "อีเจ็กเตอร์ (ejector), ระบบสุญญากาศ (vacuum sewer)"], fill="#fbfbf9", stroke=GRID, size=10.5, weight=400, color=INK2))
    return wrap(W, H, "".join(o))


# ---------------------------------------------------------------------------
def fig_centrifugal():
    W, H = 680, 350
    o = []
    cx, cy = 230, 205
    r0, r1 = 92, 138
    pts = []
    for i in range(0, 361, 4):
        a = math.pi + math.radians(i)
        r = r0 + (r1 - r0) * i / 360
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    top = cy - 175
    d = "M" + " L".join(f"{x:.1f},{y:.1f}" for x, y in pts)
    d += f" L{cx - r1:.1f},{top} L{cx - r0:.1f},{top} Z"
    o.append(f'<path d="{d}" fill="#eef3f9" stroke="{PIPE}" stroke-width="2.4" stroke-linejoin="round"/>')
    o.append(f'<circle cx="{cx}" cy="{cy}" r="84" fill="#fff" stroke="{GRID}"/>')
    for k in range(6):
        base = k * 60
        vp = []
        for j in range(0, 11):
            rr = 26 + 54 * j / 10
            ang = math.radians(base - 55 * j / 10)
            vp.append((cx + rr * math.cos(ang), cy + rr * math.sin(ang)))
        o.append('<polyline points="' + " ".join(f"{x:.1f},{y:.1f}" for x, y in vp) +
                 f'" fill="none" stroke="{BLUE}" stroke-width="4" stroke-linecap="round"/>')
    o.append(f'<circle cx="{cx}" cy="{cy}" r="80" fill="none" stroke="{BLUE}" stroke-width="1.2"/>')
    o.append(f'<circle cx="{cx}" cy="{cy}" r="24" fill="{WATER_FILL}" stroke="{WATER_EDGE}" stroke-width="1.5"/>')
    o.append(f'<circle cx="{cx}" cy="{cy}" r="7" fill="{PIPE}"/>')
    o.append(f'<path d="M{cx + 40},{cy - 60} A 72 72 0 0 1 {cx + 68},{cy - 22}" fill="none" stroke="{RED}" stroke-width="2.2"/>')
    o.append(arrow_px(cx + 62, cy - 34, cx + 68, cy - 22, RED, 0, head=9))
    for ang in (-20, 60, 140):
        a = math.radians(ang)
        o.append(arrow_px(cx + 86 * math.cos(a), cy + 86 * math.sin(a), cx + 104 * math.cos(a), cy + 104 * math.sin(a), BLUE_D, 1.6, head=7))
    o.append(arrow_px(cx - (r0 + r1) / 2, cy - 60, cx - (r0 + r1) / 2, top + 6, BLUE_D, 2.2, head=10))

    def lab(x0, y0, x1, y1, s1, s2=None):
        o.append(f'<line x1="{x0:.1f}" y1="{y0:.1f}" x2="{x1}" y2="{y1}" stroke="{MUTED}" stroke-width="1"/>')
        o.append(t(x1 + 6, y1 + 4, s1, 12, "start", INK, 600))
        if s2:
            o.append(t(x1 + 6, y1 + 20, s2, 10.5, "start", INK2))
    lab(cx - (r0 + r1) / 2 + 16, top + 30, 400, 44, "ทางออก (discharge) – น้ำความดันสูง")
    lab(cx + 14, cy + 8, 400, 120, "ตาดูด (eye) – น้ำเข้าตามแนวแกน", "ความดันต่ำที่สุดในปั๊ม → จุดเริ่มเกิดคาวิเทชัน")
    lab(cx + 56, cy + 36, 400, 184, "ใบพัด (impeller) – เพิ่มความเร็วให้น้ำ", "ใบโค้งถอยหลัง หมุนตามเข็มนาฬิกา (ลูกศรแดง)")
    lab(cx + 110, cy + 70, 400, 248, "เรือนก้นหอย (volute)", "หน้าตัดโตขึ้นเรื่อย ๆ เปลี่ยนความเร็วเป็นความดัน")
    lab(cx - r0 - 2, cy - 6, 400, 300, "ลิ้นแยกกระแส (cutwater/tongue)")
    o.append(t(20, 342, "ภาพตัดด้านหน้า (อย่างง่าย) ของปั๊มหอยโข่ง", 11, "start", INK2))
    return wrap(W, H, "".join(o))


# ---------------------------------------------------------------------------
def fig_ns_shapes():
    W, H = 680, 290
    o = []

    def panel(x0, title, sub, kind):
        o.append(f'<rect x="{x0}" y="10" width="210" height="196" rx="8" fill="#fbfbf9" stroke="{GRID}"/>')
        ax = x0 + 30
        o.append(f'<line x1="{ax - 12}" y1="180" x2="{x0 + 200}" y2="180" stroke="{MUTED}" stroke-dasharray="6 3 2 3"/>')
        o.append(t(x0 + 198, 196, "แกนเพลา", 10, "end", MUTED))
        if kind == "radial":
            hub = f"M{ax},180 L{ax + 40},180 Q{ax + 60},178 {ax + 62},150 L{ax + 64},46"
            shroud = f"M{ax},120 L{ax + 20},120 Q{ax + 36},118 {ax + 38},100 L{ax + 40},46"
            o.append(f'<path d="{hub} L{ax + 40},46 Q{ax + 38},100 {ax + 20},120 L{ax},120 Z" fill="{BLUE_L}" opacity="0.35"/>')
            o.append(f'<path d="{hub}" fill="none" stroke="{BLUE_D}" stroke-width="2.4"/>')
            o.append(f'<path d="{shroud}" fill="none" stroke="{BLUE_D}" stroke-width="2.4"/>')
            o.append(arrow_px(ax - 16, 150, ax + 22, 150, BLUE_D, 1.6))
            o.append(arrow_px(ax + 50, 90, ax + 52, 30, BLUE_D, 1.6))
        elif kind == "mixed":
            hub = f"M{ax},180 L{ax + 40},180 Q{ax + 80},176 {ax + 110},92"
            shroud = f"M{ax},124 L{ax + 20},124 Q{ax + 50},120 {ax + 70},72"
            o.append(f'<path d="{hub} L{ax + 70},72 Q{ax + 50},120 {ax + 20},124 L{ax},124 Z" fill="{BLUE_L}" opacity="0.35"/>')
            o.append(f'<path d="{hub}" fill="none" stroke="{BLUE_D}" stroke-width="2.4"/>')
            o.append(f'<path d="{shroud}" fill="none" stroke="{BLUE_D}" stroke-width="2.4"/>')
            o.append(arrow_px(ax - 16, 152, ax + 22, 152, BLUE_D, 1.6))
            o.append(arrow_px(ax + 88, 90, ax + 118, 48, BLUE_D, 1.6))
        else:
            o.append(f'<rect x="{ax + 20}" y="160" width="130" height="20" fill="{BLUE_L}" opacity="0.5"/>')
            o.append(f'<line x1="{ax}" y1="96" x2="{ax + 170}" y2="96" stroke="{PIPE}" stroke-width="2.4"/>')
            o.append(f'<path d="M{ax + 60},160 L{ax + 78},100 L{ax + 98},100 L{ax + 84},160 Z" fill="{BLUE}" opacity="0.8"/>')
            o.append(arrow_px(ax - 10, 128, ax + 40, 128, BLUE_D, 1.6))
            o.append(arrow_px(ax + 110, 128, ax + 165, 128, BLUE_D, 1.6))
        o.append(t(x0 + 105, 226, title, 12.5, "middle", INK, 700))
        o.append(t(x0 + 105, 244, sub, 11, "middle", INK2))
    panel(10, "ใบพัดไหลตามรัศมี (radial)", "nq ≈ 10–40 · เฮดสูง อัตราไหลต่ำ", "radial")
    panel(235, "ใบพัดไหลผสม (mixed flow)", "nq ≈ 40–160 · เฮดปานกลาง", "mixed")
    panel(460, "ใบพัดไหลตามแกน (axial)", "nq ≈ 160–400 · เฮดต่ำ อัตราไหลสูง", "axial")
    o.append(t(340, 276, "ภาพตัดตามแนวแกน (meridional section) · ความเร็วจำเพาะ nq เพิ่มจากซ้ายไปขวา", 11, "middle", INK2))
    return wrap(W, H, "".join(o))


# ---------------------------------------------------------------------------
def fig_impellers():
    W, H = 680, 250
    o = []
    items = [
        ("ใบพัดช่องปิด", "(closed channel)", ["η สูง 70–85%", "เสี่ยงผ้า/เศษเส้นใยพัน"], "channel"),
        ("ใบพัดวอร์เท็กซ์", "(vortex/recessed)", ["ของแข็งผ่านสะดวกมาก", "η ต่ำ 35–55%"], "vortex"),
        ("ใบพัดกึ่งเปิด", "(self-cleaning semi-open)", ["ไล่เส้นใยออกทางร่อง", "η ดี 70–80%"], "semi"),
        ("ใบพัดตัด/บด", "(chopper/grinder)", ["ตัดของแข็งให้เล็ก", "ใช้กับท่อเล็ก/LPS"], "grinder"),
        ("ใบพัดสกรูหอยโข่ง", "(screw centrifugal)", ["สูบตะกอน/ของแข็งเปราะ", "เฉือนต่ำ โค้งชัน"], "screw"),
    ]
    for i, (a, b, notes, kind) in enumerate(items):
        x0 = 8 + i * 134
        cx, cy = x0 + 62, 70
        o.append(f'<rect x="{x0}" y="6" width="126" height="236" rx="8" fill="#fbfbf9" stroke="{GRID}"/>')
        if kind == "channel":
            o.append(f'<circle cx="{cx}" cy="{cy}" r="46" fill="{BLUE_L}" fill-opacity="0.35" stroke="{BLUE_D}" stroke-width="2"/>')
            for k in (0, 180):
                a0 = math.radians(k)
                p = []
                for j in range(12):
                    rr = 12 + 34 * j / 11
                    an = a0 + math.radians(150 * j / 11)
                    p.append(f"{cx + rr * math.cos(an):.1f},{cy + rr * math.sin(an):.1f}")
                o.append(f'<polyline points="{" ".join(p)}" fill="none" stroke="{BLUE_D}" stroke-width="7" stroke-linecap="round"/>')
            o.append(f'<circle cx="{cx}" cy="{cy}" r="12" fill="#fff" stroke="{BLUE_D}" stroke-width="2"/>')
        elif kind == "vortex":
            o.append(f'<rect x="{cx - 48}" y="{cy - 44}" width="96" height="88" rx="6" fill="#eef3f9" stroke="{PIPE}" stroke-width="2"/>')
            o.append(f'<rect x="{cx - 44}" y="{cy - 44}" width="88" height="18" fill="{BLUE_L}" opacity="0.6"/>')
            for k in range(-3, 4):
                o.append(f'<line x1="{cx + k * 12}" y1="{cy - 44}" x2="{cx + k * 12}" y2="{cy - 28}" stroke="{BLUE_D}" stroke-width="3"/>')
            o.append(f'<path d="M{cx - 28},{cy + 8} a18 12 0 1 1 20 10" fill="none" stroke="{AQUA}" stroke-width="2"/>')
            o.append(f'<path d="M{cx + 8},{cy + 8} a18 12 0 1 1 20 10" fill="none" stroke="{AQUA}" stroke-width="2"/>')
            o.append(arrow_px(cx, cy + 58, cx, cy + 40, INK2, 1.4))
            o.append(t(cx, cy + 30, "ใบพัดหลบอยู่ด้านบน", 9.5, "middle", INK2))
        elif kind == "semi":
            o.append(f'<circle cx="{cx}" cy="{cy}" r="46" fill="#fff" stroke="{PIPE}" stroke-width="2"/>')
            for k in (0, 120, 240):
                a0 = math.radians(k)
                p = []
                for j in range(12):
                    rr = 10 + 36 * j / 11
                    an = a0 + math.radians(110 * j / 11)
                    p.append(f"{cx + rr * math.cos(an):.1f},{cy + rr * math.sin(an):.1f}")
                o.append(f'<polyline points="{" ".join(p)}" fill="none" stroke="{BLUE_D}" stroke-width="5" stroke-linecap="round"/>')
            o.append(f'<path d="M{cx - 8},{cy - 46} q10,20 30,24" fill="none" stroke="{RED}" stroke-width="2"/>')
            o.append(t(cx + 26, cy - 36, "ร่อง", 9.5, "start", INK2))
        elif kind == "grinder":
            o.append(f'<circle cx="{cx}" cy="{cy}" r="46" fill="#fff" stroke="{PIPE}" stroke-width="2"/>')
            o.append(f'<circle cx="{cx}" cy="{cy}" r="28" fill="#f3e6e6" stroke="{RED}" stroke-width="2"/>')
            for k in range(8):
                an = math.radians(k * 45)
                o.append(f'<line x1="{cx + 12 * math.cos(an):.1f}" y1="{cy + 12 * math.sin(an):.1f}" x2="{cx + 28 * math.cos(an):.1f}" y2="{cy + 28 * math.sin(an):.1f}" stroke="{RED}" stroke-width="2"/>')
            o.append(f'<path d="M{cx - 16},{cy - 4} l32,8 M{cx - 12},{cy + 10} l24,-18" stroke="{INK}" stroke-width="4" stroke-linecap="round"/>')
        else:
            o.append(f'<path d="M{cx - 40},{cy + 40} L{cx - 20},{cy - 40} L{cx + 20},{cy - 40} L{cx + 46},{cy + 40} Z" fill="#eef3f9" stroke="{PIPE}" stroke-width="2"/>')
            for j in range(4):
                yy = cy - 30 + j * 20
                o.append(f'<path d="M{cx - 30 + j * 5},{yy + 10} Q{cx},{yy - 6} {cx + 30 + j * 4},{yy + 14}" fill="none" stroke="{BLUE_D}" stroke-width="4"/>')
        o.append(t(cx, 142, a, 11.5, "middle", INK, 700))
        o.append(t(cx, 158, b, 10, "middle", INK2))
        for j, n in enumerate(notes):
            o.append(t(cx, 184 + j * 17, n, 10.5, "middle", INK2))
    return wrap(W, H, "".join(o))


# ---------------------------------------------------------------------------
def fig_tdh():
    W, H = 680, 380
    o = []

    def tank(x, y_top, w, h, wl):
        o.append(f'<path d="M{x},{y_top} V{y_top + h} H{x + w} V{y_top}" fill="none" stroke="{CONC_EDGE}" stroke-width="3"/>')
        o.append(f'<rect x="{x + 1.5}" y="{wl}" width="{w - 3}" height="{y_top + h - wl - 1.5}" fill="{WATER_FILL}"/>')
        o.append(f'<line x1="{x + 1.5}" y1="{wl}" x2="{x + w - 1.5}" y2="{wl}" stroke="{WATER_EDGE}" stroke-width="1.5"/>')
        o.append(water_lines(x, x + w, wl))

    for k, (title, lift) in enumerate((("(ก) ยกดูด (suction lift)", True), ("(ข) ดูดท่วม (flooded suction)", False))):
        x0 = k * 340
        o.append(t(x0 + 12, 18, title, 12, "start", INK, 700))
        cl = 250 if lift else 290
        if lift:
            tank(x0 + 14, 285, 80, 60, 300)
            swl = 300
        else:
            tank(x0 + 14, 180, 80, 150, 220)
            swl = 220
        tank(x0 + 236, 40, 80, 70, 60)
        dwl = 60
        px = x0 + 150
        o.append(f'<rect x="{px - 30}" y="{cl + 12}" width="60" height="8" fill="{CONC}" stroke="{CONC_EDGE}"/>')
        o.append(pump(px, cl, r=13, color=BLUE, direction=0))
        if lift:
            o.append(f'<polyline points="{x0 + 54},{335} {x0 + 54},{cl} {px - 13},{cl}" fill="none" stroke="{PIPE}" stroke-width="5" stroke-linejoin="round"/>')
        else:
            o.append(f'<polyline points="{x0 + 94},{cl} {px - 13},{cl}" fill="none" stroke="{PIPE}" stroke-width="5"/>')
        o.append(f'<polyline points="{px + 13},{cl} {px + 40},{cl} {px + 40},{28} {x0 + 276},{28} {x0 + 276},{44}" fill="none" stroke="{PIPE}" stroke-width="5" stroke-linejoin="round"/>')
        o.append(f'<line x1="{x0 + 8}" y1="{cl}" x2="{x0 + 330}" y2="{cl}" stroke="{MUTED}" stroke-width="1" stroke-dasharray="4 3"/>')
        o.append(t(x0 + 318, cl + 14, "ศูนย์กลางปั๊ม", 10, "end", MUTED))
        o.append(f'<line x1="{x0 + 110}" y1="{dwl}" x2="{x0 + 236}" y2="{dwl}" stroke="{MUTED}" stroke-width="1" stroke-dasharray="4 3"/>')
        o.append(dim_v(x0 + 120, dwl, cl, "", "left"))
        o.append(t(x0 + 112, 112, "เฮดสถิต", 10.5, "end", INK, 600))
        o.append(t(x0 + 112, 126, "ด้านส่ง", 10.5, "end", INK, 600))
        if lift:
            o.append(dim_v(x0 + 106, cl, swl, "ยกดูด (z_s)", "right"))
            o.append(dim_v(x0 + 330, dwl, swl, "", "left"))
            o.append(t(x0 + 324, 200, "เฮดสถิตรวม", 10.5, "end", INK, 700))
            o.append(t(x0 + 324, 214, "= ส่ง + ยกดูด", 10.5, "end", INK2))
        else:
            o.append(dim_v(x0 + 104, swl, cl, "", "right"))
            o.append(t(x0 + 112, swl + 30, "เฮดดูด", 10.5, "start", INK, 600))
            o.append(t(x0 + 112, swl + 44, "(+z_s)", 10.5, "start", INK2))
            o.append(dim_v(x0 + 330, dwl, swl, "", "left"))
            o.append(t(x0 + 324, 150, "เฮดสถิตรวม", 10.5, "end", INK, 700))
            o.append(t(x0 + 324, 164, "= ส่ง − เฮดดูด", 10.5, "end", INK2))
    o.append(t(12, 372, "เฮดสถิตรวม (Hs) = ระดับผิวน้ำปลายทาง − ระดับผิวน้ำต้นทาง (เมื่อถังทั้งสองเปิดสู่บรรยากาศ)", 11, "start", INK2))
    return wrap(W, H, "".join(o))


# ---------------------------------------------------------------------------
def fig_hgl():
    """Energy / hydraulic grade line along a simple pumping system."""
    W, H = 680, 300
    o = []
    o.append(f'<rect x="20" y="170" width="80" height="90" fill="{WATER_FILL}" stroke="{CONC_EDGE}"/>')
    o.append(f'<rect x="580" y="60" width="80" height="120" fill="none" stroke="{CONC_EDGE}"/>')
    o.append(f'<rect x="580" y="80" width="80" height="100" fill="{WATER_FILL}"/>')
    o.append(f'<line x1="20" y1="170" x2="100" y2="170" stroke="{WATER_EDGE}" stroke-width="2"/>')
    o.append(f'<line x1="580" y1="80" x2="660" y2="80" stroke="{WATER_EDGE}" stroke-width="2"/>')
    o.append(f'<polyline points="100,240 170,240 190,240 580,160" fill="none" stroke="{PIPE}" stroke-width="6" stroke-linejoin="round"/>')
    o.append(pump(180, 240, r=14))
    egl = [(20, 170), (100, 170), (108, 176), (166, 182), (194, 52), (560, 74), (580, 80), (660, 80)]
    o.append('<polyline points="' + " ".join(f"{x},{y}" for x, y in egl) + f'" fill="none" stroke="{RED}" stroke-width="2"/>')
    hgl = [(108, 184), (166, 190), (194, 60), (560, 82)]
    o.append('<polyline points="' + " ".join(f"{x},{y}" for x, y in hgl) + f'" fill="none" stroke="{BLUE}" stroke-width="2" stroke-dasharray="6 4"/>')
    o.append(dim_v(210, 182, 52, "", "right"))
    o.append(t(220, 140, "เฮดที่ปั๊มเพิ่มให้ (TDH)", 12, "start", INK, 700))
    o.append(t(220, 156, "= เฮดสถิต + ความสูญเสียทั้งหมด", 11, "start", INK2))
    o.append(dim_v(620, 80, 170, "", "left"))
    o.append(t(612, 130, "เฮดสถิต", 11, "end", INK, 600))
    o.append(f'<line x1="100" y1="170" x2="600" y2="170" stroke="{MUTED}" stroke-dasharray="3 3"/>')
    o.append(t(400, 104, "ความชันของเส้น = ความสูญเสียจากแรงเสียดทาน", 11, "middle", INK2))
    o.append(t(40, 285, "เส้นทึบแดง = เส้นระดับพลังงาน (EGL) · เส้นประฟ้า = เส้นระดับชลศาสตร์ (HGL) ห่างจาก EGL เท่ากับ v²/2g", 11, "start", INK2))
    return wrap(W, H, "".join(o))


# ---------------------------------------------------------------------------
def fig_wetwell():
    e = EX2
    W, H = 680, 360
    o = []
    k = 88

    def Y(el):
        return 44 + (-3.5 - el) * k
    xl, xr = 100, 360
    floor = Y(e["FLOOR"])
    top = Y(-3.5)
    o.append(f'<rect x="{xl - 16}" y="{top}" width="16" height="{floor - top + 16}" fill="{CONC}" stroke="{CONC_EDGE}"/>')
    o.append(f'<rect x="{xr}" y="{top}" width="16" height="{floor - top + 16}" fill="{CONC}" stroke="{CONC_EDGE}"/>')
    o.append(f'<rect x="{xl - 16}" y="{floor}" width="{xr - xl + 32}" height="16" fill="{CONC}" stroke="{CONC_EDGE}"/>')
    o.append(f'<rect x="{xl}" y="{Y(e["START1"])}" width="{xr - xl}" height="{floor - Y(e["START1"])}" fill="{SEW_FILL}"/>')
    o.append(f'<rect x="{xl}" y="{Y(e["START1"])}" width="{xr - xl}" height="{Y(e["STOP"]) - Y(e["START1"])}" fill="#d9c49a" opacity="0.55"/>')
    o.append(f'<polygon points="{xl},{floor} {xl + 40},{floor} {xl},{floor - 40}" fill="{CONC}" stroke="{CONC_EDGE}"/>')
    o.append(f'<polygon points="{xr},{floor} {xr - 40},{floor} {xr},{floor - 40}" fill="{CONC}" stroke="{CONC_EDGE}"/>')
    yi = Y(e["INV"])
    o.append(f'<rect x="{xl - 16 - 60}" y="{yi - 26}" width="76" height="26" fill="#cbb994" stroke="{SEW_EDGE}"/>')
    o.append(arrow_px(xl - 70, yi - 13, xl - 22, yi - 13, "#6b5424", 2, head=8))
    o.append(t(xl - 76, yi - 32, "ท่อน้ำเสียเข้า", 10.5, "start", INK, 600))
    for i, px in enumerate((xl + 80, xl + 190)):
        base = floor
        o.append(f'<rect x="{px - 22}" y="{base - 12}" width="44" height="12" fill="{PIPE}"/>')
        o.append(f'<rect x="{px - 18}" y="{base - 78}" width="36" height="66" rx="8" fill="#7b95b0" stroke="{PIPE}"/>')
        o.append(f'<rect x="{px - 22}" y="{base - 32}" width="44" height="20" rx="4" fill="#5d7690"/>')
        o.append(f'<line x1="{px + 30}" y1="{top}" x2="{px + 30}" y2="{base - 12}" stroke="{MUTED}" stroke-width="2"/>')
        o.append(f'<polyline points="{px + 22},{base - 6} {px + 44},{base - 6} {px + 44},{top - 14}" fill="none" stroke="{PIPE}" stroke-width="6"/>')
        o.append(t(px, base - 50, f"ปั๊ม {i + 1}", 10.5, "middle", "#fff", 700))
    o.append(t(xl + 60, top - 20, "↑ ไปห้องวาล์ว (check valve + gate/plug valve) → ท่อส่งแรงดัน", 10.5, "start", INK2))
    levels = [(e["INV"], "ท้องท่อน้ำเข้า", ORANGE), (e["HLA"], "เตือนระดับสูง (HLA)", RED),
              (e["START2"], "สั่งเดินเครื่องที่ 2 (lag start)", VIOLET), (e["START1"], "สั่งเดินเครื่องหลัก (lead start)", BLUE),
              (e["STOP"], "สั่งหยุด (stop) ≥ ระดับจมต่ำสุด", GREEN), (e["FLOOR"], "พื้นบ่อ", MUTED)]
    for el, lab, col in levels:
        y = Y(el)
        o.append(f'<line x1="{xl}" y1="{y:.1f}" x2="{xr + 30}" y2="{y:.1f}" stroke="{col}" stroke-width="1.4" stroke-dasharray="6 3"/>')
        o.append(f'<polygon points="{xr + 30},{y:.1f} {xr + 38},{y - 7:.1f} {xr + 22},{y - 7:.1f}" fill="{col}"/>')
        o.append(t(xr + 46, y + 4, f"{el:+.2f} ม.", 11.5, "start", INK, 700, extra='style="font-variant-numeric:tabular-nums"'))
        o.append(t(xr + 102, y + 4, lab, 11, "start", INK2))
    o.append(dim_v(xl + 22, Y(e["START1"]), Y(e["STOP"]), "", "right"))
    o.append(t(xl + 30, (Y(e["START1"]) + Y(e["STOP"])) / 2 + 4, f"Δh = {V['e2_dh']} ม.", 10.5, "start", INK, 700))
    o.append(t(xr + 46, Y(e["STOP"]) - 26, "แถบสีเข้ม = ปริมาตรใช้งาน (active volume)", 10.5, "start", INK2))
    o.append(t(20, H - 8, f"ภาพตัดบ่อสูบน้ำเสียแบบปั๊มจุ่ม (ตัวอย่างที่ 2) · ขนาดบ่อ {e['AW'][0]} × {e['AW'][1]} ม. · ±0.00 = ระดับถนน", 10.5, "start", INK2))
    return wrap(W, H, "".join(o))


# ---------------------------------------------------------------------------
def fig_submergence():
    W, H = 680, 330
    o = []
    wl, fl = 70, 290
    o.append(f'<rect x="40" y="{wl}" width="330" height="{fl - wl}" fill="{WATER_FILL}"/>')
    o.append(f'<line x1="40" y1="{wl}" x2="370" y2="{wl}" stroke="{WATER_EDGE}" stroke-width="2"/>')
    o.append(water_lines(40, 370, wl, 3))
    o.append(f'<rect x="370" y="30" width="16" height="{fl - 30 + 16}" fill="{CONC}" stroke="{CONC_EDGE}"/>')
    o.append(f'<rect x="20" y="{fl}" width="366" height="16" fill="{CONC}" stroke="{CONC_EDGE}"/>')
    D = 90
    bx = 370 - 0.75 * D - D / 2
    bell_y = fl - 0.4 * D
    o.append(f'<rect x="{bx - 18}" y="20" width="36" height="{bell_y - 44}" fill="#9aa9b8" stroke="{PIPE}"/>')
    o.append(f'<path d="M{bx - 18},{bell_y - 24} Q{bx - 20},{bell_y} {bx - D / 2},{bell_y} L{bx + D / 2},{bell_y} Q{bx + 20},{bell_y} {bx + 18},{bell_y - 24} Z" fill="#9aa9b8" stroke="{PIPE}"/>')
    o.append(dim_v(bx - D / 2 - 30, wl, bell_y, "S", "left"))
    o.append(dim_v(bx - D / 2 - 30, bell_y, fl, "C", "left"))
    o.append(arrow_px(bx - D / 2, bell_y + 14, bx + D / 2, bell_y + 14, INK2, 1.1, both=True, head=6))
    o.append(t(bx, bell_y + 30, "D", 11.5, "middle", INK, 700))
    o.append(arrow_px(bx + D / 2, bell_y - 40, 370, bell_y - 40, INK2, 1.1, both=True, head=6))
    o.append(t((bx + D / 2 + 370) / 2, bell_y - 46, "B", 11.5, "middle", INK, 700))
    for yy in (130, 180, 230):
        o.append(arrow_px(60, yy, 150, yy, BLUE_D, 1.5))
    o.append(t(44, 58, "การไหลเข้าสม่ำเสมอ (≈ ≤ 0.5 ม./วินาที)", 10.5, "start", INK2))
    o.append(f'<path d="M{bx - 30},{wl} q-10,10 0,22 q12,12 -2,26 q-8,10 2,20" fill="none" stroke="{RED}" stroke-width="1.6" stroke-dasharray="3 2"/>')
    tx = 410
    o.append(t(tx, 44, "สูตรการจมต่ำสุด (ANSI/HI 9.8)", 12.5, "start", INK, 700))
    o.append(t(tx, 70, "S = D (1 + 2.3 F_D)", 13, "start", INK, 600))
    o.append(t(tx, 92, "F_D = V / √(g·D)", 13, "start", INK, 600))
    lines = ["D = เส้นผ่านศูนย์กลางปากระฆัง (bell)", "V = ความเร็วที่ปากระฆัง = Q / (πD²/4)", "S = ระดับน้ำต่ำสุด ถึง ปากระฆัง",
             "C = ระยะปากระฆังถึงพื้น ≈ 0.3D–0.5D", "B = ระยะถึงผนังหลัง ≈ 0.75D", "",
             "S ไม่พอ → เกิดกระแสน้ำวนผิวน้ำ", "ดูดอากาศเข้า → สั่น เสียงดัง", "อัตราไหลลด ใบพัดเสียหาย"]
    for i, s in enumerate(lines):
        o.append(t(tx, 124 + i * 19, s, 11, "start", INK2 if i < 6 else RED))
    return wrap(W, H, "".join(o))


# ---------------------------------------------------------------------------
def fig_suction():
    W, H = 680, 300
    o = []
    for k, (title, good) in enumerate((("✓ ถูกต้อง", True), ("✗ ไม่ถูกต้อง", False))):
        x0 = k * 340
        col = GREEN if good else RED
        o.append(f'<rect x="{x0 + 6}" y="6" width="328" height="252" rx="8" fill="#fbfbf9" stroke="{GRID}"/>')
        o.append(t(x0 + 20, 28, title, 13, "start", col, 700))
        px, py = x0 + 280, 150
        o.append(f'<circle cx="{px}" cy="{py}" r="30" fill="#e6ecf2" stroke="{PIPE}" stroke-width="2"/>')
        o.append(f'<rect x="{px - 12}" y="{py - 70}" width="24" height="40" fill="#e6ecf2" stroke="{PIPE}" stroke-width="2"/>')
        o.append(t(px + 34, py + 4, "ปั๊ม", 11, "start", INK, 600))
        if good:
            o.append(f'<path d="M{px - 30},{py - 14} L{px - 60},{py - 14} L{px - 60},{py + 22} L{px - 30},{py + 14} Z" fill="#cfd8e0" stroke="{PIPE}" stroke-width="1.6"/>')
            o.append(f'<rect x="{x0 + 70}" y="{py - 14}" width="{px - 60 - x0 - 70}" height="36" fill="#dde5ec" stroke="{PIPE}" stroke-width="1.6"/>')
            o.append(f'<path d="M{x0 + 34},{py + 110} L{x0 + 34},{py + 22} Q{x0 + 34},{py - 14} {x0 + 70},{py - 14} L{x0 + 70},{py + 110} Z" fill="#dde5ec" stroke="{PIPE}" stroke-width="1.6"/>')
            o.append(arrow_px(x0 + 90, py - 34, px - 64, py - 34, INK2, 1.1, both=True, head=6))
            o.append(t((x0 + 90 + px - 64) / 2, py - 40, "ท่อตรง ≥ 5D", 11, "middle", INK, 600))
            o.append(t(px - 46, py + 42, "ข้อลดเยื้องศูนย์", 10.5, "middle", INK2))
            o.append(t(px - 46, py + 56, "ด้านเรียบอยู่บน", 10.5, "middle", INK2))
            o.append(t(x0 + 90, py + 80, "ท่อลาดขึ้นหาปั๊ม", 10.5, "start", INK2))
            o.append(t(x0 + 90, py + 94, "ไม่มีจุดกักอากาศ", 10.5, "start", INK2))
            o.append(t(x0 + 90, py + 108, "ความเร็วท่อดูด ≈ 1.0–1.8 ม./วินาที", 10.5, "start", INK2))
        else:
            o.append(f'<path d="M{px - 30},{py - 14} L{px - 50},{py - 22} L{px - 50},{py + 22} L{px - 30},{py + 14} Z" fill="#cfd8e0" stroke="{PIPE}" stroke-width="1.6"/>')
            o.append(f'<path d="M{px - 50},{py - 22} Q{px - 90},{py - 22} {px - 90},{py + 20} L{px - 90},{py + 110} L{px - 54},{py + 110} L{px - 54},{py + 22} Q{px - 54},{py + 22} {px - 50},{py + 22} Z" fill="#dde5ec" stroke="{PIPE}" stroke-width="1.6"/>')
            o.append(f'<ellipse cx="{px - 46}" cy="{py - 16}" rx="6" ry="4" fill="#fff" stroke="{RED}" stroke-width="1.5"/>')
            o.append(t(px - 58, py - 34, "ฟองอากาศค้าง", 10.5, "end", RED, 600))
            o.append(t(x0 + 24, py - 72, "ข้อโค้งติดหน้าแปลนดูด", 10.5, "start", INK2))
            o.append(t(x0 + 24, py - 58, "→ การไหลเข้าตาใบพัดไม่สม่ำเสมอ", 10.5, "start", INK2))
            o.append(t(x0 + 24, py + 60, "ข้อลดศูนย์กลางร่วม", 10.5, "start", INK2))
            o.append(t(x0 + 24, py + 74, "→ อากาศสะสมด้านบน", 10.5, "start", INK2))
            o.append(t(x0 + 24, py + 88, "→ อัตราไหลลด/สั่น", 10.5, "start", INK2))
    o.append(t(12, 284, "หลักเดียวกันใช้กับปั๊มดูดท่วม: ไม่ให้มีจุดสูงกักอากาศ และให้การไหลเข้าตาใบพัดสม่ำเสมอ", 11, "start", INK2))
    return wrap(W, H, "".join(o))


# ---------------------------------------------------------------------------
def fig_ex1_layout():
    e = EX1
    W, H = 680, 350
    o = []
    Y = lambda el: 285 - (el - 95) * (240 / 45)
    o.append(f'<rect x="20" y="{Y(105.5)}" width="120" height="{Y(99) - Y(105.5)}" fill="none" stroke="{CONC_EDGE}" stroke-width="3"/>')
    o.append(f'<rect x="22" y="{Y(e["HWL"])}" width="116" height="{Y(99) - Y(e["HWL"]) - 2}" fill="{WATER_FILL}"/>')
    for el, lab in ((e["HWL"], "HWL +104.00"), (e["LWL"], "LWL +100.00")):
        o.append(f'<line x1="22" y1="{Y(el)}" x2="138" y2="{Y(el)}" stroke="{WATER_EDGE}" stroke-dasharray="5 3"/>')
        o.append(t(26, Y(el) - 4, lab, 10.5, "start", INK, 600))
    o.append(t(80, Y(105.5) - 8, "ถังน้ำใส", 11.5, "middle", INK, 700))
    cl = Y(e["CL"])
    o.append(f'<polyline points="138,{cl} 229,{cl}" stroke="{PIPE}" stroke-width="5"/>')
    o.append(pump(242, cl, r=13))
    o.append(t(242, cl + 28, "ปั๊ม 3 ใช้งาน + 1 สำรอง", 10.5, "middle", INK, 600))
    o.append(t(242, cl + 42, f"ศูนย์กลางปั๊ม +{e['CL']:.2f}", 10.5, "middle", INK2))
    o.append(f'<polyline points="255,{cl} 300,{cl} 300,{Y(106)} 590,{Y(121)} 590,{Y(e["OUT"])} 612,{Y(e["OUT"])}" fill="none" stroke="{PIPE}" stroke-width="5" stroke-linejoin="round"/>')
    ang = math.degrees(math.atan2(Y(121) - Y(106), 290))
    lx, ly = 445, (Y(106) + Y(121)) / 2 + 20
    o.append(t(lx, ly, f"ท่อเหล็กหล่อเหนียว DN700 ยาว {e['Lm'] / 1000:.1f} กม. (C = {e['Cm']:.0f})", 11, "middle", INK, 600,
               extra=f'transform="rotate({ang:.1f} {lx} {ly:.1f})"'))
    o.append(f'<rect x="604" y="{Y(139)}" width="70" height="{Y(128) - Y(139)}" fill="none" stroke="{CONC_EDGE}" stroke-width="3"/>')
    o.append(f'<rect x="606" y="{Y(136)}" width="66" height="{Y(128) - Y(136) - 2}" fill="{WATER_FILL}"/>')
    o.append(arrow_px(614, Y(e["OUT"]) + 2, 614, Y(136.3), BLUE_D, 1.6))
    o.append(t(674, Y(139) - 22, "ถังเก็บน้ำปลายทาง", 11, "end", INK, 700))
    o.append(t(584, Y(e["OUT"]) - 6, "ปลายท่อจ่ายลงอิสระ +138.00", 10.5, "end", INK))
    o.append(f'<line x1="150" y1="{Y(e["OUT"])}" x2="590" y2="{Y(e["OUT"])}" stroke="{MUTED}" stroke-dasharray="3 3"/>')
    o.append(f'<line x1="140" y1="{Y(e["LWL"])}" x2="224" y2="{Y(e["LWL"])}" stroke="{MUTED}" stroke-dasharray="3 3"/>')
    o.append(f'<line x1="140" y1="{Y(e["HWL"])}" x2="184" y2="{Y(e["HWL"])}" stroke="{MUTED}" stroke-dasharray="3 3"/>')
    o.append(dim_v(176, Y(e["OUT"]), Y(e["HWL"]), "", "left"))
    o.append(t(168, Y(121), "Hs,min", 10.5, "end", INK, 700))
    o.append(t(168, Y(121) + 14, "34.0 ม.", 10.5, "end", INK2))
    o.append(dim_v(216, Y(e["OUT"]), Y(e["LWL"]), "", "right"))
    o.append(t(224, Y(121), "Hs,max", 10.5, "start", INK, 700))
    o.append(t(224, Y(121) + 14, "38.0 ม.", 10.5, "start", INK2))
    o.append(t(340, 342, "ตัวอย่างที่ 1: สถานีสูบส่งน้ำประปา (high lift) · ระดับเป็นเมตร รทก.", 10.5, "middle", INK2))
    return wrap(W, H, "".join(o))


# ---------------------------------------------------------------------------
def fig_vtp():
    W, H = 680, 380
    o = []
    cx = 150
    o.append(box(cx - 40, 12, 80, 56, ["มอเตอร์", "แนวตั้ง"], fill="#dfe6ee", stroke=PIPE, size=11))
    o.append(f'<rect x="{cx - 50}" y="68" width="100" height="36" fill="#c9d3dd" stroke="{PIPE}"/>')
    o.append(f'<polyline points="{cx + 50},86 {cx + 110},86" stroke="{PIPE}" stroke-width="10"/>')
    o.append(arrow_px(cx + 100, 86, cx + 130, 86, BLUE_D, 2, head=9))
    o.append(f'<rect x="20" y="104" width="300" height="12" fill="{CONC}" stroke="{CONC_EDGE}"/>')
    o.append(f'<rect x="40" y="170" width="260" height="170" fill="{WATER_FILL}"/>')
    o.append(f'<line x1="40" y1="170" x2="300" y2="170" stroke="{WATER_EDGE}" stroke-width="2"/>')
    o.append(water_lines(40, 300, 170, 3))
    o.append(f'<rect x="{cx - 16}" y="116" width="32" height="130" fill="#e6ecf2" stroke="{PIPE}"/>')
    o.append(f'<line x1="{cx}" y1="70" x2="{cx}" y2="290" stroke="{INK2}" stroke-width="2" stroke-dasharray="8 3"/>')
    for i in range(2):
        yy = 246 + i * 26
        o.append(f'<path d="M{cx - 16},{yy} L{cx - 30},{yy + 8} L{cx - 30},{yy + 20} L{cx - 16},{yy + 26} L{cx + 16},{yy + 26} L{cx + 30},{yy + 20} L{cx + 30},{yy + 8} L{cx + 16},{yy} Z" fill="#9aa9b8" stroke="{PIPE}"/>')
    o.append(f'<path d="M{cx - 16},298 Q{cx - 20},318 {cx - 36},320 L{cx + 36},320 Q{cx + 20},318 {cx + 16},298 Z" fill="#9aa9b8" stroke="{PIPE}"/>')
    o.append(f'<rect x="{cx - 38}" y="320" width="76" height="12" fill="none" stroke="{PIPE}" stroke-dasharray="2 2"/>')
    labels = [(40, "มอเตอร์: แบริ่งกันรุนรับแรงแนวแกนทั้งหมด"), (86, "หัวส่ง (discharge head) + ทางออก"),
              (150, "ท่อยก (column) + เพลายาว (lineshaft)"), (262, "ชุดเรือนใบพัด (bowl assembly) หลายชั้นได้"),
              (312, "ปากระฆังดูด (suction bell)"), (330, "ตะแกรง (strainer) – ถ้าจำเป็น")]
    for y, s in labels:
        o.append(f'<line x1="{cx + 40}" y1="{y}" x2="340" y2="{y}" stroke="{MUTED}" stroke-width="1"/>')
        o.append(t(346, y + 4, s, 11, "start", INK))
    o.append(t(20, 372, "ปั๊มเทอร์ไบน์แนวตั้ง (VTP) – ใบพัดจมใต้น้ำตลอด จึงไม่ต้องล่อน้ำและ NPSHa สูง", 11, "start", INK2))
    return wrap(W, H, "".join(o))


# ---------------------------------------------------------------------------
def fig_curve_shapes():
    """Normalised H and P curves for radial / mixed / axial pumps (two stacked panels, no dual axis)."""
    W = 680
    shapes = [
        ("หอยโข่ง (nq ≈ 20)", BLUE, lambda x: 1.22 - 0.22 * x * x, lambda x: 0.55 + 0.45 * x),
        ("ไหลผสม (nq ≈ 80)", ORANGE, lambda x: 1.7 - 0.7 * x ** 1.6, lambda x: 0.95 + 0.05 * math.sin(x * 1.3)),
        ("ไหลตามแกน (nq ≈ 200)", VIOLET, lambda x: 2.8 - 1.8 * x ** 1.3, lambda x: 2.0 - 1.0 * x),
    ]
    c1 = Chart(W, 220, (0, 1.4), (0, 3), "", "H / H_BEP", [0, 0.2, 0.4, 0.6, 0.8, 1.0, 1.2, 1.4], ticks(0, 3, 0.5),
               mt=44, mb=4, show_xaxis=False, xfmt=lambda v: f"{v:.1f}", yfmt=lambda v: f"{v:.1f}")
    c2 = Chart(W, 200, (0, 1.4), (0, 2.5), "Q / Q_BEP", "P / P_BEP", [0, 0.2, 0.4, 0.6, 0.8, 1.0, 1.2, 1.4], ticks(0, 2.5, 0.5),
               mt=8, mb=46, oy=220, xfmt=lambda v: f"{v:.1f}", yfmt=lambda v: f"{v:.1f}")
    for lab, col, fh, fp in shapes:
        c1.fn(fh, 0, 1.35, color=col, width=2)
        c2.fn(fp, 0, 1.35, color=col, width=2)
    c1.vline(1.0, MUTED, 1, "4 3")
    c2.vline(1.0, MUTED, 1, "4 3")
    c1.legend([(s[0], s[1], "line") for s in shapes])
    c2.label(0.03, 2.0, "ไหลตามแกน: กำลังสูงสุดที่วาล์วปิด!", dy=-8, size=11, color=INK)
    c2.label(0.03, 0.55, "หอยโข่ง: กำลังต่ำสุดที่วาล์วปิด", dy=16, size=11, color=INK)
    return wrap(W, 420, c1.body() + c2.body())


# ---------------------------------------------------------------------------
def fig_pd_vs_cf():
    c = Chart(680, 320, (0, 120), (0, 140), "อัตราการไหล (% ของพิกัด)", "เฮด/ความดัน (% ของพิกัด)",
              ticks(0, 120, 20), ticks(0, 140, 20), mt=36)
    c.fn(lambda q: 130 - 30 * (q / 100) ** 2, 0, 120, color=BLUE, width=2)
    c.line([100, 99, 97.5, 96, 95.3], [0, 40, 80, 120, 140], ORANGE, 2)
    c.label(8, 130, "หอยโข่ง: เฮดเปลี่ยนนิดเดียว Q เปลี่ยนมาก", dy=-8, size=11, color=INK)
    c.label(92, 30, "แทนที่เชิงบวก: Q เกือบคงที่", anchor="end", size=11, color=INK)
    c.label(92, 20, "ถ้าปิดวาล์วด้านส่ง ความดันพุ่งสูง", anchor="end", size=10.5, color=INK2, weight=400)
    c.label(92, 11, "→ ต้องมีวาล์วระบายความดัน", anchor="end", size=10.5, color=INK2, weight=400)
    c.legend([("ปั๊มหอยโข่ง", BLUE, "line"), ("ปั๊มแทนที่เชิงบวก", ORANGE, "line")])
    return c.svg()


DIAGRAMS = dict(
    fig_wtp=fig_wtp, fig_wws=fig_wws, fig_classify=fig_classify, fig_centrifugal=fig_centrifugal,
    fig_ns_shapes=fig_ns_shapes, fig_impellers=fig_impellers, fig_tdh=fig_tdh, fig_hgl=fig_hgl,
    fig_wetwell=fig_wetwell, fig_submergence=fig_submergence, fig_suction=fig_suction,
    fig_ex1_layout=fig_ex1_layout, fig_vtp=fig_vtp, fig_curve_shapes=fig_curve_shapes, fig_pd_vs_cf=fig_pd_vs_cf,
)
