#!/usr/bin/env python3
"""สร้างไฟล์ CAD (DXF, หน่วย mm) ของบ่อ 3 ช่อง ตามขนาดล่าสุด (ตรงกับ weir_design.xlsx)

มุมมอง: แปลน / รูปตัด A–A (ตามยาว) / รูปตัด B–B (ที่แผ่นเวียร์)
ระดับ ±0 = ผิวพื้นช่อง 2–3  |  x = 0 ที่ผิวในผนังหัวบ่อ  |  แปลน y = 0 ที่ผิวในผนังข้างช่อง 2–3
เวียร์ออกแบบที่ Q 65 m³/h (เดินระบบ 24 ชม.) ตรวจน้ำ 100 m³/h ไม่ล้นร่อง V
"""
import math
import ezdxf
from ezdxf.enums import TextEntityAlignment

OUT = "cad/weir_tank.dxf"

# ---------------- ขนาด (mm) ----------------
T = 200                     # ผนัง / พื้น คสล.
B = 1250                    # กว้างภายในช่อง 2–3
W1 = 3500                   # ช่อง 1 กว้าง (แบบ ข)
OFF1 = (W1 - B) / 2         # ช่อง 1 กว้างกว่ารางข้างละ
ZF1 = -1200                 # พื้นช่อง 1
L1 = 2100                   # ช่อง 1 ยาว (HRT 15 นาทีที่ 62.8 m³/h)
XB1, TB1, GAP1 = 1000, 100, 300         # บัฟเฟอร์ คสล. / หนา / ช่องลอด
ZIN, DPO = 1100, 168                    # ศก.ท่อเข้า 6" (ท่อตรง) / OD
XP, PW, PH = 1600, 400, 550             # ปั๊ม ศก. / ฐาน / สูง
L2 = 300
X2 = L1 + L2                            # ปลายพื้นยกช่อง 2 (สันปลาย)
ZR, SILL = 900, 20
XB3, TB3, ZB3 = X2 + 350, 100, 150      # (1) ผนังลอดใต้ คสล.
XS3 = XB3 + TB3 + 150                   # (2) สันล้น คสล. (ผิวต้นน้ำ)
ZS3 = 250
XA = XS3 + TB3                          # ต้นช่วงตรง
XW, TWW, ZWW = XA + 1800, 200, 400      # กำแพงเวียร์
XE = XW + TWW + 500                     # ผิวในผนังท้าย
ZTOP = 1200
ZV, ZN, ZPB, ZPT = 500, 760, 300, 860   # ยอด V / ขอบบนร่อง / แผ่นล่าง / แผ่นบน
XT, ZDL = XW - 800, 1100                # Flow meter
XBOD, YBOD, ZBOD = XA + 300, 150, 200   # BOD probe
DOUT = 200
Z1W, Z2W, Z3W, Z3D, ZTAIL = 977, 970, 710, 676, 211   # น้ำ ช่อง 1 / 2 / 3 (100) / 3 (65) / ท้าย
ZSTART, ZSTOP = 800, ZF1 + 600
LEVELS = [(1200, "สันกำแพง"), (1100, "หน้า Flow meter / ศก.ท่อเข้า 6\""), (977, "น้ำช่อง 1 (100 m³/h)"),
          (920, "สันปลายช่อง 2"), (900, "ผิวพื้นยก ช่อง 2"), (860, "ขอบบนแผ่นเวียร์"), (800, "ปั๊ม START"),
          (760, "ขอบบนร่อง V"), (710, "น้ำช่อง 3 (100 m³/h)"), (676, "น้ำช่อง 3 (65 m³/h ออกแบบ)"),
          (500, "ยอด V"), (400, "สันกำแพงเวียร์"), (300, "ขอบล่างแผ่นเวียร์"), (250, "สันล้น (2)"),
          (211, "น้ำท้ายเวียร์"), (200, "ปลาย BOD"), (150, "ขอบล่างผนังลอดใต้ (1)"), (0, "ผิวพื้นช่อง 2–3"),
          (-600, "ปั๊ม STOP"), (-900, "ขอบล่างบัฟเฟอร์ช่อง 1"), (-1200, "ผิวพื้นช่อง 1"), (-1400, "ใต้พื้นช่อง 1")]


