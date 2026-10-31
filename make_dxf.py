#!/usr/bin/env python3
"""สร้างไฟล์ CAD (DXF, หน่วย mm) ของบ่อ 3 ช่อง ตามขนาดล่าสุด

มุมมอง: แปลน / รูปตัด A–A (ตามยาว) / รูปตัด B–B (ที่แผ่นเวียร์)
ระดับ ±0 = ผิวพื้นช่อง 2–3  |  x = 0 ที่ผิวในผนังหัวบ่อ  |  แปลน y = 0 ที่ผิวในผนังข้างช่อง 2–3
"""
import ezdxf
from ezdxf.enums import TextEntityAlignment

OUT = "cad/weir_tank.dxf"

# ---------------- ขนาด (mm) ----------------
T = 200                     # ผนัง / พื้น คสล.
B = 1500                    # กว้างภายในช่อง 2–3
W1, OFF1 = 2500, 500        # ช่อง 1 กว้าง / กว้างกว่าข้างละ
ZF1 = -1000                 # พื้นช่อง 1
L1 = 3250                   # ช่อง 1 ยาว
XB1, TB1, GAP1 = 500, 100, 300          # ผนังกั้นช่อง 1 / หนา / ช่องลอด
XDIP, DPO = 200, 168                    # ท่อจุ่ม ศก. / OD 6"
ZIN, ZDIP = 1100, -500                  # ศก.ท่อเข้า / ปลายท่อจุ่ม
XP, PW, PH = 1900, 400, 550             # ปั๊ม ศก. / ฐาน / สูง
X2 = L1 + 1000                          # ปลายพื้นยกช่อง 2 (สันปลาย)
ZR, SILL = 900, 20
XB3, TB3, ZB3 = X2 + 300, 100, 200      # ① ผนังลอดใต้ คสล.
XS3 = XB3 + TB3 + 200                   # ② สันล้น คสล. (ผิวต้นน้ำ)
ZS3 = 300
XA = XS3 + TB3                          # ต้นช่วงตรง
XW, TWW, ZWW = XA + 2100, 200, 500      # กำแพงเวียร์
XE = XW + TWW + 950                     # ผิวในผนังท้าย
ZTOP = 1200
ZV, ZN, ZPB, ZPT = 600, 900, 400, 1000  # ยอด V / ขอบบนร่อง / แผ่นล่าง / แผ่นบน
XT, ZDL = XW - 950, 1100                # Flow meter
XBOD, YBOD, ZBOD = XA + 300, 150, 300   # BOD probe
DOUT = 200
LEVELS = [(1200, "สันกำแพง"), (1100, "หน้า Flow meter / ศก.ท่อเข้า 6\""), (1000, "ขอบบนแผ่นเวียร์"),
          (970, "น้ำช่อง 1 (100 m³/h)"), (920, "สันปลายช่อง 2"), (900, "ผิวพื้นยก / ขอบบนร่อง V"),
          (810, "น้ำช่อง 3 (100 m³/h)"), (800, "ปั๊ม START"), (600, "ยอด V"), (500, "สันกำแพงเวียร์"),
          (400, "ขอบล่างแผ่นเวียร์"), (300, "สันล้น ② / ปลาย BOD"), (200, "ขอบล่างผนังลอดใต้ ①"),
          (0, "ผิวพื้นช่อง 2–3"), (-400, "ปั๊ม STOP"), (-500, "ปลายท่อจุ่ม"), (-700, "ขอบล่างผนังกั้นช่อง 1"),
          (-1000, "ผิวพื้นช่อง 1"), (-1200, "ใต้พื้นช่อง 1")]

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

# =============================== แปลน ===============================
ox, oy = 0, 0
txt("แปลน  (หน่วย mm)", -T, B + OFF1 + T + 1500, 160)
# ผนังและส่วนกั้น
box(-T, -OFF1 - T, 0, B + OFF1 + T, hatch=True)                       # ผนังหัวบ่อ
box(0, -OFF1 - T, L1 + T, -OFF1, hatch=True)                          # ผนังข้างช่อง 1
box(0, B + OFF1, L1 + T, B + OFF1 + T, hatch=True)
box(L1, -OFF1, L1 + T, 0, hatch=True)                                 # บ่าช่อง 1
box(L1, B, L1 + T, B + OFF1, hatch=True)
box(L1 + T, -T, XE + T, 0, hatch=True)                                # ผนังข้างช่อง 2–3
box(L1 + T, B, XE + T, B + T, hatch=True)
box(XE, 0, XE + T, B, hatch=True)                                     # ผนังท้าย
box(XB1, -OFF1, XB1 + TB1, B + OFF1, hatch=True)                      # ผนังกั้นช่อง 1
box(XB3, 0, XB3 + TB3, B, hatch=True)                                 # ① ผนังลอดใต้
box(XS3, 0, XS3 + TB3, B, hatch=True)                                 # ② สันล้น
box(XW, 0, XW + TWW, B, hatch=True)                                   # กำแพงเวียร์
box(L1, 0, X2, B, layer="CONCRETE")                                   # พื้นยกช่อง 2 (ขอบ)
box(X2 - 6, 0, X2, B, layer="SS")                                     # สันปลาย SS
box(XW - 6, -100, XW, B + 100, layer="SS")                            # แผ่นเวียร์ (ฝังผนัง 100)
# ท่อ / อุปกรณ์
yi = -OFF1 + 300
box(-T - 500, yi - DPO / 2, XDIP, yi + DPO / 2, layer="PIPE")
msp.add_circle((XDIP, yi), DPO / 2, dxfattribs={"layer": "PIPE"})
box(XP - PW / 2, B / 2 - PW / 2, XP + PW / 2, B / 2 + PW / 2, layer="EQUIP")
msp.add_circle((XP, B / 2), 150, dxfattribs={"layer": "EQUIP"})
box(XE, B / 2 - DOUT / 2, XE + T + 500, B / 2 + DOUT / 2, layer="PIPE")
box(XT - 50, -T, XT + 50, B + T, layer="SS")                          # คาน Flow meter
box(XT - 75, B / 2 - 75, XT + 75, B / 2 + 75, layer="EQUIP")
msp.add_circle((XBOD, YBOD), 40, dxfattribs={"layer": "EQUIP"})
line((-T - 700, B / 2), (XE + T + 700, B / 2), "CENTER")
txt("A", -T - 800, B / 2 + 60, 140); txt("A", XE + T + 750, B / 2 + 60, 140)
line((XW - 300, -OFF1 - T - 300), (XW - 300, B + OFF1 + T + 300), "CENTER")
txt("B", XW - 350, -OFF1 - T - 500, 140)
for s_, x_, y_ in [("ช่อง 1 รับน้ำ + ปั๊มจุ่ม", 1500, -OFF1 + 120), ("ช่อง 2 พื้นยก +0.900", L1 + 100, 120),
                   ("ช่อง 3 เวียร์ V-notch 90°", XA + 100, B - 200), ("ปั๊มจุ่ม", XP - 120, B / 2 + 230),
                   ("ท่อเข้า 6\"", -T - 500, yi + 140), ("ท่อออก 8\"", XE + T + 50, B / 2 + 150),
                   ("Flow meter", XT + 100, B / 2 + 100), ("BOD probe", XBOD + 70, YBOD - 30),
                   ("① ผนังลอดใต้ คสล.", XB3 - 50, B + 300), ("② สันล้น คสล.", XS3 - 50, B + 450)]:
    txt(s_, x_, y_, 60)
# มิติแปลน
yt = B + OFF1 + T
chain_h(XS, yt, yt + 300)
hdim(-T, L1 + T, yt, yt + 650); hdim(L1 + T, X2, yt, yt + 650); hdim(X2, XE + T, yt, yt + 650)
hdim(-T, XE + T, yt, yt + 1000)
yb = -OFF1 - T
hdim(0, XE, yb, yb - 300)
hdim(0, XP, yb, yb - 650); hdim(XA, XBOD, -T, yb - 650); hdim(XT, XW, -T, yb - 650)
chain_v([-T, 0, B, B + T], XE + T, XE + T + 300)
vdim(-T, B + T, XE + T, XE + T + 650)
chain_v([-OFF1 - T, -OFF1, 0, B, B + OFF1, B + OFF1 + T], -T, -T - 1000)
vdim(-OFF1 - T, B + OFF1 + T, -T, -T - 1400)
vdim(-OFF1, yi, XDIP, -T - 600)
vdim(0, YBOD, XBOD, XBOD - 250)