def concrete():
    """ปริมาตรคอนกรีตโครงสร้าง (m³) แยกตามส่วน"""
    m = 1e-3
    t, b, w1, l1, l2, f = T * m, B * m, W1 * m, L1 * m, L2 * m, ZF1 * m
    lc3, top, zr = (XE - X2) * m, ZTOP * m, ZR * m
    r = {"พื้นช่อง 1": (t + l1 + t) * (w1 + 2 * t) * t,
         "ผนังช่อง 1": (t * (w1 + 2 * t) + 2 * t * l1 + 2 * t * (w1 - b) / 2) * (top - f),
         "บล็อกพื้นยกช่อง 2": b * l2 * (zr - f),
         "บัฟเฟอร์ช่อง 1": TB1 * m * w1 * (top - (f + GAP1 * m)),
         "พื้นช่อง 2–3": (l2 - t + lc3 + t) * (b + 2 * t) * t,
         "ผนังข้างช่อง 2–3": 2 * t * (l2 - t + lc3) * top + 2 * t * (l2 - t) * (0 - f),
         "ผนังท้าย": t * b * top,
         "ผนัง (1) (2) + กำแพงเวียร์": TB3 * m * b * (top - ZB3 * m) + TB3 * m * b * ZS3 * m + TWW * m * b * ZWW * m}
    return r, sum(r.values())


doc = ezdxf.new("R2010", setup=True)
doc.units = ezdxf.units.MM
doc.styles.new("THAI", dxfattribs={"font": "tahoma.ttf"})
for name, color, lt in [("CONCRETE", 8, "CONTINUOUS"), ("HATCH", 9, "CONTINUOUS"), ("SS", 5, "CONTINUOUS"),
                        ("PIPE", 30, "CONTINUOUS"), ("EQUIP", 40, "CONTINUOUS"), ("WATER", 4, "DASHED"),
                        ("CENTER", 1, "CENTER"), ("DIM", 3, "CONTINUOUS"), ("TEXT", 7, "CONTINUOUS")]:
    doc.layers.add(name, color=color, linetype=lt)
ds = doc.dimstyles.new("MM100")
ds.dxf.dimtxt, ds.dxf.dimasz, ds.dxf.dimtsz = 70, 50, 35
ds.dxf.dimexo, ds.dxf.dimexe, ds.dxf.dimgap, ds.dxf.dimdec = 30, 40, 20, 0
ds.dxf.dimtxsty = "THAI"
ds.dxf.dimtad = 1
msp = doc.modelspace()


def box(x1, y1, x2, y2, layer="CONCRETE", hatch=False, ox=0, oy=0):
    pts = [(x1 + ox, y1 + oy), (x2 + ox, y1 + oy), (x2 + ox, y2 + oy), (x1 + ox, y2 + oy)]
    msp.add_lwpolyline(pts, close=True, dxfattribs={"layer": layer})
    if hatch:
        h = msp.add_hatch(color=9, dxfattribs={"layer": "HATCH"})
        h.set_pattern_fill("ANSI31", scale=15)
        h.paths.add_polyline_path(pts, is_closed=True)


def line(p1, p2, layer="TEXT", ox=0, oy=0):
    msp.add_line((p1[0] + ox, p1[1] + oy), (p2[0] + ox, p2[1] + oy), dxfattribs={"layer": layer})


def txt(s, x, y, h=70, align=TextEntityAlignment.LEFT, ox=0, oy=0, layer="TEXT"):
    t = msp.add_text(s, height=h, dxfattribs={"layer": layer, "style": "THAI"})
    t.set_placement((x + ox, y + oy), align=align)


def hdim(x1, x2, y, base, ox=0, oy=0, text="<>"):
    msp.add_linear_dim(base=(x1 + ox, base + oy), p1=(x1 + ox, y + oy), p2=(x2 + ox, y + oy),
                       dimstyle="MM100", text=text, dxfattribs={"layer": "DIM"}).render()


def vdim(y1, y2, x, base, ox=0, oy=0, text="<>"):
    msp.add_linear_dim(base=(base + ox, y1 + oy), p1=(x + ox, y1 + oy), p2=(x + ox, y2 + oy), angle=90,
                       dimstyle="MM100", text=text, dxfattribs={"layer": "DIM"}).render()


def chain_h(xs, y, base, ox=0, oy=0):
    for a, c in zip(xs, xs[1:]):
        hdim(a, c, y, base, ox, oy)


def chain_v(ys, x, base, ox=0, oy=0):
    for a, c in zip(ys, ys[1:]):
        vdim(a, c, x, base, ox, oy)


XS = [-T, 0, XB1, XB1 + TB1, L1, X2, XB3, XB3 + TB3, XS3, XA, XW, XW + TWW, XE, XE + T]
yc = B / 2

# =============================== แปลน ===============================
ox, oy = 0, 0
txt("แปลน  (หน่วย mm)", -T, B + OFF1 + T + 1500, 160)
box(-T, -OFF1 - T, 0, B + OFF1 + T, hatch=True)                       # ผนังหัวบ่อ
box(0, -OFF1 - T, L1 + T, -OFF1, hatch=True)                          # ผนังข้างช่อง 1
box(0, B + OFF1, L1 + T, B + OFF1 + T, hatch=True)
box(L1, -OFF1, L1 + T, 0, hatch=True)                                 # บ่าช่อง 1
box(L1, B, L1 + T, B + OFF1, hatch=True)
box(L1 + T, -T, XE + T, 0, hatch=True)                                # ผนังข้างช่อง 2–3
box(L1 + T, B, XE + T, B + T, hatch=True)
box(XE, 0, XE + T, B, hatch=True)                                     # ผนังท้าย
box(XB1, -OFF1, XB1 + TB1, B + OFF1, hatch=True)                      # บัฟเฟอร์ช่อง 1
box(XB3, 0, XB3 + TB3, B, hatch=True)                                 # (1) ผนังลอดใต้
box(XS3, 0, XS3 + TB3, B, hatch=True)                                 # (2) สันล้น
box(XW, 0, XW + TWW, B, hatch=True)                                   # กำแพงเวียร์
box(L1, 0, X2, B, layer="CONCRETE")                                   # พื้นยกช่อง 2 (ขอบ)
box(X2 - 6, 0, X2, B, layer="SS")                                     # สันปลาย SS
box(XW - 6, -100, XW, B + 100, layer="SS")                            # แผ่นเวียร์ (ฝังผนัง 100)
box(-T - 500, yc - DPO / 2, 100, yc + DPO / 2, layer="PIPE")          # ท่อเข้า 6" ตรง
box(XP - PW / 2, yc + 500 - PW / 2, XP + PW / 2, yc + 500 + PW / 2, layer="EQUIP")
msp.add_circle((XP, yc + 500), 150, dxfattribs={"layer": "EQUIP"})
box(XE, yc - DOUT / 2, XE + T + 500, yc + DOUT / 2, layer="PIPE")
box(XT - 50, -T, XT + 50, B + T, layer="SS")                          # คาน Flow meter
box(XT - 75, yc - 75, XT + 75, yc + 75, layer="EQUIP")
msp.add_circle((XBOD, YBOD), 48, dxfattribs={"layer": "EQUIP"})
line((-T - 700, yc), (XE + T + 700, yc), "CENTER")
txt("A", -T - 800, yc + 60, 140); txt("A", XE + T + 750, yc + 60, 140)
line((XW - 300, -T - 300), (XW - 300, B + T + 300), "CENTER")
txt("B", XW - 350, -T - 500, 140)
for s_, x_, y_ in [("ช่อง 1 รับน้ำ + ปั๊มจุ่ม", 1150, -OFF1 + 120), ("ช่อง 2", L1 + 20, B - 150),
                   ("ช่อง 3 เวียร์ V-notch 90°", XA + 100, B - 200), ("ปั๊มจุ่ม", XP - 120, yc + 500 + 230),
                   ("ท่อเข้า 6\" (ตรง)", -T - 500, yc + 140), ("ท่อออก 8\"", XE + T + 50, yc + 150),
                   ("Flow meter", XT + 100, yc + 100), ("BOD probe", XBOD + 70, YBOD - 30),
                   ("บัฟเฟอร์ คสล. 100", XB1 + 150, -OFF1 + 400),
                   ("(1) ผนังลอดใต้ คสล.", XB3 - 50, B + T + 300), ("(2) สันล้น คสล.", XS3 - 50, B + T + 450)]:
    txt(s_, x_, y_, 60)