# =============================== รูปตัด A–A ===============================
ox, oy = 0, -6500
txt("รูปตัด A–A  (ระดับ ±0 = ผิวพื้นช่อง 2–3, หน่วย mm)", -T, ZTOP + 900, 160, oy=oy)
box(-T, ZF1 - T, L1, ZF1, hatch=True, oy=oy)                          # พื้นช่อง 1
box(-T, ZF1, 0, ZTOP, hatch=True, oy=oy)                              # ผนังหัวบ่อ
box(L1, ZF1 - T, X2, ZR, hatch=True, oy=oy)                           # ขั้น + พื้นยก
box(X2, -T, XE + T, 0, hatch=True, oy=oy)                             # พื้นช่อง 2–3
box(XE, 0, XE + T, ZTOP, hatch=True, oy=oy)                           # ผนังท้าย
box(XB1, ZF1 + GAP1, XB1 + TB1, ZTOP, hatch=True, oy=oy)              # ผนังกั้นช่อง 1
box(XB3, ZB3, XB3 + TB3, ZTOP, hatch=True, oy=oy)                     # ①
box(XS3, 0, XS3 + TB3, ZS3, hatch=True, oy=oy)                        # ②
box(XW, 0, XW + TWW, ZWW, hatch=True, oy=oy)                          # กำแพงเวียร์
box(XW - 6, ZPB, XW, ZPT, layer="SS", oy=oy)                          # แผ่นเวียร์
box(X2 - 6, ZR, X2, ZR + SILL, layer="SS", oy=oy)                     # สันปลาย SS
box(-T - 500, ZIN - DPO / 2, XDIP + DPO / 2, ZIN + DPO / 2, layer="PIPE", oy=oy)
box(XDIP - DPO / 2, ZDIP, XDIP + DPO / 2, ZIN - DPO / 2, layer="PIPE", oy=oy)
box(XP - PW / 2, ZF1, XP + PW / 2, ZF1 + PH, layer="EQUIP", oy=oy)
box(XE, 0, XE + T + 500, DOUT, layer="PIPE", oy=oy)
box(XT - 150, ZTOP, XT + 150, ZTOP + 50, layer="SS", oy=oy)
box(XT - 75, ZDL, XT + 75, ZDL + 80, layer="EQUIP", oy=oy)
line((XT, ZDL), (XT, ZV), "CENTER", oy=oy)
line((XBOD, ZTOP + 150), (XBOD, ZBOD + 300), "EQUIP", oy=oy)
box(XBOD - 30, ZBOD, XBOD + 30, ZBOD + 300, layer="EQUIP", oy=oy)
for z, x1, x2 in [(970, 0, L1), (967, L1, X2), (810, X2, XW), (210, XW + TWW, XE)]:
    line((x1, z), (x2, z), "WATER", oy=oy)
line((XA, ZV), (XW, ZV), "CENTER", oy=oy)
for z, nm in [(800, "START"), (-400, "STOP")]:
    line((XB1 + TB1, z), (L1, z), "WATER", oy=oy); txt(f"ปั๊ม {nm}", XB1 + 150, z + 30, 55, oy=oy)
for s_, x_, z_ in [("ช่อง 1", 1300, 300), ("ช่อง 2", L1 + 300, ZR + 200), ("ช่อง 3", XA + 900, 1000),
                   ("ปั๊มจุ่ม", XP - 130, ZF1 + 250), ("BOD", XBOD + 60, ZBOD + 150), ("Flow meter", XT + 100, ZDL + 20),
                   ("แผ่น V-notch SS304 6 mm", XW + 50, ZPT + 40), ("ท่อออก 8\"", XE + T + 50, DOUT + 50)]:
    txt(s_, x_, z_, 60, oy=oy)
# ระดับ
xe = XE + T + 900
zt_prev = 1e9
for z, nm in LEVELS:                                   # เลื่อนข้อความไม่ให้ทับกัน
    zt = min(z, zt_prev - 95); zt_prev = zt
    line((XE + T + 100, z), (xe - 250, z), "DIM", oy=oy)
    line((xe - 250, z), (xe - 50, zt), "DIM", oy=oy)
    txt(f"{z/1000:+.3f}  {nm}", xe, zt - 25, 55, oy=oy)
# มิติ
chain_h(XS, ZF1 - T, ZF1 - T - 400, oy=oy)
vdim(ZF1 - T, ZTOP, -T, -T - 700, oy=oy)
chain_v([ZF1 - T, ZF1, ZF1 + GAP1], -T, -T - 350, oy=oy)
vdim(ZF1, 970, XP + 600, XP + 600, oy=oy, text=f"น้ำลึก {970-ZF1}")
vdim(ZF1, ZR, L1, L1 - 250, oy=oy)
vdim(ZB3, ZTOP, XB3, XB3 - 200, oy=oy)
vdim(0, ZB3, XB3, XB3 - 200, oy=oy)
vdim(0, ZS3, XS3 + TB3, XS3 + TB3 + 200, oy=oy)
vdim(0, ZV, XW, XW - 250, oy=oy, text=f"P {ZV}")
vdim(ZPB, ZPT, XW + TWW, XW + TWW + 250, oy=oy)
vdim(0, ZWW, XW + TWW, XW + TWW + 550, oy=oy)
vdim(810, ZDL, XT, XT - 250, oy=oy)

# =============================== รูปตัด B–B ===============================
ox, oy = XE + T + 4000, -6500
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
for xb in (-500, -250, 250, 500):
    msp.add_circle((xb + ox, 450 + oy), 12, dxfattribs={"layer": "SS"})
line((-(810 - ZV), 810), ((810 - ZV), 810), "WATER", ox=ox, oy=oy)
txt("แผ่น SS304 หนา 6 mm ยึดพุก M10", -hp, ZPB - 120, 55, ox=ox, oy=oy)
hdim(-h, h, -T, -T - 600, ox=ox, oy=oy)
chain_h([-h, -B / 2, B / 2, h], -T, -T - 300, ox=ox, oy=oy)
hdim(-hp, hp, ZPT, ZPT + 500, ox=ox, oy=oy)
chain_h([-hp, -B / 2, -w, w, B / 2, hp], ZPT, ZPT + 250, ox=ox, oy=oy)
chain_v([0, ZWW, ZV, ZN, ZPT], h, h + 300, ox=ox, oy=oy)
vdim(0, ZV, h, h + 650, ox=ox, oy=oy, text=f"P {ZV}")
vdim(ZPB, ZPT, -h, -h - 300, ox=ox, oy=oy)

# ตารางสรุป
tx, ty = ox - h, oy - 1800
for i, (a, c) in enumerate([
        ("ขนาดภายนอก", f"ยาว {XE + 2*T:.0f} / กว้าง ช่อง 1 {W1 + 2*T:.0f}, ช่อง 2–3 {B + 2*T:.0f}"),
        ("ผนัง / พื้น คสล.", "200 / 200"),
        ("ช่อง 1", f"{L1} × {W1} พื้น {ZF1} (HRT 15 นาที ที่ Qavg)"),
        ("ช่อง 3: ①, ② คสล. หนา", "100 (ลอด 200 / สันล้น 300)"),
        ("แผ่นเวียร์ SS304", f"{2*hp:.0f} × {ZPT - ZPB} × 6  ร่อง V 90° ลึก {w} ปาก {2*w}"),
        ("หมายเหตุ", "ระดับ ±0 = ผิวพื้นช่อง 2–3 / โครงสร้างให้วิศวกรโยธารับรอง")]):
    txt(a, tx, ty - i * 140, 65)
    txt(c, tx + 1600, ty - i * 140, 65)

doc.saveas(OUT)
print("saved", OUT, "| ยาวภายนอก", XE + 2 * T)