yt = B + OFF1 + T
chain_h(XS, yt, yt + 300)
hdim(-T, L1, yt, yt + 650); hdim(L1, X2, yt, yt + 650); hdim(X2, XE + T, yt, yt + 650)
hdim(-T, XE + T, yt, yt + 1000)
yb = -OFF1 - T
hdim(0, XE, yb, yb - 300)
hdim(0, XP, yb, yb - 650); hdim(XA, XBOD, -T, yb - 650); hdim(XT, XW, -T, yb - 650)
chain_v([-T, 0, B, B + T], XE + T, XE + T + 300)
vdim(-T, B + T, XE + T, XE + T + 650)
chain_v([-OFF1 - T, -OFF1, 0, B, B + OFF1, B + OFF1 + T], -T, -T - 1000)
vdim(-OFF1 - T, B + OFF1 + T, -T, -T - 1400)
vdim(0, YBOD, XBOD, XBOD - 250)

# =============================== รูปตัด A–A ===============================
ox, oy = 0, -6500
txt("รูปตัด A–A  (ระดับ ±0 = ผิวพื้นช่อง 2–3, หน่วย mm)", -T, ZTOP + 900, 160, oy=oy)
box(-T, ZF1 - T, L1, ZF1, hatch=True, oy=oy)                          # พื้นช่อง 1
box(-T, ZF1, 0, ZTOP, hatch=True, oy=oy)                              # ผนังหัวบ่อ
box(L1, ZF1 - T, X2, ZR, hatch=True, oy=oy)                           # ขั้น + พื้นยก
box(X2, -T, XE + T, 0, hatch=True, oy=oy)                             # พื้นช่อง 2–3
box(XE, 0, XE + T, ZTOP, hatch=True, oy=oy)                           # ผนังท้าย
box(XB1, ZF1 + GAP1, XB1 + TB1, ZTOP, hatch=True, oy=oy)              # บัฟเฟอร์ช่อง 1
box(XB3, ZB3, XB3 + TB3, ZTOP, hatch=True, oy=oy)                     # (1)
box(XS3, 0, XS3 + TB3, ZS3, hatch=True, oy=oy)                        # (2)
box(XW, 0, XW + TWW, ZWW, hatch=True, oy=oy)                          # กำแพงเวียร์
box(XW - 6, ZPB, XW, ZPT, layer="SS", oy=oy)                          # แผ่นเวียร์
box(X2 - 6, ZR, X2, ZR + SILL, layer="SS", oy=oy)                     # สันปลาย SS
box(-T - 500, ZIN - DPO / 2, 100, ZIN + DPO / 2, layer="PIPE", oy=oy)  # ท่อเข้าตรง
v = 100 / 3600 / (math.pi * 0.154 ** 2 / 4)                           # 1.49 m/s ที่ 100 m³/h
for zl, nm in [(Z1W, "ปกติ"), (ZSTOP, "ที่ STOP")]:                   # วิถีน้ำพุ่ง
    xr = v * math.sqrt(2 * (ZIN - zl) / 1000 / 9.81) * 1000
    pts = [(100 + xr * i / 12, ZIN - (ZIN - zl) * (i / 12) ** 2 + oy) for i in range(13)]
    msp.add_lwpolyline(pts, dxfattribs={"layer": "WATER"})
    txt(f"น้ำพุ่ง {nm} {xr:.0f}", 100 + xr - 100, zl - 90, 45, oy=oy)
box(XP - PW / 2, ZF1, XP + PW / 2, ZF1 + PH, layer="EQUIP", oy=oy)
box(XE, 0, XE + T + 500, DOUT, layer="PIPE", oy=oy)
box(XT - 150, ZTOP, XT + 150, ZTOP + 50, layer="SS", oy=oy)
box(XT - 75, ZDL, XT + 75, ZDL + 80, layer="EQUIP", oy=oy)
line((XT, ZDL), (XT, ZV), "CENTER", oy=oy)
line((XBOD, ZTOP + 150), (XBOD, ZBOD + 300), "EQUIP", oy=oy)
box(XBOD - 30, ZBOD, XBOD + 30, ZBOD + 300, layer="EQUIP", oy=oy)
for z, x1, x2 in [(Z1W, 0, L1), (Z2W, L1, X2), (Z3W, X2, XW), (ZTAIL, XW + TWW, XE)]:
    line((x1, z), (x2, z), "WATER", oy=oy)
line((XA, ZV), (XW, ZV), "CENTER", oy=oy)
for z, nm in [(ZSTART, "START"), (ZSTOP, "STOP")]:
    line((XB1 + TB1, z), (L1, z), "WATER", oy=oy); txt(f"ปั๊ม {nm}", XB1 + 150, z + 30, 55, oy=oy)
for s_, x_, z_ in [("ช่อง 1", 1250, -250), ("ช่อง 2", L1 + 20, ZR + 150), ("ช่อง 3", XA + 300, 1000),
                   ("ปั๊มจุ่ม", XP - 130, ZF1 + 250), ("BOD", XBOD + 60, ZBOD + 150), ("Flow meter", XT + 100, ZDL + 120),
                   ("บัฟเฟอร์ คสล. 100 DB10@150", XB1 - 300, ZTOP + 80),
                   ("แผ่น V-notch SS304 6 mm", XW + 50, ZPT + 40), ("ท่อออก 8\"", XE + T + 50, DOUT + 50)]:
    txt(s_, x_, z_, 60, oy=oy)
xe = XE + T + 1000
zt_prev = 1e9
for z, nm in LEVELS:                                   # เลื่อนข้อความไม่ให้ทับกัน
    zt = min(z, zt_prev - 95); zt_prev = zt
    line((XE + T + 100, z), (xe - 250, z), "DIM", oy=oy)
    line((xe - 250, z), (xe - 50, zt), "DIM", oy=oy)
    txt(f"{z/1000:+.3f}  {nm}", xe, zt - 25, 55, oy=oy)
chain_h(XS, ZF1 - T, ZF1 - T - 400, oy=oy)
vdim(ZF1 - T, ZTOP, -T, -T - 700, oy=oy)
chain_v([ZF1 - T, ZF1, ZF1 + GAP1], -T, -T - 350, oy=oy)
vdim(ZF1, Z1W, XB1 + 300, XB1 + 300, oy=oy, text=f"น้ำลึก {Z1W - ZF1}")
vdim(ZF1, ZR, L1, L1 - 250, oy=oy)
vdim(ZB3, ZTOP, XB3, XB3 - 200, oy=oy)
vdim(0, ZB3, XB3, XB3 - 200, oy=oy)
vdim(0, ZS3, XS3 + TB3, XS3 + TB3 + 200, oy=oy)
vdim(0, ZV, XW, XW - 250, oy=oy, text=f"P {ZV}")
vdim(ZPB, ZPT, XW + TWW, XW + TWW + 220, oy=oy)
vdim(0, ZWW, XW + TWW, XW + TWW + 450, oy=oy)
vdim(Z3W, ZDL, XT, XT - 250, oy=oy)

# =============================== รูปตัด B–B ===============================
ox, oy = XE + T + 4500, -6500
h = B / 2 + T
txt("รูปตัด B–B ที่แผ่นเวียร์ (มองตามทิศน้ำ)", -h, ZTOP + 900, 140, ox=ox, oy=oy)
box(-h, -T, h, 0, hatch=True, ox=ox, oy=oy)
box(-h, 0, -B / 2, ZTOP, hatch=True, ox=ox, oy=oy)
box(B / 2, 0, h, ZTOP, hatch=True, ox=ox, oy=oy)
box(-B / 2, 0, B / 2, ZWW, hatch=True, ox=ox, oy=oy)
w = ZN - ZV
hp = B / 2 + 100
pts = [(-hp, ZPB), (hp, ZPB), (hp, ZPT), (w, ZPT), (w, ZN), (0, ZV), (-w, ZN), (-w, ZPT), (-hp, ZPT)]
msp.add_lwpolyline([(x + ox, y + oy) for x, y in pts], close=True, dxfattribs={"layer": "SS"})
for xb in (-450, -200, 200, 450):
    msp.add_circle((xb + ox, 350 + oy), 12, dxfattribs={"layer": "SS"})
for zz in (Z3W, Z3D):
    line((-(zz - ZV), zz), ((zz - ZV), zz), "WATER", ox=ox, oy=oy)
txt("แผ่น SS304 หนา 6 mm ยึดพุก M10 กับกำแพงเวียร์", -hp, ZTOP + 600, 60, ox=ox, oy=oy)
hdim(-h, h, -T, -T - 600, ox=ox, oy=oy)
chain_h([-h, -B / 2, B / 2, h], -T, -T - 300, ox=ox, oy=oy)
hdim(-hp, hp, ZPT, ZPT + 500, ox=ox, oy=oy)
chain_h([-hp, -B / 2, -w, w, B / 2, hp], ZPT, ZPT + 250, ox=ox, oy=oy)
chain_v([0, ZWW, ZV, ZN, ZPT], h, h + 300, ox=ox, oy=oy)
vdim(0, ZV, h, h + 650, ox=ox, oy=oy, text=f"P {ZV}")
vdim(ZPB, ZPT, -h, -h - 300, ox=ox, oy=oy)

# ตารางสรุป
parts, vol = concrete()
tx, ty = ox - h, oy - 1800
rows = [("ขนาดภายนอก", f"ยาว {XE + 2*T:.0f} / กว้าง ช่อง 1 {W1 + 2*T:.0f}, ช่อง 2–3 {B + 2*T:.0f}"),
        ("Q ออกแบบเวียร์", "65 m³/h (เดิน 24 ชม.) / น้ำ 100 m³/h ไม่ล้นร่อง V"),
        ("ผนัง / พื้น คสล.", "200 / 200"),
        ("ช่อง 1", f"{L1} × {W1} พื้น {ZF1} (HRT 15 นาที ที่ 62.8 m³/h)"),
        ("บัฟเฟอร์ช่อง 1", f"คสล. {TB1} DB10@150 ที่ {XB1} (รับ 3 บาร์)"),
        ("ช่อง 3: (1), (2) คสล. หนา", f"{TB3} (ลอด {ZB3} / สันล้น {ZS3})"),
        ("แผ่นเวียร์ SS304", f"{2*hp:.0f} × {ZPT - ZPB} × 6  ร่อง V 90° ลึก {w} ปาก {2*w}"),
        ("คอนกรีตโครงสร้าง", f"{vol:.2f} m³ (ไม่รวมเผื่อ / คอนกรีตหยาบ)"),
        ("หมายเหตุ", "ระดับ ±0 = ผิวพื้นช่อง 2–3 / โครงสร้างให้วิศวกรโยธารับรอง")]
for i, (a, c) in enumerate(rows):
    txt(a, tx, ty - i * 140, 65)
    txt(c, tx + 1600, ty - i * 140, 65)

doc.saveas(OUT)
print("saved", OUT, "| ยาวภายนอก", XE + 2 * T, "| คอนกรีต %.2f m3" % vol)
for k, val in parts.items():
    print(f"  {k}: {val:.2f}")
